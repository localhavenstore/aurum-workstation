#!/usr/bin/env bash
# B12 (code reviews r2+r3), fresh 24.04 VM (+ popularity-contest + ubuntu-report installed so the privacy steps are real).
# Results: lab/work/ws-w13[-PART]/summary.txt. W13_PART=inject runs only the injected-failure part.
#  - refusals: non-root; an admin file in the old shared cache path and a hostile link next to the unpack folder stay untouched
#  - KILL MATRIX via the test-build-only AURUM_TEST_KILL_AT hook, every install step x {intent, done}:
#    (a) undo on that partial record -> clean; (b) install again -> INSTALLED + real answer
#  - adopted-Ollama path: kill at adopt-ollama / its model step, undo -> the existing Ollama is untouched
#  - undo finalisation: kill after cli-link / leftovers / archive -> undo again from the stage path -> complete
#  - injected: no network for the Ollama download, model download failure, foreign HTTP server on 11434, model digest
#    mismatch, undeletable stage
set -uo pipefail
VM=${TESTVM:?set TESTVM to your VM helper (see tests/README.md)}; OUT=${OUTDIR:-./results}/ws-w13${W13_PART:+-$W13_PART}; DIST=$(cd "$(dirname "$0")/.." && pwd)/dist; VER=$(python3 -c "import json;print(json.load(open('$(cd "$(dirname "$0")/.." && pwd)/src/release.json'))['aurum_ws'])")
REL=$(cd "$(dirname "$0")/.." && pwd)/src/release.json
OV=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['ollama']['version'])" $REL)
OURL=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['ollama']['url'])" $REL)
OSHA=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['ollama']['sha256'])" $REL)
D=/var/lib/aurum-ws/stage/aurum-ws-$VER; A=$D/aurum-ws
mkdir -p "${OUT:?}"; rm -f "${OUT:?}"/*.txt
echo "tested tarball: $(cut -d' ' -f1 "$DIST/SHA256SUMS")" >> "$OUT/summary.txt"
s() { "$VM" ssh "$1" > "$OUT/$2.txt" 2>&1; echo "== $2 exit $?" >> "$OUT/summary.txt"; }
chk() { if eval "$2"; then echo "PASS $1" | tee -a "$OUT/summary.txt"; else echo "FAIL $1" | tee -a "$OUT/summary.txt"; fi; }
MAN="sudo python3 -c \"import json;m=json.load(open('/var/lib/aurum-ws/manifest.json'));print(m['state'],[(s['id'],s['state']) for s in m['steps']])\" 2>/dev/null || echo no-record"
CLEAN="test ! -e /usr/local/lib/ollama-$OV && test ! -e /etc/systemd/system/ollama.service && test ! -L /usr/local/bin/ollama && test ! -L /usr/local/sbin/aurum-ws && test -z \"\$(ls -d /usr/local/lib/.ollama-$OV.partial[0-9]* 2>/dev/null | grep -v 'partial99[89]')\" && test -z \"\$(ls -d /var/lib/aurum-ws/cache-* 2>/dev/null)\" && ! systemctl is-active -q ollama && test ! -e /var/lib/aurum-ws/manifest.json && echo SYSTEM-CLEAN || echo SYSTEM-NOT-CLEAN"
STAGE="cd ~ && sudo rm -rf /var/lib/aurum-ws/stage && sudo install -d -m 0700 /var/lib/aurum-ws/incoming && sudo install -m 0600 aurum-ws-$VER.tar.gz SHA256SUMS SHA256SUMS.minisig /var/lib/aurum-ws/incoming/ && sudo sh -c 'cd /var/lib/aurum-ws/incoming && minisign -Vm SHA256SUMS -p /home/learner/test.pub >/dev/null && sha256sum -c SHA256SUMS >/dev/null && install -d -m 0755 /var/lib/aurum-ws/stage && tar -xzf aurum-ws-$VER.tar.gz -C /var/lib/aurum-ws/stage --no-same-owner' && echo staged"
TSTAGE="$STAGE && sudo touch $D/.aurum-test-build"          # test build: kill + seed hooks only
I="sudo AURUM_TEST_SEED=/root/ollama.tar.zst"                 # seed the per-install download folder (test build only)
FRESH="sudo systemctl disable --now ollama.service >/dev/null 2>&1; sudo rm -f /etc/systemd/system/ollama.service /usr/local/bin/ollama /usr/local/sbin/aurum-ws; sudo systemctl daemon-reload; sudo rm -rf /usr/local/lib/ollama-$OV /var/lib/aurum-ws/cache-* /var/lib/ollama; sudo userdel ollama 2>/dev/null; sudo rm -f /var/lib/aurum-ws/manifest.json"
KEEP="sudo rm -f /var/lib/aurum-ws/manifest.json"
NOMODEL="test -z \"\$(sudo find /var/lib/ollama/models -path '*manifests*' -type f 2>/dev/null)\" && echo NO-MODEL-LEFT || echo MODEL-LEFT"            # keeps the account + model between resume rounds
ANSWER="grep -qi \"test answer from .*: '[^']\\+'\""
trap '"$VM" down >/dev/null 2>&1' EXIT
"$VM" up || exit 1
GUEST=$("$VM" ssh ". /etc/os-release; echo \$VERSION_ID" 2>/dev/null | tail -1); echo "guest Ubuntu $GUEST" >> "$OUT/summary.txt"
[ "$GUEST" = "24.04" ] || { echo "FAIL guest is $GUEST" | tee -a "$OUT/summary.txt"; exit 1; }
"$VM" put "$DIST/aurum-ws-$VER.tar.gz" /home/learner/; "$VM" put "$DIST/SHA256SUMS" /home/learner/
s "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq minisign zstd curl popularity-contest ubuntu-report >/dev/null && cd ~ && minisign -G -W -p test.pub -s test.key >/dev/null && minisign -S -s test.key -m SHA256SUMS >/dev/null && sudo curl -fsSL -o /root/ollama.tar.zst '$OURL' && echo '$OSHA  /root/ollama.tar.zst' | sudo sha256sum -c && which ubuntu-report && ls /etc/popularity-contest.conf" prep
chk "prep: privacy tools present (privacy steps are real)" "grep -q ubuntu-report '$OUT/prep.txt' && grep -q popularity-contest.conf '$OUT/prep.txt'"

if [ "${W13_PART:-all}" != inject ]; then
# --- refusals + foreign things ---
s "$STAGE; $A plan" nonroot
chk "non-root run refused" "grep -q 'run with sudo' '$OUT/nonroot.txt'"
s "sudo install -d -m 0700 /var/lib/aurum-ws/cache && echo admin | sudo tee /var/lib/aurum-ws/cache/.download.notes >/dev/null && sudo mkdir -p /usr/local/lib/.ollama-$OV.partial999/keep && echo mine | sudo tee /usr/local/lib/.ollama-$OV.partial999/keep/f >/dev/null && sudo ln -sfn /etc /usr/local/lib/.ollama-$OV.partial998 && echo planted" plant
for step in ollama-files ollama-link ollama-user models-dir ollama-unit model-qwen3:1.7b cli-link privacy-apport privacy-popcon privacy-ubuntu-report; do for pt in intent "done"; do
  s "$FRESH; $TSTAGE; $I AURUM_TEST_KILL_AT=$step:$pt $A install --model qwen3:1.7b --privacy >/dev/null 2>&1; echo \"install-exit \$?\"; $MAN; sudo $A undo --purge-models; $CLEAN" "undo-$step-$pt"
  chk "kill at $step:$pt -> undo on the partial record -> clean" "grep -qx 'install-exit 137' '$OUT/undo-$step-$pt.txt' && grep -q 'Undo complete' '$OUT/undo-$step-$pt.txt' && grep -qx SYSTEM-CLEAN '$OUT/undo-$step-$pt.txt'"
done; done
for step in model-qwen3:1.7b models-dir ollama-user ollama-files ollama-link ollama-unit cli-link privacy-apport privacy-popcon privacy-ubuntu-report; do for pt in intent "done"; do
  F=$KEEP; case $step in model-*|models-dir|ollama-user) F=$FRESH;; esac
  s "$F; $TSTAGE; $I AURUM_TEST_KILL_AT=$step:$pt $A install --model qwen3:1.7b --privacy >/dev/null 2>&1; echo \"install-exit \$?\"; $I $A install --model qwen3:1.7b --privacy; sudo $A undo | tail -1" "resume-$step-$pt"
  chk "kill at $step:$pt -> install again -> INSTALLED + real answer" "grep -qx 'install-exit 137' '$OUT/resume-$step-$pt.txt' && grep -q 'Aurum Workstation .*: INSTALLED\$' '$OUT/resume-$step-$pt.txt' && $ANSWER '$OUT/resume-$step-$pt.txt'"
done; done
# undo finalisation: kill after each final step, then undo again from the stage path
for pt in cli-link leftovers archived; do
  s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo AURUM_TEST_KILL_AT=undo:$pt $A undo --purge-models >/dev/null 2>&1; echo \"undo-exit \$?\"; sudo $A undo --purge-models; ls /var/lib/aurum-ws; $CLEAN" "final-$pt"
  chk "undo killed after $pt -> undo again -> complete + clean, stage removed" "grep -qx 'undo-exit 137' '$OUT/final-$pt.txt' && grep -q 'Undo complete' '$OUT/final-$pt.txt' && ! grep -qx stage '$OUT/final-$pt.txt' && grep -qx SYSTEM-CLEAN '$OUT/final-$pt.txt'"
done
# adopted Ollama (a real one, installed by the 'user', not by Aurum): kill at its steps, undo -> untouched
ADOPT="sudo mkdir -p /opt/own-ollama && sudo tar --zstd -xf /root/ollama.tar.zst -C /opt/own-ollama && sudo ln -sfn /opt/own-ollama/bin/ollama /usr/local/bin/ollama && sudo sh -c 'nohup /usr/local/bin/ollama serve >/tmp/own.log 2>&1 & echo \$! > /tmp/own.pid' && sleep 4"
for kp in adopt-ollama:intent model-qwen3:1.7b:intent; do
  s "$FRESH; $TSTAGE; $ADOPT; H1=\$(sha256sum /opt/own-ollama/bin/ollama); $I AURUM_TEST_KILL_AT=$kp $A install --model qwen3:1.7b >/dev/null 2>&1; echo \"install-exit \$?\"; sudo $A undo --purge-models; H2=\$(sha256sum /opt/own-ollama/bin/ollama); [ \"\$H1\" = \"\$H2\" ] && readlink /usr/local/bin/ollama && curl -s 127.0.0.1:11434/api/version && echo && echo OWN-UNTOUCHED; sudo kill \$(cat /tmp/own.pid); sudo rm -f /usr/local/bin/ollama; sudo rm -rf /opt/own-ollama" "adopt-${kp%%:*}"
  chk "existing Ollama, kill at $kp, undo -> your Ollama untouched + still running" "grep -qx 'install-exit 137' '$OUT/adopt-${kp%%:*}.txt' && grep -q 'Undo complete' '$OUT/adopt-${kp%%:*}.txt' && grep -qx OWN-UNTOUCHED '$OUT/adopt-${kp%%:*}.txt'"
done
s "$FRESH; ls -la /var/lib/aurum-ws/cache/.download.notes; cat /usr/local/lib/.ollama-$OV.partial999/keep/f; readlink /usr/local/lib/.ollama-$OV.partial998" foreign
chk "admin file in old cache path + foreign partial dir + hostile link all untouched" "grep -q '.download.notes' '$OUT/foreign.txt' && grep -qx mine '$OUT/foreign.txt' && grep -qx /etc '$OUT/foreign.txt'"
fi

# --- review r4: changed service, earlier ubuntu-report answer, changed apport file ---
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo mkdir -p /etc/systemd/system/ollama.service.d && printf '[Service]\nEnvironment=OLLAMA_KEEP_ALIVE=10m\n' | sudo tee /etc/systemd/system/ollama.service.d/mine.conf >/dev/null && sudo systemctl daemon-reload; sudo aurum-ws undo; echo \"undo-exit \$?\"; test -x /usr/local/bin/ollama && systemctl is-active ollama && echo STILL-WORKING; sudo rm -rf /etc/systemd/system/ollama.service.d; sudo systemctl daemon-reload; sudo aurum-ws undo --purge-models; $CLEAN; $NOMODEL" dropin
chk "service with your own settings -> undo stops there, Ollama keeps working; remove them -> undo --purge-models completes AND removes the model" "grep -q 'undo stops here' '$OUT/dropin.txt' && grep -qx 'undo-exit 1' '$OUT/dropin.txt' && grep -qx STILL-WORKING '$OUT/dropin.txt' && grep -q 'Undo complete' '$OUT/dropin.txt' && grep -qx SYSTEM-CLEAN '$OUT/dropin.txt' && grep -qx NO-MODEL-LEFT '$OUT/dropin.txt'"
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo ln -sfn ../lib/ollama-$OV/bin/ollama /usr/local/bin/ollama; sudo aurum-ws undo; echo \"undo-exit \$?\"; /usr/local/bin/ollama --version >/dev/null 2>&1 && echo CMD-WORKS; sudo ln -sfn /usr/local/lib/ollama-$OV/bin/ollama /usr/local/bin/ollama; sudo aurum-ws undo --purge-models; $CLEAN; $NOMODEL" own-link
chk "your own ollama command link into Aurum's files -> undo stops, command keeps working; put back -> undo completes" "grep -q 'undo stops here' '$OUT/own-link.txt' && grep -qx 'undo-exit 1' '$OUT/own-link.txt' && grep -qx CMD-WORKS '$OUT/own-link.txt' && grep -q 'Undo complete' '$OUT/own-link.txt' && grep -qx SYSTEM-CLEAN '$OUT/own-link.txt' && grep -qx NO-MODEL-LEFT '$OUT/own-link.txt'"
s "$FRESH; $TSTAGE; rm -rf ~/.cache/ubuntu-report; $I AURUM_TEST_KILL_AT=privacy-ubuntu-report:intent $A install --model qwen3:1.7b --privacy >/dev/null 2>&1; mkdir -p ~/.cache/ubuntu-report && printf '{\"mine\": 1}' > ~/.cache/ubuntu-report/ubuntu.24.04; sudo $A undo --purge-models; cat ~/.cache/ubuntu-report/ubuntu.24.04; echo; rm -rf ~/.cache/ubuntu-report; $CLEAN" ureport-later
chk "interrupted ubuntu-report step + a report file made later -> undo keeps it (not provably Aurum's)" "grep -q '{\"mine\": 1}' '$OUT/ureport-later.txt' && grep -q 'kept (Aurum cannot prove' '$OUT/ureport-later.txt' && grep -q 'Undo complete' '$OUT/ureport-later.txt' && grep -qx SYSTEM-CLEAN '$OUT/ureport-later.txt'"
for kp in none privacy-ubuntu-report:done; do
  s "$FRESH; $TSTAGE; mkdir -p ~/.cache/ubuntu-report && printf '{\"my\": \"earlier answer\"}' > ~/.cache/ubuntu-report/ubuntu.24.04 && B=\$(sha256sum ~/.cache/ubuntu-report/ubuntu.24.04 | cut -d' ' -f1); $I AURUM_TEST_KILL_AT=$kp $A install --model qwen3:1.7b --privacy >/dev/null 2>&1; echo \"after-install \$(sha256sum ~/.cache/ubuntu-report/ubuntu.24.04 | cut -d' ' -f1)\"; sudo $A undo --purge-models; A2=\$(sha256sum ~/.cache/ubuntu-report/ubuntu.24.04 | cut -d' ' -f1); [ \"\$B\" = \"\$A2\" ] && echo ANSWER-RESTORED; ls ~/.cache/ubuntu-report; rm -rf ~/.cache/ubuntu-report; $CLEAN" "ureport-${kp%%:*}"
  if [ "$kp" = none ]; then
    chk "earlier ubuntu-report answer -> undo puts it back exactly" "grep -qx ANSWER-RESTORED '$OUT/ureport-${kp%%:*}.txt' && grep -q 'Undo complete' '$OUT/ureport-${kp%%:*}.txt' && grep -qx SYSTEM-CLEAN '$OUT/ureport-${kp%%:*}.txt'"
  else
    chk "earlier ubuntu-report answer, kill at $kp -> current kept, earlier answer saved next to it (nothing lost)" "grep -qx 'ubuntu.24.04.before-aurum' '$OUT/ureport-${kp%%:*}.txt' && grep -q 'your earlier answer' '$OUT/ureport-${kp%%:*}.txt' && grep -q 'Undo complete' '$OUT/ureport-${kp%%:*}.txt' && grep -qx SYSTEM-CLEAN '$OUT/ureport-${kp%%:*}.txt'"
  fi
done
s "$FRESH; $TSTAGE; E0=\$(systemctl is-enabled apport); A0=\$(systemctl is-active apport); echo \"before \$E0 \$A0\"; $I $A install --model qwen3:1.7b --privacy >/dev/null; echo '# my note' | sudo tee -a /etc/default/apport >/dev/null; sudo $A undo --purge-models; echo \"after \$(systemctl is-enabled apport) \$(systemctl is-active apport)\"; grep -c 'my note' /etc/default/apport; $CLEAN" apport-edited
chk "apport file edited after install -> file kept, service state restored" "[ \"\$(grep '^before' '$OUT/apport-edited.txt' | cut -d' ' -f2-)\" = \"\$(grep '^after' '$OUT/apport-edited.txt' | cut -d' ' -f2-)\" ] && grep -q 'file kept' '$OUT/apport-edited.txt' && grep -qx 1 '$OUT/apport-edited.txt' && grep -qx SYSTEM-CLEAN '$OUT/apport-edited.txt'"

# --- review r6: replaced unit (symlink), changed aurum-ws link, purge must not touch another Ollama, own opt-out kept ---
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo cp /etc/systemd/system/ollama.service /root/my-ollama.service && sudo ln -sfn /root/my-ollama.service /etc/systemd/system/ollama.service; sudo aurum-ws undo; echo \"undo-exit \$?\"; readlink /etc/systemd/system/ollama.service; sudo rm -f /etc/systemd/system/ollama.service && sudo cp /root/my-ollama.service /etc/systemd/system/ollama.service; sudo aurum-ws undo --purge-models; $CLEAN" unit-link
chk "unit replaced by a link -> undo stops, link untouched; put back -> undo completes" "grep -qx 'undo-exit 1' '$OUT/unit-link.txt' && grep -q 'was replaced' '$OUT/unit-link.txt' && grep -qx /root/my-ollama.service '$OUT/unit-link.txt' && grep -q 'Undo complete' '$OUT/unit-link.txt' && grep -qx SYSTEM-CLEAN '$OUT/unit-link.txt'"
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo ln -sfn ../../../var/lib/aurum-ws/stage/aurum-ws-$VER/aurum-ws /usr/local/sbin/aurum-ws; sudo $A undo --purge-models; echo \"undo-exit \$?\"; test -e $A && echo STAGE-KEPT; sudo ln -sfn $A /usr/local/sbin/aurum-ws; sudo $A undo --purge-models; $CLEAN" cli-link-changed
chk "changed aurum-ws link into the stage -> undo stops, stage kept; put back -> undo completes" "grep -qx 'undo-exit 1' '$OUT/cli-link-changed.txt' && grep -qx STAGE-KEPT '$OUT/cli-link-changed.txt' && grep -q 'Undo complete' '$OUT/cli-link-changed.txt' && grep -qx SYSTEM-CLEAN '$OUT/cli-link-changed.txt'"
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo AURUM_TEST_KILL_AT=undo:cli-link $A undo >/dev/null 2>&1; echo \"plain-undo-exit \$?\"; ls /etc/systemd/system/ollama.service 2>&1 | head -1; sudo mkdir -p /opt/own && sudo tar --zstd -xf /root/ollama.tar.zst -C /opt/own && sudo sh -c 'OLLAMA_MODELS=/var/lib/ollama/models HOME=/root nohup /opt/own/bin/ollama serve >/tmp/own.log 2>&1 & echo \$! > /tmp/own.pid'; sleep 4; sudo $A undo --purge-models; curl -s 127.0.0.1:11434/api/tags | grep -o 'qwen3:1.7b' | head -1; sudo kill \$(cat /tmp/own.pid); sudo rm -rf /opt/own; $CLEAN" foreign-purge
chk "late --purge-models with ANOTHER Ollama on 11434 -> its model is not touched" "grep -q 'not Aurum.s' '$OUT/foreign-purge.txt' && grep -qx 'qwen3:1.7b' '$OUT/foreign-purge.txt'"

# --- review r7: --force with a changed aurum-ws link keeps the stage; deleted answer after interruption stays deleted;
#     purge never touches an Ollama that is not Aurum's running service (stopped service + own Ollama; drop-in) ---
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo ln -sfn ../../../var/lib/aurum-ws/stage/aurum-ws-$VER/aurum-ws /usr/local/sbin/aurum-ws; sudo $A undo --purge-models --force; test -e $A && /usr/local/sbin/aurum-ws --help >/dev/null 2>&1 && echo LINK-STILL-WORKS; sudo rm -f /usr/local/sbin/aurum-ws; sudo rm -rf /var/lib/aurum-ws/stage" force-cli
chk "--force with your changed aurum-ws link -> undo completes, your link still works (stage kept + reported)" "grep -q 'Undo complete' '$OUT/force-cli.txt' && grep -q 'stage: kept' '$OUT/force-cli.txt' && grep -qx LINK-STILL-WORKS '$OUT/force-cli.txt'"
s "$FRESH; $TSTAGE; mkdir -p ~/.cache/ubuntu-report && printf '{\"my\": \"earlier\"}' > ~/.cache/ubuntu-report/ubuntu.24.04; $I AURUM_TEST_KILL_AT=privacy-ubuntu-report:done $A install --model qwen3:1.7b --privacy >/dev/null 2>&1; rm -f ~/.cache/ubuntu-report/ubuntu.24.04; sudo $A undo --purge-models; ls ~/.cache/ubuntu-report; rm -rf ~/.cache/ubuntu-report; $CLEAN" ureport-deleted
chk "answer deleted by you after an interruption -> stays deleted, earlier answer saved beside it" "! grep -qx 'ubuntu.24.04' '$OUT/ureport-deleted.txt' && grep -qx 'ubuntu.24.04.before-aurum' '$OUT/ureport-deleted.txt' && grep -q 'Undo complete' '$OUT/ureport-deleted.txt'"
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo systemctl stop ollama; sudo mkdir -p /opt/own && sudo tar --zstd -xf /root/ollama.tar.zst -C /opt/own && sudo sh -c 'OLLAMA_MODELS=/var/lib/ollama/models HOME=/root nohup /opt/own/bin/ollama serve >/tmp/own.log 2>&1 & echo \$! > /tmp/own.pid'; sleep 4; sudo $A undo --purge-models; curl -s 127.0.0.1:11434/api/tags | grep -o 'qwen3:1.7b' | head -1; sudo kill \$(cat /tmp/own.pid); sudo rm -rf /opt/own" own-ollama-on-port
chk "Aurum's service stopped + your own Ollama on 11434 -> purge does not touch its model" "grep -q 'not Aurum.s' '$OUT/own-ollama-on-port.txt' && grep -qx 'qwen3:1.7b' '$OUT/own-ollama-on-port.txt'"
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo mkdir -p /etc/systemd/system/ollama.service.d && printf '[Service]\nEnvironment=OLLAMA_MODELS=/srv/mymodels\n' | sudo tee /etc/systemd/system/ollama.service.d/m.conf >/dev/null; sudo systemctl daemon-reload; sudo aurum-ws undo --purge-models; echo \"undo-exit \$?\"; sudo rm -rf /etc/systemd/system/ollama.service.d; sudo systemctl daemon-reload; sudo aurum-ws undo --purge-models; $CLEAN" dropin-models
chk "drop-in moving the models folder -> purge keeps the model, undo stops at the service" "grep -q 'not Aurum.s' '$OUT/dropin-models.txt' && grep -qx 'undo-exit 1' '$OUT/dropin-models.txt'"

# --- review r8: purge with Aurum's service merely stopped; power cut between the two stage-removal phases ---
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo systemctl stop ollama; sudo $A undo --purge-models; $CLEAN; $NOMODEL" stopped-purge
chk "--purge-models while Aurum's service is stopped -> model really removed, undo clean" "grep -q 'Undo complete' '$OUT/stopped-purge.txt' && grep -qx SYSTEM-CLEAN '$OUT/stopped-purge.txt' && grep -qx NO-MODEL-LEFT '$OUT/stopped-purge.txt'"
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo AURUM_TEST_KILL_AT=undo:stage-phase1 $A undo --purge-models >/dev/null 2>&1; echo \"undo-exit \$?\"; ls $D; sudo $A undo; ls /var/lib/aurum-ws; $CLEAN" stage-phase1
chk "power cut between the stage phases -> only the script left; running it again finishes" "grep -qx 'undo-exit 137' '$OUT/stage-phase1.txt' && grep -qx aurum-ws '$OUT/stage-phase1.txt' && grep -q 'removed the last staged file' '$OUT/stage-phase1.txt' && ! grep -qx stage '$OUT/stage-phase1.txt' && grep -qx SYSTEM-CLEAN '$OUT/stage-phase1.txt'"

s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo AURUM_TEST_KILL_AT=undo:last-files $A undo --purge-models >/dev/null 2>&1; echo \"undo-exit \$?\"; ls $D; sudo $A undo; ls /var/lib/aurum-ws; $CLEAN" last-files
chk "power cut between the last two deletions -> only the script left; running it again finishes" "grep -qx 'undo-exit 137' '$OUT/last-files.txt' && grep -q 'removed the last staged file' '$OUT/last-files.txt' && ! grep -qx stage '$OUT/last-files.txt' && grep -qx SYSTEM-CLEAN '$OUT/last-files.txt'"

s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo AURUM_TEST_KILL_AT=undo:stage-mid $A undo --purge-models >/dev/null 2>&1; echo \"undo-exit \$?\"; ls $D | wc -l; sudo $A undo; ls /var/lib/aurum-ws; $CLEAN" stage-mid
chk "power cut half-way through removing the staged copy -> running it again removes the rest" "grep -qx 'undo-exit 137' '$OUT/stage-mid.txt' && grep -q 'Undo complete' '$OUT/stage-mid.txt' && ! grep -qx stage '$OUT/stage-mid.txt' && grep -qx SYSTEM-CLEAN '$OUT/stage-mid.txt'"

# --- review r5b: --privacy without access to Ubuntu's metrics server (offline PC) ---
s "$FRESH; $TSTAGE; rm -rf ~/.cache/ubuntu-report; echo '127.0.0.9 metrics.ubuntu.com' | sudo tee -a /etc/hosts >/dev/null; $I $A install --model qwen3:1.7b --privacy; echo \"install-exit \$?\"; ls -la ~/.cache/ubuntu-report; for f in ~/.cache/ubuntu-report/*; do echo \"FILE \$f: \$(cat \"\$f\")\"; done; sudo sed -i '/metrics.ubuntu.com/d' /etc/hosts; sudo $A undo --purge-models; ls ~/.cache/ubuntu-report 2>&1; $CLEAN" ureport-offline
chk "--privacy with Ubuntu's metrics server unreachable -> install completes (answer saved for later), undo removes it" "grep -qx 'install-exit 0' '$OUT/ureport-offline.txt' && grep -q 'saved your .no.' '$OUT/ureport-offline.txt' && grep -q 'Undo complete' '$OUT/ureport-offline.txt' && grep -qx SYSTEM-CLEAN '$OUT/ureport-offline.txt'"

# --- injected failures (each from a hard-reset system) ---
s "$FRESH; $STAGE; R=\$(ip route show default | head -1); sudo ip route del \$R; sudo $A install --model qwen3:1.7b; echo \"first-exit \$?\"; sudo ip route add \$R; sudo $A install --model qwen3:1.7b; sudo aurum-ws undo --purge-models; $CLEAN" net-download
chk "no network during download -> stop; network back -> resume completes; undo clean" "grep -q 'STOPPED: command failed: curl' '$OUT/net-download.txt' && grep -qx 'first-exit 1' '$OUT/net-download.txt' && grep -q 'Aurum Workstation .*: INSTALLED\$' '$OUT/net-download.txt' && grep -qx SYSTEM-CLEAN '$OUT/net-download.txt'"
s "$FRESH; $TSTAGE; echo '127.0.0.9 registry.ollama.ai' | sudo tee -a /etc/hosts >/dev/null; $I $A install --model qwen3:1.7b; echo \"first-exit \$?\"; sudo sed -i '/registry.ollama.ai/d' /etc/hosts; sleep 8; $I $A install --model qwen3:1.7b; sudo $A undo --purge-models; $CLEAN" pull-fail
chk "model download fails -> clear stop (no traceback); resume completes; undo clean" "grep -q 'STOPPED: downloading qwen3:1.7b failed' '$OUT/pull-fail.txt' && ! grep -q Traceback '$OUT/pull-fail.txt' && grep -qx 'first-exit 1' '$OUT/pull-fail.txt' && grep -q 'Aurum Workstation .*: INSTALLED\$' '$OUT/pull-fail.txt' && grep -qx SYSTEM-CLEAN '$OUT/pull-fail.txt'"
s "$FRESH; $TSTAGE; $I AURUM_TEST_KILL_AT=ollama-unit:intent $A install --model qwen3:1.7b >/dev/null 2>&1; sudo sh -c 'nohup python3 -m http.server 11434 --bind 127.0.0.1 >/dev/null 2>&1 & echo \$! > /tmp/h.pid'; sleep 2; $I $A install --model qwen3:1.7b; echo \"second-exit \$?\"; sudo kill \$(cat /tmp/h.pid); sleep 2; $I $A install --model qwen3:1.7b; sudo $A undo --purge-models; $CLEAN" port-taken
chk "foreign HTTP server on 11434 when the service starts -> stop (no false success); then resume completes" "grep -q 'STOPPED: Ollama did not answer' '$OUT/port-taken.txt' && grep -qx 'second-exit 1' '$OUT/port-taken.txt' && grep -q 'Aurum Workstation .*: INSTALLED\$' '$OUT/port-taken.txt' && grep -qx SYSTEM-CLEAN '$OUT/port-taken.txt'"
s "$FRESH; $TSTAGE; sudo python3 -c \"import json;p='$D/release.json';d=json.load(open(p));[x.update(digest='1'*64) for x in d['models'] if x['tag']=='qwen3:1.7b'];open(p,'w').write(json.dumps(d))\"; $I $A install --model qwen3:1.7b; curl -s 127.0.0.1:11434/api/tags; echo; sudo $A undo --purge-models; sudo find /var/lib/ollama -type f 2>/dev/null | sed 's/^/LEFT /'; $CLEAN" digest
chk "digest mismatch -> stop + pulled tag removed + undo clean (only Ollama's own key/cache left, named)" "grep -q 'digest .* != pinned' '$OUT/digest.txt' && grep -q 'removed it' '$OUT/digest.txt' && grep -q '\"models\":\[\]' '$OUT/digest.txt' && grep -qx SYSTEM-CLEAN '$OUT/digest.txt' && ! grep 'LEFT' '$OUT/digest.txt' | grep -qv '/.ollama/'"
s "$FRESH; $TSTAGE; $I $A install --model qwen3:1.7b >/dev/null; sudo chattr +i $D/LICENSE; sudo aurum-ws undo --purge-models; sudo $A undo; sudo chattr -i $D/LICENSE; ls /var/lib/aurum-ws" stage-stuck
chk "undeletable stage: undo completes, record archived, stage kept + reported" "grep -q 'Undo complete' '$OUT/stage-stuck.txt' && grep -q 'stage: kept .*could not remove' '$OUT/stage-stuck.txt' && grep -q 'manifest-undone-' '$OUT/stage-stuck.txt'"
