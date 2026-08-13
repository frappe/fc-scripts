#!/usr/bin/env python3
"""Build a backup log CSV from the agent jobs sqlite database.

Usage: python3 backup_log.py [jobs.sqlite3] [backup_log.csv]
"""

import csv
import json
import re
import sqlite3
import sys

DB = sys.argv[1] if len(sys.argv) > 1 else "jobs.sqlite3"
OUT = sys.argv[2] if len(sys.argv) > 2 else "backup_log.csv"

# "FileNotFoundError: [Errno 2] ...", "subprocess.CalledProcessError: ...", "MySQLdb.OperationalError: ..."
EXC_LINE = re.compile(r"^(?:[A-Za-z_][\w.]*\.)?[A-Z]\w*(?:Error|Exception|Exit|Interrupt|Warning)\b.*")


def exception_line(text):
	"""Last exception line in a python traceback blob, ignoring frame lines."""
	if not text:
		return None
	for line in reversed(text.splitlines()):
		line = line.strip()
		if not line or line.startswith(("File \"", "Traceback", "^", "~", "During handling", "The above exception")):
			continue
		if EXC_LINE.match(line):
			return line
	return None


def last_meaningful_line(text):
	if not text:
		return None
	for line in reversed(text.splitlines()):
		line = line.strip()
		if line and not line.startswith(("File \"", "^", "~")):
			return line
	return None


def failure_reason(job_data, steps):
	"""Interpret why a backup failed, preferring the innermost python exception.

	The step traceback is usually the agent-side CalledProcessError wrapper, while
	the real cause is the last exception in the command output.
	"""
	sources = []
	for _, step_status, step_data in steps:
		if step_status == "Success":
			continue
		if isinstance(step_data, dict):
			sources.append((step_data.get("output"), step_data.get("traceback")))
	# failed jobs sometimes carry the step payload on the job itself
	if isinstance(job_data, dict) and "output" in job_data:
		sources.append((job_data.get("output"), job_data.get("traceback")))

	for output, traceback in sources:
		reason = exception_line(output) or exception_line(traceback)
		if reason:
			return reason
	for output, traceback in sources:
		reason = last_meaningful_line(output) or last_meaningful_line(traceback)
		if reason:
			return reason
	return ""


SITE_FROM_PATH = re.compile(r"(?:/sites/|^\./)([^/]+)/private/backups/")
SITE_FROM_URL = re.compile(r"^https?://([^/]+)/")
SITE_FROM_CMD = re.compile(r"--site\s+(\S+)")


def site_name(job_data, steps):
	"""Site the backup ran for, taken from the backup paths or the bench command."""
	backups = job_data.get("backups") if isinstance(job_data, dict) else None
	if isinstance(backups, dict):
		for entry in backups.values():
			if not isinstance(entry, dict):
				continue
			match = SITE_FROM_PATH.search(entry.get("path") or "")
			if match:
				return match.group(1)
			match = SITE_FROM_URL.match(entry.get("url") or "")
			if match:
				return match.group(1)

	commands = [step_data.get("command") for _, _, step_data in steps if isinstance(step_data, dict)]
	if isinstance(job_data, dict):
		commands.append(job_data.get("command"))
	for command in commands:
		if not command:
			continue
		match = SITE_FROM_CMD.search(command)
		if match:
			return match.group(1)
		match = SITE_FROM_PATH.search(command)
		if match:
			return match.group(1)
	return ""


UPLOAD_STEP = "Upload Site Backup to S3"


def backup_type(job_status, job_data, steps):
	if job_status != "Success":
		return ""
	if isinstance(job_data, dict) and job_data.get("offsite"):
		return "offsite"
	for step_name, step_status, _ in steps:
		if step_name == UPLOAD_STEP and step_status == "Success":
			return "offsite"
	return "onsite"


def size_of(backups, key):
	entry = (backups or {}).get(key)
	if isinstance(entry, dict) and isinstance(entry.get("size"), int):
		return entry["size"]
	return ""


def load_json(raw):
	if not raw:
		return None
	try:
		return json.loads(raw)
	except (ValueError, TypeError):
		return None


con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)

jobs = con.execute(
	"""
	SELECT id, agent_job_id, status, data, start, end, duration
	FROM jobmodel
	WHERE name = 'Backup Site'
	ORDER BY id
	"""
).fetchall()

steps_by_job = {}
for job_id, step_name, status, data in con.execute(
	"""
	SELECT s.job_id, s.name, s.status, s.data
	FROM stepmodel s
	JOIN jobmodel j ON j.id = s.job_id
	WHERE j.name = 'Backup Site'
	ORDER BY s.id
	"""
):
	steps_by_job.setdefault(job_id, []).append((step_name, status, load_json(data)))

with open(OUT, "w", newline="") as f:
	writer = csv.writer(f)
	writer.writerow(
		[
			"job_id",
			"agent_job_id",
			"site_name",
			"status",
			"type",
			"private_file_size_bytes",
			"public_file_size_bytes",
			"db_file_size_bytes",
			"site_config_size_bytes",
			"started_on",
			"ended_on",
			"duration",
			"failure_reason",
		]
	)

	for job_id, agent_job_id, status, data, start, end, duration in jobs:
		job_data = load_json(data)
		backups = job_data.get("backups") if isinstance(job_data, dict) else None
		steps = steps_by_job.get(job_id, [])
		reason = failure_reason(job_data, steps) if status != "Success" else ""

		writer.writerow(
			[
				job_id,
				agent_job_id or "",
				site_name(job_data, steps),
				status,
				backup_type(status, job_data, steps),
				size_of(backups, "private"),
				size_of(backups, "public"),
				size_of(backups, "database"),
				size_of(backups, "site_config"),
				start or "",
				end or "",
				duration or "",
				reason,
			]
		)

print("Wrote backup log CSV to", OUT)
