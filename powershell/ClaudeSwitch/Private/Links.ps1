# Sharing ~/.claude with a profile on Windows, without admin rights:
#   folders -> directory junctions (never need admin or Developer Mode)
#   files   -> symbolic links when allowed (Developer Mode), else hard links
# A copy is never made: a copied settings.json or projects folder silently
# drifts apart and breaks the handoff between logins.
#
# CSWITCH_FILE_LINKS picks the file link type: auto (default), symlink, hardlink.

function New-SharedLink([string]$Target, [string]$Link) {
  if (Test-Path -LiteralPath $Target -PathType Container) {
    New-Item -ItemType Junction -Path $Link -Target $Target -ErrorAction Stop | Out-Null
    return 'junction'
  }
  $mode = if ($env:CSWITCH_FILE_LINKS) { $env:CSWITCH_FILE_LINKS } else { 'auto' }
  if ($mode -in 'auto', 'symlink') {
    try {
      New-Item -ItemType SymbolicLink -Path $Link -Target $Target -ErrorAction Stop | Out-Null
      return 'symlink'
    } catch {
      if ($mode -eq 'symlink') {
        Stop-Cs "could not link $Link. Turn on Developer Mode (Settings > System > For developers) or set CSWITCH_FILE_LINKS=hardlink"
      }
    }
  }
  try {
    New-Item -ItemType HardLink -Path $Link -Target $Target -ErrorAction Stop | Out-Null
    'hardlink'
  } catch {
    Stop-Cs "could not link $Link to $Target ($($_.Exception.Message)). Profiles and ~\.claude must be on the same drive for hard links; turning on Developer Mode allows symbolic links instead"
  }
}

# What a shared item in a profile currently is: junction, symlink, hardlink,
# copy (a plain file or folder: the link was lost), or missing.
function Get-SharedLinkState([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Ignore
  if (-not $item) { return 'missing' }
  switch ($item.LinkType) {
    'Junction' { 'junction' }
    'SymbolicLink' { 'symlink' }
    'HardLink' { 'hardlink' }
    default { 'copy' }
  }
}

# A profile made with --isolated carries this marker; it shares nothing on purpose.
function Test-IsolatedProfile([string]$Name) {
  $Name -ne 'default' -and (Test-Path -LiteralPath (Join-Path (Get-ProfileDir $Name) '.cswitch-isolated'))
}

# The state of every shared item of a profile that ~\.claude has.
function Get-SharedItemStates([string]$Name) {
  $dir = Get-ProfileDir $Name
  foreach ($item in $script:SharedItems) {
    $target = Join-Path (Get-CsBase) $item
    if (-not (Test-Path -LiteralPath $target)) { continue }
    [pscustomobject]@{
      Item   = $item
      Target = $target
      Path   = Join-Path $dir $item
      Folder = Test-Path -LiteralPath $target -PathType Container
      State  = Get-SharedLinkState (Join-Path $dir $item)
    }
  }
}

# Put a lost link back. A file copy that is newer than ~\.claude's (an editor
# or Claude Code saved over the link) first passes its contents on. A folder
# copy adds the files ~\.claude lacks, is kept as <item>.cswitch-backup-<time>,
# and is replaced by a junction. Returns what it did.
function Repair-SharedItem($State) {
  switch ($State.State) {
    'missing' {
      $kind = New-SharedLink $State.Target $State.Path
      return "linked $($State.Item) ($kind)"
    }
    'copy' {
      if (-not $State.Folder) {
        $copy = Get-Item -LiteralPath $State.Path -Force
        $base = Get-Item -LiteralPath $State.Target -Force
        $note = ''
        if ($copy.LastWriteTimeUtc -gt $base.LastWriteTimeUtc) {
          # Written in place, so other links to the ~\.claude file stay intact.
          [IO.File]::WriteAllBytes($base.FullName, [IO.File]::ReadAllBytes($copy.FullName))
          $note = ', keeping its newer contents'
        }
        [IO.File]::Delete($copy.FullName)
        $kind = New-SharedLink $State.Target $State.Path
        return "relinked $($State.Item) ($kind$note)"
      }
      $added = 0
      $root = (Get-Item -LiteralPath $State.Path -Force).FullName.TrimEnd('\')
      Get-ChildItem -LiteralPath $root -Recurse -File -Force -Attributes !ReparsePoint | ForEach-Object {
        $dest = Join-Path $State.Target $_.FullName.Substring($root.Length + 1)
        if (-not (Test-Path -LiteralPath $dest)) {
          New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
          Copy-Item -LiteralPath $_.FullName -Destination $dest
          $added++
        }
      }
      $backup = "$($State.Item).cswitch-backup-$((Get-Date).ToString('yyyyMMddHHmmss'))"
      Rename-Item -LiteralPath $State.Path -NewName $backup
      $kind = New-SharedLink $State.Target $State.Path
      return "relinked $($State.Item) ($kind; added $added file(s) to ~\.claude; the copy is kept as $backup)"
    }
  }
}

# Delete a link without ever following it into what it points at.
function Remove-SharedLink([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Ignore
  if (-not $item) { return }
  if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName, $false) }
  else { [IO.File]::Delete($item.FullName) }
}

# Delete a profile folder, unlinking its shared items first so the recursive
# delete can never follow a junction or symlink into ~\.claude.
function Remove-ProfileDir([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) { return }
  Get-ChildItem -LiteralPath $Dir -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint -or $_.LinkType } |
    ForEach-Object { Remove-SharedLink $_.FullName }
  Remove-Item -LiteralPath $Dir -Recurse -Force
}
