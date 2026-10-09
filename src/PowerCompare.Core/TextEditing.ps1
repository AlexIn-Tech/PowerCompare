function Get-PCTextEditSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,
        [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    $full=Get-PCLocalPath ([uri][IO.Path]::GetFullPath($Path))
    $identity=Get-PCFileIdentity $full $CancellationToken
    if ($identity -eq '<missing>') { throw 'Text file is missing.' }
    $document=Get-PCTextDocument $full -CancellationToken $CancellationToken
    if ($document.Kind -ne 'Text') { throw "Editable text unavailable: $($document.Kind)." }
    if ((Get-PCFileIdentity $full $CancellationToken) -cne $identity) { throw 'File changed while opening the text session.' }
    [pscustomobject]@{Path=$full;Identity=$identity;Document=$document}
}

function Get-PCStrictTextEncoding {
    param([string]$Name,[bool]$HasBom)
    switch ($Name.ToLowerInvariant()) {
        'utf-8' { [Text.UTF8Encoding]::new($HasBom,$true) }
        'utf-16' { [Text.UnicodeEncoding]::new($false,$HasBom,$true) }
        'utf-16be' { [Text.UnicodeEncoding]::new($true,$HasBom,$true) }
        'utf-32' { [Text.UTF32Encoding]::new($false,$HasBom,$true) }
        'utf-32be' { [Text.UTF32Encoding]::new($true,$HasBom,$true) }
        default { throw 'Only strict UTF-8, UTF-16 and UTF-32 encodings are supported for editing.' }
    }
}

function Get-PCTextEditPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory,Position=0)][string]$Path,
        [Parameter(Mandatory,Position=1)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory,Position=2)][string]$ExpectedIdentity,
        [string]$Encoding, [Nullable[bool]]$HasBom, [object[]]$InputSession=@(),
        [ValidateSet('Preserve','LF','CRLF','CR')][string]$Newline='Preserve',
        [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    $CancellationToken.ThrowIfCancellationRequested()
    $full=[IO.Path]::GetFullPath($Path)
    if ($full.Substring([IO.Path]::GetPathRoot($full).Length).Contains(':')) { throw 'Alternate streams are not supported.' }
    Assert-PCNoLink $full
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($full))) { throw 'Output directory must exist.' }
    if ((Get-PCFileIdentity $full $CancellationToken) -cne $ExpectedIdentity) { throw 'File changed since opening. Reopen before saving.' }
    if ($ExpectedIdentity -ne '<missing>') {
        $session=Get-PCTextEditSession $full -CancellationToken $CancellationToken
        if ($session.Identity -cne $ExpectedIdentity) { throw 'File changed since opening.' }
        if (-not $Encoding) { $Encoding=$session.Document.Encoding }
        if ($null -eq $HasBom) { $HasBom=$session.Document.HasBom }
    } else {
        if (-not $Encoding) { $Encoding='utf-8' }
        if ($null -eq $HasBom) { $HasBom=$false }
    }
    if ($Newline -ne 'Preserve') {
        $delimiter=switch($Newline) { 'LF' {"`n"} 'CRLF' {"`r`n"} 'CR' {"`r"} }
        $Text=[regex]::Replace($Text,'\r\n|\n|\r',$delimiter)
    }
    $guards=[Collections.Generic.List[object]]::new()
    foreach($input in $InputSession){
        if((Get-PCFileIdentity $input.Path $CancellationToken) -cne $input.Identity){throw 'Merge input changed since preview.'}
        $guards.Add((New-PCReadOnlyRecord @{Path=$input.Path;Identity=$input.Identity}))
    }
    $codec=Get-PCStrictTextEncoding $Encoding ([bool]$HasBom)
    if (-not [bool]$HasBom -and $codec.WebName -ne 'utf-8') { throw 'UTF-16/32 saves require a BOM for unambiguous detection.' }
    # Strict encoder rejects unpaired surrogates rather than substituting data.
    $payload=$codec.GetBytes($Text)
    $bytes=[byte[]]($codec.GetPreamble()+$payload)
    if ($bytes.Length -gt 2097152) { throw 'Editable text exceeds the 2 MiB limit.' }
    $CancellationToken.ThrowIfCancellationRequested()
    New-PCReadOnlyRecord @{Version=1;Kind='TextEdit';Path=$full;ExpectedIdentity=$ExpectedIdentity;Encoding=$codec.WebName;HasBom=[bool]$HasBom;Newline=$Newline;BytesBase64=[Convert]::ToBase64String($bytes);InputIdentities=$guards.AsReadOnly()}
}

function Get-PCTextLockedIdentity {
    param([string]$Path,[IO.FileStream]$Stream,[Threading.CancellationToken]$CancellationToken)
    $info=[IO.FileInfo]::new($Path);$length=$info.Length;$ticks=$info.LastWriteTimeUtc.Ticks
    if($length -ne $Stream.Length){throw 'File changed during save.'}
    $Stream.Position=0;$sha=[Security.Cryptography.SHA256]::Create()
    try{
        $buffer=[byte[]]::new(65536)
        while($true){$CancellationToken.ThrowIfCancellationRequested();$count=$Stream.Read($buffer,0,$buffer.Length);if($count -eq 0){break};[void]$sha.TransformBlock($buffer,0,$count,$buffer,0)}
        [void]$sha.TransformFinalBlock([byte[]]@(),0,0)
        $hash=[BitConverter]::ToString($sha.Hash).Replace('-','')
    }finally{$sha.Dispose()}
    $info.Refresh();if($info.Length -ne $length -or $info.LastWriteTimeUtc.Ticks -ne $ticks){throw 'File changed during save.'}
    "$length|$ticks|$hash"
}

