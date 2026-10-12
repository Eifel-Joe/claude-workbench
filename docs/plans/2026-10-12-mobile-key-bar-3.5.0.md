# Mobil-Tastenleiste (3.5.0) – Umsetzungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auf Touch-Geräten eine Tastenleiste Esc · ↑ · ↓ · ↵ · ⇧Tab · ^C (mit 2-s-Schutz) über der Bildschirmtastatur, die wie Shift+Enter über `term.input` an das Terminal sendet.

**Architecture:** Reine, testbare Funktionen (`keySequence`, `createCtrlCGuard`, `installKeyBar`) in `image-service/public/workbench-ui.js` (UMD, schon für Shift+Enter genutzt); `index.html` bekommt Markup, CSS (`@media (any-pointer: coarse)`) und einen Aufruf. Kein Server-Code, keine Option.

**Tech Stack:** Browser-JS (ES5-Stil wie die übrigen Funktionen in `workbench-ui.js`), xterm.js 5.4 (in ttyd 1.7.7), Node 22 `node:test`.

**Spec:** `docs/specs/2026-10-12-mobile-key-bar-3.5.0-design.md` · **Branch:** `feat/mobile-toolbar`

## Global Constraints

- Keine temporären Dateien auf C:. Vor jedem Testlauf:
  `export TMPDIR=/d/Entwicklung/Claude-Code-HA/.tmp TMP='D:\Entwicklung\Claude-Code-HA\.tmp' TEMP='D:\Entwicklung\Claude-Code-HA\.tmp'`
