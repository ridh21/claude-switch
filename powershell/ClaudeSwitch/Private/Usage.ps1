# Usage limits. Claude Code on Windows keeps each login's OAuth token in
# <config dir>\.credentials.json. The token is sent only to the usage service
# (api.anthropic.com), as a request header from inside this process, so it
# never appears in a process list, and it is never printed or stored.
#
# A reading is: Status (ok, logged-out, expired, rate-limited, error, unknown),
# SessionPct, SessionAt, WeeklyPct, WeeklyAt, with the reset times as Unix
# seconds. Readings are remembered in .cache\usage-<name> in the same
# one-line format bin/cswitch uses: epoch|status|s_pct|s_at|w_pct|w_at

function Get-UsageUrl {
  if ($env:CSWITCH_USAGE_URL) { $env:CSWITCH_USAGE_URL } else { 'https://api.anthropic.com/api/oauth/usage' }
}

function Get-UsageTtl {
  $ttl = 0
  if ([int]::TryParse([string]$env:CSWITCH_USAGE_TTL, [ref]$ttl)) { $ttl } else { 120 }
}

function New-Reading([string]$Status, $SessionPct = $null, $SessionAt = $null, $WeeklyPct = $null, $WeeklyAt = $null) {
  [pscustomobject]@{ Status = $Status; SessionPct = $SessionPct; SessionAt = $SessionAt; WeeklyPct = $WeeklyPct; WeeklyAt = $WeeklyAt }
}

function ConvertTo-NullableInt($Value) {
  if ($null -eq $Value -or "$Value" -eq '' -or "$Value" -eq 'null') { return $null }
  [int][Math]::Round([double]$Value)
}

function ConvertTo-Epoch($Value) {
  if ($null -eq $Value -or "$Value" -eq '' -or "$Value" -eq 'null') { return $null }
  if ($Value -is [datetime]) { return ([DateTimeOffset]$Value).ToUnixTimeSeconds() }
  $n = 0L
  if ([long]::TryParse(("$Value" -split '\.')[0], [ref]$n)) { return $n }
  ([DateTimeOffset]::Parse("$Value", [Globalization.CultureInfo]::InvariantCulture)).ToUnixTimeSeconds()
}

# The Claude login (not the MCP tokens stored next to it) for a profile.
function Get-ProfileOAuth([string]$Name) {
  $file = Join-Path (Get-ProfileDir $Name) '.credentials.json'
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  try { (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json).claudeAiOauth } catch { $null }
}

# What can be decided without the network: logged out, or a token that has run out.
# Returns a reading, or the access token to ask with.
function Get-UsageCredential([string]$Name) {
  $oauth = Get-ProfileOAuth $Name
  if (-not $oauth) { return New-Reading 'logged-out' }
  $token = [string]$oauth.accessToken
  if (-not $token) {
    # Claude Code clears the access token but keeps the refresh token; the
    # next launch of that profile gets a new one.
    if ($oauth.refreshToken) { return New-Reading 'expired' } else { return New-Reading 'logged-out' }
  }
  $expires = 0L
  if ([long]::TryParse([string]$oauth.expiresAt, [ref]$expires) -and $expires -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) {
    return New-Reading 'expired'
  }
  $token
}

# Asks the usage service for one token, in its own runspace so several
# logins can be asked at once. Returns @{ Code; Body }.
$script:UsageRequest = {
  param([string]$Url, [string]$Token, [int]$TimeoutSec)
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $resp = $null
  try {
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Method = 'GET'
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = $TimeoutSec * 1000
    $req.UserAgent = 'cswitch-powershell'
    $req.ContentType = 'application/json'
    $req.Headers.Add('Authorization', "Bearer $Token")
    $req.Headers.Add('anthropic-beta', 'oauth-2025-04-20')
    $resp = $req.GetResponse()
  } catch {
    $ex = $_.Exception
    while ($ex -and -not ($ex -is [Net.WebException])) { $ex = $ex.InnerException }
    if ($ex) { $resp = $ex.Response }
    if (-not $resp) { return @{ Code = 0; Body = '' } }
  }
  try {
    $reader = New-Object IO.StreamReader($resp.GetResponseStream())
    @{ Code = [int]$resp.StatusCode; Body = $reader.ReadToEnd() }
  } finally {
    $resp.Close()
  }
}

function ConvertFrom-UsageResponse($Response) {
  switch ($Response.Code) {
    200 { }
    401 { return New-Reading 'expired' }
    403 { return New-Reading 'expired' }
    429 { return New-Reading 'rate-limited' }
    default { return New-Reading 'error' }
  }
  try { $body = $Response.Body | ConvertFrom-Json } catch { return New-Reading 'error' }
  $five = $body.five_hour; $seven = $body.seven_day
  New-Reading 'ok' `
    (ConvertTo-NullableInt $(if ($five) { $five.utilization })) (ConvertTo-Epoch $(if ($five) { $five.resets_at })) `
    (ConvertTo-NullableInt $(if ($seven) { $seven.utilization })) (ConvertTo-Epoch $(if ($seven) { $seven.resets_at }))
}

function Get-CacheDir { Join-Path (Get-CsHome) '.cache' }

