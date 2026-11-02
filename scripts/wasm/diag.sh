#!/bin/bash
# TEMPORARY diagnosis driver (W02).
R="$RUNNER_TEMP/res.txt"; : > "$R"
note() { echo "$*" | tee -a "$R"; }
apt-get update -qq && apt-get install -y -qq xz-utils curl ca-certificates >/dev/null 2>&1
V=6.2.4
URL="https://download.swift.org/swift-$V-release/wasm-sdk/swift-$V-RELEASE/swift-$V-RELEASE_wasm.artifactbundle.tar.gz"
swift sdk install "$URL" --checksum 32fdb8772d73bb174f77b5c59bc88a0d55003d75712832129394d3465158fb43 >"$RUNNER_TEMP/sdk.log" 2>&1 || note "SDK FAIL $(tail -3 $RUNNER_TEMP/sdk.log)"
SDK=$(swift sdk list | grep -i wasm | grep -iv embedded | head -1 | tr -d ' ')
curl -fsSL -o "$RUNNER_TEMP/wt.tar.xz" https://github.com/bytecodealliance/wasmtime/releases/download/v50.0.1/wasmtime-v50.0.1-x86_64-linux.tar.xz
mkdir -p "$RUNNER_TEMP/wt" && tar -xJf "$RUNNER_TEMP/wt.tar.xz" -C "$RUNNER_TEMP/wt" --strip-components=1
export PATH="$RUNNER_TEMP/wt:$PATH"
note "sdk=$SDK $(wasmtime --version)"
cd core
export WASMTIME_BACKTRACE_DETAILS=1

TESTS="OnboardingFlowTests/addedMemberBlocksPlanning OnboardingFlowTests/endToEnd PlanServiceTests/editApprovedCreatesRevision SafetyRecheckTests/ruleAddedAfterApproval DataServiceTests/deleteAllLeavesNothing"

run_cfg() { # name config-dir build-args...
  local name="$1" cfg="$2"; shift 2
  swift build --swift-sdk "$SDK" --build-tests "$@" >"$RUNNER_TEMP/b-$name.log" 2>&1
  note "BUILD $name rc=$?"; grep -a "error:" "$RUNNER_TEMP/b-$name.log" | head -5 | cut -c1-300 | tee -a "$R"
  local BD="$PWD/.build/wasm32-unknown-wasip1/$cfg"
  local X="$BD/CorePackageTests.xctest"
  wasmtime compile "$X" -o "$RUNNER_TEMP/$name.cwasm" 2>"$RUNNER_TEMP/cc.log"; note "COMPILE $name rc=$?"
  for stk in default big; do
    local opt=""; [ $stk = big ] && opt="-W max-wasm-stack=33554432"
    for t in $TESTS; do
      wasmtime run $opt --allow-precompiled --dir=. --dir "$BD" "$RUNNER_TEMP/$name.cwasm" --testing-library swift-testing --filter "$t" >"$RUNNER_TEMP/o.txt" 2>&1
      rc=$?
      note "== $name/$stk $t rc=$rc :: $(grep -aE 'Test run with' $RUNNER_TEMP/o.txt | head -1 | cut -c1-90)"
      grep -aE "Fatal error|wasm trap|demangle|unreachable|out of bounds|exhausted|recorded an issue|error:|Error" "$RUNNER_TEMP/o.txt" | grep -av "^ *[0-9]*:" | head -4 | cut -c1-330 | tee -a "$R"
      if [ $rc -ne 0 ]; then
        grep -aE "^ +[0-9]+: " "$RUNNER_TEMP/o.txt" | head -16 | sed -E 's/^ +[0-9]+: +(0x[0-9a-f]+ - )?//' | swift demangle --simplified 2>/dev/null | cut -c1-200 | sed 's/^/   bt: /' | tee -a "$R"
        tail -n 5 "$RUNNER_TEMP/o.txt" | cut -c1-250 | sed 's/^/   tail: /' | tee -a "$R"
      fi
    done
  done
}
run_cfg dbg debug
run_cfg rel release -c release -Xswiftc -enable-testing

cut -c1-400 "$R" | head -c 110000 | split -C 3800 -d - "$RUNNER_TEMP/chunk."
