function Show-PCTextMerge {
    [CmdletBinding()]
    param([string]$BasePath,[string]$LeftPath,[string]$RightPath,[object]$Owner)
    $reader=[Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'TextMerge.xaml'))
    try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    if($Owner){$window.Owner=$Owner}
    $status=$window.FindName('MergeStatus');$grid=$window.FindName('MergeConflicts');$output=$window.FindName('MergeOutput');$preview=$window.FindName('PreviewMerge');$edit=$window.FindName('EditMergeOutput')
    $window.FindName('MergePaths').Text="Base: $BasePath`nLeft: $LeftPath`nRight / output target: $RightPath"
    $state=@{Bundle=$null;Rows=@();Worker=(Start-PCOperationWorker -Operation Merge -Request @{BasePath=$BasePath;LeftPath=$LeftPath;RightPath=$RightPath} -Generation 1)}
    $resolve={
        $choices=@{};foreach($row in $state.Rows){if($row.Choice -ne 'Unresolved'){$choices[$row.Id]=$row.Choice}}
        Resolve-PCTextMerge $state.Bundle.Model $choices
    }.GetNewClosure()
    $preview.Add_Click({try{$output.Text=& $resolve;$status.Text='Resolution preview updated. Saving requires confirmation in the editor.';$edit.IsEnabled=$true}catch{$status.Text=$_.Exception.Message;$edit.IsEnabled=$false}}.GetNewClosure())
    $edit.Add_Click({
        try{
            $resolved=& $resolve
            Show-PCTextEditor -Path $RightPath -Session $state.Bundle.RightSession -InitialText $resolved -PeerText $state.Bundle.BaseSession.Document.Text -InputSession @($state.Bundle.BaseSession,$state.Bundle.LeftSession,$state.Bundle.RightSession) -Owner $window
        }catch{$status.Text=$_.Exception.Message}
    }.GetNewClosure())
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds(100)
    $timer.Add_Tick({
        if(-not $state.Worker){return}
        $finished=$state.Worker.Handle.IsCompleted
        foreach($message in @(Receive-PCWorkerMessages $state.Worker)){
            switch($message.Type){
                'Model'{
                    $state.Bundle=$message.Value
                    $state.Rows=@($state.Bundle.Model.Conflicts | ForEach-Object {[pscustomobject]@{Id=$_.Id;BaseText=$_.BaseText;LeftText=$_.LeftText;RightText=$_.RightText;Choice='Unresolved'}})
                    $grid.ItemsSource=$state.Rows;$preview.IsEnabled=$true
                    $status.Text="Exact merge: $($state.Rows.Count) unresolved conflicts."
                    if($state.Rows.Count -eq 0){$output.Text=$state.Bundle.Model.AutoMergedText;$edit.IsEnabled=$true}
                }
                'Error'{$status.Text=$message.Message}
                'Canceled'{$status.Text='Merge canceled.'}
            }
        }
        if($finished){Close-PCComparisonWorker $state.Worker;$state.Worker=$null}
    }.GetNewClosure())
    $window.Add_Closed({$timer.Stop();if($state.Worker){Close-PCComparisonWorker $state.Worker;$state.Worker=$null}}.GetNewClosure())
    $timer.Start();[void]$window.ShowDialog()
}
