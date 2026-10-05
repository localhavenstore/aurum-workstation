# Aurum Workstation (free, v1.0.1 preview)

Local AI on the Ubuntu you already have - with a full record of what was changed and an undo.

One install gives you **Ollama** (a pinned release, verified by sha256) running as a service on **127.0.0.1 only**,
**one model that fits your RAM**, a **working first answer**, and (optional) privacy defaults and the Aurum wallpaper.
Everything Aurum changes is written to a root-only record first; `sudo aurum-ws undo` removes what Aurum created
(and tells you what it keeps on purpose - see Undo).

> Made with AI assistance and tested on throwaway virtual machines (see "Tested"). It changes your system:
> read `plan` first. No warranty.

## Supported
Ubuntu 24.04 and 26.04, x86_64. GNOME desktop for the wallpaper option (other desktops: everything else works, the
wallpaper step is skipped). Not supported: other Ubuntu versions, other distributions, ARM, WSL.

## What it does - and does not do
- Installs Ollama 0.35.1 from its official release file (pinned sha256) - **never** Ollama's install script.
- Creates the `ollama` system user, `/var/lib/ollama`, and `ollama.service` listening on `127.0.0.1:11434`.
- Pulls one model, chosen from your RAM (as reported, rounded to whole GB), its digest checked against the pinned one:

  | RAM | model | download |
  |---|---|---|
  | under 8 GB | qwen3:1.7b | 1.4 GB |
  | 8-15 GB | qwen3:4b-instruct | 2.5 GB |
  | 16-31 GB | qwen3:8b | 5.2 GB |
  | 32 GB or more | qwen3:14b | 9.3 GB |

  You can pick another one from this list with `--model`. If you already have that model, it is used as it is and
  never replaced or removed.
