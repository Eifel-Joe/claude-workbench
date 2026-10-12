# Sitzungsstand

## 2026-10-12 (16) — Prod 3.4.1, claude-ha geprüft, PR-Weg, offene Punkte bereinigt

### Stand
- HA-Prod 2026-10-09 21:02 auf 3.4.1 (Supervisor „successfully updated“, Health-Check alle ✓,
  keine `[auto-continue]`-Zeilen). `main` = `origin/main` = `c503a887`, alle Feature-Branches
  lokal und auf GitHub gelöscht.
- LayerTM/claude-ha geprüft (Assist-Integration „AI Agent“ mit Begleit-App LayerTM/ClaudeInHA):
  nicht mit unserer App nutzbar – `engines.py` erkennt nur Slugs `*_claude-code`,
  `config_flow.py` bricht sonst mit `unsupported_addon` ab, und die Integration braucht den
  Prompt-Server aus „ha-agent-core“ (`/api/prompt`, `/api/status`, `/api/usage`,
  `/api/account_limits`, Discovery, Option `api_token`). User macht Assist anders.
- Offene Punkte bereinigt: verworfen mit Begründung in `docs/FORK-SURVEY-heytcass.md`
  („Umsetzungsstand“); offen bleiben Mobil-Toolbar (als Nächstes), `map: share/addons` und
  ripgrep-Prüfung bei Bedarf, Auto-Continue-Bremse nur bei Nutzung.

### Verworfen
- claude-ha in unsere App einbauen (Slug-Wechsel = neue App, ha-agent-core als Dauer-Abhängigkeit).

### Fallen
- Arbeitsweise neu (User 2026-10-12): eigene Änderungen über GitHub-PR (Text vorher freigeben,
  CI am PR, Merge über GitHub). `DEVELOPMENT.md` gilt für externe Beitragende und bleibt
  unverändert (Podman, `/tmp`).

### Nächste Schritte
- Mobil-Toolbar Esc/Pfeile: Ablauf nach Skill `task-loop` (Spec, Plan, je mit Freigabe).

### Empfohlene Skills
- `task-loop`, `superpowers:brainstorming`.

## 2026-10-09 (15) — 3.4.0/3.4.1 umgesetzt, HA-Test bestanden, v3.4.1 veröffentlicht

### Stand
- Plan `docs/plans/2026-10-09-shift-enter-auto-continue-3.4.0.md` Task 1–10 umgesetzt
  (Subagenten je Task, zwei Code-Reviews mit Nachträgen in Spec und Plan). Merge 3.4.0
  `371b8d45`, Korrektur 3.4.1 Merge `21b8473e` = `origin/main`. CI grün: Branch-Läufe
  37940380829 (3.4.0) und 37969861639 (3.4.1, `ca7d4dae`, „version 3.4.1“, 45 Tests).
- HA-Test 3.4.1 (MCP-Update), Health-Check „Claude CLI runs: 2.1.295 ✓“. E2E laut Spec
  bestanden: Shift+Enter, Knopf an/aus, „limit detected … will send at 19:51“ → „sent
  "continue" to pane %0“ 19:51:08 (3.4.0) und 20:04:27 (3.4.1), Gegenprobe „switched off“.
- 3.4.1 = Uhrzeit mehr als 12 h voraus gilt als gerade vergangen (gefunden auf HA-Test:
  „Resets at 19:46“ um 19:46:07 erkannt → Plan für den nächsten Tag). Live geprüft:
  Meldung mit Uhrzeit 3 min in der Vergangenheit, erkannt 20:20:27, gesendet 20:21:27.
- HA-Prod noch auf 3.3.0 (Update durch den User). 3.4.0 bekommt kein eigenes Release;
  Notizen in `docs/release-notes-3.4.1.md`.

### Verworfen
- Neues Image derselben Version per `rebuild`: geht nur bei lokalen Apps, nicht aus dem
  GitHub-Store → Korrektur als 3.4.1.

### Fallen
- `git add a b nicht-vorhanden 2>/dev/null` bricht komplett ab und verschluckt den Grund:
  Commit `b3b11353` enthielt nur die Umbenennung der Release-Notes, der Code kam erst mit
  `ca7d4dae`. Nach jedem Commit `git show --stat` lesen.
- Windows-`netstat` meldet „ABHÖREN“, nicht „LISTENING“; Hintergrund-Server mit TaskStop
  beenden.
- Test-Server ohne `AUTO_CONTINUE_DIR` schrieben nach `D:\run` (behoben, gelöscht).
- Claude kommentiert `!echo`-Limitmeldungen („not a real notice“) – stört den Test nicht.
- `sed … | grep -q` unter `pipefail` ist ein Wettlauf (SIGPIPE → Exit 141): CI 37970222395
  auf `main` rot in `test-npm-cache.sh`. Behoben in `f32f935f` (`grep … > /dev/null`), auch
  in `test-image-retention.sh` und `test-startup-order.sh`. Neue Tests so nicht schreiben.
- Release v3.4.1 veröffentlicht (Tag auf `fc58583c`), CI `main` grün (37973723650).

### Nächste Schritte
- HA-Prod-Update auf 3.4.1 durch den User, danach Supervisor- und App-Log prüfen.
- Zurückgestellt (Memory Folgepunkt 24): Bremse nach erfolglosen Versuchen / Wochenlimit.

### Empfohlene Skills
- `superpowers:verification-before-completion` beim Prüfen des Prod-Updates.

## 2026-10-09 (14) — Spec + Plan 3.4.0 (Shift+Enter, Auto-Continue)

### Stand
- `main` = `origin/main` = `5e967c62`, CI 37923584334 grün.
- Branch `feat/auto-continue-3.4.0` (nur lokal): Spec
  `docs/specs/2026-10-09-shift-enter-auto-continue-3.4.0-design.md` und Plan
  `docs/plans/2026-10-09-shift-enter-auto-continue-3.4.0.md` (Commits `7f1ec367`,
  `5a7f2c72`), beide vom User freigegeben. Noch kein Produktionscode, alle
  Checkboxen offen.
