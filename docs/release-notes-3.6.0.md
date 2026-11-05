## Alpine 3.24

- **The app now runs on Alpine 3.24.** Alpine 3.21 has been out of security support since 1 November 2026. In the terminal you get Python 3.14, Node.js 24 and tmux 3.7c. The image also picks up Alpine security fixes released after the base image was published.
- **Startup survives a briefly unreachable Supervisor.** The new base's bashio would have aborted startup, or left the terminal session empty, whenever reading an app option failed. Every option now falls back to its default.
- **Your Python packages come back.** Packages installed with `persist-install --python` live in a venv that belongs to Python 3.12. On the first start the app rebuilds it for 3.14 and reinstalls them. Anything that fails is tried again on the next start.
- **Old library copies can't break the panel.** Copies of system libraries that `persist-install` made on 3.21 are moved to `/data/packages/stale-alpine-3.21`, and the log names the packages to reinstall.

**Upgrade notes:** the first start after the update takes longer and needs the network if you have Python packages from `persist-install`. Then check the app log for `Python changed from 3.12 to 3.14`, `Reinstalling: …` and any `Could not reinstall` or `installed with persist-install on 3.21` lines, and reinstall the packages it names. Details: "After an update to a new Alpine release" in [PERSISTENT_PACKAGES.md](https://github.com/Eifel-Joe/claude-workbench/blob/main/claude-workbench/PERSISTENT_PACKAGES.md).

The move to Alpine 3.24 follows Neil Sleightholm (nsleigh, ESJavadex/claude-code-ha#56) and heytcass (heytcass/home-assistant-addons#154), who took the base image move and `apk upgrade` from owine's fork. The option-read fallbacks and the venv rebuild are adapted from both. The CI boot test builds on heytcass (#139) and unsnow-iac. Thank you! Full details: [CHANGELOG](https://github.com/Eifel-Joe/claude-workbench/blob/main/claude-workbench/CHANGELOG.md).
