#!/bin/bash
# usage: run.sh <literal-or-@file> [timeout s]; runs one.jl under ulimit -v 6000000 and timeout, prints exit code
P=/home/agent/.claude/jobs/d2d299f1/tmp/review-psc1b/probes
T=${2:-120}
start=$(date +%s%N)
( set -o pipefail; ulimit -v 6000000; timeout $T julia --project=$P/../repo/test $P/one.jl "$1" 2>&1 | tail -n 12 )
code=$?
end=$(date +%s%N)
echo "   [exit $code, wall $(( (end - start) / 1000000 )) ms] ${1:0:80}"
