#!/usr/bin/env bash
# compute-monster post-boot verification. Run: sudo bash VERIFY.sh
# Prints PASS/FAIL per component. Non-fatal (keeps going), exits 1 if any FAIL.
# Full context + fixes: VERIFY.md
fails=0
pass(){ printf "  \033[32mPASS\033[0m %s\n" "$1"; }
fail(){ printf "  \033[31mFAIL\033[0m %s\n" "$1"; fails=$((fails+1)); }
info(){ printf "  ---- %s\n" "$1"; }
hdr(){ printf "\n== %s ==\n" "$1"; }

hdr "0. first-boot provisioning"
if [ -f /var/lib/compute-monster/provisioned ] || [ -f /var/lib/compute-monster-provisioned ]; then
  pass "bootstrap completed"
else
  fail "bootstrap marker missing"
fi

hdr "1. identity / OS"
[ "$(hostnamectl --static)" = "compute-monster" ] && pass "hostname" || fail "hostname != compute-monster"
timedatectl show -p Timezone --value | grep -q "America/New_York" && pass "timezone Eastern" || fail "timezone"
id a_guy >/dev/null 2>&1 && pass "user a_guy" || fail "user a_guy missing"

hdr "2. NVIDIA / RTX 3060 Ti"
if command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
  pass "$(nvidia-smi -L | head -1)"
else fail "nvidia-smi not working (reboot once if freshly installed)"; fi

hdr "3. storage /data (Seagate)"
mountpoint -q /data && pass "/data mounted ($(df -h --output=size /data | tail -1 | xargs))" || fail "/data not mounted"
grep -q " /data " /etc/fstab && pass "/data in fstab" || fail "/data not persistent"

hdr "4. RGB red meteor"
systemctl is-active --quiet openrgb-server && pass "openrgb-server" || fail "openrgb-server down"
if systemctl is-active --quiet openrgb-meteor; then
  if journalctl -u openrgb-meteor --no-pager 2>/dev/null | grep -q "animating meteor"; then
    pass "meteor animating"
  else info "meteor service up but no device yet — run: /opt/openrgb-meteor/venv/bin/python /opt/openrgb-meteor/meteor.py --list"; fi
else fail "openrgb-meteor down"; fi

hdr "5. fan control"
command -v sensors >/dev/null && sensors 2>/dev/null | grep -qiE "fan|Tctl" && pass "sensors reporting" || info "run sensors-detect / check nct6775"

hdr "6. Wake-on-LAN"
NIC=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1)}')
if [ -n "$NIC" ] && command -v ethtool >/dev/null && ethtool "$NIC" 2>/dev/null | grep -qi "Wake-on: g"; then
  pass "WOL=g on $NIC (MAC $(cat /sys/class/net/$NIC/address))"
else fail "WOL not set to g (check BIOS Resume By PCI-E + ethtool)"; fi

hdr "7. LLM serving (ollama, smallest model)"
if systemctl is-active --quiet ollama && [ -s /var/lib/compute-monster/model-review.txt ]; then
  if grep -q "GENERATES" /var/lib/compute-monster/model-review.txt; then
    pass "$(grep -E 'SMALLEST-OK|RECOMMENDED' /var/lib/compute-monster/model-review.txt | head -1)"
  else
    fail "ollama up but no model generated output"
  fi
else
  fail "ollama not serving / model review missing"
fi

hdr "8. kubernetes prereqs"
[ -z "$(swapon --show)" ] && pass "swap off" || fail "swap still on"
systemctl is-active --quiet containerd && pass "containerd running" || fail "containerd down"
command -v kubeadm >/dev/null && pass "$(kubeadm version -o short 2>/dev/null)" || fail "kubeadm missing"
grep -rqs max-pods /etc/systemd/system/kubelet.service.d/ && pass "max-pods drop-in" || fail "max-pods drop-in missing"

hdr "SUMMARY"
if [ "$fails" -eq 0 ]; then
  printf "  \033[32mALL GREEN\033[0m — only 'kubeadm join' (manual, needs a cluster token) remains.\n"; exit 0
else
  printf "  \033[31m%d check(s) failed\033[0m — see VERIFY.md for fixes.\n" "$fails"; exit 1
fi
