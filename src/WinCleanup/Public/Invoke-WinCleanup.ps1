function Invoke-WinCleanup {
    <#
    .SYNOPSIS
        Frees space on the Windows system drive by removing disposable files.

    .DESCRIPTION
        Runs cleanup tasks in two tiers, then prints a report for manual review:
          Auto    - temp files, Windows Update cache, Disk Cleanup (safe categories).
          Confirm - Recycle Bin, old restore points, hibernation file. Asks first.
          Report  - largest personal files and installed apps. Never deleted.

        Use -WhatIf for a dry run that only measures what would be removed.

    .PARAMETER TempMinAgeHours
        Temp files modified more recently than this are kept, so running installers
        and apps do not lose files they are still using.

    .PARAMETER Deep
        Also runs DISM component store cleanup. Safe but can take 10+ minutes.

    .PARAMETER Skip
        Task ids to skip, e.g. -Skip hibernation, restore-points.

    .PARAMETER Force
        Do not ask before running Confirm-tier tasks.

    .PARAMETER NoReport
        Skip the manual review report.

    .PARAMETER LogDirectory
        Where the transcript log is written. Logs are not written in -WhatIf mode.

    .PARAMETER PassThru
        Emit one result object per task.

    .EXAMPLE
        Invoke-WinCleanup -WhatIf

    .EXAMPLE
        Invoke-WinCleanup -Skip hibernation -Deep
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(0, 8760)]
        [int] $TempMinAgeHours = 24,

        [switch] $Deep,

        [ValidateSet('user-temp', 'windows-temp', 'update-cache', 'disk-cleanup', 'component-store',
            'recycle-bin', 'restore-points', 'hibernation')]
        [string[]] $Skip = @(),

        [switch] $Force,

        [switch] $NoReport,

        [string] $LogDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WinCleanup\logs'),

        [switch] $PassThru
    )

    if (-not (Test-IsWindowsHost)) {
        throw 'Invoke-WinCleanup only runs on Windows.'
    }

    $drive = Get-SystemDrive
    $isAdmin = Test-IsAdministrator
    $olderThanUtc = [datetime]::UtcNow.AddHours(-$TempMinAgeHours)
    $isDryRun = [bool]$WhatIfPreference

    $logPath = Start-CleanupLog -Directory $LogDirectory
    try {
        if (-not $isAdmin) {
            Write-Warning 'Not running as Administrator: system-level tasks will be skipped. Use run-cleanup.cmd or an elevated PowerShell.'
        }
        if ($isDryRun) {
            Write-Host 'DRY RUN: nothing will be deleted. Sizes are estimates.' -ForegroundColor Yellow
        }

        $freeBefore = Get-FreeSpace -Drive $drive
        $tasks = @(Get-CleanupTask -SystemDrive $drive -OlderThanUtc $olderThanUtc) |
            Where-Object { $Deep -or -not $_.DeepOnly }

        $results = foreach ($task in $tasks) {
            $result = Resolve-CleanupTask -Task $task -Skip $Skip -IsAdmin $isAdmin
            if ($result.Status -ne 'Pending') {
                $result
            }
            elseif ($PSCmdlet.ShouldProcess($task.Name, 'Clean')) {
                Invoke-ResolvedTask -Task $task -Result $result -Drive $drive -Force ([bool]$Force)
            }
            else {
                $result.Status = if ($isDryRun) { 'DryRun' } else { 'Declined' }
                $result
            }
        }

        $freeAfter = Get-FreeSpace -Drive $drive

        Write-Host ''
        $results | Format-Table Name, Tier, Status, @{ Label = 'Freed'; Expression = { Format-ByteSize $_.FreedBytes } }, Detail -AutoSize -Wrap | Out-Host

        if ($isDryRun) {
            $estimate = ($results | Where-Object { $null -ne $_.FreedBytes } | Measure-Object FreedBytes -Sum).Sum
            Write-Host ("Estimated reclaimable (measurable tasks only): {0}" -f (Format-ByteSize ([long]$estimate))) -ForegroundColor Green
        }
        else {
            Write-Host ('Free space on {0} {1} -> {2} (+{3})' -f $drive, (Format-ByteSize $freeBefore),
                (Format-ByteSize $freeAfter), (Format-ByteSize ([Math]::Max(0, $freeAfter - $freeBefore)))) -ForegroundColor Green
        }

        if (-not $NoReport) { Show-ManualReviewReport }
        if ($logPath) { Write-Host "Log saved to $logPath" }
        if ($PassThru) { $results }
    }
    finally {
        if ($logPath) { Stop-CleanupLog }
    }
}
