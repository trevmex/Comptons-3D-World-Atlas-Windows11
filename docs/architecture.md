# Architecture

## Runtime isolation

The original Atlas installation is treated as read-only. The installer copies its executable/dependencies to `%LOCALAPPDATA%\Programs\Comptons 3D World Atlas Deluxe`, writes a per-user `Atlas.log`, and redirects video/game roots to `%LOCALAPPDATA%\Comptons 3D World Atlas Deluxe\Converted Media`.

The physical CD remains mounted because Atlas still reads its maps, images, chunks, help, and other non-video assets from the disc.

## Media compatibility

The disc's Indeo 3 AVI files are decoded and re-encoded to Microsoft Video 1 with FFmpeg. Audio is mapped and copied rather than resampled. The conversion manifest records source/replacement paths, codecs, and audio-stream counts. Runtime validation rejects effective Indeo files.

## Online replacement

`src/Atlas-WonderLink-Archive.c` implements the four exports expected by the 1998 Atlas executable. Top-level pages open local mirror files. Entry-specific `atlas.cgi` requests are parsed only far enough to identify a context, then rendered into a newly generated local `entry-links-*.html` file containing the original request and links into preserved local material. The live CGI URL in `Atlas.log` is an inert `.invalid` fallback; no request is forwarded to it.

`Sync-AtlasLocalArchive.js` selects captures near the April/May 1998 snapshots, downloads raw (`id_`) Wayback responses, and rewrites same-site HTML links to local relative paths. It is intentionally not a web crawler for arbitrary modern content.

## Fullscreen video

Atlas owns the video scaling path. The compatibility layer invokes the built-in Superplay/SJE_FULLSCREEN mode rather than injecting a third-party overlay or changing display settings. This provides a native 3840×2160 test target on the current system while preserving the original 4:3 aspect ratio.
