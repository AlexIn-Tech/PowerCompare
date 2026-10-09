BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../src/PowerCompare.Core/PowerCompare.Core.psd1') -Force
}
Describe 'Identity-guarded text edits' {
    BeforeEach { $path=Join-Path $TestDrive '[edit].txt'; [IO.File]::WriteAllText($path,"old`r`n",[Text.UTF8Encoding]::new($false)) }
    It 'loads a coherent text session and plans without writing' {
        $session=Get-PCTextEditSession $path
        $session.Document.Text | Should -Be "old`r`n"
        $session.Identity | Should -Not -BeNullOrEmpty
        $plan=Get-PCTextEditPlan -Path $path -Text "new`r`n" -ExpectedIdentity $session.Identity
        [IO.File]::ReadAllText($path) | Should -Be "old`r`n"
        { $plan['Text']='forged' } | Should -Throw
    }
    It 'preserves supported encoding and BOM <Name>' -TestCases @(
        @{Name='utf-8';Encoding=[Text.UTF8Encoding]::new($false,$true)},
        @{Name='utf-8-bom';Encoding=[Text.UTF8Encoding]::new($true,$true)},
        @{Name='utf-16';Encoding=[Text.UnicodeEncoding]::new($false,$true,$true)},
        @{Name='utf-16BE';Encoding=[Text.UnicodeEncoding]::new($true,$true,$true)},
        @{Name='utf-32';Encoding=[Text.UTF32Encoding]::new($false,$true,$true)},
        @{Name='utf-32BE';Encoding=[Text.UTF32Encoding]::new($true,$true,$true)}
    ) {
        param($Name,$Encoding)
        [IO.File]::WriteAllText($path,"old`r`n",$Encoding)
        $original=[IO.File]::ReadAllBytes($path)
        $session=Get-PCTextEditSession $path
        $plan=Get-PCTextEditPlan -Path $path -Text "é😀`r`n" -ExpectedIdentity $session.Identity
        $result=Invoke-PCTextEditPlan $plan -Confirm:$false
        $result.Status | Should -Be 'Saved'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($result.BackupPath)) | Should -Be ([Convert]::ToBase64String($original))
        $doc=Get-PCTextDocument $path
        $doc.Encoding | Should -Be $session.Document.Encoding
        $doc.HasBom | Should -Be $session.Document.HasBom
        $doc.Text | Should -Be "é😀`r`n"
    }
    It 'preserves mixed delimiters or normalizes only when requested' {
        $session=Get-PCTextEditSession $path
        $plan=Get-PCTextEditPlan $path "a`r`nb`nc`r" $session.Identity
        (Invoke-PCTextEditPlan $plan -Confirm:$false).Status | Should -Be 'Saved'
        [IO.File]::ReadAllText($path) | Should -Be "a`r`nb`nc`r"
        $session=Get-PCTextEditSession $path
        $plan=Get-PCTextEditPlan $path $session.Document.Text $session.Identity -Newline LF
        [void](Invoke-PCTextEditPlan $plan -Confirm:$false)
        [IO.File]::ReadAllText($path) | Should -Be "a`nb`nc`n"
    }
    It 'rejects stale edits even with preserved length and timestamp' {
        $session=Get-PCTextEditSession $path
        $plan=Get-PCTextEditPlan $path 'new' $session.Identity
        $stamp=[IO.File]::GetLastWriteTimeUtc($path)
        [IO.File]::WriteAllText($path,"bad`r`n"); [IO.File]::SetLastWriteTimeUtc($path,$stamp)
        { Invoke-PCTextEditPlan $plan -Confirm:$false } | Should -Throw '*changed*'
        [IO.File]::ReadAllText($path) | Should -Be "bad`r`n"
    }
    It 'rejects stale identities at planning time' {
        $session=Get-PCTextEditSession $path; [IO.File]::WriteAllText($path,'external')
        { Get-PCTextEditPlan $path 'edit' $session.Identity } | Should -Throw '*changed*'
    }
    It 'does not write on WhatIf or cancellation and leaves no staged files' {
        $session=Get-PCTextEditSession $path; $plan=Get-PCTextEditPlan $path 'new' $session.Identity
        (Invoke-PCTextEditPlan $plan -WhatIf).Status | Should -Be 'Skipped'
        $cts=[Threading.CancellationTokenSource]::new(); $cts.Cancel()
        try { { Invoke-PCTextEditPlan $plan -CancellationToken $cts.Token } | Should -Throw } finally { $cts.Dispose() }
        [IO.File]::ReadAllText($path) | Should -Be "old`r`n"
        @(Get-ChildItem $TestDrive -Filter '.powercompare-*').Count | Should -Be 0
    }
    It 'rejects binary input, unsupported encodings and invalid Unicode' {
        [IO.File]::WriteAllBytes($path,[byte[]]@(0,1,2))
        { Get-PCTextEditSession $path } | Should -Throw '*text*'
        [IO.File]::WriteAllText($path,'plain'); $session=Get-PCTextEditSession $path
        { Get-PCTextEditPlan $path 'x' $session.Identity -Encoding 'ascii' } | Should -Throw
        { Get-PCTextEditPlan $path ([string][char]0xD800) $session.Identity } | Should -Throw
    }
    It 'creates a new output without overwriting an intervening file' {
        $new=Join-Path $TestDrive 'new.txt'
        $plan=Get-PCTextEditPlan $new 'merge' '<missing>'
        [IO.File]::WriteAllText($new,'external')
        { Invoke-PCTextEditPlan $plan -Confirm:$false } | Should -Throw '*changed*'
        [IO.File]::Delete($new)
        (Invoke-PCTextEditPlan $plan -Confirm:$false).Status | Should -Be 'Saved'
        [IO.File]::ReadAllText($new) | Should -Be 'merge'
    }
}
Describe 'Merge input guards' {
    It 'rejects saving output when any merge input changed after preview' {
        $inputPath=Join-Path $TestDrive 'input.txt';$outputPath=Join-Path $TestDrive 'output.txt'
        [IO.File]::WriteAllText($inputPath,'base');[IO.File]::WriteAllText($outputPath,'old')
        $inputSession=Get-PCTextEditSession $inputPath;$outputSession=Get-PCTextEditSession $outputPath
        $plan=Get-PCTextEditPlan $outputPath 'merged' $outputSession.Identity -InputSession @($inputSession)
        [IO.File]::WriteAllText($inputPath,'changed')
        { Invoke-PCTextEditPlan $plan -Confirm:$false } | Should -Throw '*input*changed*'
        [IO.File]::ReadAllText($outputPath) | Should -Be 'old'
    }
}
