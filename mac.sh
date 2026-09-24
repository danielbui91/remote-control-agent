#!/usr/bin/env bash
#
# Drive macOS from the shell, using AppleScript's accessibility API.
#
# This is the cheap path: it runs under your Claude subscription, because
# Claude Code is the thing driving it. No API key, no screenshots, no pixel
# guessing — it clicks controls by NAME, so it doesn't break when a window moves.
#
# Needs: System Settings -> Privacy & Security -> Accessibility -> the app that
# owns your terminal (Visual Studio Code, iTerm, Terminal...). Without it every
# UI command fails with "not allowed assistive access (-1719)".
#
# Reach for agent.py only when a target has no named controls at all
# (canvas apps, games, remote-desktop windows).
set -euo pipefail

usage() {
    cat <<'USAGE'
usage: mac.sh <command> [args]

  apps                    running apps that have a UI
  windows <app>           window titles of an app
  tree <app>              every labelled control in the app's front window
  find <app> <text>       controls whose label contains <text>
  menus <app>             top-level menu names
  menu-items <app> <menu> items under one menu, e.g. menu-items Safari File

  launch <app>            open an app (starts it if needed)
  activate <app>          bring an app to the front
  click <app> <name>      click the control named <name>
  menu <app> <path>       click a menu item, e.g. "File>Save As…"
  type <text>             type into whatever has focus
  key <combo>             send a combo, e.g. cmd+s, ctrl+shift+tab, return
  shot [path] [display]   screenshot a display (default: /tmp/shot.png, display 1)
  shot-app <app> [path]   screenshot just that app's front window
  displays                displays, their origins and Retina scale

 Pointer control, for controls that expose no name. GLOBAL POINTS, not
 screenshot pixels — divide by the display's scale and add its origin first.
  click-at <x> <y>        click at a point
  right-click-at <x> <y>  right-click
  double-click-at <x> <y> double-click
  move-to <x> <y>         hover without clicking
  drag <x1> <y1> <x2> <y2>
  scroll <amount> [x y]   positive scrolls up
  where                   current cursor position

App names are the ones `mac.sh apps` prints. Quote anything with spaces.
USAGE
}

osa() { osascript -e "$1"; }

# Everything UI-related runs inside "tell process", so failures are consistent.
proc() {
    local app="$1" body="$2"
    osa "tell application \"System Events\" to tell process \"$app\"
$body
end tell" 2>&1 || {
        echo "failed. If this says -1719/-1728, grant Accessibility to your terminal app." >&2
        return 1
    }
}

# Walk the accessibility tree.
#
# NB: AppleScript's `entire contents` is unreliable — on SwiftUI apps it returns
# an EMPTY list even when the window demonstrably has children (Calculator is a
# live example). So we descend explicitly instead. Slower, but it actually works.
#
# argv: <mode> <app> [target]      mode = tree | find | click
ax() {
    # strip osascript's "1234:5678: execution error:" prefix — this text is what
    # you read on your phone, so it should be the message and nothing else
    ax_raw "$@" | sed 's/^[0-9]*:[0-9]*: execution error: //'
    return "${PIPESTATUS[0]}"
}