- Dateien nur mit Write-/Edit-Tool ändern, keine Heredocs/sed im Bash-Tool. Escapes (`\x1b`, `\x03`, `\r`) nach dem Schreiben im Diff prüfen.
- Nach jedem Task `git ls-files --eol | grep -c "crlf\|mixed"` → `0`. Gezielt stagen; nach jedem Commit `git show --stat --oneline HEAD` lesen.
- Im App-Code (`image-service/`, `run.sh`, `scripts/`, `Dockerfile`) kein „claude-terminal“/„Claude Terminal“. Credit dort: „mattbsea's fork, commit ed215953“.
- Credits in CHANGELOG/Release-Notes: mattbsea (`ed215953`), weiting-tw (`fe0a4ec9`), marcjay (`f6674b77`).
- Sequenzen exakt: esc `\x1b`, up `\x1b[A` (App-Cursor `\x1bOA`), down `\x1b[B` (App-Cursor `\x1bOB`), enter `\r`, shift-tab `\x1b[Z`, ctrl-c `\x03`.
- ^C-Sperre 2000 ms ab dem letzten **gesendeten** ^C; Knopf zeigt in der Zeit `wait` (Klasse `key-wait`).
- Version 3.5.0 (`claude-workbench/config.yaml`, Badge in Repo-`README.md`). `DEVELOPMENT.md` nicht ändern.
- Commit-Messages: WAS und WARUM, letzte Zeile `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Push, PR, Merge, Tag, Release nur nach Freigabe im Chat; PR-Text vorher zeigen. `gh` immer mit `--repo Eifel-Joe/claude-workbench`.

## Review Focus

1. **Tipp, bevor ttyd da ist** (Startseite im iframe, kein `term`): nichts senden, kein Fehler, und der ^C-Schutz darf dabei nicht „verbraucht“ werden – Test in Task 2.
2. **Tipp trifft ein Kind-Element des Knopfs** (Text-Span o. Ä.): Taste trotzdem erkennen – Test in Task 2.
3. **iframe neu geladen** (Reconnect): neues `term`-Objekt muss beim nächsten Tipp benutzt werden, nicht das alte – Test in Task 2.
4. **Application-Cursor-Modus** wechselt zur Laufzeit (vim, less, manche TUIs): Pfeile je Tipp neu bestimmen – Test in Task 1 und Task 2.
5. **Fokus/Bildschirmtastatur**: `pointerdown` **und** `mousedown` müssen verhindert werden, sonst wandert der Fokus aus dem iframe und die Tastatur klappt zu – Test in Task 2, live in Task 5.

---

### Task 1: `keySequence` und `createCtrlCGuard`

**Files:**
- Modify: `claude-workbench/image-service/public/workbench-ui.js` (vor dem `return {`-Block am Ende, Exporte ergänzen)
- Test: `tests/test-workbench-ui.js` (Tests ans Ende anhängen)

**Interfaces:**
- Produces: `keySequence(name: string, term: object|null) -> string|null`;
  `createCtrlCGuard(now?: () => number, windowMs?: number = 2000) -> () => boolean` (die zurückgegebene Funktion heißt `allow`).

- [x] **Step 1: Failing tests anhängen** – ans Ende von `tests/test-workbench-ui.js`:

```js
test('keySequence maps the six keys', () => {
    assert.equal(ui.keySequence('esc', {}), '\x1b');
    assert.equal(ui.keySequence('up', {}), '\x1b[A');
    assert.equal(ui.keySequence('down', {}), '\x1b[B');
    assert.equal(ui.keySequence('enter', {}), '\r');
    assert.equal(ui.keySequence('shift-tab', {}), '\x1b[Z');
    assert.equal(ui.keySequence('ctrl-c', {}), '\x03');
});

test('keySequence sends SS3 arrows in application cursor mode', () => {
    const term = { modes: { applicationCursorKeysMode: true } };
    assert.equal(ui.keySequence('up', term), '\x1bOA');
    assert.equal(ui.keySequence('down', term), '\x1bOB');
    assert.equal(ui.keySequence('esc', term), '\x1b');
    assert.equal(ui.keySequence('up', { modes: { applicationCursorKeysMode: false } }), '\x1b[A');
});

test('keySequence copes with a missing term or modes and unknown names', () => {
    assert.equal(ui.keySequence('up', null), '\x1b[A');
    assert.equal(ui.keySequence('down', {}), '\x1b[B');
    assert.equal(ui.keySequence('tab', {}), null);
    assert.equal(ui.keySequence('toString', {}), null);
});

test('createCtrlCGuard lets one Ctrl+C through per two seconds', () => {
    const clock = { t: 10000 };
    const allow = ui.createCtrlCGuard(() => clock.t);
    assert.equal(allow(), true);
    clock.t += 1000;
    assert.equal(allow(), false);
    clock.t += 999;
    assert.equal(allow(), false);
    clock.t += 1;
    assert.equal(allow(), true);
});

test('createCtrlCGuard counts from the last Ctrl+C actually let through', () => {
    const clock = { t: 0 };
    const allow = ui.createCtrlCGuard(() => clock.t, 2000);
    assert.equal(allow(), true);   // sent at 0
    clock.t = 1500;
    assert.equal(allow(), false);  // refused, does not restart the window
    clock.t = 2000;
    assert.equal(allow(), true);   // 2 s after the sent one
});
```

- [x] **Step 2: RED**

Run: `node --test --test-reporter=tap tests/test-workbench-ui.js`
Expected: die 5 neuen Tests FAIL mit `ui.keySequence is not a function` bzw. `ui.createCtrlCGuard is not a function`; die 5 alten ok.

- [x] **Step 3: Implementierung** – in `workbench-ui.js` direkt vor `    return {` einfügen:

```js
    // Phone key bar (index.html #key-bar): what each key sends, as xterm.js
    // would for the real key. Arrows follow the terminal's cursor-key mode
    // (DECCKM): full-screen programs switch to the SS3 form, so it is read on
    // every tap (mattbsea's fork, commit ed215953).
    var KEY_SEQUENCES = {
        'esc': '\x1b',
        'up': '\x1b[A',
        'down': '\x1b[B',
        'enter': '\r',
        'shift-tab': '\x1b[Z',
        'ctrl-c': '\x03'
    };
    var APP_CURSOR_SEQUENCES = { 'up': '\x1bOA', 'down': '\x1bOB' };

    function keySequence(name, term) {
        if (!Object.prototype.hasOwnProperty.call(KEY_SEQUENCES, name)) return null;
        var appCursor = !!(term && term.modes && term.modes.applicationCursorKeysMode === true);
        if (appCursor && Object.prototype.hasOwnProperty.call(APP_CURSOR_SEQUENCES, name)) {
            return APP_CURSOR_SEQUENCES[name];
        }
        return KEY_SEQUENCES[name];
    }

    /**
     * Two Ctrl+C in a row quit Claude Code, which ends the tmux session; on a
     * phone a double tap is easy. Lets one through per window, counted from
     * the last one let through.
     */
    function createCtrlCGuard(now, windowMs) {
        var clock = now || Date.now;
        var span = windowMs === undefined ? 2000 : windowMs;
        var lastSent = null;
        return function allow() {
            var t = clock();
            if (lastSent !== null && t - lastSent < span) return false;
            lastSent = t;
            return true;
        };
    }

```

  und den Export-Block ersetzen durch:

```js
    return {
        isShiftEnter: isShiftEnter,
        installShiftEnter: installShiftEnter,
        autoContinueLabel: autoContinueLabel,
        keySequence: keySequence,
        createCtrlCGuard: createCtrlCGuard
    };
```

- [x] **Step 4: GREEN**

Run: `node --test --test-reporter=tap tests/test-workbench-ui.js`
Expected: `# pass 10`, `# fail 0`. Im Diff prüfen: `'\x1b'`, `'\x1b[A'`, `'\x03'` stehen genau so in der Datei.

- [x] **Step 5: Commit**

```bash
git add claude-workbench/image-service/public/workbench-ui.js tests/test-workbench-ui.js
git commit -m "feat: key sequences and a Ctrl+C guard for the phone key bar"
```

---

### Task 2: `installKeyBar`

**Files:**
- Modify: `claude-workbench/image-service/public/workbench-ui.js`
- Test: `tests/test-workbench-ui.js`

**Interfaces:**
- Consumes: `keySequence`, `createCtrlCGuard` (Task 1).
- Produces: `installKeyBar(bar: Element, getTerm: () => object|null, options?: { now?, ctrlCWindowMs?, setTimeout? }) -> boolean` (`true` beim ersten Installieren, `false` sonst). Knöpfe tragen `data-key` mit den Namen aus Task 1.

- [x] **Step 1: Failing tests anhängen:**

```js
// Fake key bar: a container with buttons (dataset.key) and one listener list.
function fakeBar(keys) {
    const listeners = {};
    const bar = {
        parentNode: null,
        addEventListener(type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
        fire(type, target) {
            const e = {
                type, target, prevented: false,
                preventDefault() { this.prevented = true; },
            };
            for (const fn of listeners[type] || []) fn(e);
            return e;
        },
        listeners,
        buttons: {},
    };
    for (const k of keys) {
        const classes = new Set();
        bar.buttons[k] = {
            dataset: { key: k },
            parentNode: bar,
            textContent: k === 'ctrl-c' ? '^C' : k,
            classList: {
                add: (c) => classes.add(c),
                remove: (c) => classes.delete(c),
                contains: (c) => classes.has(c),
            },
        };
    }
    return bar;
}

function fakeTerm(extra) {
    const sent = [];
    return Object.assign({ sent, input(data, user) { sent.push([data, user]); } }, extra);
}

const ALL_KEYS = ['esc', 'up', 'down', 'enter', 'shift-tab', 'ctrl-c'];

test('installKeyBar sends the tapped key as typed input', () => {
    const bar = fakeBar(ALL_KEYS);
    const term = fakeTerm();
    assert.equal(ui.installKeyBar(bar, () => term), true);
    bar.fire('click', bar.buttons.down);
    bar.fire('click', bar.buttons.enter);
    bar.fire('click', bar.buttons['shift-tab']);
    assert.deepEqual(term.sent, [['\x1b[B', true], ['\r', true], ['\x1b[Z', true]]);
});

test('installKeyBar keeps the focus in the terminal', () => {
    const bar = fakeBar(ALL_KEYS);
    ui.installKeyBar(bar, () => fakeTerm());
    assert.equal(bar.fire('pointerdown', bar.buttons.esc).prevented, true);
    assert.equal(bar.fire('mousedown', bar.buttons.esc).prevented, true);
    // A tap on the bar's gap is not a key: leave it alone.
    assert.equal(bar.fire('pointerdown', bar).prevented, false);
});

test('installKeyBar finds the key from a child of the button', () => {
    const bar = fakeBar(ALL_KEYS);
    const term = fakeTerm();
    ui.installKeyBar(bar, () => term);
    const label = { parentNode: bar.buttons.up };
    bar.fire('click', label);
    assert.deepEqual(term.sent, [['\x1b[A', true]]);
});

test('installKeyBar does nothing while there is no terminal yet', () => {
    const bar = fakeBar(ALL_KEYS);
    let term = null;
    ui.installKeyBar(bar, () => term, { now: () => 0, setTimeout: () => {} });
    bar.fire('click', bar.buttons['ctrl-c']);           // start page: no term
    assert.equal(bar.buttons['ctrl-c'].textContent, '^C');
    term = fakeTerm({ input: undefined });
    bar.fire('click', bar.buttons.esc);                 // term without input()
    term = fakeTerm();
    bar.fire('click', bar.buttons['ctrl-c']);           // guard was not used up
    assert.deepEqual(term.sent, [['\x03', true]]);
});

test('installKeyBar reads the terminal on every tap', () => {
    const bar = fakeBar(ALL_KEYS);
    const first = fakeTerm();
    const second = fakeTerm({ modes: { applicationCursorKeysMode: true } });
    let current = first;
    ui.installKeyBar(bar, () => current);
    bar.fire('click', bar.buttons.up);
    current = second;                                   // iframe reloaded, vim running
    bar.fire('click', bar.buttons.up);
    assert.deepEqual(first.sent, [['\x1b[A', true]]);
    assert.deepEqual(second.sent, [['\x1bOA', true]]);
});

test('installKeyBar guards Ctrl+C and shows wait until it is free again', () => {
    const bar = fakeBar(ALL_KEYS);
    const term = fakeTerm();
    const clock = { t: 0 };
    const timers = [];
    ui.installKeyBar(bar, () => term, {
        now: () => clock.t,
        setTimeout: (fn, ms) => timers.push([fn, ms]),
    });
    const ctrlC = bar.buttons['ctrl-c'];
    bar.fire('click', ctrlC);
    clock.t = 500;
    bar.fire('click', ctrlC);
    assert.deepEqual(term.sent, [['\x03', true]]);
    assert.equal(ctrlC.textContent, 'wait');
    assert.equal(ctrlC.classList.contains('key-wait'), true);
    assert.equal(timers.length, 1);
    assert.equal(timers[0][1], 2000);
    timers[0][0]();                                     // 2 s later
    assert.equal(ctrlC.textContent, '^C');
    assert.equal(ctrlC.classList.contains('key-wait'), false);
    clock.t = 2000;
    bar.fire('click', ctrlC);
    assert.equal(term.sent.length, 2);
});

test('installKeyBar installs once per bar', () => {
    const bar = fakeBar(ALL_KEYS);
    const term = fakeTerm();
    assert.equal(ui.installKeyBar(bar, () => term), true);
    assert.equal(ui.installKeyBar(bar, () => term), false);
    bar.fire('click', bar.buttons.esc);
    assert.deepEqual(term.sent, [['\x1b', true]]);
    assert.equal(ui.installKeyBar(null, () => term), false);
});
```

- [x] **Step 2: RED**

Run: `node --test --test-reporter=tap tests/test-workbench-ui.js`
Expected: 7 neue Tests FAIL mit `ui.installKeyBar is not a function`; 10 ok.

- [x] **Step 3: Implementierung** – in `workbench-ui.js` nach `createCtrlCGuard` (vor `    return {`) einfügen:

```js
    var KEYBAR_FLAG = '__claudeKeyBarInstalled';

    /**
     * Wire the phone key bar. getTerm is asked on every tap: the ttyd frame
     * reloads on reconnect and then has a new term. pointerdown and mousedown
     * are cancelled so the tap does not move the focus out of the terminal -
     * that would close the on-screen keyboard (and a tap with the keyboard
     * closed must not open it).
     */
    function installKeyBar(bar, getTerm, options) {
        if (!bar || bar[KEYBAR_FLAG]) return false;
        bar[KEYBAR_FLAG] = true;
        var opts = options || {};
        var windowMs = opts.ctrlCWindowMs === undefined ? 2000 : opts.ctrlCWindowMs;
        var allowCtrlC = createCtrlCGuard(opts.now, windowMs);
        var later = opts.setTimeout || function (fn, ms) { return setTimeout(fn, ms); };

        function keyButton(target) {
            for (var el = target; el && el !== bar; el = el.parentNode) {
                if (el.dataset && el.dataset.key) return el;
            }
            return null;
        }

        function keepFocus(e) {
            if (keyButton(e.target)) e.preventDefault();
        }
        bar.addEventListener('pointerdown', keepFocus);
        bar.addEventListener('mousedown', keepFocus);

        bar.addEventListener('click', function (e) {
            var button = keyButton(e.target);
            if (!button) return;
            var term = getTerm();
            if (!term || typeof term.input !== 'function') return; // start page
            var name = button.dataset.key;
            var seq = keySequence(name, term);
            if (seq === null) return;
            if (name === 'ctrl-c') {
                if (!allowCtrlC()) return;
                button.textContent = 'wait';
                button.classList.add('key-wait');
                later(function () {
                    button.textContent = '^C';
                    button.classList.remove('key-wait');
                }, windowMs);
            }
            term.input(seq, true);
        });
        return true;
    }

```

  Export-Block um `installKeyBar: installKeyBar` ergänzen:

```js
    return {
        isShiftEnter: isShiftEnter,
        installShiftEnter: installShiftEnter,
        autoContinueLabel: autoContinueLabel,
        keySequence: keySequence,
        createCtrlCGuard: createCtrlCGuard,
        installKeyBar: installKeyBar
    };
```

  Den Kopfkommentar der Datei um einen Satz ergänzen (nach dem Shift+Enter-Absatz):
  ` * Phone key bar: Esc, arrows, Enter, Shift+Tab and a guarded Ctrl+C, sent the`
  ` * same way (installKeyBar).`

- [x] **Step 4: GREEN**

Run: `node --test --test-reporter=tap tests/test-workbench-ui.js && node tests/test-terminal-clipboard.js`
Expected: `# pass 17`, `# fail 0`; Clipboard „All 100 clipboard bridge tests passed“.

- [x] **Step 5: Gegenprobe** – in `installKeyBar` `bar.addEventListener('mousedown', keepFocus);` vorübergehend auskommentieren (Edit-Tool): Test „keeps the focus“ muss FAIL. Zurück per Edit-Tool, wieder GREEN.

- [x] **Step 6: Commit**

```bash
git add claude-workbench/image-service/public/workbench-ui.js tests/test-workbench-ui.js
git commit -m "feat: installKeyBar wires the phone key bar to the terminal"
```

---

### Task 3: Leiste in `index.html`

**Files:**
- Modify: `claude-workbench/image-service/public/index.html` (CSS nach `.header-btn .btn-short { display: none; }`, Markup nach `#terminal-container`, Aufruf nach `setInterval(refreshAutoContinue, 30000);`)
- Test: `tests/test-image-service.js`

**Interfaces:**
- Consumes: `ClaudeWorkbenchUi.installKeyBar` (Task 2).

- [x] **Step 1: Failing test** – in `tests/test-image-service.js` nach dem Test `'the UI loads the panel helpers and has the auto-continue button'`:

```js
test('the UI has the phone key bar with all six keys', async () => {
    const html = await (await fetch(`http://127.0.0.1:${PORT}/`)).text();
    assert.match(html, /<div id="key-bar"/);
    for (const key of ['esc', 'up', 'down', 'enter', 'shift-tab', 'ctrl-c']) {
        assert.match(html, new RegExp(`data-key="${key}"`), key);
    }
    assert.match(html, /ClaudeWorkbenchUi\.installKeyBar\(/);
    assert.match(html, /@media \(any-pointer: coarse\)/);
});
```

Run: `node --test --test-reporter=tap tests/test-image-service.js` → dieser Test FAIL.

- [x] **Step 2: CSS** – nach

```css
        .header-btn .btn-short {
            display: none;
        }
```

  einfügen:

```css

        /* Phone key bar: touch devices only, the container's last row, so it
           sits right above the on-screen keyboard (trackOnScreenKeyboard
           sizes the container to the visible viewport). */
        #key-bar {
            display: none;
            flex-shrink: 0;
            gap: 4px;
            padding: 4px;
            background: #2d2d2d;
            border-top: 1px solid #3d3d3d;
        }

        #key-bar button {
            flex: 1;
            height: 40px;
            background: #3a3a3a;
            color: #eee;
            border: 1px solid #4a4a4a;
            border-radius: 4px;
            font-size: 15px;
            font-family: inherit;
            touch-action: manipulation;
            -webkit-user-select: none;
            user-select: none;
        }

        #key-bar button:active {
            background: #007acc;
        }

        #key-bar button.key-wait {
            color: #888;
        }

        @media (any-pointer: coarse) {
            #key-bar {
                display: flex;
            }
        }
