param(
  [string]$IncludeDirectory = 'vcpkg_installed/x64-windows-static/x64-windows-static/include'
)
$ErrorActionPreference = 'Stop'
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$includePath = (Resolve-Path -LiteralPath $IncludeDirectory).Path
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'MSVC installation not found' }
$vcvars = Join-Path $installation 'VC/Auxiliary/Build/vcvars64.bat'
# Import the compiler environment only into this PowerShell process. No file
# writes, linking, unity source or precompiled header can mask missing includes.
$compilerEnvironment = & $env:ComSpec /d /c "call `"$vcvars`" >nul && set"
if ($LASTEXITCODE -ne 0) { throw 'Could not initialize MSVC' }
foreach ($line in $compilerEnvironment) {
  if ($line -match '^([^=]+)=(.*)$') {
    [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
  }
}
$flags = @('/nologo', '/Zs', '/std:c++17', '/EHsc', '/DNDEBUG', '/DWIN32',
  '/DNOMINMAX', '/DASIO_STANDALONE', '/DCURL_STATICLIB', '/DFW_GRAPHICS',
  '/DFW_NET', '/DFW_XML', '/DFW_SOUND', '/DFW_CAM', '/DWITH_ENCRYPTION',
  '/D_WIN32_WINNT=0x0601', "/I$includePath", "/I$(Join-Path $repoPath 'src')")
foreach ($file in @('src/client/luafunctions_client.cpp', 'src/client/minimap.cpp')) {
  & cl.exe @flags (Join-Path $repoPath $file)
  if ($LASTEXITCODE -ne 0) { throw "Standalone translation-unit check failed: $file" }
  Write-Output "PASS: standalone MSVC translation unit (no unity/PCH): $file"
}
