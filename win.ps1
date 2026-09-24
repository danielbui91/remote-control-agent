<#
    Drive Windows from PowerShell, using the UI Automation API.

    The Windows counterpart of mac.sh, with the same commands. This is the cheap
    path: it runs under your Claude subscription, because Claude Code is the thing
    driving it. No API key, no screenshots, no pixel guessing — it clicks controls
    by NAME, so it doesn't break when a window moves.

    Needs nothing installed: UI Automation ships with .NET on Windows. Unlike
    macOS there is no permission to grant, but PowerShell cannot drive a window
    running as Administrator unless PowerShell is elevated too.

    Reach for agent.py only when a target has no named controls at all
    (canvas apps, games, remote-desktop windows).

    usage: .\win.ps1 <command> [args]
      apps / windows <app> / tree <app> / find <app> <text>
      launch <app> / activate <app> / click <app> <name> / menu <app> "File>Save"
      type <text> / key <combo> / shot [path] / shot-app <app> [path]
      displays / click-at <x> <y> / move-to <x> <y> / drag / scroll / where
#>
param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(Position = 1)][string]$Arg1,
    [Parameter(Position = 2)][string]$Arg2,
    [Parameter(Position = 3)][string]$Arg3,
    [Parameter(Position = 4)][string]$Arg4
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public struct PT { public int X; public int Y; }
public class Win {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, int e);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out PT p);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@

# Without this, Windows lies about coordinates on a scaled display (125%, 150%)
# and every click lands short of where you aimed.
[Win]::SetProcessDPIAware() | Out-Null

$MOUSE = @{ LeftDown = 0x02; LeftUp = 0x04; RightDown = 0x08; RightUp = 0x10; Wheel = 0x0800 }

function Move-To([int]$x, [int]$y) { [Win]::SetCursorPos($x, $y) | Out-Null }

function Click-At([int]$x, [int]$y, [string]$button = 'left', [int]$times = 1) {
    Move-To $x $y
    Start-Sleep -Milliseconds 50          # let the app register the hover first
    $dn = if ($button -eq 'right') { $MOUSE.RightDown } else { $MOUSE.LeftDown }
    $up = if ($button -eq 'right') { $MOUSE.RightUp }   else { $MOUSE.LeftUp }
    for ($i = 0; $i -lt $times; $i++) {
        [Win]::mouse_event($dn, 0, 0, 0, 0)
        Start-Sleep -Milliseconds 60      # a zero-duration click is ignored by many apps
        [Win]::mouse_event($up, 0, 0, 0, 0)
        Start-Sleep -Milliseconds 60
    }
}

function Show-Usage {
    Write-Host @"
usage: .\win.ps1 <command> [args]

  apps                    running apps that have a UI
  windows <app>           window titles of an app
  tree <app>              every named control in the app's front window
  find <app> <text>       controls whose name contains <text>

  launch <app>            start an app
  activate <app>          bring an app to the front
  click <app> <name>      click the control named <name>
  menu <app> <path>       click a menu item, e.g. "File>Save As"
  type <text>             type into whatever has focus
  key <combo>             send a combo, e.g. ctrl+s, alt+shift+tab, enter
  shot [path]             screenshot the screen (default: %TEMP%\shot.png)
  shot-app <app> [path]   screenshot just that app's window
  displays                displays and their origins

 Pointer control, for controls that expose no name:
  click-at <x> <y>        click at a point
  right-click-at <x> <y>  right-click
  double-click-at <x> <y> double-click
  move-to <x> <y>         hover without clicking
  where                   current cursor position
  scroll <amount> [x y]   positive scrolls up
  drag <x1> <y1> <x2> <y2>

App names are the ones `.\win.ps1 apps` prints. Quote anything with spaces.
"@
}

# Resolve an app name to its main-window AutomationElement.
function Get-App([string]$name) {
    $p = Get-Process | Where-Object {
        $_.MainWindowHandle -ne 0 -and
        ($_.ProcessName -ieq $name -or $_.MainWindowTitle -like "*$name*")
    } | Select-Object -First 1
    if (-not $p) { throw "No running app matching '$name'. Try: .\win.ps1 apps" }
    $el = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
    if (-not $el) { throw "Could not read the UI tree of '$name'." }
    return @{ Proc = $p; Element = $el }
}

