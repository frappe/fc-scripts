#!/usr/bin/env bash
# Find the code that can serve a stale read on a site that has read_from_replica on.
# Run from bench root:  bash find-replica-reads.sh
# READ ONLY: find, grep, awk, sort. It writes no file, and it does not open the site.
set -uo pipefail

# ponytail: greps the apps instead of asking frappe, so it also runs when the
# site is down. The decorator is the whole truth here -- get_hooks cannot see it.
[ -d apps ] || { echo "run this from the bench directory" >&2; exit 1; }
STANDARD='apps/(frappe|erpnext)/'   # filtered out of the override sections

echo "== 1. reads the replica (@frappe.read_only) =="
find apps -name '*.py' -not -path '*/node_modules/*' -not -path '*/tests/*' -print0 |
xargs -0 -r awk '
  FNR==1 { pending=0; whitelisted=0 }
  /@frappe\.whitelist/ { whitelisted=1 }
  /@(frappe\.)?read_only\(\)/ { pending=1 }
  /^[[:space:]]*def[[:space:]]/ {
    if (pending) {
      name=$0; sub(/^[[:space:]]*def[[:space:]]+/, "", name); sub(/\(.*/, "", name)
      module=FILENAME; sub(/^apps\/[^\/]+\//, "", module); sub(/\.py$/, "", module); gsub(/\//, ".", module)
      printf "%s\t%s.%s\t%s:%d\n", (whitelisted ? "api     " : "internal"), module, name, FILENAME, FNR
    }
    pending=0; whitelisted=0
  }' | sort -t"$(printf '\t')" -k2

echo
echo "== 2. app overrides of the read path (hooks.py) =="
grep -rHn -A20 "^override_whitelisted_methods\|^override_doctype_class\|^permission_query_conditions\|^has_permission" apps/*/*/hooks.py |
  grep '":' | grep -Ev "$STANDARD" | grep -v '#' | sort -u

echo
echo "== 3. controller get_list / get_count (virtual doctypes) =="
grep -rHn --include='*.py' "def get_list(\|def get_count(" apps/ | grep -Ev "$STANDARD"

echo
echo "== 4. whitelisted methods named like the standard read API =="
grep -rHn --include='*.py' "^def \(get\|get_list\|get_count\|get_detail\|get_doc\)(" apps/ | grep -Ev "$STANDARD"

echo
echo "== 5. redis doc cache use (a replica read poisons it) =="
grep -rHn --include='*.py' "get_cached_doc\|get_cached_value" apps/ | grep -Ev "$STANDARD"
