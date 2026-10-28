function Test-IsWindowsHost {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return $env:OS -eq 'Windows_NT'
}

function Test-IsAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SystemDrive {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:SystemDrive) { return $env:SystemDrive }
    return 'C:'
}

function Get-FreeSpace {
    [CmdletBinding()]
    [OutputType([long])]
    param([Parameter(Mandatory)] [string] $Drive)

    return [IO.DriveInfo]::new($Drive).AvailableFreeSpace
}

function Read-UserConfirmation {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [string] $Message
    )

    $choices = [Management.Automation.Host.ChoiceDescription[]]@(
        [Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Clean this item.')
        [Management.Automation.Host.ChoiceDescription]::new('&No', 'Leave this item untouched.')
    )
    return $Host.UI.PromptForChoice($Title, $Message, $choices, 1) -eq 0
}

function Start-CleanupLog {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Directory)

    if (-not $PSCmdlet.ShouldProcess($Directory, 'Write cleanup log')) { return $null }

    $null = New-Item -ItemType Directory -Path $Directory -Force
    $path = Join-Path $Directory ('cleanup-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
    $null = Start-Transcript -Path $path -WhatIf:$false
    return $path
}

function Stop-CleanupLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only stops the transcript started by Start-CleanupLog.')]
    [CmdletBinding()]
    param()

    try { $null = Stop-Transcript } catch { Write-Verbose 'No transcript was running.' }
}
