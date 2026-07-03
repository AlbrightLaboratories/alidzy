#!/usr/bin/env bash
# Base system: updates, essentials, hostname.
set -euo pipefail
source "$HERE/config.env"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  build-essential dkms curl wget git ca-certificates gnupg lsb-release \
  ethtool lm-sensors pciutils usbutils nvme-cli htop unzip jq python3 python3-pip python3-venv

if [[ -n "${HOSTNAME_WANT:-}" && "$(hostnamectl --static)" != "$HOSTNAME_WANT" ]]; then
  hostnamectl set-hostname "$HOSTNAME_WANT"
  # keep /etc/hosts in sync so sudo doesn't warn "unable to resolve host"
  if grep -qE "^127\.0\.1\.1" /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $HOSTNAME_WANT/" /etc/hosts
  else
    echo "127.0.1.1 $HOSTNAME_WANT" >> /etc/hosts
  fi
  echo "hostname -> $HOSTNAME_WANT"
fi

echo "base packages installed."