function Get-Named($root) {
    $cond = [System.Windows.Automation.Condition]::TrueCondition
    $found = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $out = @()
    foreach ($e in $found) {
        $n = $e.Current.Name
        if ($n) { $out += [pscustomobject]@{ Type = $e.Current.ControlType.ProgrammaticName -replace '^ControlType\.', ''; Name = $n; El = $e } }
    }
    return $out
}

# Click through whichever pattern the control actually supports.
function Invoke-Element($e) {
    $patterns = @(
        @{ P = [System.Windows.Automation.InvokePattern]::Pattern;        M = 'Invoke' },
        @{ P = [System.Windows.Automation.TogglePattern]::Pattern;        M = 'Toggle' },
        @{ P = [System.Windows.Automation.SelectionItemPattern]::Pattern; M = 'Select' },
        @{ P = [System.Windows.Automation.ExpandCollapsePattern]::Pattern; M = 'Expand' }
    )
    foreach ($p in $patterns) {
        $obj = $null
        if ($e.TryGetCurrentPattern($p.P, [ref]$obj)) { $obj.($p.M)(); return $true }
    }
    # No pattern: fall back to a real click at the control's clickable point.
    try {
        $pt = $e.GetClickablePoint()
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point -ArgumentList ([int]$pt.X), ([int]$pt.Y)
        [Win]::mouse_event(0x02, 0, 0, 0, 0)   # LEFTDOWN
        [Win]::mouse_event(0x04, 0, 0, 0, 0)   # LEFTUP
        return $true
    } catch { return $false }
}

# ctrl+shift+s -> +^s   (SendKeys notation)
function ConvertTo-SendKeys([string]$combo) {
    $mods = ''; $key = ''
    foreach ($part in $combo -split '\+') {
        switch ($part.ToLower()) {
            { $_ -in 'ctrl', 'control', 'cmd', 'command' } { $mods += '^' }   # cmd maps to ctrl on Windows
            { $_ -in 'alt', 'option', 'opt' }              { $mods += '%' }
            'shift'                                        { $mods += '+' }
            'win'                                          { $mods += '^{ESC}' }
            default                                        { $key = $part }
        }
    }
    $named = @{
        'return' = '{ENTER}'; 'enter' = '{ENTER}'; 'tab' = '{TAB}'; 'esc' = '{ESC}'
        'escape' = '{ESC}'; 'space' = ' '; 'backspace' = '{BACKSPACE}'; 'delete' = '{DELETE}'
        'up' = '{UP}'; 'down' = '{DOWN}'; 'left' = '{LEFT}'; 'right' = '{RIGHT}'
        'home' = '{HOME}'; 'end' = '{END}'; 'pageup' = '{PGUP}'; 'pagedown' = '{PGDN}'
    }
    $k = $named[$key.ToLower()]
    if (-not $k) { $k = $key }
    return "$mods$k"
}

