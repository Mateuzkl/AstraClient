param([string]$MSBuild, [string]$Toolset)
$ErrorActionPreference = 'Stop'
if (-not $MSBuild) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $MSBuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
}
if (-not $MSBuild) { throw 'MSBuild with Visual C++ is required.' }
if (-not $Toolset) { $Toolset = if ($MSBuild -match '[\\/]18[\\/]') { 'v145' } else { 'v143' } }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $repo 'vc23\otclient.vcxproj'
$mockInstalled = Join-Path ([IO.Path]::GetTempPath()) 'astra-rmlui-project-test'
foreach ($configuration in @('OpenGL', 'DirectX')) {
    foreach ($platform in @('x64', 'Win32')) {
        foreach ($defaults in @($false, $true)) {
            $properties = @("/p:Configuration=$configuration", "/p:Platform=$platform", "/p:PlatformToolset=$Toolset",
                "/p:VcpkgRoot=$mockInstalled")
            if ($defaults) {
                $properties += @('/p:VcpkgInstalledDir=', "/p:_ZVcpkgInstalledDir=$mockInstalled")
            } else {
                $properties += "/p:VcpkgInstalledDir=$mockInstalled"
            }
            $output = & $MSBuild $project @properties /nologo /t:AstraResolveRmlUiDependencies `
                '-getProperty:AstraRmlUiEnabled,AstraRmlUiLuaLibrary,AstraRmlUiLuaIncludeDir' '-getItem:ClCompile'
            if ($LASTEXITCODE -ne 0) { throw "MSBuild evaluation failed: $configuration $platform ($defaults)" }
            $state = ($output -join "`n") | ConvertFrom-Json
            if ($state.Properties.AstraRmlUiEnabled -ne 'true') { throw 'RmlUi was disabled in a supported build.' }
            if ($state.Properties.AstraRmlUiLuaLibrary -match '[\\/]debug[\\/]' -or
                $state.Properties.AstraRmlUiLuaLibrary -notmatch '[\\/]lib[\\/]lua51\.lib$') {
                throw 'Release RmlUi selected the wrong LuaJIT runtime.'
            }
            $items = @($state.Items.ClCompile | Where-Object { $_.Identity -match '[\\/](rml|rmlimages)' })
            if ($items.Count -ne 6) { throw "Expected 6 RmlUi sources, found $($items.Count)." }
            foreach ($item in $items) {
                if ([IO.Path]::IsPathRooted($item.Identity) -or $item.ObjectFileName.Contains(':') -or
                    $item.ObjectFileName -notmatch '[\\/]rmlui_obj[\\/][^\\/]+\.obj$') {
                    throw "Invalid object output path: $($item.ObjectFileName)"
                }
                if ($item.PrecompiledHeader -ne 'NotUsing' -or $item.IncludeInUnityFile -ne 'false' -or
                    $item.PreprocessorDefinitions -notmatch 'FW_RMLUI') { throw 'Invalid RmlUi compiler settings.' }
                if (-not $item.AdditionalIncludeDirectories.Contains($state.Properties.AstraRmlUiLuaIncludeDir)) {
                    throw 'The RmlUi translation unit cannot find LuaJIT headers.'
                }
            }
        }
    }
}
'RmlUi MSBuild: PASS (GL/DX, x64/Win32, explicit/default vcpkg paths)'
