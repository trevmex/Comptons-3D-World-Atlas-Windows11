'use strict';

/*
 * Download the small, static portions of the 1998 Atlas and Compton's sites
 * needed by the Atlas Online menu.  This intentionally uses the Internet
 * Archive's raw replay (id_) and rewrites same-site links to files under
 * Mirror, so the installed compatibility layer can work without a live
 * Compton's server or a browser plug-in.
 *
 * No CD content is included by this script.  The generated Mirror directory
 * is machine-local and should not be committed to a public repository unless
 * the operator has permission to redistribute the archived pages/assets.
 */

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const { URL } = require('url');

const root = __dirname;
const mirrorRoot = process.env.ATLAS_ARCHIVE_MIRROR_ROOT
  ? path.resolve(process.env.ATLAS_ARCHIVE_MIRROR_ROOT)
  : path.join(root, 'Mirror');
const manifestRoot = path.join(mirrorRoot, 'manifests');
const userAgent = 'Comptons-Atlas-Windows11-ArchiveMirror/1.0 (+https://github.com/)';
const concurrency = Math.max(1, Number(process.env.ATLAS_ARCHIVE_CONCURRENCY || 8));
const retryCount = 3;

const sites = [
  {
    host: 'www.3datlas.com',
    folder: '3datlas',
    anchor: '19980421214146',
    cdx: 'https://web.archive.org/cdx/search/cdx?url=www.3datlas.com/*&from=1997&to=1999&output=json&fl=timestamp,original,statuscode,mimetype,digest,length&filter=statuscode:200&filter=mimetype:(text/html|image/.*|text/css|application/javascript)&collapse=digest&limit=20000'
  },
  {
    host: 'www.comptons.com',
    folder: 'comptons',
    anchor: '19980521123132',
    cdx: 'https://web.archive.org/cdx/search/cdx?url=www.comptons.com/*&from=1997&to=1999&output=json&fl=timestamp,original,statuscode,mimetype,digest,length&filter=statuscode:200&filter=mimetype:(text/html|image/.*|text/css|application/javascript)&collapse=digest&limit=20000'
  }
];

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function fetchBytes(url) {
  let lastError;
  for (let attempt = 1; attempt <= retryCount; attempt++) {
    try {
      const response = await fetch(url, {
        redirect: 'follow',
        headers: { 'User-Agent': userAgent, 'Accept': '*/*' }
      });
      const bytes = Buffer.from(await response.arrayBuffer());
      if (!response.ok) {
        throw new Error(`HTTP ${response.status} (${bytes.length} bytes)`);
      }
      return { bytes, contentType: response.headers.get('content-type') || '' };
    } catch (error) {
      lastError = error;
      if (attempt < retryCount) await sleep(500 * attempt);
    }
  }
  throw lastError;
}

function parseTimestamp(value) {
  const number = Number(String(value).replace(/[^0-9]/g, '').slice(0, 14));
  return Number.isFinite(number) ? number : Number.MAX_SAFE_INTEGER;
}

function canonicalOriginal(original) {
  const url = new URL(original);
  const host = url.hostname.toLowerCase();
  let pathname = decodeURIComponent(url.pathname || '/');
  if (!pathname.startsWith('/')) pathname = `/${pathname}`;
  if (pathname.endsWith('/')) pathname += 'index.html';
  // CDX can expose URL-escaped separators. Do not allow them to escape Mirror.
  pathname = path.posix.normalize(pathname).replace(/^\.\.(\/|$)+/, '');
  if (!pathname.startsWith('/')) pathname = `/${pathname}`;
  let relative = pathname.slice(1);
  if (!relative) relative = 'index.html';
  // Dynamic CGI paths without an extension can collide with captured child
  // paths on disk (for example cgi-bin/login and cgi-bin/login/...). Keep the
  // historical response as a deterministic HTML file instead.
  const lastSegment = relative.split('/').pop();
  if (!url.search && lastSegment && !path.posix.extname(lastSegment)) {
    relative = `${relative}__endpoint.html`;
  }
  if (url.search) {
    const query = Buffer.from(url.search.slice(1)).toString('hex');
    relative += `__query_${query}.html`;
  }
  return {
    host,
    key: `${host}${pathname.toLowerCase()}${url.search}`,
    relative,
    originalUrl: url
  };
}