function Write-UsageCache([string]$Name, $Reading) {
  $dir = Get-CacheDir
  try { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null } catch { return }
  $line = '{0}|{1}|{2}|{3}|{4}|{5}' -f [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(), $Reading.Status,
    $Reading.SessionPct, $Reading.SessionAt, $Reading.WeeklyPct, $Reading.WeeklyAt
  Write-CsFile (Join-Path $dir "usage-$Name") "$line`n"
}

# The remembered reading for a profile if it is at most MaxAge seconds old.
function Read-UsageCache([string]$Name, [int]$MaxAge) {
  $file = Join-Path (Get-CacheDir) "usage-$Name"
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  $line = Get-Content -LiteralPath $file -TotalCount 1
  if (-not $line) { return $null }
  $f = "$line".Split('|')
  $at = 0L
  if ($f.Count -lt 6 -or -not [long]::TryParse($f[0], [ref]$at)) { return $null }
  if ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $at -gt $MaxAge) { return $null }
  New-Reading $(if ($f[1]) { $f[1] } else { 'error' }) (ConvertTo-NullableInt $f[2]) (ConvertTo-Epoch $f[3]) `
    (ConvertTo-NullableInt $f[4]) (ConvertTo-Epoch $f[5])
}

# Readings for several profiles: remembered ones when fresh enough, the rest
# asked for all at once. A timeout of 0 never touches the network.
function Get-UsageReadings([string[]]$Names, [int]$MaxAge, [int]$TimeoutSec) {
  $result = [ordered]@{}
  $pending = @()
  foreach ($n in $Names) {
    $cached = if ($MaxAge -gt 0) { Read-UsageCache $n $MaxAge } else { $null }
    if ($cached) { $result[$n] = $cached; continue }
    if ($TimeoutSec -le 0) { $result[$n] = New-Reading 'unknown'; continue }
    $cred = Get-UsageCredential $n
    if ($cred -is [string]) { $pending += , @($n, $cred) } else { $result[$n] = $cred; Write-UsageCache $n $cred }
  }
  if ($pending.Count -gt 0) {
    $pool = [runspacefactory]::CreateRunspacePool(1, [Math]::Min(8, $pending.Count))
    $pool.Open()
    try {
      $jobs = foreach ($p in $pending) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($script:UsageRequest).AddArgument((Get-UsageUrl)).AddArgument($p[1]).AddArgument($TimeoutSec)
        [pscustomobject]@{ Name = $p[0]; PowerShell = $ps; Handle = $ps.BeginInvoke() }
      }
      foreach ($j in $jobs) {
        try {
          $out = $j.PowerShell.EndInvoke($j.Handle)
          $reading = if ($out -and $out.Count -gt 0) { ConvertFrom-UsageResponse $out[0] } else { New-Reading 'error' }
        } catch {
          $reading = New-Reading 'error'
        } finally {
          $j.PowerShell.Dispose()
        }
        $result[$j.Name] = $reading
        Write-UsageCache $j.Name $reading
      }
    } finally {
      $pool.Close(); $pool.Dispose()
    }
  }
  foreach ($n in $Names) { [pscustomobject]@{ Name = $n; Reading = $result[$n] } }
}

function ConvertFrom-Epoch($Epoch) {
  if ($null -eq $Epoch) { return $null }
  [DateTimeOffset]::FromUnixTimeSeconds([long]$Epoch).LocalDateTime
}

# "1h 05m" style text for the time until a Unix second.
function Format-Until($Epoch) {
  if ($null -eq $Epoch) { return '' }
  $s = [long]$Epoch - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  if ($s -le 0) { 'now' }
  elseif ($s -le 3540) { '{0}m' -f [Math]::Floor(($s + 59) / 60) }
  elseif ($s -lt 86400) { '{0}h {1:00}m' -f [Math]::Floor(($s + 59) / 3600), [Math]::Floor((($s + 59) % 3600) / 60) }
  else { '{0}d {1}h' -f [Math]::Floor($s / 86400), [Math]::Floor(($s % 86400) / 3600) }
}

function Test-OverLimit($Reading) {
  ($null -ne $Reading.SessionPct -and $Reading.SessionPct -ge 100) -or
  ($null -ne $Reading.WeeklyPct -and $Reading.WeeklyPct -ge 100)
}

# Where a profile's conversation history really lives, through any link.
function Get-HistoryPath([string]$Name) {
  $item = Get-Item -LiteralPath (Join-Path (Get-ProfileDir $Name) 'projects') -Force -ErrorAction Ignore
  if (-not $item) { return $null }
  $path = $item.FullName
  if ($item.LinkType -and $item.Target) { $path = @($item.Target)[0] }
  [IO.Path]::GetFullPath($path).TrimEnd('\')
}

# Two logins can carry on each other's conversations only when they keep them in the same place.
function Test-SharesHistory([string]$A, [string]$B) {
  $pa = Get-HistoryPath $A; $pb = Get-HistoryPath $B
  $pa -and $pb -and ($pa -eq $pb)
}

# The usable login furthest from either limit (session use breaks ties), or $null.
# A login at 0% session but 90% weekly is nearly out, so the higher one counts.
function Find-BestProfile($Readings, [string]$Exclude, [string]$SharesWith) {
  $best = $null; $bestWorst = 101; $bestS = 101
  foreach ($r in $Readings) {
    $x = $r.Reading
    if ($r.Name -eq $Exclude -or $x.Status -ne 'ok' -or $null -eq $x.SessionPct) { continue }
    if (Test-OverLimit $x) { continue }
    if ($SharesWith -and -not (Test-SharesHistory $SharesWith $r.Name)) { continue }
    $s = [int]$x.SessionPct
    $w = if ($null -eq $x.WeeklyPct) { 0 } else { [int]$x.WeeklyPct }
    $worst = [Math]::Max($s, $w)
    if ($worst -lt $bestWorst -or ($worst -eq $bestWorst -and $s -lt $bestS)) { $best = $r; $bestWorst = $worst; $bestS = $s }
  }
  $best
}
