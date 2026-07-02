#!/usr/bin/env bash
# compute-monster — RESUMABLE, fault-tolerant, reboot-aware provisioner.
#
# Design goals (why this exists): a single failing step must NEVER strand the box,
# and the NVIDIA driver's required reboot must not abort provisioning. So:
#   - steps run independently; a failure is logged and we CONTINUE (no set -e abort)
#   - each step's success is recorded in /var/lib/compute-monster/steps/<n>.done
#     and skipped on re-run (idempotent + resumable)
#   - a step may request a reboot by exiting 75; we reboot and RESUME next boot
#   - the final marker /var/lib/compute-monster/provisioned is written only when
#     every step has succeeded
#
# Run: sudo ./bootstrap.sh            (all pending steps)
#      sudo ./bootstrap.sh 40 50      (only these step numbers, ignores markers)
set -uo pipefail   # deliberately NO -e: we handle errors per step

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/config.env"
export HERE
STATE=/var/lib/compute-monster
LOG_DIR="$HERE/log"
mkdir -p "$STATE/steps" "$LOG_DIR"

if [[ $EUID -ne 0 ]]; then echo "Run with sudo/root." >&2; exit 1; fi

REBOOT_SIGNAL=75
REBOOT_CAP=4
want="${*:-}"
forced="[[ -n \"$want\" ]]"

overall_fail=0
reboot_requested=0

step_hash() { sha256sum "$1" | cut -c1-16; }

for f in "$HERE"/steps/*.sh; do
  n="$(basename "$f" | grep -oE '^[0-9]+')"
  name="$(basename "$f")"
  h="$(step_hash "$f")"
  # A step is "done" only if its marker matches the CURRENT script hash —
  # editing a step re-runs it (stale .done markers froze old bugs in place).
  if [[ -n "$want" ]]; then
    [[ " $want " == *" $n "* ]] || continue
  elif [[ -f "$STATE/steps/$n.done" && "$(cat "$STATE/steps/$n.done" 2>/dev/null)" == "$h" ]]; then
    echo "=== [$name] already done (hash match) — skip ==="; continue
  fi

  echo "=== [$name] $(date -Is) ==="
  bash "$f" 2>&1 | tee "$LOG_DIR/${name}.log"
  rc="${PIPESTATUS[0]}"

  if [[ "$rc" -eq 0 ]]; then
    echo "$h" > "$STATE/steps/$n.done"; echo "--- [$name] OK ---"
  elif [[ "$rc" -eq "$REBOOT_SIGNAL" ]]; then
    echo "--- [$name] requests REBOOT to continue ---"; reboot_requested=1; break
  else
    echo "!!! [$name] FAILED (rc=$rc) — continuing; see $LOG_DIR/${name}.log" >&2
    overall_fail=1
  fi
done

# Handle a requested reboot, with a loop guard.
if [[ "$reboot_requested" -eq 1 ]]; then
  count="$(cat "$STATE/reboot-count" 2>/dev/null || echo 0)"
  if [[ "$count" -ge "$REBOOT_CAP" ]]; then
    echo "Reboot cap ($REBOOT_CAP) reached — NOT rebooting again. Continuing without it." >&2
  else
    echo "$((count+1))" > "$STATE/reboot-count"
    echo "Rebooting to continue provisioning (attempt $((count+1))/$REBOOT_CAP)..."
    sync; systemctl reboot; exit 0
  fi
fi

# Mark fully provisioned only if every step has a .done marker.
all_done=1
for f in "$HERE"/steps/*.sh; do
  n="$(basename "$f" | grep -oE '^[0-9]+')"
  [[ -f "$STATE/steps/$n.done" ]] || { all_done=0; break; }
done

echo
if [[ "$all_done" -eq 1 ]]; then
  touch "$STATE/provisioned"
  # stop re-running on every boot if the systemd unit is installed
  systemctl disable compute-monster-provision.service 2>/dev/null || true
  echo "ALL STEPS COMPLETE ✅  ->  run:  sudo bash $HERE/VERIFY.sh"
else
  echo "Provisioning incomplete (some steps pending/failed). It will retry on next boot,"
  echo "or re-run: sudo bash $HERE/bootstrap.sh   (check $LOG_DIR/ for failures)"
  [[ "$overall_fail" -eq 1 ]] && exit 1 || exit 0
fi
