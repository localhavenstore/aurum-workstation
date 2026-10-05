#!/usr/bin/env bash
# W5 kill/resume + partial undo, W6 pre-existing resources, W12 failure injection, W13 lock, W14 root-login theme.
# Fresh Ubuntu 24.04 VM, real signed-release flow (test key). Logs + PASS/FAIL: lab/work/ws-w5/summary.txt.
set -uo pipefail
VM=${TESTVM:?set TESTVM to your VM helper (see tests/README.md)}; OUT=${OUTDIR:-./results}/ws-w5; DIST=$(cd "$(dirname "$0")/.." && pwd)/dist; VER=$(python3 -c "import json;print(json.load(open('$(cd "$(dirname "$0")/.." && pwd)/src/release.json'))['aurum_ws'])")
A=/var/lib/aurum-ws/stage/aurum-ws-$VER/aurum-ws
mkdir -p "$OUT"; rm -f "$OUT"/*.txt
s() { "$VM" ssh "$1" > "$OUT/$2.txt" 2>&1; echo "== $2 exit $?" >> "$OUT/summary.txt"; }
chk() { if eval "$2"; then echo "PASS $1" | tee -a "$OUT/summary.txt"; else echo "FAIL $1" | tee -a "$OUT/summary.txt"; fi; }
trap '"$VM" down >/dev/null 2>&1' EXIT
"$VM" up || exit 1
GUEST=$("$VM" ssh ". /etc/os-release; echo \$VERSION_ID" 2>/dev/null | tail -1); echo "guest Ubuntu $GUEST" >> "$OUT/summary.txt"
[ "$GUEST" = "24.04" ] || { echo "FAIL guest is $GUEST, expected 24.04" | tee -a "$OUT/summary.txt"; exit 1; }
"$VM" put "$DIST/aurum-ws-$VER.tar.gz" /home/learner/; "$VM" put "$DIST/SHA256SUMS" /home/learner/
STAGE="cd ~ && sudo rm -rf /var/lib/aurum-ws/stage && sudo install -d -m 0700 /var/lib/aurum-ws/incoming && sudo install -m 0600 aurum-ws-$VER.tar.gz SHA256SUMS SHA256SUMS.minisig /var/lib/aurum-ws/incoming/ && sudo sh -c 'cd /var/lib/aurum-ws/incoming && minisign -Vm SHA256SUMS -p /home/learner/test.pub && sha256sum -c SHA256SUMS && install -d -m 0755 /var/lib/aurum-ws/stage && tar -xzf aurum-ws-$VER.tar.gz -C /var/lib/aurum-ws/stage --no-same-owner'"
s "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq minisign zstd curl >/dev/null && cd ~ && minisign -G -W -p test.pub -s test.key >/dev/null && minisign -S -s test.key -m SHA256SUMS >/dev/null && echo ok" prep
s "$STAGE" stage

# W6a: port 11434 busy (no Ollama) -> stop, nothing created
s "sudo sh -c 'nohup python3 -m http.server 11434 --bind 127.0.0.1 >/dev/null 2>&1 &' ; sleep 1; sudo $A install --model qwen3:1.7b; echo; sudo ls /var/lib/aurum-ws; sudo pkill -f 'http.server 11434'" w6-port
chk "W6 port busy -> stop" "grep -q 'something else already listens' '$OUT/w6-port.txt' && ! grep -q 'ollama-files' '$OUT/w6-port.txt'"
s "sudo rm -f /var/lib/aurum-ws/manifest.json; echo cleaned" w6-clean

# W6b: an existing (fake, not answering) ollama binary -> adopt, never touched, stop because it does not answer
s "printf '#!/bin/sh\necho fake\n' | sudo tee /usr/local/bin/ollama >/dev/null && sudo chmod 755 /usr/local/bin/ollama && sha256sum /usr/local/bin/ollama && sudo $A install --model qwen3:1.7b; sha256sum /usr/local/bin/ollama; sudo $A undo; sha256sum /usr/local/bin/ollama; sudo rm -f /usr/local/bin/ollama" w6-binary
chk "W6 existing binary adopted + untouched (also by undo)" "grep -q 'EXISTING Ollama' '$OUT/w6-binary.txt' && [ \$(grep -c '/usr/local/bin/ollama\$' '$OUT/w6-binary.txt') -eq 3 ] && [ \$(grep '/usr/local/bin/ollama\$' '$OUT/w6-binary.txt' | awk '{print \$1}' | sort -u | wc -l) -eq 1 ]"
s "$STAGE" stage2

# W12: bad pinned checksum -> stop before anything is installed; undo works on the partial record
s "sudo python3 - <<'PY'
import json; p='/var/lib/aurum-ws/stage/aurum-ws-$VER/release.json'; d=json.load(open(p)); d['ollama']['sha256']='0'*64; open(p,'w').write(json.dumps(d))
PY
sudo $A install --model qwen3:1.7b; echo; ls /usr/local/lib; sudo $A undo" w12-badsha
chk "W12 bad checksum -> stop, nothing unpacked, undo ok" "grep -q 'does not match the pinned sha256' '$OUT/w12-badsha.txt' && ! grep -q 'ollama-0.35.1' <(sed -n '/^\$/,\$p' '$OUT/w12-badsha.txt' | head -5) && grep -q 'Undo complete' '$OUT/w12-badsha.txt'"
s "$STAGE" stage3

# W14: --theme from a root login (no SUDO_USER) -> refused
s "sudo -i env -u SUDO_USER $A plan --theme" w14
chk "W14 root login + --theme refused" "grep -q 'needs sudo from your own desktop user' '$OUT/w14.txt'"

# W5: kill -9 during the Ollama download, resume, then kill during the model pull, resume; status; undo
s "sudo sh -c '$A install --model qwen3:1.7b > /tmp/i1.log 2>&1 & echo \$! > /tmp/i1.pid'; sleep 8; sudo kill -9 \$(cat /tmp/i1.pid); sleep 1; sudo cat /tmp/i1.log; echo ---; sudo python3 -c \"import json;m=json.load(open('/var/lib/aurum-ws/manifest.json'));print([(s['id'],s['state']) for s in m['steps']])\"" w5-kill1
s "sudo $A install --model qwen3:1.7b" w5-resume1
chk "W5 resume after kill during download" "grep -q 'Aurum Workstation .*: INSTALLED' '$OUT/w5-resume1.txt' && grep -qi \"test answer from .*: '[^']\\+'\" '$OUT/w5-resume1.txt'"
# W13: two runs at once -> one waits/refuses
s "sudo sh -c '$A install --model qwen3:1.7b > /tmp/a.log 2>&1 & $A install --model qwen3:1.7b > /tmp/b.log 2>&1; wait'; cat /tmp/a.log /tmp/b.log" w13
chk "W13 second concurrent run refused (lock)" "grep -q 'another aurum-ws run is active' '$OUT/w13.txt'"
s "sudo aurum-ws undo --purge-models; ls /usr/local/lib /var/lib/aurum-ws; systemctl is-active ollama" w5-undo
chk "W5 undo after resumed install (purge)" "grep -q 'Undo complete' '$OUT/w5-undo.txt' && grep -q 'model-qwen3:1.7b: removed' '$OUT/w5-undo.txt'"
