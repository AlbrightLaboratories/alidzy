#!/usr/bin/env bash
# Build the compute-monster unattended restore ISO from a stock Ubuntu 24.04
# live-server ISO. Works on macOS (brew install xorriso) or Linux.
# Bakes in: nocloud autoinstall seed (creds/timezone) + the provision bundle,
# and sets an "autoinstall" GRUB default so it installs hands-off.
#
# Usage:
#   PASSWORD='1Sony317!' ACCOUNT=a_guy TZ=America/New_York ./build-iso.sh
# Optional: SRC_ISO=/path/to/ubuntu-24.04.4-live-server-amd64.iso
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UBUNTU_ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
UBUNTU_SHA="e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
ACCOUNT="${ACCOUNT:-a_guy}"
HOSTNAME_WANT="${HOSTNAME_WANT:-alidzy}"
TIMEZONE="${TZ:-America/New_York}"
NVME="${NVME:-/dev/nvme0n1}"
WORK="${WORK:-/tmp/cmiso}"
OUT="${OUT:-$HOME/Downloads/compute-monster-restore.iso}"
: "${PASSWORD:?set PASSWORD=... (the account password to hash)}"

command -v xorriso >/dev/null || { echo "install xorriso (macOS: brew install xorriso; Linux: apt install xorriso)"; exit 1; }
mkdir -p "$WORK"; cd "$WORK"

# 1) Get + verify the stock ISO
SRC_ISO="${SRC_ISO:-$WORK/$(basename "$UBUNTU_ISO_URL")}"
[[ -f "$SRC_ISO" ]] || wget -c -O "$SRC_ISO" "$UBUNTU_ISO_URL"
echo "$UBUNTU_SHA  $SRC_ISO" | { shasum -a 256 -c - 2>/dev/null || sha256sum -c - ; }

# 2) Hash the password (SHA-512)
HASH="$(python3 -c "from passlib.hash import sha512_crypt; print(sha512_crypt.using(rounds=5000).hash('$PASSWORD'))" 2>/dev/null \
       || openssl passwd -6 "$PASSWORD")"

# 3) NoCloud seed
mkdir -p "$WORK/nocloud"
printf 'instance-id: %s\nlocal-hostname: %s\n' "$HOSTNAME_WANT" "$HOSTNAME_WANT" > "$WORK/nocloud/meta-data"
cat > "$WORK/nocloud/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  timezone: $TIMEZONE
  keyboard: {layout: us}
  refresh-installer: {update: no}
  storage:
    layout: {name: direct, match: {path: $NVME}}
  identity:
    hostname: $HOSTNAME_WANT
    realname: $ACCOUNT
    username: $ACCOUNT
    password: "$HASH"
  ssh: {install-server: true, allow-pw: true}
  packages: [curl, git, ethtool, unzip]
  late-commands:
    # Baked offline fallback bundle.
    - mkdir -p /target/opt/compute-monster-provision /target/opt/compute-monster
    - cp -r /cdrom/provision/* /target/opt/compute-monster-provision/ 2>/dev/null || true
    # Seed /opt/compute-monster with the baked bundle; firstboot.sh git-pulls the
    # latest from the repo on boot when online, else uses this copy.
    - cp -r /cdrom/provision /target/opt/compute-monster/ 2>/dev/null || true
    - chmod +x /target/opt/compute-monster-provision/*.sh /target/opt/compute-monster-provision/steps/*.sh 2>/dev/null || true
    - chmod +x /target/opt/compute-monster/provision/*.sh /target/opt/compute-monster/provision/steps/*.sh 2>/dev/null || true
    # Passwordless sudo for the runner user (installer runs as root here).
    - "echo '$ACCOUNT ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/99-compute-monster-runner"
    - chmod 440 /target/etc/sudoers.d/99-compute-monster-runner
    # Self-healing resumable provisioner service (runs on boot until complete).
    - install -m 0644 /cdrom/provision/systemd/compute-monster-provision.service /target/etc/systemd/system/compute-monster-provision.service
    - curtin in-target --target=/target -- systemctl enable compute-monster-provision.service
EOF
python3 -c "import yaml; yaml.safe_load(open('$WORK/nocloud/user-data'))" && echo "user-data YAML OK"

# 4) Provision bundle payload (exclude big/local dirs)
rm -rf "$WORK/provision_payload"; mkdir -p "$WORK/provision_payload"
rsync -a --exclude backups --exclude log "$HERE/" "$WORK/provision_payload/"

# 5) Edit GRUB: add unattended autoinstall default + short timeout
rm -f "$WORK/grub.cfg"
xorriso -osirrox on -indev "$SRC_ISO" -extract /boot/grub/grub.cfg "$WORK/grub.cfg"
chmod u+w "$WORK/grub.cfg"
python3 - "$WORK/grub.cfg" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read().replace('set timeout=30','set timeout=5')
entry='''set default=0

menuentry "AUTOINSTALL alidzy  (WIPES the NVMe, unattended)" {
\tset gfxpayload=keep
\tlinux\t/casper/vmlinuz autoinstall "ds=nocloud;s=/cdrom/nocloud/"  ---
\tinitrd\t/casper/initrd
}
'''
i=s.index('menuentry "Try or Install Ubuntu Server"')
open(p,'w').write(s[:i]+entry+"\n"+s[i:])
PY

# 6) Remaster (clone hybrid BIOS/UEFI boot, overlay our files)
rm -f "$OUT"
xorriso -indev "$SRC_ISO" -outdev "$OUT" -boot_image any replay \
  -map "$WORK/grub.cfg" /boot/grub/grub.cfg \
  -map "$WORK/nocloud" /nocloud \
  -map "$WORK/provision_payload" /provision \
  -commit
echo "Built: $OUT"
echo "Flash with: sudo bash $HERE/flash-usb.sh"
