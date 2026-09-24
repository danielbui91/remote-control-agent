# Remote Control Agent (macOS + Windows)

Control your computer from your phone. A Claude Code session runs **on the machine**; your phone is a window into it.

**No API key, ever.** Everything here runs on your Claude subscription, because Claude Code is the thing driving the desktop. There is nothing to sign up for, nothing to pay per token, and no credential stored in this folder.

```
        your phone                    this machine
  ┌────────────────────┐        ┌──────────────────────────┐
  │  Claude app / web  │◄──────►│  claude --remote-control │
  └────────────────────┘        │            │             │
      you type a task           │            ▼             │
      you tap Approve           │     mac.sh / win.ps1     │
                                │            │             │
                                └────────────┼─────────────┘
                                             ▼
                                        your desktop
```

Two ways to drive the desktop, in order of preference:

1. **By name** — `click Maps "Zoom in"`. Reads the accessibility tree, so it doesn't break when a window moves.
2. **By coordinate** — `shot`, Claude looks at the picture, `click-at 412 380`. For controls that expose no name.

Both need nothing installed beyond what ships with the OS.

---

# Balack

You rarely need to type these commands yourself. **Balack** is a subagent at
`~/.claude/agents/balack.md` that knows this whole document — every session and
project on this machine can hand him a visual task:

```
Balack, what's on screen right now?
Balack, switch Calculator to Scientific
@agent-balack fill in the form in that app
```

He tries named controls first, falls back to the menu bar, then keystrokes, then
coordinates, and verifies before reporting. He will stop and hand back rather than
do anything destructive or type a credential.

Keep him in sync with this file — he has the display geometry and the gotchas
baked in, so if `mac.sh` gains a command or your monitors change, update both.

---

# Part 1 — Reach the machine from your phone

## 1.1 Start a Remote Control session

In this folder, on the machine:

```bash
claude --remote-control "desktop agent"
```

Or type `/remote-control` inside a session you already have open — that carries the conversation over. Press **spacebar** for a QR code.

