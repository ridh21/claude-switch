# Shared setup for the ClaudeSwitch tests. Every test runs against a
# throwaway home folder, a fake claude.cmd and a local usage service, so no
# real login, profile or network is touched.

$script:SavedEnv = @{}
$script:EnvNames = @(
  'CSWITCH_HOME', 'CSWITCH_BASE', 'CSWITCH_USAGE_URL', 'CSWITCH_UPDATE_CHECK', 'CSWITCH_PROFILE',
  'CSWITCH_HANDOFF', 'CSWITCH_SHOW_EMAIL', 'CSWITCH_USAGE_TTL', 'CSWITCH_FILE_LINKS', 'CSWITCH_BANNER',
  'CLAUDE_CONFIG_DIR', 'NO_COLOR', 'PATH', 'FAKE_CLAUDE_RC', 'FAKE_CLAUDE_SAY', 'APPDATA', 'LOCALAPPDATA'
)

function New-TestEnvironment {
  foreach ($n in $script:EnvNames) { $script:SavedEnv[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }

  $root = Join-Path ([IO.Path]::GetTempPath()) ('cswitch-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $t = [pscustomobject]@{
    Root     = $root
    Home     = Join-Path $root 'home'
    Base     = Join-Path $root 'home\.claude'
    Profiles = Join-Path $root 'home\.claude-profiles'
    Bin      = Join-Path $root 'bin'
    Fake     = Join-Path $root 'fake'
    Stub     = $null
  }
  New-Item -ItemType Directory -Force -Path $t.Base, (Join-Path $t.Base 'projects'), $t.Bin, $t.Fake | Out-Null

  # claude: log the profile it ran as and its arguments, exit with FAKE_CLAUDE_RC.
  $cmd = "@echo off`r`n>>`"$($t.Fake)\claude.log`" echo %CLAUDE_CONFIG_DIR%^|%*`r`nif defined FAKE_CLAUDE_SAY echo %FAKE_CLAUDE_SAY%`r`nexit /b %FAKE_CLAUDE_RC%`r`n"
  [IO.File]::WriteAllText((Join-Path $t.Bin 'claude.cmd'), $cmd, [Text.Encoding]::ASCII)

  # Never let a test reach the real VS Code or Windows Terminal settings.
  $env:APPDATA = Join-Path $root 'AppData'
  $env:LOCALAPPDATA = Join-Path $root 'LocalAppData'
  $env:CSWITCH_HOME = $t.Profiles
  $env:CSWITCH_BASE = $t.Base
  $env:CSWITCH_UPDATE_CHECK = '0'
  $env:NO_COLOR = '1'
  $env:FAKE_CLAUDE_RC = '0'
  $env:PATH = "$($t.Bin);$($script:SavedEnv['PATH'])"
  foreach ($n in 'CSWITCH_PROFILE', 'CSWITCH_HANDOFF', 'CSWITCH_SHOW_EMAIL', 'CSWITCH_USAGE_TTL',
    'CSWITCH_FILE_LINKS', 'CLAUDE_CONFIG_DIR', 'CSWITCH_USAGE_URL', 'CSWITCH_BANNER') {
    Remove-Item "Env:$n" -ErrorAction Ignore
  }
  $t
}

function Remove-TestEnvironment($t) {
  if ($t.Stub) { Stop-UsageStub $t.Stub }
  foreach ($n in $script:EnvNames) { [Environment]::SetEnvironmentVariable($n, $script:SavedEnv[$n], 'Process') }
  # Junctions first, so deleting the tree never follows one into the base.
  if (Test-Path $t.Profiles) {
    Get-ChildItem $t.Profiles -Recurse -Force -Attributes ReparsePoint -ErrorAction Ignore |
      ForEach-Object {
        if ($_.PSIsContainer) { [IO.Directory]::Delete($_.FullName) } else { [IO.File]::Delete($_.FullName) }
      }
  }
  Remove-Item $t.Root -Recurse -Force -ErrorAction Ignore
}

# Lines claude.cmd logged: "<CLAUDE_CONFIG_DIR>|<args>".
function Get-ClaudeLog($t) {
  $f = Join-Path $t.Fake 'claude.log'
  if (Test-Path $f) { @(Get-Content $f | ForEach-Object { $_.TrimEnd() }) } else { @() }
}

# Store a login for a profile folder the way Claude Code does on Windows.
function Set-FakeLogin {
  param($t, [string]$Profile, [string]$Token, [string]$Email, [switch]$Expired, [switch]$RefreshOnly)
  if ($Profile -eq 'default') { $dir = $t.Base; $acct = Join-Path $t.Home '.claude.json' }
  else { $dir = Join-Path $t.Profiles $Profile; $acct = Join-Path $dir '.claude.json' }
  $expires = [DateTimeOffset]::UtcNow.AddHours(6).ToUnixTimeMilliseconds()
  if ($Expired) { $expires = [DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeMilliseconds() }
  $access = if ($RefreshOnly) { '' } else { $Token }
  $creds = '{"claudeAiOauth":{"accessToken":"' + $access + '","refreshToken":"r-' + $Token +
    '","expiresAt":' + $expires + ',"scopes":["user:inference"]},"mcpOAuth":{}}'
  [IO.File]::WriteAllText((Join-Path $dir '.credentials.json'), $creds)
  if ($Email) { [IO.File]::WriteAllText($acct, '{"oauthAccount":{"emailAddress":"' + $Email + '"}}') }
}

# What the usage service answers for a token.
function Set-FakeUsage {
  param($t, [string]$Token, $Session, $Weekly, [int]$Status = 200)
  if ($Status -ne 200) { Set-Content (Join-Path $t.Fake "status-$Token") $Status; return }
  $s = (Get-Date).ToUniversalTime().AddMinutes(62).ToString('yyyy-MM-ddTHH:mm:ss.fff') + '+00:00'
  $w = (Get-Date).ToUniversalTime().AddHours(63).ToString('yyyy-MM-ddTHH:mm:ss.fff') + '+00:00'
  $body = '{"five_hour":{"utilization":' + $Session + ',"resets_at":"' + $s + '"},' +
    '"seven_day":{"utilization":' + $Weekly + ',"resets_at":"' + $w + '"}}'
  [IO.File]::WriteAllText((Join-Path $t.Fake "usage-$Token"), $body)
}

# Stand in for the console: keys to press, lines to type, and a record of
# what was drawn. Interactive unless -NotInteractive.
function Use-FakeTerm {
  param([string[]]$Keys = @(), [string[]]$Lines = @(), [switch]$NotInteractive, [int[]]$Size = @(40, 120))
  InModuleScope ClaudeSwitch -Parameters @{ Keys = $Keys; Lines = $Lines; Interactive = -not $NotInteractive; Size = $Size } {
    param($Keys, $Lines, $Interactive, $Size)
    $script:FakeKeys = New-Object Collections.Queue
    foreach ($k in $Keys) { $script:FakeKeys.Enqueue($k) }
    $script:FakeLines = New-Object Collections.Queue
    foreach ($l in $Lines) { $script:FakeLines.Enqueue($l) }
    $script:FakeOut = New-Object Text.StringBuilder
    $script:FakeInteractive = $Interactive
    $script:FakeSize = $Size
    $script:Term = @{
      IsInteractive = { $script:FakeInteractive }
      ReadKey       = { if ($script:FakeKeys.Count) { $script:FakeKeys.Dequeue() } else { 'cancel' } }
      ReadLine      = { if ($script:FakeLines.Count) { $script:FakeLines.Dequeue() } else { $null } }
      Write         = { param([string]$Text) [void]$script:FakeOut.Append($Text) }
      Size          = { $script:FakeSize }
    }
  }
}

# What was drawn on the fake console, without colour codes.
function Get-TermOutput {
  $raw = InModuleScope ClaudeSwitch { $script:FakeOut.ToString() }
  $raw -replace "$([char]27)\[[0-9;?]*[A-Za-z]", ''
}

function Get-StubLog($t) {
  $f = Join-Path $t.Fake 'http.log'
  if (Test-Path $f) { @(Get-Content $f) } else { @() }
}

# A local stand-in for api.anthropic.com/api/oauth/usage, answering from
# $Fake/usage-<token> and logging "<token>|<anthropic-beta header>".
function Start-UsageStub($t) {
  $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
  $listener = [Net.HttpListener]::new()
  $listener.Prefixes.Add("http://127.0.0.1:$port/")
  $listener.Start()
  $ps = [powershell]::Create()
  [void]$ps.AddScript({
      param($listener, $fake)
      while ($listener.IsListening) {
        try { $ctx = $listener.GetContext() } catch { break }
        $token = ([string]$ctx.Request.Headers['Authorization']) -replace '^Bearer ', ''
        Add-Content (Join-Path $fake 'http.log') ("$token|" + $ctx.Request.Headers['anthropic-beta'])
        $status = 401; $body = ''
        $codeFile = Join-Path $fake "status-$token"
        $usageFile = Join-Path $fake "usage-$token"
        if (Test-Path $codeFile) { $status = [int](Get-Content $codeFile) }
        elseif (Test-Path $usageFile) { $status = 200; $body = [IO.File]::ReadAllText($usageFile) }
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $ctx.Response.StatusCode = $status
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
      }
    }).AddArgument($listener).AddArgument($t.Fake)
  $handle = $ps.BeginInvoke()
  $env:CSWITCH_USAGE_URL = "http://127.0.0.1:$port/api/oauth/usage"
  $t.Stub = [pscustomobject]@{ Listener = $listener; PowerShell = $ps; Handle = $handle }
  $t.Stub
}

function Stop-UsageStub($stub) {
  try { $stub.Listener.Stop(); $stub.Listener.Close() } catch { }
  try { $stub.PowerShell.Dispose() } catch { }
}
