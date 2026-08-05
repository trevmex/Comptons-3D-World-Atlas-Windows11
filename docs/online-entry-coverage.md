# Entry-specific Online coverage

The Online menu is not limited to its four top-level commands. Every selected Atlas object can issue a context-sensitive request such as:

```text
https://archive-mode.invalid/atlas.cgi?p=3dwa&id=2000&m=w95&l=en&pn=New_York&t=1&la=478150656&lo=-889192448&z=7.631&h=London
```

The `Wlbrw32.dll` replacement recognizes these `atlas.cgi` requests and writes a local page under:

```text
%LOCALAPPDATA%\Comptons 3D World Atlas Deluxe\Online Archive\Mirror\3datlas\entry-links-*.html
```

The generated page includes the captured product/object/name/coordinate request and links only to preserved local country, geography, Atlas, and site-map material. It never forwards the request to `archive-mode.invalid`, `3datlas.com`, or the Wayback replay service.

## Preservation boundary

The original dynamic CGI service translated Atlas IDs into context-sensitive web content. Static Internet Archive captures contain the surrounding 1998 site, but do not contain a complete response for every Atlas object; the few captured CGI responses are mostly “site under construction” responses. Therefore the local generated page preserves the entry context and routes to the closest useful local material without inventing or claiming unavailable historical CGI content.

The four top-level command tests remain in `Test-AtlasOnlineArchive.ps1`; command 263 now verifies the entry-specific generated-file path. The New York flow has been exercised from the Cities selector through Online → New York Links.