function localRelativePath(site, relative) {
  return path.join(site.folder, ...relative.split('/'));
}

function entryFor(site, row) {
  const original = canonicalOriginal(row.original);
  if (original.host !== site.host) return null;
  return {
    site,
    timestamp: String(row.timestamp),
    original: row.original,
    status: row.statuscode,
    mime: row.mimetype,
    digest: row.digest,
    length: Number(row.length || 0),
    key: original.key,
    relative: original.relative,
    local: localRelativePath(site, original.relative),
    sourceUrl: `https://web.archive.org/web/${row.timestamp}id_/${row.original}`
  };
}

function selectEntries(site, rows) {
  const candidates = new Map();
  for (const row of rows) {
    const entry = entryFor(site, row);
    if (!entry) continue;
    if (!candidates.has(entry.key)) candidates.set(entry.key, []);
    candidates.get(entry.key).push(entry);
  }

  const anchor = parseTimestamp(site.anchor);
  const selected = [];
  for (const list of candidates.values()) {
    list.sort((a, b) => {
      const distance = Math.abs(parseTimestamp(a.timestamp) - anchor) - Math.abs(parseTimestamp(b.timestamp) - anchor);
      return distance || parseTimestamp(a.timestamp) - parseTimestamp(b.timestamp);
    });
    selected.push(list[0]);
  }
  selected.sort((a, b) => a.local.localeCompare(b.local));
  return { selected, candidates };
}

function isHtml(entry, contentType) {
  return /\.html?$/i.test(entry.relative) || /text\/html/i.test(entry.mime) || /text\/html/i.test(contentType);
}

