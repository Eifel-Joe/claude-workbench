// Real browser touch taps on the phone key bar. The unit tests call click
// listeners directly and so cannot see WebKit dropping the click after a
// cancelled pointerdown (iPhone: no key arrived). Approach and proof of the
// bug: ESJavadex, ESJavadex/claude-code-ha@ab961533.
//
// KEY_BAR_JS overrides the script under test (used to show the test fails on
// the 3.5.0 script).
import assert from 'node:assert/strict';
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { chromium, webkit } from 'playwright';

const scriptUrl = process.env.KEY_BAR_JS
    ? pathToFileURL(process.env.KEY_BAR_JS)
    : new URL('../../claude-workbench/image-service/public/workbench-ui.js', import.meta.url);
const script = await readFile(scriptUrl);
const keys = {
    esc: '\x1b', up: '\x1b[A', down: '\x1b[B', enter: '\r',
    'shift-tab': '\x1b[Z', 'ctrl-c': '\x03'
};
// Minimal page: same buttons and data-key as index.html, but without its CSS
// and tabindex - the behaviour under test is the script's event handling.
const html = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<iframe src="/terminal"></iframe>
<div id="key-bar">${Object.keys(keys).map(key => `<button type="button" data-key="${key}" aria-label="${key}">${key}</button>`).join('')}</div>
<script src="/workbench-ui.js"></script>
<script>ClaudeWorkbenchUi.installKeyBar(document.getElementById('key-bar'), () => document.querySelector('iframe').contentWindow.term, { ctrlCWindowMs: 60000 });</script>`;
const terminal = `<!doctype html><textarea></textarea><script>
window.sent = [];
window.term = { textarea: document.querySelector('textarea'), input(data, user) { sent.push([data, user]); } };
</script>`;
const server = http.createServer((req, res) => {
    res.setHeader('Content-Type', req.url === '/workbench-ui.js' ? 'text/javascript' : 'text/html');
    res.end(req.url === '/workbench-ui.js' ? script : req.url === '/terminal' ? terminal : html);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));

try {
    for (const engine of [chromium, webkit]) {
        const browser = await engine.launch();
        try {
            const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
            await page.goto(`http://127.0.0.1:${server.address().port}/`);
            await page.waitForFunction(() => document.querySelector('iframe').contentWindow.term);
            const frame = page.frames().find(candidate => candidate.url().endsWith('/terminal'));
            assert.ok(frame);
            await frame.waitForFunction(() => window.term);
            await frame.evaluate(() => window.term.textarea.focus());
            const expected = [];
            for (const [key, sequence] of Object.entries(keys)) {
                await page.locator(`[data-key="${key}"]`).tap();
                expected.push([sequence, true]);
                await frame.waitForFunction(count => window.sent.length >= count, expected.length, { timeout: 3000 });
                assert.deepEqual(await frame.evaluate(() => window.sent), expected, `${engine.name()}: ${key} sent exactly once`);
                // activeElement alone stays the textarea even when focus moved to
                // the button in the parent page; hasFocus() turns false then.
                assert.equal(await frame.evaluate(() => document.activeElement === window.term.textarea && document.hasFocus()), true,
                    `${engine.name()}: ${key} keeps terminal focus`);
            }
            // A rapid second Ctrl+C is still ignored after a real touch tap. The
            // key is aria-disabled by now, so Playwright needs force to tap it
            // the way a finger would.
            await page.locator('[data-key="ctrl-c"]').tap({ force: true });
            await page.waitForTimeout(300); // a late click must not slip past the check
            assert.deepEqual(await frame.evaluate(() => window.sent), expected);
            // While locked, assistive technology hears a locked key.
            const ctrlC = page.locator('[data-key="ctrl-c"]');
            assert.equal(await ctrlC.getAttribute('aria-disabled'), 'true', `${engine.name()}: ^C announced as disabled`);
            assert.match(await ctrlC.getAttribute('aria-label'), /locked/, `${engine.name()}: ^C label says locked`);
            console.log(`PASS ${engine.name()}: all touch keys, terminal focus and Ctrl+C guard`);
        } finally {
            await browser.close();
        }
    }
} finally {
    await new Promise(resolve => server.close(resolve));
}
