BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Import-Module (Join-Path $PSScriptRoot '..\ClaudeSwitch\ClaudeSwitch.psd1') -Force
}

Describe 'Invoke-ClaudeShim (what plain "claude" runs after setup)' {
  BeforeEach {
    $t = New-TestEnvironment
    Start-UsageStub $t | Out-Null
    $work = Join-Path $t.Profiles 'work'
  }
  AfterEach { Remove-TestEnvironment $t }

  It 'asks which account to use, then runs claude as it with the arguments unchanged' {
    New-ClaudeProfile work | Out-Null
    Use-FakeTerm -Keys @('2')

    Invoke-ClaudeShim --continue

    Get-ClaudeLog $t | Should -Be @("$work|--continue")
  }

  It 'runs nothing when the menu is cancelled' {
    New-ClaudeProfile work | Out-Null
    Use-FakeTerm -Keys @('cancel')
    Invoke-ClaudeShim
    Get-ClaudeLog $t | Should -BeNullOrEmpty
  }

  It 'goes straight to claude for <Why>' -TestCases @(
    @{ Why = '--version'; Extra = @('--version'); Interactive = $true }
    @{ Why = 'claude update'; Extra = @('update'); Interactive = $true }
    @{ Why = 'scripts and pipes'; Extra = @('-p', 'hi'); Interactive = $false }
  ) {
    param($Why, $Extra, $Interactive)
    New-ClaudeProfile work | Out-Null
    Use-FakeTerm -Keys @('2') -NotInteractive:(-not $Interactive)

    Invoke-ClaudeShim @Extra

    Get-ClaudeLog $t | Should -Be @("|$($Extra -join ' ')")
  }

  It 'goes straight to claude when default is the only profile' {
    Use-FakeTerm -Keys @('cancel')
    Invoke-ClaudeShim
    Get-ClaudeLog $t | Should -Be @('|')
  }

  It 'uses CSWITCH_PROFILE without asking' {
    New-ClaudeProfile work | Out-Null
    $env:CSWITCH_PROFILE = 'work'
    Use-FakeTerm -Keys @('cancel')

    Invoke-ClaudeShim

    Get-ClaudeLog $t | Should -Be @("$work|")
  }
}

Describe 'cswitch' {
  BeforeEach {
    $t = New-TestEnvironment
    Start-UsageStub $t | Out-Null
    $work = Join-Path $t.Profiles 'work'
  }
  AfterEach { Remove-TestEnvironment $t }

  It 'adds a profile and launches it by name, like bin/cswitch' {
    cswitch add work 6>$null | Out-Null
    cswitch work --continue
    cswitch run work -p hi
    Get-ClaudeLog $t | Should -Be @("$work|--continue", "$work|-p hi")
  }

  It 'prints the line that points this shell at a profile' {
    cswitch add work 6>$null | Out-Null
    cswitch env work | Should -Be "`$env:CLAUDE_CONFIG_DIR = '$work'"
    cswitch env default | Should -Be 'Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction Ignore'
  }

  It 'lists profiles with the active one starred' {
    cswitch add work 6>$null | Out-Null
    Set-FakeLogin $t -Profile work -Token tok-work -Email 'jane@acme.co'
    $out = cswitch list
    $out[0] | Should -Match '^\* default\s+\(not logged in\)$'
    $out[1] | Should -Match '^  work\s+ja\*\*\*e@a\*\*\*\.co$'
  }

  It 'shows a usage table that names the login with the most room' {
    cswitch add work 6>$null | Out-Null
    Set-FakeLogin $t -Profile default -Token tok-default
    Set-FakeLogin $t -Profile work -Token tok-work
    Set-FakeUsage $t -Token tok-default -Session 84 -Weekly 56
    Set-FakeUsage $t -Token tok-work -Session 12 -Weekly 20

    $out = (cswitch usage) -join "`n"

    $out | Should -Match 'PROFILE\s+ACCOUNT\s+SESSION \(5h\)'
    $out | Should -Match 'work\s+\(not logged in\)\s+12%'
    $out | Should -Match 'Most room: work \(12% session, 20% weekly\)\s+->\s+cswitch work'
  }

  It 'prints usage JSON with --json' {
    (cswitch usage --json | ConvertFrom-Json)[0].name | Should -Be 'default'
  }

  It 'launches the login with the most room with best' {
    cswitch add work 6>$null | Out-Null
    Set-FakeLogin $t -Profile default -Token tok-default
    Set-FakeLogin $t -Profile work -Token tok-work
    Set-FakeUsage $t -Token tok-default -Session 84 -Weekly 56
    Set-FakeUsage $t -Token tok-work -Session 12 -Weekly 20

    cswitch best -p hi 6>$null

    Get-ClaudeLog $t | Should -Be @("$work|-p hi")
  }

  It 'removes a profile with -y, without asking' {
    cswitch add work 6>$null | Out-Null
    cswitch remove work -y 6>$null
    $work | Should -Not -Exist
  }

  It 'explains an unknown command' {
    { cswitch frobnicate } | Should -Throw '*unknown command or profile: frobnicate*'
  }

  It 'prints its version' {
    cswitch --version | Should -Match '^cswitch \d+\.\d+\.\d+ \(PowerShell\)$'
  }
}