function Get-PCTextSaveIdentity {
    param([string]$Path,[object]$Locks,[Threading.CancellationToken]$CancellationToken)
    if($Locks.ContainsKey($Path)){Get-PCTextLockedIdentity $Path $Locks[$Path] $CancellationToken}
    else{Get-PCFileIdentity $Path $CancellationToken}
}

function Invoke-PCTextEditPlan {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
    param([Parameter(Mandatory,Position=0)][object]$Plan,
        [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    if ($Plan.Version -ne 1 -or $Plan.Kind -ne 'TextEdit') { throw 'Unsupported text edit plan.' }
    $CancellationToken.ThrowIfCancellationRequested()
    $path=[IO.Path]::GetFullPath($Plan.Path)
    if ($path.Substring([IO.Path]::GetPathRoot($path).Length).Contains(':')) { throw 'Alternate streams are not supported.' }
    Assert-PCNoLink $path
    if ((Get-PCFileIdentity $path $CancellationToken) -cne $Plan.ExpectedIdentity) { throw 'File changed since preview. Reopen before saving.' }
    foreach($input in $Plan.InputIdentities){if((Get-PCFileIdentity $input.Path $CancellationToken) -cne $input.Identity){throw 'Merge input changed since preview.'}}
    if (-not $PSCmdlet.ShouldProcess($path,'Save edited text with an original-file backup')) {
        return [pscustomobject]@{Status='Skipped';Path=$path;BackupPath=$null;Identity=$Plan.ExpectedIdentity}
    }
    $stage=$null; $backup=$null
    $pathComparer=if([Environment]::OSVersion.Platform -eq 'Win32NT'){[StringComparer]::OrdinalIgnoreCase}else{[StringComparer]::Ordinal}
    $locks=[Collections.Generic.Dictionary[string,IO.FileStream]]::new($pathComparer)
    try {
        # Deny direct writes while checking/staging. Windows permits our atomic replacement.
        $paths=@($path)+@($Plan.InputIdentities | ForEach-Object {$_.Path})
        foreach($lockedPath in $paths){
            if($locks.ContainsKey($lockedPath) -or -not [IO.File]::Exists($lockedPath)){continue}
            Assert-PCNoLink $lockedPath
            $share=if([Environment]::OSVersion.Platform -ne 'Win32NT'){[IO.FileShare]::None}elseif($pathComparer.Equals($lockedPath,$path)){[IO.FileShare]::Read -bor [IO.FileShare]::Delete}else{[IO.FileShare]::Read}
            $locks.Add($lockedPath,[IO.File]::Open($lockedPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share))
        }
        if((Get-PCTextSaveIdentity $path $locks $CancellationToken) -cne $Plan.ExpectedIdentity){throw 'File changed before save locking.'}
        foreach($input in $Plan.InputIdentities){if((Get-PCTextSaveIdentity $input.Path $locks $CancellationToken) -cne $input.Identity){throw 'Merge input changed before save locking.'}}
        $bytes=[Convert]::FromBase64String($Plan.BytesBase64)
        if ($bytes.Length -gt 2097152) { throw 'Editable text exceeds the 2 MiB limit.' }
        $stage=[IO.Path]::Combine([IO.Path]::GetDirectoryName($path),('.powercompare-'+[guid]::NewGuid()+'.tmp'))
        $stream=[IO.File]::Open($stage,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            for ($offset=0;$offset -lt $bytes.Length;$offset+=65536) {
                $CancellationToken.ThrowIfCancellationRequested()
                $stream.Write($bytes,$offset,[Math]::Min(65536,$bytes.Length-$offset))
            }
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        $savedIdentity=Get-PCFileIdentity $stage $CancellationToken
        if ((Get-PCTextSaveIdentity $path $locks $CancellationToken) -cne $Plan.ExpectedIdentity) { throw 'File changed during save.' }
        foreach($input in $Plan.InputIdentities){if((Get-PCTextSaveIdentity $input.Path $locks $CancellationToken) -cne $input.Identity){throw 'Merge input changed during save.'}}
        $CancellationToken.ThrowIfCancellationRequested(); Assert-PCNoLink $path
        if ($Plan.ExpectedIdentity -eq '<missing>') { [IO.File]::Move($stage,$path) }
        else {
            $backup=$path+'.powercompare-backup-'+[guid]::NewGuid().ToString('N')
            [IO.File]::Replace($stage,$path,$backup)
        }
        $stage=$null
        foreach($held in $locks.Values){$held.Dispose()};$locks.Clear()
        # A namespace replacement can bypass share locks. Validate the actual original
        # retained by atomic replacement and recover it instead of accepting the race.
        if($backup -and (Get-PCFileIdentity $backup) -cne $Plan.ExpectedIdentity){
            if((Get-PCFileIdentity $path) -ceq $savedIdentity){
                $rejected=$path+'.powercompare-rejected-'+[guid]::NewGuid().ToString('N')
                [IO.File]::Replace($backup,$path,$rejected)
                throw "Concurrent replacement detected; external content restored. Proposed output retained: $rejected"
            }
            throw "Concurrent replacement detected; output changed again. External original retained: $backup"
        }
        # Once committed, always return the outcome even if cancellation arrived.
        [pscustomobject]@{Status='Saved';Path=$path;BackupPath=$backup;Identity=$savedIdentity}
    } finally { foreach($held in $locks.Values){$held.Dispose()}; if ($stage -and [IO.File]::Exists($stage)) { [IO.File]::Delete($stage) } }
}
