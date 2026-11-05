# Tastenleiste – Korrekturen (3.5.1) – Umsetzungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Checkbox-Schritte (`- [ ]`).

**Goal:** Tasten der Leiste senden auf iPhone/WebKit wieder (p01), echter Browser-Test in der CI (p03), Callout aus (p05), Home-Leisten-Abstand (p06), ^C-Sperre für Bildschirmleser (p07), Sitzungsnotiz (p11).

**Spec:** `docs/specs/2026-11-05-key-bar-fixes-3.5.1-design.md` · **Branch:** `fix/key-bar-3.5.1` · **Vorlage:** `git show ab961533` (Remote `upstream`)

## Global Constraints

- Keine Temp-Dateien auf C:. Vor jedem Lauf:
  `export PATH="/c/WINDOWS/system32:$PATH" TMPDIR=D:/Entwicklung/Claude-Code-HA/.tmp TMP=D:/Entwicklung/Claude-Code-HA/.tmp TEMP=D:/Entwicklung/Claude-Code-HA/.tmp npm_config_cache=D:/Entwicklung/Claude-Code-HA/.tmp/npm-cache PLAYWRIGHT_BROWSERS_PATH=D:/Entwicklung/Claude-Code-HA/.tmp/pw-browsers`
- Dateien nur mit Write/Edit ändern; Escapes (`\x1b`, `\r`) im Diff prüfen. Gezielt stagen, nach jedem Commit `git show --stat --oneline HEAD`.
- Im App-Code kein „claude-terminal“/„Claude Terminal“.
- Commit-Messages: WAS und WARUM, letzte Zeile `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Lokal nur Einzelsuiten (`node --test tests/test-workbench-ui.js`, `bash tests/test-release-metadata.sh`); `run-tests.sh` läuft in der CI. Kein Podman.
- Runner `ubuntu-24.04`, nie `ubuntu-latest`.
- Push, PR, Merge, Tag, Release nur nach Freigabe im Chat; `gh` immer mit `--repo Eifel-Joe/claude-workbench`.
- Credit ESJavadex namentlich in Commit-Message von Task 1/2, CHANGELOG und Release-Notes.

## Review Focus

1. Kein Doppelsenden: ohne `pointerdown`-Verhinderung darf ein Tipp genau **einmal** senden (Browser-Test prüft `sent` exakt).
2. Fokus bleibt im Terminal nach Tipp (`mousedown` verhindert) – Browser-Test.
3. ^C-Schutz weiterhin aktiv nach echtem Tipp; Label/aria werden nach der Sperre **auf den Originalwert** zurückgesetzt.
4. CI-Job: Runner-Pin, `--ignore-scripts`, Lockfile vorhanden, Version von Playwright exakt gepinnt.

---

### Task 1: p01 – pointerdown nicht mehr verhindern

**Files:** `tests/test-workbench-ui.js` (Test „installKeyBar keeps the focus in the terminal“), `claude-workbench/image-service/public/workbench-ui.js` (`installKeyBar`, Kommentar + `pointerdown`-Zeile).

- [ ] **RED:** Test ersetzen durch:
  ```js
  test('installKeyBar keeps the focus in the terminal without cancelling pointerdown', () => {
      const bar = fakeBar(ALL_KEYS);
      ui.installKeyBar(bar, () => fakeTerm());
      // WebKit drops the tap's click after a cancelled pointerdown: no key is sent.
      assert.equal(bar.fire('pointerdown', bar.buttons.esc).prevented, false);
      assert.equal(bar.fire('mousedown', bar.buttons.esc).prevented, true);
      assert.equal(bar.fire('mousedown', bar).prevented, false); // gap between keys
  });
  ```
  `node --test tests/test-workbench-ui.js` → **FAIL** (pointerdown prevented = true).
- [ ] **GREEN:** Zeile `bar.addEventListener('pointerdown', keepFocus);` entfernen; Kommentar von `installKeyBar` anpassen („mousedown is cancelled …; pointerdown is left alone: cancelling it makes WebKit drop the touch's click“, Credit ESJavadex `ab961533`). Test grün, ganze Datei grün.
- [ ] Schwester-Pfad: `grep -rn pointerdown claude-workbench` – keine weiteren Treffer außer dem Kommentar.
- [ ] Commit: `fix: key bar taps reach the terminal on iPhone (WebKit)` – Body: Wurzel (cancelled pointerdown unterdrückt click), Credit ESJavadex/claude-code-ha@ab961533.

### Task 2: p03 – Browser-Test in der CI

**Files:** `tests/browser/package.json`, `tests/browser/package-lock.json` (per `npm install --package-lock-only`), `tests/browser/test-key-bar.mjs`, `.github/workflows/ci.yml` (neuer Job `browser`).

- [ ] `package.json`: `{ "name": "claude-workbench-browser-tests", "private": true, "scripts": { "test": "node test-key-bar.mjs" }, "devDependencies": { "playwright": "1.64.1" } }`. Lockfile erzeugen, `resolved`/`integrity` prüfen.
- [ ] Test nach Vorlage `git show ab961533:tests/browser/test-key-bar.mjs`, angepasst: Skriptpfad `process.env.KEY_BAR_JS` oder `../../claude-workbench/image-service/public/workbench-ui.js`; Seite ruft `ClaudeWorkbenchUi.installKeyBar(bar, getTerm, { ctrlCWindowMs: 60000 })`; Tasten laut `keySequence` (esc, up, down, enter, shift-tab, ctrl-c – ohne tab/newline, die es bei uns nicht gibt); je Taste `locator.tap()`, `sent` genau einmal, Fokus bleibt; zweites ^C abgewiesen; zusätzlich ^C-Knopf trägt während der Sperre `aria-disabled="true"` (nach Task 4).
- [ ] **RED (Beleg):** `git show main:claude-workbench/image-service/public/workbench-ui.js > .tmp/workbench-ui-3.5.0.js`, dann `KEY_BAR_JS=… npm test` → erwartet FAIL mindestens in WebKit. Ausgabe festhalten. Browser einmalig: `npx playwright install chromium webkit` (nach `.tmp/pw-browsers`).
- [ ] **GREEN:** `npm test` gegen den Fix aus Task 1 → PASS chromium + webkit.
- [ ] CI-Job `browser` (`runs-on: ubuntu-24.04`, `timeout-minutes: 10`): `actions/checkout@v7`, `actions/setup-node@v7` (Node 22, `cache: npm`, `cache-dependency-path: tests/browser/package-lock.json`), Schritt `npm ci --ignore-scripts && npx playwright install --with-deps chromium webkit` (working-directory `tests/browser`), Schritt `npm test`.
- [ ] `bash tests/test-release-metadata.sh` grün. Commit: `test: real-browser key bar test (Chromium + WebKit) in CI` – Credit ESJavadex.
- [ ] Falls WebKit unter Windows lokal nicht startet: nicht umgehen, im Chat melden; Beleg liefert dann der erste CI-Lauf (RED-Nachweis per Commit-Reihenfolge im PR: Test-Commit vor Fix-Commit läuft nicht einzeln – Alternative nach Rücksprache).

### Task 3a: p05 – Callout aus

**Files:** `tests/test-workbench-ui.js` (neuer Test „key bar CSS“), `claude-workbench/image-service/public/index.html`.

- [ ] **RED:** Test liest `index.html`, schneidet den Block `#key-bar button {…}` aus und verlangt `-webkit-touch-callout: none` und `user-select: none`. → FAIL.
- [ ] **GREEN:** `-webkit-touch-callout: none;` in `#key-bar button` ergänzen. → PASS.
- [ ] Prüfkriterium Wirkung (lokal nicht beweisbar): Langes Drücken auf eine Taste am iPhone zeigt kein Menü – im Handy-Test p04 prüfen, bis dahin „unbestätigt“.
- [ ] Commit: `fix: no iOS callout menu on a long press of a key`.

