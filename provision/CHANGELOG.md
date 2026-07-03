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

## Unreleased — post-v1.0.0

### 2026-07-03 — GitHub runner removed from the node
- 🧪 Actions runner service uninstalled, files deleted, registration removed (0 runners);
  provision-verify workflow retired. **Direct SSH (key-auth) is the ops channel now.**
- 📌 Kept deliberately: the boot-time self-heal `git pull` (read-only https, public repo,
  no credentials) — it is what makes the restore ISO always come up current. Say the word
  to sever that too and go fully offline-from-GitHub.


### 2026-07-03 — rename: compute-monster → Alidzy
- 🔧 Repo renamed to **AlbrightLaboratories/alidzy** (GitHub redirects old URLs; box's
  git pulls unaffected). Runner gained the `alidzy` label; workflow targets it.
- 🔧 Hostname → **alidzy** (lowercase — k8s RFC1123) via step 10 (now re-runs on
  config.env changes via `10.deps`; also syncs /etc/hosts). VERIFY + ISO seed updated.
- 📌 Internal paths (`/opt/compute-monster`, service names) intentionally kept for now —
  renaming them on a live box is churn without benefit; revisit at the next clean install.

### image-005 — 2026-07-03 (current restore ISO)
- 📀 v1.0.0 baseline + step 85 (160W GPU cap + train/serve timers). Exactly matches the
  running box. sha256 `dd24242a9981d59b729e545d48b6c2b03a0f7e6e09802da2a9ba9592aeb93b58`,
  at `~/Downloads/compute-monster-restore.iso`. Flash: `sudo bash flash-usb.sh`.

### 2026-07-03 — GPU power cap + train/serve schedule (step 85)
- 🔧 **160W GPU power cap**, persistent via `gpu-power-cap.service` (persistence mode +
  `nvidia-smi -pl 160`). Cooler under load (~70-75°C), ~$50/yr at KUA, ~10% training cost.
  Reversible: `nvidia-smi -pl 200`.
