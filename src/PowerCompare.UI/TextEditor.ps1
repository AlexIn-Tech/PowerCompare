function Test-PCTextEditorDirty {
    param([AllowEmptyString()][string]$Original,[AllowEmptyString()][string]$Current)
    -not [StringComparer]::Ordinal.Equals($Original,$Current)
}

function Get-PCEditorNewlineStyle {
    param([AllowEmptyString()][string]$Text)
    $styles=[Collections.Generic.HashSet[string]]::new()
    foreach($match in [regex]::Matches($Text,'\r\n|\n|\r')){
        [void]$styles.Add($(if($match.Value -eq "`r`n"){'CRLF'}elseif($match.Value -eq "`n"){'LF'}else{'CR'}))
    }
    if($styles.Count -eq 0){'None'}elseif($styles.Count -eq 1){@($styles)[0]}else{'Mixed'}
}

function ConvertTo-PCEditorSaveText {
    param([AllowEmptyString()][string]$Text,[string]$OriginalNewline,[ValidateSet('Preserve','LF','CRLF','CR')][string]$SelectedNewline='Preserve')
    if ($SelectedNewline -eq 'Preserve') {
        if ($OriginalNewline -eq 'Mixed') { throw 'Mixed line endings require an explicit LF, CRLF or CR save choice.' }
        $SelectedNewline=if ($OriginalNewline -in @('LF','CRLF','CR')) {$OriginalNewline} else {'CRLF'}
    }
    $delimiter=switch($SelectedNewline){'LF'{"`n"}'CRLF'{"`r`n"}'CR'{"`r"}}
    [regex]::Replace($Text,'\r\n|\n|\r',$delimiter)
}

