# Paths and names shared by every command. These follow docs/CONTRACT.md.

$script:SharedItems = @('settings.json', 'CLAUDE.md', 'keybindings.json', 'skills', 'commands', 'agents', 'plugins', 'projects')

function Get-CsHome {
  if ($env:CSWITCH_HOME) { $env:CSWITCH_HOME } else { Join-Path $HOME '.claude-profiles' }
}

# The stock Claude Code config: the "default" profile and the source of shared files.
function Get-CsBase {
  if ($env:CSWITCH_BASE) { $env:CSWITCH_BASE } else { Join-Path $HOME '.claude' }
}

function Get-ProfileDir([string]$Name) {
  if ($Name -eq 'default') { Get-CsBase } else { Join-Path (Get-CsHome) $Name }
}

# '<2590><259B>' -> the characters U+2590 U+259B. Source files stay ASCII,
# because Windows PowerShell 5.1 reads a .ps1 without a BOM as ANSI.
function ConvertFrom-CodePoints([string]$Text) {
  [regex]::Replace($Text, '<([0-9A-Fa-f]{4})>', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) })
}

function Stop-Cs([string]$Message) {
  throw "cswitch: $Message"
}

# Profile names: letters, digits, '.', '_' and '-', not starting with '.' or '-'.
# Windows also refuses device names (CON, NUL, COM1...) and trailing dots.
function Test-ProfileName([string]$Name) {
  if ($Name -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9._-]*$') { return $false }
  if ($Name.EndsWith('.')) { return $false }
  if (($Name -split '\.')[0] -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$') { return $false }
  $true
}

$script:ReservedNames = @('default', 'add', 'list', 'ls', 'usage', 'best', 'run', 'env', 'remove', 'rm', 'pick',
  'init', 'statusline', 'update', '_claude', 'help', 'version', 'setup', 'doctor', 'pin', 'unpin', 'vscode')

function Test-ProfileExists([string]$Name) {
  if ($Name -eq 'default') { return $true }
  (Test-ProfileName $Name) -and (Test-Path -LiteralPath (Join-Path (Get-CsHome) $Name) -PathType Container)
}

# "default" first, then every profile folder in name order.
function Get-ProfileNames {
  $names = @('default')
  $csHome = Get-CsHome
  if (Test-Path -LiteralPath $csHome) {
    $names += @(Get-ChildItem -LiteralPath $csHome -Directory -Force |
        Where-Object { Test-ProfileName $_.Name } | Sort-Object Name | ForEach-Object Name)
  }
  $names
}

# The profile this shell points at through CLAUDE_CONFIG_DIR, if any.
function Get-ActiveProfileName {
  $dir = $env:CLAUDE_CONFIG_DIR
  if (-not $dir) { return 'default' }
  $parent = [IO.Path]::GetFullPath((Get-CsHome)).TrimEnd('\', '/')
  $full = [IO.Path]::GetFullPath($dir).TrimEnd('\', '/')
  if ([IO.Path]::GetDirectoryName($full) -eq $parent) { return [IO.Path]::GetFileName($full) }
  if ($full -eq [IO.Path]::GetFullPath((Get-CsBase)).TrimEnd('\', '/')) { return 'default' }
  $null
}

function Get-LastProfileName {
  $f = Join-Path (Get-CsHome) '.last'
  if (Test-Path -LiteralPath $f) { (Get-Content -LiteralPath $f -TotalCount 1) -as [string] }
}

function Set-LastProfileName([string]$Name) {
  $csHome = Get-CsHome
  if (Test-Path -LiteralPath $csHome) { Write-CsFile (Join-Path $csHome '.last') "$Name`n" }
}

# UTF-8 without a BOM and with LF endings, so bin/cswitch reads it as written.
function Write-CsFile([string]$Path, [string]$Text) {
  $tmp = "$Path.$PID"
  try {
    [IO.File]::WriteAllText($tmp, $Text, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, $null) } else { [IO.File]::Move($tmp, $Path) }
  } catch {
    Remove-Item -LiteralPath $tmp -ErrorAction Ignore
  }
}

# "jane.doe@gmail.com" -> "ja***e@g***.com". CSWITCH_SHOW_EMAIL=1 shows it whole.
function Hide-Email([string]$Email) {
  if (-not $Email -or $Email -notmatch '@') { return $Email }
  if ($env:CSWITCH_SHOW_EMAIL -eq '1') { return $Email }
  $at = $Email.IndexOf('@')
  $user = $Email.Substring(0, $at); $domain = $Email.Substring($at + 1)
  if ($user.Length -le 3) { $user = $user.Substring(0, [Math]::Min(1, $user.Length)) + '***' }
  else { $user = $user.Substring(0, 2) + '***' + $user.Substring($user.Length - 1) }
  if ($domain -match '\.') { $domain = $domain.Substring(0, 1) + '***.' + $domain.Substring($domain.LastIndexOf('.') + 1) }
  elseif ($domain) { $domain = $domain.Substring(0, 1) + '***' }
  "$user@$domain"
}

# The logged-in account's email, from the profile's .claude.json.
function Get-ProfileEmail([string]$Name) {
  $file = if ($Name -eq 'default') { Join-Path (Split-Path (Get-CsBase) -Parent) '.claude.json' }
  else { Join-Path (Get-ProfileDir $Name) '.claude.json' }
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  $m = [regex]::Match([IO.File]::ReadAllText($file), '"emailAddress"\s*:\s*"([^"]*)"')
  if ($m.Success) { $m.Groups[1].Value }
}

function Assert-ProfileExists([string]$Name) {
  if (-not $Name) { Stop-Cs 'missing profile name' }
  if (-not (Test-ProfileExists $Name)) { Stop-Cs "no such profile: $Name (see 'cswitch list')" }
}
