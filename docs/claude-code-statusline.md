# Claude Code Status Line (oh-my-posh)

A custom `oh-my-posh` status bar for Claude Code CLI showing git context, model info, token usage, and battery.

## Prerequisites

- [Claude Code](https://claude.ai/code) installed
- [oh-my-posh](https://ohmyposh.dev/docs/installation/linux) installed and on `$PATH`
- A [Nerd Font](https://www.nerdfonts.com/) configured in your terminal

Verify oh-my-posh has Claude segment support. The basic `claude` subcommand
landed in v24, but the `Sess`/`Week` rate-limit segment uses
`FiveHourUsage` / `SevenDayUsage` which were added later — **v29.13+ is
required** for that segment to render (it is guarded with `{{ if }}`, so older
versions still work, the segment just hides).

```bash
oh-my-posh --version
```

If you need to upgrade and the binary is root-owned (e.g. `/usr/local/bin/oh-my-posh`),
`oh-my-posh upgrade` may silently no-op. Download the release binary manually
instead:

```bash
sudo curl -fsSL -o /usr/local/bin/oh-my-posh \
  https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64
sudo chmod +x /usr/local/bin/oh-my-posh
```

## Setup

**1. Copy the config file**

```bash
cp oh-my-posh/claude-code.omp.json ~/.claude.omp.json
```

**2. Merge the `statusLine` block into `~/.claude/settings.json`**

The snippet is provided as `oh-my-posh/claude-code-settings.json`. Add the `statusLine` key to your existing settings:

```json
{
  "statusLine": {
    "type": "command",
    "command": "oh-my-posh claude --config ~/.claude.omp.json",
    "padding": 0
  }
}
```

Restart Claude Code — the status bar appears at the bottom of every session.

## What Each Segment Shows

### Left

| Segment | Shows |
|---------|-------|
| **Path** | Inside a git repo: repo name + relative path. Outside: plain path. Fish-style shortened. |
| **Git** | Branch, upstream icon, working/staged change counts, ahead/behind coloring |

### Right

| Segment | Shows |
|---------|-------|
| **Model** | Current Claude model display name (e.g. `Sonnet 4.6`) |
| **Ctx** | Token count / context window size / usage % (e.g. `14.1K/400K (0%)`) |
| **Usage** | 5-hour session usage % + reset time · 7-day usage % + reset date |
| **Battery** | Charge %, color-coded by state (charging / discharging / full) |

## Color Coding

| Color | Meaning |
|-------|---------|
| Yellow git background | Uncommitted working or staged changes |
| Red git background | Diverged from upstream (ahead AND behind) |
| Purple git background | Ahead of upstream |
| Dark purple git background | Behind upstream |

## Windows / PowerShell (pwsh)

The theme defines two `prompt` blocks: a **left**-aligned block (path, git) and
a **right**-aligned block (model, ctx, usage, battery). How those two blocks lay
out depends on whether oh-my-posh can detect the terminal width when Claude Code
invokes it.

Claude Code runs the `statusLine` command non-interactively (it pipes JSON to
the command — there is no real TTY), so width detection differs by platform:

| Platform | Width detection | Result |
|----------|-----------------|--------|
| **WSL2 / bash** | No TTY and `COLUMNS` is not exported into the piped process, so width is unknown | The right block can't be pushed to the edge, so both blocks render back-to-back as **one contiguous bar** |
| **Windows / pwsh** | oh-my-posh queries the Windows console API directly and gets the real column count | The right block is pushed to the right edge, opening a **gap** between the two blocks |

So the "gap" on pwsh is oh-my-posh correctly right-aligning the second block —
not a bug. WSL just happens to render the contiguous look because it can't
measure the width.

### Make pwsh match the contiguous (no-gap) look

Change the second block's alignment from `right` to `left` so both blocks chain
into a single left-aligned powerline regardless of width:

```jsonc
{
  "type": "prompt",
  "alignment": "left",   // was "right"
  "segments": [ /* model, ctx, usage, battery */ ]
}
```

Trade-off: with everything left-aligned, on a narrow terminal the bar runs long
and truncates on the right instead of staying glued to the edge. At typical
widths it's just a tidy single bar.

> Note: the live Windows config (`%USERPROFILE%\.claude\claude-code.omp.json`)
> also adds a leading `session` (hostname) segment that the Linux variant in
> this repo omits.
