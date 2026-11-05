# Spec: Tastenleiste – Korrekturen (3.5.1)

Stand: 2026-11-05 · Ziel-Version: 3.5.1 (Patch) · Status: Entwurf, wartet auf Freigabe
Basis: `main` = `362e31e8` (v3.5.0). Branch `fix/key-bar-3.5.1`.
Quelle der Fixes: ESJavadex/claude-code-ha `ab961533` („preserve WebKit touch activation in
phone key bar“), dort im echten iPhone-/WebKit-Browser nachgewiesen.

## Problem

Die Tastenleiste aus 3.5.0 hat auf dem iPhone (Safari und HA-App) zwei Fehler und drei
Mängel, und unsere Tests konnten den ersten nicht sehen, weil sie den Browser nur simulieren.

| Punkt | Befund |
|---|---|
| p01 | `installKeyBar` verhindert `pointerdown`. WebKit unterdrückt dann auch den vom Tipp erzeugten `click`; die Taste kommt nie im Terminal an. Unser Unit-Test verlangt dieses Verhalten fälschlich. |
| p03 | Kein Test läuft in einem echten Browser; der Fehler aus p01 blieb deshalb unentdeckt. |
| p05 | Langes Drücken auf eine Taste öffnet auf iOS ein Kontextmenü (Callout). |
| p06 | Die Leiste klebt auf Geräten mit Home-Leiste an deren Unterkante. |
| p07 | Während der 2-s-Sperre sagt der Bildschirmleser „Ctrl+C“, obwohl die Taste nichts sendet. |
| p11 | `docs/SESSION-STAND.md` kennt 3.5.0 nicht. |

## Entscheidungen

- **p01:** Nur `mousedown` wird verhindert (hält den Fokus im Terminal, Tastatur bleibt
  offen). `pointerdown` bleibt unberührt. Das ist die Lösung von ESJavadex. Verworfen: auf
  `touchstart` oder `pointerup` selbst senden und `click` ignorieren – größerer Eingriff,
  neue Doppelsende-Risiken, und die Vorlage ist im echten Browser belegt.
- **p03:** Playwright **1.64.1** (gleiche Version wie die Vorlage, im npm-Register vorhanden),
  Chromium **und** WebKit, Touch-Emulation (`hasTouch`, `isMobile`), echte
  `locator.tap()`-Eingaben. Eigener Ordner `tests/browser/` mit `package.json` und
  `package-lock.json`, damit der Image-Service-Lockfile unberührt bleibt. Neuer CI-Job
  `browser` auf **`ubuntu-24.04`** (`tests/test-release-metadata.sh` verbietet
  `ubuntu-latest`). Der Test lädt unser echtes `workbench-ui.js` in eine Minimalseite mit
  Fake-Terminal im iframe (kein ttyd, kein Podman). `run-tests.sh` bleibt unverändert; der
  Browser-Job ist eine eigene Stufe der CI, weil er Browser-Downloads braucht.
  `npm ci --ignore-scripts`; Browser-Download nur über `npx playwright install`.
  Verworfen: Selenium/Cypress (schwerer, WebKit nicht sinnvoll), den Test in `run-tests.sh`
  zu hängen (lokal ohne Browser rot).
- **p05:** `-webkit-touch-callout: none` auf `#key-bar button`; `user-select: none` ist dort
  schon gesetzt.
- **p06:** `#key-bar { padding-bottom: max(4px, env(safe-area-inset-bottom)); }`. Wirkt nur,
  wo iOS einen Sicherheitsabstand meldet (HA-App); sonst bleibt es bei 4 px wie heute.
  Kein `viewport-fit=cover` in dieser Runde (würde das ganze Layout verändern).
- **p07:** Während der Sperre `aria-disabled="true"` und `aria-label` =
  „Ctrl+C, locked, wait a moment“; nach Ablauf wird das **ursprüngliche** Label (vor der
  Sperre gelesen, nicht fest einprogrammiert) wiederhergestellt und `aria-disabled`
  entfernt. Das Element bleibt anklickbar (kein `disabled`), weil der Klick weiterhin
  durch den Schutz abgewiesen werden soll.
- **p11:** Eintrag zu 3.5.0 nachtragen (Tastenleiste, erster PR-Weg
  Eifel-Joe/claude-workbench#1, Merge `362e31e8`, Release v3.5.0) und am Ende Eintrag 3.5.1.

## Nicht dazugehörig

- p04 (Handy-Test auf Prod) und p02 (Tastenleiste hinter der iOS-Tastatur): nur als Hinweis,
  nicht angefasst.
- Keine Änderung an Tasten, Sequenzen, ^C-Fenster, Server-Code, Optionen.
- `viewport-fit=cover`, Landscape-Insets links/rechts.

## Credit (CHANGELOG und Release-Notes)

„Fixed: taps on the key bar did nothing on iPhone/WebKit; real-browser test
(ESJavadex, ESJavadex/claude-code-ha@ab961533).“ Eigene Funde (p05–p07) ohne Fremdcredit.

## Ende-zu-Ende-Kriterien

1. **p01/p03:** `node tests/browser/test-key-bar.mjs` gegen den Stand von `main` (3.5.0) ist
   **rot** (WebKit: Taste kommt nicht an), gegen den Fix **grün** in Chromium und WebKit;
   dasselbe in der CI, Job `browser` grün.
2. **p01 Unit:** `node --test tests/test-workbench-ui.js` – neuer Test „pointerdown nicht
   verhindert, mousedown verhindert“ rot vor, grün nach dem Fix.
3. **p05/p06:** statischer Test liest `index.html` und verlangt die Deklarationen in den
   Regeln `#key-bar button` bzw. `#key-bar` (rot vor, grün nach der Änderung). Die
   *Wirkung* (Menü bleibt aus, Abstand zur Home-Leiste) ist lokal nicht beweisbar – sie
   wird im Handy-Test p04 geprüft; bis dahin gilt sie als **unbestätigt**.
4. **p07:** Unit-Test: beim ^C wird `aria-disabled="true"` gesetzt und das Label geändert,
   nach Ablauf des Timers beides zurückgesetzt; ein zweiter, abgewiesener Tipp ändert nichts.
5. Release-Pflicht: `claude-workbench/config.yaml` und README-Badge auf 3.5.1,
   `CHANGELOG.md`-Eintrag oben, `tests/test-release-metadata.sh` grün.
