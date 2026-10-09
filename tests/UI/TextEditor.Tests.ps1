BeforeAll {
    . (Join-Path $PSScriptRoot '../../src/PowerCompare.UI/Workers.ps1')
    $controller=Join-Path $PSScriptRoot '../../src/PowerCompare.UI/TextEditor.ps1'
    if (Test-Path $controller) { . $controller }
}
Describe 'Text editor behavior' {
    It 'preserves uniform delimiters and requires an explicit mixed-ending conversion' {
        ConvertTo-PCEditorSaveText "a`r`nb`r`n" LF Preserve | Should -Be "a`nb`n"
        ConvertTo-PCEditorSaveText "a`r`nb" CR Preserve | Should -Be "a`rb"
        { ConvertTo-PCEditorSaveText 'text' Mixed Preserve } | Should -Throw '*mixed*'
        ConvertTo-PCEditorSaveText "a`r`nb" Mixed LF | Should -Be "a`nb"
    }
    It 'finds literal text, wraps and honors case significance' {
        (Find-PCTextMatch 'a [x] b [X]' '[x]' -Start 6).Start | Should -Be 2
        (Find-PCTextMatch 'a [x] b [X]' '[x]' -Start 6 -IgnoreCase).Start | Should -Be 8
        Find-PCTextMatch 'abc' 'missing' | Should -BeNullOrEmpty
        Find-PCTextMatch 'abc' '' | Should -BeNullOrEmpty
    }
    It 'replaces literal matches without treating replacement text as regex syntax' {
        Replace-PCTextMatches 'a.* A.*' 'a.*' '$1' -IgnoreCase | Should -Be '$1 $1'
        Replace-PCTextMatches 'abc' '' 'x' | Should -Be 'abc'
    }
    It 'runs buffer comparison, editor load, merge and save through workers' {
        $l=Join-Path $TestDrive 'l.txt';$r=Join-Path $TestDrive 'r.txt';$b=Join-Path $TestDrive 'b.txt'
        [IO.File]::WriteAllText($l,'left');[IO.File]::WriteAllText($r,'right');[IO.File]::WriteAllText($b,'base')
        foreach ($operation in 'EditLoad','BufferText','Merge','TextSave') {
            $request=switch($operation) {
                'EditLoad' { @{Path=$r} }
                'BufferText' { @{LeftText='left';RightText='right'} }
                'Merge' { @{BasePath=$b;LeftPath=$l;RightPath=$r} }
                'TextSave' { @{Path=$r;Text='saved';ExpectedIdentity=$identity} }
            }
            $worker=Start-PCOperationWorker -Operation $operation -Request $request -Generation 1
            try {
                $clock=[Diagnostics.Stopwatch]::StartNew();while(-not $worker.Handle.IsCompleted -and $clock.Elapsed.TotalSeconds -lt 15){Start-Sleep -Milliseconds 10}
                $messages=@(Receive-PCWorkerMessages $worker)
                @($messages | Where-Object Type -EQ 'Error').Count | Should -Be 0
                if ($operation -eq 'EditLoad') { $identity=($messages | Where-Object Type -EQ 'Model').Value.Identity; $identity | Should -Not -BeNullOrEmpty }
                if ($operation -eq 'TextSave') { ($messages | Where-Object Type -EQ 'Result').Rows[0].Status | Should -Be 'Saved' }
                else { @($messages | Where-Object Type -EQ 'Model').Count | Should -Be 1 }
            } finally { Close-PCComparisonWorker $worker }
        }
        [IO.File]::ReadAllText($r) | Should -Be 'saved'
    }
    It 'defines editor and merge windows as valid XAML' {
        foreach($name in 'TextEditor','TextMerge') {
            { [xml](Get-Content (Join-Path $PSScriptRoot "../../src/PowerCompare.UI/$name.xaml") -Raw -ErrorAction Stop) } | Should -Not -Throw
        }
    }
}
Describe 'Editor data-preservation regressions' {
    It 'marks canonically equivalent but ordinally different Unicode as dirty' {
        Test-PCTextEditorDirty "caf$([char]0xE9)" "cafe$([char]0x301)" | Should -BeTrue
        Test-PCTextEditorDirty 'same' 'same' | Should -BeFalse
    }
    It 'derives the save policy from initial merge output before control normalization' {
        Get-PCEditorNewlineStyle "A`r`nb`n" | Should -Be 'Mixed'
        { ConvertTo-PCEditorSaveText "A`r`nb`r`n" (Get-PCEditorNewlineStyle "A`r`nb`n") Preserve } | Should -Throw '*mixed*'
    }
}
