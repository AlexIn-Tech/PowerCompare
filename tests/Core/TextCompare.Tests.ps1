BeforeAll { Import-Module (Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1') -Force }
Describe 'Text alignment' {
    It 'compares empty inputs without phantom lines' {
        $result = Compare-PCText -LeftText '' -RightText ''
        $result.Rows.Count | Should -Be 0; $result.HasDifferences | Should -BeFalse
    }
    It 'aligns inserted lines and retains line numbers' {
        $result = Compare-PCText -LeftText "a`nb" -RightText "a`nx`nb"
        $result.Rows.Status -join ',' | Should -Be 'Equal,Added,Equal'
        $result.Rows[1].LeftLineNumber | Should -BeNullOrEmpty
        $result.Rows[2].LeftLineNumber | Should -Be 2; $result.Rows[2].RightLineNumber | Should -Be 3
    }
    It 'aligns deleted lines' {
        (Compare-PCText -LeftText "a`nx`nb" -RightText "a`nb").Rows.Status -join ',' | Should -Be 'Equal,Removed,Equal'
    }
    It 'pairs replacements and marks only the changed characters' {
        $row = (Compare-PCText -LeftText 'abcXdef' -RightText 'abcYdef').Rows[0]
        $row.Status | Should -Be 'Changed'; $row.LeftChangeStart | Should -Be 3; $row.LeftChangeLength | Should -Be 1
    }
    It 'handles repeated lines deterministically' {
        $result = Compare-PCText -LeftText "a`nb`na" -RightText "a`na"
        $result.Rows.Status -join ',' | Should -Be 'Equal,Removed,Equal'
    }
    It 'detects final-newline and newline-style changes' {
        (Compare-PCText -LeftText 'a' -RightText "a`n").HasDifferences | Should -BeTrue
        (Compare-PCText -LeftText "a`r`nb" -RightText "a`nb").HasDifferences | Should -BeTrue
    }
    It 'supports explicit whitespace and case significance rules' {
        (Compare-PCText -LeftText ' A B ' -RightText 'ab' -IgnoreWhitespace -IgnoreCase).HasDifferences | Should -BeFalse
    }
    It 'reports a bounded alignment fallback without hiding changes' {
        $result = Compare-PCText -LeftText "a`nb`nc" -RightText "x`ny`nz" -MaxAlignmentCells 4
        $result.Alignment | Should -Be 'Limited'; $result.HasDifferences | Should -BeTrue
    }
}
Describe 'Text document detection' {
    It 'detects UTF-16 BOM input without misclassifying its null bytes' {
        $path = Join-Path $TestDrive 'utf16.txt'; [IO.File]::WriteAllText($path, 'hello', [Text.Encoding]::Unicode)
        $doc = Get-PCTextDocument $path
        $doc.Kind | Should -Be 'Text'; $doc.Text | Should -Be 'hello'; $doc.HasBom | Should -BeTrue
    }
    It 'detects binary inputs and prevents text comparison' {
        $path = Join-Path $TestDrive 'binary'; [IO.File]::WriteAllBytes($path, [byte[]]@(0,1,2,3))
        (Get-PCTextDocument $path).Kind | Should -Be 'Binary'
        (Compare-PCTextFile $path $path).Kind | Should -Be 'Binary'
    }
    It 'rejects malformed UTF-8 instead of silently replacing bytes' {
        $path = Join-Path $TestDrive 'invalid'; [IO.File]::WriteAllBytes($path, [byte[]]@(255,254,255))
        (Get-PCTextDocument $path).Kind | Should -Not -Be 'Text'
    }
    It 'rejects oversized previews without reading them as text' {
        $path = Join-Path $TestDrive 'large'; [IO.File]::WriteAllText($path, '12345678')
        (Get-PCTextDocument $path -MaxBytes 4).Kind | Should -Be 'TooLarge'
    }
    It 'compares Unicode file contents through the file API' {
        $left = Join-Path $TestDrive 'l.txt'; $right = Join-Path $TestDrive 'r.txt'
        [IO.File]::WriteAllText($left, 'été'); [IO.File]::WriteAllText($right, 'été')
        $result = Compare-PCTextFile $left $right
        $result.Kind | Should -Be 'Text'; $result.HasDifferences | Should -BeFalse
    }
}
Describe 'Text resource and Unicode regressions' {
    It 'detects different mixed newline sequences' {
        (Compare-PCText -LeftText "a`r`nb`nc" -RightText "a`nb`r`nc").HasDifferences | Should -BeTrue
    }
    It 'does not split a surrogate pair into separate highlighted runs' {
        $left=[char]::ConvertFromUtf32(0x1F600); $right=[char]::ConvertFromUtf32(0x1F603)
        $row=(Compare-PCText $left $right).Rows[0]
        $row.LeftChangeStart | Should -Be 0; $row.LeftChangeLength | Should -Be 2
    }
    It 'caps line count before constructing comparison rows' {
        $result=Compare-PCText -LeftText "a`nb`nc`nd" -RightText "a`nb`nc`nd" -MaxLines 2
        $result.Kind | Should -Be 'TooLarge'; $result.Rows.Count | Should -Be 0
    }
    It 'honors text alignment cancellation' {
        $cts=[Threading.CancellationTokenSource]::new();$cts.Cancel()
        try { { Compare-PCText 'a' 'b' -CancellationToken $cts.Token } | Should -Throw '*canceled*' } finally { $cts.Dispose() }
    }
}
Describe 'Navigable newline differences' {
    It 'marks exact rows whose newline delimiters differ' {
        $result=Compare-PCText -LeftText "a`r`nb`nc" -RightText "a`nb`r`nc"
        $result.Rows.Status -join ',' | Should -Be 'LineEnding,LineEnding,Equal'
        $result.Rows[0].LeftLineEnding | Should -Be 'CRLF'
        $result.Rows[0].RightLineEnding | Should -Be 'LF'
    }
}
