'use strict';

/*
 * Build a complete, practical offline copy of the static 1997-1999 pages
 * captured for the Atlas-era 3datlas.com and comptons.com sites. The CDX
 * index is the source of truth; one representative capture is selected for
 * every unique URL and all downloaded files are checksummed in a manifest.
 *
 * This tool deliberately does not claim to recreate the old atlas.cgi
 * database. The native shim renders a local context page for those requests.
 * Generated snapshots are machine-local because the historical material may
 * have redistribution restrictions.
 */

const fs = require('fs');
const fsp = fs.promises;
const crypto = require('crypto');
const path = require('path');
const { URL } = require('url');

const root = __dirname;
const mirrorRoot = process.env.ATLAS_ARCHIVE_MIRROR_ROOT
  ? path.resolve(process.env.ATLAS_ARCHIVE_MIRROR_ROOT)
  : path.join(root, 'Mirror');
const stagingRoot = `${mirrorRoot}.staging-${process.pid}`;
const manifestRoot = path.join(stagingRoot, 'manifests');
const userAgent = 'Comptons-Atlas-Windows11-ArchiveMirror/2.0 (+https://github.com/trevmex/Comptons-3D-World-Atlas-Windows11)';
const concurrency = Math.max(1, Math.min(24, Number(process.env.ATLAS_ARCHIVE_CONCURRENCY || 12)));
const retryCount = 5;
const requestTimeoutMs = 60000;
const blankImage = 'data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';
const mimeFilter = 'mimetype:(text/html|image/.*|text/css|application/javascript|application/x-javascript|text/plain|text/xml|application/xml|application/json|application/pdf|application/octet-stream|application/zip|application/x-zip-compressed|font/.*)';

const sites = [
  {
    id: '3datlas',
    folder: '3datlas',
    aliases: ['www.3datlas.com', '3datlas.com'],
    anchor: '19980421214146'
  },
  {
    id: 'comptons',
    folder: 'comptons',
    aliases: ['www.comptons.com', 'comptons.com'],
    anchor: '19980521123132'
  }
];

for (const site of sites) {
  site.cdxUrls = site.aliases.map(host => {
    const params = new URLSearchParams({
      url: `${host}/*`,
      from: '1997',
      to: '1999',
      output: 'json',
      fl: 'timestamp,original,statuscode,mimetype,digest,length',
      filter: `statuscode:200`,
      collapse: 'digest',
      limit: '20000'
    });
    // A second filter is appended rather than folded into the status filter
    // because CDX treats each filter as an independent expression.
    return `https://web.archive.org/cdx/search/cdx?${params.toString()}&filter=${encodeURIComponent(mimeFilter)}`;
  });
}

const siteByHost = new Map();
for (const site of sites) for (const host of site.aliases) siteByHost.set(host, site);

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function parseRetryAfter(value) {
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(1000, seconds * 1000);
  const date = Date.parse(value || '');
  return Number.isFinite(date) ? Math.max(1000, date - Date.now()) : 0;
}

async function fetchBytes(url) {
  let lastError;
  for (let attempt = 1; attempt <= retryCount; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), requestTimeoutMs);
    try {
      const response = await fetch(url, {
        redirect: 'follow',
        signal: controller.signal,
        headers: { 'User-Agent': userAgent, 'Accept': '*/*' }
      });
      const bytes = Buffer.from(await response.arrayBuffer());
      if (!response.ok) {
        const error = new Error(`HTTP ${response.status} (${bytes.length} bytes)`);
        error.retryAfter = response.headers.get('retry-after');
        throw error;
      }
      return { bytes, contentType: response.headers.get('content-type') || '' };
    } catch (error) {
      lastError = error;
      if (attempt < retryCount) {
        const retryAfter = parseRetryAfter(error && error.retryAfter);
        await sleep(retryAfter || Math.min(30000, 750 * (2 ** (attempt - 1))));
      }
    } finally {
      clearTimeout(timer);
    }
  }
  throw lastError;
}

