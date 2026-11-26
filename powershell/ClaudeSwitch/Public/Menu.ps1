# The account menu. Glyphs are built from code points because Windows
# PowerShell 5.1 reads a .ps1 file without a BOM as ANSI.

$script:Glyph = @{
  Pointer = [string][char]0x276F
  Arrows  = (ConvertFrom-CodePoints '<2191>/<2193>')
  Dot     = [string][char]0x00B7
}

# The Claude Code pet and the name, on the same grid of half-height pixels.
$script:BannerPet = @(
  ' <2590><259B><2588><2588><2588><259C><258C> '
  '<259D><259C><2588><2588><2588><2588><2588><259B><2598>'
  '  <2598><2598> <259D><259D>  '
) | ForEach-Object { (ConvertFrom-CodePoints $_) }
$script:BannerWord = @(
  ' <2584><2580><2580><2580>  <2584><2580><2580><2580><2580> <2588>   <2588> <2580><2588><2580> <2580><2580><2588><2580><2580> <2584><2580><2580><2580>  <2588>   <2588>'
  ' <2588>      <2580><2580><2580><2584> <2588> <2588> <2588>  <2588>    <2588>   <2588>     <2588><2580><2580><2580><2588>'
  '  <2580><2580><2580>  <2580><2580><2580><2580>   <2580> <2580>  <2580><2580><2580>   <2580>    <2580><2580><2580>  <2580>   <2580>'
) | ForEach-Object { (ConvertFrom-CodePoints $_) }

# The banner lines that fit a window of Rows x Cols with a menu of MenuRows.
function Get-Banner([int]$MenuRows, [int]$Rows, [int]$Cols, $Palette) {
  if ($env:CSWITCH_BANNER -eq '0' -or $Rows -lt ($MenuRows + 9)) { return @() }
  if ($Cols -ge 56) {
    0..2 | ForEach-Object { "$($Palette.Accent)$($script:BannerPet[$_]) $($script:BannerWord[$_])$($Palette.Reset)" }
  } elseif ($Cols -ge 14) {
    0..2 | ForEach-Object { "$($Palette.Accent)$($script:BannerPet[$_])$($Palette.Reset)" }
  } else { @() }
}

function Get-LevelColor($Pct, $Palette) {
  if ($null -eq $Pct) { '' } elseif ($Pct -ge 80) { $Palette.Red } elseif ($Pct -ge 50) { $Palette.Yellow } else { $Palette.Green }
}

# One line about a login's limits.
function Format-LimitsBrief($Reading, $Palette) {
  $c = $Palette
  switch ($Reading.Status) {
    'ok' {
      $s = $Reading.SessionPct; $w = $Reading.WeeklyPct
      if ($null -eq $s -and $null -eq $w) { return "$($c.Dim)no plan limits$($c.Reset)" }
      if (Test-OverLimit $Reading) {
        $at = if ($null -ne $s -and $s -ge 100) { $Reading.SessionAt } else { $Reading.WeeklyAt }
        return "$($c.Red)limit reached, resets in $(Format-Until $at)$($c.Reset)"
      }
      $sv = if ($null -eq $s) { '-' } else { "$s" }; $wv = if ($null -eq $w) { '-' } else { "$w" }
      return ('5h {0}{1,3}%{2}  7d {3}{4,3}%{2}' -f (Get-LevelColor $s $c), $sv, $c.Reset, (Get-LevelColor $w $c), $wv)
    }
    'logged-out' { return "$($c.Dim)not logged in$($c.Reset)" }
    'expired' { return "$($c.Yellow)login expired$($c.Reset)" }
    default { return "$($c.Dim)limits unavailable$($c.Reset)" }
  }
}

