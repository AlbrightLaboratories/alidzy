#!/usr/bin/env bash
# First-boot / self-heal entrypoint. Pulls the latest provisioning from the repo
# (so fixes land without rebuilding the ISO), then runs the resumable bootstrap.
# Falls back to the baked-in copy if offline.
set -uo pipefail

# Load repo settings from whichever copy we can find.
for c in /opt/compute-monster/provision/config.env /opt/compute-monster-provision/config.env; do
  [[ -f "$c" ]] && { source "$c"; break; }
done
REPO_URL="${REPO_URL:-https://github.com/AlbrightLaboratories/alidzy.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
REPO_DIR="${REPO_DIR:-/opt/compute-monster}"

online() { curl -fsI --max-time 8 https://github.com >/dev/null 2>&1; }

if online && command -v git >/dev/null; then
  if [[ -d "$REPO_DIR/.git" ]]; then
    echo "self-heal: git pull $REPO_DIR"
    git -C "$REPO_DIR" fetch --depth 1 origin "$REPO_BRANCH" && \
    git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH" || true
  else
    echo "self-heal: git clone $REPO_URL -> $REPO_DIR"
    rm -rf "$REPO_DIR"
    git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR" || true
  fi
fi

if [[ -x "$REPO_DIR/provision/bootstrap.sh" ]]; then
  SRC="$REPO_DIR/provision"
elif [[ -x /opt/compute-monster-provision/bootstrap.sh ]]; then
  echo "self-heal: using baked-in fallback bundle"
  SRC="/opt/compute-monster-provision"
else
  echo "no provisioning bundle found" >&2; exit 1
fi

exec bash "$SRC/bootstrap.sh"
