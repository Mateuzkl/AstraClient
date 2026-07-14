# Building AstraClient (Windows / Visual Studio)

The only supported build today is the Visual Studio solution under `vc17/`.
There is **no working CMake/Linux path**.

## What the repo does NOT ship (you must provide it)

The C++ dependencies (Boost, OpenSSL, protobuf + `protoc.exe`, PhysFS, LuaJIT,
GLEW, libzip, …) are **not** committed. They live under `vcpkg_installed/`,
which is **gitignored** and regenerated on each machine by **vcpkg**. If you
skip the vcpkg setup below, the build dies early with:

```
MSB8066: custom build for '..\src\client\proto\appearances.proto;...' exited with code 3
  O sistema não pode encontrar o caminho especificado.   (protoc.exe missing)
```

## Prerequisites

1. **Visual Studio 2022 or 2026** with the **"Desktop development with C++"**
   workload.
   - VS **2026** ships toolset **v145** (the default this repo builds with).
   - On VS **2022** you only have **v143** — pass `-Toolset v143` to
     `compile.ps1` (see below), otherwise the build fails to find v145.
2. **Git** on `PATH` (used to fetch vcpkg on the first build).

That's it — you do **not** need to install vcpkg by hand. `compile.ps1`
bootstraps it for you (clone + bootstrap + `integrate install`) on the first run,
because the project pulls every native lib (Boost, OpenSSL, protobuf + `protoc.exe`,
PhysFS, …) through vcpkg manifest mode + autolink.

## Build

From the repo root:

```powershell
.\compile.ps1 -Config DirectX            # release-style ANGLE/D3D build -> AstraClient.exe
.\compile.ps1 -Config Debug              # dev build           -> AstraClient_debug_x64.exe
.\compile.ps1 -Config OpenGL             # release-style GL    -> AstraClient_gl_x64.exe
.\compile.ps1 -Config DirectX -Toolset v143   # if you are on Visual Studio 2022
```

> **First build is slow.** The vcpkg bootstrap + manifest restore compiles
> Boost/OpenSSL/etc. from source for the static triplet — expect **30–60+ minutes
> and a few GB** the first time. Subsequent builds reuse the cached
> `vcpkg_installed/` tree and are fast.

### Managing vcpkg yourself (optional)

By default the script keeps its vcpkg clone at `%USERPROFILE%\vcpkg` (or
`$env:VCPKG_ROOT` if set). To use your own vcpkg and skip the auto-bootstrap:

```powershell
.\compile.ps1 -Config DirectX -VcpkgRoot C:\dev\vcpkg   # point at an existing clone
.\compile.ps1 -Config DirectX -NoVcpkg                  # skip the vcpkg step entirely
```

The manual equivalent of what the script does once:

```powershell
git clone https://github.com/microsoft/vcpkg C:\dev\vcpkg
C:\dev\vcpkg\bootstrap-vcpkg.bat
C:\dev\vcpkg\vcpkg.exe integrate install   # the project does NOT import vcpkg targets itself
```

The dependency set is pinned in [`vcpkg.json`](vcpkg.json); the triplet is
`x64-windows-static` (x64) / `x86-windows-static` (Win32).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `MSB8066 ... protoc ... exited with code 3` + "não pode encontrar o caminho" | `protoc.exe` missing under `vcpkg_installed/<triplet>/tools/protobuf/`. Finish the **vcpkg** setup above and rebuild so the manifest restore runs. |
| Linker can't find boost/openssl/etc. | vcpkg integration not active — run `vcpkg integrate install`. |
| `error MSB8020 ... v145 ... cannot be found` | You're on VS 2022. Build with `-Toolset v143`. |
| Build can't overwrite `AstraClient*.exe` (LNK1104) | The client is running. `compile.ps1` kills it automatically unless you pass `-NoKill`. |
