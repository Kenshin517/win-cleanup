function Get-UserFolderPath {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $known = 'Desktop', 'MyDocuments', 'MyPictures', 'MyVideos', 'MyMusic' |
        ForEach-Object { [Environment]::GetFolderPath($_) }
    $downloads = Join-Path $env:USERPROFILE 'Downloads'

    @($known) + $downloads |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } |
        Select-Object -Unique
}

function Get-LargeUserFile {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string[]] $Path = (Get-UserFolderPath),
        [long] $MinimumBytes = 100MB,
        [int] $Top = 15
    )

    $Path |
        ForEach-Object { Get-RegularFile -Path $_ } |
        Where-Object { $_.Length -ge $MinimumBytes -and -not (Test-IsCloudPlaceholder -File $_) } |
        Sort-Object Length -Descending |
        Select-Object -First $Top |
        ForEach-Object {
            [pscustomobject]@{
                Size         = Format-ByteSize $_.Length
                LastModified = $_.LastWriteTime.ToString('yyyy-MM-dd')
                Path         = $_.FullName
            }
        }
}

function Get-InstalledAppSize {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param([int] $Top = 15)

    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    # EstimatedSize is reported by the installer in KB and is missing for many apps.
    Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.EstimatedSize -and $_.SystemComponent -ne 1 } |
        Sort-Object DisplayName -Unique |
        Sort-Object EstimatedSize -Descending |
        Select-Object -First $Top |
        ForEach-Object {
            [pscustomobject]@{
                Size      = Format-ByteSize ([long]$_.EstimatedSize * 1KB)
                Name      = $_.DisplayName
                Publisher = $_.Publisher
            }
        }
}

function Show-ManualReviewReport {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '=== Manual review (nothing below was deleted) ===' -ForegroundColor Cyan
    Write-Host 'Largest files in your personal folders. Move or delete the ones you no longer need:'
    $files = @(Get-LargeUserFile)
    if ($files.Count -eq 0) { Write-Host '  No files over 100 MB found.' }
    else { $files | Format-Table -AutoSize -Wrap | Out-Host }

    Write-Host 'Largest installed apps. Uninstall unused ones from Settings > Apps:'
    Write-Host '  (Leave Microsoft and laptop-vendor drivers/utilities alone unless you know what they do.)'
    $apps = @(Get-InstalledAppSize)
    if ($apps.Count -eq 0) { Write-Host '  No size information available.' }
    else { $apps | Format-Table -AutoSize | Out-Host }
}
