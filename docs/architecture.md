# Architecture

## Runtime isolation

The physical CD is the source of truth and is never modified. The installer copies only the small original Atlas runtime to `%LOCALAPPDATA%\Programs\Comptons 3D World Atlas Deluxe`, writes a per-user `Atlas-Config.json`, and redirects video/game roots to `%LOCALAPPDATA%\Comptons 3D World Atlas Deluxe\Converted Media`. Maps, chunks, images, help, sounds, statistics, and other non-video assets continue to come from the mounted `3DATLAS` disc.

The installer does not run the original 1998 setup. That setup can install obsolete system codecs and 16-bit components that are neither required nor safe on Windows 11.

## Media compatibility

The disc's AVI inventory is discovered from `AVI`, `GAME\MOVIES`, and `GAME\MINIFLAG.AVI`. Indeo files are decoded and re-encoded to Microsoft Video 1 with FFmpeg. Audio is mapped and copied rather than resampled. The conversion manifest records source/replacement paths, SHA-256 hashes, codecs, dimensions, duration, and audio properties. The output is rebuilt cleanly on installation, and runtime validation rejects effective Indeo files.

## Online replacement

`src/Atlas-WonderLink-Archive.c` implements the four exports expected by the 1998 executable. Top-level pages open local mirror files. Entry-specific `atlas.cgi` requests are parsed only far enough to identify a context, then rendered into a newly generated local `entry-links-*.html` file containing the original request and links into preserved local material. The live URL in `Atlas.log` is an inert `.invalid` fallback; no request is forwarded to it.

`Sync-AtlasLocalArchive.js` queries both apex and `www` aliases, selects one representative capture for each unique static URL in the 1997-1999 CDX result, downloads it into a staging tree, rewrites captured same-site references to local relative paths, blocks unresolved network/form targets, adds an offline CSP, records hashes/failures, and atomically publishes only a complete mirror. Dynamic CGI responses that the Archive did not preserve are represented by the native shim's local context pages.

## Fullscreen video

Atlas owns the video scaling path. The compatibility layer invokes the built-in Superplay/SJE_FULLSCREEN mode rather than injecting a third-party overlay or changing display settings. This provides native display scaling while preserving the original 4:3 artwork.

## Build and deployment

The public repository includes the independently authored x86 archive shim artifact so installation does not require Visual Studio. `scripts/Build-WonderLink-Archive.cmd` remains the reproducible source build used by CI and maintainers. The commercial Atlas executable, CD files, converted media, and generated archive mirror are never committed.
