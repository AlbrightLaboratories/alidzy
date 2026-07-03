#!/usr/bin/env bash
# Register this box as a GitHub Actions self-hosted runner labelled 'compute-monster'
# so the provision-verify workflow can run on it and we can iterate remotely.
#
# 1) On a machine with gh, mint a short-lived registration token:
#      gh api -X POST repos/AlbrightLaboratories/compute-monster/actions/runners/registration-token -q .token
# 2) On the box (as the login user, NOT root):
#      RUNNER_TOKEN=<token> bash provision/register-runner.sh
set -euo pipefail

REPO_URL="${REPO_URL_HTTP:-https://github.com/AlbrightLaboratories/alidzy}"
: "${RUNNER_TOKEN:?set RUNNER_TOKEN=... (gh api ... registration-token -q .token)}"
LABELS="${LABELS:-compute-monster}"
NAME="${RUNNER_NAME:-compute-monster}"
DIR="${RUNNER_DIR:-$HOME/actions-runner}"

[[ $EUID -ne 0 ]] || { echo "Do NOT run as root — run as your login user (a_guy)."; exit 1; }

# Latest runner version.
VER="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | grep -oE '"tag_name": *"v[0-9.]+"' | grep -oE '[0-9.]+' | head -1)"
[[ -n "$VER" ]] || VER="2.320.0"

echo "Runner version: v${VER}"
mkdir -p "$DIR"; cd "$DIR"
if [[ ! -x ./run.sh ]]; then
  echo "Downloading actions runner..."
  curl -fsSL -o runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-x64-${VER}.tar.gz"
  tar xzf runner.tar.gz && rm runner.tar.gz
fi

# A fresh minimal Ubuntu server lacks the runner's .NET deps (libicu, etc.);
# without these config.sh fails. installdependencies.sh needs root.
echo "Installing runner OS dependencies (needs sudo)..."
sudo ./bin/installdependencies.sh

echo "Configuring runner (repo=$REPO_URL name=$NAME labels=$LABELS)..."
./config.sh --unattended --replace \
  --url "$REPO_URL" --token "$RUNNER_TOKEN" \
  --name "$NAME" --labels "$LABELS"

# CI provisioning runs `sudo` non-interactively; grant this box's runner user
# passwordless sudo (dedicated provisioning box).
echo "Granting passwordless sudo to $USER (for CI provisioning)..."
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99-compute-monster-runner >/dev/null
sudo chmod 440 /etc/sudoers.d/99-compute-monster-runner

echo "Installing + starting the runner service..."
sudo ./svc.sh install "$USER"
sudo ./svc.sh start
sudo ./svc.sh status || true
echo "DONE — Runner '$NAME' registered + running (labels: $LABELS)."
