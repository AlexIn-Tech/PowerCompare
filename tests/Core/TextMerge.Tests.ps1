BeforeAll { Import-Module (Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1') -Force }
Describe 'Exact three-way text merge' {
    It 'merges independent replacements and preserves delimiters' {
        $model=Merge-PCText -BaseText "a`r`nb`r`nc`r`n" -LeftText "A`r`nb`r`nc`r`n" -RightText "a`r`nb`r`nC`r`n"
        $model.Conflicts.Count | Should -Be 0
        $model.AutoMergedText | Should -Be "A`r`nb`r`nC`r`n"
        (Resolve-PCTextMerge $model @{}) | Should -Be $model.AutoMergedText
    }
    It 'accepts identical overlapping edits only once' {
        $model=Merge-PCText 'a' 'b' 'b'
        $model.AutoMergedText | Should -Be 'b'; $model.Conflicts.Count | Should -Be 0
    }
    It 'requires explicit choices for conflicting edits' {
        $model=Merge-PCText 'base' 'left' 'right'
        $model.Conflicts.Count | Should -Be 1; $model.AutoMergedText | Should -BeNullOrEmpty
        { Resolve-PCTextMerge $model @{} } | Should -Throw '*unresolved*'
        $id=$model.Conflicts[0].Id
        (Resolve-PCTextMerge $model @{$id='Left'}) | Should -Be 'left'
        (Resolve-PCTextMerge $model @{$id='Right'}) | Should -Be 'right'
        (Resolve-PCTextMerge $model @{$id='Base'}) | Should -Be 'base'
        (Resolve-PCTextMerge $model @{$id='Both'}) | Should -Be 'leftright'
        { Resolve-PCTextMerge $model @{$id='unexpected'} } | Should -Throw
    }
    It 'conflicts deletion against modification' {
        $m=Merge-PCText "a`nb`n" "a`n" "a`nB`n"
        $m.Conflicts.Count | Should -Be 1
        (Resolve-PCTextMerge $m @{$m.Conflicts[0].Id='Left'}) | Should -Be "a`n"
    }
    It 'merges adjacent independent changes' {
        (Merge-PCText "a`nb`n" "A`nb`n" "a`nB`n").AutoMergedText | Should -Be "A`nB`n"
    }
    It 'conflicts distinct insertions at the same boundary' {
        $m=Merge-PCText "a`n" "x`na`n" "y`na`n"
        $m.Conflicts.Count | Should -Be 1
        (Resolve-PCTextMerge $m @{$m.Conflicts[0].Id='Both'}) | Should -Be "x`ny`na`n"
    }
    It 'preserves repeated lines and disjoint insertions' {
        $m=Merge-PCText "x`nx`ny`n" "X`nx`ny`n" "x`nx`ny`nz`n"
        $m.Conflicts.Count | Should -Be 0; $m.AutoMergedText | Should -Be "X`nx`ny`nz`n"
    }
    It 'treats final-newline removal as an exact edit' {
        $m=Merge-PCText "a`nb`n" "A`nb`n" "a`nb"
        $m.AutoMergedText | Should -Be "A`nb"
    }
    It 'handles empty inputs and one-sided deletion' {
        (Merge-PCText '' '' '').AutoMergedText | Should -Be ''
        (Merge-PCText '' 'a' '').AutoMergedText | Should -Be 'a'
        (Merge-PCText 'a' '' 'a').AutoMergedText | Should -Be ''
    }
    It 'combines overlapping edit chains into one explicit conflict' {
        $m=Merge-PCText "a`nb`nc`nd`n" "A`nB`nc`nd`n" "a`nB2`nC`nd`n"
        $m.Conflicts.Count | Should -Be 1
        (Resolve-PCTextMerge $m @{$m.Conflicts[0].Id='Right'}) | Should -Be "a`nB2`nC`nd`n"
    }
    It 'rejects unbounded alignment and canceled work' {
        { Merge-PCText "a`nb" "b`na" 'x' -MaxAlignmentCells 2 } | Should -Throw '*limit*'
        $cts=[Threading.CancellationTokenSource]::new(); $cts.Cancel()
        try { { Merge-PCText 'a' 'b' 'c' -CancellationToken $cts.Token } | Should -Throw } finally { $cts.Dispose() }
    }
}
Describe 'Merge segment source ranges' {
    It 'keeps zero-based source ranges coherent after an insertion' {
        $m=Merge-PCText "a`nb`n" "x`na`nb`n" "a`nB`n"
        $changed=@($m.Segments | Where-Object Kind -EQ 'Merged')[-1]
        $changed.BaseStart | Should -Be 1
        $changed.LeftStart | Should -Be 2
        $changed.RightStart | Should -Be 1
        $changed.LeftCount | Should -Be 1
        $changed.RightCount | Should -Be 1
    }
}
