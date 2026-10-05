#!/usr/bin/env bash
# B12 depth (code review r1): kill -9 during the model pull + resume, SIGINT during the download + resume, full disk
# (stop before any download) + resume, foreign/masked ollama.service (stop, untouched), undo failure -> UNDO_FAILED ->
# finish via the documented stage path (W15). Fresh 24.04 VM. Results: lab/work/ws-w12/summary.txt
set -uo pipefail
VM=${TESTVM:?set TESTVM to your VM helper (see tests/README.md)}; OUT=${OUTDIR:-./results}/ws-w12; DIST=$(cd "$(dirname "$0")/.." && pwd)/dist; VER=$(python3 -c "import json;print(json.load(open('$(cd "$(dirname "$0")/.." && pwd)/src/release.json'))['aurum_ws'])")
A=/var/lib/aurum-ws/stage/aurum-ws-$VER/aurum-ws
mkdir -p "$OUT"; rm -f "$OUT"/*.txt
s() { "$VM" ssh "$1" > "$OUT/$2.txt" 2>&1; echo "== $2 exit $?" >> "$OUT/summary.txt"; }
chk() { if eval "$2"; then echo "PASS $1" | tee -a "$OUT/summary.txt"; else echo "FAIL $1" | tee -a "$OUT/summary.txt"; fi; }
MAN="sudo python3 -c \"import json;m=json.load(open('/var/lib/aurum-ws/manifest.json'));print(m['state'],[(s['id'],s['state']) for s in m['steps']])\""
trap '"$VM" down >/dev/null 2>&1' EXIT
"$VM" up || exit 1
GUEST=$("$VM" ssh ". /etc/os-release; echo \$VERSION_ID" 2>/dev/null | tail -1); echo "guest Ubuntu $GUEST" >> "$OUT/summary.txt"
[ "$GUEST" = "24.04" ] || { echo "FAIL guest is $GUEST" | tee -a "$OUT/summary.txt"; exit 1; }
"$VM" put "$DIST/aurum-ws-$VER.tar.gz" /home/learner/; "$VM" put "$DIST/SHA256SUMS" /home/learner/
STAGE="cd ~ && sudo rm -rf /var/lib/aurum-ws/stage && sudo install -d -m 0700 /var/lib/aurum-ws/incoming && sudo install -m 0600 aurum-ws-$VER.tar.gz SHA256SUMS SHA256SUMS.minisig /var/lib/aurum-ws/incoming/ && sudo sh -c 'cd /var/lib/aurum-ws/incoming && minisign -Vm SHA256SUMS -p /home/learner/test.pub && sha256sum -c SHA256SUMS && install -d -m 0755 /var/lib/aurum-ws/stage && tar -xzf aurum-ws-$VER.tar.gz -C /var/lib/aurum-ws/stage --no-same-owner'"
s "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq minisign zstd curl >/dev/null && cd ~ && minisign -G -W -p test.pub -s test.key >/dev/null && minisign -S -s test.key -m SHA256SUMS >/dev/null && echo ok" prep
s "$STAGE" stage

# masked ollama.service (a foreign unit) -> stop, mask untouched
s "sudo systemctl mask ollama.service; sudo $A install --model qwen3:1.7b; readlink /etc/systemd/system/ollama.service; sudo systemctl unmask ollama.service; sudo rm -f /var/lib/aurum-ws/manifest.json" masked
chk "foreign/masked ollama.service -> stop, untouched" "grep -q STOPPED '$OUT/masked.txt' && grep -qx /dev/null '$OUT/masked.txt'"

# full disk: fill the root fs to < 2 GB free -> stop before any download; free it -> resume
s "sudo fallocate -l \$(( \$(df --output=avail -B1 / | tail -1) - 1500000000 )) /fill.img; df -h / | tail -1; sudo $A install --model qwen3:1.7b; ls /usr/local/lib; sudo rm -f /fill.img; $MAN" fulldisk
chk "full disk -> stop before downloading (nothing unpacked)" "grep -q 'not enough free disk space' '$OUT/fulldisk.txt' && ! grep -qx 'ollama-0.35.1' '$OUT/fulldisk.txt'"

# SIGINT during the download -> rerun completes
# a background job of a non-interactive sh inherits SIGINT=ignored; the helper restores the terminal default (= real Ctrl+C)
s "printf 'import os, signal, sys\\nsignal.signal(signal.SIGINT, signal.SIG_DFL)\\nos.execv(sys.argv[1], sys.argv[1:])\\n' | sudo tee /usr/local/bin/sigdfl.py >/dev/null; cat /usr/local/bin/sigdfl.py" helper
s "sudo sh -c '/usr/bin/python3 /usr/local/bin/sigdfl.py $A install --model qwen3:1.7b > /tmp/i.log 2>&1 & echo \$! > /tmp/i.pid'; sleep 6; sudo kill -INT \$(cat /tmp/i.pid); sleep 3; pgrep -x curl >/dev/null && echo CURL-STILL-RUNNING || echo no-curl-left; pgrep -f 'python3 -B /var/lib/aurum-ws/stage/[a]urum-ws' >/dev/null && echo INSTALLER-STILL-RUNNING || echo no-installer-left; $MAN" sigint
chk "SIGINT during download -> installer stops, no curl left behind" "grep -qx no-curl-left '$OUT/sigint.txt' && grep -qx no-installer-left '$OUT/sigint.txt'"

# kill -9 during the model pull -> resume
s "sudo sh -c '$A install --model qwen3:1.7b > /tmp/j.log 2>&1 & echo \$! > /tmp/j.pid'; for i in \$(seq 1 300); do sudo grep -q '\"id\": \"model-qwen3:1.7b\"' /var/lib/aurum-ws/manifest.json 2>/dev/null && break; sleep 2; done; sleep 3; sudo kill -9 \$(cat /tmp/j.pid); sleep 1; $MAN" kill-pull
chk "kill -9 landed during the model pull" "grep -q \"('model-qwen3:1.7b', 'INTENT')\" '$OUT/kill-pull.txt'"
s "sudo $A install --model qwen3:1.7b" resume
chk "resume after kill during the pull -> installed + real answer" "grep -q 'Aurum Workstation .*: INSTALLED\$' '$OUT/resume.txt' && grep -qi \"test answer from .*: '[^']\\+'\" '$OUT/resume.txt'"

# undo failure (immutable file in the Ollama dir) -> UNDO_FAILED, then finish via the documented stage path (W15)
s "sudo chattr +i /usr/local/lib/ollama-0.35.1/bin/ollama; sudo aurum-ws undo --force; $MAN; sudo chattr -i /usr/local/lib/ollama-0.35.1/bin/ollama; sudo $A undo --force; ls /var/lib/aurum-ws /usr/local/lib; which aurum-ws || echo no-cli" undo-fail
chk "undo failure reported + finished via the stage path" "grep -q 'UNDO_FAILED' '$OUT/undo-fail.txt' && grep -q 'Undo complete' '$OUT/undo-fail.txt' && grep -q no-cli '$OUT/undo-fail.txt' && ! grep -q 'ollama-0.35.1' <(tail -4 '$OUT/undo-fail.txt')"
