# VS Code settings files are JSONC: JSON plus comments and trailing commas,
# which Windows PowerShell 5.1's ConvertFrom-Json cannot read. These helpers
# read them, and change one top-level setting at a time by editing only that
# setting's text, so the user's comments, order and formatting survive.

function Get-JsoncTokens([string]$Text) {
  $tokens = New-Object Collections.Generic.List[object]
  $i = 0; $n = $Text.Length
  while ($i -lt $n) {
    $ch = $Text[$i]
    if ([char]::IsWhiteSpace($ch)) { $i++; continue }
    if ($ch -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '/') {
      $j = $Text.IndexOf("`n", $i); if ($j -lt 0) { $j = $n }
      $i = $j; continue
    }
    if ($ch -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '*') {
      $j = $Text.IndexOf('*/', $i + 2); if ($j -lt 0) { throw 'a /* comment is never closed' }
      $i = $j + 2; continue
    }
    if ($ch -eq '"') {
      $j = $i + 1
      while ($j -lt $n -and $Text[$j] -ne '"') { if ($Text[$j] -eq '\') { $j++ }; $j++ }
      if ($j -ge $n) { throw 'a string is never closed' }
      $tokens.Add([pscustomobject]@{ Type = 'string'; Start = $i; End = $j + 1 }); $i = $j + 1; continue
    }
    if ('{}[]:,'.IndexOf($ch) -ge 0) {
      $tokens.Add([pscustomobject]@{ Type = [string]$ch; Start = $i; End = $i + 1 }); $i++; continue
    }
    $j = $i
    while ($j -lt $n -and -not [char]::IsWhiteSpace($Text[$j]) -and '{}[]:,/"'.IndexOf($Text[$j]) -lt 0) { $j++ }
    $tokens.Add([pscustomobject]@{ Type = 'literal'; Start = $i; End = $j }); $i = $j
  }
  , $tokens
}

# Parse JSONC text into objects (comments and trailing commas dropped).
function ConvertFrom-Jsonc([string]$Text) {
  $tk = Get-JsoncTokens $Text
  if ($tk.Count -eq 0) { return [pscustomobject]@{} }
  $sb = New-Object Text.StringBuilder
  for ($k = 0; $k -lt $tk.Count; $k++) {
    if ($tk[$k].Type -eq ',' -and $k + 1 -lt $tk.Count -and $tk[$k + 1].Type -in '}', ']') { continue }
    [void]$sb.Append($Text.Substring($tk[$k].Start, $tk[$k].End - $tk[$k].Start)).Append(' ')
  }
  $sb.ToString() | ConvertFrom-Json -ErrorAction Stop
}

# Where each top-level setting sits in the text.
function Get-JsoncLayout([string]$Text) {
  $tk = Get-JsoncTokens $Text
  if ($tk.Count -eq 0) { return $null }
  if ($tk[0].Type -ne '{') { throw 'the file is not a JSON object' }
  $members = New-Object Collections.Generic.List[object]
  $k = 1; $close = -1
  while ($true) {
    if ($k -ge $tk.Count) { throw 'the closing } is missing' }
    if ($tk[$k].Type -eq '}') { $close = $tk[$k].Start; $k++; break }
    if ($tk[$k].Type -ne 'string') { throw "a setting name was expected at character $($tk[$k].Start)" }
    $keyTok = $tk[$k]; $k++
    if ($k -ge $tk.Count -or $tk[$k].Type -ne ':') { throw "':' was expected after a setting name" }
    $k++
    if ($k -ge $tk.Count) { throw 'a value is missing' }
    $valueStart = $tk[$k].Start
    if ($tk[$k].Type -in '{', '[') {
      $depth = 0
      do {
        if ($tk[$k].Type -in '{', '[') { $depth++ } elseif ($tk[$k].Type -in '}', ']') { $depth-- }
        $k++
      } while ($depth -gt 0 -and $k -lt $tk.Count)
      if ($depth -ne 0) { throw 'a { or [ is never closed' }
      $valueEnd = $tk[$k - 1].End
    } elseif ($tk[$k].Type -in 'string', 'literal') {
      $valueEnd = $tk[$k].End; $k++
    } else { throw "a value was expected at character $($tk[$k].Start)" }
    $comma = -1
    if ($k -lt $tk.Count -and $tk[$k].Type -eq ',') { $comma = $tk[$k].Start; $k++ }
    elseif ($k -lt $tk.Count -and $tk[$k].Type -ne '}') { throw "',' or '}' was expected at character $($tk[$k].Start)" }
    $raw = $Text.Substring($keyTok.Start + 1, $keyTok.End - $keyTok.Start - 2)
    $members.Add([pscustomobject]@{
        Key = ($raw -replace '\\(["\\/])', '$1'); Start = $keyTok.Start
        ValueStart = $valueStart; ValueEnd = $valueEnd; Comma = $comma
      })
  }
  if ($k -lt $tk.Count) { throw 'there is text after the closing }' }
  [pscustomobject]@{ Open = $tk[0].Start; Close = $close; Members = $members }
}

function Get-JsoncIndent([string]$Text) {
  $m = [regex]::Match($Text, '(?m)^([ \t]+)"')
  if ($m.Success) { $m.Groups[1].Value } else { '    ' }
}

function Get-JsoncNewline([string]$Text) { if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" } }

function ConvertTo-JsonText([string]$s) {
  $sb = New-Object Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    $code = [int]$ch
    if ($code -eq 34) { [void]$sb.Append('\"') }
    elseif ($code -eq 92) { [void]$sb.Append('\\') }
    elseif ($code -eq 10) { [void]$sb.Append('\n') }
    elseif ($code -eq 13) { [void]$sb.Append('\r') }
    elseif ($code -eq 9) { [void]$sb.Append('\t') }
    elseif ($code -lt 32) { [void]$sb.AppendFormat('\u{0:x4}', $code) }
    else { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  $sb.ToString()
}

# Write a value the way VS Code lays out settings: one entry per line, and
# small objects inside arrays on one line.
function Format-JsonValue($Value, [int]$Level, [string]$Unit, [string]$Nl) {
  if ($null -eq $Value) { return 'null' }
  if ($Value -is [bool]) { return "$Value".ToLower() }
  if ($Value -is [string]) { return ConvertTo-JsonText $Value }
  if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
    return ([IFormattable]$Value).ToString($null, [Globalization.CultureInfo]::InvariantCulture)
  }
  $pad = $Unit * ($Level + 1); $end = $Unit * $Level
  if ($Value -is [Collections.IDictionary] -or $Value -is [Management.Automation.PSCustomObject]) {
    $parts = New-Object Collections.Generic.List[string]
    if ($Value -is [Collections.IDictionary]) {
      foreach ($k in @($Value.Keys)) { $parts.Add((ConvertTo-JsonText "$k") + ': ' + (Format-JsonValue $Value[$k] ($Level + 1) $Unit $Nl)) }
    } else {
      foreach ($p in $Value.PSObject.Properties) { $parts.Add((ConvertTo-JsonText $p.Name) + ': ' + (Format-JsonValue $p.Value ($Level + 1) $Unit $Nl)) }
    }
    if ($parts.Count -eq 0) { return '{}' }
    $inline = $Level -ge 2
    if ($inline) { return '{ ' + ($parts -join ', ') + ' }' }
    return '{' + $Nl + (($parts | ForEach-Object { "$pad$_" }) -join ",$Nl") + $Nl + $end + '}'
  }
  if ($Value -is [Collections.IEnumerable]) {
    $items = @($Value)
    if ($items.Count -eq 0) { return '[]' }
    $parts = foreach ($v in $items) { Format-JsonValue $v ($Level + 1) $Unit $Nl }
    $simple = -not ($items | Where-Object { $_ -is [Collections.IDictionary] -or $_ -is [Management.Automation.PSCustomObject] -or ($_ -is [Collections.IEnumerable] -and $_ -isnot [string]) })
    if ($Level -ge 2 -and $simple) { return '[ ' + ($parts -join ', ') + ' ]' }
    return '[' + $Nl + (($parts | ForEach-Object { "$pad$_" }) -join ",$Nl") + $Nl + $end + ']'
  }
  ConvertTo-JsonText "$Value"
}

# The current value of a top-level setting, or $null.
function Get-JsoncMember([string]$Text, [string]$Key) {
  $layout = Get-JsoncLayout $Text
  if (-not $layout) { return $null }
  $m = $layout.Members | Where-Object Key -eq $Key | Select-Object -Last 1
  if (-not $m) { return $null }
  , (ConvertFrom-Jsonc ('{"v":' + $Text.Substring($m.ValueStart, $m.ValueEnd - $m.ValueStart) + '}')).v
}

# Set a setting in an object's text, touching only that setting's text.
# Level is how deep the object sits (1 = the file itself); Unit is one indent.
function Set-JsoncMember([string]$Text, [string]$Key, $Value, [int]$Level = 1, [string]$Unit) {
  if (-not $Text.Trim()) { $Text = "{}" }
  $layout = Get-JsoncLayout $Text
  if (-not $Unit) { $Unit = Get-JsoncIndent $Text }
  $nl = Get-JsoncNewline $Text
  $json = Format-JsonValue $Value $Level $Unit $nl
  $m = $layout.Members | Where-Object Key -eq $Key | Select-Object -Last 1
  if ($m) { return $Text.Substring(0, $m.ValueStart) + $json + $Text.Substring($m.ValueEnd) }
  $entry = "$($Unit * $Level)$(ConvertTo-JsonText $Key): $json"
  if ($layout.Members.Count -eq 0) {
    $inside = $Text.Substring($layout.Open + 1, $layout.Close - $layout.Open - 1)
    if (-not $inside.Trim()) {
      return $Text.Substring(0, $layout.Open + 1) + "$nl$entry$nl$($Unit * ($Level - 1))" + $Text.Substring($layout.Close)
    }
    return $Text.Substring(0, $layout.Close) + "$entry$nl" + $Text.Substring($layout.Close)
  }
  $last = $layout.Members[$layout.Members.Count - 1]
  if ($last.Comma -ge 0) {
    $at = Get-JsoncLineEnd $Text ($last.Comma + 1)
    return $Text.Substring(0, $at) + "$nl$entry," + $Text.Substring($at)
  }
  $at = Get-JsoncLineEnd $Text $last.ValueEnd
  $Text.Substring(0, $last.ValueEnd) + ',' + $Text.Substring($last.ValueEnd, $at - $last.ValueEnd) + "$nl$entry" + $Text.Substring($at)
}

# Where to add a line after position $Pos: past a // comment that ends that line, so it stays with its setting.
function Get-JsoncLineEnd([string]$Text, [int]$Pos) {
  $i = $Pos
  while ($i -lt $Text.Length -and ($Text[$i] -eq ' ' -or $Text[$i] -eq "`t")) { $i++ }
  if ($i + 1 -lt $Text.Length -and $Text[$i] -eq '/' -and $Text[$i + 1] -eq '/') {
    $j = $Text.IndexOf("`n", $i)
    if ($j -lt 0) { return $Text.Length }
    if ($j -gt 0 -and $Text[$j - 1] -eq "`r") { $j-- }
    return $j
  }
  $Pos
}

# Remove a top-level setting, touching only its own text.
function Remove-JsoncMember([string]$Text, [string]$Key) {
  $layout = Get-JsoncLayout $Text
  if (-not $layout) { return $Text }
  $list = $layout.Members
  for ($idx = $list.Count - 1; $idx -ge 0; $idx--) {
    if ($list[$idx].Key -ne $Key) { continue }
    $m = $list[$idx]
    $from = $m.Start
    while ($from -gt 0 -and [char]::IsWhiteSpace($Text[$from - 1])) { $from-- }
    if ($m.Comma -ge 0) {
      $Text = $Text.Substring(0, $from) + $Text.Substring($m.Comma + 1)
    } elseif ($idx -gt 0) {
      # The last setting: drop it, then the comma the one before it no longer needs.
      $prev = $list[$idx - 1]
      $Text = $Text.Substring(0, $from) + $Text.Substring($m.ValueEnd)
      $Text = $Text.Substring(0, $prev.Comma) + $Text.Substring($prev.Comma + 1)
    } else {
      $Text = $Text.Substring(0, $from) + $Text.Substring($m.ValueEnd)
    }
    return (Remove-JsoncMember $Text $Key)
  }
  $Text
}

# Set one entry inside a top-level object setting (creating the setting if
# needed), editing only that entry's text so comments next to others survive.
function Set-JsoncEntry([string]$Text, [string]$Key, [string]$Name, $Value) {
  $layout = if ($Text.Trim()) { Get-JsoncLayout $Text }
  $m = if ($layout) { $layout.Members | Where-Object Key -eq $Key | Select-Object -Last 1 }
  if (-not $m -or $Text[$m.ValueStart] -ne '{') {
    return Set-JsoncMember $Text $Key ([ordered]@{ $Name = $Value })
  }
  $inner = $Text.Substring($m.ValueStart, $m.ValueEnd - $m.ValueStart)
  $Text.Substring(0, $m.ValueStart) + (Set-JsoncMember $inner $Name $Value 2 (Get-JsoncIndent $Text)) + $Text.Substring($m.ValueEnd)
}

# Remove one entry from a top-level object setting; the setting goes too once it is empty.
function Remove-JsoncEntry([string]$Text, [string]$Key, [string]$Name) {
  $layout = if ($Text.Trim()) { Get-JsoncLayout $Text }
  $m = if ($layout) { $layout.Members | Where-Object Key -eq $Key | Select-Object -Last 1 }
  if (-not $m -or $Text[$m.ValueStart] -ne '{') { return $Text }
  $inner = Remove-JsoncMember $Text.Substring($m.ValueStart, $m.ValueEnd - $m.ValueStart) $Name
  if ((Get-JsoncLayout $inner).Members.Count -eq 0) { return Remove-JsoncMember $Text $Key }
  $Text.Substring(0, $m.ValueStart) + $inner + $Text.Substring($m.ValueEnd)
}

# Read a settings file, change it with $Edit, and write it back only if it
# changed. A file that cannot be read is never overwritten: the error says
# what to add by hand instead.
function Update-JsoncFile([string]$Path, [scriptblock]$Edit, [string]$Snippet) {
  $text = ''; $bom = $false
  if (Test-Path -LiteralPath $Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = (New-Object Text.UTF8Encoding($false)).GetString($bytes)
    if ($bom) { $text = $text.Substring(1) }
  }
  try {
    [void](ConvertFrom-Jsonc $text)
    $layout = if ($text.Trim()) { Get-JsoncLayout $text }
    $new = & $Edit $text
    [void](ConvertFrom-Jsonc $new)
  } catch {
    Stop-Cs ("could not read $Path ($($_.Exception.Message)), so it was left as it is. Add this to it yourself:`n$Snippet")
  }
  if ($new -ceq $text) { return }
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($Path, $new, (New-Object Text.UTF8Encoding($bom)))
}

# A PSCustomObject's properties as an ordered dictionary (empty for $null).
function ConvertTo-OrderedMap($Object) {
  $map = [ordered]@{}
  if ($Object -is [Management.Automation.PSCustomObject]) { foreach ($p in $Object.PSObject.Properties) { $map[$p.Name] = $p.Value } }
  $map
}
