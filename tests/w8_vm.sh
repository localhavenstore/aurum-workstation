#!/usr/bin/env bash
# W8 offline after install (persistent outbound drop, reboot, service + answer OK), W9 reboot after install and after
# undo, W10 hostile home path (spaces/quotes) for the invoking user. Fresh 24.04 VM. Results: lab/work/ws-w8/summary.txt
set -uo pipefail
VM=${TESTVM:?set TESTVM to your VM helper (see tests/README.md)}; OUT=${OUTDIR:-./results}/ws-w8; DIST=$(cd "$(dirname "$0")/.." && pwd)/dist; VER=$(python3 -c "import json;print(json.load(open('$(cd "$(dirname "$0")/.." && pwd)/src/release.json'))['aurum_ws'])")
A=/var/lib/aurum-ws/stage/aurum-ws-$VER/aurum-ws
mkdir -p "$OUT"; rm -f "$OUT"/*.txt
s() { "$VM" ssh "$1" > "$OUT/$2.txt" 2>&1; echo "== $2 exit $?" >> "$OUT/summary.txt"; }
chk() { if eval "$2"; then echo "PASS $1" | tee -a "$OUT/summary.txt"; else echo "FAIL $1" | tee -a "$OUT/summary.txt"; fi; }
reboot_vm() { "$VM" ssh "sudo systemctl reboot" >/dev/null 2>&1; sleep 15
  for _ in $(seq 1 60); do "$VM" ssh "true" >/dev/null 2>&1 && return 0; sleep 5; done; return 1; }
trap '"$VM" down >/dev/null 2>&1' EXIT
"$VM" up || exit 1
GUEST=$("$VM" ssh ". /etc/os-release; echo \$VERSION_ID" 2>/dev/null | tail -1); echo "guest Ubuntu $GUEST" >> "$OUT/summary.txt"
[ "$GUEST" = "24.04" ] || { echo "FAIL guest is $GUEST, expected 24.04" | tee -a "$OUT/summary.txt"; exit 1; }
"$VM" put "$DIST/aurum-ws-$VER.tar.gz" /home/learner/; "$VM" put "$DIST/SHA256SUMS" /home/learner/
s "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq minisign zstd curl >/dev/null && cd ~ && minisign -G -W -p test.pub -s test.key >/dev/null && minisign -S -s test.key -m SHA256SUMS >/dev/null && sudo install -d -m 0700 /var/lib/aurum-ws/incoming && sudo install -m 0600 aurum-ws-$VER.tar.gz SHA256SUMS SHA256SUMS.minisig /var/lib/aurum-ws/incoming/ && sudo sh -c 'cd /var/lib/aurum-ws/incoming && minisign -Vm SHA256SUMS -p /home/learner/test.pub && sha256sum -c SHA256SUMS && install -d -m 0755 /var/lib/aurum-ws/stage && tar -xzf aurum-ws-$VER.tar.gz -C /var/lib/aurum-ws/stage --no-same-owner' && echo staged" prep
# W10: an invoking user whose home has spaces and a quote (privacy step runs ubuntu-report for that user if present)
s "sudo useradd -m -d \"/home/o'brien x\" -s /bin/bash obrien && echo 'obrien ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/obrien >/dev/null && sudo -u obrien -H sudo $A install --model qwen3:1.7b --privacy" w10-install
chk "W10 install as a user with a hostile home path" "grep -q 'Aurum Workstation .*: INSTALLED' '$OUT/w10-install.txt' && grep -qi \"test answer from .*: '[^']\\+'\" '$OUT/w10-install.txt'"
# W8: no internet at all (default routes removed at every boot BEFORE ollama starts; ssh via the local subnet still works)
s "printf '[Unit]\nBefore=ollama.service\nAfter=network-online.target\nWants=network-online.target\n[Service]\nType=oneshot\nExecStart=-/usr/sbin/ip route del default\nExecStart=-/usr/sbin/ip -6 route del default\n[Install]\nWantedBy=multi-user.target\n' | sudo tee /etc/systemd/system/testblock.service >/dev/null && sudo systemctl enable --now testblock.service >/dev/null 2>&1; (curl -s --max-time 5 https://github.com >/dev/null && echo NET-STILL-UP || echo net-blocked)" w8-block
chk "W8 internet blocked" "grep -q net-blocked '$OUT/w8-block.txt'"
reboot_vm || echo "FAIL reboot 1" >> "$OUT/summary.txt"
s "systemctl is-active ollama; (curl -s --max-time 5 https://github.com >/dev/null && echo NET-STILL-UP || echo net-blocked); sudo aurum-ws status" w8-after-reboot
chk "W8+W9 after reboot, offline: service active + real answer" "grep -qx active '$OUT/w8-after-reboot.txt' && grep -q net-blocked '$OUT/w8-after-reboot.txt' && grep -qi \"test answer from .*: '[^']\\+'\" '$OUT/w8-after-reboot.txt'"
s "sudo systemctl disable testblock.service >/dev/null 2>&1; sudo rm -f /etc/systemd/system/testblock.service; sudo aurum-ws undo" w9-undo
chk "W9 undo" "grep -q 'Undo complete' '$OUT/w9-undo.txt'"
reboot_vm || echo "FAIL reboot 2" >> "$OUT/summary.txt"
s "systemctl is-system-running; systemctl is-active ollama; ls /etc/systemd/system/ollama.service 2>&1; which aurum-ws ollama; true" w9-after-reboot
chk "W9 clean boot after undo (no failed units, no ollama service)" "grep -qE '^(running|degraded)' '$OUT/w9-after-reboot.txt' && ! grep -qx active '$OUT/w9-after-reboot.txt' && grep -q 'No such file' '$OUT/w9-after-reboot.txt'"
