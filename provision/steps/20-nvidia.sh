#!/usr/bin/env bash
# NVIDIA driver for the RTX 3060 Ti — reboot-aware.
# The box boots on 'nouveau'; the proprietary driver only takes over after nouveau
# is blacklisted and the box reboots. So this step:
#   - if nvidia-smi already works -> success (0)
#   - else install the driver, blacklist nouveau, and EXIT 75 to request a reboot
#     (bootstrap.sh reboots and re-runs this step, which then sees nvidia-smi work)
# It never hard-fails the whole run just because a reboot is pending.
set -uo pipefail
source "$HERE/config.env"
export DEBIAN_FRONTEND=noninteractive
REBOOT_SIGNAL=75
MODPROBE_DIR="${MODPROBE_DIR:-/etc/modprobe.d}"
NVIDIA_MODULE_VERSION_FILE="${NVIDIA_MODULE_VERSION_FILE:-/sys/module/nvidia/version}"
NVIDIA_OPERATOR_DRIVER_DIR="${NVIDIA_OPERATOR_DRIVER_DIR:-/run/nvidia/driver}"

# --- Kanboard #1868: the GPU Operator owns the driver on a cluster node -> never install a host driver/toolkit.
# NVIDIA's operator docs describe an operator-managed driver OR a preinstalled host driver, not both; the leftover apt
# 595.84 stack made host nvidia-smi fail with "Driver/library version mismatch" against the loaded 580.178.04 module.
if [[ "${NVIDIA_DRIVER_OWNER:-host}" == "operator" ]]; then
  echo "NVIDIA driver owner = GPU Operator: not installing a host driver or container toolkit."
  if [[ ! -f "$MODPROBE_DIR/blacklist-nouveau.conf" ]]; then
    printf 'blacklist nouveau\noptions nouveau modeset=0\n' > "$MODPROBE_DIR/blacklist-nouveau.conf"
    update-initramfs -u || true
  fi
  if [[ -r "$NVIDIA_MODULE_VERSION_FILE" ]]; then
    echo "operator driver module loaded: $(cat "$NVIDIA_MODULE_VERSION_FILE")"
  else
    echo "operator driver not loaded yet (deployed by the GPU Operator after the node joins the cluster)."
  fi
  # nouveau already loaded: the driver container cannot load nvidia until a reboot (NVIDIA troubleshooting).
  if lsmod 2>/dev/null | grep -q '^nouveau'; then echo "nouveau is loaded: reboot required." >&2; exit "$REBOOT_SIGNAL"; fi
  exit 0
fi

if command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
  echo "NVIDIA driver active:"; nvidia-smi -L; exit 0
fi

echo "nvidia-smi not working yet. GPU on PCI:"; lspci | grep -i nvidia || echo "(no NVIDIA on bus?)"

# Install the driver if the package set isn't present yet.
if ! dpkg -l | grep -q '^ii  nvidia-driver-'; then
  apt-get update -y
  apt-get install -y ubuntu-drivers-common
  if [[ "${NVIDIA_DRIVER:-auto}" == "auto" ]]; then
    ubuntu-drivers install || ubuntu-drivers autoinstall || apt-get install -y nvidia-driver-570 || true
  else
    apt-get install -y "$NVIDIA_DRIVER" || true
  fi
fi

# Ensure nouveau is blacklisted so the reboot brings up the NVIDIA driver.
if [[ ! -f "$MODPROBE_DIR/blacklist-nouveau.conf" ]]; then
  printf 'blacklist nouveau\noptions nouveau modeset=0\n' > "$MODPROBE_DIR/blacklist-nouveau.conf"
  update-initramfs -u || true
fi

# Optional container toolkit for GPU pods (safe to run pre-reboot).
if [[ "${INSTALL_NVIDIA_CONTAINER_TOOLKIT:-false}" == "true" ]] && ! command -v nvidia-ctk >/dev/null; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --batch --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null || true
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list 2>/dev/null || true
  apt-get update -y || true
  apt-get install -y nvidia-container-toolkit || true
fi

if dpkg -l | grep -q '^ii  nvidia-driver-'; then
  echo "NVIDIA driver installed + nouveau blacklisted. Requesting reboot to activate."
  exit "$REBOOT_SIGNAL"
else
  echo "NVIDIA driver did NOT install (check network/repo). Will retry next run." >&2
  exit 1
fi