ax_raw() {
    osascript - "$1" "$2" "${3:-}" <<'AS' 2>&1
global outList
global clickTarget
global didClick

-- A control is addressable by whichever of these it actually fills in.
on labelOf(c)
    tell application "System Events"
        repeat with getter in {"name", "title", "description", "value"}
            set v to ""
            try
                if (getter as text) is "name" then set v to name of c
                if (getter as text) is "title" then set v to title of c
                if (getter as text) is "description" then set v to description of c
                if (getter as text) is "value" then set v to value of c
            end try
            if v is not missing value and v is not "" then
                try
                    return v as text
                end try
            end if
        end repeat
    end tell
    return ""
end labelOf

on descend(el, depth, mode)
    global outList
    global clickTarget
    global didClick
    if depth > 8 or didClick then return
    tell application "System Events"
        set kids to {}
        try
            set kids to every UI element of el
        end try
        repeat with c in kids
            if didClick then return
            set nm to my labelOf(c)
            set cls to "?"
            try
                set cls to class of c as text
            end try
            if nm is not "" then
                if mode is "click" then
                    if nm is clickTarget then
                        try
                            click c
                            set didClick to true
                            return
                        end try
                    end if
                else if mode is "find" then
                    if nm contains clickTarget then set end of outList to cls & " :: " & nm
                else
                    set end of outList to cls & " :: " & nm
                end if
            end if
            my descend(c, depth + 1, mode)
        end repeat
    end tell
end descend

on run argv
    global outList
    global clickTarget
    global didClick
    set outList to {}
    set didClick to false
    set mode to item 1 of argv
    set appName to item 2 of argv
    set clickTarget to item 3 of argv

    tell application "System Events"
        if not (exists process appName) then error "no running app named '" & appName & "'"
        tell process appName
            if (count windows) is 0 then error "'" & appName & "' has no open window"
            set w to window 1
        end tell
    end tell

    my descend(w, 0, mode)

    if mode is "click" then
        if didClick then return "ok"
        error "no control labelled '" & clickTarget & "' in the front window of " & appName
    end if
    set AppleScript's text item delimiters to linefeed
    return outList as text
end run
AS
}


# ---------------------------------------------------------------------------
# Pointer control via CoreGraphics (JXA). Needs nothing installed.
#
# All coordinates are GLOBAL POINTS, not screenshot pixels. On a Retina display
# a screenshot is 2x the points, so divide by that display's scale and add its
# origin before clicking. `mac.sh displays` prints both; `mac.sh shot` reminds
# you of the one it captured. Getting this wrong is what makes clicks land in
# the wrong place.
# ---------------------------------------------------------------------------
cg() {
    osascript -l JavaScript - "$@" <<'JS' 2>&1
function run(argv) {
    ObjC.import('CoreGraphics');
    ObjC.import('AppKit');
    var mode = argv[0];
    var n = function (i) { return parseFloat(argv[i]); };
    var TAP = $.kCGHIDEventTap;
    // Events from a real HID source are treated as genuine input; the null
    // source is ignored or debounced by some apps.
    var SRC = $.CGEventSourceCreate($.kCGEventSourceStateHIDSystemState);
    var post = function (e) { $.CGEventPost(TAP, e); };
    var hold = function () { $.NSThread.sleepForTimeInterval(0.06); };
    var moveTo = function (x, y) {
        post($.CGEventCreateMouseEvent(SRC, $.kCGEventMouseMoved,
             $.CGPointMake(x, y), $.kCGMouseButtonLeft));
    };

    if (mode === 'displays') {
        var screens = $.NSScreen.screens;
        var mainH = screens.objectAtIndex(0).frame.size.height;
        var out = [];
        for (var i = 0; i < screens.count; i++) {
            var f = screens.objectAtIndex(i).frame;
            var scale = screens.objectAtIndex(i).backingScaleFactor;
            // NSScreen is bottom-left origin; CoreGraphics is top-left.
            var cgY = mainH - (f.origin.y + f.size.height);
            out.push('display ' + (i + 1) + '  origin ' + Math.round(f.origin.x) + ',' +
                     Math.round(cgY) + '  size ' + Math.round(f.size.width) + 'x' +
                     Math.round(f.size.height) + '  scale ' + scale +
                     (scale > 1 ? '  (screenshot is ' + scale + 'x these points)' : ''));
        }
        return out.join('\n');
    }

    if (mode === 'move') { moveTo(n(1), n(2)); return 'moved to ' + n(1) + ',' + n(2); }

    if (mode === 'click' || mode === 'rclick' || mode === 'dclick') {
        var x = n(1), y = n(2), pt = $.CGPointMake(x, y);
        var right = mode === 'rclick';
        var btn  = right ? $.kCGMouseButtonRight : $.kCGMouseButtonLeft;
        var dn   = right ? $.kCGEventRightMouseDown : $.kCGEventLeftMouseDown;
        var up   = right ? $.kCGEventRightMouseUp   : $.kCGEventLeftMouseUp;
        moveTo(x, y);
        var clicks = mode === 'dclick' ? 2 : 1;
        $.NSThread.sleepForTimeInterval(0.05);   // let the app see the hover first
        for (var c = 1; c <= clicks; c++) {
            var d = $.CGEventCreateMouseEvent(SRC, dn, pt, btn);
            var u = $.CGEventCreateMouseEvent(SRC, up, pt, btn);
            // A double click is two clicks with clickState 1 then 2 — not two
            // separate single clicks, which apps read as two unrelated clicks.
            $.CGEventSetIntegerValueField(d, $.kCGMouseEventClickState, c);
            $.CGEventSetIntegerValueField(u, $.kCGMouseEventClickState, c);
            post(d); hold(); post(u); hold();
        }
        return (right ? 'right-clicked ' : mode === 'dclick' ? 'double-clicked ' : 'clicked ')
               + x + ',' + y;
    }

    if (mode === 'drag') {
        var x1 = n(1), y1 = n(2), x2 = n(3), y2 = n(4);
        moveTo(x1, y1);
        post($.CGEventCreateMouseEvent(SRC, $.kCGEventLeftMouseDown,
             $.CGPointMake(x1, y1), $.kCGMouseButtonLeft));
        // Intermediate moves: a single jump is ignored by many drag handlers.
        for (var i = 1; i <= 10; i++) {
            post($.CGEventCreateMouseEvent(SRC, $.kCGEventLeftMouseDragged,
                 $.CGPointMake(x1 + (x2 - x1) * i / 10, y1 + (y2 - y1) * i / 10),
                 $.kCGMouseButtonLeft));
            $.NSThread.sleepForTimeInterval(0.02);
        }
        post($.CGEventCreateMouseEvent(SRC, $.kCGEventLeftMouseUp,
             $.CGPointMake(x2, y2), $.kCGMouseButtonLeft));
        return 'dragged ' + x1 + ',' + y1 + ' -> ' + x2 + ',' + y2;
    }

    if (mode === 'scroll') {
        var amount = n(1);
        if (argv.length > 3) moveTo(n(2), n(3));
        post($.CGEventCreateScrollWheelEvent(SRC, $.kCGScrollEventUnitLine, 1, amount));
        return 'scrolled ' + amount;
    }

    if (mode === 'where') {
        var e = $.CGEventCreate($());
        var p = $.CGEventGetLocation(e);
        return Math.round(p.x) + ',' + Math.round(p.y);
    }

    return 'unknown cg mode: ' + mode;
}
JS
}