- User-Entscheidungen: Auto-Continue mit Option als Anfangszustand **plus**
  Laufzeit-Schalter (Befehl `auto-continue`) **plus** Knopf im Panel-Header.
- Befund HA-Test (User, tmux/ps in der App): `pane_current_command` meldet für
  die Claude-Pane `bash` (Claude PID 354 in der Prozessgruppe von `bash -c`
  348); deshalb Filter über `tpgid` aus `/proc` (Spec, „Befunde“).
- ttyd 1.7.7 bündelt `@xterm/xterm` 5.4.0 mit `term.input()` (geprüft an
  `html/yarn.lock` und den Typings auf unpkg).

### Verworfen
- `pane_current_command` als Claude-Filter (siehe oben).
- mattbseas Zeit-Toleranz/12-h-Stale-Logik: passt nicht zu 30-s-Abfragen des
  Bildschirms; ersetzt durch Text-Signatur (Spec).
- JSON-Statusdatei für den Befehl (jq lokal nicht vorhanden) → Klartext.

### Fallen
- Lokal kein tmux und kein jq: alles gegen Attrappen testen.
- Ein App-Neustart beendet die tmux-Session (Container-Neustart) – meine
  gegenteilige Aussage im Chat war falsch.
- Lokaler Branch `feat/safer-defaults-3.3.0` ist ein Rest (bereits gemergt).

### Nächste Schritte
- Plan Task 1–11 umsetzen (frische Sitzung), Start mit Task 1.

### Empfohlene Skills
- `superpowers:subagent-driven-development` bzw. `superpowers:executing-plans`,
  pro Task `superpowers:test-driven-development`, am Ende
  `superpowers:requesting-code-review`.

## 2026-10-09 (13) — Release 3.3.0 (claude-doctor, tmux, Sicherheits-Doku, Runner)

### Stand
- Plan `docs/plans/2026-10-09-safer-defaults-3.3.0.md` komplett umgesetzt
  (TDD, ein Commit je Task). Merge `f09a0afd`, Release-Commit `ad5c4db3`,
  Tag und GitHub-Release `v3.3.0` „3.3.0 — claude-doctor, own tmux settings,
  honest security notes“ (Latest). CI grün: Branch 37920646911, `main`
  37920921642 und 37921617456; alle Jobs auf Runner-Image `ubuntu-24.04`,
  Image-Service unter Linux 15/0.
- Code-Review per Subagent: Health-Check lief vor `setup_persistent_claude`
  (prüfte womöglich eine andere Binary) → jetzt danach; Schwester-Pfad
  node/npm (`local v=$(…)` verschluckte den Status) → gemeinsamer Helfer
  `run_version_check`/`report_version_check`, stdin aus `/dev/null`
  (Gegenprobe rot); Nachtrag in der Spec.
- HA-Test 3.3.0 (MCP-Update 13:01): Log „Claude CLI runs: 2.1.295 (Claude
  Code) ✓“ nach dem Override; User: `claude-doctor` im Terminal liefert
  dieselben Checks; `~/.tmux.conf.local` mit `status-bg colour22` färbt die
  Leiste grün (tmux expandiert `~`).
- HA-Prod 3.3.0 (User, 13:22): Supervisor „successfully updated“, App-Log
  sauber, Health-Check alle ✓.

### Verworfen
- `timeout -k 2` im Health-Check (kein Bedarf, coreutils-timeout beendet die
  Prozessgruppe).

### Fallen
- Store auf HA-Prod kannte 3.3.0 erst nach „Nach Updates suchen“
  (`version_latest` blieb 3.2.0).
- Ein Test „stdin ist kein Terminal“ mit `[ -t 0 ]` wird im Bash-Tool nie rot
  (kein TTY) – stattdessen prüfen, ob die Kind-Binary Eingaben lesen kann.
- HA-Test und HA-Prod zeigen Claude unterschiedlich (Statuszeile, 1M-Kontext,
  Eingabe unten auf Prod): Einstellungen in `/data/home/.claude/` je
  Installation, nicht die App. User: egal.

### Nächste Schritte
- Offene Punkte aus `docs/FORK-SURVEY-heytcass.md` („Umsetzungsstand“) und
  Memory: Boot-Smoke-Test in der CI (heytcass `d50e6c0`), `claude_extra_args`,
  Mobil-Toolbar, `working_directory`, `permissions.deny`, Log-Rauschen
  „Proxy error“ beim Start, Auth-Helper-Pipe-Frage, „erst prüfen“-Punkte.

### Empfohlene Skills
- `task-loop` für den nächsten Punkt.

## 2026-10-09 (12) — Spec + Plan 3.3.0 (CI-Runner, claude-doctor, tmux, Sicherheits-Doku)

### Stand
- `main` = `origin/main` = `d2db73b9`, CI 37909804599 grün.
- Branch `feat/safer-defaults-3.3.0` (nur lokal): Spec
  `docs/specs/2026-10-09-safer-defaults-3.3.0-design.md` (`44a07dd4`) und Plan
  `docs/plans/2026-10-09-safer-defaults-3.3.0.md` (`627474e2`), beide vom User
  freigegeben. Noch kein Produktionscode, alle Checkboxen offen.
- Bündel aus den offenen Punkten: 4c (Runner `ubuntu-24.04`, Frist 2026-10-19),
  2b (Health-Check startet `claude --version`, `claude-doctor`), 2c
  (Sicherheits-Doku), 1g (no-cache), 1b (`~/.tmux.conf.local`).
- Aussage „jeder angemeldete HA-User kann das Panel öffnen“ im Code geprüft
  (Core `dev` @ `bc163ce175`, Supervisor `main` @ `2760df9b88`; Details in der Spec).

### Verworfen
- Health-Check-Gegentest mit Nicht-Admin-User auf HA-Test (User wählte
  Code-Prüfung statt Live-Test).

