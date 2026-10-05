# How Aurum Workstation is tested

Every release is tested on fresh, throw-away virtual machines (official Ubuntu cloud images, 4 CPU cores, 8 GB RAM, no
GPU, no desktop), always through the full documented flow: sign the release with a test key, copy it into a root-only
folder, verify the signature and checksum, unpack, `plan`, `install`, test answer, re-run, `undo`, reboot.

v1.0.1: 111 automated checks, all passing, in seven suites (v1.0.0-preview: 105 in six):
- Full flow on Ubuntu 24.04 and 26.04 (8 checks each): only localhost listeners added, a real test answer, re-run
  changes nothing, undo; before/after comparison of packages, unit files, /usr/local, /etc/systemd/system and users.
- Power-cut simulation (kill -9) at every install step, at two points each, followed by undo (system clean) and by
  install again (finishes with a real answer); power cuts at every stage of undo itself (running undo again finishes).
- Your existing things: an existing Ollama (untouched, also by undo), a busy port, a foreign `ollama.service`, your own
  service settings or links (undo stops instead of breaking them), an earlier ubuntu-report answer (restored, or kept
  next to the current one after an interruption).
- Failures: no network, model download failure, a different program on port 11434, wrong checksums, a full disk,
  an undeletable file during undo.
- Offline after install + reboot; clean boot after undo; a user whose home path contains spaces and a quote.
- New in 1.0.1 (W14): the default model on an 8 GB machine gives a clean test answer (no thinking text), and 1.0.1
  refuses to install over, or undo, a system set up by another Aurum version, changing nothing.

The VM test scripts are in `tests/` (see tests/README.md); they need a small VM helper of your own.

Not tested yet: real GPUs (NVIDIA / AMD), the wallpaper on a real GNOME desktop, laptops / other hardware, an automatic
upgrade from one Aurum version to the next (1.0.1 refuses instead; see README).
