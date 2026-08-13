#!/usr/bin/env bash
# Find JS/CSS/icon bundles custom apps inject into every desk and portal page load.
# Run from bench root:  bash find-asset-include-hooks.sh
set -uo pipefail

read -rp "Site name: " SITE </dev/tty

# ponytail: asks frappe instead of grepping hooks.py -- get_hooks is the merged truth,
# and app_name= gives the per-app breakdown for free.
bench --site "$SITE" console <<'PY'
STANDARD = {"frappe", "print_designer", "india_compliance", "drive", "hrms", "erpnext",
            "lms", "helpdesk", "builder", "insights", "wiki", "payments"}
DESK = ["app_include_js", "app_include_css", "app_include_icons"]
PORTAL = ["web_include_js", "web_include_css", "web_include_icons"]
custom = [app for app in frappe.get_installed_apps() if app not in STANDARD]

for label, keys in (("desk", DESK), ("portal", PORTAL)):
    for key in keys:
        total = len(frappe.get_hooks(key) or [])
        print(f"\n== {key} ({label}) -- {total} entries incl. standard apps ==")
        for app in custom:
            for value in frappe.get_hooks(key, app_name=app) or []:
                print(f"  {app:<20} {value}")
PY
