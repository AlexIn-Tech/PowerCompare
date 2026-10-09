BeforeAll {
    $onWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
    $xamlPath = Join-Path $PSScriptRoot '../../src/PowerCompare.UI/MainWindow.xaml'
}
Describe 'WPF workspace smoke checks' {
    It 'loads the view and its named controls on a Windows STA thread' {
        if (-not $onWindows) { Set-ItResult -Skipped -Because 'WPF requires Windows'; return }
        $ps = [PowerShell]::Create()
        $runspace = [RunspaceFactory]::CreateRunspace()
        $runspace.ApartmentState = 'STA'; $runspace.ThreadOptions = 'ReuseThread'; $runspace.Open(); $ps.Runspace = $runspace
        try {
            [void]$ps.AddScript({
                param($Path)
                Add-Type -AssemblyName PresentationFramework
                $reader = [Xml.XmlReader]::Create($Path)
                try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
                foreach ($name in 'CompareButton','CancelButton','LeftRoot','RightRoot','ResultsGrid','WorkspaceTabs','StatusText') {
                    if (-not $window.FindName($name)) { throw "Missing control: $name" }
                }
                $window.Close()
                'Loaded'
            }).AddArgument($xamlPath)
            $output = $ps.Invoke()
            $ps.Streams.Error.Count | Should -Be 0
            $output | Should -Contain 'Loaded'
        } finally { $ps.Dispose(); $runspace.Dispose() }
    }
    It 'contains valid XML even on non-Windows hosts' {
        { [xml](Get-Content -LiteralPath $xamlPath -Raw -ErrorAction Stop) } | Should -Not -Throw
    }
}
Describe 'Windows WPF controller integration' {
    It 'dispatches comparison clicks, keeps results reusable, and closes workers' {
        if (-not $onWindows) { Set-ItResult -Skipped -Because 'WPF requires Windows'; return }
        $repo=Join-Path $PSScriptRoot '../..'
        $ps=[PowerShell]::Create();$runspace=[RunspaceFactory]::CreateRunspace()
        $runspace.ApartmentState='STA';$runspace.ThreadOptions='ReuseThread';$runspace.Open();$ps.Runspace=$runspace
        try {
            [void]$ps.AddScript({
                param($Repo,$Fixture)
                $ErrorActionPreference='Stop'
                Import-Module (Join-Path $Repo 'src/PowerCompare.Core/PowerCompare.Core.psd1') -Force
                foreach ($name in 'Workers','Controller','TextView','Operations','Application') { . (Join-Path $Repo "src/PowerCompare.UI/$name.ps1") }
                $left=Join-Path $Fixture 'left';$right=Join-Path $Fixture 'right'
                [void][IO.Directory]::CreateDirectory($left);[void][IO.Directory]::CreateDirectory($right)
                [IO.File]::WriteAllText((Join-Path $left 'a'),'x');[IO.File]::WriteAllText((Join-Path $right 'a'),'y')
                $window=New-PCMainWindow -LeftPath $left -RightPath $right
                try {
                    $collection=$window.Tag.State.Results
                    $window.Show()
                    1..2 | ForEach-Object {
                        $window.FindName('CompareButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                        $clock=[Diagnostics.Stopwatch]::StartNew()
                        while ($window.Tag.State.Worker -and $clock.Elapsed.TotalSeconds -lt 15) {
                            $frame=[Windows.Threading.DispatcherFrame]::new()
                            $pump=[Windows.Threading.DispatcherTimer]::new();$pump.Interval=[timespan]::FromMilliseconds(20)
                            $pump.Add_Tick({$frame.Continue=$false;$pump.Stop()}.GetNewClosure());$pump.Start()
                            [Windows.Threading.Dispatcher]::PushFrame($frame)
                        }
                        if ($window.Tag.State.Status -ne 'Completed') { throw "Comparison not completed: $($window.Tag.State.Message)" }
                    }
                    if (-not [object]::ReferenceEquals($collection,$window.Tag.State.Results)) { throw 'Results collection replaced.' }
                    if ($collection.Count -ne 1 -or $collection[0].Status -ne 'Different') { throw 'Incorrect comparison display.' }
                    if ($window.FindName('ResultsGrid').Items.Count -ne 1) { throw 'Results binding failed.' }
                    foreach ($name in 'TextWindow','CopyPreview') {
                        $reader=[Xml.XmlReader]::Create((Join-Path $Repo "src/PowerCompare.UI/$name.xaml"))
                        try {$view=[Windows.Markup.XamlReader]::Load($reader)} finally {$reader.Dispose()}
                        $view.Close()
                    }
                    'Verified'
                } finally { $window.Close() }
                if ($window.Tag.State.Worker) { throw 'Worker not disposed on close.' }
            }).AddArgument($repo).AddArgument($TestDrive)
            $output=$ps.Invoke()
            if ($ps.Streams.Error.Count) { throw ($ps.Streams.Error | Out-String) }
            $output | Should -Contain 'Verified'
        } finally {$ps.Dispose();$runspace.Dispose()}
    }
}
