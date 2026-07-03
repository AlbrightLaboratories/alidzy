#!/usr/bin/env bash
# SSH banner for Alidzy — pre-auth banner (/etc/issue.net) + post-login MOTD.
set -uo pipefail
source "$HERE/config.env"

# --- pre-auth banner (shown at the ssh password prompt) ---
cat > /etc/issue.net <<'EOF'

    _    _     ___ ____  ________   __
   / \  | |   |_ _|  _ \|__  /\ \ / /
  / _ \ | |    | || | | | / /  \ V /
 / ___ \| |___ | || |_| |/ /_   | |
/_/   \_\_____|___|____//____|  |_|

  Authorized access only.
EOF

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/90-banner.conf <<'EOF'
Banner /etc/issue.net
EOF

# --- post-login MOTD (live box card) ---
cat > /etc/update-motd.d/01-alidzy <<'EOF'
#!/bin/sh
printf '\033[1;31m'
cat <<'ART'

    _    _     ___ ____  ________   __
   / \  | |   |_ _|  _ \|__  /\ \ / /
  / _ \ | |    | || | | | / /  \ V /
 / ___ \| |___ | || |_| |/ /_   | |
/_/   \_\_____|___|____//____|  |_|

ART
printf '\033[0m'
echo "  DB / NAS / k8s node  ·  Ryzen 7 5800X · 64GB · RTX 3060 Ti (160W cap)"
echo "  Serve: 07:00-01:00 (ollama)  ·  Train: 01:00-07:00"
echo "  CPU: $(sensors 2>/dev/null | awk '/Tctl/{print $2; exit}')  GPU: $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null)°C  ·  $(uptime -p)"
echo ""
EOF
chmod +x /etc/update-motd.d/01-alidzy

# quiet the noisier stock motd bits (keep security updates notice)
chmod -x /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news 2>/dev/null || true

systemctl reload ssh || systemctl reload sshd || true
echo "--- banner preview ---"
cat /etc/issue.net
/etc/update-motd.d/01-alidzy
echo "ssh banner installed."
