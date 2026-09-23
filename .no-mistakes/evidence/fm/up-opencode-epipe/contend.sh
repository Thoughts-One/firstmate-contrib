#!/usr/bin/env bash
# usage: contend.sh <runtime> <variant> ; 60 concurrent plugin processes, 20 idle events each
rt=$1 v=$2; out=/tmp/fm-epipe-lab/runs-$rt-$v; rm -rf $out; mkdir -p $out
for i in $(seq 1 60); do ( $rt /tmp/fm-epipe-lab/driver.mjs $v guard-early-close 20 >$out/$i.log 2>&1; echo $? > $out/$i.rc ) & done; wait
crash=0; for i in $(seq 1 60); do [ "$(cat $out/$i.rc)" = 0 ] || crash=$((crash+1)); done
epipe=$(grep -l EPIPE $out/*.log 2>/dev/null | wc -l)
echo "$rt $v: $crash/60 processes exited non-zero; $epipe/60 logs mention EPIPE"
