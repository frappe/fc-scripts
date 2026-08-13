#!/usr/bin/env bash
# Find JS/CSS/icon bundles custom apps inject into every desk and portal page load.
# Run from bench root:  bash find-asset-include-hooks.sh
set -uo pipefail

read -rp "Site name: " SITE </dev/tty

# ponytail: asks frappe instead of grepping hooks.py -- get_hooks is the merged truth,
# and app_name= gives the per-app breakdown for free.
# Every statement stays on one physical line: bench console is IPython, and it runs
# each piped line as its own cell, so multi-line literals and indented blocks break.
bench --site "$SITE" console <<'PY'
STANDARD = {"frappe", "print_designer", "india_compliance", "drive", "hrms", "erpnext", "lms", "helpdesk", "builder", "insights", "wiki", "payments"}
KEYS = ["app_include_js", "app_include_css", "app_include_icons", "web_include_js", "web_include_css", "web_include_icons"]
custom = [app for app in frappe.get_installed_apps() if app not in STANDARD]
print("\n".join(f"{key:<20} {app:<20} {value}" for key in KEYS for app in custom for value in (frappe.get_hooks(key, app_name=app) or [])) or "No asset includes from custom apps")
print("\n-- totals incl. standard apps --")
print("\n".join(f"{key:<20} {len(frappe.get_hooks(key) or [])}" for key in KEYS))
PY
