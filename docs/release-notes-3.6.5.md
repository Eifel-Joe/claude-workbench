## A takeover from an old app installed later keeps its Claude settings

- **Installed the older app after Claude Workbench?** If Claude Workbench had already run without a Claude login, its status line and Home Assistant plugin had written Claude's `settings.json`, plugin lists and `~/.claude.json`, and the data takeover kept the old app's versions out: its settings, plugins, MCP servers and project approvals did not arrive.
- **Now the old files replace these as whole files**, as long as there is no Claude login in Claude Workbench. Nothing is merged or deleted: the replaced files are kept in `/data/migration/replaced/<date>/`, and the summary after the takeover names the folder. The old files are swapped in only once all of them were copied, so a failed copy changes nothing.

**Check after the update:** the app starts as before; the log shows no takeover offer, the Home Assistant plugin reports "nothing to do" and the status line is shown under Claude's prompt. In the terminal, `ls /data/migration` lists no `replaced` folder.

Status line and Home Assistant plugin are by ESJavadex; their code is unchanged. Full details: [CHANGELOG](https://github.com/Eifel-Joe/claude-workbench/blob/main/claude-workbench/CHANGELOG.md).
