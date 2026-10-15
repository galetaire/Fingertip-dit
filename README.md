# Fingertip-dit

An unofficial community fork of [Fingertip](https://github.com/imperviousinc/fingertip) by
Impervious, the Handshake (HNS) resolver, with a working, up-to-date `hnsd`. Builds for
**Windows** (`.msi`) and **Linux** (`.AppImage`).

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

Downloads are on the [Releases](https://github.com/galetaire/Fingertip-dit/releases) page.

### Windows

Run `Fingertip-dit-0.0.4.msi`. Before you do:

- **Quit Fingertip first** (tray icon → Quit) if it's running.
- It's a per-user install into `%LOCALAPPDATA%\Fingertip` and needs no admin rights.
  It upgrades an existing Fingertip 0.0.3 in place.
- The files aren't code-signed, so SmartScreen may warn: **More info → Run anyway**.
  Check the download against the `.sha256` file in the release.
- Silent install: `msiexec /i Fingertip-dit-0.0.4.msi /qn`

### Linux (x86_64)

```sh
chmod +x Fingertip-dit-0.0.4-x86_64.AppImage
./Fingertip-dit-0.0.4-x86_64.AppImage
```

- Needs glibc 2.35 or newer and GTK 3 from your distro (Ubuntu 22.04+, Debian 12+,
  Fedora 36+, Arch). Some distros need `libfuse2` to run AppImages; without it, run with
  `--appimage-extract-and-run`.
- On GNOME, the tray icon needs the *AppIndicator and KStatusNotifierItem Support*
  extension (Ubuntu ships it).
- `hnsd` saves its headers in `~/.local/share/Fingertip-dit/hnsd-data`.
- Fingertip doesn't configure Linux automatically (that's unchanged from 0.0.3). On
  first launch it opens its setup page, which walks you through setting your browser's
  proxy and trusting its certificate.

On first start, lookups fail for about 2 minutes while `hnsd` syncs from its checkpoint.
After that, names resolve.

## Uninstall

### Windows

On Windows, Fingertip's **Auto configure** changes three settings outside its own
folder: the Windows proxy, a root certificate it trusts, and Firefox. Remove those
first, while Fingertip is still installed, because it finds its certificate through
its data folder.

1. **Remove Fingertip's configuration.** Right-click the tray icon → **Options** →
   untick **Auto configure** → **Yes** at "Remove Fingertip configuration settings?".
   This clears the proxy setting, deletes the Firefox `user.js` it wrote, and removes
   its current certificate.
2. **Turn off start at login.** In the tray menu, untick **Open at login**.
3. **Quit** from the tray menu.
4. **Uninstall the app:** **Settings → Apps → Installed apps** (Windows 10: **Apps & features**) → **Fingertip-dit** →
   Uninstall**. This removes the program files, the Start-menu shortcut and the
   `HKCU\Software\Fingertip-dit` registry key.
5. **Delete the data and anything left over.** In PowerShell:

   ```powershell
   # settings, logs, and Fingertip's certificate authority (including its private key)
   Remove-Item -Recurse -Force "$env:APPDATA\Fingertip" -ErrorAction SilentlyContinue
   # hnsd's saved headers (the uninstaller leaves data the app created)
   Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Fingertip" -ErrorAction SilentlyContinue
   # start-at-login shortcut, if step 2 was skipped
   Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\com.impervious.fingertip.lnk" -ErrorAction SilentlyContinue
   # every certificate Fingertip ever added: it creates a new one each time its data
   # is reset, and step 1 only removes the current one
   Get-ChildItem Cert:\CurrentUser\Root | Where-Object Subject -eq 'CN=DNSSEC, O=DNSSEC' | Remove-Item
   ```

   Windows asks you to confirm each certificate removal. Click **Yes**.

**If you already uninstalled without step 1:**
- **Proxy:** in **Settings → Network & internet → Proxy**, turn off **Use setup script**
  if its address is `http://127.0.0.1:9590/proxy.pac`. Otherwise web pages won't load.
- **Certificates:** the last line of step 5 removes them.
- **Firefox:** in `%APPDATA%\Mozilla\Firefox\Profiles\<profile>\`, delete `user.js` if
  its first line is `// AUTOCONFIG:FINGERTIP`, then restart Firefox.

### Linux

An AppImage isn't installed system-wide, so uninstalling means quitting it, undoing the
browser settings you made, and deleting its files. Everything is in your home folder,
so no `sudo` is needed.

1. **Quit Fingertip** from its tray icon (**Quit**), or run `pkill -f fingertip`.
2. **Undo the browser settings.** Otherwise the browser keeps sending traffic to a proxy
   that no longer exists, and pages won't load.
   - Firefox: **Settings → General → Network Settings → Settings…**, choose **No proxy**
     or **Use system proxy settings**, and click OK.
   - Firefox: **Settings → Privacy & Security → Certificates → View Certificates… →
     Authorities**, select **DNSSEC** (Fingertip's certificate authority), and click
     **Delete or Distrust…**.
   - If you set the proxy or imported the certificate elsewhere (system network settings,
     Chrome, the system certificate store), undo it there too.
3. **Delete the files:**

   ```sh
   # settings, logs, and Fingertip's certificate authority (including its private key)
   rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/Fingertip"
   # hnsd's saved headers
   rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/Fingertip-dit"
   # start-at-login entry, if you enabled "Open at login" in the tray menu
   rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/com.impervious.fingertip.desktop"
   # the app itself: wherever you saved it
   rm -f ~/Downloads/Fingertip-dit-0.0.4-x86_64.AppImage
   ```

   Change the last line to wherever you put the AppImage. If you ran an extracted copy
   (`squashfs-root`), delete that folder too. If you, AppImageLauncher or `appimaged`
   added Fingertip to your app menu, remove its `.desktop` file from
   `~/.local/share/applications/`.

Fingertip writes nothing outside your home folder on Linux, so that's everything.

## Build from source

### Windows

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

### Linux

On Ubuntu 22.04 x86_64 (or in an `ubuntu:22.04` container):

```sh
sudo apt-get install -y build-essential autoconf automake libtool git curl file libunbound-dev patchelf
git clone --recursive https://github.com/galetaire/Fingertip-dit.git
cd Fingertip-dit
./packaging/linux/build-appimage.sh
```

This unpacks the official Fingertip v0.0.3 AppImage (checked by SHA-256), swaps the old
`hnsd` for `hnsd-core` plus the launcher ([`wrapper/hnsd-wrapper-linux.c`](wrapper/hnsd-wrapper-linux.c)),
bundles hnsd's libraries in `usr/lib/hnsd`, drops the official AppImage's 2018 GTK/GLib
copies (only the AppIndicator tray libraries stay; the app uses the system GTK), and repacks it as
`dist/Fingertip-dit-0.0.4-x86_64.AppImage`. The [Build Linux AppImage](.github/workflows/build.yml)
GitHub Actions workflow runs the same script, checks that hnsd syncs, and launches the app
on Ubuntu 24.04, Debian 12, Fedora and Arch.

`third_party/fingertip` is pinned to the v0.0.3 source for reference. The binary
isn't rebuilt from it, so the shipped `fingertip` binaries are byte-identical to the
official releases.

## License

Apache-2.0 (see [LICENSE](LICENSE)), the same as Fingertip. Bundled components keep
their own licenses: hnsd (MIT), Unbound (BSD-3-Clause), OpenSSL (Apache-2.0). See
[THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt) and [licenses/](licenses/).