```

- [x] **Step 3: Markup** – ersetzen

```html
                <div id="drop-zone-text">Drop image here to upload</div>
            </div>
        </div>
    </div>
```

  durch

```html
                <div id="drop-zone-text">Drop image here to upload</div>
            </div>
        </div>
        <div id="key-bar" role="toolbar" aria-label="Terminal keys">
            <button type="button" tabindex="-1" data-key="esc" aria-label="Escape">Esc</button>
            <button type="button" tabindex="-1" data-key="up" aria-label="Arrow up">↑</button>
            <button type="button" tabindex="-1" data-key="down" aria-label="Arrow down">↓</button>
            <button type="button" tabindex="-1" data-key="enter" aria-label="Enter">↵</button>
            <button type="button" tabindex="-1" data-key="shift-tab" aria-label="Shift+Tab">⇧Tab</button>
            <button type="button" tabindex="-1" data-key="ctrl-c" aria-label="Ctrl+C">^C</button>
        </div>
    </div>
```

- [x] **Step 4: Aufruf** – nach der Zeile `        setInterval(refreshAutoContinue, 30000);` einfügen:

```js

        // Phone key bar (public/workbench-ui.js): the terminal is looked up on
        // every tap, the ttyd frame gets a new one after a reconnect.
        ClaudeWorkbenchUi.installKeyBar(document.getElementById('key-bar'), () => {
            try {
                return document.getElementById('terminal-frame').contentWindow.term || null;
            } catch {
                return null;
            }
        });
