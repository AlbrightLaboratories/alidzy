#!/usr/bin/env bash
# Kanboard #1873 — live-node check: SMART readable on every drive and smartd running. Run: sudo bash node-smart.sh
set -uo pipefail
fails=0; ok(){ printf '  PASS %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
command -v smartctl >/dev/null && ok "smartctl installed ($(smartctl -V | head -1))" || { bad "smartctl not installed"; echo "$fails FAILED"; exit 1; }
for d in $(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}'); do
  out="$(smartctl -H "$d" 2>&1)"
  if grep -q "PASSED" <<<"$out"; then ok "$d SMART health PASSED ($(lsblk -dno MODEL "$d" | xargs))"; else bad "$d SMART not readable/passed: $(grep -iE 'result|unsupported|failed' <<<"$out" | head -1)"; fi
done
systemctl is-active --quiet smartmontools 2>/dev/null || systemctl is-active --quiet smartd 2>/dev/null && ok "smartd active" || bad "smartd not active"
# --- alert hook (steps/13-smartd-alerts.sh, #1873)
[[ -x /etc/smartmontools/run.d/20-alert-file ]] && ok "alert hook installed in smartd run.d" || bad "alert hook missing"
grep -qE '^DEVICESCAN .* -a( |$)' /etc/smartd.conf && ok "smartd.conf monitors with -a" || bad "smartd.conf lacks -a"
[[ -d /var/lib/smartmontools/alerts ]] && ok "alerts dir exists" || bad "alerts dir missing"
echo; [[ $fails -eq 0 ]] && echo "ALL PASS" || echo "$fails FAILED"; exit $((fails>0))