- `--privacy` (optional): apport `enabled=0` + service off; popularity-contest `PARTICIPATE="no"` (only if installed);
  `ubuntu-report send no` (for you - note: Ubuntu's tool records this choice by sending one `{"OptOut": true}`
  message to Ubuntu's server). Old values (including an earlier ubuntu-report answer) are recorded and restored by undo.
- `--theme` (optional, GNOME): sets the Aurum wallpaper (`picture-uri` + `picture-uri-dark`); old values restored by undo.
- **Does not**: install GPU drivers, add apt repositories or PPAs, install apt packages, open ports beyond localhost,
  touch an Ollama you already have. Aurum itself sends no data (no telemetry); its only network use is downloading
  Ollama and the model (plus ubuntu-report's own opt-out message, only with `--privacy`).
- **GPU**: v1 reports what it sees. It says "GPU" only if Ollama actually used the GPU for the test answer;
  otherwise it says "CPU". Driver setup is up to you (Ubuntu's "Additional Drivers").

## Install
1. Tools (from Ubuntu's own archive): `sudo apt install curl zstd minisign`
2. Download from the GitHub release: `aurum-ws-1.0.1.tar.gz`, `SHA256SUMS`, `SHA256SUMS.minisig`.
3. Copy them as root into a root-only folder FIRST, then verify and unpack only those copies:
   ```
   sudo install -d -m 0700 /var/lib/aurum-ws/incoming
   sudo install -m 0600 aurum-ws-1.0.1.tar.gz SHA256SUMS SHA256SUMS.minisig /var/lib/aurum-ws/incoming/
   sudo sh -c 'cd /var/lib/aurum-ws/incoming && minisign -Vm SHA256SUMS -P RWRm811iTQFRJDr+KMkiTDBv0FiIz9owb6TzcHOD1qZrohmHulCk8m6I && sha256sum -c SHA256SUMS \
     && install -d -m 0755 /var/lib/aurum-ws/stage && tar -xzf aurum-ws-1.0.1.tar.gz -C /var/lib/aurum-ws/stage --no-same-owner'
   ```
   Release public key (key ID 2451014D625DF366):
   ```
   RWRm811iTQFRJDr+KMkiTDBv0FiIz9owb6TzcHOD1qZrohmHulCk8m6I
   ```
   It is printed here AND on https://localhavenstore.github.io (two places, so one hacked page is not enough).
4. See what would happen (changes nothing): `sudo /var/lib/aurum-ws/stage/aurum-ws-1.0.1/aurum-ws plan`
5. Install: `sudo /var/lib/aurum-ws/stage/aurum-ws-1.0.1/aurum-ws install` (add `--privacy`, `--theme`, `--model TAG`)
6. Check any time: `sudo aurum-ws status` (shows every step and a test answer).

If an install is interrupted (power cut, Ctrl+C), run the same install command again - it continues.

## Undo
`sudo aurum-ws undo` removes what Aurum created, in reverse order. Kept on purpose:
- the `ollama` system account (other software may use it) - remove by hand: `sudo userdel ollama`;
- your models in `/var/lib/ollama` - add `--purge-models` to remove the ones Aurum downloaded (only if unchanged since).
  Ollama itself also creates its own key pair and a small cache in `/var/lib/ollama/.ollama`; undo keeps that folder
  and names the files - remove it by hand if you do not need it: `sudo rm -r /var/lib/ollama`;
- files you changed after the install (reported; `--force` removes/restores anyway). If you changed `ollama.service`
  (edited it or added your own settings), undo stops at that step and leaves Ollama fully working - nothing older is
  removed - until you undo your change or add `--force`;
- `/var/lib/aurum-ws/incoming` (your verified downloads) and the record of the undo.
If undo is interrupted before it finishes: `sudo /var/lib/aurum-ws/stage/aurum-ws-1.0.1/aurum-ws undo`.

## Upgrading from 1.0.0-preview
1.0.1 changes the model for 8-15 GB of RAM to `qwen3:4b-instruct`: the `qwen3:4b` that 1.0.0-preview pinned is a
"thinking" model that writes a long reasoning text before every answer. If you installed 1.0.0-preview you can keep it
and just run `ollama pull qwen3:4b-instruct`, or undo it with its own copy
(`sudo /var/lib/aurum-ws/stage/aurum-ws-1.0.0-preview/aurum-ws undo`) and install 1.0.1. 1.0.1 never changes a
system recorded by another version - it stops and tells you this.

## Known limits (v1.0 preview)
Undo is built to never remove what it cannot prove is Aurum's, and to stop rather than guess. So if you hand-edit
things Aurum installed (its `ollama.service`, the `ollama`/`aurum-ws` command links, `/var/lib/ollama`, Aurum's record
in `/var/lib/aurum-ws`) between install and undo, undo may stop at that step and ask you to put it back or use
`--force`, or keep a file and tell you where it is. It never silently deletes your own files. If anything is unclear:
`sudo aurum-ws status` shows every step, and the record is plain JSON in `/var/lib/aurum-ws/manifest.json`.
Power loss DURING undo may leave some of Aurum's files behind: just run undo again (`sudo aurum-ws undo`, or the
staged copy `sudo /var/lib/aurum-ws/stage/aurum-ws-1.0.1/aurum-ws undo`) - it continues where it stopped.

## Tested
On fresh throwaway VMs (official Ubuntu cloud images; 4 CPU cores, 8 GB RAM, no GPU; server images, so no desktop),
always through the full flow above with a test signing key:
- Ubuntu 24.04 and 26.04: install, only localhost listeners added (11434 + Ollama's own temporary 127.0.0.1 port while a
  model is loaded), a real test answer, re-run changes nothing, undo; a before/after comparison of packages, unit
  files, /usr/local, /etc/systemd/system and user accounts shows only the kept `ollama` account (plus folder dates).
- Power-cut simulation at every install step (Ollama files, link, account, models folder, service, model, command link,
  apport, popularity-contest, ubuntu-report), at two points each (just after the step was recorded, and just after it
  was done but before that was recorded): undo afterwards leaves the system clean, and running install again finishes
  with a real answer. Also with an Ollama you already had (it stays untouched and running), kill -9 / Ctrl+C during the
  downloads, power cuts during the last steps of undo (running undo again completes it), and a failing undo step
  (undo stops there and touches nothing older; running undo again finishes it).
- Your existing things: an existing Ollama binary (left byte-identical, also by undo), a busy port 11434, a foreign
  `ollama.service`, a foreign half-unpacked Ollama folder and a planted link next to it (never touched), an admin's
  file in Aurum's old download folder (never touched), a full disk (stops before downloading).
- Failures: no network during the Ollama download, the model download failing, a different program answering on
  port 11434 (no false success), a model whose checksum does not match (removed again), a wrong release checksum, a staged copy undo cannot delete (reported).
- Refused: running without sudo, two runs at once, a cache folder replaced by a link, the wallpaper option from a root
  login. An installing user whose home path contains spaces and a quote works.
- No internet after install: reboot, the service starts and answers. Clean boot after undo.
**Not tested yet:** real GPUs (NVIDIA / AMD), the wallpaper on a real GNOME desktop, laptops / other hardware,
upgrading from one Aurum version to the next.

## Licence
MIT. Not affiliated with Ollama, Canonical/Ubuntu or the Qwen team; their names belong to them.


## Support

The tool is free and stays free. If it saved you time, you can leave a tip:
[![Tip on Ko-fi](https://img.shields.io/badge/Ko--fi-leave%20a%20tip-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/localhaven)
(optional - nothing is unlocked by it).