function Find-PCTextMatch {
    param([AllowEmptyString()][string]$Text,[AllowEmptyString()][string]$Query,[int]$Start=0,[switch]$IgnoreCase)
    if (-not $Query) { return $null }
    $comparison=if($IgnoreCase){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    $Start=[Math]::Max(0,[Math]::Min($Start,$Text.Length));$index=$Text.IndexOf($Query,$Start,$comparison)
    if($index -lt 0 -and $Start -gt 0){$index=$Text.IndexOf($Query,0,$comparison)}
    if($index -ge 0){[pscustomobject]@{Start=$index;Length=$Query.Length}}
}

function Set-PCTextMatches {
    param([AllowEmptyString()][string]$Text,[AllowEmptyString()][string]$Query,[AllowEmptyString()][string]$Replacement,[switch]$IgnoreCase)
    if(-not $Query){return $Text}
    $options=[Text.RegularExpressions.RegexOptions]::CultureInvariant
    if($IgnoreCase){$options=$options -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase}
    $regex=[regex]::new([regex]::Escape($Query),$options,[timespan]::FromSeconds(2))
    $evaluator=[Text.RegularExpressions.MatchEvaluator]{param($match) $Replacement}.GetNewClosure()
    $regex.Replace($Text,$evaluator)
}

function New-PCTextEditorWindow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[string]$PeerText,[object]$Session,
        [AllowEmptyString()][string]$InitialText,[object[]]$InputSession=@(),[object]$Owner)
    $reader=[Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'TextEditor.xaml'))
    try{$window=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    if($Owner){$window.Owner=$Owner}
    $controls=@{};foreach($name in 'EditorText','EditorStatus','EditorPath','SaveEdit','UndoEdit','RedoEdit','WrapEdit','SaveNewline','SearchText','ReplacementText','FindText','ReplaceText','SearchIgnoreCase','CompareIgnoreCase','CompareIgnoreWhitespace','EditorComparison'){$controls[$name]=$window.FindName($name)}
    $controls.EditorPath.Text=$Path
    $state=@{Session=$null;Worker=$null;Operation='';Generation=[long]0;Due=[datetime]::MaxValue;Loading=$true;OriginalEditorText='';PeerText=$PeerText;InputSession=$InputSession;Error=$false;Saved=$false}
    $window.Tag=$state
    $start={param($Operation,$Request)
        if($state.Worker){Close-PCComparisonWorker $state.Worker;$state.Worker=$null}
        $state.Generation++;$state.Operation=$Operation
        $state.Worker=Start-PCOperationWorker -Operation $Operation -Request $Request -Generation $state.Generation
    }.GetNewClosure()
    $hasInitial=$PSBoundParameters.ContainsKey('InitialText')
    $hasPeer=$PSBoundParameters.ContainsKey('PeerText')
    $initialize={param($LoadedSession)
        $state.Session=$LoadedSession;$state.Loading=$true
        $text=if($hasInitial){$InitialText}else{$LoadedSession.Document.Text}
        $controls.EditorText.IsUndoEnabled=$false
        $controls.EditorText.Text=$text
        $controls.EditorText.IsUndoEnabled=$true
        $state.EditNewline=if($hasInitial){Get-PCEditorNewlineStyle $InitialText}else{$LoadedSession.Document.Newline}
        $state.OriginalEditorText=[regex]::Replace($LoadedSession.Document.Text,'\r\n|\n|\r',"`r`n")
        if(-not $hasInitial){$state.OriginalEditorText=$controls.EditorText.Text}
        $controls.EditorText.IsEnabled=$true;$controls.SaveEdit.IsEnabled=$true
        $state.Loading=$false;$state.Due=[datetime]::UtcNow
        $controls.EditorStatus.Text="$($LoadedSession.Document.Encoding); line endings: $($LoadedSession.Document.Newline). Saves retain an original-file backup."
    }.GetNewClosure()
    $controls.EditorText.Add_TextChanged({if(-not $state.Loading){$state.Due=[datetime]::UtcNow.AddMilliseconds(350);$state.Error=$false}}.GetNewClosure())
    foreach($name in 'CompareIgnoreCase','CompareIgnoreWhitespace'){$controls[$name].Add_Click({$state.Due=[datetime]::UtcNow}.GetNewClosure())}
    $controls.UndoEdit.Add_Click({$controls.EditorText.Undo()}.GetNewClosure())
    $controls.RedoEdit.Add_Click({$controls.EditorText.Redo()}.GetNewClosure())
    $controls.WrapEdit.Add_Click({$controls.EditorText.TextWrapping=if($controls.WrapEdit.IsChecked){[Windows.TextWrapping]::Wrap}else{[Windows.TextWrapping]::NoWrap}}.GetNewClosure())
    $controls.FindText.Add_Click({
        $found=Find-PCTextMatch $controls.EditorText.Text $controls.SearchText.Text -Start ($controls.EditorText.SelectionStart+$controls.EditorText.SelectionLength) -IgnoreCase:([bool]$controls.SearchIgnoreCase.IsChecked)
        if($found){$controls.EditorText.Focus();$controls.EditorText.Select($found.Start,$found.Length);$controls.EditorText.ScrollToLine($controls.EditorText.GetLineIndexFromCharacterIndex($found.Start))}
        else{$controls.EditorStatus.Text='No matching text.'}
    }.GetNewClosure())
    $controls.ReplaceText.Add_Click({
        try{$replacement=Set-PCTextMatches $controls.EditorText.Text $controls.SearchText.Text $controls.ReplacementText.Text -IgnoreCase:([bool]$controls.SearchIgnoreCase.IsChecked);$controls.EditorText.SelectAll();$controls.EditorText.SelectedText=$replacement}catch{$controls.EditorStatus.Text=$_.Exception.Message}
    }.GetNewClosure())
    $controls.SaveEdit.Add_Click({
        if(-not $state.Session -or $state.Operation -eq 'TextSave'){return}
        try{
            $newline=[string]$controls.SaveNewline.SelectedItem.Content
            $text=ConvertTo-PCEditorSaveText $controls.EditorText.Text $state.EditNewline $newline
            $answer=[Windows.MessageBox]::Show($window,"Save edited text to $($state.Session.Path)? An overwritten file is retained in an adjacent backup.",'Confirm text save',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question)
            if($answer -ne [Windows.MessageBoxResult]::Yes){return}
            $state.PendingText=$text;$state.PendingEditorText=$controls.EditorText.Text
            $controls.EditorText.IsEnabled=$false;$controls.SaveEdit.IsEnabled=$false
            & $start 'TextSave' @{Path=$state.Session.Path;Text=$text;ExpectedIdentity=$state.Session.Identity;InputSession=$state.InputSession}
            $controls.EditorStatus.Text='Saving text…'
        }catch{$state.Error=$true;$controls.EditorStatus.Text=$_.Exception.Message;$controls.EditorText.IsEnabled=$true;$controls.SaveEdit.IsEnabled=$true}
    }.GetNewClosure())
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds(100)
    $timer.Add_Tick({
        if($state.Worker){
            $finished=$state.Worker.Handle.IsCompleted
            foreach($message in @(Receive-PCWorkerMessages $state.Worker)){
                if($message.Generation -ne $state.Generation){continue}
                switch($message.Type){
                    'Model'{
                        if($state.Operation -eq 'EditLoad'){& $initialize $message.Value}
                        elseif($state.Operation -eq 'BufferText'){$controls.EditorComparison.ItemsSource=$message.Value.Rows;if(-not $state.Error){$controls.EditorStatus.Text="Unsaved changes: $((Test-PCTextEditorDirty $state.OriginalEditorText $controls.EditorText.Text)). Comparison differences: $($message.Value.HasDifferences)."}}
                    }
                    'Result'{foreach($result in $message.Rows){
                        $state.Session.Identity=$result.Identity;$state.Session.Document.Text=$state.PendingText
                        $state.Session.Document.Newline=if($state.PendingText -match "`r`n"){'CRLF'}elseif($state.PendingText -match "`n"){'LF'}elseif($state.PendingText -match "`r"){'CR'}else{'None'}
                        $state.EditNewline=Get-PCEditorNewlineStyle $state.PendingText;$state.OriginalEditorText=$state.PendingEditorText;$state.InputSession=@();$state.Saved=$true
                        $state.Error=$false;$controls.EditorStatus.Text="Saved. Backup: $($result.BackupPath)"
                    }}
                    'Error'{$state.Error=$true;$controls.EditorStatus.Text=$message.Message}
                    'Canceled'{$state.Error=$true;$controls.EditorStatus.Text='Text operation canceled.'}
                }
            }
            if($finished){Close-PCComparisonWorker $state.Worker;$state.Worker=$null;$state.Operation='';if($state.Session){$controls.EditorText.IsEnabled=$true;$controls.SaveEdit.IsEnabled=$true}}
        }
        if($state.Session -and $state.Operation -notin @('TextSave','EditLoad') -and [datetime]::UtcNow -ge $state.Due){
            $state.Due=[datetime]::MaxValue
            $reference=if($hasPeer){$state.PeerText}else{$state.Session.Document.Text}
            $edited=try{ConvertTo-PCEditorSaveText $controls.EditorText.Text $state.EditNewline ([string]$controls.SaveNewline.SelectedItem.Content)}catch{$controls.EditorText.Text}
            & $start 'BufferText' @{LeftText=$reference;RightText=$edited;IgnoreCase=[bool]$controls.CompareIgnoreCase.IsChecked;IgnoreWhitespace=[bool]$controls.CompareIgnoreWhitespace.IsChecked}
        }
    }.GetNewClosure())
    $window.Add_Closing({param($sender,$eventArgs)
        if($state.Operation -eq 'TextSave'){$eventArgs.Cancel=$true;$controls.EditorStatus.Text='Wait for the save to finish before closing.';return}
        if($state.Session -and (Test-PCTextEditorDirty $state.OriginalEditorText $controls.EditorText.Text)){
            $answer=[Windows.MessageBox]::Show($window,'Discard unsaved text changes?','Close editor',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question)
            if($answer -ne [Windows.MessageBoxResult]::Yes){$eventArgs.Cancel=$true}
        }
    }.GetNewClosure())
    $window.Add_Closed({$timer.Stop();if($state.Worker){Close-PCComparisonWorker $state.Worker;$state.Worker=$null}}.GetNewClosure())
    if($Session){& $initialize $Session}else{& $start 'EditLoad' @{Path=$Path}}
    $timer.Start()
    $window
}

function Show-PCTextEditor {
    [CmdletBinding()]
    param([string]$Path,[string]$PeerText,[object]$Session,[AllowEmptyString()][string]$InitialText,[object[]]$InputSession=@(),[object]$Owner)
    $window=New-PCTextEditorWindow @PSBoundParameters
    [void]$window.ShowDialog()
}
