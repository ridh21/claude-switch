BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Import-Module (Join-Path $PSScriptRoot '..\ClaudeSwitch\ClaudeSwitch.psd1') -Force
}

Describe 'Select-ClaudeProfile (the account menu)' {
  BeforeEach {
    $t = New-TestEnvironment
    Start-UsageStub $t | Out-Null
    New-ClaudeProfile work | Out-Null
    New-ClaudeProfile client | Out-Null
    Set-FakeLogin $t -Profile default -Token tok-default -Email 'jane.doe@gmail.com'
    Set-FakeLogin $t -Profile work -Token tok-work -Email 'jane@acme.co'
    Set-FakeUsage $t -Token tok-default -Session 84 -Weekly 56
    Set-FakeUsage $t -Token tok-work -Session 12 -Weekly 20
    Set-Content (Join-Path $t.Profiles '.last') 'default'
  }
  AfterEach { Remove-TestEnvironment $t }

  It 'lists every login with its account and limits' {
    Use-FakeTerm -Keys @('cancel')
    Select-ClaudeProfile | Out-Null
    $out = Get-TermOutput
    $out | Should -Match 'Which Claude account\?'
    $out | Should -Match '1\s+default\s+ja\*\*\*e@g\*\*\*\.com\s+5h\s+84%\s+7d\s+56%\s+last used'
    $out | Should -Match '3\s+work\s+ja\*\*\*e@a\*\*\*\.co\s+5h\s+12%\s+7d\s+20%\s+most room'
    $out | Should -Match '2\s+client\s+not logged in\s+not logged in'
  }

  It 'starts on the login used last, so Enter repeats it' {
    Use-FakeTerm -Keys @('enter')
    Select-ClaudeProfile | Should -Be 'default'
  }

  It 'starts on the login with most room when the last one has reached a limit' {
    Set-FakeUsage $t -Token tok-default -Session 100 -Weekly 56
    Use-FakeTerm -Keys @('enter')
    Select-ClaudeProfile | Should -Be 'work'
  }

  It 'moves with the arrow keys and j/k, and wraps around' {
    Use-FakeTerm -Keys @('down', 'down', 'j', 'k', 'up', 'enter')
    Select-ClaudeProfile | Should -Be 'client'
  }

  It 'picks a row directly with its number' {
    Use-FakeTerm -Keys @('3')
    Select-ClaudeProfile | Should -Be 'work'
  }

  It 'returns nothing when cancelled with <Key>' -TestCases @(@{ Key = 'cancel' }, @{ Key = 'q' }) {
    param($Key)
    Use-FakeTerm -Keys @($Key)
    Select-ClaudeProfile | Should -BeNullOrEmpty
  }

  It 'shows the Claude banner when the window is big enough, and not when it is short' {
    Use-FakeTerm -Keys @('cancel') -Size @(40, 120)
    Select-ClaudeProfile | Out-Null
    Get-TermOutput | Should -Match ([regex]::Escape([string][char]0x2590 + [char]0x259B))

    Use-FakeTerm -Keys @('cancel') -Size @(8, 120)
    Select-ClaudeProfile | Out-Null
    Get-TermOutput | Should -Not -Match ([regex]::Escape([string][char]0x2590 + [char]0x259B))
  }

  It 'needs a console to ask on' {
    Use-FakeTerm -NotInteractive
    { Select-ClaudeProfile } | Should -Throw '*no console*'
  }
}
