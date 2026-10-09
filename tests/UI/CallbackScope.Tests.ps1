BeforeAll { $uiModule=Join-Path $PSScriptRoot '../../src/PowerCompare.UI/PowerCompare.UI.psm1' }
Describe 'Launcher callback command visibility' {
    It 'imports the UI commands without unapproved-verb warnings' {
        $warnings = @()
        Import-Module $uiModule -Force -WarningVariable warnings
        @($warnings).Count | Should -Be 0
    }
    It 'resolves UI and engine commands from closures after a script-scoped load' {
        $callback=& {
            param($Module)
            Import-Module $Module -Global -Force -ErrorAction Stop
            { $state=New-PCWorkspaceState; Close-PCWorkspace $state; ConvertTo-PCEditorSaveText "a`r`n" LF Preserve }.GetNewClosure()
        } $uiModule
        (& $callback) | Should -Be "a`n"
        foreach($name in 'Select-PCFolder','Close-PCWorkspace','Show-PCTextEditor','Show-PCTextMerge','Compare-PCText','Get-PCTextEditPlan') {
            $probe={Get-Command $name -ErrorAction Stop}.GetNewClosure()
            (& $probe).Name | Should -Be $name
        }
    }
}
Describe 'Actual Windows launcher callbacks' {
    It 'browses, compares and closes when launched with the call operator' {
        if([Environment]::OSVersion.Platform -ne 'Win32NT'){Set-ItResult -Skipped -Because 'WPF requires Windows';return}
        $wrapper=Join-Path $TestDrive 'launch-ui.ps1'
        $launcher=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../PowerCompare.ps1'))
        $code=@'
param([string]$Launcher,[string]$Fixture)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$app=[Windows.Application]::new()
$left=Join-Path $Fixture 'left';$right=Join-Path $Fixture 'right'
[void][IO.Directory]::CreateDirectory($left);[void][IO.Directory]::CreateDirectory($right)
[IO.File]::WriteAllText((Join-Path $left 'a'),'left');[IO.File]::WriteAllText((Join-Path $right 'a'),'right')
$state=@{Phase=0;Failure=$null;Verified=$false};$clock=[Diagnostics.Stopwatch]::StartNew()
$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromMilliseconds(50)
$timer.Add_Tick({
    if($clock.Elapsed.TotalSeconds -gt 30){[Environment]::Exit(2)}
    $window=@($app.Windows | Where-Object {$_.FindName('BrowseLeft')}) | Select-Object -First 1
    if(-not $window){return}
    try{
        if($state.Phase -eq 0){
            # Replace the external folder-dialog interaction, retaining the real callback.
            function global:Select-PCFolder { $global:PCTestFolder }
            $global:PCTestFolder=$left
            $window.FindName('BrowseLeft').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            if($window.FindName('LeftRoot').Text -cne $left){throw 'Left browse callback failed.'}
            $global:PCTestFolder=$right
            $window.FindName('BrowseRight').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            if($window.FindName('RightRoot').Text -cne $right){throw 'Right browse callback failed.'}
            $window.FindName('CompareButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            $state.Phase=1
        }elseif($state.Phase -eq 1 -and -not $window.Tag.State.Worker){
            if($window.Tag.State.Status -ne 'Completed'){throw $window.Tag.State.Message}
            if($window.Tag.State.Results.Count -ne 1 -or $window.Tag.State.Results[0].Status -ne 'Different'){throw 'Comparison callback failed.'}
            $state.Phase=2;$timer.Stop();$window.Close()
            if($window.Tag.State.Worker){throw 'Close callback did not dispose worker.'}
            $state.Verified=$true
        }
    }catch{[Console]::Error.WriteLine($_.Exception.ToString());[Environment]::Exit(1)}
})
$timer.Start()
try { & $Launcher } finally { $timer.Stop() }
if(-not $state.Verified){throw 'Launcher interaction was not verified.'}
'@
        [IO.File]::WriteAllText($wrapper,$code,[Text.UTF8Encoding]::new($true))
        $engine=(Get-Process -Id $PID).Path
        $arguments='-NoProfile -STA -File "'+$wrapper+'" -Launcher "'+$launcher+'" -Fixture "'+$TestDrive+'"'
        $process=[Diagnostics.Process]::new()
        $process.StartInfo=[Diagnostics.ProcessStartInfo]::new($engine,$arguments)
        $process.StartInfo.UseShellExecute=$false
        $process.StartInfo.RedirectStandardOutput=$true
        $process.StartInfo.RedirectStandardError=$true
        try{
            [void]$process.Start()
            $outputTask=$process.StandardOutput.ReadToEndAsync();$errorTask=$process.StandardError.ReadToEndAsync()
            if(-not $process.WaitForExit(45000)){$process.Kill();throw 'Launcher UI regression timed out.'}
            $stdout=$outputTask.GetAwaiter().GetResult();$stderr=$errorTask.GetAwaiter().GetResult()
            if($process.ExitCode -ne 0){throw "Launcher exited $($process.ExitCode). Standard error: $stderr Standard output: $stdout"}
            $process.ExitCode | Should -Be 0
        }finally{$process.Dispose()}
    }
}
