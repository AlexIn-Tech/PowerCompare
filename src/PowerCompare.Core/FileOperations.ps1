function New-PCReadOnlyRecord {
    param([hashtable]$Values)
    $dictionary = [Collections.Generic.Dictionary[string, object]]::new()
    foreach ($key in $Values.Keys) { $dictionary.Add($key, $Values[$key]) }
    ,([Collections.ObjectModel.ReadOnlyDictionary[string, object]]::new($dictionary))
}

function Resolve-PCCopyPath {
    param([string]$Root, [string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains(':')) { throw 'Invalid relative file path.' }
    $parts = $RelativePath.Replace('\', '/').Split('/')
    if (@($parts | Where-Object { $_ -eq '..' -or $_ -eq '.' -or $_ -eq '' }).Count) { throw 'Relative path traversal is not allowed.' }
    $path = [IO.Path]::GetFullPath([IO.Path]::Combine($Root, ($parts -join [IO.Path]::DirectorySeparatorChar)))
    $prefix = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escapes the selected root.' }
    Assert-PCNoLink -Path $path
    $path
}

function Assert-PCDisjointRoots {
    param([string]$SourceRoot, [string]$DestinationRoot)
    $s = $SourceRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $d = $DestinationRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($s.StartsWith($d, [StringComparison]::OrdinalIgnoreCase) -or $d.StartsWith($s, [StringComparison]::OrdinalIgnoreCase)) { throw 'Copy roots must not overlap.' }
}

function Get-PCFileIdentity {
    param([string]$Path, [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None)
    Assert-PCNoLink $Path
    if ([IO.Directory]::Exists($Path)) { throw 'File-directory conflict.' }
    if (-not [IO.File]::Exists($Path)) { return '<missing>' }
    $info = [IO.FileInfo]::new($Path); $length = $info.Length; $ticks = $info.LastWriteTimeUtc.Ticks
    $hash = Get-PCStreamHash -Uri ([uri]$Path) -CancellationToken $CancellationToken
    $info.Refresh()
    if ($info.Length -ne $length -or $info.LastWriteTimeUtc.Ticks -ne $ticks) { throw 'File changed while its identity was being verified.' }
    "$length|$ticks|$hash"
}

function New-PCCopyPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][string[]]$RelativePath,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )
    $CancellationToken.ThrowIfCancellationRequested()
    $source = Get-PCValidatedRoot $SourceRoot; $destination = Get-PCValidatedRoot $DestinationRoot
    Assert-PCDisjointRoots $source $destination
    $operations = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $RelativePath) {
        $CancellationToken.ThrowIfCancellationRequested()
        $sourcePath = Resolve-PCCopyPath $source $relative
        $destinationPath = Resolve-PCCopyPath $destination $relative
        if (-not $seen.Add($destinationPath)) { continue }
        $sourceIdentity = Get-PCFileIdentity $sourcePath $CancellationToken
        if ($sourceIdentity -eq '<missing>') { throw "Source file is missing: $sourcePath" }
        $destinationIdentity = Get-PCFileIdentity $destinationPath $CancellationToken
        $operations.Add((New-PCReadOnlyRecord @{
            RelativePath=$relative; SourcePath=$sourcePath; DestinationPath=$destinationPath
            SourceIdentity=$sourceIdentity; DestinationIdentity=$destinationIdentity
            Action=if ($destinationIdentity -eq '<missing>') { 'Create' } else { 'Overwrite' }
        }))
    }
    New-PCReadOnlyRecord @{ Version=1; Id=[guid]::NewGuid().ToString(); SourceRoot=$source; DestinationRoot=$destination; Operations=$operations.AsReadOnly() }
}

