# Fork-Survey: heytcass/home-assistant-addons

Stand: 2026-10-09 · Basis: `main` = 3.1.3 (`e8868d1`)
Methode: alle 104 Forks per GitHub-API gelistet (eine Ebene Unter-Forks, ESJavadex
ausgenommen – siehe `docs/FORK-SURVEY.md`); 74 Forks mit eigenen Branches als Refs
gefetcht; Commits, die nicht in heytcass, ESJavadex (upstream) oder origin liegen,
per `git patch-id` dedupliziert (1.958 Commits → 1.783 neue Patches); davon 1.092 am
Claude-Add-on (`claude-terminal*/`, `claude-home/`), `.github/` oder `tests/`.
Sichtung durch vier Subagenten (Teile unten), Befunde über unseren Code danach selbst
geprüft.

Spalte **Empf.**: ✅ übernehmen · 🟡 prüfen/angepasst übernehmen · ❌ nicht übernehmen

## Umsetzungsstand

| Thema | Quelle | Stand |
|---|---|---|
| Health-Check bricht beim ersten Fehler ab | owine #374 | ✅ 3.2.0 |
| Panel vor den langsamen Startschritten, Startseite | owine #380 | ✅ 3.2.0 |
| Upload-Endung aus dem MIME-Typ, 400 statt 500 | owine #379 | ✅ 3.2.0 |
| Mitgelieferte Skills/Commands bei jedem Start | eigener Fund | ✅ 3.2.0 |
| Auth-Helper ohne Klartext-Reste | owine `96ccd0d4` | ✅ 3.2.0 |
| `image_retention_days` | owine #380, msvinth, mattbsea | ✅ 3.2.0 |
| Health-Check startet `claude`/`node`/`npm --version` mit Zeitgrenze, `claude-doctor` | umrath (heytcass `ff4ebec`), owine `cc0d74e7` | ✅ 3.3.0 |
| `~/.tmux.conf.local`, `focus-events` | owine `1175851a`/`1e0a33e2`, BartBourgeois, Maheidem | ✅ 3.3.0 |
| `Cache-Control: no-cache` für die Oberfläche | owine `67dd7e55` | ✅ 3.3.0 |
| Sicherheits-Doku „jeder HA-User kann das Panel öffnen“ | umrath (heytcass `8e65403`) | ✅ 3.3.0 |
| Shift+Enter, Auto-Continue nach Usage-Limit (Knopf, Befehl, Option) | mattbsea | ✅ 3.4.1 |
| Mobil-Toolbar Esc/Pfeile (Y/N) | mattbsea, weiting-tw (marcjay Shift+Tab) | offen, als Nächstes (2026-10-12) |
| `map: share` / `addons` | Darrennchan8, mspnr, owine | offen, nur bei Bedarf (`/share` per Samba, lokale App-Entwicklung) |
| ripgrep unter musl | siehe Teile | offen, erst prüfen (Grep in der App) |
| Bremse nach erfolglosen Auto-Continue-Versuchen (Wochenlimit), Längengrenze für Limit-Zeilen | eigener Fund 3.4.1 | zurückgestellt, nur bei Nutzung von Auto-Continue |
| `claude_extra_args`, `working_directory` | mattbsea, ToRa89, umrath, monxas, owine, heman22union | ❌ verworfen 2026-10-12: Modell per `/model` bzw. `~/.claude/settings.json`, Verzeichnis per `cd` |
| `permissions.deny` als App-Option | Maheidem | ❌ verworfen 2026-10-12: in einer Minute selbst in `~/.claude/settings.json` eintragbar |
| Boot-Smoke-Test in der CI | heytcass `d50e6c0` | ❌ verworfen 2026-10-12: HA-Test fängt dieselben Fehler |
| Ingress-IP-Filter `172.30.32.2`, `watchdog:` | siehe Teile | ❌ verworfen 2026-10-12: kein Host-Port; Image-Service hat eigene Neustart-Schleife |
| Log-Rauschen „Proxy error“ während des Starts, Auth-Helper-Pipe-Frage | HA-Test 3.2.0, eigener Fund | ❌ verworfen 2026-10-12: Kosmetik bzw. Login funktioniert in der Praxis |
| `persist-install` kopiert keine apk-Dateien, API-Optionen, HA-MCP-Auto-Registrierung | eigener Fund, Moulbi, Maheidem, marcjay | ❌ verworfen 2026-10-12: mehrfach zurückgestellt, kein Bedarf |
| LayerTM/claude-ha (Assist-Integration) mit Begleit-App ClaudeInHA | LayerTM | ❌ nicht einbauen (2026-10-11): verlangt Slug `*_claude-code` und eigenen Prompt-Server (ha-agent-core); höchstens als eigene App neben unserer |

---

## Teil 1: Linie owine / TomaszBankowski

Stand 2026-10-09 · Refs `refs/hk/owine/main` (`0c9ac057`, 2.10.1, 2026-10-05),
`refs/hk/owine/feature/mobile-terminal-controls` (`79c1b1e4`), `refs/hk/TomaszBankowski/main`
(`d939430b` = owine 2.8.3, liegt vollständig in owine/main), `refs/hk/TomaszBankowski/patch-1` (`6f43dc3a`).
Listen: TomaszBankowski.tsv (470) + owine.tsv (90) = 560 Commits, davon ca. 230 renovate/release-bot.

### 1. Kurzfazit

owine ist der mit Abstand gründlichste Fork (eigene Testsuite, sehr gute Commit-Begründungen), und
vieles davon haben wir schon (ttyd auf Loopback, kein Host-Port, Wrapper-Neustart, npm-Cache, auth_api,
tmux, Toolbar und Link-Kopieren). Es lohnen sich aber mehrere **kleine, gut abgegrenzte Fixes**, von denen
einige **echte Bugs in unserem Code** treffen: Der Health-Check bricht beim ersten Fehler ab (errexit),
der Upload übernimmt die Dateiendung des Clients ungefiltert und tippt sie ins Terminal, die Web-UI
startet erst nach den langsamen Startschritten, und hochgeladene Bilder wachsen unbegrenzt in die Backups.
Größere Themen (ha-mcp-Bündelung, Paket-Persistenz) liefern gute Vorlagen für die zurückgestellten
Punkte, aber keinen Grund, sie jetzt umzusetzen.

### 2. Kandidaten (sortiert nach Nutzen)

