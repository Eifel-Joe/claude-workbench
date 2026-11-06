## Safer package options, a more complete data takeover

- **Package names from the options are checked first.** An entry under the persistent package options such as `--ha-cli` or `-p` (or even `ha` or `python`) used to start another installer mode, and a leading `-` reached apk or pip as a switch. Such entries are now skipped with a warning in the log; version pins and extras still work. The app installs with the new explicit form `persist-install --apk`. The data takeover from an older app checks its package names the same way.
- **The data takeover brings more along:** `statusline` and `home_assistant_plugin` from ESJavadex's Claude Terminal Pro, and its Remote Control switch (`enable_remote_control`, lost so far), as `remote_control` with the session name "Home Assistant". A plugin removed by hand in the old app stays removed.
- **`ha-statusline --refresh` waits** for a refresh already running instead of reporting success without doing anything.
- **A takeover offered on a later start keeps your old Claude settings:** while the check for an older app has not decided (e.g. the Supervisor did not answer), the status line and the plugin wait instead of writing to `~/.claude`.

**Check after the update:** add `--ha-cli` and `htop` under the persistent system packages and restart: the log skips `--ha-cli` with a warning and installs `htop`. In the terminal, `ha-statusline --refresh & ha-statusline --refresh; echo $?` prints `0`.

The package name check comes from unsnow-iac (`08686e1e`, found in miczu71's fork, branch `history/unsnow-full`; `83c6997e`). Status line and Home Assistant plugin are by ESJavadex. Full details: [CHANGELOG](https://github.com/Eifel-Joe/claude-workbench/blob/main/claude-workbench/CHANGELOG.md).
