#!/bin/bash
# usage: annotated.sh NAME command... - run a command; on failure echo the error lines of its output as an
# ::error:: annotation (readable via the public API without a token), then fail.
log="${RUNNER_TEMP:-/tmp}/ann-$1.log"; shift
"$@" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
if [ "$rc" -ne 0 ]; then
  echo "::error::FAILED rc=$rc :: $( (grep -aE 'error:|Error|FAILED|Fatal|trap' "$log" | head -6; tail -n 6 "$log") | cut -c1-300 | head -c 3000 | sed ':a;N;$!ba;s/\n/%0A/g')"
fi
exit "$rc"