function Save-Shot([string]$path, $bounds) {
    if (-not $path) { $path = Join-Path $env:TEMP 'shot.png' }
    if (-not $bounds) { $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen }
    $bmp = New-Object System.Drawing.Bitmap -ArgumentList ([int]$bounds.Width), ([int]$bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([int]$bounds.X, [int]$bounds.Y, 0, 0, $bmp.Size)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    return $path
}

switch ($Command) {
    'apps' {
        Get-Process | Where-Object { $_.MainWindowTitle } |
            Select-Object ProcessName, MainWindowTitle | Format-Table -AutoSize
    }
    'windows' {
        Get-Process | Where-Object { $_.ProcessName -ieq $Arg1 -and $_.MainWindowTitle } |
            ForEach-Object { $_.MainWindowTitle }
    }
    'tree' {
        $app = Get-App $Arg1
        Get-Named $app.Element | ForEach-Object { "$($_.Type) :: $($_.Name)" }
    }
    'find' {
        $app = Get-App $Arg1
        Get-Named $app.Element | Where-Object { $_.Name -like "*$Arg2*" } |
            ForEach-Object { "$($_.Type) :: $($_.Name)" }
    }
    'launch' { Start-Process $Arg1; "launched $Arg1" }
    'activate' {
        $app = Get-App $Arg1
        [Win]::ShowWindow($app.Proc.MainWindowHandle, 9) | Out-Null   # SW_RESTORE
        [Win]::SetForegroundWindow($app.Proc.MainWindowHandle) | Out-Null
        "activated $Arg1"
    }
    'click' {
        $app = Get-App $Arg1
        [Win]::SetForegroundWindow($app.Proc.MainWindowHandle) | Out-Null
        $hit = Get-Named $app.Element | Where-Object { $_.Name -eq $Arg2 } | Select-Object -First 1
        if (-not $hit) { throw "No control named '$Arg2' in $Arg1. Try: .\win.ps1 find $Arg1 $Arg2" }
        if (Invoke-Element $hit.El) { "clicked '$Arg2' in $Arg1" } else { throw "Found '$Arg2' but could not click it." }
    }
    'menu' {
        $app = Get-App $Arg1
        [Win]::SetForegroundWindow($app.Proc.MainWindowHandle) | Out-Null
        $scope = $app.Element
        foreach ($part in $Arg2 -split '>') {
            $hit = Get-Named $scope | Where-Object { $_.Name -eq $part } | Select-Object -First 1
            if (-not $hit) { throw "No menu item '$part' (from '$Arg2') in $Arg1." }
            Invoke-Element $hit.El | Out-Null
            Start-Sleep -Milliseconds 250
            # An opened submenu is its own top-level window, so widen the search
            # to the whole desktop for the remaining hops.
            $scope = [System.Windows.Automation.AutomationElement]::RootElement
        }
        "clicked $Arg2 in $Arg1"
    }
    'type' { [System.Windows.Forms.SendKeys]::SendWait($Arg1); 'typed' }
    'key'  { [System.Windows.Forms.SendKeys]::SendWait((ConvertTo-SendKeys $Arg1)); "sent $Arg1" }
    'displays' {
        $i = 1
        foreach ($sc in [System.Windows.Forms.Screen]::AllScreens) {
            $b = $sc.Bounds
            $tag = if ($sc.Primary) { '  (primary)' } else { '' }
            "display $i  origin $($b.X),$($b.Y)  size $($b.Width)x$($b.Height)  scale 1$tag"
            $i++
        }
        'note: with SetProcessDPIAware, screenshot pixels match these coordinates 1:1'
    }
    'click-at'        { Click-At ([int]$Arg1) ([int]$Arg2) 'left'  1; "clicked $Arg1,$Arg2" }
    'right-click-at'  { Click-At ([int]$Arg1) ([int]$Arg2) 'right' 1; "right-clicked $Arg1,$Arg2" }
    'double-click-at' { Click-At ([int]$Arg1) ([int]$Arg2) 'left'  2; "double-clicked $Arg1,$Arg2" }
    'move-to'         { Move-To ([int]$Arg1) ([int]$Arg2); "moved to $Arg1,$Arg2" }
    'where' {
        $pt = New-Object PT
        [Win]::GetCursorPos([ref]$pt) | Out-Null
        "$($pt.X),$($pt.Y)"
    }
    'drag' {
        if (-not $Arg4) { throw 'usage: drag <x1> <y1> <x2> <y2>' }
        $x1 = [int]$Arg1; $y1 = [int]$Arg2; $x2 = [int]$Arg3; $y2 = [int]$Arg4
        Move-To $x1 $y1
        [Win]::mouse_event($MOUSE.LeftDown, 0, 0, 0, 0)
        # Intermediate moves: a single jump is ignored by many drag handlers.
        for ($i = 1; $i -le 10; $i++) {
            Move-To ([int]($x1 + ($x2 - $x1) * $i / 10)) ([int]($y1 + ($y2 - $y1) * $i / 10))
            Start-Sleep -Milliseconds 20
        }
        [Win]::mouse_event($MOUSE.LeftUp, 0, 0, 0, 0)
        "dragged $x1,$y1 -> $x2,$y2"
    }
    'scroll' {
        if ($Arg2 -and $Arg3) { Move-To ([int]$Arg2) ([int]$Arg3) }
        [Win]::mouse_event($MOUSE.Wheel, 0, 0, [uint32](120 * [int]$Arg1), 0)
        "scrolled $Arg1"
    }
    'shot' { Save-Shot $Arg1 $null }
    'shot-app' {
        $app = Get-App $Arg1
        [Win]::SetForegroundWindow($app.Proc.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 300
        Save-Shot $Arg2 $app.Element.Current.BoundingRectangle
    }
    default { Show-Usage }
}
