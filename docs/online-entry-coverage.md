# Entry-specific Online coverage

The Online menu is not limited to its four top-level commands. Every selected Atlas object can issue a context-sensitive request such as:

```text
https://archive-mode.invalid/atlas.cgi?p=3dwa&id=2000&m=w95&l=en&pn=New_York&t=1&la=478150656&lo=-889192448&z=7.631&h=London
```

The `Wlbrw32.dll` replacement recognizes these `atlas.cgi` requests and writes a local page under:

```text
%LOCALAPPDATA%\Comptons 3D World Atlas Deluxe\Online Archive\Mirror\3datlas\entry-links-*.html
```

The generated page includes the captured product/object/name/coordinate request and links only to preserved local country, geography, Atlas, and site-map material. It never forwards the request to `archive-mode.invalid`, `3datlas.com`, `comptons.com`, or Wayback replay.

## Static archive coverage

The synchronizer queries both `www.3datlas.com`/`3datlas.com` and `www.comptons.com`/`comptons.com`, selects one representative 1997-1999 Internet Archive capture for every unique URL in the CDX result, and records the selected source URL, timestamp, MIME type, byte count, local path, and SHA-256 in `Mirror\manifests\mirror-manifest.json`. It also records raw CDX rows and any failed downloads. Same-site HTML/CSS references are rewritten to local paths; unresolved network/form targets are disabled and the mirror is checked for clickable network attributes before installation succeeds.

This is complete coverage of the static resources returned by the selected CDX scope, not a claim that the Internet Archive captured every historical URL or every revision. The original dynamic CGI service translated Atlas IDs into context-sensitive web content. Static captures do not contain a complete response for every Atlas object; the local generated page preserves the entry context and routes to the closest useful material without inventing unavailable historical CGI content.

The four top-level command tests remain in `Test-AtlasOnlineArchive.ps1`; command 263 verifies the generated-file path. The New York flow has been exercised from the Cities selector through Online → New York Links.
