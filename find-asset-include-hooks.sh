#!/usr/bin/env bash
# Find JS/CSS/icon bundles custom apps inject into every desk and portal page load.
# Run from bench root:  bash find-asset-include-hooks.sh
set -uo pipefail

SKIP='{frappe,print_designer,india_compliance,drive,hrms,erpnext,lms,helpdesk,builder,insights,wiki,payments}'

echo "== Desk includes (loaded on every desk page) =="
eval grep -rn -A 10 --exclude-dir="$SKIP" \
  -E "'^[^#]*app_include_(js|css|icons)'" ./apps --include='hooks.py'

echo "== Portal includes (loaded on every portal page) =="
eval grep -rn -A 10 --exclude-dir="$SKIP" \
  -E "'^[^#]*web_include_(js|css|icons)'" ./apps --include='hooks.py'
