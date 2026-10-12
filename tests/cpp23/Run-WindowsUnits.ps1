param([string]$VcpkgTriplet = '', [string]$VcVars = '')
$ErrorActionPreference = 'Stop'
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $VcpkgTriplet) { $VcpkgTriplet = Join-Path $repoPath 'vcpkg_installed/x64-windows-static/x64-windows-static' }
if (-not $VcVars) {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
  $vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  $VcVars = Join-Path $vsPath 'VC/Auxiliary/Build/vcvars64.bat'
}
$output = Join-Path $repoPath 'build/cpp23/windows-units'
New-Item -ItemType Directory -Path "$output/splash/data/images" -Force | Out-Null
Copy-Item -LiteralPath "$repoPath/data/images/splash.png" -Destination "$output/splash/data/images/splash.png"
$flags = "/nologo /O2 /MT /std:c++23preview /Zc:__cplusplus /FIframework/stdext/cxx23.h /EHsc /DNDEBUG /DWIN32 /DNOMINMAX /DASIO_STANDALONE /DCURL_STATICLIB /D_WIN32_WINNT=0x0601 /Isrc /I`"$VcpkgTriplet/include`""
$commands = @(
  "call `"$VcVars`" >nul",
  "cl $flags /Gy /Fe:`"$output/utilities.exe`" /Fo:`"$output/`" .github/tests/standalone_util.cpp src/framework/stdext/string.cpp /link /OPT:REF ws2_32.lib",
  "`"$output/utilities.exe`"",
  "cl $flags /Fe:`"$output/network.exe`" /Fo:`"$output/`" .github/tests/native_network.cpp src/framework/http/session.cpp src/framework/http/websocket.cpp /link /LIBPATH:`"$VcpkgTriplet/lib`" libcurl.lib zlib.lib libssl.lib libcrypto.lib ws2_32.lib crypt32.lib bcrypt.lib user32.lib advapi32.lib secur32.lib iphlpapi.lib",
  "node .github/tests/native_network_fixture.cjs `"$output/network.exe`" `"$output`"",
  "cl $flags /utf-8 /Fe:`"$output/splash/splash.exe`" /Fo:`"$output/`" .github/tests/native_splash.cpp src/framework/platform/nativesplash.cpp src/framework/graphics/apngloader.cpp /link gdiplus.lib user32.lib gdi32.lib `"$VcpkgTriplet/lib/zlib.lib`"",
  "`"$output/splash/splash.exe`" `"$repoPath/data/cursors`""
)
Push-Location $repoPath
try {
  foreach ($command in $commands) {
    # Each compiler invocation needs its own initialized MSVC environment.
    if ($command.StartsWith('call ')) { continue }
    & cmd.exe /d /s /c "call `"$VcVars`" >nul && $command"
    if ($LASTEXITCODE -ne 0) { throw "Windows regression command failed: $command" }
  }
} finally { Pop-Location }
