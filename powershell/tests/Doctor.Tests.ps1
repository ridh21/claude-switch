BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Import-Module (Join-Path $PSScriptRoot '..\ClaudeSwitch\ClaudeSwitch.psd1') -Force

  # What an editor's "write a new file, rename it over the old one" save does to a link.
  function Break-Link($Path, $Content) {
    [IO.File]::Delete($Path)
    [IO.File]::WriteAllText($Path, $Content)
    (Get-Item $Path).LastWriteTime = (Get-Date).AddMinutes(5)
  }
}

Describe 'Test-ClaudeSwitch (cswitch doctor)' {
  BeforeEach {
    $t = New-TestEnvironment
    Set-Content (Join-Path $t.Base 'settings.json') '{"theme":"dark"}'
    New-Item -ItemType Directory (Join-Path $t.Base 'skills') | Out-Null
    New-ClaudeProfile work 6>$null | Out-Null
    Set-FakeLogin $t -Profile work -Token tok-work -Email 'jane@acme.co'
    $workSettings = Join-Path $t.Profiles 'work\settings.json'
  }
  AfterEach { Remove-TestEnvironment $t }

  It 'passes a healthy setup' {
    $checks = Test-ClaudeSwitch
    $checks | Where-Object Status -eq 'fail' | Should -BeNullOrEmpty
    ($checks | Where-Object Check -eq 'claude').Status | Should -Be 'ok'
    ($checks | Where-Object Check -eq 'work: login').Detail | Should -Match 'ja\*\*\*e@a\*\*\*\.co'
    ($checks | Where-Object Check -eq 'work: links').Status | Should -Be 'ok'
  }

  It 'finds a shared file that has become a copy' {
    Break-Link $workSettings '{"theme":"light"}'

    $check = Test-ClaudeSwitch | Where-Object Check -eq 'work: links'

    $check.Status | Should -Be 'fail'
    $check.Detail | Should -Match 'settings.json is a copy'
  }

  It 'relinks it with -Fix, keeping the newer settings' {
    Break-Link $workSettings '{"theme":"light"}'

    Test-ClaudeSwitch -Fix | Out-Null

    Get-Content (Join-Path $t.Base 'settings.json') | Should -Be '{"theme":"light"}'
    Set-Content (Join-Path $t.Base 'settings.json') '{"theme":"blue"}'
    Get-Content $workSettings | Should -Be '{"theme":"blue"}'
    (Test-ClaudeSwitch | Where-Object Check -eq 'work: links').Status | Should -Be 'ok'
  }

  It 'replaces a copied folder with a link, keeping a backup and adding its new files to ~/.claude' {
    $skills = Join-Path $t.Profiles 'work\skills'
    [IO.Directory]::Delete($skills)
    New-Item -ItemType Directory $skills | Out-Null
    Set-Content (Join-Path $skills 'mine.md') 'only in the copy'

    Test-ClaudeSwitch -Fix | Out-Null

    (Get-Item $skills).LinkType | Should -Be 'Junction'
    Join-Path $t.Base 'skills\mine.md' | Should -Exist
    @(Get-ChildItem (Join-Path $t.Profiles 'work') -Directory -Filter 'skills.cswitch-backup-*').Count | Should -Be 1
  }

  It 'reports when claude is not on the PATH' {
    $env:PATH = 'C:\nowhere'
    (Test-ClaudeSwitch | Where-Object Check -eq 'claude').Status | Should -Be 'fail'
  }

  It 'repairs a broken file link by itself when the profile is launched' {
    Break-Link $workSettings '{"theme":"light"}'

    Invoke-ClaudeProfile work

    Get-Content (Join-Path $t.Base 'settings.json') | Should -Be '{"theme":"light"}'
    Set-Content (Join-Path $t.Base 'settings.json') '{"theme":"blue"}'
    Get-Content $workSettings | Should -Be '{"theme":"blue"}'
  }

  It 'is what cswitch doctor prints' {
    $out = (cswitch doctor) -join "`n"
    $out | Should -Match 'ok\s+claude'
    $out | Should -Match 'ok\s+work: links'
  }
}
