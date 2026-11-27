Describe 'install.ps1' {
  BeforeAll {
    $repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $installer = Join-Path $repo 'install.ps1'
    $module = Join-Path $repo 'powershell\ClaudeSwitch'
  }

  It 'downloads every file the module is made of, and nothing else' {
    $block = [regex]::Match((Get-Content $installer -Raw), '\$files = @\(([\s\S]*?)\)').Groups[1].Value
    $listed = ([regex]::Matches($block,"'((?:Private|Public)/[\w.-]+\.ps1|ClaudeSwitch\.[\w.]+)'") | ForEach-Object { $_.Groups[1].Value }) | Sort-Object
    $actual = Get-ChildItem $module -Recurse -File | ForEach-Object { $_.FullName.Substring($module.Length + 1).Replace('\', '/') } | Sort-Object
    $listed | Should -Be $actual
  }

  It 'installs a working module where PowerShell finds it' {
    $dest = Join-Path ([IO.Path]::GetTempPath()) ('cswitch-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
      powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Source $module -ModulesPath $dest | Out-Null
      $LASTEXITCODE | Should -Be 0
      $version = (Import-PowerShellDataFile (Join-Path $module 'ClaudeSwitch.psd1')).ModuleVersion
      Join-Path $dest "ClaudeSwitch\$version\ClaudeSwitch.psd1" | Should -Exist
      $out = powershell -NoProfile -Command "`$env:PSModulePath = '$dest;' + `$env:PSModulePath; Import-Module ClaudeSwitch; cswitch --version"
      $out | Should -Be "cswitch $version (PowerShell)"
    } finally {
      Remove-Item $dest -Recurse -Force -ErrorAction Ignore
    }
  }
}