- 🔧 **Night-train / day-serve timers**: 01:00 stops ollama and runs
  `/opt/compute-monster/training/train.sh` if present; 07:00 kills training and restarts
  ollama. Enforces the 8GB-VRAM split (serving and QLoRA can't coexist).

## Release v1.0.0 — 2026-07-03 — "fans red, box green" (operator-accepted)

**The compute-monster is fully operational and operator-confirmed.** Everything below is
🧪 tested on the hardware and reproducible from a fresh install via the self-healing
provisioner (steps 05–80):

| Component | State |
|---|---|
| Ubuntu 24.04 unattended install (wipes NVMe only) | 🧪 |
| NVIDIA driver (RTX 3060 Ti), reboot-aware install | 🧪 |
| **Fans: pure-red Meteor on all 4 hub groups (lianli-linux)** — "perfect" per operator | 🧪 |
| Smallest-LLM serving: qwen2.5:0.5b floor / llama3.2:1b recommended (Ollama) | 🧪 |
| Wake-on-LAN (enp42s0), sensors, swap-off, containerd, kubeadm v1.31 + max-pods 160 | 🧪 |
| CI loop: self-hosted runner + provision-verify workflow | 🧪 |
| Seagate 2TB `/data` | ⏸ parked — drive not yet installed; auto-mounts when cabled |

### 2026-07-03 — pure-red tuning (operator: "perfect!")
- 🧪 Pink wash eliminated: all 4 Meteor color slots set to pure `[255,0,0]` (the old
  `#DD1713` tail carried green/blue and interpolated pink on some blades).

### 2026-07-03 — 🎉🧪 FANS CONFIRMED: red meteor running (operator-verified)
- 🧪 **Operator visually confirmed the fans run the red meteor** (docs/09 profile:
  Meteor, #FF0000 + #DD1713 tail, all 4 hub groups) via **lianli-linux**
  (github.com/sgtaziz/lian-li-linux) — the open-source L-Connect 3 replacement whose
  reverse-engineered ENE 6K77 protocol actually drives this hub.
- **Final architecture:** `lianli-daemon` runs as an `a_guy` user service (linger enabled),
  reads `~/.config/lianli/config.json` (written by step 46), re-applies the effect at every
  boot. OpenRGB services removed. Steps 45+46 fully reproduce this on a fresh install.
- 📌 **Finding for the record:** OpenRGB (1.0rc3 AND master git2031) detects the
  SL-Infinity hub (0cf2:a102) but its LED writes are silently ignored by this firmware
  (v1.5 per lianli-daemon readback; USB string says v1.4). Only fan-count/speed ops land.
  Kernel USB/HID stack verified healthy throughout — the gap is OpenRGB's protocol.
  Consider filing upstream with these diagnostics.

### 2026-07-02 — RGB root cause found: no "Direct" mode; switched to NATIVE hub Meteor
- 🔧 **Why the fans never lit:** the Lian Li hub exposes **no "Direct" mode** — every
  `set_mode("Direct")` failed (silently, until we logged it), so all animator frames were
  ignored. Its writable mode is **"Custom"**; its mode list also includes a **native
  hardware "Meteor"**.
- 🔧 **Fix — use the hub's native Meteor (red):** hardware-rendered across ALL connected
  fans (zone sizes irrelevant), zero software dependency, persists like L-Connect hardware
  effects. `meteor.py` sets native Meteor + red colors + speed and exits clean; the Custom
  software animator remains as fallback (`NATIVE_METEOR=0`).
- Box logged `native mode active — no software animation needed; exiting OK`.
  (Awaiting operator visual confirm → 🧪.)

### 2026-07-02 — fans still dark: hub zones were 0 LEDs
- 🔧 **Step-asset deps now hashed** (steps/<n>.deps manifests): editing rgb/meteor.py did NOT re-run step 40 (only the step script was hashed), so the zone-resize fix never deployed. Added 40.deps → asset edits now redeploy.
- 🔧 **Operator reports no red fans despite "animating" log.** Root cause hypothesis:
  OpenRGB models the Lian Li hub's 4 channels as **resizable zones defaulting to 0 LEDs**;
  the animator was driving an empty LED list (software green, fans dark). `meteor.py` now
  **resizes every resizable zone to max**, reconnects, **logs actual LED counts** per
  device, and hard-fails if all targets still have 0 LEDs (no more silent success).

### 2026-07-02 — 🧪 smallest-model review COMPLETE
- 🧪 **Both candidates generate on the RTX 3060 Ti (8192 MiB):**
  `qwen2.5:0.5b` (~0.4 GB) → GENERATES ('OK') — **smallest that runs okay**;
  `llama3.2:1b` (~1.3 GB) → GENERATES ('OK') — **recommended smallest-useful**.
  VERIFY LLM check passes. Review file: `/var/lib/compute-monster/model-review.txt`.
- Machine state: **all software checks green**; only the 2 `/data` checks fail (Seagate
  physically absent — hardware cabling at the box).

### 2026-07-02 — Ollama headless fix
- 🔧 **Model pulls failed headless:** `ollama pull` panics under the systemd transient unit
  (`panic: $HOME is not defined`). Step 80 now exports `HOME` and pulls via the **HTTP API**
  (`/api/pull`, stream=false, 15-min cap) — immune to CLI env quirks. (Pending 🧪.)

### 2026-07-02 — software all-green; smallest-LLM phase begins
- 🧪 **VERIFY marker path fixed** (checked old `/var/lib/compute-monster-provisioned`; new
  bootstrap writes `/var/lib/compute-monster/provisioned`). Software checks now **all
  green** — the only failures are the 2 `/data` checks (Seagate physically absent; needs
  SATA/power cabling at the box; auto-mounts when it appears).
- 🔧 **Step 80: Ollama + smallest-model review.** Installs Ollama, pulls **qwen2.5:0.5b**
  (~0.4 GB, absolute floor) and **llama3.2:1b** (~1.3 GB, recommended smallest-useful),
  validates each actually generates on the RTX 3060 Ti (8 GB), records the review to
  `/var/lib/compute-monster/model-review.txt`; VERIFY gains an LLM-serving check.

### 2026-07-02 — 🎉 FANS RED: Lian Li hub detected, meteor on the fans
- 🧪 **OpenRGB 1.0rc3 detects the hub:** device list now shows `Lian Li Uni Hub - SL
  Infinity`, and the animator logs `animating meteor on: ['Lian Li Uni Hub - SL Infinity']`
  — the red meteor runs on the actual fans (operator visual confirm pending).
- 🔧 **gpg idempotency:** step 70 failed on re-run (`gpg: cannot open '/dev/tty'` —
  overwrite prompt with no tty). All `gpg --dearmor` now `--batch --yes` (steps 20/70).
- 🔧 **Storage hardening:** `30-storage.sh` now skips **removable/USB** disks (it once
  picked the USB stick and wrote a garbage `/data` fstab entry with an ISO-date UUID) and
  **removes stale fstab entries** whose UUID no longer exists. Seagate remains physically
  absent from `lsblk` — hardware check (SATA data + power) still needed at the box.

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

### image-003 — 2026-07-02  (current — built, awaiting flash + clean-install proof)
- 📀 Everything through the smallest-model milestone baked in: hash-aware resumable
  bootstrap, reboot-aware NVIDIA step, runner passwordless-sudo (installer + step 05),
  OpenRGB **1.0rc3** (Lian Li SL-Infinity detected), storage hardening (no USB picks,
  stale-fstab cleanup), gpg idempotency, **Ollama + smallest-model step 80**.
- sha256 `05aaa2c2fc323309fd4f55c39d10fc177ee3b6c2e6f84b51d4c015cf4a2af427`
- At `~/Downloads/compute-monster-restore.iso`. Flash: `sudo bash flash-usb.sh`
  (note: current USB holds `register-here.sh`; flashing overwrites it — it's preserved in
  the repo at `provision/register-runner.sh` equivalent).

### image-002 — 2026-07-02  (superseded — clean-install validation pending)
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