function Select-ClaudeProfile {
  <#
  .SYNOPSIS
  Ask which Claude account to use, and return its profile name.
  .DESCRIPTION
  Arrow keys or j/k move, Enter picks, 1-9 picks a row directly, q or Esc
  cancels (and returns nothing). The menu starts on the login used last,
  unless that one has reached a limit and another still has room.
  #>
  [CmdletBinding()]
  param()
  if (-not (Test-Interactive)) { Stop-Cs "no console to ask on; use 'cswitch <name>'" }
  $c = Get-Palette
  $names = @(Get-ProfileNames)
  $count = $names.Count

  if ($script:Term.ContainsKey('Begin')) { & $script:Term.Begin }
  Write-Term "  $($c.Dim)checking limits...$($c.Reset)"
  $readings = @(Get-UsageReadings $names (Get-UsageTtl) 3)
  $best = Find-BestProfile $readings
  $bestIndex = if ($best) { [array]::IndexOf($names, $best.Name) } else { -1 }

  $last = Get-LastProfileName
  $startOn = if ($env:CLAUDE_CONFIG_DIR) { Get-ActiveProfileName } else { $last }
  $sel = [Math]::Max(0, [array]::IndexOf($names, $startOn))
  if ($readings[$sel].Reading.Status -eq 'ok' -and (Test-OverLimit $readings[$sel].Reading) -and $bestIndex -ge 0) { $sel = $bestIndex }

  $emails = foreach ($n in $names) { $e = Hide-Email (Get-ProfileEmail $n); if ($e) { $e } else { 'not logged in' } }
  $briefs = foreach ($r in $readings) { Format-LimitsBrief $r.Reading $c }
  $nameWidth = ($names | Measure-Object -Property Length -Maximum).Maximum
  $emailWidth = ($emails | Measure-Object -Property Length -Maximum).Maximum
  $size = & $script:Term.Size
  $banner = @(Get-Banner $count $size[0] $size[1] $c)

  $e = [char]27
  $drawn = 0
  try {
    # No cursor and no line wrap while the menu is up, so redraws stay in place.
    Write-Term "$e[?25l$e[?7l"
    while ($true) {
      $lines = New-Object Collections.Generic.List[string]
      $lines.Add('')
      if ($banner.Count) { foreach ($b in $banner) { $lines.Add("  $b") }; $lines.Add('') }
      $lines.Add("  $($c.Bold)Which Claude account?$($c.Reset)")
      $lines.Add('')
      for ($i = 0; $i -lt $count; $i++) {
        $tag = ''
        if ($names[$i] -eq $last) { $tag = '  last used' }
        if ($i -eq $bestIndex -and $count -gt 1) { $tag += '  most room' }
        $num = if ($i -lt 9) { "$($i + 1)" } else { ' ' }
        $n = $names[$i].PadRight($nameWidth); $m = $emails[$i].PadRight($emailWidth)
        if ($i -eq $sel) {
          $lines.Add("  $($c.Accent)$($c.Bold)$($script:Glyph.Pointer) $num  $n  $m$($c.Reset)  $($briefs[$i])$($c.Dim)$tag$($c.Reset)")
        } else {
          $lines.Add("    $($c.Dim)$num$($c.Reset)  $n  $($c.Dim)$m$($c.Reset)  $($briefs[$i])$($c.Dim)$tag$($c.Reset)")
        }
      }
      $lines.Add('')
      $d = $script:Glyph.Dot
      $lines.Add("  $($c.Dim)$($script:Glyph.Arrows) move  $d  enter select  $d  1-9 pick  $d  q cancel$($c.Reset)")

      $frame = if ($drawn) { "$e[$($drawn)A" } else { "`r$e[2K" }
      $frame += ($lines | ForEach-Object { "`r$e[2K$_" }) -join "`n"
      Write-Term "$frame`n"
      $drawn = $lines.Count

      $key = & $script:Term.ReadKey
      if ($key -in 'up', 'k') { $sel = ($sel + $count - 1) % $count }
      elseif ($key -in 'down', 'j') { $sel = ($sel + 1) % $count }
      elseif ($key -in 'enter', ' ') { break }
      elseif ($key -in 'cancel', 'q') { $sel = -1; break }
      elseif ($key -match '^[1-9]$' -and [int]$key -le $count) { $sel = [int]$key - 1; break }
    }
  } finally {
    Write-Term "$e[$($drawn)A`r$e[J$e[?7h$e[?25h"
    if ($sel -ge 0) { Write-Term "  $($c.Accent)$($script:Glyph.Pointer)$($c.Reset) $($names[$sel]) $($c.Dim)$($emails[$sel])$($c.Reset)`n" }
    if ($script:Term.ContainsKey('End')) { & $script:Term.End }
  }
  if ($sel -lt 0) { return }
  $names[$sel]
}