### Fallen
- `SESSION-STAND.md`: „Abschnitt 11“ ist `## 2026-10-09 (11) …` oben in der
  Datei, nicht eine Überschrift `## 11`.
- README behauptete Zugriff auf `/addons`; gemappt ist `all_app_configs`
  (`/addon_configs`) – im Plan Task 6 mit korrigiert.

### Nächste Schritte
- Plan Task 1–8 umsetzen (frische Sitzung), Start mit Task 1.

### Empfohlene Skills
- `superpowers:executing-plans` bzw. `superpowers:subagent-driven-development`,
  pro Task `superpowers:test-driven-development`, am Ende
  `superpowers:requesting-code-review`.

## 2026-10-09 (11) — Release 3.2.0 (Fork-Fixes, Bilder-Aufräumen)

### Stand
- Plan `docs/plans/2026-10-09-fork-fixes-3.2.0.md` komplett umgesetzt (TDD,
  RED/GREEN-Commits). Merge `7aa35ca0`, Release-Titel-Fix `cadd1d38`, Tag und
  GitHub-Release `v3.2.0` „3.2.0 — Cleaner backups, a panel that comes up
  first“. CI grün: Branch 37907770615, `main` 37908298432 und 37909296560
  (Image-Service-Suite unter Linux 14/0 – der ECONNRESET-Fehlschlag ist
  Windows-only).
- Code-Review per Subagent: I1 (Health-Check-Netzproben verzögerten das
  Panel bis ~45 s offline) → Health-Check läuft jetzt nach dem Bild-Service;
  M1 Obergrenze 3650 (BusyBox-find 32 Bit); M2 Kopieren/Aufräumen brechen den
  Start nicht mehr ab; Texte präzisiert.
- HA-Test 3.2.0 (Update per MCP 11:00): „Removed 1 uploaded image(s) older
  than 30 day(s)“, Bild-Service healthy vor Health-Check und Claude-Update,
  Health-Check-Zusammenfassung, Skills „up to date“; User: `pasted-old.png`
  weg, `pasted-new.png` da, `SKILL-OK`, neues Bild
  `pasted-1791536787576-150d9996.png`.
- HA-Prod 3.2.0 (User, 11:09): Logs per MCP sauber, keine alten Bilder.
- `docs/FORK-SURVEY-heytcass.md` (vier Teilberichte + Umsetzungsstand);
  `refs/hk/*` gelöscht, `.tmp/` geleert.

### Verworfen
- Credit-Kommentare mit Repo-Namen `owine/claude-terminal-home-assistant`
  im App-Code: `tests/test-release-metadata.sh` verbietet „claude-terminal“
  dort → „owine's fork, PR #…“; voller Name nur in CHANGELOG/Release-Notes.

### Fallen
- Tests für „Funktion darf den Start nicht abbrechen“ nie mit `|| fail`
  aufrufen: das schaltet errexit in der Funktion ab und verdeckt den Abbruch.
- GNU-find (Git Bash, CI) zeigt den 32-Bit-Überlauf von BusyBox-find nicht;
  Ablehnung mit Warnung prüfen statt „nichts gelöscht“.
- `gh release view --json isLatest` gibt es nicht (Exit 1 nach erfolgreichem
  Release) – `gh release list` zeigt „Latest“.
- unbestätigt: Startseite „Claude Workbench is starting…“ live nicht gesehen –
  ein offener Terminal-Tab verbindet sich selbst neu; erscheint nur bei
  frischem Laden während des Starts (automatisch getestet).

### Nächste Schritte
- Offene Ideen aus `docs/FORK-SURVEY-heytcass.md` (Umsetzungsstand) und
  heytcass-Reste (Boot-Smoke-Test in der CI, Health-Check mit
  `claude --version`, Sicherheits-Doku) – neue Spec.
- Log-Rauschen „Proxy error … ECONNREFUSED“ während des Starts dämpfen.
- Offene Frage: Auth-Helper `echo code | claude` – funktioniert der Login so?
- CI: `ubuntu-latest` wechselt ab 2026-10-19 auf Ubuntu 26.

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.

## 2026-10-09 (10) — heytcass-Forks gesichtet, Spec + Plan 3.2.0

### Stand
- HA-Prod 09:19 auf 3.1.3 (User), Supervisor- und App-Log per MCP geprüft
  („Removed the old npm cache …“ einmal, keine Fehler). Backup-Vergleich
  belegt: „Claude Workbench 3.1.2“ 553.666.560 B → manuelles App-Backup
  „Claude Workbench Test“ (3.1.3) 443.412.480 B, −110 MB.
- Remote- und lokaler Branch `fix/backup-cache-auth-api` gelöscht.
- Alle 104 Forks von heytcass/home-assistant-addons gesichtet: 58 mit eigenen
  Commits, 1.092 am Claude-Add-on, CI oder Tests. Berichte der vier
  Subagenten in `.tmp/hk-report-1..4.md` (gitignored, NICHT löschen, bevor
  der User über die Übernahme ins Repo entschieden hat — Plan Task 9 Step 9).
  Fork-Branches liegen als `refs/hk/<owner>/<branch>` im Repo (166 Refs).
- Branch `feat/fork-fixes-3.2.0` (nur lokal): Spec
  `docs/specs/2026-10-09-fork-fixes-3.2.0-design.md` und Plan
  `docs/plans/2026-10-09-fork-fixes-3.2.0.md`, beide vom User freigegeben.
  Noch kein Produktionscode.

### Verworfen
- Patch-ID je Commit in einer Schleife (zwei Git-Prozesse pro Commit, über
  20 min) → ein `git log -p --stdin | git patch-id` für alle Commits, 38 s.

### Fallen
- `gh api …/compare` scheitert bei Forks mit abweichendem Repo-Namen
  (cabinlab, evandepol, petterl/repo) → per Fetch einbezogen.
