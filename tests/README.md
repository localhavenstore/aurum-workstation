# Aurum Workstation - VM tests

These are the scripts behind TESTING.md. Each one starts a FRESH throw-away Ubuntu VM, runs the documented flow
(sign with a test key -> root-only copy -> verify -> unpack -> plan/install/undo), and writes PASS/FAIL lines to
`$OUTDIR/ws-<suite>/summary.txt` (default `./results`).

They need a small VM helper, given as `TESTVM=/path/to/helper`, with four commands:
- `helper up` - boot a fresh official Ubuntu cloud image (24.04, or 26.04 when `TESTVM_UBUNTU=26.04`) with a user that
  has passwordless sudo and network access; exit non-zero if the machine is busy
- `helper ssh 'COMMAND'` - run a shell command in the VM as that user
- `helper put LOCAL REMOTE_DIR` - copy a file into the VM
- `helper down` - stop the VM and delete its disk

Build first (`bash build/build.sh` -> `dist/`), then e.g. `TESTVM=~/bin/testvm bash tests/w1_vm.sh`.
w13 uses a test-only hook: it puts a `.aurum-test-build` marker into the staged copy inside the VM, which enables
deterministic kill points (`AURUM_TEST_KILL_AT`) and a local copy of the Ollama download. Release builds never contain
that marker, so the hooks are dead code there.
