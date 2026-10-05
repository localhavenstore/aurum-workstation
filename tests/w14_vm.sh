#!/usr/bin/env bash
# W14 (1.0.1): the DEFAULT model path (no --model; 8 GB VM -> qwen3:4b-instruct) gives a clean test answer (no thinking
# text), and a record from another Aurum version is refused by install AND undo with nothing changed.
set -uo pipefail
VM=${TESTVM:?set TESTVM to your VM helper (see tests/README.md)}; OUT=${OUTDIR:-./results}/ws-w14; DIST=$(cd "$(dirname "$0")/.." && pwd)/dist
VER=$(python3 -c "import json;print(json.load(open('$(cd "$(dirname "$0")/.." && pwd)/src/release.json'))['aurum_ws'])")
mkdir -p "$OUT"; rm -f "$OUT"/*.txt
s() { "$VM" ssh "$1" > "$OUT/$2.txt" 2>&1; echo "== $2 exit $?" | tee -a "$OUT/summary.txt"; }
trap '"$VM" down >/dev/null 2>&1' EXIT
"$VM" up || exit 1
"$VM" put "$DIST/aurum-ws-$VER.tar.gz" /home/learner/; "$VM" put "$DIST/SHA256SUMS" /home/learner/
A=/var/lib/aurum-ws/stage/aurum-ws-$VER/aurum-ws
s "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq minisign zstd curl >/dev/null && echo prereq-ok" prereq
s "cd ~ && minisign -G -W -p test.pub -s test.key >/dev/null && minisign -S -s test.key -m SHA256SUMS >/dev/null && sudo install -d -m 0700 /var/lib/aurum-ws/incoming && sudo install -m 0600 aurum-ws-$VER.tar.gz SHA256SUMS SHA256SUMS.minisig /var/lib/aurum-ws/incoming/ && sudo sh -c 'cd /var/lib/aurum-ws/incoming && minisign -Vm SHA256SUMS -p /home/learner/test.pub && sha256sum -c SHA256SUMS && install -d -m 0755 /var/lib/aurum-ws/stage && tar -xzf aurum-ws-$VER.tar.gz -C /var/lib/aurum-ws/stage --no-same-owner'" stage
s "free -g | awk '/Mem:/{print \"ram\", \$2}'; sudo $A plan | grep -i model" plan
s "sudo $A install" install
s "ollama run qwen3:4b-instruct --think=false 'In one short sentence: why run AI on your own computer?' 2>&1 | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g'" ask
s "sudo python3 -c 'import json;p=\"/var/lib/aurum-ws/manifest.json\";m=json.load(open(p));m[\"version\"]=\"1.0.0-preview\";json.dump(m,open(p,\"w\"))' && sudo sha256sum /var/lib/aurum-ws/manifest.json; sudo $A install; echo rc=\$?; sudo $A undo; echo rc=\$?; sudo sha256sum /var/lib/aurum-ws/manifest.json; systemctl is-active ollama" guard
s "sudo python3 -c 'import json;p=\"/var/lib/aurum-ws/manifest.json\";m=json.load(open(p));m[\"version\"]=\"$VER\";json.dump(m,open(p,\"w\"))' && sudo aurum-ws undo --purge-models" undo
s "which ollama aurum-ws; systemctl is-active ollama; true" gone
chk() { if eval "$2"; then echo "PASS $1" | tee -a "$OUT/summary.txt"; else echo "FAIL $1" | tee -a "$OUT/summary.txt"; fi; }
chk "default model is qwen3:4b-instruct" "grep -q 'model qwen3:4b-instruct' '$OUT/plan.txt'"
chk "install completed" "grep -q 'Aurum Workstation $VER: INSTALLED' '$OUT/install.txt'"
chk "test answer has no thinking text" "grep -q \"OK - test answer from qwen3:4b-instruct: '\" '$OUT/install.txt' && ! grep -qiE \"test answer.*(<think>|'hmm|the user)\" '$OUT/install.txt'"
chk "plain ollama run answers without a think block" "! grep -q '</think>' '$OUT/ask.txt' && [ \$(wc -w < '$OUT/ask.txt') -lt 60 ]"
chk "other-version record refused by install + undo, unchanged, Ollama still running" "[ \$(grep -c 'set up by Aurum Workstation 1.0.0-preview' '$OUT/guard.txt') = 2 ] && [ \$(grep -c '^rc=1' '$OUT/guard.txt') = 2 ] && [ \$(grep -oE '^[0-9a-f]{64}' '$OUT/guard.txt' | sort -u | wc -l) = 1 ] && tail -1 '$OUT/guard.txt' | grep -qx active"
chk "undo complete" "grep -q 'Undo complete' '$OUT/undo.txt'"