- Subagenten-Befunde über unseren Code vor dem Weitergeben selbst prüfen
  (alle bestätigt: `health-check.sh:158-163`, `run.sh:759/811-815`,
  `server.js:42`, `run.sh:179-185`, `claude-auth-helper.sh:36`,
  `persist-install:104-106`).

### Nächste Schritte
- Plan `docs/plans/2026-10-09-fork-fixes-3.2.0.md` ab Task 1 umsetzen, auf
  Branch `feat/fork-fixes-3.2.0`.
- Danach (eigene Spec): weitere Fork-Ideen (`claude_extra_args`,
  `~/.tmux.conf.local`, Mobil-Toolbar, `working_directory`, `map: share`,
  `permissions.deny`, Shift+Enter, ripgrep prüfen) und heytcass-Reste.

### Empfohlene Skills
- `superpowers:subagent-driven-development` oder `superpowers:executing-plans`,
  pro Task `superpowers:test-driven-development`; `code-doku` für Kommentare.

## 2026-10-09 (9) — Release 3.1.3 (aus dem heytcass-Original)

### Stand
- heytcass/home-assistant-addons gesichtet (Remote `heytcass`, 71 Commits
  seit der Abspaltung `fa10282`); Ergebnis als Folgepunkt 20 im Memory
  `claude-code-ha-followups`.
- Spec `docs/specs/2026-10-09-backup-cache-auth-api-design.md`, Plan
  `docs/plans/2026-10-09-backup-cache-auth-api.md`. Auf `main` (`b42963a`),
  Tag/Release `v3.1.3`. CI grün: Branch 37894699879, `main` 37895096647
  (inkl. neuer Suite `tests/test-npm-cache.sh`).
- `auth_api` entfernt (Metadaten-Test verhindert Rückkehr); npm-Cache per
  `setup_npm_cache` nach `/tmp/npm-cache`, alter `/data/home/.npm` wird beim
  Start einmal gelöscht; Profil exportiert dieselbe Variable. Credits an
  heytcass in CHANGELOG und Release-Notes.
- Entscheidung A (Cache nach `/tmp`) statt B (`backup_exclude`) nach Messung
  auf HA-Test: Update mit leerem Cache 19,1 s / 113 MB, mit warmem 2,9 s.
- HA-Test 3.1.3 (Update per MCP 08:46): Log „Removed the old npm cache …“
  einmal, Update beim Start 08:46:34–08:46:54, `auth_api: false`, healthy.
  User: `/data/home/.npm` weg, `npm_config_cache=/tmp/npm-cache`,
  `/tmp/npm-cache` 113 MB; Picker-Punkt 7 „changed 2 packages in 3s“
  (erbt den Cache über tmux).
- Offen: HA-Prod-Update (User) und Backup-Vergleich dort (siehe Plan,
  Task 4 Step 6). Das MCP-Update auf Test legte kein automatisches Backup an.

### Verworfen
- `backup_exclude` (Variante B), `npm_config_cache` zusätzlich im Picker
  setzen, `npm cache clean`.

### Fallen
- `"$B\\$cache"` in Bash ergab den Ordner `npmprobe$cache` — Pfade für
  Windows-npm mit Vorwärts-Schrägstrichen (`D:/…`) bauen.
- Foreground-`sleep` ist im Bash-Tool gesperrt; Warten per
  `run_in_background`.
- MCP `ha_manage_backup` create macht nur Voll-Backups, kein Teil-Backup
  einer App.

### Nächste Schritte
- HA-Prod auf 3.1.3 (User), danach Logs per MCP; später Teil-Backup der App
  und Größenvergleich mit „Claude Workbench 3.1.2“.
- Remote-Branch `fix/backup-cache-auth-api` löschen (Freigabe).
- Weitere heytcass-Punkte (Folgepunkt 20): Boot-Smoke-Test in der CI,
  Health-Check mit `claude --version` und CPU-Gate, Sicherheits-Doku.

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.

## 2026-10-07 (8) — Release 3.1.2 (Picker-Label) und Fork-🟡-Entscheidungen

### Stand
- Spec `docs/specs/2026-10-07-picker-update-label-design.md`, Plan
  `docs/plans/2026-10-07-picker-update-label.md`. Auf `main` (`7a810b3`),
  Tag/Release `v3.1.2`. CI grün: Branch 37625705821, `main` 37626581553.
- `update_menu_label` sagt bei unbekannter installierter Version nicht mehr
  „up to date“ (CPU ohne x86-64-v2, fehlende Binary). Review fand den
  Spiegelfall „Fehlertext statt Version“ (`(Error:, up to date)`), per Test
  belegt und in `get_installed_version` behoben (`5ef3dea`).
- HA-Test 3.1.2 (Update per MCP 15:14): Log „CPU meets …“, „All checks
  passed“, Image-Service healthy; Picker (User-Screenshot) zeigt
  „Update Claude Code (2.1.292, up to date)“, Update über Punkt 7 läuft,
  Claude startet. CPU-Zweig nur per Unit-Test (HA-Test auf `host`).
- HA-Prod 3.1.2 (Update durch User, 15:20:08): Backup vorher, Log „CPU
  meets …“, Python-Pakete da, Image-Service healthy, keine neuen Warnungen.
- Fork-Survey-🟡 alle zurückgestellt (Begründungen im Memory
  `claude-code-ha-followups`): scholarnemo API-Optionen, marcjay HA-MCP
  (SSH/Telegram verworfen), Moulbi Paket-Persistenz (kleine Variante
  besprochen, offen: Alt-Kopien in `/data/packages/bin|lib`; `hassio_role`
  nicht entschieden). Neuer Folgepunkt 19: neue Fork-Runde.

### Verworfen
- Update-Menüpunkt auf nicht unterstützten CPUs ausblenden (Menünummern),
  installierte Version aus `package.json` lesen (Zusatzpfad ohne Nutzen).

### Fallen
- Review-Minor-Befunde nicht übernommen: leere `--version`-Ausgabe mit
  Exit 0 lässt Versionszeile/Update-Meldung leer (schon auf `main` so);
  kein Test für „latest unknown“.
