function Get-PCTextDocument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [ValidateRange(1, 67108864)][int]$MaxBytes = 2097152,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None)
    $CancellationToken.ThrowIfCancellationRequested()
    $stream = Open-PCResourceRead -Uri ([uri][IO.Path]::GetFullPath($Path))
    try {
        if ($stream.Length -gt $MaxBytes) { return [pscustomobject]@{ Kind='TooLarge'; Text=$null; Encoding=$null; HasBom=$false; Newline=$null; Error="Preview exceeds $MaxBytes bytes." } }
        $bytes = [byte[]]::new([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $CancellationToken.ThrowIfCancellationRequested()
            $count = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($count -eq 0) { throw 'File changed while reading text preview.' }
            $offset += $count
        }
    } finally { $stream.Dispose() }
    $bom = 0
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    if ($bytes.Length -ge 4 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254 -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) {
        $encoding = [Text.UTF32Encoding]::new($false, $true, $true); $bom = 4
    } elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 254 -and $bytes[3] -eq 255) {
        $encoding = [Text.UTF32Encoding]::new($true, $true, $true); $bom = 4
    } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        $bom = 3
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
        $encoding = [Text.UnicodeEncoding]::new($false, $true, $true); $bom = 2
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) {
        $encoding = [Text.UnicodeEncoding]::new($true, $true, $true); $bom = 2
    }
    try {
        $text = $encoding.GetString($bytes, $bom, $bytes.Length - $bom)
        if ($text.IndexOf([char]0) -ge 0 -or $text -match '[\x01-\x08\x0B\x0E-\x1F]') { throw 'Binary control characters detected.' }
        [pscustomobject]@{ Kind='Text'; Text=$text; Encoding=$encoding.WebName; HasBom=($bom -gt 0); Newline=(Get-PCNewlineStyle $text); Error=$null }
    } catch {
        [pscustomobject]@{ Kind='Binary'; Text=$null; Encoding=$null; HasBom=($bom -gt 0); Newline=$null; Error=$_.Exception.Message }
    }
}

function Get-PCNewlineStyle {
    param([AllowEmptyString()][string]$Text)
    $styles = [Collections.Generic.HashSet[string]]::new()
    foreach ($match in [regex]::Matches($Text, '\r\n|\n|\r')) {
        $style = if ($match.Value -eq "`r`n") { 'CRLF' } elseif ($match.Value -eq "`n") { 'LF' } else { 'CR' }
        [void]$styles.Add($style)
    }
    if ($styles.Count -eq 0) { 'None' } elseif ($styles.Count -eq 1) { @($styles)[0] } else { 'Mixed' }
}

function New-PCTextRow {
    param($LeftNumber, $RightNumber, [AllowEmptyString()][string]$LeftText, [AllowEmptyString()][string]$RightText, [string]$Status)
    $start = 0; $suffix = 0
    if ($Status -ne 'Equal') {
        while ($start -lt [Math]::Min($LeftText.Length, $RightText.Length) -and $LeftText[$start] -ceq $RightText[$start]) { $start++ }
        while ($suffix -lt [Math]::Min($LeftText.Length, $RightText.Length) - $start -and $LeftText[$LeftText.Length - 1 - $suffix] -ceq $RightText[$RightText.Length - 1 - $suffix]) { $suffix++ }
    }
    if ($Status -ne 'Equal') {
        if ($start -gt 0 -and $start -lt $LeftText.Length -and [char]::IsHighSurrogate($LeftText[$start-1]) -and [char]::IsLowSurrogate($LeftText[$start])) { $start-- }
        $boundary=$LeftText.Length-$suffix
        if ($suffix -gt 0 -and $boundary -gt 0 -and [char]::IsHighSurrogate($LeftText[$boundary-1]) -and [char]::IsLowSurrogate($LeftText[$boundary])) { $suffix-- }
    }
    [pscustomobject]@{
        LeftLineNumber=$LeftNumber; RightLineNumber=$RightNumber; LeftText=$LeftText; RightText=$RightText; Status=$Status
        LeftChangeStart=$start; RightChangeStart=$start
        LeftChangeLength=if ($Status -eq 'Equal') { 0 } else { $LeftText.Length - $start - $suffix }
        RightChangeLength=if ($Status -eq 'Equal') { 0 } else { $RightText.Length - $start - $suffix }
    }
}

