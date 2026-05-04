---
description: List local repos so the user can pick one to open with clrepo
allowed-tools: ["Bash"]
argument-hint: "[repo-name]"
---

If `$ARGUMENTS` is set, treat it as a repo name. Otherwise, list the
available local repos so the user can pick one.

If a repo name was provided:
- Tell the user to open it from a host shell with `clrepo $ARGUMENTS`.
  (Launching a Claude session from inside another Claude session via the
  Bash tool would block this current session, so we don't run `clrepo`
  directly here.)

If no repo name was provided:
- Run `find $HOME/projects/repos -type d -name '_archive' -prune -o -type d -name .git -printf '%h\n' 2>/dev/null | sed "s|^$HOME/projects/repos/||" | sort` using the Bash tool.
- Show the result as a fenced code block, with a one-line tip at the top:
  "Pick one and open from a host shell with `clrepo <name>`."
