# AstraClient

AstraClient is the public client identity for this project.

Created/maintained by Mateuzkl.


## Protocol Features

Read the feature guide before changing `g_game.enableFeature` or `g_game.disableFeature`:

- English: `docs/protocol-features-8.60.md`
- PT-BR: `docs/protocol-features-8.60.pt-BR.md`

## Build

### Windows

Install vcpkg:

```powershell
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat
.\vcpkg.exe integrate install
```

Open the Visual Studio solution in `vc17`, select the desired backend and platform, then build the `AstraClient` project.

### Linux

```bash
sudo apt update
sudo apt install git curl build-essential cmake gcc g++ pkg-config autoconf libtool libglew-dev -y
git clone https://github.com/microsoft/vcpkg.git ~/vcpkg
~/vcpkg/bootstrap-vcpkg.sh
~/vcpkg/vcpkg install
mkdir build
cd build
cmake -DCMAKE_TOOLCHAIN_FILE=~/vcpkg/scripts/buildsystems/vcpkg.cmake ..
cmake --build . --config Release
```

## Credits

See `CREDITS.md` for upstream and license-related credits.
