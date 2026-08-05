# Compton's 3D World Atlas Deluxe on Windows 11

A reversible, user-local compatibility layer for **Compton's 3D World Atlas Deluxe v3.2** (Windows 95). It converts the disc's obsolete Indeo movies to Microsoft Video 1, preserves their PCM audio, uses the built-in Superplay fullscreen path, and replaces the retired Online service with a complete practical static mirror of the 1997-1999 Internet Archive captures for the Atlas-era 3datlas.com and comptons.com sites.

## Downloadable Windows installer

Download `Comptons-3D-World-Atlas-Windows11-Setup.exe` from the [GitHub Releases page](https://github.com/trevmex/Comptons-3D-World-Atlas-Windows11/releases). The installer contains only this compatibility toolkit; it does not contain the commercial Atlas program or CD data. It refuses to continue unless the physical `3DATLAS` disc is mounted, then runs the complete media conversion and archive setup for the current Windows user. The work runs inside the installer progress UI with parallel archive downloads and media conversion; no separate PowerShell console is opened. The finished page includes a closed-by-default **Show installation details** window containing the captured compatibility log. Verify the adjacent `SHA256SUMS.txt` before running it.

## One-install promise and the physical-media boundary

This repository does **not** contain `ATLAS.EXE`, CD media, proprietary Atlas DLLs, converted movies, or generated archive snapshots. The installer succeeds **only** when your lawful original CD is mounted and identified as volume `3DATLAS`. The disc must remain mounted while the program runs because Atlas reads its maps, chunks, images, sounds, help, and statistics from the CD.

The installer does **not** run the 1998 setup program, install Indeo/Video for Windows, modify Program Files, write legacy browser registry associations, or install AOL/Internet Explorer/DDE components. It copies the small Atlas runtime directly from the physical disc into a user-local directory and creates a separate converted-media tree.

If you are running from a cloned repository instead of the release installer, one non-elevated PowerShell command is sufficient:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Install-AtlasWindows11.ps1
```

The installer and script automatically install the user-scoped LGPL FFmpeg tools and Node.js LTS with Windows Package Manager (`winget`) when they are absent. Internet access is required during installation to obtain those tools and the historical archive. No Visual Studio installation is required: the repository carries the independently authored x86 archive shim artifact and also retains its reproducible C build.

Launch the program from the installer-created Start Menu shortcuts or the desktop shortcut named `Compton's 3D World Atlas Deluxe - Windows 11 Archive Mode`. Do not use an older desktop shortcut or the original Program Files executable; that copy still uses the retired online connection and will show `Online Connection Needed`.

The defaults are `D:` for the CD, `%LOCALAPPDATA%\Comptons 3D World Atlas Deluxe` for generated data, and `%LOCALAPPDATA%\Programs\Comptons 3D World Atlas Deluxe` for the runtime. The release installer automatically checks other drive letters when `D:` does not contain the disc; use `/DISC=E:` when launching it to select a specific drive. The PowerShell script accepts `-DiscDrive E:`, but the chosen volume must still be labeled `3DATLAS`.

## What installation does

1. Verifies the physical media, label, and required Atlas runtime files.
2. Copies only the original runtime files to a user-local directory; the disc and any existing Program Files installation remain untouched.
3. Converts every disc AVI that uses Indeo to Microsoft Video 1 (`MSVC`) while checking dimensions, stream counts, audio codec, sample rate, and channels. Unchanged supported AVIs are copied; PCM audio is never resampled.
4. Writes a generated `Atlas-Config.json` so launchers and tests honor non-default paths.
5. Downloads the static archive, rewrites captured same-site links to local files, removes clickable network/form targets, adds an offline CSP, checks every manifest file, and atomically replaces only a complete mirror.
6. Builds or installs the x86 `Wlbrw32.dll` replacement and records its SHA-256 hash.
7. Creates windowed and built-in Superplay fullscreen Start-menu shortcuts.

If archive synchronization or media conversion fails, installation fails rather than claiming that an incomplete offline copy is ready. `-SkipArchiveMirror` exists only for repair/development work and marks the generated profile `NOT_SYNCED`.

## Video, audio, and fullscreen

- Indeo 3/4/5 files are transcoded to Microsoft Video 1, a codec Windows 11 can decode without an obsolete system codec.
- Original PCM audio streams are copied unchanged and verified after conversion. Atlas starts with volume 5, music enabled, and narration enabled.
- The fullscreen shortcut selects Atlas's native `SJE_FULLSCREEN`/Superplay path. It preserves the original 4:3 artwork instead of stretching it to 16:9.
- The original executable and disc content are never modified.

## Complete local Online archive

`Sync-AtlasLocalArchive.js` queries the Internet Archive CDX index for both `www` and apex hostnames, selects one representative 1997-1999 capture for every unique static URL, downloads the supported document/assets, records capture URLs, byte counts, SHA-256 hashes and failures, and rewrites links into the local mirror:

```text
%LOCALAPPDATA%\Comptons 3D World Atlas Deluxe\Online Archive\Mirror
```

The mirror includes the captured HTML, image, CSS/text/document and other static archive resources exposed by the CDX index. It is validated as a closed local tree; unresolved links become local unavailable markers rather than opening a live site. The native shim opens these local top-level commands:

- Downloadable Extras
- 3D World Atlas Home
- Compton's Home
- Archived site map
- Context-sensitive links for a selected city, country, topic, map pin, or other entry

The original dynamic `atlas.cgi` database response was not preserved for every object. For those requests the shim writes `3datlas\entry-links-*.html`, records the requested name/ID/coordinates, and links to the closest preserved country, Atlas, geography, and site-map material. That is an honest local context index, not invented live content.

Historical pages are treated as read-only documentation. Do not run old installers, submit archived forms, follow unavailable external links, or enter credentials into historical sign-in pages.

## Verification

After installation:

```powershell
.\scripts\Test-Installation.ps1
.\scripts\Validate-AtlasLocalArchive.ps1
.\scripts\Validate-AtlasMedia.ps1
.\scripts\Test-AtlasGameMoviesMci.ps1
.\scripts\Run-AtlasDisplayTests.ps1
.\scripts\Run-AtlasContentSmokeTests.ps1
.\scripts\Test-AtlasAudioSession.ps1
.\scripts\Validate-AtlasWindows11Setup.ps1
```

The last three groups are interactive/runtime checks. Static installation, archive, and media validation do not require Atlas to be running.

## Repository layout

- `installer/` — Inno Setup source and reproducible installer build script
- `scripts/` — one-step installer, tool bootstrap, launcher, media conversion, archive sync, and tests
- `src/` — source for the safe x86 `Wlbrw32.dll` replacement
- `build/Wlbrw32.dll` — reproducible-project build artifact used when a compiler is unavailable
- `archive/` — local archive portal templates; generated snapshots are not committed
- `docs/` — architecture, coverage, and troubleshooting documentation

## Redistribution and rights

The compatibility scripts and native shim source/artifact are released under the MIT license in `LICENSE`. FFmpeg is obtained separately through its LGPL package and is not bundled here. The commercial Atlas executable, disc content, generated converted media, and Internet Archive captures remain subject to their respective rights and are deliberately excluded from this public repository.