function Invoke-PCCopyPlan {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )
    if ($Plan.Version -ne 1) { throw 'Unsupported copy plan version.' }
    $sourceRoot = Get-PCValidatedRoot $Plan.SourceRoot; $destinationRoot = Get-PCValidatedRoot $Plan.DestinationRoot
    Assert-PCDisjointRoots $sourceRoot $destinationRoot
    foreach ($operation in $Plan.Operations) {
        $stagePath = $null; $backupPath = $null; $errorMessage = $null; $status = 'Failed'
        try {
            $CancellationToken.ThrowIfCancellationRequested()
            $source = Resolve-PCCopyPath $sourceRoot $operation.RelativePath
            $destination = Resolve-PCCopyPath $destinationRoot $operation.RelativePath
            if ($source -cne $operation.SourcePath -or $destination -cne $operation.DestinationPath) { throw 'Plan path does not match its selected roots.' }
            if ((Get-PCFileIdentity $source $CancellationToken) -ne $operation.SourceIdentity) { throw 'Source changed since preview. Create a new plan.' }
            if ((Get-PCFileIdentity $destination $CancellationToken) -ne $operation.DestinationIdentity) { throw 'Destination changed since preview. Create a new plan.' }
            if (-not $PSCmdlet.ShouldProcess($destination, "$($operation.Action) from $source")) {
                $status = 'Skipped'
            } else {
                $directory = [IO.Path]::GetDirectoryName($destination)
                [void][IO.Directory]::CreateDirectory($directory)
                Assert-PCNoLink $directory
                $stagePath = [IO.Path]::Combine($directory, ('.powercompare-' + [guid]::NewGuid() + '.tmp'))
                $inputStream = Open-PCResourceRead -Uri ([uri]$source)
                try {
                    $outputStream = [IO.File]::Open($stagePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                    try {
                        $buffer = [byte[]]::new(65536)
                        while ($true) {
                            $CancellationToken.ThrowIfCancellationRequested()
                            $count = $inputStream.Read($buffer, 0, $buffer.Length)
                            if ($count -eq 0) { break }
                            $outputStream.Write($buffer, 0, $count)
                        }
                        $outputStream.Flush($true)
                    } finally { $outputStream.Dispose() }
                } finally { $inputStream.Dispose() }
                $expectedHash = $operation.SourceIdentity.Split('|')[2]
                if ((Get-PCStreamHash ([uri]$stagePath) $CancellationToken) -ne $expectedHash) { throw 'Source bytes changed during copy.' }
                if ((Get-PCFileIdentity $source $CancellationToken) -ne $operation.SourceIdentity) { throw 'Source changed during copy.' }
                if ((Get-PCFileIdentity $destination $CancellationToken) -ne $operation.DestinationIdentity) { throw 'Destination changed during copy.' }
                $ticks = [long]$operation.SourceIdentity.Split('|')[1]
                [IO.File]::SetLastWriteTimeUtc($stagePath, [datetime]::new($ticks, [DateTimeKind]::Utc))
                $CancellationToken.ThrowIfCancellationRequested()
                Assert-PCNoLink $destination
                if ($operation.DestinationIdentity -eq '<missing>') {
                    [IO.File]::Move($stagePath, $destination)
                } else {
                    $backupPath = $destination + '.powercompare-backup-' + [guid]::NewGuid().ToString('N')
                    [IO.File]::Replace($stagePath, $destination, $backupPath)
                }
                $stagePath = $null; $status = 'Copied'
            }
        } catch {
            $errorMessage = $_.Exception.Message
            $status = if ($CancellationToken.IsCancellationRequested) { 'Canceled' } else { 'Failed' }
        } finally {
            if ($stagePath -and [IO.File]::Exists($stagePath)) {
                try { [IO.File]::Delete($stagePath) } catch { $errorMessage += " Temporary file cleanup failed: $stagePath" }
            }
        }
        [pscustomobject]@{ RelativePath=$operation.RelativePath; SourcePath=$operation.SourcePath; DestinationPath=$operation.DestinationPath
            Status=$status; BackupPath=$backupPath; Error=$errorMessage }
    }
}
