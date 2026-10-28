BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\WinCleanup\WinCleanup.psd1') -Force
}

Describe 'Resolve-CleanupTask' {
    BeforeEach {
        $task = InModuleScope WinCleanup {
            New-CleanupTask -Id 'fake' -Name 'Fake task' -Tier Auto -Measure { 1000 } -Invoke { }
        }
    }

    It 'marks a runnable task as Pending with its estimated size' {
        $result = InModuleScope WinCleanup -Parameters @{ Task = $task } {
            Resolve-CleanupTask -Task $Task -IsAdmin $true
        }
        $result.Status | Should -Be 'Pending'
        $result.FreedBytes | Should -Be 1000
    }

    It 'skips tasks listed in -Skip' {
        $result = InModuleScope WinCleanup -Parameters @{ Task = $task } {
            Resolve-CleanupTask -Task $Task -Skip 'fake' -IsAdmin $true
        }
        $result.Status | Should -Be 'Skipped'
    }

    It 'refuses admin-only tasks without elevation' {
        $task.RequiresAdmin = $true
        $result = InModuleScope WinCleanup -Parameters @{ Task = $task } {
            Resolve-CleanupTask -Task $Task -IsAdmin $false
        }
        $result.Status | Should -Be 'NeedsAdmin'
    }

    It 'reports NothingToDo when the task is not applicable' {
        $task.IsApplicable = { $false }
        $result = InModuleScope WinCleanup -Parameters @{ Task = $task } {
            Resolve-CleanupTask -Task $Task -IsAdmin $true
        }
        $result.Status | Should -Be 'NothingToDo'
    }

    It 'reports Failed when measuring throws' {
        $task.Measure = { throw 'access denied' }
        $result = InModuleScope WinCleanup -Parameters @{ Task = $task } {
            Resolve-CleanupTask -Task $Task -IsAdmin $true
        }
        $result.Status | Should -Be 'Failed'
        $result.Detail | Should -Be 'access denied'
    }
}

Describe 'Invoke-ResolvedTask' {
    BeforeEach {
        $task = InModuleScope WinCleanup {
            $script:fakeInvoked = $false
            New-CleanupTask -Id 'fake' -Name 'Fake task' -Tier Auto -Invoke { $script:fakeInvoked = $true; [long]900 }
        }
        $pending = [pscustomobject]@{ Status = 'Pending'; FreedBytes = 1000; Detail = '' }
        Mock -ModuleName WinCleanup Get-FreeSpace { 0 }
        Mock -ModuleName WinCleanup Write-Host { }
    }

    It 'runs the task and records bytes freed' {
        $result = InModuleScope WinCleanup -Parameters @{ Task = $task; Result = $pending } {
            Invoke-ResolvedTask -Task $Task -Result $Result -Drive 'C:'
        }
        $result.Status | Should -Be 'Cleaned'
        $result.FreedBytes | Should -Be 900
    }

    It 'falls back to the free-space delta when a task reports no size' {
        $task.Invoke = { }
        $script:calls = 0
        Mock -ModuleName WinCleanup Get-FreeSpace { if ($script:calls++ -eq 0) { 1000 } else { 4000 } }

        $result = InModuleScope WinCleanup -Parameters @{ Task = $task; Result = $pending } {
            Invoke-ResolvedTask -Task $Task -Result $Result -Drive 'C:'
        }
        $result.FreedBytes | Should -Be 3000
    }

    It 'captures failures instead of aborting the run' {
        $task.Invoke = { throw 'boom' }
        $result = InModuleScope WinCleanup -Parameters @{ Task = $task; Result = $pending } {
            Invoke-ResolvedTask -Task $Task -Result $Result -Drive 'C:'
        }
        $result.Status | Should -Be 'Failed'
        $result.Detail | Should -Be 'boom'
    }

    Context 'Confirm tier' {
        BeforeEach {
            $task.Tier = 'Confirm'
            Mock -ModuleName WinCleanup Read-UserConfirmation { $false }
        }

        It 'does not run when the user declines' {
            $result = InModuleScope WinCleanup -Parameters @{ Task = $task; Result = $pending } {
                Invoke-ResolvedTask -Task $Task -Result $Result -Drive 'C:'
                $script:fakeInvoked | Should -BeFalse
            }
            $result.Status | Should -Be 'Declined'
        }

        It 'runs without asking when -Force is set' {
            $result = InModuleScope WinCleanup -Parameters @{ Task = $task; Result = $pending } {
                Invoke-ResolvedTask -Task $Task -Result $Result -Drive 'C:' -Force $true
            }
            $result.Status | Should -Be 'Cleaned'
            Should -Invoke -ModuleName WinCleanup Read-UserConfirmation -Times 0 -Exactly
        }
    }
}

