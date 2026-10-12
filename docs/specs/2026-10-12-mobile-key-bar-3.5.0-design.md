# Spec: Mobil-Tastenleiste (3.5.0)

Stand: 2026-10-12 · Ziel-Version: 3.5.0 (neues Bedienelement) · Status: Entwurf im Chat bestätigt
Quelle: `docs/FORK-SURVEY-heytcass.md` (mattbsea `ed215953`, weiting-tw `fe0a4ec9`) und
`docs/FORK-SURVEY.md` (marcjay `f6674b77`). Branch `feat/mobile-toolbar`, Basis `main` = `c503a887`.

## Problem

Am Handy fehlen auf der Bildschirmtastatur die Tasten, die Claude Code zur Bedienung braucht:
**Esc** (laufende Antwort abbrechen, Dialog schließen), **↑ ↓** (Menüs und Auswahllisten wie
`/model`, `/resume`, Rückfragen), **Shift+Tab** (Modus wechseln: normal / auto / plan) und
**Strg+C** (in der bash einen hängenden Befehl abbrechen). Das Panel hat heute nur die Knöpfe
im Header (⏩ Auto-continue, 🔗 Copy link, 📋 Copy, 🎤 Voice, 📎 Upload; `index.html:464-490`).

## Befunde

- Layout: `#container` ist ein Flex-Container in Spaltenrichtung (`index.html:28-32`), darin
  `#header` (`flex-shrink: 0`) und `#terminal-container` (`flex: 1`). `trackOnScreenKeyboard()`
  (`index.html:1117`) setzt die Höhe des Containers auf `visualViewport.height`, sobald die
  Bildschirmtastatur offen ist. Ein weiteres Kind am Ende des Containers sitzt damit direkt
  über der Tastatur.
- Senden: Seit 3.4.0 sendet Shift+Enter über `term.input(data, true)` im ttyd-iframe
  (`public/workbench-ui.js`, `installShiftEnter`). ttyd 1.7.7 bündelt `@xterm/xterm` 5.4.0;
  `input()` löst `onData` aus und geht wie getippte Tasten an ttyd. `term.modes` (mit
  `applicationCursorKeysMode`) ist ebenfalls API von xterm.js 5.
- Fokus: Ein Tipp auf einen Knopf im Eltern-Dokument nimmt dem Terminal im iframe den Fokus,
  die Bildschirmtastatur schließt sich. `preventDefault` auf `pointerdown` verhindert den
  Fokuswechsel.
- Claude Code: Esc bricht ab; Strg+C leert die Eingabe, **zweimal Strg+C beendet Claude**. Bei
  uns endet damit die tmux-Session (`bash -c 'eval "$CLAUDE_LAUNCH_CMD"'`), ttyd startet den
  Wrapper neu, die laufende Sitzung ist weg (Verlauf per `/resume` erhalten).

## Optionen

- Tasten (User: Variante A): **Esc, ↑, ↓, ↵, ⇧Tab, ^C**. Verworfen: Y/N und 1–5 (tippt die
  Bildschirmtastatur problemlos), Tab, ←/→, ^D (Shell-Komfort, kein Bedarf).
- Ort (User: Variante A): **unten über der Bildschirmtastatur, nur auf Touch-Geräten**
  (`@media (any-pointer: coarse)`). Verworfen: im Header (dort voll, weit vom Daumen) und ein
  zusätzlicher Einblend-Knopf am PC (kein Bedarf).
- ^C (User: Variante B): **behalten, mit Schutz**: ein zweites ^C innerhalb von 2 s wird nicht
  gesendet. Verworfen: ^C weglassen (in der bash nötig) und ungeschützt (Doppel-Tipp beendet
  Claude).
- Senden (wie Shift+Enter): **im Browser über `term.input`**. Verworfen: Server-Endpunkt mit
  `tmux send-keys` wie weiting-tw (zusätzliche Angriffsfläche; dort mit Shell-Injection, siehe
  Survey) und eine zweite WebSocket zu ttyd wie owines Branch `feature/mobile-terminal-controls`
  (von owine selbst zurückgenommen).

## Entscheidung

### Leiste
- Neues Element `<div id="key-bar">` als letztes Kind von `#container`, nach
  `#terminal-container`. Sechs Knöpfe mit `data-key="esc|up|down|enter|shift-tab|ctrl-c"` und
  den Beschriftungen `Esc`, `↑`, `↓`, `↵`, `⇧Tab`, `^C`; je ein `aria-label`
  („Escape“, „Arrow up“, „Arrow down“, „Enter“, „Shift+Tab“, „Ctrl+C“).
- CSS: standardmäßig `display: none`; in `@media (any-pointer: coarse)` als Zeile mit
  gleich breiten Knöpfen (`display: flex`, `flex: 1`), Höhe ca. 40 px, `flex-shrink: 0`, im
  Farbschema des Headers (`#2d2d2d`, Rand `#3d3d3d`), Schrift 15 px. Am PC bleibt der
  Terminal-Bereich unverändert groß.

### Sequenzen (`keySequence(name, term)`)
| Taste | Sequenz | im Application-Cursor-Modus |
|---|---|---|
| esc | `\x1b` | – |
| up | `\x1b[A` | `\x1bOA` |
| down | `\x1b[B` | `\x1bOB` |
| enter | `\r` | – |
| shift-tab | `\x1b[Z` | – |
| ctrl-c | `\x03` | – |

