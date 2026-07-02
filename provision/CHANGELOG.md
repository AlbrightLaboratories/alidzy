# compute-monster provisioning — CHANGELOG

The control record for the build-out loop. Read the status tags:

- 🔧 **on-main** — fix is in the repo `main`; the box **pulls it automatically** on the next
  provision run (`firstboot.sh` self-heals). Not yet proven on hardware.
- 🧪 **tested** — verified working on the actual box.
- 📀 **baked** — included in a cut ISO image (offline fallback + fresh-install default).

## The loop

1. We fix something → it lands on `main` (🔧). The box pulls + applies it on re-run.
2. You confirm it works on the box → mark 🧪.
3. You say **"add that to the iso"** → the item is queued for the next image.
4. You say **re-image** → `build-iso.sh` cuts a new ISO from `main`, we log an **ISO image**
   entry listing everything 📀 in it, then `flash-usb.sh` writes the USB for a clean install.

Because the ISO pulls `main` at boot, a fresh install already gets the latest 🔧 fixes;
re-imaging mainly refreshes the **offline fallback** and pins a known-good baseline.

---

## Unreleased — on `main` (pulled live by the box)

### 2026-07-02 — RGB + storage fixes (iterating)
- 🧪 **OpenRGB install fixed.** OpenRGB is **not in Ubuntu's repos** (`E: Unable to locate
  package openrgb`), so the meteor service never started. Now installs the upstream `.deb`
  (`openrgb_0.9_amd64_bookworm` — runs on noble). Services now **active**; VERIFY reports
  "meteor animating". `step 40-openrgb.sh`.
- 🔧 **Stale-marker bug: changed steps now re-run (hash-aware markers).** The resumable
  bootstrap skipped any step with a `.done` marker even after the step's script changed —
  so the 1.0rc3 upgrade in step 40 never executed (box stayed on 0.9; device list showed
  4× Corsair RAM + Gigabyte RTX 3060 Ti + MSI B550-A PRO, **no Lian Li hub**). Markers now
  store the step's sha256; edit a step → it re-runs. Legacy empty markers migrate cleanly.
- 🔧 **Fans dark → OpenRGB version bump to 1.0rc3.** `lsusb` confirms the hub IS on the bus
  (`0cf2:a102 ENE Technology LianLi-SL-infinity-v1.4`), so it's not a cable — **OpenRGB 0.9
  simply lacks the SL-Infinity v1.4 detector** (it saw only the Corsair RAM). Switched
  `40-openrgb.sh` to install **OpenRGB 1.0rc3** (version-aware, `--allow-downgrades`) and to
  **restart** the services so the new binary re-detects. Also seen on the bus: MSI Mystic
  Light (`1462:7c56`). (Pending 🧪 confirmation that 1.0rc3 lists the Lian Li hub.)
- ❌ **2 TB Seagate not present.** `lsblk` shows only the NVMe + the FAT32 USB (sda, at
  /mnt/usb) — no 2 TB disk. Storage step wrongly picked the USB and a stale `/data` fstab
  entry (bad UUID) exists. Needs: confirm the Seagate is cabled; harden `30-storage.sh` to
  ignore removable/USB media and never write a bad fstab entry. (Not yet 🧪.)

### 2026-07-02 — CI runner privilege bootstrap
- 🧪 **Passwordless sudo for the runner user.** CI runs as `a_guy` and provisioning needs
  root; without a NOPASSWD grant, `sudo` in CI failed ("a password is required"). Fixed
  structurally so no human types it again: root provisioning step `05-runner-sudo.sh`
  (validated with `visudo -c`), the ISO autoinstall late-commands, and `register-runner.sh`.
  On the *current* box it was applied manually once (the privilege-bootstrap can't grant
  itself without an existing root/password — see note below).
- 🔧 **Reboot-safe CI.** `provision-verify` kicks provisioning as a detached transient unit
  (`systemd-run --no-block`) so the NVIDIA reboot can't kill the job, then reports VERIFY
  state + dumps logs for remote iteration.

> **Why the sudo grant needs one manual run on an already-installed box:** the runner is
> unprivileged and cannot grant itself root without root; the only no-password root contexts
> are the installer and the root provisioning service, which future boxes use automatically.

### 2026-07-02 — root-cause fix for the failed first install
- 🔧 **Resumable, fault-tolerant, reboot-aware bootstrap.** A single failing step no longer
  aborts the whole run (was `set -e`); steps record `/var/lib/compute-monster/steps/<n>.done`
  and are skipped on re-run. Fixes: "one step failed → RGB/storage/WOL/k8s all skipped."
- 🔧 **NVIDIA step reboot-aware.** Installs the driver, **blacklists nouveau**, and requests a
  reboot (exit 75) to activate — then resumes and continues. Fixes: "GPU bound to nouveau,
  nvidia-smi failed, bootstrap died."
- 🔧 **Self-healing repo pull.** `firstboot.sh` clones/pulls this repo on each boot and runs
  the latest scripts (baked copy = offline fallback), via `compute-monster-provision.service`
  that runs until `/var/lib/compute-monster/provisioned` exists.
- 🔧 **CI loop.** `provision-verify` workflow + `register-runner.sh` so provisioning can be
  dispatched and its results read remotely instead of copy-paste.

---

## ISO images

### image-002 — 2026-07-02  (current — clean-install validation pending)
- 📀 Self-healing **pull model**: `compute-monster-provision.service` runs `firstboot.sh`,
  which git-pulls `main` and runs the resumable bootstrap (baked copy = offline fallback).
- 📀 Resumable, fault-tolerant, **reboot-aware** bootstrap (all the 2026-07-02 fixes above).
- 📀 Ubuntu 24.04.4 autoinstall; user `a_guy`, tz America/New_York; wipes NVMe only.
- sha256 `b38985329574098745d4b8442e58eab01463fe4d442f68c9b5f3654c5bf0aeed`
- **Status:** flashed to USB; a clean install is the end-to-end test. Because it pulls
  `main`, later fixes reach fresh installs without another re-image.

### image-001 — 2026-07-02  (❌ superseded)
- 📀 Ubuntu 24.04.4 unattended autoinstall; user `a_guy`, tz America/New_York; wipes NVMe only.
- 📀 Baked provision bundle + first-boot service (original fragile version).
- **Result:** install OK, but provisioning aborted on the NVIDIA/nouveau step; RGB never ran.
- **Superseded by** the Unreleased fixes above — do not reuse; re-image after fixes are 🧪.