- CI-Hinweis: `ubuntu-latest` wird ab 2026-10-19 Ubuntu 26 (Probe in 2.3.3
  war grün).

### Nächste Schritte
- 3.1.3 aus dem heytcass-Original (Remote `heytcass`; Sichtung als
  Folgepunkt 20 im Memory `claude-code-ha-followups`): `auth_api` entfernen,
  npm-Cache aus den Backups. Branch `fix/backup-cache-auth-api`. Vor der Spec:
  npm-Messung im Container auf HA-Test (Befehl im Memory), dann Variante A
  (Cache nach `/tmp`) oder B (`backup_exclude`) entscheiden. Credits an
  heytcass (Memory `credit-adopted-ideas`).
- Danach: Boot-Smoke-Test in der CI, Health-Check mit `claude --version`,
  Sicherheits-Doku (alles Folgepunkt 20).

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.

## 2026-10-07 (7) — Release 3.1.1 (Folgepunkt 3: CPU ohne x86-64-v2)

### Stand
- Spec `docs/specs/2026-10-07-cpu-x86-64-v2-check-design.md`, Plan
  `docs/plans/2026-10-07-cpu-x86-64-v2-check.md`. Auf `main` (`b477063`),
  Tag/Release `v3.1.1`. CI grün: Branch 37611402653, `main` 37612034914.
- Belegt (HA-Test, Proxmox-CPU-Typ umgestellt): Claude Code 2.1.292 läuft auf
  `x86-64-v2-AES` (popcnt, sse4_2, kein avx/avx2), hängt auf `kvm64`.
  Anforderung ist x86-64-v2, nicht AVX2. Keine baseline-Binary bei
  Anthropic; npm-Paket ist Wrapper um dieselbe Binary.
- `scripts/cpu-check.sh`, eingebunden in Health-Check, Autostart,
  `setup_persistent_claude` und Session-Picker (alle Claude-Aufrufe inkl.
  Auth-Helper und Versionsanzeige). Review fand Auth-Helper und
  Persistent-Smoke-Test, beide nachgezogen.
- HA-Test 3.1.1: `kvm64` → Log-Warnungen, Picker mit „not supported on this
  CPU“, Menüpunkt 1 erklärt, Bash/`ha`/`gh` laufen; `host` → „CPU meets
  Claude Code's requirements ✓“, Claude startet (User). HA-Test steht jetzt
  auf CPU-Typ `host`.
- HA-Prod 3.1.1 (Update durch User, 13:15:41): Log „CPU meets Claude Code's
  requirements ✓“, Image-Service healthy, keine CPU-Warnung.

### Verworfen
- Prüfung auf AVX2 (belegt falsch), `install.sh` im Dockerfile überspringen
  (npm liefert dieselbe Binary), nur Log-Warnung (Panel hinge weiter).

### Fallen
- GitHub startete für einen Push zwei CI-Läufe; `cancel-in-progress` brach
  den ersten ab (`cancelled`, nicht rot) — auf den zweiten Lauf schauen.
- Session-Picker ist nicht `set -u`-fest; im Test `set +u` vor dem Sourcen.
- Menünummer der Bash ist 7 oder 8 (je nach `use_persistent_claude`) — in
  Anleitungen den Namen „Drop to bash shell“ nennen.
- `tests/test-production-run.sh` scheitert lokal unter Windows (auch auf
  `main`), in der CI grün.

### Nächste Schritte
- Kleinpunkt: Picker-Menüpunkt „Update Claude Code“ zeigt auf CPUs ohne
  x86-64-v2 „(<neueste>, up to date)“, weil die installierte Version nicht
  abgefragt wird — irreführend, harmlos.
- Folgepunkt 7 (Fork-Survey 🟡) im Memory `claude-code-ha-followups`.

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.

## 2026-10-07 (6) — Release 3.1.0 (Folgepunkte 15, 17, 18; Issues)

### Stand
- Spec `docs/specs/2026-10-07-proxy-map-translations-design.md`, Plan
  `docs/plans/2026-10-07-proxy-map-translations.md`. Auf `main` (`bbeba7b`),
  Tag/Release `v3.1.0`. CI grün: Branch 37607065722, `main` 37607502832
  (Image-Service-Suite unter Node 22 `# pass 13`, inkl. „keine Warnung“).
- `http-proxy-middleware` 4.2 (statt 2.0.10, `http-proxy` raus, `httpxy`),
  `engines.node >=22.15`; Review fand einen echten Absturz (502 nach
  gesendeten Headern → `ERR_HTTP_HEADERS_SENT`), per Test reproduziert und
  behoben (`2429c6b`).
- `map`: `homeassistant_config` mit `path: /config`; Übersetzungen
  `claude-workbench/translations/{en,de}.yaml` für alle 9 Optionen.
- Version 3.1.0 statt 3.0.1 (neues Feature → Minor, Review-Hinweis, User).
- GitHub: Issues eingeschaltet, Vorlagen `.github/ISSUE_TEMPLATE/`
  (Bug, Feature, Verweis auf anthropics/claude-code); Auswahlseite vom User
  bestätigt.
- HA-Test 3.1.0: keine `map`-Warnung seit Store-Reload 12:28, kein `DEP0060`
  nach Panel-Nutzung (3.0.0 hatte es um 11:36:23), `/config` ok, deutsche
  Erklärungen sichtbar (User).
- HA-Prod 3.1.0 (Update durch User, 12:32:04): kein `DEP0060` nach
  Panel-Nutzung, keine `map`-Warnung für Claude Workbench beim Store-Reload
  12:31:32 (nur noch für fremde Apps Ism7MQTT, ESPHome-Legacy). Alte
  Repository-Einträge (`6ef0b4d0`, ESJavadex, heytcass) vom User entfernt.

### Verworfen
- `http-proxy` per npm-`overrides` auf `http-proxy-3` umbiegen (Alias-Trick,
  bleibt auf hpm 2); `--no-deprecation` (versteckt nur).
