# Troubleshooting

## CD not found

Atlas requires the original disc. Confirm:

```powershell
Get-Volume -DriveLetter D
Test-Path D:\ATLAS.EXE
```

The label should be `3DATLAS`. If another device occupies D:, assign the optical drive D: before launching; the 1998 executable's drive check is not reliably relocatable.

## Splash screen stays open

The launcher sends synthetic cursor/mouse input to the old splash-screen window. If it remains, move the pointer onto the primary monitor once, close Atlas, and retry. Do not install compatibility codecs.

## Videos are black or crash

Run `Test-AtlasGameMoviesMci.ps1` and inspect `Converted Media\AVI\conversion-manifest.tsv`. The effective `Atlas.log` AVI root must point to the converted directory, not `D:\AVI`.

## Online links do not open

Check that these files exist under the local mirror:

- `3datlas\index.html`
- `3datlas\download\f_main_dl.html`
- `3datlas\sitemap.html`
- `3datlas\entry-links.html`
- `comptons\index.html`

Entry-specific requests generate `3datlas\entry-links-*.html` beside the template. Re-run the archive sync with Node.js and keep the generated `Mirror` directory beside the installed archive shim.

## GitHub hygiene

Never commit the commercial executable, CD images, converted media, generated mirror, test screenshots, crash dumps, or personal paths. The repository is designed to distribute source and reproducible scripts only.
