# Troubleshooting

## Downloadable installer

The GitHub release installer is a user-scoped Inno Setup package. It extracts the redistributable toolkit and invokes the same `scripts\Install-AtlasWindows11.ps1` used by a repository checkout. The installer itself never contains Atlas media. The compatibility phase runs behind the installer progress page; after completion, click **Show installation details** on the finished page to open the captured log. The details window is closed by default. To rebuild it on a maintainer machine, install Inno Setup 6 and run:

```powershell
.\installer\Build-AtlasInstaller.ps1
```

The output is `dist\Comptons-3D-World-Atlas-Windows11-Setup.exe` plus `SHA256SUMS.txt`. A release install requires the CD at the configured drive; the installer checks other drive letters automatically when `/DISC` is omitted, and `/DISC=E:` is available for a specific labeled optical drive. Archive downloads use a bounded parallel pool with a low-concurrency retry pass, and AVI conversion uses four local worker processes. Each run stages the runtime, media, and archive before publishing them, so a failed retry preserves the previous working installation. If the compatibility phase fails, inspect `Install-AtlasWindows11.log` in `%LOCALAPPDATA%\Comptons 3D World Atlas Deluxe Toolkit`, correct the reported issue, and rerun the installer.

## Online Connection Needed or dead browser links

Those symptoms mean the original Program Files copy or an old desktop shortcut was launched. Use the installer-created `Compton's 3D World Atlas Deluxe - Windows 11 Archive Mode` desktop shortcut, or either Windows 11 shortcut in the Start Menu. The local archive shim is only installed in the user-local runtime; the original Program Files installation is deliberately left untouched. The Windows 11 launcher also keeps legacy modal dialogs above the Atlas window without interfering with normal menu popups.

## Installer says the disc is missing

The toolkit intentionally refuses to install without the physical media:

```powershell
Get-Volume -DriveLetter D
Test-Path D:\ATLAS.EXE
```

The label must be `3DATLAS`. If another device occupies the configured drive, assign the optical drive that letter and rerun with `-DiscDrive X:`. Keep the disc mounted while Atlas runs.

## Tool bootstrap fails

Windows 11's `winget` is used only for user-scoped Node.js LTS and the LGPL FFmpeg tools. Run `winget search Node.js` and `winget search FFmpeg` to confirm the package source, or install compatible `node.exe`, `ffmpeg.exe`, and `ffprobe.exe` on `PATH` before rerunning. The installer never installs an obsolete system codec.

## Splash screen stays open

The launcher sends synthetic cursor/mouse input to the old splash-screen window. If it remains, move the pointer onto the primary monitor once, close Atlas, and retry. Do not install Indeo.

## Videos are black or crash

Run `Validate-AtlasMedia.ps1` and `Test-AtlasGameMoviesMci.ps1`. Inspect `Converted Media\AVI\conversion-manifest.tsv`; every effective AVI must use Microsoft Video 1 or another Windows 11-supported codec, and the generated `Atlas.log` AVI root must point to `Converted Media\AVI`, not the CD's `AVI` directory.

## Online links do not open

Run:

```powershell
.\scripts\Validate-AtlasLocalArchive.ps1
```

These files must exist under the installed mirror:

- `3datlas\index.html`
- `3datlas\download\f_main_dl.html`
- `3datlas\sitemap.html`
- `3datlas\entry-links.html`
- `comptons\index.html`
- `manifests\mirror-manifest.json`

If synchronization was interrupted, rerun the installer. An incomplete staging tree is never published over a previously complete mirror.

## GitHub hygiene

Never commit the commercial executable, CD images, converted media, generated mirror, test screenshots, crash dumps, or personal paths. The public repository contains source, the independently authored shim artifact, reproducible scripts, and documentation only.
