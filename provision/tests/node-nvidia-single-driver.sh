#!/usr/bin/env bash
# Kanboard #1868 — live-node check: exactly ONE NVIDIA driver stack (the GPU Operator's) on alidzy.
# Run on the node:  sudo EXPECT_DRIVER=580.178.04 bash node-nvidia-single-driver.sh
# EXPECT_DRIVER must equal ClusterPolicy spec.driver.version (kubectl get clusterpolicy cluster-policy -o jsonpath='{.spec.driver.version}').
set -uo pipefail
fails=0
ok(){ printf '  PASS %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
EXPECT_DRIVER="${EXPECT_DRIVER:?set EXPECT_DRIVER to the ClusterPolicy driver version}"

mod="$(cat /sys/module/nvidia/version 2>/dev/null)"
[[ "$mod" == "$EXPECT_DRIVER" ]] && ok "loaded module $mod == ClusterPolicy $EXPECT_DRIVER" || bad "loaded module '$mod' != $EXPECT_DRIVER"

if out="$(chroot /run/nvidia/driver nvidia-smi -L 2>&1)" && grep -q "3060 Ti" <<<"$out"; then ok "operator-path nvidia-smi: $(head -1 <<<"$out" | cut -c1-48)"; else bad "operator-path nvidia-smi failed: $out"; fi

hostsmi="$(nvidia-smi -L 2>&1 || true)"
if grep -qi "mismatch" <<<"$hostsmi"; then bad "host nvidia-smi reports a driver/library mismatch"; else ok "host nvidia-smi has no mismatch error"; fi

left="$(dpkg -l 2>/dev/null | awk '/^ii/ && /nvidia/ && /595/ {print $2}' | tr '\n' ' ')"
[[ -z "$left" ]] && ok "no *nvidia*595* packages installed" || bad "leftover packages: $left"

[[ -f /etc/modprobe.d/blacklist-nouveau.conf ]] && ok "nouveau blacklist present" || bad "nouveau blacklist missing"
lsmod | grep -q '^nouveau' && bad "nouveau loaded" || ok "nouveau not loaded"

banner="$(/etc/update-motd.d/01-alidzy 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
grep -qE 'GPU [0-9]+°C' <<<"$banner" && ok "banner shows a numeric GPU temperature" || bad "banner GPU temp missing: $(grep -o 'GPU.*' <<<"$banner" | head -1)"

echo; [[ $fails -eq 0 ]] && echo "ALL PASS" || echo "$fails FAILED"
exit $((fails>0))
