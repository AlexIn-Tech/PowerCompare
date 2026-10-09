function New-PCFileOperationState {
    [pscustomobject]@{ Generation=[long]0; Kind=''; Phase='Idle'; Plan=$null; Worker=$null; Message=''; Results=[Collections.ObjectModel.ObservableCollection[object]]::new() }
}

function Start-PCFileOperationRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$State, [ValidateSet('CopyPlan','Copy','Report')][string]$Kind, [hashtable]$Request)
    if ($State.Worker) {
        if (-not $State.Worker.Handle.IsCompleted) { throw 'A file operation is already running.' }
        Close-PCComparisonWorker $State.Worker; $State.Worker=$null
    }
    $State.Generation++; $State.Kind=$Kind; $State.Results.Clear()
    $State.Phase=switch ($Kind) { 'CopyPlan' {'Planning'}; 'Copy' {'Copying'}; 'Report' {'Exporting'} }
    $State.Message=switch ($Kind) { 'CopyPlan' {'Verifying files for the copy preview…'}; 'Copy' {'Copying selected files…'}; 'Report' {'Exporting comparison report…'} }
    if ($Kind -eq 'CopyPlan') { $State.Plan=$null }
    try { $State.Worker=Start-PCOperationWorker -Operation $Kind -Request $Request -Generation $State.Generation }
    catch { $State.Phase='Error'; $State.Message=$_.Exception.Message; throw }
}

function Update-PCFileOperationState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$State, [AllowEmptyCollection()][object[]]$Messages)
    foreach ($message in $Messages) {
        if ($message.Generation -ne $State.Generation) { continue }
        switch ($message.Type) {
            'Model' { $State.Plan=$message.Value }
            'Result' { foreach ($row in $message.Rows) { $State.Results.Add($row) } }
            'Completed' {
                if ($State.Kind -eq 'CopyPlan') { $State.Phase='Preview'; $State.Message='Review the copy plan before writing.' }
                elseif ($State.Kind -eq 'Report') { $State.Phase='Completed'; $State.Message='Comparison report exported.' }
                else {
                    $State.Phase='Completed'
                    $copied=@($State.Results | Where-Object Status -EQ 'Copied').Count
                    $failed=@($State.Results | Where-Object Status -EQ 'Failed').Count
                    $State.Message="Copy finished: $copied copied, $failed failed. Review the operation log; compare again to refresh folder results."
                }
            }
            'Error' { $State.Phase='Error'; $State.Message=$message.Message }
            'Canceled' { $State.Phase='Canceled'; $State.Message='File operation canceled. Review any already completed copies in the log.' }
        }
    }
}

function Show-PCCopyPreview {
    param([object]$Plan, [object]$Owner)
    $reader=[Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'CopyPreview.xaml'))
    try { $dialog=[Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
    $dialog.Owner=$Owner
    # Convert dictionaries into ordinary display records for WPF property binding.
    $dialog.FindName('PlanRows').ItemsSource=@($Plan.Operations | ForEach-Object {
        [pscustomobject]@{Action=$_.Action;SourcePath=$_.SourcePath;DestinationPath=$_.DestinationPath}
    })
    $dialog.FindName('ConfirmCopy').Add_Click({ $dialog.DialogResult=$true }.GetNewClosure())
    $dialog.ShowDialog() -eq $true
}
