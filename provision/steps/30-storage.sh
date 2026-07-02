#!/usr/bin/env bash
# Mount the 2TB Seagate as $DATA_MOUNT (bulk data). Boot NVMe is untouched.
# Hardened: never selects removable/USB media (a USB stick was once picked and a
# garbage fstab entry written); cleans any stale/bogus /data fstab line first.
set -euo pipefail
source "$HERE/config.env"

# --- Clean any stale /data fstab entry whose UUID doesn't exist on this system ---
if grep -qE "\s${DATA_MOUNT}\s" /etc/fstab; then
  uuid_in_fstab="$(awk -v m="$DATA_MOUNT" '$2==m {sub(/^UUID=/,"",$1); print $1}' /etc/fstab | head -1)"
  if [[ -n "$uuid_in_fstab" ]] && ! blkid -U "$uuid_in_fstab" >/dev/null 2>&1; then
    echo "removing stale $DATA_MOUNT fstab entry (UUID $uuid_in_fstab not present)"
    sed -i.bak "\|\s${DATA_MOUNT}\s|d" /etc/fstab
    systemctl daemon-reload || true
  fi
fi

is_removable() { [[ "$(cat "/sys/block/$(basename "$1")/removable" 2>/dev/null)" == "1" ]]; }
is_usb() { readlink -f "/sys/block/$(basename "$1")" 2>/dev/null | grep -q usb; }

disk="${DATA_DISK:-}"
if [[ -z "$disk" ]]; then
  # Auto-pick the largest NON-nvme, NON-removable, NON-usb whole disk with no mounts.
  best=""; best_size=0
  while read -r name type size; do
    [[ "$type" == "disk" ]] || continue
    [[ "$name" == *nvme* ]] && continue
    is_removable "$name" && { echo "skip $name (removable)"; continue; }
    is_usb "$name" && { echo "skip $name (usb)"; continue; }
    lsblk -no MOUNTPOINT "$name" | grep -q '[^[:space:]]' && { echo "skip $name (mounted)"; continue; }
    bytes=$(lsblk -bdno SIZE "$name")
    (( bytes > best_size )) && { best="$name"; best_size=$bytes; }
  done < <(lsblk -dpno NAME,TYPE,SIZE)
  disk="$best"
fi

if [[ -z "$disk" || ! -b "$disk" ]]; then
  echo "No eligible data disk found (Seagate absent/uncabled?). Skipping — will retry next run." >&2
  exit 0
fi

echo "Data disk = $disk"
part="${disk}1"; [[ "$disk" == *nvme* ]] && part="${disk}p1"

if ! lsblk -no NAME "$disk" | grep -q "$(basename "$part")"; then
  echo "Partitioning $disk (single GPT partition)..."
  parted -s "$disk" mklabel gpt
  parted -s "$disk" mkpart primary "$DATA_FS" 0% 100%
  sleep 2
fi

if ! blkid "$part" >/dev/null 2>&1; then
  echo "Formatting $part as $DATA_FS..."
  mkfs."$DATA_FS" -F "$part"
fi

uuid="$(blkid -s UUID -o value "$part")"
mkdir -p "$DATA_MOUNT"
if ! grep -q "$uuid" /etc/fstab; then
  echo "UUID=$uuid  $DATA_MOUNT  $DATA_FS  defaults,nofail,x-systemd.device-timeout=10  0  2" >> /etc/fstab
fi
mount -a
echo "Mounted $part ($uuid) at $DATA_MOUNT:"
df -h "$DATA_MOUNT"
