# win-cleanup

[![CI](https://github.com/Kenshin517/win-cleanup/actions/workflows/ci.yml/badge.svg)](https://github.com/Kenshin517/win-cleanup/actions/workflows/ci.yml)
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

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (already built into Windows) or PowerShell 7+
- Administrator rights for the system-level tasks
- [Git](https://git-scm.com/download/win) *only* if you want to install with `git clone`

## Installation

Pick **one** of the two options.

### Option A: git clone

1. Open **PowerShell** (no admin needed for this step).
2. Go to the folder where you want to keep the tool, e.g. your user folder:

   ```powershell
   cd $HOME
   ```

3. Clone the repository:

   ```powershell
   git clone https://github.com/Kenshin517/win-cleanup.git
   ```

4. Enter the folder:

   ```powershell
   cd win-cleanup
   ```

To update later, run `git pull` inside the `win-cleanup` folder.

### Option B: download ZIP (no Git needed)

1. On this page, click the green **Code** button, then **Download ZIP**.
2. Right-click the downloaded `win-cleanup-main.zip`, choose **Properties**, tick **Unblock**, click **OK**.
   (This stops Windows from blocking scripts downloaded from the internet.)
3. Right-click the ZIP again, choose **Extract All...**, and extract it, e.g. to `C:\win-cleanup`.

## Usage

### Easiest: double-click

1. Open the `win-cleanup` folder in File Explorer.
2. Double-click **`run-cleanup.cmd`**.
3. Click **Yes** on the Administrator (UAC) prompt.
4. Automatic tasks run first. For each "ask first" task, type **Y** to clean it or **N** to keep it, then press Enter.
5. Read the summary and the list of your largest files/apps, then press any key to close.

> [!TIP]
> If Windows shows **"Windows protected your PC"**, click **More info → Run anyway**.

### Recommended: dry run first (PowerShell)

A dry run shows what *would* be deleted and how much space you'd get, without deleting anything.

1. Press **Start**, type `PowerShell`, right-click **Windows PowerShell**, choose **Run as administrator**.
2. Go to the folder (adjust the path to where you put it):

   ```powershell
   cd $HOME\win-cleanup
   ```

3. Run the dry run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\cleanup.ps1 -WhatIf
   ```

4. If you're happy with the result, run it for real:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\cleanup.ps1
   ```

`-ExecutionPolicy Bypass` only applies to this one command; it does not change your system settings.

### More examples

```powershell
# Never touch the hibernation file or restore points
powershell -ExecutionPolicy Bypass -File .\cleanup.ps1 -Skip hibernation, restore-points

# Also run the slow DISM component store cleanup
powershell -ExecutionPolicy Bypass -File .\cleanup.ps1 -Deep

# Delete all temp files, not only ones older than 24 hours
powershell -ExecutionPolicy Bypass -File .\cleanup.ps1 -TempMinAgeHours 0
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

### Instalasi

**Opsi A, pakai git clone** (butuh [Git](https://git-scm.com/download/win)):

```powershell
cd $HOME
git clone https://github.com/Kenshin517/win-cleanup.git
cd win-cleanup
```

Untuk update ke versi terbaru: `git pull` di dalam folder `win-cleanup`.

**Opsi B, download ZIP:** klik tombol hijau **Code → Download ZIP**, klik kanan file ZIP →
**Properties** → centang **Unblock** → OK, lalu klik kanan → **Extract All...**

### Cara pakai

**Paling gampang:** buka folder `win-cleanup`, klik dua kali `run-cleanup.cmd`, klik **Yes** di prompt
Administrator. Untuk task "tanya dulu", ketik **Y** (bersihkan) atau **N** (lewati) lalu Enter.
Kalau muncul "Windows protected your PC", klik **More info → Run anyway**.

**Disarankan, simulasi dulu:** buka PowerShell sebagai Administrator (Start → ketik `PowerShell` →
klik kanan → **Run as administrator**), lalu:

```powershell
cd $HOME\win-cleanup
powershell -ExecutionPolicy Bypass -File .\cleanup.ps1 -WhatIf   # simulasi, tidak menghapus apa pun
powershell -ExecutionPolicy Bypass -File .\cleanup.ps1           # jalankan beneran
```
