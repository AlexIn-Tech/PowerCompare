function Get-PCEnumerationFailure {
    param([object]$Index, [string]$RelativePath)
    $ancestor=$RelativePath
    while ($ancestor) {
        if ($Index.ContainsKey($ancestor) -and $Index[$ancestor].Error) { return "$ancestor : $($Index[$ancestor].Error)" }
        $separator=$ancestor.LastIndexOf('/')
        if ($separator -lt 0) { break }
        $ancestor=$ancestor.Substring(0,$separator)
    }
    $null
}

function Get-PCStreamHash {
    param([uri]$Uri, [Threading.CancellationToken]$CancellationToken)
    $stream = Open-PCResourceRead -Uri $Uri
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $buffer = [byte[]]::new(65536)
        while ($true) {
            $CancellationToken.ThrowIfCancellationRequested()
            $count = $stream.Read($buffer, 0, $buffer.Length)
            if ($count -eq 0) { break }
            [void]$sha.TransformBlock($buffer, 0, $count, $buffer, 0)
        }
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        [BitConverter]::ToString($sha.Hash).Replace('-', '')
    } finally { $sha.Dispose(); $stream.Dispose() }
}

function Compare-PCFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LeftPath,
        [Parameter(Mandatory)][string]$RightPath,
        [ValidateSet('Metadata', 'Content')][string]$Mode = 'Content',
        [string[]]$Include = @('*'),
        [string[]]$Exclude = @(),
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )
    $CancellationToken.ThrowIfCancellationRequested()
    $leftRoot = Get-PCValidatedRoot -Path $LeftPath
    $rightRoot = Get-PCValidatedRoot -Path $RightPath
    $leftIndex = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $rightIndex = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $collisions = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pair in @(@{ Root = $leftRoot; Index = $leftIndex }, @{ Root = $rightRoot; Index = $rightIndex })) {
        foreach ($entry in (Get-PCResourceEntries -Uri ([uri]$pair.Root) -CancellationToken $CancellationToken)) {
            if ($pair.Index.ContainsKey($entry.RelativePath)) {
                if ($entry.EntryType -ne 'Error') { [void]$collisions.Add($entry.RelativePath) }
            }
            $pair.Index[$entry.RelativePath] = $entry
        }
    }
    $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $leftIndex.Keys) { [void]$keys.Add($key) }
    foreach ($key in $rightIndex.Keys) { [void]$keys.Add($key) }
    $includes = @($Include | ForEach-Object { [Management.Automation.WildcardPattern]::new($_, 'IgnoreCase') })
    $excludes = @($Exclude | ForEach-Object { [Management.Automation.WildcardPattern]::new($_, 'IgnoreCase') })
    $output=[Collections.Generic.List[object]]::new()
    $outputByPath=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in ($keys | Sort-Object)) {
        $CancellationToken.ThrowIfCancellationRequested()
        $accepted = $includes.Count -eq 0
        foreach ($pattern in $includes) { if ($pattern.IsMatch($key)) { $accepted = $true; break } }
        foreach ($pattern in $excludes) { if ($pattern.IsMatch($key)) { $accepted = $false; break } }
        $leftIssue=Get-PCEnumerationFailure $leftIndex $key
        $rightIssue=Get-PCEnumerationFailure $rightIndex $key
        if (-not $accepted -and -not $leftIssue -and -not $rightIssue) { continue }
        $l = if ($leftIndex.ContainsKey($key)) { $leftIndex[$key] } else { $null }
        $r = if ($rightIndex.ContainsKey($key)) { $rightIndex[$key] } else { $null }
        $errorMessage = $null
        $type = if ($l) { $l.EntryType } else { $r.EntryType }
        if ($collisions.Contains($key)) { $status = 'Error'; $errorMessage = 'Case-insensitive relative-path collision.' }
        elseif ($leftIssue -or $rightIssue) {
            $status = 'Error'; $errorMessage = @($leftIssue,$rightIssue | Where-Object { $_ }) -join '; '
        }
        elseif (-not $l) { $status = 'RightOnly' }
        elseif (-not $r) { $status = 'LeftOnly' }
        elseif ($l.EntryType -ne $r.EntryType) { $status = 'TypeConflict' }
        elseif ($type -eq 'Directory') { $status = 'Equal' }
        elseif ($Mode -eq 'Metadata') {
            $status = if ($l.Length -eq $r.Length -and $l.LastWriteTimeUtc -eq $r.LastWriteTimeUtc) { 'MetadataMatch' } else { 'Different' }
        }
        else {
            try {
                $status = if ($l.Length -ne $r.Length) { 'Different' }
                elseif ((Get-PCStreamHash $l.Uri $CancellationToken) -eq (Get-PCStreamHash $r.Uri $CancellationToken)) { 'Equal' }
                else { 'Different' }
            } catch {
                if ($CancellationToken.IsCancellationRequested) { $CancellationToken.ThrowIfCancellationRequested() }
                $status = 'Error'; $errorMessage = $_.Exception.Message
            }
        }
        $row=[pscustomobject]@{
            RelativePath = $key; EntryType = $type
            LeftPath = if ($l) { Get-PCLocalPath $l.Uri } else { $null }
            RightPath = if ($r) { Get-PCLocalPath $r.Uri } else { $null }
            LeftLength = if ($l) { $l.Length } else { $null }
            RightLength = if ($r) { $r.Length } else { $null }
            LeftLastWriteTimeUtc = if ($l) { $l.LastWriteTimeUtc } else { $null }
            RightLastWriteTimeUtc = if ($r) { $r.LastWriteTimeUtc } else { $null }
            Status = $status; ComparisonMode = $Mode; Error = $errorMessage
        }
        $output.Add($row); $outputByPath[$key]=$row
    }
    foreach ($row in $output) {
        if ($row.Status -in @('Equal','MetadataMatch')) { continue }
        $parent=$row.RelativePath
        while ($parent.LastIndexOf('/') -ge 0) {
            $parent=$parent.Substring(0,$parent.LastIndexOf('/'))
            if (-not $outputByPath.ContainsKey($parent)) { continue }
            $container=$outputByPath[$parent]
            if ($container.EntryType -ne 'Directory' -or $container.Status -in @('LeftOnly','RightOnly','TypeConflict')) { continue }
            if ($row.Status -eq 'Error') { $container.Status='Error';$container.Error='One or more descendants could not be compared.' }
            elseif ($container.Status -ne 'Error') { $container.Status='Different' }
        }
    }
    $output.ToArray()
}
