const assert = require('node:assert/strict');
const test = require('node:test');

const archive = require('../../scripts/Sync-AtlasLocalArchive.js');

const atlasSite = archive.sites.find(site => site.id === '3datlas');

function entry(url, timestamp = '19980421214146') {
  return archive.entryFor(atlasSite, {
    timestamp,
    original: url,
    statuscode: '200',
    mimetype: 'text/html',
    digest: `digest-${url}`,
    length: '10'
  });
}

test('canonicalOriginal gives extensionless archive URLs stable local names', () => {
  const result = archive.canonicalOriginal(atlasSite, 'https://www.3datlas.com/see/china');
  assert.equal(result.relative, 'see/china__endpoint.html');
  assert.equal(archive.entryFor(atlasSite, {
    timestamp: '19980421214146',
    original: 'https://www.3datlas.com/see/china',
    statuscode: '200',
    digest: 'china'
  }).local, '3datlas/see/china__endpoint.html');
});

test('selectEntries deduplicates URLs and chooses the capture nearest the site anchor', () => {
  const rows = [
    { timestamp: '19970101000000', original: 'https://www.3datlas.com/index.html', digest: 'old' },
    { timestamp: '19980421214146', original: 'https://www.3datlas.com/index.html', digest: 'anchor' },
    { timestamp: '19980421214146', original: 'https://www.3datlas.com/about.html', digest: 'about' }
  ];
  const result = archive.selectEntries(atlasSite, rows);
  assert.equal(result.selected.length, 2);
  assert.equal(result.selected.find(item => item.relative === 'index.html').timestamp, '19980421214146');
});

test('rewriteHtml localizes same-site links and blocks active external targets', () => {
  const current = entry('https://www.3datlas.com/index.html');
  const target = entry('https://www.3datlas.com/about.html');
  const entries = new Map([[current.key, current], [target.key, target]]);
  const html = '<head></head><a href="https://www.3datlas.com/about.html">About</a>' +
    '<img src="https://evil.example/image.png"><form action="https://evil.example/login"></form>';

  const rewritten = archive.rewriteHtml(html, current, entries);
  assert.match(rewritten, /href="\.\/about\.html"/);
  assert.match(rewritten, /src="data:image\/gif;base64,/);
  assert.match(rewritten, /action="#archive-external"/);
  assert.match(rewritten, /Content-Security-Policy/);
  assert.doesNotMatch(rewritten, /evil\.example/);
});

test('rewriteCss localizes same-site URLs and replaces external URLs', () => {
  const current = entry('https://www.3datlas.com/css/site.css');
  const target = entry('https://www.3datlas.com/images/map.gif');
  const entries = new Map([[current.key, current], [target.key, target]]);

  const rewritten = archive.rewriteCss(
    'body { background: url("https://www.3datlas.com/images/map.gif") } .x { background: url(https://evil.example/x.png) }',
    current,
    entries
  );
  assert.match(rewritten, /url\("\.\.\/images\/map\.gif"\)/);
  assert.match(rewritten, /url\(data:image\/gif;base64,/);
});

test('reference classification rejects network and executable URL schemes', () => {
  assert.equal(archive.isNetworkReference('https://example.test/x'), true);
  assert.equal(archive.isNetworkReference('/local/x'), false);
  assert.deepEqual(archive.splitReference('page.html#section'), {
    address: 'page.html',
    fragment: '#section'
  });
});
