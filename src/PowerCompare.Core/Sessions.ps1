function New-PCSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LeftPath, [Parameter(Mandatory)][string]$RightPath,
        [ValidateSet('Content','Metadata')][string]$Mode='Content', [string[]]$Include=@('*'), [string[]]$Exclude=@())
    if ([string]::IsNullOrWhiteSpace($LeftPath) -or [string]::IsNullOrWhiteSpace($RightPath)) { throw 'Session roots cannot be empty.' }
    if ($LeftPath -match '://' -or $RightPath -match '://') { throw 'This session schema supports local folder paths only.' }
    [pscustomobject]@{ Version=1; LeftPath=$LeftPath; RightPath=$RightPath; Mode=$Mode; Include=@($Include); Exclude=@($Exclude) }
}

function ConvertTo-PCValidatedSession {
    param([object]$Session)
    if ($null -eq $Session -or $Session -is [array] -or $Session -is [string]) { throw 'Invalid session object.' }
    $names=@($Session.PSObject.Properties.Name)
    foreach ($name in $names) { if ($name -notin @('Version','LeftPath','RightPath','Mode','Include','Exclude')) { throw "Unknown session field: $name" } }
    foreach ($name in 'Version','LeftPath','RightPath','Mode') { if ($name -notin $names) { throw "Missing session field: $name" } }
    if ($Session.Version -ne 1 -or ($Session.Version -isnot [int] -and $Session.Version -isnot [long])) { throw 'Unsupported session version.' }
    foreach ($name in 'LeftPath','RightPath','Mode') { if ($Session.$name -isnot [string]) { throw "Invalid session field: $name" } }
    $params=@{LeftPath=$Session.LeftPath;RightPath=$Session.RightPath;Mode=$Session.Mode}
    foreach ($name in 'Include','Exclude') {
        if ($name -in $names) {
            if ($null -eq $Session.$name -or $Session.$name -isnot [array]) { throw "Session $name must be an array of masks." }
            foreach ($mask in $Session.$name) { if ($mask -isnot [string]) { throw 'Masks must be strings.' } }
            $params[$name]=[string[]]$Session.$name
        }
    }
    New-PCSession @params
}

function Write-PCAtomicText {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    $full=[IO.Path]::GetFullPath($Path); Assert-PCNoLink $full
    $directory=[IO.Path]::GetDirectoryName($full)
    [void][IO.Directory]::CreateDirectory($directory)
    Assert-PCNoLink $directory
    $stage=[IO.Path]::Combine($directory, '.powercompare-' + [guid]::NewGuid() + '.tmp')
    try {
        [IO.File]::WriteAllText($stage, $Text, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($full)) { [IO.File]::Replace($stage,$full,$full + '.powercompare-backup-' + [guid]::NewGuid().ToString('N')) }
        else { [IO.File]::Move($stage,$full) }
    } finally { if ([IO.File]::Exists($stage)) { [IO.File]::Delete($stage) } }
}

function Save-PCSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Session, [Parameter(Mandatory)][string]$Path)
    $validated=ConvertTo-PCValidatedSession $Session
    Write-PCAtomicText -Path $Path -Text (ConvertTo-Json -InputObject $validated -Depth 4)
}

function Import-PCSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $doc=Get-PCTextDocument -Path $Path -MaxBytes 1048576
    if ($doc.Kind -ne 'Text') { throw 'Session must be a UTF JSON document no larger than 1 MiB.' }
    $session=ConvertFrom-Json -InputObject $doc.Text -ErrorAction Stop
    ConvertTo-PCValidatedSession $session
}

function Export-PCComparisonReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][string]$Path, [ValidateSet('Json','Csv','Html')][string]$Format='Json')
    $columns=@('RelativePath','EntryType','Status','ComparisonMode','LeftPath','RightPath','LeftLength','RightLength','LeftLastWriteTimeUtc','RightLastWriteTimeUtc','Error')
    $records=@($Rows | Select-Object -Property $columns)
    $text=switch ($Format) {
        'Json' { ConvertTo-Json -InputObject $records -Depth 6 }
        'Csv' {
            if ($records.Count) { ($records | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine }
            else { '"' + ($columns -join '","') + '"' }
        }
        'Html' {
            ($records | ConvertTo-Html -Title 'PowerCompare comparison report' -PreContent '<h1>PowerCompare comparison report</h1>' -Property $columns) -join [Environment]::NewLine
        }
    }
    Write-PCAtomicText -Path $Path -Text $text
}
