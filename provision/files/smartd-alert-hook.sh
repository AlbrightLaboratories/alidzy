#!/bin/sh
# smartd-runner drop-in (installed as /etc/smartmontools/run.d/20-alert-file by steps/13-smartd-alerts.sh). Kanboard #1873.
# smartd runs every executable in run.d on a SMART alert and exports SMARTD_* variables. This writes the alert as ONE small
# key=value file; the in-cluster smart-watch CronJob (cluster-health repo) reads that directory read-only and relays new
# files to Telegram, so the bot token never has to exist on this host. Never fails smartd (exit 0 always).
D="${SMART_ALERT_DIR:-/var/lib/smartmontools/alerts}"
mkdir -p "$D" || exit 0
epoch=$(date +%s); host=$(hostname -s 2>/dev/null || echo host)
dev=$(printf '%s' "${SMARTD_DEVICESTRING:-${SMARTD_DEVICE:-unknown}}" | tr -c 'A-Za-z0-9._-' '_')
typ=$(printf '%s' "${SMARTD_FAILTYPE:-unknown}" | tr -c 'A-Za-z0-9._-' '_')
f="$D/$(printf '%010d' "$epoch")-$host-$dev-$typ.alert"
msg=$(printf '%s' "${SMARTD_MESSAGE:-}" | tr '\n\r' '  ' | cut -c1-400)
{
  echo "time=$(date -Is)"; echo "epoch=$epoch"; echo "host=$host"
  echo "device=${SMARTD_DEVICE:-unknown}"; echo "type=${SMARTD_FAILTYPE:-unknown}"; echo "message=$msg"
} > "$f.tmp" && mv "$f.tmp" "$f"
chmod 0644 "$f" 2>/dev/null
# bound the directory: keep the newest 200 alerts
n=$(ls -1 "$D"/*.alert 2>/dev/null | wc -l)
if [ "$n" -gt 200 ]; then
  ls -1 "$D"/*.alert | sort | head -n $((n - 200)) | while read -r old; do rm -f "$old"; done
fi
exit 0
