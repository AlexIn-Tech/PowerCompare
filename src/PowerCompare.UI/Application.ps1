function Select-PCFolder {
    $shell = New-Object -ComObject Shell.Application
    $folder = $null
    try {
        $folder = $shell.BrowseForFolder(0, 'Choose a comparison folder', 0x11, 0)
        if ($folder) { $folder.Self.Path }
    } finally {
        if ($folder) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($folder) }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

function New-PCMainWindow {
    [CmdletBinding()]
    param([string]$LeftPath, [string]$RightPath, [ValidateSet('Content', 'Metadata')][string]$Mode = 'Content')
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'WPF requires Windows.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'WPF requires an STA thread.' }
    Add-Type -AssemblyName PresentationFramework
    $reader = [Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'MainWindow.xaml'))
    try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
    $state = New-PCWorkspaceState
    $operationState = New-PCFileOperationState
    $controls = @{}
    foreach ($name in 'LeftRoot','RightRoot','BrowseLeft','BrowseRight','CompareButton','CancelButton','ModeSelector','IncludeFilter','ExcludeFilter','DifferencesOnly','ResultsGrid','StatusText','WorkProgress','WorkspaceTabs','OpenText','CopyLeftToRight','CopyRightToLeft','OperationResults','OperationsTab','SaveSession','LoadSession','ExportReport') {
        $controls[$name] = $window.FindName($name)
    }
    $controls.LeftRoot.Text = $LeftPath; $controls.RightRoot.Text = $RightPath
    $controls.ModeSelector.SelectedIndex = if ($Mode -eq 'Content') { 0 } else { 1 }
    $controls.ResultsGrid.ItemsSource = $state.Results
    $controls.OperationResults.ItemsSource = $operationState.Results
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($state.Results)
    $view.Filter = [Predicate[object]]{
        param($row)
        -not $controls.DifferencesOnly.IsChecked -or $row.Status -notin @('Equal', 'MetadataMatch')
    }.GetNewClosure()
    $controls.DifferencesOnly.Add_Click({ $view.Refresh() }.GetNewClosure())
    $controls.BrowseLeft.Add_Click({
        try { $selected = Select-PCFolder; if ($selected) { $controls.LeftRoot.Text = $selected } }
        catch { $controls.StatusText.Text = $_.Exception.Message }
    }.GetNewClosure())
    $controls.BrowseRight.Add_Click({
        try { $selected = Select-PCFolder; if ($selected) { $controls.RightRoot.Text = $selected } }
        catch { $controls.StatusText.Text = $_.Exception.Message }
    }.GetNewClosure())
    $controls.CompareButton.Add_Click({
        try {
            $request = @{
                LeftPath=$controls.LeftRoot.Text; RightPath=$controls.RightRoot.Text
                Mode=[string]$controls.ModeSelector.SelectedItem.Content
                Include=@($controls.IncludeFilter.Text -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                Exclude=@($controls.ExcludeFilter.Text -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            if ($operationState.Worker) { throw 'Wait for the file operation to finish.' }
            $operationState.Phase='Idle'
            Invoke-PCCompareRequest -State $state -Request $request
            $controls.StatusText.Text = $state.Message
        } catch { $controls.StatusText.Text = $_.Exception.Message }
    }.GetNewClosure())
    $controls.CancelButton.Add_Click({
        if ($operationState.Worker) { Stop-PCComparisonWorker $operationState.Worker }
        elseif ($state.Worker) { Stop-PCComparisonWorker $state.Worker }
    }.GetNewClosure())
    $openText = {
        $row=$controls.ResultsGrid.SelectedItem
        if ($row -and $row.EntryType -eq 'File') {
            try { Show-PCTextComparison -LeftPath $row.LeftPath -RightPath $row.RightPath -Owner $window }
            catch { $controls.StatusText.Text=$_.Exception.Message }
        }
    }.GetNewClosure()
    $controls.OpenText.Add_Click($openText)
    $controls.ResultsGrid.Add_MouseDoubleClick($openText)
    foreach ($direction in 'LeftToRight','RightToLeft') {
        $controls["Copy$direction"].Add_Click({
            if ($state.Worker -or $operationState.Worker) { return }
            try {
                $paths=@(Get-PCEligibleCopyPaths @($controls.ResultsGrid.SelectedItems) -Direction $direction)
                if (-not $paths.Count) { throw 'Select source files without errors or type conflicts.' }
                $sourceRoot=if ($direction -eq 'LeftToRight') { $state.LeftPath } else { $state.RightPath }
                $destinationRoot=if ($direction -eq 'LeftToRight') { $state.RightPath } else { $state.LeftPath }
                Start-PCFileOperationRequest $operationState -Kind CopyPlan -Request @{SourceRoot=$sourceRoot;DestinationRoot=$destinationRoot;RelativePath=$paths}
                $controls.StatusText.Text=$operationState.Message
            } catch { $controls.StatusText.Text=$_.Exception.Message }
        }.GetNewClosure())
    }
    $controls.SaveSession.Add_Click({
        try {
            $dialog=[Microsoft.Win32.SaveFileDialog]::new(); $dialog.Filter='PowerCompare session|*.json'; $dialog.DefaultExt='.json'
            if ($dialog.ShowDialog($window)) {
                $session=New-PCSession -LeftPath $controls.LeftRoot.Text -RightPath $controls.RightRoot.Text -Mode ([string]$controls.ModeSelector.SelectedItem.Content) -Include @($controls.IncludeFilter.Text -split ';') -Exclude @($controls.ExcludeFilter.Text -split ';' | Where-Object { $_ })
                Save-PCSession -Session $session -Path $dialog.FileName
                $controls.StatusText.Text="Session saved: $($dialog.FileName)"
            }
        } catch { $controls.StatusText.Text=$_.Exception.Message }
    }.GetNewClosure())
    $controls.LoadSession.Add_Click({
        try {
            if ($state.Worker -or $operationState.Worker) { throw 'Wait for current work before loading a session.' }
            $dialog=[Microsoft.Win32.OpenFileDialog]::new(); $dialog.Filter='PowerCompare session|*.json'
            if ($dialog.ShowDialog($window)) {
                $session=Import-PCSession $dialog.FileName
                $controls.LeftRoot.Text=$session.LeftPath; $controls.RightRoot.Text=$session.RightPath
                $controls.ModeSelector.SelectedIndex=if ($session.Mode -eq 'Content') {0} else {1}
                $controls.IncludeFilter.Text=$session.Include -join ';'; $controls.ExcludeFilter.Text=$session.Exclude -join ';'
                $state.Results.Clear(); $state.Status='Ready'; $state.LeftPath=''; $state.RightPath=''
                $controls.StatusText.Text='Session loaded. Compare to obtain current results.'
            }
        } catch { $controls.StatusText.Text=$_.Exception.Message }
    }.GetNewClosure())
    $controls.ExportReport.Add_Click({
        try {
            if ($state.Status -ne 'Completed' -or $operationState.Worker) { throw 'Complete a comparison before exporting its report.' }
            $dialog=[Microsoft.Win32.SaveFileDialog]::new(); $dialog.Filter='HTML report|*.html|CSV report|*.csv|JSON report|*.json'; $dialog.DefaultExt='.html'
            if ($dialog.ShowDialog($window)) {
                $format=@('Html','Csv','Json')[$dialog.FilterIndex-1]
                Start-PCFileOperationRequest $operationState -Kind Report -Request @{Rows=@($state.Results);Path=$dialog.FileName;Format=$format}
            }
        } catch { $controls.StatusText.Text=$_.Exception.Message }
    }.GetNewClosure())
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
    $timer.Add_Tick({
        if ($state.Worker) {
            $messages = @(Receive-PCWorkerMessages $state.Worker)
            Update-PCWorkspace $state $messages
            if ($state.Worker.Handle.IsCompleted) {
                Update-PCWorkspace $state @(Receive-PCWorkerMessages $state.Worker)
                if ($state.Status -eq 'Comparing') {
                    $state.Status = 'Error'; $state.Message = 'Comparison worker stopped unexpectedly.'
                }
                Close-PCComparisonWorker $state.Worker; $state.Worker = $null
            }
            $controls.StatusText.Text=$state.Message
        }
        if ($operationState.Worker) {
            Update-PCFileOperationState $operationState @(Receive-PCWorkerMessages $operationState.Worker)
            if ($operationState.Worker.Handle.IsCompleted) {
                Update-PCFileOperationState $operationState @(Receive-PCWorkerMessages $operationState.Worker)
                Close-PCComparisonWorker $operationState.Worker; $operationState.Worker=$null
                if ($operationState.Phase -eq 'Preview') {
                    $operationState.Phase='Reviewing'
                    if (Show-PCCopyPreview $operationState.Plan -Owner $window) {
                        Start-PCFileOperationRequest $operationState -Kind Copy -Request @{Plan=$operationState.Plan}
                        $controls.OperationsTab.IsSelected=$true
                    } else { $operationState.Phase='Canceled'; $operationState.Message='Copy plan canceled; no files were written.' }
                }
            }
            $controls.StatusText.Text=$operationState.Message
        }
        $running = $state.Status -eq 'Comparing' -or $null -ne $operationState.Worker
        $controls.CompareButton.IsEnabled = $null -eq $operationState.Worker
        $controls.CopyLeftToRight.IsEnabled = -not $running
        $controls.CopyRightToLeft.IsEnabled = -not $running
        $controls.CancelButton.IsEnabled = $running
        $controls.WorkProgress.Visibility = if ($running) { 'Visible' } else { 'Collapsed' }

    }.GetNewClosure())
    $window.Add_Closed({ $timer.Stop(); Close-PCWorkspace $state; if ($operationState.Worker) { Close-PCComparisonWorker $operationState.Worker; $operationState.Worker=$null } }.GetNewClosure())
    $window.Tag = @{ State=$state; Timer=$timer; Controls=$controls; Operations=$operationState }
    $timer.Start()
    $window
}

function Show-PCMainWindow {
    [CmdletBinding()]
    param([string]$LeftPath, [string]$RightPath, [ValidateSet('Content', 'Metadata')][string]$Mode = 'Content')
    $window = New-PCMainWindow -LeftPath $LeftPath -RightPath $RightPath -Mode $Mode
    try { [void]$window.ShowDialog() } finally {
        $window.Tag.Timer.Stop()
        Close-PCWorkspace $window.Tag.State
        if ($window.Tag.Operations.Worker) { Close-PCComparisonWorker $window.Tag.Operations.Worker }
    }
}
