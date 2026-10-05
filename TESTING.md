# How Aurum Workstation is tested

Every release is tested on fresh, throw-away virtual machines (official Ubuntu cloud images, 4 CPU cores, 8 GB RAM, no
GPU, no desktop), always through the full documented flow: sign the release with a test key, copy it into a root-only
folder, verify the signature and checksum, unpack, `plan`, `install`, test answer, re-run, `undo`, reboot.

v1.0.0-preview: 105 automated checks, all passing, in six suites:
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

Not tested yet: real GPUs (NVIDIA / AMD), the wallpaper on a real GNOME desktop, laptops / other hardware, upgrading
from one Aurum version to the next. The VM test scripts will be published in a later version.