- `homeassistant_config` ohne `path` (Mount wanderte nach `/homeassistant`).

### Fallen
- `git checkout -- .` bei einer Gegenprobe setzte auch noch nicht committete
  Test-Änderungen zurück; Gegenproben nur auf einzelnen Dateien rückgängig
  machen oder vorher committen.
- Heredoc + Python-Regex mit Backslashes → wieder verstümmelt; Edit-Tool nehmen.
- `node --test tests/test-image-service.js` unter Windows: alle Tests pass,
  aber ein Datei-Fehlschlag durch nachlaufendes `ECONNRESET` (auch auf altem
  `main`); CI grün.
- DEP0060 erscheint erst beim ersten Proxy-Aufruf (Panel öffnen), nicht beim
  Start — Log-Prüfung erst nach Panel-Nutzung aussagekräftig.
- npm-Cache per `npm_config_cache` nach `.tmp/`.

### Nächste Schritte
- Folgepunkte im Memory `claude-code-ha-followups`: 3 (CPU ohne AVX2),
  7 (Fork-Survey 🟡).

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.

## 2026-10-07 (5) — Release 3.0.0: Claude Workbench (umgesetzt, Test + Prod)

### Stand
- Plan `docs/plans/2026-10-07-claude-workbench-rename.md` umgesetzt (Tasks
  1–13 abgehakt), gemergt nach `main` (`f80fd7f`), Tag/Release `v3.0.0`.
- GitHub-Repo umbenannt: `Eifel-Joe/claude-workbench` (alte URL → 301);
  lokales `origin` umgestellt. Das Repo ist bei GitHub kein Fork
  (`parent` leer) — Herkunft steht in README/DOCS/LICENSE.
- CI grün: Branch-Lauf 37600460758, `main` 37601028703 (Build aus
  `context: claude-workbench`, amd64 + aarch64).
- Code-Review per Subagent: wichtiger Befund umgesetzt (`37564be`): der alte
  Repository-Eintrag listet Workbench per Weiterleitung als
  `6ef0b4d0_claude_workbench`; Anleitung nennt `0e003122_claude_workbench`
  (Hash = sha1 der kleingeschriebenen Repo-URL, Metadaten-Test rechnet nach).
- HA-Test: `0e003122_claude_workbench` 3.0.0 installiert, Übernahme aus
  `6ef0b4d0_claude_terminal_pro` (alle 6 Punkte ok, Start ohne Login, vom
  User bestätigt), alte App deinstalliert und alter Repository-Eintrag
  entfernt (per MCP, Supervisor-Log 11:38:53/54). Store: Workbench einmal.
- HA-Prod (vom User): `0e003122_claude_workbench` 3.0.0 installiert, Übernahme
  11:49–11:50 alle Punkte ok inkl. „Python packages installed!“, Start ohne
  Login (User); `persist-install --list` zeigt fastmcp 4.0.11, pdfplumber
  0.11.10, pypdf 6.19.0, websocket-client 1.9.2 (166 MB). Alte App vom User
  deinstalliert (Supervisor-Log 11:52:27). Offen (User): alten
  Repository-Eintrag `6ef0b4d0` (…/claude-code-ha) auf Prod entfernen.

### Verworfen
- Siehe Abschnitt (4); zusätzlich: Übersetzungen und `map: config` nicht mehr
  in 3.0.0 aufgenommen (neue Folgepunkte).

### Fallen
- Store auf Prod hatte den alten Eintrag noch nicht neu eingelesen → Workbench
  erschien dort nur einmal (richtiger Eintrag `0e003122`).
- `gh release view --json isLatest` gibt es nicht (`gh release list` zeigt
  „Latest“).
- Image-Service-Tests lokal unter Windows: 9/9 pass, aber Exit 1 durch
  nachlaufendes `ECONNRESET` (auch auf altem `main`); CI grün.
- Mit `PATH="/c/WINDOWS/system32:$PATH"` greift Windows-`timeout` statt GNU.

### Nächste Schritte
- Neue Folgepunkte im Memory `claude-code-ha-followups`: 17 (Optionen ohne
  Erklärung — `claude-workbench/translations/en.yaml`/`de.yaml` fehlen),
  18 (Supervisor-Warnung „deprecated map option 'config'; use
  'homeassistant_config'“). Daneben 3, 7, 15.

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.

## 2026-10-07 (4) — Umbenennung in Claude Workbench: Spec + Plan

### Stand
- GitHub aufgeräumt: `main` gepusht (`fca0da7`), 9 gemergte Remote-Branches
  und 10 lokale gelöscht; `git ls-remote --heads origin` → nur `main`.
- Spec `docs/specs/2026-10-07-claude-workbench-rename-design.md` und Plan
  `docs/plans/2026-10-07-claude-workbench-rename.md` vom User freigegeben,
  auf Branch `feat/claude-workbench` (lokal, nicht gepusht; `bcfe8c8`,
  `4bd4928`). Noch keine Code-Änderung.
- Bestätigtes Logo: `docs/plans/2026-10-07-claude-workbench-logo-preview.png`.

### Verworfen
- Nur Anzeigename ändern (User will eigenen Slug), Übergangsversion der alten
  App, nachgezeichneter Funke (User wählte das Original), Ordner behalten.

### Fallen
- Nach dem Merge zeigt der alte HA-Repository-Eintrag per GitHub-Weiterleitung
  schon Claude Workbench → zweimal im Store bis zum Entfernen des alten
  Eintrags (erst möglich nach Deinstallation der alten App).
- Push meldet `git: 'credential-manager-core' is not a git command` —
  harmlos, Push klappt trotzdem.

### Nächste Schritte
- Plan ab Task 1 umsetzen (`docs/plans/2026-10-07-claude-workbench-rename.md`).
- Danach Folgepunkte im Memory `claude-code-ha-followups` (3, 7, 15).