function parseTimestamp(value) {
  const digits = String(value).replace(/[^0-9]/g, '').slice(0, 14);
  const number = Number(digits);
  return Number.isFinite(number) ? number : Number.MAX_SAFE_INTEGER;
}

function hashText(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function decodePathname(value) {
  let pathname;
  try {
    pathname = decodeURIComponent(value || '/');
  } catch (_) {
    throw new Error(`Invalid URL pathname: ${value}`);
  }
  pathname = pathname.replace(/\\/g, '/');
  if (pathname.indexOf('\0') >= 0) throw new Error('NUL in URL pathname');
  const parts = pathname.split('/');
  if (parts.some(part => part === '..')) throw new Error(`Path traversal in URL pathname: ${value}`);
  const safe = parts.filter(part => part && part !== '.').map(part =>
    part.replace(/[<>:"|?*]/g, '_')
  );
  return '/' + safe.join('/');
}

function canonicalOriginal(site, original) {
  const url = new URL(original);
  const host = url.hostname.toLowerCase();
  if (!site.aliases.includes(host)) throw new Error(`Unexpected host ${host} for ${site.id}`);
  let pathname = decodePathname(url.pathname);
  if (pathname.endsWith('/')) pathname += 'index.html';
  if (pathname === '/') pathname = '/index.html';
  let relative = pathname.slice(1) || 'index.html';
  const hasQuery = url.href.indexOf('?') >= 0;
  const lastSegment = relative.split('/').pop();
  if (hasQuery) {
    relative += `__query_${hashText(url.search.slice(1)).slice(0, 32)}.html`;
  } else if (lastSegment && !path.posix.extname(lastSegment)) {
    relative += '__endpoint.html';
  }
  return {
    host,
    key: `${site.id}${pathname.toLowerCase()}${url.search}`,
    relative,
    originalUrl: url
  };
}

function localRelativePath(site, relative) {
  return path.posix.join(site.folder, ...relative.split('/'));
}

function entryFor(site, row) {
  if (!row || !row.original) return null;
  const original = canonicalOriginal(site, row.original);
  return {
    site,
    timestamp: String(row.timestamp),
    original: row.original,
    status: row.statuscode,
    mime: row.mimetype || '',
    digest: row.digest || '',
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
    try {
      const entry = entryFor(site, row);
      if (!entry) continue;
      if (!candidates.has(entry.key)) candidates.set(entry.key, []);
      candidates.get(entry.key).push(entry);
    } catch (error) {
      process.stderr.write(`Skipping invalid CDX row for ${site.id}: ${error.message}\n`);
    }
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
  return /\.(?:html?|shtml|map)$/i.test(entry.relative) || /text\/html/i.test(entry.mime) || /text\/html/i.test(contentType);
}

function isCss(entry, contentType) {
  return /\.css$/i.test(entry.relative) || /text\/css/i.test(entry.mime) || /text\/css/i.test(contentType);
}

function splitReference(value) {
  const match = String(value).match(/^([^#]*)(#.*)?$/s);
  return { address: match ? match[1] : String(value), fragment: match && match[2] ? match[2] : '' };
}

function isNetworkReference(value) {
  return /^(?:https?:|\/\/)/i.test(String(value).trim());
}

function findMappedEntry(entriesByKey, baseOriginal, value) {
  const split = splitReference(value);
  const address = split.address.trim();
  if (!address) return { value: split.fragment || address, local: true };
  if (/^data:/i.test(address)) return { value: address + split.fragment, local: true };
  if (/^javascript:/i.test(address)) return { value: '#archive-script', local: false };
  if (/^(?:mailto|tel):/i.test(address)) return { value: '#archive-external', local: false };

  let resolved;
  try {
    resolved = new URL(address, baseOriginal);
  } catch (_) {
    return { value: '#archive-missing', local: false };
  }
  const site = siteByHost.get(resolved.hostname.toLowerCase());
  if (!site) return { value: '#archive-external', local: false };
  let normalized;
  try {
    normalized = canonicalOriginal(site, resolved.href);
  } catch (_) {
    return { value: '#archive-missing', local: false };
  }
  const entry = entriesByKey.get(normalized.key);
  if (!entry) return { value: '#archive-missing', local: false };
  return { value: entry, fragment: split.fragment, local: true };
}

function replacementFor(currentEntry, mapped) {
  if (!mapped.local || typeof mapped.value === 'string') return mapped.value;
  const from = path.posix.dirname(currentEntry.relative);
  let result = path.posix.relative(from, mapped.value.relative).replace(/\\/g, '/');
  if (!result) result = path.posix.basename(mapped.value.relative);
  if (!result.startsWith('.')) result = `./${result}`;
  return result + (mapped.fragment || '');
}

function replacementForAttribute(currentEntry, base, attribute, value, entriesByKey) {
  const mapped = findMappedEntry(entriesByKey, base, value);
  if (mapped.local) return replacementFor(currentEntry, mapped);
  if (/^(?:src|poster|background)$/i.test(attribute)) return blankImage;
  return mapped.value;
}

function rewriteHtml(text, entry, entriesByKey) {
  const base = new URL(entry.original);
  let output = text;
  const attributePattern = /\b(href|src|action|poster|background)\s*=\s*(?:(["'])(.*?)\2|([^\s>]+))/gis;
  output = output.replace(attributePattern, (whole, attribute, quote, quotedValue, bareValue) => {
    const value = quote ? quotedValue : bareValue;
    const replacement = replacementForAttribute(entry, base, attribute, value.trim(), entriesByKey);
    return `${attribute}="${replacement.replace(/"/g, '&quot;')}"`;
  });

  output = output.replace(/\bsrcset\s*=\s*(["'])(.*?)\1/gis, (whole, quote, value) => {
    const rewritten = value.split(',').map(candidate => {
      const parts = candidate.trim().split(/\s+/);
      if (!parts[0]) return candidate;
      parts[0] = replacementForAttribute(entry, base, 'src', parts[0], entriesByKey);
      return parts.join(' ');
    }).join(', ');
    return `srcset=${quote}${rewritten}${quote}`;
  });

  output = output.replace(/url\(\s*(["']?)([^)"']+)\1\s*\)/gi, (whole, quote, value) => {
    const replacement = replacementForAttribute(entry, base, 'src', value.trim(), entriesByKey);
    return `url(${quote}${replacement}${quote})`;
  });

  output = output.replace(/(content\s*=\s*["'][^"']*?url=)([^"']+)/gi, (whole, prefix, value) =>
    prefix + replacementForAttribute(entry, base, 'href', value, entriesByKey)
  );

  // Local copies are documentation, not executable web applications. This
  // blocks old scripts, plugins, forms, and network requests in modern Edge.
  const csp = '<meta http-equiv="Content-Security-Policy" content="default-src \'self\'; base-uri \'none\'; object-src \'none\'; form-action \'none\'; connect-src \'none\'; script-src \'none\'">';
  if (!/<meta[^>]+http-equiv=["']Content-Security-Policy["']/i.test(output)) {
    output = /<head\b[^>]*>/i.test(output)
      ? output.replace(/<head\b[^>]*>/i, match => `${match}${csp}`)
      : csp + output;
  }
  return output;
}

function rewriteCss(text, entry, entriesByKey) {
  const base = new URL(entry.original);
  let output = text.replace(/url\(\s*(["']?)([^)"']+)\1\s*\)/gi, (whole, quote, value) => {
    const replacement = replacementForAttribute(entry, base, 'src', value.trim(), entriesByKey);
    return `url(${quote}${replacement}${quote})`;
  });
  output = output.replace(/(@import\s+)(["'])(.*?)\2/gi, (whole, prefix, quote, value) =>
    prefix + quote + replacementForAttribute(entry, base, 'href', value.trim(), entriesByKey) + quote
  );
  return output;
}

async function readCdx(site) {
  const allRows = [];
  const seen = new Set();
  for (const cdxUrl of site.cdxUrls) {
    const response = await fetchBytes(cdxUrl);
    let rows;
    try { rows = JSON.parse(response.bytes.toString('utf8')); }
    catch (error) { throw new Error(`CDX returned invalid JSON for ${site.id}: ${error.message}`); }
    if (!Array.isArray(rows) || rows.length < 2) throw new Error(`Empty CDX response for ${site.id}`);
    const headers = rows[0];
    for (const values of rows.slice(1)) {
      const row = Object.fromEntries(headers.map((key, index) => [key, values[index]]));
      const identity = `${row.timestamp}|${row.original}|${row.digest}`;
      if (!seen.has(identity)) { seen.add(identity); allRows.push(row); }
    }
  }
  return allRows;
}

async function writeJson(file, value) {
  await fsp.mkdir(path.dirname(file), { recursive: true });
  await fsp.writeFile(file, JSON.stringify(value, null, 2) + '\n', 'utf8');
}

async function removeIfExists(file) {
  await fsp.rm(file, { recursive: true, force: true });
}

async function replaceMirror() {
  const parent = path.dirname(mirrorRoot);
  await fsp.mkdir(parent, { recursive: true });
  const backup = `${mirrorRoot}.previous-${Date.now()}`;
  if (fs.existsSync(mirrorRoot)) await fsp.rename(mirrorRoot, backup);
  try {
    await fsp.rename(stagingRoot, mirrorRoot);
  } catch (error) {
    if (fs.existsSync(backup) && !fs.existsSync(mirrorRoot)) await fsp.rename(backup, mirrorRoot);
    throw error;
  }
  await removeIfExists(backup);
}

async function main() {
  await removeIfExists(stagingRoot);
  await fsp.mkdir(manifestRoot, { recursive: true });

  const all = [];
  const selectedBySite = new Map();
  for (const site of sites) {
    process.stdout.write(`Reading CDX for ${site.aliases.join(', ')}...\n`);
    const rows = await readCdx(site);
    await writeJson(path.join(manifestRoot, `${site.folder}-cdx.json`), rows);
    const { selected } = selectEntries(site, rows);
    selectedBySite.set(site.id, selected);
    all.push(...selected);
    process.stdout.write(`  ${selected.length} unique archived files selected\n`);
  }

  const entriesByKey = new Map(all.map(entry => [entry.key, entry]));
  const manifest = {
    generatedAt: new Date().toISOString(),
    source: 'Internet Archive Wayback Machine raw replay (id_)',
    coverage: 'One representative 1997-1999 capture per unique static URL; dynamic atlas.cgi responses are rendered locally by Wlbrw32.dll.',
    files: all.map(entry => ({
      site: entry.site.folder,
      timestamp: entry.timestamp,
      original: entry.original,
      mime: entry.mime,
      bytes: entry.length,
      local: entry.local,
      source: entry.sourceUrl
    }))
  };

  let completed = 0;
  let failed = 0;
  const failures = [];

  async function downloadEntry(entry) {
    const destination = path.join(stagingRoot, ...entry.local.split('/'));
    const response = await fetchBytes(entry.sourceUrl);
    await fsp.mkdir(path.dirname(destination), { recursive: true });
    const bytes = isHtml(entry, response.contentType)
      ? Buffer.from(rewriteHtml(response.bytes.toString('utf8'), entry, entriesByKey), 'utf8')
      : isCss(entry, response.contentType)
        ? Buffer.from(rewriteCss(response.bytes.toString('utf8'), entry, entriesByKey), 'utf8')
        : response.bytes;
    await fsp.writeFile(destination, bytes);
    entry.downloadedBytes = bytes.length;
    entry.sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  }

  async function downloadBatch(entries, workerCount, label) {
    let cursor = 0;
    const batchFailures = [];
    async function worker() {
      while (true) {
        const index = cursor++;
        if (index >= entries.length) return;
        const entry = entries[index];
        try {
          await downloadEntry(entry);
          completed++;
          if (completed % 50 === 0 || completed === all.length) {
            process.stdout.write(`Downloaded ${completed}/${all.length}\n`);
          }
        } catch (error) {
          batchFailures.push({ entry, error });
          process.stderr.write(`${label} ${entry.local}: ${error && error.message || error}\n`);
        }
      }
    }
    await Promise.all(Array.from({ length: workerCount }, worker));
    return batchFailures;
  }

  process.stdout.write(`Downloading ${all.length} archive files with ${concurrency} workers...\n`);
  let batchFailures = await downloadBatch(all, concurrency, 'FAILED');
  if (batchFailures.length) {
    // Wayback occasionally throttles a burst of requests even when the
    // individual request retry loop succeeds at lower rates. Retry only the
    // failed entries with a small pool instead of discarding the whole run.
    const retryConcurrency = Math.max(1, Math.min(4, Math.floor(concurrency / 4)));
    process.stdout.write(`Retrying ${batchFailures.length} throttled/failed archive files with ${retryConcurrency} workers...\n`);
    batchFailures = await downloadBatch(
      batchFailures.map(item => item.entry),
      retryConcurrency,
      'RETRY FAILED'
    );
  }
  failed = batchFailures.length;
  for (const item of batchFailures) {
    failures.push({
      local: item.entry.local,
      source: item.entry.sourceUrl,
      error: String(item.error && item.error.message || item.error)
    });
  }

  const entryTemplateCandidates = [
    path.join(root, 'Atlas-Online-Entry.html'),
    path.join(root, '..', 'archive', 'Atlas-Online-Entry.html')
  ];
  const entryTemplate = entryTemplateCandidates.find(file => fs.existsSync(file));
  if (entryTemplate) {
    await fsp.copyFile(entryTemplate, path.join(stagingRoot, '3datlas', 'entry-links.html'));
  }

  const required = [
    '3datlas/index.html',
    '3datlas/download/f_main_dl.html',
    '3datlas/sitemap.html',
    'comptons/index.html'
  ];
  for (const relative of required) {
    if (!fs.existsSync(path.join(stagingRoot, ...relative.split('/')))) {
      failures.push({ local: relative, source: 'required archive target', error: 'missing after download' });
      failed++;
    }
  }

  manifest.files = all.map(entry => ({
    site: entry.site.folder,
    timestamp: entry.timestamp,
    original: entry.original,
    mime: entry.mime,
    bytes: entry.downloadedBytes || entry.length,
    local: entry.local,
    source: entry.sourceUrl,
    sha256: entry.sha256 || null
  }));
  await writeJson(path.join(manifestRoot, 'mirror-manifest.json'), manifest);
  await writeJson(path.join(manifestRoot, 'download-failures.json'), failures);
  const summary = {
    generatedAt: manifest.generatedAt,
    sites: sites.map(site => ({ site: site.id, aliases: site.aliases, selected: selectedBySite.get(site.id).length })),
    selected: all.length,
    downloaded: completed,
    failed,
    mirrorRoot,
    manifest: path.join(mirrorRoot, 'manifests', 'mirror-manifest.json'),
    failures: path.join(mirrorRoot, 'manifests', 'download-failures.json')
  };
  await writeJson(path.join(manifestRoot, 'mirror-summary.json'), summary);
  process.stdout.write(JSON.stringify(summary, null, 2) + '\n');

  if (failed) {
    process.stderr.write(`Archive sync left an incomplete staging mirror at ${stagingRoot}; the previous mirror was not replaced.\n`);
    process.exitCode = 1;
    return;
  }
  await replaceMirror();
}

if (require.main === module) {
  main().catch(async error => {
    console.error(error.stack || error);
    process.exitCode = 1;
  });
}

module.exports = {
  canonicalOriginal,
  entryFor,
  findMappedEntry,
  isCss,
  isHtml,
  isNetworkReference,
  replacementFor,
  rewriteCss,
  rewriteHtml,
  selectEntries,
  sites,
  splitReference
};
