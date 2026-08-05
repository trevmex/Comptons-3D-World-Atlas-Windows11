# Local archive data

`Atlas-Online-Archive.html` and `Atlas-Online-Entry.html` are templates copied into the installed user workspace. `scripts/Sync-AtlasLocalArchive.js` generates the complete machine-local `Mirror/` tree from Internet Archive CDX records; it is staged and replaced only after every selected file and required top-level page succeeds.

The generated mirror is intentionally ignored by Git. Historical pages and assets may have redistribution restrictions, so this repository publishes the reproducible downloader and provenance manifests format, not the captured snapshots themselves. The installed mirror contains a SHA-256 manifest and `download-failures.json`; `Validate-AtlasLocalArchive.ps1` rejects incomplete or network-clickable copies.
