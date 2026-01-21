; c = case sensitive
; c1 = ignore the case that was typed, always use the same case for output
; * = immediate change (no need for space, period, or enter)
; ? = triggered even when the character typed immediately before it is alphanumeric
; r = raw output

; the auto-exec section ends at the first hotkey/hotstring or return or exit or at the script end - whatever comes first; function definitions get ignored by the execution flow.

#NoEnv
#SingleInstance Force
#InstallMouseHook
#InstallKeybdHook
#UseHook
#include %A_ScriptDir%\UIAutomation-main\Lib\UIA_Interface.ahk
; #include %A_ScriptDir%\Acc.ahk
#HotString EndChars ()[]{}:;,.?!`n `t
#MaxhotKeysPerInterval 500
#KeyHistory 25

; #include %A_ScriptDir%\_VD.ahk
; DLL
Global VDA_DllName := "VirtualDesktopAccessor_Win11.dll"
Global dllPath := A_ScriptDir . "\" . VDA_DllName  ; destination: next to EXE/script
Global hVirtualDesktopAccessor             := 0
Global GetDesktopCountProc                 := 0
Global GoToDesktopNumberProc               := 0
Global GetCurrentDesktopNumberProc         := 0
Global IsWindowOnCurrentVirtualDesktopProc := 0
Global IsWindowOnDesktopNumberProc         := 0
Global MoveWindowToDesktopNumberProc       := 0
Global IsPinnedWindowProc                  := 0
Global GetDesktopNameProc                  := 0
Global SetDesktopNameProc                  := 0
Global CreateDesktopProc                   := 0
Global RemoveDesktopProc                   := 0

SendMode, Input ; It injects the whole keystroke atomically, reducing the window where logical/physical can disagree

; SetKeyDelay is not obeyed by SendInput; there is no delay between keystrokes in that mode.
; This same is true for Send when SendMode Input is in effect.
; SetKeyDelay, -1, -1
SetMouseDelay,   -1
SetBatchLines,   -1
SetWinDelay,      1 ; 10
SetControlDelay,  1 ; 10

Global CurrentDesktop                      := 1
Global mouseMoving                         := False
Global skipCheck                           := False
Global cycling                             := False
Global ValidWindows                        := []
Global GroupedWindows                      := []
Global PrevActiveWindows                   := []
Global minWinArray                         := []
Global allWinArray                         := []
Global cycleCount                          := 1
Global startHighlight                      := False
Global border_thickness                    := 4
Global border_color                        := 0xFF00FF
Global hitTAB                              := False
Global hitTilde                            := False
Global SearchingWindows                    := False
Global UserInputTrimmed                    := ""
Global memotext                            := ""
Global totalMenuItemCount                  := 0
Global onlyTitleFound                      := ""
Global CancelClose                         := False
Global DrawingRect                         := False
Global LclickSelected                      := False
Global StopRecursion                       := False
Global currMonHeight                       := 0
Global currMonWidth                        := 0
Global LbuttonEnabled                      := True
Global X_PriorPriorHotKey                  :=
Global StopAutoFix                         := False
Global disableEnter                        := False
Global EVENT_SYSTEM_MENUPOPUPSTART         := 0x0006
Global EVENT_SYSTEM_MENUPOPUPEND           := 0x0007
Global TimeOfLastHotkeyTyped               := A_TickCount
Global currentMon                          := 0
Global previousMon                         := 0
Global targetDesktop                       := 0
Global currentPath                         := ""
Global prevPath                            := ""
Global _winCtrlD                           := ""
Global MbuttonIsEnter                      := False
Global textBoxSelected                     := False
Global WindowTitleID                       :=
Global keys                                := "abcdefghijklmnopqrstuvwxyz"
Global numbers                             := "0123456789"
Global DoubleClickTime                     := DllCall("GetDoubleClickTime")
Global isWin11                             := DetectWin11()
Global isModernExplorerInReg               := IsExplorerModern()
Global TaskBarHeight                       := 0
Global lastHotkeyTyped                     := ""
Global DraggingWindow                      := False
Global hActWin := DllCall("user32\SetWinEventHook", UInt,0x3, UInt,0x3, Ptr,0, Ptr,RegisterCallback("OnWinActiveChange"), UInt,0, UInt,0, UInt,0, Ptr)
; Global winhookevent := DllCall("SetWinEventHook", "UInt", EVENT_SYSTEM_MENUPOPUPSTART, "UInt", EVENT_SYSTEM_MENUPOPUPSTART, "Ptr", 0, "Ptr", (lpfnWinEventProc := RegisterCallback("OnPopupMenu", "")), "UInt", 0, "UInt", 0, "UInt", WINEVENT_OUTOFCONTEXT := 0x0000 | WINEVENT_SKIPOWNPROCESS := 0x0002)
; Turn key blocking ON/OFF
Global blockKeys := false

; --- Config ---
Global UseWorkArea  := true   ; true = monitor work area (ignores taskbar). false = full monitor.
Global SnapRange    := 20     ; px: distance from edge to begin snapping
Global BreakAway    := 60     ; px: while snapped, drag this far further TOWARD the outside to push past edge
Global ReleaseAway  := 24     ; px: while snapped, drag this far AWAY from the edge to release the snap

; Skip dragging these classes (taskbar/desktop)
Global skipClasses := { "Shell_TrayWnd":1, "Shell_SecondaryTrayWnd":1, "Progman":1, "WorkerW":1 }

; === Settings ===
Global BlockClicks := False    ; true = block clicks outside active window, false = let clicks pass through
Global Opacity     := 215     ; 255=opaque black; try 200 to "dim" instead of fully black

; === Globals ===
Global black1Hwnd := ""
Global black2Hwnd := ""
Global black3Hwnd := ""
Global black4Hwnd := ""
Global hTop       := ""
Global hLeft      := ""
Global hRight     := ""
Global hBottom    := ""

Process, Priority,, High

Global UIA := UIA_Interface() ; Initialize UIA interface
UIA.TransactionTimeout := 2000
UIA.ConnectionTimeout  := 20000

Menu, Tray, Icon
Menu, Tray, NoStandard
Menu, Tray, Add, Menu, Routine
Menu, Tray, Add, Run at startup, Startup
Menu, Tray, Add, &Suspend, Suspend_label
Menu, Tray, Add, Reload, Reload_label
Menu, Tray, Add, Exit, Exit_label
; Menu, Tray, Default, &Suspend
Menu, Tray, Default, Menu
Menu, Tray, Add
Menu, Tray, Add, Key History, keyhist_label
Menu, Tray, Add, List Hotkeys, listHotkeys_label
Menu, Tray, Add, List Vars, listVars_label
Menu, Tray, Add, List Lines, listLines_label
Menu, Tray, Click, 1

link := A_Startup . "\AutoCorrect.lnk"
runAtStartup := FileExist(link) ? 1 : 0
If (runAtStartup)
    Menu, Tray, Check, Run at startup
Else
    Menu, Tray, Uncheck, Run at startup

; Create 4 mask GUIs (top, left, right, bottom)
CreateMaskGui(index, ByRef hWndOut) {
    global BlockClicks, Opacity, black1Hwnd, black2Hwnd, black3Hwnd, black4Hwnd

    clickStyle := BlockClicks ? "" : "+E0x20"
    ; Build a variable name like "hWnd1", "hWnd2", etc.
    if (index) {
        hwndVarName := "black" . index . "Hwnd"
        Gui, %index%: +AlwaysOnTop -Caption +ToolWindow %clickStyle% +Hwnd%hwndVarName%
        Gui, %index%: Color, Black
        WinSet, Transparent, %Opacity%, ahk_id %hwndVarName%
        hWndOut := hwndVarName
        Gui, %index%: Hide
    }
}

CreateMaskGui(1, hTop)
CreateMaskGui(2, hLeft)
CreateMaskGui(3, hRight)
CreateMaskGui(4, hBottom)

SysGet, MonNum, MonitorPrimary
SysGet, MonitorWorkArea, MonitorWorkArea, %MonNum%
SysGet, MonCount, MonitorCount

; leftArrow  := "←"
; rightArrow := "→"
; upArrow    := "↑"
; downArrow  := "↓"
leftArrow  := Chr(0x2190)  ; ←
rightArrow := Chr(0x2192)  ; →
upArrow    := Chr(0x2191)  ; ↑
downArrow  := Chr(0x2193)  ; ↓

GetDesktopEdges(ByRef leftEdge, ByRef topEdge, ByRef rightEdge, ByRef bottomEdge) {
    SysGet, monCount, MonitorCount

    leftEdge  := ""
    topEdge   := ""
    rightEdge := ""
    bottomEdge:= ""

    Loop, %monCount% {
        ; "mon" is the prefix; SysGet will set monLeft, monTop, monRight, monBottom
        SysGet, mon, Monitor, %A_Index%

        if (A_Index = 1) {
            leftEdge   := monLeft
            topEdge    := monTop
            rightEdge  := monRight
            bottomEdge := monBottom
        } else {
            if (monLeft < leftEdge)
                leftEdge := monLeft
            if (monTop < topEdge)
                topEdge := monTop
            if (monRight > rightEdge)
                rightEdge := monRight
            if (monBottom > bottomEdge)
                bottomEdge := monBottom
        }
    }
}

GetDesktopEdges(G_DisplayLeftEdge, G_DisplayTopEdge, G_DisplayRightEdge, G_DisplayBottomEdge)

line1 := "Total Number of Monitors is " MonCount " with Primary being " MonNum
line1a := "Desktop edges: " leftArrow . "(" . G_DisplayLeftEdge . "," . G_DisplayRightEdge . ")" . rightArrow
line1b := "Desktop edges: " upArrow . "(" . G_DisplayTopEdge . "," . G_DisplayBottomEdge . ")" . downArrow
line2 := "Current Mon is     " GetCurrentMonitorIndex()
line3 := "Win11 is           " isWin11
line4 := "Modern Explorer is " isModernExplorerInReg
Tooltip, % line1 "`n" line1a "`n" line1b "`n" line2 "`n" line3 "`n" line4
Sleep 5000
Tooltip

Gui, ShadowFrFull: New
Gui, ShadowFrFull: +HwndIGUIF
Gui, ShadowFrFull: +AlwaysOnTop +ToolWindow -DPIScale +E0x08000000 +E0x20 -Caption +Owner +LastFound
Gui, ShadowFrFull: Color, FF00FF
FrameShadow(IGUIF)

Gui, ShadowFrFull2: New
Gui, ShadowFrFull2: +HwndIGUIF2
Gui, ShadowFrFull2: +AlwaysOnTop +ToolWindow -DPIScale +E0x08000000 +E0x20 -Caption +Owner +LastFound
Gui, ShadowFrFull2: Color, FF00FF
FrameShadow(IGUIF2)

Gui, GUI4Boarder: New
Gui, GUI4Boarder: +HwndHighlighter
Gui, GUI4Boarder: +AlwaysOnTop +Toolwindow -Caption +Owner +Lastfound
Gui, GUI4Boarder: Color, %border_color%

WinGet, allwindows, List
loop % allwindows
{
    winID := allWindows%A_Index%
    WinGet, minState, MinMax, ahk_id %winID%

    If (minState > -1 && IsAltTabWindow(winID)) {
        prevActiveWindows.push(winID)
    }
}

Expr =
(
    #NoEnv
    #NoTrayIcon
    #KeyHistory 0
    ; #Persistent ; already the default
    #WinActivateForce
    SetBatchLines -1
    ListLines Off
    ; DetectHiddenWindows, Off ; already the default

    WinWait, ahk_class #32768,, 3

    If ErrorLevel
        ExitApp

    SendInput, {DOWN}
    ; https://www.autohotkey.com/board/topic/11157-popup-menu-sometimes-doesnt-have-focus/page-2
    ; MouseMove, %x%, %y%

    ; Input, SingleKey, L1, {Lbutton}{ESC}{ENTER}, *
    Return

    $~ENTER::
        ExitApp
    Return

    $~ESC::
        ExitApp
    Return

    $~*LBUTTON::
        ExitApp
    Return

    $SPACE::
        SendInput, {DOWN}
    Return
)

ExprAltUp =
(
    #NoEnv
    #NoTrayIcon
    #KeyHistory 0
    ; #Persistent ; already the default
    #WinActivateForce
    SetBatchLines -1
    ListLines Off
    ; DetectHiddenWindows, Off ; already the default

    #IfWinNotActive ahk_class #32770
    ~Alt Up::
        If WinExist("ahk_class #32768")
            Send, {ENTER}
        If WinExist("ahk_class #32768")
            WinClose, ahk_class #32768
        ExitApp
    Return
    #IfWinNotActive
)

TooltipExpr =
(
    #NoEnv
    #NoTrayIcon
    #KeyHistory 0
    #SingleInstance, Off
    ; #Persistent ; already the default
    SetBatchLines -1
    ListLines Off

    tooltip, Navigating Up...
    sleep, 1000
    tooltip
    ExitApp
)

;------------------------------------------------------------------------------
; AUto-COrrect TWo COnsecutive CApitals.
; Disabled by default to prevent unwanted corrections such as IfEqual->Ifequal.
; To enable it, remove the /*..*/ symbols around it.
; From Laszlo's script at http://www.autohotkey.com/forum/topic9689.html
;------------------------------------------------------------------------------
; The first line of code below is the set of letters, digits, and/or symbols
; that are eligible for this type of correction.  Customize if you wish:

HotKey, ~/,  Marktime_FixSlash
HotKey, ~',  Hoty ;'
HotKey, ~?,  Hoty
HotKey, ~!,  Hoty
HotKey, ~`,, Hoty
HotKey, ~.,  Marktime_Hoty
HotKey, ~_,  Hoty
HotKey, ~-,  Hoty
Hotkey, ~:,  MarkKeypressTime

Loop Parse, keys
{
    Hotkey, %  "~" . A_LoopField, Marktime_Hoty_FixSlash, On
    Hotkey, % "~+" . A_LoopField, Marktime_Hoty_FixSlash, On
}

; Numbers
Loop Parse, numbers
{
    Hotkey, % "~" . A_LoopField, Marktime_Hoty_FixSlash, On
}

Send #^{Left}
sleep, 50
Send #^{Left}
sleep, 50
Send #^{Left}
sleep, 50
Send #^{Left}
sleep, 50

WinGetPos, , , , TaskBarHeight, ahk_class Shell_TrayWnd

If (MonCount > 1) {
    currentMon := MWAGetMonitorMouseIsIn()
    previousMon := currentMon
}

; Get module handle for this process (needed by SetWindowsHookEx for LL hooks)
hMod := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")

; Low-level keyboard hook: WH_KEYBOARD_LL = 13
kbdCallback := RegisterCallback("LL_KeyboardHook", "Fast")
hHookKbd   := DllCall("SetWindowsHookEx"
    , "Int", 13              ; WH_KEYBOARD_LL
    , "Ptr", kbdCallback
    , "Ptr", hMod
    , "UInt", 0
    , "Ptr")

; Low-level mouse hook: WH_MOUSE_LL = 14
mouseCallback := RegisterCallback("LL_MouseHook", "Fast")
hHookMouse    := DllCall("SetWindowsHookEx"
    , "Int", 14              ; WH_MOUSE_LL
    , "Ptr", mouseCallback
    , "Ptr", hMod
    , "UInt", 0
    , "Ptr")

if (!hHookKbd || !hHookMouse)
{
    MsgBox, 16, Error, Failed to install low-level hooks.`nKeyboard: %hHookKbd%`nMouse: %hHookMouse%
    ExitApp
}

OnExit, UnhookHooks

SetTimer mouseTrack, 10
SetTimer keyTrack, 5

Return

; ==========================================================================================================================================
; -----------------------------------------------          START OF APPLICATION           --------------------------------------------------
; ==========================================================================================================================================
; Helper to resolve exports
_gp(name) {
    global hVirtualDesktopAccessor

    return DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", name, "Ptr")
}

InitVDA() {
    global VDA_DllName, hVirtualDesktopAccessor, dllPath
    global GetDesktopCountProc, GoToDesktopNumberProc, GetCurrentDesktopNumberProc
    global IsWindowOnCurrentVirtualDesktopProc, IsWindowOnDesktopNumberProc, MoveWindowToDesktopNumberProc
    global IsPinnedWindowProc, GetDesktopNameProc, SetDesktopNameProc
    global CreateDesktopProc, RemoveDesktopProc

    ; If we already resolved at least the "core" proc, assume init done.
    ; (Change this to a stricter check if you prefer.)
    if (IsWindowOnCurrentVirtualDesktopProc)
        return true

    ; Optional safety: ensure file exists
    if !FileExist(dllPath) {
        MsgBox % "VDA DLL missing:`n" dllPath
        return false
    }

    ; Load DLL (once)
    if (!hVirtualDesktopAccessor) {
        hVirtualDesktopAccessor := DllCall("LoadLibrary", "Str", dllPath, "Ptr")
        if (!hVirtualDesktopAccessor) {
            MsgBox % "LoadLibrary failed:`n" dllPath "`nA_LastError=" A_LastError
            return false
        }
    }

    ; Resolve all requested exports
    GetDesktopCountProc                 := _gp("GetDesktopCount")
    GoToDesktopNumberProc               := _gp("GoToDesktopNumber")
    GetCurrentDesktopNumberProc         := _gp("GetCurrentDesktopNumber")
    IsWindowOnCurrentVirtualDesktopProc := _gp("IsWindowOnCurrentVirtualDesktop")
    IsWindowOnDesktopNumberProc         := _gp("IsWindowOnDesktopNumber")
    MoveWindowToDesktopNumberProc       := _gp("MoveWindowToDesktopNumber")
    IsPinnedWindowProc                  := _gp("IsPinnedWindow")
    GetDesktopNameProc                  := _gp("GetDesktopName")
    SetDesktopNameProc                  := _gp("SetDesktopName")
    CreateDesktopProc                   := _gp("CreateDesktop")
    RemoveDesktopProc                   := _gp("RemoveDesktop")

    ; Return true only if the key procs exist.
    ; (You can tighten/loosen this depending on what you require.)
    return !!(GetDesktopCountProc
           && GoToDesktopNumberProc
           && GetCurrentDesktopNumberProc
           && IsWindowOnCurrentVirtualDesktopProc
           && IsWindowOnDesktopNumberProc
           && MoveWindowToDesktopNumberProc
           && IsPinnedWindowProc
           && GetDesktopNameProc
           && SetDesktopNameProc
           && CreateDesktopProc
           && RemoveDesktopProc)
}
; ---- Low-level hardware key filter ----
; --------------------------------------------------
; Common filter logic for keyboard - Yes, your hook can create the stuck modifier by swallowing physical KEYUP.
; --------------------------------------------------
LL_KeyboardHook(nCode, wParam, lParam)
{
    ; When blockKeys := true, you return 1 for everything physical, including key-up messages.
    ; If the user releases LCtrl while blocking is active, Windows never receives the LCtrl-up → Ctrl stays down.
    global blockKeys, hHookKbd

    ; If we must pass the event through without processing
    if (nCode < 0)
        return DllCall("CallNextHookEx", "Ptr", hHookKbd, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    ; If not blocking, just pass through
    if (!blockKeys)
        return DllCall("CallNextHookEx", "Ptr", hHookKbd, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    ; KBDLLHOOKSTRUCT:
    ;   vkCode      (DWORD)  offset 0
    ;   scanCode    (DWORD)  offset 4
    ;   flags       (DWORD)  offset 8
    ;   time        (DWORD)  offset 12
    ;   dwExtraInfo (ULONG_PTR) offset 16

    flags    := NumGet(lParam + 0, 8, "UInt")
    injected := (flags & 0x10)  ; LLKHF_INJECTED

    ; Allow injected keys (from Send/SendInput)
    if (injected)
        return DllCall("CallNextHookEx", "Ptr", hHookKbd, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    ; Otherwise block physical key
    return 1  ; non-zero = swallow
}

; --------------------------------------------------
; Common filter logic for mouse - Yes, your hook can create the stuck modifier by swallowing physical KEYUP.
; --------------------------------------------------
LL_MouseHook(nCode, wParam, lParam)
{
    ; When blockKeys := true, you return 1 for everything physical, including key-up messages.
    ; If the user releases LCtrl while blocking is active, Windows never receives the LCtrl-up → Ctrl stays down.
    global blockKeys, hHookMouse

    if (nCode < 0)
        return DllCall("CallNextHookEx", "Ptr", hHookMouse, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    if (!blockKeys)
        return DllCall("CallNextHookEx", "Ptr", hHookMouse, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    ; MSLLHOOKSTRUCT:
    ; flags offset 12
    flags    := NumGet(lParam + 0, 12, "UInt")
    injected := (flags & 0x01)  ; LLMHF_INJECTED

    ; wParam: mouse message:
    ;   0x0201 WM_LBUTTONDOWN
    ;   0x0202 WM_LBUTTONUP
    ;   0x0204 WM_RBUTTONDOWN
    ;   0x0205 WM_RBUTTONUP
    ;   0x0207 WM_MBUTTONDOWN
    ;   0x0208 WM_MBUTTONUP
    ;   plus dbl-click messages, etc.
    ;
    ; MSLLHOOKSTRUCT:
    ;   pt          (POINT)  offset 0 (8 bytes)
    ;   mouseData   (DWORD)  offset 8
    ;   flags       (DWORD)  offset 12
    ;   time        (DWORD)  offset 16
    ;   dwExtraInfo (ULONG_PTR) offset 20

    ; Allow injected mouse events (SendInput/Click)
    if (injected)
        return DllCall("CallNextHookEx", "Ptr", hHookMouse, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    ; Block wheel messages too
    if (wParam = 0x020A || wParam = 0x020E)  ; WM_MOUSEWHEEL / WM_MOUSEHWHEEL
        return 1

    ; Block physical mouse button messages
    if (wParam >= 0x0201 && wParam <= 0x0209)
        return 1

    ; Otherwise pass through (move, etc.)
    return DllCall("CallNextHookEx", "Ptr", hHookMouse, "Int", nCode, "UInt", wParam, "Ptr", lParam)
}

OnPopupMenu(hWinEventHook, event, hWnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    ; tooltip, pop!
}

MarkKeypressTime:
    TimeOfLastHotkeyTyped := A_TickCount
    lastHotkeyTyped := A_ThisHotkey
Return

Marktime_Hoty:
    GoSub, MarkKeypressTime
    GoSub, Hoty
Return

Marktime_Hoty_FixSlash:
    GoSub, MarkKeypressTime
    GoSub, Hoty
    GoSub, FixSlash
Return

Marktime_FixSlash:
    GoSub, MarkKeypressTime
    GoSub, FixSlash
Return

Startup:
    runAtStartup := !runAtStartup

    if (runAtStartup) {

        if (A_IsCompiled)
            target := A_ScriptFullPath
        else
            target := A_AhkPath . " " . A_ScriptFullPath

        FileCreateShortcut, %target%, %link%
        Menu, Tray, Check, Run at startup

    } else {
        IfExist, %link%
            FileDelete, %link%
        Menu, Tray, Uncheck, Run at startup
    }
Return

Tray_SingleLclick:
    msgbox You left-clicked tray icon
Return

Reload_label:
    StopRecursion := True
    sleep, 1000
    Reload
Return

Suspend_label:
    Menu, Tray, Togglecheck, &Suspend
    Suspend
Return

Exit_label:
    exitapp
Return

keyhist_label:
    KeyHistory
Return

listHotkeys_label:
    ListHotkeys
Return

listVars_label:
    ListVars
Return

listLines_label:
    ListLines
Return

; ==========================================================================================================================================
; -----------------------------------------------          TYPING MANIUPLATION           --------------------------------------------------
; ==========================================================================================================================================
Hoty:
    CapCount := (IsPriorHotKeyCapital() && A_TimeSincePriorHotkey < 999) ? CapCount + 1 : 1 ; note that CapCount is ALWAYS at least 1
    If !IsGoogleDocWindow() && !StopAutoFix && CapCount == 3 && IsThisHotKeyLowerCase()  {
        Send % "{Left}{BS}" . SubStr(A_PriorHotKey,3,1) . "{Right}"
        CapCount := 1
    }
    If StopAutoFix
        X_PriorPriorHotKey :=
Return

FixSlash:
    If !IsGoogleDocWindow() && (!StopAutoFix && IsPriorHotKeyLetterKey()) && A_ThisHotkey == "~/"
        disableEnter := True
    Else If !IsGoogleDocWindow() && (!StopAutoFix && IsThisHotKeyLetterKey())
        disableEnter := False
    ; tooltip, %disableEnter% - %X_PriorPriorHotKey% - %A_PriorHotKey% - %A_ThisHotkey%
    If      (disableEnter && !IsGoogleDocWindow() && (!StopAutoFix && InStr(keys, X_PriorPriorHotKey, False) && A_PriorHotKey == "~/" && A_ThisHotkey == "$~Space" && A_TimeSincePriorHotkey<999)) {
        Send, % "{BS}{BS}{?}{SPACE}"
        disableEnter := False
    }
    Else If (disableEnter && !IsGoogleDocWindow() && (!StopAutoFix && InStr(keys, X_PriorPriorHotKey, False) && A_PriorHotKey == "~/" && A_ThisHotkey == "$Enter" && A_TimeSincePriorHotkey<999)) {
        Send, % "{BS}{?}{ENTER}"
        disableEnter := False
    }
    If IsPriorHotKeyLowerCase()   ; as long as a letter key is pressed we record the priorprior hotkey
        X_PriorPriorHotKey := Substr(A_PriorHotkey,2,1) ; record the letter key pressed
    If IsPriorHotKeyCapital()
        X_PriorPriorHotKey := Substr(A_PriorHotkey,3,1) ; record only the letter key pressed If captialized
Return

IsPriorHotKeyLetterKey() {
    Return (IsPriorHotKeyCapital() || IsPriorHotKeyLowerCase())
}
IsThisHotKeyLetterKey() {
    Return (IsThisHotKeyCapital() || IsThisHotKeyLowerCase())
}
IsPriorHotKeyCapital() {
    global keys
    Return (StrLen(A_PriorHotkey) == 3 && SubStr(A_PriorHotKey,1,1)!="!" && SubStr(A_PriorHotKey,2,1)="+" && InStr(keys, Substr(A_PriorHotkey,3,1), False))
}
IsPriorHotKeyLowerCase() {
    global keys
    Return (StrLen(A_PriorHotkey) == 2 && InStr(keys, Substr(A_PriorHotkey,2,1), False))
}
IsThisHotKeyCapital() {
    global keys
    Return (StrLen(A_ThisHotKey) == 3 && SubStr(A_ThisHotKey,1,1)!="!" && SubStr(A_ThisHotKey,2,1)="+" && InStr(keys, Substr(A_ThisHotKey,3,1), False))
}
IsThisHotKeyLowerCase() {
    global keys
    Return (StrLen(A_ThisHotKey) == 2 && InStr(keys, Substr(A_ThisHotKey,2,1), False))
}

DoNothing() {
    Return
}

; ==========================================================================================================================================
; ==========================================================================================================================================
WhichButton(vPosX, vPosY, hWnd) {

    errorFound := False

    ;get role number
    ; vRole := "", try vRole := oAcc.accRole(vChildID)
    ;get role text method 1
    ; vRoleText1 := Acc_Role(oAcc, vChildID)
    ;get role text method 2 (using role number from earlier)
    ; vRoleText2 := (vRole = "") ? "" : Acc_GetRoleText(vRole)
    vName := "",

    try {
        oAcc := Acc_ObjectFromPoint(vChildID)
        If oAcc
            vName := oAcc.accName(vChildID)
    }
    catch e {
        tooltip, error thrown
        errorFound := True
    }

    If (vName == "" || (!InStr(vName,"close",false) && !InStr(vName,"restore",false) && !InStr(vName,"maximize",false) && !InStr(vName,"minimize",false))) {
        SendMessage, 0x84, 0, (vPosX & 0xFFFF) | (vPosY & 0xFFFF)<<16,, ahk_id %hWnd%, , , , 500
        If (ErrorLevel == 8)
            vName := "minimize"
        Else If (ErrorLevel == 9)
            vName := "maximize"
        Else If (ErrorLevel == 20)
            vName := "close"
        ; msgbox, 1 - %vName%
    }

    isAltTab := JEE_WinHasAltTabIcon(hWnd)
    If (isAltTab && vName == "") { ; || (!InStr(vName,"close",false) && !InStr(vName,"restore",false) && !InStr(vName,"maximize",false) && !InStr(vName,"minimize",false)))) {
        wx := wy := ww := wh := 0
        SysGet, SM_CXBORDER, 5
        SysGet, SM_CYBORDER, 6
        SysGet, SM_CXFIXEDFRAME, 7
        SysGet, SM_CYFIXEDFRAME, 8
        SysGet, SM_CXMIN, 28
        SysGet, SM_CYMIN, 29
        SysGet, SM_CXSIZE, 30
        SysGet, SM_CYSIZE , 31
        SysGet, SM_CXSIZEFRAME, 32
        SysGet, SM_CYSIZEFRAME , 33

        WinGet, isMax, MinMax, ahk_id %WindowUnderMouseID%

        titlebarHeight := SM_CYMIN-SM_CYSIZEFRAME
        If (isMax == 1)
            titlebarHeight := SM_CYSIZE

        WinGetPosEx(hWnd, wx, wy, ww, wh)

        If      ((vPosY > wy) && (vPosY < (wy+titlebarHeight)) && (vPosX > (wx+ww-SM_CXBORDER-(45*3)) && (vPosX < (wx+ww-SM_CXBORDER-(45*2)))))
            vName := "minimize"
        Else If ((vPosY > wy) && (vPosY < (wy+titlebarHeight)) && (vPosX > (wx+ww-SM_CXBORDER-(45*2)) && (vPosX < (wx+ww-SM_CXBORDER-(45*1)))))
            vName := "maximize"
        Else If ((vPosY > wy) && (vPosY < (wy+titlebarHeight)) && (vPosX > (wx+ww-SM_CXBORDER-(45*1)) && (vPosX < (wx+ww-SM_CXBORDER-(45*0)))))
            vName := "close"
        ; msgbox, 2 - %vName% - %wx% %wy% %ww% %wh%
    }

    ; vValue := "", try vValue := oAcc.accValue(vChildID)
    oAcc := ""

    vOutput := ""
    ; vOutput := "role: " vRole "`r`n"
    ; If (vRoleText1 == vRoleText2)
        ; vOutput .= "role text: " vRoleText1 "`r`n"
    ; Else
    ; vOutput .= "role text (1): " vRoleText1 "`r`n" "role text (2): " vRoleText2 "`r`n"
    If !errorFound
        vOutput .= "name: " vName ; "`r`n"
    Else
        vOutput .= "error: " vName ; "`r`n"
    Return vOutput
}

DetectWin11()
{
    ; Get version via WMI to capture the build number
    version := ""
    buildNumber := ""
    try {
        wmi := ComObjGet("winmgmts:\\.\root\cimv2")
        for os in wmi.ExecQuery("Select * from Win32_OperatingSystem")
        {
            version := os.Version  ; e.g., "10.0.22621"
            buildNumber := os.BuildNumber  ; e.g., "22621"
            break
        }
    } catch e {
        MsgBox, Failed to query OS version.`nError: %e%
        Return False
    }

    If (SubStr(version, 1, 4) = "10.0" && buildNumber >= 22000)
        Return True
    Else
        Return False
}

; Choose the monitor containing the mouse. If none contains it (rare with odd layouts),
; pick the nearest monitor by distance.
; Summary
; First preference: the monitor that actually contains the mouse.
; Else: the nearest monitor rectangle (useful if the mouse is exactly outside due to odd DPI layouts, mis-alignment, or negative coords).
; The function returns the rectangle by reference into L, T, R, B.
; So in your drag script, every frame we call this with the current mouse (mx, my), and get the correct monitor bounds whether your monitors
; are side-by-side, stacked vertically, diagonal, or even negative-coordinate setups.

; (rLeft, rTop) ----------------- (rRight, rTop)
       ; |                        |
       ; |                        |
       ; |        Monitor         |
       ; |                        |
; (rLeft, rBottom) ------------- (rRight, rBottom)

GetMonitorRectForMouse(mx, my, useWorkArea, ByRef L, ByRef T, ByRef R, ByRef B) {
    SysGet, count, MonitorCount
    bestDist := 0x7FFFFFFF, found := false

    Loop, %count% {
        idx := A_Index
        if (useWorkArea)
            SysGet, r, MonitorWorkArea, %idx%
        else
            SysGet, r, Monitor, %idx%

        ; Inside?
        if (mx >= rLeft && mx < rRight && my >= rTop && my < rBottom) {
            L := rLeft, T := rTop, R := rRight, B := rBottom
            return
        }

        ; Distance from point to rect (0 if inside)
        cx := (mx < rLeft) ? rLeft : (mx > rRight ? rRight : mx)
        cy := (my < rTop)  ? rTop  : (my > rBottom ? rBottom : my)
        dx := mx - cx, dy := my - cy
        dist2 := dx*dx + dy*dy
        if (dist2 < bestDist) {
            bestDist := dist2
            L := rLeft, T := rTop, R := rRight, B := rBottom
            found := true
        }
    }
    if (!found) {
        ; Fallback to primary
        if (useWorkArea)
            SysGet, r, MonitorWorkArea, 1
        else
            SysGet, r, Monitor, 1
        L := rLeft, T := rTop, R := rRight, B := rBottom
    }
}

;------------------------------------------------------------------------------
;https://www.autohotkey.com/boards/viewtopic.php?t=51265
;------------------------------------------------------------------------------
OnWinActiveChange(hWinEventHook, vEvent, hWnd)
{
    global prevActiveWindows
    global StopRecursion
    global blockKeys

    If !StopRecursion && !hitTab {

        DetectHiddenWindows, Off
        SetTimer, keyTrack,   Off
        SetTimer, mouseTrack, Off

        loop 500 {
            WinGetClass, vWinClass, % "ahk_id " hWnd
            WinGetTitle, vWinTitle, % "ahk_id " hWnd
            WinGet, vWinProc, ProcessName, ahk_id %hWnd%
            If (vWinClass != "" || vWinTitle != "" || WinExist("ahk_class #32768"))
                break
            sleep, 1
        }

        ; If (vWinProc == "Everything.exe") {
            ; blockKeys := True
            ; Send, {LCtrl UP}
            ; Send, {Space UP}
            ; SendEvent, {Blind}{vkFF} ; send a dummy key (vkFF = undefined key)
            ; blockKeys := False
        ; }

        If (vWinClass == "#32770" && vWinTitle == "Run") {
            WinGetPos, rx, ry, rw, rh, ahk_id %hWnd%
            If UIA_GetStartButtonCenter(sx, sy, bw) {
                x := sx - (rw/2) - bw ; 44 is the width of a single taskbar button
                WinMove, ahk_id %hWnd%,, x,
            }
        }
        Else {
            WinGet, vWinStyle, Style, % "ahk_id " hWnd
            If (   IsOverException(hWnd)
                || ((vWinStyle & 0xFFF00000 == 0x94C00000) && vWinClass != "#32770")
                || !WinExist("ahk_id " hWnd)) {
                If (vWinClass == "#32768" || vWinClass == "OperationStatusWindow") {
                    WinSet, AlwaysOnTop, On, ahk_id %hWnd%
                }
                Return
            }
        }

        WaitForFadeInStop(hWnd)
        LbuttonEnabled := False

        If (vWinClass == "wxWindowNR" && vWinProc == "clipdiary-portable.exe") {
            EnsureFocusedCtrlNN(hWnd, "Edit1", 60, 10)
            blockKeys := True
            Send, {LCtrl UP}
            Send, {LShift UP}
            Send, {. UP}
            Send, {Backspace}
            ControlFocus, Edit1, ahk_id %hWnd%
            blockKeys := False
        }

        If ( !HasVal(prevActiveWindows, hWnd) || vWinClass == "#32770" || vWinClass == "CabinetWClass" ) {
            Critical, On
            prevActiveWindows.push(hWnd)
            Critical, Off

            KeyWait, Lbutton, U T10

            WinGet, state, MinMax, ahk_id %hWnd%
            If (state > -1 && vWinTitle != "" && MonCount > 1) {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := IsWindowOnMonNum(hWnd, currentMon)
                If !currentMonHasActWin {
                    WinActivate, ahk_id %hWnd%
                    Send, #+{Left}
                }
            }

            If (vWinClass == "#32770") {
                WinSet, AlwaysOnTop, On, ahk_id %hWnd%
            }
            Else If (vWinClass != "#32770" && WinExist("ahk_class #32770")) {
                WinSet, AlwaysOnTop, On,  ahk_id %hWnd%
                WinSet, AlwaysOnTop, Off, ahk_class #32770
                WinSet, AlwaysOnTop, Off, ahk_id %hWnd%
            }

            If (InStr(vWinTitle, "Save", False) && vWinClass != "#32770") {
                WinSet, AlwaysOnTop, On,  ahk_id %hWnd%
                WinSet, AlwaysOnTop, Off, ahk_id %hWnd%
                LbuttonEnabled := True
                Return
            }

            initFocusedCtrl := ""
            loop, 100 {
                ControlGetFocus, initFocusedCtrl, ahk_id %hWnd%
                If (initFocusedCtrl != "")
                    break
                sleep, 1
            }

            SendCtrlAdd(hWnd,,,vWinClass, initFocusedCtrl)
            LbuttonEnabled := True

            DetectHiddenWindows, On
            i := 1
            while (i <= prevActiveWindows.MaxIndex()) {
                checkID := prevActiveWindows[i]
                If !WinExist("ahk_id " checkID)
                    prevActiveWindows.RemoveAt(i)
                Else
                    ++i
                If (GetKeyState("Lbutton", "P")) {
                    break
                }
            }
        }
    }
    DetectHiddenWindows, Off
    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On
    LbuttonEnabled := True
    Return
}

; Waits until the shell view’s item list has finished populating.
; Works for both:
;   - Explorer windows (ahk_class CabinetWClass)
;   - Common file dialogs (ahk_class #32770)
; Returns an object { hwnd: <hwnd>, itemsView: <UIA element>, count: <int> }
; or 0 on timeout.
WaitForShellViewReady_UIA(hwnd := "", timeout := 10000, stableChecks := 5, poll := 100) {
    if !hwnd {
        ; If no hwnd provided, use the active window (either class will work)
        WinGet, hwnd, ID, A
        if !hwnd
            return 0
    }

    UIA   := UIA_Interface()
    root  := UIA.ElementFromHandle(hwnd)
    if !IsObject(root)
        return 0

    start := A_TickCount
    items := ""

    ; -------- 1) Find the shell view’s item list (works across Explorer + dialogs)
    ; Try List first (Explorer “Items View”), then DataGrid/Table (some dialogs), then Tree (rare)
    for _, ctlType in ["UIA_ListControlTypeId", "UIA_DataGridControlTypeId", "UIA_TableControlTypeId", "UIA_TreeControlTypeId"] {
        items := root.FindFirstBy("ControlType=" . ctlType)
        if (items)
            break
    }
    if !items
        return 0

    ; -------- 2) If there’s an active “Working on it…” progress bar, wait for it to go away
    ; Not all windows show one; that’s fine—we’ll proceed either way.
    while (A_TickCount - start < timeout) {
        prog := root.FindFirstBy("ControlType=UIA_ProgressBarControlTypeId")
        if !prog
            break
        ; Heuristic: if the progress bar is offscreen/hidden, treat as gone
        off := prog.GetCurrentPropertyValue(UIA_IsOffscreenPropertyId)
        if (off = 1)
            break
        Sleep, %poll%
    }

    ; -------- 3) Wait for the item count to stabilize
    last := -1, stable := 0
    while (A_TickCount - start < timeout) {
        ; Children() is inexpensive here and works for both Explorer + dialogs.
        cnt := items.Children().Length()

        if (cnt = last) {
            stable++
            if (stable >= stableChecks)
                return { hwnd: hwnd, itemsView: items, count: cnt }
        } else {
            last := cnt
            stable := 0
        }
        Sleep, %poll%
    }
    return 0
}

WaitForFadeInStop(hwnd) {
    HexColorLast1 :=
    HexColorLast2 :=
    HexColorLast3 :=
    HexColorLast4 :=
    HexColorLast5 :=

    WinGetPos, sx, sy, sw, sh, ahk_id %hwnd%
    sampleX := (sx + sw)/2
    sampleY := (sy + 13)
    CoordMode, Pixel, Screen
    loop 500 {
        PixelGetColor, HexColor%A_Index%, %sampleX%, %sampleY%, RGB
        If (A_Index >= 5) {
            If (HexColor%A_Index% == HexColorLast1 && HexColorLast1 == HexColorLast2 && HexColorLast2 == HexColorLast3 && HexColorLast3 == HexColorLast4 && HexColorLast4 == HexColorLast5)
                break
            HexColorLast1 := HexColor%A_Index%
            HexColorLast2 := HexColorLast1
            HexColorLast3 := HexColorLast2
            HexColorLast4 := HexColorLast3
            HexColorLast5 := HexColorLast4
        }
        sleep, 1
    }
    CoordMode, Mouse, screen
    Return
}

; --------------------------------------------------
; Unhook on exit
; --------------------------------------------------
UnhookHooks:
    StopRecursion := True
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off

    if (hActWin)
        DllCall( "UnhookWinEvent", "Ptr", hActWin)
    if (hHookKbd)
        DllCall("UnhookWindowsHookEx", "Ptr", hHookKbd)
    if (hHookMouse)
        DllCall("UnhookWindowsHookEx", "Ptr", hHookMouse)
    ExitApp
return

; Uses UIA_Interface.ahk to find the Start button and return its center (screen coords).
UIA_GetStartButtonCenter(ByRef sx, ByRef sy, ByRef buttonWidth) {
    global UIA

    try {
        hTask := WinExist("ahk_class Shell_TrayWnd")
        if !hTask
            return False

        tb := UIA.ElementFromHandle(hTask)
        if (IsObject(tb)) {
            ; Try several robust queries (name is localized; AutomationId often stable)
            startEl := tb.FindFirstBy("AutomationId=StartButton")

            if !IsObject(startEl)
                startEl := tb.FindFirstByNameAndType("Start", "Button")
            if !IsObject(startEl)
                startEl := tb.FindFirstByNameAndType("Start menu", "Button")
            if !IsObject(startEl)
                return False

            ; Get bounding rectangle and compute center
            ; UIA_Interface exposes CurrentBoundingRectangle (object with x,y,w,h)
            rect := startEl.CurrentBoundingRectangle
            if (!IsObject(rect) && rect == "") {
                ; Older versions may expose .BoundingRectangle or GetBoundingRectangle()
                rect := startEl.BoundingRectangle ? startEl.BoundingRectangle : startEl.GetBoundingRectangle()
            }
        }
        else {
            tooltip, no taskbar found...
            sleep, 1500
            tooltip,
        }

        if (IsObject(rect)) {
            sx := round(rect.l + (rect.r-rect.l)/2)
            sy := round(rect.t + (rect.b-rect.t)/2)
            buttonWidth := rect.r-rect.l
            return true
        }
        else
            return False

    } catch e {
        return False
    }
}

$~^Enter::
    DetectHiddenWindows, Off
    WinGet, myWindow, List
    Loop % myWindow
    {
        ControlGet, myOkay, Hwnd,, OK, % "ahk_id " myWindow%A_Index%
        If (myOkay) {
            ControlClick,, ahk_id %myOkay%,,,2
            hwndID := "ahk_id " myWindow%A_Index%
            sleep, 400
            If WinExist(hwndID)
                Send, !{o}
            break
        }
    }
    FixModifiers()
Return

$^WheelUp::
    If ((IsConsoleWindow() || textBoxSelected) && !MouseIsOverTitleBar()) {
        StopRecursion := True
        SetTimer, MbuttonTimer, Off
        Send, {UP}
        sleep, 125
        SetTimer, MbuttonTimer, -1
        StopRecursion := False
    }
    Else {
        Send, ^{WheelUp}
    }
Return

$^WheelDown::
    If ((IsConsoleWindow() || textBoxSelected) && !MouseIsOverTitleBar()) {
        StopRecursion := True
        SetTimer, MbuttonTimer, Off
        Send, {DOWN}
        sleep, 125
        SetTimer, MbuttonTimer, -1
        StopRecursion := False
    }
    Else {
        Send, ^{wheelDown}
    }
Return

MbuttonTimer:
    MbuttonIsEnter := True
    sleep, 1500
    MbuttonIsEnter := False
Return

#If MbuttonIsEnter
Mbutton::
    Send, {Enter}
    SetTimer, MbuttonTimer, Off
    SetTimer, MbuttonTimer, -1
Return
#If

; ===========================
    ; Auto-execute section
; ===========================
WU_lastZoomTime  := 0   ; last time we sent ^{NumpadAdd}
WU_lastWheelTime := 0   ; last time any WheelDown happened
WU_burstGap      := 250 ; ms: gap that defines a "new burst"
WU_zoomInterval  := 200 ; ms: min time between zooms *within* a burst

$~WheelUp::
    global WU_lastZoomTime, WU_lastWheelTime, WU_burstGap, WU_zoomInterval
    StopRecursion := True
    Critical, Off
    Sleep, -1


    If (!MouseIsOverTitleBar() && !MouseIsOverTaskbarBlank()) {
        MouseGetPos,,, wdID, wuCtrl
        WinGetClass, hoverClass, ahk_id %wdID%
        WinGetClass, activeClass, A

        ; Only do zoom logic for your target controls
        If (hoverClass != "ProgMan"
         && hoverClass != "WorkerW"
         && hoverClass != "Notepad++"
         && hoverClass != "CASCADIA_HOSTING_WINDOW_CLASS"
         && activeClass != "CASCADIA_HOSTING_WINDOW_CLASS"
         && (wuCtrl == "SysListView321"
          || wuCtrl == "DirectUIHWND2"
          || wuCtrl == "DirectUIHWND3"))
        {
            now := A_TickCount

            ; --- Burst detection ---
            ; If enough time has passed since the last wheel,
            ; treat this as the first event of a new burst.
            If (now - WU_lastWheelTime > WU_burstGap) {
                WU_lastZoomTime := 0  ; reset so first event always zooms
                ControlFocus, %wuCtrl%, ahk_id %wdID%
            }
            WU_lastWheelTime := now

            ; --- Zoom timing ---
            ; First in burst (WU_lastZoomTime=0) -> zoom immediately.
            ; In a burst -> zoom only If >= WU_zoomInterval has passed.
            If (WU_lastZoomTime = 0 || now - WU_lastZoomTime >= WU_zoomInterval) {
                Critical, On
                WU_lastZoomTime := now
                ; Optional debug:
                ; ToolTip % "Zoom at: " . now
                ; SetTimer, ClearToolTip, -400
                blockKeys := True
                Send, ^{NumpadAdd}
                blockKeys := False
                Critical, Off
                FixModifiers()
            }
        }
        ; We still want normal scrolling here, so handled stays False
    }
    Else If MouseIsOverTaskbarBlank() {
        Send, #^{Left}
        sleep, 1000
    }
    StopRecursion := False
Return

; ===========================
; Auto-execute section
; ===========================
WD_lastZoomTime  := 0   ; last time we sent ^{NumpadAdd}
WD_lastWheelTime := 0   ; last time any WheelDown happened
WD_burstGap      := 250 ; ms: gap that defines a "new burst"
WD_zoomInterval  := 200 ; ms: min time between zooms *within* a burst

$~WheelDown::
    global WD_lastZoomTime, WD_lastWheelTime, WD_burstGap, WD_zoomInterval
    StopRecursion := True
    Critical, Off
    Sleep, -1


    If (!MouseIsOverTitleBar() && !MouseIsOverTaskbarBlank()) {
        MouseGetPos,,, wdID, wuCtrl
        WinGetClass, hoverClass, ahk_id %wdID%
        WinGetClass, activeClass, A

        ; Only do zoom logic for your target controls
        If (hoverClass != "ProgMan"
         && hoverClass != "WorkerW"
         && hoverClass != "Notepad++"
         && hoverClass != "CASCADIA_HOSTING_WINDOW_CLASS"
         && activeClass != "CASCADIA_HOSTING_WINDOW_CLASS"
         && (wuCtrl == "SysListView321"
          || wuCtrl == "DirectUIHWND2"
          || wuCtrl == "DirectUIHWND3"))
        {
            now := A_TickCount

            ; --- Burst detection ---
            ; If enough time has passed since the last wheel,
            ; treat this as the first event of a new burst.
            If (now - WD_lastWheelTime > WD_burstGap) {
                WD_lastZoomTime := 0  ; reset so first event always zooms
                ControlFocus, %wuCtrl%, ahk_id %wdID%
            }
            WD_lastWheelTime := now

            ; --- Zoom timing ---
            ; First in burst (WD_lastZoomTime=0) -> zoom immediately.
            ; In a burst -> zoom only If >= WD_zoomInterval has passed.
            If (WD_lastZoomTime = 0 || now - WD_lastZoomTime >= WD_zoomInterval) {
                Critical, On
                WD_lastZoomTime := now
                ; Optional debug:
                ; ToolTip % "Zoom at: " . now
                ; SetTimer, ClearToolTip, -400
                blockKeys := True
                Send, ^{NumpadAdd}
                blockKeys := False
                Critical, Off
                FixModifiers()
            }
        }
        ; We still want normal scrolling here, so handled stays False
    }
    Else If (MouseIsOverTitleBar()) {
        ; In this branch we swallow the wheel
        blockKeys := True
        MouseGetPos,,, winHwnd, ctrlHwnd, 2

        rootHwnd := DllCall("GetAncestor", "ptr", winHwnd, "uint", 2, "ptr") ; GA_ROOT

        WinMinimize, ahk_id %rootHwnd%
        Sleep, 500
        blockKeys := False
        Return
    }
    Else If MouseIsOverTaskbarBlank() {
        Send, #^{Right}
        sleep, 1000
    }
    StopRecursion := False
Return
#MaxThreadsPerHotkey 1

IsConsoleWindow() {
    WinGetClass, targetClass, A
    If (targetClass == "mintty" || targetClass == "CASCADIA_HOSTING_WINDOW_CLASS" || targetClass == "ConsoleWindowClass")
        Return True
    Else
        Return False
}

IsWindowScrollable() {
    MouseGetPos, , , hwnd, ctrlN
    WinGet, ExControlStyle, ExStyle, ahk_id %hwnd%
    ControlGet, ControlStyle, Style,, %ctrlN%, ahk_id %hwnd%
    If (((ControlStyle & 0x100000) || (ControlStyle & 0x200000)) || (ExControlStyle & 0x4000)) {
        ; tooltip, is scrollable %ControlStyle%
        Return True
    }
    Else {
        ; tooltip, NOT scrollable %ControlStyle%
        Return False
    }
}

IsMouseOnLeftSide() {
    divisor := 5
    MouseGetPos, mx, my, hwnd, ctrlN
    If (!ctrlN) {
        WinGetPos, x, y, w, h, ahk_id %hwnd%
        ; tooltip, % x "-" y "-" x+w "-" y+h "-" mx "-" my
        ; If (mx > x && mx < (x+w/divisor) && my > y && my < (y+h)) {
        If (mx > x && mx < (x+300) && my > y && my < (y+h)) {
            Return True
        }
        Else
            Return False
    }
    Else {
        ControlGetPos , cx, cy, cw, ch, %ctrlN%, ahk_id %hwnd%
        If (cx && cy && cw && ch) {
            ; If (mx > cx && mx < (cx+cw/divisor) && my > cy && my < (cy+ch)) {
            If (mx > cx && mx < (cx+300) && my > cy && my < (cy+ch)) {
                Return True
            }
        }
        Else
            Return False
    }
}

#If !MbuttonIsEnter && !MouseIsOverTaskbar()
$*MButton::
    global DraggingWindow

    StopRecursion := True
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    Hotkey, *Rbutton, DoNothing, On
    Hotkey, Mbutton & Rbutton, DoNothing, On

    MouseGetPos, mx0, my0, hWnd, ctrl, 2

    isOverTitleBar        := MouseIsOverTitleBar(mx0, my0)
    checkClickMx          := mx0
    checkClickMy          := my0
    wx0                   := 0
    wy0                   := 0
    ww                    := 0
    wh                    := 0
    virtwx0               := 0
    virtwy0               := 0
    offsetX               := 0
    offsetY               := 0
    windowSnapped         := False
    TL                    := False
    TR                    := False
    BL                    := False
    BR                    := False
    snapShotX             := 0
    snapShotY             := 0
    adjustSize            := False
    isRbutton             := False
    switchingBackToMove   := False
    switchingBacktoResize := False
    skipAlwaysOnTop       := False

    If (!hWnd || !JEE_WinHasAltTabIcon(hWnd))
        return

    initTime := A_TickCount

    WinGet, isMax, MinMax, ahk_id %hWnd%
    WinGetClass, cls, ahk_id %hWnd%
    If (skipClasses.HasKey(cls)) {
        KeyWait, Mbutton, U T3
        Send, {Mbutton}
        return
    }

    BlockInput, MouseMove
    WinGetPosEx(hWnd, wx0, wy0, ww, wh, offsetX, offsetY)
    If (ww = "" || wh = "") {
        BlockInput, MouseMoveOff
        KeyWait, Mbutton, U T3
        Send, {Mbutton}
        return
    }

    snapState     := ""   ; "", "left", "right"
    mxPrev        := mx0  ; track prior mouse X to know approach direction
    myPrev        := my0  ; track prior mouse X to know approach direction

    leftWinEdge   := wx0
    topWinEdge    := wy0
    rightWinEdge  := wx0 + ww
    bottomWinEdge := wy0 + wh

    ; msgbox, % leftWinEdge "," rightWinEdge "-" topWinEdge "," bottomWinEdge ":" offsetX " & " offsetY
    startMon := MWAGetMonitorMouseIsIn()
    GetMonitorRectForMouse(mx0, my0, UseWorkArea, monL, monT, monR, monB)
    If ((leftWinEdge - monL) <= SnapRange && (leftWinEdge - monL) >= 0) {
        snapState := "left"
    } Else If ((rightWinEdge - monR) <= SnapRange && (rightWinEdge - monR) >= 0) {
        snapState := "right"
    }

    If      (mx0 <= leftWinEdge + floor(ww/2) && my0 <= wy0 + floor(wh/2))
        TL := True
    Else If (mx0 >  leftWinEdge + floor(ww/2) && my0 <= wy0 + floor(wh/2))
        TR := True
    Else If (mx0 <= leftWinEdge + floor(ww/2) && my0 >  wy0 + floor(wh/2))
        BL := True
    Else If (mx0 >  leftWinEdge + floor(ww/2) && my0 >  wy0 + floor(wh/2))
        BR := True

    WinSet, Transparent, 255, ahk_id %hWnd%

    If (wh/abs(monB-monT) > 0.95) {
        WinMove, ahk_id %hWnd%, , , %monT%, , abs(monB-monT)+2*abs(offsetY) + 1
        WinGetPosEx(hWnd, wx0, wy0, ww, wh, offsetX, offsetY)
        leftWinEdge   := wx0
        topWinEdge    := wy0
        rightWinEdge  := wx0 + ww
        bottomWinEdge := wy0 + wh
    }

    BlockInput, MouseMoveOff

    skipAlwaysOnTop := IsAlwaysOnTop(hWnd)

    Critical, On
    while GetKeyState("MButton", "P") {

        DraggingWindow := True
        isRbutton := GetKeyState("Rbutton","P")
        If (!isRbutton && isRbutton_last) {
            BlockInput, MouseMove
            sleep, 250
            BlockInput, MouseMoveOff
            switchingBackToMove := True
        }
        Else
            switchingBackToMove := False

        If (isRbutton && !isRbutton_last) {
            switchingBacktoResize := True
        }
        Else
            switchingBacktoResize := False

        isRbutton_last := isRbutton

        windowSnapped := False

        MouseGetPos, mx, my,

        If switchingBackToMove {
            mx0 := mx
            my0 := my
            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
        }
        Else If switchingBacktoResize {
            mx0 := mx
            my0 := my
            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
        }

        If (isMax == 1 && (abs(mx - mx0) > 5 || abs(my - my0) > 5)) {
            BlockInput, Mousemove
            xRatio := (mx-monL)/ww
            yRatio := (my-monT)/wh
            ; Guard against weirdness
            if (xRatio < 0)
                xRatio := 0
            if (xRatio > 1)
                xRatio := 1
            if (yRatio < 0)
                yRatio := 0
            if (yRatio > 1)
                yRatio := 1

            WinRestore, ahk_id %hWnd%
            WaitForStableWindow(hWnd)

            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
            moveToX := Round(mx - xRatio * ww)
            moveToY := Round(my - yRatio * wh)

            WinMove, ahk_id %hWnd%,, %moveToX%, %moveToY%
            WaitForStableWindow(hWnd)

            isMax == 0
            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
            MouseGetPos, mx, my,
            BlockInput, MouseMoveOff
        }

        dragHorz := ""
        dragVert := ""
        If ((my - myPrev) < 0) && abs(my - my0) > 5 && abs(my - myPrev) > (abs(mx - mxPrev))   {
            dragVert := "up"
        }
        Else If ((my - myPrev) > 0) && abs(my - my0) > 5  && abs(my - myPrev) > (abs(mx - mxPrev))  {
            dragVert := "down"
        }
        Else If ((mx - mxPrev) > 0 && abs(mx - mx0) > 5) {
            dragHorz := "right"
        }
        Else If ((mx - mxPrev) < 0 && abs(mx - mx0) > 5) {
            dragHorz := "left"
        }
        mxPrev := mx
        myPrev := my

        If (dragHorz_prev != "" && dragHorz != "" && dragHorz_prev != dragHorz)
        || (dragVert_prev != "" && dragVert != "" && dragVert_prev != dragVert) {
            mx0 := mx
            my0 := my
            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
        }

        If WinExist("ahk_class tooltips_class32")
            WinClose, ahk_class tooltips_class32

        If dragHorz
            dragHorz_prev := dragHorz
        If dragVert
            dragVert_prev := dragVert

        dx := mx - mx0
        dy := my - my0

        WinGet, trans, Transparent, ahk_id %hWnd%
        If (trans == 255 && (abs(dx) > 5 || abs(dy) > 5)) {
            WinSet, Transparent, 225, ahk_id %hWnd%
            sleep, 8
            WinSet, Transparent, 200, ahk_id %hWnd%
            sleep, 8
            WinSet, Transparent, 185, ahk_id %hWnd%
        }

        GetMonitorRectForMouse(mx, my, UseWorkArea, monL, monT, monR, monB)
        monW := monR-monL
        monH := monB-monT
        ; Vertical allowable range for current monitor
        minX  := monL
        minY  := monT
        maxY  := monB - wh
        maxHD := (monB - wy0)
        maxHU := (wy0+wh - monT)
        maxWL := (wx0 + ww) - monL
        maxWR := (monR - wx0)

        ; virtwx0 is continuously changing with your mouse and represents the current theoretical value of the window's x coordinate.
        ; it's "theoretical" because the window may be "snapped" but this value will still change as the mouse moves which
        ; is why you can compare virtwx0 against the difference between monL and BreakAway/ReleaseAway distances
        ; monL is fixed to the active monitor’s left edge.
        virtwx0 := wx0 + dx ; (original window X) + (how far the mouse has moved in X since drag start)
        virtwy0 := wy0 + dy

        If !isRbutton {
            WinSet, AlwaysOnTop, On, ahk_id %hWnd%
            UnclipCursor()
            ; --- One-way vertical clamp (top/bottom) ---
            If (virtwy0 < minY)
                newY := minY
            Else If (virtwy0 > maxY)
                newY := maxY
            Else
                newY := virtwy0

            ; --- Horizontal snapping with pass-through ---
            leftWinEdge   := virtwx0
            rightWinEdge  := virtwx0 + ww

            rightSnapX    := monR - ww  ; X that places the right edge at monitor's right

            WinGetPosEx(hWnd, null, null, ww, wh, null, null)
            If (snapState = "left") {
                ; While snapped left:
                ; - Push-through: keep dragging left until virtwx0 <= monL - BreakAway to break snap
                ; - Release: drag right until virtwx0 >= monL + ReleaseAway to release snap
                ; ie Have you moved (virtwx0) far enough past the monitor edge (monL) → BreakAway/ReleaseAway
                If (virtwx0 <= monL - BreakAway || virtwx0 >= monL + ReleaseAway) {
                    snapState := ""
                    newX := virtwx0
                } Else {
                    newX := monL
                }
            } Else If (snapState = "right") {
                ; While snapped right (window's right edge at monR):
                ; - Push-through: keep dragging right until virtwx0 >= rightSnapX + BreakAway to break snap
                ; - Release: drag left until virtwx0 <= rightSnapX - ReleaseAway to release snap
                If (virtwx0 >= rightSnapX + BreakAway || virtwx0 <= rightSnapX - ReleaseAway) {
                    snapState := ""
                    newX := virtwx0
                } Else {
                    newX := rightSnapX
                }
            } Else {
                ; Not currently snapped: check proximity to edges to start snapping
                If (Abs(leftWinEdge - monL) <= SnapRange && dragHorz == "left") {
                    snapState := "left"
                    windowSnapped := True
                    newX := monL
                    ; tooltip, snapState %snapState%
                } Else If (Abs(rightWinEdge - monR) <= SnapRange && dragHorz == "right") {
                    snapState := "right"
                    windowSnapped := True
                    newX := rightSnapX
                    ; tooltip, snapState %snapState%
                } Else {
                    newX := virtwx0
                    ; tooltip, snapState "none" - %virtwx0% - %dx% - %dy%
                }
            }

            ; correct for windows' shadows
            newX := newX + offsetX
            ; No horizontal clamping otherwise: allow off-screen left/right
            WinMove, ahk_id %hWnd%, , %newX%, %newY%
        }
        Else {
            gridSize := SnapRange

            gridDx := ceil(dx/gridSize) * gridSize
            gridDy := ceil(dy/gridSize) * gridSize

            If      (TL || TR) && (dragVert == "up"   || dragVert == "down") {
                WinGetPosEx(hWnd, tx, ty, tw, th, null, null)
                If (dragVert == "up" && ty == minY) {
                    adjustSize := False
                    BlockInput, MouseMove
                    MouseMove, mx, my
                    ConfineMouseToCurrentMonitorArea( "work", 0, my, monW, monH-my)
                    sleep, 250
                    BlockInput, MouseMoveOff
                }
                Else {
                    If (dragVert == "up") {
                        virtwy0 := wy0 - abs(gridDy)
                        virtwh0 := wh  + abs(gridDy)
                        If ((virtwh0 > maxHU - SnapRange) || (virtwy0 < minY + SnapRange)) {
                            virtwy0 := minY
                            virtwh0 := maxHU
                        }
                    }
                    Else If (dragVert == "down") {
                        virtwh0 := wh - abs(dy)
                    }

                    adjustSize := True
                    newX :=
                    newY := virtwy0
                    newW :=
                    newH := virtwh0 + 2*abs(offsetY) + 1 ; these adjustments are ONLY needed for WinMove, WinGetPosEx is 100% accurate
                }
            }
            Else If (BL || BR) && (dragVert == "up"   || dragVert == "down") {
                WinGetPosEx(hWnd, tx, ty, tw, th, null, null)
                If (dragVert == "down" && th == maxHD) {
                    adjustSize := False
                    BlockInput, MouseMove
                    MouseMove, mx, my
                    ConfineMouseToCurrentMonitorArea( "work", 0, 0, monW, my)
                    sleep, 250
                    BlockInput, MouseMoveOff
                }
                Else {
                    If (dragVert == "down") {
                        ; virtwy0 doesnt matter since it remains fixed when adjusting width
                        virtwh0 := wh + abs(gridDy)
                        If (virtwh0 > maxHD - SnapRange)
                            virtwh0 := maxHD
                    }
                    Else If (dragVert == "up") {
                        virtwh0 := wh - abs(dy)
                    }

                    adjustSize := True
                    newX :=
                    newY :=
                    newW :=
                    newH := virtwh0 + 2*abs(offsetY) + 1 ; these adjustments are ONLY needed for WinMove, WinGetPosEx is 100% accurate
                }
            }
            Else If (TL || BL) && (dragHorz == "left" || dragHorz == "right") {
                WinGetPosEx(hWnd, tx, ty, tw, th, null, null)
                If (dragHorz == "left" && tx == minX) {
                    adjustSize := False
                    BlockInput, MouseMove
                    MouseMove, mx, my
                    ConfineMouseToCurrentMonitorArea( "work", mx, 0, monW-mx, monH)
                    sleep, 250
                    BlockInput, MouseMoveOff
                }
                Else {
                    If (dragHorz == "left") {
                        virtwx0 := wx0 - abs(gridDx)
                        virtww0 := ww  + abs(gridDx)
                        If ((virtww0 > (maxWL - SnapRange)) || (virtwx0 < (minX + SnapRange))) {
                            virtwx0 := minX
                            virtww0 := maxWL
                        }
                    }
                    Else If (dragHorz == "right") {
                        virtww0 := ww - abs(dx)
                    }

                    adjustSize := True
                    newX := virtwx0 + offsetX
                    newY :=
                    newW := virtww0  + 2*abs(offsetX)
                    newH :=
                }
            }
            Else If (TR || BR) && (dragHorz == "left" || dragHorz == "right") {
                WinGetPosEx(hWnd, tx, ty, tw, th, null, null)
                If (dragHorz == "right" && tx+tw == monR) {
                    adjustSize := False
                    BlockInput, MouseMove
                    MouseMove, mx, my
                    ConfineMouseToCurrentMonitorArea( "work", 0, 0, mx, monH)
                    sleep, 250
                    BlockInput, MouseMoveOff
                }
                Else {
                    If (dragHorz == "right") {
                        ; virtwx0 doesnt matter since it remains fixed when adjusting width
                        virtww0 := ww + abs(gridDx)
                        If (virtww0 > (maxWR - SnapRange))
                            virtww0 := maxWR
                    }
                    Else If (dragHorz == "left") {
                        virtww0 := ww - abs(dx)
                    }

                    adjustSize := True
                    newX :=
                    newY :=
                    newW :=virtww0 + 2*abs(offsetX)
                    newH :=
                }
            }

            ; correct for windows' shadows
            If adjustSize {
                WinMove, ahk_id %hWnd%, , %newX%, %newY%, %newW%, %newH%
            }
        }

        If (windowSnapped) {
            BlockInput, MouseMove
            sleep, 250
            BlockInput, MouseMoveOff
        }
    }
    Critical, Off

    rlsTime := A_TickCount
    stopMon := MWAGetMonitorMouseIsIn()

    If (rlsTime - initTime < floor(DoubleClickTime/2)
        && isOverTitleBar
        && (abs(checkClickMx - mx0) <= 5)
        && (abs(checkClickMy - my0) <= 5)) {

        WinSet, Transparent, Off, ahk_id %hWnd%
        GoSub, SwitchDesktop
    }
    Else If (rlsTime - initTime < floor(DoubleClickTime/2)
            && (abs(checkClickMx - mx0) <= 5)
            && (abs(checkClickMy - my0) <= 5)) {
        Send, {Mbutton}
    }
    Else If (wh/abs(monB-monT) > 0.95)
        WinMove, ahk_id %hWnd%, , , %monT%, , abs(monB-monT)+2*abs(offsetY) + 1

    If !skipAlwaysOnTop
        WinSet, AlwaysOnTop, Off, ahk_id %hWnd%

    WinSet, Transparent, Off, ahk_id %hWnd%

    If (GetKeyState("Ctrl","P") && startMon != stopMon && MonCount > 1) { ; mouse dragged window
        WinSet, AlwaysOnTop, On, ahk_id %hWnd%
        WinGet, targetProcess, ProcessName, ahk_id %hWnd%
        WinGet, windowsFromProc, list, ahk_exe %targetProcess% ahk_class %cls%
            ; Get monitor rectangles for start/stop monitors
        SysGet, startMonInfo, Monitor, %startMon%
        SysGet, stopMonInfo,  Monitor, %stopMon%

        dx := stopMonInfoLeft - startMonInfoLeft
        dy := stopMonInfoTop  - startMonInfoTop
        ; Optional: avoid weird re-entrancy from hotkey → disable other threads
        Critical, On
        SetWinDelay, -1

        Loop %windowsFromProc% {
            thisId := windowsFromProc%A_Index%

            ; Skip windows that aren't on the start monitor
            if !IsWindowOnMonNum(thisId, startMon)
                continue

            ; Get current position/size
            WinGetPos, wx, wy, ww, wh, ahk_id %thisId%

            ; Compute new coordinates on target monitor
            newX := wx + dx
            newY := wy + dy

            ; Move the window directly instead of using Win+Shift+Arrow
            WinMove, ahk_id %thisId%, , newX, newY
        }

        Critical, Off
        previousMon := stopMon
    }

    StopRecursion := False
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
    Hotkey, *Rbutton, DoNothing, Off
    Hotkey, Mbutton & Rbutton, DoNothing, Off
    DraggingWindow := False
Return
#If

WaitForStableWindow(hwnd, delay := 30, timeout := 1000) {
    lastW := lastH := 0
    elapsed := 0
    Loop {
        WinGetPos,,, w, h, ahk_id %hwnd%
        if (w = lastW && h = lastH)
            return true
        lastW := w, lastH := h
        Sleep, delay
        elapsed += delay
        if (elapsed > timeout)
            return false
    }
}

; =========================
; ConfineMouseToCurrentMonitorArea(area, x, y, w, h)
; =========================
; area  - "work" (exclude taskbar) or "monitor" (full monitor). Default = "work".
; x, y  - offset from top-left corner of chosen area (in pixels)
; w, h  - width and height of the box (in pixels)
ConfineMouseToCurrentMonitorArea(area := "work", x := 0, y := 0, w := 0, h := 0) {
    ; Get current mouse position
    MouseGetPos, mx, my

    ; Get monitor handle under cursor
    hMon := DllCall("user32\MonitorFromPoint", "int64", (my << 32) | (mx & 0xFFFFFFFF), "uint", 2, "ptr")
    if !hMon
        return 0

    ; Prepare MONITORINFO structure
    VarSetCapacity(mi, 40, 0)
    NumPut(40, mi, 0, "UInt")

    if !DllCall("user32\GetMonitorInfo", "ptr", hMon, "ptr", &mi)
        return 0

    ; rcMonitor (offset 4), rcWork (offset 20)
    monL  := NumGet(mi,  4, "Int"), monT  := NumGet(mi,  8, "Int")
    monR  := NumGet(mi, 12, "Int"), monB  := NumGet(mi, 16, "Int")
    workL := NumGet(mi, 20, "Int"), workT := NumGet(mi, 24, "Int")
    workR := NumGet(mi, 28, "Int"), workB := NumGet(mi, 32, "Int")

    ; Determine which area to use
    area := (area = "MONITOR" || area = "monitor") ? "monitor" : "work"
    if (area = "monitor") {
        baseL := monL, baseT := monT, baseR := monR, baseB := monB
    } else {
        baseL := workL, baseT := workT, baseR := workR, baseB := workB
    }

    baseW := baseR - baseL
    baseH := baseB - baseT

    ; Clamp the box within monitor boundaries
    if (w <= 0) || (w > baseW)
        w := baseW
    if (h <= 0) || (h > baseH)
        h := baseH
    if (x < 0)
        x := 0
    if (y < 0)
        y := 0
    if (x + w > baseW)
        x := baseW - w
    if (y + h > baseH)
        y := baseH - h

    ; Compute absolute screen coords
    left   := baseL + x
    top    := baseT + y
    right  := left + w
    bottom := top + h

    ; Build RECT and clip
    VarSetCapacity(rc, 16, 0)
    NumPut(left,   rc,  0, "Int")
    NumPut(top,    rc,  4, "Int")
    NumPut(right,  rc,  8, "Int")
    NumPut(bottom, rc, 12, "Int")

    return DllCall("user32\ClipCursor", "ptr", &rc) ? 1 : 0
}

; Unclip
UnclipCursor() {
    return DllCall("user32\ClipCursor", "ptr", 0) ? 1 : 0
}

$^+Esc::
    Run, C:\Program Files\SystemInformer\SystemInformer.exe
Return

$CapsLock::
    TimeOfLastHotkeyTyped := A_TickCount
    Send {Delete}
    lastHotkeyTyped := "CapsLock"
Return

#If (!WinActive("ahk_exe notepad++.exe") && !WinActive("ahk_exe Everything.exe") && !WinActive("ahk_exe Code.exe") && !WinActive("ahk_exe EXCEL.EXE") && !IsEditFieldActive())
^+d::
    if (WinExist("ahk_class rctrl_renwnd32") && ControlExist("OOCWindow1", "ahk_class rctrl_renwnd32"))
        Send, {Esc}

    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    Send, {Down}
    sleep, 10
    Send, {Home}{Home}
    sleep, 10
    Send, +{up}
    sleep, 10
    Send, +{Home}
    ; Send, {End}
    ; Send, +{Home}+{Home}+{Home}
    sleep, 10
    Send, {Delete}

    ; Your environment reset
    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

^d::
    if (WinExist("ahk_class rctrl_renwnd32") && ControlExist("OOCWindow1", "ahk_class rctrl_renwnd32"))
        Send, {Esc}

    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True
    ; If there’s no caret (e.g., not in a text field), pass through native Ctrl+Shift+D.
    if (A_CaretX = "")
    {
        Send ^+d
        Return
    }
    Send, {Ctrl Up}
    ; Your environment hooks
    ; StopAutoFix := True
    ; SetTimer, keyTrack, Off

    ; 1) Go to absolute start of the line and select it
    Send, {Home}{Home}
    Sleep, 10
    Send, +{End}
    Sleep, 10

    ; 2) Copy the line text via your clipboard-safe helper
    lineText := Clip()   ; returns the copied text, clipboard will auto-restore later

    ; 3) Insert a newline and paste the duplicate line BELOW
    Send, {End}
    Sleep, 10
    Send, {Enter}
    Sleep, 10
    Send, +{Home}
    Sleep, 10
    Clip(lineText)       ; paste via helper (keeps clipboard safe)
    Sleep, 10

    ; 4) Return caret to the original line at column 1 (reliably cross-editor)
    Send, {Up} ; {Home}{Home}
    Sleep, 100
    ; Optional: if you prefer immediate clipboard restore instead of the ~700ms timer, uncomment:
    ; Clip("", "", "RESTORE")

    ; Your environment reset
    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return
#If

ControlExist(ctrl, winTitle := "", winText := "") {
    ControlGet, hCtl, Hwnd,, %ctrl%, %winTitle%, %winText%
    Return !!hCtl
}

!a::
    StopAutoFix := True
    Send, {Home}
    Hotstring("Reset")
    StopAutoFix := False
Return

!;::
    StopAutoFix := True
    Send, {End}
    Hotstring("Reset")
    StopAutoFix := False
Return

!+;::
    StopAutoFix := True
    Send, +{End}
    Hotstring("Reset")
    StopAutoFix := False
Return

!+i::
    StopAutoFix := True
    Send +{UP}
    Hotstring("Reset")
    StopAutoFix := False
Return

!+k::
    StopAutoFix := True
    Send +{Down}
    Hotstring("Reset")
    StopAutoFix := False
Return

!+':: ;'
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := """" . store . """"
    Else
        store := """" . store . """" . " "
    Clip(store)

    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

!+[::
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "{" . store . "}"
    Else
        store := "{" . store . "} "
    Clip(store)

    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

!+]::
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "{" . store . "}"
    Else
        store := "{" . store . "} "
    Clip(store)

    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

!+<::
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "<" . store . ">"
    Else
        store := "<" . store . "> "
    Clip(store)

    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

!+>::
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "<" . store . ">"
    Else
        store := "<" . store . "> "
    Clip(store)

    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

!+(::
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "(" . store . ")"
    Else
        store := "(" . store . ") "
    Clip(store)

    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

!+)::
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "(" . store . ")"
    Else
        store := "(" . store . ") "
    Clip(store)

    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

!+b::
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "\b" . store . "\b"
    Else
        store := "\b" . store . "\b "
    Clip(store)

    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

!+5::
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    StopAutoFix := True
    blockKeys   := True

    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "%" . store . "%"
    Else
        store := "%" . store . "% "
    Clip(store)

    Hotstring("Reset")
    StopAutoFix := False
    blockKeys   := False
    FixModifiers()
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return

$!i::
    StopAutoFix := True
    Send, {UP}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!k::
    StopAutoFix := True
    Send, {Down}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!j::
    StopAutoFix := True
    Send, ^{Left}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!+j::
    StopAutoFix := True
    SendLevel, 1
    Send, ^+{Left}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!^j::
    StopAutoFix := True
    Send, {Left}
    ; StopAutoFix := False
Return

$!l::
    StopAutoFix := True
    Send, ^{Right}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!+l::
    StopAutoFix := True
    Send ^+{Right}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!h::
    Send, {Backspace}
Return

#If disableEnter
$Enter::
    GoSub, FixSlash
    disableEnter := False
Return
#If

; --- Volume control when holding Left Win ---
#If GetKeyState("LWin", "P")   ; condition: while LWin is physically held
$WheelUp::Send {Volume_Up}
$WheelDown::Send {Volume_Down}
#If   ; end of context-sensitive block
;=============== KILL WINDOWS SHORTCUT KEYS =============
; Block bare Win keys
*LWin::Return
*RWin::Return
*LWin up::Return
*RWin up::Return

; Optionally block specific Windows shortcuts
#d::Return      ; Block Win+D (Show desktop)
#i::Return      ; Block Win+I (Settings)
#x::Return      ; Block Win+X (Power user menu)
#v::Return      ; Block Win+V (Clipboard history)
#space::Return  ; Block Win+Space (input language switch)
#+s::Return

; =========================================================

#If !disableEnter && (WinActive("ahk_class CabinetWClass") || WinActive("ahk_class #32770"))
$~Enter::
    ControlGetFocus, entCtrl, A
    WinGetClass, entCl, A
    WinGetTitle, entTi, A
    WinGet, entID, ID, A
    If     (entCl == "CabinetWClass" && InStr(entCtrl, "Edit", True))
        || (entCl == "#32770" && InStr(entCtrl, "Edit", True) && (InStr(entTi, "Save", True) || InStr(entTi, "Open", True))) {

        Keywait, Enter, U T3

        WinGet, checkID, ID, A
        If (checkID == entID)
            SendCtrlAdd(entID, , , entCl)
        }
Return

$~F2::
    LbuttonEnabled := False
    StopRecursion  := True
    SetTimer, mouseTrack, Off
    SetTimer, keyTrack,   Off

    KeyWait, F2, U T3

    loop 10000 {
        If (GetKeyState("Enter") || GetKeyState("Lbutton") || GetKeyState("Esc"))
            break
        sleep, 1
    }

    LbuttonEnabled := True
    StopRecursion  := False
    SetTimer, mouseTrack, On
    SetTimer, keyTrack,   On
Return
#If

$~Space::
    GoSub, Marktime_Hoty_FixSlash
    lastHotkeyTyped := "~Space"
Return

; duplicate hotkey in case shift is accidentally  held as a result of attempting to type a '?'
$~+Space::
    GoSub, Marktime_Hoty_FixSlash
    lastHotkeyTyped := "~Space"
Return

$~^Backspace::
    Hotstring("Reset")
Return

$~Backspace::
    TimeOfLastHotkeyTyped := A_TickCount
    lastHotkeyTyped := "~Backspace"
Return

$~Left::
    X_PriorPriorHotKey :=
Return

$~Right::
    X_PriorPriorHotKey :=
Return

; Ctl+Tab in chrome to goto recent
prevChromeTab()
{
    global StopRecursion
    StopRecursion := True
    DetectHiddenWindows, Off
    Send, ^+{a}
    loop 100
    {
        WinGet, allChromeWindows, List, ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe
        loop % allChromeWindows
        {
            this_id := allChromeWindows%A_Index%
            WinGetTitle, titID, ahk_id %this_id%
            If (titID == "")
                break
        }
        If (titID == "")
            break
        sleep, 20
        If (A_Index == 99) {
            StopRecursion := False
            Return
        }
    }
    sleep, 250
    WinActivate, ahk_id %this_id%
    ; ControlFocus, Chrome_RenderWidgetHostHWND1, ahk_id %this_id%
    Send, {Enter}
    sleep, 150
    If WinExist("ahk_id " . this_id) && WinActive("ahk_id " . this_id)
        Send, {tab}{tab}{Enter}
    tooltip, switched!
    sleep, 1000
    tooltip,
    StopRecursion := False
}

#If WinActive("ahk_exe Chrome.exe")
    ^Tab::
        prevChromeTab()
    Return
#If

#If !SearchingWindows && !hitTAB
; Defining Esc & x:: turns Esc into a prefix key. While a prefix is held, AHK delays (or suppresses) the Esc down hotkey until it
; knows whether a combo (with x) is coming. That’s why your 2nd press + hold never reaches your $Esc routine, so GoSub, DrawRect never runs.
$Esc::
    StopRecursion := True
    SetTimer, EscTimer, Off
    SetTimer, keyTrack,   Off
    SetTimer, mouseTrack, Off
    executedOnce   := False
    escHwndID := FindTopMostWindow()
    WinGetTitle, escTitle, ahk_id %escHwndID%

    If (A_PriorHotKey == A_ThisHotKey && A_TimeSincePriorHotkey  < DoubleClickTime && escHwndID == escHwndID_old && escTitle == escTitle_old) {

        DetectHiddenWindows, Off

        If IsAltTabWindow(escHwndID) {
            WinActivate, ahk_id %escHwndID%
            WinGet, pp, ProcessPath , ahk_id %escHwndID%
            Hotkey, x, DoNothing, On
            ; GoSub, DrawRect
            DrawMasks(escHwndID)
            DrawWindowTitlePopup("Close?", pp, False, escHwndID)

            loop {
                ; tooltip Close `"%escTitle%`" ? ;"
                sleep, 1
                If !GetKeyState("Esc","P")
                    break
                If GetKeyState("x","P") {
                    Tooltip, Canceled!
                    ; ClearRect()
                    ClearMasks("", Opacity)
                    GoSub, FadeOutWindowTitle
                    CancelClose := True
                    sleep, 1500
                    Tooltip,
                    StopRecursion := False
                    SetTimer, keyTrack,   On
                    SetTimer, mouseTrack, On
                }
            }
            Hotkey, x, DoNothing, Off
            If !CancelClose {
                Winclose, ahk_id %escHwndID%

                loop 10 {
                    ; tooltip, Waiting for `"%escTitle%`" to close... ; "
                    If !WinExist("ahk_id " . escHwndID) {
                        ; ClearRect(escHwndID)
                        ClearMasks(escHwndID, Opacity)
                        GoSub, FadeOutWindowTitle
                        ActivateTopMostWindow()
                        break
                    }
                    sleep, 100

                    WinGetClass, actClass, A

                    If ((WinActive("ahk_class #32770") || InStr(actClass, "dialog", False)) && !executedOnce) {
                        WinGet, dialog_hwndID, ID, A
                        executedOnce := True
                        WinSet, AlwaysOnTop, On, ahk_class #32770
                        SendCtrlAdd(escHwndID)
                        WinWaitClose, ahk_id %dialog_hwndID%
                        break
                    }
                }
                If !executedOnce && WinExist("ahk_id " . escHwndID) {
                    WinGet, kill_pid, PID, ahk_id %escHwndID%
                    Process, Close, %kill_pid%
                }

                If (WinExist("ahk_id " . escHwndID) && !executedOnce) {
                    WinKill , ahk_id %escHwndID%
                    loop 50 {
                        If !WinExist("ahk_id " . escHwndID) {
                            ; ClearRect(escHwndID)
                            ClearMasks(escHwndID, Opacity)
                            GoSub, FadeOutWindowTitle
                            ActivateTopMostWindow()
                            break
                        }
                        sleep 125
                        WinKill , ahk_id %escHwndID%
                    }
                }
            }
            Else
                CancelClose := False
        }
        tooltip
        StopRecursion := False
        SetTimer, keyTrack,   On
        SetTimer, mouseTrack, On
        Return
    }

    delayValue := -1*(DoubleClickTime/2)
    SetTimer, EscTimer, %delayValue%
    escTitle_old  := escTitle
    escHwndID_old := escHwndID
    StopRecursion := False
    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On
Return

#If

EscTimer:
    tooltip, escaped!
    Send, {Esc}
Return

;https://superuser.com/questions/950452/how-to-quickly-move-current-window-to-another-task-view-desktop-in-windows-10
; #MaxThreadsPerHotkey 1
; #MaxThreadsBuffer On

!0::
    DetectHiddenWindows, On
    wndIdOnDesk := getForemostWindowIdOnDesktop(2)
    WinGetClass, cl, ahk_id %wndIdOnDesk%
    total := GetDesktopCount()
    tooltip, class is %cl% of %total% desktops
    DetectHiddenWindows, Off
    FixModifiers()
Return

!1::
    StopRecursion := True
    SetTimer, keyTrack,   Off
    SetTimer, mouseTrack, Off
    GoSub, SwitchToVD1
    StopRecursion := False
    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On
    FixModifiers()
Return

SwitchToVD1:
    CurrentDesktop := GetCurrentDesktopNumber() + 1
    testDesktop := CurrentDesktop
    while (CurrentDesktop < 1) {
        Send #^{Right}
        while (CurrentDesktop == testDesktop) {
            sleep, 100
            testDesktop := GetCurrentDesktopNumber() + 1
        }
        CurrentDesktop := GetCurrentDesktopNumber() + 1
    }
    while (CurrentDesktop > 1) {
        Send #^{Left}
        while (CurrentDesktop == testDesktop) {
            sleep, 100
            testDesktop := GetCurrentDesktopNumber() + 1
        }
        CurrentDesktop := GetCurrentDesktopNumber() + 1
    }
Return

!2::
    StopRecursion := True
    SetTimer, keyTrack,   Off
    SetTimer, mouseTrack, Off
    GoSub, SwitchToVD2
    StopRecursion := False
    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On
    FixModifiers()
Return

SwitchToVD2:
    If  (GetDesktopCount() >= 2) {
        CurrentDesktop := GetCurrentDesktopNumber() + 1
        testDesktop := CurrentDesktop
        while (CurrentDesktop < 2) {
            Send #^{Right}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
        while (CurrentDesktop > 2) {
            Send #^{Left}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
    }
Return

!3::
    StopRecursion := True
    SetTimer, keyTrack,   Off
    SetTimer, mouseTrack, Off
    GoSub, SwitchToVD3
    StopRecursion := False
    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On
    FixModifiers()
Return

SwitchToVD3:
    If  (GetDesktopCount() >= 3) {
        CurrentDesktop := GetCurrentDesktopNumber() + 1
        testDesktop := CurrentDesktop
        while (CurrentDesktop < 3) {
            Send #^{Right}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
        while (CurrentDesktop > 3) {
            Send #^{Left}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
    }
Return

!4::
    StopRecursion := True
    SetTimer, keyTrack,   Off
    SetTimer, mouseTrack, Off
    GoSub, SwitchToVD4
    StopRecursion := False
    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On
    FixModifiers()
Return

SwitchToVD4:
    If  (GetDesktopCount() >= 4) {
        CurrentDesktop := GetCurrentDesktopNumber() + 1
        testDesktop := CurrentDesktop
        while (CurrentDesktop < 4) {
            Send #^{Right}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
        while (CurrentDesktop > 4) {
            Send #^{Left}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
    }
Return

; #MaxThreadsBuffer Off
;https://superuser.com/questions/1261225/prevent-alttab-from-switching-to-minimized-windows
Altup:
    global cycling, cycleCount, ValidWindows, GroupedWindows, startHighlight, hitTAB, hitTilde, LclickSelected, blockKeys

    Critical, On
    cycling        := False
    hitTAB         := False
    hitTilde       := False

    WinGet, actWndID, ID, A
    If (LclickSelected && (GroupedWindows.length() > 2) && actWndID != ValidWindows[1]) {
        If (startHighlight) {
            blockKeys := True
            GoSub, SortAllWins
            blockKeys := False
        }
    }
    Else {
        If (GetKeyState("x","P") || actWndID == ValidWindows[1] || GroupedWindows.length() <= 1) {
            ; canceled!
            If (GetKeyState("x","P")) {
                blockKeys := True
                GoSub, ResetWins
                blockKeys := False
            }
        } ; this condition is attempting to account for the user starting with alt+tab then switching to alt+`
        Else If (startHighlight && (GroupedWindows.length() > 2)  && actWndID != ValidWindows[1]) {
            blockKeys := True
            GoSub, SortGroupedWins ; currently, GroupedWindows == ValidWindows for alt+tab but not for alt+`
            blockKeys := False
        }
    }

    cycleCount     := 1
    ValidWindows   := []
    GroupedWindows := []
    startHighlight := False
    LclickSelected := False
    Critical, Off
    SetTimer, mouseTrack, On
    SetTimer, keyTrack,   On
Return

;============================================================================================================================
SortAllWins:
    Critical, On

    WinSet, AlwaysOnTop, Off, ahk_id %_winIdD%
    WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%

    WinSet, AlwaysOnTop, On, ahk_id %_winIdD%
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%

    ; If (_winIdD != ValidWindows[1] && ValidWindows.MaxIndex() >= 1)
        ; WinSet, Transparent, 0, % "ahk_id " ValidWindows[1]
    ; If (_winIdD != ValidWindows[2] && ValidWindows.MaxIndex() >= 2)
        ; WinSet, Transparent, 0, % "ahk_id " ValidWindows[2]
    ; If (_winIdD != ValidWindows[3] && ValidWindows.MaxIndex() >= 3)
        ; WinSet, Transparent, 0, % "ahk_id " ValidWindows[3]
    ; If (_winIdD != ValidWindows[4] && ValidWindows.MaxIndex() >= 4)
        ; WinSet, Transparent, 0, % "ahk_id " ValidWindows[4]

    If (_winIdD != ValidWindows[4] && ValidWindows.MaxIndex() >= 4) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[4]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[4]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }
    If (_winIdD != ValidWindows[3] && ValidWindows.MaxIndex() >= 3) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[3]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[3]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }
    If (_winIdD != ValidWindows[2] && ValidWindows.MaxIndex() >= 2) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[2]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[2]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }
    If (_winIdD != ValidWindows[1] && ValidWindows.MaxIndex() >= 1) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[1]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[1]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }

    WinSet, AlwaysOnTop, On, ahk_id %_winIdD%
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    WinActivate, % "ahk_id " _winIdD

    ; If (ValidWindows.MaxIndex() >= 1 && _winIdD != ValidWindows[1]) {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[1]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[1]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[1]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[1]
    ; }
    ; If (ValidWindows.MaxIndex() >= 2 && _winIdD != ValidWindows[2]) {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[2]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[2]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[2]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[2]
    ; }
    ; If (ValidWindows.MaxIndex() >= 3 && _winIdD != ValidWindows[3]) {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[3]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[3]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[3]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[3]
    ; }
    ; If (ValidWindows.MaxIndex() >= 4 && _winIdD != ValidWindows[4]) {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[4]
    ; }

    WinSet, AlwaysOnTop, Off , % "ahk_id " _winIdD
    Critical, Off
Return

SortGroupedWins:
    Critical, On
    WinSet, AlwaysOnTop, Off ,% "ahk_id " GroupedWindows[cycleCount]
    WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%

    WinSet, AlwaysOnTop, On ,% "ahk_id " GroupedWindows[cycleCount]
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%

    If (ValidWindows.MaxIndex() >= 4 && GroupedWindows[cycleCount] != ValidWindows[4]) {
        ; WinSet, Transparent, 0, % "ahk_id " ValidWindows[4]
        WinActivate, % "ahk_id " ValidWindows[4]
    }
    If (ValidWindows.MaxIndex() >= 3 && GroupedWindows[cycleCount] != ValidWindows[3]) {
        ; WinSet, Transparent, 0, % "ahk_id " ValidWindows[3]
        WinActivate, % "ahk_id " ValidWindows[3]
    }
    If (ValidWindows.MaxIndex() >= 2 && GroupedWindows[cycleCount] != ValidWindows[2]) {
        ; WinSet, Transparent, 0, % "ahk_id " ValidWindows[2]
        WinActivate, % "ahk_id " ValidWindows[2]
    }
    If (ValidWindows.MaxIndex() >= 1 && GroupedWindows[cycleCount] != ValidWindows[1]) {
        ; WinSet, Transparent, 0, % "ahk_id " ValidWindows[1]
        WinActivate, % "ahk_id " ValidWindows[1]
    }

    WinSet, AlwaysOnTop, On ,% "ahk_id " GroupedWindows[cycleCount]
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    WinActivate, % "ahk_id " GroupedWindows[cycleCount]

    ; If (ValidWindows.MaxIndex() >= 1 && GroupedWindows[cycleCount] != ValidWindows[1])
    ; {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[1]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[1]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[1]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[1]
    ; }
    ; If (ValidWindows.MaxIndex() >= 2 && GroupedWindows[cycleCount] != ValidWindows[2])
    ; {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[2]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[2]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[2]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[2]
    ; }
    ; If (ValidWindows.MaxIndex() >= 3 && GroupedWindows[cycleCount] != ValidWindows[3])
    ; {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[3]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[3]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[3]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[3]
    ; }
    ; If (ValidWindows.MaxIndex() >= 4 && GroupedWindows[cycleCount] != ValidWindows[4])
    ; {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[4]
    ; }

    WinSet, AlwaysOnTop, Off ,% "ahk_id " GroupedWindows[cycleCount]
    Critical, Off
Return

ResetWins:
    If (ValidWindows.MaxIndex() >= 4)
        WinActivate, % "ahk_id " ValidWindows[4]
    If (ValidWindows.MaxIndex() >= 3)
        WinActivate, % "ahk_id " ValidWindows[3]
    If (ValidWindows.MaxIndex() >= 2)
        WinActivate, % "ahk_id " ValidWindows[2]
    If (ValidWindows.MaxIndex() >= 1)
        WinActivate, % "ahk_id " ValidWindows[1]
Return

$!Tab::
$!+Tab::
If !hitTAB {
    firstDraw := True
    textBoxSelected := False
    StopRecursion  := True
    SetTimer, mouseTrack, Off
    SetTimer, keyTrack,   Off
    hitTAB := True
    cc := Cycle()

    If (cc > 2) {
        WinSet, Transparent, 255, ahk_id %black1Hwnd%
        WinSet, Transparent, 255, ahk_id %black2Hwnd%
        WinSet, Transparent, 255, ahk_id %black3Hwnd%
        WinSet, Transparent, 255, ahk_id %black4Hwnd%
    }
    GoSub, Altup
    ClearMasks()

    SetTimer, mouseTrack, On
    SetTimer, keyTrack,   On
    StopRecursion := False
}
FixModifiers()
Return

!`::
    ; tooltip, swapping between windows of app
    StopRecursion  := True
    SetTimer, mouseTrack, Off
    SetTimer, keyTrack,   Off

    ActivateTopMostWindow()

    DetectHiddenWindows, Off
    WinGet, activeProcessName, ProcessName, A
    WinGetClass, activeClassName, A

    WinGet, allWindows, List
    loop % allWindows
    {
        hwndID := allWindows%A_Index%

        If (MonCount > 1) {
            currentMon := MWAGetMonitorMouseIsIn()
            currentMonHasActWin := IsWindowOnMonNum(hwndID, currentMon)
        }
        Else {
            currentMonHasActWin := True
        }

        If (currentMonHasActWin) {
            If (IsAltTabWindow(hwndID)) {
                WinGet, state, MinMax, ahk_id %hwndID%
                If (state > -1) {
                    ValidWindows.push(hwndID)
                }
            }
        }
    }

    tempWinActID := HandleWindowsWithSameProcessAndClass(activeProcessName, activeClassName)

    If !LclickSelected
        lastActWinID := tempWinActID
    Else
        LclickSelected := False

    WinSet, AlwaysOnTop, On, ahk_id %lastActWinID%

    ; cycleCount is global here because above we return tempWinActID whereas cycle() returns the cycleCount itself
    If (cycleCount > 2) {
        WinSet, Transparent, 255, ahk_id %black1Hwnd%
        WinSet, Transparent, 255, ahk_id %black2Hwnd%
        WinSet, Transparent, 255, ahk_id %black3Hwnd%
        WinSet, Transparent, 255, ahk_id %black4Hwnd%
        GoSub, SortGroupedWins
    }
    ClearMasks()

    WinSet, AlwaysOnTop, Off, ahk_id %lastActWinID%
    WinActivate, ahk_id %lastActWinID%

    ValidWindows   := []
    GroupedWindows := []

    SetTimer, mouseTrack, On
    SetTimer, keyTrack,   On
    StopRecursion := False
Return

#If hitTAB
$!x::
    tooltip, Canceled Operation!
    Gui, GUI4Boarder: Hide
    Gui, WindowTitle: Destroy
    GoSub, ResetWins
    sleep, 1000
    tooltip,
    FixModifiers()
Return
#If

$!Lbutton::
    If (hitTab || hitTilde) {
        LclickSelected := True
        Gui, WindowTitle: Destroy
        ClearMasks()
        MouseGetPos, , , _winIdD,
        WinActivate, ahk_id %_winIdD%
        WinGetTitle, actTitle, ahk_id %_winIdD%
        WinGet, pp, ProcessPath , ahk_id %_winIdD%

        lastActWinID := _winIdD

        DrawMasks(_winIdD)
        DrawWindowTitlePopup(actTitle, pp)

        KeyWait, LAlt, U T5

        GoSub, FadeOutWindowTitle
        GoSub, Altup
        ClearMasks()
    }
    Else If (A_PriorHotkey == A_ThisHotkey && (A_TimeSincePriorHotkey < 550)) {
        Send, {Click, left}
        Send, {ENTER}
        sleep, 275
    }
Return

RunDynaExpr:
    DynaRun(Expr, Expr_Name)
Return

RunDynaAltUp:
    DynaRun(ExprAltUp, ExprAltUp_Name)
Return

RunDynaExprTimeout:
    DynaRun(TooltipExpr, ExprTimeout_Name)
Return

RunDynaExprCenter:
    DynaRun(CenterExpr, CenterTimeout_Name)
Return

FadeOutWindowTitle:
    global WindowTitleID

    delayTime := 80

    WinSet, Transparent, 200, ahk_id %WindowTitleID%
    sleep, %delayTime%
    WinSet, Transparent, 175, ahk_id %WindowTitleID%
    sleep, %delayTime%,
    WinSet, Transparent, 150, ahk_id %WindowTitleID%
    sleep, %delayTime%,
    WinSet, Transparent, 125, ahk_id %WindowTitleID%
    sleep, %delayTime%,
    WinSet, Transparent, 100, ahk_id %WindowTitleID%
    sleep, %delayTime%,
    WinSet, Transparent, 75,  ahk_id %WindowTitleID%
    sleep, %delayTime%,
    WinSet, Transparent, 50,  ahk_id %WindowTitleID%
    sleep, %delayTime%
    WinSet, Transparent, 25,  ahk_id %WindowTitleID%
    sleep, %delayTime%
    Gui, WindowTitle: Destroy
Return

Cycle()
{
    global cycling, ValidWindows, GroupedWindows, MonCount, startHighlight, LclickSelected, firstDraw

    prev_exe   :=
    prev_cl    :=
    cycleCount := 1

    If !cycling
    {
        DetectHiddenWindows, Off
        failedSwitch := False

        WinGet, actId, ID, A
        WinGet, allWindows, List

        loop % allWindows
        {
            Critical On
            hwndID := allWindows%A_Index%

            If (MonCount > 1) {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := IsWindowOnMonNum(hwndID, currentMon)
            }
            Else {
                currentMonHasActWin := True
            }

            If (currentMonHasActWin) {
                If (IsAltTabWindow(hwndID)) {
                    WinGet, state, MinMax, ahk_id %hwndID%
                    ; WinGet, exe, ProcessName, ahk_id %hwndID%
                    ; WinGetClass, cl, ahk_id %hwndID%
                    If (state > -1) {
                        ValidWindows.push(hwndID)
                        ; If (prev_cl != cl || prev_exe != exe) {
                        GroupedWindows.push(hwndID)

                        If (GroupedWindows.MaxIndex() == 2) {
                            WinActivate, % "ahk_id " hwndID
                            cycleCount := 2
                            If (hwndID == actId) {
                                failedSwitch := True
                            }
                            Else {
                                Critical, Off
                                ; GoSub, DrawRect
                                DrawMasks(hwndID)
                                If !GetKeyState("LAlt","P") || GetKeyState("q","P") {
                                    GroupedWindows := []
                                    ValidWindows   := []
                                    Critical, Off
                                    Return 0
                                }
                            }
                        }
                        If (GroupedWindows.MaxIndex() == 3 && failedSwitch) {
                            WinActivate, % "ahk_id " hwndID
                            cycleCount := 3
                            Critical, Off
                            ; GoSub, DrawRect
                            DrawMasks(hwndID)
                        }
                        If ((GroupedWindows.MaxIndex() > 3) && (!GetKeyState("LAlt","P") || GetKeyState("q","P"))) {
                            GroupedWindows := []
                            ValidWindows   := []
                            Critical, Off
                            Return 0
                        }
                        ; }
                        ; prev_exe := exe
                        ; prev_cl  := cl
                    }
                }
            }
        }
        Critical, Off
    }

    If (GroupedWindows.length() == 1) {
        tooltip, % "Only " GroupedWindows.length() " Window to Show..."
        sleep, 1000
        tooltip,
        Return 1
    }

    KeyWait, Tab, U
    cycling := True

    If cycling {
        loop
        {
            If (GroupedWindows.length() >= 2 && cycling)
            {
                KeyWait, Tab, D T0.1
                If !ErrorLevel
                {
                    If !GetKeyState("LShift","P") {
                        If (cycleCount == GroupedWindows.MaxIndex())
                            cycleCount := 1
                        Else
                            cycleCount += 1
                    }
                    Else If GetKeyState("LShift","P") {
                        If (cycleCount == 1)
                            cycleCount := GroupedWindows.MaxIndex()
                        Else
                            cycleCount -= 1
                    }

                    ; WinSet, AlwaysOnTop, On, ahk_class tooltips_class32
                    WinActivate, % "ahk_id " GroupedWindows[cycleCount]
                    WinWaitActive, % "ahk_id " GroupedWindows[cycleCount], , 2
                    gwHwnd := GroupedWindows[cycleCount]
                    ; GoSub, DrawRect
                    DrawMasks(gwHwnd, False)
                    WinGetTitle, tits, % "ahk_id " GroupedWindows[cycleCount]
                    WinGet, pp, ProcessPath , % "ahk_id " GroupedWindows[cycleCount]

                    DrawWindowTitlePopup(tits, pp)
                    KeyWait, Tab, U

                    If (cycleCount > 2)
                        startHighlight := True
                }
            }
        } until (!GetKeyState("LAlt", "P") || GetKeyState("q","P"))
        If !LclickSelected {
            GoSub, FadeOutWindowTitle
        }
    }
    Return cycleCount
}

ClearRect(hwnd := "") {
    global DrawingRect, Highlighter, GUI4Boarder

    If DrawingRect {
        Critical, On
        loop 5 {
            DrawingRect := False
            If (GetKeyState("LAlt", "P") || GetKeyState("LButton", "P")) {
                Critical, Off
                Gui, GUI4Boarder: Hide
                WinSet, Transparent, 255, ahk_id %Highlighter%
                WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
                Return
            }
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
            sleep, 5
        }

        decrement_amount := 15
        loop % floor(255/decrement_amount)
        {
            current_trans := 255-(decrement_amount * A_Index)
            WinSet, Transparent, %current_trans%, ahk_id %Highlighter%
            If (GetKeyState("LAlt", "P") || GetKeyState("LButton", "P")) {
                Critical, Off
                Gui, GUI4Boarder: Hide
                WinSet, Transparent, 255, ahk_id %Highlighter%
                WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
                Return
            }
            If (hwnd != "" && !WinExist("ahk_id " . hwnd)) {
                Critical, Off
                Gui, GUI4Boarder: Hide
                WinSet, Transparent, 255, ahk_id %Highlighter%
                WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
                Return
            }
            WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
            sleep 5
        }
        Gui, GUI4Boarder: Hide
        Critical, Off
    }
Return
}

; https://www.autohotkey.com/boards/viewtopic.php?t=110505
DrawRect:
    Gui, GUI4Boarder: Hide
    DrawingRect := True
    WinGet, activeWin, ID, A
    x := y := w := h := 0
    WinGetPosEx(activeWin, x, y, w, h)

    If (x="")
        Return

    borderType:="inside"                ; set to inside, outside, or both

    If (borderType="outside") {
        outerX:=0
        outerY:=0
        outerX2:=w+2*border_thickness
        outerY2:=h+2*border_thickness

        innerX:=border_thickness
        innerY:=border_thickness
        innerX2:=border_thickness+w
        innerY2:=border_thickness+h

        newX:=x-border_thickness
        newY:=y-border_thickness
        newW:=w+2*border_thickness
        newH:=h+2*border_thickness

    } Else If (borderType="inside") {
        ; WinGet, myState, MinMax, A
        ; If (myState == 1)
            ; offset:=8
        ; Else
            offset:=0

        outerX:=offset
        outerY:=offset
        outerX2:=w-offset
        outerY2:=h-offset

        innerX:=border_thickness+offset
        innerY:=border_thickness+offset
        innerX2:=w-border_thickness-offset
        innerY2:=h-border_thickness-offset

        newX:=x
        newY:=y
        newW:=w
        newH:=h

    } Else If (borderType="both") {
        outerX:=0
        outerY:=0
        outerX2:=w+2*border_thickness
        outerY2:=h+2*border_thickness

        innerX:=border_thickness*2
        innerY:=border_thickness*2
        innerX2:=w
        innerY2:=h

        newX:=x-border_thickness
        newY:=y-border_thickness
        newW:=w+4*border_thickness
        newH:=h+4*border_thickness
    }
    Critical, On
    Gui,GUI4Boarder: Show, w%newW% h%newH% x%newX% y%newY% NA, Table awaiting Action
    WinSet, Region, %outerX%-%outerY%  %outerX2%-%outerY%  %outerX2%-%outerY2%  %outerX%-%outerY2%  %outerX%-%outerY%  %innerX%-%innerY%  %innerX2%-%innerY%  %innerX2%-%innerY2%  %innerX%-%innerY2%  %innerX%-%innerY%, ahk_id %Highlighter%

    WinSet, Transparent, Off, ahk_id %Highlighter%
    WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    WinActivate, ahk_id %activeWin%
    WinWaitActive, ahk_id %activeWin%, , 2
    Critical, Off
Return

; Switch "App" open windows based on the same process and class
HandleWindowsWithSameProcessAndClass(activeProcessName, activeClass) {
    global MonCount, Highlighter, hitTAB, hitTilde, GroupedWindows, cycleCount, LclickSelected

    windowsToMinimize := []
    minimizedWindows  := []
    lastActWinID      := ""
    hitTAB            := False
    hitTilde          := True

    ; SetTimer, UpdateValidWindows, -1
    UpdateValidWindows()

    currentMon := MWAGetMonitorMouseIsIn()
    Critical, On
    cycleCount := 2
    WinGet, windowsListWithSameProcessAndClass, List, ahk_exe %activeProcessName% ahk_class %activeClass%

    loop % windowsListWithSameProcessAndClass
    {
        hwndID := windowsListWithSameProcessAndClass%A_Index%
        WinGetTitle, tit, ahk_id %hwndID%
        WinGet, mmState, MinMax, ahk_id %hwndID%
        If (MonCount > 1 && mmState > -1) {
            currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
        }
        Else If (mmState > -1) {
            currentMonHasActWin := True
        }

        If (currentMonHasActWin && tit != ""  && mmState > -1) {
            GroupedWindows.push(hwndID)
        }
        Else If (mmState == -1) {
            minimizedWindows.push(hwndID)
        }
    }
    ; add minimized windows to the end of the GroupedWindows array so they can be selected too but afterwards
    loop % minimizedWindows.length()
    {
        minHwndID := minimizedWindows[A_Index]
        GroupedWindows.push(minHwndID)
    }

    numWindows := GroupedWindows.length()

    If (numWindows <= 1) {
        loop 100 {
            Tooltip, Only %numWindows% Window(s) found!
            sleep, 10
        }
        Tooltip,
        Return
    }

    ; WinActivate, % "ahk_id " GroupedWindows[1]
    WinGet, mmState, MinMax, % "ahk_id " GroupedWindows[cycleCount]
    If (MonCount > 1 && mmState == -1) {
        windowsToMinimize.push(GroupedWindows[cycleCount])
        lastActWinID := GroupedWindows[cycleCount]
    }
    WinActivate, % "ahk_id " GroupedWindows[cycleCount]
    WinGetTitle, actTitle, % "ahk_id " GroupedWindows[cycleCount]
    WinGet, pp, ProcessPath , % "ahk_id " GroupedWindows[cycleCount]

    Critical, Off

    gwHwndId := GroupedWindows[cycleCount]
    DrawMasks(gwHwndId)
    DrawWindowTitlePopup(actTitle, pp, True)

    KeyWait, ``, U T1

    cycleCount++
    If (cycleCount > numWindows) {
        cycleCount := 1
    }
    gwHwndId := GroupedWindows[cycleCount]
    ; tooltip, num of windows is %numWindows%
    loop
    {
        If LclickSelected
            break

        KeyWait, ``, D T0.1
        If !ErrorLevel
        {
            WinGet, mmState, MinMax, ahk_id %gwHwndId%
            If (MonCount > 1 && mmState == -1) {
                windowsToMinimize.push(gwHwndId)
            }
            WinActivate, ahk_id %gwHwndId%
            lastActWinID := gwHwndId
            WinGetTitle, actTitle, ahk_id %gwHwndId%
            WinGet, pp, ProcessPath , ahk_id %gwHwndId%

            DrawMasks(gwHwndId, False)
            DrawWindowTitlePopup(actTitle, pp, True)

            KeyWait, ``, U
            If !ErrorLevel
            {
                cycleCount++
                If (cycleCount > numWindows)
                {
                    cycleCount := 1
                }
                loop {
                    gwHwndId := GroupedWindows[cycleCount]
                    If !IsWindowOnMonNum(gwHwndId, currentMon) {
                        cycleCount++
                        If (cycleCount > numWindows)
                        {
                            cycleCount := 1
                        }
                        gwHwndId := GroupedWindows[cycleCount]
                    }
                    Else
                        break
                }
            }
        }
    } until (!GetKeyState("LAlt", "P"))

    GoSub, FadeOutWindowTitle

    loop % windowsToMinimize.length()
    {
        tempId := windowsToMinimize[A_Index]
        If (tempId != lastActWinID) {
            WinMinimize, ahk_id %tempId%
            sleep, 100
        }
        Else {
            If !IsWindowOnMonNum(tempId, currentMon) {
                WinActivate, ahk_id %tempId%
                Send, #+{Left}
            }
        }
    }
    cycleCount := cycleCount - 1
    If (cycleCount <= 0)
        cycleCount := GroupedWindows.MaxIndex()

    Return lastActWinID
}

; ------------------  ChatGPT ------------------------------------------------------------------
ClearMasks(monitorHwnd := "", initTransVal := 255) {
    global black1Hwnd, black2Hwnd, black3Hwnd, black4Hwnd

    iterations := 10
    transVal   := initTransVal
    opacityInterval := Floor(initTransVal / iterations)

    ; fade-out loop (non-critical)
    Loop, %iterations%
    {
        transVal -= opacityInterval
        currentVal := transVal

        WinSet, Transparent, %currentVal%, ahk_id %black1Hwnd%
        WinSet, Transparent, %currentVal%, ahk_id %black2Hwnd%
        WinSet, Transparent, %currentVal%, ahk_id %black3Hwnd%
        WinSet, Transparent, %currentVal%, ahk_id %black4Hwnd%

        ; Short sleep for visual smoothness; not in Critical
        sleep, 3
        If (GetKeyState("LAlt", "P")) {
            Loop, 4
                Gui, %A_Index%: Hide
            Return
        }

        ; Now a tiny critical section to safely check/early-exit
        Critical, On
        If (monitorHwnd != "" && !WinExist("ahk_id " . monitorHwnd)) {
            Loop, 4
                Gui, %A_Index%: Hide
            Critical, Off
            Return
        }
        Critical, Off
    }

    ; Final hide – we do want this to be atomic-ish
    Critical, On
    Loop, 4
        Gui, %A_Index%: Hide
    Critical, Off

    Return
}

DrawBlackBar(guiIndex, x, y, w, h) {
    global hLeft, hTop, hRight, hBottom
    global black1Hwnd, black2Hwnd, black3Hwnd, black4Hwnd

    If (w <= 0 || h <= 0) {
        Gui, %guiIndex%: Hide
        Return
    }

    hwndVarName := "black" . guiIndex . "Hwnd"
    If !WinExist("ahk_id " . hwndVarName) {
        If (guiIndex == 1)
            CreateMaskGui(guiIndex, hTop)
        Else if (guiIndex == 2)
            CreateMaskGui(guiIndex, hLeft)
        Else if (guiIndex == 2)
            CreateMaskGui(guiIndex, hRight)
        Else if (guiIndex == 2)
            CreateMaskGui(guiIndex, hBottom)
    }
    ; Showing with new size/position is one atomic operation internally
    Gui, %guiIndex%: Show, x%x% y%y% w%w% h%h% NoActivate

    ; Make sure they’re on top exactly once per draw
    WinSet, AlwaysOnTop, On, ahk_id %hwndVarName%
    WinSet, Transparent,  1, ahk_id %hwndVarName%
}

; Why this helps flicker:
    ; All geometry & showing of the 4 bars happens back-to-back while uninterruptible:
        ; No Sleep inside Critical.
        ; No other thread can sneak in and change these GUIs mid-update.
    ; The visual fade (the transparent WinSet calls) happens after the bars are in their final positions and already visible. So even If a timer/hotkey interrupts, it doesn’t cause a half-drawn layout—only an intermediate opacity.
DrawMasks(targetHwnd := "", firstDraw := True) {
    global hLeft, hTop, hRight, hBottom, Opacity
    global black1Hwnd, black2Hwnd, black3Hwnd, black4Hwnd

    Margin := 0  ; expands the hole around the active window by this many pixels

    ; Resolve target window
    If !targetHwnd
        WinGet, hA, ID, A
    Else
        hA := targetHwnd

    ; Don’t mask our own mask windows
    If ((!hA) || (hA == hTop || hA == hLeft || hA == hRight || hA == hBottom))
        Return

    ; Get monitor WORK AREA for active window’s monitor
    If (!GetMonitorRectsForWindow(hA, mx, my, mw, mh, wx2, wy2, ww2, wh2))
        Return

    wRight  := wx2 + ww2
    wBottom := wy2 + wh2

    ; Active window rect (expanded)
    WinGetPosEx(hA, wx, wy, ww, wh)
    If (wx = "")
        Return

    wx -= Margin, wy -= Margin, ww += 2*Margin, wh += 2*Margin

    holeL := Max(wx2, wx)
    holeT := Max(wy2, wy)
    holeR := Min(wRight,  wx + ww)
    holeB := Min(wBottom, wy + wh)

    ; --- CRITICAL SECTION: JUST THE GEOMETRY + SHOWS ---
    Critical, On
    ; TOP panel
    DrawBlackBar(1, wx2, wy2, ww2, Max(0, holeT - wy2))
    ; LEFT panel
    DrawBlackBar(2, wx2, holeT, Max(0, holeL - wx2), Max(0, holeB - holeT))
    ; RIGHT panel
    DrawBlackBar(3, holeR, holeT, Max(0, wRight - holeR), Max(0, holeB - holeT))
    ; BOTTOM panel
    DrawBlackBar(4, wx2, holeB, ww2, Max(0, wBottom - holeB))
    Critical, Off
    ; --- END CRITICAL SECTION ---

    ; At this point all 4 bars are in place and visible.
    ; Any animation is now cosmetic and won’t affect “tearing” of geometry.

    ; --- FADE / OPACITY (non-critical) ---
    If (firstDraw) {
        incrValue         := 5
        opacityInterval   := Ceil(Opacity / incrValue)
        transVal          := opacityInterval
    } Else {
        ; For subsequent moves, you can skip animation entirely If you want:
        incrValue         := 1
        opacityInterval   := 0
        transVal          := Opacity
    }

    Loop, %incrValue%
    {
        WinSet, Transparent, %transVal%, ahk_id %black1Hwnd%
        WinSet, Transparent, %transVal%, ahk_id %black2Hwnd%
        WinSet, Transparent, %transVal%, ahk_id %black3Hwnd%
        WinSet, Transparent, %transVal%, ahk_id %black4Hwnd%

        transVal += opacityInterval
        Sleep, 2   ; purely visual – safe outside Critical
        If (!GetKeyState("LAlt", "P")) {
            WinSet, Transparent, %Opacity%, ahk_id %black1Hwnd%
            WinSet, Transparent, %Opacity%, ahk_id %black2Hwnd%
            WinSet, Transparent, %Opacity%, ahk_id %black3Hwnd%
            WinSet, Transparent, %Opacity%, ahk_id %black4Hwnd%
            break
        }
    }
    Return
}

; Finds the monitor + work area rect that contains the center of the given window.
GetMonitorRectsForWindow(hWnd, ByRef monX, ByRef monY, ByRef monW, ByRef monH
                       , ByRef workX, ByRef workY, ByRef workW, ByRef workH) {
    ; WinGetPos, wx, wy, ww, wh, ahk_id %hWnd%
    WinGetPosEx(hWnd, wx, wy, ww, wh)
    if (wx = "")
        return false
    cx := wx + ww//2
    cy := wy + wh//2

    SysGet, MonCount, MonitorCount
    Loop, %MonCount%
    {
        SysGet, Mon,  Monitor,         %A_Index% ; MonLeft/MonTop/MonRight/MonBottom
        SysGet, Work, MonitorWorkArea, %A_Index% ; WorkLeft/WorkTop/WorkRight/WorkBottom
        if (cx >= MonLeft && cx < MonRight && cy >= MonTop && cy < MonBottom) {
            monX := MonLeft, monY := MonTop, monW := MonRight - MonLeft, monH := MonBottom - MonTop
            workX := WorkLeft, workY := WorkTop, workW := WorkRight - WorkLeft, workH := WorkBottom - WorkTop
            return true
        }
    }
    Return false
}

Max(a,b) {
    Return (a > b) ? a : b
}
Min(a,b) {
    Return (a < b) ? a : b
}
; -------------------------------------------------------------------------------------------

#If MouseIsOverTaskbarWidgets()
$~^Lbutton::
    global MonCount
    StopRecursion := True
    SetTimer, mouseTrack, Off
    SetTimer, keyTrack,   Off

    DetectHiddenWindows, Off
    SysGet, MonCount, MonitorCount

    KeyWait, Lbutton, U T3

    sleep, 125
    targetID := FindTopMostWindow()
    WinGetClass, targetClass, ahk_id %targetID%

    If (targetClass != "Windows.UI.Core.CoreWindow" && targetClass != "TaskListThumbnailWnd" && targetClass != "XamlExplorerHostIslandWindow") {
        WinGet, targetProcess, ProcessName, ahk_id %targetID%
        WinGet, windowsFromProc, list, ahk_exe %targetProcess% ahk_class %targetClass%
        loop % windowsFromProc
        {
            hwndID := windowsFromProc%A_Index%
            WinGet, isMin, MinMax, ahk_id %hwndId%
            If (isMin == -1) {
                WinRestore, ahk_id %hwndId%
                If (MonCount > 1) {
                    currentMon := MWAGetMonitorMouseIsIn()
                    currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
                    If !currentMonHasActWin
                        WinMinimize, ahk_id %hwndId%
                }
            }
            Else If (isMin == 0) {
                If (MonCount > 1) {
                    currentMon := MWAGetMonitorMouseIsIn()
                    currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
                    If currentMonHasActWin
                        WinActivate, ahk_id %hwndId%
                }
                Else {
                    WinActivate, ahk_id %hwndId%
                }
            }
        }
        FixModifiers()
    }
    WinActivate, ahk_id %targetID%
    StopRecursion := False
    SetTimer, mouseTrack, On
    SetTimer, keyTrack,   On
Return
#If

#If MouseIsOverTitleBar()
$^LButton::
    global currentMon, previousMon, DoubleClickTime, MonCount
    DetectHiddenWindows, Off
    StopRecursion := True
    SetTimer, mouseTrack, Off

    MouseGetPos, mx1, my1, actID,
    If !((A_TimeSincePriorHotkey < DoubleClickTime) && (A_PriorHotKey == A_ThisHotKey)) {
        Send, {Lbutton DOWN}
        startMon := MWAGetMonitorMouseIsIn()
    }

    KeyWait, Lbutton, U T5

    MouseGetPos, mx2, my2, ,
    If !((A_TimeSincePriorHotkey < DoubleClickTime) && (A_PriorHotKey == A_ThisHotKey))
        Send, {Lbutton UP}

    If (   (A_TimeSincePriorHotkey < DoubleClickTime)
        && (A_PriorHotKey == A_ThisHotKey)
        && (abs(mx2-mx1) < 15 && abs(my2-my1) < 15)) {

        WinSet, AlwaysOnTop, On, ahk_id %actID%
        WinGet, targetProcess, ProcessName, ahk_id %actID%
        WinGetClass, targetClass, ahk_id %actID%
        WinGet, windowsFromProc, list, ahk_exe %targetProcess% ahk_class %targetClass%
        loop % windowsFromProc
        {
            hwndID := windowsFromProc%A_Index%
            WinGet, isMin, MinMax, ahk_id %hwndId%
            If (isMin == 0) {
                If (MonCount > 1) {
                    currentMonHasActWin := IsWindowOnMonNum(hwndId, startMon)
                    If (currentMonHasActWin)
                        WinActivate, ahk_id %hwndId%
                }
                Else {
                    WinActivate, ahk_id %hwndId%
                }
            }
        }
        WinActivate, ahk_id %actID%
        WinSet, AlwaysOnTop, Off, ahk_id %actID%
        WinActivate, ahk_id %actID%
        FixModifiers()
    }

    StopRecursion := False
    SetTimer, mouseTrack, On
Return
#If


#If MouseIsOverTaskbarBlank()
$~Lbutton::
    MouseGetPos, expX1, expY1,
    If (A_PriorHotkey == A_ThisHotkey
        && (A_TimeSincePriorHotkey < DoubleClickTime)
        && (abs(expX1-expX2) < 20 && abs(expY1-expY2) < 20)) {
        run, explorer.exe
        expX2 := 0
        expY2 := 0
        Return
    }

    KeyWait, LButton, U T5
    MouseGetPos, expX2, expY2,
Return
#If

; ----------------------- EXAMPLE USAGE ----------------------------
; clickType := ExplorerHitTestType()
    ; ; --- Handle double-click on BLANK SPACE ---
    ; if (clickType = "blank") {
        ; if (A_PriorHotkey = "~LButton" && A_TimeSincePriorHotkey < 300) {
            ; ; >>> YOUR DOUBLE-CLICK-BLANK ACTION HERE <<<
            ; Tooltip, Double-click on blank space
; ------------------------------------------------------------------
ExplorerHitTestType() {
    /*
        Returns one of:
            "blank"         - blank space in file list
            "item"          - file/folder item
            "columnHeader"  - column header in Details view
            "navTreeItem"   - left navigation tree item
            "breadcrumb"    - breadcrumb / address bar segment (heuristic)
            "other"         - anything else, or not Explorer
    */

    static ROLE_SYSTEM_LIST        := 0x21
    static ROLE_SYSTEM_LISTITEM    := 0x22
    static ROLE_SYSTEM_OUTLINEITEM := 0x24
    static ROLE_SYSTEM_COLUMNHEADER:= 0x19
    static ROLE_SYSTEM_TOOLBAR     := 0x16
    static ROLE_SYSTEM_PUSHBUTTON  := 0x2B
    static ROLE_SYSTEM_LINK        := 0x1E
    static ROLE_SYSTEM_SEPARATOR   := 0x0C

    CoordMode, Mouse, Screen
    MouseGetPos, x, y, winHwnd
    if (!winHwnd)
        return "other"

    WinGetClass, cls, ahk_id %winHwnd%
    if (cls != "CabinetWClass" && cls != "ExplorerWClass" && cls != "#32770")
        return "other"

    ; Get MSAA object under cursor
    acc := Acc_ObjectFromPoint(x, y)
    if !IsObject(acc)
        return "other"

    ; Collect this object + its parents up to a small depth
    objs := []
    roles := []
    cur := acc

    loop, 8 {
        if !IsObject(cur)
            break
        r := Explorer__GetRoleNum(cur)
        objs.Push(cur)
        roles.Push(r)
        try cur := cur.accParent
        catch
        {
            cur := ""
            break
        }
    }

    if (roles.Length() = 0)
        return "other"

    startRole := roles[1]

    hasOutlineItem := False
    hasToolbar     := False

    for i, r in roles {
        if (r = ROLE_SYSTEM_OUTLINEITEM)
            hasOutlineItem := true
        else if (r = ROLE_SYSTEM_TOOLBAR)
            hasToolbar := true
    }

    ; --- Left navigation tree (anywhere within OUTLINEITEM subtree) ---
    if (hasOutlineItem)
        return "navTreeItem"

    ; --- Direct checks on the object under cursor ---
    if (startRole = ROLE_SYSTEM_LIST)
        return "blank"

    if (startRole = ROLE_SYSTEM_LISTITEM)
        return "item"

    if (startRole = ROLE_SYSTEM_COLUMNHEADER)
        return "columnHeader"

    ; --- Breadcrumb / address bar (heuristic) ---
    ; Typically a PUSHBUTTON / LINK / SEPARATOR on a toolbar above the list.
    if (hasToolbar
        && (startRole = ROLE_SYSTEM_PUSHBUTTON
         || startRole = ROLE_SYSTEM_LINK
         || startRole = ROLE_SYSTEM_SEPARATOR))
    {
        return "breadcrumb"
    }

    return "other"
}
; ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Explorer__GetRoleNum(ByRef accObj := "") {
    if (accObj == "")
        accObj := Acc_ObjectFromPoint()

    if !accObj
        return
    ; Safely get numeric MSAA role
    role := ""
    try role := accObj.accRole(0)
    catch
        return 0

    ; Sometimes Acc.ahk may return a string; handle that as a fallback
    if role is Integer
        return role

    ; String fallback, normalized
    r := Trim(role)
    StringLower, r, r

    ; Role Constant             Hex     Meaning
    ; ROLE_SYSTEM_LIST          0x21    The container list
    ; ROLE_SYSTEM_LISTITEM      0x22    A file/folder in Explorer
    ; ROLE_SYSTEM_OUTLINEITEM   0x24    Tree-view style item
    ; ROLE_SYSTEM_COLUMNHEADER  0x19    Column header: Name, Date Modified, Type, etc.
    ; ROLE_SYSTEM_PUSHBUTTON    0x2B    Buttons
    ; ROLE_SYSTEM_LINK          0x1E    Hyperlink-like UI elements
    if (r == "list")
        return 0x21
    if (r == "list item" || r == "listitem")
        return 0x22
    if (r == "outline item" || r == "outlineitem")
        return 0x24
    if (r == "columnheader" || r == "column header")
        return 0x19
    if (r == "toolbar")
        return 0x16
    if (r == "push button" || r == "pushbutton")
        return 0x2B
    if (r == "link")
        return 0x1E
    if (r == "separator")
        return 0x0C
    ; In Explorer, distinguishing between:
    ; List (0x21)         ← blank area
    ; ListItem (0x22)     ← real file/folder
    ; ColumnHeader (0x19) ← click on a sort header

    ; Explorer’s modern implementation sometimes reports:
        ; ROLE_SYSTEM_OUTLINE (0x3E) for the whole file-view region
        ; ROLE_SYSTEM_OUTLINEITEM (0x24) for individual files/folders
        ; Instead of using classic LIST (0x21) / LISTITEM (0x22)
    ; This happens frequently in:
        ; Windows 11’s XAML Explorer
        ; WebView-backed folder views
        ; File dialogs using UIA → MSAA proxying
    return 0
}
; ------------------------------------------------------------------
; 1. Gets the window + control under the cursor (MouseGetPos → ctrlNN → ControlGet Hwnd).
; 2. Converts screen coords to that control’s client coords (ScreenToClient).
; 3. Gets the accessibility root for that control (Acc_ObjectFromWindow(hCtl)).
; 4. Calls accHitTest(cx, cy) and then:
; a) If it gets an object: optionally walks up parents up to maxHops looking for ROLE_SYSTEM_OUTLINE.
; b) If it gets a child-id: checks accRoot.accRole(childId).
; This is basically “restrict the search to a known hwnd, then do a precise hit-test”.
IsExplorerHeaderClick_Local() {
    static ROLE_SYSTEM_OUTLINE := 0x3E
    static maxHops := 6

    CoordMode, Mouse, Screen
    MouseGetPos, mx, my, winHwnd, ctrlNN
    if (!winHwnd)
        return false

    WinGetClass, cls, ahk_id %winHwnd%
    if (cls != "CabinetWClass" && cls != "ExplorerWClass" && cls != "#32770")
        return false

    ControlGet, hCtl, Hwnd,, %ctrlNN%, ahk_id %winHwnd%
    if (!hCtl)
        return false

    VarSetCapacity(pt, 8, 0)
    NumPut(mx, pt, 0, "Int"), NumPut(my, pt, 4, "Int")
    if !DllCall("ScreenToClient", "ptr", hCtl, "ptr", &pt)
        return false
    cx := NumGet(pt, 0, "Int"), cy := NumGet(pt, 4, "Int")

    accRoot := Acc_ObjectFromWindow(hCtl)
    if !IsObject(accRoot)
        return false

    hit := accRoot.accHitTest(cx, cy)

    if (IsObject(hit)) {
        acc := hit
        Loop, %maxHops% {
            try
                role := acc.accRole(0)
            catch
                break
            if (role == ROLE_SYSTEM_OUTLINE)
                return true
            try
                acc := acc.accParent
            catch
                break
            if !IsObject(acc)
                break
        }
        return false
    } else if (hit != "") {
        ; child-id path (no parent-walk unless you resolve to an object)
        childId := hit
        try role := accRoot.accRole(childId)
        catch
            return false
        return (role == ROLE_SYSTEM_OUTLINE)
    }

    return false
}
; 1. Gets screen coords.
; 2. Calls Acc_ObjectFromPoint(idChild, mx, my) (wrapper over AccessibleObjectFromPoint).
; 3. Checks acc.accRole(0) only.
; AccessibleObjectFromPoint returns the accessible object “displayed at a specified point on the screen” and the point must be in physical screen coordinates.
; Also, it can return the parent object plus a child-id for the element at the point.
IsExplorerHeaderClick() {
    static ROLE_SYSTEM_OUTLINE := 0x3E
    static lastWin := 0, lastCls := ""

    CoordMode, Mouse, Screen
    MouseGetPos, mx, my, winHwnd, ctrlNN
    if (!winHwnd)
        return False

    if (winHwnd != lastWin) {
        WinGetClass, cls, ahk_id %winHwnd%
        lastWin := winHwnd
        lastCls := cls
    } else {
        cls := lastCls
    }

    if (cls != "CabinetWClass" && cls != "ExplorerWClass" && cls != "#32770")
        return False

    ; optional accuracy filter
    ; if !(ctrlNN ~= "i)^DirectUIHWND\d+$")
    ;     return False

    acc := Acc_ObjectFromPoint(idChild, mx, my)  ; <-- key change

    if !IsObject(acc)
        return False

    try
        role := acc.accRole(0)
    catch
        return False

    return (role == ROLE_SYSTEM_OUTLINE)
}
; COMPARISONS:
; Rule of thumb: if you call this on every mouse move, the point-based one will typically feel lighter. If you call it only on click, you probably won’t notice either way.
; Rule of thumb: if your script sometimes can’t trust the control under the cursor, “point-based” is usually the most broadly robust.
; Rule of thumb: if you can reliably identify the correct control hwnd, “local hit-test” is usually the most semantically correct.
; ------------------------------------------------------------------

Dialog_IsDetails_UIA_ByPoint(dlgHwnd := "") {
    ; Requires: #Include UIA_Interface.ahk
    ; Uses ElementFromPoint only (since ElementFromHandle fails for you)

    static UIA_HeaderTypeId := 50034
    static UIA_SplitButtonTypeId := 50031

    global UIA
    if (!IsObject(UIA))
        UIA := UIA_Interface()

    if (!dlgHwnd)
        WinGet, dlgHwnd, ID, A
    if (!dlgHwnd)
        return false

    WinGetPos, wx, wy, ww, wh, ahk_id %dlgHwnd%
    probes := [[70,45],[60,45],[80,45],[70,55],[60,55],[80,55],[75,35],[75,65],[55,50],[85,50]]

    items := ""
    for _, p in probes
    {
        px := wx + (ww * p[1] // 100)
        py := wy + (wh * p[2] // 100)

        el := UIA_SafeElementFromPoint_(px, py)
        if !IsObject(el)
            continue

        items := UIA_WalkUpToUIItemsView_(el)
        if IsObject(items)
            break
    }

    if !IsObject(items)
        return false

    ; Signal #1: Header exists (try multiple APIs)
    if (UIA_FindFirstByControlTypeAny_(items, UIA_HeaderTypeId))
        return true

    ; Signal #2: Grid pattern column count >= 2 (try ID + name)
    cols := UIA_TryGetGridColumnCountAny_(items)
    if (cols >= 2)
        return true

    ; Signal #3: SplitButton named "Name" (typical details header widget)
    if (UIA_FindFirstByControlTypeAndNameAny_(items, UIA_SplitButtonTypeId, "Name"))
        return true

    return false
}

UIA_FindFirstByControlTypeAny_(rootEl, ctlTypeId) {
    ; Returns true if a descendant with ControlType == ctlTypeId exists.
    ; Uses UIA_Interface.ahk (CreatePropertyCondition + FindFirst) with a couple fallbacks.

    global UIA
    static TreeScope_Subtree := 0x4
    static UIA_ControlTypePropertyId := 30003

    if !IsObject(rootEl)
        return false

    cond := ""
    try
        cond := UIA.CreatePropertyCondition(UIA_ControlTypePropertyId, ctlTypeId)
    catch
        cond := ""

    if IsObject(cond)
    {
        found := ""
        try
            found := rootEl.FindFirst(TreeScope_Subtree, cond)
        catch
            found := ""

        if IsObject(found)
            return true
    }

    ; Some forks expose convenience search methods
    found2 := ""
    try
        found2 := rootEl.FindFirstByControlType(ctlTypeId)
    catch
        found2 := ""

    return IsObject(found2)
}

UIA_TryGetGridColumnCountAny_(el) {
    ; Returns GridPattern ColumnCount, or -1 if not available.
    ; Tries both numeric ID and string name variants (fork tolerance).

    static UIA_GridPatternId := 10006

    if !IsObject(el)
    return -1

    pat := ""

    try
        pat := el.GetCurrentPattern(UIA_GridPatternId)
    catch
        pat := ""

    if !IsObject(pat)
    {
        try
            pat := el.GetPattern(UIA_GridPatternId)
        catch
            pat := ""
    }

    if !IsObject(pat)
    {
        try
            pat := el.GetCurrentPattern("Grid")
        catch
            pat := ""
    }

    if !IsObject(pat)
    {
        try
            pat := el.GetPattern("Grid")
        catch
            pat := ""
    }

    if !IsObject(pat)
        return -1

    cols := -1
    try
        cols := pat.CurrentColumnCount
    catch
        cols := -1

    return cols
}

UIA_FindFirstByControlTypeAndNameAny_(rootEl, ctlTypeId, wantName) {
    ; Returns true if a descendant exists with:
        ; ControlType == ctlTypeId AND Name == wantName
    ; Uses UIA_Interface.ahk (CreateAndCondition + FindFirst) with fallbacks.

    global UIA
    static TreeScope_Subtree := 0x4
    static UIA_ControlTypePropertyId := 30003
    static UIA_NamePropertyId := 30005

    if !IsObject(rootEl)
        return false

    condType := ""
    condName := ""
    condAnd := ""

    try
        condType := UIA.CreatePropertyCondition(UIA_ControlTypePropertyId, ctlTypeId)
    catch
        condType := ""

    try
        condName := UIA.CreatePropertyCondition(UIA_NamePropertyId, wantName)
    catch
        condName := ""

    if (IsObject(condType) && IsObject(condName))
    {
        try
            condAnd := UIA.CreateAndCondition(condType, condName)
        catch
            condAnd := ""

        if IsObject(condAnd)
        {
            found := ""
            try
                found := rootEl.FindFirst(TreeScope_Subtree, condAnd)
            catch
                found := ""

            if IsObject(found)
                return true
        }
    }

    ; Convenience fallback: Find by name, then verify control type if possible
    found2 := ""
    try
        found2 := rootEl.FindFirstByName(wantName)
    catch
        found2 := ""

    if !IsObject(found2)
        return false

    t := ""
    try
        t := found2.CurrentControlType
    catch
        t := ""

    return (t = ctlTypeId)
}

UIA_TryGetGridColumnCount_(el, gridPatternId := 10006) {
    ; gridPatternId default = UIA_GridPatternId (10006)
    ; Returns column count, or -1 if GridPattern not available.

    pat := ""
    try
        pat := el.GetCurrentPattern(gridPatternId)
    catch
        pat := ""

    if !IsObject(pat)
        return -1

    cols := -1
    try
        cols := pat.CurrentColumnCount
    catch
        cols := -1

    return cols
}

UIA_WalkUpToUIItemsView_(el) {
    ; Walk up until we hit ClassName UIItemsView OR Name Items View (List)
    static UIA_ListTypeId := 50008

    cur := el
    Loop, 25
    {
        cls := ""
        try
            cls := cur.CurrentClassName
        catch
            cls := ""

        if (cls = "UIItemsView")
            return cur

        name := ""
        ctype := ""

        try
            name := cur.CurrentName
        catch
            name := ""

        try
            ctype := cur.CurrentControlType
        catch
            ctype := ""

        if (ctype = UIA_ListTypeId && name = "Items View")
            return cur

        next := ""
        try
            next := cur.GetParent()
        catch
            next := ""

        if !IsObject(next)
            break

        cur := next
    }

    return ""
}

UIA_SubtreeHasType_(rootEl, scope, propTypeId, ctlTypeId) {
    global UIA
    cond := ""
    try
        cond := UIA.CreatePropertyCondition(propTypeId, ctlTypeId)
    catch
        return false

    found := ""
    try
        found := rootEl.FindFirst(scope, cond)
    catch
        found := ""

    return IsObject(found)
}

UIA_SubtreeHasTypeAndName_(rootEl, scope, propTypeId, propNameId, ctlTypeId, wantName) {
    global UIA

    condType := ""
    condName := ""
    condAnd := ""

    try
        condType := UIA.CreatePropertyCondition(propTypeId, ctlTypeId)
    catch
        return false

    try
        condName := UIA.CreatePropertyCondition(propNameId, wantName)
    catch
        return false

    try
        condAnd := UIA.CreateAndCondition(condType, condName)
    catch
        return false

    found := ""
    try
        found := rootEl.FindFirst(scope, condAnd)
    catch
        found := ""

    return IsObject(found)
}

Dialog_IsDetails_UIA_ByPoint_COM(dlgHwnd := "") {
    static UIA_ControlTypePropertyId := 30003
    static UIA_ClassNamePropertyId := 30012
    static UIA_HeaderTypeId := 50034

    static UIA_GridPatternId := 10006
    static TreeScope_Subtree := 0x4

    if (!dlgHwnd)
        WinGet, dlgHwnd, ID, A
    if (!dlgHwnd)
        return false

    WinGetPos, wx, wy, ww, wh, ahk_id %dlgHwnd%

    probes := [[70,45],[60,45],[80,45],[70,55],[60,55],[80,55],[75,35],[75,65]]

    uia := ComObjCreate("UIAutomationClient.CUIAutomation")
    walker := uia.ControlViewWalker

    items := ""
    for _, p in probes
    {
        px := wx + (ww * p[1] // 100)
        py := wy + (wh * p[2] // 100)

        el := UIA_ComElementFromPoint_(uia, px, py)
        if !IsObject(el)
            continue

        items := UIA_ComWalkUpToClass_(walker, el, "UIItemsView")
        if IsObject(items)
            break
    }

    if !IsObject(items)
        return false

    ; 1) Header exists => Details
    condHeader := uia.CreatePropertyCondition(UIA_ControlTypePropertyId, UIA_HeaderTypeId)
    hdr := ""
    try
        hdr := items.FindFirst(TreeScope_Subtree, condHeader)
    catch
        hdr := ""

    if IsObject(hdr)
        return true

    ; 2) GridPattern column count >= 2 => Details
    pat := ""
    try
        pat := items.GetCurrentPattern(UIA_GridPatternId)
    catch
        pat := ""

    if IsObject(pat)
    {
        cols := -1
        try
            cols := pat.CurrentColumnCount
        catch
            cols := -1

        if (cols >= 2)
            return true
    }

    return false
}

UIA_ComElementFromPoint_(uia, x, y) {
    VarSetCapacity(pt, 8, 0)
    NumPut(x, pt, 0, "Int")
    NumPut(y, pt, 4, "Int")

    el := ""
    try
        el := uia.ElementFromPoint(pt)
    catch
        el := ""
    return el
}

UIA_ComWalkUpToClass_(walker, el, wantClass) {
    cur := el
    Loop, 25
    {
        cls := ""
        try
            cls := cur.CurrentClassName
        catch
            cls := ""

        if (cls = wantClass)
        return cur

        next := ""
        try
            next := walker.GetParentElement(cur)
        catch
            next := ""

        if !IsObject(next)
            break

        cur := next
    }
    return ""
}

IsDetailsView(winHwnd := "") {
    if (!winHwnd)
        WinGet, winHwnd, ID, A
    if (!winHwnd)
        return false

    WinGetClass, cls, ahk_id %winHwnd%

    if (cls = "CabinetWClass" || cls = "ExplorerWClass")
        return IsDetailsView_ExplorerCOM(winHwnd)

    if (cls = "#32770")
        return Dialog_IsDetails_UIA_ByPoint(winHwnd)

    return false
}

IsDetailsView_ExplorerCOM(winHwnd := "") {
    static FVM_DETAILS := 4  ; FOLDERVIEWMODE.FVM_DETAILS

    if (!winHwnd)
        WinGet, winHwnd, ID, A
    if (!winHwnd)
        return false

    shell := ComObjCreate("Shell.Application")
    for oWin in shell.Windows
    {
        h := ""
        try
            h := oWin.Hwnd
        catch
        {
            try
                h := oWin.HWND
            catch
                h := ""
        }

        if (h = winHwnd)
        {
            try
                return (oWin.Document.CurrentViewMode = FVM_DETAILS)
            catch
                return false
        }
    }
    return false
}

UIA_SafeElementFromPoint_(x, y) {
    ; Requires: #Include UIA_Interface.ahk
    ; Returns a UIA element or "" if it fails.

    global UIA

    if (!IsObject(UIA))
        UIA := UIA_Interface()

    el := ""
    try
        el := UIA.ElementFromPoint(x, y, False)
    catch
    {
        ; UIA wrapper can occasionally get into a bad COM state, re-init once
        UIA := ""
        UIA := UIA_Interface()

        try
            el := UIA.ElementFromPoint(x, y, False)
        catch
            el := ""
    }
    return el
}

; ------------------------------------------------------------------
; Returns true if the mouse is over a file/folder item in an Explorer file view
IsExplorerItemClick() {
    static ROLE_SYSTEM_LISTITEM    := 0x22  ; 34
    static ROLE_SYSTEM_OUTLINEITEM := 0x24  ; 36
    static ROLE_SYSTEM_LIST        := 0x21  ; 33
    static ROLE_SYSTEM_OUTLINE     := 0x3E  ; 62

    CoordMode, Mouse, Screen
    MouseGetPos, mx, my, winHwnd
    if (!winHwnd)
        return False

    ; Only standard Explorer windows / file dialogs
    WinGetClass, cls, ahk_id %winHwnd%
    if (cls != "CabinetWClass" && cls != "ExplorerWClass" && cls != "#32770")
        return False

    ; NOTE: depending on your Acc.ahk, you might want Acc_ObjectFromPoint() or Acc_ObjectFromPoint(, mx, my).
    ; If your version expects (x,y) directly, this is fine:
    acc := Acc_ObjectFromPoint(mx, my)
    ; If it expects ByRef child,x,y, the safer call is: acc := Acc_ObjectFromPoint(, mx, my)
    if !IsObject(acc)
        return False

    ; --- step 1: climb to the nearest LISTITEM / OUTLINEITEM ---
    item := ""
    cur  := acc

    Loop 15 {  ; don’t walk forever
        if !IsObject(cur)
            break

        role := ""
        try role := cur.accRole(0)
        catch
            break

        ; normalize numeric-strings like "34"
        if role is number
            role += 0
        else {
            ; string variants from Acc.ahk / proxies
            r := role
            StringLower, r, r
            r := Trim(r)
            if (r = "list item" || r = "listitem")
                role := ROLE_SYSTEM_LISTITEM
            else if (r = "outline item" || r = "outlineitem")
                role := ROLE_SYSTEM_OUTLINEITEM
        }

        if (role = ROLE_SYSTEM_LISTITEM || role = ROLE_SYSTEM_OUTLINEITEM) {
            item := cur
            break
        }

        ; go up one level
        parent := ""
        try parent := cur.accParent
        cur := parent
    }

    if !IsObject(item)
        return False   ; nothing in this chain looks like a file/folder item

    ; --- optional: verify it really belongs to the file view (list/outline) ---
    cur := item
    viewFound := False

    Loop 10 {
        parent := ""
        try parent := cur.accParent
        if !IsObject(parent)
            break

        role := ""
        try role := parent.accRole(0)
        catch
            break

        if role is number
            role += 0
        else {
            r := role
            StringLower, r, r
            r := Trim(r)
            if (r = "list")
                role := ROLE_SYSTEM_LIST
            else if (r = "outline")
                role := ROLE_SYSTEM_OUTLINE
        }

        if (role = ROLE_SYSTEM_LIST || role = ROLE_SYSTEM_OUTLINE) {
            viewFound := true
            break
        }

        cur := parent
    }

    ; If you don’t care about verifying the view, you could just `return true` once item is found.
    return viewFound
}

DebugRolesUnderMouse() {
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    acc := Acc_ObjectFromPoint(mx, my)
    if !IsObject(acc) {
        MsgBox, No acc object
        return
    }

    out := ""
    cur := acc
    Loop 20 {
        if !IsObject(cur)
            break

        role := ""
        try role := cur.accRole(0)
        catch
            break

        out .= "Level " . A_Index . ": " . role . "`n"

        parent := ""
        try parent := cur.accParent
        cur := parent
    }
    MsgBox, %out%
}

IsExplorerBlankSpaceClick() {
    static ROLE_SYSTEM_LIST        := 0x21  ; 33
    static ROLE_SYSTEM_OUTLINE     := 0x3E  ; 62
    static ROLE_SYSTEM_LISTITEM    := 0x22  ; 34
    static ROLE_SYSTEM_OUTLINEITEM := 0x24  ; 36

    CoordMode, Mouse, Screen
    MouseGetPos, x, y, winHwnd
    if (!winHwnd)
        return False

    ; Only Explorer + common dialogs
    WinGetClass, cls, ahk_id %winHwnd%
    if (cls != "CabinetWClass" && cls != "ExplorerWClass" && cls != "#32770")
        return False

    ; MSAA: object under cursor
    ; If your Acc.ahk uses ByRef child,x,y, you may need: acc := Acc_ObjectFromPoint(, x, y)
    acc := Acc_ObjectFromPoint(x, y)
    if !IsObject(acc)
        return False

    ; If you treat header clicks separately, you can short‑circuit here:
    ; (This calls your IsExplorerHeaderClick that checks for ROLE_SYSTEM_OUTLINE)
    if (IsExplorerHeaderClick())
        return False

    ; ------------------------------------------------------------
    ; Step 1: Is this click on an item (file/folder/group header)?
    ; ------------------------------------------------------------
    cur := acc
    Loop 15 {
        if !IsObject(cur)
            break

        role := ""
        try role := cur.accRole(0)
        catch
            break

        ; Normalize numeric role
        if role is number
            role += 0
        else {
            ; Normalize common string variants
            r := role
            StringLower, r, r
            r := Trim(r)
            if (r = "list item" || r = "listitem")
                role := ROLE_SYSTEM_LISTITEM
            else if (r = "outline item" || r = "outlineitem")
                role := ROLE_SYSTEM_OUTLINEITEM
        }

        ; Any LISTITEM / OUTLINEITEM on the way up = item / group header → not blank
        if (role = ROLE_SYSTEM_LISTITEM || role = ROLE_SYSTEM_OUTLINEITEM)
            return False

        parent := ""
        try parent := cur.accParent
        cur := parent
    }

    ; ------------------------------------------------------------
    ; Step 2: Are we inside a LIST / OUTLINE at all?
    ;         If yes → blank space within the view.
    ; ------------------------------------------------------------
    cur := acc
    Loop 15 {
        if !IsObject(cur)
            break

        role := ""
        try role := cur.accRole(0)
        catch
            break

        if role is number
            role += 0
        else {
            r := role
            StringLower, r, r
            r := Trim(r)
            if (r = "list")
                role := ROLE_SYSTEM_LIST
            else if (r = "outline")
                role := ROLE_SYSTEM_OUTLINE
        }

        if (role = ROLE_SYSTEM_LIST || role = ROLE_SYSTEM_OUTLINE) {
            ; We're in the file view, and we already ruled out items above → blank
            return true
        }

        parent := ""
        try parent := cur.accParent
        cur := parent
    }

    ; No list/outline ancestor: not part of the file view
    return False
}


; =========================================
; Smart IsCaretInEdit – AHK v1.1+
;   useUIA  = try UIA (UIA_Interface.ahk) if available
;   useMSAA = try MSAA (Acc.ahk) if available
; =========================================
IsCaretInEdit(useUIA := true, useMSAA := true) {
    WinGet, hWnd, ID, A
    if !hWnd
        return false

    ; ================================
    ; 1) Classic Win32 detection
    ; ================================
    ControlGetFocus, ctrl, ahk_id %hWnd%
    if (ctrl != "") {
        ControlGet, hCtrl, Hwnd,, %ctrl%, ahk_id %hWnd%
        if (hCtrl) {
            WinGetClass, cls, ahk_id %hCtrl%

            ; Classic edit controls
            if (cls = "Edit"
             || cls = "RichEdit20A"
             || cls = "RichEdit20W"
             || cls = "RICHEDIT50W")
                return true
        }
    }

    ; ================================
    ; 2) UIA detection (if enabled)
    ; ================================
    if (useUIA && UIA_IsFocusedEditable())
        return true

    ; ================================
    ; 3) MSAA fallback (if enabled)
    ; ================================
    if (useMSAA && MSAA_IsFocusedEditable())
        return true

    return false
}

UIA_IsFocusedEditable() {
    global UIA

    try {
        if !IsObject(UIA)
            return false    ; or instantiate here if desired

        focus := UIA.GetFocusedElement()
        if !IsObject(focus)
            return false

        ct := focus.CurrentControlType  ; 50004 = Edit

        ; Direct Edit control type -> editable
        if (ct = 50004)
            return true

        ; More generic: if it supports ValuePattern and is not read-only
        vp := ""
        try vp := focus.GetCurrentPatternAs("Value")
        catch
            vp := ""

        if (IsObject(vp)) {
            isRO := ""
            try isRO := vp.CurrentIsReadOnly
            catch
                isRO := ""

            ; If property exists and is false → editable
            if (isRO = false)
                return true

            ; If IsReadOnly missing but ValuePattern exists at all,
            ; we still *suspect* it’s editable.
            if (isRO = "")
                return true
        }
    } catch e {
        return false
    }

    return false
}

MSAA_IsFocusedEditable() {
    ; Needs Acc.ahk (Acc_Role, etc.)
    if !IsFunc("Acc_Role")
        return false

    acc := Acc_Focus()
    if !acc
        return false

    role := ""
    try role := acc.accRole(0)
    catch
        role := ""

    ; Numeric ROLE_SYSTEM_TEXT
    if (role = 42)
        return true

    ; String role via Acc_Role()
    roleStr := ""
    try roleStr := Acc_Role(acc)
    catch
        roleStr := ""

    if (roleStr != "") {
        StringLower, roleLower, roleStr   ; v1-style lowercase
        if (InStr(roleLower, "edit")
         || InStr(roleLower, "editable")
         || InStr(roleLower, "text"))
            return true
    }

    return false
}


GetThreadFocusHwnd(tid)
{
    ; GUITHREADINFO size differs slightly by arch; this works for both.
    size := 48 + (A_PtrSize * 2)
    VarSetCapacity(gui, size, 0)
    NumPut(size, gui, 0, "UInt")

    ok := DllCall("user32\GetGUIThreadInfo", "UInt", tid, "Ptr", &gui, "Int")
    if (!ok)
        return 0

    return NumGet(gui, 12, "Ptr") ; hwndFocus
}

ControlGetFocusEx(tidTarget, hwndTarget, timeoutMs := 15)
{
    if !DllCall("user32\IsWindow", "Ptr", hwndTarget, "Int")
        return false

    hwndFocus := GetThreadFocusHwnd(tidTarget)
    if (hwndFocus && (hwndFocus = hwndTarget || DllCall("user32\IsChild", "Ptr", hwndTarget, "Ptr", hwndFocus, "Int")))
        return true

    if (timeoutMs <= 0)
        return false

    start := A_TickCount
    Loop
    {
        hwndFocus := GetThreadFocusHwnd(tidTarget)
        if (hwndFocus && (hwndFocus = hwndTarget || DllCall("user32\IsChild", "Ptr", hwndTarget, "Ptr", hwndFocus, "Int")))
            return true

        if ((A_TickCount - start) >= timeoutMs)
            break

        Sleep, 0
    }
    return false
}

F8::
    WinGet, hwnd, ID, A

    ok := IsDetailsView(hwnd)

    msg := "Probe: " px "," py
    msg := msg "`nHit Name: " n
    msg := msg "`nHit Class: " c
    msg := msg "`nHit Type: " t
    msg := msg "`nDetails?: " (ok ? "YES" : "NO")

    ToolTip % msg
return

EnsureFocusedHwnd(hwndTarget, totalMs := 60, refocusEveryMs := 15)
{
    if !DllCall("user32\IsWindow", "Ptr", hwndTarget, "Int")
        return false

    tidTarget := DllCall("user32\GetWindowThreadProcessId", "Ptr", hwndTarget, "UInt*", 0, "UInt")

    ; already focused?
    if (ControlGetFocusEx(tidTarget, hwndTarget, 0))
        return true

    start := A_TickCount
    nextRefocus := 0
    didForeground := false

    Loop
    {
        now := A_TickCount
        if ((now - start) >= totalMs)
            break

        if (now >= nextRefocus)
        {
            ; Foreground only once, retries are cheap (ensureForeground := false)
            FocusHwndFast(hwndTarget, false, !didForeground)
            didForeground := true
            nextRefocus := now + refocusEveryMs
        }

        if (ControlGetFocusEx(tidTarget, hwndTarget, 0))
            return true

        Sleep, 0
    }

    return ControlGetFocusEx(tidTarget, hwndTarget, 0)
}
; Why that’s faster
    ; One-time ControlGet and minimal focus calls
    ; Verification is a single API call (GetGUIThreadInfo) + IsChild, rather than a higher-level AHK command and repeated focus attempts
    ; The total work is bounded by a time budget (e.g., 35–60ms), not a huge loop count
; Why it’s more reliable
    ; It doesn’t require the focused thing to equal your exact ClassNN string.
    ; It treats “focus is within the target control subtree” as success, which is what you actually want before sending keys (especially for DirectUIHWND*).
; When not to use it
    ; For simple, same-process Win32 apps where ControlGetFocus is perfectly reliable, your old loop isn’t necessary anyway; one ControlFocus is enough.
EnsureFocusedCtrlNN(hwndTop, ctrlNN, totalMs := 60, refocusEveryMs := 15)
{
    ControlGet, hCtl, Hwnd,, %ctrlNN%, ahk_id %hwndTop%
    if (!hCtl)
        return false
    return EnsureFocusedHwnd(hCtl, totalMs, refocusEveryMs)
}
;You can use WinGetClass, cls, ahk_id %hwnd%, but it’s heavier in tight loops because it’s a higher-
; level AHK command. The direct DllCall("GetClassNameW") version is typically faster and easier
; to use in a parent-walk loop.
GetClassName(hwnd)
{
    VarSetCapacity(buf, 256 * 2, 0)
    DllCall("user32\GetClassNameW", "Ptr", hwnd, "Ptr", &buf, "Int", 256)
    return StrGet(&buf, "UTF-16")
}

FindAncestorByClassPrefix_Walk(hwnd, prefix, maxDepth := 20)
{
    Loop, %maxDepth%
    {
        if (!hwnd)
            return 0

        cls := GetClassName(hwnd)
        if (SubStr(cls, 1, StrLen(prefix)) = prefix)
            return hwnd

        hwnd := DllCall("user32\GetParent", "Ptr", hwnd, "Ptr")
    }
    return 0
}

ToolbarHitTest(tbHwnd)
{
    VarSetCapacity(pt, 8, 0)
    DllCall("user32\GetCursorPos", "Ptr", &pt)
    DllCall("user32\ScreenToClient", "Ptr", tbHwnd, "Ptr", &pt)

    ; TB_HITTEST = WM_USER + 69 = 0x445
    idx := DllCall("user32\SendMessageW", "Ptr", tbHwnd, "UInt", 0x445, "Ptr", 0, "Ptr", &pt, "Ptr")
    return idx ; -1 means none
}

UIA_HitTestName(desiredName, ByRef extra := "")
{
    global UIA
    extra := ""

    if (!IsObject(UIA))
        return 0

    VarSetCapacity(pt, 8, 0)
    DllCall("user32\GetCursorPos", "Ptr", &pt)
    x := NumGet(pt, 0, "Int")
    y := NumGet(pt, 4, "Int")

    el := ""
    try
        el := UIA.ElementFromPoint(x, y)
    catch e
        return 0

    if (!IsObject(el))
        return 0

    cur := el
    Loop, 20
    {
        nm := ""
        try
            nm := cur.CurrentName
        catch e
            nm := ""

        if (nm = desiredName)
        {
            extra := nm
            ; Return native hwnd if available, else just return 1
            h := 0
            try
                h := cur.CurrentNativeWindowHandle
            catch e
                h := 0

            if (h)
                return h
            return 1
        }

        parent := ""
        try
            parent := cur.GetParent()
        catch e
            parent := ""

        if (!IsObject(parent))
            break

        cur := parent
    }

    return 0
}

FindAncestorByClassPrefix(hwnd, prefix, ByRef extra := "", maxDepth := 20)
{
    extra := 0

    ; Special case: detect "any toolbar button item"
    if (prefix = "ToolbarButton")
    {
        tbHwnd := FindAncestorByClassPrefix_Walk(hwnd, "ToolbarWindow32", maxDepth)
        if (!tbHwnd)
            return false

        idx := ToolbarHitTest(tbHwnd)
        if (idx < 0)
            return false

        ; extra can carry both values if you want:
        ; - store toolbar hwnd, and index as a string "HWND|IDX"
        extra := tbHwnd "|" idx
        return true
    }

    ; Optional special case: UIA name hit-test (Win11 command bar buttons)
    if (SubStr(prefix, 1, 4) = "UIA:")
    {
        desiredName := SubStr(prefix, 5)

        ; UIA_HitTestName can return hwnd (if it has one) or 1/0.
        hit := UIA_HitTestName(desiredName, extra)

        ; Normalize to boolean; also capture hit in extra
        if (hit)
        {
            ; if UIA_HitTestName returned a hwnd, keep it
            ; otherwise keep whatever it wrote to extra
            if (!extra)
                extra := hit
            return true
        }
        return false
    }

    ; Default: original behavior
    hFound := FindAncestorByClassPrefix_Walk(hwnd, prefix, maxDepth)
    if (hFound)
    {
        extra := hFound
        return true
    }
    return false
}

#MaxThreadsPerHotkey 2
#If !VolumeHover() && !IsOverException() && LbuttonEnabled && !hitTAB && !MouseIsOverTitleBar(,,False) && !MouseIsOverTaskbarWidgets()
$~LButton::
    SetTimer, SendCtrlAddLabel, Off
    tooltip,
    HotString("Reset")
    textBoxSelected := False

    CoordMode, Mouse, Screen
    MouseGetPos, lbX1, lbY1, _winIdD, _winCtrlD
    WinGetClass, wmClassD, ahk_id %_winIdD%

    If (   wmClassD != "CabinetWClass"
        && wmClassD != "#32770"
        && !InStr(_winCtrlD, "SysListView32", True)
        && !InStr(_winCtrlD, "DirectUIHWND", True)
        && !InStr(_winCtrlD, "SysTreeView32", True)
        && !InStr(_winCtrlD, "SysHeader32", True))
        Return

    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    ; tooltip, % "is it blank? " IsExplorerBlankSpaceClick()
    initTime := A_TickCount

    If (    A_PriorHotkey == A_ThisHotkey
        && (A_TimeSincePriorHotkey < DoubleClickTime)
        && (abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25)
        && (InStr(_winCtrlD, "SysListView32", True) || InStr(_winCtrlD, "DirectUIHWND", True))) {
        ; tooltip, %isBlankSpaceExplorer% - %isBlankSpaceNonExplorer%
        If (isBlankSpaceExplorer || isBlankSpaceNonExplorer) {
            If (InStr(_winCtrlD, "SysListView32", True)) {
                Send, {Backspace}
                SetTimer, RunDynaExprTimeout, -1
            }
            Else {
                Send, !{Up}
                SetTimer, RunDynaExprTimeout, -1
            }
        }

        KeyWait, Lbutton, U T3
        LbuttonEnabled     := False

        If (wmClassD == "CabinetWClass" || wmClassD == "#32770") {
            ; tooltip, getting path
            currentPath    := ""
            loop 50 {
                If (GetKeyState("LButton","P") || WinExist("A") != _winIdD) {
                    LbuttonEnabled     := True
                    SetTimer, keyTrack, On
                    SetTimer, mouseTrack, On
                    Return
                }
                currentPath := GetExplorerPath(_winIdD)
                If (currentPath != "" && prevPath != currentPath )
                    break
                sleep, 1
            }
            ; tooltip, %A_TimeSincePriorHotkey% - %prevPath% - %currentPath%
            If (prevPath != "" && currentPath != "" && prevPath != currentPath) {
                SendCtrlAdd(_winIdD, prevPath, currentPath, wmClassD)
            }

            LbuttonEnabled     := True
            SetTimer, keyTrack, On
            SetTimer, mouseTrack, On
            Return
        }
        Else {
            ; tooltip, sending to non-explorer
            SendCtrlAdd(_winIdD,,,wmClassD)
            SetTimer, keyTrack, On
            SetTimer, mouseTrack, On
            If isBlankSpaceNonExplorer
                sleep, 250
            LbuttonEnabled     := True
            Return
        }
    }

    isBlankSpaceExplorer    := False
    isBlankSpaceNonExplorer := False
    isExplorerHeader        := False
    ; isExplorerItem          :=

    prevPath := ""
    If (wmClassD == "CabinetWClass" || wmClassD == "#32770") {
        If (InStr(_winCtrlD, "SysListView32", True) || InStr(_winCtrlD, "DirectUIHWND", True))
            isBlankSpaceExplorer := IsExplorerBlankSpaceClick()
        loop 50 {
            If (GetKeyState("LButton","P") || WinExist("A") != _winIdD) {
                LbuttonEnabled     := True
                SetTimer, keyTrack, On
                SetTimer, mouseTrack, On
                Return
            }
            prevPath := GetExplorerPath(_winIdD)
            If (prevPath != "")
                break
            sleep, 1
        }
    }
    Else {
        LBD_HexColor1 := 0x000000
        LBD_HexColor2 := 0x000000
        LBD_HexColor3 := 0x000000
        CoordMode, Pixel, Screen
        lbX1 -= 2
        lbY1 -= 2
        loop 5 {
            PixelGetColor, LBD_HexColor%A_Index%, %lbX1%, %lbY1%, RGB
            lbX1 += 1
            lbY1 += 1
        }
        CoordMode, Mouse, Screen
        isBlankSpaceNonExplorer := (LBD_HexColor1 == 0xFFFFFF && LBD_HexColor2 == 0xFFFFFF && LBD_HexColor3  == 0xFFFFFF)
    }

    KeyWait, LButton, U T5

    MouseGetPos, lbX2, lbY2, _winIdU, _winCtrlU
    ; MouseGetPos, , , , _winCtrlUNN

    rlsTime  := A_TickCount
    timeDiff := rlsTime - initTime
    extra    := ""

    ; tooltip, % isWin11 "-" IsExplorerModern() "-" IsExplorerHeaderClick() "-" IsModernExplorerActive(_winIdU)
    ; tooltip, %timeDiff% ms - %wmClassD% - %_winCtrlU% - %LBD_HexColor1% - %LBD_HexColor2% - %LBD_HexColor3% - %lbX1% - %lbX2%

    If (timeDiff < floor(DoubleClickTime/2) && (abs(lbX1-lbX2) < 15 && abs(lbY1-lbY2) < 15)) {

        If (   (InStr(_winCtrlU, "SysListView32", True) || InStr(_winCtrlU, "DirectUIHWND", True))
            && (isBlankSpaceExplorer || isBlankSpaceNonExplorer) ) {

            ; tooltip, here1
            SetTimer, SendCtrlAddLabel, -125
        }
        Else If ( (InStr(_winCtrlU,"SysHeader32", True) || InStr(_winCtrlU, "DirectUIHWND", True))
               && !IsExplorerItemClick()) {

            ; tooltip, here1a
            If (!InStr(_winCtrlU,"SysHeader32", True)) {
                If (wmClassD == "#32770") {
                    isExplorerHeader := IsExplorerHeaderClick_Local()
                }
                Else
                    isExplorerHeader := IsExplorerHeaderClick()
            }
            Else {
                isExplorerHeader := True
            }

            ListLines, Off
            ListLines, On ; clears history and starts fresh

            If (!isExplorerHeader) {
                ; Get UIA element
                pt    := SafeUIA_ElementFromPoint(lbX2, lbY2)
                ctype := SafeUIA_GetControlType(pt)
                ; Optional if used later
                ; cname := SafeUIA_GetName(pt, "")
                ; Cache risky UIA properties ONCE
                If (ctype == "" || ctype > 50035 || ctype < 50031) {
                    SetTimer, keyTrack,   On
                    SetTimer, mouseTrack, On
                    Return
                }
            }

            If (isExplorerHeader || ctype  == 50031) {
                ; tooltip, % "line4 - " pt.CurrentControlType
                If (wmClassD == "#32770" || InStr(_winCtrlU,"DirectUIHWND3", True)) {

                    EnsureFocusedCtrlNN(_winIdU, _winCtrlU, 60, 15)
                    Send, ^{NumpadAdd}
                    Return
                }
                Else If (wmClassD == "CabinetWClass" && isWin11 && isModernExplorerInReg) {

                    EnsureFocusedCtrlNN(_winIdU, _winCtrlU, 60, 15)
                    Send, ^{NumpadAdd}
                    Return
                }
                Else If (ctype  == 50035) { ; this most likely would indicate an SysListView based window like 7-zip
                    If !isWin11
                        Send, {F5}

                    Send, ^{NumpadAdd}
                    Return
                }
                Else If ((ctype == 50033) && (InStr(_winCtrlU, "DirectUIHWND", True))) {

                    Send, ^{NumpadAdd}
                    Return
                }
            }
        }
        Else If ( (wmClassD == "CabinetWClass" || wmClassD == "#32770")
            && (   InStr(_winCtrlU, "ToolbarWindow32", True)
                || InStr(_winCtrlU, "ReBarWindow32", True)
                || InStr(_winCtrlU, "Microsoft.UI.Content.DesktopChildSiteBridge", True)
                || InStr(_winCtrlU, "Windows.UI.Composition.DesktopWindowContentBridge", True) )) {

            ; tooltip, here2
            pt     := SafeUIA_ElementFromPoint(lbX2,lbY2)
            ctype  := SafeUIA_GetControlType(pt)
            cname  := SafeUIA_GetName(pt)
            cltype := SafeUIA_GetLocalizedControlType(pt)

            If (ctype == "") {

                SetTimer, keyTrack,   On
                SetTimer, mouseTrack, On
                Return
            }
            ; tooltip, % pt.CurrentControlType "-" pt.CurrentName "-" pt.CurrentLocalizedControlType
            If (ctype == 50000
                && !InStr(cname, "Back", True) && !InStr(cname, "Forward", True) && !InStr(cname, "Up", True) && !InStr(cname, "Refresh", True)) {

                SetTimer, keyTrack,   On
                SetTimer, mouseTrack, On
                Return
            }

            If InStr(cname, "Refresh", True) {
                SendCtrlAdd(_winIdU, , , wmClassD)
            }
            Else If (  (ctype == 50000) ; handles explorer based buttons
                    || (ctype == 50011) ; handles #32770 breadcrumb bar
                    || (ctype == 50020) ; handles normal explorer breadcrumb bar
                    || (ctype == 50031 && !InStr(cname,  "Open",  True)) ; handles #32770 breadcrumb bar
                    || (ctype == 50031 && !InStr(cltype, "split", True))) { ; handles normal explorer breadcrumb bar

                ; tooltip, here3
                currentPath := ""
                loop 100 {
                    currentPath := GetExplorerPath(_winIdU)
                    If (currentPath != "" && currentPath != prevPath)
                        break
                    sleep, 1
                }
                SendCtrlAdd(_winIdU, prevPath, currentPath, wmClassD)
            }
        }
        Else If (   InStr(_winCtrlU, "SysTreeView32", True)
                && (wmClassD == "CabinetWClass" || wmClassD == "#32770")
                && (!isBlankSpaceExplorer && !isBlankSpaceNonExplorer)) {

            ; tooltip, here4
            currentPath := ""
            loop 100 {
                currentPath := GetExplorerPath(_winIdU)
                If (currentPath != "" && currentPath != prevPath)
                    break
                sleep, 1
            }
            ; tooltip, sending
            SendCtrlAdd(_winIdU, prevPath, currentPath, wmClassD, _winCtrlU)
        }
    }

    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On
Return
#If

; FocusHwndFast(hwnd)
; - Activates the top-level window, brings it to foreground safely, and sets keyboard focus to 'hwnd'.
; - Pure Win32, avoids UIA. Works only for HWND-backed controls.
; Fast, reliable focus with minimal overhead
FocusHwndFast(hwndTarget, verify := true, ensureForeground := true)
{
    if !DllCall("IsWindow", "Ptr", hwndTarget)
        return false

    ; Quick success path (same as your original)
    if (DllCall("GetFocus", "Ptr") = hwndTarget)
        return true

    hwndTop := DllCall("GetAncestor", "Ptr", hwndTarget, "UInt", 2, "Ptr")
    if (!hwndTop)
        hwndTop := hwndTarget

    if (DllCall("IsIconic", "Ptr", hwndTop))
        DllCall("ShowWindowAsync", "Ptr", hwndTop, "Int", 9)

    hFG    := DllCall("GetForegroundWindow", "Ptr")
    tidAHK := DllCall("GetCurrentThreadId", "UInt")
    tidTW  := DllCall("GetWindowThreadProcessId", "Ptr", hwndTop, "UInt*", 0, "UInt")

    attachedToTW := false
    if (tidTW != tidAHK)
    {
        DllCall("AttachThreadInput", "UInt", tidTW, "UInt", tidAHK, "Int", 1)
        attachedToTW := true
    }

    attachedToFG := false
    if (ensureForeground && hFG != hwndTop)
    {
        tidFG := DllCall("GetWindowThreadProcessId", "Ptr", hFG, "UInt*", 0, "UInt")
        if (tidFG != tidAHK)
        {
            DllCall("AttachThreadInput", "UInt", tidFG, "UInt", tidAHK, "Int", 1)
            attachedToFG := true
        }

        DllCall("SetForegroundWindow", "Ptr", hwndTop)
    }

    DllCall("SetActiveWindow", "Ptr", hwndTop)
    DllCall("SetFocus", "Ptr", hwndTarget, "Ptr")

    success := true
    if (verify)
        success := (DllCall("GetFocus", "Ptr") = hwndTarget)

    if (attachedToFG)
        DllCall("AttachThreadInput", "UInt", tidFG, "UInt", tidAHK, "Int", 0)

    if (attachedToTW)
        DllCall("AttachThreadInput", "UInt", tidTW, "UInt", tidAHK, "Int", 0)

    return success
}

GetItemsViewHwndFromUIA(shellEl)
{
    hCtl := 0

    ; Most UIA wrappers expose CurrentNativeWindowHandle
    try
        hCtl := shellEl.CurrentNativeWindowHandle
    catch e
        hCtl := 0

    return hCtl
}

WaitForExplorerLoad(targetHwndID, skipFocus := False, isCabinetWClass10 := False) {
    global UIA

    try {
        exEl := UIA.ElementFromHandle(targetHwndID)
        shellEl := exEl.FindFirstByName("Items View")
        shellEl.WaitElementExist("ControlType=ListItem OR Name=This folder is empty. OR Name=No items match your search.",,,,5000)

        If (!isCabinetWClass10 && !skipFocus) {
            ; ControlGet, hCtl, Hwnd,, DirectUIHWND2, ahk_id %targetHwndID%
            hCtl := GetItemsViewHwndFromUIA(shellEl)

            if (!hCtl)
                ControlGet, hCtl, Hwnd,, DirectUIHWND2, ahk_id %targetHwndID%

            if (!hCtl)
                return

            tidTarget := DllCall("GetWindowThreadProcessId", "Ptr", hCtl, "UInt*", 0, "UInt")

            ; if already focused inside the view, skip everything
            if (ControlGetFocusEx(tidTarget, hCtl, 0))
                return

            ; expensive once
            FocusHwndFast(hCtl, false, true)
            if (ControlGetFocusEx(tidTarget, hCtl, 15))
                return

            ; cheap retry (usually 1-2 is enough)
            Loop, 2
            {
                FocusHwndFast(hCtl, false, false)
                if (ControlGetFocusEx(tidTarget, hCtl, 15))
                    break
                Sleep, 1
            }
        }
    } catch e {
        tooltip, 4: UIA TIMED OUT!!!!
        WinGetClass, wndClass, ahk_id %targetHwndID%
        MsgBox % "Exception caught:`n"
            . "targetHwndID: " targetHwndID "`n"
            . "Class: " wndClass "`n"
            . "Message: " e.Message "`n"
            . "What: " e.What "`n"
            . "File: " e.File "`n"
            . "Line: " e.Line "`n"
            . "Extra: " e.Extra
        UIA :=  ;// set to a different value
        ; VarSetCapacity(UIA, 0) ;// set capacity to zero
        UIA := UIA_Interface() ; Initialize UIA interface
        UIA.TransactionTimeout := 2000
        UIA.ConnectionTimeout  := 20000
        LbuttonEnabled := True
    }
    Return
}

SendCtrlAddLabel:
    SendCtrlAdd(_winIdU, , , , _winCtrlUNN)
Return

#MaxThreadsPerHotkey 1
UpdateInputBoxTitle:
    WinSet, ExStyle, +0x80, ahk_class #32770 ; 0x80 is WS_EX_TOOLWINDOW
    If (WinExist("Type Up to 3 Letters of a Window Title to Search") && !StopCheck) {
        WinSet, AlwaysOnTop, On, Type Up to 3 Letters of a Window Title to Search
        StopCheck := True
    }

    ControlGetText, memotext, Edit1, Type Up to 3 Letters of a Window Title to Search
    StringLen, memolength, memotext

    If ((memolength >= 3 && (A_TickCount-TimeOfLastHotkeyTyped > 400)) || (memolength >= 1 && InStr(memotext, " "))) {
        UserInputTrimmed := Trim(memotext)
        Send, {ENTER}
        SetTimer, UpdateInputBoxTitle, off
        Return
    }
    Else {
        UserInputTrimmed := Trim(memotext)
    }
Return

; https://superuser.com/questions/1603554/autohotkey-find-and-focus-windows-by-name-accross-virtual-desktops
$~Ctrl::
    GoSub, LaunchWinFind
Return

LaunchWinFind:
    If (A_PriorHotkey = "$~Ctrl" && A_TimeSincePriorHotkey < (DoubleClickTime/2))
    {
        StopRecursion   := True
        SetTimer, mouseTrack, off

        UserInputTrimmed :=
        StopCheck        := False
        SearchingWindows := True
        BlockKeyboard(True)
        SetTimer, UpdateInputBoxTitle, 5
        BlockKeyboard(False)
        InputBox, UserInput, Type Up to 3 Letters of a Window Title to Search, , , 340, 100, CoordXCenterScreen()-(340/2), CoordYCenterScreen()-(100/2)
        SetTimer, UpdateInputBoxTitle, off

        If ErrorLevel
        {
            StopRecursion    := False
            SearchingWindows := False
            SetTimer, mouseTrack, On
            Return
        }
        Else
        {
            DetectHiddenWindows, On
            Critical On
            totalMenuItemCount := 0
            onlyTitleFound := ""
            allWinArray := []
            winAssoc := {}
            winArraySort := []

            WinGet, id, list
            Loop, %id%
            {
                this_ID := id%A_Index%

                If !JEE_WinHasAltTabIcon(this_ID)
                   continue

                WinGetTitle, title, ahk_id %this_ID%
                WinGet, procName, ProcessName , ahk_id %this_ID%
                desknum := findDesktopWindowIsOn(this_ID)
                ; desknum := 1
                If desknum <= 0
                    continue
                finalTitle := % "Desktop " desknum " ↑ " procName " ↑ " title "^" this_ID
                allWinArray.Push(finalTitle)
            }

            If (allWinArray.length() == 0) {
                Critical, Off
                Tooltip, No matches found...
                Sleep, 1500
                Tooltip,
                StopRecursion := False
                SetTimer, mouseTrack, On
                Return
            }

            For k, v in allWinArray
            {
                winAssoc[v] := k
            }

            For k, v in winAssoc
            {
                winArraySort.Push(k)
            }

            desktopEntryLast := ""

            Menu, windows, Add
            Menu, windows, deleteAll
            For k, ft in winArraySort
            {
                splitEntry1 := StrSplit(ft , "^")
                entry := splitEntry1[1]
                ahkid := splitEntry1[2]

                WinGet, minState, MinMax, ahk_id %ahkid%

                splitEntry2    := StrSplit(entry, "↑")
                desktopEntry   := splitEntry2[1]
                procEntry      := Trim(splitEntry2[2])
                ; procEntry      := RTrim(procEntry)
                titleEntry     := Trim(splitEntry2[3])

                WinGet, Path, ProcessPath, ahk_exe %procEntry%
                If (minState == -1 )
                    finalEntry   := % desktopEntry ":  [" titleEntry "] (" procEntry ")"
                Else
                    finalEntry   := % desktopEntry ":  " titleEntry " (" procEntry ")"
                ; tooltip, searching for %UserInputTrimmed%
                If (!InStr(finalEntry, UserInputTrimmed))
                    continue

                If (desktopEntryLast != ""  && (desktopEntryLast != desktopEntry)) {
                    Menu, windows, Add
                }
                If (finalEntry != "" && titleEntry != "") {
                    totalMenuItemCount := totalMenuItemCount + 1
                    onlyTitleFound := finalEntry

                    Menu, windows, Add, %finalEntry%, ActivateWindow
                    Try
                        Menu, windows, Icon, %finalEntry%, %Path%,, 32
                    Catch
                        Menu, windows, Icon, %finalEntry%, %A_WinDir%\System32\SHELL32.dll, 3, 32
                }
                desktopEntryLast := desktopEntry
            }
            Critical Off

            If (totalMenuItemCount == 1 && onlyTitleFound != "") {
                GoSub, ActivateWindow
            }
            Else If (totalMenuItemCount > 1) {
                SetTimer, RunDynaExpr, -1

                CoordMode, Mouse, Screen
                CoordMode, Menu, Screen
                ; https://www.autohotkey.com/boards/viewtopic.php?style=17&t=107525#p478308
                drawX := CoordXCenterScreen()
                drawY := CoordYCenterScreen()
                Gui, ShadowFrFull:  Show, x%drawX% y%drawY% h0 w0
                ; Gui, ShadowFrFull2: Show, x%drawX% y%drawY% h1 y1
                ; sleep, 100
                ; DllCall("SetTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 1, "UInt", 10, "Ptr", RegisterCallback("MyFader", "F"))
                ; DllCall("SetTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 2, "UInt", 150, "Ptr", RegisterCallback("MyTimer", "F"))
                ; Menu, windows, show, % A_ScreenWidth/4, % A_ScreenHeight/3
                ShowMenuX("windows", drawX, drawY, 0x14)
                ; Gui, ShadowFrFull:  Hide
                Menu, windows, deleteAll
            }
            Else {
                loop 100 {
                    tooltip, No windows found!
                    sleep, 10
                }
                tooltip,
            }
        }
        SearchingWindows := False

        StopRecursion   := False
        SetTimer, mouseTrack, On
    }
    KeyWait, Ctrl, U T10
Return

ActivateWindow:
    Gui, ShadowFrFull:  Hide
    ; Gui, ShadowFrFull2: Hide
    DetectHiddenWindows, On
    thisMenuItem := ""
    result := {}

    If (totalMenuItemCount == 1 && onlyTitleFound != "")
        thisMenuItem := onlyTitleFound
    Else
        thisMenuItem := A_ThisMenuItem

    SetTitleMatchMode, 3
    SetTitleMatchMode, Fast

    fulltitle := RegExReplace(thisMenuItem, "\(\S+\.\S+\)$", "")
    fulltitle := Trim(fulltitle)
    ; msgbox, %fulltitle%
    fulltitle := RegExReplace(fulltitle, "^Desktop\s\d+\s*\:\s?", "")
    fulltitle := Trim(fulltitle)
    RegExMatch(fulltitle, "O)(\]$)", result)
    ; msgbox, % fulltitle " with " result.Count()
    If (result.Count() > 0) {
        fulltitle := RegExReplace(fulltitle, "^\[", "")
        fulltitle := Trim(fulltitle)
        fulltitle := RegExReplace(fulltitle, "\]?\s*$", "")
        fulltitle := Trim(fulltitle)
    }

    If (fulltitle == "Calculator") {
        ; https://www.autohotkey.com/boards/viewtopic.php?t=43997
        WinGet, CalcIDs, List, Calculator
        If (CalcIDs = 1) ; Calc is NOT minimized
            CalcID := CalcIDs1
        Else
            CalcID := CalcIDs2 ; Calc is Minimized use 2nd ID
        WinActivate, ahk_id %CalcID%
    }
    Else
        WinActivate, %fulltitle%

    ; tooltip, activating %fulltitle%
    sleep, 125
    ; WinGet, hwndId, ID, A
    ; currentMon := MWAGetMonitorMouseIsIn()
    ; currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
    ; If !currentMonHasActWin {
        ; Send, #+{Left}
        ; sleep, 150
     ; }
    GoSub, DrawRect
    sleep, 200
    ClearRect()
    ; }
    Process, Close, Expr_Name
    Process, Close, ExprAltUp_Name

Return

SwitchDesktop:
    global movehWndId
    global GoToDesktop := False

    StopRecursion := True
    SetTimer, keyTrack,   Off
    SetTimer, mouseTrack, Off

    MouseGetPos, , , movehWndId
    WinActivate, ahk_id %movehWndId%
    CurrentDesktop := GetCurrentDesktopNumber() + 1
    Menu, vdeskMenu, Add
    Menu, vdeskMenu, DeleteAll
    loop % getTotalDesktops()
    {
        If (CurrentDesktop != A_Index)
        {
            Menu, vdeskMenu, Add,  Move to Desktop %A_Index%, SendWindow
            ; Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_WinDir%\System32\imageres.dll, 290, 32
            If ( A_Index == 1)
                Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_ScriptDir%\1-move-blk.ico, , 32
            Else If (A_Index == 2)
                Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_ScriptDir%\2-move-blk.ico, , 32
            Else If (A_Index == 3)
                Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_ScriptDir%\3-move-blk.ico, , 32
            Else If (A_Index == 4)
                Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_ScriptDir%\4-move-blk.ico, , 32

            Menu, vdeskMenu, Add,  Move and Go to Desktop %A_Index%, SendWindowAndGo
            ; Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_WinDir%\System32\imageres.dll, 290, 32
            If ( A_Index == 1)
                Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_ScriptDir%\1-moveswitch-blk.ico, , 32
            Else If (A_Index == 2)
                Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_ScriptDir%\2-moveswitch-blk.ico, , 32
            Else If (A_Index == 3)
                Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_ScriptDir%\3-moveswitch-blk.ico, , 32
            Else If (A_Index == 4)
                Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_ScriptDir%\4-moveswitch-blk.ico, , 32
        }
    }
    Menu, vdeskMenu, Show

    If GoToDesktop
        sleep, 1000
    StopRecursion := False
    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On

Return

SendWindow:
    global movehWndId
    global targetDesktop
    moveLeftConst := -1
    moveRightConst := 1
    moveConst := 0

    DetectHiddenWindows, On

    InitialDesktop := GetCurrentDesktopNumber() + 1

    If      (A_ThisMenuItem == "Move to Desktop 1") || (A_ThisMenuItem == "Move and Go to Desktop 1")
        targetDesktop := 1
    Else If (A_ThisMenuItem == "Move to Desktop 2") || (A_ThisMenuItem == "Move and Go to Desktop 2")
        targetDesktop := 2
    Else If (A_ThisMenuItem == "Move to Desktop 3") || (A_ThisMenuItem == "Move and Go to Desktop 3")
        targetDesktop := 3
    Else If (A_ThisMenuItem == "Move to Desktop 4") || (A_ThisMenuItem == "Move and Go to Desktop 4")
        targetDesktop := 4
    Else If (A_ThisMenuItem == "Move to Desktop 5") || (A_ThisMenuItem == "Move and Go to Desktop 5")
        targetDesktop := 5
    Else If (A_ThisMenuItem == "Move to Desktop 6") || (A_ThisMenuItem == "Move and Go to Desktop 6")
        targetDesktop := 6
    Else If (A_ThisMenuItem == "Move to Desktop 7") || (A_ThisMenuItem == "Move and Go to Desktop 7")
        targetDesktop := 7
    Else If (A_ThisMenuItem == "Move to Desktop 8") || (A_ThisMenuItem == "Move and Go to Desktop 8")
        targetDesktop := 8

    WinGetPos, sw_x, sw_y, sw_h, sw_w, ahk_id %movehWndId%
    If (targetDesktop < InitialDesktop)
        MoveAndFadeWindow(movehWndId, sw_x, False)
    Else
        MoveAndFadeWindow(movehWndId, sw_x, True)

    If      (A_ThisMenuItem == "Move to Desktop 1") || (A_ThisMenuItem == "Move and Go to Desktop 1")
        MoveCurrentWindowToDesktop(1)
    Else If (A_ThisMenuItem == "Move to Desktop 2") || (A_ThisMenuItem == "Move and Go to Desktop 2")
        MoveCurrentWindowToDesktop(2)
    Else If (A_ThisMenuItem == "Move to Desktop 3") || (A_ThisMenuItem == "Move and Go to Desktop 3")
        MoveCurrentWindowToDesktop(3)
    Else If (A_ThisMenuItem == "Move to Desktop 4") || (A_ThisMenuItem == "Move and Go to Desktop 4")
        MoveCurrentWindowToDesktop(4)
    Else If (A_ThisMenuItem == "Move to Desktop 5") || (A_ThisMenuItem == "Move and Go to Desktop 5")
        MoveCurrentWindowToDesktop(5)
    Else If (A_ThisMenuItem == "Move to Desktop 6") || (A_ThisMenuItem == "Move and Go to Desktop 6")
        MoveCurrentWindowToDesktop(6)
    Else If (A_ThisMenuItem == "Move to Desktop 7") || (A_ThisMenuItem == "Move and Go to Desktop 7")
        MoveCurrentWindowToDesktop(7)
    Else If (A_ThisMenuItem == "Move to Desktop 8") || (A_ThisMenuItem == "Move and Go to Desktop 8")
        MoveCurrentWindowToDesktop(8)

    If !GoToDesktop
        WinSet, Transparent, 255, ahk_id %movehWndId%

    DetectHiddenWindows, Off
Return

SendWindowAndGo:
    global movehWndId, targetDesktop

    GoToDesktop := True
    GoSub, SendWindow

    GoSub, SwitchToVD%targetDesktop%
    sleep, 400

    WinGetPos, sw_x, sw_y, sw_h, sw_w, ahk_id %movehWndId%
    If (targetDesktop < InitialDesktop)
        MoveAndFadeWindow(movehWndId, sw_x, False, "in")
    Else
        MoveAndFadeWindow(movehWndId, sw_x, True, "in")

    GoToDesktop := False
Return

; → Returns the entire window’s bounding box in screen coordinates.
; What it measures
; The outer rectangle of a window/control: includes title bar, borders, shadows, scrollbars, etc.
; Coordinates (L, T, R, B) are relative to the screen (top-left of the monitor).
GetWindowRectEx(hWnd, ByRef L, ByRef T, ByRef R, ByRef B) {
    VarSetCapacity(RECT, 16, 0)
    ; BOOL GetWindowRect(HWND hWnd, LPRECT lpRect)
    ok := DllCall("GetWindowRect", "ptr", hWnd, "ptr", &RECT, "int")
    if (!ok)
        return false
    L := NumGet(RECT, 0,  "Int")
    T := NumGet(RECT, 4,  "Int")
    R := NumGet(RECT, 8,  "Int")
    B := NumGet(RECT, 12, "Int")
    return true
}

; Returns true if subkey (like "Software\Classes\CLSID\{...}\InProcServer32") exists under HKCU
KeyExistsInHKCU(subkey) {
    ; constants
    HKEY_CURRENT_USER := 0x80000001
    KEY_READ := 0x20019

    ; try to open the subkey (Unicode)
    hKey := 0
    ret := DllCall("Advapi32\RegOpenKeyExW", "Ptr", HKEY_CURRENT_USER, "WStr", subkey, "UInt", 0, "UInt", KEY_READ, "PtrP", hKey)

    if (ret == 0) { ; ERROR_SUCCESS
        ; close handle and return true
        DllCall("Advapi32\RegCloseKey", "Ptr", hKey)
        return true
    }
    return false
}

; IsExplorerModern() -> returns true if modern (Windows 11) Explorer UI is active,
;                      false if classic (Windows 10) Explorer UI is active.
HasWin10ExplorerOverride() {
    win10ExplorerGUIDs := ["{2aa9162e-c906-4dd9-ad0b-3d24a8eef5a0}", "{6480100b-5a83-4d1e-9f69-8ae5a88e9a33}"]
    base := "Software\Classes\CLSID\"
    for _, guid in win10ExplorerGUIDs {
        subkey := base . guid . "\InProcServer32"
        if (KeyExistsInHKCU(subkey))
            return true
    }
    return false
}
IsExplorerModern() {
    return !HasWin10ExplorerOverride()
}

; -----------------------
; Example usage:
; -----------------------
; if (IsExplorerModern())
;     MsgBox % "Explorer appears to be MODERN (Windows 11)."
; else
;     MsgB

IsModernExplorerActive(hWnd := "") {
    global UIA, isWin11

    if !isWin11
        return false

    ; 1) Get target window (active if none passed)
    if !hWnd {
        WinGet, hWnd, ID, A
        if !hWnd
            return false
    }

    ; 2) Must be Explorer frame, backed by explorer.exe
    WinGetClass, cls, ahk_id %hWnd%
    if (cls != "CabinetWClass")
        return false

    WinGet, proc, ProcessName, ahk_id %hWnd%
    if (proc != "explorer.exe")
        return false

    ; 3) Ensure UIA is initialized
    if !IsObject(UIA) {
        try {
            UIA := UIA_Interface()
            UIA.TransactionTimeout := 2000
            UIA.ConnectionTimeout  := 20000
        } catch e {
            return false
        }
    }

    ; 4) Get UIA root for this Explorer window
    root := ""
    try
        root := UIA.ElementFromHandle(hWnd)
    catch
        root := ""

    if !IsObject(root)
        return false

    ; 5) Look for the WinUI/XAML host:
    ;    ClassName = Microsoft.UI.Content.DesktopChildSiteBridge
    bridge := ""
    try
        bridge := root.FindFirstBy("ClassName=InputSiteWindowClass")
    catch
        bridge := ""

    if !IsObject(bridge)
        return false

    ; 6) Check its FrameworkId – should be XAML / WinUI on modern Explorer
    fw := ""
    try
        fw := bridge.FrameworkId
    catch
        fw := ""

    ; Normalize to lower for comparison
    if (fw != "") {
        StringLower, fwLower, fw
        if (fwLower == "xaml" || fwLower == "winui")
            return true
    }

    return false
}

GetCtrlNNsByPrefix(hwndTop, classPrefix)
{
    WinGet, listC, ControlList,     ahk_id %hwndTop%
    WinGet, listH, ControlListHwnd, ahk_id %hwndTop%

    ; Build array of ctrlNNs by index in one pass
    ctrlAt := []
    Loop, Parse, listC, `n, `r
    {
        ctrlAt.Push(A_LoopField)
    }

    out := ""
    idx := 0
    Loop, Parse, listH, `n, `r
    {
        idx++
        hCtl := A_LoopField + 0
        if (!hCtl)
            continue

        cls := GetClassName(hCtl)
        if (SubStr(cls, 1, StrLen(classPrefix)) != classPrefix)
            continue

        ctrlNN := (idx <= ctrlAt.Length()) ? ctrlAt[idx] : ""
        if (ctrlNN != "")
            out .= ctrlNN " "
    }

    return RTrim(out, " ")
}


SendCtrlAdd(initTargetHwnd := "", prevPath := "", currentPath := "", initTargetClass := "", initFocusedCtrlNN := "") {
    global UIA, isWin11, blockKeys

    TargetControl := ""
    OutputVar1    := 0
    OutputVar2    := 0
    OutputVar3    := 0
    OutputVar4    := 0
    OutputVar6    := 0
    OutputVar8    := 0

    If (initTargetClass == "")
        WinGetClass, lClassCheck, ahk_id %initTargetHwnd%
    Else
        lClassCheck := initTargetClass

    WinGet, quickCheckID, ID, A
    If (quickCheckID != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd)) {
        SetTimer, SendCtrlAddLabel, Off
        WinGetClass, lClassCheck, ahk_id %initTargetHwnd%
        ; toolTip % "failed quick check: " lClassCheck
                ; . " - " Format("0x{:X}", quickCheckID+0)
                ; . " - " Format("0x{:X}", initTargetHwnd+0)
        Return
    }
    ; tooltip, here1
    If (!GetKeyState("LShift","P" )) {
        If (initFocusedCtrlNN == "") {
            MouseGetPos, , , , initFocusedCtrlNN
            while (initFocusedCtrlNN == "ShellTabWindowClass1") {
                MouseGetPos, , , , initFocusedCtrlNN
                sleep, 1
            }
        }
        ; tooltip, here2
        If (GetKeyState("LButton","P") || WinExist("A") != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd))
            Return

        If (InStr(initFocusedCtrlNN,  "SysListView32", True)) {
            OutputVar1    := 1
            TargetControl := initFocusedCtrlNN
        }
        Else If (initFocusedCtrlNN == "DirectUIHWND4") {
            OutputVar4    := 1
            TargetControl := initFocusedCtrlNN
        }
        Else If (initFocusedCtrlNN == "DirectUIHWND6") {
            OutputVar6    := 1
            TargetControl := initFocusedCtrlNN
        }
        Else If (initFocusedCtrlNN == "DirectUIHWND8") {
            OutputVar8    := 1
            TargetControl := initFocusedCtrlNN
        }
        Else If (initFocusedCtrlNN == "DirectUIHWND2") {
            OutputVar2    := 1
            TargetControl := initFocusedCtrlNN
        }
        Else If (initFocusedCtrlNN == "DirectUIHWND3") {
            OutputVar3    := 1
            TargetControl := initFocusedCtrlNN
        }
        Else {
            DirectUICtrls := GetCtrlNNsByPrefix(initTargetHwnd, "DirectUIHWND")
            SysListCtrls := GetCtrlNNsByPrefix(initTargetHwnd, "SysListView32")
            OutputVar1 := InStr(SysListCtrls,  "SysListView32", false) > 0
            OutputVar2 := InStr(DirectUICtrls, "DirectUIHWND2", false) > 0
            OutputVar3 := InStr(DirectUICtrls, "DirectUIHWND3", false) > 0
            OutputVar4 := InStr(DirectUICtrls, "DirectUIHWND4", false) > 0
            OutputVar6 := InStr(DirectUICtrls, "DirectUIHWND6", false) > 0
            OutputVar8 := InStr(DirectUICtrls, "DirectUIHWND8", false) > 0
        }

        ; tooltip, OutputVar1:%OutputVar1% OutputVar2:%OutputVar2% OutputVar3:%OutputVar3% OutputVar4:%OutputVar4% OutputVar6:%OutputVar6% OutputVar8:%OutputVar8%

        If (GetKeyState("LButton","P") || WinExist("A") != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd))
            Return

        If (TargetControl == "" && (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1 || OutputVar4 == 1 || OutputVar6 == 1 || OutputVar8 == 1)) {

            ; tooltip, here6
            If (OutputVar1 == 1) {
                TargetControl := "SysListView321"
            }
            Else If ((OutputVar2 == 1 && OutputVar3 == 1 && !OutputVar4 && !OutputVar6 && !OutputVar8)
                    && (lClassCheck == "CabinetWClass" || lClassCheck == "#32770")) {

                OutHeight2 := 0
                OutHeight3 := 0

                If isWin11 {
                    ControlGet, hCtl, Hwnd,, DirectUIHWND2, ahk_id %initTargetHwnd%
                   ; In the Win32 API, everything that has an HWND — from the desktop to a text box — is a “window.”
                    ; That’s why these functions don’t care whether it’s a dialog, listview, or StaticNN.
                    If (GetWindowRectEx(hCtl, L, T, R, B)) {
                        OutHeight2 := B - T
                        OutWidth2  := R - L
                    }
                }
                Else {
                    ControlGetPos, , , , OutHeight2, DirectUIHWND2, ahk_id %initTargetHwnd%, , , ,
                }
                ; tooltip, 2: %OutHeight2% vs 3: %OutHeight3%
                If (lClassCheck == "CabinetWClass" && !isModernExplorerInReg)
                    ControlGetPos, , , , OutHeight3, DirectUIHWND3, ahk_id %initTargetHwnd%, , , ,

                If (lClassCheck == "CabinetWClass" && (!isWin11 || !isModernExplorerInReg))
                    TargetControl := "DirectUIHWND3"
                Else If (OutHeight2 > OutHeight3)
                    TargetControl := "DirectUIHWND2"
                Else
                    TargetControl := "DirectUIHWND2"
            }
            Else If (OutputVar2 == 1) {
                TargetControl := "DirectUIHWND2"
            }
            Else If (OutputVar3 == 1) {
                TargetControl := "DirectUIHWND3"
            }
            Else If (lClassCheck == "CabinetWClass" || lClassCheck == "#32770") {
                If OutputVar4
                    TargetControl := "DirectUIHWND4"
                Else If OutputVar6
                    TargetControl := "DirectUIHWND6"
                Else If OutputVar8
                    TargetControl := "DirectUIHWND8"
            }
        }
        ; tooltip, here7

        If (GetKeyState("LButton","P") || TargetControl == "" || WinExist("A") != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd))
            Return

        WinGet, proc, ProcessName, ahk_id %initTargetHwnd%
        WinGetTitle, vWinTitle, ahk_id %initTargetHwnd%

        ; tooltip, targeted is %TargetControl% with init at %initFocusedCtrlNN%
        If (TargetControl == "DirectUIHWND3" && (lClassCheck == "#32770" || lClassCheck == "CabinetWClass")) {
            WaitForExplorerLoad(initTargetHwnd, , True)
            ; tooltip, here7a targeted is %TargetControl% with init at %initFocusedCtrlNN%
            If (TargetControl != initFocusedCtrlNN) {

                EnsureFocusedCtrlNN(initTargetHwnd, TargetControl, 60, 15)
            }
        }
        Else If (TargetControl == "DirectUIHWND2" && lClassCheck == "#32770") {
            WaitForExplorerLoad(initTargetHwnd, True)
            ; tooltip, here7b targeted is %TargetControl% with init at %initFocusedCtrlNN%
            If (TargetControl != initFocusedCtrlNN) {

                EnsureFocusedCtrlNN(initTargetHwnd, TargetControl, 60, 15)
            }
        }
        Else If ((lClassCheck == "CabinetWClass" || lClassCheck == "#32770") && (InStr(proc,"explorer.exe",False) || InStr(vWinTitle,"Save",True) || InStr(vWinTitle,"Open",True))) {
            ; tooltip, here7c
            WaitForExplorerLoad(initTargetHwnd)
        }
        Else {
            ; tooltip, here7d targeted is %TargetControl% with init at %initFocusedCtrlNN%
            If (TargetControl != initFocusedCtrlNN) {

                EnsureFocusedCtrlNN(initTargetHwnd, TargetControl, 60, 15)
            }
        }
        ; tooltip, here8

        If (GetKeyState("LButton","P") || TargetControl == "" || WinExist("A") != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd))
            Return

        ; tooltip, targeted is %TargetControl% with init at %initFocusedCtrlNN%

        If (InStr(TargetControl, "SysListView32", True) || InStr(TargetControl,  "DirectUIHWND", True)) {
            blockKeys := True

            Send, ^{NumpadAdd}

            If ((InStr(initFocusedCtrlNN,"Edit",True) || InStr(initFocusedCtrlNN,"Tree",True)) && initFocusedCtrlNN != TargetControl) {
                sleep, 125
                blockKeys := False

                If (GetKeyState("LButton","P") || WinExist("A") != initTargetHwnd)
                    Return

                ; Use bounded focus+verify instead of 200 iterations
                EnsureFocusedCtrlNN(initTargetHwnd, initFocusedCtrlNN, 120, 15)
            }
            blockKeys := False
            FixModifiers()
        }
    }
Return
}

#If MouseIsOverTitleBar()
~Lbutton & Rbutton::
    ; ComboActive := True
    HotKey, Rbutton, DoNothing, On
    MouseGetPos, , , hwndId
    WinGetTitle, winTitle, ahk_id %hwndId%
    BlockInput, MouseMove
    WinGet, ExStyle, ExStyle, ahk_id %hwndId%
    If IsAlwaysOnTop(hwndID)
        Gui, GUI4Boarder: Color, 0x00FF00
    Else
        Gui, GUI4Boarder: Color, 0xFF0000
    GoSub, DrawRect
    sleep, 200
    ClearRect()
    Gui, GUI4Boarder: Color, %border_color%
    WinSet, AlwaysOnTop, toggle, ahk_id %hwndId%
    BlockInput, MouseMoveOff
    HotKey, Rbutton, DoNothing, Off
Return
#If

IsAlwaysOnTop(hwndID) {
    WinGet, ExStyle, ExStyle, ahk_id %hwndId% ; 0x8 is WS_EX_LAYERED.
    If (ExStyle & 0x8)
        Return True
    Else
        Return False
}

; Requires your WinGetPosEx() function to be present.

; Uses SysGet(SM_CXVSCROLL) to size the right-edge zone.
; extraW lets you widen beyond the system metric (useful for overlay scrollbars).
IsMouseInVScrollZone_WinGetPosEx_Sys(zonePadTop := 10, zonePadBot := 14
    , extraW := 6
    , ByRef hitHwnd := 0, useRoot := true
    , ByRef wx := "", ByRef wy := "", ByRef ww := "", ByRef wh := ""
    , ByRef zoneW := "")
{
    ; System metric: vertical scrollbar width
    SysGet, sbW, 2  ; SM_CXVSCROLL
    if (sbW <= 0)
        sbW := 17  ; sane fallback

    ; Make it a bit wider than the metric (Win11 overlay scrollbars feel easier this way)
    zoneW := sbW + extraW

    MouseGetPos, mx, my, winHwnd
    if (!winHwnd)
        return false

    hitHwnd := winHwnd

    if (useRoot)
    {
        rootHwnd := DllCall("GetAncestor", "ptr", hitHwnd, "uint", 2, "ptr") ; GA_ROOT=2
        if (rootHwnd)
            hitHwnd := rootHwnd
    }

    WinGetPosEx(hitHwnd, wx, wy, ww, wh)

    if (ww <= 0 || wh <= 0)
        return false

    right  := wx + ww
    bottom := wy + wh

    if (my < wy + zonePadTop || my >= bottom - zonePadBot)
        return false

    if (mx >= right - zoneW && mx < right)
        return true

    return false
}

#If MouseIsOverTaskbarBlank()
Lbutton & Rbutton::
    Send, #{r}
Return
#If

#If VolumeHover()
$WheelUp::send {Volume_Up}
$WheelDown::send {Volume_Down}
#If

#If !mouseMoving && !VolumeHover() && !IsOverException() && !DraggingWindow
RButton & WheelUp::
    SetTimer, SendCtrlAddLabel, Off
    WinGetClass, currClass, A
    If IsMouseInVScrollZone_WinGetPosEx_Sys(10, 14, 12, h) {
        If (currClass == "CASCADIA_HOSTING_WINDOW_CLASS") {
            Send, ^+{Home}
        }
        Else {
            Send, ^{Home}
            Send, {Home}
        }
    }
    Else If (currClass == "CASCADIA_HOSTING_WINDOW_CLASS") {
        Send, ^+{PgUp}
    }
    Else {
        Send, {PgUp}
    }
Return

RButton & WheelDown::
    SetTimer, SendCtrlAddLabel, Off
    WinGetClass, currClass, A
    If IsMouseInVScrollZone_WinGetPosEx_Sys(10, 14, 12, h) {
        If (currClass == "CASCADIA_HOSTING_WINDOW_CLASS") {
            Send, ^+{End}
        }
        Else {
            Send, ^{End}
            Send, {End}
        }
    }
    Else If (currClass == "CASCADIA_HOSTING_WINDOW_CLASS") {
        Send, ^+{PgDn}
    }
    Else {
        Send, {PgDn}
    }
Return

$RButton::
    StopRecursion := True
    Send, {Rbutton}
    StopRecursion := False
Return
#If

/* ;
***********************************
***** SHORTCUTS CONFIGURATION *****
***** https://github.com/JuanmaMenendez/AutoHotkey-script-Open-Show-Apps/blob/master/Switch-opened-windows-of-same-App.ahk ****
***********************************
*/
VolumeHover() {
    ControlGetText, toolText,, ahk_class tooltips_class32
    If (InStr(toolText, "Speakers", False) || InStr(toolText, "Headphones", False))
        Return True
    Else
        Return False
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
IsOverException(hWnd := "") {
    If (hWnd == "")
        MouseGetPos, , , hwndID
    Else
        hwndID := hWnd

    WinGetTitle, tit, ahk_id %hwndID%
    WinGetClass, cl, ahk_id %hwndID%
    WinGet, proc, ProcessName, ahk_id %hwndID%

    If (   proc == "peazip.exe"
        || proc == "SndVol.exe"
        || ((InStr("File Explorer", tit, True) || proc == "explorer.exe") && (InStr("Home", tit, True) || InStr("This PC", tit, True) || InStr("Gallery", tit, True)))
        || (InStr("InstallShield", tit, True))
        || cl == "#32768"
        || cl == "Autohotkey"
        || cl == "AutohotkeyGUI"
        || cl == "SysShadow"
        || cl == "TaskListThumbnailWnd"
        || cl == "Windows.UI.Core.CoreWindow"
        || cl == "ProgMan"
        || cl == "WorkerW"
        || cl == "tooltips_class32"
        || cl == "DropDown"
        || cl == "Microsoft.UI.Content.PopupWindowSiteBridge"
        || cl == "TopLevelWindowForOverflowXamlIsland"
        || cl == "OperationStatusWindow"
        || cl == "NativeHWNDHost"
        || cl == "Net UI Tool Window"
        || cl == "SDL_app"
        || cl == "DV2ControlHost"
        || cl == "TfrmSafelyRemoveMenu"
        || cl == "Qt6101QWindowIcon"
        || (cl != "#32770" && cl != "CabinetWClass" && InStr(tit, "VirtualBox",True)))
        Return True
    Else
        Return False
}

;-----------------------------------------------------------------
; Check whether the target window is activation target
;-----------------------------------------------------------------
; https://www.autohotkey.com/boards/viewtopic.php?t=81064
ShowMenu(hMenu, MenuLoop:=0, X:=0, Y:=0, Flags:=0) {            ; Ver 0.61 by SKAN on D39F/D39G
    Local                                                           ;            @ tiny.cc/showmenu
      If (hMenu="WM_ENTERMENULOOP")
        Return True
      Fn := Func("ShowMenu").Bind("WM_ENTERMENULOOP"), n := MenuLoop=0 ? 0 : OnMessage(0x211,Fn,-1)
      DllCall("SetForegroundWindow","Ptr",A_ScriptHwnd)
      R := DllCall("TrackPopupMenu", "Ptr",hMenu, "Int",Flags, "Int",X, "Int",Y, "Int",0
                 , "Ptr",A_ScriptHwnd, "Ptr",0, "UInt"),                     OnMessage(0x211,Fn, 0)
      DllCall("PostMessage", "Ptr",A_ScriptHwnd, "Int",0, "Ptr",0, "Ptr",0)

    Return R
}

; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=81064#p533551
ShowMenuX(hMenu, X := "", Y := "", Flags := 0) {   ;  ShowMenu v0.63 by SKAN on D39F/D689 @ autohotkey.com/r?t=81064
  Local
  If   hMenu Is Not Integer
       hMenu := MenuGetHandle(hMenu)

  If ( X=""  Or  Y="" ) {
       CMM := A_CoordModeMouse
       CoordMode, Mouse, Screen
       MouseGetPos, XX, YY
       CoordMode, Mouse, %CMM%
       X := X="" ? XX : X
       Y := Y="" ? YY : Y
  }

  Flags    &= ~0x180                              ;  disallow flags TPM_RETURNCMD (0x100), TPM_NONOTIFY (0x80)
  pWnd     := DllCall("User32\GetForegroundWindow", "Ptr")
  DllCall("User32\SetForegroundWindow","Ptr",mWnd := A_ScriptHwnd)

  ; Old_IsCritical := A_IsCritical
  ; Critical On

  R := DllCall("User32\TrackPopupMenuEx", "Ptr",hMenu, "UInt",Flags, "Int",X, "Int",Y, "Ptr",mWnd, "Ptr",0, "UInt")
  Sleep, 50                                       ;  wait for WM_COMMAND... DllCall("WaitMessage") too late, sucks!
  DllCall("User32\PostMessage", "Ptr",mWnd, "Int",0, "Ptr",0, "Ptr",0)

  If DllCall("User32\GetForegroundWindow", "Ptr") = mWnd  And Not  WinActive("ahk_id " mWnd)
     DllCall("User32\SetForegroundWindow","Ptr",pWnd)

  ; Critical %Old_IsCritical%
Return R
}

IsWindow(hWnd) {
    WinGet, dwStyle, Style, ahk_id %hWnd%
    If ((dwStyle & 0x08000000) || !(dwStyle & 0x10000000)) {
        Return False
    }
    WinGet, dwExStyle, ExStyle, ahk_id %hWnd%
    If (dwExStyle & 0x00000080) {
        Return False
    }
    WinGetClass, szClass, ahk_id %hWnd%
    If (szClass = "TApplication") {
        Return False
    }
    WinGetPos,,,W,H, ahk_id %hWnd%
    WinGet, state, MinMax, ahk_id %hWnd%
    If (H < 375 && state > -1 || W < 290 && state > -1) {
        Return False
    }
    Return True
}

; https://www.autohotkey.com/boards/search.php?style=17&author_id=62433&sr=posts
MyTimer() {
   DllCall("KillTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 2)

   WinWait, ahk_class #32768,, 3

   WinGetPos, menux, menuy, menuw, menuh, ahk_class #32768
   menux := menux + 10
   menuy := menuy + 10
   MouseMove, %menux%, %menuy%
}

MyFader() {
    DllCall("KillTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 1)
    tooltip, waiting...
    WinWait, ahk_class #32768, , 5
    WinSet, Transparent, 0, ahk_class #32768
    sleep 50
    WinSet, Transparent, 50, ahk_class #32768
    sleep 50
    WinSet, Transparent, 100, ahk_class #32768
    sleep 50
    WinSet, Transparent, 125, ahk_class #32768
    sleep 50
    WinSet, Transparent, 150, ahk_class #32768
    sleep 50
    WinSet, Transparent, 200, ahk_class #32768
    sleep 50
    WinSet, Transparent, 225, ahk_class #32768
    sleep 50
    WinSet, Transparent, 255, ahk_class #32768
    tooltip, done
}

; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=31716
GetCurrentMonitorIndex(){
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    SysGet, monitorsCount, 80

    Loop %monitorsCount%{
        SysGet, monitor, Monitor, %A_Index%
        If (monitorLeft <= mx && mx <= monitorRight && monitorTop <= my && my <= monitorBottom){
            Return A_Index
        }
    }
    Return 0
}

CoordXCenterScreen()
{
    ScreenNumber := GetCurrentMonitorIndex()
    SysGet, Mon1, Monitor, %ScreenNumber%
    Return (( Mon1Right-Mon1Left ) / 2) + Mon1Left
}

CoordYCenterScreen()
{
    ScreenNumber := GetCurrentMonitorIndex()
    SysGet, Mon1, Monitor, %ScreenNumber%
    Return ((Mon1Bottom-Mon1Top - 30) / 2) + Mon1Top
}

; https://www.autohotkey.com/boards/viewtopic.php?p=96016#p96016
ProcessIsElevated(vPID)
{
    ;PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    If !(hProc := DllCall("kernel32\OpenProcess", "UInt",0x1000, "Int",0, "UInt",vPID, "Ptr"))
        Return -1
    ;TOKEN_QUERY := 0x8
    hToken := 0
    If !(DllCall("advapi32\OpenProcessToken", "Ptr",hProc, "UInt",0x8, "Ptr*",hToken))
    {
        DllCall("kernel32\CloseHandle", "Ptr",hProc)
        Return -1
    }
    ;TokenElevation := 20
    vIsElevated := vSize := 0
    vRet := (DllCall("advapi32\GetTokenInformation", "Ptr",hToken, "Int",20, "UInt*",vIsElevated, "UInt",4, "UInt*",vSize))
    DllCall("kernel32\CloseHandle", "Ptr",hToken)
    DllCall("kernel32\CloseHandle", "Ptr",hProc)
    Return vRet ? vIsElevated : -1
}

; https://www.autohotkey.com/boards/viewtopic.php?t=37184
; gives you roughly the correct results (tested on Windows 7)
; The function approximates Windows’ Alt-Tab eligibility:
; Include: visible, enabled, top-level windows; anything explicitly marked WS_EX_APPWINDOW.
; Exclude: child/owned/tool windows, non-activating windows, disabled/invisible windows, and some known host processes.
JEE_WinHasAltTabIcon(hWnd)
{
    local
    If !(DllCall("user32\GetDesktopWindow", "Ptr") = DllCall("user32\GetAncestor", "Ptr",hWnd, "UInt",1, "Ptr")) ;GA_PARENT := 1
    ;|| DllCall("user32\GetWindow", "Ptr",hWnd, "UInt",4, "Ptr") ;GW_OWNER := 4 ;affects taskbar but not alt-tab
        Return 0

    WinGet, vWinProc, ProcessName, % "ahk_id " hWnd
    If InStr(vWinProc, "InputHost.exe") || InStr(vWinProc, "App.exe")
        Return 0

    WinGet, vWinStyle, Style, % "ahk_id " hWnd
    If !vWinStyle
    || !(vWinStyle & 0x10000000) ;WS_VISIBLE := 0x10000000
    || (vWinStyle & 0x8000000) ;WS_DISABLED := 0x8000000 ;affects alt-tab but not taskbar
        Return 0
    WinGet, vWinExStyle, ExStyle, % "ahk_id " hWnd
    If (vWinExStyle & 0x40000) ;WS_EX_APPWINDOW := 0x40000
        Return 1
    If (vWinExStyle & 0x80) ;WS_EX_TOOLWINDOW := 0x80
    || (vWinExStyle & 0x8000000) ;WS_EX_NOACTIVATE := 0x8000000 ;affects alt-tab but not taskbar
        Return 0
    Return 1
}

IsAltTabWindow_Why(hWnd)
{
    static WS_EX_APPWINDOW := 0x40000
    static WS_EX_TOOLWINDOW := 0x80
    static DWMWA_CLOAKED := 14
    static DWM_CLOAKED_SHELL := 2
    static WS_EX_NOACTIVATE := 0x8000000
    static GA_PARENT := 1
    static GW_OWNER := 4
    static WS_EX_WINDOWEDGE := 0x100
    static WS_EX_CONTROLPARENT := 0x10000
    static WS_EX_DLGMODALFRAME := 0x00000001

    WinGetTitle, hasTitle, ahk_id %hWnd%
    if (!hasTitle)
        return "no title"

    if !DllCall("IsWindowVisible", "uptr", hWnd)
        return "not visible"

    DllCall("DwmApi\DwmGetWindowAttribute", "uptr", hWnd, "uint", DWMWA_CLOAKED, "uint*", cloaked, "uint", 4)
    if (cloaked = DWM_CLOAKED_SHELL)
        return "cloaked shell"

    parent := DllCall("GetAncestor", "uptr", hWnd, "uint", GA_PARENT, "ptr")
    if (parent && realHwnd(parent) != realHwnd(DllCall("GetDesktopWindow", "ptr")))
        return "parent not desktop"

    WinGetClass, winClass, ahk_id %hWnd%
    if (winClass = "Windows.UI.Core.CoreWindow" || winClass = "ProgMan" || winClass = "WorkerW")
        return "blocked class: " . winClass

    WinGet, exStyles, ExStyle, ahk_id %hWnd%
    if (exStyles & WS_EX_APPWINDOW)
        return "passes via WS_EX_APPWINDOW"

    if (exStyles & WS_EX_TOOLWINDOW)
        return "toolwindow"
    if (exStyles & WS_EX_NOACTIVATE)
        return "noactivate"
    if (exStyles & WS_EX_DLGMODALFRAME)
        return "dlgmodalframe"

    if (exStyles & (WS_EX_WINDOWEDGE | WS_EX_CONTROLPARENT))
        return "passes via edge/controlparent"

    hwnd2 := hWnd
    loop
    {
        prev := hwnd2
        hwnd2 := DllCall("GetWindow", "uptr", hwnd2, "uint", GW_OWNER, "ptr")
        if (!hwnd2)
            return "passes via owner-walk end (prev=" . prev . ")"

        if DllCall("IsWindowVisible", "uptr", hwnd2)
            return "visible owner: " . hwnd2
    }
}

; https://www.autohotkey.com/boards/viewtopic.php?t=26700#p176849
; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=122399
IsAltTabWindow(hWnd) {
    static WS_EX_APPWINDOW := 0x40000, WS_EX_TOOLWINDOW := 0x80, DWMWA_CLOAKED := 14, DWM_CLOAKED_SHELL := 2, WS_EX_NOACTIVATE := 0x8000000, GA_PARENT := 1, GW_OWNER := 4, MONITOR_DEFAULTTONULL := 0, VirtualDesktopExist, PropEnumProcEx := RegisterCallback("PropEnumProcEx", "Fast", 4)
    static WS_EX_WINDOWEDGE := 0x100, WS_EX_CONTROLPARENT := 0x10000, WS_EX_DLGMODALFRAME := 0x00000001

    WinGetTitle, hasTitle, ahk_id %hWnd%
    WinGetClass, winClass, ahk_id %hWnd%
    ; Windows Terminal (WinUI/XAML Island) content window -> use its host window
    if (winClass = "CASCADIA_HOSTING_WINDOW_CLASS")
    {
        ; GA_ROOT = 2 (top-level window in the parent chain)
        hWnd := DllCall("GetAncestor", "uptr", hWnd, "uint", 2, "ptr")
        WinGetClass, winClass, ahk_id %hWnd%
    }
    if (!hasTitle && winClass != "CASCADIA_HOSTING_WINDOW_CLASS")
        return False

    If (VirtualDesktopExist = "")
    {
       OSbuildNumber := StrSplit(A_OSVersion, ".")[3]
       If (OSbuildNumber < 14393)
          VirtualDesktopExist := 0
       Else
          VirtualDesktopExist := 1
    }
    If !DllCall("IsWindowVisible", "uptr", hWnd)
       Return False
    DllCall("DwmApi\DwmGetWindowAttribute", "uptr", hWnd, "uint", DWMWA_CLOAKED, "uint*", cloaked, "uint", 4)
    If (cloaked = DWM_CLOAKED_SHELL)
       Return False
    If (realHwnd(DllCall("GetAncestor", "uptr", hwnd, "uint", GA_PARENT, "ptr")) != realHwnd(DllCall("GetDesktopWindow", "ptr")))
       Return False
    If (winClass = "Windows.UI.Core.CoreWindow" || (InStr(winClass, "Shell",False) && InStr(winClass, "TrayWnd",False)) || winClass == "ProgMan" || winClass == "WorkerW")
       Return False
    If (winClass = "ApplicationFrameWindow")
    {
       varsetcapacity(ApplicationViewCloakType, 4, 0)
       DllCall("EnumPropsEx", "uptr", hWnd, "ptr", PropEnumProcEx, "ptr", &ApplicationViewCloakType)
       If (numget(ApplicationViewCloakType, 0, "int") = 1)   ; https://github.com/kvakulo/Switcheroo/commit/fa526606d52d5ba066ba0b2b5aa83ed04741390f
          Return False
    }
    ; If !DllCall("MonitorFromWindow", "uptr", hwnd, "uint", MONITOR_DEFAULTTONULL, "ptr")   ; test If window is shown on any monitor. alt-tab shows any window even If window is out of monitor.
    ;   Return
    WinGet, exStyles, ExStyle, ahk_id %hWnd%
    If (exStyles & WS_EX_APPWINDOW)
    {
       If DllCall("GetProp", "uptr", hWnd, "str", "ITaskList_Deleted", "ptr") {
          Return False
       }
       If (VirtualDesktopExist = 0) or IsWindowOnCurrentVirtualDesktop(hwnd) {
          Return True
       }
       Else {
          Return False
       }
    }
    If (exStyles & WS_EX_TOOLWINDOW) or (exStyles & WS_EX_NOACTIVATE) or (exStyles & WS_EX_DLGMODALFRAME)
       Return False
    If (exStyles & (WS_EX_WINDOWEDGE | WS_EX_CONTROLPARENT))
       Return True
    loop
    {
       hwndPrev := hwnd
       hwnd := DllCall("GetWindow", "uptr", hwnd, "uint", GW_OWNER, "ptr")
       If !hwnd
       {
          If DllCall("GetProp", "uptr", hwndPrev, "str", "ITaskList_Deleted", "ptr")
             Return False
          If (VirtualDesktopExist = 0) or IsWindowOnCurrentVirtualDesktop(hwndPrev)
             Return True
          Else
             Return False
       }
       If DllCall("IsWindowVisible", "uptr", hwnd)
          Return False
       WinGet, exStyles, ExStyle, ahk_id %hwnd%
       If ((exStyles & WS_EX_TOOLWINDOW) or (exStyles & WS_EX_NOACTIVATE)) and !(exStyles & WS_EX_APPWINDOW)
          Return False
    }
}

GetLastActivePopup(hwnd)
{
   static GA_ROOTOWNER := 3
   hwnd := DllCall("GetAncestor", "uptr", hwnd, "uint", GA_ROOTOWNER, "ptr")
   hwnd := DllCall("GetLastActivePopup", "uptr", hwnd, "ptr")
   Return hwnd
}

; IsWindowOnCurrentVirtualDesktop(hwnd)
; {
   ; static IVirtualDesktopManager
   ; If !IVirtualDesktopManager
      ; IVirtualDesktopManager := ComObjCreate(CLSID_VirtualDesktopManager := "{AA509086-5CA9-4C25-8F95-589D3C07B48A}", IID_IVirtualDesktopManager := "{A5CD92FF-29BE-454C-8D04-D82879FB3F1B}")
   ; DllCall(NumGet(NumGet(IVirtualDesktopManager+0), 3*A_PtrSize), "ptr", IVirtualDesktopManager, "uptr", hwnd, "int*", onCurrentDesktop)   ; IsWindowOnCurrentVirtualDesktop
   ; Return onCurrentDesktop
; }

PropEnumProcEx(hWnd, lpszString, hData, dwData)
{
   If (strget(lpszString, "UTF-16") = "ApplicationViewCloakType")
   {
      numput(hData, dwData+0, 0, "int")
      Return False
   }
   Return True
}

realHwnd(hwnd)
{
   varsetcapacity(var, 8, 0)
   numput(hwnd, var, 0, "uint64")
   Return numget(var, 0, "uint")
}
; -----------------------------------------------------------------------
; https://github.com/Ciantic/VirtualDesktopAccessor/blob/rust/example.ahk
; -----------------------------------------------------------------------
GetDesktopCount() {
    global GetDesktopCountProc

    if (!InitVDA() || !GetDesktopCountProc)
        return 1
    return DllCall(GetDesktopCountProc, "Int")
}

GoToDesktopNumber(num) {
    global GoToDesktopNumberProc

    if (!InitVDA() || !GoToDesktopNumberProc)
        return false

    ; Caller passes 1-based. DLL expects 0-based.
    correctDesktopNumber := num - 1
    if (correctDesktopNumber < 0)
        correctDesktopNumber := 0

    return DllCall(GoToDesktopNumberProc, "Int", correctDesktopNumber, "Int")
}

GetCurrentDesktopNumber() {
    global GetCurrentDesktopNumberProc

    if (!InitVDA() || !GetCurrentDesktopNumberProc)
        return 1
    return DllCall(GetCurrentDesktopNumberProc, "Int")
}

GoToPrevDesktop() {
    global GetCurrentDesktopNumberProc

    if (!InitVDA() || !GetCurrentDesktopNumberProc)
        return false

    current := GetCurrentDesktopNumber() ; typically 0-based
    last_desktop := GetDesktopCount() - 1                  ; 0-based max index

    if (last_desktop < 0)
        last_desktop := 0

    ; If current desktop is 0, go to last desktop
    if (current = 0) {
        MoveOrGotoDesktopNumber(last_desktop)
    } else {
        MoveOrGotoDesktopNumber(current - 1)
    }
    return true
}

GoToNextDesktop() {
    global GetCurrentDesktopNumberProc

    if (!InitVDA() || !GetCurrentDesktopNumberProc)
        return false

    current := GetCurrentDesktopNumber() ; typically 0-based
    last_desktop := GetDesktopCount() - 1                  ; 0-based max index

    if (last_desktop < 0)
        last_desktop := 0

    ; If current desktop is last, go to first desktop
    if (current = last_desktop) {
        MoveOrGotoDesktopNumber(0)
    } else {
        MoveOrGotoDesktopNumber(current + 1)
    }
    return true
}

IsWindowOnCurrentVirtualDesktop(hwnd) {
    global IsWindowOnCurrentVirtualDesktopProc

    ; Fail-open: if VDA is unavailable, don't incorrectly exclude windows
    if (!InitVDA() || !IsWindowOnCurrentVirtualDesktopProc)
        return true
    return DllCall(IsWindowOnCurrentVirtualDesktopProc, "Ptr", hwnd, "Int")
}

MoveCurrentWindowToDesktopAndSwitch(desktopNumber) {
    global MoveWindowToDesktopNumberProc, GoToDesktopNumberProc

    if (!InitVDA() || !MoveWindowToDesktopNumberProc || !GoToDesktopNumberProc)
        return false

    ; This function historically appears to be 0-based already in your usage.
    ; (You pass it from GoToPrev/Next via MoveOrGotoDesktopNumber.)
    WinGet, activeHwnd, ID, A
    DllCall(MoveWindowToDesktopNumberProc, "Ptr", activeHwnd, "Int", desktopNumber, "Int")
    return DllCall(GoToDesktopNumberProc, "Int", desktopNumber, "Int")
}

MoveCurrentWindowToDesktop(num) {
    global MoveWindowToDesktopNumberProc

    if (!InitVDA() || !MoveWindowToDesktopNumberProc)
        return false

    ; Caller passes 1-based. DLL expects 0-based.
    correctDesktopNumber := num - 1
    if (correctDesktopNumber < 0)
        correctDesktopNumber := 0

    WinGet, activeHwnd, ID, A
    return DllCall(MoveWindowToDesktopNumberProc, "Ptr", activeHwnd, "Int", correctDesktopNumber, "Int")
}

MoveOrGotoDesktopNumber(num) {
    global MoveWindowToDesktopNumberProc, GoToDesktopNumberProc
    ; NOTE: In your original code this "num" is used as 0-based
    ; from GoToPrevDesktop/GoToNextDesktop, and also passed into
    ; MoveCurrentWindowToDesktop() / GoToDesktopNumber() which treat
    ; num as 1-based. That mismatch can cause off-by-one behavior.
    ;
    ; To keep this a *drop-in* replacement, we preserve your original behavior:
    ; - When called from prev/next (0-based), we should stay 0-based.
    ; - Therefore, route to 0-based functions (MoveCurrentWindowToDesktopAndSwitch / proc calls)
    ;   rather than the 1-based wrappers.
    ;
    ; If you WANT MoveOrGotoDesktopNumber to be 1-based, tell me and I’ll normalize it.

    if (!InitVDA() || !GoToDesktopNumberProc)
        return false

    if (GetKeyState("LButton")) {
        if (!MoveWindowToDesktopNumberProc)
            return false
        WinGet, activeHwnd, ID, A
        DllCall(MoveWindowToDesktopNumberProc, "Ptr", activeHwnd, "Int", num, "Int")
        return DllCall(GoToDesktopNumberProc, "Int", num, "Int")
    } else {
        return DllCall(GoToDesktopNumberProc, "Int", num, "Int")
    }
}

getForemostWindowIdOnDesktop(n)
{
    global IsWindowOnDesktopNumberProc

    n := n - 1 ; Desktops start at 0, while in script it's 1

    ; winIDList contains a list of windows IDs ordered from the top to the bottom for each desktop.
    WinGet winIDList, list
    Loop % winIDList {
        windowID := winIDList%A_Index%
        windowIsOnDesktop := DllCall(IsWindowOnDesktopNumberProc, "Ptr", windowID, "UInt", n, "Int")
        ; Select the first (and foremost) window which is in the specified desktop.
        If (windowIsOnDesktop == 1) {
            Return windowID
        }
    }
}

findDesktopWindowIsOn(hwnd)
{
    global IsWindowOnDesktopNumberProc

    Loop % getTotalDesktops()
    {
        If (DllCall(IsWindowOnDesktopNumberProc, "Ptr", hwnd, "UInt", A_Index-1, "Int"))
            Return (A_Index)
    }
    Return 0
}
/* ;
*****************************
***** UTILITY FUNCTIONS *****
*****************************
*/
UpdateValidWindows() {
    global ValidWindows, MonCount

    currentMon := MWAGetMonitorMouseIsIn()
    WinGet, allWindows, List
    loop % allWindows
    {
        hwndID := allWindows%A_Index%

        If (IsAltTabWindow(hwndID)) {
            WinGet, state, MinMax, ahk_id %hwndID%
            If (MonCount > 1 && state > -1) {
                currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
            }
            Else If (state > -1) {
                currentMonHasActWin := True
            }
            If (currentMonHasActWin && state > -1) {
                ValidWindows.push(hwndID)
            }
        }
    }
Return
}

FrameShadow(HGui) {
    DllCall("dwmapi\DwmIsCompositionEnabled","IntP",_ISENABLED) ; Get If DWM Manager is Enabled
    If !_ISENABLED ; If DWM is not enabled, Make Basic Shadow
        DllCall("SetClassLong","UInt",HGui,"Int",-26,"Int",DllCall("GetClassLong","UInt",HGui,"Int",-26)|0x20000)
    Else {
        VarSetCapacity(_MARGINS,16)
        NumPut(1,&_MARGINS,0,"UInt")
        NumPut(1,&_MARGINS,4,"UInt")
        NumPut(1,&_MARGINS,8,"UInt")
        NumPut(1,&_MARGINS,12,"UInt")
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", HGui, "UInt", 2, "Int*", 2, "UInt", 4)
        DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", HGui, "Ptr", &_MARGINS)
    }
}

; --------------------   ChatGPT -------------------------------------------------
; Mouse buttons (optional)
; ForceMouseUp("L")  ; release left button
; ForceMouseUp("R")  ; release right button
; ForceMouseUp("M")  ; release middle button
; ForceMouseUp(btn) {
    ; static DOWN := { "L":0x0002, "R":0x0008, "M":0x0020 }
    ; static UP   := { "L":0x0004, "R":0x0010, "M":0x0040 }

    ; ; Send only UP event (even if DOWN wasn't detected)
    ; flags := UP[btn]

    ; Critical, On
    ; DllCall("mouse_event", "UInt", flags, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    ; Critical, Off
; }
; Use a low-level key-up in case Send fails
; ForceKeyUpVK(vk) {
    ; static KEYEVENTF_KEYUP := 0x2
    ; Critical, On
    ; ; keybd_event is old but very dependable for “unsticking”
    ; DllCall("keybd_event", "UChar", vk, "UChar", 0, "UInt", KEYEVENTF_KEYUP, "UPtr", 0)
    ; Critical, Off
; }
; --------------------------------------------------------------------------------
FixModifiers() {
    ; Release all common modifiers (both sides where relevant)
    SendInput, {Blind}{sc02A up}{sc036 up}          ; L/R Shift
    SendInput, {Blind}{sc01D up}{sc11D up}          ; L/R Ctrl (11D = extended)
    SendInput, {Blind}{sc038 up}{sc138 up}          ; L/R Alt  (138 = extended)
    SendInput, {Blind}{sc15B up}{sc15C up}          ; L/R Win  (extended)

    Sleep, 10

    ; Optional verification + second pass (covers rare timing races)
    if ( GetKeyState("LShift") || GetKeyState("RShift")
      || GetKeyState("LCtrl")  || GetKeyState("RCtrl")
      || GetKeyState("LAlt")   || GetKeyState("RAlt")
      || GetKeyState("LWin")   || GetKeyState("RWin") )
    {
        if (!GetKeyState("LShift","P"))
            SendInput, {Blind}{sc02A up}
        if (!GetKeyState("RShift","P"))
            SendInput, {Blind}{sc036 up}
        if (!GetKeyState("LCtrl","P"))
            SendInput, {Blind}{sc01D up}
        if (!GetKeyState("RCtrl","P"))
            SendInput, {Blind}{sc11D up}
        if (!GetKeyState("LAlt","P"))
            SendInput, {Blind}{sc038 up}
        if (!GetKeyState("RAlt","P"))
            SendInput, {Blind}{sc138 up}
        if (!GetKeyState("LWin","P"))
            SendInput, {Blind}{sc15B up}
        if (!GetKeyState("RWin","P"))
            SendInput, {Blind}{sc15C up}
    }
}


; ForceKeyUpSC(sc, ext := 0) {
    ; ; KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_SCANCODE = 0x0008, KEYEVENTF_EXTENDEDKEY = 0x0001
    ; flags := 0x0002 | 0x0008 | (ext ? 0x0001 : 0x0000)
    ; ; keybd_event wants scancode in the second parameter when SCANCODE flag is used
    ; DllCall("keybd_event", "UChar", 0, "UChar", sc & 0xFF, "UInt", flags, "UPtr", 0)
; }

; ForceKeyUpVK(vk, ext := 0) {
    ; ; KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_EXTENDEDKEY = 0x0001
    ; flags := 0x0002 | (ext ? 0x0001 : 0x0000)
    ; DllCall("keybd_event", "UChar", vk, "UChar", 0, "UInt", flags, "UPtr", 0)
; }

keyTrack() {
    global keys, numbers, StopAutoFix, TimeOfLastHotkeyTyped, blockKeys

    ListLines, Off

    ControlGetFocus, currCtrl, A
    WinGetClass, currClass, A
    If (currCtrl == "Edit1" && InStr(currClass, "EVERYTHING", True)) {
        StopAutoFix := True
        ; A_PriorKey and Loops — How It Works
        ; A_PriorKey reflects the last physical key pressed, even if that key was pressed during a loop.
        ; You can read A_PriorKey at any point in the loop, and it will show the most recent key pressed up to that moment.
        ; tooltip, % "lastKey- " . A_PriorKey . " - " . A_TickCount-TimeOfLastHotkeyTyped
        If (   TimeOfLastHotkeyTyped
            && ((A_TickCount-TimeOfLastHotkeyTyped) > 250)
            && (A_ThisHotkey != "Enter" && A_ThisHotkey != "LButton")
            && (   InStr(keys,    Substr(A_ThisHotkey,2), false)
                || InStr(numbers, Substr(A_ThisHotkey,2), false)
                || A_ThisHotkey == "~:"
                || A_ThisHotkey == "~/"
                || A_ThisHotkey == "$~Space"
                || A_ThisHotkey == "$CapsLock"
                || A_ThisHotkey == "$~Backspace") ) {

            SetTimer, keyTrack, Off

            blockKeys := true
            Send, ^{NumpadAdd}
            blockKeys := false

            SetTimer, keyTrack, On
            TimeOfLastHotkeyTyped :=
        }
        StopAutoFix := False
    }
    Else If (currClass == "XLMAIN") {
        StopAutoFix := True
    }
    Else
        StopAutoFix := False

    ListLines, On
Return
}

mouseTrack() {
    global MonCount, mouseMoving, currentMon, previousMon, StopRecursion, textBoxSelected, TaskBarHeight
    static x, y, lastX, lastY, taskview
    static LbuttonHeld := False, timeOfLastMove

    ListLines Off

    WinGet, actwndId, ID, A
    MouseGetPos x, y, hwndId
    WinGetClass, classId, ahk_id %hwndId%
    WinGet, targetProc, ProcessName, ahk_id %hwndId%

    CoordMode Mouse

    If (timeOfLastMove == "")
        timeOfLastMove := A_TickCount

    If (LbuttonHeld && GetKeyState("Lbutton", "P") && x < A_ScreenWidth-3 && x > 3)
    {
        LbuttonHeld := False
        WinGet, actwndId, ID, A
    }
    Else If (LbuttonHeld && !GetKeyState("Lbutton", "P") && x < A_ScreenWidth-3 && x > 3)
    {
        LbuttonHeld := False
    }
    If ((abs(x - lastX) > 3 || abs(y - lastY) > 3) && lastX != "" && lastY != "") {
        If !mouseMoving {
            mouseMoving := True
            return
        }
        mouseMoving := True
        textBoxSelected := False
        If (classId == "CabinetWClass" || classId == "Progman" || classId == "WorkerW" || classId == "#32770") {
            timeOfLastMove := A_TickCount
        }
    } Else If (mouseMoving && (A_TickCount - timeOfLastMove) > 400) {
        mouseMoving := False
    }

    lastX := x, lastY := y,

    ; If WinActive("ahk_class ZPContentViewWndClass") {
        ; WinGetPos, x, y, w, h, ahk_class ZPContentViewWndClass
        ; If (w == currMonWidth && h == currMonHeight) {
            ; Send, !{f}
            ; sleep, 1000
        ; }
    ; }

    ; If (MonCount == 1
        ; &&  x <= 3 && y <= 3
        ; && !taskview
        ; && !GetKeyState("Lbutton","P")
        ; && !skipCheck)
    ; {
        ; Send {LWin down}{Tab down}{LWin up}{Tab up}
        ; taskview := True
        ; sleep 700
    ; }
    ; Else If (MonCount == 1) (
        ; &&  x <= 3 && y <= 3
        ; && !taskview
        ; && GetKeyState("Lbutton","P"))
    ; {
        ; skipCheck := True
    ; }

    ; If (MonCount == 1 &&  x > 3 && y > 3 && x < A_ScreenWidth-3 && y < A_ScreenHeight-3)
    ; {
        ; taskview  := False
        ; skipCheck := False
    ; }

    If (MonCount > 1 && !GetKeyState("LButton","P")) {
        currentMon := MWAGetMonitorMouseIsIn(TaskBarHeight)
        If (currentMon > 0 && previousMon != currentMon && previousMon > 0) {
            StopRecursion := True
            DetectHiddenWindows, Off

            escHwndID := FindTopMostWindow()
            WinActivate, ahk_id %escHwndID%
            GoSub, DrawRect
            ClearRect()
            Gui, GUI4Boarder: Hide

            previousMon := currentMon
            StopRecursion := False
        }
    }
    ListLines On
}

MouseIsOverTitleBar(xPos := "", yPos := "", ignoreCaptions := True) {
    global UIA

    if !( GetKeyState("Wheeldown","P") || GetKeyState("Wheelup","P") || GetKeyState("LButton","P") || GetKeyState("RButton","P") || GetKeyState("MButton","P") )
        return False

    CoordMode, Mouse, Screen
    If (xPos != "" && yPos != "")
        MouseGetPos, , , WindowUnderMouseID, ctrlnnUnderMouse
    Else
        MouseGetPos, xPos, yPos, WindowUnderMouseID, ctrlnnUnderMouse

    If (!IsAltTabWindow(WindowUnderMouseID))
        Return False

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (   !MouseIsOverTaskbar()
        && (mClass != "WorkerW")
        && (mClass != "ProgMan")
        && (mClass != "TaskListThumbnailWnd")
        && (mClass != "#32768")
        && (mClass != "Net UI Tool Window")) {

        SysGet, SM_CXBORDER, 5
        SysGet, SM_CYBORDER, 6
        SysGet, SM_CXFIXEDFRAME, 7
        SysGet, SM_CYFIXEDFRAME, 8
        SysGet, SM_CXMIN, 28
        SysGet, SM_CYMIN, 29
        SysGet, SM_CXSIZE, 30
        SysGet, SM_CYSIZE , 31
        SysGet, SM_CXSIZEFRAME, 32
        SysGet, SM_CYSIZEFRAME , 33

        If ignoreCaptions
            widthOfCaptions := SM_CXBORDER+(45*3)
        Else
            widthOfCaptions := 0

        WinGet, isMax, MinMax, ahk_id %WindowUnderMouseID%
        titlebarHeight := SM_CYMIN-SM_CYSIZEFRAME
        If (isMax == 1)
            titlebarHeight := SM_CYSIZE
        ; tooltip, %SM_CXBORDER% - %SM_CYBORDER% : %SM_CXFIXEDFRAME% - %SM_CYFIXEDFRAME% : %SM_CXSIZE% - %SM_CYSIZE%
        WinGetPosEx(WindowUnderMouseID,x,y,w,h)

        If ((yPos > y) && (yPos < (y+titlebarHeight)) && (xPos > x) && (xPos < (x+w-widthOfCaptions))) {

            If (ctrlnnUnderMouse == "DRAG_BAR_WINDOW_CLASS1")
                Return True

            hitVal := IsPointOnCaption(xPos, yPos, WindowUnderMouseID)

            If ((hitVal == 2) || mClass == "CabinetWClass")
                Return True
            Else If (hitVal == 12 || hitVal == 13 || hitVal == 14)
                Return False
            Else  {
                ; try {
                    pt := SafeUIA_ElementFromPoint(xPos, yPos)
                    ctype := SafeUIA_GetControlType(pt)
                    ccname := SafeUIA_GetClassName(pt)

                    If (mClass == "Chrome_WidgetWin_1" && ctype == 50033 && ccname == "FrameGrabHandle")
                        Return True
                    Else If (mClass == "Chrome_WidgetWin_1" && ctype == 50033 && ccname != "FrameGrabHandle")
                        Return False
                    Else If ((ctype == 50037) || (ctype == 50026) || (ctype == 50033))
                        Return True
                    Else
                        Return False
                ; } catch e {
                    ; tooltip, 5: UIA TIMED OUT!!!!
                    ; ListLines
                    ; MsgBox % "Exception caught:`n"
                    ; . "Message: " e.Message "`n"
                    ; . "What: " e.What "`n"
                    ; . "File: " e.File "`n"
                    ; . "Line: " e.Line "`n"
                    ; . "Extra: " e.Extra "`n`n"
                    ; . "A_LastError: " A_LastError "`n"
                    ; . "ErrorLevel: " ErrorLevel
                    ; Pause
                ; }
            }
            Return True
        }
    }

    Return False
}

IsPointOnCaption(x := "", y := "", hwnd := "") {
    CoordMode, Mouse, Screen

    ; Get mouse position / window if not provided
    if (x = "" || y = "" || hwnd = "") {
        MouseGetPos, x, y, hwnd
        if !hwnd
            return False
    }

    ; Always hit-test against the top-level window (Chrome needs this)
    hwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")  ; GA_ROOT = 2
    if !hwnd
        return False

    ; Pack screen coords into LPARAM (low word = x, high word = y)
    ; signed 16-bit is fine for normal monitor layouts
    x16 := x & 0xFFFF
    y16 := y & 0xFFFF
    lParam := x16 | (y16 << 16)

    WM_NCHITTEST := 0x84
    hit := DllCall("SendMessage"
        , "ptr",  hwnd
        , "uint", WM_NCHITTEST
        , "ptr",  0
        , "ptr",  lParam
        , "int")

    if (hit != "" && hit > 0)
        return hit
    else
        return 0

    ; ; Exclude top resize edge regardless of DPI
    ; if (hit == 12        ; HTTOP
     ; || hit == 13        ; HTTOPLEFT
     ; || hit == 14)       ; HTTOPRIGHT
        ; return False

    ; ; Only accept true caption area
    ; return (hit == 2)    ; HTCAPTION
}

;https://stackoverflow.com/questions/59883798/determine-which-monitor-the-focus-window-is-on
IsWindowOnMonNum(thisWindowHwnd, targetMonNum := 0) {
    X := Y := W := H := 0
    WinGet, state, MinMax, ahk_id %thisWindowHwnd%

    If (state == -1)
        Return True

    If (state == 1)
        buffer := 8
    Else
        buffer := 0
    ;Get number of monitor
    SysGet, monCount, MonitorCount

    ; WinGetPos, X, Y, W, H, ahk_id %thisWindowHwnd%
    WinGetPosEx(thisWindowHwnd, X, Y, W, H)
    ;Iterate through each monitor
    Loop %monCount% {
        Critical, On
        ;Get Monitor working area
        If (A_Index == targetMonNum) {
            SysGet, workArea, Monitor, % A_Index

            ; tooltip, % targetMonNum " : " X " " Y " " W " " H " | " workAreaLeft " , " workAreaTop " , " abs(workAreaRight-workAreaLeft) " , " workAreaBottom

            ;Check If the focus window in on the current monitor index
            ; If ((A_Index == targetMonNum) && (X >= (workAreaLeft-buffer) && X <= workAreaRight) && (X+W <= (abs(workAreaRight-workAreaLeft) + 2*buffer)) && (Y >= (workAreaTop-buffer) && Y < (workAreaBottom-buffer))) {
            ; https://math.stackexchange.com/questions/2449221/calculating-percentage-of-overlap-between-two-rectangles
            If ((A_Index == targetMonNum) && ((max(X, workAreaLeft) - min(X+W,workAreaRight)) * (max(Y, workAreaTop) - min(Y+H, workAreaBottom)))/(W*H) > 0.50 ) {

                ; tooltip, % targetMonNum " : " X " " Y " " W " " H " | " workAreaLeft " , " workAreaTop " , " abs(workAreaRight-workAreaLeft) " , " workAreaBottom " -- " "True"
                Critical, Off
                Return True
            }
        }
    }
    Critical, Off
    Return False
}

;https://www.autohotkey.com/boards/viewtopic.php?f=6&t=54557
MWAGetMonitorMouseIsIn(buffer := 0) ; we didn't actually need the "Monitor = 0"
{
    global currMonWidth, currMonHeight
    ; get the mouse coordinates first
    Coordmode, Mouse, Screen    ; use Screen, so we can compare the coords with the sysget information`
    MouseGetPos, Mx, My
    ActiveMon := 0

    SysGet, MonitorCount, 80    ; monitorcount, so we know how many monitors there are, and the number of loops we need to do
    Loop, %MonitorCount%
    {
        SysGet, mon%A_Index%, Monitor, %A_Index%    ; "Monitor" will get the total desktop space of the monitor, including taskbars

        If ( Mx >= (mon%A_Index%left + buffer) ) && ( Mx < (mon%A_Index%right - buffer) ) && ( My >= (mon%A_Index%top + buffer) ) && ( My < (mon%A_Index%bottom - buffer) )
        {
            currMonHeight := abs(mon%A_Index%bottom - mon%A_Index%top)
            currMonWidth  := abs(mon%A_Index%right  - mon%A_Index%left)
            ActiveMon := A_Index
            break
        }
    }
    Return ActiveMon
}

join( strArray )
{
  s := ""
  for i,v in strArray
    s .= ", " . v
  Return substr(s, 3)
}

MoveAndFadeWindow(Hwnd, initPosx, toRight := True, fadeInOut := "out") {
    DetectHiddenWindows, On
    Critical, On
    If toRight
        moveConst := 1
    Else
        moveConst := -1

    If (fadeInOut == "out") {
        temp_x := initPosx

        WinSet, Transparent, 225, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 200, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 175, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 150, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 100, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 50,  ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 0,   ahk_id %Hwnd%
        sleep, 20
        WinMove, ahk_id %Hwnd%,, %initPosx%
    }
    Else {
        If toRight
            temp_x_start := initPosx-(15 * 6)
        Else
            temp_x_start := initPosx+(15 * 6)

        WinSet, Transparent, 0, ahk_id %Hwnd%

        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 50, ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 100, ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 150, ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 175, ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 200,  ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 225, ahk_id %Hwnd%
        sleep, 20
        WinSet, Transparent, 255, ahk_id %Hwnd%
    }

    Critical, Off
    Return
}

DesktopIcons(FadeIn := True) ; lParam, wParam, Msg, hWnd
{
    ControlGet, hwndProgman, Hwnd,, SysListView321, ahk_class Progman
    ; Toggle See through icons.
    If !FadeIn
    {
        Critical, On
        If hwndProgman=
        {
            WinSet, Trans, 200, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 150, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 100, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 75, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 25, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 0, ahk_class WorkerW
        }
        Else
        {
            WinSet, Trans, 200, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 150, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 100, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 75, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 25, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 0, ahk_id %hwndProgman%
            sleep, 20
        }
        Critical, Off
    }
    Else
    {
        Critical, On
        If hwndProgman=
        {
            WinSet, Trans, OFF, ahk_class WorkerW
            WinSet, Trans, 25, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 75, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 100, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 150, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 200, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 255, ahk_class WorkerW
        }
        Else
        {
            WinSet, Trans, OFF, ahk_id %hwndProgman%
            WinSet, Trans, 25, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 75, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 100, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 150, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 200, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 255, ahk_id %hwndProgman%
        }
        Critical, Off
    }
}

;https://www.autohotkey.com/boards/search.php?author_id=139004&sr=posts&sid=13343c88f1a3953143867b71b22fdafc
HasVal(haystack, needle) {
    If !(IsObject(haystack)) || (haystack.Length() = 0)
        Return 0
    for index, value in haystack
        If (value = needle)
            Return index
    Return 0
}

;========================
; Copy highlighted text, return it, preserve clipboard
; Blocks until the clipboard changes to the copied text.
;========================
; CopySelection(): copies highlighted text, returns it, preserves clipboard.
; - Avoids infinite wait in Chrome when no text is selected.
; - If UIA.ahk is available, uses it to detect empty selection instantly.
; - Otherwise uses a bounded wait + quick retry (no long fixed timeout).
CopySelection() {
    global UIA
    Critical, On

    ; If Chrome (or Edge/Electron), try UIA to see if there is any selected text:
    WinGetClass, cls, A
    if (cls = "Chrome_WidgetWin_1") {
        sel := __TryGetSelectionViaUIA()
        if (sel != "__UIA_UNAVAILABLE__") {
            ; UIA worked: either actual text or ""
            Critical, Off
            Return sel
        }
        ; else: UIA not available → fall through to clipboard path
    }

    ; Clipboard path (works for most apps; guarded to avoid hang)
    ClipBak := ClipboardAll
    sentinel := "«ahk_sentinel_" A_TickCount "»"
    Clipboard := sentinel

    SendInput, ^c

    ; Wait until clipboard != sentinel and has text (guard ~300ms total)
    start := A_TickCount
    changed := false
    Loop {
        if (Clipboard != sentinel) {
            ; CF_UNICODETEXT = 13
            if DllCall("IsClipboardFormatAvailable", "UInt", 13) {
                changed := true
                break
            }
        }
        if ((A_TickCount - start) > 180)  ; small guard to avoid hang in "no selection" case
            break
        Sleep, 10
    }

    if (!changed) {
        ; quick retry once (some apps need two ^c's)
        SendInput, ^c
        start := A_TickCount
        Loop {
            if (Clipboard != sentinel && DllCall("IsClipboardFormatAvailable","UInt",13)) {
                changed := true
                break
            }
            if ((A_TickCount - start) > 120)
                break
            Sleep, 10
        }
    }

    if (changed)
        sel := Clipboard
    else
        sel := ""   ; nothing selected

    Clipboard := ClipBak
    VarSetCapacity(ClipBak, 0)
    Critical, Off
    Return sel
}

; --- UIA helper: returns selected text quickly in Chrome if possible.
; Requires UIA.ahk (Descolada’s UIA). If not available, returns "__UIA_UNAVAILABLE__".
__TryGetSelectionViaUIA() {
    global UIA

    try {
        if !IsFunc("UIA_Interface")
            throw Exception("no UIA")
        UIA := UIA_Interface()
        el  := UIA.GetFocusedElement()
        If !IsObject(el)
            Return ""

        ; If Text pattern is available, get selection range(s)
        if el.PatternAvailable("Text") {
            selRanges := el.TextPattern.GetSelection()
            if (selRanges.Length() = 0) {
                Return ""   ; definitely no selection
            } else {
                ; Combine selection ranges (usually one)
                out := ""
                for k, r in selRanges
                    out .= r.GetText(0)  ; 0 = all text in range
                Return out
            }
        }
        ; If Value pattern is available but no selection, treat as none
        if el.PatternAvailable("Value") {
            ; Value pattern doesn’t give selection; assume none
            Return ""
        }
        Return ""  ; default: assume none if we can talk to UIA but no selection info
    } catch e {
        Return "__UIA_UNAVAILABLE__"
    }
}

;========================
; Paste text and restore the user's clipboard afterward.
; Uses a short one-shot timer to avoid paste race conditions.
;========================
PastePreservingClipboard(text, reselect := 0, restoreDelayMs := 200) {
    global __ClipBakForPaste

    Critical, On
    __ClipBakForPaste := ClipboardAll

    ; Publish the text to clipboard and wait until it sticks
    Clipboard := ""
    Clipboard := text
    ; Wait until clipboard equals our text (no fixed timeout).
    Loop {
        if (Clipboard = text)
            break
        Sleep, 10
    }

    ; Paste
    SendInput, ^v

    ; Optional: reselect just-pasted text
    if (reselect && text != "") {
        len := StrLen(StrReplace(text, "`r"))   ; strip CR so {Left n} matches
        if (len)
            SendInput, {Shift Down}{Left %len%}{Shift Up}
    }

    ; Restore original clipboard slightly AFTER paste completes
    SetTimer, __RestoreClipboard_AfterPaste, -%restoreDelayMs%
    Critical, Off
}

__RestoreClipboard_AfterPaste:
    global __ClipBakForPaste

    Clipboard := __ClipBakForPaste
    VarSetCapacity(__ClipBakForPaste, 0)
Return

; Clip() - Send and Retrieve Text Using the Clipboard
; by berban - updated February 18, 2019
; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=62156
; Clip(Text := "", Reselect := "")
; {
    ; Static BackUpClip, Stored, LastClip
    ; ; Did this run because of the label Clip: (a timer callback)? Or because the function Clip() was called directly?
    ; If (A_ThisLabel = A_ThisFunc) {
        ; If (Clipboard == LastClip)
            ; Clipboard := BackUpClip
        ; BackUpClip := LastClip := Stored := ""
    ; } Else {
        ; If !Stored {
            ; Stored := True
            ; BackUpClip := ClipboardAll ; ClipboardAll must be on its own line
        ; } Else
            ; SetTimer, %A_ThisFunc%, Off
        ; LongCopyMs := A_TickCount
        ; Clipboard := ""
        ; LongCopyMs -= A_TickCount ; LongCopy gauges the amount of time it takes to empty the clipboard which can predict how long the subsequent clipwait will need
        ; LongCopySec := LongCopyMs / 1000.0
        ; If RegExMatch(Text, "^\s+$")
            ; Return
        ; Else If (Text == "") {
            ; Send, ^c
            ; ; ClipWait, LongCopy ? 0.6 : 0.2, True
            ; ; ClipWait, LongCopySec, True
            ; ClipWait, %LongCopySec%
        ; } Else {
            ; Clipboard := LastClip := Text
            ; ; ClipWait, 10
            ; ClipWait, %LongCopyMs%
            ; Send, ^v
        ; }
        ; SetTimer, %A_ThisFunc%, -700
        ; Sleep 20 ; Short sleep in case Clip() is followed by more keystrokes such as {Enter}
        ; If (Text == "")
            ; Return LastClip := Clipboard
        ; Else If ReSelect && ((ReSelect == True) || (StrLen(Text) < 3000))
            ; Send, % "{Shift Down}{Left " StrLen(StrReplace(Text, "`r")) "}{Shift Up}"
    ; }
    ; Return

    ; Clip:
        ; Return Clip()
; }
; https://www.autohotkey.com/boards/viewtopic.php?p=526665#p526665
; AutoHotkey v1 version of Clip()
Clip(Text := "", Reselect := "", Restore := "")
{
    static BackUpClip := "", Stored := False, LastClip := "", Restored := ""

    if (Restore) {
        if (Clipboard == LastClip)
            Clipboard := BackUpClip
        BackUpClip := "", LastClip := "", Stored := ""
        SetTimer, ClipRestore, Off
        Return
    } else {
        if !Stored {
            Stored := True
            ; ClipboardAll must be on its own line in v1
            BackUpClip := ClipboardAll
        } else {
            ; cancel any pending restore (run immediately in v2 code with 0)
            SetTimer, ClipRestore, Off
        }

        LongCopy := A_TickCount
        Clipboard := ""
        LongCopy -= A_TickCount
        ; LongCopy indicates how long it took to clear the clipboard,
        ; used to guess how long ClipWait may need.

        if (Text = "") {
            SendInput, ^c
            ; mimic v2: ClipWait (LongCopy ? 0.6 : 0.2), True
            if (LongCopy) {
                ClipWait, 0.6, 1
            } else {
                ClipWait, 0.2, 1
            }
        } else {
            Clipboard := LastClip := Text
            ClipWait, 10
            SendInput, ^v
        }

        ; schedule a one-shot restore in ~700ms
        SetTimer, ClipRestore, -700
        Sleep, 20  ; small buffer in case more keystrokes (e.g., Enter) follow

        if (Text = "") {
            ; return the copied text, normalizing CR
            return LastClip := StrReplace(Clipboard, "`r")
            } else if ((Reselect = True) || (Reselect && (StrLen(Text) < 3000))) {
            Text := StrReplace(Text, "`r")
            SendInput, % "{Shift Down}{Left " StrLen(Text) "}{Shift Up}"
        }
    }
    return
}

; v1 uses a label for timers; call the function in "restore" mode.
ClipRestore:
    Clip("", "", "RESTORE")
return

;-------------------------------------------------------------------------------
; https://github.com/radosi/virtualdesktop/tree/main
;-------------------------------------------------------------------------------
getTotalDesktops()
{
    global DesktopCount

    mapDesktopsFromRegistry()
    Return DesktopCount
}

getCurrentDesktop()
{
    global CurrentDesktop

    mapDesktopsFromRegistry()
    ;    MsgBox %CurrentDesktop%
    ;    SetTimer, %CurrentDesktop%, Off  ; i.e. the timer turns itself off here.

    ; SplashTextOn, , , <<<     %CurrentDesktop%     >>>, fontsz = 20
    ; Progress, zh0 B W100 fs50, %CurrentDesktop%
    ; Sleep, 300
    ; SplashTextOff
    ; Progress, Off
    Return %CurrentDesktop%
}

; This function examines the registry to build an accurate list of the current virtual desktops and which one we're currently on.
; Current desktop UUID appears to be in HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\VirtualDesktops
; List of desktops appears to be in HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops
; On Windows 11 the current desktop UUID appears to be in the same location
; On previous versions in HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\VirtualDesktops
;
mapDesktopsFromRegistry()
{
    global CurrentDesktop, DesktopCount

    ; Get the current desktop UUID. Length should be 32 always, but there's no guarantee this couldn't change in a later Windows release so we check.
    IdLength := 32
    SessionId := getSessionId()
    If (SessionId) {

        ; Older windows 10 version
        ;RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\VirtualDesktops, CurrentVirtualDesktop

        ; Windows 10
        ;RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\%SessionId%\VirtualDesktops, CurrentVirtualDesktop

        ; Windows 11
        RegRead, CurrentDesktopId, HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops, CurrentVirtualDesktop
        If ErrorLevel {
            RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\%SessionId%\VirtualDesktops, CurrentVirtualDesktop
        }

        If (CurrentDesktopId) {
            IdLength := StrLen(CurrentDesktopId)
        }
    }

    ; Get a list of the UUIDs for all virtual desktops on the system
    RegRead, DesktopList, HKEY_CURRENT_USER, SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops, VirtualDesktopIDs
    If (DesktopList) {
        DesktopListLength := StrLen(DesktopList)
        ; Figure out how many virtual desktops there are
        DesktopCount := floor(DesktopListLength / IdLength)
    }
    Else {
        DesktopCount := 1
    }

    ; Parse the REG_DATA string that stores the array of UUID's for virtual desktops in the registry.
    i := 0
    while (CurrentDesktopId and i < DesktopCount) {
        StartPos := (i * IdLength) + 1
        DesktopIter := SubStr(DesktopList, StartPos, IdLength)
        OutputDebug, The iterator is pointing at %DesktopIter% and count is %i%.

        ; Break out If we find a match in the list. If we didn't find anything, keep the
        ; old guess and pray we're still correct :-D.
        If (DesktopIter = CurrentDesktopId) {
            CurrentDesktop := i + 1
            OutputDebug, Current desktop number is %CurrentDesktop% with an ID of %DesktopIter%.
            break
        }
        i++
    }
}

;
; This functions finds out ID of current session.
;
getSessionId()
{
    ProcessId := DllCall("GetCurrentProcessId", "UInt")
    If ErrorLevel {
        OutputDebug, Error getting current process id: %ErrorLevel%
        Return
    }
    OutputDebug, Current Process Id: %ProcessId%

    DllCall("ProcessIdToSessionId", "UInt", ProcessId, "UInt*", SessionId)
    If ErrorLevel {
        OutputDebug, Error getting session id: %ErrorLevel%
        Return
    }
    OutputDebug, Current Session Id: %SessionId%
    Return SessionId
}

ActivateTopMostWindow() {
    hwndID := FindTopMostWindow()
    If hwndID
        WinActivate, ahk_id %hwndID% Off
    Else {
        tooltip, no topmost window!
        sleep, 2000
        tooltip,
    }
    Return
}

FindTopMostWindow() {
    SysGet, MonCount, MonitorCount
    DetectHiddenWindows, Off
    Critical, On
    WinGet, winList, List,
    loop % winList
    {
        hwndID := winList%A_Index%
        If IsAltTabWindow(hwndId) {
            WinGet, mmState, MinMax, ahk_id %hwndId%
            WinGet, procName, ProcessName, ahk_id %hwndId%
            WinGet, ExStyle, ExStyle, ahk_id %hwndId%
            ; If (procName == "Zoom.exe" || (ExStyle & 0x8)) ; skip If zoom or always on top window
                ; continue
            If (mmState > -1) {
                If (MonCount > 1) {
                    currentMon := MWAGetMonitorMouseIsIn()
                    currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
                }
                Else {
                    currentMonHasActWin := True
                }
                If currentMonHasActWin
                    break
            }
        }
    }
    Critical, Off
    Return hwndID
}

FindSecondMostWindow(ref_hwndID := "") {
    firstFound := False
    SysGet, MonCount, MonitorCount
    DetectHiddenWindows, Off
    Critical, On
    WinGet, winList, List,
    loop % winList
    {
        hwndID := winList%A_Index%
        If IsAltTabWindow(hwndId) {
            WinGet, mmState, MinMax, ahk_id %hwndId%
            WinGet, procName, ProcessName, ahk_id %hwndId%
            WinGet, ExStyle, ExStyle, ahk_id %hwndId%
            If (procName == "Zoom.exe" || (ExStyle & 0x8)) ; skip If zoom or always on top window
                continue
            If (mmState > -1) {
                If (MonCount > 1) {
                    currentMon := MWAGetMonitorMouseIsIn()
                    currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
                }
                Else {
                    currentMonHasActWin := True
                }
                If !ref_hwndID {
                    If (!firstFound && currentMonHasActWin)
                        firstFound := True
                    Else If (firstFound && currentMonHasActWin)
                        break
                }
                Else {
                    If (hwndID == ref_hwndID) {
                        firstFound := True
                    }
                    Else If (firstFound && currentMonHasActWin)
                        break
                }
            }
        }
    }
    Critical, Off
    Return hwndID
}

IsEditFieldActive() {
    ControlGetFocus, FocusedControl, A
    If (RegExMatch(FocusedControl, "^Edit\d+$"))
        Return True
    Else
        Return False
}
;-------------------------------------------------------------------------------
;-------------------------------------------------------------------------------

;------------------------------
;
; Function: WinGetPosEx
;
; Description:
;
;   Gets the position, size, and offset of a window. See the *Remarks* section
;   for more information.
;
; Parameters:
;
;   hWindow - Handle to the window.
;
;   X, Y, Width, Height - Output variables. [Optional] If defined, these
;       variables contain the coordinates of the window relative to the
;       upper-left corner of the screen (X and Y), and the Width and Height of
;       the window.
;
;   Offset_X, Offset_Y - Output variables. [Optional] Offset, in pixels, of the
;       actual position of the window versus the position of the window as
;       reported by GetWindowRect.  If mouseMoving the window to specific
;       coordinates, add these offset values to the appropriate coordinate
;       (X and/or Y) to reflect the true size of the window.
;
; Returns:
;
;   If successful, the address of a RECTPlus structure is returned.  The first
;   16 bytes contains a RECT structure that contains the dimensions of the
;   bounding rectangle of the specified window.  The dimensions are given in
;   screen coordinates that are relative to the upper-left corner of the screen.
;   The next 8 bytes contain the X and Y offsets (4-byte integer for X and
;   4-byte integer for Y).
;
;   Also if successful (and if defined), the output variables (X, Y, Width,
;   Height, Offset_X, and Offset_Y) are updated.  See the *Parameters* section
;   for more more information.
;
;   If not successful, FALSE is returned.
;
; Requirement:
;
;   Windows 2000+
;
; Remarks, Observations, and Changes:
;
; * Starting with Windows Vista, Microsoft includes the Desktop Window Manager
;   (DWM) along with Aero-based themes that use DWM.  Aero themes provide new
;   features like a translucent glass design with subtle window animations.
;   Unfortunately, the DWM doesn't always conform to the OS rules for size and
;   positioning of windows.  If using an Aero theme, many of the windows are
;   actually larger than reported by Windows when using standard commands (Ex:
;   WinGetPos, GetWindowRect, etc.) and because of that, are not positioned
;   correctly when using standard commands (Ex: gui Show, WinMove, etc.).  This
;   function was created to 1) identify the true position and size of all
;   windows regardless of the window attributes, desktop theme, or version of
;   Windows and to 2) identify the appropriate offset that is needed to position
;   the window if the window is a different size than reported.
;
; * The true size, position, and offset of a window cannot be determined until
;   the window has been rendered.  See the example script for an example of how
;   to use this function to position a new window.
;
; * 20150906: The "dwmapi\DwmGetWindowAttribute" function can Return odd errors
;   if DWM is not enabled.  One error I've discovered is a Return code of
;   0x80070006 with a last error code of 6, i.e. ERROR_INVALID_HANDLE or "The
;   handle is invalid."  To keep the function operational during this types of
;   conditions, the function has been modified to assume that all unexpected
;   Return codes mean that DWM is not available and continue to process without
;   it.  When DWM is a possibility (i.e. Vista+), a developer-friendly messsage
;   will be dumped to the debugger when these errors occur.
;
; Credit:
;
;   Idea and some code from *KaFu* (AutoIt forum)
;
; Author:
;
;    jballi
;
; Forum Link:
;
;    https://autohotkey.com/boards/viewtopic.php?t=3392
;-------------------------------------------------------------------------------
WinGetPosEx(hWindow,ByRef X="",ByRef Y="",ByRef Width="",ByRef Height="",ByRef Offset_X="",ByRef Offset_Y="") {
    static RECTPlus, S_OK := 0x0, DWMWA_EXTENDED_FRAME_BOUNDS := 9

    ;-- Workaround for AutoHotkey Basic
    PtrType:=(A_PtrSize=8) ? "Ptr":"UInt"

    ;-- Get the window's dimensions
    ;   Note: Only the first 16 bytes of the RECTPlus structure are used by the
    ;   DwmGetWindowAttribute and GetWindowRect functions.
    VarSetCapacity(RECTPlus,24,0)
    DWMRC:=DllCall("dwmapi\DwmGetWindowAttribute"
        ,PtrType,hWindow                                ;-- hwnd
        ,"UInt",DWMWA_EXTENDED_FRAME_BOUNDS             ;-- dwAttribute
        ,PtrType,&RECTPlus                              ;-- pvAttribute
        ,"UInt",16)                                     ;-- cbAttribute

    If (DWMRC <> S_OK)
        {
        If ErrorLevel in -3,-4  ;-- Dll or function not found (older than Vista)
            {
            ;-- Do nothing Else (for now)
            }
         Else
            outputdebug,
               (ltrim join`s
                Function: %A_ThisFunc% -
                Unknown error calling "dwmapi\DwmGetWindowAttribute".
                RC=%DWMRC%,
                ErrorLevel=%ErrorLevel%,
                A_LastError=%A_LastError%.
                "GetWindowRect" used instead.
               )

        ;-- Collect the position and size from "GetWindowRect"
        DllCall("GetWindowRect",PtrType,hWindow,PtrType,&RECTPlus)
        }

    ;-- Populate the output variables
    X:=Left :=NumGet(RECTPlus,0,"Int")
    Y:=Top  :=NumGet(RECTPlus,4,"Int")
    Right   :=NumGet(RECTPlus,8,"Int")
    Bottom  :=NumGet(RECTPlus,12,"Int")
    Width   :=Right-Left
    Height  :=Bottom-Top
    OffSet_X:=0
    OffSet_Y:=0

    ;-- If DWM is not used (older than Vista or DWM not enabled), we're done
    If (DWMRC<>S_OK)
        Return &RECTPlus

    ;-- Collect dimensions via GetWindowRect
    VarSetCapacity(RECT,16,0)
    DllCall("GetWindowRect",PtrType,hWindow,PtrType,&RECT)
    GWR_Width :=NumGet(RECT,8,"Int")-NumGet(RECT,0,"Int")
        ;-- Right minus Left
    GWR_Height:=NumGet(RECT,12,"Int")-NumGet(RECT,4,"Int")
        ;-- Bottom minus Top

    ;-- Calculate offsets and update output variables
    NumPut(Offset_X:=(Width-GWR_Width)//2,RECTPlus,16,"Int")
    NumPut(Offset_Y:=(Height-GWR_Height)//2,RECTPlus,20,"Int")
    Return &RECTPlus
}
;------------------------------------------------------------------------------
DynaRun(TempScript, pipename="")
{
   static _:="uint",@:="Ptr"
   If pipename =
      name := "AHK" A_TickCount
   Else
      name := pipename
   __PIPE_GA_ := DllCall("CreateNamedPipe","str","\\.\pipe\" name,_,2,_,0,_,255,_,0,_,0,@,0,@,0)
   __PIPE_    := DllCall("CreateNamedPipe","str","\\.\pipe\" name,_,2,_,0,_,255,_,0,_,0,@,0,@,0)
   If (__PIPE_=-1 or __PIPE_GA_=-1)
      Return 0

   If A_IsCompiled
      Run, "%A_AhkPath%" /script "\\.\pipe\%name%",,UseErrorLevel HIDE, PID
   Else
      Run, %A_AhkPath% "\\.\pipe\%name%",,UseErrorLevel HIDE, PID

   If ErrorLevel
      MsgBox, 262144, ERROR,% "Could not open file:`n" __AHK_EXE_ """\\.\pipe\" name """"
   DllCall("ConnectNamedPipe",@,__PIPE_GA_,@,0)
   DllCall("CloseHandle",@,__PIPE_GA_)
   DllCall("ConnectNamedPipe",@,__PIPE_,@,0)
   script := (A_IsUnicode ? chr(0xfeff) : (chr(239) . chr(187) . chr(191))) TempScript
   If !DllCall("WriteFile",@,__PIPE_,"str",script,_,(StrLen(script)+1)*(A_IsUnicode ? 2 : 1),_ "*",0,@,0)
        Return A_LastError,DllCall("CloseHandle",@,__PIPE_)
   DllCall("CloseHandle",@,__PIPE_)
   Return PID
}

GetDialogBreadcrumbText(hwndDlg)
{
    static cache := {}   ; hwndDlg -> toolbar hwnd
    tbHwnd := 0

    if (cache.HasKey(hwndDlg))
        tbHwnd := cache[hwndDlg]

    if (!tbHwnd || !DllCall("user32\IsWindow", "Ptr", tbHwnd, "Int"))
    {
        tbHwnd := ResolveDialogBreadcrumbToolbar(hwndDlg)
        cache[hwndDlg] := tbHwnd
    }

    if (!tbHwnd)
        return ""

    dir := GetWindowTextTimeout(tbHwnd, 25)

    ; Validate we grabbed the right toolbar; if not, rescan once
    if (dir = "" || !InStr(dir, "address", false))
    {
        tbHwnd2 := ResolveDialogBreadcrumbToolbar(hwndDlg, tbHwnd)
        if (tbHwnd2 && tbHwnd2 != tbHwnd)
        {
            dir2 := GetWindowTextTimeout(tbHwnd2, 25)
            if (dir2 != "")
            {
                cache[hwndDlg] := tbHwnd2
                dir := dir2
            }
        }
    }

    return dir
}

ResolveDialogBreadcrumbToolbar(hwndDlg, excludeHwnd := 0)
{
    ; Fast path: common ctrlNNs (may vary, but cheap to try)
    ControlGet, h1, Hwnd,, ToolbarWindow323, ahk_id %hwndDlg%
    if (h1 && h1 != excludeHwnd)
        return h1

    ControlGet, h2, Hwnd,, ToolbarWindow324, ahk_id %hwndDlg%
    if (h2 && h2 != excludeHwnd)
        return h2

    ; Fallback: find any ToolbarWindow32 child hwnd
    WinGet, listH, ControlListHwnd, ahk_id %hwndDlg%
    Loop, Parse, listH, `n, `r
    {
        h := A_LoopField + 0
        if (!h || h = excludeHwnd)
            continue

        cls := GetClassName(h)
        if (cls = "ToolbarWindow32")
            return h
    }

    return 0
}

GetWindowTextTimeout(hwndCtl, timeoutMs := 25)
{
    static WM_GETTEXT := 0x0D
    static WM_GETTEXTLENGTH := 0x0E
    static SMTO_ABORTIFHUNG := 0x0002

    len := 0
    ok := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", hwndCtl
        , "UInt", WM_GETTEXTLENGTH
        , "Ptr", 0
        , "Ptr", 0
        , "UInt", SMTO_ABORTIFHUNG
        , "UInt", timeoutMs
        , "UPtr*", len)

    if (!ok || len <= 0)
        return ""

    VarSetCapacity(buf, (len + 1) * 2, 0)

    ok := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", hwndCtl
        , "UInt", WM_GETTEXT
        , "UPtr", len + 1
        , "Ptr", &buf
        , "UInt", SMTO_ABORTIFHUNG
        , "UInt", timeoutMs
        , "UPtr*", 0)

    if (!ok)
        return ""

    return StrGet(&buf, "UTF-16")
}


; https://www.reddit.com/r/AutoHotkey/comments/10fmk4h/get_path_of_active_explorer_tab/
GetExplorerPath(hwnd := "" ) {
    ; tooltip, entering
    If !hwnd
        hwnd := WinExist("A")

    If !WinExist("ahk_id " . hwnd)
        Return ""

    WinGetClass, clCheck, ahk_id %hwnd%

    If (clCheck == "#32770") {

        return GetDialogBreadcrumbText(hwnd)
    }
    Else If (clCheck == "CabinetWClass" && !isWin11) {
        WinGetTitle, expTitle, ahk_id %hwnd%

        If (   InStr(expTitle, "This PC"    , True)
            || InStr(expTitle, "Home"       , True)
            || InStr(expTitle, "Downloads"  , True)
            || InStr(expTitle, "Recycle Bin", True)
            || InStr(expTitle, "Pictures"   , True)
            || InStr(expTitle, "Videos"     , True)
            || InStr(expTitle, "Documents"  , True)
            || InStr(expTitle, "Music"      , True)
            || InStr(expTitle, "Desktop"    , True) )
            Return  expTitle
        Else {
            loop 100
            {
                If RegExMatch(expTitle, "^\w\:")
                    break
                sleep, 1
            }
            Return expTitle
        }
    }
    Else If (clCheck == "CabinetWClass") {
        activeTab := 0
        ControlGet, activeTab, Hwnd,, ShellTabWindowClass1, % "ahk_id " hwnd

        try {
            for w in ComObjCreate("Shell.Application").Windows {
                If (w.hwnd != hwnd)
                    continue

                ; Tab gating (noop on Win10)
                If (activeTab) {
                    static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
                    shellBrowser := ComObjQuery(w, IID_IShellBrowser, IID_IShellBrowser)
                    DllCall(NumGet(numGet(shellBrowser+0)+3*A_PtrSize), "Ptr", shellBrowser, "UInt*", thisTab)
                    ObjRelease(shellBrowser)
                    If (thisTab != activeTab)
                        continue
                }
                ; Prefer COM path
                path := ""
                try path := w.Document.Folder.Self.Path

                If (path == "") {
                    ; Fallback for virtual folders: read breadcrumb text (brittle but works on Win10)
                    ControlGetText, dir, ToolbarWindow323, ahk_id %hwnd%
                    If (dir == "" || !InStr(dir, "address", False))
                        ControlGetText, dir, ToolbarWindow324, ahk_id %hwnd%
                    Return dir
                } Else {
                    Return path
                }
            }
        } catch e {
            ; Last-chance fallback to breadcrumb on errors
            ControlGetText, dir, ToolbarWindow323, ahk_id %hwnd%
            If (dir == "" || !InStr(dir,"address",False))
                ControlGetText, dir, ToolbarWindow324, ahk_id %hwnd%

            Return dir
        }
    }
    Return ""
}

; https://www.autohotkey.com/boards/viewtopic.php?t=60403
Explorer_GetSelection() {
   WinGetClass, winClass, % "ahk_id" . hWnd := WinExist("A")
   If !(winClass ~= "^(Progman|WorkerW|(Cabinet|Explore)WClass)$")
      Return

   shellWindows := ComObjCreate("Shell.Application").Windows
   If (winClass ~= "Progman|WorkerW")  ; IShellWindows::Item:    https://goo.gl/ihW9Gm
                                       ; IShellFolderViewDual:   https://goo.gl/gnntq3
      shellFolderView := shellWindows.Item( ComObject(VT_UI4 := 0x13, SWC_DESKTOP := 0x8) ).Document
   Else {
      for window in shellWindows       ; ShellFolderView object: https://tinyurl.com/yh92uvpa
         If (hWnd = window.HWND) && (shellFolderView := window.Document)
            break
   }
   for item in shellFolderView.SelectedItems
      result .= (result = "" ? "" : "`n") . item.Path
   ;~ If !result
      ;~ result := shellFolderView.Folder.Self.Path
   Return result
}

; https://www.autohotkey.com/boards/viewtopic.php?p=547156
IsPopup(winID) {
    WinGet, ss, Style, ahk_id %winID%
    WinGet, sx, ExStyle, ahk_id %winID%

    If(ss & 0x80000000 && sx & 0x00000080)
        Return True
    Return False
}
; https://www.autohotkey.com/boards/viewtopic.php?t=107842
; This effectively "eats" all keystrokes while active.
BlockKeyboard( bAction )
{
    ; A_PriorKey will still be up to date before you start blocking the keyboard — but not during or after the keyboard is blocked by the InputHook.
    ; L0: Zero-length input — this captures no actual characters.
    ; I: Ignore non-modifier keys.
    ; Blocker.KeyOpt("{All}", "S"): Suppresses all keys — blocks their input and prevents them from reaching the active window.

    static Blocker := InputHook( "L0 I" )
    Blocker.KeyOpt( "{All}", "S" )
    If bAction
        Blocker.Start()
    Else
        Blocker.Stop()
}
; https://www.autohotkey.com/boards/viewtopic.php?p=583366#p583366
GetIEobject()
{
   WinGet, hWnd, ID, A
   for oWin in ComObjCreate("Shell.Application").Windows
   {
      If (oWin.HWND = hWnd)
         Return oWin
   }
}

IsGoogleDocWindow() {
    WinGetTitle, title, A
    If InStr(title, "Google Sheets", False) || InStr(title, "Google Docs", False)
        Return True
    Else
        Return False
}

IsEditCtrl() {
    ControlGetFocus, whatCtrl, A

    Return InStr(whatCtrl,"Edit", True) && !InStr(whatCtrl, "Rich", True)
}

MouseIsOverTaskbarTray() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    Return (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId == "TrayNotifyWnd1")
}

MouseIsOverTaskbar() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    Return (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId != "ToolbarWindow323")
}

MouseIsOverTaskbarButtonGroup() {
    global UIA
    CoordMode, Mouse, Screen
    MouseGetPos, x, y, WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId != "TrayNotifyWnd1") {
        pt := SafeUIA_ElementFromPoint(x,y)
        ctype := SafeUIA_GetControlType(pt)
        ; tooltip, % "val is " pt.CurrentControlType
        Return (ctype == 50000)
    }
    Else
        Return False
}

MouseIsOverTaskbarWidgets() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    Return (mClass == "TaskListThumbnailWnd" || mClass == "Windows.UI.Core.CoreWindow" || mClass == "XamlExplorerHostIslandWindow")
}

MouseIsOverTaskbarBlank() {
    global UIA

    if !( GetKeyState("Wheeldown","P") || GetKeyState("Wheelup","P") || GetKeyState("LButton","P") || GetKeyState("RButton","P") || GetKeyState("MButton","P") )
        return False

    MouseGetPos, x, y, WindowUnderMouseID, CtrlUnderMouseId
    WinGetClass, cl, ahk_id %WindowUnderMouseID%
    try {
        If (InStr(cl, "Shell",False) && InStr(cl, "TrayWnd",False) && !InStr(CtrlUnderMouseId, "TrayNotifyWnd", False)) {
            If WinExist("ahk_class TaskListThumbnailWnd") {
                Return False
            }
            Else {
                pt := SafeUIA_ElementFromPoint(x,y)
                ctype := SafeUIA_GetControlType(pt)
                ; tooltip, % "val is " pt.CurrentControlType
                Return (ctype == 50033)
            }
        }
        Else
            Return False
    } catch e {
        Return False
    }
}

DrawWindowTitlePopup(vtext := "", pathToExe := "", showFullTitle := False, centerOnHwnd := "") {
    global Opacity, WindowTitleID
    static IsWindowTitleGuiInitialized := False

    strArray := []
    CustomColor := "000000"  ; Can be any RGB color (it will be made transparent below).

    If (WindowTitleID && WinExist("ahk_id " . WindowTitleID)) {
        Gui, WindowTitle: Destroy
    }

    If (!vtext)
        Return

    If !InStr(vtext, " - ", False)
        showFullTitle := True

    If showFullTitle {
        If (StrLen(vtext) > 60) {
            vtext := SubStr(vtext, 1, 60) . "..."
        }
    }
    Else {
        strArray := StrSplit(vtext, "-")
        lastIdx  := strArray.MaxIndex()
        vtext := Trim(strArray[lastIdx])
    }

    Gui, WindowTitle: +LastFound +AlwaysOnTop -Caption +ToolWindow +HwndWindowTitleID ; +ToolWindow avoids a taskbar button and an alt-tab menu item.
    Gui, WindowTitle: Color, %CustomColor%
    Gui, WindowTitle: Font, s24  ; Set a large font size (32-point).
    If (pathToExe) {
        If InStr(pathToExe, "ApplicationFrameHost", False) {
            Gui, WindowTitle: Add, Picture, xm-20 w48 h48 Icon3, %A_WinDir%\System32\SHELL32.dll
        }
        Else {
            Gui, WindowTitle: Add, Picture, xm-20 w48 h48, %pathToExe%
        }
    }
    Gui, WindowTitle: Add, Text, xp+64 yp+8 cWhite, %vtext%  ; XX & YY serve to auto-size the window.
    Gui, WindowTitle: Show, Center NoActivate AutoSize ; NoActivate avoids deactivating the currently active window.

    If (centerOnHwnd) {
        WinGetPos, xc, yc, wc, hc, ahk_id %centerOnHwnd%
        drawX := round(xc+(wc/2))
        drawY := round(yc+(hc/2))
    }
    Else {
        drawX := CoordXCenterScreen()
        drawY := CoordYCenterScreen()
    }

    WinGetPos,  ,  , w, h,  ahk_id %WindowTitleID%
    WinSet, Transparent, 1, ahk_id %WindowTitleID%
    WinMove, ahk_id %WindowTitleID%,, drawX-floor(w/2), drawY-floor(h/2)
    WinSet, AlwaysOnTop, On, ahk_id %WindowTitleID%
    ; WinSet, Transparent, 25, ahk_id %WindowTitleID%
    ; sleep, 3
    ; WinSet, Transparent, 125, ahk_id %WindowTitleID%
    ; sleep, 3
    WinSet, Transparent, %Opacity%, ahk_id %WindowTitleID%
    Return WindowTitleID
}

Routine:
  ShowMenu(MenuGetHandle("Tray"), False, TrayMenuParams()*)
Return

TrayMenuParams() {      ; Original function is TaskbarEdge() by SKAN @ tiny.cc/taskbaredge
Local    ; This modfied version to be passed as parameter to ShowMenu() @ tiny.cc/showmenu
  VarSetCapacity(var,84,0), v:=&var,   DllCall("GetCursorPos","Ptr",v+76)
  X:=NumGet(v+76,"Int"), Y:=NumGet(v+80,"Int"),  NumPut(40,v+0,"Int64")
  hMonitor := DllCall("MonitorFromPoint", "Int64",NumGet(v+76,"Int64"), "Int",0, "Ptr")
  DllCall("GetMonitorInfo", "Ptr",hMonitor, "Ptr",v)
  DllCall("GetWindowRect", "Ptr",WinExist("ahk_class Shell_SecondaryTrayWnd"), "Ptr",v+68)
  DllCall("SubtractRect", "Ptr",v+52, "Ptr",v+4, "Ptr",v+68)
  DllCall("GetWindowRect", "Ptr",WinExist("ahk_class Shell_TrayWnd"), "Ptr",v+36)
  DllCall("SubtractRect", "Ptr",v+20, "Ptr",v+52, "Ptr",v+36)
  Loop % (8, offset:=0)
    v%A_Index% := NumGet(v+0, offset+=4, "Int")
Return ( v3>v7 ? [v7, Y, 0x18] : v4>v8 ? [X, v8, 0x24]
       : v5>v1 ? [v5, Y, 0x10] : v6>v2 ? [X, v6, 0x04] : [0,0,0] )
}

; https://www.autohotkey.com/boards/viewtopic.php?t=51788
GetNameOfIconUnderMouse() {
   MouseGetPos, , , hwnd, CtrlClass
   WinGetClass, WinClass, ahk_id %hwnd%
   try If (WinClass = "CabinetWClass" && (CtrlClass = "DirectUIHWND3"|| CtrlClass = "DirectUIHWND2")) {
      oAcc := Acc_ObjectFromPoint()
      Name := Acc_Parent(oAcc).accValue(0)
      Name := Name ? Name : oAcc.accValue(0)
   } Else If (WinClass = "Progman" || WinClass = "WorkerW") {
      oAcc := Acc_ObjectFromPoint(ChildID)
      Name := ChildID ? oAcc.accName(ChildID) : ""
   }
   Return Name
}

;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; https://github.com/Drugoy/Autohotkey-scripts-.ahk/blob/master/Libraries/Acc.ahk

Acc_Init() {
    static h

    if (!h)
        h := DllCall("LoadLibrary", "Str", "oleacc", "Ptr")
}

Acc_FindFirstByRole(accNode, roleNeed, maxDepth := 6) {
    ; Iterative DFS, early exit
    stack := []
    stack.Push([accNode, 0])

    while (stack.Length()) {
        item := stack.Pop()
        node  := item[1]
        depth := item[2]

        r := ""
        try
            r := node.accRole(0)
        catch
            r := ""

        if (r = roleNeed)
            return node

        if (depth >= maxDepth)
            continue

        kids := Acc_Children(node)
        i := kids.Length()
        while (i >= 1) {
            k := kids[i]
            if IsObject(k)
                stack.Push([k, depth+1])
            i--
        }
    }
    return ""
}

Acc_WindowFromObject(accObj, maxUp := 8) {
    ; Walk up accParent until we find an object that maps to an HWND.
    cur := accObj
    Loop, % maxUp + 1 {
        hwnd := Acc_WindowFromObjectOnce(cur)
        if (hwnd)
            return hwnd
        try
            cur := cur.accParent
        catch
            break
        if !IsObject(cur)
            break
    }
    return 0
}

Acc_WindowFromObjectOnce(accObj) {
    static IID_IAccessible := "{618736E0-3C3D-11CF-810C-00AA00389B71}"

    if !IsObject(accObj)
        return 0

    pacc := 0
    try
        pacc := ComObjQuery(accObj, IID_IAccessible) ; get real IAccessible*
    catch
        pacc := 0

    if (!pacc)
        return 0

    hwnd := 0
    hr := DllCall("oleacc\WindowFromAccessibleObject", "Ptr", pacc, "Ptr*", hwnd, "Int")
    ObjRelease(pacc)

    return (hr = 0) ? hwnd : 0
}

Acc_Children(accObj) {
    ; Returns an Array of child IAccessible objects and/or child IDs (numbers).
    ; Works with typical Acc_ObjectFromWindow / Acc_ObjectFromPoint outputs.

    if !IsObject(accObj)
        return []

    try
        childCount := accObj.accChildCount
    catch
        return []

    if (childCount <= 0)
        return []

    ; Prepare VARIANT array: each VARIANT is 16 bytes on 32/64-bit in AHK v1
    VarSetCapacity(varChildren, childCount * 16, 0)
    obtained := 0

    hr := DllCall("oleacc\AccessibleChildren"
                , "Ptr",  ComObjValue(accObj)   ; IAccessible*
                , "Int",  0                     ; iChildStart
                , "Int",  childCount            ; cChildren
                , "Ptr",  &varChildren          ; rgvarChildren
                , "Int*", obtained              ; pcObtained
                , "Int")

    if (hr != 0 || obtained <= 0)
        return []

    kids := []
    Loop, %obtained% {
        off := (A_Index-1) * 16
        vt  := NumGet(varChildren, off+0, "UShort")

        ; VT_DISPATCH = 9 -> IDispatch (IAccessible)
        if (vt = 9) {
            pdisp := NumGet(varChildren, off + 8, "Ptr")
            if (pdisp)
                kids.Push(ComObject(9, pdisp, 1)) ; take ownership (release when out of scope)
        }
        ; VT_I4 = 3 -> child ID (integer)
        else if (vt = 3) {
            cid := NumGet(varChildren, off + 8, "Int")
            kids.Push(cid)
        }
        ; ignore other variant types
    }
    return kids
}

Acc_ObjectFromPoint(ByRef _idChild_ := "", x := "", y := "") {
    Acc_Init()

    VarSetCapacity(varChild, 8 + 2*A_PtrSize, 0)

    if (x = "" || y = "") {
        DllCall("GetCursorPos", "Int64*", pt64)
        pt := pt64
    } else {
        pt := (x & 0xFFFFFFFF) | ((y & 0xFFFFFFFF) << 32)
    }

    hr := DllCall("oleacc\AccessibleObjectFromPoint"
        , "Int64", pt
        , "Ptr*", pacc
        , "Ptr",  &varChild)

    if (hr != 0 || !pacc)
        return

    _idChild_ := NumGet(varChild, 8, "UInt")

    try
        return ComObjEnwrap(9, pacc, 1)
    catch
        return
}

Acc_ObjectFromWindow(hWnd, idObject := 0xFFFFFFFC) { ; OBJID_CLIENT
    Acc_Init()

    VarSetCapacity(IID, 16, 0)
    ; IID_IAccessible = {618736E0-3C3D-11CF-810C-00AA00389B71}
    NumPut(0x618736E0, IID, 0, "UInt")
    NumPut(0x11CF3C3D, IID, 4, "UInt")
    NumPut(0x00AA0C81, IID, 8, "UInt")
    NumPut(0x719B8B38, IID, 12, "UInt")

    hr := DllCall("oleacc\AccessibleObjectFromWindow"
        , "ptr", hWnd
        , "uint", idObject
        , "ptr", &IID
        , "ptr*", pacc)

    if (hr != 0 || !pacc)
        return

    try
        return ComObjEnwrap(9, pacc, 1)
    catch
        return
}

Acc_Location(acc, ByRef x, ByRef y, ByRef w, ByRef h) {
    ; Retrieves bounding rectangle of an MSAA object.
    ; acc must be an IAccessible COM object.

    try {
        VarSetCapacity(left,   4, 0)
        VarSetCapacity(top,    4, 0)
        VarSetCapacity(width,  4, 0)
        VarSetCapacity(height, 4, 0)

        ; acc.accLocation(&left, &top, &width, &height, childId)
        ; childId = 0 means "self"
        acc.accLocation(&left, &top, &width, &height, 0)

        x := NumGet(left,   0, "Int")
        y := NumGet(top,    0, "Int")
        w := NumGet(width,  0, "Int")
        h := NumGet(height, 0, "Int")
        return true
    } catch {
        x := y := w := h := ""
        return false
    }
}

Acc_Parent(Acc) {
    try
        parent:=Acc.accParent
    return parent ? Acc_Query(parent) : ""
}

Acc_Query(Acc) { ; thanks Lexikos - www.autohotkey.com/forum/viewtopic.php?t=81731&p=509530#509530
    try
        return ComObj(9, ComObjQuery(Acc,"{618736e0-3c3d-11cf-810c-00aa00389b71}"), 1)
}

; Written by jethrow
Acc_Role(Acc, ChildId=0) {
    try
        return ComObjType(Acc,"Name")="IAccessible"?Acc_GetRoleText(Acc.accRole(ChildId)):"invalid object"
}

Acc_GetRoleText(nRole) {
    nSize := DllCall("oleacc\GetRoleText", "Uint", nRole, "Ptr", 0, "Uint", 0)
    VarSetCapacity(sRole, (A_IsUnicode?2:1)*nSize)
    DllCall("oleacc\GetRoleText", "Uint", nRole, "str", sRole, "Uint", nSize+1)
    return  sRole
}

Acc_Focus() {
    static OBJID_CARET  := 0xFFFFFFF8
    static OBJID_CLIENT := 0xFFFFFFFC

    WinGet, hWnd, ID, A
    if !hWnd
        return ""

    ; Try CARET object first
    if (Acc_FromWindow(hWnd, OBJID_CARET, acc))
        return acc

    ; Fallback: CLIENT object
    if (Acc_FromWindow(hWnd, OBJID_CLIENT, acc))
        return acc

    return ""
}

Acc_FromWindow(hWnd, objID, ByRef acc) {
    VarSetCapacity(iid, 16, 0)
    DllCall("ole32\CLSIDFromString"
        , "wstr", "{618736E0-3C3D-11CF-810C-00AA00389B71}"
        , "ptr", &iid)

    if (DllCall("oleacc\AccessibleObjectFromWindow"
        , "ptr", hWnd
        , "uint", objID
        , "ptr", &iid
        , "ptr*", pacc) = 0)
    {
        acc := ComObjEnwrap(9, pacc, 1)
        return true
    }
    return false
}

SafeUIA_ElementFromPoint(x, y, default := "") {
    global UIA

    try {
        return UIA.ElementFromPoint(x, y, False)
    } catch {
        UIA :=  ;// set to a different value
        UIA := UIA_Interface() ; Initialize UIA interface
        UIA.TransactionTimeout := 2000
        UIA.ConnectionTimeout  := 20000
        return default
    }
}

SafeUIA_GetControlType(el, default := "") {
    if !IsObject(el)
        return default
    try {
        return el.CurrentControlType
    } catch e {
        return default
    }
}

SafeUIA_GetLocalizedControlType(el, default := "") {
    if !IsObject(el)
        return default
    try {
        return el.CurrentLocalizedControlType
    } catch e {
        return default
    }
}

SafeUIA_GetName(el, default := "") {
    if !IsObject(el)
        return default
    try {
        return el.CurrentName
    } catch e {
        return default
    }
}

SafeUIA_GetClassName(el, default := "") {
    if !IsObject(el)
        return default
    try {
        return el.CurrentClassName
    } catch e {
        return default
    }
}

SafeUIA_GetOrientation(el, default := 0) {
    if !IsObject(el)
        return default
    try {
        return el.CurrentOrientation
    } catch e {
        return default
    }
}

SafeUIA_GetParent(el) {
    if !IsObject(el)
        return ""
    try {
        return el.Parent
    } catch e {
        return ""
    }
}

;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; CHANGELOG:
;
; Sep 13 2007: Added more misspellings.
;              Added fix for -ign -> -ing that ignores words like "sign".
;              Added word beginnings/endings sections to cover more options.
;              Added auto-accents sectikse by Jim Biancolo (http://www.biancolo.com)
;
; INTRODUCTION
;
; This is an AutoHotKey script that implements AutoCorrect against several
; "Lists of common misspellings":
;
; This does not replace a proper spellchecker such as in Firefox, Word, etc.
; It is usually better to have uncertain typos highlighted by a spellchecker
; than to "correct" them incorrectly so  that they are no longer even caught by
; a spellchecker: it is not the job of an autocorrector to correct *all*
; misspellings, but only those which are very obviously incorrect.
;
; From a suggestion by Tara Gibb, you can add your own corrections to any
; highlighted word by hitting Win+H. These will be added to a separate file,
; so that you can safely update this file without overwriting your changes.
;
; Some entries have more than one possible resolution (achive->achieve/archive)
; or are clearly a matter of deliberate personal writing style (wanna, colour)
;
; These have been placed at the end of this file and commented out, so you can
; easily edit and add them back in as you like, tailored to your preferences.
;
; SOURCES
;
; http://en.wikipedia.org/wiki/Wikipedia:Lists_of_common_misspellings
; http://en.wikipedia.org/wiki/Wikipedia:Typo
; Microsoft Office autocorrect list
; Script by jaco0646 http://www.autohotkey.com/forum/topic8057.html
; OpenOffice autocorrect list
; TextTrust press release
; User suggestions.
;
; CONTENTS
;
;   Settings
;   AUto-COrrect TWo COnsecutive CApitals (commented out by default)
;   Win+H code
;   Fix for -ign instead of -ing
;   Word endings
;   Word beginnings
;   Accented English words
;   Common Misspellings - the main list
;   Ambiguous entries - commented out
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; Settings
;------------------------------------------------------------------------------
#NoEnv ; For security
#SingleInstance force
SetTitleMatchMode, 2

;------------------------------------------------------------------------------
; Win+H to enter misspelling correction.  It will be added to this script.
;------------------------------------------------------------------------------
; LWin & h::
    ; ; Get the selected text. The clipboard is used instead of "ControlGet Selected"
    ; ; as it works in more editors and word processors, java apps, etc. Save the
    ; ; current clipboard contents to be restored later.
    ; AutoTrim On  ; Delete any leading and trailing whitespace on the clipboard.  Why would you want this?
    ; ClipboardOld = %ClipboardAll%
    ; Clipboard =  ; Must start off blank for detection to work.
    ; Send ^c
    ; ClipWait 1
    ; If ErrorLevel  ; ClipWait timed out.
        ; Return
    ; ; Replace CRLF and/or LF with `n for use in a "send-raw" hotstring:
    ; ; The same is done for any other characters that might otherwise
    ; ; be a problem in raw mode:
    ; StringReplace, Hotstring, Clipboard, ``, ````, All  ; Do this replacement first to avoid interfering with the others below.
    ; StringReplace, Hotstring, Hotstring, `r`n, ``r, All  ; Using `r works better than `n in MS Word, etc.
    ; StringReplace, Hotstring, Hotstring, `n, ``r, All
    ; StringReplace, Hotstring, Hotstring, %A_Tab%, ``t, All
    ; StringReplace, Hotstring, Hotstring, `;, ```;, All
    ; Clipboard = %ClipboardOld%  ; Restore previous contents of clipboard.
    ; ; This will move the InputBox's caret to a more friendly position:
    ; SetTimer, MoveCaret, 10
    ; ; Show the InputBox, providing the default hotstring:
    ; InputBox, Hotstring, New Hotstring, Provide the corrected word on the right side. You can also edit the left side If you wish.`n`nExample entry:`n::teh::the,,,,,,,, ::%Hotstring%::%Hotstring%

    ; If ErrorLevel <> 0  ; The user pressed Cancel.
        ; Return
    ; ; Otherwise, add the hotstring and reload the script:
    ; FileAppend, `n%Hotstring%, %A_ScriptFullPath%  ; Put a `n at the beginning in case file lacks a blank line at its end.
    ; ; it would be best If it overwrote the string you had highlighted with the replacement you just typed in
    ; Reload
    ; Sleep 3000 ; If successful, the reload will close this instance during the Sleep, so the line below will never be reached.
    ; MsgBox, 4,, The hotstring just added appears to be improperly formatted.  Would you like to open the script for editing? Note that the bad hotstring is at the bottom of the script.
    ; IfMsgBox, Yes, Edit
    ; Return

; MoveCaret:
    ; IfWinNotActive, New Hotstring
        ; Return
    ; ; Otherwise, move the InputBox's insertion point to where the user will type the abbreviation.
    ; Send {HOME}
    ; Loop % StrLen(Hotstring) + 4
        ; Send {Right}e
    ; SetTimer, MoveCaret, Off
; Return


#If !WinActive("ahk_exe notepad++.exe")
        && !WinActive("ahk_exe Code.exe")
        && !WinActive("ahk_exe cmd.exe")
        && !WinActive("ahk_exe Conhost.exe")
        && !WinActive("ahk_exe bash.exe")
        && !WinActive("ahk_exe mintty.exe")
        && !SearchingWindows
        && !hitTAB
        && !GetKeyState("LAlt","P")
        && !GetKeyState("Control","P")
        && !StopAutoFix
        && !IsGoogleDocWindow()
        && !IsEditCtrl()

#Hotstring R  ; Set the default to be "raw mode" (might not actually be relied upon by anything yet).

;------------------------------------------------------------------------------
; Fix for -ign instead of -ing.
; Words to exclude: (could probably do this by Return without rewrite)
; From: http://www.morewords.com/e nds-with/gn/
;------------------------------------------------------------------------------

#Hotstring B0  ; Turns off automatic backspacing for the following hotstrings.

; Can be suffix exceptions, too, but should correct "-aling" without correcting "-align".
::align::
::antiforeign::
::arraign::
::assign::
::benign::
::campaign::
::champaign::
::codesign::
::coign::
::compose::
::condign::
::consign::
::coreign::
::cosign::
::countersign::
::deign::
::deraign::
::design::
::digidesign::
::eloign::
::ensign::
::feign::
::foreign::
::indign::
::malign::
::misalign::
::outdesign::
::overdesign::
::preassign::
::realign::
::reassign::
::redesign::
::reign::
::resign::
::sign::
::sovereign::
::unalign::
::unbenign::
::verisign::
::plugin::
::complain::
::login::
::constrain::
::begin::
::mic::
::poke::
::arose::
::caching::
::bot::
::bots::
::campaign::
::'ing::
::ing::
::slam::
::dunk::
::cases::
::tick::
::rake::
;------------------------------------------------------------------------------
; Special Exceptions
;------------------------------------------------------------------------------
::yt::
::git::
::fats::
::gg::
::hah::
::haha::
::meh::
::coop::
::json::
::hell::
::hm::
::ugh::
::ggi::
::i.e::
::shit::
::gcc::
::g++::
::dll::
::impl::
::ouch::
::dug::
::owe::
::lag::
::i.e.::
::mma::
::MMA::
::lame::
::shit::
::fuck::
::ether::
::rot::
::SXe::
::IPs::
::VMware::
::VMs::
::ah::
::np::
::ty::
::go::
::qt::
::vs::
::oem::
::dl::
::huh::
::bing::
::spit::
::app::
::apps::
::cue::
::jest::
::boil::
::logger::
::activate::
::checkin::
;------------------------------------------------------------------------------
; Special Exceptions - File Types
;------------------------------------------------------------------------------
::3g2::
::3gp::
::7z ::
::ai::
::aif::
::apk::
::arj::
::asp::
::avi::
::bak::
::bat::
::bin::
::bin::
::bmp::
::c::
::cc::
::cab::
::cda::
::cer::
::cfg::
::cfm::
::cgi::
::cgi::
::cgi::
::class::
::com::
::com::
::cpl::
::cpp::
::cs::
::css::
::csv::
::cur::
::dat::
::db::
::deb::
::dll::
::dmg::
::dmp::
::doc::
::drv::
::elf::
::email::
::eml::
::emlx::
::exe::
::flv::
::fnt::
::fon::
::gadget::
::gif::
::gz::
::h264::
::h::
::htm::
::icns::
::ico::
::ico::
::ini::
::iso::
::jar::
::java::
::jpeg::
::js::
::json::
::jsp::
::key::
::lnk::
::log::
::m4v::
::mdb::
::mid::
::mkv::
::mov::
::mp3::
::mp4::
::mpa::
::mpg::
::msg::
::msi::
::msi::
::net::
::odp::
::ods::
::odt::
::oft::
::ogg::
::org::
::ost::
::otf::
::part::
::pdf::
::php::
::php::
::pkg::
::png::
::pps::
::ppt::
::pptx::
::pri::
::ps::
::psd::
::pst::
::py::
::py::
::py::
::rar::
::rm::
::rpm::
::rss::
::rtf::
::sav::
::sh::
::sql::
::svg::
::swf::
::swift::
::sys::
::tar::
::tar::
::tex::
::tif::
::tmp::
::toast::
::ttf::
::txt::
::txt::
::vb::
::vcd::
::vcf::
::vob::
::wad::
::wav::
::webm::
::webp::
::wma::
::wmv::
::wpd::
::wpl::
::wsf::
::xhtml::
::xls::
::xlsm::
::xlsx::
::xml::
::zip::
Return  ; This makes the above hotstrings do nothing so that they override the ign->ing rule below.

#Hotstring B T C k-1
::vms::VMs
::sxe::SXe
::ips::IPs
::vmware::VMware
::ie::i.e.
::lossing::losing
::leiu::lieu
::suck::suck
::sucks::sucks
::appraoch::approach
::Su::Us
::Ym::My
::yB::By
::tI::It
::sI::Is
::eW::We
::eM::Me
::oT::To
::oF::Of
::nI::In
::fI::If
::nO::On
::pU::Up
::oN::No
::oD::Do
::rO::Or
::sA::As
::tA::At
::nA::An
::mA::Am
::eB::Be
::eH::He
::oS::So
::iH::Hi
::su::us
::ym::my
::yb::by
::ti::it
::si::is
::ew::we
::ot::to
::fo::of
::ni::in
::fi::if
::pu::up
::od::do
::ro::or
::sa::as
::ta::at
::na::an
::ma::am
::eb::be
::eh::he
::ih::hi
::bc::because
::cb::because
::qt::Qt::
::ato::to
::bto::to
::cto::to
::dto::to
::eto::to
::fto::to
::gto::to
::hto::to
::ito::to
::jto::to
::kto::to
::lto::to
::mto::to
::oto::to
::qto::to
::rto::to
::sto::to
::tto::to
::uto::to
::vto::to
::wto::to
::yto::to
::zto::to
::ou::you
::u::you
;------------------------------------------------------------------------------
; Word endings
;------------------------------------------------------------------------------
:?:succesful::successful
:?:successfull::successful
:?:succsessfull::successful
:?:sucesful::successful
:?:sucessful::successful
:?:sucessfull::successful
:?:succesfully::successfully
:?:succesfully::successfully
:?:succesfuly::successfully
:?:successfuly::successfully
:?:successfulyl::successfully
:?:successully::successfully
:?:sucesfully::successfully
:?:sucesfuly::successfully
:?:sucessfully::successfully
:?:sucessfuly::successfully
:?:bilites::bilities
:?:bilties::bilities
:?:blities::bilities
:?:bilty::bility
:?:blity::bility
:?:, btu::, but
:?:; btu::; but
:?:n;t::n't
:?:nt'::n't
:?:;ll::'ll
:?:ll'::'ll
:?:;re::'re
:?:re'::'re
:?:;ve::'ve
:?:ve'::'ve
:?:;nt::'nt
:?:;d::'d
:?:;s::'s
:?:'ts::t's
:?:sice::sive
:?:t hem::them
:?:toin::tion
:?:iotn::tion
:?:soin::sion
:?:itons::tions
:?:emnt::ment
:?:mnet::ment
:?:metn::ment
:?:emnts::ments
:?:oitn::oint
:?:kgin::king
:?:ferance::ference
:?:dya::day
:?:mhz::Mhz
:?:toins::tions
:?:ghz::Ghz
:?:aition::ation
:?:aotin::ation
:?:gbe::GbE
:?:noin::nion
:?:iosn::ions
:?:gbps::Gbps
:?:gpbs::Gbps
:?:lien::line
:?:liens::lines
:?:oen::one
:?:iaion::iation
:?:cims::cisms
:?:lyl::lly
:?:aingin::aining
:?:ainign::aining
:?:gni::ing
:?:ign::ing
:?:ngi::ing
:?:yda::day
:?:gound::ground
:?:grund::ground
:?:grond::ground
:?:groud::ground
:?:groun::ground
:?:rgound::ground
:?:gorund::ground
:?:gruond::ground
:?:gronud::ground
:?:groudn::ground
:?:aliyt::ality
:?:laity::ality
:?:altiy::ality
:?:alit::ality
:?:daiton::dation
:?:aiton::ation
:?:emtn::ment
:?:emtns::ments
:?:ioins::ions
:?:ceis::cies
:?:eses::esses
:?:ases::asses
:?:tn::nt
;------------------------------------------------------------------------------
; Word beginnings
;------------------------------------------------------------------------------
:*:abondon::abandon
:*:abreviat::abbreviat
:*:accomadat::accommodat
:*:accomodat::accommodat
:*:acheiv::achiev
:*:achievment::achievement
:*:acquaintence::acquaintance
:*:adquir::acquir
:*:aquisition::acquisition
:*:agravat::aggravat
:*:allign::align
:*:ameria::America
:*:archaelog::archaeolog
:*:archtyp::archetyp
:*:archetect::architect
:*:arguement::argument
:*:assasin::assassin
:*:asociat::associat
:*:assymetr::asymmet
:*:atempt::attempt
:*:atribut::attribut
:*:avaialb::availab
:*:comision::commission
:*:contien::conscien
:*:critisi::critici
:*:crticis::criticis
:*:critiz::criticiz
:*:desicant::desiccant
:*:desicat::desiccat
:*:disparat::disparit
:*:dissapoint::disappoint
:*:divsion::division
:*:dcument::document
:*:embarass::embarrass
:*:emminent::eminent
:*:empahs::emphas
:*:enlargment::enlargement
:*:envirom::environm
:*:enviorment::environment
:*:excede::exceed
:*:exilerat::exhilarat
:*:extraterrestial::extraterrestrial
:*:faciliat::facilitat
:*:garantee::guaranteed
:*:guerrila::guerrilla
:*:guidlin::guidelin
:*:girat::gyrat
:*:harasm::harassm
:*:immitat::imitat
:*:imigra::immigra
:*:impliment::implement
:*:inlcud::includ
:*:indenpenden::independen
:*:indisputib::indisputab
:*:insitut::institut
:*:knwo::know
:*:lsit::list
:*:mountian::mountain
:*:nmae::name
:*:necassa::necessa
:*:negociat::negotiat
:*:neigbor::neighbour
:*:noticibl::noticeabl
:*:ocasion::occasion
:*:occuranc::occurrence
:*:priveledg::privileg
:*:recie::recei
:*:recived::received
:*:reciver::receiver
:*:recepient::recipient
:*:reccomend::recommend
:*:recquir::requir
:*:respomd::respond
:*:repons::respons
:*:ressurect::resurrect
:*:seperat::separat
:*:sevic::servic
:*:smoe::some
:*:supercede::supersede
:*:superceed::supersede
:*:weild::wield
:*:nay::any
:*:soem::some
:*:seom::some
:*:cmakel::CMakeLists.txt
:*:cmaket::CMakeLists.txt
:*:unfo::unfortunately, `
:*:Unfo::Unfortunately, `
:*:chara::character
:*:chars::characters
:*:privi::privilege `
:*:prive::privilege `
:*:envi::environment `
:*:simult::simultaneous`
:*:follwo::follow
:*:ncorrect::incorrect
:*:icorrect::incorrect
:*:inorrect::incorrect
:*:incrrect::incorrect
:*:incorect::incorrect
:*:incorrct::incorrect
:*:incorret::incorrect
:*:incorrec::incorrect
:*:nicorrect::incorrect
:*:icnorrect::incorrect
:*:inocrrect::incorrect
:*:incrorect::incorrect
:*:incorerct::incorrect
:*:incorrcet::incorrect
:*:incorretc::incorrect
:*:methodo::methodology `
:*:orthog::orthogonal
:*:pecifi::specifi
:*:secifi::specifi
:*:spcifi::specifi
:*:speifi::specifi
:*:specfi::specifi
:*:specii::specifi
:*:psecifi::specifi
:*:sepcifi::specifi
:*:spceifi::specifi
:*:speicfi::specifi
:*:specfii::specifi
:*:speciif::specifi
:*:fucn::func
:*:retreiv::retriev
;------------------------------------------------------------------------------
; Word middles
;------------------------------------------------------------------------------
:?*:compatab::compatib  ; Covers incompat* and compat*
:?*:isgn::sign  ; Covers subcatagories and catagories.
:?*:sgin::sign  ; Covers subcatagories and catagories.
:?*:fortuante::fortunate  ; Covers subcatagories and catagories.
:?*:laod::load
:?*:olad::load
:?*:laod::load
:?*:loda::load
:?*:isntall::install
:?*:insatll::install
:?*:istall::install
:?*:intall::install
:?*:usou::uous
;------------------------------------------------------------------------------
; Common Misspellings - the main list
;------------------------------------------------------------------------------
::requiremts::requirement
::requireement::requirement
::termainl::terminal
::SO::So
::onesself::oneself
::violance::violence
::stuats::status
::claend::cleaned
::its he::is the
::Shoudl::Should
::a mnot::am not
::a tthat::at that
::not hat::on that
::aanother::another
::abandonned::abandoned
::abbout::about
::abbreviatoin::abbreviation
::abcense::absense
::aberation::aberration
::aborigene::aborigine
::abortificant::abortifacient
::abou tit::about it
::abouta::about a
::aboutit::about it
::aboutthe::about the
::abscence::absence
::absense::absence
::absorbsion::absorption
::absorbtion::absorption
::abundacies::abundances
::abundancies::abundances
::abundunt::abundant
::abutts::abuts
::acadamy::academy
::accademic::academic
::accademy::academy
::acccused::accused
::accelleration::acceleration
::accension::accession
::acceotable::acceptable
::acceptence::acceptance
::acceptible::acceptable
::accesorise::accessorise
::accessable::accessible
::accidant::accident
::accidentaly::accidentally
::accidently::accidentally
::accidnetally::accidentally
::acclimitization::acclimatization
::accomdate::accommodate
::accomodated::accommodated
::accomodates::accommodates
::accomodating::accommodating
::accompanyed::accompanied
::accordeon::accordion
::accordian::accordion
::accordingto::according to
::accoustic::acoustic
::accquainted::acquainted
::accross::across
::accussed::accused
::acedemic::academic
::achive::achieve
::acide::acid
::acknowledgeing::acknowledging
::acomodate::accommodate
::acquiantence::acquaintance
::acquiantences::acquaintances
::acquited::acquitted
::acused::accused
::acustom::accustom
::acustommed::accustomed
::acutaly::actually
::acutlaly::actually
::ad::Ad
::adaption::adaptation
::adaptions::adaptations
::adavanced::advanced
::adbandon::abandon
::addmission::admission
::addopt::adopt
::addopted::adopted
::addoptive::adoptive
::addresable::addressable
::addressess::addresses
::adecuate::adequate
::adequit::adequate
::adequite::adequate
::adhearing::adhering
::adherance::adherence
::adjusmenet::adjustment
::adjustement::adjustment
::adjustemnet::adjustment
::adjustmenet::adjustment
::admendment::amendment
::admininistrative::administrative
::admissability::admissibility
::admissable::admissible
::admitedly::admittedly
::adres::address
::adresable::addressable
::adresing::addressing
::adressable::addressable
::adventrous::adventurous
::advesary::adversary
::adviced::advised
::aeriel::aerial
::aeriels::aerials
::afficianados::aficionados
::afficionado::aficionado
::afficionados::aficionados
::affilliate::affiliate
::affraid::afraid
::aforememtioned::aforementioned
::afterthe::after the
::againnst::against
::againstt he::against the
::aggaravates::aggravates
::aggreed::agreed
::aggreement::agreement
::aggregious::egregious
::agreeement::agreement
::agreemeent::agreement
::agreemeents::agreements
::agregates::aggregates
::agreing::agreeing
::agressor::aggressor
::agrieved::aggrieved
::ahev::have
::airbourne::airborne
::aircrafts::aircraft
::airporta::airports
::airrcraft::aircraft
::aisian::Asian
::albiet::albeit
::alchohol::alcohol
::alchoholic::alcoholic
::alcholic::alcoholic
::alcohal::alcohol
::alcoholical::alcoholic
::aledge::allege
::aledged::alleged
::aledges::alleges
::alegience::allegiance
::algebraical::algebraic
::algorhitms::algorithms
::alientating::alienating
::all the itme::all the time
::alledge::allege
::alledged::alleged
::alledgedly::allegedly
::alledges::alleges
::allegedely::allegedly
::allegence::allegiance
::allegience::allegiance
::alliviate::alleviate
::allopone::allophone
::allopones::allophones
::allready::already
::allthough::although
::alltime::all-time
::allwasy::always
::allwyas::always
::alonw::alone
::alotted::allotted
::alrigth::alright
::alriht::alright
::alsation::Alsatian
::alse::else
::alseep::asleep
::alsot::also
::alterior::ulterior
::alternitives::alternatives
::altho::although
::althought::although
::altogehter::altogether
::alwats::always
::alwayus::always
::amalgomated::amalgamated
::amendmant::amendment
::amerliorate::ameliorate
::ammend::amend
::ammended::amended
::ammendment::amendment
::ammendments::amendments
::ammount::amount
::ammused::amused
::amoung::among
::amoungst::amongst
::amplfieir::amplifier
::ampliotude::amplitude
::amploitude::amplitude
::amploitudes::amplitudes
::amplotude::amplitude
::amplotuide::amplitude
::amung::among
::an dgot::and got
::analagous::analogous
::analitic::analytic
::analogeous::analogous
::analyse::analyze
::anarchim::anarchism
::anarchistm::anarchism
::anbd::and
::ancestory::ancestry
::ancilliary::ancillary
::Andone::and one
::Anroid::Android
::Andoid::Android
::Andrid::Android
::Androd::Android
::Androi::Android
::Android::Android
::nAdroid::Android
::Adnroid::Android
::Anrdoid::Android
::Andorid::Android
::Andriod::Android
::Androdi::Android
::androgenous::androgynous
::androgeny::androgyny
::andt he::and the
::andteh::and the
::andthe::and the
::anihilation::annihilation
::anmd::and
::annoint::anoint
::annointed::anointed
::annointing::anointing
::annoints::anoints
::annuled::annulled
::anomolies::anomalies
::anomolous::anomalous
::anomoly::anomaly
::anonimity::anonymity
::ansalisation::nasalisation
::ansalization::nasalization
::ansestors::ancestors
::antartic::antarctic
::anthromorphisation::anthropomorphisation
::anthromorphization::anthropomorphization
::anti-semetic::anti-Semitic
::anticlimatic::anticlimactic
::anulled::annulled
::anuthing::anything
::anyother::any other
::anythihng::anything
::anytying::anything
::aparmtnet::apartment
::apenines::Apennines
::apolegetics::apologetics
::apparant::apparent
::apparantly::apparently
::apparnelty::apparently
::apparntely::apparently
::apparrent::apparent
::appart::apart
::appartment::apartment
::appartments::apartments
::appealling::appealing
::appeareance::appearance
::appearence::appearance
::appearences::appearances
::appeares::appears
::appenines::Apennines
::apperances::appearances
::appluied::applied
::applyed::applied
::appointiment::appointment
::appologies::apologies
::appology::apology
::apprearance::appearance
::apprieciate::appreciate
::appropropiate::appropriate
::approproximate::approximate
::approrpriate::appropriate
::approxamately::approximately
::approximitely::approximately
::aprehensive::apprehensive
::aquaintance::acquaintance
::aquainted::acquainted
::aquiantance::acquaintance
::aquit::acquit
::aquitted::acquitted
::arbouretum::arboretum
::archetectural::architectural
::archetecturally::architecturally
::archetecture::architecture
::archiac::archaic
::archictect::architect
::archimedian::Archimedean
::architechturally::architecturally
::architechture::architecture
::architechtures::architectures
::areodynamics::aerodynamics
::argubly::arguably
::arguements::arguments
::arised::arose
::armamant::armament
::armistace::armistice
::around ot::around to
::arragnemetn::arrangement
::arragnemnet::arrangement
::arround::around
::artical::article
::artifically::artificially
::artillary::artillery
::asdvertising::advertising
::asetic::ascetic
::askt he::ask the
::asphyxation::asphyxiation
::assassintation::assassination
::assemple::assemble
::assertation::assertion
::asside::aside
::assisnate::assassinate
::assistent::assistant
::assosication::assassination
::asssassans::assassins
::assualted::assaulted
::asteriod::asteroid
::asthe::as the
::asthetic::aesthetic
::asthetical::aesthetic
::asthetically::aesthetically
::aswell::as well
::atheistical::atheistic
::athenean::Athenian
::atheneans::Athenians
::athiesm::atheism
::athiest::atheist
::attatch::attach
::attendence::attendance
::attendent::attendant
::attendents::attendants
::attension::attention
::attentioin::attention
::atthe::at the
::attitide::attitude
::attributred::attributed
::attrocities::atrocities
::audiance::audience
::austrailia::Australia
::austrailian::Australian
::auther::author
::authobiographic::autobiographic
::authobiography::autobiography
::authorative::authoritative
::authorithy::authority
::authoritiers::authorities
::authoritive::authoritative
::authrorities::authorities
::autochtonous::autochthonous
::autoctonous::autochthonous
::automaticly::automatically
::automibile::automobile
::automonomous::autonomous
::auxilary::auxiliary
::auxillaries::auxiliaries
::auxillary::auxiliary
::auxilliaries::auxiliaries
::auxilliary::auxiliary
::availablility::availability
::availaible::available
::availiable::available
::availible::available
::avalance::avalanche
::ave::have
::avengence::a vengeance
::averageed::averaged
::aweomse::awesome
::awesomoe::awesome
::aywa::away
::aziumth::azimuth
::baceause::because
::balence::balance
::ballance::balance
::banannas::bananas
::barbeque::barbecue
::barcod::barcode
::basicly::basically
::batteryes::batteries
::bceayuse::because
::beachead::beachhead
::beacues::because
::beastiality::bestiality
::beaurocracy::bureaucracy
::beaurocratic::bureaucratic
::beautyfull::beautiful
::becamae::became
::becausea::because a
::becauseof::because of
::becausethe::because the
::becauseyou::because you
::becayse::because
::beccause::because
::beceause::because
::becomeing::becoming
::becomming::becoming
::becouse::because
::bedore::before
::begginer::beginner
::begginers::beginners
::beggining::beginning
::begginings::beginnings
::beggins::begins
::beginining::beginning
::behavour::behaviour
::beleagured::beleaguered
::beleiev::believe
::beleieve::believe
::beleiving::believing
::beligum::belgium
::belligerant::belligerent
::bellweather::bellwether
::bemusemnt::bemusement
::beneficary::beneficiary
::benificial::beneficial
::benifit::benefit
::benifits::benefits
::bergamont::bergamot
::bernouilli::Bernoulli
::beseige::besiege
::beseiged::besieged
::beseiging::besieging
::betweeen::between
::bicep::biceps
::bilateraly::bilaterally
::billingualism::bilingualism
::binominal::binomial
::bizzare::bizarre
::blaim::blame
::blaimed::blamed
::blessure::blessing
::blitzkreig::Blitzkrieg
::bodydbuilder::bodybuilder
::bombardement::bombardment
::bonnano::Bonanno
::bootlaoder::bootloader
::bouat::about
::bouy::buoy
::bouyancy::buoyancy
::bouyant::buoyant
::boyant::buoyant
::boyfriedn::boyfriend
::brasillian::Brazilian
::breakthough::breakthrough
::breakthroughts::breakthroughs
::brethen::brethren
::bretheren::brethren
::brigthness::brightness
::brimestone::brimstone
::brittish::British
::broacasted::broadcast
::broadacasting::broadcasting
::broady::broadly
::brocolli::broccoli
::buddah::Buddha
::bufferring::buffering
::buisnessman::businessman
::buit::but
::buoancy::buoyancy
::burried::buried
::bussiness::business
::butthe::but the
::bve::be
::bweteen::between
::byt he::by the
::cacuses::caucuses
::caeser::caesar
::caffeien::caffeine
::caharcter::character
::calander::calendar
::calcullated::calculated
::calculs::calculus
::calenders::calendars
::califronian::Californian
::caligraphy::calligraphy
::callipigian::callipygian
::caluculate::calculate
::caluculated::calculated
::camoflage::camouflage
::candadate::candidate
::candidiate::candidate
::canidtes::candidates
::cannister::canister
::cannisters::canisters
::cannnot::cannot
::cannonical::canonical
::cannotation::connotation
::cannotations::connotations
::cantalope::cantaloupe
::capacitro::capacitor
::capcaitors::capacitors
::caperbility::capability
::capetown::Cape Town
::capible::capable
::carachter::character
::caracterised::characterised
::carcas::carcass
::cardiod::cardioid
::cardiodi::cardioid
::cardoid::cardioid
::carefull::careful
::careing::caring
::caridoid::cardioid
::carismatic::charismatic
::carmalite::Carmelite
::carniverous::carnivorous
::carreer::career
::carrers::careers
::carribbean::Caribbean
::carribean::Caribbean
::cartdridge::cartridge
::carthagian::Carthaginian
::carthographer::cartographer
::cartilege::cartilage
::cartilidge::cartilage
::casion::caisson
::cassawory::cassowary
::cassowarry::cassowary
::casulaties::casualties
::casulaty::casualty
::catagories::categories
::catagory::category
::categiory::category
::catelog::catalog
::catholocism::catholicism
::catterpilar::caterpillar
::catterpilars::caterpillars
::cattleship::battleship
::caucasion::Caucasian
::causalities::casualties
::causeing::causing
::ceasar::Caesar
::celcius::Celsius
::cellpading::cellpadding
::cementary::cemetery
::cemetarey::cemetery
::cemetaries::cemeteries
::cemetary::cemetery
::cencus::census
::cententenial::centennial
::cerimonial::ceremonial
::cerimonies::ceremonies
::cerimonious::ceremonious
::cerimony::ceremony
::ceromony::ceremony
::certainity::certainty
::challange::challenge
::challanged::challenged
::challanges::challenges
::changable::changeable
::changeing::changing
::charachter::character
::charachters::characters
::charactersistic::characteristic
::charactor::character
::charactors::characters
::charasmatic::charismatic
::charaterised::characterised
::charecter::character
::charector::character
::charistics::characteristics
::chcance::chance
::checmicals::chemicals
::chemestry::chemistry
::childbird::childbirth
::chilli::chili
::choosen::chosen
::cilinder::cylinder
::cincinatti::Cincinnati
::cincinnatti::Cincinnati
::circumfrence::circumference
::circumsicion::circumcision
::ciricuit::circuit
::ciriculum::curriculum
::cirtus::citrus
::civillian::civilian
::claerer::clearer
::claimes::claims
::clasically::classically
::cleareance::clearance
::cliant::client
::clinicaly::clinically
::clipipng::clipping
::clippin::clipping
::closeing::closing
::co-incided::coincided
::cognizent::cognizant
::coincedentally::coincidentally
::colaborations::collaborations
::colateral::collateral
::collaberative::collaborative
::collectable::collectible
::collonade::colonnade
::collonies::colonies
::collony::colony
::collosal::colossal
::colonisators::colonisers
::colonizators::colonizers
::comando::commando
::comandos::commandos
::comapany::company
::comback::comeback
::combanations::combinations
::combintation::combination
::combusion::combustion
::comdemnation::condemnation
::comeing::coming
::comemmorate::commemorate
::comemmorates::commemorates
::comemoretion::commemoration
::comissioning::commissioning
::comited::committed
::comiting::committing
::commandoes::commandos
::commedic::comedic
::commemerative::commemorative
::commemmorate::commemorate
::commemmorating::commemorating
::commerically::commercially
::commericial::commercial
::commericially::commercially
::commerorative::commemorative
::comming::coming
::comminication::communication
::commisioning::commissioning
::committment::commitment
::committments::commitments
::committy::committee
::commiunicating::communicating
::commmemorated::commemorated
::commongly::commonly
::commuinications::communications
::communiucating::communicating
::comntain::contain
::comntains::contains
::compability::compatibility
::compair::compare
::comparision::comparison
::comparisions::comparisons
::comparitive::comparative
::comparitively::comparatively
::compatiable::compatible
::compatioble::compatible
::compensantion::compensation
::competance::competence
::competant::competent
::competative::competitive
::competitiion::competition
::competive::competitive
::competiveness::competitiveness
::comphrehensive::comprehensive
::compitent::competent
::compleated::completed
::compleatly::completely
::compleatness::completeness
::completedthe::completed the
::completelyl::completely
::completetion::completion
::completness::completeness
::componant::component
::composate::composite
::comprimise::compromise
::compulsary::compulsory
::compulsery::compulsory
::computarised::computerised
::computarized::computerized
::comtain::contain
::comtains::contains
::concensus::consensus
::concider::consider
::concidered::considered
::concidering::considering
::conciders::considers
::concieted::conceited
::conciously::consciously
::condamned::condemned
::condemmed::condemned
::condensor::condenser
::condidtion::condition
::condidtions::conditions
::condolances::condolences
::conesencus::consensus
::conferance::conference
::confidentally::confidentially
::confids::confides
::configuraoitn::configuration
::configureable::configurable
::confirmmation::confirmation
::confortable::comfortable
::confusnig::confusing
::congradulations::congratulations
::conived::connived
::conjecutre::conjecture
::conotations::connotations
::conquerd::conquered
::conquerer::conqueror
::conquerers::conquerors
::conqured::conquered
::conscent::consent
::consdider::consider
::consdidered::considered
::consectutive::consecutive
::consenquently::consequently
::consentrate::concentrate
::consentrated::concentrated
::consentrates::concentrates
::consept::concept
::consequentually::consequently
::consequeseces::consequences
::consern::concern
::conserned::concerned
::conserning::concerning
::conservitive::conservative
::consiciousness::consciousness
::consideres::considered
::considerit::considerate
::considerite::considerate
::consistant::consistent
::consistantly::consistently
::consistnelty::consistently
::consistntely::consistently
::consolodate::consolidate
::consolodated::consolidated
::consonent::consonant
::consonents::consonants
::consorcium::consortium
::conspiracys::conspiracies
::conspiriator::conspirator
::conspiricy::conspiracy
::constarnation::consternation
::constinually::continually
::constituant::constituent
::constituants::constituents
::consttruction::construction
::consultent::consultant
::consumate::consummate
::consumated::consummated
::consumber::consumer
::contaiminate::contaminate
::containes::contains
::contamporaries::contemporaries
::contamporary::contemporary
::contemporaneus::contemporaneous
::contempory::contemporary
::contendor::contender
::continueing::continuing
::contravercial::controversial
::contraversy::controversy
::contributer::contributor
::contributers::contributors
::contritutions::contributions
::controll::control
::controlls::controls
::controvercial::controversial
::controvercy::controversy
::controvertial::controversial
::convenant::covenant
::convential::conventional
::convertable::convertible
::convertables::convertibles
::convertion::conversion
::convertor::converter
::convertors::converters
::conveyer::conveyor
::convienient::convenient
::cooparate::cooperate
::cooporate::cooperate
::coorperations::corporations
::copywrite::copyright
::coridal::cordial
::corosion::corrosion
::corparate::corporate
::corperations::corporations
::correcters::correctors
::correposding::corresponding
::correspondant::correspondent
::correspondants::correspondents
::corridoors::corridors
::corrispond::correspond
::corrispondant::correspondent
::corrispondants::correspondents
::corrisponded::corresponded
::corrisponding::corresponding
::corrisponds::corresponds
::corruptable::corruptible
::cotten::cotton
::couldthe::could the
::countains::contains
::counterfiet::counterfeit
::coururier::courier
::cpacitor::capacitor
::creaeted::created
::creedence::credence
::critereon::criterion
::criterias::criteria
::criticing::criticising
::criticists::critics
::critised::criticised
::crockodiles::crocodiles
::crucifiction::crucifixion
::crystalisation::crystallisation
::culiminating::culminating
::cumulatative::cumulative
::curcuit::circuit
::curiousity::curiosity
::curriculem::curriculum
::currnets::currents
::cxan::can
::cxan::cyan
::cyclinder::cylinder
::dakiri::daiquiri
::dalmation::dalmatian
::damenor::demeanor
::damenor::demeanour
::damenour::demeanour
::danceing::dancing
::dardenelles::Dardanelles
::debateable::debatable
::decaffinated::decaffeinated
::decathalon::decathlon
::decendant::descendant
::decendants::descendants
::decendent::descendant
::decendents::descendants
::decideable::decidable
::decidely::decidedly
::decieved::deceived
::decomissioned::decommissioned
::decomposit::decompose
::decomposited::decomposed
::decompositing::decomposing
::decomposits::decomposes
::decress::decrees
::dectect::detect
::defencive::defensive
::defendent::defendant
::defendents::defendants
::deffensively::defensively
::deffine::define
::deffined::defined
::definance::defiance
::definate::definite
::definately::definitely
::definatly::definitely
::definetly::definitely
::definining::defining
::degrate::degrade
::degredation::degradation
::delagates::delegates
::delapidated::dilapidated
::delerious::delirious
::delevopment::development
::delusionally::delusively
::demenor::demeanor
::demenour::demeanour
::demographical::demographic
::demolision::demolition
::demorcracy::democracy
::denegrating::denigrating
::dependance::dependence
::dependancy::dependency
::dependant::dependent
::depricate::deprecate
::depricated::deprecated
::deprication::deprecation
::deptartment::department
::deriviated::derived
::derivitive::derivative
::derogitory::derogatory
::descendands::descendants
::descision::decision
::descisions::decisions
::descriibes::describes
::descripters::descriptors
::desctruction::destruction
::descuss::discuss
::desease::disease
::desicion::decision
::desicions::decisions
::deside::decide
::desigining::designing
::desintegrated::disintegrated
::desintegration::disintegration
::desireable::desirable
::desision::decision
::desisions::decisions
::desitned::destined
::desktiop::desktop
::desorder::disorder
::desoriented::disoriented
::desparate::desperate
::desparately::desperately
::despatched::dispatched
::despict::depict
::despiration::desperation
::dessicated::desiccated
::dessigned::designed
::destablised::destabilised
::destablized::destabilized
::detailled::detailed
::detatched::detached
::deteoriated::deteriorated
::deteriate::deteriorate
::deterioriating::deteriorating
::determinining::determining
::detremental::detrimental
::devasted::devastated
::develeoprs::developers
::devellop::develop
::develloped::developed
::develloper::developer
::devellopers::developers
::develloping::developing
::devellopment::development
::devellopments::developments
::devellops::develop
::developor::developer
::developors::developers
::developped::developed
::devels::delves
::devestated::devastated
::devestating::devastating
::devide::divide
::devided::divided
::devistating::devastating
::devolopement::development
::diablical::diabolical
::diaplay::display
::diarhea::diarrhoea
::dichtomy::dichotomy
::diciplin::discipline
::diconnects::disconnects
::dicovering::discovering
::dicovers::discovers
::didnot::did not
::dieing::dying
::dieties::deities
::diety::deity
::diferrent::different
::differance::difference
::differances::differences
::differant::different
::differemt::different
::differentiatiations::differentiations
::difficulity::difficulty
::digestable::digestible
::dimention::dimension
::dimentional::dimensional
::dimentions::dimensions
::diminuitive::diminutive
::diosese::diocese
::diphtong::diphthong
::diphtongs::diphthongs
::diplomancy::diplomacy
::diptheria::diphtheria
::dipthong::diphthong
::dipthongs::diphthongs
::directer::director
::directers::directors
::directiosn::direction
::dirived::derived
::disagreeed::disagreed
::disapear::disappear
::disapeared::disappeared
::disapointing::disappointing
::disappearred::disappeared
::disaproval::disapproval
::disasterous::disastrous
::disatisfaction::dissatisfaction
::disatisfied::dissatisfied
::disatrous::disastrous
::discontentment::discontent
::discrepencies::discrepancies
::discrepency::discrepancy
::discribe::describe
::discribed::described
::discribes::describes
::discribing::describing
::disctinction::distinction
::disctinctive::distinctive
::disemination::dissemination
::disenchanged::disenchanted
::disign::design
::disiplined::disciplined
::disobediance::disobedience
::disobediant::disobedient
::dispair::despair
::disparingly::disparagingly
::dispeled::dispelled
::dispeling::dispelling
::dispell::dispel
::dispells::dispels
::dispence::dispense
::dispenced::dispensed
::dispencing::dispensing
::dispicable::despicable
::dispite::despite
::disproportiate::disproportionate
::disputandem::disputandum
::dissagreement::disagreement
::dissapear::disappear
::dissapearance::disappearance
::dissapeared::disappeared
::dissapearing::disappearing
::dissapears::disappears
::dissappear::disappear
::dissappears::disappears
::dissappointed::disappointed
::dissarray::disarray
::dissobediance::disobedience
::dissobediant::disobedient
::dissobedience::disobedience
::dissobedient::disobedient
::dissonent::dissonant
::distingish::distinguish
::distingishes::distinguishes
::distingishing::distinguishing
::distingquished::distinguished
::distribusion::distribution
::distrubution::distribution
::distruction::destruction
::distructive::destructive
::divice::device
::doccument::document
::doccumented::documented
::doccuments::documents
::docuement::documents
::doe snot::does not ; *could* be legitimate... but very unlikely!
::doese::does
::dogin::doing
::doimg::doing
::doind::doing
::dollers::dollars
::dominent::dominant
::dominiant::dominant
::don't no::don't know
::draughtman::draughtsman
::dravadian::Dravidian
::driveing::driving
::druming::drumming
::drummless::drumless
::drunkeness::drunkenness
::dukeship::dukedom
::dumbell::dumbbell
::durring::during
::duting::during
::eachotehr::eachother
::earnt::earned
::ebceause::because
::ecclectic::eclectic
::eceonomy::economy
::ecidious::deciduous
::ecomonic::economic
::eearly::early
::efel::evil
::effeciency::efficiency
::effecient::efficient
::effeciently::efficiently
::effulence::effluence
::eight o::eight o
::eigth::eighth
::electricly::electrically
::eleminated::eliminated
::eleminating::eliminating
::eles::eels
::elicided::elicited
::eligable::eligible
::elimentary::elementary
::ellected::elected
::embargos::embargoes
::embarras::embarrass
::embarrased::embarrassed
::embarrasing::embarrassing
::embarrasment::embarrassment
::embezelled::embezzled
::emblamatic::emblematic
::eminate::emanate
::eminated::emanated
::emited::emitted
::emiting::emitting
::emmediately::immediately
::emmigrated::emigrated
::emmisaries::emissaries
::emmisarries::emissaries
::emmisarry::emissary
::emmisary::emissary
::emmision::emission
::emmisions::emissions
::emmited::emitted
::emmiting::emitting
::emmitted::emitted
::emmitting::emitting
::emnity::enmity
::emperical::empirical
::emphaised::emphasised
::emphysyma::emphysema
::emprisoned::imprisoned
::enameld::enamelled
::enchancement::enhancement
::encryptiion::encryption
::endevors::endeavors
::endevour::endeavour
::endevours::endeavours
::endolithes::endoliths
::enduce::induce
::enflamed::inflamed
::enforceing::enforcing
::engeneer::engineer
::engeneering::engineering
::engieneer::engineer
::engieneers::engineers
::enought::enough
::enourmous::enormous
::enourmously::enormously
::ensconsed::ensconced
::entaglements::entanglements
::entitity::entity
::entitlied::entitled
::enviornmentalist::environmentalist
::envolutionary::evolutionary
::epidsodes::episodes
::epsidoe::episode
::equippment::equipment
::equitorial::equatorial
::equivalant::equivalent
::equivelant::equivalent
::equivelent::equivalent
::equivilant::equivalent
::equivilent::equivalent
::equivlalent::equivalent
::eratic::erratic
::eratically::erratically
::eraticly::erratically
::errupted::erupted
::esctasy::ecstasy
::espesially::especially
::essencial::essential
::essense::essence
::essentual::essential
::essesital::essential
::ethnocentricm::ethnocentrism
::europian::European
::europians::Europeans
::evenhtually::eventually
::eventially::eventually
::everytime::every time
::evidentally::evidently
::exagerate::exaggerate
::exagerated::exaggerated
::exagerates::exaggerates
::exagerating::exaggerating
::exagerrate::exaggerate
::exagerrated::exaggerated
::exagerrates::exaggerates
::exagerrating::exaggerating
::examinated::examined
::exampt::exempt
::exapansion::expansion
::excact::exact
::excecute::execute
::excecuted::executed
::excecutes::executes
::excecuting::executing
::excecution::execution
::excedded::exceeded
::excell::excel
::excellance::excellence
::excellant::excellent
::excells::excels
::excercise::exercise
::exchanching::exchanging
::excisted::existed
::exculsivly::exclusively
::execising::exercising
::exeedingly::exceedingly
::exelent::excellent
::exemple::example
::exerbate::exacerbate
::exerbated::exacerbated
::exerciese::exercises
::exerpts::excerpts
::exersize::exercise
::exerternal::external
::exhalted::exalted
::exinct::extinct
::exisiting::existing
::existance::existence
::existant::existent
::existince::existence
::exliled::exiled
::exonorate::exonerate
::exoskelaton::exoskeleton
::expecially::especially
::expeditonary::expeditionary
::expell::expel
::expells::expels
::experiance::experience
::experianced::experienced
::expiditions::expeditions
::expierence::experience
::explaination::explanation
::exploititive::exploitative
::expresso::espresso
::expropiated::expropriated
::expropiation::expropriation
::extention::extension
::extentions::extensions
::extered::exerted
::extermist::extremist
::extradiction::extradition
::extravagent::extravagant
::extrememly::extremely
::extremeophile::extremophile
::extrordinarily::extraordinarily
::facia::fascia
::facillitate::facilitate
::facinated::fascinated
::facist::fascist
::familliar::familiar
::fammiliar::familiar
::famoust::famous
::fanatism::fanaticism
::farenheit::Fahrenheit
::fascitious::facetious
::fascitis::fasciitis
::faught::fought
::favoutrable::favourable
::feasable::feasible
::fedreally::federally
::feromone::pheromone
::fertily::fertility
::fi::If
::fianite::finite
::ficed::fixed
::ficticious::fictitious
::fictious::fictitious
::fiercly::fiercely
::fightings::fighting
::filiament::filament
::fimilies::families
::firc::furc
::firey::fiery
::fisionable::fissionable
::flamable::flammable
::flawess::flawless
::flemmish::Flemish
::florescent::fluorescent
::flourescent::fluorescent
::flouride::fluoride
::fluorish::flourish
::fo::of
::focussed::focused
::focusses::focuses
::focussing::focusing
::fonetic::phonetic
::foootball::football
::fora::for a
::forbad::forbade
::foreward::foreword
::forfiet::forfeit
::forhead::forehead
::formalhaut::Fomalhaut
::formallise::formalise
::formallised::formalised
::formallize::formalize
::formallized::formalized
::formaly::formally
::formelly::formerly
::formost::foremost
::forsaw::foresaw
::forseeable::foreseeable
::fortelling::foretelling
::forthe::for the
::forunner::forerunner
::forwrds::forwards
::foundaries::foundries
::foundary::foundry
::foundland::Newfoundland
::fourties::forties
::fourty::forty
::fowards::forwards
::fransiscan::Franciscan
::fransiscans::Franciscans
::frequentily::frequently
::frome::from
::fromt he::from the
::fromthe::from the
::fucniton::function
::fued::feud
::funguses::fungi
::furneral::funeral
::furuther::further
::galatic::galactic
::galations::Galatians
::gallaxies::galaxies
::galvinised::galvanised
::galvinized::galvanized
::gameboy::Game Boy
::ganes::games
::ganster::gangster
::garnison::garrison
::gauarana::guarana
::gaurentee::guarantee
::gaurenteed::guaranteed
::gaurentees::guarantees
::gemeral::general
::geneological::genealogical
::geneologies::genealogies
::geneology::genealogy
::generatting::generating
::genialia::genitalia
::geographicial::geographical
::geometrician::geometer
::geometricians::geometers
::ghandi::Gandhi
::giid::good
::giveing::giving
::glight::flight
::gnawwed::gnawed
::godess::goddess
::godesses::goddesses
::godounov::Godunov
::gothenberg::Gothenburg
::gottleib::Gottlieb
::gouvener::governor
::govement::government
::governer::governor
::govorment::government
::govormental::governmental
::govornment::government
::gracefull::graceful
::graffitti::graffiti
::grafitti::graffiti
::gramatically::grammatically
::grammaticaly::grammatically
::grammer::grammar
::gratuitious::gratuitous
::greatful::grateful
::greatfully::gratefully
::greif::grief
::gridles::griddles
::guadulupe::Guadalupe
::guarentee::guarantee
::guarenteed::guaranteed
::guarentees::guarantees
::guatamala::Guatemala
::guatamalan::Guatemalan
::guidence::guidance
::guilia::Giulia
::guiliani::Giuliani
::guilio::Giulio
::guiness::Guinness
::guiseppe::Giuseppe
::gunanine::guanine
::guttaral::guttural
::gutteral::guttural
::haad::had
::habaeus::habeas
::habeus::habeas
::habsbourg::Habsburg
::hace::hare
::hadbeen::had been
::haemorrage::haemorrhage
::hallowean::Halloween
::halp::help
::happended::happened
::happenned::happened
::harased::harassed
::harases::harasses
::harassement::harassment
::harras::harass
::harrased::harassed
::harrases::harasses
::harrasing::harassing
::harrasment::harassment
::harrasments::harassments
::harrassed::harassed
::harrasses::harassed
::harrassing::harassing
::harrassment::harassment
::harrassments::harassments
::hasbeen::has been
::havebeen::have been
::haveing::having
::haviest::heaviest
::headquater::headquarter
::headquatered::headquartered
::healthercare::healthcare
::heared::heard
::heidelburg::Heidelberg
::heigher::higher
::heirarchies::hierarchies
::heirarchy::heirarchy
::heiroglyphics::hieroglyphics
::helment::helmet
::helpfull::helpful
::helpped::helped
::hemmorhage::hemorrhage
::herf::href
::heridity::heredity
::heroe::hero
::heros::heroes
::hersuit::hirsute
::hertzs::hertz
::hesaid::he said
::hesistant::hesitant
::heterogenous::heterogeneous
::hewas::he was
::hge::he
::hier::heir
::hierachies::hierarchies
::hieroglph::hieroglyph
::hieroglphs::hieroglyphs
::hillarious::hilarious
::himselv::himself
::hinderance::hindrance
::hinderence::hindrance
::hindrence::hindrance
::hipopotamus::hippopotamus
::historicians::historians
::hitsingles::hit singles
::holliday::holiday
::homestate::home state
::homogeneize::homogenize
::homogeneized::homogenized
::honory::honorary
::honourarium::honorarium
::honourific::honorific
::hosited::hoisted
::hospitible::hospitable
::hounour::honour
::hsitorians::historians
::htikn::think
::htp:::http:
::http:\\::http://
::httpL::http:
::humer::humour
::humerous::humourous
::huminoid::humanoid
::humoural::humoral
::humurous::humourous
::hwihc::which
::hydropile::hydrophile
::hydropilic::hydrophilic
::hydropobe::hydrophobe
::hydropobic::hydrophobic
::hypocracy::hypocrisy
::hypocrasy::hypocrisy
::hypocricy::hypocrisy
::hypocrit::hypocrite
::hypocrits::hypocrites
::i snot::is not
::i"d::I'd
::i"ll::I'll
::i"m::I'm
::i"ve::I've
::i::I
::I"m::I'm ; "
::iconclastic::iconoclastic
::idaeidae::idea
::idealogies::ideologies
::idealogy::ideology
::identicial::identical
::identifers::identifiers
::identofy::identify
::ideosyncratic::idiosyncratic
::idiosyncracy::idiosyncrasy
::ignorence::ignorance
::ihaca::Ithaca
::iits the::it's the
::illegimacy::illegitimacy
::illiegal::illegal
::illution::illusion
::ilogical::illogical
::imagenary::imaginary
::imanent::imminent
::imcomplete::incomplete
::imediatly::immediately
::imense::immense
::immidately::immediately
::immidiately::immediately
::immunosupressant::immunosuppressant
::impecabbly::impeccably
::impedence::impedance
::implamenting::implementing
::imploys::employs
::importamt::important
::importent::important
::impossable::impossible
::imprioned::imprisoned
::imprisonned::imprisoned
::improvision::improvisation
::inablility::inability
::inaccessable::inaccessible
::inadiquate::inadequate
::inadquate::inadequate
::inadvertant::inadvertent
::inadvertantly::inadvertently
::inagurated::inaugurated
::inaguration::inauguration
::inaugures::inaugurates
::inbalance::imbalance
::inbalanced::imbalanced
::inbetween::between
::incarcirated::incarcerated
::incidentially::incidentally
::incidently::incidentally
::inclreased::increased
::incompetance::incompetence
::incompetant::incompetent
::incomptable::incompatible
::incomptetent::incompetent
::inconsistant::inconsistent
::incorperation::incorporation
::incorruptable::incorruptible
::incramentally::incrementally
::increadible::incredible
::incredable::incredible
::inctroduce::introduce
::inctroduced::introduced
::incunabla::incunabula
::indecate::indicate
::indefinately::indefinitely
::indefineable::undefinable
::indepedantly::independently
::independance::independence
::independant::independent
::independantly::independently
::independendet::independent
::indictement::indictment
::indigineous::indigenous
::indipendence::independence
::indipendent::independent
::indipendently::independently
::indispensible::indispensable
::indite::indict
::indulgue::indulge
::inefficienty::inefficiently
::inevatible::inevitable
::inevitible::inevitable
::inevititably::inevitably
::infalability::infallibility
::infallable::infallible
::infectuous::infectious
::infilitrate::infiltrate
::infilitrated::infiltrated
::infilitration::infiltration
::infinitly::infinitely
::inflamation::inflammation
::influance::influence
::influencial::influential
::influented::influenced
::infrantryman::infantryman
::ingreediants::ingredients
::inhabitans::inhabitants
::inherantly::inherently
::inheritence::inheritance
::initation::initiation
::initiaitive::initiative
::inmigrant::immigrant
::inmigrants::immigrants
::innoculate::inoculate
::innoculated::inoculated
::inocence::innocence
::inofficial::unofficial
::inpeach::impeach
::inpolite::impolite
::inprisonment::imprisonment
::inproving::improving
::insectiverous::insectivorous
::insensative::insensitive
::inseperable::inseparable
::insistance::insistence
::instade::instead
::instatance::instance
::instutionalized::institutionalized
::instutions::intuitions
::insurence::insurance
::int he::in the
::inteh::in the
::intepretator::interpretor
::interchangable::interchangeable
::interchangably::interchangeably
::intercontinetal::intercontinental
::interferance::interference
::interfereing::interfering
::intergrated::integrated
::intergration::integration
::internation::international
::interrim::interim
::interrugum::interregnum
::intertaining::entertaining
::interum::interim
::interupt::interrupt
::intervines::intervenes
::inthe::in the
::intruduced::introduced
::intrusted::entrusted
::inumerable::innumerable
::inventer::inventor
::invertibrates::invertebrates
::investingate::investigate
::inwhich::in which
::irelevent::irrelevant
::iresistable::irresistible
::iresistably::irresistibly
::iresistible::irresistible
::iresistibly::irresistibly
::iritable::irritable
::iritated::irritated
::ironicly::ironically
::irregardless::regardless
::irrelevent::irrelevant
::irreplacable::irreplaceable
::irresistable::irresistible
::irresistably::irresistibly
::issueing::issuing
::isthe::is the
::it snot::it's not
::it' snot::it's not
::itis::it is
::ititial::initial
::and it's::and its
::to it's::to its
::it's appearance::its appearance
::it's color::its color
::it's data::its data
::it's design::its design
::it's effect::its effect
::it's egg::its egg
::it's failure::its failure
::it's function::its function
::it's functionality::its functionality
::it's fur::its fur
::it's habitat::its habitat
::it's impact::its impact
::it's influence::its influence
::it's interface::its interface
::it's limits::its limits
::it's location::its location
::it's mate::its mate
::it's meaning::its meaning
::it's name::its name
::it's nest::its nest
::it's network::its network
::it's operation::its operation
::it's object::its object
::it's origin::its origin
::it's output::its output
::it's own::its own
::it's parts::its parts
::it's performance::its performance
::it's position::its position
::it's potential::its potential
::it's prey::its prey
::it's process::its process
::it's purpose::its purpose
::it's reputation::its reputation
::it's role::its role
::it's shape::its shape
::it's size::its size
::it's smell::its smell
::it's sound::its sound
::it's structure::its structure
::it's success::its success
::it's surface::its surface
::it's system::its system
::it's tail::its tail
::it's taste::its taste
::it's territory::its territory
::it's texture::its texture
::it's users::its users
::it's value::its value
::it's weight::its weight
::it's wings::its wings
::it's young::its young
::its a::it's a
::its an::it's an
::its apparently::it's apparently
::its the::it's the
::itwas::it was
::its any::it's any
::its available::it's available
::its beautiful::it's beautiful
::its been::it's been
::its broken::it's broken
::its changed::it's changed
::its clear::it's clear
::its cold::it's cold
::its complicated::it's complicated
::its developed::it's developed
::its difficult:: it's difficult
::its done::it's done
::its down::it's down
::its easy:: it's easy
::its easiest:: it's easiest
::its evolved::it's evolved
::its false::it's false
::its fine::it's fine
::its finished::it's finished
::its gone::it's gone
::its grown::it's grown
::its happened::it's happened
::its happening::it's happening
::its hard:: it's hard
::its here:: it's here
::its her::it's her
::its his::it's his
::its hot::it's hot
::its increased::it's increased
::its important::it's important
::its improved::it's improved
::its in::it's in
::its late::it's late
::its lacking::it's lacking
::its left::it's left
::its new::it's new
::its none::it's none
::its not::it's not
::its nothing::it's nothing
::its of::it's of
::its off::it's off
::its okay::it's okay
::its old::it's old
::its on::it's on
::its over::it's over
::its possible::it's possible
::its raining::it's raining
::its ready::it's ready
::its really::it's really
::its right::it's right
::its run::it's run
::its something::it's something
::its started::it's started
::its sunny::it's sunny
::its there::it's there
::its time::it's time
::its true::it's true
::its up::it's up
::its very::it's very
::its working::it's working
::its your::it's your
::its yours::it's yours
::iunior::junior
::jaques::jacques
::jeapardy::jeopardy
::jewelery::jewellery
::jewllery::jewellery
::johanine::Johannine
::journied::journeyed
::journies::journeys
::jstu::just
::juadaism::Judaism
::juadism::Judaism
::judgment::judgement
::judisuary::judiciary
::juducial::judicial
::juristiction::jurisdiction
::juristictions::jurisdictions
::kindergarden::kindergarten
::klenex::kleenex
::knifes::knives
::knive::knife
::knowlegeable::knowledgeable
::kwno::know
::labled::labelled
::labourious::laborious
::larrry::larry
::lasoo::lasso
::lastest::latest
::lastr::last
::lastyear::last year
::lattitude::latitude
::launchs::launch
::lavae::larvae
::layed::laid
::lazer::laser
::lazyness::laziness
::leaded::led
::leathal::lethal
::lefted::left
::legitamate::legitimate
::legitamite::legitimate
::leibnitz::leibniz
::lerans::learns
::lets'::let's
::let's him::lets him
::let's it::lets it
::leutenant::lieutenant
::levetate::levitate
::levetated::levitated
::levetates::levitates
::levetating::levitating
::liasion::liaison
::liason::liaison
::liasons::liaisons
::libell::libel
::libguistic::linguistic
::libguistics::linguistics
::libitarianisn::libertarianism
::librarry::library
::librery::library
::lieing::lying
::lieutenent::lieutenant
::lieved::lived
::lightening::lightning
::lightyear::light year
::lightyears::light years
::likelyhood::likelihood
::linnaena::linnaean
::lippizaner::lipizzaner
::liquify::liquefy
::lisense::license
::listners::listeners
::litature::literature
::litterally::literally
::litttle::little
::liuke::like
::liveing::living
::livley::lively
::lonelyness::loneliness
::longitudonal::longitudinal
::loosing::losing
::lotharingen::lothringen
::lukid::likud
::lveo::love
::lybia::Libya
::mackeral::mackerel
::magasine::magazine
::magincian::magician
::magnificient::magnificent
::magolia::magnolia
::maintainance::maintenance
::maintainence::maintenance
::maintance::maintenance
::maintenence::maintenance
::maintinaing::maintaining
::maintioned::mentioned
::majoroty::majority
::makeing::making
::malcom::Malcolm
::maltesian::Maltese
::mamal::mammal
::mamalian::mammalian
::managable::manageable
::manifestion::manifestation
::manisfestations::manifestations
::manoeuverability::maneuverability
::manufacturedd::manufactured
::manuver::maneuver
::marjority::majority
::markes::marks
::marketting::marketing
::marmelade::marmalade
::marrtyred::martyred
::marryied::married
::massachussets::Massachusetts
::massachussetts::Massachusetts
::massmedia::mass media
::masterbation::masturbation
::mataphysical::metaphysical
::materalists::materialist
::mathamatics::mathematics
::mathematicas::mathematics
::matheticians::mathematicians
::may of::may have
::mccarthyst::mccarthyist
::meaninng::meaning
::medacine::medicine
::medevial::medieval
::mediciney::mediciny
::medieval::mediaeval
::medievel::medieval
::mediterainnean::mediterranean
::meerkrat::meerkat
::melieux::milieux
::membranaphone::membranophone
::memeber::member
::mercentile::mercantile
::merchent::merchant
::messanger::messenger
::messenging::messaging
::metalurgic::metallurgic
::metalurgical::metallurgical
::metalurgy::metallurgy
::metamorphysis::metamorphosis
::metaphoricial::metaphorical
::meterologist::meteorologist
::meterology::meteorology
::methaphor::metaphor
::methaphors::metaphors
::michagan::Michigan
::micoscopy::microscopy
::midwifes::midwives
::might of::might have
::mileau::milieu
::milennia::millennia
::mileu::milieu
::miliraty::military
::millenia::millennia
::millenial::millennial
::millenialism::millennialism
::millepede::millipede
::millioniare::millionaire
::millitary::military
::minerial::mineral
::miniscule::minuscule
::ministery::ministry
::minumum::minimum
::mirrorred::mirrored
::miscellanious::miscellaneous
::mischeivous::mischievous
::mischevious::mischievous
::mischievious::mischievous
::misdameanor::misdemeanor
::misdameanors::misdemeanors
::misdemenor::misdemeanor
::misdemenors::misdemeanors
::misfourtunes::misfortunes
::mispell::misspell
::mispelled::misspelled
::mispelling::misspelling
::mispellings::misspellings
::missen::mizzen
::missisipi::Mississippi
::missonary::missionary
::misterious::mysterious
::mistery::mystery
::misteryous::mysterious
::mkea::make
::moderm::modem
::mohammedans::muslims
::moil::mohel
::momento::memento
::monestaries::monasteries
::monestary::monastery
::monickers::monikers
::monkies::monkeys
::monolite::monolithic
::monserrat::Montserrat
::montanous::mountainous
::montypic::monotypic
::moreso::more so
::morisette::Morissette
::morrisette::Morissette
::morroccan::moroccan
::morrocco::morocco
::morroco::morocco
::motiviated::motivated
::mottos::mottoes
::mounth::month
::mucuous::mucous
::mudering::murdering
::muhammadan::muslim
::multicultralism::multiculturalism
::multipled::multiplied
::multiplers::multipliers
::munbers::numbers
::muncipalities::municipalities
::munnicipality::municipality
::muscician::musician
::muscicians::musicians
::must of::must have
::mutiliated::mutilated
::myraid::myriad
::mysogynist::misogynist
::mysogyny::misogyny
::mythraic::Mithraic
::myu::my
::naieve::naive
::napoleonian::Napoleonic
::naturely::naturally
::naturual::natural
::naturually::naturally
::naywya::anyway
::nazereth::Nazareth
::neccesarily::necessarily
::neccesary::necessary
::neccessarily::necessarily
::neccessary::necessary
::neccessities::necessities
::necessiate::necessitate
::neglible::negligible
::negligable::negligible
::negociable::negotiable
::neice::niece
::neigbourhood::neighbourhood
::neolitic::neolithic
::nessasarily::necessarily
::nessecary::necessary
::nestin::nesting
::newyorker::New Yorker
::nightime::nighttime
::nineth::ninth
::ninteenth::nineteenth
::ninties::nineties ; fixed from "1990s": could refer to temperatures too.
::ninty::ninety
::nkwo::know
::noncombatents::noncombatants
::nonsence::nonsense
::nontheless::nonetheless
::noone::no one
::northereastern::northeastern
::notabley::notably
::noteable::notable
::noteably::notably
::noteriety::notoriety
::noticable::noticeable
::noticably::noticeably
::noticeing::noticing
::notive::notice
::notwhithstanding::notwithstanding
::noveau::nouveau
::nowdays::nowadays
::nowe::now
::nucular::nuclear
::nuculear::nuclear
::nuisanse::nuisance
::nullabour::Nullarbor
::numberous::numerous
::nuptual::nuptial
::nuremburg::Nuremberg
::nusance::nuisance
::nutritent::nutrient
::nutritents::nutrients
::nuturing::nurturing
::obediance::obedience
::obediant::obedient
::obession::obsession
::obsolecence::obsolescence
::obssessed::obsessed
::obstacal::obstacle
::obstancles::obstacles
::obstruced::obstructed
::ocassion::occasion
::ocassional::occasional
::ocassionally::occasionally
::ocassionaly::occasionally
::ocassioned::occasioned
::ocassions::occasions
::occassion::occasion
::occassional::occasional
::occassionally::occasionally
::occassionaly::occasionally
::occassioned::occasioned
::occassions::occasions
::occationally::occasionally
::occour::occur
::occurr::occur
::occurrance::occurrence
::occurrances::occurrences
::octohedra::octahedra
::octohedral::octahedral
::octohedron::octahedron
::ocurr::occur
::ocurrance::occurrence
::odouriferous::odoriferous
::odourous::odorous
::offereings::offerings
::officaly::officially
::ofits::of its
::oft he::of the ; Could be legitimate in poetry, but more usually a typo.
::oftenly::often
::ofthe::of the
::omision::omission
::omited::omitted
::omiting::omitting
::omlette::omelette
::ommision::omission
::ommited::omitted
::ommiting::omitting
::ommitted::omitted
::ommitting::omitting
::omnious::ominous
::omniverous::omnivorous
::omniverously::omnivorously
::oneof::one of
::onepoint::one point
::onomatopeia::onomatopoeia
::ont he::on the
::onthe::on the
::openess::openness
::opose::oppose
::oppasite::opposite
::oppenly::openly
::opperation::operation
::oppertunity::opportunity
::oppinion::opinion
::opponant::opponent
::oppononent::opponent
::opposate::opposite
::opposible::opposable
::oppositition::opposition
::oppossed::opposed
::opression::oppression
::opressive::oppressive
::opthalmic::ophthalmic
::opthalmologist::ophthalmologist
::opthalmology::ophthalmology
::opthamologist::ophthalmologist
::optmizations::optimizations
::optomism::optimism
::orded::ordered
::organim::organism
::orginization::organization
::orginize::organise
::orginized::organized
::oridinarily::ordinarily
::origanaly::originally
::originially::originally
::originnally::originally
::origional::original
::orthagonal::orthogonal
::orthagonally::orthogonally
::otherw::others
::ouevre::oeuvre
::outof::out of
::outtage::outage
::overshaddowed::overshadowed
::overthe::over the
::overthere::over there
::overwelming::overwhelming
::overwheliming::overwhelming
::owudl::would
::oxident::oxidant
::oxigen::oxygen
::oximoron::oxymoron
::paide::paid
::paitience::patience
::paleolitic::paleolithic
::paliamentarian::parliamentarian
::palistian::Palestinian
::palistinian::Palestinian
::palistinians::Palestinians
::pallete::palette
::pamflet::pamphlet
::pamplet::pamphlet
::pantomine::pantomime
::papaer::paper
::papanicalou::Papanicolaou
::paralelly::parallelly
::paralely::parallelly
::parallely::parallelly
::paranthesis::parenthesis
::paraphenalia::paraphernalia
::parellels::parallels
::parituclar::particular
::parrakeets::parakeets
::parralel::parallel
::parrallel::parallel
::parrallell::parallel
::parrallelly::parallelly
::parrallely::parallelly
::particularily::particularly
::partof::part of
::passerbys::passersby
::pasttime::pastime
::pastural::pastoral
::pattented::patented
::pavillion::pavilion
::payed::paid
::peacefuland::peaceful and
::peageant::pageant
::peculure::peculiar
::pedestrain::pedestrian
::peleton::peloton
::peloponnes::Peloponnesus
::penerator::penetrator
::penisular::peninsular
::penninsula::peninsula
::penninsular::peninsular
::pensinula::peninsula
::perade::parade
::percentof::percent of
::percentto::percent to
::percepted::perceived
::percieve::perceive
::perenially::perennially
::perfomers::performers
::performence::performance
::performes::performs
::perheaps::perhaps
::peripathetic::peripatetic
::perjery::perjury
::perjorative::pejorative
::permanant::permanent
::permenant::permanent
::permenantly::permanently
::perminent::permanent
::permissable::permissible
::perogative::prerogative
::perphas::perhaps
::perpindicular::perpendicular
::perseverence::perseverance
::persistance::persistence
::persistant::persistent
::personell::personnel
::personnell::personnel
::persuded::persuaded
::persue::pursue
::persued::pursued
::persuing::pursuing
::persuit::pursuit
::persuits::pursuits
::pertubation::perturbation
::pertubations::perturbations
::pessiary::pessary
::petetion::petition
::pharoah::Pharaoh
::phenomenom::phenomenon
::phenomenonal::phenomenal
::phenomenonly::phenomenally
::phenomonenon::phenomenon
::phenomonon::phenomenon
::phenonmena::phenomena
::pheonix::phoenix ; Not forcing caps, as it could be the bird
::philisopher::philosopher
::philisophical::philosophical
::philisophy::philosophy
::phillipine::Philippine
::phillipines::Philippines
::phillippines::Philippines
::phillosophically::philosophically
::philosphies::philosophies
::phonecian::Phoenecian
::phongraph::phonograph
::phylosophical::philosophical
::pilgrimmage::pilgrimage
::pilgrimmages::pilgrimages
::pinapple::pineapple
::pinnaple::pineapple
::pinoneered::pioneered
::plagarism::plagiarism
::planation::plantation
::plateu::plateau
::plausable::plausible
::playright::playwright
::playwrite::playwright
::playwrites::playwrights
::pleasent::pleasant
::plebicite::plebiscite
::poeoples::peoples
::poisin::poison
::polical::political
::polinator::pollinator
::polinators::pollinators
::politican::politician
::polyphonyic::polyphonic
::polysaccaride::polysaccharide
::polysaccharid::polysaccharide
::pomegranite::pomegranate
::popoulation::population
::popularaty::popularity
::populare::popular
::portayed::portrayed
::portraing::portraying
::portuguease::portuguese
::posessed::possessed
::posesses::possesses
::posessing::possessing
::posessions::possessions
::possable::possible
::possably::possibly
::posseses::possesses
::possesing::possessing
::possessess::possesses
::possibile::possible
::possiblility::possibility
::possiblilty::possibility
::possition::position
::postdam::Potsdam
::posthomous::posthumous
::postition::position
::potatoe::potato
::potrayed::portrayed
::poverful::powerful
::powerfull::powerful
::practially::practically
::practicaly::practically
::practicioner::practitioner
::practicioners::practitioners
::practicly::practically
::practioner::practitioner
::practioners::practitioners
::prairy::prairie
::praries::prairies
::pre-Colombian::pre-Columbian
::preample::preamble
::precedessor::predecessor
::preceeded::preceded
::preceeding::preceding
::precice::precise
::precident::precedent
::precurser::precursor
::predecesors::predecessors
::predicatble::predictable
::predomiantly::predominately
::prefering::preferring
::preferrably::preferably
::pregancies::pregnancies
::pregnent::pregnant
::preliferation::proliferation
::premeired::premiered
::premillenial::premillennial
::preminence::preeminence
::premonasterians::Premonstratensians
::preocupation::preoccupation
::prepair::prepare
::prepatory::preparatory
::preperation::preparation
::preperations::preparations
::preriod::period
::presance::presence
::presedential::presidential
::presense::presence
::prestigeous::prestigious
::presumabely::presumably
::presumibly::presumably
::pretection::protection
::prevelant::prevalent
::preverse::perverse
::previvous::previous
::priestood::priesthood
::primative::primitive
::primatively::primitively
::primatives::primitives
::primordal::primordial
::privelege::privilege
::priveleged::privileged
::priveleges::privileges
::privelige::privilege
::priveliged::privileged
::priveliges::privileges
::privelleges::privileges
::privilage::privilege
::priviledge::privilege
::priviledges::privileges
::privledge::privilege
::privledges::privileges
::probabilaty::probability
::probablistic::probabilistic
::probablly::probably
::probalibity::probability
::proccess::process
::proccessing::processing
::procedger::procedure
::proceedure::procedure
::processer::processor
::proclaimation::proclamation
::proclomation::proclamation
::professer::professor
::proffesed::professed
::proffesion::profession
::proffesional::professional
::proffesor::professor
::profilic::prolific
::progessed::progressed
::programable::programmable
::prohabition::prohibition
::prologomena::prolegomena
::prominance::prominence
::prominant::prominent
::prominantly::prominently
::promiscous::promiscuous
::promotted::promoted
::pronomial::pronominal
::pronouced::pronounced
::pronounched::pronounced
::pronounciation::pronunciation
::proove::prove
::prooved::proved
::prophacy::prophecy
::propmted::prompted
::propoganda::propaganda
::propogate::propagate
::propogates::propagates
::propogation::propagation
::propper::proper
::propperly::properly
::proprietory::proprietary
::proseletyzing::proselytizing
::protaganist::protagonist
::protaganists::protagonists
::protem::pro tem
::protocal::protocol
::protoganist::protagonist
::protrayed::portrayed
::protruberance::protuberance
::protruberances::protuberances
::prouncements::pronouncements
::provacative::provocative
::provinicial::provincial
::provisonal::provisional
::proximty::proximity
::pseudononymous::pseudonymous
::pseudonyn::pseudonym
::psuedo::pseudo
::psyhic::psychic
::ptogress::progress
::publically::publicly
::publicaly::publicly
::pucini::Puccini
::puertorrican::Puerto Rican
::puertorricans::Puerto Ricans
::pumkin::pumpkin
::puritannical::puritanical
::purposedly::purposely
::purpotedly::purportedly
::pursuade::persuade
::pursuaded::persuaded
::pursuades::persuades
::pususading::persuading
::pwn::own
::pyscic::psychic
::quantaty::quantity
::quantitiy::quantity
::quarantaine::quarantine
::questioms::questions
::questonable::questionable
::quicklyu::quickly
::quinessential::quintessential
::quitted::quit
::rabinnical::rabbinical
::racaus::raucous
::radiactive::radioactive
::radify::ratify
::rancourous::rancorous
::rarified::rarefied
::rasberry::raspberry
::reaccurring::recurring
::readmition::readmission
::realitvely::relatively
::reasearch::research
::rebiulding::rebuilding
::rebounce::rebound
::reccommend::recommend
::reccommended::recommended
::reccommending::recommending
::reccuring::recurring
::receeded::receded
::receeding::receding
::receieve::receive
::receivedfrom::received from
::rechargable::rechargeable
::recide::reside
::recided::resided
::recident::resident
::recidents::residents
::reciding::residing
::reciepents::recipients
::recipiant::recipient
::recipiants::recipients
::recogise::recognise
::recomending::recommending
::reconaissance::reconnaissance
::reconcilation::reconciliation
::reconnaissence::reconnaissance
::recontructed::reconstructed
::recordproducer::record producer
::recurrance::recurrence
::rediculous::ridiculous
::reedeming::redeeming
::reenforced::reinforced
::refedendum::referendum
::referiang::referring
::referrence::reference
::referrs::refers
::reffered::referred
::refference::reference
::refrers::refers
::refridgeration::refrigeration
::refridgerator::refrigerator
::refromist::reformist
::refusla::refusal
::regardes::regards
::regulaotrs::regulators
::regularily::regularly
::rehersal::rehearsal
::reicarnation::reincarnation
::reigining::reigning
::reknown::renown
::reknowned::renowned
::relatiopnship::relationship
::relected::reelected
::releive::relieve
::releived::relieved
::releiver::reliever
::relevence::relevance
::relevent::relevant
::relient::reliant
::religeous::religious
::religously::religiously
::relinqushment::relinquishment
::relitavely::relatively
::relized::realised
::reluctent::reluctant
::remaing::remaining
::rememberable::memorable
::rememberance::remembrance
::remembrence::remembrance
::remenant::remnant
::remenicent::reminiscent
::reminent::remnant
::reminescent::reminiscent
::reminscent::reminiscent
::reminsicent::reminiscent
::rendevous::rendezvous
::rendezous::rendezvous
::renedered::rende
::rentors::renters
::reoccurrence::recurrence
::reorganision::reorganisation
::repentence::repentance
::repentent::repentant
::repeteadly::repeatedly
::repetion::repetition
::repid::rapid
::reportadly::reportedly
::represantative::representative
::representive::representative
::representives::representatives
::reproducable::reproducible
::reprtoire::repertoire
::reptition::repetition
::resembelance::resemblance
::resembes::resembles
::resemblence::resemblance
::resignement::resignment
::resistable::resistible
::resistence::resistance
::resistent::resistant
::resollution::resolution
::respomse::response
::responce::response
::responsability::responsibility
::responsable::responsible
::responsibile::responsible
::ressemblance::resemblance
::ressemble::resemble
::ressembled::resembled
::ressemblence::resemblance
::ressembling::resembling
::resssurecting::resurrecting
::ressurrection::resurrection
::restaraunt::restaurant
::restaraunteur::restaurateur
::restaraunteurs::restaurateurs
::restaraunts::restaurants
::restauranteurs::restaurateurs
::restauration::restoration
::restauraunt::restaurant
::resteraunt::restaurant
::resteraunts::restaurants
::resturaunt::restaurant
::resurecting::resurrecting
::resurgance::resurgence
::retalitated::retaliated
::retalitation::retaliation
::reuse::re-use
::revaluated::reevaluated
::reversable::reversible
::rewitten::rewritten
::rewriet::rewrite
::rhymme::rhyme
::rhythem::rhythm
::rhythim::rhythm
::rigeur::rigueur
::rigourous::rigorous
::rininging::ringing
::rised::rose
::rockerfeller::Rockefeller
::rococco::rococo
::rocord::record
::rucuperate::recuperate
::rudimentatry::rudimentary
::rulle::rule
::rumers::rumors
::runnung::running
::russion::Russian
::ry::try
::rythem::rhythm
::rythim::rhythm
::rythyms::rhythms
::sacrafice::sacrifice
::sacreligious::sacrilegious
::sacrifical::sacrificial
::saidhe::said he
::saidit::said it
::saidt he::said the
::saidthat::said that
::saidthe::said the
::salery::salary
::sanctionning::sanctioning
::sandess::sadness
::sandwhich::sandwich
::sanhedrim::Sanhedrin
::sargant::sergeant
::sargeant::sergeant
::saterday::Saturday
::saterdays::Saturdays
::satisfactority::satisfactorily
::satric::satiric
::satrical::satirical
::satrically::satirically
::sattelite::satellite
::sattelites::satellites
::saught::sought
::saxaphone::saxophone
::scaleable::scalable
::scandanavia::Scandinavia
::scaricity::scarcity
::scavanged::scavenged
::schedual::schedule
::scholarstic::scholastic
::screenwrighter::screenwriter
::scrutinity::scrutiny
::scuptures::sculptures
::secratary::secretary
::secretery::secretary
::sedereal::sidereal
::seeked::sought
::segementation::segmentation
::seguoys::segues
::seige::siege
::seldomly::seldom
::sence::sense
::sensure::censure
::sentance::sentence
::separeate::separate
::sepina::subpoena
::sepulchure::sepulchre
::sercumstances::circumstances
::sergent::sergeant
::settelement::settlement
::severeal::several
::severley::severely
::severly::severely
::shaddow::shadow
::shesaid::she said
::shineing::shining
::shopkeeepers::shopkeepers
::shortwhile::short while
::shoudlnt::shouldn't
::should of::should have
::showinf::showing
::shreak::shriek
::shrinked::shrunk
::sideral::sidereal
::sieze::seize
::siezed::seized
::siezing::seizing
::siezure::seizure
::siezures::seizures
::siginificant::significant
::signficiant::significant
::signifacnt::significant
::signifantly::significantly
::significently::significantly
::signifigant::significant
::signifigantly::significantly
::signitories::signatories
::signitory::signatory
::silicone chip::silicon chip
::simalar::similar
::similarily::similarly
::similiar::similar
::similiarity::similarity
::similiarly::similarly
::simmilar::similar
::simpley::simply
::simplier::simpler
::sincerley::sincerely
::sincerly::sincerely
::singsog::singsong
::sionist::Zionist
::sionists::Zionists
::sixtin::Sistine
::skagerak::Skagerrak
::skateing::skating
::slaugterhouses::slaughterhouses
::smoothe::smooth
::smoothes::smooths
::sneeks::sneaks
::snese::sneeze
::socalism::socialism
::soilders::soldiers
::solatary::solitary
::soliliquy::soliloquy
::soluable::soluble
::sophicated::sophisticated
::sophmore::sophomore
::sorceror::sorcerer
::sorrounding::surrounding
::sot hat::so that
::sourth::south
::sourthern::southern
::souvenier::souvenir
::souveniers::souvenirs
::soveits::soviets
::soveits::soviets(x
::sovereignity::sovereignty
::soverignity::sovereignty
::spainish::Spanish
::speach::speech
::speciallized::specialised
::specifiying::specifying
::speciman::specimen
::spectaulars::spectaculars
::spendour::splendour
::spermatozoan::spermatozoon
::spoace::space
::sponser::sponsor
::sponsered::sponsored
::sponzored::sponsored
::spoonfulls::spoonfuls
::sportscar::sports car
::sppeches::speeches
::spreaded::spread
::sprech::speech
::spriritual::spiritual
::stablility::stability
::stainlees::stainless
::stateman::statesman
::statememts::statements
::steriods::steroids
::stilus::stylus
::stingent::stringent
::stiring::stirring
::stirrs::stirs
::stopry::story
::stornegst::strongest
::stradegies::strategies
::stradegy::strategy
::stratagically::strategically
::streemlining::streamlining
::strenghened::strengthened
::strenghtened::strengthened
::strengtened::strengthened
::strenous::strenuous
::strictist::strictest
::strikely::strikingly
::stubborness::stubbornness
::studdy::study
::stuggling::struggling
::subconsiously::subconsciously
::subjudgation::subjugation
::submachne::submachine
::subpecies::subspecies
::subsiduary::subsidiary
::substancial::substantial
::substituded::substituted
::substract::subtract
::substracted::subtracted
::substracting::subtracting
::substraction::subtraction
::substracts::subtracts
::subterranian::subterranean
::suburburban::suburban
::succceeded::succeeded
::succcesses::successes
::succedded::succeeded
::succeded::succeeded
::succeds::succeeds
::succesion::succession
::succesive::successive
::succsess::success
::suceeded::succeeded
::suceeding::succeeding
::suceeds::succeeds
::sucesion::succession
::sucesses::successes
::sucession::succession
::sucessive::successive
::sucessor::successor
::sucessot::successor
::sucidial::suicidal
::sufferage::suffrage
::sufferred::suffered
::sufferring::suffering
::sufficiant::sufficient
::suggestable::suggestible
::superintendant::superintendent
::suphisticated::sophisticated
::suplimented::supplemented
::suposedly::supposedly
::suposes::supposes
::suposing::supposing
::supplamented::supplemented
::suppliementing::supplementing
::supposingly::supposedly
::suppossed::supposed
::suprisingly::surprisingly
::suprize::surprise
::suprized::surprised
::suprizing::surprising
::suprizingly::surprisingly
::suroundings::surroundings
::surounds::surrounds
::surplanted::supplanted
::surpress::suppress
::surpressed::suppressed
::surprize::surprise
::surprized::surprised
::surprizing::surprising
::surprizingly::surprisingly
::surrended::surrendered
::surrepetitious::surreptitious
::surrepetitiously::surreptitiously
::surreptious::surreptitious
::surreptiously::surreptitiously
::surrundering::surrendering
::surveilence::surveillance
::surveill::surveil
::surveyer::surveyor
::surviver::survivor
::survivers::survivors
::survivied::survived
::suseptable::susceptible
::suseptible::susceptible
::suspention::suspension
::swaer::swear
::swaers::swears
::swepth::swept
::symetrical::symmetrical
::symetrically::symmetrically
::symetry::symmetry
::symettric::symmetric
::symmetral::symmetric
::symmetricaly::symmetrically
::synagouge::synagogue
::syncronization::synchronization
::synonomous::synonymous
::synonymns::synonyms
::synphony::symphony
::syphyllis::syphilis
::syrap::syrup
::sysmatically::systematically
::tabacco::tobacco
::targetted::targeted
::targetting::targeting
::tath::that
::tattooes::tattoos
::taxanomic::taxonomic
::taxanomy::taxonomy
::teached::taught
::techiniques::techniques
::technitian::technician
::technnology::technology
::tehw::the
::telelevision::television
::televize::televise
::tellt he::tell the
::temparate::temperate
::temperarily::temporarily
::temperment::temperament
::tempermental::temperamental
::tenacle::tentacle
::tenacles::tentacles
::tendacy::tendency
::tendancies::tendencies
::tendancy::tendency
::tendonitis::tendinitis
::tennisplayer::tennis player
::termoil::turmoil
::terrestial::terrestrial
::territorist::terrorist
::testiclular::testicular
::tghe::the
::tghis::this
::tshi::this
::th::the
::thatt he::that the
::thatthe::that the
::theather::theatre
::thecompany::the company
::theese::these
::thefirst::the first
::thegovernment::the government
::theh::the
::theif::thief
::their are::there are
::their is::there is
::theives::thieves
::themself::themselves
::themselfs::themselves
::thenew::the new
::there's is::theirs is
::thesame::the same
::thetwo::the two
::they're are::there are
::they're is::there is
::thgat::that
::thge::the
::thigsn::things
::thisyear::this year
::thiunk::think
::thoguth::thought
::threee::three
::threshhold::threshold
::throrough::thorough
::thw::the
::thyat::that
::ti"s::it's ; "
::tiget::tiger
::tihkn::think
::timne::time
::tiogether::together
::tje::the
::tjhe::the
::tjpanishad::upanishad
::tobbaco::tobacco
::toghether::together
::toldt he::told the
::tolerence::tolerance
::tolkein::Tolkien
::tommorow::tomorrow
::tommorrow::tomorrow
::toriodal::toroidal
::tormenters::tormentors
::torpeados::torpedoes
::torpedos::torpedoes
::tot he::to the
::tothe::to the
::toubles::troubles
::tounge::tongue
::towords::towards
::tradionally::traditionally
::traditionnal::traditional
::traditition::tradition
::trafficed::trafficked
::trafficing::trafficking
::trancendent::transcendent
::trancending::transcending
::transcendance::transcendence
::transcendant::transcendent
::transcendentational::transcendental
::transcripting::transcribing
::transending::transcending
::transistion::transition
::translater::translator
::translaters::translators
::transmissable::transmissible
::tremelo::tremolo
::tremelos::tremolos
::triathalon::triathlon
::triguered::triggered
::triology::trilogy
::troling::trolling
::troup::troupe
::truely::truly
::truley::truly
::trustworthyness::trustworthiness
::tryed::tried
::tthe::the
::twpo::two
::tyhat::that
::tyhe::the
::tyhe::they
::tyranical::tyrannical
::tyranies::tyrannies
::tyrany::tyranny
::tyrranies::tyrannies
::tyrrany::tyranny
::ubiquitious::ubiquitous
::ucould::could
::uise::use
::ukelele::ukulele
::ukranian::Ukrainian
::ultimely::ultimately
::unahppy::unhappy
::unanymous::unanimous
::unavailible::unavailable
::unballance::unbalance
::unbeleivable::unbelievable
::uncertainity::uncertainty
::unchallengable::unchallengeable
::unchangable::unchangeable
::uncompetive::uncompetitive
::unconcious::unconscious
::unconciousness::unconsciousness
::unconfortability::discomfort
::unconvential::unconventional
::undecideable::undecidable
::understoon::understood
::undert he::under the
::undesireable::undesirable
::undetecable::undetectable
::undoubtely::undoubtedly
::uneccesary::unnecessary
::unequalities::inequalities
::unforetunately::unfortunately
::unforgetable::unforgettable
::unforgiveable::unforgivable
::unfourtunately::unfortunately
::unihabited::uninhabited
::unilateraly::unilaterally
::unilatreal::unilateral
::unilatreally::unilaterally
::uninterruped::uninterrupted
::uninterupted::uninterrupted
::unitedstates::United States
::unitesstates::United States
::unmanouverable::unmanoeuvrable
::unmistakeably::unmistakably
::unneccesarily::unnecessarily
::unneccesary::unnecessary
::unneccessarily::unnecessarily
::unneccessary::unnecessary
::unnecesarily::unnecessarily
::unoffical::unofficial
::unoperational::nonoperational
::unoticeable::unnoticeable
::unplease::displease
::unpleasently::unpleasantly
::unplesant::unpleasant
::unprecendented::unprecedented
::unprecidented::unprecedented
::unrepentent::unrepentant
::unrepetant::unrepentant
::unrepetent::unrepentant
::unsubstanciated::unsubstantiated
::unsuccesful::unsuccessful
::unsuccessfull::unsuccessful
::unsucesful::unsuccessful
::unsucessful::unsuccessful
::unsucessfull::unsuccessful
::unsuprised::unsurprised
::unsuprising::unsurprising
::unsuprisingly::unsurprisingly
::unsuprized::unsurprised
::unsuprizing::unsurprising
::unsuprizingly::unsurprisingly
::unsurprized::unsurprised
::unsurprizing::unsurprising
::unsurprizingly::unsurprisingly
::untill::until
::untranslateable::untranslatable
::unuseable::unusable
::unusuable::unusable
::unwarrented::unwarranted
::unweildly::unwieldy
::unwieldly::unwieldy
::upcomming::upcoming
::upgradded::upgraded
::useage::usage
::usefull::useful
::usefuly::usefully
::useing::using
::usiing::using
::ususally::usually
::ut::but
::vaccum::vacuum
::vaccume::vacuum
::vacinity::vicinity
::vaguaries::vagaries
::vaialable::available
::vailidty::validity
::valetta::valletta
::valueable::valuable
::varient::variant
::varients::variants
::vasall::vassal
::vasalls::vassals
::vegatarian::vegetarian
::vegitable::vegetable
::vegitables::vegetables
::vehicule::vehicle
::vell::well
::venemous::venomous
::vengance::vengeance
::vengence::vengeance
::vermillion::vermilion
::versitilaty::versatility
::versitlity::versatility
::vetween::between
::vigilence::vigilance
::vigourous::vigorous
::villian::villain
::villification::vilification
::villify::vilify
::vincinity::vicinity
::violentce::violence
::visable::visible
::visably::visibly
::vitories::victories
::volcanoe::volcano
::volkswagon::Volkswagen
::volontary::voluntary
::volonteer::volunteer
::volonteered::volunteered
::volonteering::volunteering
::volonteers::volunteers
::volounteer::volunteer
::volounteered::volunteered
::volounteering::volunteering
::volounteers::volunteers
::vreity::variety
::vulnerablility::vulnerability
::vulnerible::vulnerable
::vyer::very
::vyre::very
::wa snot::was not
::waas::was
::wan tit::want it
::warantee::warranty
::wardobe::wardrobe
::warrent::warrant
::warrriors::warriors
::wass::was
::wayword::wayward
::weaponary::weaponry
::weas::was
::weilded::wielded
::wendsay::Wednesday
::wensday::Wednesday
::wereabouts::whereabouts
::werre::were
::wether::weather
::whant::want
::whants::wants
::whent he::when the
::wherease::whereas
::whereever::wherever
::wherre::where
::whicht he::which the
::whith::with
::whlch::which
::wholey::wholly
::wiegh::weigh
::wiew::view
::willbe::will be
::wille::will
::willingless::willingness
::windoes::windows
::wintery::wintry
::witha::with a
::withe::with
::witheld::withheld
::withing::within
::withold::withhold
::witht he::with the
::witht::with
::withthe::with the
::witn::with
::wiull::will
::wonderfull::wonderful
::workststion::workstation
::worls::world
::worstened::worsened
::would of::would have
::wouldbe::would be
::wresters::wrestlers
::writting::writing
::ws::was
::wuould::would
::wupport::support
::x-Box::Xbox
::xenophoby::xenophobia
::xomplex::complex
::yaching::yachting
::yatch::yacht
::yeilding::yielding
::yersa::years
::yoiu::you
::youare::you are
::youseff::yousef
::ytou::you
::zeebra::zebra
:C:Nto::Not
:C:nto::not
;------------------------------------------------------------------------------
;  Capitalise dates
;------------------------------------------------------------------------------
::monday::Monday
::tuesday::Tuesday
::wednesday::Wednesday
::thursday::Thursday
::friday::Friday
::saturday::Saturday
::sunday::Sunday
::january::January
::february::February
::april::April
::june::June
::july::July
::august::August
::september::September
::october::October
::november::November
::december::December
::fpga::FPGA
::pcie::PCIe
::icd::ICD
::fw::FW
::scadapp::SCADApp
::scad::SCAD
;------------------------------------------------------------------------------
; Anything below this point was added to the script by the user via the Win+H hotkey.
;------------------------------------------------------------------------------
::releasses::releases
::ahven't::haven't
::ahvent::haven't
::arent'::aren't
::arent::aren't
::arn't::aren't
::cant'::can't
::cant::can't
::childrens::children's
::companys::company's
::coudln't::couldn't
::coudn't::couldn't
::couldnt::couldn't
::coudlnt::couldn't
::didint::didn't
::didnt::didn't
::dint::didn't
::didtn::didn't
::dno't::don't
::dnot::don't
::do'nt::don't
::deosnt::doesn't
::doens't::doesn't
::doens::doesn't
::doenst::doesn't
::does't::doesn't
::doesnt::doesn't
::doest::doesn't
::doestn::doesn't
::doent::doesn't
::dosnt::doesn't
::dont::don't
::dosen't::doesn't
::dosn't::doesn't
::dotn::don't
::gentlemens::gentlemen's
::hadnt::hadn't
::hasnt::hasn't
::havent::haven't
::heres::here's
::hes::he's
::hsan't::hasn't
::i'd::I'd
::i'll::I'll
::Ill'::I'll
::i'm::I'm
::Im'::I'm
::i've::I've
::id'::I'd
::Id'::I'd
::im::I'm
::isnt'::isn't
::isnt::isn't
::istn::isn't
::Istn::Isn't
::its'::it's
::iv'e::I've
::ive::I've
::lets::let's
::odnt::don't
::taht's::that's
::thast::that's
::thats::that's
::theres::there's
::theyd::they'd
::theyll::they'll
::theyl'l::they'll
::theyll'::they'll
::theyre::they're
::theyr'e::they're
::theyre'::they're
::theyve::they've
::theyv'e::they've
::theyve'::they've
::ti's::it's
::todays::today's
::w'ere::we're
::wasnt::wasn't
::wer'e::we're
::wern't::weren't
::werent::weren't
::whats::what's
::whats'::what's
::wnot::won't
::wo'nt::won't
::womens::women's
::wont::won't
::wotn::won't
::woudln't::wouldn't
::woudlnt::wouldn't
::woudn't::wouldn't
::wouldnt::wouldn't
::yorue::you're
::you'er::you're
::youd::you'd
::youe'r::you're
::youer::you're
::youll::you'll
::your'e::you're
::youre::you're
::youv'e::you've
::youve::you've
::repetative::repetitive
::repetetive::repetitive
::deterant::deterrent
::deterants::deterrents
::inprecise::imprecise
::god::God
::ram::RAM
::rescheulde::reschedule
::awhiel::awhile
::locaation::location
::determing::determining
::offerred::offered
::documention::documentation
::ar eyou::are you
::al lthe::all the
::interestin::interest in
::inteeresting::interesting
::implmenetation::implementation
::incompatibiility::incompatibility
::intesreting::interesting
::releated::related
::resset::reset
::confusgin::confusing
::pilling::piling
::your a::you're a
::your an::you're an
::your her::you're her
::your here::you're here
::your his::you're his
::your my::you're my
::your the::you're the
::your their::you're their
::your your::you're your
::you're own::your own
::Suggetsions::Suggestions
::specificed::specified
::docn::documentation
::docs::documents
::doc::document
::votlages::voltages
::can not::cannot
::ackolwedgement::acknowledgement
::questionaire::questionnaire
::ppl::people
::a the::at the
::ist he::is the
::Hoewver::However
::dsp::DSP
::Techncially::Technically
::tehcncailly::technically
::spreadhsset::spreadsheet
::confirmmed::confirmed
::implmeneted::implemented
::Unforntuately::Unfortunately
::spreadhseet::spreadsheet
::trasnceivers::transceivers
::utliamtely::ultimately
::implmenet::implement
::Unfortuantley::Unfortunatley
::respresnted::represented
::challenege::challenge
::appercaite::appreciate
::forsee::foresee
::jtag::JTAG
::avstx8::AvSTx8
::avstx32::AvSTx32
::opencl::OpenCL
::schedeuled::scheduled
::jesd::JESD
::orf::for
::seqeuencing::sequencing
::abuot::aboyout
::intpretation::intepretation
::developemtn::development
::gogin::going
::hweover::however
::deos::does
::wuold::woyould
::hsoudl::should
::emif::EMIF
::seomthing::soemthing
::bets::best
::fpgas::FPGAs
::webex::WebEx
::soluations::solutions
::appreacited::appreciated
::Unfortuatnely::Unfortunately
::pelsae::please
::xcvr::XCVR
::xcvrs::XCVRs
::mhz::Mhz
::quartus::Quartus
::cuodl::could
::dma::DMA
::htme::them
::Soc::SoC
::seotmhing::something
::usb::USB
::awalys::always
::makgni::making
::simplist::simplest
::defintinon::definition
::fof::for
::ta::at
::determininstic::deterministic
::Hye::Hey
::th e::the
::npoe::nope
::speicifc::specifIc
::tho::though
::Godo::Good
::resopnses::responses
::reposne::response
::instatiating::instantiating
::gbe::GbE
::Unforutntely::Unfortunately
::Ocne::Once
::Welcoem::Welcome
::osemthing::something
::Stya::Stay
::udnersatnding::understanding
::undertsands::understands
::transceviers::transceivers
::shceudled::scheduled
::doucmentaotin::documentation
::diffuclty::difficulty
::Vinec::Vince
::asap::ASAP
::direcotires::directorIes
::partioin::partition
::Quratus::Quartus
::hcnage::change
::opinons::opinIons
::Unforutnately::Unfortunately
::Unforutnatley::Unfortunately
::shcematic::schematic
::shcematics::schematics
::hwy::why
::adddressing::addressing
::disucsison::discussion
::Produciton::ProductIon
::doucments::documents
::adivsigin::advising
::opporotunity::opportunity
::cocks::clocks
::piont::poInt
::deisng::design
::hps::HPS
::cusomter::customer
::conecnered::concerned
::iopll::IOPLL
::Suggesitons::SuggestIons
::Vicne::Vince
::pgorammer::programmer
::Antony::Anthony
::knowledgable::knowledgeable
::begininning::beginning
::sesen::sense
::concnered::concerned
::calcualtions::calculations
::discoved::discovered
::possiblites::possibIlites
::disadvantes::disadvantages
::problsme::problems
::componets::components
::axi::AXI
::hcnaged::changed
::consdiering::considering
::windriver::Wind River
::WindRiver::Wind River
::levaing::leaving
::leaveing::leaving
::mpsoc::MPSoC
::artitechture::architecture
::environemental::environemental
::vxworks::VxWorks
::interpretting::interpreting
::feb::Feb
::Porbably::Probably
::defitintion::definition
::reporsitory::repository
::apparoch::appraoch
::depednencey::dependencey
::minimim::minimum
::fukcing::fucking
::oover::over
::ecrypted::encrypted
::NTO::NOT
::canabalize::cannibalize
::xilinx::Xilinx
::sepcfiication::specification
::Unfrotuantely::Unfortunately
::thuoght::thought
::imprsesion::impression
::unfotunatley::unfortunately
::bascially::basically
::checkins::check-ins
::inprecisely::imprecisely
::youa re::you are
::asychronously::asynchronously
::depdenency::dependency
::incredably::incredibly
::os::so
;------------------------------------------------------------------------------
; Generated Misspellings - the main list
;------------------------------------------------------------------------------
#include %A_ScriptDir%\generatedwords.ahk
#If