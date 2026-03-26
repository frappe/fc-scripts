import argparse
import json
import os
import subprocess
import sys
import time

MAPPING_FILE = "recovery_mapping.json"
SOCKET = "/tmp/recovery_mysql.sock"


def load_mapping():
    if os.path.exists(MAPPING_FILE):
        try:
            with open(MAPPING_FILE) as f:
                return json.load(f)
        except json.JSONDecodeError:
            pass
    return {}


def save_mapping(mapping):
    with open(MAPPING_FILE, "w") as f:
        json.dump(mapping, f, indent=2)


def run(cmd):
    print(f"+ {cmd}")
    return subprocess.run(cmd, shell=True).returncode == 0


def start_mariadb(datadir):
    proc = subprocess.Popen(
        ["mysqld", f"--datadir={datadir}", "--skip-networking",
         f"--socket={SOCKET}", "--user=root"],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    attempts = 0
    while True:
        if os.path.exists(SOCKET):
            if subprocess.run(["mysqladmin", f"--socket={SOCKET}", "ping"], capture_output=True).returncode == 0:
                return proc
        time.sleep(1)
        attempts += 1
        
        if attempts >= 60:
            user_input = input("\nMariaDB has not started after 60 seconds. Retry for another 60? (y/n): ")
            if user_input.lower() != 'y':
                print("MariaDB failed to start. Exiting.")
                proc.terminate()
                sys.exit(1)
            attempts = 0


def stop_mariadb(proc, db_pass):
    subprocess.run(["mysqladmin", f"--socket={SOCKET}", "-u", "root", f"-p{db_pass}", "shutdown"], capture_output=True)
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def recover_db(datadir, db_pass, bucket, prefix):
    mapping = load_mapping()
    proc = start_mariadb(datadir)

    try:
        result = subprocess.run(
            ["mysql", f"--socket={SOCKET}", "-u", "root", f"-p{db_pass}", "-N", "-e", "SHOW DATABASES"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"Failed to list databases: {result.stderr}")
            sys.exit(1)

        skip = {"mysql", "information_schema", "performance_schema", "sys"}
        databases = [db.strip() for db in result.stdout.strip().split("\n") if db.strip() and db not in skip]

        if not databases:
            print("No user databases found.")
            return

        failed = []
        for db in databases:
            if db in mapping:
                print(f"Skipping {db} (already at {mapping[db]})")
                continue

            s3_dest = f"s3://{bucket}/{prefix}/{db}.sql.gz"
            cmd = f"mysqldump --socket={SOCKET} -u root -p{db_pass} --single-transaction --quick {db} | gzip -c | aws s3 cp - {s3_dest}"

            if run(cmd):
                mapping[db] = s3_dest
                save_mapping(mapping)
            else:
                failed.append(db)

        if failed:
            print(f"Failed: {', '.join(failed)}")
            sys.exit(1)
    finally:
        stop_mariadb(proc, db_pass)


def recover_app(benches_dir, bucket, prefix):
    if not os.path.isdir(benches_dir):
        print(f"Directory not found: {benches_dir}")
        sys.exit(1)

    mapping = load_mapping()
    failed = []

    for bench in sorted(os.listdir(benches_dir)):
        sites_dir = os.path.join(benches_dir, bench, "sites")
        if not os.path.isdir(sites_dir):
            continue

        for site in sorted(os.listdir(sites_dir)):
            site_path = os.path.join(sites_dir, site)
            if not os.path.isdir(site_path):
                continue

            print(f"\n{site}")

            uploads = {
                f"{site}_public_files":  (os.path.join(site_path, "public", "files"),  f"{site}_public_files.tar",  "dir"),
                f"{site}_private_files": (os.path.join(site_path, "private", "files"), f"{site}_private_files.tar", "dir"),
                f"{site}_site_config":   (os.path.join(site_path, "site_config.json"), f"{site}_site_config.json",  "file"),
            }

            for key, (path, filename, kind) in uploads.items():
                if key in mapping:
                    print(f"  skip {filename}")
                    continue

                exists = os.path.isdir(path) if kind == "dir" else os.path.isfile(path)
                if not exists:
                    continue

                s3_dest = f"s3://{bucket}/{prefix}/{filename}"
                if kind == "dir":
                    rel = os.path.relpath(path, sites_dir)
                    cmd = f"tar -cf - -C {sites_dir} {rel} | aws s3 cp - {s3_dest}"
                else:
                    cmd = f"aws s3 cp {path} {s3_dest}"

                if run(cmd):
                    mapping[key] = s3_dest
                    save_mapping(mapping)
                else:
                    failed.append(key)

    if failed:
        print(f"\nFailed: {', '.join(failed)}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", required=True, choices=["db", "app"])
    parser.add_argument("--data", required=True)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--db-pass")
    args = parser.parse_args()

    missing = [v for v in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_DEFAULT_REGION") if not os.environ.get(v)]
    if missing:
        parser.error(f"Missing env vars: {', '.join(missing)}")

    if args.mode == "db":
        if not args.db_pass:
            parser.error("--db-pass is required for db mode.")
        recover_db(args.data, args.db_pass, args.bucket, args.prefix)
    else:
        recover_app(args.data, args.bucket, args.prefix)


if __name__ == "__main__":
    main()