Describe 'Get-CleanupTask' {
    BeforeAll {
        $env:SystemRoot = if ($env:SystemRoot) { $env:SystemRoot } else { Join-Path $TestDrive 'Windows' }
        $env:TEMP = if ($env:TEMP) { $env:TEMP } else { Join-Path $TestDrive 'Temp' }
        $tasks = InModuleScope WinCleanup { Get-CleanupTask -SystemDrive 'C:' -OlderThanUtc ([datetime]::UtcNow) }
    }

    It 'gives every task a unique id' {
        $ids = $tasks.Id
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'keeps -Skip validation in sync with the task ids' {
        $allowed = (Get-Command Invoke-WinCleanup).Parameters['Skip'].Attributes |
            Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] } |
            ForEach-Object ValidValues
        $tasks.Id | Sort-Object | Should -Be ($allowed | Sort-Object)
    }

    It 'asks before every task that destroys user-recoverable data' {
        ($tasks | Where-Object Id -In 'recycle-bin', 'restore-points', 'hibernation').Tier |
            Should -Not -Contain 'Auto'
    }
}

Describe 'Disk Cleanup handler whitelist' {
    It 'never includes <Handler>' -TestCases @(
        @{ Handler = 'DownloadsFolder' }
        @{ Handler = 'Recycle Bin' }
        @{ Handler = 'Previous Installations' }
        @{ Handler = 'Windows ESD installation files' }
        @{ Handler = 'User file versions' }
    ) {
        InModuleScope WinCleanup -Parameters @{ Handler = $Handler } {
            $script:DiskCleanupHandlers | Should -Not -Contain $Handler
        }
    }
}

Describe 'Invoke-WinCleanup' {
    BeforeEach {
        Mock -ModuleName WinCleanup Test-IsWindowsHost { $true }
        Mock -ModuleName WinCleanup Test-IsAdministrator { $true }
        Mock -ModuleName WinCleanup Get-SystemDrive { 'C:' }
        Mock -ModuleName WinCleanup Get-FreeSpace { 10GB }
        Mock -ModuleName WinCleanup Start-CleanupLog { $null }
        Mock -ModuleName WinCleanup Show-ManualReviewReport { }
        Mock -ModuleName WinCleanup Write-Host { }
        Mock -ModuleName WinCleanup Out-Host { }
        Mock -ModuleName WinCleanup Read-UserConfirmation { $true }
        $fakeTasks = InModuleScope WinCleanup {
            New-CleanupTask -Id 'auto' -Name 'Auto' -Tier Auto -Measure { 10 } -Invoke { $script:ran += 'auto'; [long]10 }
            New-CleanupTask -Id 'deep' -Name 'Deep' -Tier Auto -DeepOnly -Invoke { $script:ran += 'deep'; [long]5 }
        }
        Mock -ModuleName WinCleanup Get-CleanupTask { $fakeTasks }
        InModuleScope WinCleanup { $script:ran = @() }
    }

    It 'refuses to run outside Windows' {
        Mock -ModuleName WinCleanup Test-IsWindowsHost { $false }
        { Invoke-WinCleanup -NoReport } | Should -Throw '*only runs on Windows*'
    }

    It 'changes nothing with -WhatIf' {
        $results = Invoke-WinCleanup -WhatIf -PassThru -NoReport
        InModuleScope WinCleanup { $script:ran | Should -BeNullOrEmpty }
        $results.Status | Should -Not -Contain 'Cleaned'
    }

    It 'skips deep-only tasks unless -Deep is given' {
        $null = Invoke-WinCleanup -NoReport -Confirm:$false
        InModuleScope WinCleanup { $script:ran | Should -Be @('auto') }
    }

    It 'runs deep-only tasks with -Deep' {
        $null = Invoke-WinCleanup -Deep -NoReport -Confirm:$false
        InModuleScope WinCleanup { $script:ran | Should -Be @('auto', 'deep') }
    }
}
