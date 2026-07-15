# Screenshots into the container — design decisions

Standalone design doc for wiring macOS screenshots into every `claude-dev-env` container. Written in
the style of the repo's `decisions.md`; not yet merged into it. Host is macOS + OrbStack.

## Problem

Claude Code's image paste (`Cmd+V`) doesn't work inside the devcontainers. The CLI reads clipboard
images via `wl-paste`/`xclip`/`xsel`, which need an X11/Wayland selection. These containers have neither
the binaries nor any display server (`DISPLAY`/`WAYLAND_DISPLAY` empty), so there is no clipboard for the
CLI to read. Installing the binaries alone wouldn't fix it — there's nothing behind them.

Goal (as refined during the interview): when I take a **macOS screenshot**, I want Claude in the
container to be able to see it — integrated with the native macOS screenshot flow, not a separate
copy-and-dump ritual.

---

## §1 — Mechanism: screenshot-to-file, not clipboard paste

**Decision.** Use macOS screenshot-**to-file**. Screenshots land in a host folder that is bind-mounted
into the container; Claude reads the newest file. No `Cmd+V`, no clipboard, no display server.

**Reasoning.** A headless Linux container can't participate in the macOS clipboard or render a paste.
Files are the one channel that crosses the boundary reliably (OrbStack bind mounts sync live).

**Alternatives rejected.**
- *True `Cmd+V` paste in the TUI* — would need a headless Xvfb + `xclip` baked into every image **and**
  a standing host-side LaunchAgent daemon pushing every clipboard change into the container via
  `docker exec … xclip -i`. An always-on background process, not a config change. Deferred as a much
  bigger lift, only worth it if the file flow proves too annoying.
- *Hotkey dumps clipboard → file on demand* (`osascript` PNG dump) — works from the clipboard, no daemon,
  but still a per-image manual trigger and doesn't ride the native screenshot flow the user asked for.

---

## §2 — Capture: a non-default entry in the screenshot "Save to" menu

**Decision.** Add `~/claude-shots` as a **non-default, selectable** destination in the `Cmd+Shift+5`
screenshot toolbar's "Save to" menu, via a **one-time** `Options → Save to → Other Location… →
~/claude-shots` pick. The Desktop stays the default. Per screenshot, the user picks `claude-shots` when
they want Claude to see that image.

**Reasoning.** The user wanted a *destination in the native screenshot menu*, not a global redirect of
their normal screenshot habit. macOS persists folders chosen via "Other Location…" in that menu as
selectable recent destinations.

**Known limitation / honesty.** This is **not scriptable**. The only documented, scriptable knob is
`com.apple.screencapture location`, which sets the *default* (making the folder catch **all**
screenshots) — the global redirect we explicitly rejected. There is no known `defaults` key to inject a
named, non-default entry. So the pick is a documented one-time manual step, and the menu's recent-list can
rotate the folder out if many other "Other Location…" folders are chosen later. (Not verified on the host
from inside the Linux container — worth a quick confirm on the Mac.)

**Alternatives rejected.**
- *Set it as the scriptable default* — hijacks the default; Desktop screenshots stop.
- *Mount `~/Desktop` read-only and read newest there* — exposes the whole Desktop and reads from clutter.
- *Folder Action / watcher copying Desktop shots into `~/claude-shots`* — more moving parts to maintain.

---

## §3 — Scope: one global folder

**Decision.** A single global `~/claude-shots` on the host, mounted into every container (`cc` + all
seeded/cloned projects).

**Reasoning.** Screenshots are transient scratch, not per-project artifacts, and the destination is
chosen manually in the macOS menu anyway. One folder = one `Other Location…` pick, one `mkdir`, works
everywhere.

**Alternative rejected.** *Per-project folder* (`~/claude-shots/<project>`) — would force re-picking the
destination in the macOS menu on every project switch, defeating the one-time-setup goal.

---

## §4 — Mount mode: read-write

**Decision.** Mount read-write (plain `type=bind`; `-v` for `cc`).

**Reasoning.** Claude needs to delete a screenshot after reading it (see §5).

**Alternative rejected.** *Read-only* — safer against accidental clobber, but blocks the cleanup in §5;
the user chose to accept the clobber risk in exchange for auto-cleanup.

---

## §5 — Post-read: delete

**Decision.** After Claude reads a screenshot, it `rm`s the file.

**Reasoning.** Keeps the folder tiny and keeps "newest at top level" unambiguous over a long session.

**Alternatives rejected.**
- *Move to `~/.claude-shots/seen/`* — reversible, but the user preferred the simpler tiny-folder outcome.
- *Leave in place* — folder grows; "newest" gets muddier; read-write access would be pointless.

---

## §6 — Convention home: `general/CLAUDE.md`

**Decision.** Add a short `## Screenshots` section to `general/CLAUDE.md` (which is `@import`ed into every
container): when the user refers to a screenshot they took / "my last screenshot", read the **newest file
by mtime at the top level of `~/.claude-shots/`**, then `rm` it after use; if the folder is empty, say so.