### Task 3b: p06 – Abstand zur Home-Leiste

- [ ] **RED:** gleicher CSS-Test, Block `#key-bar {…}` muss `padding-bottom: max(4px, env(safe-area-inset-bottom))` enthalten. → FAIL.
- [ ] **GREEN:** Zeile nach `padding: 4px;` in `#key-bar` einfügen. → PASS.
- [ ] Prüfkriterium: am iPhone mit Home-Leiste (HA-App) sitzt die Leiste sichtbar über der Home-Leiste – Handy-Test p04, bis dahin „unbestätigt“.
- [ ] Commit: `fix: key bar keeps clear of the iPhone home bar`.

### Task 4: p07 – gesperrte ^C-Taste ansagen

**Files:** `tests/test-workbench-ui.js` (fakeBar-Buttons: `attrs`-Map mit `getAttribute/setAttribute/removeAttribute`, `aria-label` vorbelegt), `workbench-ui.js`.

- [ ] **RED:** Test „guarded ^C announces itself as locked“: nach erstem ^C `aria-disabled === 'true'` und Label `'Ctrl+C, locked, wait a moment'`; zweiter Tipp ändert nichts; Timer ausführen → `aria-disabled` entfernt, Label wieder das ursprüngliche (`'Ctrl+C'`). → FAIL.
- [ ] **GREEN:** In `installKeyBar` beim ^C: `var label = button.getAttribute('aria-label');` vor der Änderung, `button.setAttribute('aria-disabled','true')`, `setAttribute('aria-label', LOCKED_LABEL)`; im Timer: Label zurück (bei `null` Attribut entfernen), `removeAttribute('aria-disabled')`. → PASS, ganze Datei grün.
- [ ] Browser-Test (Task 2) um die aria-Prüfung ergänzen, laufen lassen.
- [ ] Commit: `fix: screen readers hear the locked ^C key as locked`.

