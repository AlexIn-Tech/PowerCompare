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
    if ($payload.Length -gt 2097152) { throw 'Editable text exceeds the 2 MiB limit.' }
    $bytes=[byte[]]($codec.GetPreamble()+$payload)
    $CancellationToken.ThrowIfCancellationRequested()
    New-PCReadOnlyRecord @{Version=1;Kind='TextEdit';Path=$full;ExpectedIdentity=$ExpectedIdentity;Encoding=$codec.WebName;HasBom=[bool]$HasBom;Newline=$Newline;BytesBase64=[Convert]::ToBase64String($bytes);InputIdentities=$guards.AsReadOnly()}
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
    try {
        $bytes=[Convert]::FromBase64String($Plan.BytesBase64)
        if ($bytes.Length -gt 2097156) { throw 'Editable text exceeds the 2 MiB limit.' }
        $stage=[IO.Path]::Combine([IO.Path]::GetDirectoryName($path),('.powercompare-'+[guid]::NewGuid()+'.tmp'))
        $stream=[IO.File]::Open($stage,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            for ($offset=0;$offset -lt $bytes.Length;$offset+=65536) {
                $CancellationToken.ThrowIfCancellationRequested()
                $stream.Write($bytes,$offset,[Math]::Min(65536,$bytes.Length-$offset))
            }
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        if ((Get-PCFileIdentity $path $CancellationToken) -cne $Plan.ExpectedIdentity) { throw 'File changed during save.' }
        foreach($input in $Plan.InputIdentities){if((Get-PCFileIdentity $input.Path $CancellationToken) -cne $input.Identity){throw 'Merge input changed during save.'}}
        $savedIdentity=Get-PCFileIdentity $stage $CancellationToken
        $CancellationToken.ThrowIfCancellationRequested(); Assert-PCNoLink $path
        if ($Plan.ExpectedIdentity -eq '<missing>') { [IO.File]::Move($stage,$path) }
        else {
            $backup=$path+'.powercompare-backup-'+[guid]::NewGuid().ToString('N')
            [IO.File]::Replace($stage,$path,$backup)
        }
        $stage=$null
        # Once committed, always return the outcome even if cancellation arrived.
        [pscustomobject]@{Status='Saved';Path=$path;BackupPath=$backup;Identity=$savedIdentity}
    } finally { if ($stage -and [IO.File]::Exists($stage)) { [IO.File]::Delete($stage) } }
}
