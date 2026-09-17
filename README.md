# caffeinate-win-pwsh

**The macOS `caffeinate` command, on Windows, in PowerShell.**

Keeps a Windows machine — and optionally its display — awake on demand, using the
same flags and the same muscle memory as `caffeinate -sid` on a Mac.

```powershell
caffeinate -sid                      # stay awake until Ctrl+C
caffeinate -sid -t 3600              # stay awake for an hour
caffeinate -sid npm run build        # stay awake for exactly as long as the build runs
```

---

## Why this exists

If you move between macOS and Windows workstations, `caffeinate` is one of those
commands your fingers already know. Windows has no equivalent. The usual
workarounds — nudging the mouse pointer on a timer, sending fake keystrokes, or
flipping the power plan and forgetting to flip it back — are all crude, and the
power-plan approach is genuinely risky because a crashed script leaves the machine
permanently unable to sleep.

This does it properly. It calls the Win32 API that Windows itself uses for this —
[`SetThreadExecutionState`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate) —
which is the same mechanism a video player or a disc burner uses to say "don't
sleep while I'm working." No synthetic input, no power-plan edits, nothing to
clean up afterwards. The assertion is scoped to your shell and is released
automatically when the command ends, when you press Ctrl+C, or if the shell exits.

Typical uses: long renders, model training runs, large downloads or uploads,
overnight builds, and remote sessions you need to stay reachable.

---

## Requirements

- Windows
- Windows PowerShell 5.1 **or** PowerShell 7+ — verified on both
- No administrator rights, no dependencies, nothing to compile

---

## Installation

```powershell
git clone https://github.com/MushroomFleet/caffeinate-win-pwsh.git
cd caffeinate-win-pwsh
.\install.ps1
```

That's it. Open a new shell and `caffeinate -sid` is available.

The installer finds every PowerShell host on the machine and writes the function
into each one's profile. This matters because Windows PowerShell 5.1 and
PowerShell 7 use *different* profile files, so installing into one leaves the
other without the command. It asks each host for its own profile path rather than
guessing, so a Documents folder redirected to OneDrive is handled correctly.

Re-running is safe. The function is written between marker comments and replaced
in place, so it updates rather than accumulating copies. To preview without
writing anything:

```powershell
.\install.ps1 -WhatIf
```

To remove it again, leaving the rest of your profile untouched:

```powershell
.\install.ps1 -Uninstall
```

If profile scripts are blocked, authorise them once with:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Without installing

To try it in the current session only:

```powershell
. .\caffeinate.ps1
```

---

## Usage

### Flags

Flags stack exactly as they do on macOS, so `-sid` works as one token.

| Flag | macOS meaning | Windows mapping |
|------|---------------|-----------------|
| `-d` | Prevent display sleep | `ES_DISPLAY_REQUIRED` |
| `-i` | Prevent idle system sleep | `ES_SYSTEM_REQUIRED` |
| `-s` | Prevent system sleep on AC power | `ES_SYSTEM_REQUIRED` |
| `-u` | Declare user activity | `ES_DISPLAY_REQUIRED` |
| `-m` | Prevent disk idle sleep | *accepted, no Windows equivalent* |
| `-t <seconds>` | Hold the assertion for a fixed duration | — |
| `-w <pid>` | Hold until the given process exits | — |

With no flags, `caffeinate` prevents idle sleep only (`-i`), matching macOS —
the display is still allowed to switch off.

### Modes

**Indefinite** — hold until you stop it:

```powershell
caffeinate -sid
```

**Fixed duration** — release automatically after N seconds:

```powershell
caffeinate -sid -t 1800
```

**Wrap a command** — awake for exactly the lifetime of that process, then released:

```powershell
caffeinate -sid npm run build
caffeinate -i python train_model.py --epochs 200
caffeinate -d "C:\Tools\Backup Utility.exe" --all
```

Arguments, quoting and paths containing spaces are passed through untouched, and
the wrapped command's exit code is preserved in `$LASTEXITCODE`.

**Wait on an existing process** — useful for something already running:

```powershell
caffeinate -sid -w 12345
```

### Releasing early

Press `Ctrl+C`. The assertion is released on the way out.

A `decaffeinate` command is also included as an escape hatch, for the rare case
where cleanup is skipped but the shell itself is still running:

```powershell
decaffeinate
```

If the shell exits at all — closed normally, or killed outright — the assertion
goes with it. The state belongs to that process rather than to the system, so no
crash can leave your machine permanently unable to sleep. This is the main
practical advantage over power-plan-editing approaches, which fail dirty.

---

## Implementation notes

The port is less trivial than it looks, and these are the traps worth knowing
about if you plan to modify the script or write your own:

- **PowerShell cannot bind stacked Unix-style flags.** `-sid` is not parsed as
  `-s -i -d`; PowerShell searches for a single parameter named `sid`, fails, and
  either errors or silently swallows the token. This script parses its own argv
  to deliver real `-sid` stacking.

- **`0x80000000` is a *negative Int32* in PowerShell.** Writing
  `[uint32]$flags = 0x80000000` throws a conversion error, and `ES_CONTINUOUS`
  never gets set. Without that bit, `SetThreadExecutionState` performs a one-shot
  reset of the idle timer rather than a standing assertion, so the machine sleeps
  a few minutes later anyway. The portable spelling is `[uint32]2147483648` — the
  `0x80000000u` suffix is PowerShell 7 only and fails to parse under 5.1.

- **Flags must be combined with `-bor`, not `+`.** Adding overlapping bits
  carries: `-s` plus `-i` both being `0x1` sums to `0x2`, which is
  `ES_DISPLAY_REQUIRED` — the exact inverse of what was asked for. Summed
  `-sid` lands on `0x4` (`ES_USER_PRESENT`), which the API rejects outright,
  returning `0`.

- **`-i` collides with a common parameter.** Adding `[CmdletBinding()]` brings in
  `-InformationAction` and `-InformationVariable`, making a bare `-i` ambiguous.
  `caffeinate` is therefore deliberately a simple function reading `$args`.

- **The assertion is per-*thread*.** It is set and cleared on the same PowerShell
  pipeline thread, which is stable across commands within a session. A
  `Start-Job` background wrapper runs on a different thread and would not work.

---

## Repository structure

```
install.ps1                    installs into every PowerShell host's profile
caffeinate.ps1                 the implementation
scratch-concept/               original concept notes, kept for provenance
README.md
LICENSE
```

`scratch-concept/` holds the two hand-written guides this project grew out of:
`original-caffeinate-instructions.md` and the portable `caffeinate-windows.md`.
They are archived as a record of how the idea took shape, and are **superseded by
`caffeinate.ps1`**.

Treat them as notes, not instructions. The PowerShell in those documents predates
the fixes listed under [Implementation notes](#implementation-notes) and does not
work as written — among other things `-sid` never binds, `ES_CONTINUOUS` is never
set, and the flags are summed rather than OR'd, so the headline
`caffeinate -sid` is a no-op. Run `install.ps1` instead.

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).

---

## 📚 Citation

### Academic Citation

If you use this codebase in your research or project, please cite:

```bibtex
@software{caffeinate_win_pwsh,
  title = {caffeinate-win-pwsh: macOS caffeinate for Windows PowerShell},
  author = {Drift Johnson},
  year = {2026},
  url = {https://github.com/MushroomFleet/caffeinate-win-pwsh},
  version = {1.0.0}
}
```

### Donate:

[![Ko-Fi](https://cdn.ko-fi.com/cdn/kofi3.png?v=3)](https://ko-fi.com/driftjohnson)

---
