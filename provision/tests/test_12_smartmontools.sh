#!/usr/bin/env bash
# Kanboard #1873 — unit test for steps/12-smartmontools.sh (all external commands stubbed).
# Contract: install ONLY smartmontools, without recommends, never run an upgrade (10-base.sh does `apt-get upgrade -y`,
# which would pull kernel updates under the operator-built NVIDIA driver), enable smartd, and be safe to re-run.
set -uo pipefail
HERE_REAL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
ok(){ printf '  PASS %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
STEP="$HERE_REAL/steps/12-smartmontools.sh"
[[ -f "$STEP" ]] || { bad "steps/12-smartmontools.sh missing"; echo "1 FAILED"; exit 1; }

T="$(mktemp -d)"; mkdir -p "$T/bin" "$T/here"; cp "$HERE_REAL/config.env" "$T/here/config.env"; : > "$T/calls"
for c in apt-get systemctl; do printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\nexit 0\n' "$c" "$T" > "$T/bin/$c"; chmod +x "$T/bin/$c"; done
printf '#!/bin/sh\nexit 1\n' > "$T/bin/smartctl"; chmod +x "$T/bin/smartctl"      # smartctl absent -> must install
PATH="$T/bin:$PATH" HERE="$T/here" bash "$STEP" >"$T/out" 2>&1; rc=$?
[[ $rc -eq 0 ]] && ok "exit 0" || bad "exit $rc"
grep -q 'apt-get install.*--no-install-recommends.*smartmontools' "$T/calls" && ok "installs smartmontools with --no-install-recommends" || bad "install line wrong: $(cat "$T/calls")"
grep -qE 'apt-get (upgrade|dist-upgrade|full-upgrade)' "$T/calls" && bad "ran an apt upgrade" || ok "no apt upgrade"
[[ "$(grep -c 'apt-get install' "$T/calls")" -eq 1 ]] && ok "exactly one install call" || bad "more than one install call"
grep -q 'systemctl.*enable.*smartmontools\|systemctl.*enable.*smartd' "$T/calls" && ok "smartd enabled" || bad "smartd not enabled"
echo; [[ $fails -eq 0 ]] && echo "ALL PASS" || echo "$fails FAILED"; exit $((fails>0))
