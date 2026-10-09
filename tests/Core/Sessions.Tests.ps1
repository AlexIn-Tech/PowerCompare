BeforeAll { Import-Module (Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1') -Force }
Describe 'Sessions and comparison reports' {
    It 'round trips validated comparison settings without saving secrets' {
        $path=Join-Path $TestDrive 'session.json'
        $session=New-PCSession -LeftPath $TestDrive -RightPath $TestDrive -Mode Content -Include '*.txt' -Exclude '*.tmp'
        Save-PCSession $session $path
        $restored=Import-PCSession $path
        $restored.Mode | Should -Be 'Content'; $restored.Include | Should -Contain '*.txt'
        (Get-Content -LiteralPath $path -Raw) | Should -Not -Match 'password|token|secret'
    }
    It 'rejects unsupported versions and unknown fields' {
        $path=Join-Path $TestDrive 'invalid.json'
        [IO.File]::WriteAllText($path,'{"Version":99,"LeftPath":"x","RightPath":"y","Mode":"Content"}')
        { Import-PCSession $path } | Should -Throw
        [IO.File]::WriteAllText($path,'{"Version":1,"LeftPath":"x","RightPath":"y","Mode":"Content","Password":"secret"}')
        { Import-PCSession $path } | Should -Throw
    }
    It 'validates mode and mask types before accepting session data' {
        $path=Join-Path $TestDrive 'bad.json'
        [IO.File]::WriteAllText($path,'{"Version":1,"LeftPath":"x","RightPath":"y","Mode":"Unexpected","Include":{}}')
        { Import-PCSession $path } | Should -Throw
    }
    It 'exports valid JSON arrays for zero and one comparison rows' {
        $path=Join-Path $TestDrive 'report.json'
        Export-PCComparisonReport -Rows @() -Path $path -Format Json
        ([IO.File]::ReadAllText($path) -replace '\s', '') | Should -Be '[]'
        Export-PCComparisonReport -Rows @([pscustomobject]@{RelativePath='a';Status='Different'}) -Path $path -Format Json
        $decoded=@(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
        $decoded.Count | Should -Be 1; $decoded[0].Status | Should -Be 'Different'
    }
    It 'escapes HTML reports instead of rendering file names as markup' {
        $path=Join-Path $TestDrive 'report.html'
        Export-PCComparisonReport -Rows @([pscustomobject]@{RelativePath='<script>alert(1)</script>';Status='LeftOnly'}) -Path $path -Format Html
        $html=[IO.File]::ReadAllText($path)
        $html | Should -Match '&lt;script&gt;'; $html | Should -Not -Match '<script>'
    }
    It 'exports literal filenames and comma-containing values as CSV' {
        $path=Join-Path $TestDrive '[report].csv'
        Export-PCComparisonReport -Rows @([pscustomobject]@{RelativePath='a,b';Status='LeftOnly'}) -Path $path -Format Csv
        (Import-Csv -LiteralPath $path).RelativePath | Should -Be 'a,b'
    }
}
