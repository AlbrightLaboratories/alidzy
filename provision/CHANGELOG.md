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
