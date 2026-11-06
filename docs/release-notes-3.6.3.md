## Persistent programs first in Claude's terminal again

- **Fix for 3.6.2:** In the terminal window Claude starts in (and in the session picker's shell), programs you installed with `persist-install` came after the image's own again. tmux gives a new session's first window the `PATH` of the program that creates the session, and since 3.6.2 that is the app's start with the system's programs first. The window now sets its own `PATH`; the app's start and services keep the system's programs first.
- New tmux windows and login shells were not affected; libraries from `persist-install` (`LD_LIBRARY_PATH`) were not affected either.

**Check after the update:** in the session picker's shell (option 8), `echo $PATH` starts with `/data/packages/bin`.

The system-first start comes from unsnow-iac (`08686e1e`, `83c6997e`). Full details: [CHANGELOG](https://github.com/Eifel-Joe/claude-workbench/blob/main/claude-workbench/CHANGELOG.md).
