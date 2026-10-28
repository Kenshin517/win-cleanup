@{
    RootModule           = 'WinCleanup.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '6f1f4c3e-2b8a-4d7e-9a51-3c0d8e7b2f14'
    Author               = 'Sandy'
    Copyright            = '(c) Sandy. MIT License.'
    Description          = 'Safely frees space on the Windows system drive: temp files, update cache, Disk Cleanup, with dry-run, confirmations and a manual review report.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Invoke-WinCleanup')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('Windows', 'Cleanup', 'DiskSpace', 'Maintenance')
            LicenseUri = 'https://opensource.org/licenses/MIT'
        }
    }
}