```

- [x] **Step 5: GREEN + Syntax**

Run: `node --test --test-reporter=tap tests/test-image-service.js` → alle Einzeltests ok (unter Windows ggf. der bekannte ECONNRESET-Fehlschlag auf Dateiebene; maßgeblich sind die Einzeltests).
Syntax-Probe ohne Datei: `node -e "const h=require('fs').readFileSync('claude-workbench/image-service/public/index.html','utf8');const b=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)];new Function(b[b.length-1][1]);console.log('syntax ok')"` → `syntax ok`.

- [x] **Step 6: Lokale Sichtprüfung (Kriterium vorab: Desktop ohne Leiste, Mobil mit Leiste unten, sechs gleich breite Knöpfe)**

  Image-Service im Hintergrund starten (Bash-Tool `run_in_background`):
  `cd claude-workbench/image-service && TMPDIR=… TMP=… TEMP=… IMAGE_SERVICE_PORT=17680 TTYD_PORT=17681 UPLOAD_DIR='D:\Entwicklung\Claude-Code-HA\.tmp\preview-img' AUTO_CONTINUE_DIR='D:\Entwicklung\Claude-Code-HA\.tmp\preview-ac' node server.js`
  Browser-Fenster: `http://localhost:17680/` → Screenshot Desktop (keine Leiste); `resize_window` Preset `mobile`, neu laden → Screenshot (Leiste unten). Danach Preset `desktop`, Server per **TaskStop** beenden (nicht per netstat – Windows meldet „ABHÖREN“), `.tmp/preview-img` und `.tmp/preview-ac` löschen, `.tmp` leer.

