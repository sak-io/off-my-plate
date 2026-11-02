#!/bin/bash
# usage: emit.sh FROM TO - echo chunks FROM..TO of the diagnostics as ::error:: annotations
ls "${RUNNER_TEMP}"/chunk.* 2>/dev/null | sed -n "$1,$2p" | while read -r f; do
  echo "::error::$(sed ':a;N;$!ba;s/\n/%0A/g' "$f")"
done
exit 0
