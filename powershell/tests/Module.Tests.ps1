Describe 'The ClaudeSwitch module' {
  BeforeAll { $root = Join-Path $PSScriptRoot '..\ClaudeSwitch' }

  It 'has a valid manifest' {
    { Test-ModuleManifest (Join-Path $root 'ClaudeSwitch.psd1') -ErrorAction Stop } | Should -Not -Throw
  }

  It 'defines every function its manifest exports' {
    $m = Import-Module (Join-Path $root 'ClaudeSwitch.psd1') -Force -PassThru
    $declared = (Import-PowerShellDataFile (Join-Path $root 'ClaudeSwitch.psd1')).FunctionsToExport
    $m.ExportedFunctions.Keys | Sort-Object | Should -Be ($declared | Sort-Object)
  }

  It 'keeps every script ASCII, so Windows PowerShell 5.1 reads it the same as pwsh 7' {
    Get-ChildItem $root -Recurse -Include *.ps1, *.psm1, *.psd1, *.ps1xml | ForEach-Object {
      $bad = [IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -gt 127 } | Select-Object -First 1
      if ($null -ne $bad) { throw "$($_.Name) contains non-ASCII bytes" }
    }
  }
}
