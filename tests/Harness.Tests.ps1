BeforeAll {
    $runner = Join-Path $PSScriptRoot '../scripts/Test.ps1'
    $engine = (Get-Process -Id $PID).Path
}
Describe 'Pester test runner exit contract' {
    It 'returns zero for a passing suite' {
        $fixture = Join-Path $TestDrive 'pass.Tests.ps1'
        Set-Content -LiteralPath $fixture -Value "Describe 'fixture' { It 'passes' { 1 | Should -Be 1 } }"
        & $engine -NoProfile -File $runner -Path $fixture -ResultsPath (Join-Path $TestDrive 'pass.xml') *> $null
        $LASTEXITCODE | Should -Be 0
    }
    It 'returns nonzero for a failing suite' {
        $fixture = Join-Path $TestDrive 'fail.Tests.ps1'
        Set-Content -LiteralPath $fixture -Value "Describe 'fixture' { It 'fails' { 1 | Should -Be 2 } }"
        & $engine -NoProfile -File $runner -Path $fixture -ResultsPath (Join-Path $TestDrive 'fail.xml') *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
    It 'returns nonzero for discovery errors' {
        $fixture = Join-Path $TestDrive 'broken.Tests.ps1'
        Set-Content -LiteralPath $fixture -Value "throw 'discovery failure'"
        & $engine -NoProfile -File $runner -Path $fixture -ResultsPath (Join-Path $TestDrive 'broken.xml') *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
    It 'returns nonzero when no tests are discovered' {
        $fixture = Join-Path $TestDrive 'empty.Tests.ps1'
        Set-Content -LiteralPath $fixture -Value '# no tests'
        & $engine -NoProfile -File $runner -Path $fixture -ResultsPath (Join-Path $TestDrive 'empty.xml') *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
}
