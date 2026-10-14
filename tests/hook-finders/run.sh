#!/usr/bin/env bash
# Run the hook finders against the fake bench in ./apps and diff against expected/*.txt.
# Run from anywhere:  bash tests/hook-finders/run.sh
# After an intended output change, refresh the expected files:  bash tests/hook-finders/run.sh --update
set -uo pipefail

cd "$(dirname "$0")"
status=0
for script in find-doc-save-hooks find-form-js-hooks; do
  if [[ ${1:-} == --update ]]; then
    bash "../../$script.sh" >"expected/$script.txt"
  elif diff -u "expected/$script.txt" <(bash "../../$script.sh"); then
    echo "ok   $script"
  else
    echo "FAIL $script"
    status=1
  fi
done
exit $status
