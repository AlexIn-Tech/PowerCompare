BeforeAll {
    $path = Join-Path $PSScriptRoot '../../src/PowerCompare.UI/Workers.ps1'
    if (Test-Path $path) { . $path }
    function Wait-Worker($Worker) {
        $messages = [Collections.Generic.List[object]]::new()
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while ($timer.Elapsed.TotalSeconds -lt 15) {
            foreach ($message in (Receive-PCWorkerMessages $Worker)) { $messages.Add($message) }
            if ($Worker.Handle.IsCompleted) {
                foreach ($message in (Receive-PCWorkerMessages $Worker)) { $messages.Add($message) }
                return $messages.ToArray()
            }
            Start-Sleep -Milliseconds 10
        }
        throw 'Worker timeout'
    }
}
Describe 'Comparison workers' {
    BeforeEach {
        $left = Join-Path $TestDrive ('l-' + [guid]::NewGuid()); $right = Join-Path $TestDrive ('r-' + [guid]::NewGuid())
        [void][IO.Directory]::CreateDirectory($left); [void][IO.Directory]::CreateDirectory($right)
        [IO.File]::WriteAllText((Join-Path $left 'a'), 'one'); [IO.File]::WriteAllText((Join-Path $right 'a'), 'two')
    }
    It 'publishes results and completion with the generation identity' {
        $worker = Start-PCComparisonWorker -Request @{ LeftPath=$left; RightPath=$right; Mode='Content' } -Generation 12
        try {
            $messages = @(Wait-Worker $worker)
            @($messages | Where-Object Type -EQ 'Result').Count | Should -BeGreaterThan 0
            ($messages | Where-Object Type -EQ 'Result').Rows.Status | Should -Contain 'Different'
            $messages[-1].Type | Should -Be 'Completed'
            @($messages | Where-Object Generation -NE 12).Count | Should -Be 0
        } finally { Close-PCComparisonWorker $worker }
    }
    It 'publishes a worker failure explicitly' {
        $worker = Start-PCComparisonWorker -Request @{ LeftPath=$left; RightPath=(Join-Path $right 'missing') } -Generation 2
        try {
            $messages = @(Wait-Worker $worker)
            ($messages | Where-Object Type -EQ 'Error').Message | Should -Not -BeNullOrEmpty
        } finally { Close-PCComparisonWorker $worker }
    }
    It 'cancels without publishing completion as success' {
        $worker = Start-PCComparisonWorker -Request @{ LeftPath=$left; RightPath=$right } -Generation 3
        try {
            Stop-PCComparisonWorker $worker
            $messages = @(Wait-Worker $worker)
            $messages.Type | Should -Contain 'Canceled'
            $messages.Type | Should -Not -Contain 'Completed'
        } finally { Close-PCComparisonWorker $worker }
    }
    It 'rejects stale generations' {
        Test-PCCurrentGeneration -Current 5 -Incoming 4 | Should -BeFalse
        Test-PCCurrentGeneration -Current 5 -Incoming 5 | Should -BeTrue
    }
    It 'disposes canceled workers repeatedly without holding files open' {
        1..3 | ForEach-Object {
            $worker = Start-PCComparisonWorker -Request @{ LeftPath=$left; RightPath=$right } -Generation $_
            Close-PCComparisonWorker $worker
            { Close-PCComparisonWorker $worker } | Should -Not -Throw
        }
        { [IO.Directory]::Delete($left, $true) } | Should -Not -Throw
    }
}
Describe 'Copy cancellation audit records' {
    It 'retains completed file outcomes when a later copy is canceled' {
        Import-Module (Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1') -Force
        $source=Join-Path $TestDrive 'copy-source';$destination=Join-Path $TestDrive 'copy-destination'
        [void][IO.Directory]::CreateDirectory($source);[void][IO.Directory]::CreateDirectory($destination)
        [IO.File]::WriteAllText((Join-Path $source 'first'),'small')
        $large=[IO.File]::Create((Join-Path $source 'second'));try {$large.SetLength(134217728)} finally {$large.Dispose()}
        $plan=New-PCCopyPlan $source $destination @('first','second')
        $worker=Start-PCOperationWorker -Operation Copy -Request @{Plan=$plan} -Generation 20
        try {
            $timer=[Diagnostics.Stopwatch]::StartNew()
            while (-not [IO.File]::Exists((Join-Path $destination 'first')) -and -not $worker.Handle.IsCompleted -and $timer.Elapsed.TotalSeconds -lt 15) { Start-Sleep -Milliseconds 1 }
            [IO.File]::Exists((Join-Path $destination 'first')) | Should -BeTrue
            Stop-PCComparisonWorker $worker
            $messages=@(Wait-Worker $worker)
            $outcomes=@($messages | Where-Object Type -EQ 'Result' | ForEach-Object Rows)
            ($outcomes | Where-Object RelativePath -EQ 'first').Status | Should -Be 'Copied'
            $messages.Type | Should -Contain 'Canceled'
        } finally {Close-PCComparisonWorker $worker}
    }
}
