#!/usr/bin/env bash
# Find slow client-side form hooks users blame on the platform.
# Run from bench root:  bash find-form-js-hooks.sh
set -uo pipefail

# read -rp "Site name: " SITE </dev/tty

SKIP='{frappe,print_designer,india_compliance,drive,hrms,erpnext,lms,helpdesk,builder,insights,wiki,payments,node_modules,dist}'
EVENTS='setup|onload|onload_post_render|refresh|validate|before_save|after_save|before_submit|on_submit|before_cancel|after_cancel'
# Matches `refresh(frm) {`, `async refresh() {`, `refresh: function`, `"refresh": (frm) =>`, `refresh: frm =>`.
HANDLER="\b($EVENTS)[\"']?\s*(\([^)]*\)\s*\{|:\s*(async\s+)?(function|\(|\w+\s*=>))"

echo "== Form event handlers in app JS =="
eval grep -rn -A 10 --exclude-dir="$SKIP" --exclude='*.min.js' \
  -E '"$HANDLER"' ./apps --include='*.js'

echo "== doctype_js / page_js in hooks.py =="
eval grep -rn -A 10 --exclude-dir="$SKIP" \
  -E "'(doctype(_list|_tree|_calendar)?|page|webform_include)_js'" ./apps --include='hooks.py'

# echo "== Enabled Client Scripts with loops or server calls on common ERPNext doctypes =="
# # Every statement below stays on one physical line: bench console is IPython, and it
# # runs each piped line as its own cell, so multi-line calls and indented blocks break.
# bench --site "$SITE" console <<'PY'
# import re
# DOCTYPES = ["Sales Order","Item","Job Card","Sales Invoice","Purchase Order","Stock Entry","Delivery Note"]
# rows = frappe.get_all("Client Script", filters={"enabled": 1, "dt": ["in", DOCTYPES]}, fields=["name","dt","view","script"])
# print("\n".join(f"{r.name} | {r.dt} | {r.view}" for r in rows if re.search(r"\b(for|while|forEach)\b|frappe\.(call|xcall|db\.)", r.script or "")))
# PY