- [x] **Step 7: Commit**

```bash
git add claude-workbench/image-service/public/index.html tests/test-image-service.js
git commit -m "feat: phone key bar above the on-screen keyboard"
```

---

### Task 4: Doku und Version 3.5.0

**Files:**
- Modify: `claude-workbench/config.yaml` (`version: "3.5.0"`), `README.md` (Badge `version-3.5.0`)
- Modify: `claude-workbench/CHANGELOG.md`, `claude-workbench/DOCS.md` (`### Keyboard`), `claude-workbench/README.md` (Feature-Liste)
- Create: `docs/release-notes-3.5.0.md`
- Modify: `docs/FORK-SURVEY-heytcass.md` (Zeile „Mobil-Toolbar …“)

- [x] **Step 1: Version** – `config.yaml` `version: "3.4.1"` → `"3.5.0"`; Repo-`README.md` `version-3.4.1-` → `version-3.5.0-`.
  Run: `bash tests/test-release-metadata.sh` → FAIL, weil CHANGELOG noch keinen 3.5.0-Abschnitt hat (RED für Step 2).

- [x] **Step 2: CHANGELOG** – oben nach `# Changelog`:

```markdown
## 3.5.0

### ✨ New Feature - Key bar for phones
- **Esc, ↑, ↓, ↵, ⇧Tab and ^C** in a row above the on-screen keyboard, on
  touch devices only: cancel a reply, move through Claude's menus and
  questions, switch the mode with Shift+Tab, stop a command in the shell
  (mattbsea, mattbsea's heytcass fork, commit `ed215953`; weiting-tw
  `fe0a4ec9`; marcjay `f6674b77`).
- **The keyboard stays open** while you tap the keys.
- **^C is guarded**: a second ^C within two seconds is not sent, because two
  in a row quit Claude Code and end the session.
```

  Run: `bash tests/test-release-metadata.sh` → „Release metadata suite passed (version 3.5.0)“.