| Fork | Commit(s) | Inhalt | Nutzen für uns | Empf. | Aufwand |
|---|---|---|---|---|---|
| owine | `12316e4a` | Health-Check: `check \|\| ((errors++))` liefert beim ersten Fehler 1 (Post-Increment von 0), unter bashios errexit endet das Skript dort. Alle weiteren Checks und die Zusammenfassung fehlen | **Bug bei uns**: `claude-workbench/scripts/health-check.sh:158-163` hat genau dieses Muster. Fix: `errors=$((errors+1))`. Hängt mit dem vorgemerkten Punkt „Health-Check mit `claude --version`“ zusammen | ✅ | klein |
| owine | `e696dc39` (`upload-naming.js`), `40f69266`, `2f434157` | Upload-Name aus dem MIME-Typ (Allowlist) + Zufallssuffix statt `path.extname(originalname)`. Abgelehnter Dateityp gibt 400 statt 500 | **Bug bei uns**: `image-service/server.js:41` nimmt die Endung vom Client. `path.extname('x.png;touch $(id) #')` ergibt `.png;touch $(id) #` (lokal geprüft), und `index.html:858` fügt den Pfad per `term.paste()` an der Shell-Eingabe ein. Gefahr bei Drag&Drop einer präparierten Datei. Dazu Kollision bei 2 Uploads in derselben ms (multer überschreibt). Der Pfad-Traversal-Check `2f434157` ist dann überflüssig. **Sicherheitsrelevant (niedrig)** | ✅ | klein |
| owine | `d685687b` (Teil 1) | Wrapper/Web-UI vor den netzlastigen Startschritten starten (Paket-Autoinstall, Docker, ha-mcp) | Bei uns startet `start_image_service` erst in `start_web_terminal` (`run.sh:758`) **nach** `setup_persistent_claude` (npm-Update) und `setup_persistent_packages`. So lange zeigt HA eine leere 502. Hingehört: `main()` in `run.sh`, Bild-Service direkt nach `init_environment` starten, tmux/ttyd bleiben am Ende | ✅ | klein |
| owine | `d685687b` (Teil 2) | Option `image_retention_days` (Standard 30, 0 = behalten): `find /data/images -name 'pasted-*' -mmin +N -delete` beim Start; ungültiger/leerer Wert löscht nichts | Bei uns wird `/data/images` nie aufgeräumt und wandert in jedes Backup (passt zum 3.1.3-Thema Backup-Größe). Hingehört: `run.sh` + `config.yaml` + `translations/en,de.yaml`. Löschung nur `pasted-*`, sichere Vorgabe bei leerem Wert übernehmen | ✅ | klein |
| owine | `96ccd0d4` | `claude-auth-helper.sh`: Auth-Code nicht mehr nach `/tmp/claude-auth-code` schreiben (wurde nie gelesen); `/config/auth-code.txt` sofort nach dem Lesen löschen | **Bei uns noch drin**: `scripts/claude-auth-helper.sh:36` schreibt den Code in eine Datei, die niemand liest. Datei unter `/config` liegt bis zur Löschung im HA-Backup. **Sicherheitsrelevant (niedrig)** | ✅ | klein |
| owine | `67dd7e55` (`cache-policy.js`) | Shell-Assets (HTML/JS/JSON) mit `Cache-Control: no-cache` ausliefern; Safari nutzte nach einem Update alte JS mit neuer HTML weiter | Bei uns `express.static` mit Standard `max-age=0` (`server.js:131`). `index.html` und `terminal-clipboard.js` können nach einem App-Update auseinanderlaufen. Hingehört: `setHeaders` in `server.js`. Der PWA-Teil gilt für uns nicht | ✅ | klein |
| owine | `1175851a`, `1e0a33e2`, `e0420936` | tmux: `source-file -q ~/.tmux.local.conf` am Ende (eigene Einstellungen überleben den Neustart), `focus-events on` (Claude Code/vim erkennen den Fokus), `display-time 2000` | Bei uns wird `~/.tmux.conf` bei jedem Start überschrieben (`run.sh:312`), eigene Anpassungen gehen still verloren. Hingehört: Heredoc in `setup_tmux`. `xterm-keys` (`1a659f46`) ist in aktuellen tmux-Versionen eh Standard, daher nur prüfen | ✅ | klein |
| owine | `8910b097` (+`9c605aa9`) | Alt-Login-Migration kopiert nach `$HOME/.claude/.credentials.json` und `$HOME/.claude.json`. Laut owine liest Claude Code `ANTHROPIC_CONFIG_DIR` nie; nur kopieren, wenn HOME leer ist; Marker pro Quelle | Unsere `migrate_legacy_auth_files` (`run.sh:176,198ff`) hat Glob- und Überschreib-Fix schon, **kopiert aber nach `ANTHROPIC_CONFIG_DIR` (`/data/.config/claude`)**, also womöglich an einen Ort, den Claude nicht liest. Betrifft nur Alt-Nutzer mit `/config/claude-config`. Vorher verifizieren, ob die CLI `ANTHROPIC_CONFIG_DIR` liest | 🟡 | klein |
| owine | `cc0d74e7` | `health-check.sh` als `claude-doctor` nach `/usr/local/bin` verlinken; Check startet `claude --version` mit Timeout und zeigt den echten Fehler (libc, hängende CPU) | Fertige Vorlage für den **vorgemerkten** heytcass-Punkt „Health-Check mit `claude --version` + CPU-Gate“. Der Symlink macht ihn im Terminal erreichbar. Hingehört: `Dockerfile` (Symlink) + `scripts/health-check.sh` | 🟡 | klein |
| owine | `54dc7036` | Persistentes venv neu bauen, wenn sich die Python-Minor-Version des Images ändert (`pyvenv.cfg` mit `python3` vergleichen) | Bei uns ist python3 im Image (`Dockerfile:30`), das venv liegt in `/data/packages/python/venv`. Beim nächsten Wechsel des Basis-Images (3.21 → neuer) bricht `pip` im venv. Hingehört: `persist-install` (`install_python_packages`) + venv-Aktivierung in `run.sh:132` | 🟡 | klein |
| owine | `7e4c5187` | Überholte native Claude-Binaries (~250 MB je Update) in `$XDG_DATA_HOME/claude/versions` aufräumen. Laut owine aktualisiert die native CLI sich trotz Einstellung selbst (`autoUpdatesProtectedForNative`) | Unser `XDG_DATA_HOME=/data/.local/share` (`run.sh:100`), wir installieren Claude aber per npm nach `/data/npm` und setzen `DISABLE_AUTOUPDATER=1`. **Erst auf HA-Test prüfen**, ob `/data/.local/share/claude/versions` existiert und wächst. Nur dann übernehmen | 🟡 | klein |
| owine | `8ed192d3`, `9d9b9d84`, `07c3a577` (`http-guards.js`) | Origin-Prüfung für POST und WebSocket-Upgrade (403 bei fremdem Origin, erlaubt: gleicher Host, kein Origin, `X-Ingress-Path`), Rate-Limit für Upload | Bei uns kein Origin-Check (`server.js:165`, Upgrade geht direkt an den Proxy). Ohne Host-Port verhindert laut owines Analyse schon der SameSite=Strict-`ingress_session`-Cookie Cross-Site-Zugriffe über Ingress. Nur als zusätzliche Absicherung nützlich, das Rate-Limit nicht nötig. Hingehört: `server.js` (`server.on('upgrade')` + POST-Middleware) | 🟡 | klein |
| owine | `e1c44156` | Option `claude_code_oauth_token` (`password?`, maskiert, nie geloggt) → `CLAUDE_CODE_OAUTH_TOKEN`, Login per `claude setup-token` ohne Browser-OAuth | Nimmt den heikelsten Schritt beim Einrichten weg. **Sicherheit**: Token landet in den Supervisor-Optionen (`/data/options.json` → Backups); laut owine kein Remote Control mit Token-Auth. Hingehört: `config.yaml`/`translations` + Export in `init_environment` | 🟡 | klein |
| owine | `8015c3a2`, `e644cf51` | `map: share:rw` (→ `/share`) + Option `working_directory` (tmux `new-session -c`, ungültiger Pfad → Warnung + `/config`) | Komfort für Projekte außerhalb von `/config`. `/share` erweitert die Schreibfläche der Root-Shell (vertretbar). Hingehört: `config.yaml` `map`, `run.sh:767` | 🟡 | klein |
| owine | `416eb6ae` | Menü-Kästen in Session-Picker/Auth-Helper auf 40 Spalten | Unsere Kästen sind ca. 66 Spalten breit (`claude-session-picker.sh`) und brechen auf dem Handy um. Rein optisch | 🟡 | klein |
| owine | `a2e09917` | `persist-install`: versionierte apk-Specs (`pkg=1.2`) für `apk info -L` auf den reinen Namen kürzen; leeres `apk info -L` = Fehler | Nur relevant, wenn die zurückgestellte Paket-Persistenz wieder aufgegriffen wird (siehe Abschnitt 4: unser Kopier-Schritt kopiert weiter nichts). Den pip-Exitcode-Teil haben wir schon (`persist-install:173`) | 🟡 (mit Paket-Persistenz) | klein |
| owine | `f413f336`, `88a32d90`, `5011f124`, `6ee21699` | ha-mcp gebündelt (uv-Lock, Installation beim Build, HA-Skills mitgeliefert), `claude mcp add` mit wörtlichem `'${SUPERVISOR_TOKEN}'` statt Klartext-Token | HA-MCP ist zurückgestellt. owines Lösung ist die sauberste Vorlage, vor allem `6ee21699` (Token nicht in `/data/home/.claude.json` → nicht in Backups). Siehe Abschnitt 4 | 🟡 (zurückgestellt) | mittel |
| owine | `aec79bed` | Option `enable_docker` (Docker-CLI + `docker_api`) | `docker_api` gibt praktisch Host-Root, Protection Mode muss aus sein. Nicht unser Fokus | ❌ | mittel |

### 3. Gesichtet, nichts dabei

- **renovate[bot] / release-bot / github-actions / claude[bot]** (~230 Commits): Versions-Bumps, Lockfile-Pflege, Release-PRs.
- **owine CI/Release** (`d22c59b1`, `0a9763db`, `3e5e7d47`, `a0e440dd`, Trivy `a1e4e62e` … `bbe6f48a`, `01820456`, `b965742b`, `f8fca167` u. a.): GHCR/Cosign/release-please/Renovate verworfen; Trivy-Scan wäre ein Extra, kein Bedarf.
- **owine Versions-Pinning mit SHA256** (`2abe5d1e`, `ebd470fc`, `b1102bc2`, `90cca72a`): blockiert „latest“ Claude, früher schon abgelehnt (albertonoys).
- **TomaszBankowski `6f43dc3a`** (patch-1): entfernt nur owines apk-Versionspins wegen Build-Brüchen. Wir pinnen keine apk-Versionen.
- **owine Fork-Einrichtung / Slug / Umbenennung** (`5df9c2fa`, `74703e01`, `894b4da5`, `f71f403f`, `944cd902`): persönlich bzw. haben wir („App“-Begriff schon).
- **tmux-Grundlage, Session-Picker-Quoting, Launcher** (`d68a7c88`, `6ca9211b`, `25ef7540`, `bff8933d`, `175d0ca5`, `ab937b3a`, `d35640e4`, `085629d3`, `276ebf2d`): haben wir.
- **Session-Picker `eval`** (`dfce9ab6`, Teil von `e696dc39`): Eingabe kommt vom Nutzer in seiner eigenen Root-Shell, keine Sicherheitsgrenze. Unser `eval` (`claude-session-picker.sh:236`) wertet Anführungszeichen korrekt aus.
- **http-proxy-middleware v3/v4, WS-Upgrade-Handler, pathRewrite** (`e5f1188c`, `339eb40a`, `6fbd32ed`, `116f7fa5`, `a419824d`): bei uns in 3.1.0 gelöst (`server.js:100-165`).
- **Wrapper-Neustart, Proxy-Fehler-Absturz** (`bd883605`): haben wir (`run.sh:671` `run_image_service_supervised`, `server.js:116` `headersSent`).
- **ttyd auf 127.0.0.1, Port nicht veröffentlichen** (`2cd5850e`, `6a369992`, Teil von `8ed192d3`): haben wir.
- **auth_api raus, npm-Cache flüchtig, all_addon_configs, map-Objektform** (`a1db84b5`, `499874ba`, `bbaf1df8`, `b445560a`): haben wir (3.1.0/3.1.3).
- **build.yaml raus, Labels im Dockerfile, Image-`image:`** (`8f8e3cc6`, `4472c1af`, `e6c4800a`): build.yaml-Teil haben wir; `image:` = GHCR, verworfen.
- **armv7 raus** (`efbfb596`): haben wir.
- **YOLO-/Dangerous-Mode** (`ef776dfd`, `d36f0d1c`, `6975a18b`): haben wir als `dangerously_skip_permissions` + `IS_SANDBOX`.
- **Claude-Binary persistent, ~/.local/bin im PATH** (`4c7514c6`, `ade74b10`, `d014b694`, `786584dd`): durch `use_persistent_claude` (/data/npm) gelöst.
- **Paket-Autoinstall jq/options.json** (`1645f84e`, `2ca9904c`, `54a2ad79`): wir nutzen `normalize_config_list` + Zeitgrenzen (`run.sh:488ff`).
- **Wedged Claude / AVX-Warnung** (`bffa3ca6`): Zeitgrenzen und CPU-Check haben wir, AVX verworfen.
- **HA-CLI-Download prüfen, `--ha-cli` entfernen** (`bcffa290`, `1525c1ce`): wir kopieren die `ha` aus dem Image (`persist-install` `PERSIST_IMAGE_HA`).
- **Login-Link-Assistent** (`63b08c17`): Link-Erkennung + One-Tap-Kopieren haben wir (`index.html:1071ff`); das Einfügen des Codes per Banner wäre nur ein Extra.
- **Image-Paste-UX, Toolbar, iOS-Scroll/Tastatur** (`0e3cc934`, `248fa4ba`, `800707e0`, `94e6c602`, `edee0b2b`, `96b60c39`, `1f957d4a`): haben wir (`visualViewport`, `index.html:1039`).
- **Theme/Renderer-Fixes** (`3aaf45d6`, `499e3d38`, `3b4c8dcb`, `59880f49`): Theme verworfen, DOM-Renderer von owine selbst zurückgenommen.
- **PWA** (`13485462`, `1732488c`, `ebd184c4`, `fc5ef9ef`, `72c30080`, `554651e4`, `4cc108e9`, `67672dff`): braucht direkten Port bzw. funktioniert nicht hinter der Ingress-Session, passt nicht zu unserem Modell ohne Port.
- **Maus-/Clipboard-Umbau** (`a5a346f5`, `533a7bcf`, `faeb7281`, `a49819f6`, `f781563a`, `4adab2b4`, `4acf4a25`, `47a7dfab`, `0dd9330d`): owine hat drei Releases mit Mausmodus-Wettläufen gekämpft und landet bei „tmux besitzt die Maus, Prefix+m schaltet um“. Unser Stand (Option `tmux_mouse`, OSC 52, Toolbar) funktioniert. Höchstens die Bindung `bind m set -g mouse` wäre ein Mini-Extra.
- **Branch `feature/mobile-terminal-controls`** (`342b84c6`, `ec329b13`, `5f991a88`, `79c1b1e4`, `7730373c`, `d07baeb4`): Steuerleiste über eine zweite WebSocket zu ttyd, von owine selbst aus main zurückgenommen (`2632dde8`). Unsere Toolbar deckt das ab.
- **Testsuite/Doku** (`5cb4e74e`, `b4c885bd`, `b85a0e64`, `03a93904`, `fd86d40d`, `dccbe218`): eigene Suite haben wir. Nützliches Detail aus `1175851a`: `new_tmpdir` in `$(...)` verliert die Cleanup-Registrierung (gleiches Muster ggf. in `tests/` prüfen).
- **Libexec-Persistenz für `docker compose`** (`2ea570a9`), **Relative-Pfad-Fix persist-install** (`a329540b`): gehören zur zurückgestellten Paket-Persistenz bzw. zu Docker.
- **`.dockerignore`** (`db3bbfb4`): Bei uns löscht `npm ci` (`Dockerfile:133`) ein eingeschlepptes `node_modules` eh. Allenfalls Hygiene für lokale Podman-Builds.
- **Alpine 3.24 / cryptography-Override** (`e68ee2a3`, `14f3315e`, `d97765af`): betrifft owines Basis bzw. ha-mcp.

