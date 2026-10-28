Set-StrictMode -Version Latest

foreach ($folder in 'Private', 'Public') {
    Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' |
        ForEach-Object { . $_.FullName }
}

Export-ModuleMember -Function 'Invoke-WinCleanup'
