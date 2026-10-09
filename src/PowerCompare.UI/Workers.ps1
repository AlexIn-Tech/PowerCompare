function Test-PCCurrentGeneration {
    param([long]$Current, [long]$Incoming)
    $Current -eq $Incoming
}

function Start-PCOperationWorker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Request, [Parameter(Mandatory)][long]$Generation,
        [ValidateSet('Folder','Text','CopyPlan','Copy','Report')][string]$Operation = 'Folder')
    $queue = [Collections.Concurrent.BlockingCollection[object]]::new(64)
    $cts = [Threading.CancellationTokenSource]::new()
    $outcomes = [Collections.Concurrent.ConcurrentQueue[object]]::new()
    $powershell = [PowerShell]::Create()
    $module = Join-Path $PSScriptRoot '../PowerCompare.Core/PowerCompare.Core.psd1'
    $work = {
        param($Module, $Request, $Generation, $Cancellation, $Queue, $Operation, $Outcomes)
        $ErrorActionPreference = 'Stop'
        try {
            Import-Module $Module -Force -ErrorAction Stop
            $Cancellation.Token.ThrowIfCancellationRequested()
            if ($Operation -in @('Text', 'CopyPlan','Report')) {
                $value = switch ($Operation) {
                    'Text' { Compare-PCTextFile @Request -CancellationToken $Cancellation.Token }
                    'CopyPlan' { New-PCCopyPlan @Request -CancellationToken $Cancellation.Token }
                    'Report' { Export-PCComparisonReport @Request; $Request.Path }
                }
                $Cancellation.Token.ThrowIfCancellationRequested()
                $Queue.Add([pscustomobject]@{ Type='Model'; Generation=$Generation; Value=$value }, $Cancellation.Token)
                $Queue.Add([pscustomobject]@{ Type='Completed'; Generation=$Generation; Count=1 }, $Cancellation.Token)
                return
            }
            $batch = [Collections.Generic.List[object]]::new()
            $count = 0
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $producer = {
                if ($Operation -eq 'Copy') { Invoke-PCCopyPlan @Request -CancellationToken $Cancellation.Token -Confirm:$false }
                else { Compare-PCFolder @Request -CancellationToken $Cancellation.Token }
            }
            & $producer | ForEach-Object {
                if ($Operation -eq 'Copy') {
                    # Outcomes describe filesystem mutations. Never discard them on cancellation.
                    $Outcomes.Enqueue($_); $count++; return
                }
                $Cancellation.Token.ThrowIfCancellationRequested()
                $batch.Add($_); $count++
                if ($batch.Count -ge 128) {
                    $Queue.Add([pscustomobject]@{ Type='Result'; Generation=$Generation; Rows=$batch.ToArray() }, $Cancellation.Token)
                    $batch.Clear()
                }
                if ($clock.ElapsedMilliseconds -ge 250) {
                    [void]$Queue.TryAdd([pscustomobject]@{ Type='Progress'; Generation=$Generation; Count=$count })
                    $clock.Restart()
                }
            }
            $Cancellation.Token.ThrowIfCancellationRequested()
            if ($batch.Count) { $Queue.Add([pscustomobject]@{ Type='Result'; Generation=$Generation; Rows=$batch.ToArray() }, $Cancellation.Token) }
            $Queue.Add([pscustomobject]@{ Type='Completed'; Generation=$Generation; Count=$count }, $Cancellation.Token)
        } catch {
            if ($Cancellation.IsCancellationRequested) {
                [void]$Queue.TryAdd([pscustomobject]@{ Type='Canceled'; Generation=$Generation }, 100)
            } else {
                [void]$Queue.TryAdd([pscustomobject]@{ Type='Error'; Generation=$Generation; Message=$_.Exception.Message }, 100)
            }
        }
    }
    try {
        [void]$powershell.AddScript($work.ToString()).AddArgument($module).AddArgument($Request.Clone()).AddArgument($Generation).AddArgument($cts).AddArgument($queue).AddArgument($Operation).AddArgument($outcomes)
        $handle = $powershell.BeginInvoke()
        [pscustomobject]@{ Generation=$Generation; PowerShell=$powershell; Handle=$handle; CancellationSource=$cts; Queue=$queue; Outcomes=$outcomes; Closed=$false }
    } catch { $powershell.Dispose(); $cts.Dispose(); $queue.Dispose(); throw }
}

function Receive-PCWorkerMessages {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Worker)
    if ($Worker.Closed) { return }
    $message = $null
    $messages=[Collections.Generic.List[object]]::new()
    while ($Worker.Queue.TryTake([ref]$message)) { $messages.Add($message) }
    $records=[Collections.Generic.List[object]]::new()
    while ($Worker.Outcomes.TryDequeue([ref]$message)) { $records.Add($message) }
    # Drain outcomes before terminal messages so summaries include all completed writes.
    if ($records.Count) { [pscustomobject]@{Type='Result';Generation=$Worker.Generation;Rows=$records.ToArray()} }
    $messages.ToArray()
}

function Stop-PCComparisonWorker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Worker)
    if (-not $Worker.Closed) { $Worker.CancellationSource.Cancel() }
}

function Close-PCComparisonWorker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Worker)
    if ($Worker.Closed) { return }
    $Worker.Closed = $true
    try {
        $Worker.CancellationSource.Cancel()
        if (-not $Worker.Handle.IsCompleted) { $Worker.PowerShell.Stop() }
        try { [void]$Worker.PowerShell.EndInvoke($Worker.Handle) } catch { Write-Verbose $_.Exception.Message }
    } finally {
        $Worker.PowerShell.Dispose(); $Worker.CancellationSource.Dispose(); $Worker.Queue.Dispose()
    }
}

function Start-PCComparisonWorker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Request, [Parameter(Mandatory)][long]$Generation)
    Start-PCOperationWorker -Request $Request -Generation $Generation -Operation Folder
}
