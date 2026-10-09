BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1') -Force
    function Write-FixtureFile($Root, $Relative, $Text) {
        $path = Join-Path $Root $Relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($path, $Text)
    }
}
Describe 'Recursive folder comparison' {
    BeforeEach {
        $left = Join-Path $TestDrive ('left-' + [guid]::NewGuid()); $right = Join-Path $TestDrive ('right-' + [guid]::NewGuid())
        [void][IO.Directory]::CreateDirectory($left); [void][IO.Directory]::CreateDirectory($right)
    }
    It 'compares empty roots without phantom rows' { @(Compare-PCFolder $left $right).Count | Should -Be 0 }
    It 'matches nested files by relative path and actual contents' {
        Write-FixtureFile $left 'nested/[é].txt' 'same'; Write-FixtureFile $right 'nested/[é].txt' 'same'
        $rows = @(Compare-PCFolder $left $right)
        ($rows | Where-Object RelativePath -EQ 'nested/[é].txt').Status | Should -Be 'Equal'
        $rows.Count | Should -Be 2
    }
    It 'finds same-size different content even with identical timestamps' {
        Write-FixtureFile $left 'a' 'abcd'; Write-FixtureFile $right 'a' 'abce'
        $stamp = [datetime]'2024-01-01T00:00:00Z'
        [IO.File]::SetLastWriteTimeUtc((Join-Path $left 'a'), $stamp); [IO.File]::SetLastWriteTimeUtc((Join-Path $right 'a'), $stamp)
        (Compare-PCFolder $left $right -Mode Content).Status | Should -Be 'Different'
        (Compare-PCFolder $left $right -Mode Metadata).Status | Should -Be 'MetadataMatch'
    }
    It 'reports left-only and right-only files in correct columns' {
        Write-FixtureFile $left 'l' 'x'; Write-FixtureFile $right 'r' 'y'
        $rows = @(Compare-PCFolder $left $right)
        ($rows | Where-Object RelativePath -EQ 'l').Status | Should -Be 'LeftOnly'
        ($rows | Where-Object RelativePath -EQ 'l').RightPath | Should -BeNullOrEmpty
        ($rows | Where-Object RelativePath -EQ 'r').Status | Should -Be 'RightOnly'
        ($rows | Where-Object RelativePath -EQ 'r').LeftPath | Should -BeNullOrEmpty
    }
    It 'identifies file-directory conflicts' {
        Write-FixtureFile $left 'a' 'x'; [void][IO.Directory]::CreateDirectory((Join-Path $right 'a'))
        (Compare-PCFolder $left $right).Status | Should -Be 'TypeConflict'
    }
    It 'filters paths without preventing nested traversal' {
        Write-FixtureFile $left 'nested/a.txt' 'x'; Write-FixtureFile $right 'nested/a.txt' 'x'
        Write-FixtureFile $left 'nested/b.tmp' 'x'; Write-FixtureFile $left 'excluded/a.txt' 'x'
        $rows = @(Compare-PCFolder $left $right -Include '*.txt' -Exclude 'excluded/*')
        $rows.Count | Should -Be 1; $rows[0].RelativePath | Should -Be 'nested/a.txt'
    }
    It 'rejects invalid roots before showing comparison results' { { Compare-PCFolder $left (Join-Path $right 'missing') } | Should -Throw }
    It 'honors canceled tokens and releases read handles' {
        Write-FixtureFile $left 'a' 'x'; Write-FixtureFile $right 'a' 'x'
        $cts = [Threading.CancellationTokenSource]::new(); $cts.Cancel()
        try { { Compare-PCFolder $left $right -CancellationToken $cts.Token } | Should -Throw '*canceled*' } finally { $cts.Dispose() }
        Compare-PCFolder $left $right | Out-Null
        { [IO.File]::Delete((Join-Path $left 'a')) } | Should -Not -Throw
    }
    It 'reports read failures as errors rather than equality' {
        Write-FixtureFile $left 'a' 'x'; Write-FixtureFile $right 'a' 'x'
        Mock Open-PCResourceRead -ModuleName PowerCompare.Core { throw [IO.IOException]::new('fixture read denied') }
        $row = Compare-PCFolder $left $right
        $row.Status | Should -Be 'Error'; $row.Error | Should -Match 'fixture read denied'
    }
    It 'does not silently choose a case-colliding file' {
        if ([Environment]::OSVersion.Platform -eq 'Win32NT') { Set-ItResult -Skipped -Because 'Requires a case-sensitive fixture filesystem'; return }
        Write-FixtureFile $left 'A' 'x'; Write-FixtureFile $left 'a' 'y'; Write-FixtureFile $right 'a' 'x'
        $row = Compare-PCFolder $left $right
        $row.Status | Should -Be 'Error'; $row.Error | Should -Match 'collision'
    }
    It 'keeps links visible as errors' {
        Write-FixtureFile $left 'a' 'x'
        try { New-Item -ItemType SymbolicLink -Path (Join-Path $right 'a') -Target (Join-Path $left 'a') -ErrorAction Stop | Out-Null }
        catch { Set-ItResult -Skipped -Because 'Symbolic link creation is unavailable'; return }
        (Compare-PCFolder $left $right).Status | Should -Be 'Error'
    }
}
Describe 'Folder summary status' {
    It 'marks shared parent folders different when a nested file differs' {
        $l=Join-Path $TestDrive 'rollup-l';$r=Join-Path $TestDrive 'rollup-r'
        [void][IO.Directory]::CreateDirectory((Join-Path $l 'parent/child'));[void][IO.Directory]::CreateDirectory((Join-Path $r 'parent/child'))
        [IO.File]::WriteAllText((Join-Path $l 'parent/child/a'),'x');[IO.File]::WriteAllText((Join-Path $r 'parent/child/a'),'y')
        $rows=@(Compare-PCFolder $l $r)
        ($rows | Where-Object RelativePath -EQ 'parent').Status | Should -Be 'Different'
        ($rows | Where-Object RelativePath -EQ 'parent/child').Status | Should -Be 'Different'
    }
}
Describe 'Unknown unreadable subtrees' {
    It 'does not treat an unreadable subtree as missing even with file-only filters' {
        $l=Join-Path $TestDrive 'denied-left';$r=Join-Path $TestDrive 'denied-right'
        $locked=Join-Path $l 'locked';$other=Join-Path $r 'locked'
        [void][IO.Directory]::CreateDirectory($locked);[void][IO.Directory]::CreateDirectory($other)
        [IO.File]::WriteAllText((Join-Path $locked 'a.txt'),'same');[IO.File]::WriteAllText((Join-Path $other 'a.txt'),'same')
        $windows=[Environment]::OSVersion.Platform -eq 'Win32NT'
        if ($windows) {
            $original=Get-Acl -LiteralPath $locked
            $denied=Get-Acl -LiteralPath $locked
            $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User, [Security.AccessControl.FileSystemRights]::ListDirectory, [Security.AccessControl.AccessControlType]::Deny)
            $denied.AddAccessRule($rule); Set-Acl -LiteralPath $locked -AclObject $denied
        } else { & chmod 000 $locked }
        try {
            $rows=@(Compare-PCFolder $l $r -Include '*.txt')
            ($rows | Where-Object RelativePath -EQ 'locked/a.txt').Status | Should -Be 'Error'
            @($rows | Where-Object Status -EQ 'RightOnly').Count | Should -Be 0
            ($rows | Where-Object RelativePath -EQ 'locked').Status | Should -Be 'Error'
        } finally { if ($windows) {Set-Acl -LiteralPath $locked -AclObject $original} else {& chmod 700 $locked} }
    }
}
