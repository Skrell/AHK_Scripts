; c = case sensitive
; c1 = ignore the case that was typed, always use the same case for output
; * = immediate change (no need for space, period, or enter)
; ? = triggered even when the character typed immediately before it is alphanumeric
; r = raw output


; dummyFunction1() {
    ; static dummyStatic1 := VD.init()
; }
; the auto-exec section ends at the first hotkey/hotstring or return or exit or at the script end - whatever comes first; function definitions get ignored by the execution flow.
#NoEnv
#SingleInstance
#InstallMouseHook
#InstallKeybdHook
#UseHook
#HotString EndChars ()[]{}:;,.?!`n `t
#MaxhotKeysPerInterval 500
#KeyHistory 25

; #include %A_ScriptDir%\_VD.ahk
; DLL
hVirtualDesktopAccessor := DllCall("LoadLibrary", "Str", A_ScriptDir . "\VirtualDesktopAccessor.dll", "Ptr")

GetDesktopCountProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "GetDesktopCount", "Ptr")
GoToDesktopNumberProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "GoToDesktopNumber", "Ptr")
GetCurrentDesktopNumberProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "GetCurrentDesktopNumber", "Ptr")
IsWindowOnCurrentVirtualDesktopProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "IsWindowOnCurrentVirtualDesktop", "Ptr")
IsWindowOnDesktopNumberProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "IsWindowOnDesktopNumber", "Ptr")
MoveWindowToDesktopNumberProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "MoveWindowToDesktopNumber", "Ptr")
IsPinnedWindowProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "IsPinnedWindow", "Ptr")
GetDesktopNameProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "GetDesktopName", "Ptr")
SetDesktopNameProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "SetDesktopName", "Ptr")
CreateDesktopProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "CreateDesktop", "Ptr")
RemoveDesktopProc := DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", "RemoveDesktop", "Ptr")

Global CurrentDesktop := 1

#include %A_ScriptDir%\UIAutomation-main\Lib\UIA_Interface.ahk

SendMode, Input ; It injects the whole keystroke atomically, reducing the window where logical/physical can disagree
SetKeyDelay, -1, -1
SetMouseDelay, -1
SetBatchLines -1
SetWinDelay   10
SetControlDelay 10
; SetKeyDelay is not obeyed by SendInput; there is no delay between keystrokes in that mode.
; This same is true for Send when SendMode Input is in effect.

Global mouseMoving                 := False
Global skipCheck                   := False
Global cycling                     := False
Global ValidWindows                := []
Global GroupedWindows              := []
Global PrevActiveWindows           := []
Global minWinArray                 := []
Global allWinArray                 := []
Global cycleCount                  := 1
Global startHighlight              := False
Global border_thickness            := 4
Global border_color                := 0xFF00FF
Global hitTAB                      := False
Global hitTilde                    := False
Global SearchingWindows            := False
Global UserInputTrimmed            := ""
Global memotext                    := ""
Global totalMenuItemCount          := 0
Global onlyTitleFound              := ""
Global nil
Global CancelClose                 := False
Global lastWinMinHwndId            := 0x999999
Global DrawingRect                 := False
Global LclickSelected              := False
Global StopRecursion               := False
Global currMonHeight               := 0
Global currMonWidth                := 0
Global LbuttonEnabled              := True
Global X_PriorPriorHotKey          :=
Global StopAutoFix                 := False
Global disableEnter                := False
Global disableWheeldown            := False
Global pauseWheel                  := False
Global EVENT_SYSTEM_MENUPOPUPSTART := 0x0006
Global EVENT_SYSTEM_MENUPOPUPEND   := 0x0007
Global TimeOfLastHotkeyTyped               := A_TickCount
Global lbX1
Global lbX2
Global currentMon                  := 0
Global previousMon                 := 0
Global targetDesktop               := 0
Global currentPath                 := ""
Global prevPath                    := ""
Global _winCtrlD                   := ""
Global MbuttonIsEnter              := False
Global textBoxSelected             := False
Global WindowTitleID               :=
Global keys                        := "abcdefghijklmnopqrstuvwxyz"
Global numbers                     := "0123456789"
Global DoubleClickTime             := DllCall("GetDoubleClickTime")
Global isWin11                     := DetectWin11()
Global TaskBarHeight               := 0
Global lastHotkeyTyped             := ""
Global DraggingWindow              := False

; --- Config ---
UseWorkArea  := true   ; true = monitor work area (ignores taskbar). false = full monitor.
SnapRange    := 20     ; px: distance from edge to begin snapping
BreakAway    := 64     ; px: while snapped, drag this far further TOWARD the outside to push past edge
ReleaseAway  := 24     ; px: while snapped, drag this far AWAY from the edge to release the snap

; Skip dragging these classes (taskbar/desktop)
skipClasses := { "Shell_TrayWnd":1, "Shell_SecondaryTrayWnd":1, "Progman":1, "WorkerW":1 }

; === Settings ===
BlockClicks := true    ; true = block clicks outside active window, false = let clicks pass through
Opacity     := 215     ; 255=opaque black; try 200 to "dim" instead of fully black
Margin      := 0       ; expands the hole around the active window by this many pixels

; === Globals ===
blackoutOn := false

black1Hwnd := ""
black2Hwnd := ""
black3Hwnd := ""
black4Hwnd := ""
firstDraw  := True

Process, Priority,, High

UIA := UIA_Interface() ; Initialize UIA interface
UIA.ConnectionTimeout := 6000
; cacheRequest := UIA.CreateCacheRequest()
; cacheRequest.TreeScope := 5 ; Set TreeScope to include the starting element and all descendants as well
; cacheRequest.AddProperty("ControlType") ; Add all the necessary properties that DumpAll uses: ControlType, LocalizedControlType, AutomationId, Name, Value, ClassName, AcceleratorKey
; cacheRequest.AddProperty("LocalizedControlType")
; cacheRequest.AddProperty("Name")
; cacheRequest.AddProperty("ClassName")

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

; Create 4 mask GUIs (top, left, right, bottom)
CreateMaskGui(index, ByRef hWndOut) {
    Global BlockClicks, Opacity, black1Hwnd, black2Hwnd, black3Hwnd, black4Hwnd
    clickStyle := BlockClicks ? "" : "+E0x20"
    ; Build a variable name like "hWnd1", "hWnd2", etc.
    hwndVarName := "black" index "Hwnd"
    Gui, %index%: +AlwaysOnTop -Caption +ToolWindow %clickStyle% +Hwnd%hwndVarName%
    Gui, %index%: Color, Black
    WinSet, Transparent, %Opacity%, ahk_id %hwndVarName%
    hWndOut := hwndVarName
    Gui, %index%: Hide
}

CreateMaskGui(1, hTop)
CreateMaskGui(2, hLeft)
CreateMaskGui(3, hRight)
CreateMaskGui(4, hBottom)

SysGet, MonNum, MonitorPrimary
SysGet, MonitorWorkArea, MonitorWorkArea, %MonNum%
SysGet, MonCount, MonitorCount
Sysget, totalDesktopWidth, 78
Sysget, totalDesktopHeight, 79

