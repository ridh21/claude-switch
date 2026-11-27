BeforeAll {
  . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  Import-Module (Join-Path $PSScriptRoot '..\ClaudeSwitch\ClaudeSwitch.psd1') -Force
}

Describe 'Get-ClaudeUsage' {
  BeforeEach {
    $t = New-TestEnvironment
    Start-UsageStub $t | Out-Null
  }
  AfterEach { Remove-TestEnvironment $t }

  It "returns each login's session and weekly use, asking with that login's token" {
    New-ClaudeProfile work | Out-Null
    Set-FakeLogin $t -Profile default -Token tok-default -Email 'jane.doe@gmail.com'
    Set-FakeLogin $t -Profile work -Token tok-work -Email 'jane@acme.co'
    Set-FakeUsage $t -Token tok-default -Session 84.4 -Weekly 56
    Set-FakeUsage $t -Token tok-work -Session 12 -Weekly 20.6

    $rows = Get-ClaudeUsage

    $rows.Profile | Should -Be @('default', 'work')
    $rows[0].Status | Should -Be 'ok'
    $rows[0].SessionPct | Should -Be 84
    $rows[0].WeeklyPct | Should -Be 56
    $rows[1].SessionPct | Should -Be 12
    $rows[1].WeeklyPct | Should -Be 21
    $rows[1].Account | Should -Be 'ja***e@a***.co'
    $rows[0].SessionResetsAt | Should -BeOfType [datetime]
    ($rows[0].SessionResetsAt - (Get-Date)).TotalMinutes | Should -BeGreaterThan 55
    Get-StubLog $t | Sort-Object | Should -Be @('tok-default|oauth-2025-04-20', 'tok-work|oauth-2025-04-20')
  }

  It 'reports logins that cannot be checked, without asking for expired ones' {
    'gone', 'stale', 'cleared', 'denied', 'busy' | ForEach-Object { New-ClaudeProfile $_ | Out-Null }
    Set-FakeLogin $t -Profile stale -Token tok-stale -Expired
    Set-FakeLogin $t -Profile cleared -Token tok-cleared -RefreshOnly
    Set-FakeLogin $t -Profile denied -Token tok-denied
    Set-FakeLogin $t -Profile busy -Token tok-busy
    Set-FakeUsage $t -Token tok-busy -Status 429

    $status = @{}
    Get-ClaudeUsage | ForEach-Object { $status[$_.Profile] = $_.Status }

    $status['default'] | Should -Be 'logged-out'
    $status['gone'] | Should -Be 'logged-out'
    $status['stale'] | Should -Be 'expired'
    $status['cleared'] | Should -Be 'expired'
    $status['denied'] | Should -Be 'expired'
    $status['busy'] | Should -Be 'rate-limited'
    Get-StubLog $t | ForEach-Object { ($_ -split '\|')[0] } | Sort-Object | Should -Be @('tok-busy', 'tok-denied')
  }

  It 'remembers readings in the format bin/cswitch reads: one LF line, no BOM' {
    Set-FakeLogin $t -Profile default -Token tok-default
    Set-FakeUsage $t -Token tok-default -Session 40 -Weekly 10
    Get-ClaudeUsage | Out-Null

    $bytes = [IO.File]::ReadAllBytes((Join-Path $t.Profiles '.cache\usage-default'))
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $bytes[0] | Should -Not -Be 0xEF
    $text | Should -Match '^\d{10}\|ok\|40\|\d{10}\|10\|\d{10}\n$'
  }

  It 'uses a fresh remembered reading with -Cached instead of asking again' {
    Set-FakeLogin $t -Profile default -Token tok-default
    Set-FakeUsage $t -Token tok-default -Session 40 -Weekly 10
    Get-ClaudeUsage | Out-Null
    Set-FakeUsage $t -Token tok-default -Session 99 -Weekly 99

    (Get-ClaudeUsage -Cached).SessionPct | Should -Be 40
    @(Get-StubLog $t).Count | Should -Be 1
  }

  It 'reads a reading that bin/cswitch statusline remembered' {
    New-Item -ItemType Directory -Force (Join-Path $t.Profiles '.cache') | Out-Null
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    [IO.File]::WriteAllText((Join-Path $t.Profiles '.cache\usage-default'), "$now|ok|42|$($now + 600)|18|`n")

    $row = Get-ClaudeUsage -Cached
    $row.SessionPct | Should -Be 42
    $row.WeeklyPct | Should -Be 18
    $row.WeeklyResetsAt | Should -BeNullOrEmpty
    @(Get-StubLog $t).Count | Should -Be 0
  }

  It 'prints the same JSON shape as bin/cswitch usage --json' {
    New-ClaudeProfile work | Out-Null
    Set-FakeLogin $t -Profile work -Token tok-work -Email 'jane@acme.co'
    Set-FakeUsage $t -Token tok-work -Session 12 -Weekly 20
    Set-Content (Join-Path $t.Profiles '.last') 'work'

    $json = Get-ClaudeUsage -Json
    $data = $json | ConvertFrom-Json

    $json | Should -BeLike '`[*'
    @($data).Count | Should -Be 2
    $data[0].name | Should -Be 'default'
    $data[0].email | Should -BeNullOrEmpty
    $data[0].status | Should -Be 'logged-out'
    $data[0].active | Should -BeTrue
    $data[0].session.percent | Should -BeNullOrEmpty
    $data[1].email | Should -Be 'ja***e@a***.co'
    $data[1].last_used | Should -BeTrue
    $data[1].session.percent | Should -Be 12
    $data[1].weekly.percent | Should -Be 20
    "$($data[1].session.resets_at)" | Should -Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$|^\d'
    $json | Should -Match '"resets_at":"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"'
  }

  It 'marks the login furthest from either limit as having the most room' {
    'a', 'b', 'c' | ForEach-Object { New-ClaudeProfile $_ | Out-Null; Set-FakeLogin $t -Profile $_ -Token "tok-$_" }
    Set-FakeUsage $t -Token tok-a -Session 0 -Weekly 85
    Set-FakeUsage $t -Token tok-b -Session 10 -Weekly 29
    Set-FakeUsage $t -Token tok-c -Session 100 -Weekly 1

    (Get-ClaudeUsage | Where-Object MostRoom).Profile | Should -Be 'b'
  }

  It 'shows as a readable table by default' {
    New-ClaudeProfile work | Out-Null
    Set-FakeLogin $t -Profile work -Token tok-work -Email 'jane@acme.co'
    Set-FakeUsage $t -Token tok-work -Session 12 -Weekly 20

    $text = Get-ClaudeUsage | Out-String -Width 200

    $text | Should -Match 'Profile\s+Account\s+Session\s+Resets\s+Weekly\s+Resets\s+Room'
    $text | Should -Match 'work\s+ja\*\*\*e@a\*\*\*\.co\s+12%\s+1h 0[12]m\s+20%\s+2d 1[45]h\s+most'
    $text | Should -Match '\* default\s+logged-out'
  }

  It 'reports an unreachable service as an error' {
    Set-FakeLogin $t -Profile default -Token tok-default
    $env:CSWITCH_USAGE_URL = 'http://127.0.0.1:9/api/oauth/usage'
    (Get-ClaudeUsage -TimeoutSec 2).Status | Should -Be 'error'
  }
}
