BeforeAll {
    $launcher = Join-Path $PSScriptRoot '../PowerCompare.ps1'
    $engine = (Get-Process -Id $PID).Path
}
Describe 'Application launcher' {
    It 'supports headless folder comparison without GUI dependencies' {
        $left = Join-Path $TestDrive 'left'; $right = Join-Path $TestDrive 'right'
        [void][IO.Directory]::CreateDirectory($left); [void][IO.Directory]::CreateDirectory($right)
        [IO.File]::WriteAllText((Join-Path $left 'a'), 'x')
        $output = & $engine -NoProfile -File $launcher -NoGui -LeftPath $left -RightPath $right 2>$null
        $LASTEXITCODE | Should -Be 0
        $rows = ($output -join "`n") | ConvertFrom-Json
        $rows[0].Status | Should -Be 'LeftOnly'
    }
    It 'fails explicitly for missing comparison roots' {
        & $engine -NoProfile -File $launcher -NoGui -LeftPath (Join-Path $TestDrive 'missing') -RightPath $TestDrive *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
    It 'explains the Windows requirement on non-Windows hosts' {
        if ([Environment]::OSVersion.Platform -eq 'Win32NT') { Set-ItResult -Skipped -Because 'Non-Windows platform check'; return }
        $output = & $engine -NoProfile -File $launcher 2>&1
        ($output | Out-String) | Should -Match 'WPF.*Windows'
        $LASTEXITCODE | Should -Not -Be 0
    }
}