# cmd+shift+s -> keystroke "s" using {command down, shift down}
send_key() {
    local combo="$1" mods=() key=""
    local IFS='+'
    for part in $combo; do
        case "$(echo "$part" | tr '[:upper:]' '[:lower:]')" in
            cmd|command|super|win) mods+=("command down") ;;
            ctrl|control)          mods+=("control down") ;;
            alt|option|opt)        mods+=("option down") ;;
            shift)                 mods+=("shift down") ;;
            *) key="$part" ;;
        esac
    done
    local using=""
    if [ ${#mods[@]} -gt 0 ]; then
        local joined; IFS=', '; joined="${mods[*]}"; unset IFS
        using=" using {$joined}"
    fi
    # Named keys have no character, so they go through `key code`.
    local code=""
    case "$(echo "$key" | tr '[:upper:]' '[:lower:]')" in
        return|enter) code=36 ;;  tab) code=48 ;;   space) code=49 ;;
        delete|backspace) code=51 ;; escape|esc) code=53 ;;
        left) code=123 ;; right) code=124 ;; down) code=125 ;; up) code=126 ;;
        home) code=115 ;; end) code=119 ;; pageup) code=116 ;; pagedown) code=121 ;;
    esac
    if [ -n "$code" ]; then
        osa "tell application \"System Events\" to key code $code$using"
    else
        osa "tell application \"System Events\" to keystroke \"$key\"$using"
    fi
}

cmd="${1:-}"; shift || true

