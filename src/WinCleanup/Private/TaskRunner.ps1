function Resolve-CleanupTask {
    <#
    .SYNOPSIS
        Decides whether a task can run and measures it, without changing anything.
        Returns a result whose Status is 'Pending' when the task is ready to run.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Task,
        [string[]] $Skip = @(),
        [bool] $IsAdmin
    )

    $result = [pscustomobject]@{
        Id         = $Task.Id
        Name       = $Task.Name
        Tier       = $Task.Tier
        Status     = 'Pending'
        FreedBytes = $null
        Detail     = ''
    }

    if ($Skip -contains $Task.Id) {
        $result.Status = 'Skipped'
        $result.Detail = 'Skipped by -Skip.'
        return $result
    }
    if ($Task.RequiresAdmin -and -not $IsAdmin) {
        $result.Status = 'NeedsAdmin'
        return $result
    }

    try {
        if (-not (& $Task.IsApplicable $Task.Data)) {
            $result.Status = 'NothingToDo'
            return $result
        }
        $result.FreedBytes = & $Task.Measure $Task.Data
    }
    catch {
        $result.Status = 'Failed'
        $result.Detail = $_.Exception.Message
    }
    return $result
}

function Invoke-ResolvedTask {
    <#
    .SYNOPSIS
        Runs a task that Resolve-CleanupTask marked as Pending and updates its result.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Task,
        [Parameter(Mandatory)] [pscustomobject] $Result,
        [Parameter(Mandatory)] [string] $Drive,
        [bool] $Force
    )

    if ($Task.Tier -eq 'Confirm' -and -not $Force) {
        $message = '{0} Size: {1}. Continue?' -f $Task.Warning, (Format-ByteSize $Result.FreedBytes)
        if (-not (Read-UserConfirmation -Title $Task.Name -Message $message)) {
            $Result.Status = 'Declined'
            return $Result
        }
    }

    Write-Host "Cleaning: $($Task.Name)..."
    $freeBefore = Get-FreeSpace -Drive $Drive
    try {
        $freed = & $Task.Invoke $Task.Data | Select-Object -Last 1
        if ($freed -isnot [long] -and $freed -isnot [int]) {
            # Tasks like Disk Cleanup cannot report a size, so measure the drive instead.
            $freed = [Math]::Max(0, (Get-FreeSpace -Drive $Drive) - $freeBefore)
        }
        $Result.Status = 'Cleaned'
        $Result.FreedBytes = [long]$freed
    }
    catch {
        $Result.Status = 'Failed'
        $Result.Detail = $_.Exception.Message
    }
    return $Result
}