### Empfohlene Skills
- `superpowers:executing-plans` oder `superpowers:subagent-driven-development`,
  pro Task `superpowers:test-driven-development`.

## 2026-10-07 (3) — Release 2.3.4 (Folgepunkte 9, 13, 14; Prod nachgezogen)

### Stand
- Spec `docs/specs/2026-10-07-github-redirect-cleanup-design.md`, Plan
  `docs/plans/2026-10-07-github-redirect-cleanup.md` (abgehakt). Auf `main`
  (`8c51581`), Tag/Release `v2.3.4`.
- CI grün: Branch-Lauf 37592072331, `main` 37592623079. Build-Log beider
  Architekturen: „Installing Home Assistant CLI 5.5.0“, „Installing GitHub CLI
  v2.102.0“ — ohne `api.github.com`.
- HA-Test auf 2.3.4 (`state: started`, Log fehlerfrei); vom User im
  App-Terminal: `persist-install --ha-cli --force` → v5.5.0, „ha runs ✓“;
  Kopie danach laut User per `rm` entfernt (Image-CLI gilt wieder).
- HA-Prod: vom User von 2.3.0 auf 2.3.3 und dann auf 2.3.4 aktualisiert; per
  MCP geprüft (Backup vor Update, `state: started`, Log fehlerfrei). Alte App
  `789f524e` ist deinstalliert.

### Verworfen
- GitHub-Token beim Build (Supervisor baut auf den Geräten ohne Token),
  Versions-Pinning (widerspricht „neueste Version“), `releases/latest/download`
  ohne Version (geht nicht für `gh`, `.ha-version` ginge verloren).
- Mac-Clipboard-Monitor auf Ingress umbauen (Einfügen im Terminal ersetzt ihn).

### Fallen
- Echtes `curl -f -w '%{url_effective}'` gibt die URL auch bei Exit 22 aus —
  der `|| resolved_url=""` in `persist-install` ist nötig; das Fake-`curl` im
  Test bildet das nach (Gegenprobe ohne Schutz fiel durch).
- Node 24 lokal meldet `ℹ pass`/`ℹ fail` statt `# pass`.
- Prod-Update per MCP blockiert der Auto-Mode-Klassifizierer („Production
  Deploy“) — der User startet Prod-Updates selbst.
- Docker-Cache: ein Versions-Bump ohne geänderte `RUN`-Zeilen baut in Sekunden
  aus dem Cache; HA-CLI/gh bleiben dann auf dem Stand des älteren Builds.

### Nächste Schritte
- Folgepunkte im Memory `claude-code-ha-followups`: 3 (CPU ohne AVX2),
  7 (Fork-Survey 🟡), 15 (Node-Warnung DEP0060 im Image-Service).
- Remote-Branch `fix/github-redirect-cleanup` kann gelöscht werden.

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.

## 2026-10-07 (2) — Release 2.3.3 (Folgepunkte 10–12, persist-install --ha-cli)

### Stand
- Spec `docs/specs/2026-10-07-cleanup-32bit-ci-design.md`, Plan
  `docs/plans/2026-10-07-cleanup-32bit-ci.md` (abgehakt). 2.3.1 (Bereinigung,
  CI), 2.3.2 (`ha --version` gibt es nicht) und 2.3.3 (Hinweis auf verdeckende
  Kopie) auf `main` (`ef6999e`); nur Tag/Release `v2.3.3` als Sammel-Release.
- CI grün auf `main` (Lauf 37587636406). Ubuntu-26.04-Probe grün
  (Lauf 37583213130); Actions auf Node-24-Majors, Tests auf Node 22.
