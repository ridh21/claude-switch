BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Import-Module (Join-Path $PSScriptRoot '..\ClaudeSwitch\ClaudeSwitch.psd1') -Force
}

Describe 'New-ClaudeProfile' {
  BeforeEach { $t = New-TestEnvironment }
  AfterEach { Remove-TestEnvironment $t }

  It 'shares conversation history with ~/.claude instead of copying it' {
    New-ClaudeProfile work | Out-Null

    Set-Content (Join-Path $t.Profiles 'work\projects\from-work.txt') 'hello'

    Join-Path $t.Base 'projects\from-work.txt' | Should -Exist
  }

  It 'shares settings.json, so a change in ~/.claude shows up in the profile' -TestCases @(
    @{ Mode = 'auto' }, @{ Mode = 'hardlink' }
  ) {
    param($Mode)
    $env:CSWITCH_FILE_LINKS = $Mode
    Set-Content (Join-Path $t.Base 'settings.json') '{"theme":"dark"}'
    New-ClaudeProfile work | Out-Null

    Set-Content (Join-Path $t.Base 'settings.json') '{"theme":"light"}'

    Get-Content (Join-Path $t.Profiles 'work\settings.json') | Should -Be '{"theme":"light"}'
  }

  It 'refuses the name <Name>' -TestCases @(
    @{ Name = 'my work' }, @{ Name = '.hidden' }, @{ Name = '-x' }, @{ Name = 'usage' },
    @{ Name = 'default' }, @{ Name = 'CON' }, @{ Name = 'nul' }, @{ Name = 'com1' }, @{ Name = 'work.' }
  ) {
    param($Name)
    { New-ClaudeProfile $Name } | Should -Throw
    Join-Path $t.Profiles $Name | Should -Not -Exist
  }

  It 'refuses to create a profile that already exists' {
    New-ClaudeProfile work | Out-Null
    { New-ClaudeProfile work } | Should -Throw '*already exists*'
  }

  It 'leaves ~/.claude untouched' {
    Set-Content (Join-Path $t.Base 'settings.json') '{}'
    $before = Get-ChildItem $t.Base -Recurse -Force | ForEach-Object FullName
    New-ClaudeProfile work | Out-Null
    Get-ChildItem $t.Base -Recurse -Force | ForEach-Object FullName | Should -Be $before
  }

  It 'shares nothing with -Isolated, and says so' {
    Set-Content (Join-Path $t.Base 'settings.json') '{}'
    New-ClaudeProfile solo -Isolated | Out-Null
    @(Get-ChildItem (Join-Path $t.Profiles 'solo') -Force | Where-Object Name -ne '.cswitch-isolated').Count | Should -Be 0
    (Get-ClaudeProfile solo).Isolated | Should -BeTrue
  }
}

Describe 'Get-ClaudeProfile' {
  BeforeEach { $t = New-TestEnvironment }
  AfterEach { Remove-TestEnvironment $t }

  It 'lists default first, then every profile, with masked emails' {
    New-ClaudeProfile work | Out-Null
    New-ClaudeProfile client | Out-Null
    Set-FakeLogin $t -Profile default -Token t1 -Email 'jane.doe@gmail.com'
    Set-FakeLogin $t -Profile work -Token t2 -Email 'jane@acme.co'

    $list = Get-ClaudeProfile

    $list.Name | Should -Be @('default', 'client', 'work')
    $list[0].Account | Should -Be 'ja***e@g***.com'
    $list[2].Account | Should -Be 'ja***e@a***.co'
    $list[1].Account | Should -BeNullOrEmpty
  }

  It 'shows full emails with CSWITCH_SHOW_EMAIL=1' {
    Set-FakeLogin $t -Profile default -Token t1 -Email 'jane.doe@gmail.com'
    $env:CSWITCH_SHOW_EMAIL = '1'
    (Get-ClaudeProfile).Account | Should -Be 'jane.doe@gmail.com'
  }

  It 'marks the profile this shell points at as active' {
    New-ClaudeProfile work | Out-Null
    $env:CLAUDE_CONFIG_DIR = Join-Path $t.Profiles 'work'
    (Get-ClaudeProfile | Where-Object Active).Name | Should -Be 'work'
  }
}

Describe 'Remove-ClaudeProfile' {
  BeforeEach { $t = New-TestEnvironment }
  AfterEach { Remove-TestEnvironment $t }

  It 'deletes the profile but never the shared history or settings it links to' {
    Set-Content (Join-Path $t.Base 'projects\keep.txt') 'history'
    Set-Content (Join-Path $t.Base 'settings.json') '{}'
    New-ClaudeProfile work | Out-Null
    Set-FakeLogin $t -Profile work -Token t2 -Email 'jane@acme.co'

    Remove-ClaudeProfile work -Force

    Join-Path $t.Profiles 'work' | Should -Not -Exist
    Join-Path $t.Base 'projects\keep.txt' | Should -Exist
    Join-Path $t.Base 'settings.json' | Should -Exist
  }

  It 'refuses to remove default' {
    { Remove-ClaudeProfile default -Force } | Should -Throw '*cannot be removed*'
  }
}
