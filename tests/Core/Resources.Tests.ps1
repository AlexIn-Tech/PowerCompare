BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1'
    if (Test-Path $modulePath) { Import-Module $modulePath -Force }
}
Describe 'Local resources' {
    BeforeEach { $root = Join-Path $TestDrive ([guid]::NewGuid().ToString()); [void][IO.Directory]::CreateDirectory($root) }
    It 'enumerates nested and hidden entries by relative literal path' {
        [void][IO.Directory]::CreateDirectory((Join-Path $root 'nested'))
        [IO.File]::WriteAllText((Join-Path $root 'nested/[draft].txt'), 'hello')
        [IO.File]::WriteAllText((Join-Path $root '.hidden'), 'hidden')
        $entries = @(Get-PCResourceEntries -Uri ([uri]$root))
        $entries.RelativePath | Should -Contain 'nested/[draft].txt'
        $entries.RelativePath | Should -Contain '.hidden'
        ($entries | Where-Object RelativePath -EQ 'nested/[draft].txt').Length | Should -Be 5
    }
    It 'returns no entries for an empty root' { @(Get-PCResourceEntries -Uri ([uri]$root)).Count | Should -Be 0 }
    It 'rejects a missing root' { { Get-PCResourceEntries -Uri ([uri](Join-Path $root 'missing')) } | Should -Throw }
    It 'rejects a file as root' {
        $file = Join-Path $root 'file'; [IO.File]::WriteAllText($file, 'x')
        { Get-PCResourceEntries -Uri ([uri]$file) } | Should -Throw
    }
    It 'rejects unsupported resource schemes' { { Get-PCResourceCapabilities -Uri 'https://example.com' } | Should -Throw '*not supported*' }
    It 'announces only implemented provider capabilities' {
        $caps = Get-PCResourceCapabilities -Uri ([uri]$root)
        $caps.Scheme | Should -Be 'file'
        $caps.CanRead | Should -BeTrue
        $caps.SupportsResume | Should -BeFalse
    }
    It 'opens Unicode and literal wildcard filenames without expansion' {
        $file = Join-Path $root 'été[1].txt'; [IO.File]::WriteAllText($file, 'unicode')
        $stream = Open-PCResourceRead -Uri ([uri]$file)
        try { $stream.Length | Should -Be 7 } finally { $stream.Dispose() }
        { [IO.File]::Delete($file) } | Should -Not -Throw
    }
    It 'honors an already canceled token' {
        $cts = [Threading.CancellationTokenSource]::new(); $cts.Cancel()
        try { { Get-PCResourceEntries -Uri ([uri]$root) -CancellationToken $cts.Token } | Should -Throw '*canceled*' } finally { $cts.Dispose() }
    }
    It 'reports links without traversing them' {
        $target = Join-Path $TestDrive 'target'; [void][IO.Directory]::CreateDirectory($target)
        [IO.File]::WriteAllText((Join-Path $target 'secret'), 'x')
        try { New-Item -ItemType SymbolicLink -Path (Join-Path $root 'link') -Target $target -ErrorAction Stop | Out-Null }
        catch { Set-ItResult -Skipped -Because 'Symbolic link creation not permitted on this runner'; return }
        $entries = @(Get-PCResourceEntries -Uri ([uri]$root))
        ($entries | Where-Object RelativePath -EQ 'link').EntryType | Should -Be 'Link'
        $entries.RelativePath | Should -Not -Contain 'link/secret'
        { Open-PCResourceRead -Uri ([uri](Join-Path $root 'link/secret')) } | Should -Throw '*link*'
    }
}
