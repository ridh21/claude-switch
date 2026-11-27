BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Import-Module (Join-Path $PSScriptRoot '..\ClaudeSwitch\ClaudeSwitch.psd1') -Force
}

Describe 'Invoke-ClaudeProfile' {
  BeforeEach { $t = New-TestEnvironment }
  AfterEach { Remove-TestEnvironment $t }

  It 'runs Claude Code as the profile, with the arguments unchanged' {
    New-ClaudeProfile work | Out-Null

    Invoke-ClaudeProfile work --continue

    Get-ClaudeLog $t | Should -Be @("$(Join-Path $t.Profiles 'work')|--continue")
  }

  It "leaves this shell's CLAUDE_CONFIG_DIR as it was afterwards" {
    New-ClaudeProfile work | Out-Null
    $env:CLAUDE_CONFIG_DIR = 'C:\somewhere\else'

    Invoke-ClaudeProfile work

    $env:CLAUDE_CONFIG_DIR | Should -Be 'C:\somewhere\else'
  }

  It 'runs default with CLAUDE_CONFIG_DIR unset, as Claude Code expects' {
    New-ClaudeProfile work | Out-Null
    $env:CLAUDE_CONFIG_DIR = Join-Path $t.Profiles 'work'

    Invoke-ClaudeProfile default

    Get-ClaudeLog $t | Should -Be @('|')
  }

  It 'remembers the login it launched, for the menu' {
    New-ClaudeProfile work | Out-Null
    Invoke-ClaudeProfile work
    (Get-Content (Join-Path $t.Profiles '.last') -Raw) | Should -Be "work`n"
  }

  It "passes Claude Code's exit code on" {
    $env:FAKE_CLAUDE_RC = '3'
    Invoke-ClaudeProfile default
    $LASTEXITCODE | Should -Be 3
  }

  It "lets Claude Code's output flow down the pipeline, as with -p" {
    $env:FAKE_CLAUDE_SAY = 'the answer'
    $env:FAKE_CLAUDE_RC = '0'

    $out = Invoke-ClaudeProfile default -p hi

    $out | Should -Be 'the answer'
    $LASTEXITCODE | Should -Be 0
    Get-ClaudeLog $t | Should -Be @('|-p hi')
  }

  It "passes on arguments that look like PowerShell's own parameters" {
    Invoke-ClaudeProfile default -n -Name x --model opus -Verbose
    Get-ClaudeLog $t | Should -Be @('|-n -Name x --model opus -Verbose')
  }

  It 'refuses an unknown profile' {
    { Invoke-ClaudeProfile nope } | Should -Throw '*no such profile*'
    Get-ClaudeLog $t | Should -BeNullOrEmpty
  }
}

Describe 'Handoff when a login runs out' {
  BeforeEach {
    $t = New-TestEnvironment
    Start-UsageStub $t | Out-Null
    New-ClaudeProfile work | Out-Null
    Set-FakeLogin $t -Profile default -Token tok-default
    Set-FakeLogin $t -Profile work -Token tok-work
    Set-FakeUsage $t -Token tok-default -Session 100 -Weekly 40
    Set-FakeUsage $t -Token tok-work -Session 12 -Weekly 30
    $work = Join-Path $t.Profiles 'work'
  }
  AfterEach { Remove-TestEnvironment $t }

  It 'offers to continue the conversation on the login with the most room, and does on Enter' {
    Use-FakeTerm -Lines @('')

    Invoke-ClaudeProfile default

    Get-TermOutput | Should -Match 'default hit its 5-hour limit'
    Get-TermOutput | Should -Match 'Continue this conversation on work \(12% session, 30% weekly\)\? \[Y/n\]'
    Get-ClaudeLog $t | Should -Be @('|', "$work|--continue")
  }

  It 'stays put when the answer is no' {
    Use-FakeTerm -Lines @('n')
    Invoke-ClaudeProfile default
    Get-ClaudeLog $t | Should -Be @('|')
  }

  It 'does not offer for <Why>' -TestCases @(
    @{ Why = 'one-off prompts'; Extra = @('-p', 'hi'); Off = $false; Interactive = $true }
    @{ Why = 'subcommands like mcp'; Extra = @('mcp', 'list'); Off = $false; Interactive = $true }
    @{ Why = 'CSWITCH_HANDOFF=0'; Extra = @(); Off = $true; Interactive = $true }
    @{ Why = 'scripts and pipes'; Extra = @(); Off = $false; Interactive = $false }
  ) {
    param($Why, $Extra, $Off, $Interactive)
    if ($Off) { $env:CSWITCH_HANDOFF = '0' }
    Use-FakeTerm -Lines @('') -NotInteractive:(-not $Interactive)

    Invoke-ClaudeProfile default @Extra

    @(Get-ClaudeLog $t).Count | Should -Be 1
    Get-TermOutput | Should -BeNullOrEmpty
  }

  It 'only offers logins that share conversation history' {
    Remove-ClaudeProfile work -Force | Out-Null
    New-ClaudeProfile solo -Isolated | Out-Null
    Set-FakeLogin $t -Profile solo -Token tok-work
    Use-FakeTerm -Lines @('')

    Invoke-ClaudeProfile default

    Get-TermOutput | Should -Match 'No other login with shared history has room'
    @(Get-ClaudeLog $t).Count | Should -Be 1
  }
}