- [x] **Step 3: DOCS.md** – Abschnitt `### Keyboard` ersetzen durch:

```markdown
### Keyboard
- **Shift+Enter** inserts a new line in Claude's input instead of sending it.
- **Key bar on phones and tablets:** a row of keys above the on-screen
  keyboard, shown on touch devices only. **Esc** cancels a reply or closes a
  dialog, **↑ ↓ ↵** move through Claude's menus and questions (`/model`,
  `/resume`), **⇧Tab** switches the mode (normal, auto, plan), and **^C**
  stops a command in the shell. The on-screen keyboard stays open while you
  tap them.
- **^C on the key bar** is sent at most once every two seconds: two Ctrl+C in
  a row quit Claude Code and end the session (your history stays available
  through `/resume`).
```

- [x] **Step 4: App-README** – in `claude-workbench/README.md` nach der Zeile
  `- **Shift+Enter**: Inserts a new line in Claude's input instead of sending it` einfügen:
  `- **Key Bar on Phones**: Esc, arrow keys, Enter, Shift+Tab and a guarded Ctrl+C above the on-screen keyboard`

- [x] **Step 5: Release-Notes** – `docs/release-notes-3.5.0.md`:

```markdown
## Key bar for phones

- **Esc, ↑, ↓, ↵, ⇧Tab and ^C** in a row above the on-screen keyboard, shown on touch devices only. Cancel a reply, move through Claude's menus and questions, switch the mode with Shift+Tab, stop a command in the shell — without a hardware keyboard.
- **The keyboard stays open** while you tap the keys.
- **^C is guarded:** a second ^C within two seconds is not sent, because two in a row quit Claude Code and end the session.

**Upgrade notes:** nothing to do. Reload the panel once after the update; on a PC nothing changes.

The idea comes from mattbsea's fork of [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons) (`ed215953`), with the key choice informed by weiting-tw (`fe0a4ec9`) and marcjay (`f6674b77`). Thank you! Full details: [CHANGELOG](https://github.com/Eifel-Joe/claude-workbench/blob/main/claude-workbench/CHANGELOG.md).
```

