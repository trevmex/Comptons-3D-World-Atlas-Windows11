BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $modulePath = Join-Path $repoRoot 'scripts\AtlasInstaller.Core.psm1'
    Import-Module $modulePath -Force
}

Describe 'Atlas installer core helpers' {
    It 'updates an existing INI section without touching neighboring sections' {
        $text = "[Installed]`r`nold=C:\old`r`n`r`n[Sounds]`r`nVolume=1`r`n"
        $result = Set-AtlasSectionBody -Text $text -Section 'Installed' -Body 'new=C:\new'

        $result | Should -Match '(?m)^\[Installed\]\r?$'
        $result | Should -Match '(?m)^new=C:\\new\r?$'
        $result | Should -Match '(?m)^\[Sounds\]\r?$'
        $result | Should -Match '(?m)^Volume=1\r?$'
        $result | Should -Not -Match '(?m)^old='
    }

    It 'replaces an INI value and adds missing values to an existing section' {
        $text = "[Sounds]`r`nVolume=1`r`n"
        $result = Set-AtlasSectionValue -Text $text -Section 'Sounds' -Key 'Volume' -Value '5'
        $result = Set-AtlasSectionValue -Text $result -Section 'Sounds' -Key 'Music' -Value '1'

        @($result -split "`r?`n") | Should -Contain 'Volume=5'
        @($result -split "`r?`n") | Should -Contain 'Music=1'
    }

    It 'creates a missing INI section' {
        $result = Set-AtlasSectionValue -Text "[Version]`r`nName=Atlas`r`n" -Section 'Sounds' -Key 'Volume' -Value '5'

        $result | Should -Match '(?ms)\[Sounds\]\r?\nVolume=5'
    }

    It 'maps a staged path into the final installation tree' {
        $stagedRoot = Join-Path $TestDrive 'staged'
        $finalRoot = Join-Path $TestDrive 'installed'
        $stagedFile = Join-Path $stagedRoot 'Converted Media\AVI\intro.avi'

        $result = Get-AtlasFinalPath -StagedRoot $stagedRoot -FinalRoot $finalRoot -StagedPath $stagedFile

        $result | Should -Be (Join-Path $finalRoot 'Converted Media\AVI\intro.avi')
    }

    It 'rejects a path outside the staging root' {
        $outside = Join-Path $TestDrive 'outside.txt'

        { Get-AtlasFinalPath -StagedRoot (Join-Path $TestDrive 'staged') -FinalRoot (Join-Path $TestDrive 'installed') -StagedPath $outside } |
            Should -Throw '*outside its staging root*'
    }

    It 'verifies the published x86 shim and its hash' {
        $artifact = Join-Path $repoRoot 'build\Wlbrw32.dll'
        $sidecar = Join-Path $repoRoot 'build\Wlbrw32.dll.sha256'
        $info = Test-AtlasShimArtifact -Path $artifact
        $expected = ((Get-Content -LiteralPath $sidecar -Raw).Trim() -split '\s+')[0].ToUpperInvariant()

        $info.IsX86 | Should -BeTrue
        $info.Machine | Should -Be 0x014c
        $info.Hash | Should -Be $expected
    }

    It 'publishes a staged directory and can restore the previous directory' {
        $live = Join-Path $TestDrive 'live'
        $staged = Join-Path $TestDrive 'staged'
        New-Item -ItemType Directory -Path $live, $staged -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $live 'state.txt') -Value 'old'
        Set-Content -LiteralPath (Join-Path $staged 'state.txt') -Value 'new'

        $backup = Publish-AtlasStagedDirectory -StagedPath $staged -LivePath $live -TransactionId 'unit-test'
        Get-Content -LiteralPath (Join-Path $live 'state.txt') | Should -Be 'new'
        Test-Path -LiteralPath $backup | Should -BeTrue

        Restore-AtlasPublishedDirectory -LivePath $live -BackupPath $backup -WasPublished $true
        Get-Content -LiteralPath (Join-Path $live 'state.txt') | Should -Be 'old'
    }

    It 'removes a newly published directory when there was no previous installation' {
        $live = Join-Path $TestDrive 'new-live'
        $staged = Join-Path $TestDrive 'new-staged'
        New-Item -ItemType Directory -Path $staged -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $staged 'state.txt') -Value 'new'

        $backup = Publish-AtlasStagedDirectory -StagedPath $staged -LivePath $live -TransactionId 'unit-test-empty'
        $backup | Should -BeNullOrEmpty
        Restore-AtlasPublishedDirectory -LivePath $live -BackupPath $backup -WasPublished $true
        Test-Path -LiteralPath $live | Should -BeFalse
    }
}
