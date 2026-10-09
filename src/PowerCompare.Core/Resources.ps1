function Get-PCLocalPath {
    param([Parameter(Mandatory)][uri]$Uri)
    if (-not $Uri.IsAbsoluteUri -and [IO.Path]::IsPathRooted($Uri.OriginalString)) {
        return [IO.Path]::GetFullPath($Uri.OriginalString)
    }
    if (-not $Uri.IsAbsoluteUri -or -not $Uri.IsFile) {
        throw [NotSupportedException]::new("Resource scheme is not supported: $Uri")
    }
    [IO.Path]::GetFullPath($Uri.LocalPath)
}

function Assert-PCNoLink {
    param([Parameter(Mandatory)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw [IO.IOException]::new("Symbolic link or junction is not allowed: $current")
            }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Get-PCValidatedRoot {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    Assert-PCNoLink -Path $full
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) { throw [ArgumentException]::new("Root must be a directory: $full") }
    # Enumerating the root must succeed. A denied root is never treated as empty.
    [void]$item.GetFileSystemInfos()
    $full
}

function Get-PCResourceCapabilities {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri)
    [void](Get-PCLocalPath -Uri $Uri)
    [pscustomobject]@{
        Scheme = 'file'; CanRead = $true; CanWrite = $true; CanDelete = $true
        SupportsResume = $false; SupportsAtomicReplace = $true
    }
}

function Get-PCResourceEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )
    $CancellationToken.ThrowIfCancellationRequested()
    $root = Get-PCValidatedRoot -Path (Get-PCLocalPath -Uri $Uri)
    $prefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($root)
    while ($stack.Count -gt 0) {
        $CancellationToken.ThrowIfCancellationRequested()
        $directory = $stack.Pop()
        try {
            Assert-PCNoLink -Path $directory
            $children = @(([IO.DirectoryInfo]::new($directory)).GetFileSystemInfos() | Sort-Object Name)
        } catch {
            if ($directory -eq $root) { throw }
            [pscustomobject]@{
                RelativePath = $directory.Substring($prefix.Length).Replace('\', '/'); EntryType = 'Error'
                Uri = [uri]$directory; Length = $null; LastWriteTimeUtc = $null; Attributes = $null
                Error = $_.Exception.Message
            }
            continue
        }
        foreach ($item in $children) {
            $CancellationToken.ThrowIfCancellationRequested()
            $relative = $item.FullName.Substring($prefix.Length).Replace('\', '/')
            try {
                $item.Refresh()
                $isLink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                $isDirectory = ($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0
                $type = if ($isLink) { 'Link' } elseif ($isDirectory) { 'Directory' } else { 'File' }
                $length = if ($type -eq 'File') { $item.Length } else { $null }
                [pscustomobject]@{
                    RelativePath = $relative; EntryType = $type; Uri = [uri]$item.FullName
                    Length = $length; LastWriteTimeUtc = $item.LastWriteTimeUtc; Attributes = $item.Attributes
                    Error = if ($isLink) { 'Link traversal is disabled.' } else { $null }
                }
                if ($type -eq 'Directory') { $stack.Push($item.FullName) }
            } catch {
                [pscustomobject]@{
                    RelativePath = $relative; EntryType = 'Error'; Uri = [uri]$item.FullName
                    Length = $null; LastWriteTimeUtc = $null; Attributes = $null; Error = $_.Exception.Message
                }
            }
        }
    }
}

function Open-PCResourceRead {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri)
    $path = Get-PCLocalPath -Uri $Uri
    Assert-PCNoLink -Path $path
    [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
}
