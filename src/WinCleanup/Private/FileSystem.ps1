# OneDrive "online-only" placeholders report a full Length but use no local disk space.
$script:RecallOnDataAccess = 0x400000

function Test-IsReparsePoint {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [IO.FileSystemInfo] $Item)

    return [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Test-IsCloudPlaceholder {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [IO.FileInfo] $File)

    $mask = [int][IO.FileAttributes]::Offline -bor $script:RecallOnDataAccess
    return [bool]([int]$File.Attributes -band $mask)
}

function Get-DirectoryEntry {
    [CmdletBinding()]
    [OutputType([IO.FileSystemInfo])]
    param([Parameter(Mandatory)] [IO.DirectoryInfo] $Directory)

    try {
        $Directory.GetFileSystemInfos()
    }
    catch [UnauthorizedAccessException], [IO.IOException] {
        Write-Verbose "Cannot read '$($Directory.FullName)': $($_.Exception.Message)"
    }
}

function Get-RegularFile {
    <#
    .SYNOPSIS
        Enumerates files under a directory without ever following symlinks or junctions.
    .NOTES
        Recursing through a junction (e.g. one pointing at a user's Documents folder)
        is how naive temp cleaners destroy real data, so reparse points are never entered.
    #>
    [CmdletBinding()]
    [OutputType([IO.FileInfo])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [datetime] $OlderThanUtc = [datetime]::MaxValue
    )

    $root = [IO.DirectoryInfo]::new($Path)
    if (-not $root.Exists) { return }

    $pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $pending.Push($root)

    while ($pending.Count -gt 0) {
        foreach ($entry in (Get-DirectoryEntry -Directory $pending.Pop())) {
            if (Test-IsReparsePoint -Item $entry) { continue }

            if ($entry -is [IO.DirectoryInfo]) {
                $pending.Push($entry)
            }
            elseif ($entry.LastWriteTimeUtc -lt $OlderThanUtc) {
                $entry
            }
        }
    }
}

function Get-PathSize {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [datetime] $OlderThanUtc = [datetime]::MaxValue
    )

    [long] $total = 0
    foreach ($file in (Get-RegularFile -Path $Path -OlderThanUtc $OlderThanUtc)) {
        $total += $file.Length
    }
    return $total
}

function Remove-DirectoryContent {
    <#
    .SYNOPSIS
        Deletes the contents of a directory (never the directory itself), skipping
        files that are in use, newer than the cutoff, or behind a reparse point.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [datetime] $OlderThanUtc = [datetime]::MaxValue
    )

    $result = [pscustomobject]@{ FreedBytes = [long]0; Deleted = 0; Skipped = 0 }
    $root = [IO.DirectoryInfo]::new($Path)
    if (-not $root.Exists -or -not $PSCmdlet.ShouldProcess($root.FullName, 'Delete contents')) {
        return $result
    }

    Remove-DirectoryContentCore -Directory $root -OlderThanUtc $OlderThanUtc -Result $result
    return $result
}

function Remove-DirectoryContentCore {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal helper; the caller Remove-DirectoryContent is the ShouldProcess gate.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [IO.DirectoryInfo] $Directory,
        [Parameter(Mandatory)] [datetime] $OlderThanUtc,
        [Parameter(Mandatory)] [pscustomobject] $Result
    )

    foreach ($entry in (Get-DirectoryEntry -Directory $Directory)) {
        if (Test-IsReparsePoint -Item $entry) {
            $Result.Skipped++
            continue
        }

        if ($entry -is [IO.DirectoryInfo]) {
            Remove-DirectoryContentCore -Directory $entry -OlderThanUtc $OlderThanUtc -Result $Result
            Remove-EmptyDirectory -Directory $entry -OlderThanUtc $OlderThanUtc
            continue
        }

        if ($entry.LastWriteTimeUtc -ge $OlderThanUtc) {
            $Result.Skipped++
            continue
        }

        $size = $entry.Length
        try {
            if ($entry.IsReadOnly) { $entry.IsReadOnly = $false }
            $entry.Delete()
            $Result.FreedBytes += $size
            $Result.Deleted++
        }
        catch {
            Write-Verbose "Skipped '$($entry.FullName)': $($_.Exception.Message)"
            $Result.Skipped++
        }
    }
}

function Remove-EmptyDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal helper; the caller Remove-DirectoryContent is the ShouldProcess gate.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [IO.DirectoryInfo] $Directory,
        [Parameter(Mandatory)] [datetime] $OlderThanUtc
    )

    # CreationTime is used because deleting children bumps LastWriteTime to "now".
    if ($Directory.CreationTimeUtc -ge $OlderThanUtc) { return }

    try {
        $Directory.Refresh()
        if ($Directory.Exists -and $Directory.GetFileSystemInfos().Count -eq 0) {
            $Directory.Delete($false)
        }
    }
    catch {
        Write-Verbose "Kept directory '$($Directory.FullName)': $($_.Exception.Message)"
    }
}
