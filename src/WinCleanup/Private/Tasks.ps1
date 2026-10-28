# Disk Cleanup handlers that only ever touch disposable system data. Deliberately
# excluded: DownloadsFolder, Recycle Bin, Temporary Files (handled with an age filter),
# Previous Installations and Windows ESD files (needed to roll back or reset Windows),
# Device Driver Packages, Language Pack and User file versions.
$script:DiskCleanupHandlers = @(
    'Active Setup Temp Folders'
    'D3D Shader Cache'
    'Delivery Optimization Files'
    'Downloaded Program Files'
    'Internet Cache Files'
    'Old ChkDsk Files'
    'Setup Log Files'
    'System error memory dump files'
    'System error minidump files'
    'Temporary Setup Files'
    'Thumbnail Cache'
    'Update Cleanup'
    'Upgrade Discarded Files'
    'Windows Error Reporting Files'
    'Windows Upgrade Log Files'
)
$script:DiskCleanupProfile = 4242
$script:VolumeCachesKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'

function New-CleanupTask {
    <#
    .NOTES
        Each scriptblock receives the task's Data hashtable as its only argument. Data is
        used instead of GetNewClosure() because closures lose access to module-private functions.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory object; changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('Auto', 'Confirm')] [string] $Tier,
        [Parameter(Mandatory)] [scriptblock] $Invoke,
        [scriptblock] $Measure = { $null },
        [scriptblock] $IsApplicable = { $true },
        [hashtable] $Data = @{},
        [string] $Warning = '',
        [switch] $RequiresAdmin,
        [switch] $DeepOnly
    )

    [pscustomobject]@{
        Id            = $Id
        Name          = $Name
        Tier          = $Tier
        Warning       = $Warning
        RequiresAdmin = [bool]$RequiresAdmin
        DeepOnly      = [bool]$DeepOnly
        Data          = $Data
        IsApplicable  = $IsApplicable
        Measure       = $Measure
        Invoke        = $Invoke
    }
}

function New-FolderCleanupTask {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory object; changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Path,
        [Parameter(Mandatory)] [datetime] $OlderThanUtc,
        [switch] $RequiresAdmin
    )

    New-CleanupTask -Id $Id -Name $Name -Tier Auto -RequiresAdmin:$RequiresAdmin `
        -Data @{ Path = $Path; OlderThanUtc = $OlderThanUtc } `
        -IsApplicable { param($d) $d.Path -and (Test-Path -LiteralPath $d.Path -PathType Container) } `
        -Measure { param($d) Get-PathSize -Path $d.Path -OlderThanUtc $d.OlderThanUtc } `
        -Invoke { param($d) (Remove-DirectoryContent -Path $d.Path -OlderThanUtc $d.OlderThanUtc -Confirm:$false).FreedBytes }
}

