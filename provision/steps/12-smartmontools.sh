#!/usr/bin/env bash
# SMART disk-health tools: smartctl + the smartd monitor (Kanboard #1873).
# Install-only on purpose: 10-base.sh runs `apt-get upgrade -y`, and a re-run of it would pull kernel updates under the
# operator-built NVIDIA driver (see #1868/#1872). This step installs ONLY smartmontools, without recommends, and is safe to re-run.
set -euo pipefail
source "$HERE/config.env"
export DEBIAN_FRONTEND=noninteractive

if smartctl -V >/dev/null 2>&1; then
  echo "smartmontools already installed: $(smartctl -V | head -1)"
else
  apt-get update -y
  apt-get install -y --no-install-recommends smartmontools
fi

# smartd polls every drive (default every 30 min), logs to the journal. Alert routing is a separate task.
systemctl enable --now smartmontools 2>/dev/null || systemctl enable --now smartd
echo "smartd enabled. Drives:"; lsblk -dno NAME,SIZE,MODEL,TRAN | grep -v '^loop' || true
