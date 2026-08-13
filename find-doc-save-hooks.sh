#!/usr/bin/env bash
# Find slow document save hooks users blame on the platform.
# Run from bench root:  bash find-doc-save-hooks.sh
set -uo pipefail

read -rp "Site name: " SITE </dev/tty

SKIP='{frappe,print_designer,india_compliance,drive,hrms,erpnext,lms,helpdesk,builder,insights,wiki,payments}'

echo "== Controller lifecycle methods =="
eval grep -rn -A 10 --exclude-dir="$SKIP" \
  -E "'def (validate|before_save|after_save|before_insert|after_insert|on_update|on_change|on_submit|before_submit|on_trash|before_validate)\('" \
  ./apps --include='*.py'

echo "== doc_events in hooks.py =="
eval grep -rn -A 10 --exclude-dir="$SKIP" 'doc_events' ./apps --include='hooks.py'

echo "== Request/job hooks in hooks.py =="
eval grep -rn -A 10 --exclude-dir="$SKIP" \
  -E "'(before|after)_(request|job)'" ./apps --include='hooks.py'

echo "== Enabled Server Scripts with loops on common ERPNext doctypes =="
# ponytail: SQL, not bench console -- Server Scripts live in the database, and the
# mariadb client reads piped stdin properly where IPython chops it into per-line cells.
bench --site "$SITE" mariadb <<'SQL'
SELECT name, reference_doctype, doctype_event FROM `tabServer Script`
WHERE disabled = 0
  AND reference_doctype IN ('Sales Order','Item','Job Card','Sales Invoice','Purchase Order','Stock Entry','Delivery Note')
  AND script RLIKE '\\b(for|while)\\b';
SQL
