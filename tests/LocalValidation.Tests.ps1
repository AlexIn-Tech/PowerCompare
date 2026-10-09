BeforeAll {
    $runner = Join-Path $PSScriptRoot '../scripts/Validate.ps1'
    $engine = (Get-Process -Id $PID).Path
}
Describe 'Local validation exit contract' {
    It 'returns zero for passing tests and clean source analysis' {
        $fixture = Join-Path $TestDrive 'pass.Tests.ps1'
        Set-Content -LiteralPath $fixture -Value "Describe 'fixture' { It 'passes' { 1 | Should -Be 1 } }"
        & $engine -NoProfile -File $runner -Path $fixture -ResultsDirectory (Join-Path $TestDrive 'pass') *> $null
        $LASTEXITCODE | Should -Be 0
    }
    It 'returns nonzero when the tests fail' {
        $fixture = Join-Path $TestDrive 'fail.Tests.ps1'
        Set-Content -LiteralPath $fixture -Value "Describe 'fixture' { It 'fails' { 1 | Should -Be 2 } }"
        & $engine -NoProfile -File $runner -Path $fixture -ResultsDirectory (Join-Path $TestDrive 'fail') *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
}