**Reasoning.** `general/CLAUDE.md` is always in context in every container, so the convention fires
implicitly on "look at my screenshot" with no re-explaining. This is the piece that makes it *integrated*.

**Alternatives rejected.**
- *A dedicated skill* — heavier, only fires on explicit invocation; overkill for a one-line convention.
- *README only, tell Claude the path each session* — least integrated.

---

## §7 — Coverage: templates + `cc`, not the base container

**Decision.** Add the mount to `templates/node-ts`, `templates/python`, and `cc.sh`. **Not** the repo's
own `.devcontainer/devcontainer.json`.

**Reasoning.** Screenshots matter where app work happens. The base container is for hacking on
`claude-dev-env`'s own shell scripts, where UI screenshots don't come up; it currently mounts nothing
from `$HOME`, so adding it there is low-value.

**Alternative rejected.** *All four (uniform)* — harmless and consistent, but a needless line in a
container that won't use it.

---

## §8 — Folder creation: `setup.sh` + all four bring-up scripts

**Decision.** `mkdir -p "$HOME/claude-shots"` in `setup.sh` **and** in `seed.sh`, `up.sh`, `clone.sh`,
`cc.sh`, next to the existing state-dir precreation.

**Reasoning.** A bind source must exist at container-create time, and `setup.sh` isn't guaranteed to have
run before a given bring-up (existing installs; a fresh clone + `d seed` without re-running `setup.sh`).
Guaranteeing it at every bring-up mirrors exactly how the repo already precreates
`~/claude-state/<name>/{projects,claude.json}` ("Mount targets must pre-exist; idempotent"). One line ×5.

**Alternative rejected.** *`setup.sh` only* — minimal, but a bring-up before `setup.sh` fails the mount
with `invalid mount config … field Source must not be empty`.

---

## §9 — Naming: visible host, hidden container

**Decision.** Host **`~/claude-shots`** (visible); container target **`~/.claude-shots`** (hidden).

**Reasoning.** The macOS `Other Location…` picker doesn't surface hidden dot-folders without
`Cmd+Shift+.`, so the host folder must be visible to be pickable. Inside the container a dot-folder keeps
`$HOME` tidy. The asymmetry is intentional and documented.

**Alternatives rejected.** *Both visible* (symmetric, one extra visible dir in container home — fine but
not tidy) and *both hidden* (host folder awkward to select in the Finder dialog). The handoff's original
`~/.claude-clipboard` name is dropped: "shots" fits screenshots, and a hidden host folder is a pain to
pick.

---

## §10 — Discoverability of the one-time pick

**Decision.** Document it in a new README subsection (host-setup area) **and** echo a next-step reminder
at the end of `setup.sh` (matching the existing OAuth-token note):
`Cmd+Shift+5 → Options → Save to → Other Location… → ~/claude-shots`.

**Reasoning.** It's the single manual, non-scriptable step; if it isn't surfaced, screenshots silently
won't appear. README gives a lasting reference; the `setup.sh` echo nudges at the moment of setup.

**Alternatives rejected.** *README only* (easy to miss) and *`setup.sh` only* (no reference once the
terminal scrolls).

---

## Concrete artifacts to change

- `templates/node-ts/.devcontainer/devcontainer.json` — add to `mounts`:
  `"source=${localEnv:HOME}/claude-shots,target=/home/node/.claude-shots,type=bind"`
- `templates/python/.devcontainer/devcontainer.json` — same, target `/home/vscode/.claude-shots`
- `cc.sh` — add `-v "$HOME/claude-shots":/home/node/.claude-shots` to `docker run`, and
  `mkdir -p "$HOME/claude-shots"` next to the existing `mkdir -p "$WORKSPACE" "$STATE/projects"`
- `seed.sh`, `up.sh`, `clone.sh` — `mkdir -p "$HOME/claude-shots"` next to the state precreation
- `setup.sh` — `mkdir -p "$HOME/claude-shots"` + a next-step echo for the one-time menu pick
- `general/CLAUDE.md` — new `## Screenshots` section
- `README.md` — new "Screenshots into the container" subsection

## Verify at implementation time (risks, not decisions)

- **Write permission from the container.** Host-created source → OrbStack maps ownership to the container
  user, so `rm` should work without the `sudo chown` the auto-created state mounts need. Confirm with a
  real `rm` inside a container.
- **Rebuild required.** Mounts are fixed at create time; existing projects/`cc` need a rebuild
  (`d seed …` / `cc --rebuild`) before the mount appears.
