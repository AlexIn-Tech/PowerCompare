function Get-PCMergeTokens {
    param([AllowEmptyString()][string]$Text)
    $tokens=[Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Text,'[^\r\n]*(?:\r\n|\n|\r)|[^\r\n]+$')) { $tokens.Add($match.Value) }
    ,$tokens.ToArray()
}

function Get-PCMergeEdits {
    param([string[]]$Base,[string[]]$Changed,[string]$Side,[long]$MaxAlignmentCells,[Threading.CancellationToken]$CancellationToken)
    if ([long]($Base.Count+1)*($Changed.Count+1) -gt $MaxAlignmentCells) { throw 'Exact merge alignment exceeds the configured cell limit.' }
    $table=[int[,]]::new($Base.Count+1,$Changed.Count+1)
    for ($i=$Base.Count-1;$i -ge 0;$i--) {
        $CancellationToken.ThrowIfCancellationRequested()
        for ($j=$Changed.Count-1;$j -ge 0;$j--) {
            if ([StringComparer]::Ordinal.Equals($Base[$i],$Changed[$j])) { $table[$i,$j]=1+$table[($i+1),($j+1)] }
            else { $down=$table[($i+1),$j]; $across=$table[$i,($j+1)]; $table[$i,$j]=[Math]::Max($down,$across) }
        }
    }
    $i=0; $j=0; $start=-1; $inserted=[Collections.Generic.List[string]]::new()
    while ($i -lt $Base.Count -or $j -lt $Changed.Count) {
        $CancellationToken.ThrowIfCancellationRequested()
        if ($i -lt $Base.Count -and $j -lt $Changed.Count -and [StringComparer]::Ordinal.Equals($Base[$i],$Changed[$j])) {
            if ($start -ge 0) { [pscustomobject]@{Start=$start;End=$i;Text=($inserted -join '');Side=$Side};$start=-1;$inserted.Clear() }
            $i++;$j++;continue
        }
        if ($start -lt 0) { $start=$i }
        if ($j -lt $Changed.Count -and ($i -eq $Base.Count -or $table[$i,($j+1)] -gt $table[($i+1),$j])) { $inserted.Add($Changed[$j]);$j++ }
        else { $i++ }
    }
    if ($start -ge 0) { [pscustomobject]@{Start=$start;End=$i;Text=($inserted -join '');Side=$Side} }
}

function Test-PCMergeEditOverlap {
    param($A,$B)
    if ($A.Start -eq $A.End -and $B.Start -eq $B.End) { return $A.Start -eq $B.Start }
    if ($A.Start -eq $A.End) { return $A.Start -ge $B.Start -and $A.Start -lt $B.End }
    if ($B.Start -eq $B.End) { return $B.Start -ge $A.Start -and $B.Start -lt $A.End }
    $A.Start -lt $B.End -and $B.Start -lt $A.End
}

function Get-PCMergeRegionText {
    param([string[]]$Base,[int]$Start,[int]$End,[object[]]$Edits)
    $result=[Text.StringBuilder]::new();$cursor=$Start
    foreach ($edit in ($Edits | Sort-Object Start,End)) {
        while ($cursor -lt $edit.Start) { [void]$result.Append($Base[$cursor]);$cursor++ }
        [void]$result.Append($edit.Text);$cursor=$edit.End
    }
    while ($cursor -lt $End) { [void]$result.Append($Base[$cursor]);$cursor++ }
    $result.ToString()
}

