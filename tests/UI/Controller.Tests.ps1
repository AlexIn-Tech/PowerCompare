BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1') -Force
    . (Join-Path $PSScriptRoot '../../src/PowerCompare.UI/Workers.ps1')
    $controller = Join-Path $PSScriptRoot '../../src/PowerCompare.UI/Controller.ps1'
    if (Test-Path $controller) { . $controller }
}
Describe 'Workspace controller' {
    It 'starts with reusable empty results' {
        $state = New-PCWorkspaceState
        $state.Results.Count | Should -Be 0; $state.Status | Should -Be 'Ready'
    }
    It 'rejects invalid roots without launching a worker' {
        $state = New-PCWorkspaceState
        { Invoke-PCCompareRequest $state @{ LeftPath=''; RightPath=$TestDrive } } | Should -Throw
        $state.Worker | Should -BeNullOrEmpty
    }
    It 'ignores results from superseded generations' {
        $state = New-PCWorkspaceState; $state.Generation = 10
        Update-PCWorkspace $state @([pscustomobject]@{ Type='Result'; Generation=9; Rows=@([pscustomobject]@{Status='Equal'}) })
        $state.Results.Count | Should -Be 0
    }
    It 'retains the results collection across repeated comparisons' {
        $state = New-PCWorkspaceState; $collection = $state.Results
        try {
            Invoke-PCCompareRequest $state @{ LeftPath=$TestDrive; RightPath=$TestDrive }
            Invoke-PCCompareRequest $state @{ LeftPath=$TestDrive; RightPath=$TestDrive }
            [object]::ReferenceEquals($collection, $state.Results) | Should -BeTrue
            $state.Generation | Should -Be 2
        } finally { Close-PCWorkspace $state }
    }
    It 'surfaces worker errors without losing selected roots' {
        $state = New-PCWorkspaceState; $state.Generation = 2; $state.LeftPath = 'left'
        Update-PCWorkspace $state @([pscustomobject]@{ Type='Error'; Generation=2; Message='access denied' })
        $state.Status | Should -Be 'Error'; $state.Message | Should -Be 'access denied'; $state.LeftPath | Should -Be 'left'
    }
    It 'closes running work and discards late messages' {
        $state = New-PCWorkspaceState
        Invoke-PCCompareRequest $state @{ LeftPath=$TestDrive; RightPath=$TestDrive }
        Close-PCWorkspace $state
        $state.Worker | Should -BeNullOrEmpty
        Update-PCWorkspace $state @([pscustomobject]@{ Type='Completed'; Generation=$state.Generation; Count=0 })
        $state.Status | Should -Be 'Closed'
    }
}
