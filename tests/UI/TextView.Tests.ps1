BeforeAll {
    $path = Join-Path $PSScriptRoot '../../src/PowerCompare.UI/TextView.ps1'
    if (Test-Path $path) { . $path }
    . (Join-Path $PSScriptRoot '../../src/PowerCompare.UI/Workers.ps1')
}
Describe 'Text view behavior' {
    It 'navigates differences in either direction and wraps at boundaries' {
        $rows = @([pscustomobject]@{Status='Equal'},[pscustomobject]@{Status='Changed'},[pscustomobject]@{Status='Equal'},[pscustomobject]@{Status='Added'})
        Get-PCNextDifferenceIndex $rows -CurrentIndex 1 -Direction Next | Should -Be 3
        Get-PCNextDifferenceIndex $rows -CurrentIndex 3 -Direction Next | Should -Be 1
        Get-PCNextDifferenceIndex $rows -CurrentIndex 1 -Direction Previous | Should -Be 3
    }
    It 'returns no selection when there are no differences' {
        Get-PCNextDifferenceIndex @([pscustomobject]@{Status='Equal'}) -CurrentIndex -1 -Direction Next | Should -Be -1
    }
    It 'builds copy selections only from eligible source files' {
        $rows = @(
            [pscustomobject]@{EntryType='File'; Status='LeftOnly'; RelativePath='a'; LeftPath='l'; RightPath=$null},
            [pscustomobject]@{EntryType='Directory'; Status='Equal'; RelativePath='dir'; LeftPath='l'; RightPath='r'},
            [pscustomobject]@{EntryType='File'; Status='Error'; RelativePath='bad'; LeftPath='l'; RightPath='r'}
        )
        @(Get-PCEligibleCopyPaths $rows -Direction LeftToRight) -join ',' | Should -Be 'a'
        @(Get-PCEligibleCopyPaths $rows -Direction RightToLeft).Count | Should -Be 0
    }
    It 'loads valid XML for the text comparison and copy preview' {
        foreach ($name in 'TextWindow.xaml','CopyPreview.xaml') {
            { [xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../src/PowerCompare.UI/$name") -Raw -ErrorAction Stop) } | Should -Not -Throw
        }
    }
}
Describe 'Operation workers' {
    It 'computes text comparison off the UI thread' {
        $l=Join-Path $TestDrive 'left.txt'; $r=Join-Path $TestDrive 'right.txt'
        [IO.File]::WriteAllText($l,'a'); [IO.File]::WriteAllText($r,'b')
        $worker = Start-PCOperationWorker -Operation Text -Request @{LeftPath=$l;RightPath=$r} -Generation 1
        try {
            $messages = [Collections.Generic.List[object]]::new(); $timer=[Diagnostics.Stopwatch]::StartNew()
            while (-not $worker.Handle.IsCompleted -and $timer.Elapsed.TotalSeconds -lt 10) {
                foreach ($message in (Receive-PCWorkerMessages $worker)) { $messages.Add($message) }
                Start-Sleep -Milliseconds 10
            }
            foreach ($message in (Receive-PCWorkerMessages $worker)) { $messages.Add($message) }
            $model = ($messages | Where-Object Type -EQ 'Model').Value
            $model.Kind | Should -Be 'Text'; $model.HasDifferences | Should -BeTrue
        } finally { Close-PCComparisonWorker $worker }
    }
}
Describe 'Display segments and UI operation state' {
    It 'preserves text around inline highlighted spans' {
        $row = [pscustomobject]@{LeftLineNumber=1;RightLineNumber=1;LeftText='abcXdef';RightText='abcYdef';Status='Changed';LeftLineEnding='None';RightLineEnding='None';LeftChangeStart=3;LeftChangeLength=1;RightChangeStart=3;RightChangeLength=1}
        $display = @(ConvertTo-PCTextDisplayRows @($row))[0]
        $display.LeftBefore | Should -Be 'abc'; $display.LeftChanged | Should -Be 'X'; $display.LeftAfter | Should -Be 'def'
    }
    It 'exposes copy controls and result logs in the main workspace' {
        [xml]$xml = Get-Content (Join-Path $PSScriptRoot '../../src/PowerCompare.UI/MainWindow.xaml') -Raw
        $names = @($xml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') })
        $names | Should -Contain 'CopyLeftToRight'; $names | Should -Contain 'OperationResults'; $names | Should -Contain 'OpenText'
    }
}
Describe 'Session controls' {
    It 'offers save/load session and report export controls' {
        [xml]$xml=Get-Content (Join-Path $PSScriptRoot '../../src/PowerCompare.UI/MainWindow.xaml') -Raw
        $names=@($xml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') })
        $names | Should -Contain 'SaveSession'; $names | Should -Contain 'LoadSession'; $names | Should -Contain 'ExportReport'
    }
}
