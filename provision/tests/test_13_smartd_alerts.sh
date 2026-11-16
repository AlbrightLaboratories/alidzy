#!/usr/bin/env bash
# Kanboard #1873 — unit tests for the smartd alert hook (files/smartd-alert-hook.sh) and steps/13-smartd-alerts.sh.
# Contract: each smartd alert becomes ONE small key=value file in the alerts dir (the in-cluster smart-watch CronJob relays it
# to Telegram, so no bot token ever sits on this host); step 13 is idempotent, installs the hook where smartd-runner looks
# (/etc/smartmontools/run.d), makes smartd monitor with -a, and reloads smartd.
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fails=0
ok(){ printf '  PASS %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
HOOK="$R/files/smartd-alert-hook.sh"; STEP="$R/steps/13-smartd-alerts.sh"
[[ -f "$HOOK" ]] || { bad "files/smartd-alert-hook.sh missing"; }
[[ -f "$STEP" ]] || { bad "steps/13-smartd-alerts.sh missing"; }
[[ -f "$HOOK" && -f "$STEP" ]] || { echo "$fails FAILED"; exit 1; }

T="$(mktemp -d)"; A="$T/alerts"
echo "== hook: one alert -> one file"
SMART_ALERT_DIR="$A" SMARTD_DEVICE=/dev/sda SMARTD_DEVICESTRING="/dev/sda [SAT]" SMARTD_FAILTYPE=Health \
  SMARTD_MESSAGE=$'Device: /dev/sda, SMART Failure: DATA\nsecond line' sh "$HOOK" >/dev/null 2>&1
n=$(ls "$A"/*.alert 2>/dev/null | wc -l); [[ "$n" -eq 1 ]] && ok "exactly one .alert file" || bad "got $n files"
f=$(ls "$A"/*.alert 2>/dev/null | head -1)
[[ "$(basename "$f")" =~ ^[0-9]{10}-.+-_dev_sda__SAT_-Health\.alert$ ]] && ok "name is epoch-host-device-type (sanitized)" || bad "bad name: $(basename "$f")"
grep -q '^type=Health$' "$f" && ok "type=Health" || bad "type missing"
grep -q '^device=/dev/sda$' "$f" && ok "device kept" || bad "device missing"
[[ "$(grep -c '^message=' "$f")" -eq 1 && "$(wc -l < "$f")" -eq 6 ]] && ok "message is a single line (newline stripped), 6 lines total" || bad "format: $(cat "$f")"
ls "$A"/*.tmp >/dev/null 2>&1 && bad "left a .tmp file" || ok "no .tmp left behind"

echo "== hook: keeps only the newest 200"
for i in $(seq 1 205); do : > "$A/$(printf '%010d' $((1000+i)))-h-d-t.alert"; done
SMART_ALERT_DIR="$A" SMARTD_DEVICE=/dev/sda SMARTD_FAILTYPE=Health SMARTD_MESSAGE=x sh "$HOOK" >/dev/null 2>&1
[[ "$(ls "$A"/*.alert | wc -l)" -eq 200 ]] && ok "pruned to 200" || bad "count $(ls "$A"/*.alert | wc -l)"
[[ ! -f "$A/0000001001-h-d-t.alert" ]] && ok "oldest removed" || bad "oldest kept"

echo "== step 13: install, configure, reload, idempotent"
mkdir -p "$T/bin" "$T/here" "$T/run.d" "$T/etc"; cp "$R/config.env" "$T/here/config.env"; : > "$T/calls"
printf 'DEVICESCAN -d removable -n standby -m root -M exec /usr/share/smartmontools/smartd-runner\n' > "$T/etc/smartd.conf"
for c in systemctl; do printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\nexit 0\n' "$c" "$T" > "$T/bin/$c"; chmod +x "$T/bin/$c"; done
runstep(){ PATH="$T/bin:$PATH" HERE="$T/here" SMARTD_CONF="$T/etc/smartd.conf" SMARTD_RUN_DIR="$T/run.d" SMART_ALERT_DIR="$T/state/alerts" HOOK_SRC="$HOOK" bash "$STEP" >"$T/out" 2>&1; }
runstep; rc=$?; [[ $rc -eq 0 ]] && ok "step exit 0" || bad "step exit $rc: $(tail -3 "$T/out")"
[[ -x "$T/run.d/20-alert-file" ]] && ok "hook installed executable in run.d" || bad "hook not installed"
grep -qE '^DEVICESCAN .* -a( |$)' "$T/etc/smartd.conf" && ok "smartd.conf monitors with -a" || bad "conf: $(cat "$T/etc/smartd.conf")"
grep -q 'smartd-runner' "$T/etc/smartd.conf" && ok "still routes through smartd-runner" || bad "runner dropped"
[[ -d "$T/state/alerts" ]] && ok "alerts dir created" || bad "alerts dir missing"
grep -qE 'systemctl (reload|restart) smartmontools' "$T/calls" && ok "smartd reloaded" || bad "no reload: $(cat "$T/calls")"
sum1=$(cat "$T/etc/smartd.conf" "$T/run.d/20-alert-file" | cksum); runstep; sum2=$(cat "$T/etc/smartd.conf" "$T/run.d/20-alert-file" | cksum)
[[ "$sum1" == "$sum2" ]] && ok "second run changes nothing" || bad "not idempotent"
[[ "$(grep -c '^DEVICESCAN' "$T/etc/smartd.conf")" -eq 1 ]] && ok "single DEVICESCAN line" || bad "duplicated DEVICESCAN"
echo; [[ $fails -eq 0 ]] && echo "ALL PASS" || echo "$fails FAILED"; exit $((fails>0))