Application-Cursor-Modus = `term.modes && term.modes.applicationCursorKeysMode === true`.
Unbekannter Name → `null` (nichts senden).

### ^C-Schutz (`createCtrlCGuard(now, windowMs = 2000)`)
- Liefert eine Funktion `allow()`: `true` beim ersten ^C, danach `false` für alle weiteren ^C,
  bis 2 s seit dem letzten **gesendeten** ^C vergangen sind. `now` ist für Tests austauschbar.
- Während der Sperre zeigt der ^C-Knopf „wait“ (Klasse `key-wait`); nach 2 s wieder „^C“.

### Verdrahtung (`installKeyBar(bar, getTerm, options)`)
- Ein Listener je Knopf (bzw. per Delegation auf `bar`):
  - `pointerdown`: `preventDefault()`, damit der Fokus im Terminal bleibt und die Tastatur
    offen bleibt; ein Tipp öffnet die Tastatur auch nicht, wenn sie zu ist.
  - `click`: Sequenz bestimmen; bei ^C den Schutz fragen; dann `getTerm()` und, falls
    vorhanden mit `input`-Funktion, `term.input(seq, true)`. Fehlt `term` (Startseite, ttyd noch
    nicht da), passiert nichts und es gibt keinen Fehler.
- `getTerm` liest bei jedem Tipp `iframe.contentWindow.term` (nach einem Neuladen des iframes
  ist es ein neues Objekt); Zugriffsfehler → `null`.
- Einmal installieren (Schutz gegen doppelte Installation über ein Flag am Element).

### Ablage
- Reine Funktionen und `installKeyBar` in `image-service/public/workbench-ui.js` (dort liegen
  schon `isShiftEnter`, `installShiftEnter`, `autoContinueLabel`), exportiert für Node-Tests.
- `index.html`: Markup, CSS, ein Aufruf `ClaudeWorkbenchUi.installKeyBar(...)`.
- Keine Server-Änderung, keine Option, kein neuer Endpunkt.

### Credits
CHANGELOG und Release-Notes: „Key bar for phones (mattbsea, mattbsea's heytcass fork, commit
ed215953; weiting-tw `fe0a4ec9`; marcjay `f6674b77`)“. Im App-Code nur „mattbsea's fork,
commit ed215953“ (kein „claude-terminal“, siehe `tests/test-release-metadata.sh`).

## Doku
- `claude-workbench/DOCS.md`, Abschnitt `### Keyboard` (Zeile ~225): Absatz zur Leiste – nur
  auf Touch-Geräten, welche Tasten wofür (Esc abbrechen, ↑↓↵ Menüs, ⇧Tab Modus, ^C mit
  2-s-Schutz und warum), Tastatur bleibt offen.
- `claude-workbench/README.md`, Feature-Liste (neben „Shift+Enter“, Zeile ~30): eine Zeile
  „Key bar on phones“.
- `claude-workbench/CHANGELOG.md`: Abschnitt 3.5.0 (✨ New Feature) mit Credits.
- `docs/release-notes-3.5.0.md` im Stil von 3.4.1.
- `docs/FORK-SURVEY-heytcass.md`, Tabelle „Umsetzungsstand“: Zeile Mobil-Toolbar → ✅ 3.5.0.
- Version 3.5.0 in `claude-workbench/config.yaml` und im Badge der Repo-`README.md`.

## Ausdrücklich nicht dabei
- Y/N, Zahlen, Tab, ←/→, ^D, weitere Tasten.
- Anzeige am PC oder Option zum Ein-/Ausschalten.
- Anpassbare Tastenbelegung.
- Änderung an `DEVELOPMENT.md` (gilt für externe Beitragende).

## Tests
- `tests/test-workbench-ui.js` (`node --test`):
  - `keySequence` für alle sechs Tasten, beide Pfeil-Modi, unbekannter Name → `null`,
    `term` ohne `modes` → normale Pfeile.
  - `createCtrlCGuard`: erstes ^C erlaubt, zweites nach 1 s nicht, nach 2 s wieder erlaubt;
    Sperre misst ab dem letzten gesendeten ^C.
  - `installKeyBar` mit Fake-Elementen: `pointerdown` wird verhindert; Tipp auf ↓ sendet die
    richtige Sequenz mit `wasUserInput = true`; ohne `term` kein Fehler und kein Senden;
    doppelter ^C-Tipp sendet einmal und setzt „wait“; doppelte Installation hängt keine
    zweiten Listener an.
- `tests/test-image-service.js`: ausgelieferte Seite enthält `id="key-bar"` und alle sechs
  `data-key`-Werte.
- `tests/test-release-metadata.sh` wie gehabt (Version, CHANGELOG).

## Ende-zu-Ende-Kriterium
1. **Lokal, Browser-Fenster:** Image-Service unter `.tmp/` gestartet; Desktop-Ansicht ohne
   Leiste, Mobil-Ansicht (Touch-Emulation) mit Leiste unten, sechs gleich breite Knöpfe.
2. **HA-Test, echtes Handy:** In Claude `/model` → ↓ ↓ ↵ wählt ein anderes Modell; eine lange
   Antwort anstoßen → Esc bricht ab; ⇧Tab wechselt den Modus (Anzeige unten in Claude);
   ^C zweimal schnell → Claude läuft weiter, Knopf zeigt kurz „wait“; Bildschirmtastatur bleibt
   bei allen Tipps offen; am PC keine Leiste.
