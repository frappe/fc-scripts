#!/usr/bin/env bash
# Run the hook finders against the fake bench in ./apps and diff against expected/*.txt.
# Run from anywhere:  bash tests/hook-finders/run.sh
# After an intended output change, refresh the expected files:  bash tests/hook-finders/run.sh --update
set -uo pipefail

cd "$(dirname "$0")"
status=0
for script in find-doc-save-hooks find-form-js-hooks; do
  # stderr goes into the compared output: a finder's exit status is just its last grep's,
  # which is 1 whenever that section finds nothing, so errors are caught as output instead.
  if [[ ${1:-} == --update ]]; then
    bash "../../$script.sh" >"expected/$script.txt" 2>&1
  elif diff -u "expected/$script.txt" <(bash "../../$script.sh" 2>&1); then
    echo "ok   $script"
  else
    echo "FAIL $script"
    status=1
  fi
done
exit $status