function Compare-PCText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$LeftText,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RightText,
        [switch]$IgnoreWhitespace, [switch]$IgnoreCase,
        [ValidateRange(1, 16000000)][int]$MaxAlignmentCells = 4000000,
        [ValidateRange(1, 100000)][int]$MaxLines = 20000,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )
    $CancellationToken.ThrowIfCancellationRequested()
    $splitter=[regex]::new('\r\n|\n|\r')
    $left = @(if ($LeftText.Length) { $splitter.Split($LeftText, $MaxLines+1) })
    $right = @(if ($RightText.Length) { $splitter.Split($RightText, $MaxLines+1) })
    if ($left.Count -gt $MaxLines -or $right.Count -gt $MaxLines) {
        return [pscustomobject]@{Kind='TooLarge';Rows=@();Alignment='Unavailable';HasDifferences=$null;NewlineDifference=$null}
    }
    $lkeys = @($left | ForEach-Object { if ($IgnoreWhitespace) { [regex]::Replace($_, '\s', '') } else { $_ } })
    $rkeys = @($right | ForEach-Object { if ($IgnoreWhitespace) { [regex]::Replace($_, '\s', '') } else { $_ } })
    $comparer = if ($IgnoreCase) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $rows = [Collections.Generic.List[object]]::new()
    $alignment = 'Exact'
    $n = $left.Count; $m = $right.Count
    if ([long]($n + 1) * [long]($m + 1) -gt $MaxAlignmentCells) {
        $alignment = 'Limited'
        for ($i = 0; $i -lt [Math]::Max($n, $m); $i++) {
            $CancellationToken.ThrowIfCancellationRequested()
            $ln = if ($i -lt $n) { $i + 1 } else { $null }; $rn = if ($i -lt $m) { $i + 1 } else { $null }
            $lt = if ($ln) { $left[$i] } else { '' }; $rt = if ($rn) { $right[$i] } else { '' }
            $status = if (-not $ln) { 'Added' } elseif (-not $rn) { 'Removed' } elseif ($comparer.Equals($lkeys[$i], $rkeys[$i])) { 'Equal' } else { 'Changed' }
            $rows.Add((New-PCTextRow $ln $rn $lt $rt $status))
        }
    } else {
        $table = [int[,]]::new($n + 1, $m + 1)
        for ($i = $n - 1; $i -ge 0; $i--) {
            $CancellationToken.ThrowIfCancellationRequested()
            for ($j = $m - 1; $j -ge 0; $j--) {
                if ($comparer.Equals($lkeys[$i], $rkeys[$j])) { $table[$i, $j] = 1 + $table[($i + 1), ($j + 1)] }
                else {
                    $down=$table[($i + 1), $j]
                    $across=$table[$i, ($j + 1)]
                    $table[$i, $j] = [Math]::Max($down, $across)
                }
            }
        }
        $i = 0; $j = 0
        while ($i -lt $n -or $j -lt $m) {
            if ($i -lt $n -and $j -lt $m -and $comparer.Equals($lkeys[$i], $rkeys[$j])) {
                $rows.Add((New-PCTextRow ($i + 1) ($j + 1) $left[$i] $right[$j] 'Equal')); $i++; $j++; continue
            }
            $removed = [Collections.Generic.List[int]]::new(); $added = [Collections.Generic.List[int]]::new()
            while (($i -lt $n -or $j -lt $m) -and -not ($i -lt $n -and $j -lt $m -and $comparer.Equals($lkeys[$i], $rkeys[$j]))) {
                if ($i -lt $n -and ($j -ge $m -or $table[($i + 1), $j] -ge $table[$i, ($j + 1)])) { $removed.Add($i); $i++ }
                else { $added.Add($j); $j++ }
            }
            for ($k = 0; $k -lt [Math]::Max($removed.Count, $added.Count); $k++) {
                $ln = if ($k -lt $removed.Count) { $removed[$k] + 1 } else { $null }
                $rn = if ($k -lt $added.Count) { $added[$k] + 1 } else { $null }
                $lt = if ($ln) { $left[$ln - 1] } else { '' }; $rt = if ($rn) { $right[$rn - 1] } else { '' }
                $status = if (-not $ln) { 'Added' } elseif (-not $rn) { 'Removed' } else { 'Changed' }
                $rows.Add((New-PCTextRow $ln $rn $lt $rt $status))
            }
        }
    }
    $leftBreaks=@([regex]::Matches($LeftText, '\r\n|\n|\r') | ForEach-Object Value)
    $rightBreaks=@([regex]::Matches($RightText, '\r\n|\n|\r') | ForEach-Object Value)
    $leftEndings=$leftBreaks -join '|'
    $rightEndings=$rightBreaks -join '|'
    foreach ($row in $rows) {
        $le=if ($row.LeftLineNumber -and $row.LeftLineNumber -le $leftBreaks.Count) { Get-PCNewlineStyle $leftBreaks[$row.LeftLineNumber-1] } else {'None'}
        $re=if ($row.RightLineNumber -and $row.RightLineNumber -le $rightBreaks.Count) { Get-PCNewlineStyle $rightBreaks[$row.RightLineNumber-1] } else {'None'}
        $row | Add-Member -NotePropertyName LeftLineEnding -NotePropertyValue $le
        $row | Add-Member -NotePropertyName RightLineEnding -NotePropertyValue $re
        if ($row.Status -eq 'Equal' -and $le -ne $re) { $row.Status='LineEnding' }
    }
    $newlineDifference = $leftEndings -cne $rightEndings
    [pscustomobject]@{
        Kind='Text'; Rows=$rows.ToArray(); Alignment=$alignment
        HasDifferences=($newlineDifference -or @($rows | Where-Object Status -NE 'Equal').Count -gt 0)
        NewlineDifference=$newlineDifference
    }
}

