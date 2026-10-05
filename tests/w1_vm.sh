#!/usr/bin/env bash
# W1 (+W3, W4 core): fresh Ubuntu 24.04 VM, real user flow (signed release -> root stage -> plan -> install ->
# status -> rerun -> undo), snapshots before/after. Logs: lab/work/ws-w1/. The VM is deleted at the end.
set -uo pipefail
VM=${TESTVM:?set TESTVM to your VM helper (see tests/README.md)}; OUT=${OUTDIR:-./results}/ws-w1; DIST=$(cd "$(dirname "$0")/.." && pwd)/dist; VER=$(python3 -c "import json;print(json.load(open('$(cd "$(dirname "$0")/.." && pwd)/src/release.json'))['aurum_ws'])")
mkdir -p "$OUT"; rm -f "$OUT"/*.txt
s() { "$VM" ssh "$1" > "$OUT/$2.txt" 2>&1; echo "== $2 exit $?" | tee -a "$OUT/summary.txt"; }
trap '"$VM" down >/dev/null 2>&1' EXIT
"$VM" up || exit 1
GUEST=$("$VM" ssh ". /etc/os-release; echo \$VERSION_ID" 2>/dev/null | tail -1); echo "guest Ubuntu $GUEST" >> "$OUT/summary.txt"
[ "$GUEST" = "24.04" ] || { echo "FAIL guest is $GUEST, expected 24.04" | tee -a "$OUT/summary.txt"; exit 1; }
"$VM" put "$DIST/aurum-ws-$VER.tar.gz" /home/learner/; "$VM" put "$DIST/SHA256SUMS" /home/learner/
SNAP='dpkg-query -W -f "\${Package} \${Version}\n" | sort; echo ---; systemctl list-unit-files --no-legend | sort; echo ---; ls -la /usr/local/bin /usr/local/sbin /usr/local/lib /etc/systemd/system; echo ---; getent passwd | cut -d: -f1 | sort; echo ---; cat /etc/default/apport 2>/dev/null; echo ---; sudo ss -tlnH | awk "{print \$4}" | sort'
s "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq minisign zstd curl >/dev/null && echo prereq-ok" prereq
s "$SNAP" snap-before
s "cd ~ && minisign -G -W -p test.pub -s test.key >/dev/null && minisign -S -s test.key -m SHA256SUMS >/dev/null && ls SHA256SUMS.minisig" sign
s "cd ~ && sudo install -d -m 0700 /var/lib/aurum-ws/incoming && sudo install -m 0600 aurum-ws-$VER.tar.gz SHA256SUMS SHA256SUMS.minisig /var/lib/aurum-ws/incoming/ && sudo sh -c 'cd /var/lib/aurum-ws/incoming && minisign -Vm SHA256SUMS -p /home/learner/test.pub && sha256sum -c SHA256SUMS && install -d -m 0755 /var/lib/aurum-ws/stage && tar -xzf aurum-ws-$VER.tar.gz -C /var/lib/aurum-ws/stage --no-same-owner'" stage
s "cd /home/learner && tar -xzf aurum-ws-$VER.tar.gz && aurum=/var/lib/aurum-ws/stage/aurum-ws-$VER/aurum-ws; echo '--- user-writable copy refused:'; sudo ./aurum-ws-$VER/aurum-ws plan 2>&1 | tail -1 || true; echo '--- staged plan:'; sudo \$aurum plan" plan
s "sudo /var/lib/aurum-ws/stage/aurum-ws-$VER/aurum-ws install --model qwen3:1.7b --privacy" install
s "sudo ss -tlnH | awk '{print \$4}' | sort; echo ---; curl -s --max-time 3 http://127.0.0.1:11434/api/version; echo; sudo aurum-ws status" after-install
s "sudo aurum-ws install --model qwen3:1.7b --privacy" rerun
s "sudo aurum-ws undo" undo
s "$SNAP" snap-after
s "ls -la /var/lib/aurum-ws/ /var/lib/ollama 2>&1; which ollama aurum-ws; systemctl is-active ollama 2>&1" leftovers
diff <(sed 1d "$OUT/snap-before.txt") <(sed 1d "$OUT/snap-after.txt") > "$OUT/snap-diff.txt"; echo "== snap-diff lines $(wc -l < "$OUT/snap-diff.txt")" | tee -a "$OUT/summary.txt"
# machine checks (W1/W3/W4)
chk() { if eval "$2"; then echo "PASS $1" | tee -a "$OUT/summary.txt"; else echo "FAIL $1" | tee -a "$OUT/summary.txt"; fi; }
chk "user-writable copy refused" "grep -q 'run the staged copy' '$OUT/plan.txt'"
chk "install completed" "grep -q 'Aurum Workstation .*: INSTALLED' '$OUT/install.txt'"
chk "test answer non-empty" "grep -qi \"test answer from .*: '[^']\\+'\" '$OUT/after-install.txt'"
NEW=$(comm -13 <(awk 'BEGIN{n=0} /^---$/{n++; next} n==5' "$OUT/snap-before.txt" | sort) <(sed -n '1,/^---$/p' "$OUT/after-install.txt" | grep -v '^---' | sort))
echo "$NEW" > "$OUT/new-listeners.txt"
chk "new listeners localhost only + 11434" "grep -qx '127.0.0.1:11434' '$OUT/new-listeners.txt' && ! grep -v -E '^(127\\.0\\.0\\.1|\\[::1\\]):[0-9]+\$' '$OUT/new-listeners.txt' | grep -q ."
chk "rerun adds no steps" "! grep -q 'adopt-ollama' '$OUT/rerun.txt'"
chk "undo complete" "grep -q 'Undo complete' '$OUT/undo.txt'"
chk "diff only allowlisted" "! grep '^[<>]' '$OUT/snap-diff.txt' | grep -v -E 'session-[0-9]+\\.scope|^[<>] drwx|^[<>] ollama\$' | grep -q ."
chk "no cache left" "! grep -qE ' cache(-[0-9a-f]+)?\$' '$OUT/leftovers.txt'"
