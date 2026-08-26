<p align="center">
  <a href="https://postimg.cc/kDVTKHBd">
    <img src="https://i.postimg.cc/Df6Rkkhm/Chat-GPT-Image-17-de-ago-de-2026-09-25-48.png" alt="AstraClient" width="100%" />
  </a>
</p>

<div align="center">

# AstraClient

**Modern OTClient v8 fork for protocol 8.60 with a feature set and visual direction inspired by modern Global 15.x clients.**

[![Windows / Linux CI](https://github.com/Mateuzkl/AstraClient/actions/workflows/build-vcpkg.yml/badge.svg?branch=main)](https://github.com/Mateuzkl/AstraClient/actions/workflows/build-vcpkg.yml)
[![Repository size](https://img.shields.io/github/repo-size/Mateuzkl/AstraClient?style=flat-square)](https://github.com/Mateuzkl/AstraClient)
[![Issues](https://img.shields.io/github/issues/Mateuzkl/AstraClient?style=flat-square)](https://github.com/Mateuzkl/AstraClient/issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/Mateuzkl/AstraClient?style=flat-square)](https://github.com/Mateuzkl/AstraClient/pulls)
[![Commits](https://img.shields.io/github/commit-activity/m/Mateuzkl/AstraClient?style=flat-square)](https://github.com/Mateuzkl/AstraClient/commits/main)

<br />

![Client](https://img.shields.io/badge/CLIENT-AstraClient-7c3aed?style=for-the-badge)
![Base](https://img.shields.io/badge/BASE-OTClient%20v8-2563eb?style=for-the-badge)
![Protocol](https://img.shields.io/badge/PROTOCOL-8.60-f97316?style=for-the-badge)
![Style](https://img.shields.io/badge/FEATURES-15.x%20Inspired-8b5cf6?style=for-the-badge)
![C++](https://img.shields.io/badge/C++-Modern-00599C?style=for-the-badge&logo=cplusplus&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-Modules-2C2D72?style=for-the-badge&logo=lua&logoColor=white)

<br />
<br />

Created and maintained by [Mateuzkl](https://github.com/Mateuzkl).

[Repository](https://github.com/Mateuzkl/AstraClient) ·
[Issues](https://github.com/Mateuzkl/AstraClient/issues) ·
[Pull Requests](https://github.com/Mateuzkl/AstraClient/pulls)

</div>

---

## Quick Download — Windows

Want to test AstraClient without compiling it locally?

**[Download latest Windows CI build](https://github.com/Mateuzkl/AstraClient/actions/workflows/build-vcpkg.yml?query=branch%3Amain)**

The GitHub Actions workflow builds the Windows client automatically and uploads the compiled package as an artifact.

### Where the executable is generated

During CI, the Windows build creates:

```text
build/AstraClient.exe
```

The workflow then uploads:

```text
astraclient-windows-<commit-sha>
├── AstraClient.exe
└── *.dll
```

### How to download

1. Open **Download latest Windows CI build** above.
2. Open the newest successful `main` workflow run.
3. Scroll to **Artifacts**.
4. Download `astraclient-windows-<commit-sha>`.
5. Extract the archive.
6. Run `AstraClient.exe`.

> [!NOTE]
> GitHub Actions artifacts are development builds generated from repository commits.
> For stable public one-click downloads, use GitHub **Releases** when official versions are published.

---

## About AstraClient

**AstraClient** is the public client identity for this project.

It is based on **OTClient v8 / OTAcademy** and is focused on keeping the classic **protocol 8.60** while supporting a more modern client experience inspired by later Global clients.

The project is designed for developers and server owners who want:

- Protocol **8.60** compatibility.
- Modern OTClient v8 architecture.
- Lua-based modules and interface systems.
- A modern visual direction inspired by **15.x Global** clients.
- Support for extended protocol features when both client and server are configured correctly.
- A base that can be customized without changing the server protocol away from 8.60.

> [!IMPORTANT]
> AstraClient uses **protocol 8.60**.
>
> References to **15.x**, **Global**, or modern client systems describe the feature set, interface direction and compatibility work.
> They do **not** mean that AstraClient changes its network protocol to 15.x.

---

## Highlights

| Area | Description |
|---|---|
| Base | OTClient v8 / OTAcademy fork |
| Protocol | Native project target: **8.60** |
| Features | Extended protocol and modern Global-inspired client features |
| UI | Modernized OTClient interface and modules |
| Assets | Tibia 8.60 DAT/SPR package supported through `data/things/860/` |
| Configuration | Protocol features controlled through `g_game.enableFeature` / `g_game.disableFeature` |
| Platforms | Windows and Linux build instructions included |

---

## Protocol Features

AstraClient uses feature flags to control protocol behavior.

Before changing any call to:

```lua
g_game.enableFeature(...)
g_game.disableFeature(...)
```

read the protocol feature documentation first.

### Documentation

- English: [`docs/protocol-features-8.60.md`](docs/protocol-features-8.60.md)
- PT-BR: [`docs/protocol-features-8.60.pt-BR.md`](docs/protocol-features-8.60.pt-BR.md)

> [!WARNING]
> Client and server packet structures must match.
>
> Enabling a feature only on the client, disabling a required feature, or using a different field size/order than the server can cause packet parsing errors, unread bytes, invalid opcodes or protocol desynchronization.

### Protocol philosophy

AstraClient keeps **8.60 as the protocol foundation** while allowing newer systems to be ported or recreated when the client and server implement the same packet structure.

```text
Protocol 8.60
     |
     +-- OTClient v8 / OTAcademy base
     |
     +-- Extended protocol features
     |
     +-- Modern UI / modules
     |
     +-- Global 15.x-inspired systems
```

Protocol compatibility always comes before visual or feature compatibility.

---

## Game Assets

Download the protocol 8.60 asset package:

**[Download 860.rar](https://github.com/Mateuzkl/AstraClient/raw/refs/heads/main/data/things/860.rar)**

Archive contents:

```text
860/Tibia.dat
860/Tibia.otfi
860/Tibia.spr
```

Extract the archive inside:

```text
data/things/
```

Final structure:

```text
data/
└── things/
    └── 860/
        ├── Tibia.dat
        ├── Tibia.otfi
        └── Tibia.spr
```

### SHA-256

```text
1857FA472F2BC28EF2E62A8B889C3D80380B7A7287B28EA4AAD10C6793537B19
```

Use the hash above to verify that the downloaded archive/assets match the expected package.

---

## Build

### Windows

Install [vcpkg](https://github.com/microsoft/vcpkg):

```powershell
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat
.\vcpkg.exe integrate install
```

Then:

1. Open the Visual Studio solution inside `vc17`.
2. Select the desired backend and platform.
3. Select the appropriate build configuration.
4. Build the `AstraClient` project.

---

### Android / APK

The Android project uses the original OTClientV8 Visual Studio/NDK toolchain. Create `C:\android` with:

- Android SDK 25.
- Android NDK r21d.
- Apache Ant 1.9.
- The contents of `android_libs.7z` (`C:\android\lib`, `C:\android\lib64` and `C:\android\include`).

Install **Mobile development with C++** through Visual Studio Installer, then generate the APK assets:

```powershell
powershell -ExecutionPolicy Bypass -File .\create_android_assets.ps1
```

Open `android/otclientv8.sln`, configure the SDK, NDK and Ant paths in Visual Studio, select **Release / ARM64**, and build the `otclientv8` project with the phone icon. The generated APK includes `android/otclientv8/assets/data.zip`.

For local device testing with ADB, use `run_android.bat` after placing the generated `otclientv8.apk` in the repository root.

---

### Linux

Install required packages:

```bash
sudo apt update
sudo apt install git curl build-essential cmake gcc g++ pkg-config autoconf libtool libglew-dev -y
```

Install vcpkg:

```bash
git clone https://github.com/microsoft/vcpkg.git ~/vcpkg
~/vcpkg/bootstrap-vcpkg.sh
~/vcpkg/vcpkg install
```

Configure and build AstraClient:

```bash
mkdir build
cd build
cmake -DCMAKE_TOOLCHAIN_FILE=~/vcpkg/scripts/buildsystems/vcpkg.cmake ..
cmake --build . --config Release
```

---

## Recommended Workflow

When adding or porting a protocol feature:

1. Identify the exact packet opcode.
2. Compare client and server serializers/parsers.
3. Verify field order.
4. Verify integer sizes such as `uint8`, `uint16`, `uint32` and `uint64`.
5. Verify strings, counts and optional fields.
6. Add or adjust the required feature flag only when necessary.
7. Test login and normal gameplay before testing the new system.
8. Test the feature with protocol logs enabled.
9. Confirm that the full packet is consumed without unread bytes.
10. Document the feature behavior in `docs/protocol-features-8.60.md`.

This avoids byte desynchronization and makes protocol changes easier to review.

---

## Project Direction

AstraClient aims to combine:

- Classic **8.60 protocol compatibility**.
- Modern OTClient v8 development.
- Modernized interface and module design.
- Newer Global-inspired systems where compatible.
- Clear separation between protocol, feature flags, UI and game assets.

The project does not need to become a native 15.x client to reproduce modern systems.

Instead, compatible systems can be adapted to the 8.60-based client/server stack by implementing the required packet logic on both sides.

---

## Contributing

Bug reports and pull requests are welcome.

When opening an issue, include:

- Clear problem description.
- Steps to reproduce.
- Expected behavior.
- Actual behavior.
- Client log.
- Full protocol parser error when applicable.
- Opcode involved, if known.
- Server revision/commit used during the test.
- Screenshots or video when useful.

When submitting a pull request:

- Keep the change focused.
- Avoid unrelated formatting changes.
- Preserve protocol compatibility.
- Document new feature flags.
- Explain packet structure changes.
- Test both feature-enabled and feature-disabled behavior when applicable.

---

## Credits

See [`CREDITS.md`](CREDITS.md) for upstream projects, authors and license-related credits.

AstraClient is built on work from the **OTClient / OTClient v8 / OTAcademy ecosystem** and community contributors.

---

<div align="center">

## AstraClient

**Protocol 8.60 · OTClient v8 Base · Modern Global-Inspired Features**

Made and maintained by [Mateuzkl](https://github.com/Mateuzkl)

</div>
