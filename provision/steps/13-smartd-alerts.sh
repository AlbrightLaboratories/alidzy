#!/usr/bin/env bash
# smartd alert hook (Kanboard #1873): every smartd alert becomes a file under /var/lib/smartmontools/alerts that the
# in-cluster smart-watch CronJob relays to Telegram (token stays in the cluster). Idempotent; safe to re-run.
# Uses Ubuntu's documented hook point (/etc/smartmontools/run.d, run by smartd-runner) and only edits the DEVICESCAN line.
set -euo pipefail
source "$HERE/config.env"
SMARTD_CONF="${SMARTD_CONF:-/etc/smartd.conf}"
SMARTD_RUN_DIR="${SMARTD_RUN_DIR:-/etc/smartmontools/run.d}"
SMART_ALERT_DIR="${SMART_ALERT_DIR:-/var/lib/smartmontools/alerts}"
HOOK_SRC="${HOOK_SRC:-$HERE/files/smartd-alert-hook.sh}"

mkdir -p "$SMARTD_RUN_DIR" "$SMART_ALERT_DIR"; chmod 0755 "$SMART_ALERT_DIR"
install -m 0755 "$HOOK_SRC" "$SMARTD_RUN_DIR/20-alert-file"

# Monitor with -a (health, error log, self-test log, pending/uncorrectable sectors) and keep the stock runner.
WANT='DEVICESCAN -d removable -a -n standby -m root -M exec /usr/share/smartmontools/smartd-runner'
if ! grep -qxF "$WANT" "$SMARTD_CONF" 2>/dev/null; then
  [[ -f "$SMARTD_CONF" && ! -f "$SMARTD_CONF.bak-1873" ]] && cp -a "$SMARTD_CONF" "$SMARTD_CONF.bak-1873"
  { grep -vE '^\s*DEVICESCAN' "$SMARTD_CONF" 2>/dev/null || true; echo "$WANT"; } > "$SMARTD_CONF.new"
  mv "$SMARTD_CONF.new" "$SMARTD_CONF"
  echo "smartd.conf: DEVICESCAN now monitors with -a (backup $SMARTD_CONF.bak-1873)"
fi
systemctl reload smartmontools 2>/dev/null || systemctl restart smartmontools
echo "smartd alert hook installed: $SMARTD_RUN_DIR/20-alert-file -> $SMART_ALERT_DIR"
