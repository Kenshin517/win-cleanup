# win-cleanup

[![CI](https://github.com/OWNER/win-cleanup/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/win-cleanup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

One script to free space on a full Windows `C:` drive, **safely**.

Most "clean your C: drive" tutorials walk you through 7+ manual steps: empty `%temp%`, delete the
Windows Update cache, run Disk Cleanup, clear the Recycle Bin, remove restore points, and so on.
`win-cleanup` does the safe parts automatically, asks before the risky ones, and only *reports*
the parts that need a human decision.

> [!NOTE]
> Bahasa Indonesia? Lihat [Ringkasan](#ringkasan-bahasa-indonesia) di bawah.

## Features

- **Dry run first**: `-WhatIf` shows what would be removed and how much space you'd get, without deleting anything.
- **Three safety tiers**: automatic, ask-first, and report-only (see below).
- **Before/after report** of free space on the system drive.
- **Never follows symlinks or junctions** when deleting, so a link inside a temp folder can't take your real files with it.
- **Skips files in use** and temp files modified in the last 24 hours (configurable), so running installers don't break.
- **Logs every run** to `%LOCALAPPDATA%\WinCleanup\logs`.
- Works on **Windows PowerShell 5.1** (built into Windows 10/11) and **PowerShell 7+**. No dependencies.

## What it cleans

| Tier | Task | Id (for `-Skip`) | Notes |
|---|---|---|---|
| Auto | User temp files (`%TEMP%`) | `user-temp` | Files older than 24 h by default |
| Auto | Windows temp files | `windows-temp` | Admin |
| Auto | Windows Update download cache | `update-cache` | Admin. Stops `wuauserv`/`bits` first, restarts them after |
| Auto | Disk Cleanup, safe categories only | `disk-cleanup` | Admin. **Never** includes Downloads, Recycle Bin or "Previous Installations" |
| Auto | Component store cleanup (DISM) | `component-store` | Admin. Only with `-Deep`; can take 10+ minutes |
| Ask first | Recycle Bin | `recycle-bin` | Shows the size before asking |
| Ask first | Old restore points | `restore-points` | Admin. Always keeps the newest one |
| Ask first | Hibernation file (`hiberfil.sys`) | `hibernation` | Admin. Also turns off Fast Startup. Undo: `powercfg /hibernate on` |
| Report only | Largest files in Desktop, Documents, Downloads, Pictures, Videos, Music | | Nothing is deleted |
| Report only | Largest installed apps | | Nothing is uninstalled |

**What it deliberately never does:** delete your personal files, uninstall apps, clear the `Prefetch`
folder (that makes apps start *slower*), or touch Windows rollback data.

## Quick start

1. Download this repo: **Code → Download ZIP**, then extract it (or `git clone`).
2. Double-click **`run-cleanup.cmd`** and accept the Administrator prompt.

### Recommended: dry run first

Open PowerShell **as Administrator** in the extracted folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\cleanup.ps1 -WhatIf
```

When you're happy with what it shows, run it for real:

```powershell
powershell -ExecutionPolicy Bypass -File .\cleanup.ps1
```

### Options

| Option | Description |
|---|---|
| `-WhatIf` | Dry run. Measures only, deletes nothing |
| `-Deep` | Also run DISM component store cleanup (slow) |
| `-Skip <ids>` | Skip tasks, e.g. `-Skip hibernation, restore-points` |
| `-Force` | Don't ask before "ask first" tasks. Use with care |
| `-TempMinAgeHours <n>` | Keep temp files newer than `n` hours (default `24`, `0` = delete all) |
| `-NoReport` | Skip the manual review report |
| `-LogDirectory <path>` | Where to write the log |
| `-PassThru` | Output result objects (for scripting) |

Without Administrator rights, it still cleans your own temp files and Recycle Bin and skips the rest.

## Sample output (illustrative)

```text
Name                                  Tier    Status      Freed     Detail
----                                  ----    ------      -----     ------
User temp files (%TEMP%)              Auto    Cleaned     1.84 GB
Windows temp files                    Auto    Cleaned     312.40 MB
Windows Update download cache         Auto    Cleaned     790.12 MB
Disk Cleanup (safe categories only)   Auto    Cleaned     2.95 GB
Recycle Bin                           Confirm Declined    4.10 GB
Old restore points (keeps the newest) Confirm NothingToDo unknown
Hibernation file (hiberfil.sys)       Confirm Cleaned     6.38 GB

Free space on C: 3.12 GB -> 15.41 GB (+12.29 GB)
```

## Honest expectations

The automatic tasks usually free a few GB. Tutorials that show "3 GB → 33 GB" get most of that
from deleting personal files and uninstalling apps, which no script can decide for you. That's
why the report at the end lists your biggest files and apps: the big wins are there.

## Development

Requires [Pester 5](https://pester.dev) and [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer).

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force

Invoke-Pester ./tests
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

CI runs both on Windows PowerShell 5.1 and PowerShell 7 for every push and pull request.

### Project layout

```text
cleanup.ps1                  Entry point; forwards options to Invoke-WinCleanup
run-cleanup.cmd              Double-click launcher (self-elevates)
src/WinCleanup/
  Public/Invoke-WinCleanup.ps1   Orchestration, dry run, summary
  Private/Tasks.ps1              Task definitions (add new tasks here)
  Private/TaskRunner.ps1         Resolve (check + measure) and run a task
  Private/FileSystem.ps1         Symlink-safe size/delete helpers
  Private/Reports.ps1            Report-only tier
tests/                       Pester tests
```

To add a task, add a `New-CleanupTask` entry in `Get-CleanupTask`, add its id to the `-Skip`
`ValidateSet` in `Invoke-WinCleanup` (a test enforces this), and document it in the table above.

## Contributing

Issues and pull requests are welcome. Please use [Conventional Commits](https://www.conventionalcommits.org)
(`feat(tasks): add browser cache cleanup`) and make sure `Invoke-Pester` and `Invoke-ScriptAnalyzer` pass.

## Disclaimer

This tool deletes files. It has been designed to be conservative, but you use it at your own risk.
Run `-WhatIf` first.

## License

[MIT](LICENSE)

---

## Ringkasan (Bahasa Indonesia)

Satu script untuk mengosongkan drive `C:` yang penuh dengan **aman**. Langkah-langkah yang biasanya
dilakukan manual (hapus `%temp%`, cache Windows Update, Disk Cleanup, Recycle Bin, restore point)
digabung jadi satu:

- **Otomatis**: file temp, cache update, Disk Cleanup (kategori aman saja).
- **Tanya dulu**: Recycle Bin, restore point lama (yang terbaru tetap disimpan), file hibernasi.
- **Laporan saja**: file terbesar di folder pribadi dan aplikasi terbesar. Tidak ada yang dihapus.

**Cara pakai:** download ZIP, ekstrak, lalu klik dua kali `run-cleanup.cmd`.
Untuk simulasi tanpa menghapus apa pun, jalankan `.\cleanup.ps1 -WhatIf` di PowerShell (Administrator).