function Merge-PCText {
    [CmdletBinding()]
    param([Parameter(Mandatory,Position=0)][AllowEmptyString()][string]$BaseText,
        [Parameter(Mandatory,Position=1)][AllowEmptyString()][string]$LeftText,
        [Parameter(Mandatory,Position=2)][AllowEmptyString()][string]$RightText,
        [ValidateRange(1,16000000)][long]$MaxAlignmentCells=4000000,
        [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    $CancellationToken.ThrowIfCancellationRequested()
    if ([Math]::Max($BaseText.Length,[Math]::Max($LeftText.Length,$RightText.Length)) -gt 2097152) { throw 'Text merge exceeds the document size limit.' }
    $base=Get-PCMergeTokens $BaseText; $left=Get-PCMergeTokens $LeftText; $right=Get-PCMergeTokens $RightText
    $edits=@(Get-PCMergeEdits $base $left 'Left' $MaxAlignmentCells $CancellationToken)+@(Get-PCMergeEdits $base $right 'Right' $MaxAlignmentCells $CancellationToken)
    $groups=[Collections.Generic.List[object]]::new();$group=[Collections.Generic.List[object]]::new()
    foreach ($edit in ($edits | Sort-Object Start,End,Side)) {
        $overlap=$false
        foreach ($member in $group) { if (Test-PCMergeEditOverlap $member $edit) { $overlap=$true;break } }
        if ($group.Count -and -not $overlap) { $groups.Add($group.ToArray());$group.Clear() }
        $group.Add($edit)
    }
    if ($group.Count) { $groups.Add($group.ToArray()) }
    $segments=[Collections.Generic.List[object]]::new();$conflicts=[Collections.Generic.List[object]]::new();$cursor=0;$leftCursor=0;$rightCursor=0
    foreach ($members in $groups) {
        $CancellationToken.ThrowIfCancellationRequested()
        $start=[int](($members | Measure-Object Start -Minimum).Minimum);$end=[int](($members | Measure-Object End -Maximum).Maximum)
        if ($cursor -lt $start) {
            $unchanged=Get-PCMergeRegionText $base $cursor $start @()
            $segments.Add((New-PCReadOnlyRecord @{Kind='Unchanged';Text=$unchanged;BaseStart=$cursor;BaseCount=$start-$cursor;LeftStart=$leftCursor;LeftCount=$start-$cursor;RightStart=$rightCursor;RightCount=$start-$cursor}))
            $leftCursor+=$start-$cursor;$rightCursor+=$start-$cursor
        }
        $baseRegion=Get-PCMergeRegionText $base $start $end @()
        $leftEdits=@($members | Where-Object Side -EQ 'Left');$rightEdits=@($members | Where-Object Side -EQ 'Right')
        $leftRegion=Get-PCMergeRegionText $base $start $end $leftEdits
        $rightRegion=Get-PCMergeRegionText $base $start $end $rightEdits
        $leftCount=(Get-PCMergeTokens $leftRegion).Count;$rightCount=(Get-PCMergeTokens $rightRegion).Count
        if ($leftEdits.Count -and $rightEdits.Count -and -not [StringComparer]::Ordinal.Equals($leftRegion,$rightRegion)) {
            $conflict=New-PCReadOnlyRecord @{Kind='Conflict';Id=('conflict-'+($conflicts.Count+1));BaseStart=$start;BaseCount=$end-$start;LeftStart=$leftCursor;LeftCount=$leftCount;RightStart=$rightCursor;RightCount=$rightCount;BaseText=$baseRegion;LeftText=$leftRegion;RightText=$rightRegion}
            $segments.Add($conflict);$conflicts.Add($conflict)
        } else {
            $text=if ($leftEdits.Count) { $leftRegion } else { $rightRegion }
            $segments.Add((New-PCReadOnlyRecord @{Kind='Merged';Text=$text;BaseStart=$start;BaseCount=$end-$start;LeftStart=$leftCursor;LeftCount=$leftCount;RightStart=$rightCursor;RightCount=$rightCount}))
        }
        $cursor=$end;$leftCursor+=$leftCount;$rightCursor+=$rightCount
    }
    if ($cursor -lt $base.Count) { $segments.Add((New-PCReadOnlyRecord @{Kind='Unchanged';Text=(Get-PCMergeRegionText $base $cursor $base.Count @());BaseStart=$cursor;BaseCount=$base.Count-$cursor;LeftStart=$leftCursor;LeftCount=$base.Count-$cursor;RightStart=$rightCursor;RightCount=$base.Count-$cursor})) }
    $auto=if ($conflicts.Count) { $null } else { ($segments | ForEach-Object {$_.Text}) -join '' }
    [pscustomobject]@{Kind='Merge';Segments=$segments.AsReadOnly();Conflicts=$conflicts.AsReadOnly();AutoMergedText=$auto;Alignment='Exact'}
}

function Resolve-PCTextMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory,Position=0)][object]$Model,[Parameter(Mandatory,Position=1)][hashtable]$Choices)
    $output=[Text.StringBuilder]::new()
    foreach ($segment in $Model.Segments) {
        if ($segment.Kind -ne 'Conflict') { [void]$output.Append($segment.Text);continue }
        if (-not $Choices.ContainsKey($segment.Id)) { throw "Merge conflict unresolved: $($segment.Id)." }
        $text=switch -CaseSensitive ($Choices[$segment.Id]) {
            'Left' {$segment.LeftText} 'Right' {$segment.RightText} 'Base' {$segment.BaseText}
            'Both' {$segment.LeftText+$segment.RightText}
            default { throw "Unsupported merge choice for $($segment.Id)." }
        }
        [void]$output.Append($text)
    }
    $output.ToString()
}