- HA-Test auf 2.3.3; vom User im App-Terminal bestätigt: `--force` installiert
  v5.5.0 („ha runs ✓"), ohne `--force` ⚠️-Hinweis auf die Kopie (v5.5.0), nach
  `rm` wieder „Nothing to do".
- HA-Prod: laut User 2.2.2, nicht per MCP geprüft; Update nur mit Freigabe.

### Verworfen
- `persist-install --ha-cli` streichen (User wählte „neueste Version holen").
- `/config/` komplett in `.gitignore` (nur `/data/` ergänzt).
- Versionsdatei für die Image-CLI (Dockerfile-Änderung, nicht nötig).

### Fallen
- Die HA-CLI hat kein `--version` (4.x und 5.x, `cmd/root.go` ohne `Version`).
- Im Image gibt es `/usr/bin/ha`: ohne `--force` greift immer zuerst diese
  Prüfung; Tests überschreiben den Pfad mit `PERSIST_IMAGE_HA`.
- Git Bash hält Dateien nur mit Shebang für ausführbar — Test-Fakes brauchen eins.
- Eigene Kommentare mit `4.46.0`/`armv7` lösen den Metadaten-Schutz aus.
- api.github.com ohne Token: 403 durch Rate-Limit möglich (CI-Lauf
  37584251742, per Rerun grün) → Folgepunkt 13.
- Temp-Dateien nur unter `.tmp/` im Projekt (Memory `no-temp-files-on-c`);
  lokale Tests mit `TMPDIR`/`TMP`/`TEMP` darauf.

### Nächste Schritte
- HA-Prod auf 2.3.3 (Freigabe nötig).
- Folgepunkte im Memory `claude-code-ha-followups` (3, 7, 9, 13, 14).

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.

## 2026-10-07 — Release 2.3.0 (Dockerfile statt build.yaml, armv7 raus, Doku)

### Stand
- Spec `docs/specs/2026-10-07-dockerfile-build-design.md`, Plan
  `docs/plans/2026-10-07-dockerfile-build.md` (alle Schritte abgehakt). Gemergt
  nach `main` (`d016c71`), CI grün (Branch: Lauf 37548664129, main: 37549114833;
  Build-Log: `FROM ghcr.io/home-assistant/base:3.21`, Claude Code nativ
  installiert, Hadolint ohne DL3006 grün). Tag + GitHub-Release `v2.3.0`.
- HA-Test auf 2.3.0 (Update 2026-10-07 01:58): Supervisor-Build ohne
  `BUILD_FROM`, keine `build.yaml`-Warnung mehr (letzte 2026-10-06 17:45:31),
  `state: started`, App-Log ohne Fehler („Claude CLI is executable ✓").
  unbestätigt: `claude --version` im Terminal (User gab Release frei, Ausgabe
  nicht gezeigt).
- HA-Prod: laut User auf 2.2.2, nicht per MCP geprüft. Update auf 2.3.0 nur
  mit Freigabe.
- Lokal grün: `bash tests/test-release-metadata.sh` (2.3.0),
  `bash tests/test-startup-timeouts.sh`, ShellCheck; Clipboard (100) und
  Migration (57) vor dem Review-Commit `d2d8b0b`, der nur Doku/Metadaten-Test
  berührt.

### Verworfen
- armv7 über `${BUILD_ARCH}-base` behalten: Supervisor auf 32-Bit holt seit
  2025.12 keine App-Updates mehr, `armv7-base` seit 2025.11 eingefroren.
- `ARG BUILD_FROM` mit Default: ältere Supervisor übergeben ohne build.yaml
  `{arch}-base:latest` und würden Alpine still tauschen.
- Migrationsreste (Options-Pinning, pip-Versionen, `.egg-info`) bewusst nicht
  umgesetzt — Begründung in der Spec, Abschnitt 5.
- `options.json` für lokale Testläufe (weder unter `/config` noch `/data`):
  bashio liest Optionen über die Supervisor-API
  (`bashio::app.config` → `GET /addons/self/options/config`); lokal gelten die
  Standardwerte aus `run.sh`.

### Fallen
- `ghcr.io/home-assistant/base:3.21` enthält nur amd64/arm64 (Manifest geprüft).
- Supervisor-Quelle heißt jetzt `supervisor/apps/build.py` (nicht `addons/`).
- Lokal kein docker/podman/hadolint: Image-Build und Hadolint nur in der CI.
- Escapes: Heredocs über das Bash-Tool verstümmeln `\\` + Zeilenumbruch.
  Python-Skripte für Mehrzeilen-Ersetzungen mit dem Write-Tool anlegen und
  Backslashes über `chr(92)` bauen.
- Die Version steht seit 2.3.0 nur noch in `config.yaml` (plus README-Badge,
  vom Metadaten-Test geprüft) — `build.yaml` gibt es nicht mehr.

### Nächste Schritte
- HA-Prod auf 2.3.0 (Freigabe nötig).
- Folgepunkte im Memory `claude-code-ha-followups` (3, 7, 9–12).

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.

## 2026-10-06 — Releases 2.2.1 (klickbare Links) und 2.2.2 (Zeitgrenzen beim Start)

### Stand
- **2.2.1** (Folgepunkt 2): Plan `docs/plans/2026-10-06-terminal-link-click.md`,
  Spec `docs/specs/2026-10-06-terminal-link-click-design.md`. Auf `main`, Tag und
  GitHub-Release `v2.2.1`. HA-Test live vom User bestätigt: alle Zeilen des
  `/login`-Links öffnen die korrekte, vollständige URL.
- **2.2.2** (Folgepunkte 4 und 6): Plan `docs/plans/2026-10-06-startup-timeouts.md`,
  Spec `docs/specs/2026-10-06-startup-timeouts-design.md`. Auf `main` (`b081ad7`),
  CI grün (Lauf 37489708521, inkl. Image-Builds mit `coreutils`). HA-Test auf 2.2.2:
  App-Log „Persistent Claude override: update completed" nach 3 s, kein
  „timed out", Image-Service healthy, `state: started`. Tag/Release `v2.2.2`.
- Lokal: `bash tests/test-startup-timeouts.sh`, `bash tests/test-release-metadata.sh`,
  `node tests/test-terminal-clipboard.js` (100) grün; ShellCheck ohne Befund.
- Offen: HA-Prod steht auf 2.2.0 — Update nur nach ausdrücklicher Freigabe.

### Verworfen
- 2.2.1: nur `window.open` umleiten; ttyd-Addon über private xterm-Felder abschalten;
  Bruchstück über den ganzen Puffer auflösen (öffnete nach zweitem `/login` den
  falschen Link).
- 2.2.2: Netzwerk-Schritte in den Hintergrund verlegen (Claude könnte während des
  Binary-Tauschs starten); automatisches Aufräumen von npm-Resten (npm-Verhalten
  nach Abbruch unbelegt).

### Fallen
- `gh` ohne `--repo Eifel-Joe/claude-code-ha` zielt auf Upstream (404 bei `gh run`).
- `build.yaml` trägt die Version mit; `tests/test-release-metadata.sh` prüft das.
- HA-Basis-Image hat kein `coreutils`: BusyBox-`timeout` killt nur den direkten
  Prozess. Deshalb `coreutils` im Dockerfile — nicht entfernen.
- Browser-Pane führt `file://` nicht aus: Prüfstand über `python -m http.server`
  mit temporärer `.claude/launch.json` (nicht committen).
- HA-Update per MCP kann wegen des Image-Builds mit „Request timed out" antworten,
  obwohl der Build läuft: Supervisor-Log prüfen, nicht erneut auslösen.
- Update-Entität in HA Core hängt nach einem Supervisor-Update einige Minuten nach.
- `tests/test-production-run.sh` läuft lokal nicht (Symlinks); neue Bash-Tests
  daher in eigene, lokal lauffähige Suiten legen.

### Nächste Schritte
- HA-Prod auf 2.2.2 (Freigabe nötig).
- Übrige Folgepunkte: Memory `claude-code-ha-followups` (1, 3, 5, 7, 8).
- Veraltete `DEVELOPMENT.md` / `DEVELOPMENT_STATUS.md` (u. a. `/config/claude-config`).

### Empfohlene Skills
- `task-loop` für den nächsten Folgepunkt.
