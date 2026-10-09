function New-PCWorkspaceState {
    [pscustomobject]@{
        Generation = [long]0; LeftPath = ''; RightPath = ''; Mode = 'Content'
        Worker = $null; Results = [Collections.ObjectModel.ObservableCollection[object]]::new()
        Status = 'Ready'; Message = 'Choose two folders to compare.'; Closed = $false
    }
}

function Invoke-PCCompareRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$State, [Parameter(Mandatory)][hashtable]$Request)
    if ($State.Closed) { throw 'Workspace is closed.' }
    $normalized = $Request.Clone()
    foreach ($name in 'LeftPath', 'RightPath') {
        if ([string]::IsNullOrWhiteSpace($Request[$name])) { throw "Choose a folder for $name." }
        $item = Get-Item -LiteralPath $Request[$name] -Force -ErrorAction Stop
        if (-not $item.PSIsContainer) { throw "$name must be a folder." }
        $normalized[$name] = $item.FullName
    }
    if ($State.Worker) { Close-PCComparisonWorker $State.Worker }
    $State.Generation++; $State.Results.Clear()
    $State.LeftPath = $normalized.LeftPath; $State.RightPath = $normalized.RightPath
    $State.Status = 'Comparing'; $State.Message = 'Scanning and comparing…'
    try { $State.Worker = Start-PCComparisonWorker -Request $normalized -Generation $State.Generation }
    catch { $State.Worker = $null; $State.Status = 'Error'; $State.Message = $_.Exception.Message; throw }
}

function Update-PCWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$State, [AllowEmptyCollection()][object[]]$Messages)
    if ($State.Closed) { return }
    foreach ($message in $Messages) {
        if (-not (Test-PCCurrentGeneration $State.Generation $message.Generation)) { continue }
        switch ($message.Type) {
            'Result' { foreach ($row in $message.Rows) { $State.Results.Add($row) } }
            'Progress' { $State.Message = "Compared $($message.Count) entries…" }
            'Completed' { $State.Status = 'Completed'; $State.Message = "$($message.Count) entries compared." }
            'Canceled' { $State.Status = 'Canceled'; $State.Message = 'Comparison canceled; results are incomplete.' }
            'Error' { $State.Status = 'Error'; $State.Message = $message.Message }
        }
    }
}

function Close-PCWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$State)
    if ($State.Worker) { Close-PCComparisonWorker $State.Worker; $State.Worker = $null }
    $State.Closed = $true; $State.Status = 'Closed'
}
