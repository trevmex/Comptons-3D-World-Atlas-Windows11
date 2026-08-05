# Compton's 3D World Atlas Deluxe on Windows 11

A reproducible, user-local compatibility toolkit for **Compton's 3D World Atlas Deluxe v3.2** (Windows 95). It replaces the obsolete Intel Indeo playback path, preserves the disc's PCM audio, provides scaled Superplay video, and replaces the retired Online service with a local mirror of static Internet Archive snapshots.

## Important: bring your own disc

This repository does **not** include `ATLAS.EXE`, CD media, converted videos, proprietary DLLs, or the generated archive mirror. Use it only with a lawfully owned copy of the original CD. The original installer should be run first; this toolkit leaves the original Program Files installation untouched and creates a user-local runtime.

The original live `3datlas.com` CGI service was discontinued. The Online menu cannot be restored as a live service. The replacement is read-only and offline: static 1998 pages and assets are downloaded from the Internet Archive and same-site links are rewritten to local files.

## Quick start

1. Insert the Atlas CD and mount it as **D:**. Confirm `D:\ATLAS.EXE` exists and the volume label is `3DATLAS`.
2. Run the disc's original setup into the normal `Compton's Home Library` directory.
3. Install prerequisites:
   - Windows PowerShell 5+
   - `ffmpeg.exe` and `ffprobe.exe` on `PATH`
   - Node.js 18+
   - Visual Studio Build Tools with the x86 C++ workload
4. From an elevated PowerShell only when the original installer requires it, run:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\scripts\Install-AtlasWindows11.ps1
   ```

5. Start **Compton's 3D World Atlas Deluxe - Windows 11 Fullscreen** from the generated Start-menu folder.

The disc must remain mounted while Atlas runs. The current implementation intentionally uses D: because the 1998 executable performs its own CD drive check.

## Video and audio

- All effective Indeo 3 AVI files are transcoded to Microsoft Video 1 (`MSVC`), which Windows 11 can decode without installing an obsolete system codec.
- Original PCM audio streams are copied unchanged; Atlas starts with volume 5, music enabled, and narration enabled.
- For scaled video, open a video and choose **Display → Superplay** (or press `Ctrl+Shift+.` / `Ctrl+>`). Atlas's native `SJE_FULLSCREEN` path scales the video to the primary display, preserving its aspect ratio rather than stretching 4:3 artwork to 16:9.
- The installer does not install Indeo, AOL, Internet Explorer, Netscape, DDE components, or browser plug-ins.

## Local Online archive

`Sync-AtlasLocalArchive.js` downloads the static 1997–1999 HTML/image/CSS captures for `3datlas.com` and `comptons.com`, then rewrites links between captured pages to local relative paths. The generated files are under:

```text
%LOCALAPPDATA%\Comptons 3D World Atlas Deluxe\Online Archive\Mirror
```

The four Atlas Online commands open local files:

- Downloadable Extras
- 3D World Atlas Home
- Compton's Home
- Context-sensitive Links → local archived site map

Do not run old installers or enter credentials into historical pages.

## Tests

After installation, useful checks are:

```powershell
.\scripts\Test-Installation.ps1
.\scripts\Test-AtlasGameMoviesMci.ps1
.\scripts\Test-AtlasOnlineArchive.ps1
.\scripts\Run-AtlasDisplayTests.ps1
.\scripts\Run-AtlasContentSmokeTests.ps1
```

`Test-AtlasAudioSession.ps1` samples the Windows Core Audio peak meter for a running Atlas process while a narrated/video item is playing. `Validate-AtlasMedia.ps1` performs exhaustive FFmpeg decode and codec checks.

## Repository layout

- `scripts/` — installer, launcher, media conversion, archive sync, and test automation
- `src/` — source for the safe `Wlbrw32.dll` replacement
- `archive/` — local archive portal template; generated snapshots are not committed
- `docs/` — design and troubleshooting notes

## Redistribution

The compatibility scripts and native shim source are released under the MIT license in `LICENSE`. The commercial Atlas executable, disc content, and Internet Archive captures remain subject to their respective rights and are deliberately excluded from this repository.
