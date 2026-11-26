#!/usr/bin/env bash
# Summarise a `swift test` log: the slowest tests, and any test that started
# but never finished.
#
#   swift test --no-parallel 2>&1 | tee test.log
#   Tools/test-timings.sh test.log [count]
#
# CI runs this after the suite, pass or fail. The `test` job has a 15-minute
# cap, and a run that hits it is cancelled mid-test; the second list is how
# you find which test was hanging instead of rerunning blind.
#
# Reads swift-testing's console lines:
#   ◇ Test name() started.
#   ✔ Test name() passed after 1.234 seconds.
#   ✘ Test name() failed after 1.234 seconds with 1 issue.
#   ✔ Test name(a:) with 9 test cases passed after 1.234 seconds.
# Anything before the glyph (a CI timestamp, say) is ignored. Per-argument
# "Test case passing ..." lines and the "Test run with ..." total are left out.
set -euo pipefail
export LC_ALL=C   # awk and printf must read "1.234" as a number in any locale

log=${1:?usage: Tools/test-timings.sh <swift-test-log> [count]}
count=${2:-15}

if [[ ! -s $log ]]; then
    echo "No test log at $log: the suite never started."
    exit 0
fi

# One "seconds name" line per finished test, parameterised suffix stripped.
finished() {
    sed -nE 's/.*[✔✘] Test (.*) (passed|failed) after ([0-9.]+) seconds.*/\3 \1/p' "$log" \
        | grep -vE '^[0-9.]+ (case passing |run with )' \
        | sed -E 's/ with [0-9]+ test cases?$//' || true
}

total=$(sed -nE 's/.*[✔✘] (Test run with .*)/\1/p' "$log" | tail -n 1)
echo "${total:-The run did not reach its summary line: it was cut off or crashed.}"
echo
echo "Slowest $count tests:"
# awk, not head: head closing the pipe early is a SIGPIPE, fatal under pipefail.
finished | sort -rn | awk -v n="$count" 'NR <= n { t = $1; $1 = ""; printf "  %8.2fs %s\n", t, substr($0, 2) }'

# Names are not unique across suites, so match by count rather than by name:
# a name that started more often than it finished is still running somewhere.
unfinished=$(
    {
        sed -nE 's/.*◇ Test (.*) started\..*/S \1/p' "$log" | grep -vE '^S (case passing |run$)' || true
        finished | sed -E 's/^[0-9.]+ /F /'
    } | awk '
        { kind = $1; $1 = ""; name = substr($0, 2) }
        kind == "S" { open[name]++ }
        kind == "F" { open[name]-- }
        END { for (name in open) if (open[name] > 0) print "  " name }
    ' | sort
)

echo
if [[ -n $unfinished ]]; then
    echo "Started but never finished (a hang, or the run was cut off):"
    echo "$unfinished"
else
    echo "Every test that started also finished."
fi
