<#
.SYNOPSIS
    Entry point. Imports the module and forwards every argument to Invoke-WinCleanup.
.EXAMPLE
    .\cleanup.ps1 -WhatIf
.EXAMPLE
    .\cleanup.ps1 -Skip hibernation -Deep
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = '-WhatIf/-Confirm are forwarded to Invoke-WinCleanup, which calls ShouldProcess.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [int] $TempMinAgeHours = 24,
    [switch] $Deep,
    [string[]] $Skip = @(),
    [switch] $Force,
    [switch] $NoReport,
    [string] $LogDirectory,
    [switch] $PassThru
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\WinCleanup\WinCleanup.psd1') -Force
Invoke-WinCleanup @PSBoundParameters