function splitReference(value) {
  const match = String(value).match(/^([^#]*)(#.*)?$/s);
  return { address: match ? match[1] : String(value), fragment: match && match[2] ? match[2] : '' };
}

function findMappedEntry(entriesByKey, siteByHost, baseOriginal, value) {
  const split = splitReference(value);
  if (!split.address || /^(?:data|javascript|mailto|tel):/i.test(split.address)) return null;

  let resolved;
  try {
    resolved = new URL(split.address, baseOriginal);
  } catch (_) {
    return null;
  }
  const host = resolved.hostname.toLowerCase();
  const site = siteByHost.get(host);
  if (!site) return null;

  const normalized = canonicalOriginal(resolved);
  const entry = entriesByKey.get(normalized.key);
  if (!entry) return null;
  return { entry, fragment: split.fragment, resolved };
}

function replacementFor(currentEntry, mapped) {
  const from = path.posix.dirname(currentEntry.relative);
  let result = path.posix.relative(from, mapped.entry.relative).replace(/\\/g, '/');
  if (!result) result = path.posix.basename(mapped.entry.relative);
  if (!result.startsWith('.')) result = `./${result}`;
  return result + mapped.fragment;
}

function rewriteHtml(text, entry, entriesByKey, siteByHost) {
  let output = text;
  const base = new URL(entry.original);
  const attributePattern = /\b(?:href|src|action|poster|background)\s*=\s*(["'])(.*?)\1/gi;
  output = output.replace(attributePattern, (whole, quote, value) => {
    const mapped = findMappedEntry(entriesByKey, siteByHost, base, value.trim());
    if (!mapped) return whole;
    return whole.slice(0, whole.indexOf(quote) + 1) + replacementFor(entry, mapped) + quote;
  });

  // The old pages occasionally put URLs in CSS-style url(...), even though
  // most assets are ordinary IMG/FRAME attributes.
  output = output.replace(/url\(\s*(["']?)([^)"']+)\1\s*\)/gi, (whole, quote, value) => {
    const mapped = findMappedEntry(entriesByKey, siteByHost, base, value.trim());
    if (!mapped) return whole;
    return `url(${quote}${replacementFor(entry, mapped)}${quote})`;
  });
  return output;
}

async function readCdx(site) {
  const response = await fetchBytes(site.cdx);
  const rows = JSON.parse(response.bytes.toString('utf8'));
  if (!Array.isArray(rows) || rows.length < 2) throw new Error(`Empty CDX response for ${site.host}`);
  const headers = rows[0];
  return rows.slice(1).map(values => Object.fromEntries(headers.map((key, index) => [key, values[index]])));
}

async function writeJson(file, value) {
  await fsp.mkdir(path.dirname(file), { recursive: true });
  await fsp.writeFile(file, JSON.stringify(value, null, 2) + '\n', 'utf8');
}

async function main() {
  await fsp.mkdir(mirrorRoot, { recursive: true });
  await fsp.mkdir(manifestRoot, { recursive: true });

  const all = [];
  const selectedBySite = new Map();
  for (const site of sites) {
    process.stdout.write(`Reading CDX for ${site.host}...\n`);
    const rows = await readCdx(site);
    await writeJson(path.join(manifestRoot, `${site.folder}-cdx.json`), rows);
    const { selected } = selectEntries(site, rows);
    selectedBySite.set(site.host, selected);
    all.push(...selected);
    process.stdout.write(`  ${selected.length} unique archived files selected\n`);
  }

  const entriesByKey = new Map(all.map(entry => [entry.key, entry]));
  const siteByHost = new Map(sites.map(site => [site.host, site]));
  const manifest = {
    generatedAt: new Date().toISOString(),
    source: 'Internet Archive Wayback Machine raw replay (id_)',
    files: all.map(entry => ({
      site: entry.site.folder,
      timestamp: entry.timestamp,
      original: entry.original,
      mime: entry.mime,
      bytes: entry.length,
      local: entry.local
    }))
  };
  await writeJson(path.join(manifestRoot, 'mirror-manifest.json'), manifest);

  let completed = 0;
  let failed = 0;
  let cursor = 0;
  const failures = [];
  async function worker() {
    while (true) {
      const index = cursor++;
      if (index >= all.length) return;
      const entry = all[index];
      const destination = path.join(mirrorRoot, entry.local);
      try {
        const response = await fetchBytes(entry.sourceUrl);
        await fsp.mkdir(path.dirname(destination), { recursive: true });
        const bytes = isHtml(entry, response.contentType)
          ? Buffer.from(rewriteHtml(response.bytes.toString('utf8'), entry, entriesByKey, siteByHost), 'utf8')
          : response.bytes;
        await fsp.writeFile(destination, bytes);
        completed++;
        if (completed % 50 === 0 || completed === all.length) {
          process.stdout.write(`Downloaded ${completed}/${all.length}\n`);
        }
      } catch (error) {
        failed++;
        failures.push({ local: entry.local, source: entry.sourceUrl, error: String(error && error.message || error) });
        process.stderr.write(`FAILED ${entry.local}: ${error.message || error}\n`);
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, worker));

  // Provide the local context page used for every entry-specific atlas.cgi
  // request. The native shim generates a per-request local page; this
  // template is also available for browsing before any entry is opened.
  const entryTemplateCandidates = [
    path.join(root, 'Atlas-Online-Entry.html'),
    path.join(root, '..', 'archive', 'Atlas-Online-Entry.html')
  ];
  const entryTemplate = entryTemplateCandidates.find(file => fs.existsSync(file));
  if (entryTemplate) {
    await fsp.copyFile(entryTemplate, path.join(mirrorRoot, '3datlas', 'entry-links.html'));
  }

  // Provide deterministic aliases for the four top-level URLs the native
  // shim opens. The files themselves remain preserved site pages.
  const aliases = [
    ['3datlas/index.html', '3datlas/index.html'],
    ['3datlas/download/f_main_dl.html', '3datlas/download/f_main_dl.html'],
    ['3datlas/sitemap.html', '3datlas/sitemap.html'],
    ['comptons/index.html', 'comptons/index.html']
  ];
  for (const [alias, target] of aliases) {
    const source = path.join(mirrorRoot, target);
    const destination = path.join(mirrorRoot, alias);
    if (source !== destination && fs.existsSync(source)) await fsp.copyFile(source, destination);
  }

  await writeJson(path.join(manifestRoot, 'download-failures.json'), failures);
  const summary = {
    sites: sites.map(site => ({ host: site.host, selected: selectedBySite.get(site.host).length })),
    downloaded: completed,
    failed,
    mirrorRoot,
    failures: path.join(manifestRoot, 'download-failures.json')
  };
  process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
  if (failed) process.exitCode = 1;
}

main().catch(error => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
