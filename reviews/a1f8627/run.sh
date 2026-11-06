#!/bin/bash
# usage: run.sh <name> <literal-file> [timeout s]; one process, ulimit -v 6000000; summarises stderr
P=/home/agent/.claude/jobs/d2d299f1/tmp/review-psc1d/probes
T=${3:-120}
log=$(mktemp)
start=$(date +%s%N)
( ulimit -v 6000000; timeout $T julia --project=$P/../repo/test $P/one.jl "@$2" > $log 2>&1 )
code=$?
end=$(date +%s%N)
so=$(grep -ci "stack overflow" $log); soe=$(grep -c StackOverflowError $log)
echo "$1: exit=$code wall=$(( (end - start) / 1000000 ))ms overflow-warnings=$so StackOverflowError=$soe | $(grep -- ' -> ' $log | sed 's/.* -> //' | tr -s ' ' | head -1)"
rm -f $log
