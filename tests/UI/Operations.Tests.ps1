BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1') -Force
    . (Join-Path $PSScriptRoot '../../src/PowerCompare.UI/Workers.ps1')
    $path = Join-Path $PSScriptRoot '../../src/PowerCompare.UI/Operations.ps1'; if (Test-Path $path) { . $path }
}
Describe 'UI copy lifecycle' {
    It 'keeps a completed copy plan in preview state without executing it' {
        $state = New-PCFileOperationState; $state.Generation=1; $state.Kind='CopyPlan'
        Update-PCFileOperationState $state @(
            [pscustomobject]@{Type='Model';Generation=1;Value='plan'},
            [pscustomobject]@{Type='Completed';Generation=1;Count=1}
        )
        $state.Phase | Should -Be 'Preview'; $state.Plan | Should -Be 'plan'; $state.Results.Count | Should -Be 0
    }
    It 'does not accept a stale operation plan' {
        $state = New-PCFileOperationState; $state.Generation=2
        Update-PCFileOperationState $state @([pscustomobject]@{Type='Model';Generation=1;Value='stale'})
        $state.Plan | Should -BeNullOrEmpty
    }
    It 'plans and executes copy through background workers only after a separate request' {
        $s=Join-Path $TestDrive 's';$d=Join-Path $TestDrive 'd'
        [void][IO.Directory]::CreateDirectory($s);[void][IO.Directory]::CreateDirectory($d);[IO.File]::WriteAllText((Join-Path $s 'a'),'new')
        $state = New-PCFileOperationState
        try {
            Start-PCFileOperationRequest $state -Kind CopyPlan -Request @{SourceRoot=$s;DestinationRoot=$d;RelativePath=@('a')}
            $timer=[Diagnostics.Stopwatch]::StartNew()
            while (-not $state.Worker.Handle.IsCompleted -and $timer.Elapsed.TotalSeconds -lt 10) {
                Update-PCFileOperationState $state @(Receive-PCWorkerMessages $state.Worker); Start-Sleep -Milliseconds 10
            }
            Update-PCFileOperationState $state @(Receive-PCWorkerMessages $state.Worker)
            $state.Phase | Should -Be 'Preview'; [IO.File]::Exists((Join-Path $d 'a')) | Should -BeFalse
            Start-PCFileOperationRequest $state -Kind Copy -Request @{Plan=$state.Plan}
            $timer.Restart()
            while (-not $state.Worker.Handle.IsCompleted -and $timer.Elapsed.TotalSeconds -lt 10) {
                Update-PCFileOperationState $state @(Receive-PCWorkerMessages $state.Worker); Start-Sleep -Milliseconds 10
            }
            Update-PCFileOperationState $state @(Receive-PCWorkerMessages $state.Worker)
            $state.Phase | Should -Be 'Completed'; $state.Results[0].Status | Should -Be 'Copied'
        } finally { if ($state.Worker) { Close-PCComparisonWorker $state.Worker } }
    }
}
