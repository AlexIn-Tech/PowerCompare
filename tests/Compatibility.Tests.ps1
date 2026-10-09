BeforeAll { $repo=Split-Path $PSScriptRoot -Parent }
Describe 'Windows PowerShell source compatibility' {
    It 'encodes Unicode PowerShell source with a BOM for Windows PowerShell 5.1' {
        $files=@(Get-ChildItem -LiteralPath (Join-Path $repo 'src') -Recurse -File | Where-Object Extension -In @('.ps1','.psm1','.psd1'))
        $files += Get-Item -LiteralPath (Join-Path $repo 'PowerCompare.ps1')
        foreach ($file in $files) {
            $bytes=[IO.File]::ReadAllBytes($file.FullName)
            if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) {
                $bytes[0] | Should -Be 239 -Because $file.FullName
                $bytes[1] | Should -Be 187; $bytes[2] | Should -Be 191
            }
        }
    }
}