- [x] **Step 6: Survey** – in `docs/FORK-SURVEY-heytcass.md` die Zeile
  `| Mobil-Toolbar Esc/Pfeile (Y/N) | mattbsea, weiting-tw (marcjay Shift+Tab) | offen, als Nächstes (2026-10-12) |`
  ersetzen durch
  `| Mobil-Tastenleiste Esc, ↑, ↓, ↵, ⇧Tab, ^C (geschützt) | mattbsea, weiting-tw, marcjay | ✅ 3.5.0 |`

- [x] **Step 7: Prüfen und committen**

Run: `bash tests/test-release-metadata.sh && git ls-files --eol | grep -c "crlf\|mixed"` → passed (3.5.0), `0`.

```bash
git add claude-workbench/config.yaml README.md claude-workbench/CHANGELOG.md claude-workbench/DOCS.md claude-workbench/README.md docs/release-notes-3.5.0.md docs/FORK-SURVEY-heytcass.md
git commit -m "docs: 3.5.0 - key bar for phones, credits to mattbsea, weiting-tw, marcjay"
git show --stat --oneline HEAD
```

---

### Task 5: Gesamtprüfung, Review, PR, CI, HA-Test, Release

- [x] **Step 1: Alle lokalen Suiten** (TMPDIR/TMP/TEMP auf `.tmp`):
  `bash tests/test-release-metadata.sh`, `bash tests/test-persist-install.sh`, `bash tests/test-startup-timeouts.sh`,
  `bash tests/test-cpu-check.sh < /dev/null`, `bash tests/test-npm-cache.sh`, `bash tests/test-health-check.sh`,
  `bash tests/test-startup-order.sh`, `bash tests/test-claude-assets.sh`, `bash tests/test-auth-helper.sh`,
  `bash tests/test-image-retention.sh`, `bash tests/test-tmux-config.sh`, `bash tests/test-auto-continue-cmd.sh`,
  `node tests/test-terminal-clipboard.js`, `node --test tests/test-workbench-ui.js`, `node --test tests/test-auto-continue.js`,
  `PATH="/c/WINDOWS/system32:$PATH" node --test tests/test-app-migration.js`,
  `node --test --test-reporter=tap tests/test-image-service.js`; ShellCheck wie die CI. Ausgaben zeigen.