# `set -u` turns a missing argument into a bare "unbound variable" at some line
# number, which tells you nothing. Name what's missing instead.
need() {
    local n="$1"; shift
    if [ "$#" -lt "$n" ]; then
        echo "$cmd needs $n argument(s), got $#. Run: mac.sh help" >&2
        exit 1
    fi
}

case "$cmd" in
    apps)
        osa 'tell application "System Events" to get name of every process whose background only is false' \
            | tr ',' '\n' | sed 's/^ *//' ;;
    windows)
        need 1 "$@"
        proc "$1" 'return name of every window' | tr ',' '\n' | sed 's/^ *//' ;;
    tree)
        need 1 "$@"
        ax tree "$1" ;;
    find)
        need 2 "$@"
        ax find "$1" "$2" ;;
    launch)
        need 1 "$@"
        open -a "$1" && echo "launched $1" ;;
    activate)
        need 1 "$@"
        proc "$1" 'set frontmost to true' >/dev/null && echo "activated $1" ;;
    click)
        need 2 "$@"
        proc "$1" 'set frontmost to true' >/dev/null
        # ax() folds stderr into stdout, so capture it rather than discard it —
        # otherwise a failed click exits 1 silently.
        if out=$(ax click "$1" "$2") && [ "$out" = "ok" ]; then
            echo "clicked '$2' in $1"
        else
            echo "${out:-click failed}" >&2
            echo "hint: ./mac.sh tree $1   shows what is actually labelled" >&2
            exit 1
        fi ;;
    menus)
        need 1 "$@"
        proc "$1" 'return name of every menu bar item of menu bar 1' \
            | tr ',' '\n' | sed 's/^ *//' | grep -v '^missing value$' ;;
    menu-items)
        need 2 "$@"
        proc "$1" "return name of every menu item of menu 1 of menu bar item \"$2\" of menu bar 1" \
            | tr ',' '\n' | sed 's/^ *//' | grep -v '^missing value$' ;;
    menu)
        need 2 "$@"
        proc "$1" 'set frontmost to true' >/dev/null
        top="${2%%>*}"; item="${2##*>}"
        proc "$1" "click menu item \"$item\" of menu 1 of menu bar item \"$top\" of menu bar 1" >/dev/null \
            && echo "clicked $2 in $1" ;;
    type)
        need 1 "$@"
        osa "tell application \"System Events\" to keystroke \"$1\"" && echo "typed" ;;
    key)
        need 1 "$@"
        send_key "$1" && echo "sent $1" ;;
    displays)
        cg displays ;;
    shot)
        out="${1:-/tmp/shot.png}"; d="${2:-1}"
        screencapture -x -D "$d" "$out" || exit 1
        echo "$out"
        cg displays | sed -n "${d}p" ;;
    click-at)
        need 2 "$@"
        cg click "$1" "$2" ;;
    right-click-at)
        need 2 "$@"
        cg rclick "$1" "$2" ;;
    double-click-at)
        need 2 "$@"
        cg dclick "$1" "$2" ;;
    move-to)
        need 2 "$@"
        cg move "$1" "$2" ;;
    drag)
        need 4 "$@"
        cg drag "$1" "$2" "$3" "$4" ;;
    scroll)
        cg scroll "$1" "${2:-}" "${3:-}" ;;
    where)
        cg where ;;
    shot-app)
        need 1 "$@"
        # System Events' window `id` is NOT the CGWindowID screencapture -l wants,
        # so capture the window's rectangle instead.
        out="${2:-/tmp/shot.png}"
        proc "$1" 'set frontmost to true' >/dev/null
        rect=$(proc "$1" '
        set p to position of window 1
        set s to size of window 1
        return ((item 1 of p) as text) & "," & ((item 2 of p) as text) & "," & ((item 1 of s) as text) & "," & ((item 2 of s) as text)') || exit 1
        screencapture -x -R"$rect" "$out" && echo "$out" ;;
    ""|-h|--help|help) usage ;;
    *) echo "unknown command: $cmd" >&2; usage >&2; exit 1 ;;
esac
