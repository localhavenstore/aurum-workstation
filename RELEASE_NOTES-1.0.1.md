Aurum Workstation 1.0.1 (preview) - fixes found by recording a real demo of 1.0.0-preview on a fresh VM.

Changes
- The model for 8-15 GB of RAM is now `qwen3:4b-instruct`. The `qwen3:4b` tag that 1.0.0-preview pinned is now a
  "thinking" model upstream: every answer started with a long reasoning text, also the install's own test answer.
- The install's test answer never shows thinking text (a leading <think> block is removed).
- If Ollama answers slowly right after a big download, install waits longer and retries; if it still does not answer,
  it stops with a clear message ("wait a minute, then run the same command again") instead of "unexpected error".
- One record = one version: 1.0.1 refuses to install over, or undo, a system set up by another Aurum version, and
  tells you the exact command for that version's own copy. Nothing is changed when it refuses.
- New VM test W14 (default model on an 8 GB machine, clean test answer, other-version refusal). The VM test scripts are
  now in the repo (tests/).

Upgrading from 1.0.0-preview: keep it and run `ollama pull qwen3:4b-instruct`, or undo it with its own copy
(`sudo /var/lib/aurum-ws/stage/aurum-ws-1.0.0-preview/aurum-ws undo`) and install 1.0.1. See README.

Still a preview: tested on fresh Ubuntu 24.04/26.04 VMs (111 automated checks incl. power-cut simulation),
not yet on real GPUs, a real GNOME desktop or laptops.

Verify before you run anything (README step 3):
  minisign -Vm SHA256SUMS -P RWRm811iTQFRJDr+KMkiTDBv0FiIz9owb6TzcHOD1qZrohmHulCk8m6I && sha256sum -c SHA256SUMS
Files: aurum-ws-1.0.1.tar.gz, SHA256SUMS, SHA256SUMS.minisig.

Made with AI assistance. MIT licence. Not affiliated with Ollama, Canonical/Ubuntu or the Qwen team.
