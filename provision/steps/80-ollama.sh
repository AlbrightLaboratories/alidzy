#!/usr/bin/env bash
# Smallest-LLM serving on the RTX 3060 Ti (8 GB) via Ollama.
# Candidates (smallest first): llama3.2:1b (~1.3 GB), qwen3:4b (~2.5 GB; the policy light model,
# minimum Qwen 3.8 elsewhere, Kanboard #1752).
# Pulls both, validates each actually generates, and records the review to
# /var/lib/compute-monster/model-review.txt (used by VERIFY).
set -uo pipefail
source "$HERE/config.env"
export DEBIAN_FRONTEND=noninteractive
# Runs under a systemd transient unit with no $HOME — the ollama CLI panics
# without it ("panic: $HOME is not defined").
export HOME="${HOME:-/root}"

# --- Install Ollama (official installer; idempotent) ---
if ! command -v ollama >/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi
systemctl enable --now ollama 2>/dev/null || true

# Wait for the API.
for i in $(seq 1 30); do
  curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS http://127.0.0.1:11434/api/tags >/dev/null || { echo "ollama API not up"; exit 1; }

REVIEW=/var/lib/compute-monster/model-review.txt
mkdir -p /var/lib/compute-monster
: > "$REVIEW"

test_model() {
  local m="$1"
  echo "--- pulling $m (via API) ---"
  # API pull avoids CLI env quirks; blocks until complete with stream=false.
  curl -fsS --max-time 900 http://127.0.0.1:11434/api/pull \
    -d "{\"model\":\"$m\",\"stream\":false}" >/dev/null \
    || { echo "$m: PULL FAILED" >> "$REVIEW"; return 1; }
  echo "--- generating with $m ---"
  local out
  out="$(curl -fsS http://127.0.0.1:11434/api/generate \
        -d "{\"model\":\"$m\",\"prompt\":\"Reply with exactly: OK\",\"stream\":false}" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin).get("response","")[:80])' 2>/dev/null)"
  if [[ -n "$out" ]]; then
    echo "$m: GENERATES ('$out')" >> "$REVIEW"; return 0
  else
    echo "$m: NO OUTPUT" >> "$REVIEW"; return 1
  fi
}

ok_smallest=1; ok_small=1
test_model "llama3.2:1b" && ok_smallest=0
test_model "qwen3:4b"    && ok_small=0

{
  echo
  echo "GPU: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo unknown)"
  if [[ $ok_smallest -eq 0 ]]; then
    echo "SMALLEST-OK: llama3.2:1b (~1.3 GB) — absolute floor, runs fine"
  fi
  if [[ $ok_small -eq 0 ]]; then
    echo "RECOMMENDED-SMALLEST-USEFUL: qwen3:4b (~2.5 GB) — policy light model, better quality, fits in 8 GB"
  fi
} >> "$REVIEW"

cat "$REVIEW"
# Step passes if at least one model generates.
[[ $ok_smallest -eq 0 || $ok_small -eq 0 ]]
