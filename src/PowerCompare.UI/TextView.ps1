function Get-PCNextDifferenceIndex {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Rows, [int]$CurrentIndex = -1, [ValidateSet('Next','Previous')][string]$Direction = 'Next')
    $indices = @(); for ($i=0; $i -lt $Rows.Count; $i++) { if ($Rows[$i].Status -ne 'Equal') { $indices += $i } }
    if ($indices.Count -eq 0) { return -1 }
    if ($Direction -eq 'Next') {
        foreach ($index in $indices) { if ($index -gt $CurrentIndex) { return $index } }
        return $indices[0]
    }
    for ($i=$indices.Count-1; $i -ge 0; $i--) { if ($indices[$i] -lt $CurrentIndex) { return $indices[$i] } }
    $indices[-1]
}

function Get-PCEligibleCopyPaths {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Rows, [ValidateSet('LeftToRight','RightToLeft')][string]$Direction)
    foreach ($row in $Rows) {
        if ($row.EntryType -ne 'File' -or $row.Status -in @('Error','TypeConflict')) { continue }
        $path = if ($Direction -eq 'LeftToRight') { $row.LeftPath } else { $row.RightPath }
        if ($path) { $row.RelativePath }
    }
}

function ConvertTo-PCTextDisplayRows {
    param([AllowEmptyCollection()][object[]]$Rows)
    foreach ($row in $Rows) {
        $values=@{LeftLineNumber=$row.LeftLineNumber;RightLineNumber=$row.RightLineNumber;Status=$row.Status;LeftLineEnding=$row.LeftLineEnding;RightLineEnding=$row.RightLineEnding}
        foreach ($side in 'Left','Right') {
            $text=[string]$row."${side}Text"; $start=[int]$row."${side}ChangeStart"; $length=[int]$row."${side}ChangeLength"
            $values["${side}Before"]=$text.Substring(0,$start)
            $values["${side}Changed"]=$text.Substring($start,$length)
            $values["${side}After"]=$text.Substring($start+$length)
        }
        [pscustomobject]$values
    }
}

function Show-PCTextComparison {
    [CmdletBinding()]
    param([string]$LeftPath, [string]$RightPath, [object]$Owner)
    if (-not $LeftPath -or -not $RightPath) { throw 'Select a file present on both sides for text comparison.' }
    $reader=[Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'TextWindow.xaml'))
    try { $window=[Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
    $window.Owner=$Owner
    $grid=$window.FindName('TextRows'); $summary=$window.FindName('TextSummary')
    $window.FindName('TextPaths').Text="$LeftPath ↔ $RightPath"
    $worker=Start-PCOperationWorker -Operation Text -Request @{LeftPath=$LeftPath;RightPath=$RightPath} -Generation 1
    $viewState=@{Rows=@();Worker=$worker}
    foreach ($direction in 'Next','Previous') {
        $button=$window.FindName("${direction}Difference")
        $button.Add_Click({
            $index=Get-PCNextDifferenceIndex -Rows $viewState.Rows -CurrentIndex $grid.SelectedIndex -Direction $direction
            if ($index -ge 0) { $grid.SelectedIndex=$index; $grid.ScrollIntoView($grid.SelectedItem) }
        }.GetNewClosure())
    }
    $window.FindName('CancelText').Add_Click({ if ($viewState.Worker) { Stop-PCComparisonWorker $viewState.Worker } }.GetNewClosure())
    $timer=[Windows.Threading.DispatcherTimer]::new(); $timer.Interval=[timespan]::FromMilliseconds(100)
    $timer.Add_Tick({
        if (-not $viewState.Worker) { return }
        $finished=$viewState.Worker.Handle.IsCompleted
        foreach ($message in (Receive-PCWorkerMessages $viewState.Worker)) {
            switch ($message.Type) {
                'Model' {
                    $model=$message.Value
                    if ($model.Kind -eq 'Text') {
                        $viewState.Rows=$model.Rows
                        $grid.ItemsSource=@(ConvertTo-PCTextDisplayRows $model.Rows)
                        $summary.Text="Alignment: $($model.Alignment). Left: $($model.LeftDocument.Encoding) / $($model.LeftDocument.Newline). Right: $($model.RightDocument.Encoding) / $($model.RightDocument.Newline). Differences: $($model.HasDifferences)."
                    } else { $summary.Text="Text preview unavailable: $($model.Kind). Binary/oversized input was not decoded." }
                }
                'Error' { $summary.Text=$message.Message }
                'Canceled' { $summary.Text='Text comparison canceled.' }
            }
        }
        if ($finished) { Close-PCComparisonWorker $viewState.Worker; $viewState.Worker=$null }
    }.GetNewClosure())
    $window.Add_Closed({ $timer.Stop(); if ($viewState.Worker) { Close-PCComparisonWorker $viewState.Worker; $viewState.Worker=$null } }.GetNewClosure())
    $timer.Start()
    try { [void]$window.ShowDialog() } finally { $timer.Stop(); if ($viewState.Worker) { Close-PCComparisonWorker $viewState.Worker } }
}