function Get-CleanupTask {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $SystemDrive,
        [Parameter(Mandatory)] [datetime] $OlderThanUtc
    )

    $windowsDir = $env:SystemRoot
    $drive = @{ Drive = $SystemDrive }

    New-FolderCleanupTask -Id 'user-temp' -Name 'User temp files (%TEMP%)' `
        -Path $env:TEMP -OlderThanUtc $OlderThanUtc

    New-FolderCleanupTask -Id 'windows-temp' -Name 'Windows temp files' -RequiresAdmin `
        -Path (Join-Path $windowsDir 'Temp') -OlderThanUtc $OlderThanUtc

    New-CleanupTask -Id 'update-cache' -Name 'Windows Update download cache' -Tier Auto -RequiresAdmin `
        -Data @{ Path = (Join-Path $windowsDir 'SoftwareDistribution\Download') } `
        -IsApplicable { param($d) Test-Path -LiteralPath $d.Path -PathType Container } `
        -Measure { param($d) Get-PathSize -Path $d.Path } `
        -Invoke { param($d) Clear-WindowsUpdateCache -Path $d.Path }

    New-CleanupTask -Id 'disk-cleanup' -Name 'Disk Cleanup (safe categories only)' -Tier Auto -RequiresAdmin `
        -IsApplicable { [bool](Get-Command cleanmgr.exe -ErrorAction SilentlyContinue) } `
        -Invoke { Invoke-DiskCleanup }

    New-CleanupTask -Id 'component-store' -Name 'Component store cleanup (DISM, slow)' -Tier Auto -RequiresAdmin -DeepOnly `
        -Invoke { Invoke-ComponentStoreCleanup }

    New-CleanupTask -Id 'recycle-bin' -Name 'Recycle Bin' -Tier Confirm -Data $drive `
        -Warning 'Everything in the Recycle Bin will be permanently deleted.' `
        -IsApplicable { (Get-RecycleBinSize) -gt 0 } `
        -Measure { Get-RecycleBinSize } `
        -Invoke { param($d) Clear-RecycleBin -DriveLetter $d.Drive.TrimEnd(':') -Force -Confirm:$false -ErrorAction Stop }

    New-CleanupTask -Id 'restore-points' -Name 'Old restore points (keeps the newest)' -Tier Confirm -RequiresAdmin -Data $drive `
        -Warning 'You will not be able to roll Windows back to these older states. Backup tools that rely on shadow copies may also be affected.' `
        -IsApplicable { param($d) @(Get-OldShadowCopy -Drive $d.Drive).Count -gt 0 } `
        -Invoke { param($d) Remove-OldShadowCopy -Drive $d.Drive -Confirm:$false }

    New-CleanupTask -Id 'hibernation' -Name 'Hibernation file (hiberfil.sys)' -Tier Confirm -RequiresAdmin `
        -Data @{ Path = "$SystemDrive\hiberfil.sys" } `
        -Warning 'Hibernate and Fast Startup will be turned off. Re-enable later with: powercfg /hibernate on' `
        -IsApplicable { param($d) Test-Path -LiteralPath $d.Path } `
        -Measure { param($d) (Get-Item -LiteralPath $d.Path -Force).Length } `
        -Invoke { Disable-Hibernation }
}

function Invoke-NativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [string[]] $ArgumentList = @()
    )

    & $FilePath @ArgumentList | Write-Verbose
    if ($LASTEXITCODE -ne 0) {
        throw "'$FilePath $($ArgumentList -join ' ')' failed with exit code $LASTEXITCODE."
    }
}

function Clear-WindowsUpdateCache {
    [CmdletBinding()]
    [OutputType([long])]
    param([Parameter(Mandatory)] [string] $Path)

    $serviceNames = 'wuauserv', 'bits'
    $wasRunning = @(Get-Service -Name $serviceNames -ErrorAction SilentlyContinue |
        Where-Object Status -EQ 'Running' | ForEach-Object Name)

    # Deleting the cache while Windows Update holds it would corrupt an in-flight download.
    Stop-Service -Name $serviceNames -Force -ErrorAction Stop
    try {
        return (Remove-DirectoryContent -Path $Path -Confirm:$false).FreedBytes
    }
    finally {
        if ($wasRunning.Count -gt 0) {
            Start-Service -Name $wasRunning -ErrorAction Continue
        }
    }
}

function Invoke-DiskCleanup {
    [CmdletBinding()]
    param()

    $flag = 'StateFlags{0:D4}' -f $script:DiskCleanupProfile
    foreach ($handler in (Get-ChildItem -LiteralPath $script:VolumeCachesKey)) {
        $enabled = [int]($script:DiskCleanupHandlers -contains $handler.PSChildName) * 2
        Set-ItemProperty -LiteralPath $handler.PSPath -Name $flag -Value $enabled -Type DWord
    }

    $process = Start-Process -FilePath 'cleanmgr.exe' -ArgumentList "/sagerun:$($script:DiskCleanupProfile)" `
        -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "cleanmgr.exe exited with code $($process.ExitCode)."
    }
}

function Invoke-ComponentStoreCleanup {
    [CmdletBinding()]
    param()

    Invoke-NativeCommand -FilePath 'dism.exe' -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/NoRestart'
}

function Get-RecycleBinSize {
    [CmdletBinding()]
    [OutputType([long])]
    param()

    $recycleBinFolderId = 10
    $shell = New-Object -ComObject Shell.Application
    try {
        [long] $total = 0
        foreach ($item in $shell.NameSpace($recycleBinFolderId).Items()) {
            $total += $item.Size
        }
        return $total
    }
    finally {
        $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

function Get-OldShadowCopy {
    [CmdletBinding()]
    [OutputType([CimInstance])]
    param([Parameter(Mandatory)] [string] $Drive)

    $volume = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter = '$Drive'"
    if (-not $volume) { return }

    Get-CimInstance -ClassName Win32_ShadowCopy |
        Where-Object VolumeName -EQ $volume.DeviceID |
        Sort-Object InstallDate -Descending |
        Select-Object -Skip 1
}

function Remove-OldShadowCopy {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Drive)

    foreach ($shadow in (Get-OldShadowCopy -Drive $Drive)) {
        if ($PSCmdlet.ShouldProcess($shadow.InstallDate, 'Delete restore point')) {
            Remove-CimInstance -InputObject $shadow -ErrorAction Stop
        }
    }
}

function Disable-Hibernation {
    [CmdletBinding()]
    param()

    Invoke-NativeCommand -FilePath 'powercfg.exe' -ArgumentList '/hibernate', 'off'
}
