BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\WinCleanup\WinCleanup.psd1') -Force

    function New-TestFile {
        param([string] $Path, [int] $Bytes, [int] $AgeHours = 48)

        $null = New-Item -ItemType Directory -Path (Split-Path $Path) -Force
        [IO.File]::WriteAllBytes($Path, [byte[]]::new($Bytes))
        (Get-Item $Path).LastWriteTimeUtc = [datetime]::UtcNow.AddHours(-$AgeHours)
    }
}

Describe 'Format-ByteSize' {
    It 'formats <Bytes> as <Expected>' -TestCases @(
        @{ Bytes = 0; Expected = '0 B' }
        @{ Bytes = 512; Expected = '512 B' }
        @{ Bytes = 1536; Expected = '1.50 KB' }
        @{ Bytes = 5GB; Expected = '5.00 GB' }
        @{ Bytes = -2MB; Expected = '-2.00 MB' }
    ) {
        InModuleScope WinCleanup -Parameters $_ {
            Format-ByteSize $Bytes | Should -Be $Expected
        }
    }

    It 'returns "unknown" for $null' {
        InModuleScope WinCleanup { Format-ByteSize $null | Should -Be 'unknown' }
    }
}

Describe 'Get-PathSize' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-TestFile -Path (Join-Path $root 'a.tmp') -Bytes 100
        New-TestFile -Path (Join-Path $root 'sub/b.tmp') -Bytes 200
        New-TestFile -Path (Join-Path $root 'fresh.tmp') -Bytes 50 -AgeHours 0
    }

    It 'sums every file recursively' {
        InModuleScope WinCleanup -Parameters @{ Root = $root } {
            Get-PathSize -Path $Root | Should -Be 350
        }
    }

    It 'only counts files older than the cutoff' {
        InModuleScope WinCleanup -Parameters @{ Root = $root } {
            Get-PathSize -Path $Root -OlderThanUtc ([datetime]::UtcNow.AddHours(-24)) | Should -Be 300
        }
    }

    It 'returns 0 for a missing path' {
        InModuleScope WinCleanup { Get-PathSize -Path (Join-Path $TestDrive 'missing') | Should -Be 0 }
    }

    It 'does not follow symbolic links into other folders' {
        $outside = Join-Path $TestDrive ([guid]::NewGuid())
        New-TestFile -Path (Join-Path $outside 'important.doc') -Bytes 1000
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $root 'link') -Target $outside

        InModuleScope WinCleanup -Parameters @{ Root = $root } {
            Get-PathSize -Path $Root | Should -Be 350
        }
    }
}

Describe 'Remove-DirectoryContent' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-TestFile -Path (Join-Path $root 'old.tmp') -Bytes 100
        New-TestFile -Path (Join-Path $root 'nested/old.tmp') -Bytes 200
        New-TestFile -Path (Join-Path $root 'fresh.tmp') -Bytes 50 -AgeHours 0
        (Get-Item (Join-Path $root 'nested')).CreationTimeUtc = [datetime]::UtcNow.AddHours(-48)
        $cutoff = [datetime]::UtcNow.AddHours(-24)
    }

    It 'deletes old files, keeps fresh ones, and reports bytes freed' {
        $result = InModuleScope WinCleanup -Parameters @{ Root = $root; Cutoff = $cutoff } {
            Remove-DirectoryContent -Path $Root -OlderThanUtc $Cutoff -Confirm:$false
        }

        $result.FreedBytes | Should -Be 300
        $result.Deleted | Should -Be 2
        Join-Path $root 'old.tmp' | Should -Not -Exist
        Join-Path $root 'fresh.tmp' | Should -Exist
    }

    It 'removes emptied old subfolders but keeps the root folder' {
        InModuleScope WinCleanup -Parameters @{ Root = $root; Cutoff = $cutoff } {
            $null = Remove-DirectoryContent -Path $Root -OlderThanUtc $Cutoff -Confirm:$false
        }

        Join-Path $root 'nested' | Should -Not -Exist
        $root | Should -Exist
    }

    It 'never deletes files behind a symbolic link' {
        $outside = Join-Path $TestDrive ([guid]::NewGuid())
        $precious = Join-Path $outside 'thesis.docx'
        New-TestFile -Path $precious -Bytes 1000
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $root 'link') -Target $outside

        InModuleScope WinCleanup -Parameters @{ Root = $root } {
            $null = Remove-DirectoryContent -Path $Root -Confirm:$false
        }

        $precious | Should -Exist
    }

    It 'deletes nothing with -WhatIf' {
        $result = InModuleScope WinCleanup -Parameters @{ Root = $root } {
            Remove-DirectoryContent -Path $Root -WhatIf
        }

        $result.Deleted | Should -Be 0
        Join-Path $root 'old.tmp' | Should -Exist
    }

    It 'returns an empty result for a missing path' {
        $result = InModuleScope WinCleanup {
            Remove-DirectoryContent -Path (Join-Path $TestDrive 'missing') -Confirm:$false
        }
        $result.FreedBytes | Should -Be 0
    }
}
