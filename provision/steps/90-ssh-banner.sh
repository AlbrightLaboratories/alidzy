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

# --- post-login MOTD (rainbow art + live box card) ---
cat > /etc/update-motd.d/01-alidzy <<'EOF'
#!/bin/bash
# rainbow line colors (256-color): red orange yellow green cyan violet
C=(196 208 226 46 51 135)
R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
c(){ printf '\033[1;38;5;%sm' "$1"; }

echo
printf '%s' "$(c ${C[0]})";  echo '        _    _     ___ ____  ________   __'
printf '%s' "$(c ${C[1]})";  echo '       / \  | |   |_ _|  _ \|__  /\ \ / /'
printf '%s' "$(c ${C[2]})";  echo '      / _ \ | |    | || | | | / /  \ V /'
printf '%s' "$(c ${C[3]})";  echo '     / ___ \| |___ | || |_| |/ /_   | |'
printf '%s' "$(c ${C[4]})";  echo '    /_/   \_\_____|___|____//____|  |_|'
printf '%s' "$(c ${C[5]})";  echo '        ✦ ·  ⋆   ·     ── meteor online ──╼'
printf '%s' "$R"
echo
printf "    ${B}⚡${R} DB · NAS · k8s node    ${B}🧠${R} gemma-class LLM serving\n"
printf "    ${D}Ryzen 7 5800X · 64GB DDR4 · RTX 3060 Ti (160W cap)${R}\n"
printf "    ${D}Serve 07:00-01:00 (ollama) · Train 01:00-07:00${R}\n"
cpu=$(sensors 2>/dev/null | awk '/Tctl/{gsub(/\+/,"");print $2; exit}')
gpu=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null)
printf "    🌡  CPU ${B}%s${R} · GPU ${B}%s°C${R} · %s\n" "${cpu:-n/a}" "${gpu:-n/a}" "$(uptime -p)"
echo
EOF
chmod +x /etc/update-motd.d/01-alidzy

# quiet the noisier stock motd bits (keep security updates notice)
chmod -x /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news 2>/dev/null || true

systemctl reload ssh || systemctl reload sshd || true
echo "--- banner preview ---"
cat /etc/issue.net
/etc/update-motd.d/01-alidzy
echo "ssh banner installed."