### 4. Auffälligkeiten

1. **persist-install kopiert bei uns weiterhin nichts.** `claude-workbench/scripts/persist-install` vergleicht die Ausgabe von `apk info -L` mit `/usr/bin/*`. apk liefert aber relative Pfade (`usr/bin/tree`), wie owine in `a329540b` im Container belegt. Der zurückgestellte Punkt (FORK-SURVEY: mmackenzie2026 #38 / Moulbi) ist also weiter ein **echter Funktionsfehler**. Die Meldung „System packages installed and persisted!“ stimmt nicht; nur `persistent_apk_packages` überlebt, weil diese Pakete beim Start neu installiert werden. owines Fix ist klein (`persist_target_dir`), löst aber nicht die offene Frage, dass `lib` in `LD_LIBRARY_PATH` `/usr/lib` verdrängt.
2. **Health-Check bricht bei uns ab** (siehe Tabelle, `12316e4a`): Ein fehlgeschlagener Check überspringt die restlichen, auch den Claude-CLI-Check, und die Zusammenfassung fehlt.
3. **Shell-Injection über den Upload-Dateinamen** (siehe Tabelle, `e696dc39`): Die Endung kommt ungefiltert vom Client und landet per `term.paste()` an der Shell-Eingabe.
4. **SUPERVISOR_TOKEN im Klartext in `/data`** (`6ee21699`): Wer einen MCP-Server per `claude mcp add --env "TOKEN=${SUPERVISOR_TOKEN}"` (doppelte Anführungszeichen) registriert, schreibt das Token in `/data/home/.claude.json` und damit in jedes HA-Backup. Der User hat HA-MCP laut Memory schon im user-scope eingebunden; **prüfen, ob dort ein Klartext-Token steht** (auf HA-Prod/Test `grep -c SUPERVISOR /data/home/.claude.json` bzw. auf `eyJ` prüfen). Korrekt ist `'${SUPERVISOR_TOKEN}'` in einfachen Anführungszeichen.
5. **Port 7680 ist im hassio-Netz ohne Auth erreichbar** (nicht aus dem Fork, beim Abgleich aufgefallen): `server.js` bindet `0.0.0.0` und leitet `/terminal` an ttyd weiter. Jeder andere Container im internen Supervisor-Netz (z. B. ein kompromittiertes App) bekommt so eine Root-Shell ohne Anmeldung. Ein Origin-Guard hilft dagegen nicht (Nicht-Browser-Clients schicken kein Origin). Die HA-Entwicklerdoku zu Ingress empfiehlt meines Wissens, nur Verbindungen von `172.30.32.2` (Supervisor-Ingress) anzunehmen. Ein Remote-Address-Filter in `server.js` (HTTP + `upgrade`) wäre ein kleiner, wirksamer Schutz. **Vor der Umsetzung die Doku verifizieren.**
6. owine hält `ANTHROPIC_CONFIG_DIR` für wirkungslos, weil Claude Code laut owine nur `CLAUDE_CONFIG_DIR` bzw. `~/.claude` liest (`8910b097`). Wir exportieren es und nutzen es als Migrationsziel. Bei uns nicht verifiziert.

---

## Teil 2: mattbsea, cabinlab, evandepol

Stand: 2026-10-09 · Basis: `refs/hk/<owner>/*`, Listen `.tmp/hk-lists/{mattbsea,cabinlab,evandepol}.tsv`
(95 + 123 + 7 Commits). Abgleich gegen `claude-workbench/` (3.1.3).

### 1. Kurzfazit

Nur **mattbsea** hat Brauchbares. Er hat ttyd+tmux durch einen eigenen Node-/xterm.js-Tab-Server
ersetzt (Debian-Basis, Non-root-User, OpenCode). Das meiste davon passt nicht zu uns, ein paar
Einzelteile aber schon. Am wertvollsten ist **Auto-Continue nach Rate-/Usage-Limit**: ein
gut getesteter Parser für die Reset-Zeit, der nach dem Reset „continue“ tippt. Bei uns ginge das über
`tmux capture-pane`/`send-keys` im Image-Service. Klein und nützlich sind außerdem
**Shift+Enter = Zeilenumbruch**, **Esc/Pfeiltasten in der Mobil-Toolbar** und eine
**Größengrenze für eingefügte Bilder**: Unser `/data/images` wächst unbegrenzt und landet in jedem Backup.
**cabinlab** („Claude Home“, Juni 2025) und **evandepol** (OpenAI Watchdog) sind veraltete Experimente bzw.
ein anderes KI-Backend. Dort ist nichts zu holen.

### 2. Kandidaten (nach Nutzen)

| Fork | Commit(s) | Inhalt | Nutzen für uns | Empf. | Aufwand |
|---|---|---|---|---|---|
| mattbsea | `16847c88`, `533ae0ef`, `5924cd08`, `00e22fc0` (Datei `web-terminal/auto-continue.js` + `test/auto-continue.test.js`) | **Auto-Continue**: erkennt in der Terminal-Ausgabe (ANSI-bereinigt) Meldungen wie „5-hour limit reached – resets 3pm (Europe/Dublin)“, „try again in N hours“, rechnet die Reset-Zeit DST-fest per `Intl` aus und schreibt 1 min danach `continue` + Enter. Erkennt alte, neu gezeichnete Banner, damit kein falscher Neustart nach 24 h kommt (`00e22fc0`), Fallback 30 min, Obergrenze 24 h | Hoch für lange, unbeaufsichtigte Sitzungen (Remote-Control, Handy). Bei uns läuft die tmux-Session `claude` schon ab dem Start ohne Browser (`run.sh:764-767`), Auto-Continue wirkt also auch ohne offenes Panel | 🟡 | mittel |
| mattbsea | `6e44e41f` | **Shift+Enter** fügt einen Zeilenumbruch ein: `attachCustomKeyEventHandler` sendet `\` + CR (wird von Claude Code nativ unterstützt) statt Absenden | Mittel. Bei uns fehlt das (kein Treffer für `shiftKey`/`Shift+Enter` in `image-service/public/`). `/terminal-setup` hilft in ttyd+tmux nicht | ✅ | klein |
| mattbsea | `0a3b8548`, `8afc5dc6` (`paste-image.js` `pruneToSizeLimit`) | Ordner für eingefügte Bilder wird nach jedem Speichern auf 200 MB gekürzt (älteste zuerst, das neue Bild bleibt) | Mittel. Unser `image-service/server.js:27` speichert nach `/data/images` und räumt nie auf (kein prune/cleanup in `server.js`/`run.sh`). Die Bilder landen in jedem App-Backup, passt also zur Backup-Verkleinerung aus 3.1.3 | ✅ | klein |
| mattbsea | `ed215953` (index.html/style.css) | Mobil-Toolbar: Tasten **Esc, ←, ↑, ↓, →** senden rohe ANSI-Sequenzen. Nur auf Touch-Geräten sichtbar (Gate per `any-pointer: coarse`, siehe `6bcca457`) | Mittel. Auf dem Handy gibt es kein Esc (Claude abbrechen) und keine Pfeile (Menüs). Bei uns fehlt das: keine Esc-Buttons in `image-service/public/`. Zweiter Fork nach marcjay (FORK-SURVEY B, 🟡) | 🟡 | klein |
| mattbsea | `1598796b`, `83de6353`, `1ef731a1` | Option `claude_args` (freie Zusatz-Argumente für den Claude-Start, z. B. `--model opus`) | Gering bis mittel. Würde „anthropic_model“ (zurückgestellt) generisch abdecken. mattbsea zerlegt die Argumente naiv per `split(" ")` | 🟡 | klein |
| mattbsea | `ed215953` (run.sh, Dockerfile) | Server läuft unter `ssh-agent` (`exec ssh-agent node …`), alle Tabs teilen sich `SSH_AUTH_SOCK`, dazu `openssh-client` | Gering. Nur für git über SSH, wir haben `gh` (HTTPS). Bei uns fehlt openssh/ssh-agent komplett | 🟡 | klein |
| mattbsea | `5aa12b71` (config.yaml) | `map: media:rw`: `/media` (z. B. USB-Platten) im Terminal sichtbar | Gering. Bei uns nicht gemappt (`config.yaml` map: nur homeassistant_config + all_app_configs) | 🟡 | klein |
| mattbsea | `4a348fe9`, `b3f0f877` | `uv`/`uvx` im Image (für Plugin-MCP-Server wie claude-mem). Dazu Python 3.14 über uv | Gering. Mit `persist-install uv` (Alpine community) ohne Image-Änderung erreichbar, also höchstens Doku | 🟡 | klein |
| mattbsea | `1626cdf0`, `5924cd08` | Safari-Kopieren: erst synchron `execCommand('copy')` (contenteditable + Range statt `textarea.select()`), danach Clipboard-API. Außerdem `rightClickSelectsWord: false` | Gering. Unser `terminal-clipboard.js:66-81` ruft erst `clipboard.writeText` auf und greift erst nach dessen Ablehnung auf execCommand zurück. Das ist dasselbe Muster, das bei mattbsea in Safari die Nutzergeste verbrauchte. Wir nutzen aber zusätzlich `setSelectionRange` (iOS-Workaround). Auch bei mattbsea auf echtem Safari unbestätigt | 🟡 nur bei Safari-Meldungen | klein |
| mattbsea | `d9cbf643` | Add-on-Version in der Kopfzeile | Kosmetik | ❌ | klein |
| mattbsea | `a875faf2` | Konfigurierte Tabs starten ohne offenen Browser | Schon vorhanden: tmux-Session wird beim Start vorab erzeugt (`run.sh:764-767`) | ❌ | – |
| mattbsea | `dac23604`, `c8c8d014`, `3621ef8a`, `2e35d4e7` | Klickbare URLs über umbrochene Zeilen | Schon vorhanden: `installLinkProvider`/`linkSpansInRows` in `image-service/public/terminal-clipboard.js:527ff` | ❌ | – |
| mattbsea | `0a3b8548`, `a76462f8`, `176248b6`, `c8e147c4` | Bild-Paste als Dateireferenz | Schon vorhanden (Image-Paste-Service, `image-service/server.js`). Nur die Größengrenze ist neu (siehe oben) | ❌ | – |
| mattbsea | `89a4bab7` | Scrollback 10k | Schon vorhanden: tmux `history-limit 50000` (`run.sh:325`) | ❌ | – |
| mattbsea | `21463783` … `9d33a04d` (`claude_tabs`/`opencode_tabs`) | Mehrere Claude-Tabs je Verzeichnis mit `args`/`prompt` und Neustart-Schleife | Eigene Tab-Architektur. Bei uns gibt es `remote_control` + tmux. Die Neustart-Schleife mit festem Prompt startet bei jedem Ende einen neuen Agentenlauf (Kosten-/Sicherheitsrisiko) | ❌ | groß |

Zu den ✅/🟡-Zeilen (wo es bei uns hingehört, Sicherheit):
- **Auto-Continue** gehört in `image-service/server.js` als eigenes Modul (Parser aus `auto-continue.js` fast
  1:1 übernehmen, samt Tests). Statt PTY-Daten wird `tmux capture-pane -p -t claude` periodisch abgefragt,
  dann `tmux send-keys -t claude continue` und danach `Enter`. Dazu eine neue Option `auto_continue`.
  Sicherheit: Die Option muss **opt-in (Default false)** sein, bei mattbsea ist sie standardmäßig an. Zusammen mit
  `dangerously_skip_permissions` arbeitet Claude sonst nachts unbeaufsichtigt weiter. Gesendet wird nur
  der feste String, Ausgabetext wird nie ausgeführt.
- **Shift+Enter** gehört in `image-service/public/terminal-clipboard.js` (dort gibt es schon `window.term`).
  Zu prüfen ist, ob ttyd 1.7.7 selbst einen `attachCustomKeyEventHandler` belegt (es gibt nur einen Slot),
  sonst ein keydown-Listener in der Capture-Phase auf `term.textarea`. Kein Sicherheitsaspekt.
- **Bild-Grenze** gehört in `image-service/server.js` (nach dem Upload prunen, Grenze z. B. 200 MB oder nach
  Alter). Sicherheit: Nur innerhalb von `UPLOAD_DIR` löschen, das gerade hochgeladene Bild schonen.
- **Esc/Pfeile** gehören in die Toolbar in `image-service/public/index.html`. Gesendet wird über `term.input()` bzw.
  den ttyd-Socket, gemeinsam mit der marcjay-Variante (Shift+Tab) entscheiden. Kein Sicherheitsaspekt.
- **claude_args** gehört in `run.sh` beim Bau des Startbefehls. Sicherheit: Jedes Argument muss mit `printf '%q'`
  quotiert werden (wie bei `remote_control_session_name`, `run.sh:573`), weil der Wrapper `eval` benutzt.
- **ssh-agent** würde `openssh-client` im Dockerfile und `ssh-agent` um tmux/ttyd in `run.sh` brauchen. Keine Ports.
- **media:rw** ist eine Zeile in `config.yaml` `map:`. Sie gibt der Root-Shell zusätzlich Schreibzugriff auf /media.
- **uv** wäre nur ein Doku-Hinweis in `PERSISTENT_PACKAGES.md` (`persist-install uv`).
- **Safari-Kopieren**: In `terminal-clipboard.js` `makeCopyText` die Reihenfolge drehen (synchron zuerst),
  aber nur bei konkreten Meldungen.

### 3. Gesichtet, nichts dabei

- **mattbsea**, Branches `switch-alpine-to-ubuntu-17i1o`, `fix-debian-image-and-changelog-17i1o`
  (`5e444c15`, `823d8f86`, `58014a25`, `2d968c06`, `477a83ac`, `72276b1f`, `5012a9e4`, `ec5072a8`,
  `1b0d2798`, `24572731`): Umstieg auf Debian bzw. Non-root-User mit `NOPASSWD`-sudo. Das bringt keinen
  Sicherheitsgewinn und ist ein Basis-Umbau.
- **mattbsea**, Tab-Server-Umbau v2.0.0 (`ac51f25c`, `04eaa332`, `0f24d6c1` und ~30 WebSocket-/Ingress-Debug-Commits
  `6dbc591d` … `7157b640`, `2802f291`, `a002be9a`, `104939ff`, `2b08760c`, `5175be75`, `6d2fb16a`,
  `b5d23748`, `298927d0`, `5ba3d3ee`, `07298751`, `0593d5f8`, `22598451`, `c48228e3`, `2342d302`): Das ist eine eigene
  Terminal-Architektur ohne ttyd/tmux, nicht übertragbar.
- **mattbsea**, `4f25b89f`, `3b886c66`, `ca1dd85e`, `2e6218dd`, `11507968`, `4637f1d1`, `8e232e43`, `97c9489f`,
  `1dbf9f20`, `1fdeac19`, `4790edbe`, `09467d3e`, `1994c7e3`: nvm/Node-24, happy-coder, PATH-/CWD- und
  tmux-Doppelstart-Fixes der eigenen Linie. Bei uns gelöst bzw. nicht relevant.
- **mattbsea**, `3a4cb087` (Bun vorinstalliert + Mobil-Paste/Copy-Buttons; Copy/Paste haben wir schon),
  `6bcca457` (Toolbar-Gate, nur zusammen mit Esc-Tasten relevant), `a0b1f3eb`, `30950f14`, `a04c7606`
  (OpenCode/OpenRouter/claude-mem): persönliche Anpassungen bzw. andere Backends, verworfen.
- **mattbsea**, Branches `home-assistant-ai-addon-IaEqe`, `pull-latest-code-u5imqd`, `main`, sonstige Ordner
  (pai, teslausb-viewer, portainer-mcp, nginx-proxy-manager-mcp, paseo, webtmux …): andere Add-ons.
- **cabinlab** (alle 123): „Claude Home“ (Juni 2025, alter Stand). Darin: Modellauswahl
  `haiku|sonnet|opus` (zurückgestellt `anthropic_model`), Auth-Persistenz-Experimente unter `/config/claude-config` (bei
  uns `/data`), `hass-mcp-lite`/hass-mcp (HA-MCP zurückgestellt; HA hat inzwischen einen offiziellen MCP-Server),
  ein Chat-UI auf Branch `dev-chat-interface` (selbst als „broken state“ markiert, `5d83d624`), „Security-Framework“
  (`40e182e8`: Aktivitäts-Logger, ulimits, das ist Security-Theater), Debian-Basis, CI-Auto-Revert, Theme,
  APC-UPS-/Access-Point-Add-ons, `disable_telemetry` (setzt nur `DISABLE_TELEMETRY`, geht auch per `~/.claude/settings.json`),
  `ha_notifications` (schreibt einen erfundenen Schlüssel in `settings.json`, wirkungslos). My-HA-Buttons im README
  haben wir schon (`README.md:40`).
- **evandepol** (alle 7): „OpenAI Watchdog“ = Kopie von cabinlabs claude-watchdog mit OpenAI-Backend plus
  `.github/copilot-instructions.md`, also ein anderes KI-Backend, verworfen.

### 4. Auffälligkeiten

- **mattbsea, offene Root-Shell im LAN:** Der Tab-Server lauscht auf `0.0.0.0:7681`
  (`server.js` `server.listen(PORT, '0.0.0.0')`), `config.yaml` veröffentlicht `7681/tcp: 7681`, eine
  Authentifizierung gibt es nicht. Der User `claude` hat `NOPASSWD: ALL`, das ist also effektiv eine Root-Shell mit
  `SUPERVISOR_TOKEN` (hassio_role manager). Es ist dieselbe Lücke wie bei Moulbi/miczu71 (FORK-SURVEY).
  **Wir haben sie nicht:** Ohne `ports:` und mit ttyd auf 127.0.0.1 ist das von `tests/test-release-metadata.sh` abgesichert.
  Außerdem `maxPayload: 250 MB` pro WebSocket-Nachricht und `auth_api: true`.
- **cabinlab:** `full_access: true` und `ports: 7681` (ttyd, ohne Auth) in `claude-home/config.yaml`.
  Das ist noch weiter offen, betrifft uns nicht.
- **Bei uns gefunden:** `/data/images` wird nie aufgeräumt. Die Upload-Größe ist auf 10 MB pro Bild begrenzt,
  die Gesamtmenge aber nicht, und alles geht in jedes App-Backup (siehe Kandidat Bild-Grenze). Ein Sicherheitsproblem ist
  das nicht, da `/data/images` nicht ausgeliefert wird (kein static-Mount; auch SVG-Uploads sind damit unkritisch).
- **Bei uns, gering:** `makeCopyText` (`terminal-clipboard.js:66-81`) nutzt dasselbe „async zuerst, execCommand als
  Fallback“-Muster, das bei mattbsea in Safari die Nutzergeste verbrauchte (`5924cd08`). Nur relevant, wenn
  Safari-Nutzer Kopierfehler melden.

---

## Teil 3: abhikmitra, weiting-tw, KadenThomp36, msvinth, alexcf, FleshDK, heman22union, Maheidem

Forks: abhikmitra, weiting-tw, KadenThomp36, msvinth, alexcf, FleshDK, heman22union, Maheidem
Basis: `.tmp/hk-lists/<owner>.tsv` und die zusätzlich genannten Branches (`refs/hk/<owner>/*`).
Abgleich gegen `claude-workbench/` (3.1.3), `docs/FORK-SURVEY.md` und die Liste „bereits bekannt“ im Brief.

### 1. Kurzfazit

Es gibt wenig Großes, aber ein paar kleine, gut abgrenzbare Punkte. Am meisten bringt Maheidem
(`ee4853c4`): Beim ersten Start wird eine `permissions.deny`-Liste für `secrets.yaml`, `.storage/`
und die Recorder-Datenbank angelegt, dazu ein kurzer Sicherheits-Hinweis als CLAUDE.md. Fast genauso
nützlich ist die automatische Bereinigung hochgeladener Bilder von msvinth (`f6a11ce0`): Bei uns wächst
`/data/images` ohne Grenze und landet in jedem Backup. Auf Alpine sollte Claude Code laut zwei Forks das
System-ripgrep nutzen (`USE_BUILTIN_RIPGREP=0`); das prüfen wir am besten zuerst in der laufenden App.
Die großen Umbauten (abhikmitras Conversation-Agent/API-Server, KadenThomp36s herdr/T3, Maheidems
Debian-Neubau) passen nicht zu uns oder bringen Sicherheitsprobleme mit. Die Branches von alexcf und
heman22union, die du genannt hast, sind bei uns schon gelöst oder bewusst verworfen.

### 2. Kandidaten (sortiert nach Nutzen)

| Fork | Commit(s) | Inhalt | Nutzen für uns | Empf. | Aufwand |
|---|---|---|---|---|---|
| Maheidem | `ee4853c4` (`settings.default.json`, `config-CLAUDE.md`) | Beim ersten Start wird `permissions.deny` angelegt: `Read/Edit(//config/secrets.yaml)`, `Read/Edit(//config/.storage/**)`, `Read(//config/*.db)`, `Read(//config/*.db-*)`. Dazu kommt eine CLAUDE.md mit Hausregeln: vor YAML-Änderungen ein Backup, danach die Konfiguration prüfen, `.storage` nie anfassen, Secrets nie ausgeben. | Bei uns gibt es weder eine Deny-Liste noch einen HA-Sicherheitshinweis (grep nach `permissions`, `secrets.yaml` und `deny` in `claude-workbench/` ohne Treffer). Claude hat `/config` mit Schreibrechten. Damit sinkt das Risiko, dass Secrets oder die Datenbank versehentlich im Kontext landen. | ✅ (angepasst) | klein |
| msvinth | `f6a11ce0` | Hintergrund-Task löscht alle 30 min hochgeladene Bilder in `/data/images`, die älter als `IMAGE_MAX_AGE_HOURS` sind (Standard 6 h). | `server.js` und `run.sh` (`start_image_service`) legen `/data/images` an, räumen aber nie auf. In `config.yaml` steht kein `backup_exclude`, also wandert jedes eingefügte Bild ins Backup. | ✅ (angepasst) | klein |
| FleshDK, Maheidem | `6b7f47a1`, `b768eee5` (FleshDK); `443e0f32`, `4135c726`, `ee4853c4` (Maheidem) | `apk add ripgrep` (FleshDK zusätzlich `libgcc` und `libstdc++`), dazu `USE_BUILTIN_RIPGREP=0`, damit Claude Code auf musl das System-ripgrep nimmt. | Unser `Dockerfile` installiert weder `ripgrep` noch setzt es `USE_BUILTIN_RIPGREP` (grep ohne Treffer). Zwei Forks sind unabhängig voneinander darauf gekommen. Ob das mitgelieferte rg bei uns wirklich versagt, ist **nicht belegt**. `libstdc++` und `libgcc` kommen vermutlich schon über `nodejs` mit, auch das ist ungeprüft. | 🟡 | klein |
| weiting-tw | `6b63a7b6` (+ Toolbar `fe0a4ec9`) | Schnelltasten-Leiste für Handys: Y, N, 1–5, ↵, Esc, ^C. So lassen sich Claudes Auswahl-Prompts ohne Bildschirmtastatur beantworten. | Bei uns gibt es keine solche Leiste (`index.html` hat nur Link, Copy, Voice und Upload). Das deckt sich mit der zurückgestellten marcjay-Idee (Esc/Shift+Tab, FORK-SURVEY B) und ergänzt sie. | 🟡 | klein–mittel |
| heman22union | `26b07458` (Branch `feature/configurable-paths`, auch in `cb312f87`) | Optionen `working_directory` (Startverzeichnis für Claude und Picker) und `prompt_working_directory` (beim Öffnen nachfragen). Ebenfalls enthalten: `claude_data_path`. | Bei uns ist das Startverzeichnis fest `/config` (`Dockerfile` `WORKDIR /config`), eine Option gibt es nicht. Claude Code legt Projekt-Gedächtnis und Verlauf je Arbeitsverzeichnis an, daher kann z. B. ein Git-Repo unter `/config/…` sinnvoll sein. | 🟡 (nur `working_directory`) | klein |
| Maheidem | `f5e00ba1` | Eigene Anpassungen bleiben erhalten: `tmux.conf.local` wird aus der erzeugten tmux.conf eingebunden, `init.sh` läuft beim Start in einer Subshell (Fehler blockieren den Start nicht, siehe `5c5a2e93`), dazu `bashrc.local`. | `setup_tmux` in `run.sh` überschreibt `~/.tmux.conf` bei jedem Start (`cat > "$tmux_conf"`), eigene tmux-Einstellungen gehen also verloren. Einen Start-Hook gibt es nicht. | 🟡 | klein |
| Maheidem | `5c5a2e93` | `watchdog: "http://[HOST]:[PORT:7681]/"` in `config.yaml`: Der Supervisor startet die App neu, wenn der Dienst nicht mehr antwortet. | Bei uns gibt es keinen `watchdog:`-Eintrag. Ein `/health` liefert der Image-Service schon (`server.js`). Laut Maheidems Kommentar funktioniert `[PORT:x]` auch ohne veröffentlichten Port. Das ist **unbelegt**. | 🟡 | klein |

**Wo es bei uns hingehört und Sicherheitsaspekte (für ✅/🟡):**
- **Deny-Liste und Sicherheitshinweis:** Gehört in `init_environment` in `run.sh`. Neben dem bestehenden Kopieren von `/opt/.claude` wird `$HOME/.claude/settings.json` angelegt, wenn die Datei fehlt. Gibt es sie schon, wird die Deny-Liste per `jq` ergänzt, nichts überschrieben. Den Hinweistext besser nach `$HOME/.claude/CLAUDE.md` (User-Memory) legen statt nach `/config`, damit wir nichts in die HA-Konfiguration schreiben. Pfade auf unser Mapping prüfen: `homeassistant_config` liegt auf `/config`. **Sicherheit:** Das ist eine Verbesserung, aber keine harte Grenze. Über Bash (`cat`) lässt sich die Regel umgehen; so sollte es auch in der Doku stehen.
- **Bild-Bereinigung:** Gehört als `setInterval` in `claude-workbench/image-service/server.js`. Der Standard sollte länger sein als 6 h: Fortgesetzte Unterhaltungen verweisen auf alte Pfade, deshalb eher Tage. Zusätzlich `backup_exclude: ["images/*"]` in `config.yaml` erwägen. Kein Sicherheitsrisiko; nur Dateien in `UPLOAD_DIR` löschen, keinen Symlinks folgen.
- **ripgrep:** Gehört in die `apk add`-Liste im `Dockerfile` plus `ENV USE_BUILTIN_RIPGREP=0`. Prüfkriterium vorher: In der laufenden App mit `claude` eine Suche über das Grep-Tool bzw. `/doctor` ausführen. Kommt dabei ein Fehler oder ein leeres Ergebnis, übernehmen. Kein Sicherheitsaspekt.
- **Schnelltasten:** Gehört in `image-service/public/index.html` und `terminal-clipboard.js`. Die Tasten sollten **im Client** über `window.term`, also den ttyd-WebSocket, gesendet werden, **nicht** wie bei weiting-tw über einen Server-Endpoint mit `tmux send-keys` (siehe Auffälligkeiten).
- **working_directory:** Gehört in `config.yaml`, die Übersetzungen und den tmux-Wrapper in `run.sh`. Den Wert per `printf %q` übergeben, nicht wie bei heman22union in `'${working_dir}'` einbetten. **`claude_data_path` nicht übernehmen:** Es verschiebt Zugangsdaten zurück nach `/config` (per SMB lesbar). Genau das haben wir mit dem Umzug nach `/data` bewusst beendet.
- **tmux.conf.local und init.sh:** Gehört ans Ende von `setup_tmux` als `source-file -q ~/.tmux.conf.local`, der Start-Hook in eine Subshell mit Zeitgrenze, wie bei den übrigen Startschritten. **Sicherheit:** `init.sh` läuft als root, liegt aber in `/data` und ist nur für Nutzer erreichbar, die ohnehin eine Root-Shell haben. Kein neues Risiko.
- **watchdog:** Gehört in `config.yaml` als `watchdog: "http://[HOST]:[PORT:7680]/health"`. Vorher auf HA-Test prüfen: Erkennt der Supervisor das Ziel ohne `ports:`-Mapping, und startet er die App neu, wenn der Image-Service gestoppt wird? **Es darf kein `ports:`-Eintrag dazukommen**, das würde `tests/test-release-metadata.sh` ohnehin abfangen.

**Nur zur Erinnerung, zurückgestellt:** Maheidem `ee4853c4` hat `oauth_token` und `api_key` als Optionen mit Schema-Typ **`password?`**, exportiert als `CLAUDE_CODE_OAUTH_TOKEN` bzw. `ANTHROPIC_API_KEY`. Dazu kommen ein Warnhinweis zur Vorrangregel und das Schwärzen von `TOKEN`, `KEY`, `SECRET` und `PASSWORD` im Log. Das ist sauberer als die scholarnemo-Variante mit `str` (FORK-SURVEY C). Falls die API-Optionen wieder aufgegriffen werden, ist das die bessere Vorlage.

### 3. Gesichtet, nichts dabei

| Fork | Commits | Grund |
|---|---|---|
| abhikmitra | `ca6a8306`, `66a30ebd`, `b2462155`, `ba6a258b`, `569d4345`, `30dd58d2`, `42f83ecd`, `9e0b22a9`, `a9f27f4c`, `aae3e05c`, `4069064`, `263d4c8d`, `3cf5bdf3`, `39c1e53b` u. a. | Eigene HA-Integration (Conversation- und AI-Task-Entity) plus Python-API-Server mit Claude Agent SDK. Sehr groß, `bypassPermissions`, Server ohne Authentifizierung (siehe Auffälligkeiten). Dazu Codex- und ChatGPT-Bridges (verworfen: andere KI-Backends). |
| abhikmitra | `1dfc3916`, `eb5ffc6b`, `4182e738`, `5ab8eb88`, `6cbd4b5a`, `20eae672` | YOLO standardmäßig an, `IS_SANDBOX`, Agent-Teams-Env. Bei uns gibt es `dangerously_skip_permissions` als Option (Standard aus) und `IS_SANDBOX=1` (`run.sh:124`, `:153`). |
| abhikmitra | `06a1bd0b`, `f27a936a`, `df4b735e`, `7e29045e`, `ec1975b1`, `47ee653b`, `4ff64c86`, `de076647`, `6563845a`, `5be22bee`, `9b3164e7`, `2416aaeb`, `7b929147`, `45d7bc3c` | Versionssprünge, Debug-Hilfen, Tests und Codex-Routing für die oben genannte Integration. |
| weiting-tw (`security-refactor`) | `52747291` | Entfernt das `config`-Mapping, setzt `hassio_role: default` und schaltet `homeassistant_api` ab. Das widerspricht dem Zweck unserer App (Claude soll `/config` bearbeiten). `auth_api` ist bei uns schon raus. `hassio_role` steht als offene Frage schon in der Folgeliste (Moulbi Teil c). Die entfernte `config/claude-config/.claude.json` führen wir nicht im Repo (`git ls-files config` leer, seit `49edda28`). |
| weiting-tw (`security-refactor`) | `d9ec9fb5`, `8401f971`, `cceb6d71`, `f9ae1cff`, `0411ef16`, `650ab58c`, `2b630795`, `efcfd6dc`, `869212ca`, `dacad707`, `ad8b32d1`, `d8019984`, `3ec31cce`, `b5c899f5`, `aec9be76`, `0730c341`, `6f776b43` | Builder-, QEMU-, GHCR- und Pfad-Experimente sowie Versionssprünge. GHCR ist verworfen, unser Build läuft. |
| weiting-tw | `3904ceda`, `72afcb03`, `5112b742`, `fb3196dd`, `75c7ec48` | CI-Workflow mit yamllint, gitleaks und Test-Job. Unsere `ci.yml` deckt shellcheck, hadolint, Tests und Image-Builds ab. |
| weiting-tw | `78f1d9c3`, `fe0a4ec9`, `2562ab27`, `6297a56a` | tmux-Persistenz, Session-Picker und Toolbar-iframe. Haben wir schon (tmux, Picker, Toolbar). |
| weiting-tw | `c143fcca`, `f783e499`, `b07081f6` | Option `system_prompt` überschreibt bei jedem Start `/data/CLAUDE.md`, mit Standard „Antworte immer auf Traditionellem Chinesisch“. Persönlich; Nutzer können `~/.claude/CLAUDE.md` selbst pflegen. |
| weiting-tw | `39e55094` | Option `enable_context7`, schreibt bei jedem Start `settings.json` komplett neu (nur `mcpServers`). Persönliche Vorliebe, und das Überschreiben würde Nutzer-Einstellungen löschen. |
| KadenThomp36 | `0295b5ff`, `af632f75`, `b1f8d422`, `ecb95836`, `30d14390`, `55d806c3`, `05fabe76`, `ed4f784f`, `723c578f`, `d43293be` | Eigene App „claude-terminal-herdr“ (herdr statt tmux, Theme, Corgi- und Collie-Bridges, spawn-project-Skill). Persönliche Infrastruktur. |
| KadenThomp36 | `898c614d`, `4eb5a91f`, `83be9fe0`, `0b66d9f0` | Separate App „t3code“ (T3-Code-GUI). Gehört nicht zu uns. |
| KadenThomp36 | `bb7657f8` | OSC-52-Handler über eine eingeschleuste ttyd-`index.html`. Haben wir schon (`terminal-clipboard.js:694` `registerOscHandler(52…)`, `run.sh:318` `set-clipboard on`). |
| KadenThomp36 | `56145dfa` | Statuszeile eines Dritten (daniel3303) mitgeliefert, überschreibt `statusLine` bei jedem Start. Geschmackssache. |
| KadenThomp36 | übrige Branches (`claude/*`, `feat/ha-mcp-integration`) | Keine eigenen Commits in der Liste (≤1 Commit vor heytcass, per patch-id schon abgeglichen). |
| msvinth | `e969e8bd`, `2e102c29`, `4ca33bf7`, `80ce0ae4`, `c08c03c2` | Bild-Paste und Clipboard-Fixes für ihren Python-Image-Service. Haben wir schon (Node-Service, `terminal-clipboard.js`). |
| msvinth | `a8a72224`, `30024886` | WebSocket-Keepalive, tmux-Reattach und Fallback auf bash. Bei uns gibt es `--ping-interval 30` und `reconnect=5` (`run.sh:787f.`) sowie tmux mit Picker-Schleife. Ihr Fix betrifft einen Proxy-Fehler (`autoping=False`) in ihrem aiohttp-Proxy, den wir nicht haben. |
| msvinth | `b04c4d63`, `ad68ab19` | `NODE_OPTIONS=--max-old-space-size=64…256`. Wirkt bei uns nicht, weil Claude als natives Binary installiert wird (`Dockerfile:83`). Bei der npm-Variante würde ein Heap von 64–256 MB Claude Code eher abstürzen lassen. |
| msvinth | `6527e228` | Claude beim Wiederverbinden automatisch neu starten. Bei uns kehrt ein beendetes Claude in den Picker zurück, nicht genug Nutzen. |
| msvinth | `d039ba47`, `273fb2b0`, `7a2a4f0d`, `2e05b215` | ha-mcp per `uvx` (zurückgestellt). Löst es nicht besser, und `--index-strategy unsafe-best-match` ist bedenklich (siehe Auffälligkeiten). |
| alexcf (`fix/yolo-warning-hardening`, `feature/yolo-mode`, `feature/yolo-mode-owine`) | `4cbd9a55`, `5de68e54`, `744dfd1b`, `bef09ba4`, `a663ce15`, `d6428a12`, `1a950bb7`, `cceefed2`, `6e0f5067`, `d6c8b65e`, `b0f8ef5e`, `dc16898e` | Menüpunkt YOLO, über `ALLOW_YOLO_MODE` bzw. die Option `dangerously_skip_permissions` freigeschaltet, mit verschärfter Warnung. Haben wir schon: Option `dangerously_skip_permissions` (Standard `false`, `config.yaml:42`), `get_claude_flags` im Picker hängt das Flag nur bei `CLAUDE_DANGEROUS_MODE=true` an. |
| alexcf | `531e586e`, `b4c6f793` | CI-Workflow claude-review für Fork-PRs. Haben wir nicht und brauchen wir nicht. |
| FleshDK | `0a4695cb`, `0ccd0360`, `2f4b58e0`, `5891885c`, `6614c242`, `729ab335`, `7d8143d2`, `b2a1c1d6`, `c9aab7a4`, `e5c344b0`, `3d99a945`, `3f63aea2` | Dockerfile- und run.sh-Edits über die Web-Oberfläche: ttyd ins Image (haben wir), tmux aus dem Start-Befehl entfernt (Rückschritt). Einziger brauchbarer Punkt ist ripgrep (siehe oben). |
| heman22union (`feature/ssh-server`, `test`) | `d09c2741`, `e439e05f`, `62ad4b5c`, `527a421d`, `366b8bee`, `3ae959b5`, `c6dc34f3` | SSH-Server mit Port 2222 nach außen (zurückgestellt, Ports nach außen verworfen). Nicht besser als marcjay. Den bashio-Listen-Fallstrick (`3ae959b5`) lösen wir schon mit `normalize_config_list` (`run.sh:495`). |
| heman22union (`fix/claude-login-url-hardwrap`) | `e56b53a4` | Login-URL, die über mehrere Zeilen hart umbrochen ist, wird in `claude-login-url.sh` wieder zusammengesetzt. Haben wir schon im Browser: `terminal-clipboard.js` (`wrapWidth`, Umbruch-Erkennung ab Z. 260ff, Link-Button). |
| heman22union (`integration/login-url-fix`, `feature/login-url-notification`) | `16af268a`, `70434bea`, `4f8d3a5f`, `35b25d98` | Login-URL als HA-Benachrichtigung (verworfen) sowie Versionssprünge und Revert. |
| heman22union (`main`) | `cb312f87`, `1576c24e`, `3a315c21`, `5d3c8f5b`, `8a267ef2`, `b7429bc7` | Sammel-Commit aus SSH, Pfaden und Picker-Schalter. Der Picker-Schalter entspricht unserem `auto_launch_claude`. Dazu Slug-, URL- und Repo-Anpassungen und ein persönliches Arbeitsverzeichnis `/config/ha_ai_repo`. |
| Maheidem | `4135c726` | Neubau auf Debian-Basis mit `CLAUDE_CONFIG_DIR=/config/claude-config` (Zugangsdaten in `/config`) und `startup_command`. Andere Architektur; Zugangsdaten in `/config` wollen wir nicht. |
| Maheidem | `1f4acfdb`, `5c5a2e93` (Launcher-Teil) | Claude-Installationsverzeichnis persistent, Updater an. Haben wir schon mit `use_persistent_claude` und `auto_update_claude_on_start` (`/data/npm`). |
| Maheidem | `805d19ae` | `/root/.claude` als Symlink in den persistenten Bereich. Bei uns ist `HOME=/data/home`, `~/.claude` liegt also ohnehin persistent. |
| Maheidem | `ee4853c4` (übrige Teile) | Neustart-Schleifen für `startup_command` und ttyd, Session-Log über s6-log, `claude-login` mit QR-Code, `ha-check`/`ha-restart`/`ha-notify` (bei uns gibt es `ha` CLI und `ha core check`), ttyd-SHA256-Prüfung (wir nehmen ttyd aus apk), `rendererType=dom` (unser Kopieren läuft über die term-API, DOM-Rendering ist langsamer), Aufräumen alter Binaries (bei npm nicht nötig). |
| Maheidem | `443e0f32`, `7f993c27`, `311928d1`, `a3c2b94a`, `cbd18811` | Alte Überarbeitung von 2025/2026-03: Alpine 3.21, tmux, Persistenz, Ports. Inhalt haben wir schon. |

### 4. Auffälligkeiten

- **abhikmitra: API-Server ohne Authentifizierung, mit RCE.** `scripts/api-server.py` hört auf
  `API_HOST = "0.0.0.0"` Port 8099 und ruft die Agent-SDK mit `"permission_mode": "bypassPermissions"` auf.
  Dazu kommt ein `/api/run-script`-Endpoint. Jeder Container im hassio-Netz kann so Befehle als root
  ausführen, mit `SUPERVISOR_TOKEN` und `/config` mit Schreibrechten. Außerdem liest der Server
  `claude_oauth_token` aus `/config/secrets.yaml`. Uns betrifft das nicht, aber es ist eine Warnung,
  falls wir je einen Agent-Endpoint bauen: nur 127.0.0.1 oder eine Ingress-geschützte Route.
- **weiting-tw: Shell-Injection im `/api/key`-Endpoint** (`6b63a7b6`, `web-ui.js`). Der Code ist
  `execSync(\`tmux send-keys -t … -l ${JSON.stringify(key)}\`)`. `JSON.stringify` setzt den Text in
  doppelte Anführungszeichen, in denen die Shell `$(…)` trotzdem auswertet; das gilt auch bei 20 Zeichen
  Längengrenze. Hinter Ingress ist der Schaden gering, weil man ohnehin eine Root-Shell hat. Für uns heißt
  das: Schnelltasten nur im Client umsetzen, keinen Server-Endpoint einführen.
- **msvinth: `uvx --index-strategy unsafe-best-match`** (`2e05b215`) mischt den HA-Wheel-Index mit PyPI.
  Das öffnet die Tür für Dependency-Confusion. Falls wir HA-MCP angehen, nicht so übernehmen.
- **heman22union und Maheidem: Zugangsdaten nach `/config`** (`claude_data_path`, `CLAUDE_CONFIG_DIR=/config/claude-config`).
  Dort sind sie per SMB und Samba sowie in HA-Backups lesbar. Wir haben das bewusst nach `/data` verschoben; nicht regressieren.
- **Fund im eigenen Code, nebenbei:** `run.sh:179–185` kopiert `/opt/.claude` (Skills und Commands) nur,
  wenn `$HOME/.claude` **noch nicht existiert**. Neue oder geänderte mitgelieferte Skills (z. B.
  `persistent-package-manager`) kommen bei bestehenden Installationen also nie an. Das ist relevant, falls
  wir die Deny-Liste bzw. CLAUDE.md über denselben Weg ausliefern wollen. Dafür einen eigenen Merge-Schritt vorsehen.
- **Maheidem behauptet** (`4135c726`), Alpines musl 1.2.5 exportiere kein `posix_getdents`, das das
  native Claude ab 2.1.64 brauche. Das ist ungeprüft. Unser 3.1.3 läuft auf Alpine 3.21 (musl 1.2.5) mit
  aktuellem Claude, daher besteht kein Handlungsbedarf. Das ist nur eine Notiz für den Fall eines Ladefehlers.

---

## Teil 4: die kleinen heytcass-Forks (44 Forks)

Grundlage: `.tmp/hk-lists/<owner>.tsv` für alle Forks außer TomaszBankowski, owine, mattbsea,
cabinlab, evandepol, abhikmitra, weiting-tw, KadenThomp36, msvinth, alexcf, FleshDK,
heman22union und Maheidem. Abgeglichen wurde mit `claude-workbench/` (3.1.3). Für WKassebaum
und JoshDev gibt es keine eigene Liste: Die fünf Commits von WKassebaum/feat/persistent-claude-native
stecken in der ToRa89-Liste. JoshDev/fix/native-claude-runnable-fallback (940f2fd8) prüft, ob
`claude --version` läuft; das haben wir schon (`run.sh` Z. 402–418).

### 1. Kurzfazit

Bei den kleinen Forks ist wenig dabei. Etwa die Hälfte sind Notreparaturen aus der Zeit
um den März 2026, als die Installation brach: Umstieg auf npm, Debian statt Alpine, ttyd als
fertiges Binary, musl aus Alpine edge. Das lösen wir längst mit „nativ, sonst npm“ samt Timeout.
Dazu kommen persönliche Umbenennungen und Versions-Bumps. Für uns brauchbar sind ein möglicher
**ripgrep-Fehler unter musl**, den wir noch prüfen müssen (cgidfar), die **Volume-Mappings
`share`/`addons`** (Darrennchan8, mspnr) und ein Doku-Satz von umrath dazu, dass **jedes
Backup das lokal gebaute Image enthält**. Dazu kommen ein paar kleine Komfort-Optionen
(Startverzeichnis, zusätzliche Claude-Argumente, eigene tmux-Konfiguration). Die
„Security-Hardening“-Commits von daspl1ff und Arborist-ai sind großteils Theater für einen
Root-Container mit nur einem Nutzer. Übernehmen muss man davon nichts.

### 2. Kandidaten (nach Nutzen sortiert)

| Fork | Commit(s) | Inhalt | Nutzen für uns | Empf. | Aufwand |
|---|---|---|---|---|---|
| cgidfar | 422152f3 | Für die native musl-Binary werden `libgcc`, `libstdc++` und **`ripgrep`** installiert und `ENV USE_BUILTIN_RIPGREP=0` gesetzt. Im Commit steht: „Claude's bundled ripgrep doesn't work on musl“. | Bei uns gibt es weder ripgrep noch `USE_BUILTIN_RIPGREP` (grep über `claude-workbench/`, `docs/`, `tests/` findet nichts). Funktioniert der mitgelieferte rg unter musl nicht, versagen Claudes Grep/Glob-Suche und die @-Dateisuche, ohne dass man es merkt. libgcc/libstdc++ kommen bei uns vermutlich schon über `nodejs` mit, das ist aber nicht geprüft. | 🟡 | klein |
| Darrennchan8 (expand-volume-maps), mspnr | 103ac8b9, 2437e048 | Zusätzliche Mappings `addons`, `share`, `media`, `backup`, `ssl` (Darrennchan8: „the same folders as Studio Code Server“). mspnr: nur `share:rw`. | Wir mappen nur `homeassistant_config` und `all_app_configs` (`config.yaml` Z. 62–68). Ohne `share` kein Datenaustausch mit anderen Apps, ohne `addons` keine Entwicklung lokaler Apps. Laut Diff-Kontext hat heytcass/main inzwischen selbst `share:rw`. | 🟡 | klein |
| umrath | 5b8c576d | Doku: Ohne `image:` exportiert der Supervisor das lokal gebaute Image in **jedes Backup**. Das lässt sich nicht abstellen, nur durch einen Teil-Backup ohne die App umgehen. | Wir setzen auch kein `image:`. In `DOCS.md` steht der Image-Umfang bisher nur beim Teil-Backup der Übernahme (Z. 34–35), der Hinweis zu jedem regulären Backup fehlt. Nimmt Nutzern die Überraschung „Backup plötzlich mehrere hundert MB größer“. | 🟡 | klein |
| ToRa89 (auch in heytcass/main) | 26b07458 | Option `working_directory` (Standard `/config`), optional `prompt_working_directory` mit `pick-working-dir.sh` | Bei uns ist das Startverzeichnis fest `/config` (`Dockerfile` Z. 139). Eine Option für z. B. `/config/appdaemon` oder `/share` ist praktisch. Den Teil `claude_data_path` (Credentials nach `/config`) **nicht** übernehmen, sonst landen Zugangsdaten in `/config` und damit in jedem Backup. | 🟡 | klein |
| ToRa89 / umrath / monxas | 30816c5c, Fix 601b87ae (umrath security/hardening), f1fef3f5 | Option `claude_extra_args` bzw. `extra_claude_flags`, die beim Start an `claude` angehängt wird | Wir haben nur `dangerously_skip_permissions` und `remote_control`. Viele Flags (Modell usw.) lassen sich auch über `~/.claude/settings.json` setzen, daher nur mäßiger Nutzen. Wenn übernommen, dann so, dass der Wert nur einmal geparst wird: ToRa89s Fassung bricht bei Anführungszeichen, umrath hat das korrigiert. Bei uns wie bei `remote_control_session_name` mit `printf %q` oder als Array (`run.sh` Z. 570–575). | 🟡 | klein |
| BartBourgeois | dc56696d | `~/.tmux.conf` nur beim ersten Start installieren, damit eigene Anpassungen erhalten bleiben | Bei uns überschreibt `setup_tmux` die Datei bei jedem Start (`run.sh` Z. 312, `cat >`), weil `tmux_mouse` hineingeneriert wird. Der Fork-Ansatz würde die Option aushebeln. Besser: am Ende der Datei `source-file -q ~/.tmux.conf.local`. Der restliche Commit (IS_SANDBOX, HA-CONTEXT.md) ist bei uns vorhanden oder entfällt. | 🟡 | klein |
| Arborist-ai | 40083ab9, bb69f70a | Option `auto_resume_session`: Autostart mit `claude -c`, ohne vorhandene Sitzung neu (`claude-smart-resume.sh`) | Dank tmux brauchen wir das beim Neuladen des Browsers nicht. Nach einem Neustart der App startet Claude aber leer. Nur die Idee taugt (`claude --continue \|\| claude`). Die Erkennung im Fork sucht an falschen Orten (`conversations.json`, `*.json` im State-Verzeichnis statt `~/.claude/projects`). Unser Picker bietet „Continue“ schon an (`claude-session-picker.sh` Z. 201). | 🟡 | klein |
| monxas | 10bf3d69 | Feld `oauth_code` in der App-Konfiguration. Ein Poller fragt alle 2 s `/addons/self/info` ab und tippt den Code per `tmux send-keys` ein | Das Paste-Problem lösen wir über Toolbar und Clipboard (`image-service/public/index.html` Z. 385 ff., `terminal-clipboard.js`). Der Dauer-Poller gegen den Supervisor ist Overhead, und der Code landet kurz in den Optionen. | ❌ | – |
| billsq | 1fd78d77, dcd961a1 u. a. | Option `environmental_variables` (Liste `KEY=VAL`, wird exportiert) | Für Claude reicht `env` in `~/.claude/settings.json`. Die Umsetzung zerlegt Werte an Leerzeichen und schreibt alle Werte ins Log, also auch Secrets. Berührt außerdem die zurückgestellten `anthropic_*`-Optionen. | ❌ | – |
| Arborist-ai | 1ff56851, efa4ff07, 34e23f15 | `uv`/`uvx` ins Image (für den MCP-Server ha-mcp) | Gehört zur zurückgestellten HA-MCP-Auto-Registrierung und löst sie nicht besser. Bei Bedarf über `persist-install`. | ❌ | – |
| lcoppenr | 27f0fa96, 888317de | SSH-Server (aus PR #92) mit gehärteter `sshd_config` (nur Pubkey, `PermitRootLogin prohibit-password`, ohne X11) | SSH ist zurückgestellt. Die Härtung ist Standard und nicht deutlich besser als andere Lösungen. Falls SSH je kommt: die `sshd_config` aus 27f0fa96 ist eine brauchbare Vorlage. | ❌ | – |
| 7c | 808baa3c | `ENV IS_SANDBOX=1` im Dockerfile, `--dangerously-skip-permissions` **standardmäßig an** | IS_SANDBOX haben wir (`run.sh` Z. 124 und 153). Die Freigabe ohne Rückfrage als Standard lehnen wir ab, bei uns ist sie Opt-in. | ❌ | – |
| daspl1ff, Arborist-ai | 4733fd66, cd6da3aa, c2027f2e, 6f6ece23, 2d3f3d69, 001b851a | „Security“: Allowlist bei der eigenen Claude-Eingabe im Picker, Auth-Code-Validierung, chmod 700/600, Symlink-Prüfungen, `hassio_role: default`, `homeassistant_api: false`, HEALTHCHECK auf 7681 | Die „Command Injection“ im Picker betrifft den Nutzer, der ohnehin eine Root-Shell hat, ist also keine Lücke. Die Rechte-Absenkung bricht `ha`/API-Funktionen. Der HEALTHCHECK auf 7681 passt nicht zu unserer Architektur (Health-Check des Image-Service gibt es). Siehe Abschnitt 4 zu `/tmp/claude-auth-code`. | ❌ | – |
| replicatorbe | a1594cba | Claude als Nicht-Root-Nutzer `claude` über `su -` | Erledigt sich durch IS_SANDBOX. Schreibrechte auf `/config` und das Credential-Layout wären zu umzubauen. | ❌ | – |
| replicatorbe | 001daea7, 966b7570, ba99c501 | homeassistant-cli über pip/pipx, `allowedTools` auf `ha`-Befehle beschränkt (in `config/claude-config/.claude.json` des Repos) | Bei uns schon vorhanden: `ha` als Binary (`Dockerfile` „Install Home Assistant CLI“) und `persist-install --ha-cli`. Die Beschränkung ist eine persönliche Einstellung. | ❌ | – |
| petterl | 90a3b1c7 | HTTP-API (`claude -p`) auf Port **7682, als Host-Port veröffentlicht**, ohne Authentifizierung | Sicherheitslücke, siehe Abschnitt 4. | ❌ | – |
| petterl | c856e81d, a132daca, 4af2cc00 | tmux-Persistenz, tmux.conf mit OSC 52 (`set-clipboard on`) | Bei uns schon vorhanden (`run.sh` Z. 312–339). | ❌ | – |
| jokerigno | df86b565, eeea4097 | ttyd `--ping-interval` und Reconnect-Optionen | Bei uns schon vorhanden (`run.sh` Z. 787–788: `--ping-interval 30`, `reconnect=5`). | ❌ | – |
| weebl2000, ToRa89 | 92918faa, 36c1c113, 86dc01db | Claude beim Start aktualisieren, persistente native Installation, npm-Cache aus `/data` | Bei uns schon vorhanden (`use_persistent_claude`, `auto_update_claude_on_start`, npm-Cache nach /tmp). | ❌ | – |
| ToRa89 | ad3712d1, 1d4d5956, 74b2b1b3, 6b16a0b2, 3ae959b5, d09c2741 | ha-mcp-Pin, Shellcheck-Fixes am eigenen health-check, Welcome-Banner, `$HOME` statt fester Pfade, SSH | Wir haben kein ha-mcp und kein welcome.sh. Bei unserem health-check läuft Shellcheck in der CI. SSH ist zurückgestellt. | ❌ | – |
| dnhrdt (fix/oauth-persistence-complete) | 067a61e3 | Symlink `/root/.claude` → `/data/.claude` für OAuth-Persistenz | Bei uns gelöst über `HOME=/data/home`, Credentials in `/data/home/.claude` (DOCS.md Z. 163). | ❌ | – |
| cgidfar (fix-nuc-install) | 422152f3 (Installation), 498c460b, 329cfb2c | Kaskade: Binary direkt aus GCS mit SHA256-Prüfung und `--version`-Test, dann install.sh, dann npm | Unser Weg „install.sh mit Timeout, sonst npm“ (`Dockerfile` Z. 81–83) reicht. Siehe Abschnitt 4 zum `--version`-Test. | ❌ | – |
| basketball00011 | db83b2fd, 5fc82953 u. a. | Ollama als Backend (`ANTHROPIC_BASE_URL`) | Andere KI-Backends haben wir bewusst verworfen. | ❌ | – |

Zu den ✅/🟡-Zeilen, wohin es gehört und ob es Sicherheitsfragen gibt:

- **ripgrep (cgidfar):** gehört in `claude-workbench/Dockerfile`: `ripgrep` in die `apk add`-Liste, `ENV USE_BUILTIN_RIPGREP=0`. Keine Sicherheitsfrage. **Vorher prüfen:** In der laufenden App `claude doctor` ausführen bzw. Claude etwas mit dem Grep-Tool suchen lassen. Liefert das Fehler oder leere Treffer, dann umsetzen.
- **Mappings (Darrennchan8/mspnr):** gehören in `config.yaml` unter `map:`. `share` und `addons` mit Schreibrecht sind vertretbar. **`ssl` und `backup` nicht**, auch nicht schreibgeschützt: Private TLS-Schlüssel und Backups mit Secrets gehören nicht in eine Root-Shell ohne Passwort, die jeder HA-Nutzer erreicht. Größerer Zugriff vergrößert den Schaden bei einem Fehlgriff, das gehört in DOCS.md.
- **Backup-Doku (umrath):** gehört in `DOCS.md`, Abschnitt Installation/Speicher. Keine Sicherheitsfrage.
- **working_directory (ToRa89):** gehört in `config.yaml` (options/schema, Übersetzungen en/de) und in den `cd` vor dem Launch in `run.sh`. Pfad mit `printf %q` quoten. Sicherheit: unkritisch.
- **claude_extra_args:** gehört in `run.sh` → `get_claude_launch_command` und `claude-session-picker.sh`. Sicherheit: Der Wert stammt aus der Admin-Konfiguration. Der Quoting-Fehler (Wert zweimal geparst) muss vermieden werden, sonst startet das Terminal nicht.
- **tmux.conf.local (BartBourgeois, angepasst):** gehört ans Ende des Heredocs in `run.sh` `setup_tmux`. Unkritisch.
- **Auto-Resume (Arborist-ai, nur die Idee):** gehört als Option in `run.sh` `get_claude_launch_command`. Unkritisch.

### 3. Gesichtet, nichts dabei

- **7c**: README-URLs auf den eigenen Fork, Rest siehe Tabelle (Freigabe ohne Rückfrage als Standard).
- **Arborist-ai**: 146032dc/9b80c17f/63fc3375 sind Upstream-Integration und Doku, 268087d2 ein `~/.local/bin`-Symlink (haben wir), 330ee356 `homeassistant_api` (haben wir).
- **BartBourgeois**: 54f32ed9 ist nur ein Versionsformat.
- **CodyJon**: 10 Commits rund um npm statt install.sh und Symlink-Reparatur, das deckt unser Fallback ab.
- **Darrennchan8**: 2d937faa/f97e7425/d78c1dc3/deab131e sind Fork-Sync-Mechanik und Umbenennung.
- **Fireblade80, IworiKoso, JC-GRCC-GIT, clavdal, daco-tech, jfgreco (c3d2a4f8), kowal119, Lentomannen, todd3mecom**: jeweils nur npm statt install.sh. kowal119 begründet das mit AVX, was wir bewusst verworfen haben.
- **anphex**: npm-Installation, ttyd im Image (haben wir), persist-config-Hin-und-Her (78eb1187 wieder zurückgenommen in c25a1234).
- **c0linzeal, chackneyrules, hack2spider, mfjpeachey, raulpuente**: Umbau auf Debian/apt, ttyd von GitHub-Releases. Passt nicht zu unserer Alpine-Basis. c0linzeal 17620e58 ist ein fremdes Windows-Projekt.
- **masterchiefofbikeride**: musl aus Alpine **edge** auf Basis 3.21, das Risiko ist zu hoch.
- **rweijnen**: `apk update` vor `apk add --no-cache`, wirkungslos.
- **tecman77**: gepinnte curl-/vim-Versionen, persönlich.
- **graphicgenie**: nur CHANGELOG/Version, die Werkzeuge haben wir.
- **LynSisCZ**: Dev-Toolkit (Python-Bibliotheken, vim, tree usw., haben wir; postgresql-client/openssh-client gehen über persist-install), eigene ttyd-HTML-Seite (selbst wieder zurückgenommen, 20f43a47), IS_SANDBOX (haben wir).
- **clutchthrower**: Umbau auf OpenAI Codex (verworfen).
- **markopolopb**: nur Shellcheck-Workflow für Kiro/Goose/Gemini-Apps.
- **meagerfindings, mspnr (f514afe9), replicatorbe (368335c7, 2ddaed8a, 80e739f0, 26da63f2, 3c31a3fd, 8920d188)**: Name/Slug/Version für parallele Installation, persönlich.
- **djasper-ha, juli734, mspnr (eae273b1)**: `addon_configs` einbinden (haben wir: `all_app_configs:rw`).
- **jfgreco e4761cf1**: eigener GitHub-Workflow.
- **umrath**: 0053bda3 lokal bauen statt GHCR (machen wir), 54beda70 Workflows gestrichen, 8d96105c auth_api (haben wir entfernt), 7c8c8b28 Doku „jeder HA-User erreicht das Panel“ (schon aus heytcass vorgemerkt), 24f23fce/a6640c0a Release-Commits. 37c8787c siehe Abschnitt 4.
- **monxas**: f1fef3f5/ba6c1b10 Freigabe ohne Rückfrage plus IS_SANDBOX (haben wir), zusätzliche Flags siehe Tabelle.
- **lcoppenr**: e87e918b CalVer-Rebranding und Doku.
- **ToRa89**: 3ae959b5 betrifft nur SSH-Schlüssel.

### 4. Auffälligkeiten

1. **petterl 90a3b1c7: offene Claude-API ohne Login.** `claude-api-server.py` läuft standardmäßig (`api_enabled: true`) auf Port 7682, der in `ports:` als `7682/tcp: 7682` veröffentlicht ist. Jeder im LAN kann ohne Authentifizierung `claude -p` als Root starten, mit Zugriff auf `/config` und den Supervisor. Bei uns gibt es so etwas nicht, und `tests/test-release-metadata.sh` verbietet `ports:`. Nur als Warnung, falls jemand diesen Fork vorschlägt.
2. **Bei uns: `scripts/claude-auth-helper.sh` lässt den Auth-Code in `/tmp/claude-auth-code` liegen.** Z. 36 schreibt die Datei, gelöscht wird sie nirgends (nur `/config/auth-code.txt` wird in Z. 65 entfernt). Außerdem wird der Code per `echo "$auth_code" | claude` an Claude übergeben (Z. 42/62). Bei nicht-interaktiver stdin läuft Claude vermutlich nicht im Login-Dialog, die Hilfe dürfte also wirkungslos sein. **Nicht live geprüft.** Daspl1ff und Arborist-ai haben die Datei abgesichert. Für uns liegt näher, die Hilfe zu prüfen bzw. zu entfernen, weil Toolbar und Clipboard den Login ohnehin abdecken. Kleines Risiko, da der Container nur einen Nutzer hat. Die Datei überlebt aber bis zum nächsten Neustart.
3. **umrath 37c8787c: SUPERVISOR_TOKEN landete im Klartext in `/data/home/.claude.json`** und damit in jedem Backup, weil `claude mcp add --env "TOKEN=${SUPERVISOR_TOKEN}"` den Wert in der Shell auflöst. Bei uns gibt es keine automatische MCP-Registrierung, wir schreiben den Token nirgends hin (grep: nur `ha-api-examples.sh` liest ihn aus der Umgebung). **Falls die zurückgestellte HA-MCP-Auto-Registrierung kommt:** den Token wie umrath als Literal `'${SUPERVISOR_TOKEN}'` eintragen.
4. **musl/`posix_getdents`:** JoshDev (940f2fd8) schreibt, neuere native Claude-Builds bräuchten `posix_getdents`, das die musl 1.2.5 in Alpine 3.21 nicht habe. masterchiefofbikeride (287cc17f) setzt die Grenze dagegen bei 1.2.4. Unser Laufzeit-Fallback prüft nur die persistente Binary mit `--version` (`run.sh` Z. 402–418). Die im Image unter `/usr/local/bin/claude` liegende Kopie wird im Dockerfile nicht mit `claude --version` getestet. Das passt zum schon vorgemerkten Boot-Smoke-Test bzw. Health-Check mit `claude --version`: dort mit abdecken.
5. `run.sh` Z. 81 setzt `chmod 755` auch auf `$claude_config_dir`. Im Root-Container mit nur einem Nutzer ist das folgenlos. Ändern muss man es nicht, es wird hier nur notiert, weil zwei Forks es als „kritisch“ führen.

---

