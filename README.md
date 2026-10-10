# Fingertip-dit

An unofficial community fork of [Fingertip](https://github.com/imperviousinc/fingertip) by
Impervious, the Windows Handshake (HNS) resolver, with a working, up-to-date `hnsd`.

> Not affiliated with or endorsed by Impervious Inc. Fingertip is © Impervious Inc.,
> licensed under Apache-2.0.

## Why

Fingertip 0.0.3 (2021) ships a 2021 build of `hnsd` whose hardcoded seed peers have all
gone offline, so it never syncs and Handshake names stop resolving. It also syncs the
whole chain from block 0 on every start and bundles OpenSSL 1.1.1k (end of life).

Fingertip-dit keeps the original `fingertip.exe` unchanged and replaces what's around it:

| File | Fingertip 0.0.3 | Fingertip-dit 0.0.4 |
|---|---|---|
| `hnsd-core.exe` | hnsd from 2021 (dead seeds) | [handshake-org/hnsd](https://github.com/handshake-org/hnsd) `0cb70e5` (Aug 2026, current seeds) |
| `hnsd.exe` | hnsd | small launcher ([`wrapper/hnsd-wrapper.c`](wrapper/hnsd-wrapper.c)) that adds `--checkpoint --prefix` |
| OpenSSL | 1.1.1k | 3.x |
| Startup | syncs from block 0 each launch | syncs from checkpoint once (~2 min), then saves headers so later starts take seconds |

The launcher exists because `fingertip.exe` starts `hnsd.exe` with fixed arguments. It
runs `hnsd-core.exe` with checkpoint sync and a header store in `Fingertip\hnsd-data`,
and puts it in a Windows job object so it stops when Fingertip stops it.

## Install

Download `Fingertip-dit-0.0.4.msi` from [Releases](https://github.com/galetaire/Fingertip-dit/releases)
and run it. Before you do:

- **Quit Fingertip first** (tray icon → Quit) if it's running.
- It's a per-user install into `%LOCALAPPDATA%\Fingertip` and needs no admin rights.
  It upgrades an existing Fingertip 0.0.3 in place.
- The files aren't code-signed, so SmartScreen may warn: **More info → Run anyway**.
  Check the download against the `.sha256` file in the release.
- Silent install: `msiexec /i Fingertip-dit-0.0.4.msi /qn`

On first start, lookups fail for about 2 minutes while `hnsd` syncs from its checkpoint.
After that, names resolve.

## Build from source

Requires [MSYS2](https://www.msys2.org). In an **MSYS2 MINGW64** shell:

```sh
pacman -S --needed base-devel autotools git mingw-w64-x86_64-toolchain \
  mingw-w64-x86_64-unbound mingw-w64-x86_64-crt-git mingw-w64-x86_64-msitools
git clone --recursive https://github.com/galetaire/Fingertip-dit.git
cd Fingertip-dit
./build.sh
```

`build.sh` builds `hnsd` from the pinned submodule, compiles the launcher, downloads the
official Fingertip v0.0.3 MSI and extracts `fingertip.exe` from it (both checked by
SHA-256), copies the Unbound/OpenSSL DLLs from MSYS2, and builds
`dist/Fingertip-dit-0.0.4.msi` with `wixl`.

`third_party/fingertip` is pinned to the v0.0.3 source for reference. The binary
isn't rebuilt from it, so the shipped `fingertip.exe` is byte-identical to the
official release.

## License

Apache-2.0 (see [LICENSE](LICENSE)), the same as Fingertip. Bundled components keep
their own licenses: hnsd (MIT), Unbound (BSD-3-Clause), OpenSSL (Apache-2.0). See
[THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt) and [licenses/](licenses/).