function Compare-PCTextFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LeftPath, [Parameter(Mandatory)][string]$RightPath,
        [ValidateRange(1, 67108864)][int]$MaxBytes = 2097152,
        [ValidateRange(1, 16000000)][int]$MaxAlignmentCells = 4000000,
        [ValidateRange(1, 100000)][int]$MaxLines = 20000,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None)
    $left = Get-PCTextDocument -Path $LeftPath -MaxBytes $MaxBytes -CancellationToken $CancellationToken
    $right = Get-PCTextDocument -Path $RightPath -MaxBytes $MaxBytes -CancellationToken $CancellationToken
    if ($left.Kind -ne 'Text' -or $right.Kind -ne 'Text') {
        $kind = if ($left.Kind -eq 'TooLarge' -or $right.Kind -eq 'TooLarge') { 'TooLarge' } else { 'Binary' }
        return [pscustomobject]@{ Kind=$kind; Rows=@(); HasDifferences=$null; Alignment='Unavailable'; LeftDocument=$left; RightDocument=$right; NewlineDifference=$null }
    }
    $result = Compare-PCText -LeftText $left.Text -RightText $right.Text -MaxAlignmentCells $MaxAlignmentCells -MaxLines $MaxLines -CancellationToken $CancellationToken
    [pscustomobject]@{ Kind=$result.Kind; Rows=$result.Rows; HasDifferences=$result.HasDifferences; Alignment=$result.Alignment
        LeftDocument=$left; RightDocument=$right; NewlineDifference=$result.NewlineDifference }
}
