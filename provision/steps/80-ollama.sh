#!/usr/bin/env bash
# Smallest-LLM serving on the RTX 3060 Ti (8 GB) via Ollama.
# Candidates (smallest first): qwen2.5:0.5b (~0.4 GB), llama3.2:1b (~1.3 GB).
# Pulls both, validates each actually generates, and records the review to
# /var/lib/compute-monster/model-review.txt (used by VERIFY).
set -uo pipefail
source "$HERE/config.env"
export DEBIAN_FRONTEND=noninteractive

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
  echo "--- pulling $m ---"
  ollama pull "$m" || { echo "$m: PULL FAILED" >> "$REVIEW"; return 1; }
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
test_model "qwen2.5:0.5b" && ok_smallest=0
test_model "llama3.2:1b"  && ok_small=0

{
  echo
  echo "GPU: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo unknown)"
  if [[ $ok_smallest -eq 0 ]]; then
    echo "SMALLEST-OK: qwen2.5:0.5b (~0.4 GB) — absolute floor, runs fine"
  fi
  if [[ $ok_small -eq 0 ]]; then
    echo "RECOMMENDED-SMALLEST-USEFUL: llama3.2:1b (~1.3 GB) — better quality, trivial fit in 8 GB"
  fi
} >> "$REVIEW"

cat "$REVIEW"
# Step passes if at least one model generates.
[[ $ok_smallest -eq 0 || $ok_small -eq 0 ]]