- [x] **Step 2: Code-Review per Subagent** (Diff `c503a887..HEAD`, Spec, Plan), Befunde über `superpowers:receiving-code-review` prüfen, Fixes mit Test und eigenem Commit.
- [ ] **Step 3: Push des Branches, PR-Text im Chat zeigen**, nach Freigabe `gh pr create --repo Eifel-Joe/claude-workbench --base main --head feat/mobile-toolbar`; danach `ccd_pr`-Tools (`get_status`, ggf. `bind_pr`) und CI am PR abwarten.
- [ ] **Step 4: Merge über GitHub nach Freigabe**, dann HA-Test per MCP: `ha_manage_app check_updates`, dann `update`; App-Log prüfen.
- [ ] **Step 5: Ende-zu-Ende auf HA-Test am echten Handy** laut Spec („Ende-zu-Ende-Kriterium“ Punkt 2): `/model` ↓↓↵, Esc bricht ab, ⇧Tab wechselt den Modus, ^C doppelt → Claude läuft weiter und Knopf zeigt „wait“, Tastatur bleibt offen; am PC keine Leiste. Ergebnis in `docs/SESSION-STAND.md`.
- [ ] **Step 6: Release nach Freigabe**: Tag `v3.5.0`, GitHub-Release „3.5.0 — Key bar for phones“ mit `docs/release-notes-3.5.0.md`; HA-Prod-Update startet der User (vorher „Nach Updates suchen“), danach Supervisor- und App-Log per MCP.
