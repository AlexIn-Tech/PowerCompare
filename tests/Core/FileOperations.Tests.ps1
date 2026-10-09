BeforeAll { Import-Module (Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1') -Force }
Describe 'Previewed copy operations' {
    BeforeEach {
        $source = Join-Path $TestDrive ('s-' + [guid]::NewGuid()); $destination = Join-Path $TestDrive ('d-' + [guid]::NewGuid())
        [void][IO.Directory]::CreateDirectory($source); [void][IO.Directory]::CreateDirectory($destination)
        [IO.File]::WriteAllText((Join-Path $source '[a].txt'), 'new')
    }
    It 'plans without writing and copies only when explicitly executed' {
        $plan = New-PCCopyPlan $source $destination @('[a].txt')
        [IO.File]::Exists((Join-Path $destination '[a].txt')) | Should -BeFalse
        $plan.Operations.Count | Should -Be 1
        $result = Invoke-PCCopyPlan $plan -Confirm:$false
        $result.Status | Should -Be 'Copied'
        [IO.File]::ReadAllText((Join-Path $destination '[a].txt')) | Should -Be 'new'
    }
    It 'does not write in WhatIf mode' {
        $plan = New-PCCopyPlan $source $destination @('[a].txt')
        Invoke-PCCopyPlan $plan -WhatIf | Out-Null
        [IO.Directory]::GetFiles($destination).Count | Should -Be 0
    }
    It 'backs up overwritten files with exact original bytes' {
        [IO.File]::WriteAllText((Join-Path $destination '[a].txt'), 'original')
        $plan = New-PCCopyPlan $source $destination @('[a].txt')
        $plan.Operations[0].Action | Should -Be 'Overwrite'
        $result = Invoke-PCCopyPlan $plan -Confirm:$false
        $result.Status | Should -Be 'Copied'
        [IO.File]::ReadAllText($result.BackupPath) | Should -Be 'original'
    }
    It 'rejects stale source content even if size and timestamp are preserved' {
        $path = Join-Path $source '[a].txt'; $stamp = [IO.File]::GetLastWriteTimeUtc($path)
        $plan = New-PCCopyPlan $source $destination @('[a].txt')
        [IO.File]::WriteAllText($path, 'bad'); [IO.File]::SetLastWriteTimeUtc($path, $stamp)
        (Invoke-PCCopyPlan $plan -Confirm:$false).Status | Should -Be 'Failed'
        [IO.File]::Exists((Join-Path $destination '[a].txt')) | Should -BeFalse
    }
    It 'rejects changed destinations without overwriting the newer bytes' {
        $path = Join-Path $destination '[a].txt'; [IO.File]::WriteAllText($path, 'old')
        $plan = New-PCCopyPlan $source $destination @('[a].txt')
        [IO.File]::WriteAllText($path, 'latest')
        (Invoke-PCCopyPlan $plan -Confirm:$false).Status | Should -Be 'Failed'
        [IO.File]::ReadAllText($path) | Should -Be 'latest'
    }
    It 'rejects unexpected newly created destinations' {
        $plan = New-PCCopyPlan $source $destination @('[a].txt')
        [IO.File]::WriteAllText((Join-Path $destination '[a].txt'), 'created later')
        (Invoke-PCCopyPlan $plan -Confirm:$false).Status | Should -Be 'Failed'
    }
    It 'creates nested destination folders for selected files' {
        [void][IO.Directory]::CreateDirectory((Join-Path $source 'nested'))
        [IO.File]::WriteAllText((Join-Path $source 'nested/é.txt'), 'x')
        $plan = New-PCCopyPlan $source $destination @('nested/é.txt')
        (Invoke-PCCopyPlan $plan -Confirm:$false).Status | Should -Be 'Copied'
        [IO.File]::ReadAllText((Join-Path $destination 'nested/é.txt')) | Should -Be 'x'
    }
    It 'rejects traversal, rooted paths, and alternate streams' {
        foreach ($relative in @('../escape','/rooted','a:stream','nested/../escape')) {
            { New-PCCopyPlan $source $destination @($relative) } | Should -Throw
        }
    }
    It 'rejects overlapping roots and file-directory conflicts' {
        { New-PCCopyPlan $source $source @('[a].txt') } | Should -Throw '*overlap*'
        [void][IO.Directory]::CreateDirectory((Join-Path $source 'inner'))
        { New-PCCopyPlan $source (Join-Path $source 'inner') @('[a].txt') } | Should -Throw '*overlap*'
        [void][IO.Directory]::CreateDirectory((Join-Path $destination '[a].txt'))
        { New-PCCopyPlan $source $destination @('[a].txt') } | Should -Throw
    }
    It 'uses read-only plan operation records' {
        $plan = New-PCCopyPlan $source $destination @('[a].txt')
        { $plan.Operations[0]['DestinationPath'] = Join-Path $TestDrive 'escape' } | Should -Throw
    }
    It 'reports partial failures individually without abandoning valid files' {
        [IO.File]::WriteAllText((Join-Path $source 'b'), 'valid')
        $plan = New-PCCopyPlan $source $destination @('[a].txt','b')
        [IO.File]::Delete((Join-Path $source '[a].txt'))
        $results = @(Invoke-PCCopyPlan $plan -Confirm:$false)
        $results.Status | Should -Contain 'Failed'; $results.Status | Should -Contain 'Copied'
        [IO.File]::ReadAllText((Join-Path $destination 'b')) | Should -Be 'valid'
    }
    It 'honors cancellation without leaving staged files' {
        $plan = New-PCCopyPlan $source $destination @('[a].txt')
        $cts = [Threading.CancellationTokenSource]::new(); $cts.Cancel()
        try { (Invoke-PCCopyPlan $plan -CancellationToken $cts.Token -Confirm:$false).Status | Should -Be 'Canceled' } finally { $cts.Dispose() }
        [IO.Directory]::GetFiles($destination).Count | Should -Be 0
    }
    It 'rejects destination link traversal' {
        $target = Join-Path $TestDrive 'outside'; [void][IO.Directory]::CreateDirectory($target)
        try { New-Item -ItemType SymbolicLink -Path (Join-Path $destination 'nested') -Target $target -ErrorAction Stop | Out-Null }
        catch { Set-ItResult -Skipped -Because 'Symbolic links unavailable'; return }
        [void][IO.Directory]::CreateDirectory((Join-Path $source 'nested')); [IO.File]::WriteAllText((Join-Path $source 'nested/a'), 'x')
        { New-PCCopyPlan $source $destination @('nested/a') } | Should -Throw '*link*'
    }
}
Describe 'Copy preview cancellation' {
    It 'cancels preview hashing before creating a plan' {
        $cts=[Threading.CancellationTokenSource]::new();$cts.Cancel()
        try { { New-PCCopyPlan $TestDrive $TestDrive @('a') -CancellationToken $cts.Token } | Should -Throw '*canceled*' } finally { $cts.Dispose() }
    }
}
