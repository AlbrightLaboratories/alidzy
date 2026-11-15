#!/usr/bin/env bash
# Kanboard #1868 — unit test for steps/20-nvidia.sh (runs anywhere: every external command is stubbed).
# Contract: when the GPU Operator owns the driver (NVIDIA_DRIVER_OWNER=operator) step 20 must NOT install a
# host NVIDIA driver (that is what created the NVML 595.84 vs module 580.178.04 mismatch). When the host owns
# the driver (NVIDIA_DRIVER_OWNER=host) the old behaviour must be unchanged.
set -uo pipefail
HERE_REAL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
ok(){ printf '  PASS %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

run_step() { # $1 = owner ; sets RC and CALLS
  local owner="$1" T; T="$(mktemp -d)"
  mkdir -p "$T/bin" "$T/modprobe.d" "$T/driver" "$T/here"
  cp "$HERE_REAL/config.env" "$T/here/config.env"
  : > "$T/calls"
  for c in apt-get ubuntu-drivers update-initramfs curl gpg; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\nexit 0\n' "$c" "$T" > "$T/bin/$c"; chmod +x "$T/bin/$c"
  done
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/nvidia-smi"          # host nvidia-smi absent/broken
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/lspci"
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/dpkg"                  # no nvidia-driver-* installed
  chmod +x "$T/bin/"*
  echo "580.178.04" > "$T/module-version"
  : > "$T/driver/driver-ready"
  CALLS="$T/calls"
  PATH="$T/bin:$PATH" HERE="$T/here" NVIDIA_DRIVER_OWNER="$owner" \
    NVIDIA_MODULE_VERSION_FILE="$T/module-version" NVIDIA_OPERATOR_DRIVER_DIR="$T/driver" MODPROBE_DIR="$T/modprobe.d" \
    bash "$HERE_REAL/steps/20-nvidia.sh" >"$T/out" 2>&1
  RC=$?; OUT="$T/out"; TMPD="$T"
}

echo "== owner=operator: no host driver install, exit 0, nouveau still blacklisted"
run_step operator
[[ $RC -eq 0 ]] && ok "exit 0" || bad "exit $RC (want 0)"
grep -qE '^(apt-get|ubuntu-drivers)' "$CALLS" && bad "installed host packages: $(tr '\n' ';' < "$CALLS")" || ok "no apt-get / ubuntu-drivers call"
[[ -f "$TMPD/modprobe.d/blacklist-nouveau.conf" ]] && ok "nouveau blacklist ensured" || bad "nouveau blacklist not ensured"

echo "== owner=host: legacy behaviour kept (installs driver, requests reboot 75)"
run_step host
grep -q '^ubuntu-drivers' "$CALLS" && ok "host owner still installs via ubuntu-drivers" || bad "host owner no longer installs"

echo; [[ $fails -eq 0 ]] && echo "ALL PASS" || echo "$fails FAILED"
exit $((fails>0))