Loop, %MonCount%
{
    SysGet, MonitorName, MonitorName, %A_Index%
    SysGet, Monitor, Monitor, %A_Index%
    SysGet, MonitorWorkArea, MonitorWorkArea, %A_Index%
    ;MsgBox, Monitor:`t#%A_Index%`nName:`t%MonitorName%`nLeft:`t%MonitorLeft% (%MonitorWorkAreaLeft% work)`nTop:`t%MonitorTop% (%MonitorWorkAreaTop% work)`nRight:`t%MonitorRight% (%MonitorWorkAreaRight% work)`nBottom:`t%MonitorBottom% (%MonitorWorkAreaBottom% work)
    If (MonitorWorkAreaLeft < 0) {
        Global G_DisplayLeftEdge := A_ScreenWidth-totalDesktopWidth
    }
    Else {
        Global G_DisplayRightEdge := A_ScreenWidth
        Global G_DisplayLeftEdge  := 0
    }
}

Tooltip, Total Number of Monitors is %MonCount% with Primary being %MonNum% with edges: %G_DisplayLeftEdge% - %G_DisplayRightEdge%
sleep 3000
Tooltip, % "Current Mon is " GetCurrentMonitorIndex() " and Win11 is " isWin11
sleep 2000
; Tooltip, Path to ahk %A_AhkPath%
; sleep 2000
Tooltip,

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
    #Persistent
    #WinActivateForce
    ListLines Off
    SetBatchLines -1
    DetectHiddenWindows, Off

    WinWait, ahk_class #32768,, 3

    If ErrorLevel
        ExitApp

    SendInput, {DOWN}
    ; https://www.autohotkey.com/board/topic/11157-popup-menu-sometimes-doesnt-have-focus/page-2
    ; MouseMove, %x%, %y%

    ; Input, SingleKey, L1, {Lbutton}{ESC}{ENTER}, *
    Return

    ~ENTER::
        ExitApp
    Return

    ~ESC::
        ExitApp
    Return

    ~*LBUTTON::
        ExitApp
    Return

    SPACE::
        SendInput, {DOWN}
    Return
)

ExprAltUp =
(
    #NoEnv
    #NoTrayIcon
    #KeyHistory 0
    #Persistent
    #WinActivateForce
    SetBatchLines -1
    ListLines Off
    DetectHiddenWindows, Off

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

ExprTimeout =
(
    #NoEnv
    #NoTrayIcon
    #SingleInstance, Off
    #Persistent
    #KeyHistory 0
    SetBatchLines -1
    ListLines Off

    tooltip, Navigating Up...
    sleep, 1000
    tooltip
    ExitApp
)

OnExit("PreventRecur")

;------------------------------------------------------------------------------
; AUto-COrrect TWo COnsecutive CApitals.
; Disabled by default to prevent unwanted corrections such as IfEqual->Ifequal.
; To enable it, remove the /*..*/ symbols around it.
; From Laszlo's script at http://www.autohotkey.com/forum/topic9689.html
;------------------------------------------------------------------------------
; The first line of code below is the set of letters, digits, and/or symbols
; that are eligible for this type of correction.  Customize if you wish:

ReAssignHotkeys()

HotKey ~/,  FixSlash
HotKey ~',  Hoty ;'
HotKey ~?,  Hoty
HotKey ~!,  Hoty
HotKey ~`,, Hoty
HotKey ~.,  Marktime_Hoty
HotKey ~_,  Hoty
HotKey ~-,  Hoty

Send #^{Left}
sleep, 50
Send #^{Left}
sleep, 50
Send #^{Left}
sleep, 50
Send #^{Left}
sleep, 50

WinGetPos, , , , TaskBarHeight, ahk_class Shell_TrayWnd

;EVENT_SYSTEM_FOREGROUND := 0x3
DllCall("user32\SetWinEventHook", UInt,0x3, UInt,0x3, Ptr,0, Ptr,RegisterCallback("OnWinActiveChange"), UInt,0, UInt,0, UInt,0, Ptr)
 winhookevent := DllCall("SetWinEventHook", "UInt", EVENT_SYSTEM_MENUPOPUPSTART, "UInt", EVENT_SYSTEM_MENUPOPUPSTART, "Ptr", 0, "Ptr", (lpfnWinEventProc := RegisterCallback("OnPopupMenu", "")), "UInt", 0, "UInt", 0, "UInt", WINEVENT_OUTOFCONTEXT := 0x0000 | WINEVENT_SKIPOWNPROCESS := 0x0002)

If (MonCount > 1) {
    currentMon := MWAGetMonitorMouseIsIn()
    previousMon := currentMon
}
SetTimer mouseTrack, 10
SetTimer keyTrack, 1

Return

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

Startup:
    Menu, Tray, Togglecheck, Run at startup
    IfExist, %A_Startup%/AutoCorrect.lnk
        FileDelete, %A_Startup%/AutoCorrect.lnk
    Else
        FileCreateShortcut, % H_Compiled ? A_AhkPath : A_ScriptFullPath, %A_Startup%/AutoCorrect.lnk
Return

Tray_SingleLclick:
    msgbox You left-clicked tray icon
Return

Reload_label:
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

Hoty:
    CapCount := (IsPriorHotKeyCapital() && A_TimeSincePriorHotkey<999) ? CapCount+1 : 1 ; note that CapCount is ALWAYS at least 1
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
    If      (disableEnter && !IsGoogleDocWindow() && (!StopAutoFix && inStr(keys, X_PriorPriorHotKey, False) && A_PriorHotKey == "~/" && A_ThisHotkey == "~Space" && A_TimeSincePriorHotkey<999)) {
        Send, % "{BS}{BS}{?}{SPACE}"
        disableEnter := False
    }
    Else If (disableEnter && !IsGoogleDocWindow() && (!StopAutoFix && inStr(keys, X_PriorPriorHotKey, False) && A_PriorHotKey == "~/" && A_ThisHotkey == "Enter" && A_TimeSincePriorHotkey<999)) {
        Send, % "{BS}{?}{ENTER}"
        disableEnter := False
    }
    If IsPriorHotKeyLowerCase()   ; as long as a letter key is pressed we record the priorprior hotkey
        X_PriorPriorHotKey := Substr(A_PriorHotkey,2,1) ; record the letter key pressed
    If IsPriorHotKeyCapital()
        X_PriorPriorHotKey := Substr(A_PriorHotkey,3,1) ; record only the letter key pressed If captialized
Return
;------------------------------------------------------------------------------
IsPriorHotKeyLetterKey() {
    Return (IsPriorHotKeyCapital() || IsPriorHotKeyLowerCase())
}
IsThisHotKeyLetterKey() {
    Return (IsThisHotKeyCapital() || IsThisHotKeyLowerCase())
}
IsPriorHotKeyCapital() {
    Global keys
    Return (StrLen(A_PriorHotkey) == 3 && SubStr(A_PriorHotKey,1,1)!="!" && SubStr(A_PriorHotKey,2,1)="+" && inStr(keys, Substr(A_PriorHotkey,3,1), False))
}
IsPriorHotKeyLowerCase() {
    Global keys
    Return (StrLen(A_PriorHotkey) == 2 && inStr(keys, Substr(A_PriorHotkey,2,1), False))
}
IsThisHotKeyCapital() {
    Global keys
    Return (StrLen(A_ThisHotKey) == 3 && SubStr(A_ThisHotKey,1,1)!="!" && SubStr(A_ThisHotKey,2,1)="+" && inStr(keys, Substr(A_ThisHotKey,3,1), False))
}
IsThisHotKeyLowerCase() {
    Global keys
    Return (StrLen(A_ThisHotKey) == 2 && inStr(keys, Substr(A_ThisHotKey,2,1), False))
}

ReAssignHotkeys() {
    Global keys
    Global numbers

    Loop Parse, keys
    {
        HotKey, ~+%A_LoopField%, Marktime_Hoty_FixSlash, On
    }
    Loop Parse, keys
    {
        HotKey,  ~%A_LoopField%, Marktime_Hoty_FixSlash, On
    }
    Loop Parse, numbers
    {
        HotKey,  ~%A_LoopField%, Marktime_Hoty_FixSlash, On
    }
    Hotkey,   Ctrl, DoNothing,     Off
    Hotkey,      ., DoNothing,     Off
    HotKey, ~$Ctrl, LaunchWinFind, On
    Hotkey,     ~., Marktime_Hoty, On
    Return
}

DeAssignHotkeys() {
    Global keys
    Global numbers

    Loop Parse, keys
    {
        HotKey, +%A_LoopField%, DoNothing, On
    }
    Loop Parse, keys
    {
        HotKey,  %A_LoopField%, DoNothing, On
    }
    Loop Parse, numbers
    {
        HotKey,  %A_LoopField%, DoNothing, On
    }
    HotKey, ~$Ctrl, LaunchWinFind, Off
    Hotkey,     ~., Marktime_Hoty, Off
    Hotkey,   Ctrl, DoNothing,     On
    Hotkey,      ., DoNothing,     On
    Return
}

DoNothing:
Return

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
        return False
    }

    if (SubStr(version, 1, 4) = "10.0" && buildNumber >= 22000)
        return True
    else
        return False
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
    Global prevActiveWindows
    Global StopRecursion
    Global UIA
    static exEl, shellEl, listEl

    If !StopRecursion && !hitTab {
        DetectHiddenWindows, Off
        loop 500 {
            WinGetClass, vWinClass, % "ahk_id " hWnd
            WinGetTitle, vWinTitle, % "ahk_id " hWnd
            If (vWinClass != "" || vWinTitle != "" || WinExist("ahk_class #32768"))
                break
            sleep, 1
        }

        WinGet, vWinStyle, Style, % "ahk_id " hWnd
        If (   vWinClass == "#32768"
            || vWinClass == "Autohotkey"
            || vWinClass == "AutohotkeyGUI"
            || vWinClass == "SysShadow"
            || vWinClass == "TaskListThumbnailWnd"
            || vWinClass == "Windows.UI.Core.CoreWindow"
            || vWinClass == "Progman"
            || vWinClass == "WorkerW"
            || vWinClass == "tooltips_class32"
            || vWinClass == "OperationStatusWindow"
            || (InStr(vWinClass, "Shell",False) && InStr(vWinClass, "TrayWnd",False))
            || vWinClass == ""
            || vWinTitle == ""
            || ((vWinStyle & 0xFFF00000 == 0x94C00000) && vWinClass != "#32770")
            || !WinExist("ahk_id " hWnd)) {
            If (vWinClass == "#32768" || vWinClass == "OperationStatusWindow") {
                WinSet, AlwaysOnTop, On, ahk_id %hWnd%
            }
            Return
        }

        LbuttonEnabled := False
        SetTimer, keyTrack,   Off
        SetTimer, mouseTrack, Off

        If ( !HasVal(prevActiveWindows, hWnd) || vWinClass == "#32770" || vWinClass == "CabinetWClass") {

            WinGet, state, MinMax, ahk_id %hWnd%
            If (state > -1 && vWinTitle != "" && MonCount > 1) {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := IsWindowOnCurrMon(hWnd, currentMon)
                If !currentMonHasActWin {
                    WinActivate, ahk_id %hWnd%
                    Send, #+{Left}
                }
            }

            loop, 100 {
                ControlGetFocus, initFocusedCtrl, ahk_id %hWnd%
                If (initFocusedCtrl != "")
                    break
                sleep, 1
            }

            If (vWinClass == "#32770") {
                WinSet, AlwaysOnTop, On, ahk_id %hWnd%
            }
            Else If (vWinClass != "#32770" && WinExist("ahk_class #32770")) {
                WinSet, AlwaysOnTop, On, ahk_id %hWnd%
                WinSet, AlwaysOnTop, Off, ahk_class #32770
                WinSet, AlwaysOnTop, Off, ahk_id %hWnd%
            }

            If (vWinClass == "wxWindowNR") {
                loop, 150 {
                    ControlFocus, Edit1, ahk_id %hWnd%
                    ControlGetFocus, testCtrlFocus , ahk_id %hWnd%
                    If (testCtrlFocus == "Edit1")
                        break
                    sleep, 2
                }
                Send, {Backspace}
            }
            ; tooltip, here we go

            If (InStr(vWinTitle, "Save", False) && vWinClass != "#32770") {
                WinSet, AlwaysOnTop, On,  ahk_id %hWnd%
                WinSet, AlwaysOnTop, Off, ahk_id %hWnd%
                LbuttonEnabled := True
                Return
            }

            ;EVENT_SYSTEM_FOREGROUND := 0x3
            ; static _ := DllCall("user32\SetWinEventHook", UInt,0x3, UInt,0x3, Ptr,0, Ptr,RegisterCallback("OnWinActiveChange"), UInt,0, UInt,0, UInt,0, Ptr)

            If !WinExist("ahk_id " hWnd) || !WinActive("ahk_id " hWnd) {
                SetTimer, keyTrack,   On
                SetTimer, mouseTrack, On
                LbuttonEnabled := True
                Return
            }

            WinGet, proc, ProcessName, ahk_id %hWnd%
            If (proc == "Everything.exe")
                SendEvent, {Blind}{vkFF} ; send a dummy key (vkFF = undefined key)

            Critical, On
            prevActiveWindows.push(hWnd)
            Critical, Off

            WaitForFadeInStop(hWnd)

            SendCtrlAdd(hWnd,,,vWinClass, initFocusedCtrl)

            ; OutputVar1 := 0
            ; OutputVar2 := 0
            ; OutputVar3 := 0
            ; OutputVar4 := 0
            ; OutputVar6 := 0
            ; OutputVar8 := 0

            ; loop 200 {
                ; ControlGet, OutputVar1, Visible ,, SysListView321, ahk_id %hWnd%
                ; ControlGet, OutputVar2, Visible ,, DirectUIHWND2,  ahk_id %hWnd%
                ; ControlGet, OutputVar3, Visible ,, DirectUIHWND3,  ahk_id %hWnd%
                ; ControlGet, OutputVar4, Visible ,, DirectUIHWND4,  ahk_id %hWnd%
                ; ControlGet, OutputVar6, Visible ,, DirectUIHWND6,  ahk_id %hWnd%
                ; ControlGet, OutputVar8, Visible ,, DirectUIHWND8,  ahk_id %hWnd%
                ; If (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1 || OutputVar4 == 1 || OutputVar6 == 1 || OutputVar8 == 1)
                    ; break
                ; sleep, 1
            ; }

            ; tooltip, %OutputVar1% - %OutputVar2% - %OutputVar3% - %OutputVar4% - %OutputVar6% - %OutputVar8%
            ; If (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1 || OutputVar4 == 1 || OutputVar6 == 1 || OutputVar8 == 1 ) {
                ; If (OutputVar1 == 1) {
                    ; TargetControl := "SysListView321"
                    ; ; ControlGet, ctrlNnHwnd, Hwnd,, SysListView321, ahk_id %hWnd%
                    ; ControlGetPos, ctrlX, ctrlY, ctrlW, ctrlH, SysListView321, ahk_id %hWnd%
                    ; WinGetPos, winX, winY, winW, winH, ahk_id %hWnd%
                    ; ; tooltip, %ctrlW% - %winW%
                    ; If (ctrlW < floor(0.5*winW)) {
                        ; LbuttonEnabled := True
                        ; Return
                    ; }
                    ; Else {
                        ; loop, 100 {
                            ; ControlFocus, %TargetControl%, ahk_id %hWnd%
                            ; ControlGetFocus, testCtrlFocus , ahk_id %hWnd%
                            ; If (testCtrlFocus == TargetControl)
                                ; break
                            ; sleep, 1
                        ; }
                    ; }
                ; }
                ; Else If (((OutputVar2 == 1 && OutputVar3 == 1) && !OutputVar4 && !OutputVar6 && !OutputVar8)
                    ; && (vWinClass == "CabinetWClass" || vWinClass == "#32770")) {

                    ; OutHeight2 := 0
                    ; OutHeight3 := 0
                    ; ControlGetPos, , , , OutHeight2, DirectUIHWND2, ahk_id %hWnd%, , , ,
                    ; ControlGetPos, , , , OutHeight3, DirectUIHWND3, ahk_id %hWnd%, , , ,
                    ; If (OutHeight2 > OutHeight3)
                        ; TargetControl := "DirectUIHWND2"
                    ; Else
                        ; TargetControl := "DirectUIHWND3"
                ; }

                ; Critical, On
                ; ; tooltip, init focus is %initFocusedCtrl% and target is %TargetControl%
                ; If ((vWinClass == "#32770" || vWinClass == "CabinetWClass") && initFocusedCtrl != TargetControl) {
                    ; If (OutputVar3 == 1) {
                        ; WaitForExplorerLoad(hWnd, True)
                        ; loop, 100 {
                            ; ControlFocus, %TargetControl%, ahk_id %hWnd%
                            ; ControlGetFocus, testCtrlFocus , ahk_id %hWnd%
                            ; If (testCtrlFocus == TargetControl)
                                ; break
                            ; sleep, 1
                        ; }
                    ; }
                    ; Else
                        ; WaitForExplorerLoad(hWnd)
                ; }

                ; If !WinExist("ahk_id " hWnd) || !WinActive("ahk_id " hWnd) {
                    ; SetTimer, keyTrack,   On
                    ; SetTimer, mouseTrack, On
                    ; LbuttonEnabled := True
                    ; Critical, Off
                    ; Return
                ; }
                ; Else {
                    ; WinGet, finalActiveHwnd, ID, A
                    ; If (hWnd == finalActiveHwnd) {
                        ; BlockInput, On
                        ; Send, {Ctrl UP}
                        ; Send, ^{NumpadAdd}
                        ; Send, {Ctrl UP}
                        ; BlockInput, Off

                        ; If (vWinClass == "#32770" || vWinClass == "CabinetWClass")
                            ; sleep, 125

                        ; If (initFocusedCtrl != "" && initFocusedCtrl != TargetControl) {
                            ; loop, 500 {
                                ; ControlFocus , %initFocusedCtrl%, ahk_id %hWnd%
                                ; ControlGetFocus, testCtrlFocus , ahk_id %hWnd%
                                ; If (testCtrlFocus == initFocusedCtrl)
                                    ; break
                                ; sleep, 1
                            ; }
                            ; If (GetKeyState("Lbutton", "P")) {
                                ; SetTimer, keyTrack,   On
                                ; SetTimer, mouseTrack, On
                                ; LbuttonEnabled := True
                                ; Critical, Off
                                ; Return
                            ; }
                        ; }
                    ; }
                ; }
                ; Critical, Off
            ; }

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
                    DetectHiddenWindows, Off
                    SetTimer, keyTrack,   On
                    SetTimer, mouseTrack, On
                    Return
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
    if !root
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
    loop 100 {
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
        sleep, 2
    }
    CoordMode, Mouse, screen
    Return
}

PreventRecur() {
    Global StopRecursion, hWinEventHook
    StopRecursion := True
    nCheck := DllCall( "UnhookWinEvent", Ptr,hWinEventHook )
    DllCall( "CoUninitialize" )
Return
}

; CapsCorrectionFront($) {
    ; tofix := $.Value(2)
    ; StringLower, fixed, tofix
    ; Send, % $.Value(1) fixed $.Value(3)
; Return
; }

; CapsCorrectionBack($) {
    ; tofix := $.Value(2)
    ; StringLower, fixed, tofix
    ; Send, % $.Value(1) fixed
; Return
; }

; QuestionMarkorrection($) {
    ; Send, % $.Value(1) "?" $.Value(2)
; Return
; }

~^Enter::
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
Return

!Mbutton::
    Send, {Enter}
Return

#If ((IsConsoleWindow() && IsMouseOnLeftSide()) || textBoxSelected) && !MouseIsOverTitleBar()
WheelDown::
    ; tooltip, % IsConsoleWindow() "-" IsMouseOnLeftSide() "-" textBoxSelected
    StopRecursion := True
    SetTimer, MbuttonTimer, Off
    Send, {DOWN}
    sleep, 125
    SetTimer, MbuttonTimer, -1
    StopRecursion := False
Return

WheelUp::
    StopRecursion := True
    SetTimer, MbuttonTimer, Off
    Send, {UP}
    sleep, 125
    SetTimer, MbuttonTimer, -1
    StopRecursion := False
Return
#If

#If !MouseIsOverTitleBar() && !disableWheeldown && !pauseWheel
~WheelUp::
    StopRecursion := True
    pauseWheel := True
    MouseGetPos, , , wuID, wuCtrl
    WinGetClass, wuClass, ahk_id %wuID%

    If (wuClass == "Shell_TrayWnd" && !mouseMoving && wuCtrl != "ToolbarWindow323" && wuCtrl != "TrayNotifyWnd1")
    {
        Send #^{Left}
        sleep, 200
    }
    Else If (wdClass != "ProgMan" && wdClass != "WorkerW" && wdClass != "Notepad++" && (wuCtrl == "SysListView321" || wuCtrl == "DirectUIHWND2" || wuCtrl == "DirectUIHWND3")) {
        ControlFocus , %wuCtrl%, % "ahk_id " wdID
        ControlGetFocus, TargetControl, A
        If (TargetControl == wuCtrl) {
            BlockInput, On
            If !GetKeyState("Control") {
                Send, {Ctrl Up}
            }
            sleep, 100
            Send, ^{NumpadAdd}
            sleep, 100
            If !GetKeyState("Control") {
                Send, {Ctrl Up}
            }
            BlockInput, Off
        }
    }
    pauseWheel := False
    StopRecursion := False
Return
#If

#If MouseIsOverTitleBar() || disableWheeldown
WheelDown::
    disableWheeldown := True
    MouseGetPos, , , wdID,
    WinMinimize, ahk_id %wdID%
    sleep, 500
    disableWheeldown := False
Return
#If

#If !MouseIsOverTitleBar() && !disableWheeldown && !pauseWheel
~WheelDown::
    StopRecursion := True
    pauseWheel := True
    MouseGetPos, , , wdID, wuCtrl
    WinGetClass, wdClass, ahk_id %wdID%

    If (wdClass == "Shell_TrayWnd" && !mouseMoving && wuCtrl != "ToolbarWindow323" && wuCtrl != "TrayNotifyWnd1")
    {
        Send #^{Right}
        sleep, 200
    }
    Else If (wdClass != "ProgMan" && wdClass != "WorkerW" && wdClass != "Notepad++" && (wuCtrl == "SysListView321" || wuCtrl == "DirectUIHWND2" || wuCtrl == "DirectUIHWND3")) {
        ControlFocus , %wuCtrl%, % "ahk_id " wdID
        ControlGetFocus, TargetControl, A
        If (TargetControl == wuCtrl) {
            BlockInput, On
            If !GetKeyState("Control") {
                Send, {Ctrl Up}
            }
            sleep, 100
            Send, ^{NumpadAdd}
            sleep, 100
            If !GetKeyState("Control") {
                Send, {Ctrl Up}
            }
            BlockInput, Off
        }
    }
    pauseWheel := False
    StopRecursion := False
Return
#If

IsConsoleWindow() {
    WinGetClass, targetClass, A
    If (targetClass == "mintty" || targetClass == "CASCADIA_HOSTING_WINDOW_CLASS" || targetClass == "ConsoleWindowClass ")
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

#If !MbuttonIsEnter ; && !MouseIsOverTitleBar()
MButton::
    Global DraggingWindow
    StopRecursion := True
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off
    Hotkey, *Rbutton, DoNothing, On
    Hotkey, Mbutton & Rbutton, DoNothing, On

    wx0 := 0
    wy0 := 0
    ww  := 0
    wh  := 0
    virtwx0 := 0
    virtwy0 := 0
    offsetX := 0
    offsetY := 0
    windowSnapped := False
    TL := False
    TR := False
    BL := False
    BR := False
    snapShotX := 0
    snapShotY := 0
    adjustSize := False
    isRbutton  := False
    switchingBackToMove := False
    switchingBacktoResize := False
    skipAlwaysOnTop := False

    MouseGetPos, mx0, my0, hWnd, ctrl, 2
    checkClickMx := mx0
    checkClickMy := my0

    If (!hWnd)
        return

    BlockInput, MouseMove
    WinGet, isMax, MinMax, ahk_id %hWnd%
    WinGetClass, cls, ahk_id %hWnd%
    If (skipClasses.HasKey(cls) || isMax == 1)
        return

    WinGetPosEx(hWnd, wx0, wy0, ww, wh, offsetX, offsetY)
    If (ww = "" || wh = "")
        return

    snapState := ""   ; "", "left", "right"
    mxPrev := mx0         ; track prior mouse X to know approach direction
    myPrev := my0         ; track prior mouse X to know approach direction

    leftWinEdge   := wx0
    topWinEdge    := wy0
    rightWinEdge  := wx0 + ww
    bottomWinEdge := wy0 + wh

    ; msgbox, % leftWinEdge "," rightWinEdge "-" topWinEdge "," bottomWinEdge ":" offsetX " & " offsetY

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
    while GetKeyState("MButton", "P")
    {
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

        MouseGetPos, mx, my, mbuttonHwnID

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
            Blockinput, MouseMove
            WinSet, Transparent, 225, ahk_id %hWnd%
            sleep, 8
            WinSet, Transparent, 200, ahk_id %hWnd%
            sleep, 8
            WinSet, Transparent, 185, ahk_id %hWnd%
            Blockinput, MouseMoveOff
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
            Else If (BL || BR) && (dragVert == "up"   || dragVert == "down")  {
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

        ; Sleep, 1
    }
    Critical, Off

    If (MouseIsOverTitleBar(mx, my) && (abs(checkClickMx - mx0) <= 5) && (abs(checkClickMy - my0) <= 5)) {
        WinSet, Transparent, Off, ahk_id %hWnd%
        GoSub, SwitchDesktop
    }
    Else If (wh/abs(monB-monT) > 0.95)
        WinMove, ahk_id %hWnd%, , , %monT%, , abs(monB-monT)+2*abs(offsetY) + 1

    If !skipAlwaysOnTop
        WinSet, AlwaysOnTop, Off, ahk_id %hWnd%
    WinSet, Transparent, Off, ahk_id %hWnd%
    StopRecursion := False
    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
    Hotkey, *Rbutton, DoNothing, Off
    Hotkey, Mbutton & Rbutton, DoNothing, Off
    DraggingWindow := False
Return
#If

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
    monL := NumGet(mi,  4, "Int"), monT := NumGet(mi,  8, "Int")
    monR := NumGet(mi, 12, "Int"), monB := NumGet(mi, 16, "Int")
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

^+Esc::
    Run, C:\Program Files\SystemInformer\SystemInformer.exe
Return

CapsLock::
    TimeOfLastHotkeyTyped := A_TickCount
    Send {Delete}
    lastHotkeyTyped := "CapsLock"
Return

#If (!WinActive("ahk_exe notepad++.exe") && !WinActive("ahk_exe Everything.exe") && !WinActive("ahk_exe Code.exe") && !WinActive("ahk_exe EXCEL.EXE") && !IsEditFieldActive())
^+d::
    StopAutoFix := True
    SetTimer, keyTrack, Off
    Send, {Down}
    sleep, 10
    Send, {Home}{Home}
    sleep, 10
    Send, +{up}
    ; Send, {End}
    ; Send, +{Home}+{Home}+{Home}
    sleep, 10
    Send, {Delete}
    Hotstring("Reset")
    StopAutoFix := False
    SetTimer, keyTrack, On
Return

^d::
    StopAutoFix := True
    SetTimer, keyTrack, Off
    Send, {End}
    sleep, 10
    Send, +{Home}+{Home}+{Home}
    sleep, 10
    store := Clip()
    tooltip, %store%
    sleep, 10
    Send, {End}
    sleep, 10
    Send, {Enter}
    sleep, 10
    Send, {Home}
    Clip(store)
    Hotstring("Reset")
    StopAutoFix := False
    SetTimer, keyTrack, On
    sleep, 500
Return
#If

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

!+'::
    Critical, On
    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := """" . store . """"
    Else
        store := """" . store . """" . " "
    Clip(store)
    Critical, Off
Return

!+[::
    Critical, On
    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "{" . store . "}"
    Else
        store := "{" . store . "} "
    Clip(store)
    Critical, Off
Return

!+]::
    Critical, On
    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "{" . store . "}"
    Else
        store := "{" . store . "} "
    Clip(store)
    Critical, Off
Return

!+<::
    Critical, On
    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "<" . store . ">"
    Else
        store := "<" . store . "> "
    Clip(store)
    Critical, Off
Return

!+>::
    Critical, On
    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "<" . store . ">"
    Else
        store := "<" . store . "> "
    Clip(store)
    Critical, Off
Return

!+(::
    Critical, On
    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "(" . store . ")"
    Else
        store := "(" . store . ") "
    Clip(store)
    Critical, Off
Return

!+)::
    Critical, On
    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "(" . store . ")"
    Else
        store := "(" . store . ") "
    Clip(store)
    Critical, Off
Return

!+b::
    Critical, On
    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "\b" . store . "\b"
    Else
        store := "\b" . store . "\b "
    Clip(store)
    Critical, Off
Return

!+5::
    Critical, On
    store := Clip()
    len := StrLen(store)
    foundSpace := SubStr(store, len-1, 1) == " " ? True : False
    store := Trim(store)
    If !foundSpace
        store := "%" . store . "%"
    Else
        store := "%" . store . "% "
    Clip(store)
    Critical, Off
Return

$!Space::
    StopAutoFix := True
    Send, {Left}
    ; StopAutoFix := False
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


#If disableEnter
Enter::
    GoSub, FixSlash
    disableEnter := False
Return
#If

#If !disableEnter && (WinActive("ahk_class CabinetWClass") || WinActive("ahk_class #32770"))
~Enter::
    ControlGetFocus, entCtrl, A
    WinGetClass, entCl, A
    WinGetTitle, entTi, A
    WinGet, entID, ID, A
    If     (entCl == "CabinetWClass" && InStr(entCtrl, "Edit", True))
        || (entCl == "#32770" && InStr(entCtrl, "Edit", True) && (InStr(entTi, "Save", True) || InStr(entTi, "Open", True))) {

        Keywait, Enter, U T3

        ; WaitForExplorerLoad(entID)
        WinGet, checkID, ID, A
        If (checkID == entID)
            SendCtrlAdd(entID, , , entCl)
            ; Send, ^{NumpadAdd}
    }
Return

~$F2::
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

#+s::Return

~Space::
    GoSub, Marktime_Hoty_FixSlash
    lastHotkeyTyped := "Space"
Return

; duplicate hotkey in case shift is accidentally  held as a result of attempting to type a '?'
~+Space::
    GoSub, Marktime_Hoty_FixSlash
    lastHotkeyTyped := "Space"
Return

~^Backspace::
    Hotstring("Reset")
Return

~$Backspace::
    TimeOfLastHotkeyTyped := A_TickCount
    lastHotkeyTyped := "Backspace"
Return

~$Delete::
    TimeOfLastHotkeyTyped := A_TickCount
Return

~$Left::
    X_PriorPriorHotKey :=
Return

~$Right::
    X_PriorPriorHotKey :=
Return


; Ctl+Tab in chrome to goto recent
prevChromeTab()
{
    Global StopRecursion
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
            Hotkey, x, DoNothing, On
            GoSub, DrawRect

            loop {
                tooltip Close `"%escTitle%`" ? ;"
                sleep, 1
                If !GetKeyState("Esc","P")
                    break
                If GetKeyState("x","P") {
                    Tooltip, Canceled!
                    ClearRect()
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
                    tooltip, Waiting for `"%escTitle%`" to close... ; "
                    If !WinExist("ahk_id " . escHwndID) {
                        ClearRect(escHwndID)
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
                            ClearRect(escHwndID)
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

    SetTimer, EscTimer, -150
    escTitle_old  := escTitle
    escHwndID_old := escHwndID
    StopRecursion := False
    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On
Return

#If

EscTimer:
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
Return

!1::
    StopRecursion := True
    SetTimer, keyTrack,   Off
    SetTimer, mouseTrack, Off
    GoSub, SwitchToVD1
    StopRecursion := False
    SetTimer, keyTrack,   On
    SetTimer, mouseTrack, On
Return

SwitchToVD1:
    CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
    testDesktop := CurrentDesktop
    while (CurrentDesktop < 1) {
        Send #^{Right}
        while (CurrentDesktop == testDesktop) {
            sleep, 100
            testDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
        }
        CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
    }
    while (CurrentDesktop > 1) {
        Send #^{Left}
        while (CurrentDesktop == testDesktop) {
            sleep, 100
            testDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
        }
        CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
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
Return

SwitchToVD2:
    If  (GetDesktopCount() >= 2) {
        CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
        testDesktop := CurrentDesktop
        while (CurrentDesktop < 2) {
            Send #^{Right}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
            }
            CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
        }
        while (CurrentDesktop > 2) {
            Send #^{Left}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
            }
            CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
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
Return

SwitchToVD3:
    If  (GetDesktopCount() >= 3) {
        CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
        testDesktop := CurrentDesktop
        while (CurrentDesktop < 3) {
            Send #^{Right}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
            }
            CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
        }
        while (CurrentDesktop > 3) {
            Send #^{Left}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
            }
            CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
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
Return

SwitchToVD4:
    If  (GetDesktopCount() >= 4) {
        CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
        testDesktop := CurrentDesktop
        while (CurrentDesktop < 4) {
            Send #^{Right}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
            }
            CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
        }
        while (CurrentDesktop > 4) {
            Send #^{Left}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
            }
            CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
        }
    }
Return

; #MaxThreadsBuffer Off
;https://superuser.com/questions/1261225/prevent-alttab-from-switching-to-minimized-windows
Altup:
    Global cycling
    Global cycleCount
    Global ValidWindows
    Global GroupedWindows
    Global MonCount
    Global startHighlight
    Global hitTAB
    Global LclickSelected

    cycling        := False
    If !hitTAB {
        Critical, On
        cycleCount     := 1
        ValidWindows   := []
        GroupedWindows := []
        startHighlight := False
        LclickSelected := False
        Critical, Off
        Return
    }
    Else {
        Critical, On
        BlockKeyboard(True)
        WinGet, actWndID, ID, A
        If (LclickSelected && (GroupedWindows.length() > 2) && actWndID != ValidWindows[1]) {
            If (startHighlight) {
                BlockInput, On
                GoSub, FadeInWin1
                BlockInput, Off
            }
        }
        Else {
            If (GetKeyState("x","P") || actWndID == ValidWindows[1] || GroupedWindows.length() <= 1) {
                If (GetKeyState("x","P")) {
                    BlockInput, On
                    GoSub, ResetWins
                    BlockInput, Off
                }
            }
            Else If (startHighlight && (GroupedWindows.length() > 2)  && actWndID != ValidWindows[1]) {
                BlockInput, On
                GoSub, FadeInWin2
                BlockInput, Off
            }
        }
    }

    cycleCount     := 1
    ValidWindows   := []
    GroupedWindows := []
    startHighlight := False
    hitTAB         := False
    LclickSelected := False
    BlockKeyboard(False)
    Critical, Off
    ; ClearRect()
    ; tooltip,
Return

;============================================================================================================================
FadeInWin1:
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

FadeInWin2:
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

; #MaxThreadsPerHotkey 2
$!Tab::
$!+Tab::
If !hitTAB {
    firstDraw := True
    textBoxSelected := False
    StopRecursion  := True
    SetTimer, mouseTrack, Off
    SetTimer, keyTrack,   Off

    Cycle()

    Gui, GUI4Boarder: Hide
    WinSet, Transparent, 255, ahk_id %black1Hwnd%
    WinSet, Transparent, 255, ahk_id %black2Hwnd%
    WinSet, Transparent, 255, ahk_id %black3Hwnd%
    WinSet, Transparent, 255, ahk_id %black4Hwnd%
    GoSub, Altup
    GoSub, HideMasks

    SetTimer, mouseTrack, On
    SetTimer, keyTrack,   On
    StopRecursion := False
}
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

    tempWinActID := HandleWindowsWithSameProcessAndClass(activeProcessName, activeClassName)

    If !LclickSelected
        lastActWinID := tempWinActID
    Else
        LclickSelected := False

    WinSet, AlwaysOnTop, On, ahk_id %lastActWinID%

    Gui, GUI4Boarder: Hide
    If (cycleCount > 2)
        GoSub, FadeInWin2

    WinSet, AlwaysOnTop, Off, ahk_id %lastActWinID%
    WinActivate, ahk_id %lastActWinID%

    ValidWindows   := []
    GroupedWindows := []

    SetTimer, mouseTrack, On
    SetTimer, keyTrack,   On
    StopRecursion := False
Return

#If hitTAB
!x::
    tooltip, Canceled Operation!
    Gui, GUI4Boarder: Hide
    Gui, WindowTitle: Destroy
    GoSub, ResetWins
    sleep, 1000
    tooltip,
Return
#If

!Lbutton::
    If hitTab {
        LclickSelected := True
        MouseGetPos, , , _winIdD,
        WinActivate, ahk_id %_winIdD%
        WinGetTitle, actTitle, ahk_id %_winIdD%
        WinGet, pp, ProcessPath , ahk_id %_winIdD%

        GoSub, DrawRect
        WindowTitleID := DrawWindowTitlePopup(actTitle, pp)
        KeyWait, LAlt, U
        GoSub, FadeOutWindowTitle
        GoSub, Altup
        SetTimer, mouseTrack, On
        SetTimer, keyTrack,   On
    }
    Else If hitTilde {
        LclickSelected := True
        MouseGetPos, , , _winIdD,
        WinGetTitle, actTitle, ahk_id %_winIdD%
        WinGet, pp, ProcessPath , ahk_id %_winIdD%

        WinActivate, ahk_id %_winIdD%
        lastActWinID := _winIdD

        GoSub, DrawRect
        WindowTitleID := DrawWindowTitlePopup(actTitle, pp, True)
        KeyWait, LAlt, U
        GoSub, FadeOutWindowTitle
        SetTimer, mouseTrack, On
        SetTimer, keyTrack,   On
    }
    Else If (A_PriorHotkey == A_ThisHotkey && (A_TimeSincePriorHotkey < 550)) {
        Send, {Alt UP}
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
    DynaRun(ExprTimeout, ExprTimeout_Name)
Return

FadeOutWindowTitle:
    Global WindowTitleID

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
    Global cycling
    Global cycleCount
    Global ValidWindows
    Global GroupedWindows
    Global MonCount
    Global startHighlight
    Global hitTAB
    Global LclickSelected
    Global WindowTitleID
    Global firstDraw

    prev_exe :=
    prev_cl  :=

    hitTAB := True

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
                currentMonHasActWin := IsWindowOnCurrMon(hwndID, currentMon)
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
                                    GoSub, UpdateMasks
                                    If !GetKeyState("LAlt","P") || GetKeyState("q","P") {
                                        GroupedWindows := []
                                        ValidWindows   := []
                                        Critical, Off
                                        Return
                                    }
                                }
                            }
                            If (GroupedWindows.MaxIndex() == 3 && failedSwitch) {
                                WinActivate, % "ahk_id " hwndID
                                cycleCount := 3
                                Critical, Off
                                ; GoSub, DrawRect
                                GoSub, UpdateMasks
                            }
                            If ((GroupedWindows.MaxIndex() > 3) && (!GetKeyState("LAlt","P") || GetKeyState("q","P"))) {
                                GroupedWindows := []
                                ValidWindows   := []
                                Critical, Off
                                Return
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
        Return
    }

    KeyWait, Tab, U
    cycling := True
    firstDraw := False

    If cycling {
        loop {
            If (GroupedWindows.length() >= 2 && cycling)
            {
                KeyWait, Tab, D  T0.1
                If !ErrorLevel
                {
                    If !GetKeyState("Lshift","P") {
                        If (cycleCount == GroupedWindows.MaxIndex())
                            cycleCount := 1
                        Else
                            cycleCount += 1
                    }
                    Else If GetKeyState("Lshift","P") {
                        If (cycleCount == 1)
                            cycleCount := GroupedWindows.MaxIndex()
                        Else
                            cycleCount -= 1
                    }

                    ; WinSet, AlwaysOnTop, On, ahk_class tooltips_class32
                    WinActivate, % "ahk_id " GroupedWindows[cycleCount]
                    WinWaitActive, % "ahk_id " GroupedWindows[cycleCount], , 2
                    ; GoSub, DrawRect
                    GoSub, UpdateMasks
                    WinGetTitle, tits, % "ahk_id " GroupedWindows[cycleCount]
                    WinGet, pp, ProcessPath , % "ahk_id " GroupedWindows[cycleCount]

                    WindowTitleID := DrawWindowTitlePopup(tits, pp)
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
    Return
}

ClearRect(hwnd := "") {
    Global DrawingRect
    Global Highlighter
    Global GUI4Boarder

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

; ------------------  ChatGPT ------------------------------------------------------------------
HideMasks:
    transVal   := 255
    iterations := 10
    Critical, On
    Loop, %iterations%
    {
        currentVal := transVal - (floor(255/iterations))
        WinSet, Transparent, %currentVal%, ahk_id %black1Hwnd%
        WinSet, Transparent, %currentVal%, ahk_id %black2Hwnd%
        WinSet, Transparent, %currentVal%, ahk_id %black3Hwnd%
        WinSet, Transparent, %currentVal%, ahk_id %black4Hwnd%
        transVal := transVal - (floor(255/iterations))
        sleep, 10
    }
    Loop, 4
        Gui, %A_Index%: Hide
    Critical, Off
Return

UpdateMasks:
    WinGet, hA, ID, A
    if (!hA)
        return
    if (hA = hTop || hA = hLeft || hA = hRight || hA = hBottom)
        return

    ; Get the monitor WORK AREA (excludes taskbar) for the active window's monitor
    if (!GetMonitorRectsForWindow(hA, mx, my, mw, mh, wx2, wy2, ww2, wh2))
        return
    wRight  := wx2 + ww2
    wBottom := wy2 + wh2

    ; Active window rect (expanded slightly)
    ; WinGetPos, wx, wy, ww, wh, ahk_id %hA%
    WinGetPosEx(hA, wx, wy, ww, wh)
    if (wx = "")
        return
    wx -= Margin, wy -= Margin, ww += 2*Margin, wh += 2*Margin
    holeL := Max(wx2, wx)
    holeT := Max(wy2, wy)
    holeR := Min(wRight,  wx + ww)
    holeB := Min(wBottom, wy + wh)

    ; Mask only within the WORK AREA (taskbar region is untouched, so it's visible & clickable)
    ; TOP panel (across full work area width, above hole)
    DrawBlackBar(1, wx2, wy2, ww2, Max(0, holeT - wy2))
    ; LEFT panel
    DrawBlackBar(2, wx2, holeT, Max(0, holeL - wx2), Max(0, holeB - holeT))
    ; RIGHT panel
    DrawBlackBar(3, holeR, holeT, Max(0, wRight - holeR), Max(0, holeB - holeT))
    ; BOTTOM panel
    DrawBlackBar(4, wx2, holeB, ww2, Max(0, wBottom - holeB))

    If firstDraw {
        transVal := ceil(Opacity/5)
        incrValue := 5
    }
    Else {
        transVal := Opacity
        incrValue := 1
    }

    loop, %incrValue%
    {
        WinSet, Transparent, %transVal%, ahk_id %black1Hwnd%
        WinSet, AlwaysOnTop, On, ahk_id %black1Hwnd%

        WinSet, Transparent, %transVal%, ahk_id %black2Hwnd%
        WinSet, AlwaysOnTop, On, ahk_id %black2Hwnd%

        WinSet, Transparent, %transVal%, ahk_id %black3Hwnd%
        WinSet, AlwaysOnTop, On, ahk_id %black3Hwnd%

        WinSet, Transparent, %transVal%, ahk_id %black4Hwnd%
        WinSet, AlwaysOnTop, On, ahk_id %black4Hwnd%

        transVal += ceil(Opacity/5)
        sleep, 3
    }
Return

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

DrawBlackBar(guiIndex, x, y, w, h) {
    If (w <= 0 || h <= 0) {
        Gui, %guiIndex%: Hide
    } else {
        Gui, %guiIndex%: Show, x%x% y%y% w%w% h%h% NoActivate
    }
}

Max(a,b) {
    Return a > b ? a : b
}
Min(a,b) {
    Return a < b ? a : b
}
; -------------------------------------------------------------------------------------------

#If MouseIsOverTaskbarBlank()
~Lbutton::
    ; StopRecursion     := True
    MouseGetPos, lbX1, lbY1,
    If (A_PriorHotkey == A_ThisHotkey
        && (A_TimeSincePriorHotkey < 550)
        && (abs(lbX1-lbX2) < 20 && abs(lbY1-lbY2) < 20)) {
        run, explorer.exe
        ; StopRecursion     := False
        Return
    }

    KeyWait, LButton, U T5
    MouseGetPos, lbX2, lbY2,
    ; StopRecursion     := False
Return
#If

#If MouseIsOverTaskbarWidgets()
~^Lbutton::
    StopRecursion := True
    SetTimer, mouseTrack, Off
	SetTimer, keyTrack,   Off

    DetectHiddenWindows, Off
    SysGet, MonCount, MonitorCount

    KeyWait, Lbutton, U T3

    sleep, 125
    WinGet, winList, List,
    loop % winList
    {
        hwndID := winList%A_Index%
        If IsAltTabWindow(hwndId) {
            WinGet, targetID, ID, ahk_id %hwndID%
            break
        }
    }
    WinGetClass, targetClass, ahk_id %targetID%

    If (targetClass != "Windows.UI.Core.CoreWindow" && targetClass != "TaskListThumbnailWnd") {
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
                    currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
                    If !currentMonHasActWin
                        WinMinimize, ahk_id %hwndId%
                }
            }
            Else If (isMin == 0) {
                If (MonCount > 1) {
                    currentMon := MWAGetMonitorMouseIsIn()
                    currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
                    If currentMonHasActWin
                        WinActivate, ahk_id %hwndId%
                }
                Else {
                    WinActivate, ahk_id %hwndId%
                }
            }
        }
    }
    WinActivate, ahk_id %targetID%

    StopRecursion := False
    SetTimer, mouseTrack, On
    SetTimer, keyTrack,   On
Return
#If

#If MouseIsOverTitleBar()
^LButton::
    Global currentMon, previousMon
    DetectHiddenWindows, Off
    StopRecursion := True
    SetTimer, mouseTrack, Off

    Critical, On
    MouseGetPos, mx1, my1, actID,
    Send, {Lbutton DOWN}

    KeyWait, Lbutton, U T5

    MouseGetPos, mx2, my2, ,
    Send, {Lbutton UP}
    Critical, Off

    If (MonCount > 1)
        currentMon := MWAGetMonitorMouseIsIn()

    If (abs(mx2-mx1) < 15 && abs(my2-my1) < 15) {
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
                    currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
                    If currentMonHasActWin
                        ; WinSet, AlwaysOnTop, On, ahk_id %hwndId%
                        ; WinSet, AlwaysOnTop, Off, ahk_id %hwndId%
                        WinActivate, ahk_id %hwndId%
                }
                Else {
                    ; WinSet, AlwaysOnTop, On, ahk_id %hwndId%
                    ; WinSet, AlwaysOnTop, Off, ahk_id %hwndId%
                    WinActivate, ahk_id %hwndId%
                }
            }
        }
        WinActivate, ahk_id %actID%
        WinSet, AlwaysOnTop, Off, ahk_id %actID%
        WinActivate, ahk_id %actID%
    }
    Else {
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
                    currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
                    If !currentMonHasActWin {
                        WinActivate, ahk_id %hwndId%
                        Send, #+{Left}
                    }
                }
                Else {
                    break
                }
            }
        }
        WinActivate, ahk_id %actID%
        WinSet, AlwaysOnTop, Off, ahk_id %actID%
        WinActivate, ahk_id %actID%
        previousMon := currentMon
    }

    StopRecursion := False
    SetTimer, mouseTrack, On
Return
#If

#MaxThreadsPerHotkey 2
#If (!VolumeHover() && LbuttonEnabled && !IsOverException() && !hitTAB && !MouseIsOverTitleBar() && !MouseIsOverTaskbarBlank())
~LButton::
    tooltip,
    HotString("Reset")
    textBoxSelected := False
    SetTimer, SendCtrlAddLabel, Off
    SetTimer, keyTrack, Off
    SetTimer, mouseTrack, Off

    CoordMode, Mouse, Screen
    MouseGetPos, lbX1, lbY1, _winIdD, _winCtrlD
    WinGetClass, wmClassD, ahk_id %_winIdD%
    Gui, GUI4Boarder: Hide
    initTime := A_TickCount

    If (    A_PriorHotkey == A_ThisHotkey
        && (A_TimeSincePriorHotkey < DoubleClickTime)
        && (abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25)
        && (_winCtrlD == "SysListView321" || _winCtrlD == "DirectUIHWND2" || _winCtrlD == "DirectUIHWND3" || _winCtrlD == "DirectUIHWND4" || _winCtrlD == "DirectUIHWND6" || _winCtrlD == "DirectUIHWND8")) {

        ; tooltip, %A_TimeSincePriorHotkey% - %prevPath% - %LBD_HexColor1% - %LBD_HexColor2% - %LBD_HexColor3%  - %X1% %X2% %Y1% %Y2% - %_winCtrlD% - %A_ThisHotkey% - %A_PriorHotkey%
        If ((LBD_HexColor1 == 0xFFFFFF) && (LBD_HexColor2 == 0xFFFFFF) && (LBD_HexColor3  == 0xFFFFFF)) {
            If (_winCtrlD == "SysListView321") {
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
            currentPath    := ""
            loop 100 {
                currentPath := GetExplorerPath(_winIdD)
                If (currentPath != "" && prevPath != currentPath )
                    break
                sleep, 1
            }
            ; tooltip, %A_TimeSincePriorHotkey% - %prevPath% - %currentPath%
            If (prevPath != "" && currentPath != "" && prevPath != currentPath) {
                SendCtrlAdd(_winIdU, prevPath, currentPath, wmClassD)
            }

            LbuttonEnabled     := True
            SetTimer, keyTrack, On
            SetTimer, mouseTrack, On
            Return
        }
        Else {
            tooltip, sending

            SendCtrlAdd(_winIdD,,,wmClassD)
            SetTimer, keyTrack, On
            SetTimer, mouseTrack, On
            sleep, 250
            LbuttonEnabled     := True
            Return
        }
    }

    prevPath := ""
    If (wmClassD == "CabinetWClass" || wmClassD == "#32770") {
        loop 100 {
            prevPath := GetExplorerPath(_winIdD)
            If (prevPath != "")
                break
            sleep, 1
        }
    }

    LBD_HexColor1 := 0x000000
    LBD_HexColor2 := 0x000000
    LBD_HexColor3 := 0x000000
    CoordMode, Pixel, Screen
    lbX1 -= 3
    lbY1 -= 3
    loop 3 {
        PixelGetColor, LBD_HexColor%A_Index%, %lbX1%, %lbY1%, RGB
        lbX1 += 1
        lbY1 += 1
    }
    CoordMode, Mouse, Screen

    KeyWait, LButton, U T5

    MouseGetPos, lbX2, lbY2, _winIdU, _winCtrlU

    rlsTime := A_TickCount
    timeDiff := rlsTime - initTime

    ; tooltip, %timeDiff% ms - %_winCtrlD% - %LBD_HexColor1% - %LBD_HexColor2% - %LBD_HexColor3% - %lbX1% - %lbX2%

    If ((abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25)
        && (timeDiff < DoubleClickTime/2)
        && (InStr(_winCtrlD,"SysListView32",True) || _winCtrlD == "DirectUIHWND2" || _winCtrlD == "DirectUIHWND3" || _winCtrlD == "DirectUIHWND4" || _winCtrlD == "DirectUIHWND6" || _winCtrlD == "DirectUIHWND8")
        && (LBD_HexColor1 == 0xFFFFFF) && (LBD_HexColor2 == 0xFFFFFF) && (LBD_HexColor3  == 0xFFFFFF)) {

        SetTimer, SendCtrlAddLabel, -125
    }
    Else If ((abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25)
        && (InStr(_winCtrlD,"SysHeader32",True) || _winCtrlD == "DirectUIHWND2" || _winCtrlD == "DirectUIHWND3" || _winCtrlD == "DirectUIHWND4" || _winCtrlD == "DirectUIHWND6" || _winCtrlD == "DirectUIHWND8")
        && (LBD_HexColor1 != 0xFFFFFF) && (LBD_HexColor2 != 0xFFFFFF) && (LBD_HexColor3 != 0xFFFFFF)) {

        try {
            pt := UIA.ElementFromPoint(lbX2,lbY2,False)

            If (pt.CurrentControlType == 50031) {
                If (wmClassD == "#32770" || _winCtrlD == "DirectUIHWND3")
                    ControlFocus, %_winCtrlD%, ahk_id %_winIdU%

                Send, ^{NumpadAdd}
                Return
            } ; this specific combination is needed for the "Name" column ONLY
            Else If (pt.CurrentControlType == 50033 && (_winCtrlD == "DirectUIHWND2" || _winCtrlD == "DirectUIHWND3" || _winCtrlD == "DirectUIHWND4" || _winCtrlD == "DirectUIHWND6" || _winCtrlD == "DirectUIHWND8")) {

                Send, ^{NumpadAdd}
                Return
            }
            Else If (pt.CurrentControlType == 50035) { ; this most likely would indicate an SysListView based window like 7-zip
                ControlFocus, SysListView321, ahk_id %_winIdU%
                If !isWin11
                    Send, {F5}

                Send, ^{NumpadAdd}
                Return
            }
        } catch e {
            tooltip, TIMED OUT!!!!
            UIA :=  ;// set to a different value
            ; VarSetCapacity(UIA, 0) ;// set capacity to zero
            UIA := UIA_Interface() ; Initialize UIA interface
            UIA.ConnectionTimeout := 6000
        }
    }
    Else If ((abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25)
        && (_winCtrlD == "UpBand1" || InStr(_winCtrlD,"ToolbarWindow32", True) || _winCtrlD == "Microsoft.UI.Content.DesktopChildSiteBridge1")
        && (timeDiff < DoubleClickTime/2)) {

        try {
            pt := UIA.ElementFromPoint(lbX2,lbY2,False)
            If ((pt.CurrentControlType == 50000 || pt.CurrentControlType == 50020)  && !inStr(pt.Name, "Refresh", True)) {
                sleep, 150
                If (WinExist("ahk_class Microsoft.UI.Content.PopupWindowSiteBridge") || WinExist("ahk_class #32768") || GetKeyState("Lbutton","P")) {
                    tooltip, forget it
                    SetTimer, keyTrack, On
                    SetTimer, mouseTrack, On
                    Return
                }
            }
        } catch e {
            tooltip, TIMED OUT!!!!
            UIA :=  ;// set to a different value
            ; VarSetCapacity(UIA, 0) ;// set capacity to zero
            UIA := UIA_Interface() ; Initialize UIA interface
            UIA.ConnectionTimeout := 6000
            SetTimer, keyTrack, On
            SetTimer, mouseTrack, On
            Return
        }

        If inStr(pt.Name, "Refresh", True) {
            SendCtrlAdd(_winIdU, , , wmClassD)
        }
        Else { ; not Refresh and hence a button was hit which would navigate to new folder
            currentPath := ""
            loop 100 {
                currentPath := GetExplorerPath(_winIdD)
                If (currentPath != "" && currentPath != prevPath)
                    break
                sleep, 1
            }
            SendCtrlAdd(_winIdU, prevPath, currentPath, wmClassD)
        }
    }
    Else If ((abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25)
            && (InStr(_winCtrlD, "SysTreeView32", True))
            && (timeDiff < DoubleClickTime/2)
            && (LBD_HexColor1 != 0xFFFFFF) && (LBD_HexColor2 != 0xFFFFFF) && (LBD_HexColor3  != 0xFFFFFF)) {

        currentPath := ""
        loop 100 {
            currentPath := GetExplorerPath(_winIdD)
            If (currentPath != "" && currentPath != prevPath)
                break
            sleep, 1
        }
        SendCtrlAdd(_winIdU, prevPath, currentPath, wmClassD, _winCtrlD)
    }
    Else If (abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25) {
        try {
            pt := UIA.ElementFromPoint(lbX1,lbY1,False)
            mElPos := pt.CurrentBoundingRectangle
            ; RangeTip(mElPos.l, mElPos.t, mElPos.r-mElPos.l, mElPos.b-mElPos.t, "Blue", 4)
            If (abs(mElPos.t - mElPos.b) <= 40 ) {
                ; tooltip, % pt.CurrentControlType "-" abs(mElPos.t - mElPos.b)
                textBoxSelected := (pt.CurrentControlType == 50004)
            }
            Else
                textBoxSelected := False
        } catch e {
                tooltip, TIMED OUT!!!!
                UIA :=  ;// set to a different value
                ; VarSetCapacity(UIA, 0) ;// set capacity to zero
                UIA := UIA_Interface() ; Initialize UIA interface
                UIA.ConnectionTimeout := 6000
        }
    }

    SetTimer, keyTrack, On
    SetTimer, mouseTrack, On
Return
#If

; FocusHwndFast(hwnd)
; - Activates the top-level window, brings it to foreground safely, and sets keyboard focus to 'hwnd'.
; - Pure Win32, avoids UIA. Works only for HWND-backed controls.
FocusHwndFast(hwndTarget) {
    if !DllCall("IsWindow", "ptr", hwndTarget)
        return false

    ; Get top-level window
    hwndTop := DllCall("GetAncestor", "ptr", hwndTarget, "uint", 2, "ptr") ; GA_ROOT
    if (!hwndTop)
        hwndTop := hwndTarget

    ; If minimized, restore first
    if (DllCall("IsIconic", "ptr", hwndTop))
        DllCall("ShowWindow", "ptr", hwndTop, "int", 9)  ; SW_RESTORE

    hFG := DllCall("GetForegroundWindow", "ptr")
    tidFG := DllCall("GetWindowThreadProcessId", "ptr", hFG,     "uint*", 0, "uint")
    tidTW := DllCall("GetWindowThreadProcessId", "ptr", hwndTop, "uint*", 0, "uint")
    tidAHK := DllCall("GetCurrentThreadId", "uint")

    ; Safely steal foreground using AttachThreadInput to bypass focus restrictions.
    ; Sequence: attach → bring to top/activate → set focus → detach.
    DllCall("AttachThreadInput", "uint", tidFG, "uint", tidAHK, "int", 1)
    DllCall("AttachThreadInput", "uint", tidTW, "uint", tidAHK, "int", 1)

    DllCall("BringWindowToTop", "ptr", hwndTop)
    DllCall("SetForegroundWindow", "ptr", hwndTop)
    DllCall("SetActiveWindow", "ptr", hwndTop)

    ; If the target is not focusable, this will quietly do nothing.
    ok := DllCall("SetFocus", "ptr", hwndTarget, "ptr")

    ; Verify (still attached)
    curFocus := DllCall("GetFocus", "ptr")
    success := (curFocus = hwndTarget)

    ; Detach
    DllCall("AttachThreadInput", "uint", tidTW, "uint", tidAHK, "int", 0)
    DllCall("AttachThreadInput", "uint", tidFG, "uint", tidAHK, "int", 0)

    return success
}

FocusByClassNN(classNN, winTitle:="A") {
    ControlGet, hCtl, Hwnd,, %classNN%, %winTitle%
    if (!hCtl)
        return false
    return FocusHwndFast(hCtl)
}

IsTabbedExplorer(targetHwndID) {
    ControlGet, OutputVar4, Visible ,, DirectUIHWND4,  ahk_id %targetHwndID%
    ControlGet, OutputVar6, Visible ,, DirectUIHWND6,  ahk_id %targetHwndID%
    ControlGet, OutputVar8, Visible ,, DirectUIHWND8,  ahk_id %targetHwndID%
    Return (OutputVar4 == 1 || OutputVar6 == 1 || OutputVar8 == 1)
}

WaitForExplorerLoad(targetHwndID, skipFocus := False, isCabinetWClass10 := False) {
    Global UIA
    try {
        exEl := UIA.ElementFromHandle(targetHwndID)
        shellEl := exEl.FindFirstByName("Items View")
        shellEl.WaitElementExist("ControlType=ListItem OR Name=This folder is empty. OR Name=No items match your search.",,,,5000)
        If !isCabinetWClass10 && !skipFocus {
            loop 50 {
                ; shellEl.setFocus()
                FocusByClassNN("DirectUIHWND2")
                sleep, 1
                ControlGetFocus, testFocus, ahk_id %targetHwndID%
                if (InStr(testFocus, "DirectUIHWND", false))
                    break
            }
        }
    } catch e {
        tooltip, TIMED OUT!!!!
        UIA :=  ;// set to a different value
        ; VarSetCapacity(UIA, 0) ;// set capacity to zero
        UIA := UIA_Interface() ; Initialize UIA interface
        UIA.ConnectionTimeout := 6000
    }
    Return
}

SendCtrlAddLabel:
    SendCtrlAdd(_winIdU, prevPath, currentPath, _winCtrlD)
Return

RangeTip(x:="", y:="", w:="", h:="", color:="Red", d:=2) ; from the FindText library, credit goes to feiyue
{
  static id:=0
  If (x="")
  {
    id:=0
    Loop 4
      Gui, Range_%A_Index%: Destroy
    Return
  }
  If (!id)
  {
    Loop 4
      Gui, Range_%A_Index%: +Hwndid +AlwaysOnTop -Caption +ToolWindow
        -DPIScale +E0x08000000
  }
  x:=Floor(x), y:=Floor(y), w:=Floor(w), h:=Floor(h), d:=Floor(d)
  Loop 4
  {
    i:=A_Index
    , x1:=(i=2 ? x+w : x-d)
    , y1:=(i=3 ? y+h : y-d)
    , w1:=(i=1 or i=3 ? w+2*d : d)
    , h1:=(i=2 or i=4 ? h+2*d : d)
    Gui, Range_%i%: Color, %color%
    Gui, Range_%i%: Show, NA x%x1% y%y1% w%w1% h%h1%
  }
}

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
~$Ctrl::
    GoSub, LaunchWinFind
Return

LaunchWinFind:
    If (A_PriorHotkey = "~$Ctrl" && A_TimeSincePriorHotkey < 200)
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

    ; cdt := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
    ; desknum := VD.getDesktopNumOfWindow(fulltitle)
    ; If (desknum < cdt)
    ; {
        ; WinGet, vState, MinMax, %fulltitle%
        ; WinGet, vID, ID, %fulltitle%
        ; WinGetPos, vwx,vwy,vww,, %fulltitle%
        ; WinSet, Transparent, 0, %fulltitle%
        ; ; VD.MoveWindowToCurrentDesktop(fulltitle)
        ; DllCall(MoveWindowToDesktopNumberProc, "Ptr", vID, "Int", cdt, "Int")

        ; If (vState > -1) {
            ; ; WinRestore , %fulltitle%
            ; WinActivate, %fulltitle%
            ; offscreenX := -1*vww

            ; WinMove, %fulltitle%,, %offscreenX%, , , ,

            ; WinSet, Transparent, 255, %fulltitle%
            ; loopCount := (vwx+abs(offscreenX))/100

            ; loop, %loopCount%
            ; {
                ; offscreenX := offscreenX + 100
                ; WinMove, %fulltitle%,, offscreenX, , , ,
                ; sleep 1
            ; }
            ; WinMove, %fulltitle%,, vwx, , , ,
        ; }
        ; Else {
            ; sleep 500
            ; WinMinimize, %fulltitle%
            ; WinSet, Transparent, 255, %fulltitle%
            ; ; WinRestore , %fulltitle%
            ; WinActivate, %fulltitle%
        ; }
    ; }
    ; Else If (desknum > cdt)
    ; {
        ; WinGet, vState, MinMax, %fulltitle%
        ; WinGet, vID, ID, %fulltitle%
        ; WinGetPos, vwx,vwy,vww,, %fulltitle%
        ; WinSet, Transparent, 0, %fulltitle%
        ; ; VD.MoveWindowToCurrentDesktop(fulltitle)
        ; DllCall(MoveWindowToDesktopNumberProc, "Ptr", vID, "Int", cdt, "Int")

        ; If (vState > -1) {
            ; ; WinRestore , %fulltitle%
            ; WinActivate, %fulltitle%
            ; offscreenX := A_ScreenWidth

            ; WinMove, %fulltitle%,, %offscreenX%, , , ,

            ; WinSet, Transparent, 255, %fulltitle%
            ; loopCount := (A_ScreenWidth-vwx)/100
            ; ; tooltip, %loopCount%
            ; loop, %loopCount%
            ; {
                ; offscreenX := offscreenX - 100
                ; WinMove, %fulltitle%,, offscreenX, , , ,
                ; sleep 1
            ; }
            ; WinMove, %fulltitle%,, vwx, , , ,
        ; }
        ; Else {
            ; sleep 500
            ; WinMinimize, %fulltitle%
            ; WinSet, Transparent, 255, %fulltitle%
            ; ; WinRestore , %fulltitle%
            ; WinActivate, %fulltitle%
        ; }
    ; }
    ; Else
    ; {
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
    WinGet, hwndId, ID, A
    currentMon := MWAGetMonitorMouseIsIn()
    currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
    If !currentMonHasActWin {
        Send, #+{Left}
        sleep, 150
     }
    GoSub, DrawRect
    sleep, 200
    ClearRect()
    ; }
    Process, Close, Expr_Name
    Process, Close, ExprAltUp_Name

Return

SwitchDesktop:
    Global movehWndId
    Global GoToDesktop := False

    StopRecursion := True
    SetTimer, keyTrack,   Off
    SetTimer, mouseTrack, Off

    MouseGetPos, , , movehWndId
    WinActivate, ahk_id %movehWndId%
    CurrentDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1
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
    Global movehWndId
    Global targetDesktop
    moveLeftConst := -1
    moveRightConst := 1
    moveConst := 0

    DetectHiddenWindows, On

    InitialDesktop := DllCall(GetCurrentDesktopNumberProc, "Int") + 1

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
    Global movehWndId
    Global targetDesktop
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

SendCtrlAdd(initTargetHwnd := "", prevPath := "", currentPath := "", initTargetClass := "", initFocusedCtrlNN := "") {
    Global UIA

    If (initTargetClass == "")
        WinGetClass, lClassCheck, ahk_id %initTargetHwnd%
    Else
        lClassCheck := initTargetClass

    WinGet, lastCheckID, ID, A
    If (lastCheckID != initTargetHwnd) {
        SetTimer, SendCtrlAddLabel, Off
        WinGetClass, lClassCheck, ahk_id %initTargetHwnd%
        tooltip, %lClassCheck% - %lastCheckID% - %initTargetHwnd%
        Return
    }

    If (!GetKeyState("LShift","P" )
        && lClassCheck != "WorkerW" && lClassCheck != "ProgMan"
        && lClassCheck != "Shell_TrayWnd" && !InStr(lClassCheck, "EVERYTHING", True)) {

        If (initFocusedCtrlNN == "") {
            MouseGetPos, , , , initFocusedCtrlNN
            while (initFocusedCtrlNN == "ShellTabWindowClass1") {
                MouseGetPos, , , , initFocusedCtrlNN
            }
        }

        GetKeyState("LButton","P") ? Return : ""

        OutputVar1 := 0
        OutputVar2 := 0
        OutputVar3 := 0
        OutputVar4 := 0
        OutputVar6 := 0
        OutputVar8 := 0

        If (!InStr(initFocusedCtrlNN,"SysListView32",True)
             && initFocusedCtrlNN != "DirectUIHWND2"
             && initFocusedCtrlNN != "DirectUIHWND3"
             && initFocusedCtrlNN != "DirectUIHWND4"
             && initFocusedCtrlNN != "DirectUIHWND6"
             && initFocusedCtrlNN != "DirectUIHWND8") {

            loop 200 {
                ControlGet, OutputVar1, Visible ,, SysListView321, ahk_id %initTargetHwnd%
                ControlGet, OutputVar4, Visible ,, DirectUIHWND4,  ahk_id %initTargetHwnd%
                ControlGet, OutputVar6, Visible ,, DirectUIHWND6,  ahk_id %initTargetHwnd%
                ControlGet, OutputVar8, Visible ,, DirectUIHWND8,  ahk_id %initTargetHwnd%
                ControlGet, OutputVar2, Visible ,, DirectUIHWND2,  ahk_id %initTargetHwnd%
                ControlGet, OutputVar3, Visible ,, DirectUIHWND3,  ahk_id %initTargetHwnd%
                If (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1 || OutputVar4 == 1 || OutputVar6 == 1 || OutputVar8 == 1)
                    break
                sleep, 1
            }
        }
        Else {
            If (InStr(initFocusedCtrlNN,  "SysListView32",True))
                OutputVar1 := 1
            Else If (initFocusedCtrlNN == "DirectUIHWND4")
                OutputVar4 := 1
            Else If (initFocusedCtrlNN == "DirectUIHWND6")
                OutputVar6 := 1
            Else If (initFocusedCtrlNN == "DirectUIHWND8")
                OutputVar8 := 1
            Else If (initFocusedCtrlNN == "DirectUIHWND2")
                OutputVar2 := 1
            Else If (initFocusedCtrlNN == "DirectUIHWND3")
                OutputVar3 := 1
        }

        GetKeyState("LButton","P") ? Return : ""


        If (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1 || OutputVar4 == 1 || OutputVar6 == 1 || OutputVar8 == 1) {
            ; tooltip, init focus is %initFocusedCtrlNN% - %OutputVar1% - %OutputVar2% - %OutputVar3% - %OutputVar4% - %OutputVar6% - %OutputVar8%

            WinGet, proc, ProcessName, ahk_id %initTargetHwnd%
            WinGetTitle, vWinTitle, ahk_id %initTargetHwnd%

            GetKeyState("LButton","P") ? Return : ""

            Critical,   On

            If (OutputVar1 == 1) {
                TargetControl := "SysListView321"
            }
            Else If (((OutputVar2 == 1 && OutputVar3 == 1) && !OutputVar4 && !OutputVar6 && !OutputVar8)
                    && (lClassCheck == "CabinetWClass" || lClassCheck == "#32770")) {
                OutHeight2 := 0
                OutHeight3 := 0
                ControlGetPos, , , , OutHeight2, DirectUIHWND2, ahk_id %initTargetHwnd%, , , ,
                ControlGetPos, , , , OutHeight3, DirectUIHWND3, ahk_id %initTargetHwnd%, , , ,
                If (OutHeight2 > OutHeight3)
                    TargetControl := "DirectUIHWND2"
                Else
                    TargetControl := "DirectUIHWND3"
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

            GetKeyState("LButton","P") ? Return : ""

            tooltip, targeted is %TargetControl% with init at %initFocusedCtrlNN%
            If (TargetControl == "DirectUIHWND3" && (lClassCheck == "#32770" || lClassCheck == "CabinetWClass")) {
                If (prevPath != "" && currentPath != "" && prevPath != currentPath)
                    WaitForExplorerLoad(initTargetHwnd, , True)

                loop, 500 {
                    ControlFocus, %TargetControl%, ahk_id %initTargetHwnd%
                    ControlGetFocus, testCtrlFocus, ahk_id %initTargetHwnd%
                    If (testCtrlFocus == TargetControl)
                        break
                    sleep, 1
                }
            }
            Else If (TargetControl == "DirectUIHWND2" && lClassCheck == "#32770") {
                WaitForExplorerLoad(initTargetHwnd, , True)

                loop, 500 {
                    ControlFocus, %TargetControl%, ahk_id %initTargetHwnd%
                    ControlGetFocus, testCtrlFocus, ahk_id %initTargetHwnd%
                    If (testCtrlFocus == TargetControl)
                        break
                    sleep, 1
                }
            }
            Else If ((lClassCheck == "CabinetWClass" || lClassCheck == "#32770") && (InStr(proc,"explorer.exe",False) || InStr(vWinTitle,"Save",True) || InStr(vWinTitle,"Open",True))) {
                If (prevPath != "" && currentPath != "" && prevPath != currentPath)
                    WaitForExplorerLoad(initTargetHwnd)
            }

            GetKeyState("LButton","P") ? Return : ""

            WinGet, finalActiveHwnd, ID, A
            If (initTargetHwnd == finalActiveHwnd) {
                BlockInput, On
                Send, {Ctrl UP}
                Send, ^{NumpadAdd}
                Send, {Ctrl UP}
                BlockInput, Off

                If (lClassCheck == "#32770" || lClassCheck == "CabinetWClass")
                    sleep, 125

                GetKeyState("LButton","P") ? Return : ""

                If ((InStr(initFocusedCtrlNN,"Edit",True) || InStr(initFocusedCtrlNN,"Tree",True)) && initFocusedCtrlNN != TargetControl) {
                    loop, 500 {
                        ControlFocus , %initFocusedCtrlNN%, ahk_id %initTargetHwnd%
                        ControlGetFocus, testCtrlFocus , ahk_id %initTargetHwnd%
                        If (testCtrlFocus == initFocusedCtrlNN)
                            break
                        sleep, 1
                    }
                }
            }
            Critical,   Off
        }
    }
Return
}

; https://www.autohotkey.com/boards/viewtopic.php?style=2&t=113107
check() {
last := dir, dir := explorerGetPath()
 If WinActive("ahk_class CabinetWClass") && dir != last {
  ControlGetFocus orig
  tree := InStr(orig, "Tree")
  Send % (tree ? "`t" : "") "^{NumpadAdd}" (tree ? "+{Tab}" : "")
 }
}

explorerGetPath(hwnd := 0) { ; https://www.autohotkey.com/boards/viewtopic.php?p=387113#p387113
 If hWnd
  explorerHwnd := WinExist("ahk_class CabinetWClass ahk_id " . hwnd)
 Else (!explorerHwnd := WinActive("ahk_class CabinetWClass")) && explorerHwnd := WinExist("ahk_class CabinetWClass")
 If explorerHwnd
  For window in ComObjCreate("Shell.Application").Windows
   Try If (window && window.hwnd && window.hwnd==explorerHwnd)
    Return window.Document.Folder.Self.Path
 Return False
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
    WinGet, ExStyle, ExStyle, ahk_id %hwndId%
    If (ExStyle & 0x8)
        Return True
    Else
        Return False
}

#If MouseIsOverTaskbarBlank()
Lbutton & Rbutton::
    Send, #{r}
Return
#If

LWin & WheelUp::send {Volume_Up}
LWin & WheelDown::send {Volume_Down}

!WheelUp::send, {PgUp}
!WheelDown::send, {PgDn}

#If VolumeHover() && !IsOverException()
WheelUp::send {Volume_Up}
WheelDown::send {Volume_Down}
#If

; $LButton::
    ; Run, C:\Windows\System32\SndVol.exe
    ; WinWait, ahk_exe SndVol.exe
    ; WinGetPos, sx, sy, sw, sh, ahk_exe SndVol.exe
    ; sw := sw + 200
    ; WinMove, ahk_exe SndVol.exe, , A_ScreenWidth-sw, MonitorWorkAreaBottom-sh, sw
    ; WinActivate, ahk_exe SndVol.exe
    ; x_coord := A_ScreenWidth - floor((sx+sw)/2)
    ; y_coord := MonitorWorkAreaBottom - 30
    ; CoordMode, Pixel, Screen
    ; sleep 300
    ; Critical On
    ; loop
    ; {
        ; PixelGetColor, HexColor, %x_coord%, %y_coord%, RGB
        ; ; msgbox, %HexColor% - %x_coord% - %y_coord%
        ; newX := A_ScreenWidth-sw-(10*A_Index)
        ; newW := sw + (10*A_Index)
        ; If (HexColor == 0xCDCDCD || HexColor == 0xF0F0F0)
            ; WinMove, ahk_exe SndVol.exe, , %newX%, , %newW%
        ; Else
            ; break
    ; }
    ; Critical Off
; Return
; #If

#If !mouseMoving && !VolumeHover() && !IsOverException() && !DraggingWindow
; $RButton::
    ; StopRecursion := True

    ; KeyWait, Rbutton, U T3

    ; If GetKeyState("LShift") && !GetKeyState("LShift","P")
        ; Send, +{Click, Right}
    ; Else
        ; Send,  {Click, Right}

    ; StopRecursion := False
; Return

RButton & WheelUp::
    ; HotKey, Rbutton, DoNothing, On
    SetTimer, SendCtrlAddLabel, Off
    Send, ^{Home}
    ; HotKey, Rbutton, DoNothing, Off
Return

RButton & WheelDown::
    ; HotKey, Rbutton, DoNothing, On
    SetTimer, SendCtrlAddLabel, Off
    Send, ^{End}
    ; HotKey, Rbutton, DoNothing, Off
Return

$RButton::
    StopRecursion := True
    Send {Rbutton}
    StopRecursion := False
Return
#If

ScrollLines(lines,hWnd="") {
static EM_LINESCROLL := 0xB6
    If !hWnd
    {
        ControlGetFocus, c, A
        ControlGet, hWnd, hWnd, , %c%, A
    }
    PostMessage, EM_LINESCROLL, 0, lines-1, , ahk_id %hWnd% ; 'lines-1' makes the line you wish to jump to visible
Return
}

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

IsOverException() {
    MouseGetPos, , , hwndID
    WinGetClass, cl, ahk_id %hwndID%
    WinGet, proc, ProcessName, ahk_id %hwndID%
    If (cl == "WorkerW" || cl == "ProgMan" || proc == "peazip.exe")
        Return True
    Else
        Return False
}

IsEmptySpace() {
    static ROLE_SYSTEM_LIST := 0x21
    If MouseIsOverTitleBar() {
        ; tooltip, yes!
        Return
    }

    If WinActive("ahk_class CabinetWClass") || WinActive("ahk_class #32770") || WinActive("ahk_class #32768") {
        CoordMode, Mouse
        MouseGetPos, X, Y, mID, mCtrlNN

        If (mCtrlNN == "SysListView321" || mCtrlNN == "DirectUIHWND2" || mCtrlNN == "DirectUIHWND3") {
            AccObj := AccObjectFromPoint(idChild, X, Y)
            Return (AccObj.accRole(0) == ROLE_SYSTEM_LIST)
        }
        Else
            Return False
    }
}

AccObjectFromPoint(ByRef _idChild_ = "", x = "", y = "") {
   static VT_DISPATCH := 9, F_OWNVALUE := 1, h := DllCall("LoadLibrary", "Str", "oleacc", "Ptr")

   (x = "" || y = "") ? DllCall("GetCursorPos", "Int64P", pt) : pt := x & 0xFFFFFFFF | y << 32
   VarSetCapacity(varChild, 8 + 2*A_PtrSize, 0)
   If DllCall("oleacc\AccessibleObjectFromPoint", "Int64", pt, "PtrP", pAcc, "Ptr", &varChild) = 0
      Return ComObject(VT_DISPATCH, pAcc, F_OWNVALUE), _idChild_ := NumGet(varChild, 8, "UInt")
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

IsWindow(hWnd){
    WinGet, dwStyle, Style, ahk_id %hWnd%
    If ((dwStyle&0x08000000) || !(dwStyle&0x10000000)) {
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
   ; Global IGUIF
   ; Global IGUIF2
   DllCall("KillTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 2)

   WinWait, ahk_class #32768,, 3

   WinGetPos, menux, menuy, menuw, menuh, ahk_class #32768
   menux := menux + 10
   menuy := menuy + 10
   MouseMove, %menux%, %menuy%

   ; WinMove, ahk_id %IGUIF%  , ,menux, menuy, menuw, menuh,
   ; ; WinMove, ahk_id %IGUIF2%  , ,menux, menuy, menuw, menuh,
   ; WinSet, TransColor, FF00FF 50, ahk_id %IGUIF%
   ; sleep, 20
   ; ; WinSet, TransColor, FF00FF 50, ahk_id %IGUIF2%
   ; sleep, 20
   ; WinSet, TransColor, FF00FF 100, ahk_id %IGUIF%
   ; sleep, 20
   ; ; WinSet, TransColor, FF00FF 100, ahk_id %IGUIF2%
   ; sleep, 20
   ; WinSet, TransColor, FF00FF 150, ahk_id %IGUIF%
   ; sleep, 20
   ; ; WinSet, TransColor, FF00FF 150, ahk_id %IGUIF2%
   ; sleep, 20
   ; WinSet, TransColor, FF00FF 200, ahk_id %IGUIF%
   ; sleep, 20
   ; ; WinSet, TransColor, FF00FF 200, ahk_id %IGUIF2%
   ; sleep, 20
   ; WinSet, TransColor, FF00FF 254, ahk_id %IGUIF%
   ; sleep, 20
   ; ; WinSet, TransColor, FF00FF 254, ahk_id %IGUIF2%

   ; WinSet, AlwaysOnTop, on,  ahk_class #32768
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
    Return 1
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
;gives you roughly the correct results (tested on Windows 7)
;JEE_WinIsAltTab
JEE_WinHasAltTabIcon(hWnd)
{
	local
	If !(DllCall("user32\GetDesktopWindow", "Ptr") = DllCall("user32\GetAncestor", "Ptr",hWnd, "UInt",1, "Ptr")) ;GA_PARENT := 1
	;|| DllCall("user32\GetWindow", "Ptr",hWnd, "UInt",4, "Ptr") ;GW_OWNER := 4 ;affects taskbar but not alt-tab
		Return 0

    WinGet, vWinProc, ProcessName, % "ahk_id " hWnd
    If inStr(vWinProc, "InputHost.exe") || inStr(vWinProc, "App.exe")
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

; https://www.autohotkey.com/boards/viewtopic.php?t=26700#p176849
; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=122399
IsAltTabWindow(hWnd) {
    static WS_EX_APPWINDOW := 0x40000, WS_EX_TOOLWINDOW := 0x80, DWMWA_CLOAKED := 14, DWM_CLOAKED_SHELL := 2, WS_EX_NOACTIVATE := 0x8000000, GA_PARENT := 1, GW_OWNER := 4, MONITOR_DEFAULTTONULL := 0, VirtualDesktopExist, PropEnumProcEx := RegisterCallback("PropEnumProcEx", "Fast", 4)
    static WS_EX_WINDOWEDGE := 0x100, WS_EX_CONTROLPARENT := 0x10000, WS_EX_DLGMODALFRAME := 0x00000001

    WinGetTitle, hasTitle, ahk_id %hWnd%
    If !hasTitle
       Return False

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
    WinGetClass, winClass, ahk_id %hWnd%
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
       If DllCall("GetProp", "uptr", hWnd, "str", "ITaskList_Deleted", "ptr")
          Return False
       If (VirtualDesktopExist = 0) or IsWindowOnCurrentVirtualDesktop(hwnd)
          Return True
       Else
          Return False
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
MoveCurrentWindowToDesktop(num) {
    global MoveWindowToDesktopNumberProc
    correctDesktopNumber := num-1
    WinGet, activeHwnd, ID, A
    Return DllCall(MoveWindowToDesktopNumberProc, "Ptr", activeHwnd, "Int", correctDesktopNumber, "Int")
}

IsWindowOnCurrentVirtualDesktop(hwnd)
{
   Global IsWindowOnCurrentVirtualDesktopProc
   Return DllCall(IsWindowOnCurrentVirtualDesktopProc, "Ptr", hwnd, "Int")
}

GetDesktopCount() {
    global GetDesktopCountProc
    count := DllCall(GetDesktopCountProc, "Int")
    Return count
}

MoveCurrentWindowToDesktopAndSwitch(desktopNumber) {
    global MoveWindowToDesktopNumberProc, GoToDesktopNumberProc
    WinGet, activeHwnd, ID, A
    DllCall(MoveWindowToDesktopNumberProc, "Ptr", activeHwnd, "Int", desktopNumber, "Int")
    DllCall(GoToDesktopNumberProc, "Int", desktopNumber)
}

GoToPrevDesktop() {
    global GetCurrentDesktopNumberProc, GoToDesktopNumberProc
    current := DllCall(GetCurrentDesktopNumberProc, "Int")
    last_desktop := GetDesktopCount() - 1
    ; If current desktop is 0, go to last desktop
    If (current = 0) {
        MoveOrGotoDesktopNumber(last_desktop)
    } Else {
        MoveOrGotoDesktopNumber(current - 1)
    }
    Return
}

GoToNextDesktop() {
    global GetCurrentDesktopNumberProc
    current := DllCall(GetCurrentDesktopNumberProc, "Int")
    last_desktop := GetDesktopCount() - 1
    ; If current desktop is last, go to first desktop
    If (current = last_desktop) {
        MoveOrGotoDesktopNumber(0)
    } Else {
        MoveOrGotoDesktopNumber(current + 1)
    }
    Return
}

GoToDesktopNumber(num) {
    global GoToDesktopNumberProc
    correctDesktopNumber := num-1
    DllCall(GoToDesktopNumberProc, "Int", correctDesktopNumber, "Int")
    Return
}

MoveOrGotoDesktopNumber(num) {
    ; If user is holding down Mouse left button, move the current window also
    If (GetKeyState("LButton")) {
        MoveCurrentWindowToDesktop(num)
    } Else {
        GoToDesktopNumber(num)
    }
    Return
}

getForemostWindowIdOnDesktop(n)
{
    Global IsWindowOnDesktopNumberProc
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
    Global IsWindowOnDesktopNumberProc
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
Global ValidWindows
Global MonCount

    currentMon := MWAGetMonitorMouseIsIn()
    WinGet, allWindows, List
    loop % allWindows
    {
        hwndID := allWindows%A_Index%

        If (IsAltTabWindow(hwndID)) {
            WinGet, state, MinMax, ahk_id %hwndID%
            If (MonCount > 1 && state > -1) {
                currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
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

; Switch "App" open windows based on the same process and class
HandleWindowsWithSameProcessAndClass(activeProcessName, activeClass) {
    Global MonCount, VD, Highlighter, hitTAB, hitTilde, WindowTitleID, GroupedWindows, cycleCount, LclickSelected

    windowsToMinimize := []
    minimizedWindows  := []
    ; finalWindowsListWithProcAndClass := []
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
            currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
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

    WinActivate, % "ahk_id " GroupedWindows[1]
    WinGet, mmState, MinMax, % "ahk_id " GroupedWindows[cycleCount]
    If (MonCount > 1 && mmState == -1) {
        windowsToMinimize.push(GroupedWindows[cycleCount])
        lastActWinID := GroupedWindows[cycleCount]
    }
    WinActivate, % "ahk_id " GroupedWindows[cycleCount]
    WinGetTitle, actTitle, % "ahk_id " GroupedWindows[cycleCount]
    WinGet, pp, ProcessPath , % "ahk_id " GroupedWindows[cycleCount]

    Critical, Off

    GoSub, DrawRect
    DrawWindowTitlePopup(actTitle, pp, True)

    KeyWait, ``, U T1

    cycleCount++
    If (cycleCount > numWindows) {
        cycleCount := 1
    }

    hwndId := GroupedWindows[cycleCount]

    loop
    {
        If LclickSelected
            break

        KeyWait, ``, D T0.1
        If !ErrorLevel
        {
            WinGet, mmState, MinMax, ahk_id %hwndId%
            If (MonCount > 1 && mmState == -1) {
                windowsToMinimize.push(hwndId)
            }
            WinActivate, ahk_id %hwndId%
            lastActWinID := hwndId
            WinGetTitle, actTitle, ahk_id %hwndId%
            WinGet, pp, ProcessPath , ahk_id %hwndId%

            GoSub, DrawRect
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
                    hwndId := GroupedWindows[cycleCount]
                    If !IsWindowOnCurrMon(hwndId, currentMon) {
                        cycleCount++
                        If (cycleCount > numWindows)
                        {
                            cycleCount := 1
                        }
                        hwndId := GroupedWindows[cycleCount]
                    }
                    Else
                        break
                }
            }
        }
    }
    until (!GetKeyState("LAlt", "P"))
    GoSub, FadeOutWindowTitle

    loop % windowsToMinimize.length()
    {
        tempId := windowsToMinimize[A_Index]
        If (tempId != lastActWinID) {
            WinMinimize, ahk_id %tempId%
            sleep, 100
        }
        Else {
            If !IsWindowOnCurrMon(tempId, currentMon) {
                WinActivate, ahk_id %tempId%
                Send, #+{Left}
            }
        }
    }
    cycleCount := cycleCount - 1
    If (cycleCount <= 0)
        cycleCount := GroupedWindows.MaxIndex()

    ; If (cycleCount > 2) {
        ; WinSet, AlwaysOnTop, On, ahk_id %lastActWinID%
        ; WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
        ; WinSet, AlwaysOnTop, On,  ahk_id %Highlighter%

        ; If (finalWindowsListWithProcAndClass.MaxIndex() >= 4 && finalWindowsListWithProcAndClass[4] != lastActWinID) {
            ; WinGet, isMin, MinMax, % "ahk_id " finalWindowsListWithProcAndClass[4]
            ; If (isMin > -1)
                ; WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[4]
        ; }
        ; If (finalWindowsListWithProcAndClass.MaxIndex() >= 3 && finalWindowsListWithProcAndClass[3] != lastActWinID) {
            ; WinGet, isMin, MinMax, % "ahk_id " finalWindowsListWithProcAndClass[3]
            ; If (isMin > -1)
                ; WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[3]
        ; }
        ; If (finalWindowsListWithProcAndClass.MaxIndex() >= 2 &&  finalWindowsListWithProcAndClass[2] != lastActWinID) {
            ; WinGet, isMin, MinMax, % "ahk_id " finalWindowsListWithProcAndClass[2]
            ; If (isMin > -1)
                ; WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[2]
        ; }
        ; If (finalWindowsListWithProcAndClass.MaxIndex() >= 1 && finalWindowsListWithProcAndClass[1] != lastActWinID) {
            ; WinGet, isMin, MinMax, % "ahk_id " finalWindowsListWithProcAndClass[1]
            ; If (isMin > -1)
                ; WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[1]
        ; }
    ; }
    ; WinSet, AlwaysOnTop, Off, ahk_id %lastActWinID%
    ; WinActivate, ahk_id %lastActWinID%
    Return lastActWinID
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

; Copy this function into your script to use it.
HideTrayTip() {
    TrayTip  ; Attempt to hide it the normal way.
    If SubStr(A_OSVersion,1,3) = "10." {
        Menu Tray, NoIcon
        Sleep 200  ; It may be necessary to adjust this sleep.
        Menu Tray, Icon
    }
}
; --------------------   ChatGPT -------------------------------------------------
FixMod(name, vk) {
    if (A_IsSending)  ; skip if script is sending keys
        return
    ; If Windows thinks it's down (logical) but physically it's not, force an Up
    if ( GetKeyState(name) && !GetKeyState(name, "P") )  ; logical down, physical up
        ForceKeyUpVK(vk)
}
; Mouse buttons (optional)
; FixKey("RButton", "RButton Up")
FixKey(name, upSpec) {
    if ( GetKeyState(name) && !GetKeyState(name, "P") ) {
        Critical, On
        SendInput, {%upSpec%}
        Critical, Off
    }
}
; Use a low-level key-up in case Send fails
ForceKeyUpVK(vk) {
    static KEYEVENTF_KEYUP := 0x2
    Critical, On
    ; keybd_event is old but very dependable for “unsticking”
    DllCall("keybd_event", "UChar", vk, "UChar", 0, "UInt", KEYEVENTF_KEYUP, "UPtr", 0)
    Critical, Off
}
; --------------------------------------------------------------------------------
keyTrack() {
    Global keys
    Global numbers
    Global lastHotkeyTyped
    Global StopAutoFix
    Global TimeOfLastHotkeyTyped
    static x_PriorPriorKey
    ListLines, Off

    FixMod("LShift", 0xA0), FixMod("RShift", 0xA1)
    FixMod("LCtrl",  0xA2), FixMod("RCtrl",  0xA3)
    FixMod("LAlt",   0xA4), FixMod("RAlt",   0xA5)

    ControlGetFocus, currCtrl, A
    WinGetClass, currClass, A
    If (currCtrl == "Edit1" && InStr(currClass, "EVERYTHING", True)) {
        StopAutoFix := True
        ; A_PriorKey and Loops — How It Works
        ; A_PriorKey reflects the last physical key pressed, even if that key was pressed during a loop.
        ; You can read A_PriorKey at any point in the loop, and it will show the most recent key pressed up to that moment.
        ; tooltip, lastKey-%lastHotkeyTyped% missedKey-%A_PriorKey%
        If (   TimeOfLastHotkeyTyped
            && ((A_TickCount-TimeOfLastHotkeyTyped) > 300)
            && A_PriorKey != "Enter"
            && A_PriorKey != "LButton"
            && A_PriorKey != "LControl"
            && (InStr(keys, x_PriorPriorKey, false) || InStr(numbers, x_PriorPriorKey, false))
            && x_PriorPriorKey != "LControl") {

            TimeOfLastHotkeyTyped :=
            SetTimer, keyTrack,   Off
            DeAssignHotkeys()

            Critical, On
            Send, ^{NumpadAdd}
            Critical, Off

            If ((InStr(keys, lastHotkeyTyped, false) || (InStr(numbers, lastHotkeyTyped, false) || A_PriorKey == "Space") || A_PriorKey == "CapsLock" || A_PriorKey == "Backspace")
                && lastHotkeyTyped != "" && A_PriorKey != "" && A_PriorKey != lastHotkeyTyped) {
                If (A_PriorKey == "Space")
                    Send, {SPACE}
                Else If (A_PriorKey == "CapsLock")
                    Send, {DELETE}
                Else If (A_PriorKey == "Backspace")
                    Send, {Backspace}
                Else
                    Send, %A_PriorKey%
                tooltip, sent %A_PriorKey%
                lastHotkeyTyped := A_PriorKey
            }

            ReAssignHotkeys()
            SetTimer, keyTrack,   On
        }
        StopAutoFix := False
    }
    Else If (currClass == "XLMAIN") {
        StopAutoFix := True
    }
    Else
        StopAutoFix := False

    If (x_PriorPriorKey != A_PriorKey)
        x_PriorPriorKey := A_PriorKey

    ListLines, On
Return
}

mouseTrack() {
    Global MonCount, mouseMoving, currentMon, previousMon, StopRecursion, LbuttonEnabled, textBoxSelected, TaskBarHeight
    Static x, y, lastX, lastY, lastMon, taskview, PrevActiveWindHwnd, LastActiveWinHwnd1, LastActiveWinHwnd2, LastActiveWinHwnd3, LastActiveWinHwnd4
    Static LbuttonHeld := False, timeOfLastMove
    ListLines Off
    HexColor1 := 0x0
    HexColor2 := 0x1
    HexColor3 := 0x2

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

    If WinActive("ahk_class ZPContentViewWndClass") {
        WinGetPos, x, y, w, h, ahk_class ZPContentViewWndClass
        If (w == currMonWidth && h == currMonHeight) {
            Send, !{f}
            sleep, 1000
        }
    }

    If (MonCount == 1
        &&  x <= 3 && y <= 3
        && !taskview
        && !GetKeyState("Lbutton","P")
        && !skipCheck)
    {
        Send {LWin down}{Tab down}{LWin up}{Tab up}
        taskview := True
        sleep 700
    }
    Else If (MonCount == 1) (
        &&  x <= 3 && y <= 3
        && !taskview
        && GetKeyState("Lbutton","P"))
    {
        skipCheck := True
    }

    If (MonCount == 1 &&  x > 3 && y > 3 && x < A_ScreenWidth-3 && y < A_ScreenHeight-3)
    {
        taskview  := False
        skipCheck := False
    }

    If (MonCount > 1 && !GetKeyState("LButton","P")) {
        currentMon := MWAGetMonitorMouseIsIn(TaskBarHeight)
        If (currentMon > 0 && previousMon != currentMon && previousMon > 0) {
            StopRecursion := True
            DetectHiddenWindows, Off
            WinGet, allWindows, List, , , ""
            loop % allWindows {
                hwnd_id := allWindows%A_Index%
                WinGet, isMin, MinMax, ahk_id %hwnd_id%
                WinGet, whatProc, ProcessName, ahk_id %hwnd_id%
                currentMonHasActWin := IsWindowOnCurrMon(hwnd_id, currentMon)

                If (isMin > -1 &&  currentMonHasActWin && (IsAltTabWindow(hwnd_id) || whatProc == "Zoom.exe")) {
                    WinActivate, ahk_id %hwnd_id%
                    GoSub, DrawRect
                    ClearRect()
                    Gui, GUI4Boarder: Hide
                    break
                }
            }
            previousMon := currentMon
            StopRecursion := False
        }
    }
    ListLines On
}

MouseIsOverTitleBar(xPos := "", yPos := "") {
    Global UIA
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


    CoordMode, Mouse, Screen
    If (xPos != "" && yPos != "")
        MouseGetPos, , , WindowUnderMouseID
    Else
        MouseGetPos, xPos, yPos, WindowUnderMouseID

    WinGet, isMax, MinMax, ahk_id %WindowUnderMouseID%

    titlebarHeight := SM_CYMIN-SM_CYSIZEFRAME
    If (isMax == 1)
        titlebarHeight := SM_CYSIZE

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (   !MouseIsOverTaskbar()
        && (mClass != "WorkerW")
        && (mClass != "ProgMan")
        && (mClass != "TaskListThumbnailWnd")
        && (mClass != "#32768")
        && (mClass != "Net UI Tool Window")) {

        ; tooltip, %SM_CXBORDER% - %SM_CYBORDER% : %SM_CXFIXEDFRAME% - %SM_CYFIXEDFRAME% : %SM_CXSIZE% - %SM_CYSIZE%

        WinGetPosEx(WindowUnderMouseID,x,y,w,h)
        If (yPos > y) && (yPos < (y+titlebarHeight)) && (xPos > x) && (xPos < (x+w-SM_CXBORDER-(45*3))) {
            SendMessage, 0x84, 0, (xPos & 0xFFFF) | (yPos & 0xFFFF)<<16,, % "ahk_id " WindowUnderMouseID
            If ((yPos > y) && (yPos < (y+titlebarHeight)) && (ErrorLevel == 2)) {
                Return True
            }
            Else If ((ErrorLevel != 12) && (mClass != "Chrome_WidgetWin_1")) {
                pt := UIA.ElementFromPoint(xPos,yPos,False)
                Return (pt.CurrentControlType == 50037)
            }
            Else
                Return True
        }
        Else
            Return False
    }
    Else
        Return False
}

;https://stackoverflow.com/questions/59883798/determine-which-monitor-the-focus-window-is-on
IsWindowOnCurrMon(thisWindowHwnd, currentMonNum := 0) {
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
        If (A_Index == currentMonNum) {
            SysGet, workArea, Monitor, % A_Index

            ; tooltip, % currentMonNum " : " X " " Y " " W " " H " | " workAreaLeft " , " workAreaTop " , " abs(workAreaRight-workAreaLeft) " , " workAreaBottom

            ;Check If the focus window in on the current monitor index
            ; If ((A_Index == currentMonNum) && (X >= (workAreaLeft-buffer) && X <= workAreaRight) && (X+W <= (abs(workAreaRight-workAreaLeft) + 2*buffer)) && (Y >= (workAreaTop-buffer) && Y < (workAreaBottom-buffer))) {
            ; https://math.stackexchange.com/questions/2449221/calculating-percentage-of-overlap-between-two-rectangles
            If ((A_Index == currentMonNum) && ((max(X, workAreaLeft) - min(X+W,workAreaRight)) * (max(Y, workAreaTop) - min(Y+H, workAreaBottom)))/(W*H) > 0.50 ) {

                ; tooltip, % currentMonNum " : " X " " Y " " W " " H " | " workAreaLeft " , " workAreaTop " , " abs(workAreaRight-workAreaLeft) " , " workAreaBottom " -- " "True"
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
    Global currMonWidth, currMonHeight
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

ShellMessage( wParam, lParam )
{
    Global nil, lastWinMinHwndId, PrevActiveWindows, VD, MonCount, lastHwnd, prevWParam1, prevWParam2, prevWParam3, prevWParam4

    ; tooltip, %wParam% %prevWParam1% %prevWParam2% %prevWParam3% %prevWParam4%
    If (wParam = 1) ;  HSHELL_WINDOWCREATED := 1
    {
        ID := lParam
        ; loop 10 {
            ; sleep 100
            ; WinGetPos, x, y, w, h, ahk_id %ID%
            ; If (x == x2 && y == y2 && w == w2 && h == h2)
                ; break
            ; x2 := x
            ; y2 := y
            ; w2 := w
            ; h2 := h
        ; }
        ; sleep, 300
        WinGetTitle, title, ahk_id %ID%
        WinGet, procStr, ProcessName, ahk_id %ID%
        WinGet, hwndID, ID, ahk_id %ID%
        WinGetClass, classStr, ahk_id %ID%

        WinWaitActive, ahk_id %ID%, , 3
        ; tooltip, %classStr%
        If (classStr == "OperationStatusWindow" || classStr == "#32770") {
            sleep 100
            WinSet, AlwaysOnTop, On, ahk_class %classStr%
        }

        If (IsAltTabWindow(hwndID) || (procStr == "OUTLOOK.EXE" && classStr == "#32770")) {
            If (MonCount == 1) {
                Return
            }

            WinGet, state, MinMax, ahk_id %ID%
            ; tooltip, %classStr% - %currentMonHasActWin%
            If (state > -1) {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
                If !currentMonHasActWin {
                    WinActivate, ahk_id %ID%
                    Send, #+{Left}
                }
            }
        }
    }
}

ShellMsg( wParam, lParam )
{
    Global nil, lastWinMinHwndId, PrevActiveWindows, VD, MonCount, lastHwnd, prevWParam1, prevWParam2, prevWParam3

    If (wParam = 5)  ;HSHELL_GETMINRECT
    {
         hwnd := NumGet( lParam+0 )
         WinGet, status, MinMax, ahk_id %hwnd%
         WinGetClass, cl, ahk_id %hwnd%
         If (status == -1)
         {
             lastWinMinHwndId := Format("0x{1:x}",hwnd)
             ; tooltip, minimized %lastWinMinHwndId%
             ; WinSet, ExStyle, ^0x80,  ahk_id %hwnd% ; 0x80 is WS_EX_TOOLWINDOW
             ; sleep 50
             ; WinSet, ExStyle, ^0x80,  ahk_id %hwnd%
             ;https://www.autohotkey.com/boards/viewtopic.php?t=59047
             ; WinGet oldxs, ExStyle, ahk_id %hwnd%
             ; newxs := (oldxs & ~0x40000) | 0x80
             ; If (newxs != oldxs)
             ; {
                ; WinSet ExStyle, % newxs, ahk_id %hwnd%
                ; WinSet ExStyle, % oldxs, ahk_id %hwnd%
             ; }
         }
    }
     ; If (wParam=2) ;  HSHELL_WINDOWDESTROYED := 2
     ; {
         ; ID:=lParam
         ; If (nil == ID)
         ; {
             ; MsgBox, %ID% closed.
         ; }
     ; }
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

HasVal(haystack, needle) {
    If !(IsObject(haystack)) || (haystack.Length() = 0)
        Return 0
    for index, value in haystack
        If (value = needle)
            Return index
    Return 0
}

; Clip() - Send and Retrieve Text Using the Clipboard
; by berban - updated February 18, 2019
; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=62156
Clip(Text := "", Reselect := "")
{
    Static BackUpClip, Stored, LastClip
    If (A_ThisLabel = A_ThisFunc) {
        If (Clipboard == LastClip)
            Clipboard := BackUpClip
        BackUpClip := LastClip := Stored := ""
    } Else {
        If !Stored {
            Stored := True
            BackUpClip := ClipboardAll ; ClipboardAll must be on its own line
        } Else
            SetTimer, %A_ThisFunc%, Off
        LongCopyMs := A_TickCount
        Clipboard := ""
        LongCopyMs -= A_TickCount ; LongCopy gauges the amount of time it takes to empty the clipboard which can predict how long the subsequent clipwait will need
        LongCopySec := LongCopyMs / 1000.0
        If RegExMatch(Text, "^\s+$")
            Return
        Else If (Text == "") {
            Send, ^c
            ; ClipWait, LongCopy ? 0.6 : 0.2, True
            ; ClipWait, LongCopySec, True
            ClipWait, %LongCopySec%
        } Else {
            Clipboard := LastClip := Text
            ; ClipWait, 10
            ClipWait, %LongCopyMs%
            Send, ^v
        }
        SetTimer, %A_ThisFunc%, -700
        Sleep 20 ; Short sleep in case Clip() is followed by more keystrokes such as {Enter}
        If (Text == "")
            Return LastClip := Clipboard
        Else If ReSelect && ((ReSelect == True) || (StrLen(Text) < 3000))
            Send, % "{Shift Down}{Left " StrLen(StrReplace(Text, "`r")) "}{Shift Up}"
    }
    Return

    Clip:
        Return Clip()
}


;-------------------------------------------------------------------------------
; https://github.com/radosi/virtualdesktop/tree/main
;-------------------------------------------------------------------------------
getTotalDesktops()
{
    Global DesktopCount
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
            If (procName == "Zoom.exe" || (ExStyle & 0x8)) ; skip If zoom or always on top window
                continue
            If (mmState > -1) {
                If (MonCount > 1) {
                    currentMon := MWAGetMonitorMouseIsIn()
                    currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
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
                    currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
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
    If (InStr(FocusedControl, "Edit", True))
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
    Static Dummy5693
          ,RECTPlus
          ,S_OK:=0x0
          ,DWMWA_EXTENDED_FRAME_BOUNDS:=9

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

    If (DWMRC<>S_OK)
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

; https://www.autohotkey.com/boards/viewtopic.php?t=3951
; Modified from AutoHotkey.chm::/docs/commands/_If.htm
ControlWaitActive(Hwnd, Seconds = "") {
    StartTime := A_TickCount

    Loop {
        Sleep, 100
        ControlGetFocus, TargetControl, A
        ControlGet, FocusedControlHwnd, Hwnd,, %TargetControl%, A
    }
    Until ( FocusedControlHwnd = Hwnd )
       || ( Seconds && (A_TickCount-StartTime)/1000 >= Seconds )

    Return (FocusedControlHwnd=Hwnd)
}

; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=69925
GetActiveExplorerPath()
{
    explorerHwnd := WinActive("ahk_class CabinetWClass")
    If (explorerHwnd)
    {
        for window in ComObjCreate("Shell.Application").Windows
        {
            If (window.hwnd==explorerHwnd)
            {
                Return window.Document.Folder.Self.Path
            }
        }
    }
}

; https://www.reddit.com/r/AutoHotkey/comments/10fmk4h/get_path_of_active_explorer_tab/
GetExplorerPath(hwnd:="") {
    ; tooltip, entering
    If !hwnd
        hwnd := WinExist("A")

    If !WinExist("ahk_id " . hwnd)
        Return ""

    WinGetClass, clCheck, ahk_id %hwnd%

    If (clCheck == "#32770") {
        ; ControlFocus, ToolbarWindow323, ahk_id %hwnd%
        ControlGetText, dir, ToolbarWindow323, ahk_id %hwnd%
        If (dir == "" || !InStr(dir,"address",False)) {
            ; ControlFocus, ToolbarWindow324, ahk_id %hwnd%
            ControlGetText, dir, ToolbarWindow324, ahk_id %hwnd%
        }
        Return dir
    }
    Else If (clCheck == "CabinetWClass") {
        WinGetTitle, expTitle, ahk_id %hwnd%
        cleaned := StrReplace(expTitle, " - File Explorer",,,1)
        ; tooltip, cleaned is %cleaned%
        If (   cleaned == "This PC"
            || cleaned == "Home"
            || cleaned == "Downloads"
            || cleaned == "Recycle Bin"
            || cleaned == "Pictures"
            || cleaned == "Videos"
            || cleaned == "Documents"
            || cleaned == "Music"
            || cleaned == "Desktop" )
            Return cleaned
        Else If inStr(cleaned, "\", False) {
            Return cleaned
        }
        Return ""
    }
    Else {
        activeTab := 0
        try {
            ControlGet, activeTab, Hwnd,, % "ShellTabWindowClass1", % "ahk_id" hwnd
            for w in ComObjCreate("Shell.Application").Windows {
                If (w.hwnd != hwnd)
                    continue
                If activeTab {
                    static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
                    shellBrowser := ComObjQuery(w, IID_IShellBrowser, IID_IShellBrowser)
                    DllCall(NumGet(numGet(shellBrowser+0)+3*A_PtrSize), "Ptr", shellBrowser, "UInt*", thisTab)
                    If (thisTab != activeTab)
                        continue
                    ObjRelease(shellBrowser)
                }
                If (w.Document.Folder.Self.Path == 0) {
                    ControlGetText, dir, ToolbarWindow323, ahk_id %hwnd%
                    If (dir == "" || !InStr(dir,"address",False))
                        ControlGetText, dir, ToolbarWindow324, ahk_id %hwnd%
                    Return dir
                }
                Else
                    Return w.Document.Folder.Self.Path
            }
        }catch e {
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
    If InStr(whatCtrl,"Edit", True) && !InStr(whatCtrl, "Rich", True)
        Return True
    Else
        Return False
}
; ___________________________________

;    Get Explorer Path https://www.autohotkey.com/boards/viewtopic.php?p=587509#p587509
; ___________________________________

; GetExplorerPath(explorerHwnd=0){
    ; If(!explorerHwnd)
        ; ExplorerHwnd:= winactive("ahk_class CabinetWClass")

    ; If(!explorerHwnd){
        ; WinGet, explorerHwnd, List, ahk_class CabinetWClass
        ; loop, % explorerHwnd
        ; {
            ; loopindex:= A_Index
            ; for window in ComObjCreate("Shell.Application").Windows{
                ; try{
                    ; If (window.hwnd==explorerHwnd%loopindex%){
                        ; folder:= window.Document.Folder.Self.Path
                        ; If (instr(folder,"\"))
                            ; Return folder
                    ; }
                ; }
            ; }
        ; }
    ; }Else{
        ; for window in ComObjCreate("Shell.Application").Windows{
            ; try{
                ; If (window.hwnd==explorerHwnd)
                    ; Return window.Document.Folder.Self.Path
            ; }
        ; }
    ; }
; Return False
; }

MouseIsOverTaskbar() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId != "ToolbarWindow323" && CtrlUnderMouseId != "TrayNotifyWnd1")
        Return True
    Else
        Return False
}

MouseIsOverTaskbarButtonGroup() {
    Global UIA
    CoordMode, Mouse, Screen
    MouseGetPos, x, y, WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId != "TrayNotifyWnd1") {
        pt := UIA.ElementFromPoint(x,y,False)
        ; tooltip, % "val is " pt.CurrentControlType
        Return (pt.CurrentControlType == 50000)
    }
    Else
        Return False
}

MouseIsOverTaskbarWidgets() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (mClass == "TaskListThumbnailWnd" || mClass == "Windows.UI.Core.CoreWindow")
        Return True
    Else
        Return False
}

MouseIsOverTaskbarBlank() {
    Global UIA
    MouseGetPos, x, y, WindowUnderMouseID, CtrlUnderMouseId
    WinGetClass, cl, ahk_id %WindowUnderMouseID%
    try {
        If (InStr(cl, "Shell",False) && InStr(cl, "TrayWnd",False) && !InStr(CtrlUnderMouseId, "TrayNotifyWnd", False)) {
            If WinExist("ahk_class TaskListThumbnailWnd") {
                Return False
            }
            Else {
                pt := UIA.ElementFromPoint(x,y,False)
                ; tooltip, % "val is " pt.CurrentControlType
                Return (pt.CurrentControlType == 50033)
            }
        }
        Else
            Return False
    } catch e {
        Return False
    }
}

DrawWindowTitlePopup(vtext := "", pathToExe := "", showFullTitle := False) {
   Gui, WindowTitle: Destroy

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
        vtext := trim(strArray[lastIdx])
    }

    CustomColor := "000000"  ; Can be any RGB color (it will be made transparent below).
    Gui, WindowTitle: +LastFound +AlwaysOnTop -Caption +ToolWindow +HwndWindowTitleID ; +ToolWindow avoids a taskbar button and an alt-tab menu item.
    Gui, WindowTitle: Color, %CustomColor%
    Gui, WindowTitle: Font, s24  ; Set a large font size (32-point).
    If InStr(pathToExe, "ApplicationFrameHost", False) {
        Gui, WindowTitle: Add, Picture, xm-20 w48 h48 Icon3, %A_WinDir%\System32\SHELL32.dll
    }
    Else {
        Gui, WindowTitle: Add, Picture, xm-20 w48 h48, %pathToExe%
    }
    Gui, WindowTitle: Add, Text, xp+64 yp+8 cWhite, %vtext%  ; XX & YY serve to auto-size the window.

    drawX := CoordXCenterScreen()
    drawY := CoordYCenterScreen()
    Gui, WindowTitle: Show, Center NoActivate AutoSize ; NoActivate avoids deactivating the currently active window.

    WinGetPos, , , w , h, ahk_id %WindowTitleID%
    WinSet, Transparent, 1, ahk_id %WindowTitleID%
    WinMove, ahk_id %WindowTitleID%,, drawX-floor(w/2), drawY-floor(h/2)
    WinSet, AlwaysOnTop, On, ahk_id %WindowTitleID%
    WinSet, Transparent, 25, ahk_id %WindowTitleID%
    sleep, 3
    WinSet, Transparent, 125, ahk_id %WindowTitleID%
    sleep, 3
    WinSet, Transparent, 225, ahk_id %WindowTitleID%
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

; https://github.com/Drugoy/Autohotkey-scripts-.ahk/blob/master/Libraries/Acc.ahk

Acc_Init() {
	Static h
	If Not h
		h:=DllCall("LoadLibrary","Str","oleacc","Ptr")
}
Acc_ObjectFromPoint(ByRef _idChild_ = "", x = "", y = "") {
	Acc_Init()
	If	DllCall("oleacc\AccessibleObjectFromPoint", "Int64", x==""||y==""?0*DllCall("GetCursorPos","Int64*",pt)+pt:x&0xFFFFFFFF|y<<32, "Ptr*", pacc, "Ptr", VarSetCapacity(varChild,8+2*A_PtrSize,0)*0+&varChild)=0
	Return ComObjEnwrap(9,pacc,1), _idChild_:=NumGet(varChild,8,"UInt")
}
Acc_Parent(Acc) {
	try parent:=Acc.accParent
	Return parent?Acc_Query(parent):
}
Acc_Query(Acc) { ; thanks Lexikos - www.autohotkey.com/forum/viewtopic.php?t=81731&p=509530#509530
	try Return ComObj(9, ComObjQuery(Acc,"{618736e0-3c3d-11cf-810c-00aa00389b71}"), 1)
}
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
::cab::
::cda::
::cer::
::cfg::
::cfm::
::cgi::
::cgi::
::cgi::
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
:?:bj::b
:?:cj::c
:?:dj::d
:?:fq::f
:?:gj::g
:?:iq::i
:?:jq::j
:?:jx::j
:?:kj::k
:?:kq::k
:?:mq::m
:?:oj::o
:?:qj::q
:?:qq::q
:?:qx::q
:?:qz::q
:?:uj::u
:?:vq::v
:?:wq::w
:?:wz::w
:?:xq::x
:?:xz::x
:?:yq::y
:?:zq::z
:?:zz::z
:?:cz::c
:?:dx::d
:?:ez::e
:?:hx::h
:?:jy::j
:?:kx::k
:?:nx::n
:?:oz::o
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
; :*:dj::j
; :*:fj::j
; :*:gj::j
; :*:hz::z
; :*:ij::j
; :*:jq::q
; :*:kq::q
; :*:qj::j
; :*:qw::w
; :*:qz::z
; :*:vx::x
; :*:vz::z
; :*:wq::q
; :*:wz::z
; :*:xj::j
; :*:xz::z
; :*:yq::q
; :*:zq::q
; :*:zz::z
; :*:aj::j
; :*:bq::q
; :*:cj::j
; :*:dk::k
; :*:ez::z
; :*:ix::x
; :*:jx::x
; :*:kf::f
; :*:lx::x
; :*:mx::x
; :*:nz::z
; :*:oj::j
; :*:px::x
; :*:qx::x
; :*:rx::x
; :*:sx::x
; :*:ux::x
; :*:vx::x
; :*:wx::x
; :*:yx::x
; :*:zx::x
; :*:bb::b
; :*:cc::c
; :*:dd::d
; :*:ff::f
; :*:gg::g
; :*:hh::h
; :*:ii::i
; :*:jj::j
; :*:kk::k
; :*:mm::m
; :*:nn::n
; :*:pp::p
; :*:qq::q
; :*:rr::r
; :*:ss::s
; :*:tt::t
; :*:uu::u
; :*:vv::v
; :*:yy::y
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
::ad::had
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
::andone::and one
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
::its a::it's a
::its an::it's an
::its the::it's the
::itwas::it was
::it's color::its color
::it's surface::its surface
::it's texture::its texture
::it's smell::its smell
::it's shape::its shape
::it's size::its size
::it's weight::its weight
::it's taste::its taste
::it's sound::its sound
::it's name::its name
::it's appearance::its appearance
::it's parts::its parts
::it's design::its design
::it's structure::its structure
::it's purpose::its purpose
::it's role::its role
::it's position::its position
::it's location::its location
::it's function::its function
::it's system::its system
::it's process::its process
::it's operation::its operation
::it's output::its output
::it's performance::its performance
::it's success::its success
::it's failure::its failure
::it's data::its data
::it's users::its users
::it's interface::its interface
::it's network::its network
::it's tail::its tail
::it's fur::its fur
::it's nest::its nest
::it's wings::its wings
::it's egg::its egg
::it's prey::its prey
::it's mate::its mate
::it's habitat::its habitat
::it's territory::its territory
::it's young::its young
::it's meaning::its meaning
::it's value::its value
::it's impact::its impact
::it's origin::its origin
::it's influence::its influence
::it's potential::its potential
::it's limits::its limits
::it's reputation::its reputation
::it's effect::its effect
::its raining::it's raining
::its sunny::it's sunny
::its cold::it's cold
::its hot::it's hot
::its time::it's time
::its late::it's late
::its true::it's true
::its false::it's false
::its over::it's over
::its ready::it's ready
::its done::it's done
::its fine::it's fine
::its okay::it's okay
::its possible::it's possible
::its important::it's important
::its clear::it's clear
::its complicated::it's complicated
::its happening::it's happening
::its working::it's working
::its broken::it's broken
::its beautiful::it's beautiful
::its been::it's been
::its gone::it's gone
::its easy:: it's easy
::its hard:: it's hard
::its difficult:: it's difficult
::its finished::it's finished
::its started::it's started
::its happened::it's happened
::its improved::it's improved
::its changed::it's changed
::its grown::it's grown
::its developed::it's developed
::its evolved::it's evolved
::its not::it's not
::its in::it's in
::its up::it's up
::its down::it's down
::its left::it's left
::its right::it's right
::its any::it's any
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
;------------------------------------------------------------------------------
; Generated Misspellings - the main list
;------------------------------------------------------------------------------
#include %A_ScriptDir%\generatedwords.ahk
#If