### Task 5: Version, CHANGELOG, p11 (3.5.0-Eintrag)

**Files:** `claude-workbench/config.yaml` (3.5.1), `README.md` (Badge), `claude-workbench/CHANGELOG.md` (oben), `docs/SESSION-STAND.md`.

- [ ] CHANGELOG-Eintrag oben:
  ```
  ## 3.5.1

  ### 🐛 Bug Fix - Key bar did nothing on iPhone
  - **Taps now reach the terminal on iPhone** (Safari and the Home Assistant app): the
    bar no longer cancels `pointerdown`, which made WebKit drop the tap. The keyboard
    still stays open (ESJavadex, ESJavadex/claude-code-ha@ab961533).
  - **No callout menu** on a long press of a key; the bar **keeps clear of the home bar**.
  - **Screen readers** hear the locked ^C key as locked during its two-second wait.

  ### 🔧 Technical - Real-browser test
  - CI taps the key bar with real touch input in Chromium and WebKit
    (ESJavadex, ESJavadex/claude-code-ha@ab961533).
  ```
- [ ] `SESSION-STAND.md`: neuer Eintrag **(17) 2026-10-12 — 3.5.0 Tastenleiste** über (16) (Stand: Spec/Plan 3.5.0, erster PR-Weg Eifel-Joe/claude-workbench#1, Merge `362e31e8`, Release v3.5.0; Offen: Handy-Test auf Prod; Fallen: pointerdown-Fehler siehe 3.5.1). Der Eintrag **(18) 3.5.1** kommt erst nach Review und CI (Task 7).
- [ ] `bash tests/test-release-metadata.sh` grün. Commit: `docs: 3.5.1 version, changelog, session note for 3.5.0`.

### Task 6: Review

- [ ] Opus-Subagent (`superpowers:requesting-code-review`), sieht nur Diff `main..HEAD` + Spec + Plan. Funde über `superpowers:receiving-code-review` prüfen, abarbeiten, je Fund Commit.
- [ ] Subagenten-Änderungen per `git show` gegen den Plan prüfen (Escapes!).

### Task 7: PR (nur nach Freigabe)

- [ ] SESSION-STAND-Eintrag (18) 3.5.1 schreiben und committen.
- [ ] PR-Text und Release-Notes im Chat zeigen, Freigabe abwarten. Dann Push, `gh pr create --repo Eifel-Joe/claude-workbench`, ccd_pr: `get_status`/`bind_pr`, CI beobachten.
- [ ] Danach Hauptsitzung und User melden; auf Merge-/Release-Freigabe warten. `.tmp/` leeren.
