function Get-ClaudeUsage {
  <#
  .SYNOPSIS
  Show every login's 5-hour session and weekly limits, as objects.
  .DESCRIPTION
  The same numbers /usage shows inside Claude Code. All logins are asked at
  once. -Cached uses readings remembered in the last CSWITCH_USAGE_TTL seconds
  (default 120) instead of asking again. -Json prints the same JSON as
  'cswitch usage --json' in bin/cswitch.
  .EXAMPLE
  Get-ClaudeUsage | Where-Object WeeklyPct -lt 50
  #>
  [CmdletBinding()]
  param(
    [Parameter(Position = 0)][string[]]$Name,
    [switch]$Cached,
    [switch]$Json,
    [int]$TimeoutSec = 15
  )
  $names = @(Get-ProfileNames | Where-Object { -not $Name -or $Name -contains $_ })
  $maxAge = if ($Cached) { Get-UsageTtl } else { 0 }
  $readings = @(Get-UsageReadings $names $maxAge $TimeoutSec)
  $rows = @(ConvertTo-UsageRows $readings)
  if ($Json) { ConvertTo-UsageJson $rows } else { $rows }
}

function ConvertTo-UsageRows($Readings) {
  $active = Get-ActiveProfileName
  $last = Get-LastProfileName
  $best = Find-BestProfile $Readings
  foreach ($r in $Readings) {
    $x = $r.Reading
    [pscustomobject]@{
      PSTypeName      = 'ClaudeSwitch.Usage'
      Profile         = $r.Name
      Account         = Hide-Email (Get-ProfileEmail $r.Name)
      Status          = $x.Status
      SessionPct      = $x.SessionPct
      SessionResetsAt = ConvertFrom-Epoch $x.SessionAt
      SessionResetsIn = Format-Until $x.SessionAt
      WeeklyPct       = $x.WeeklyPct
      WeeklyResetsAt  = ConvertFrom-Epoch $x.WeeklyAt
      WeeklyResetsIn  = Format-Until $x.WeeklyAt
      Active          = ($r.Name -eq $active)
      LastUsed        = ($r.Name -eq $last)
      MostRoom        = ($null -ne $best -and $r.Name -eq $best.Name -and @($Readings).Count -gt 1)
    }
  }
}

function ConvertTo-JsonString($Value) {
  if ($null -eq $Value -or "$Value" -eq '') { return 'null' }
  '"' + ("$Value" -replace '\\', '\\' -replace '"', '\"') + '"'
}

function ConvertTo-JsonIso($Date) {
  if ($null -eq $Date) { return 'null' }
  '"' + ([DateTimeOffset]$Date).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) + '"'
}

# Byte-for-byte the shape bin/cswitch prints for 'usage --json'.
function ConvertTo-UsageJson($Rows) {
  $items = foreach ($r in $Rows) {
    $s = if ($null -eq $r.SessionPct) { 'null' } else { $r.SessionPct }
    $w = if ($null -eq $r.WeeklyPct) { 'null' } else { $r.WeeklyPct }
    '{"name":' + (ConvertTo-JsonString $r.Profile) + ',"email":' + (ConvertTo-JsonString $r.Account) +
    ',"status":"' + $r.Status + '","active":' + "$($r.Active)".ToLower() + ',"last_used":' + "$($r.LastUsed)".ToLower() +
    ',"session":{"percent":' + $s + ',"resets_at":' + (ConvertTo-JsonIso $r.SessionResetsAt) + '}' +
    ',"weekly":{"percent":' + $w + ',"resets_at":' + (ConvertTo-JsonIso $r.WeeklyResetsAt) + '}}'
  }
  '[' + (@($items) -join ',') + ']'
}