Then open it from the Claude app on [iOS](https://apps.apple.com/us/app/claude-by-anthropic/id6473753684) / [Android](https://play.google.com/store/apps/details?id=com.anthropic.claude), or [claude.ai/code](https://claude.ai/code).

Requires a Pro, Max, Team, or Enterprise plan. API keys are not supported for Remote Control — which suits this project fine.

## 1.2 Push notifications

`/config` → **Push when actions required** and **Push when Claude decides**.

Two things that make this look broken when it isn't:

- These rows only appear in `/config` **once Remote Control is active**. Start the session first.
- Pushes are **deliberately suppressed while you're focused on the connected terminal**. Walk away from the machine to test it.

## 1.3 Keeping it alive

Remote Control is a local process. If the terminal closes or the machine sleeps, the session goes offline. To survive an SSH disconnect, start it inside `tmux` or `screen`.

## 1.4 Approvals

You get Claude Code's own permission prompts, forwarded to your phone and held open until you answer. That is the safety gate: nothing runs while you're away unless you tapped Approve, or you pre-approved that command in your settings.

---

# Part 2 — Setup

## 2.1 macOS

Grant **Accessibility** to the app that owns your terminal. Not to a script — to the *app*:

**System Settings → Privacy & Security → Accessibility → +** → Visual Studio Code (or iTerm, or Terminal). Restart it afterwards.

To find which app that is, walk up from your shell:

```bash
pid=$$; while [ "$pid" -ne 1 ]; do ps -o pid=,ppid=,comm= -p "$pid"; pid=$(ps -o ppid= -p "$pid"|tr -d ' '); done
```

Without it, UI commands fail with `not allowed assistive access (-1719)` and synthetic clicks are silently dropped.

For `shot` you also need **Screen Recording**, granted to the same app.

```bash
chmod +x mac.sh
```

## 2.2 Windows

Nothing to install — UI Automation and the Win32 APIs ship with the OS. Two caveats:

- PowerShell can't drive a window running **as Administrator** unless PowerShell is elevated too.
- If scripts are blocked: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

> `win.ps1` mirrors `mac.sh` command for command, but has **not been run on a real Windows machine yet**. Treat the first session as a debugging run.

---

# Part 3 — The commands

## 3.1 Discovery and named controls

| | macOS | Windows |
|---|---|---|
| Apps with a UI | `./mac.sh apps` | `.\win.ps1 apps` |
| Window titles | `./mac.sh windows Maps` | `.\win.ps1 windows notepad` |
| Every labelled control | `./mac.sh tree Maps` | `.\win.ps1 tree notepad` |
| Search controls | `./mac.sh find Maps Zoom` | `.\win.ps1 find notepad Save` |
| Top-level menus | `./mac.sh menus Calculator` | — (use `tree`) |
| Items under a menu | `./mac.sh menu-items Calculator View` | — (use `tree`) |
| Start an app | `./mac.sh launch Calculator` | `.\win.ps1 launch notepad` |
| Bring to front | `./mac.sh activate Maps` | `.\win.ps1 activate notepad` |
| Click by name | `./mac.sh click Maps "Zoom in"` | `.\win.ps1 click notepad OK` |
| Click a menu item | `./mac.sh menu Calculator "View>Scientific"` | `.\win.ps1 menu notepad "File>Save"` |
| Type into the focused app | `./mac.sh type "hello"` | `.\win.ps1 type "hello"` |
| Send a key combo | `./mac.sh key cmd+s` | `.\win.ps1 key ctrl+s` |

`cmd` is accepted on Windows and mapped to `ctrl`, so the same phrasing works from your phone on either machine.

## 3.2 Pointer control

For controls with no name. Same on both platforms:

| | |
|---|---|
| `click-at <x> <y>` | click at a point |
| `right-click-at <x> <y>` | right-click |
| `double-click-at <x> <y>` | double-click |
| `move-to <x> <y>` | hover without clicking |
| `drag <x1> <y1> <x2> <y2>` | drag |
| `scroll <amount> [x y]` | positive scrolls up |
| `where` | current cursor position |

## 3.3 Screenshots and the coordinate trap

| | macOS | Windows |
|---|---|---|
| Screenshot a display | `./mac.sh shot /tmp/s.png 1` | `.\win.ps1 shot C:\temp\s.png` |
| Screenshot one window | `./mac.sh shot-app Maps /tmp/s.png` | `.\win.ps1 shot-app notepad C:\temp\s.png` |
| List displays | `./mac.sh displays` | `.\win.ps1 displays` |

**Coordinates are global points, not screenshot pixels.** On a Retina Mac a screenshot is 2× the points, so a coordinate read straight off the image lands at half the distance from the origin. `displays` prints what you need:

```
$ ./mac.sh displays
display 1  origin 0,0       size 1920x1080  scale 1
display 2  origin -1116,70  size 1116x756   scale 2  (screenshot is 2x these points)
```

```
point = origin + (pixel / scale)
```

On Windows this is handled for you — the script calls `SetProcessDPIAware()`, so screenshot pixels match coordinates 1:1 even at 125% or 150% scaling.

---

# Part 4 — The workflow

## 4.1 Prefer names

**Discover, then act** — never guess a control name:

```bash
./mac.sh tree Maps              # what is actually on screen?
./mac.sh click Maps "Zoom in"   # now click something that exists
```

A click either resolves or fails loudly, instead of landing in the wrong place:

```
$ ./mac.sh click Calculator 7
no control labelled '7' in the front window of Calculator
hint: ./mac.sh tree Calculator   shows what is actually labelled
```

## 4.2 When an app exposes no names

Not every app cooperates. Run `tree` first and look at what comes back:

```
$ ./mac.sh tree Maps | head -3        $ ./mac.sh tree Calculator | head -3
button :: Compass                     button :: button
button :: Zoom in                     button :: button
button :: Hide Sidebar                button :: button
```

Maps names its controls; Calculator (SwiftUI) does not — its 19 keypad buttons are all just `button`. Three escalating fallbacks:

1. **Use the menu bar.** Almost always well exposed even when the window isn't — `./mac.sh menu Calculator "View>Scientific"` works fine.
2. **Use keystrokes.** Many apps accept them: `./mac.sh type "12*34"` then `./mac.sh key return`.
3. **Use coordinates.** Screenshot it, let Claude look, convert, click.

## 4.3 Worked example — clicking by coordinate

Pressing Calculator's `7`, which has no name. Calculator is on the Retina display.

```bash
$ ./mac.sh shot-app Calculator /tmp/c.png     # 396x700 pixels
$ ./mac.sh displays
display 2  origin -1052,183  size 198x350  scale 2
```

Claude reads the image and puts the `7` centre at pixel (60, 365). Converting:

```
x = -1052 + 60/2  = -1022
y =   183 + 365/2 =   366
```

```bash
$ ./mac.sh click-at -1022 366
clicked -1022,366
$ ./mac.sh tree Calculator | grep "static text"
static text :: 7
```

Chaining `7`, `×`, `8`, `=` gives `56`. That is the whole of pixel-level computer use, on your subscription.

---

# Troubleshooting

- **`not allowed assistive access (-1719)`** — Accessibility isn't granted to the terminal's owning app. See 2.1. Restart the app after granting.
- **Clicks move the cursor but nothing happens** — usually Accessibility again; macOS lets a process move the pointer but silently drops its synthetic clicks. Check 2.1 before anything else.
- **`tree` returns nothing, or everything is called `button`** — the app doesn't expose names. See 4.2.
- **`'X' has no open window`** — the app is running but has no window up. `apps` lists what's running; open a window first.
- **Clicks land short of the target, toward the top-left** — you used screenshot pixels as coordinates on a Retina display. See 3.3.
- **Blank screenshots on macOS** — Screen Recording missing, or granted to the wrong app. It applies to the app that *owns* the terminal.
- **No push notifications** — see 1.2. Both causes look like a bug and aren't.

# Next steps for reliability

- **Reach for an API before the UI.** If the target app has an API, database, or CLI, use that. Faster and more reliable than any UI automation.
- **Prefer names over coordinates.** Coordinates break the moment a window moves or a display changes.
