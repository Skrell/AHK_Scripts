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

SetBatchLines -1
SetWinDelay   -1
SetControlDelay -1
SetKeyDelay, 1
SendMode, Input

Global moving := False
Global ComboActive := False
Global skipCheck := False
Global hwndVD
Global forward := True
Global cycling := False
Global ValidWindows := []
Global GroupedWindows := []
Global PrevActiveWindows := []
Global minWinArray := []
Global allWinArray := []
Global cycleCount := 1
Global startHighlight := False
Global border_thickness := 4
Global border_color := 0xFF00FF
Global hitTAB := False
Global SearchingWindows := False
Global UserInputTrimmed := ""
Global memotext := ""
Global totalMenuItemCount := 0
Global onlyTitleFound := ""
Global nil
Global CancelClose := False
Global lastWinMinHwndId := 0x999999
Global DesktopIconsVisible := False
Global DrawingRect := False
Global LclickSelected := False
Global StopRecurssion := False
Global currMonHeight := 0
Global currMonWidth  := 0
Global LbuttonEnabled := True
Global LastKey4 :=
Global LastKey1 :=
Global LastKey2 :=
Global LastKey3 :=
Global X_PriorPriorHotKey :=
Global StopAutoFix := False
Global disableEnter := False
Global disableWheeldown := False
Global pauseWheel  := False
Global EVENT_SYSTEM_MENUPOPUPSTART := 0x0006
Global EVENT_SYSTEM_MENUPOPUPEND   := 0x0007
Global TimeOfLastKey := A_TickCount
Global lbX1
Global lbX2
Global currentMon := 0
Global previousMon := 0

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

SysGet, MonNum, MonitorPrimary
SysGet, MonitorWorkArea, MonitorWorkArea, %MonNum%
SysGet, MonCount, MonitorCount

Tooltip, Total Number of Monitors is %MonCount% with Primary being %MonNum%
sleep 1000
Tooltip, % "Current Mon is " GetCurrentMonitorIndex()
sleep 1000
Tooltip, Path to ahk %A_AhkPath%
sleep 2000
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
    ; tooltip, started
    WinWait, ahk_class #32768,, 3000
    ; tooltip, done waiting
    If ErrorLevel
        ExitApp
        
    sleep, 125

    SendInput, {DOWN}
    ; https://www.autohotkey.com/board/topic/11157-popup-menu-sometimes-doesnt-have-focus/page-2
    ; MouseMove, %x%, %y%
    
    
    ; Input, SingleKey, L1, {Lbutton}{ESC}{ENTER}, *
    Return
    
    ~ENTER::
        ExitApp
    return
    
    ~ESC::
        ExitApp
    return
    
    ~*LBUTTON::
        ExitApp
    return
    
    SPACE::
        SendInput, {DOWN}
    return
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
keys = abcdefghijklmnopqrstuvwxyz
Loop Parse, keys
{
    HotKey ~+%A_LoopField%, Hoty
    HotKey ~%A_LoopField%, FixSlash
}
numbers = 0123456789
Loop Parse, numbers
{
    HotKey ~%A_LoopField%, Hoty
}

HotKey ~/,  FixSlash
HotKey ~',  Hoty
HotKey ~?,  Hoty
HotKey ~!,  Hoty
HotKey ~`,, Hoty
HotKey ~.,  Hoty
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

;EVENT_SYSTEM_FOREGROUND := 0x3
DllCall("user32\SetWinEventHook", UInt,0x3, UInt,0x3, Ptr,0, Ptr,RegisterCallback("OnWinActiveChange"), UInt,0, UInt,0, UInt,0, Ptr)
 winhookevent := DllCall("SetWinEventHook", "UInt", EVENT_SYSTEM_MENUPOPUPSTART, "UInt", EVENT_SYSTEM_MENUPOPUPSTART, "Ptr", 0, "Ptr", (lpfnWinEventProc := RegisterCallback("OnPopupMenu", "")), "UInt", 0, "UInt", 0, "UInt", WINEVENT_OUTOFCONTEXT := 0x0000 | WINEVENT_SKIPOWNPROCESS := 0x0002)

SetTimer track, 100
SetTimer keyTrack, 1

Return

OnPopupMenu(hWinEventHook, event, hWnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    ; tooltip, pop!
}

Startup:
    Menu, Tray, Togglecheck, Run at startup
    IfExist, %A_Startup%/AutoCorrect.lnk
        FileDelete, %A_Startup%/AutoCorrect.lnk
    else 
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
    ; tooltip %A_PriorHotkey% - %CapCount%
    If !IsGoogleDocWindow() && (!StopAutoFix && CapCount == 2 && (SubStr(A_ThisHotKey,2,1)=="'" || SubStr(A_ThisHotKey,2,1)=="-")) {
        return
    }
    else If !IsGoogleDocWindow() && (!StopAutoFix && CapCount == 2 && IsThisHotKeyCapital()) {
        Send % "{BS}" . SubStr(A_ThisHotKey,3,1)
    }
    else If !IsGoogleDocWindow() && (!StopAutoFix && (CapCount == 3 || (CapCount == 2 && (A_ThisHotkey == "~Space" || A_ThisHotkey == "~." || A_ThisHotkey == "~?" || A_ThisHotkey == "~!") ))) {
        Send % "{Left}{BS}+" . SubStr(A_PriorHotKey,3,1) . "{Right}"
    }
    If StopAutoFix
        X_PriorPriorHotKey := 
Return

FixSlash:
    TimeOfLastKey := A_TickCount
    If !IsGoogleDocWindow() && (!StopAutoFix && IsPriorHotKeyLetterKey()) && A_ThisHotkey == "~/"
        disableEnter := True
    ; tooltip, %disableEnter% - %X_PriorPriorHotKey% - %A_PriorHotKey% - %A_ThisHotkey%
    If      (disableEnter && !IsGoogleDocWindow() && (!StopAutoFix && inStr(keys, X_PriorPriorHotKey, false) && A_PriorHotKey == "~/" && A_ThisHotkey == "~Space" && A_TimeSincePriorHotkey<999)) {
        Send, % "{BS}{BS}{?}{SPACE}"
        disableEnter := False
    }
    Else If (disableEnter && !IsGoogleDocWindow() && (!StopAutoFix && inStr(keys, X_PriorPriorHotKey, false) && A_PriorHotKey == "~/" && A_ThisHotkey == "Enter" && A_TimeSincePriorHotkey<999)) {
        Send, % "{BS}{?}{ENTER}"
        disableEnter := False
    }
    If IsPriorHotKeyLowerCase()   ; as long as a letter key is pressed we record the priorprior hotkey
        X_PriorPriorHotKey := Substr(A_PriorHotkey,2,1) ; record the letter key pressed
    If IsPriorHotKeyCapital()
        X_PriorPriorHotKey := Substr(A_PriorHotkey,3,1) ; record only the letter key pressed if captialized
Return
;------------------------------------------------------------------------------
IsPriorHotKeyLetterKey() {
    return (IsPriorHotKeyCapital() || IsPriorHotKeyLowerCase())
}
IsPriorHotKeyCapital() {
    Global keys
    return (StrLen(A_PriorHotkey) == 3 && SubStr(A_PriorHotKey,2,1)="+" && inStr(keys, Substr(A_PriorHotkey,3,1), false))
}
IsPriorHotKeyLowerCase() {
    Global keys
    return (StrLen(A_PriorHotkey) == 2 && inStr(keys, Substr(A_PriorHotkey,2,1), false))
}
IsThisHotKeyCapital() {
    Global keys
    return (StrLen(A_ThisHotKey) == 3 && SubStr(A_ThisHotKey,2,1)="+" && inStr(keys, Substr(A_ThisHotKey,3,1), false))
}
;------------------------------------------------------------------------------
;https://www.autohotkey.com/boards/viewtopic.php?t=51265
;------------------------------------------------------------------------------
OnWinActiveChange(hWinEventHook, vEvent, hWnd)
{
    Global prevActiveWindows
    Global StopRecurssion
    Global UIA
    static exEl, shellEl, listEl
    CoordMode, Mouse, Screen

    If !StopRecurssion {

        DetectHiddenWindows, On
        
        WinGetClass, vWinClass, % "ahk_id " hWnd
        If (vWinClass == "OperationStatusWindow" || vWinClass == "#32770") {
            WinSet, AlwaysOnTop, On, Ahk_id %hWnd%
        }
        Else If (vWinClass == "#32768" || vWinClass == "Shell_TrayWnd" || vWinClass == "") {
            Return
        }
        ; Else If (vWinClass == "Autohotkey") {
            ; pw := 0
            ; ph := 0
            ; WinGetPos, px, py, pw, ph, ahk_id %hWnd%
            ; tooltip, here
            ; WinMove, ahk_class %hWnd%, , (A_ScreenWidth/2)-(pw/2), (A_ScreenHeight/2)-(ph/2)
        ; }
                
        If ((!HasVal(prevActiveWindows, hWnd) && vWinClass != "Autohotkey") || vWinClass == "#32770") {
            loop 200 {
                WinGetTitle, vWinTitle, % "ahk_id " hWnd
                If (vWinTitle != "")
                    break
                sleep, 5
             }

            If (vWinTitle == "") {
                DetectHiddenWindows, Off
                Return
            }
            Else If (InStr(vWinTitle, "Save As", false)) {
                WinActivate, % "ahk_id " hWnd
                DetectHiddenWindows, Off
                Return
            }

            WinGet, state, MinMax, Ahk_id %hWnd%
            If (state > -1 && vWinTitle != "") {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := IsWindowOnCurrMon(hWnd, currentMon)
                If !currentMonHasActWin {
                    WinActivate, Ahk_id %hWnd%
                    Send, #+{Left}
                }
            }

            ;EVENT_SYSTEM_FOREGROUND := 0x3
            ; static _ := DllCall("user32\SetWinEventHook", UInt,0x3, UInt,0x3, Ptr,0, Ptr,RegisterCallback("OnWinActiveChange"), UInt,0, UInt,0, UInt,0, Ptr)

            Critical, On

            prevActiveWindows.push(hWnd)

            ; ToolTip, % vWinTitle " - " vWinClass " - " prevActiveWindows.length()
            loop 200
            {
                If WinExist("ahk_id " hWnd)
                    break
                sleep, 5
            }
            ; If (!GetKeyState("LCtrl") && !GetKeyState("LShift")) {
                OutputVar1 := OutputVar2 := OutputVar3 := ""

                loop 200 {
                    ControlGet, OutputVar1, Visible ,, SysListView321, ahk_id %hWnd%
                    ControlGet, OutputVar2, Visible ,, DirectUIHWND2,  ahk_id %hWnd%
                    ControlGet, OutputVar3, Visible ,, DirectUIHWND3,  ahk_id %hWnd%
                    If (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1)
                        break
                    sleep, 5
                }

                If (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1 ) {
                    ; BlockKeyboard(true)
                    BlockInput, On
                    loop, 100 {
                        ControlGetFocus, initFocusedCtrl , % "ahk_id " hWnd
                        If (initFocusedCtrl != "")
                            break
                        sleep, 5
                    }
                    ; tooltip, init focus is %initFocusedCtrl%
                    If (vWinClass == "CabinetWClass" || vWinClass == "#32770") {
                        If (vWinClass != "EVERYTHING_(1.5a)") {
                            exEl := UIA.ElementFromHandle(hWnd)
                            shellEl := exEl.FindFirstByName("Items View")
                            shellEl.WaitElementExist("ControlType=ListItem OR Name=This folder is empty. OR Name=No items match your search.",,,,5000)
                        }
                    }

                    If (OutputVar2 == 1) {
                        FocusedControl := "DirectUIHWND2"
                    }
                    Else If (OutputVar3 == 1) {
                        FocusedControl := "DirectUIHWND3"
                    }
                    Else If (OutputVar1 == 1) {
                        FocusedControl := "SysListView321"
                    }
                    
                    loop, 100 {
                        ControlFocus, %FocusedControl%, % "ahk_id " hWnd
                        ControlGetFocus, testCtrlFocus , % "ahk_id " hWnd
                        If (testCtrlFocus == FocusedControl)
                            break
                        sleep, 5
                    }
                    ; tooltip, about to send to %testCtrlFocus%
                    WinGet, testID, ID, A
                    If (testID == hWnd) {
                        sleep, 125
                        Send, ^{NumpadAdd}
                        sleep, 10
                    }

                    If initFocusedCtrl {
                        loop, 100 {
                            ControlFocus , %initFocusedCtrl%, % "ahk_id " hWnd
                            ControlGetFocus, testCtrlFocus , % "ahk_id " hWnd
                            If (testCtrlFocus == initFocusedCtrl)
                                break
                            sleep, 5
                        }
                    }
                    ; tooltip, returned to edit
                    ; BlockKeyboard(false)
                    BlockInput, Off
                }
            ; }
            Critical, Off
        }

        i := 1
        while (i <= prevActiveWindows.MaxIndex()) {
            checkID := prevActiveWindows[i]
            If !WinExist("ahk_id " checkID)
                prevActiveWindows.RemoveAt(i)
            else
                ++i
        }
        DetectHiddenWindows, Off
    }
    Return
}

PreventRecur() {
    Global StopRecurssion, hWinEventHook
    StopRecurssion := True
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
    if (myOkay) {
        ControlClick,, ahk_id %myOkay%,,,2
        hwndID := "ahk_id " myWindow%A_Index%
        sleep, 400
        if WinExist(hwndID)
            Send, !{o}
        break
    }
}
Return

#IfWinExist ahk_class #32770
!WheelDown::
    WinActivate, ahk_class #32770
    ControlGet, mOutput, Visible ,, Edit1, A
    If (mOutput == 1) {
        ControlFocus, Edit1, A
        Send, {Enter}
        sleep, 50
    }
Return

!WheelUp::
    WinActivate, ahk_class #32770
    ControlGet, mOutput, Visible ,, Edit1, A
    If (mOutput == 1) {
        ControlFocus, Edit1, A
        Send, +{Enter}
        sleep, 50
    }
Return
#IfWinExist

CapsLock::
    Send {Delete}
    TimeOfLastKey := A_TickCount
Return

!a::
    StopAutoFix := true
    Send, {home}
    Hotstring("Reset")
    StopAutoFix := false
Return

+!a::
    StopAutoFix := true
    Send, +{home}
    Hotstring("Reset")
    StopAutoFix := false
Return

!;::
    StopAutoFix := true
    If GetKeyState("a")
        Send, +{end}
    Else
        Send, {end}
    Hotstring("Reset")
    StopAutoFix := false
Return

!+;::
    StopAutoFix := true
    Send, +{end}
    Hotstring("Reset")
    StopAutoFix := false
Return

!+i::
    StopAutoFix := true
    Send +{UP}
    Hotstring("Reset")
    StopAutoFix := false
Return

!+k::
    StopAutoFix := true
    Send +{DOWN}
    Hotstring("Reset")
    StopAutoFix := false
Return

!+j::
    StopAutoFix := true
    Send ^+{LEFT}
    Hotstring("Reset")
    StopAutoFix := false
Return

!+l::
    StopAutoFix := true
    Send ^+{RIGHT}
    Hotstring("Reset")
    StopAutoFix := false
Return

!+'::
    Critical, On
    store := Clip()
    store := Trim(store)
    store := """" . store . """"
    Clip(store)
    Critical, Off
Return

!+[::
    Critical, On
    store := Clip()
    store := Trim(store)
    store := "{" . store . "}"
    Clip(store)
    Critical, Off
Return

!+]::
    Critical, On
    store := Clip()
    store := Trim(store)
    store := "{" . store . "}"
    Clip(store)
    Critical, Off
Return

!+<::
    Critical, On
    store := Clip()
    store := Trim(store)
    store := "<" . store . ">"
    Clip(store)
    Critical, Off
Return

!+>::
    Critical, On
    store := Clip()
    store := Trim(store)
    store := "<" . store . ">"
    Clip(store)
    Critical, Off
Return

!+(::
    Critical, On
    store := Clip()
    store := Trim(store)
    store := "(" . store . ")"
    Clip(store)
    Critical, Off
Return

!+)::
    Critical, On
    store := Clip()
    store := Trim(store)
    store := "(" . store . ")"
    Clip(store)
    Critical, Off
Return

!i::
    StopAutoFix := true
    Send, {UP}
    Hotstring("Reset")
    StopAutoFix := false
Return

!k::
    StopAutoFix := true
    Send, {DOWN}
    Hotstring("Reset")
    StopAutoFix := false
Return

!j::
    StopAutoFix := true
    Send, ^{LEFT}
    ; Send, {LEFT}
    ; Send, ^{RIGHT}
    StopAutoFix := false
Return

!l::
    StopAutoFix := true
    Send, ^{RIGHT}
    StopAutoFix := false
Return

#If disableEnter
Enter::
    GoSub, FixSlash
    ; GoSub, Hoty
    disableEnter := false
Return
#If

#If !disableEnter
~Enter::
    ControlGetFocus, currCtrl, A
    WinGetClass, currCl, A
    WinGetTitle, currTit, A
    If (!InStr(currTit, "Type Up to 3", true) && (currCtrl == "SysTreeView321" || currCtrl == "DirectUIHWND2" || currCtrl == "DirectUIHWND3" || (currCl == "CabinetWClass" && currCtrl == "Edit1") || (currCl == "#32770" && currCtrl == "Edit1"))) {
        GoSub, SendCtrlAdd
    }
Return
#If

#+s::Return

~Space::
    GoSub, Hoty
    GoSub, FixSlash
Return

; duplicate hotkey in case shift is accidentally  held as a result of attempting to type a '?'
~+Space::
    GoSub, Hoty
Return

~^Backspace::
    Hotstring("Reset")
Return

~$Backspace::
    TimeOfLastKey := A_TickCount
Return

~$Delete::
    TimeOfLastKey := A_TickCount
Return

~$Left::
    X_PriorPriorHotKey := 
Return

~$Right::
    X_PriorPriorHotKey := 
Return

$F2::
    LbuttonEnabled := False
    StopRecurssion := True
    SetTimer, track, Off
    SetTimer, keyTrack, Off
    KeyWait, F2, U T1
    Send, {F2}
    sleep, 150
    ; ControlFocus, Edit1, A
    ; result := UIA.GetFocusedElement()
    ; ControlFocus, Edit1, A
    ; tooltip, % "name is " result.value
    loop 500 {
        If GetKeyState("Enter") || GetKeyState("Lbutton") || GetKeyState("Esc")
            break
        sleep, 10
    }
    SetTimer, track, On
    SetTimer, keyTrack, On
    StopRecurssion := False
    LbuttonEnabled := True
Return

; Ctl+Tab in chrome to goto recent
prevChromeTab()
{
    Global StopRecurssion
    StopRecurssion := True
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
            StopRecurssion := False
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
    StopRecurssion := False
}

#If WinActive("ahk_exe Chrome.exe")
    ^Tab::
        prevChromeTab()
    Return
#If

#If !SearchingWindows && !hitTAB
~Esc::
    WinGet, escHwndID, ID, A
    StopRecurssion := True
    executedOnce   := False

    If ( A_PriorHotkey == A_ThisHotKey && A_TimeSincePriorHotkey  < 550 && escHwndID == escHwndID_old) {
        DetectHiddenWindows, Off
        If IsAltTabWindow(escHwndID) {
            GoSub, DrawRect
            WinGetTitle, tit, ahk_id %escHwndID%
            loop {
                tooltip Close `"%tit%`" ?
                sleep, 10
                If !GetKeyState("Esc")
                    break
            }

            If !CancelClose {
                tooltip, Waiting for `"%tit%`" to close...
                Winclose, ahk_id %escHwndID%
                
                loop 10 {
                    If !WinExist("ahk_id " . escHwndID) {
                        GoSub, ClearRect
                        ActivateTopMostWindow()
                        break
                    }
                    sleep, 125

                    WinGetClass, actClass, A

                    If ((WinActive("ahk_class #32770") || InStr(actClass, "dialog", false)) && !executedOnce) {
                        WinGet, dialog_hwndID, ID, A
                        executedOnce := True
                        WinSet, AlwaysOnTop, On, ahk_class #32770
                        GoSub, SendCtrlAdd
                        WinWaitClose, ahk_id %dialog_hwndID%
                        break
                    }
                    If !executedOnce && WinExist("ahk_id " . escHwndID) {
                        WinGet, kill_pid, PID, ahk_id %escHwndID%
                        Process, Close, %kill_pid%
                    }
                }
                
                If (WinExist("ahk_id " . escHwndID) && !executedOnce) {
                    WinKill , ahk_id %escHwndID%
                    loop 50 {
                        If !WinExist("ahk_id " . escHwndID) {
                            GoSub, ClearRect
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
    }

    escHwndID_old := escHwndID
    StopRecurssion := False
Return

Esc & x::
    Tooltip, Canceled!
    GoSub, ClearRect
    CancelClose := True
    sleep, 1500
    Tooltip,
Return
#If

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
    ; tooltip, Switching...
    StopRecurssion := True
    CurrentDesktop := getCurrentDesktop()
    If GetKeyState("Lbutton", "P") {
        BlockInput, MouseMove
        Send {Lbutton up}
        WinGetTitle, Title, A
        WinGet, hwndVD, ID, A
        ; WinActivate, ahk_class Shell_TrayWnd
        WinSet, AlwaysOnTop , On, %Title%
        loop, 5
        {
            level := 255-(A_Index*50)
            WinSet, Transparent , %level%, %Title%
            sleep, 30
        }
        ; WinSet, ExStyle, ^0x80, %Title%
        If (CurrentDesktop == 3) {
            MoveCurrentWindowToDesktop(2)
            Send #^{Left}
            sleep, 100
            CurrentDesktop -= 1
            MoveCurrentWindowToDesktop(1)
            Send #^{Left}
            CurrentDesktop -= 1
            sleep, 1000
        }
        Else If (CurrentDesktop == 2) {
            MoveCurrentWindowToDesktop(1)
            Send #^{Left}
            CurrentDesktop -= 1
            sleep 500
        }
        ; WinMinimize, ahk_class Shell_TrayWnd
        ; WinSet, ExStyle, ^0x80, %Title%
        loop, 5
        {
            level := (A_Index*50)
            WinSet, Transparent , %level%, %Title%
            sleep, 30
        }
        WinSet, Transparent , off, %Title%
        WinActivate, %Title%
        Send {Lbutton down}
        sleep, 50
        BlockInput, MouseMoveOff
        KeyWait, Lbutton, U T10
        Send {Lbutton up}
        WinSet, AlwaysOnTop , Off, %Title%
    }
    Else {
        If (CurrentDesktop == 3) {
            Send #^{Left}
            sleep, 100
            CurrentDesktop -= 1
            Send #^{Left}
            CurrentDesktop -= 1
        }
        Else If (CurrentDesktop == 2) {
            Send #^{Left}
            CurrentDesktop -= 1
        }
        sleep 250
    }
    while (1 != getCurrentDesktop()) 
    {
        sleep, 25
    }
    StopRecurssion := False
    ; Tooltip, Done 1
Return

!2::
    ; tooltip, Switching...
    StopRecurssion := True
    CurrentDesktop := getCurrentDesktop()
    If GetKeyState("Lbutton", "P") {
        BlockInput, MouseMove
        Send {Lbutton up}
        WinGetTitle, Title, A
        WinGet, hwndVD, ID, A
        ; WinActivate, ahk_class Shell_TrayWnd
        WinSet, AlwaysOnTop , On, %Title%
        loop, 5
        {
            level := 255-(A_Index*50)
            WinSet, Transparent , %level%, %Title%
            sleep, 30
        }
        MoveCurrentWindowToDesktop(2)
        ; WinSet, ExStyle, ^0x80, %Title%
        If (CurrentDesktop == 1) {
            Send #^{Right}
            CurrentDesktop += 1
        }
        Else If (CurrentDesktop == 3) {
            Send #^{Left}
            CurrentDesktop -= 1
        }
        sleep 500
        ; WinMinimize, ahk_class Shell_TrayWnd
        ; WinSet, ExStyle, ^0x80, %Title%
        loop, 5
        {
            level := (A_Index*50)
            WinSet, Transparent , %level%, %Title%
            sleep, 30
        }
        WinSet, Transparent , off, %Title%
        WinActivate, %Title%
        Send {Lbutton down}
        sleep, 50
        BlockInput, MouseMoveOff
        KeyWait, Lbutton, U T10
        Send {Lbutton up}
        WinSet, AlwaysOnTop , Off, %Title%
    }
    Else {
        If (CurrentDesktop == 1) {
            Send #^{Right}
            CurrentDesktop += 1
        }
        Else If (CurrentDesktop == 3) {
            Send #^{Left}
            CurrentDesktop -= 1
        }
        sleep 250
    }
    while (2 != getCurrentDesktop()) 
    {
        sleep, 25
    }
    StopRecurssion := False
    ; Tooltip, Done 2
Return

!3::
    ; tooltip, Switching...
    StopRecurssion := True
    CurrentDesktop := getCurrentDesktop()
    If GetKeyState("Lbutton", "P") {
        BlockInput, MouseMove
        Send {Lbutton up}
        WinGetTitle, Title, A
        WinGet, hwndVD, ID, A
        ; WinActivate, ahk_class Shell_TrayWnd
        WinSet, AlwaysOnTop , On, %Title%
        loop, 5
        {
            level := 255-(A_Index*50)
            WinSet, Transparent , %level%, %Title%
            sleep, 30
        }
        MoveCurrentWindowToDesktop(3)
        ; WinSet, ExStyle, ^0x80, %Title%
        If (CurrentDesktop == 1) {
            MoveCurrentWindowToDesktop(2)
            Send #^{Right}
            sleep, 100
            CurrentDesktop += 1
            MoveCurrentWindowToDesktop(3)
            Send #^{Right}
            CurrentDesktop += 1
            sleep, 1000
        }
        Else If (CurrentDesktop == 2) {
            MoveCurrentWindowToDesktop(3)
            Send #^{Right}
            CurrentDesktop += 1
            sleep 500
        }
        ; WinMinimize, ahk_class Shell_TrayWnd
        ; WinSet, ExStyle, ^0x80, %Title%
        loop, 5
        {
            level := (A_Index*50)
            WinSet, Transparent , %level%, %Title%
            sleep, 30
        }
        WinSet, Transparent , off, %Title%
        WinActivate, %Title%
        Send {Lbutton down}
        sleep, 50
        BlockInput, MouseMoveOff
        KeyWait, Lbutton, U T10
        Send {Lbutton up}
        WinSet, AlwaysOnTop , Off, %Title%
    }
    Else {
        If (CurrentDesktop == 1) {
            Send #^{Right}
            sleep, 100
            CurrentDesktop += 1
            Send #^{Right}
            CurrentDesktop += 1
        }
        Else If (CurrentDesktop == 2) {
            Send #^{Right}
            CurrentDesktop += 1
        }
        sleep 250
    }
    while (3 != getCurrentDesktop()) 
    {
        sleep, 25
    }
    StopRecurssion := False
    ; Tooltip, Done 3
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
        cycleCount     := 1
        ValidWindows   := {}
        GroupedWindows := {}
        startHighlight := False
        hitTAB         := False
        LclickSelected := False
        Return
    }
    Else {
        BlockKeyboard(true)
        WinGet, actWndID, ID, A
        If (LclickSelected && (GroupedWindows.length() > 2) && actWndID != ValidWindows[1]) {
            If (startHighlight) {
                BlockInput, MouseMove
                GoSub, FadeInWin1
                BlockInput, MouseMoveOff
            }
        }
        Else {
            If (GetKeyState("x","P") || actWndID == ValidWindows[1] || GroupedWindows.length() <= 1) {
                If (GetKeyState("x","P")) {
                    Gui, GUI4Boarder: Hide
                    GoSub, ResetWins
                }
            }
            Else If (startHighlight && (GroupedWindows.length() > 2)  && actWndID != ValidWindows[1]) {
                GoSub, FadeInWin2
            }
        }
    }

    cycleCount     := 1
    ValidWindows   := {}
    GroupedWindows := {}
    startHighlight := False
    hitTAB         := False
    LclickSelected := False
    BlockKeyboard(false)
    Gosub, ClearRect
    ; tooltip,
Return

;============================================================================================================================
FadeInWin1:
    Critical, On

    WinSet, AlwaysOnTop, Off, ahk_id %lbhwnd%
    WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
    
    WinSet, AlwaysOnTop, On, ahk_id %lbhwnd%
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%

    If (lbhwnd != ValidWindows[1] && Highlighter != ValidWindows[1] && ValidWindows.MaxIndex() >= 1)
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[1]
    If (lbhwnd != ValidWindows[2] && Highlighter != ValidWindows[2] && ValidWindows.MaxIndex() >= 2)
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[2]
    If (lbhwnd != ValidWindows[3] && Highlighter != ValidWindows[3] && ValidWindows.MaxIndex() >= 3)
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[3]
    If (lbhwnd != ValidWindows[4] && Highlighter != ValidWindows[4] && ValidWindows.MaxIndex() >= 4)
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[4]

    If (lbhwnd != ValidWindows[4] &&ValidWindows.MaxIndex() >= 4) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[4]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[4]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }
    If (lbhwnd != ValidWindows[3] &&ValidWindows.MaxIndex() >= 3) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[3]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[3]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }
    If (lbhwnd != ValidWindows[2] &&ValidWindows.MaxIndex() >= 2) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[2]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[2]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }
    If (lbhwnd != ValidWindows[1] &&ValidWindows.MaxIndex() >= 1) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[1]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[1]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }
    
    WinSet, AlwaysOnTop, On, ahk_id %lbhwnd%
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    WinActivate, % "ahk_id " lbhwnd

    If (ValidWindows.MaxIndex() >= 1 && Highlighter != ValidWindows[1] && lbhwnd != ValidWindows[1]) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[1]
        sleep 10
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[1]
        sleep 10
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[1]
        sleep 10
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[1]
    }
    If (ValidWindows.MaxIndex() >= 2 && Highlighter != ValidWindows[2] && lbhwnd != ValidWindows[2]) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[2]
        sleep 10
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[2]
        sleep 10
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[2]
        sleep 10
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[2]
    }
    If (ValidWindows.MaxIndex() >= 3 && Highlighter != ValidWindows[3] && lbhwnd != ValidWindows[3]) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[3]
        sleep 10
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[3]
        sleep 10
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[3]
        sleep 10
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[3]
    }
    If (ValidWindows.MaxIndex() >= 4 && Highlighter != ValidWindows[4] && lbhwnd != ValidWindows[4]) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[4]
        sleep 10
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[4]
        sleep 10
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[4]
        sleep 10
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[4]
    }
    
    WinSet, AlwaysOnTop, Off , % "ahk_id " lbhwnd
    Critical, Off
Return

FadeInWin2:
    Critical, On
    WinSet, AlwaysOnTop, Off ,% "ahk_id " GroupedWindows[cycleCount]
    WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
    
    WinSet, AlwaysOnTop, On ,% "ahk_id " GroupedWindows[cycleCount]
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    
    If (ValidWindows.MaxIndex() >= 1 && GroupedWindows[cycleCount] != ValidWindows[1])
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[1]
    If (ValidWindows.MaxIndex() >= 2 && GroupedWindows[cycleCount] != ValidWindows[2]) 
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[2]
    If (ValidWindows.MaxIndex() >= 3 && GroupedWindows[cycleCount] != ValidWindows[3])
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[3]

    If (ValidWindows.MaxIndex() >= 3) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[3]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[3]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }
    If (ValidWindows.MaxIndex() >= 2) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[2]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[2]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }
    If (ValidWindows.MaxIndex() >= 1) {
            WinSet, AlwaysOnTop, On, % "ahk_id " ValidWindows[1]
            WinSet, AlwaysOnTop, Off, % "ahk_id " ValidWindows[1]
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    }

    WinSet, AlwaysOnTop, On ,% "ahk_id " GroupedWindows[cycleCount]
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    WinActivate, % "ahk_id " GroupedWindows[cycleCount]

    If (ValidWindows.MaxIndex() >= 1 && GroupedWindows[cycleCount] != ValidWindows[1]) 
    {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[1]
        sleep 10
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[1]
        sleep 10
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[1]
        sleep 10
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[1]
    }
    If (ValidWindows.MaxIndex() >= 2 && GroupedWindows[cycleCount] != ValidWindows[2]) 
    {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[2]
        sleep 10
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[2]
        sleep 10
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[2]
        sleep 10
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[2]
    }
    If (ValidWindows.MaxIndex() >= 3 && GroupedWindows[cycleCount] != ValidWindows[3]) 
    {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[3]
        sleep 10
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[3]
        sleep 10
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[3]
        sleep 10
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[3]
    }
    If (ValidWindows.MaxIndex() >= 4 && GroupedWindows[cycleCount] != ValidWindows[4])
    {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[4]
        sleep 10
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[4]
        sleep 10
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[4]
        sleep 10
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[4]
    }
    
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
ComboActive := False
SetTimer, track, Off
SetTimer, keyTrack, Off
Cycle(forward)
GoSub, Altup
SetTimer, track, On
SetTimer, keyTrack, On
Return

$!+Tab::
ComboActive := False
SetTimer, track, Off
SetTimer, keyTrack, Off
Cycle(!forward)
GoSub, ClearRect
SetTimer, track, On
SetTimer, keyTrack, On
Return

; #If !hitTAB
!q::
    ; tooltip, swapping between windows of app
    StopRecurssion := True
    ComboActive    := False
    ActivateTopMostWindow()

    DetectHiddenWindows, Off
    WinGet, activeProcessName, ProcessName, A
    WinGetClass, activeClassName, A
    
    HandleWindowsWithSameProcessAndClass(activeProcessName, activeClassName)
    GoSub, ClearRect

    ; tooltip,
    StopRecurssion := False
Return
; #If

#If hitTAB
!x::
    Gui, GUI4Boarder: Hide
    GoSub, ResetWins
Return
#If

RunDynaExpr:
    DynaRun(Expr, Expr_Name)
Return

RunDynaAltUp:
    DynaRun(ExprAltUp, ExprAltUp_Name)
Return

RunDynaExprTimeout:
    DynaRun(ExprTimeout, ExprTimeout_Name)
Return


!Capslock::
    StopRecurssion := True
    totalMenuItemCount := 0
    onlyTitleFound := ""
    winAssoc := {}
    winArraySort := []
    tooltip, Looking for Minimized Apps...

    DetectHiddenWindows, Off
    Critical On
    WinGet, id, list
    Loop, %id%
    {
        this_ID := id%A_Index%
        WinGet, minState, MinMax, ahk_id %this_ID%

        desknum := 1
        ; desknum := VD.getDesktopNumOfWindow(title)
        ; If desknum <= 0
            ; continue

        If (minState > -1 || !IsAltTabWindow(this_ID))
            continue

        WinGetTitle, title, ahk_id %this_ID%
        WinGet, procName, ProcessName , ahk_id %this_ID%
        finalTitle := % "Desktop " desknum " ↑ " procName " ↑ " title "^" this_ID
        If HasVal(minWinArray,finalTitle)
            continue

        minWinArray.Push(finalTitle)
    }

    If (minWinArray.length() == 0) {
        Tooltip, No matches found...
        Sleep, 1500
        Tooltip,
        StopRecurssion := False
        Critical Off
        Return
    }

    For k, v in minWinArray
    {
        winAssoc[v] := k
    }

    For k, v in winAssoc
    {
        winArraySort.Push(k)
    }

    desktopEntryLast := ""

    Menu, minWindows, Add
    Menu, minWindows, deleteAll
    For k, ft in winArraySort
    {
        splitEntry1 := StrSplit(ft , "^")
        entry := splitEntry1[1]
        ahkid := splitEntry1[2]

        splitEntry2    := StrSplit(entry, "↑")
        desktopEntry   := splitEntry2[1]
        procEntry      := Trim(splitEntry2[2])
        titleEntry     := Trim(splitEntry2[3])

        ; If (VD.getDesktopNumOfWindow(titleEntry) == VD.getCurrentDesktopNum())
        ; finalEntry   := % desktopEntry " : [" titleEntry "] (" procEntry ")"
            finalEntry   := %  "[" titleEntry "] (" procEntry ")"
        ; Else
            ; continue

        WinGet, Path, ProcessPath, ahk_exe %procEntry%
        If (desktopEntryLast != ""  && (desktopEntryLast != desktopEntry)) {
            Menu, minWindows, Add
        }
        If (finalEntry != "" && titleEntry != "") {
            totalMenuItemCount := totalMenuItemCount + 1
            onlyTitleFound := finalEntry

            Menu, minWindows, Add, %finalEntry%, ActivateWindow
            Try
                Menu, minWindows, Icon, %finalEntry%, %Path%,, 32
            Catch
                Menu, minWindows, Icon, %finalEntry%, %A_WinDir%\System32\SHELL32.dll, 3, 32
        }
        desktopEntryLast := desktopEntry
    }

    Critical Off

    SetTimer, RunDynaAltUp, -1

    CoordMode, Mouse, Screen
    CoordMode, Menu, Screen
    drawX := CoordXCenterScreen()
    drawY := CoordYCenterScreen()
    Gui, ShadowFrFull:  Show, x%drawX% y%drawY% h0 w0
    ; Gui, ShadowFrFull2: Show, x%drawX% y%drawY% h0 w0

    DllCall("SetTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 2, "UInt", 150, "Ptr", RegisterCallback("MyTimer", "F"))
    Tooltip,
    ShowMenu(MenuGetHandle("minWindows"), False, drawX, drawY, 0x14)
    ; Tooltip, Done.
    Gui, ShadowFrFull:  Hide

    StopRecurssion := False

    Menu, minWindows, deleteAll
    i := 1
    while (i <= minWinArray.MaxIndex()) {
        checkID := minWinArray[i]
        If !WinExist("ahk_id " checkID)
            minWinArray.RemoveAt(i)
        else
            ++i
    }
Return

Cycle(direction)
{
    Global cycling
    Global cycleCount
    Global ValidWindows
    Global GroupedWindows
    Global MonCount
    Global startHighlight
    Global hitTAB
    Global lbhwnd
    static prev_cl, prev_exe
    hitTAB := True
    prev_cl  := ""
    prev_exe := ""

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
                currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
            }
            Else {
                currentMonHasActWin := True
            }

            If (currentMonHasActWin) {
                If (IsAltTabWindow(hwndID)) {
                    WinGet, state, MinMax, ahk_id %hwndID%
                    WinGet, exe, ProcessName, ahk_id %hwndID%
                    WinGetClass, cl, ahk_id %hwndID%
                    If (state > -1) {
                        ValidWindows.push(hwndID)

                        If (prev_cl != cl || prev_exe != exe) {
                            GroupedWindows.push(hwndId)

                            If (GroupedWindows.MaxIndex() == 2) {
                                WinActivate, % "ahk_id " hwndID
                                ; WinWaitActive,  % "ahk_id " hwndID, , 2
                                cycleCount := 2
                                If (hwndID == actId) {
                                    failedSwitch := True
                                }
                                Else {
                                    Critical, Off
                                    GoSub, DrawRect
                                    If !GetKeyState("Alt","P") || GetKeyState("q","P")
                                        Return
                                }
                            }
                            If (GroupedWindows.MaxIndex() == 3 && failedSwitch) {
                                WinActivate, % "ahk_id " hwndID
                                ; WinWaitActive,  % "ahk_id " hwndID, , 2
                                cycleCount := 3
                                Critical, Off
                                GoSub, DrawRect
                            }
                            If ((GroupedWindows.MaxIndex() > 3) && (!GetKeyState("Alt","P") || GetKeyState("q","P"))) {
                                Critical, Off
                                Return
                            }
                        }
                        prev_exe := exe
                        prev_cl  := cl
                    }
                }
            }
        }
    }
    Critical, Off
    
    If (GroupedWindows.length() == 1) {
        tooltip, % "Only " GroupedWindows.length() " Window to Show..."
        sleep, 1000
        tooltip,
        Return
    }
    KeyWait, Tab, U
    cycling := True
    If cycling {
        ; tooltip, cycling
        loop {
            If (GroupedWindows.length() >= 2 && cycling)
            {
                KeyWait, Lbutton, D  T0.1
                If !ErrorLevel {
                    MouseGetPos, , , lbhwnd, 
                    WinGetTitle, actTitle, ahk_id %lbhwnd%
                    WinGet, pp, ProcessPath , ahk_id %lbhwnd%
                    
                    LclickSelected := True
                    GoSub, DrawRect
                    DrawWindowTitlePopup(actTitle, pp)
                    WinSet, AlwaysOnTop, On, ahk_class tooltips_class32
                    KeyWait, Lbutton, U
                }
            
                KeyWait, Tab, D  T0.1
                If !ErrorLevel
                {
                    If direction {
                        If (cycleCount == GroupedWindows.MaxIndex())
                            cycleCount := 1
                        Else
                            cycleCount += 1
                        WinActivate, % "ahk_id " GroupedWindows[cycleCount]
                        WinWaitActive, % "ahk_id " GroupedWindows[cycleCount], , 2
                        WinGetTitle, tits, % "ahk_id " GroupedWindows[cycleCount]
                        WinGet, pp, ProcessPath , % "ahk_id " GroupedWindows[cycleCount]

                        GoSub, DrawRect
                        DrawWindowTitlePopup(tits, pp)
                        WinSet, AlwaysOnTop, On, ahk_class tooltips_class32
                        KeyWait, Tab, U
                    }
                    Else {
                        If (cycleCount == 1)
                            cycleCount := GroupedWindows.MaxIndex()
                        Else
                            cycleCount -= 1
                        WinActivate, % "ahk_id " GroupedWindows[cycleCount]
                        WinWaitActive, % "ahk_id " GroupedWindows[cycleCount], , 2
                        WinGetTitle, tits, % "ahk_id " GroupedWindows[cycleCount]
                        WinGet, pp, ProcessPath , % "ahk_id " GroupedWindows[cycleCount]
                        GoSub, DrawRect
                        DrawWindowTitlePopup(tits, pp)
                        WinSet, AlwaysOnTop, On, ahk_class tooltips_class32
                        KeyWait, Tab, U
                    }
                    If (cycleCount > 2)
                        startHighlight := True
                }
            }
        } until (!GetKeyState("LAlt", "P") || GetKeyState("q","P"))
        Gui, WindowTitle: Destroy
    }
    Return
}

ClearRect:
    Critical, On
    If DrawingRect {
        loop 5 {
            DrawingRect := False
            If !ComboActive && (GetKeyState("LAlt", "P") || GetKeyState("LButton", "P")) {
                Critical, Off
                Gui, GUI4Boarder: Hide
                WinSet, Transparent, 255, ahk_id %Highlighter%
                WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
                Return
            }
            sleep, 5
        }
        
        decrement_amount := 15
        loop % floor(255/decrement_amount)
        {
            current_trans := 255-(decrement_amount * A_Index)
            WinSet, Transparent, %current_trans%, ahk_id %Highlighter%
            If !ComboActive && (GetKeyState("LAlt", "P") || GetKeyState("LButton", "P")) {
                Critical, Off
                Gui, GUI4Boarder: Hide
                WinSet, Transparent, 255, ahk_id %Highlighter%
                WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
                Return
            }
            sleep 5
        }
        Gui, GUI4Boarder: Hide
    }
    Critical, Off
Return

; https://www.autohotkey.com/boards/viewtopic.php?t=110505
DrawRect:
    Gui, GUI4Boarder: Hide
    DrawingRect := True
    WinGet, activeWin, ID, A
    x := y := w := h := 0
    WinGetPosEx(activeWin, x, y, w, h)

    if (x="")
        Return

    borderType:="inside"                ; set to inside, outside, or both

    if (borderType="outside") {
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

    } else if (borderType="inside") {
        ; WinGet, myState, MinMax, A
        ; if (myState == 1)
            ; offset:=8
        ; else
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

    } else if (borderType="both") {
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

!Lbutton::
    If (A_PriorHotkey == A_ThisHotkey && (A_TimeSincePriorHotkey < 550))
        Send, {ENTER}
    Else
        Send, {click, Left}
Return

#If MouseIsOverTaskbarBlank()
~Lbutton::
    StopRecurssion     := True
    MouseGetPos, lbX1, lbY1,
    If (A_PriorHotkey == A_ThisHotkey
        && (A_TimeSincePriorHotkey < 550)
        && (abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25)) {
        run, explorer.exe 
        StopRecurssion     := False
        Return
    }
    
    KeyWait, LButton, U T5
    MouseGetPos, lbX2, lbY2,
    StopRecurssion     := False
Return
#If

#If MouseIsOverTaskbarWidgets()
~^Lbutton::
    StopRecurssion := True
    SetTimer, track, Off
	SetTimer, keyTrack, Off
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
    SetTimer, track, On
	SetTimer, keyTrack, On
    StopRecurssion := False
Return
#If

KeepCenteringTimer:
    MouseGetPos, , , , lctrlN
    If (GetKeyState("Lbutton","P") || GetKeyState("Rbutton","P") || GetKeyState("LAlt","P") ) {
        SetTimer, KeepCenteringTimer, Off
        Return
    }
    Else If  (lctrlN != "SysListView321" && lctrlN != "DirectUIHWND2" && lctrlN != "DirectUIHWND3") {
        SetTimer, KeepCenteringTimer, Off
        Return
    }
    Else
        Send, ^{NumpadAdd}
Return

#If MouseIsOverTitleBar()
~^LButton::
    DetectHiddenWindows, Off
    SetTimer, track, Off
    MouseGetPos, mx1, my1, actID,
    KeyWait, Lbutton, U T5
    MouseGetPos, mx2, my2, ,
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
    SetTimer, track, On
Return
#If

#MaxThreadsPerHotkey 2
#If (!VolumeHover() && LbuttonEnabled && !IsOverDesktop() && !hitTAB && !MouseIsOverTitleBar() && !MouseIsOverTaskbarBlank())
~LButton::
    tooltip,
    StopRecurssion     := True
    CoordMode, Mouse, Screen
    MouseGetPos, lbX1, lbY1, lbhwnd, lctrlN
    SetTimer, SendCtrlAdd, Off
    WinGetClass, lClass, ahk_id %lbhwnd%
    Gui, GUI4Boarder: Hide
    
    If (A_PriorHotkey == A_ThisHotkey
        && (A_TimeSincePriorHotkey < 550)
        && (abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25)
        && (lctrlN == "SysListView321" || lctrlN == "DirectUIHWND2" || lctrlN == "DirectUIHWND3")) {
        
        currentPath    := ""

        ; tooltip, %A_TimeSincePriorHotkey% - %prevPath% - %LB_HexColor1% - %LB_HexColor2% - %LB_HexColor3%  - %X1% %X2% %Y1% %Y2% - %lctrlN% - %A_ThisHotkey% - %A_PriorHotkey%

        If ((LB_HexColor1 == 0xFFFFFF) && (LB_HexColor2 == 0xFFFFFF) && (LB_HexColor3  == 0xFFFFFF)) {
            If (lctrlN == "SysListView321") {
                Send, {Backspace}
                SetTimer, RunDynaExprTimeout, -1
            }
            Else {
                Send, !{Up}
                SetTimer, RunDynaExprTimeout, -1
            }
        }
        
        ; KeyWait, Lbutton, U T3
        LbuttonEnabled     := False
        
        If (lClass == "CabinetWClass" || lClass == "#32770") {
            loop 100 {
                currentPath := GetExplorerPath(lbhwnd)
                If (currentPath != "")
                    break
                sleep, 2
            }
            
            If (prevPath != "" && currentPath != "" && prevPath != currentPath)
                SetTimer, SendCtrlAdd, -1
                ; SetTimer, KeepCenteringTimer, 5
            
            LbuttonEnabled     := True
            StopRecurssion     := False
            Return
        }
        Else {
            ; SetTimer, KeepCenteringTimer, 5
            SetTimer, SendCtrlAdd, -1
            sleep, 100
            LbuttonEnabled     := True
            StopRecurssion     := False
            Return
        }
    }
    
    CoordMode, Pixel, Screen
    PixelGetColor, LB_HexColor1, %lbX1%, %lbY1%, RGB
    lbX1 -= 1
    lbY1 -= 1
    PixelGetColor, LB_HexColor2, %lbX1%, %lbY1%, RGB
    lbX1 += 2
    lbY1 += 2
    PixelGetColor, LB_HexColor3, %lbX1%, %lbY1%, RGB

    initTime := A_TickCount

    currentPath := ""
    prevPath := ""
    If ((lClass == "CabinetWClass" || lClass == "#32770") && (lctrlN == "SysListView321" || lctrlN == "DirectUIHWND2" || lctrlN == "DirectUIHWND3")) {
        prevPath := GetExplorerPath(lbhwnd)
    }
    
    KeyWait, LButton, U T5
    CoordMode, Mouse, screen
    MouseGetPos, lbX2, lbY2,

    rlsTime := A_TickCount
    timeDiff := rlsTime - initTime
    ; tooltip, %timeDiff% ms - %lctrlN% - %LB_HexColor1% - %LB_HexColor2% - %LB_HexColor3% - %lbX1% - %lbX2%

    If ((abs(lbX1-lbX2) < 25 && abs(lbY1-lbY2) < 25)
        && (timeDiff < 325)
        && ((LB_HexColor1 == 0xFFFFFF) && (LB_HexColor2 == 0xFFFFFF) && (LB_HexColor3  == 0xFFFFFF))
        && (lctrlN == "SysListView321" || lctrlN == "DirectUIHWND2" || lctrlN == "DirectUIHWND3" || lctrlN == "Microsoft.UI.Content.DesktopChildSiteBridge1" || lctrlN == "UpBand1" || lctrlN == "ToolbarWindow321" || lctrlN == "ToolbarWindow323" || lctrlN == "ToolbarWindow324"))  {

        SetTimer, SendCtrlAdd, -125
        }
    Else If (lctrlN == "SysTreeView321") && (LB_HexColor1 != 0xFFFFFF) && (LB_HexColor2 != 0xFFFFFF) && (LB_HexColor3  != 0xFFFFFF) {
        SetTimer, SendCtrlAdd, -125
    }
    Else
        SetTimer, SendCtrlAdd, Off
    
    StopRecurssion := False
    LbuttonEnabled := True
Return
#If

#MaxThreadsPerHotkey 1

UpdateInputBoxTitle:
    WinSet, ExStyle, +0x80, ahk_class #32770 ; 0x80 is WS_EX_TOOLWINDOW
    If (WinExist("Type Up to 3 Letters of a Window Title to Search") && !StopCheck) {
        WinSet, AlwaysOnTop, On, Type Up to 3 Letters of a Window Title to Search
        StopCheck := True
    }

    ControlGetText, memotext, Edit1, Type Up to 3 Letters of a Window Title to Search
    StringLen, memolength, memotext

    If ((memolength >= 2 && (A_TickCount-TimeOfLastKey > 400)) || (memolength >= 1 && InStr(memotext, " "))) {
        UserInputTrimmed := Trim(memotext)
        Send, {ENTER}
        SetTimer, UpdateInputBoxTitle, off
        Return
    }
    else {
        UserInputTrimmed := Trim(memotext)
    }
Return

; https://superuser.com/questions/1603554/autohotkey-find-and-focus-windows-by-name-accross-virtual-desktops
!`::
    SetTimer, track,    off
    UserInputTrimmed :=
    StopCheck        := False
    SearchingWindows := True
    StopRecurssion   := True
    BlockKeyboard(True)
    SetTimer, UpdateInputBoxTitle, 5
    BlockKeyboard(False)
    InputBox, UserInput, Type Up to 3 Letters of a Window Title to Search, , , 340, 100, CoordXCenterScreen()-(340/2), CoordYCenterScreen()-(100/2)
    SetTimer, UpdateInputBoxTitle, off
    ; tooltip, searching %UserInputTrimmed%
    If ErrorLevel
    {
        SetTimer, track,    on
        Return
    }
    else
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
            ; desknum := VD.getDesktopNumOfWindow(title)
            desknum := 1
            If desknum <= 0
                continue
            finalTitle := % "Desktop " desknum " ↑ " procName " ↑ " title "^" this_ID
            allWinArray.Push(finalTitle)
        }

        If (allWinArray.length() == 0) {
            Tooltip, No matches found...
            Sleep, 1500
            Tooltip,
            StopRecurssion := False
            Critical, Off
            SetTimer, track,    on
            ; SetTimer, keyTrack, on
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
            ; Gui, ShadowFrFull:  Show, x%drawX% y%drawY% h0 y0
            ; Gui, ShadowFrFull2: Show, x%drawX% y%drawY% h1 y1
            sleep, 100
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
    StopRecurssion   := False
    SearchingWindows := False
    SetTimer, track,    on
    ; SetTimer, keyTrack, on
Return

ActivateWindow:
    BlockKeyboard(true)
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
        ; else {
            ; sleep 500
            ; WinMinimize, %fulltitle%
            ; WinSet, Transparent, 255, %fulltitle%
            ; ; WinRestore , %fulltitle%
            ; WinActivate, %fulltitle%
        ; }
    ; }
    ; else If (desknum > cdt)
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
        ; else {
            ; sleep 500
            ; WinMinimize, %fulltitle%
            ; WinSet, Transparent, 255, %fulltitle%
            ; ; WinRestore , %fulltitle%
            ; WinActivate, %fulltitle%
        ; }
    ; }
    ; else
    ; {
    If (fulltitle == "Calculator") {
        ; https://www.autohotkey.com/boards/viewtopic.php?t=43997
        WinGet, CalcIDs, List, Calculator
        If (CalcIDs = 1) ; Calc is NOT minimized
            CalcID := CalcIDs1
        else
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
    GoSub, ClearRect
    ; }
    Process, Close, Expr_Name
    Process, Close, ExprAltUp_Name
    BlockKeyboard(false)
Return


#If MouseIsOverTitleBar()
Mbutton::
    Global movehWndId
    MouseGetPos, , , movehWndId
    WinActivate, ahk_id %movehWndId%
    
    loop % getTotalDesktops()
    {
        Menu, vdeskMenu, Add,  Move to Desktop %A_Index%, SendWindow
        Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_WinDir%\System32\imageres.dll, 290, 32
    }
    Menu, vdeskMenu, Show
Return
#If

SendWindow:
    Global movehWndId
    moveLeftConst := -1
    moveRightConst := 1
    moveConst := 0
    targetDesktop := 0
    DetectHiddenWindows, On
    WinGetPos, sw_x, sw_y, sw_h, sw_w, ahk_id %movehWndId%
    sw_x_org := sw_x
    
    CurrentDesktop := getCurrentDesktop()
    If      (A_ThisMenuItem == "Move to Desktop 1")
        targetDesktop := 1
    Else If (A_ThisMenuItem == "Move to Desktop 2")
        targetDesktop := 2
    Else If (A_ThisMenuItem == "Move to Desktop 3")
        targetDesktop := 3
    Else If (A_ThisMenuItem == "Move to Desktop 4")
        targetDesktop := 4
    Else If (A_ThisMenuItem == "Move to Desktop 5")
        targetDesktop := 5
    Else If (A_ThisMenuItem == "Move to Desktop 6")
        targetDesktop := 6
    Else If (A_ThisMenuItem == "Move to Desktop 7")
        targetDesktop := 7
    Else If (A_ThisMenuItem == "Move to Desktop 8")
        targetDesktop := 8
    
    If (targetDesktop < CurrentDesktop)
        moveConst := moveLeftConst
    Else
        moveConst := moveRightConst
    
    WinSet, Transparent, 225, ahk_id %movehWndId%
    sw_x += 15*moveConst
    WinMove, ahk_id %movehWndId%,, %sw_x%
    sleep, 20
    WinSet, Transparent, 200, ahk_id %movehWndId%
    sw_x += 15*moveConst
    WinMove, ahk_id %movehWndId%,, %sw_x%
    sleep, 20
    WinSet, Transparent, 175, ahk_id %movehWndId%
    sw_x += 15*moveConst
    WinMove, ahk_id %movehWndId%,, %sw_x%
    sleep, 20
    WinSet, Transparent, 150, ahk_id %movehWndId%
    sw_x += 15*moveConst
    WinMove, ahk_id %movehWndId%,, %sw_x%
    sleep, 20
    WinSet, Transparent, 100, ahk_id %movehWndId%
    sw_x += 15*moveConst
    WinMove, ahk_id %movehWndId%,, %sw_x%
    sleep, 20
    WinSet, Transparent, 50,  ahk_id %movehWndId%
    sw_x += 15*moveConst
    WinMove, ahk_id %movehWndId%,, %sw_x%
    sleep, 20
    WinSet, Transparent, 0,   ahk_id %movehWndId%
    sleep, 20
    
    WinMove, ahk_id %movehWndId%,, %sw_x_org%
    
    If      (A_ThisMenuItem == "Move to Desktop 1")
        MoveCurrentWindowToDesktop(1)
    Else If (A_ThisMenuItem == "Move to Desktop 2")
        MoveCurrentWindowToDesktop(2)
    Else If (A_ThisMenuItem == "Move to Desktop 3")
        MoveCurrentWindowToDesktop(3)
    Else If (A_ThisMenuItem == "Move to Desktop 4")
        MoveCurrentWindowToDesktop(4)
    Else If (A_ThisMenuItem == "Move to Desktop 5")
        MoveCurrentWindowToDesktop(5)
    Else If (A_ThisMenuItem == "Move to Desktop 6")
        MoveCurrentWindowToDesktop(6)
    Else If (A_ThisMenuItem == "Move to Desktop 7")
        MoveCurrentWindowToDesktop(7)
    Else If (A_ThisMenuItem == "Move to Desktop 8")
        MoveCurrentWindowToDesktop(8)
        
    WinSet, Transparent, 255, ahk_id %movehWndId%
    DetectHiddenWindows, Off
Return

SendCtrlAdd:
    WinGetClass, lClassCheck, A

    If (lClassCheck != lClass) {
        SetTimer, SendCtrlAdd, Off
        Return
    }

    ; CoordMode, Mouse, Screen
    If (!GetKeyState("LShift","P" ) && lClassCheck == lClass && lclass != "WorkerW" && lclass != "ProgMan" && lclass != "Shell_TrayWnd" && !InStr(lClassCheck, "EVERYTHING", True)) {
        WinGet, lIdCheck, ID, A
        OutputVar1 := OutputVar2 := OutputVar3 := ""
       
        loop 500 {
            ControlGet, OutputVar1, Visible ,, SysListView321, ahk_id %lIdCheck%
            ControlGet, OutputVar2, Visible ,, DirectUIHWND2,  ahk_id %lIdCheck%
            ControlGet, OutputVar3, Visible ,, DirectUIHWND3,  ahk_id %lIdCheck%
            ControlGet, HasEdit, Visible ,, Edit1,  ahk_id %lIdCheck%
            If (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1)
                break
            sleep, 1
        }
        
        If (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1) {
            If ((lClassCheck == "CabinetWClass" || (lClassCheck == "#32770" && HasEdit == 1))) {
                try {
                    exEl := UIA.ElementFromHandle(lIdCheck)
                    shellEl := exEl.FindFirstByName("Items View")
                    shellEl.WaitElementExist("ControlType=ListItem OR Name=This folder is empty. OR Name=No items match your search.",,,,5000)
                } catch e {
                    tooltip, TIMED OUT!!!!
                    UIA :=  ;// set to a different value
                    ; VarSetCapacity(UIA, 0) ;// set capacity to zero
                    UIA := UIA_Interface() ; Initialize UIA interface
                    UIA.ConnectionTimeout := 6000
                    Return
                }

                If (OutputVar1 == 1) {
                    FocusedControl := "SysListView321"
                }
                Else If (OutputVar2 == 1) {
                    FocusedControl := "DirectUIHWND2"
                }
                Else If (OutputVar3 == 1) {
                    FocusedControl := "DirectUIHWND3"
                }
                
                BlockInput, On
                loop, 250 {
                    ControlFocus, %FocusedControl%, ahk_id %lIdCheck%
                    ControlGetFocus, whatCtrl, ahk_id %lIdCheck%
                    If (FocusedControl == whatCtrl)
                        break
                    sleep, 1
                }
                    
                WinGet, lIdCheck2, ID, A
                If (lIdCheck == lIdCheck2) {
                    Send, ^{NumpadAdd}
                    tooltip, sent to %whatCtrl%
                }

                If (lctrlN == "SysTreeView321") {
                    sleep, 125
                    loop, 500 {
                        ControlFocus , SysTreeView321, ahk_id %lIdCheck%
                        ControlGetFocus, testCtrlFocus , ahk_id %lIdCheck%
                        If (testCtrlFocus == "SysTreeView321")
                            break
                        sleep, 1
                    }
                }
                BlockInput, Off
            }
            Else {
                Send, ^{NumpadAdd}
                tooltip, sent
            }
        }
    }
Return

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
    ComboActive := True
    MouseGetPos, , , hwndId
    WinGetTitle, winTitle, ahk_id %hwndId%
    BlockInput, MouseMove
    WinGet, ExStyle, ExStyle, ahk_id %hwndId%
    If (ExStyle & 0x8)
        Gui, GUI4Boarder: Color, 0x00FF00
    Else
        Gui, GUI4Boarder: Color, 0xFF0000
    GoSub, DrawRect
    sleep, 100
    GoSub, ClearRect
    Gui, GUI4Boarder: Color, %border_color%
    WinSet, AlwaysOnTop, toggle, ahk_id %hwndId%
    BlockInput, MouseMoveOff
Return
#If

LWin & WheelUp::send {Volume_Up}
LWin & WheelDown::send {Volume_Down}

#If VolumeHover() && !IsOverDesktop()
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

#If moving
~RButton::
    ComboActive := False
Return
#If

#If !moving && !IsOverDesktop()
*RButton::
    StopRecurssion := True
    ComboActive := False
    loop 600 {
        If !(GetKeyState("RButton"))
        {
            break
        }
        sleep 5
    }
    If !ComboActive
    {
        If GetKeyState("LShift") && !GetKeyState("LShift","P")
            Send, +{Click, Right}
        Else
            Send, {Click, Right}
    }
    else
        ComboActive := False
        
    StopRecurssion := False
Return
#If

#If !moving && !VolumeHover() && !IsOverDesktop()
RButton & WheelUp::
    SetTimer, SendCtrlAdd, Off
    ComboActive := True
    MouseGetPos, , , targetID, targetCtrl
    WinActivate, ahk_id %targetID%
    ControlFocus, %targetCtrl%, ahk_id %targetID%
    Send, ^{Home}
Return
#If

#If !moving && !VolumeHover() && !IsOverDesktop()
RButton & WheelDown::
    SetTimer, SendCtrlAdd, Off
    ComboActive := True
    MouseGetPos, , , targetID, targetCtrl
    WinActivate, ahk_id %targetID%
    ControlFocus, %targetCtrl%, ahk_id %targetID%
    Send, ^{End}
Return
#If

#If !MouseIsOverTitleBar() && !disableWheeldown && !pauseWheel
~WheelUp::
    ; Hotkey, ~WheelDown, Off
    pauseWheel := True
    MouseGetPos, , , wuID, wuCtrl
    WinGetClass, wuClass, ahk_id %wuID%

    If (wuClass == "Shell_TrayWnd" && !moving && wuCtrl != "ToolbarWindow323" && wuCtrl != "TrayNotifyWnd1")
    {
        Send #^{Left}
        sleep, 200
    }
    Else If (wdClass != "ProgMan" && wdClass != "WorkerW" && wdClass != "Notepad++" && (wuCtrl == "SysListView321" || wuCtrl == "DirectUIHWND2" || wuCtrl == "DirectUIHWND3")) {
        ControlFocus , %wuCtrl%, % "ahk_id " wdID
        ControlGetFocus, FocusedControl, A
        If (FocusedControl == wuCtrl) {
            BlockInput, On
            If !GetKeyState("Ctrl") {
                Send, {Ctrl Up}
            }
            Send, ^{NumpadAdd}
            sleep, 200
            If !GetKeyState("Ctrl") {
                Send, {Ctrl Up}
            }
            BlockInput, Off
        }
    }
    ; Hotkey, ~WheelUp, On
    pauseWheel := False
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
    ; Hotkey, ~WheelDown, Off
    pauseWheel := True
    MouseGetPos, , , wdID, wuCtrl
    WinGetClass, wdClass, ahk_id %wdID%

    If (wdClass == "Shell_TrayWnd" && !moving && wuCtrl != "ToolbarWindow323" && wuCtrl != "TrayNotifyWnd1")
    {
        Send #^{Right}
        sleep, 200
    }
    Else If (wdClass != "ProgMan" && wdClass != "WorkerW" && wdClass != "Notepad++" && (wuCtrl == "SysListView321" || wuCtrl == "DirectUIHWND2" || wuCtrl == "DirectUIHWND3")) {
        ControlFocus , %wuCtrl%, % "ahk_id " wdID
        ControlGetFocus, FocusedControl, A
        If (FocusedControl == wuCtrl) {
            BlockInput, On
            If !GetKeyState("Ctrl") {
                Send, {Ctrl Up}
            }
            Send, ^{NumpadAdd}
            sleep, 200
            If !GetKeyState("Ctrl") {
                Send, {Ctrl Up}
            }
            BlockInput, Off
        }
    }
    pauseWheel := False
    ; Hotkey, ~WheelDown, On
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
    If (InStr(toolText, "Speakers", false) || InStr(toolText, "Headphones", false))
        Return True
    Else
        Return False
}

IsOverDesktop() {
    MouseGetPos, , , hwndID
    WinGetClass, cl, ahk_id %hwndID%
    If (cl == "WorkerW" || cl == "ProgMan")
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
   Global IGUIF
   ; Global IGUIF2
   DllCall("KillTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 2)

   WinWait, ahk_class #32768,, 3000

   WinGetPos, menux, menuy, menuw, menuh, ahk_class #32768
   menux := menux + 10
   menuy := menuy + 10
   ; WinMove, ahk_class #32768, , %menux%, %menuy%
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
	if !(DllCall("user32\GetDesktopWindow", "Ptr") = DllCall("user32\GetAncestor", "Ptr",hWnd, "UInt",1, "Ptr")) ;GA_PARENT := 1
	;|| DllCall("user32\GetWindow", "Ptr",hWnd, "UInt",4, "Ptr") ;GW_OWNER := 4 ;affects taskbar but not alt-tab
		return 0

    WinGet, vWinProc, ProcessName, % "ahk_id " hWnd
    If inStr(vWinProc, "InputHost.exe") || inStr(vWinProc, "App.exe")
        return 0

	WinGet, vWinStyle, Style, % "ahk_id " hWnd
	if !vWinStyle
	|| !(vWinStyle & 0x10000000) ;WS_VISIBLE := 0x10000000
	|| (vWinStyle & 0x8000000) ;WS_DISABLED := 0x8000000 ;affects alt-tab but not taskbar
		return 0
	WinGet, vWinExStyle, ExStyle, % "ahk_id " hWnd
	if (vWinExStyle & 0x40000) ;WS_EX_APPWINDOW := 0x40000
		return 1
	if (vWinExStyle & 0x80) ;WS_EX_TOOLWINDOW := 0x80
	|| (vWinExStyle & 0x8000000) ;WS_EX_NOACTIVATE := 0x8000000 ;affects alt-tab but not taskbar
		return 0
	return 1
}

; https://www.autohotkey.com/boards/viewtopic.php?t=26700#p176849
; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=122399
IsAltTabWindow(hWnd) {
   
   static WS_EX_APPWINDOW := 0x40000, WS_EX_TOOLWINDOW := 0x80, DWMWA_CLOAKED := 14, DWM_CLOAKED_SHELL := 2, WS_EX_NOACTIVATE := 0x8000000, GA_PARENT := 1, GW_OWNER := 4, MONITOR_DEFAULTTONULL := 0, VirtualDesktopExist, PropEnumProcEx := RegisterCallback("PropEnumProcEx", "Fast", 4)

   if (VirtualDesktopExist = "")
   {
      OSbuildNumber := StrSplit(A_OSVersion, ".")[3]
      if (OSbuildNumber < 14393)
         VirtualDesktopExist := 0
      else
         VirtualDesktopExist := 1
   }
   if !DllCall("IsWindowVisible", "uptr", hWnd)
      return false
   DllCall("DwmApi\DwmGetWindowAttribute", "uptr", hWnd, "uint", DWMWA_CLOAKED, "uint*", cloaked, "uint", 4)
   if (cloaked = DWM_CLOAKED_SHELL)
      return false
   if (realHwnd(DllCall("GetAncestor", "uptr", hwnd, "uint", GA_PARENT, "ptr")) != realHwnd(DllCall("GetDesktopWindow", "ptr")))
      return false
   WinGetClass, winClass, ahk_id %hWnd%
   if (winClass = "Windows.UI.Core.CoreWindow" || winClass = "Shell_TrayWnd")
      return false
   if (winClass = "ApplicationFrameWindow")
   {
      varsetcapacity(ApplicationViewCloakType, 4, 0)
      DllCall("EnumPropsEx", "uptr", hWnd, "ptr", PropEnumProcEx, "ptr", &ApplicationViewCloakType)
      if (numget(ApplicationViewCloakType, 0, "int") = 1)   ; https://github.com/kvakulo/Switcheroo/commit/fa526606d52d5ba066ba0b2b5aa83ed04741390f
         return false
   }
   ; if !DllCall("MonitorFromWindow", "uptr", hwnd, "uint", MONITOR_DEFAULTTONULL, "ptr")   ; test if window is shown on any monitor. alt-tab shows any window even if window is out of monitor.
   ;   return
   WinGet, exStyles, ExStyle, ahk_id %hWnd%
   if (exStyles & WS_EX_APPWINDOW)
   {
      if DllCall("GetProp", "uptr", hWnd, "str", "ITaskList_Deleted", "ptr")
         return false
      if (VirtualDesktopExist = 0) or IsWindowOnCurrentVirtualDesktop(hwnd)
         return true
      else
         return false
   }
   if (exStyles & WS_EX_TOOLWINDOW) or (exStyles & WS_EX_NOACTIVATE)
      return false
   loop
   {
      hwndPrev := hwnd
      hwnd := DllCall("GetWindow", "uptr", hwnd, "uint", GW_OWNER, "ptr")
      if !hwnd
      {
         if DllCall("GetProp", "uptr", hwndPrev, "str", "ITaskList_Deleted", "ptr")
            return false
         if (VirtualDesktopExist = 0) or IsWindowOnCurrentVirtualDesktop(hwndPrev)
            return true
         else
            return false
      }
      if DllCall("IsWindowVisible", "uptr", hwnd)
         return false
      WinGet, exStyles, ExStyle, ahk_id %hwnd%
      if ((exStyles & WS_EX_TOOLWINDOW) or (exStyles & WS_EX_NOACTIVATE)) and !(exStyles & WS_EX_APPWINDOW)
         return false
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
      Return false
   }
   Return true
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
    return count
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
    if (current = 0) {
        MoveOrGotoDesktopNumber(last_desktop)
    } else {
        MoveOrGotoDesktopNumber(current - 1)
    }
    return
}

GoToNextDesktop() {
    global GetCurrentDesktopNumberProc
    current := DllCall(GetCurrentDesktopNumberProc, "Int")
    last_desktop := GetDesktopCount() - 1
    ; If current desktop is last, go to first desktop
    if (current = last_desktop) {
        MoveOrGotoDesktopNumber(0)
    } else {
        MoveOrGotoDesktopNumber(current + 1)
    }
    return
}

GoToDesktopNumber(num) {
    global GoToDesktopNumberProc
    correctDesktopNumber := num-1
    DllCall(GoToDesktopNumberProc, "Int", correctDesktopNumber, "Int")
    return
}

MoveOrGotoDesktopNumber(num) {
    ; If user is holding down Mouse left button, move the current window also
    if (GetKeyState("LButton")) {
        MoveCurrentWindowToDesktop(num)
    } else {
        GoToDesktopNumber(num)
    }
    return
}
/* ;
*****************************
***** UTILITY FUNCTIONS *****
*****************************
*/

; Switch "App" open windows based on the same process and class
HandleWindowsWithSameProcessAndClass(activeProcessName, activeClass) {
    Global MonCount, VD, Highlighter, hitTAB
    SetTimer, track, Off
    windowsToMinimize := []
    minimizedWindows  := []
    finalWindowsListWithProcAndClass := []
    lastActWinID      := ""
    hitTAB := False
    
    currentMon := MWAGetMonitorMouseIsIn()
    Critical, On
    counter := 2
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
            finalWindowsListWithProcAndClass.push(hwndID)
        }
        Else If (mmState == -1) {
            minimizedWindows.push(hwndID)
        }
    }

    loop % minimizedWindows.length()
    {
        minHwndID := minimizedWindows[A_Index]
        finalWindowsListWithProcAndClass.push(minHwndID)
    }

    numWindows := finalWindowsListWithProcAndClass.length()

    If (numWindows <= 1) {
        SetTimer, track, On
        loop 100 {
            Tooltip, Only %numWindows% window found!
            sleep, 10
        }
        Tooltip,
        Return
    }

    WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[1]
    WinGet, mmState, MinMax, % "ahk_id " finalWindowsListWithProcAndClass[counter]
    If (MonCount > 1 && mmState == -1) {
        windowsToMinimize.push(finalWindowsListWithProcAndClass[counter])
        lastActWinID := finalWindowsListWithProcAndClass[counter]
    }
    WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[counter]
    WinGetTitle, actTitle, % "ahk_id " finalWindowsListWithProcAndClass[counter]
    WinGet, pp, ProcessPath , % "ahk_id " finalWindowsListWithProcAndClass[counter]

    Critical, Off
    
    GoSub, DrawRect
    DrawWindowTitlePopup(actTitle, pp, True)
    
    KeyWait, q, U T1

    counter++
    If (counter > numWindows)
    {
        counter := 1
    }

    hwndId := finalWindowsListWithProcAndClass[counter]

    loop
    {
        KeyWait, Lbutton, D T0.1
        If !ErrorLevel {
            MouseGetPos, , , lbhwnd, 
            WinGetTitle, actTitle, ahk_id %lbhwnd%
            WinGet, pp, ProcessPath , ahk_id %lbhwnd%
            
            LclickSelected := True
            GoSub, DrawRect
            DrawWindowTitlePopup(actTitle, pp, True)
            WinSet, AlwaysOnTop, On, ahk_class tooltips_class32
            lastActWinID := lbhwnd

            KeyWait, Lbutton, U
        }
    
        KeyWait, q, D T0.1
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

            KeyWait, q, U
            If !ErrorLevel
            {
                counter++
                If (counter > numWindows)
                {
                    counter := 1
                }
                loop {
                    hwndId := finalWindowsListWithProcAndClass[counter]
                    If !IsWindowOnCurrMon(hwndId, currentMon) {
                        counter++
                        If (counter > numWindows)
                        {
                            counter := 1
                        }
                        hwndId := finalWindowsListWithProcAndClass[counter]
                    }
                    Else
                        break
                }
            }
        }
        WinGetClass, testCl, A
        If (testCl != activeClass) {
            Return
        }
    }
    until (!GetKeyState("LAlt", "P"))
    Gui, WindowTitle: Destroy
    
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

    BlockKeyboard(true)
    counter := counter - 1
    If (counter <= 0)
        counter := finalWindowsListWithProcAndClass.MaxIndex()

    If (counter > 2) {
        WinSet, AlwaysOnTop, On, ahk_id %lastActWinID%
        WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
        WinSet, AlwaysOnTop, On, ahk_id %Highlighter%

        If (finalWindowsListWithProcAndClass.MaxIndex() >= 4 && finalWindowsListWithProcAndClass[4] != lastActWinID) {
            WinGet, isMin, MinMax, % "ahk_id " finalWindowsListWithProcAndClass[4]
            If (isMin > -1)
                WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[4]
        }
        If (finalWindowsListWithProcAndClass.MaxIndex() >= 3 && finalWindowsListWithProcAndClass[3] != lastActWinID) {
            WinGet, isMin, MinMax, % "ahk_id " finalWindowsListWithProcAndClass[3]
            If (isMin > -1)
                WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[3]
        }
        If (finalWindowsListWithProcAndClass.MaxIndex() >= 2 &&  finalWindowsListWithProcAndClass[2] != lastActWinID) {
            WinGet, isMin, MinMax, % "ahk_id " finalWindowsListWithProcAndClass[2]
            If (isMin > -1)
                WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[2]
        }
        If (finalWindowsListWithProcAndClass.MaxIndex() >= 1 && finalWindowsListWithProcAndClass[1] != lastActWinID) {
            WinGet, isMin, MinMax, % "ahk_id " finalWindowsListWithProcAndClass[1]
            If (isMin > -1)
                WinActivate, % "ahk_id " finalWindowsListWithProcAndClass[1]
        }
    }
    WinSet, AlwaysOnTop, Off, ahk_id %lastActWinID%
    WinActivate, ahk_id %lastActWinID%
    BlockKeyboard(false)
    SetTimer, track, On
}

FrameShadow(HGui) {
    DllCall("dwmapi\DwmIsCompositionEnabled","IntP",_ISENABLED) ; Get If DWM Manager is Enabled
    If !_ISENABLED ; If DWM is not enabled, Make Basic Shadow
        DllCall("SetClassLong","UInt",HGui,"Int",-26,"Int",DllCall("GetClassLong","UInt",HGui,"Int",-26)|0x20000)
    else {
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

keyTrack() {
    ListLines, Off
    Global StopAutoFix
    Global TimeOfLastKey

    ControlGetFocus, currCtrl, A
    WinGetClass, currClass, A
    If (currCtrl == "Edit1" && InStr(currClass, "EVERYTHING", true)) {
        StopAutoFix := True
        If ((A_TickCount-TimeOfLastKey) < 650 && A_PriorKey != "Enter" && A_PriorKey != "LButton" && A_ThisHotKey != "Enter" && A_ThisHotKey != "LButton") {
            SetTimer, keyTrack, Off
            ControlGet, OutputVar1, Visible ,, SysListView321, A
            ControlGet, OutputVar2, Visible ,, DirectUIHWND2,  A
            ControlGet, OutputVar3, Visible ,, DirectUIHWND3,  A
            If (OutputVar1 == 1 || OutputVar2 == 1 || OutputVar3 == 1) {
                WinGetClass, testClass, A
                If (testClass == currClass) {
                    BlockKeyboard(true)
                    Send, ^{NumpadAdd}
                    BlockKeyboard(false)
                    sleep, 400
                }
            }
            SetTimer, keyTrack, On
        }
    }
    Else If (currClass == "XLMAIN") {
        StopAutoFix := True
    }
    Else
        StopAutoFix := False
        
    ListLines, On
Return
}

track() {
    ListLines Off
    Global MonCount, MonNum, moving, currentMon, previousMon
    Static x, y, lastX, lastY, lastMon, taskview, PrevActiveWindHwnd, LastActiveWinHwnd1, LastActiveWinHwnd2, LastActiveWinHwnd3, LastActiveWinHwnd4
    Static LbuttonHeld := False

    WinGet, actwndId, ID, A
    MouseGetPos x, y, hwndId
    WinGetClass, classId, ahk_id %hwndId%
    WinGet, targetProc, ProcessName, ahk_id %hwndId%

    CoordMode Mouse

    If (LbuttonHeld && !GetKeyState("Lbutton", "P"))
    {
        LbuttonHeld := False
        Send {Lbutton up}
        WinGet, actwndId, ID, A
    }

    If ((abs(x - lastX) > 10 || abs(y - lastY) > 10) && lastX != "") {
        moving := True
        If (classId == "CabinetWClass" || classId == "Progman" || classId == "WorkerW" || classId == "#32770")
            sleep 250
    } Else {
        moving := False
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
    Else If (MonCount == 1
        &&  x <= 3 && y <= 3
        && !taskview
        && GetKeyState("Lbutton","P"))
    {
        skipCheck := True
    }
    Else If (
        && MonCount == 1
        && x >= A_ScreenWidth-3 && y < A_ScreenHeight-200
        && GetKeyState("Lbutton", "P")
        && MouseIsOverTitleBar())
    {
        KeyWait, Lbutton, T0.2
        If (ErrorLevel == 1 && abs(y-ny) < 3)
        {
            Critical On
            BlockInput, MouseMove
            Send {Lbutton up}
            WinGetTitle, Title, A
            WinGet, hwndVD, ID, A
            WinGetPos, wx, wy, ww, wh, ahk_id %hwndVD%
            newWx := wx

            WinActivate, ahk_class Shell_TrayWnd
            WinSet, AlwaysOnTop , On, %Title%
            ; VD.PinWindow(Title)
            moveAmount := ceil((A_ScreenWidth-wx)/5)
            loop, 5
            {
                newWx += moveAmount
                WinMove, %Title%,, newWx,,,,
                sleep 10
            }
            sleep 50
            Send {LWin down}{Ctrl down}{Right}{Ctrl up}{LWin up}
            WinMove, %Title%,, wx,,,,
            sleep, 250
            ; VD.UnPinWindow(Title)
            WinMinimize, ahk_class Shell_TrayWnd
            WinSet, AlwaysOnTop , Off, %Title%
            WinActivate, %Title%
            Send {Lbutton down}
            LbuttonHeld := True
            BlockInput, MouseMoveOff
            sleep 500
            Critical off
        }
    }
    Else If (
            && MonCount == 1
            && x <= 3 && y < A_ScreenHeight-200
            && GetKeyState("Lbutton", "P")
            && MouseIsOverTitleBar())
    {
        KeyWait, Lbutton, T0.2
        If (ErrorLevel == 1 && abs(y-ny) < 3)
        {
            Critical On
            BlockInput, MouseMove
            Send {Lbutton up}
            WinGetTitle, Title, A
            WinGet, hwndVD, ID, A
            WinGetPos, wx, wy, ww, wh, ahk_id %hwndVD%
            newWx := wx

            WinActivate, ahk_class Shell_TrayWnd
            WinSet, AlwaysOnTop , On, %Title%

            ; VD.PinWindow(Title)
            moveAmount := ceil((wx+ww)/5)
            loop, 5
            {
                newWx -= moveAmount
                WinMove, %Title%,, newWx,,,,
                sleep 10
            }
            sleep 50
            Send {LWin down}{Ctrl down}{Left}{Ctrl up}{LWin up}
            WinMove, %Title%,, wx,,,,
            sleep, 250
            ; VD.UnPinWindow(Title)
            WinMinimize, ahk_class Shell_TrayWnd
            WinSet, AlwaysOnTop , Off, %Title%
            WinActivate, %Title%
            Send {Lbutton down}
            LbuttonHeld := True
            BlockInput, MouseMoveOff
            sleep 500
            Critical Off
        }
    }

    If (MonCount == 1 &&  x > 3 && y > 3 && x < A_ScreenWidth-3 && y < A_ScreenHeight-3)
    {
        taskview  := False
        skipCheck := False
    }

    If (MonCount > 1 && !GetKeyState("LButton","P")) {
        currentMon := MWAGetMonitorMouseIsIn(40)
        If (currentMon > 0 && previousMon != currentMon && previousMon > 0) {
            DetectHiddenWindows, Off
            Critical, On
            WinGet, allWindows, List
            loop % allWindows {
                hwnd_id := allWindows%A_Index%
                WinGet, isMin, MinMax, ahk_id %hwnd_id%
                WinGet, whatProc, ProcessName, ahk_id %hwnd_id%
                currentMonHasActWin := IsWindowOnCurrMon(hwnd_id, currentMon)

                If (isMin > -1 &&  currentMonHasActWin && (IsAltTabWindow(hwnd_id) || whatProc == "Zoom.exe")) {
                    WinActivate, ahk_id %hwnd_id%
                    GoSub, DrawRect
                    GoSub, ClearRect
                    Gui, GUI4Boarder: Hide
                    previousMon := currentMon
                    Critical, Off
                    ListLines On
                    return
                }
            }
        }
        Critical, Off
    }
    
    If (MonCount > 1 && !GetKeyState("LButton","P")) {
        previousMon := currentMon
    }
    ListLines On
}

MouseIsOverTitleBar(xPos := "", yPos := "") {
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

    titlebarHeight := SM_CYMIN-SM_CYSIZEFRAME

    CoordMode, Mouse, Screen
    If (xPos != "" && yPos != "")
        MouseGetPos, , , WindowUnderMouseID
    Else
        MouseGetPos, xPos, yPos, WindowUnderMouseID

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If ((mClass != "Shell_TrayWnd") 
        && (mClass != "WorkerW")  
        && (mClass != "ProgMan")   
        && (mClass != "TaskListThumbnailWnd") 
        && (mClass != "#32768") 
        && (mClass != "Net UI Tool Window")) {
        
        WinGetPosEx(WindowUnderMouseID,x,y,w,h)
        
        SendMessage, 0x84, 0, (xPos & 0xFFFF) | (yPos & 0xFFFF)<<16,, % "ahk_id " WindowUnderMouseID 
        If ((yPos > y) && (yPos < (y+titlebarHeight)) && (ErrorLevel == 2))
            Return True
        Else If ((ErrorLevel != 12) && (mClass != "Chrome_WidgetWin_1") && (yPos > y) && (yPos < (y+titlebarHeight)) && (xPos > x) && (xPos < (x+w-SM_CXBORDER-(45*3)))) {
            ; tooltip, %SM_CXBORDER% - %SM_CYBORDER% : %SM_CXFIXEDFRAME% - %SM_CYFIXEDFRAME%
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
            currMonWidth  := abs(mon%A_Index%right - mon%A_Index%left)
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
            ; WinGetPos, x, y, w, h, Ahk_id %ID%
            ; If (x == x2 && y == y2 && w == w2 && h == h2)
                ; break
            ; x2 := x
            ; y2 := y
            ; w2 := w
            ; h2 := h
        ; }
        ; sleep, 300
        WinGetTitle, title, Ahk_id %ID%
        WinGet, procStr, ProcessName, Ahk_id %ID%
        WinGet, hwndID, ID, Ahk_id %ID%
        WinGetClass, classStr, Ahk_id %ID%

        WinWaitActive, Ahk_id %ID%, , 3
        ; tooltip, %classStr%
        If (classStr == "OperationStatusWindow" || classStr == "#32770") {
            sleep 100
            WinSet, AlwaysOnTop, On, ahk_class %classStr%
        }

        If (IsAltTabWindow(hwndID) || (procStr == "OUTLOOK.EXE" && classStr == "#32770")) {
            If (MonCount == 1) {
                Return
            }

            WinGet, state, MinMax, Ahk_id %ID%
            ; tooltip, %classStr% - %currentMonHasActWin%
            If (state > -1) {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
                If !currentMonHasActWin {
                    WinActivate, Ahk_id %ID%
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

DesktopIcons(FadeIn := True) ; lParam, wParam, Msg, hWnd
{
    ControlGet, hwndProgman, Hwnd,, SysListView321, ahk_class Progman
    ; Toggle See through icons.
    if !FadeIn
    {
        Critical, On
        if hwndProgman=
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
        else
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
    else
    {
        Critical, On
        if hwndProgman=
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
        else
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
Clip(Text="", Reselect="")
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
        LongCopy := A_TickCount, Clipboard := "", LongCopy -= A_TickCount ; LongCopy gauges the amount of time it takes to empty the clipboard which can predict how long the subsequent clipwait will need
        If (Text = "") {
            Send, ^c
            ClipWait, LongCopy ? 0.6 : 0.2, True
        } Else {
            Clipboard := LastClip := Text
            ClipWait, 10
            Send, ^v
        }
        SetTimer, %A_ThisFunc%, -700
        Sleep 20 ; Short sleep in case Clip() is followed by more keystrokes such as {Enter}
        If (Text = "")
            Return LastClip := Clipboard
        Else If ReSelect and ((ReSelect = True) or (StrLen(Text) < 3000))
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
    if (SessionId) {

        ; Older windows 10 version
        ;RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\VirtualDesktops, CurrentVirtualDesktop

        ; Windows 10
        ;RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\%SessionId%\VirtualDesktops, CurrentVirtualDesktop

        ; Windows 11
        RegRead, CurrentDesktopId, HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops, CurrentVirtualDesktop
        if ErrorLevel {
            RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\%SessionId%\VirtualDesktops, CurrentVirtualDesktop
        }

        if (CurrentDesktopId) {
            IdLength := StrLen(CurrentDesktopId)
        }
    }

    ; Get a list of the UUIDs for all virtual desktops on the system
    RegRead, DesktopList, HKEY_CURRENT_USER, SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops, VirtualDesktopIDs
    if (DesktopList) {
        DesktopListLength := StrLen(DesktopList)
        ; Figure out how many virtual desktops there are
        DesktopCount := floor(DesktopListLength / IdLength)
    }
    else {
        DesktopCount := 1
    }

    ; Parse the REG_DATA string that stores the array of UUID's for virtual desktops in the registry.
    i := 0
    while (CurrentDesktopId and i < DesktopCount) {
        StartPos := (i * IdLength) + 1
        DesktopIter := SubStr(DesktopList, StartPos, IdLength)
        OutputDebug, The iterator is pointing at %DesktopIter% and count is %i%.

        ; Break out if we find a match in the list. If we didn't find anything, keep the
        ; old guess and pray we're still correct :-D.
        if (DesktopIter = CurrentDesktopId) {
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
    if ErrorLevel {
        OutputDebug, Error getting current process id: %ErrorLevel%
        return
    }
    OutputDebug, Current Process Id: %ProcessId%

    DllCall("ProcessIdToSessionId", "UInt", ProcessId, "UInt*", SessionId)
    if ErrorLevel {
        OutputDebug, Error getting session id: %ErrorLevel%
        return
    }
    OutputDebug, Current Session Id: %SessionId%
    return SessionId
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
        if (windowIsOnDesktop == 1) {
            return windowID
        }
    }
}

ActivateTopMostWindow() {
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
            If (procName == "Zoom.exe" || (ExStyle & 0x8)) ; skip if zoom or always on top window
                continue
            If (mmState > -1) {
                If (MonCount > 1) {
                    currentMon := MWAGetMonitorMouseIsIn()
                    currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
                }
                Else {
                    currentMonHasActWin := True
                }
                If currentMonHasActWin {
                    WinActivate, ahk_id %hwndID%
                    break
                }
            }
        }
    }
    Critical, Off
    Return
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
;       reported by GetWindowRect.  If moving the window to specific
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

    if (DWMRC<>S_OK)
        {
        if ErrorLevel in -3,-4  ;-- Dll or function not found (older than Vista)
            {
            ;-- Do nothing else (for now)
            }
         else
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
    if (DWMRC<>S_OK)
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
   if (__PIPE_=-1 or __PIPE_GA_=-1)
      Return 0
   Run, %A_AhkPath% "\\.\pipe\%name%",,UseErrorLevel HIDE, PID
   If ErrorLevel
      MsgBox, 262144, ERROR,% "Could not open file:`n" __AHK_EXE_ """\\.\pipe\" name """"
   DllCall("ConnectNamedPipe",@,__PIPE_GA_,@,0)
   DllCall("CloseHandle",@,__PIPE_GA_)
   DllCall("ConnectNamedPipe",@,__PIPE_,@,0)
   script := (A_IsUnicode ? chr(0xfeff) : (chr(239) . chr(187) . chr(191))) TempScript
   if !DllCall("WriteFile",@,__PIPE_,"str",script,_,(StrLen(script)+1)*(A_IsUnicode ? 2 : 1),_ "*",0,@,0)
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
        ControlGetFocus, FocusedControl, A
        ControlGet, FocusedControlHwnd, Hwnd,, %FocusedControl%, A
    }
    Until ( FocusedControlHwnd = Hwnd )
       || ( Seconds && (A_TickCount-StartTime)/1000 >= Seconds )

    Return (FocusedControlHwnd=Hwnd)
}

; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=69925
GetActiveExplorerPath()
{
    explorerHwnd := WinActive("ahk_class CabinetWClass")
    if (explorerHwnd)
    {
        for window in ComObjCreate("Shell.Application").Windows
        {
            if (window.hwnd==explorerHwnd)
            {
                return window.Document.Folder.Self.Path
            }
        }
    }
}

; https://www.reddit.com/r/AutoHotkey/comments/10fmk4h/get_path_of_active_explorer_tab/
GetExplorerPath(hwnd:="") {
    if !hwnd
        hwnd := WinExist("A")
    
    If !WinExist("ahk_id " . hwnd)
        Return false
    
    WinGetClass, clCheck, ahk_id %hwnd%
    
    If (clCheck == "#32770") {
        ; ControlFocus, ToolbarWindow323, ahk_id %hwnd%
        ControlGetText, dir, ToolbarWindow323, ahk_id %hwnd%
        If (dir == "" || !InStr(dir,"address",false))
            ControlGetText, dir, ToolbarWindow324, ahk_id %hwnd%
        Return dir
    }
    else {
        activeTab := 0
        try {
            ControlGet, activeTab, Hwnd,, % "ShellTabWindowClass1", % "ahk_id" hwnd
            for w in ComObjCreate("Shell.Application").Windows {
                if (w.hwnd != hwnd)
                    continue
                if activeTab {
                    static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
                    shellBrowser := ComObjQuery(w, IID_IShellBrowser, IID_IShellBrowser)
                    DllCall(NumGet(numGet(shellBrowser+0)+3*A_PtrSize), "Ptr", shellBrowser, "UInt*", thisTab)
                    if (thisTab != activeTab)
                        continue
                    ObjRelease(shellBrowser)
                }
                If (w.Document.Folder.Self.Path == 0) {
                    ControlGetText, dir, ToolbarWindow323, ahk_id %hwnd%
                    If (dir == "" || !InStr(dir,"address",false))
                        ControlGetText, dir, ToolbarWindow324, ahk_id %hwnd%
                    Return dir
                }
                Else
                    Return w.Document.Folder.Self.Path
            } 
        }catch e {
            ControlGetText, dir, ToolbarWindow323, ahk_id %hwnd%
            If (dir == "" || !InStr(dir,"address",false))
                ControlGetText, dir, ToolbarWindow324, ahk_id %hwnd%
            Return dir
        }
    }
    Return false
}

; https://www.autohotkey.com/boards/viewtopic.php?t=60403
Explorer_GetSelection() {
   WinGetClass, winClass, % "ahk_id" . hWnd := WinExist("A")
   if !(winClass ~= "^(Progman|WorkerW|(Cabinet|Explore)WClass)$")
      Return

   shellWindows := ComObjCreate("Shell.Application").Windows
   if (winClass ~= "Progman|WorkerW")  ; IShellWindows::Item:    https://goo.gl/ihW9Gm
                                       ; IShellFolderViewDual:   https://goo.gl/gnntq3
      shellFolderView := shellWindows.Item( ComObject(VT_UI4 := 0x13, SWC_DESKTOP := 0x8) ).Document
   else {
      for window in shellWindows       ; ShellFolderView object: https://tinyurl.com/yh92uvpa
         if (hWnd = window.HWND) && (shellFolderView := window.Document)
            break
   }
   for item in shellFolderView.SelectedItems
      result .= (result = "" ? "" : "`n") . item.Path
   ;~ if !result
      ;~ result := shellFolderView.Folder.Self.Path
   Return result
}

; https://www.autohotkey.com/boards/viewtopic.php?p=547156
IsPopup(winID) {
    WinGet, ss, Style, ahk_id %winID%
    WinGet, sx, ExStyle, ahk_id %winID%

    If(ss & 0x80000000 && sx & 0x00000080)
        Return true
    Return false
}
; https://www.autohotkey.com/boards/viewtopic.php?t=107842
BlockKeyboard( bAction )
{
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
      if (oWin.HWND = hWnd)
         return oWin
   }
}

IsGoogleDocWindow() {
    WinGetTitle, title, A
    If InStr(title, "Google Sheets", false) || InStr(title, "Google Docs", false) 
        Return True
    Else
        Return False
}

IsEditCtrl() {
    ControlGetFocus, whatCtrl, A
    If InStr(whatCtrl,"Edit",True)
        Return True
    Else
        Return False
}
; ___________________________________

;    Get Explorer Path https://www.autohotkey.com/boards/viewtopic.php?p=587509#p587509
; ___________________________________

; GetExplorerPath(explorerHwnd=0){
    ; if(!explorerHwnd)
        ; ExplorerHwnd:= winactive("ahk_class CabinetWClass")

    ; if(!explorerHwnd){
        ; WinGet, explorerHwnd, List, ahk_class CabinetWClass 
        ; loop, % explorerHwnd
        ; {
            ; loopindex:= A_Index
            ; for window in ComObjCreate("Shell.Application").Windows{
                ; try{
                    ; if (window.hwnd==explorerHwnd%loopindex%){
                        ; folder:= window.Document.Folder.Self.Path
                        ; if (instr(folder,"\"))
                            ; return folder
                    ; }
                ; }
            ; }
        ; }
    ; }else{
        ; for window in ComObjCreate("Shell.Application").Windows{
            ; try{
                ; if (window.hwnd==explorerHwnd)
                    ; return window.Document.Folder.Self.Path
            ; }
        ; }
    ; }
; return false
; }

MouseIsOverTaskbar() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID, CtrlUnderMouseId
    
    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (InStr(mClass,"TrayWnd",false) && InStr(mClass,"Shell",false) && CtrlUnderMouseId != "ToolbarWindow323" && CtrlUnderMouseId != "TrayNotifyWnd1")
        Return True
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
    MouseGetPos, x, y, hwnd, hctrl
    WinGetClass, cl, ahk_id %hwnd%
    try {
        If (InStr(cl, "Shell",false) && InStr(cl, "TrayWnd",false) && hctrl != "TrayNotifyWnd1") {
            If WinExist("ahk_class TaskListThumbnailWnd") {
                return False
            }
            Else {
                pt := UIA.ElementFromPoint(x,y,False)
                ; tooltip, % "val is " pt.CurrentControlType
                return (pt.CurrentControlType == 50033)
            }
        }
        Else
            Return False
    } catch e {
        return False
    }
}

DrawWindowTitlePopup(vtext := "", pathToExe := "", showFullTitle := False) {
    Gui, WindowTitle: Destroy

    If !InStr(vtext, " - ", false)
        showFullTitle := True
    
    If showFullTitle {
        If (StrLen(vtext) > 40) {
            vtext := SubStr(vtext, 1, 40) . "..."
        }
    }
    Else {
        strArray := StrSplit(vtext, "-")
        lastIdx  := strArray.MaxIndex()
        vtext := trim(strArray[lastIdx])
    }
    
    CustomColor := "000000"  ; Can be any RGB color (it will be made transparent below).
    Gui, WindowTitle: +LastFound +AlwaysOnTop -Caption +ToolWindow +HwndTEST ; +ToolWindow avoids a taskbar button and an alt-tab menu item.
    Gui, WindowTitle: Color, %CustomColor%
    Gui, WindowTitle: Font, s24  ; Set a large font size (32-point).
    If InStr(pathToExe, "ApplicationFrameHost", false) {
        Gui, WindowTitle: Add, Picture, xm-20 w48 h48 Icon3, %A_WinDir%\System32\SHELL32.dll
    }
    Else {
        Gui, WindowTitle: Add, Picture, xm-20 w48 h48, %pathToExe%
    }
    Gui, WindowTitle: Add, Text, xp+64 yp+8 cWhite, %vtext%  ; XX & YY serve to auto-size the window.

    drawX := CoordXCenterScreen()
    drawY := CoordYCenterScreen()
    Gui, WindowTitle: Show, Center NoActivate AutoSize ; NoActivate avoids deactivating the currently active window.
    WinGetPos, x, y, w , h, ahk_id %TEST%
    WinSet, Transparent, 225, ahk_id %TEST%
    WinMove, ahk_id %TEST%,, drawX-floor(w/2), drawY-floor(h/2)
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
        && !GetKeyState("Ctrl","P")
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
;------------------------------------------------------------------------------
; Special Exceptions - File Types
;------------------------------------------------------------------------------
::org::
::com::
::net::
::txt::
::aif::
::cda::
::mid::
::mp3::
::mpa::
::ogg::
::wav::
::wma::
::wpl::
::7z ::
::arj::
::deb::
::pkg::
::rar::
::rpm::
::tar::
::gz::
::zip::
::bin::
::dmg::
::iso::
::toast::
::vcd::
::csv::
::dat::
::db::
::log::
::mdb::
::sav::
::sql::
::tar::
::xml::
::email::
::eml::
::emlx::
::msg::
::oft::
::ost::
::pst::
::vcf::
::apk::
::bat::
::bin::
::cgi::
::com::
::exe::
::elf::
::gadget::
::jar::
::msi::
::py::
::wsf::
::fnt::
::fon::
::otf::
::ttf::
::ai::
::bmp::
::gif::
::ico::
::jpeg::
::png::
::ps::
::psd::
::svg::
::tif::
::webp::
::asp::
::cer::
::cfm::
::cgi::
::css::
::htm::
::js::
::jsp::
::part::
::php::
::py::
::rss::
::pri::
::xhtml::
::key::
::odp::
::pps::
::ppt::
::pptx::
::c::
::cgi::
::class::
::cpp::
::cs::
::h::
::java::
::php::
::py::
::sh::
::swift::
::vb::
::ods::
::xls::
::xlsm::
::xlsx::
::bak::
::cab::
::cfg::
::cpl::
::cur::
::dll::
::dmp::
::drv::
::icns::
::ico::
::ini::
::lnk::
::msi::
::sys::
::tmp::
::3g2::
::3gp::
::avi::
::flv::
::h264::
::m4v::
::mkv::
::mov::
::mp4::
::mpg::
::rm::
::swf::
::vob::
::webm::
::wmv::
::doc::
::odt::
::pdf::
::rtf::
::tex::
::txt::
::wpd::
::json::
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
::istn::isn't
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
:?:sice::sive
:?:t hem:: them
:?:toin::tion
:?:iotn::tion
:?:soin::sion
:?:emnt::ment
:?:mnet::ment
:?:oitn::oint
:?:kgin::king
:?:ferance::ference
:?:metn::ment
:?:dya::day
:?:mhz::Mhz
:?:toins::tions
:?:emnts::ments
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
:?:groudn::ground
:?:aliyt::ality
:?:laity::ality
:?:altiy::ality
:?:alit::ality
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
::develope::develop
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
:*:tyring::trying
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
;------------------------------------------------------------------------------
; Common Misspellings - the main list
;------------------------------------------------------------------------------
::outtage::outage
::reuse::re-use
::fucniton::function
::waas::was
::haad::had
::precident::precedent
::ave::have
::ad::had
::catelog::catalog
::legitamite::legitimate
::shoudlnt::shouldn't
::tryin::trying
::discrepencies::discrepancies
::discrepency::discrepancy
::digestable::digestible
::i::I
::fo::of
::fi::If
::ry::try
::tyr::try
::rying::trying
::htp:::http:
::http:\\::http://
::httpL::http:
::herf::href
::deprication::deprecation
::depricated::deprecated
::depricate::deprecate
::desparately::desperately
::avengence::a vengeance
::adbandon::abandon
::abandonned::abandoned
::abbreviatoin::abbreviation
::aberation::aberration
::aborigene::aborigine
::abortificant::abortifacient
::abbout::about
::abot::about
::abotu::about
::abuot::about
::aobut::about
::baout::about
::bouat::about
::abouta::about a
::abou tit::about it
::aboutit::about it
::aboutthe::about the
::abscence::absence
::absense::absence
::abcense::absense
::absolutley::absolutely
::absolutly::absolutely
::asorbed::absorbed
::absorbsion::absorption
::absorbtion::absorption
::abundacies::abundances
::abundancies::abundances
::abundunt::abundant
::abutts::abuts
::acadmic::academic
::accademic::academic
::acedemic::academic
::acadamy::academy
::accademy::academy
::accelleration::acceleration
::acceotable::acceptable
::acceptible::acceptable
::accetpable::acceptable
::acceptence::acceptance
::accessable::accessible
::accension::accession
::accesories::accessories
::accesorise::accessorise
::accidant::accident
::accidentaly::accidentally
::accidently::accidentally
::accidnetally::accidentally
::acclimitization::acclimatization
::accomdate::accommodate
::accomodate::accommodate
::acommodate::accommodate
::acomodate::accommodate
::accomodated::accommodated
::accomodates::accommodates
::accomodating::accommodating
::accomodation::accommodation
::accomodations::accommodations
::accompanyed::accompanied
::acomplish::accomplish
::acomplished::accomplished
::accomplishemnt::accomplishment
::acomplishment::accomplishment
::acomplishments::accomplishments
::accoding::according
::accoring::according
::acording::according
::accordingto::according to
::acordingly::accordingly
::accordeon::accordion
::accordian::accordion
::acconut::account
::acocunt::account
::acuracy::accuracy
::acccused::accused
::accussed::accused
::acused::accused
::acustom::accustom
::acustommed::accustomed
::achive::achieve
::achivement::achievement
::achivements::achievements
::acide::acid
::acknolwedge::acknowledge
::acknowldeged::acknowledged
::acknowledgeing::acknowledging
::accoustic::acoustic
::acquiantence::acquaintance
::aquaintance::acquaintance
::aquiantance::acquaintance
::acquiantences::acquaintances
::accquainted::acquainted
::aquainted::acquainted
::aquire::acquire
::aquired::acquired
::aquiring::acquiring
::aquit::acquit
::acquited::acquitted
::aquitted::acquitted
::accross::across
::activly::actively
::activites::activities
::actaully::actually
::actualy::actually
::actualyl::actually
::acutally::actually
::acutaly::actually
::acutlaly::actually
::atually::actually
::adaption::adaptation
::adaptions::adaptations
::addng::adding
::addtion::addition
::additinal::additional
::addtional::additional
::additinally::additionally
::addres::address
::adres::address
::adress::address
::addresable::addressable
::adresable::addressable
::adressable::addressable
::addresed::addressed
::adressed::addressed
::addressess::addresses
::addresing::addressing
::adresing::addressing
::adecuate::adequate
::adequit::adequate
::adequite::adequate
::adherance::adherence
::adhearing::adhering
::adjusmenet::adjustment
::adjusment::adjustment
::adjustement::adjustment
::adjustemnet::adjustment
::adjustmenet::adjustment
::adminstered::administered
::adminstrate::administrate
::adminstration::administration
::admininistrative::administrative
::adminstrative::administrative
::adminstrator::administrator
::admissability::admissibility
::admissable::admissible
::addmission::admission
::admited::admitted
::admitedly::admittedly
::adolecent::adolescent
::addopt::adopt
::addopted::adopted
::addoptive::adoptive
::adavanced::advanced
::adantage::advantage
::advanage::advantage
::adventrous::adventurous
::advesary::adversary
::advertisment::advertisement
::advertisments::advertisements
::asdvertising::advertising
::adviced::advised
::aeriel::aerial
::aeriels::aerials
::areodynamics::aerodynamics
::asthetic::aesthetic
::asthetical::aesthetic
::asthetically::aesthetically
::afair::affair
::affilate::affiliate
::affilliate::affiliate
::afficionado::aficionado
::afficianados::aficionados
::afficionados::aficionados
::aforememtioned::aforementioned
::affraid::afraid
::afradi::afraid
::afriad::afraid
::afterthe::after the
::agani::again
::agian::again
::agin::again
::againnst::against
::agains::against
::agaisnt::against
::aganist::against
::agianst::against
::aginst::against
::againstt he::against the
::aggaravates::aggravates
::agregate::aggregate
::agregates::aggregates
::agression::aggression
::aggresive::aggressive
::agressive::aggressive
::agressively::aggressively
::agressor::aggressor
::agrieved::aggrieved
::agre::agree
::aggreed::agreed
::agred::agreed
::agreing::agreeing
::aggreement::agreement
::agreeement::agreement
::agreemeent::agreement
::agreemnet::agreement
::agreemnt::agreement
::agreemeents::agreements
::agreemnets::agreements
::agricuture::agriculture
::aheda::ahead
::airbourne::airborne
::aicraft::aircraft
::aircaft::aircraft
::aircrafts::aircraft
::airrcraft::aircraft
::aiport::airport
::airporta::airports
::albiet::albeit
::alchohol::alcohol
::alchol::alcohol
::alcohal::alcohol
::alochol::alcohol
::alchoholic::alcoholic
::alcholic::alcoholic
::alcoholical::alcoholic
::algebraical::algebraic
::algoritm::algorithm
::algorhitms::algorithms
::algoritms::algorithms
::alientating::alienating
::all the itme::all the time
::alltime::all-time
::aledge::allege
::alege::allege
::alledge::allege
::aledged::alleged
::aleged::alleged
::alledged::alleged
::alledgedly::allegedly
::allegedely::allegedly
::allegedy::allegedly
::allegely::allegedly
::aledges::alleges
::alledges::alleges
::alegience::allegiance
::allegence::allegiance
::allegience::allegiance
::alliviate::alleviate
::allopone::allophone
::allopones::allophones
::alotted::allotted
::alowed::allowed
::alowing::allowing
::alusion::allusion
::almots::almost
::almsot::almost
::alomst::almost
::alonw::alone
::allready::already
::alraedy::already
::alreayd::already
::alreday::already
::alredy::already
::aready::already
::alrigth::alright
::alriht::alright
::alsation::Alsatian
::alos::also
::alsot::also
::aslo::also
::laternative::alternative
::alternitives::alternatives
::allthough::although
::altho::although
::althought::although
::altough::although
::altogehter::altogether
::allwasy::always
::allwyas::always
::alwasy::always
::alwats::always
::alway::always
::alwayus::always
::alwyas::always
::awlays::always
::a mnot::am not
::amalgomated::amalgamated
::amatuer::amateur
::amerliorate::ameliorate
::ammend::amend
::ammended::amended
::admendment::amendment
::amendmant::amendment
::ammendment::amendment
::ammendments::amendments
::amoung::among
::amung::among
::amoungst::amongst
::ammount::amount
::amonut::amount
::amoutn::amount
::amplfieir::amplifier
::amplfiier::amplifier
::ampliotude::amplitude
::amploitude::amplitude
::amplotude::amplitude
::amplotuide::amplitude
::amploitudes::amplitudes
::ammused::amused
::analagous::analogous
::analogeous::analogous
::analitic::analytic
::analyse::analyze
::anarchim::anarchism
::anarchistm::anarchism
::ansestors::ancestors
::ancestory::ancestry
::ancilliary::ancillary
::adn::and
::anbd::and
::anmd::and
::an dgot::and got
::andone::and one
::andt he::and the
::andteh::and the
::andthe::and the
::androgenous::androgynous
::androgeny::androgyny
::anihilation::annihilation
::aniversary::anniversary
::annouced::announced
::anounced::announced
::announcemnt::announcement
::anual::annual
::annualy::annually
::annuled::annulled
::anulled::annulled
::annoint::anoint
::annointed::anointed
::annointing::anointing
::annoints::anoints
::anomolies::anomalies
::anomolous::anomalous
::anomoly::anomaly
::anonimity::anonymity
::aanother::another
::anohter::another
::anotehr::another
::anothe::another
::ansewr::answer
::anwsered::answered
::naswered::answered
::antartic::antarctic
::anthromorphisation::anthropomorphisation
::anthromorphization::anthropomorphization
::anti-semetic::anti-Semitic
::anticlimatic::anticlimactic
::anyother::any other
::anuthing::anything
::anyhting::anything
::anythihng::anything
::anytihng::anything
::anyting::anything
::anytying::anything
::naything::anything
::anwyay::anyway
::anywya::anyway
::nayway::anyway
::naywya::anyway
::anyhwere::anywhere
::appart::apart
::aparment::apartment
::aparmtent::apartment
::aparmtnet::apartment
::apartmnet::apartment
::appartment::apartment
::apartmetns::apartments
::appartments::apartments
::apenines::Apennines
::appenines::Apennines
::apolegetics::apologetics
::appologies::apologies
::appology::apology
::aparent::apparent
::apparant::apparent
::apparrent::apparent
::apparantly::apparently
::apparnelty::apparently
::apparnetly::apparently
::apparntely::apparently
::appealling::appealing
::appeareance::appearance
::appearence::appearance
::apperance::appearance
::apprearance::appearance
::appearences::appearances
::apperances::appearances
::appeares::appears
::aplication::application
::applicaiton::application
::applicaitons::applications
::aplied::applied
::appluied::applied
::applyed::applied
::appointiment::appointment
::apprieciate::appreciate
::aprehensive::apprehensive
::approachs::approaches
::appropiate::appropriate
::appropraite::appropriate
::appropropiate::appropriate
::approrpiate::appropriate
::approrpriate::appropriate
::apropriate::appropriate
::approvla::approval
::approproximate::approximate
::aproximate::approximate
::approxamately::approximately
::approxiately::approximately
::approximitely::approximately
::aproximately::approximately
::arbitarily::arbitrarily
::abritrary::arbitrary
::arbitary::arbitrary
::arbouretum::arboretum
::archiac::archaic
::archimedian::Archimedean
::archictect::architect
::archetectural::architectural
::architectual::architectural
::archetecturally::architecturally
::architechturally::architecturally
::archetecture::architecture
::architechture::architecture
::architechtures::architectures
::argubly::arguably
::arguements::arguments
::argumetns::arguments
::armamant::armament
::armistace::armistice
::arised::arose
::arond::around
::aronud::around
::aroud::around
::arround::around
::arund::around
::around ot::around to
::aranged::arranged
::arangement::arrangement
::arragnemetn::arrangement
::arragnemnet::arrangement
::arrangemetn::arrangement
::arrangment::arrangement
::arrangments::arrangements
::arival::arrival
::artical::article
::artice::article
::articel::article
::artilce::article
::artifical::artificial
::artifically::artificially
::artillary::artillery
::asthe::as the
::aswell::as well
::asetic::ascetic
::aisian::Asian
::asside::aside
::askt he::ask the
::asknig::asking
::alseep::asleep
::asphyxation::asphyxiation
::assisnate::assassinate
::assassintation::assassination
::assosication::assassination
::asssassans::assassins
::assualt::assault
::assualted::assaulted
::assemple::assemble
::assertation::assertion
::assesment::assessment
::asign::assign
::assit::assist
::assistent::assistant
::assitant::assistant
::assoicate::associate
::assoicated::associated
::assoicates::associates
::assocation::association
::asume::assume
::asteriod::asteroid
::asychronous::asynchronous
::a tthat::at that
::atthe::at the
::athiesm::atheism
::athiest::atheist
::atheistical::atheistic
::athenean::Athenian
::atheneans::Athenians
::atmospher::atmosphere
::attrocities::atrocities
::attatch::attach
::attahed::attached
::atain::attain
::attemp::attempt
::attemt::attempt
::attemped::attempted
::attemted::attempted
::attemting::attempting
::attemts::attempts
::attendence::attendance
::attendent::attendant
::attendents::attendants
::attened::attended
::atention::attention
::attension::attention
::attentioin::attention
::attitide::attitude
::atorney::attorney
::attributred::attributed
::audeince::audience
::audiance::audience
::austrailia::Australia
::austrailian::Australian
::australian::Australian
::auther::author
::autor::author
::authorative::authoritative
::authoritive::authoritative
::authorites::authorities
::authoritiers::authorities
::authrorities::authorities
::authorithy::authority
::autority::authority
::authobiographic::autobiographic
::authobiography::autobiography
::autochtonous::autochthonous
::autoctonous::autochthonous
::automaticly::automatically
::automibile::automobile
::automonomous::autonomous
::auxillaries::auxiliaries
::auxilliaries::auxiliaries
::auxilary::auxiliary
::auxillary::auxiliary
::auxilliary::auxiliary
::availablility::availability
::avaiable::available
::availaible::available
::availalbe::available
::availble::available
::availiable::available
::availible::available
::avalable::available
::avaliable::available
::avialable::available
::avilable::available
::vaialable::available
::avalance::avalanche
::averageed::averaged
::avation::aviation
::awared::awarded
::awya::away
::aywa::away
::aweomse::awesome
::aweosme::awesome
::awesomoe::awesome
::aziumth::azimuth
::abck::back
::bakc::back
::bcak::back
::backgorund::background
::backrounds::backgrounds
::balence::balance
::ballance::balance
::balacned::balanced
::banannas::bananas
::bandwith::bandwidth
::bankrupcy::bankruptcy
::banruptcy::bankruptcy
::barbeque::barbecue
::barcod::barcode
::basicaly::basically
::basiclaly::basically
::basicly::basically
::batteryes::batteries
::batery::battery
::cattleship::battleship
::bve::be
::beachead::beachhead
::beatiful::beautiful
::beautyfull::beautiful
::beutiful::beautiful
::becamae::became
::baceause::because
::bcause::because
::bceause::because
::bceayuse::because
::beacues::because
::beacuse::because
::becasue::because
::becaues::because
::becaus::because
::becayse::because
::beccause::because
::beceause::because
::becouse::because
::becuase::because
::becuse::because
::ebcause::because
::ebceause::because
::becausea::because a
::becauseof::because of
::becausethe::because the
::becauseyou::because you
::becoe::become
::becomeing::becoming
::becomming::becoming
::bedore::before
::befoer::before
::ebfore::before
::begginer::beginner
::begginers::beginners
::beggining::beginning
::begining::beginning
::beginining::beginning
::beginnig::beginning
::begginings::beginnings
::beggins::begins
::behavour::behaviour
::beng::being
::benig::being
::beleagured::beleaguered
::beligum::belgium
::beleif::belief
::beleiev::believe
::beleieve::believe
::beleive::believe
::belive::believe
::beleived::believed
::belived::believed
::beleives::believes
::beleiving::believing
::belligerant::belligerent
::bellweather::bellwether
::bemusemnt::bemusement
::benefical::beneficial
::benificial::beneficial
::beneficary::beneficiary
::benifit::benefit
::benifits::benefits
::bergamont::bergamot
::bernouilli::Bernoulli
::beseige::besiege
::beseiged::besieged
::beseiging::besieging
::beastiality::bestiality
::beter::better
::betweeen::between
::betwen::between
::bewteen::between
::bweteen::between
::inbetween::between
::vetween::between
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
::bombarment::bombardment
::bonnano::Bonanno
::bootlaoder::bootloader
::bototm::bottom
::bougth::bought
::bondary::boundary
::boundry::boundary
::boxs::boxes
::boyfriedn::boyfriend
::brasillian::Brazilian
::breka::break
::breakthough::breakthrough
::breakthroughts::breakthroughs
::brethen::brethren
::bretheren::brethren
::breif::brief
::breifly::briefly
::brigthness::brightness
::briliant::brilliant
::brillant::brilliant
::brimestone::brimstone
::britian::Britain
::brittish::British
::broacasted::broadcast
::brodcast::broadcast
::broadacasting::broadcasting
::broady::broadly
::brocolli::broccoli
::borke::broke
::borther::brother
::broguht::brought
::buddah::Buddha
::buiding::building
::bouy::buoy
::bouyancy::buoyancy
::buoancy::buoyancy
::bouyant::buoyant
::boyant::buoyant
::beaurocracy::bureaucracy
::bureacracy::bureaucracy
::beaurocratic::bureaucratic
::burried::buried
::buisness::business
::busness::business
::bussiness::business
::busineses::businesses
::buisnessman::businessman
::buit::but
::ubt::but
::ut::but
::butthe::but the
::buynig::buying
::byt he::by the
::caeser::caesar
::ceasar::Caesar
::caffeien::caffeine
::casion::caisson
::calcluate::calculate
::caluclate::calculate
::caluculate::calculate
::calulate::calculate
::claculate::calculate
::calcullated::calculated
::caluclated::calculated
::caluculated::calculated
::calulated::calculated
::claculated::calculated
::calcuation::calculation
::claculation::calculation
::claculations::calculations
::calculs::calculus
::calander::calendar
::calednar::calendar
::calenders::calendars
::califronia::California
::califronian::Californian
::caligraphy::calligraphy
::calilng::calling
::callipigian::callipygian
::cambrige::Cambridge
::cmae::came
::camoflage::camouflage
::campain::campaign
::campains::campaigns
::acn::can
::cna::can
::cxan::can
::cancle::cancel
::candadate::candidate
::candiate::candidate
::candidiate::candidate
::candidtae::candidate
::candidtaes::candidates
::candidtes::candidates
::canidtes::candidates
::cannister::canister
::cannisters::canisters
::cannnot::cannot
::cannonical::canonical
::cantalope::cantaloupe
::caperbility::capability
::capible::capable
::capacitro::capacitor
::cpacitor::capacitor
::capcaitors::capacitors
::capetown::Cape Town
::captial::capital
::captued::captured
::capturd::captured
::carcas::carcass
::cardiod::cardioid
::cardiodi::cardioid
::cardoid::cardioid
::caridoid::cardioid
::carreer::career
::carrers::careers
::carefull::careful
::carribbean::Caribbean
::carribean::Caribbean
::careing::caring
::carmalite::Carmelite
::carniverous::carnivorous
::carthagian::Carthaginian
::cartilege::cartilage
::cartilidge::cartilage
::carthographer::cartographer
::cartdridge::cartridge
::cartrige::cartridge
::casette::cassette
::cassawory::cassowary
::cassowarry::cassowary
::casulaties::casualties
::causalities::casualties
::casulaty::casualty
::categiory::category
::ctaegory::category
::catagory::category
::catagories::categories
::catterpilar::caterpillar
::catterpilars::caterpillars
::cathlic::catholic
::catholocism::catholicism
::caucasion::Caucasian
::cacuses::caucuses
::causeing::causing
::cieling::ceiling
::cellpading::cellpadding
::celcius::Celsius
::cemetaries::cemeteries
::cementary::cemetery
::cemetarey::cemetery
::cemetary::cemetery
::sensure::censure
::cencus::census
::cententenial::centennial
::centruies::centuries
::centruy::century
::cerimonial::ceremonial
::cerimonies::ceremonies
::cerimonious::ceremonious
::cerimony::ceremony
::ceromony::ceremony
::certian::certain
::certainity::certainty
::chariman::chairman
::challange::challenge
::challege::challenge
::challanged::challenged
::challanges::challenges
::chalenging::challenging
::champange::champagne
::chcance::chance
::chaneg::change
::chnage::change
::hcange::change
::changable::changeable
::chagned::changed
::chnaged::changed
::chanegs::changes
::changeing::changing
::changin::changing
::changng::changing
::cahnnel::channel
::chanenl::channel
::channle::channel
::hcannel::channel
::chanenls::channels
::caharcter::character
::carachter::character
::charachter::character
::charactor::character
::charecter::character
::charector::character
::chracter::character
::caracterised::characterised
::charaterised::characterised
::charactersistic::characteristic
::charistics::characteristics
::caracterized::characterized
::charaterized::characterized
::cahracters::characters
::charachters::characters
::charactors::characters
::hcarge::charge
::chargig::charging
::carismatic::charismatic
::charasmatic::charismatic
::chartiable::charitable
::caht::chat
::chcek::check
::chekc::check
::chemcial::chemical
::chemcially::chemically
::chemicaly::chemically
::checmicals::chemicals
::chemestry::chemistry
::cheif::chief
::childbird::childbirth
::childen::children
::chilli::chili
::choosen::chosen
::chrisitan::Christian
::chruch::church
::chuch::church
::churhc::church
::curch::church
::churchs::churches
::cincinatti::Cincinnati
::cincinnatti::Cincinnati
::circut::circuit
::ciricuit::circuit
::curcuit::circuit
::circulaton::circulation
::circumsicion::circumcision
::circumfrence::circumference
::sercumstances::circumstances
::citaion::citation
::cirtus::citrus
::civillian::civilian
::claimes::claims
::clas::class
::clasic::classic
::clasical::classical
::clasically::classically
::claer::clear
::cleareance::clearance
::claered::cleared
::claerer::clearer
::claerly::clearly
::clikc::click
::cliant::client
::clincial::clinical
::clinicaly::clinically
::clipipng::clipping
::clippin::clipping
::closeing::closing
::caost::coast
::coctail::cocktail
::ocde::code
::cognizent::cognizant
::co-incided::coincided
::coincedentally::coincidentally
::colaborations::collaborations
::collaberative::collaborative
::colateral::collateral
::collegue::colleague
::collegues::colleagues
::collectable::collectible
::colection::collection
::collecton::collection
::colelctive::collective
::collonies::colonies
::colonisators::colonisers
::colonizators::colonizers
::collonade::colonnade
::collony::colony
::collosal::colossal
::colum::column
::combintation::combination
::combanations::combinations
::combinatins::combinations
::combusion::combustion
::ocme::come
::comback::comeback
::commedic::comedic
::confortable::comfortable
::comeing::coming
::comming::coming
::commadn::command
::comander::commander
::comando::commando
::comandos::commandos
::commandoes::commandos
::comemmorate::commemorate
::commemmorate::commemorate
::commmemorated::commemorated
::comemmorates::commemorates
::commemmorating::commemorating
::comemoretion::commemoration
::commemerative::commemorative
::commerorative::commemorative
::commerical::commercial
::commericial::commercial
::commerically::commercially
::commericially::commercially
::comission::commission
::commision::commission
::comissioned::commissioned
::commisioned::commissioned
::comissioner::commissioner
::commisioner::commissioner
::comissioning::commissioning
::commisioning::commissioning
::comissions::commissions
::commisions::commissions
::comit::commit
::committment::commitment
::committments::commitments
::comited::committed
::comitted::committed
::commited::committed
::comittee::committee
::commitee::committee
::committe::committee
::committy::committee
::comiting::committing
::comitting::committing
::commiting::committing
::commongly::commonly
::commonweath::commonwealth
::comunicate::communicate
::commiunicating::communicating
::communiucating::communicating
::comminication::communication
::communciation::communication
::communiation::communication
::commuications::communications
::commuinications::communications
::communites::communities
::comunity::community
::comanies::companies
::comapnies::companies
::comany::company
::comapany::company
::comapny::company
::comparitive::comparative
::comparitively::comparatively
::comapre::compare
::compair::compare
::comparision::comparison
::comparisions::comparisons
::compability::compatibility
::compatiable::compatible
::compatioble::compatible
::compensantion::compensation
::competance::competence
::competant::competent
::compitent::competent
::competitiion::competition
::competitoin::competition
::compeitions::competitions
::competative::competitive
::competive::competitive
::competiveness::competitiveness
::copmetitors::competitors
::complier::compiler
::compleated::completed
::completedthe::completed the
::competely::completely
::compleatly::completely
::completelyl::completely
::completley::completely
::completly::completely
::compleatness::completeness
::completness::completeness
::completetion::completion
::ocmplex::complex
::xomplex::complex
::comopnent::component
::componant::component
::comopnents::components
::composate::composite
::comphrehensive::comprehensive
::comprimise::compromise
::compulsary::compulsory
::compulsery::compulsory
::cmoputer::computer
::comptuer::computer
::compuer::computer
::copmuter::computer
::coputer::computer
::ocmputer::computer
::computarised::computerised
::computarized::computerized
::comptuers::computers
::ocmputers::computers
::concieted::conceited
::concieve::conceive
::concieved::conceived
::consentrate::concentrate
::consentrated::concentrated
::consentrates::concentrates
::consept::concept
::consern::concern
::conserned::concerned
::conserning::concerning
::comdemnation::condemnation
::condamned::condemned
::condemmed::condemned
::condensor::condenser
::condidtion::condition
::ocndition::condition
::condidtions::conditions
::condolances::condolences
::conferance::conference
::confidental::confidential
::confidentally::confidentially
::confids::confides
::configureable::configurable
::configuraiton::configuration
::configuraoitn::configuration
::confirmmation::confirmation
::ocnfirmed::confirmed
::coform::conform
::confusnig::confusing
::congradulations::congratulations
::congresional::congressional
::conjecutre::conjecture
::conjuction::conjunction
::connet::connect
::conected::connected
::conneted::connected
::conneticut::Connecticut
::conneting::connecting
::conection::connection
::connectino::connection
::connetion::connection
::connetions::connections
::connetors::connectors
::conived::connived
::cannotation::connotation
::cannotations::connotations
::conotations::connotations
::conquerd::conquered
::conqured::conquered
::conquerer::conqueror
::conquerers::conquerors
::concious::conscious
::consious::conscious
::conciously::consciously
::conciousness::consciousness
::consciouness::consciousness
::consiciousness::consciousness
::consicousness::consciousness
::consectutive::consecutive
::concensus::consensus
::conesencus::consensus
::conscent::consent
::consequeseces::consequences
::consenquently::consequently
::consequentually::consequently
::conservitive::conservative
::concider::consider
::consdider::consider
::considerit::considerate
::considerite::considerate
::concidered::considered
::consdidered::considered
::consdiered::considered
::considerd::considered
::consideres::considered
::concidering::considering
::conciders::considers
::consistant::consistent
::consistnet::consistent
::consistantly::consistently
::consistnelty::consistently
::consistnetly::consistently
::consistntely::consistently
::consolodate::consolidate
::consolodated::consolidated
::consonent::consonant
::consonents::consonants
::consorcium::consortium
::conspiracys::conspiracies
::conspiricy::conspiracy
::conspiriator::conspirator
::constatn::constant
::constnat::constant
::constanly::constantly
::constnatly::constantly
::constarnation::consternation
::consituencies::constituencies
::consituency::constituency
::constituant::constituent
::constituants::constituents
::consituted::constituted
::consitution::constitution
::constituion::constitution
::costitution::constitution
::consitutional::constitutional
::constituional::constitutional
::constriant::constraint
::constaints::constraints
::consttruction::construction
::constuction::construction
::contruction::construction
::consulant::consultant
::consultent::consultant
::consumber::consumer
::consumate::consummate
::consumated::consummated
::comntain::contain
::comtain::contain
::comntains::contains
::comtains::contains
::containes::contains
::countains::contains
::contaiminate::contaminate
::contemporaneus::contemporaneous
::contamporaries::contemporaries
::contamporary::contemporary
::contempoary::contemporary
::contempory::contemporary
::contendor::contender
::constinually::continually
::contined::continued
::continueing::continuing
::continous::continuous
::continously::continuously
::contritutions::contributions
::contributer::contributor
::contributers::contributors
::contorl::control
::controll::control
::controled::controlled
::controling::controlling
::controlls::controls
::contravercial::controversial
::controvercial::controversial
::controversal::controversial
::controvertial::controversial
::controveries::controversies
::contraversy::controversy
::controvercy::controversy
::controvery::controversy
::conveinent::convenient
::convienient::convenient
::convential::conventional
::convertion::conversion
::convertor::converter
::convertors::converters
::convertable::convertible
::convertables::convertibles
::conveyer::conveyor
::conviced::convinced
::cooparate::cooperate
::cooporate::cooperate
::coordiantion::coordination
::cpoy::copy
::copyrigth::copyright
::copywrite::copyright
::coridal::cordial
::corparate::corporate
::corproation::corporation
::coorperations::corporations
::corperations::corporations
::corproations::corporations
::corret::correct
::correciton::correction
::corretly::correctly
::correcters::correctors
::correlatoin::correlation
::corrispond::correspond
::corrisponded::corresponded
::correspondant::correspondent
::corrispondant::correspondent
::correspondants::correspondents
::corrispondants::correspondents
::correponding::corresponding
::correposding::corresponding
::corrisponding::corresponding
::corrisponds::corresponds
::corridoors::corridors
::corosion::corrosion
::corruptable::corruptible
::cotten::cotton
::coudl::could
::oculd::could
::ucould::could
::couldthe::could the
::coucil::council
::counterfiet::counterfeit
::counries::countries
::countires::countries
::ocuntries::countries
::ocuntry::country
::coururier::courier
::convenant::covenant
::creaeted::created
::creedence::credence
::criterias::criteria
::critereon::criterion
::crtical::critical
::critised::criticised
::criticing::criticising
::criticists::critics
::crockodiles::crocodiles
::crucifiction::crucifixion
::crusies::cruises
::crystalisation::crystallisation
::culiminating::culminating
::cumulatative::cumulative
::curiousity::curiosity
::currnet::current
::currenly::currently
::curretnly::currently
::currnets::currents
::ciriculum::curriculum
::curriculem::curriculum
::cusotmer::customer
::cutsomer::customer
::cusotmers::customers
::cutsomers::customers
::cxan::cyan
::cilinder::cylinder
::cyclinder::cylinder
::dakiri::daiquiri
::dalmation::dalmatian
::danceing::dancing
::dardenelles::Dardanelles
::dael::deal
::debateable::debatable
::decaffinated::decaffeinated
::decathalon::decathlon
::decieved::deceived
::decideable::decidable
::deside::decide
::decidely::decidedly
::ecidious::deciduous
::decison::decision
::descision::decision
::desicion::decision
::desision::decision
::decisons::decisions
::descisions::decisions
::desicions::decisions
::desisions::decisions
::decomissioned::decommissioned
::decomposit::decompose
::decomposited::decomposed
::decomposits::decomposes
::decompositing::decomposing
::decress::decrees
::deafult::default
::defendent::defendant
::defendents::defendants
::defencive::defensive
::deffensively::defensively
::definance::defiance
::deffine::define
::deffined::defined
::definining::defining
::definate::definite
::definit::definite
::definately::definitely
::definatly::definitely
::definetly::definitely
::definitly::definitely
::definiton::definition
::defintion::definition
::degredation::degradation
::degrate::degrade
::dieties::deities
::diety::deity
::delagates::delegates
::deliberatly::deliberately
::delerious::delirious
::delusionally::delusively
::devels::delves
::damenor::demeanor
::demenor::demeanor
::damenor::demeanour
::damenour::demeanour
::demenour::demeanour
::demorcracy::democracy
::demographical::demographic
::demolision::demolition
::demostration::demonstration
::denegrating::denigrating
::densly::densely
::deparment::department
::deptartment::department
::dependance::dependence
::dependancy::dependency
::dependant::dependent
::despict::depict
::derivitive::derivative
::deriviated::derived
::dirived::derived
::derogitory::derogatory
::decendant::descendant
::decendent::descendant
::decendants::descendants
::decendents::descendants
::descendands::descendants
::decribe::describe
::discribe::describe
::decribed::described
::descibed::described
::discribed::described
::decribes::describes
::descriibes::describes
::discribes::describes
::decribing::describing
::discribing::describing
::descriptoin::description
::descripton::description
::descripters::descriptors
::dessicated::desiccated
::disign::design
::desgined::designed
::dessigned::designed
::desigining::designing
::desireable::desirable
::desktiop::desktop
::dispair::despair
::desparate::desperate
::despiration::desperation
::dispicable::despicable
::dispite::despite
::destablised::destabilised
::destablized::destabilized
::desinations::destinations
::desitned::destined
::destory::destroy
::desctruction::destruction
::distruction::destruction
::distructive::destructive
::detatched::detached
::detailled::detailed
::deatils::details
::dectect::detect
::deteriate::deteriorate
::deteoriated::deteriorated
::deterioriating::deteriorating
::determinining::determining
::detremental::detrimental
::devasted::devastated
::devestated::devastated
::devestating::devastating
::devistating::devastating
::devellop::develop
::devellops::develop
::develloped::developed
::developped::developed
::develloper::developer
::developor::developer
::develeoprs::developers
::devellopers::developers
::developors::developers
::develloping::developing
::delevopment::development
::devellopment::development
::develpment::development
::devolopement::development
::devellopments::developments
::divice::device
::diablical::diabolical
::diamons::diamonds
::diarhea::diarrhoea
::dichtomy::dichotomy
::didnot::did not
::differance::difference
::diferences::differences
::differances::differences
::difefrent::different
::diferent::different
::diferrent::different
::differant::different
::differemt::different
::differnt::different
::diffrent::different
::differentiatiations::differentiations
::diffcult::difficult
::diffculties::difficulties
::dificulties::difficulties
::diffculty::difficulty
::difficulity::difficulty
::dificulty::difficulty
::delapidated::dilapidated
::dimention::dimension
::dimentional::dimensional
::dimesnional::dimensional
::dimenions::dimensions
::dimentions::dimensions
::diminuitive::diminutive
::diosese::diocese
::diptheria::diphtheria
::diphtong::diphthong
::dipthong::diphthong
::diphtongs::diphthongs
::dipthongs::diphthongs
::diplomancy::diplomacy
::directiosn::direction
::driectly::directly
::directer::director
::directers::directors
::disagreeed::disagreed
::dissagreement::disagreement
::disapear::disappear
::dissapear::disappear
::dissappear::disappear
::dissapearance::disappearance
::disapeared::disappeared
::disappearred::disappeared
::dissapeared::disappeared
::dissapearing::disappearing
::dissapears::disappears
::dissappears::disappears
::dissappointed::disappointed
::disapointing::disappointing
::disaproval::disapproval
::dissarray::disarray
::diaster::disaster
::disasterous::disastrous
::disatrous::disastrous
::diciplin::discipline
::disiplined::disciplined
::unconfortability::discomfort
::diconnects::disconnects
::discontentment::discontent
::dicover::discover
::disover::discover
::dicovered::discovered
::discoverd::discovered
::dicovering::discovering
::dicovers::discovers
::dicovery::discovery
::descuss::discuss
::dicussed::discussed
::desease::disease
::disenchanged::disenchanted
::desintegrated::disintegrated
::desintegration::disintegration
::disobediance::disobedience
::dissobediance::disobedience
::dissobedience::disobedience
::disobediant::disobedient
::dissobediant::disobedient
::dissobedient::disobedient
::desorder::disorder
::desoriented::disoriented
::disparingly::disparagingly
::despatched::dispatched
::dispell::dispel
::dispeled::dispelled
::dispeling::dispelling
::dispells::dispels
::dispence::dispense
::dispenced::dispensed
::dispencing::dispensing
::diaplay::display
::dispaly::display
::unplease::displease
::dispostion::disposition
::disproportiate::disproportionate
::disputandem::disputandum
::disatisfaction::dissatisfaction
::disatisfied::dissatisfied
::disemination::dissemination
::disolved::dissolved
::dissonent::dissonant
::disctinction::distinction
::distiction::distinction
::disctinctive::distinctive
::distingish::distinguish
::distingished::distinguished
::distingquished::distinguished
::distingishes::distinguishes
::distingishing::distinguishing
::ditributed::distributed
::distribusion::distribution
::distrubution::distribution
::disricts::districts
::devide::divide
::devided::divided
::divison::division
::divisons::divisions
::docrines::doctrines
::doctines::doctrines
::doccument::document
::docuemnt::document
::documetn::document
::documnet::document
::documenatry::documentary
::doccumented::documented
::doccuments::documents
::docuement::documents
::documnets::documents
::doese::does
::doe snot::does not ; *could* be legitimate... but very unlikely!
::doign::doing
::doimg::doing
::doind::doing
::donig::doing
::dollers::dollars
::dominent::dominant
::dominiant::dominant
::dominaton::domination
::don't no::don't know
::doulbe::double
::dowloads::downloads
::dramtic::dramatic
::draughtman::draughtsman
::dravadian::Dravidian
::deram::dream
::derams::dreams
::dreasm::dreams
::drnik::drink
::driveing::driving
::drummless::drumless
::druming::drumming
::drunkeness::drunkenness
::dukeship::dukedom
::dumbell::dumbbell
::dupicate::duplicate
::durig::during
::durring::during
::duting::during
::dieing::dying
::eahc::each
::eachotehr::eachother
::ealier::earlier
::earlies::earliest
::eearly::early
::earnt::earned
::ecclectic::eclectic
::eclispe::eclipse
::ecomonic::economic
::eceonomy::economy
::esctasy::ecstasy
::eles::eels
::effeciency::efficiency
::efficency::efficiency
::effecient::efficient
::efficent::efficient
::effeciently::efficiently
::efficently::efficiently
::effulence::effluence
::efort::effort
::eforts::efforts
::aggregious::egregious
::eight o::eight o
::eigth::eighth
::eiter::either
::ellected::elected
::electrial::electrical
::electricly::electrically
::electricty::electricity
::eletricity::electricity
::elementay::elementary
::elimentary::elementary
::elphant::elephant
::elicided::elicited
::eligable::eligible
::eleminated::eliminated
::eleminating::eliminating
::alse::else
::esle::else
::eminate::emanate
::eminated::emanated
::embargos::embargoes
::embarras::embarrass
::embarrased::embarrassed
::embarrasing::embarrassing
::embarrasment::embarrassment
::embezelled::embezzled
::emblamatic::emblematic
::emmigrated::emigrated
::emmisaries::emissaries
::emmisarries::emissaries
::emmisarry::emissary
::emmisary::emissary
::emision::emission
::emmision::emission
::emmisions::emissions
::emited::emitted
::emmited::emitted
::emmitted::emitted
::emiting::emitting
::emmiting::emitting
::emmitting::emitting
::emphsis::emphasis
::emphaised::emphasised
::emphysyma::emphysema
::emperical::empirical
::imploys::employs
::enameld::enamelled
::encouraing::encouraging
::encryptiion::encryption
::encylopedia::encyclopedia
::endevors::endeavors
::endevour::endeavour
::endevours::endeavours
::endig::ending
::endolithes::endoliths
::enforceing::enforcing
::engagment::engagement
::engeneer::engineer
::engieneer::engineer
::engeneering::engineering
::engieneers::engineers
::enlish::English
::enchancement::enhancement
::emnity::enmity
::enourmous::enormous
::enourmously::enormously
::enought::enough
::ensconsed::ensconced
::entaglements::entanglements
::intertaining::entertaining
::enteratinment::entertainment
::entitlied::entitled
::entitity::entity
::entrepeneur::entrepreneur
::entrepeneurs::entrepreneurs
::intrusted::entrusted
::enviornment::environment
::enviornmental::environmental
::enviornmentalist::environmentalist
::enviornmentally::environmentally
::enviornments::environments
::envrionments::environments
::epsiode::episode
::epidsodes::episodes
::equitorial::equatorial
::equilibium::equilibrium
::equilibrum::equilibrium
::equippment::equipment
::equiped::equipped
::equialent::equivalent
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
::especally::especially
::especialy::especially
::especialyl::especially
::espesially::especially
::expecially::especially
::expresso::espresso
::essense::essence
::esential::essential
::essencial::essential
::essentail::essential
::essentual::essential
::essesital::essential
::essentialy::essentially
::estabishes::establishes
::establising::establishing
::esitmated::estimated
::ect::etc
::ethnocentricm::ethnocentrism
::europian::European
::eurpean::European
::eurpoean::European
::europians::Europeans
::evenhtually::eventually
::eventally::eventually
::eventially::eventually
::eventualy::eventually
::eveyr::every
::everytime::every time
::everthing::everything
::evidentally::evidently
::efel::evil
::envolutionary::evolutionary
::exerbate::exacerbate
::exerbated::exacerbated
::excact::exact
::exagerate::exaggerate
::exagerrate::exaggerate
::exagerated::exaggerated
::exagerrated::exaggerated
::exagerates::exaggerates
::exagerrates::exaggerates
::exagerating::exaggerating
::exagerrating::exaggerating
::exhalted::exalted
::examinated::examined
::exemple::example
::exmaple::example
::excedded::exceeded
::exeedingly::exceedingly
::excell::excel
::excellance::excellence
::excelent::excellent
::excellant::excellent
::exelent::excellent
::exellent::excellent
::excells::excels
::exept::except
::exeptional::exceptional
::exerpt::excerpt
::exerpts::excerpts
::excange::exchange
::exchagne::exchange
::exhcange::exchange
::exchagnes::exchanges
::exhcanges::exchanges
::exchanching::exchanging
::excitment::excitement
::exicting::exciting
::exludes::excludes
::exculsivly::exclusively
::excecute::execute
::excecuted::executed
::exectued::executed
::excecutes::executes
::excecuting::executing
::excecution::execution
::exection::execution
::exampt::exempt
::excercise::exercise
::exersize::exercise
::exerciese::exercises
::execising::exercising
::extered::exerted
::exhibtion::exhibition
::exibition::exhibition
::exibitions::exhibitions
::exliled::exiled
::excisted::existed
::existance::existence
::existince::existence
::existant::existent
::exisiting::existing
::exonorate::exonerate
::exoskelaton::exoskeleton
::exapansion::expansion
::expeced::expected
::expeditonary::expeditionary
::expiditions::expeditions
::expell::expel
::expells::expels
::experiance::experience
::experienc::experience
::expierence::experience
::exprience::experience
::experianced::experienced
::exprienced::experienced
::expeiments::experiments
::expalin::explain
::explaning::explaining
::explaination::explanation
::explictly::explicitly
::explotation::exploitation
::exploititive::exploitative
::exressed::expressed
::expropiated::expropriated
::expropiation::expropriation
::extention::extension
::extentions::extensions
::exerternal::external
::exinct::extinct
::extradiction::extradition
::extrordinarily::extraordinarily
::extrordinary::extraordinary
::extravagent::extravagant
::extemely::extremely
::extrememly::extremely
::extremly::extremely
::extermist::extremist
::extremeophile::extremophile
::fascitious::facetious
::facillitate::facilitate
::facilites::facilities
::farenheit::Fahrenheit
::familair::familiar
::familar::familiar
::familliar::familiar
::fammiliar::familiar
::familes::families
::fimilies::families
::famoust::famous
::fanatism::fanaticism
::facia::fascia
::fascitis::fasciitis
::facinated::fascinated
::facist::fascist
::favoutrable::favourable
::feasable::feasible
::faeture::feature
::faetures::features
::febuary::February
::fedreally::federally
::efel::feel
::fertily::fertility
::fued::feud
::fwe::few
::ficticious::fictitious
::fictious::fictitious
::feild::field
::feilds::fields
::fiercly::fiercely
::firey::fiery
::fightings::fighting
::filiament::filament
::fiel::file
::fiels::files
::fianlly::finally
::finaly::finally
::finalyl::finally
::finacial::financial
::financialy::financially
::fidn::find
::fianite::finite
::firts::first
::fisionable::fissionable
::ficed::fixed
::flamable::flammable
::flawess::flawless
::flemmish::Flemish
::glight::flight
::fluorish::flourish
::florescent::fluorescent
::flourescent::fluorescent
::flouride::fluoride
::foucs::focus
::focussed::focused
::focusses::focuses
::focussing::focusing
::follwo::follow
::follwoing::following
::folowing::following
::formalhaut::Fomalhaut
::foootball::football
::fora::for a
::forthe::for the
::forbad::forbade
::forbiden::forbidden
::forhead::forehead
::foriegn::foreign
::formost::foremost
::forunner::forerunner
::forsaw::foresaw
::forseeable::foreseeable
::fortelling::foretelling
::foreward::foreword
::forfiet::forfeit
::formallise::formalise
::formallised::formalised
::formallize::formalize
::formallized::formalized
::formaly::formally
::fomed::formed
::fromed::formed
::formelly::formerly
::fourties::forties
::fourty::forty
::forwrd::forward
::foward::forward
::forwrds::forwards
::fowards::forwards
::faught::fought
::fougth::fought
::foudn::found
::foundaries::foundries
::foundary::foundry
::fouth::fourth
::fransiscan::Franciscan
::fransiscans::Franciscans
::frequentily::frequently
::freind::friend
::freindly::friendly
::firends::friends
::freinds::friends
::frmo::from
::frome::from
::fromt he::from the
::fromthe::from the
::froniter::frontier
::fufill::fulfill
::fufilled::fulfilled
::fulfiled::fulfilled
::funtion::function
::fundametal::fundamental
::fundametals::fundamentals
::furneral::funeral
::funguses::fungi
::firc::furc
::furuther::further
::futhermore::furthermore
::galatic::galactic
::galations::Galatians
::gallaxies::galaxies
::galvinised::galvanised
::galvinized::galvanized
::gameboy::Game Boy
::ganes::games
::ghandi::Gandhi
::ganster::gangster
::garnison::garrison
::guage::gauge
::geneological::genealogical
::geneologies::genealogies
::geneology::genealogy
::gemeral::general
::generaly::generally
::generatting::generating
::genialia::genitalia
::geographicial::geographical
::geometrician::geometer
::geometricians::geometers
::geting::getting
::gettin::getting
::guilia::Giulia
::guiliani::Giuliani
::guilio::Giulio
::guiseppe::Giuseppe
::gievn::given
::giveing::giving
::glace::glance
::gloabl::global
::gnawwed::gnawed
::godess::goddess
::godesses::goddesses
::godounov::Godunov
::goign::going
::gonig::going
::oging::going
::giid::good
::gothenberg::Gothenburg
::gottleib::Gottlieb
::goverance::governance
::govement::government
::govenment::government
::govenrment::government
::goverment::government
::governmnet::government
::govorment::government
::govornment::government
::govermental::governmental
::govormental::governmental
::gouvener::governor
::governer::governor
::gracefull::graceful
::graffitti::graffiti
::grafitti::graffiti
::grammer::grammar
::gramatically::grammatically
::grammaticaly::grammatically
::greatful::grateful
::greatfully::gratefully
::gratuitious::gratuitous
::gerat::great
::graet::great
::grat::great
::gridles::griddles
::greif::grief
::gropu::group
::gruop::group
::gruops::groups
::grwo::grow
::guadulupe::Guadalupe
::gunanine::guanine
::gauarana::guarana
::gaurantee::guarantee
::gaurentee::guarantee
::guarentee::guarantee
::gurantee::guarantee
::gauranteed::guaranteed
::gaurenteed::guaranteed
::guarenteed::guaranteed
::guranteed::guaranteed
::gaurantees::guarantees
::gaurentees::guarantees
::guarentees::guarantees
::gurantees::guarantees
::gaurd::guard
::guatamala::Guatemala
::guatamalan::Guatemalan
::guidence::guidance
::guiness::Guinness
::guttaral::guttural
::gutteral::guttural
::gusy::guys
::habaeus::habeas
::habeus::habeas
::habsbourg::Habsburg
::hda::had
::hadbeen::had been
::haemorrage::haemorrhage
::hallowean::Halloween
::ahppen::happen
::hapen::happen
::hapened::happened
::happend::happened
::happended::happened
::happenned::happened
::hapening::happening
::hapens::happens
::harras::harass
::harased::harassed
::harrased::harassed
::harrassed::harassed
::harrasses::harassed
::harases::harasses
::harrases::harasses
::harrasing::harassing
::harrassing::harassing
::harassement::harassment
::harrasment::harassment
::harrassment::harassment
::harrasments::harassments
::harrassments::harassments
::hace::hare
::hsa::has
::hasbeen::has been
::ahev::have
::ahve::have
::haev::have
::hvae::have
::havebeen::have been
::haveing::having
::hvaing::having
::hge::he
::hesaid::he said
::hewas::he was
::headquater::headquarter
::headquatered::headquartered
::headquaters::headquarters
::healthercare::healthcare
::heathy::healthy
::heared::heard
::hearign::hearing
::herat::heart
::haviest::heaviest
::heidelburg::Heidelberg
::hieght::height
::hier::heir
::heirarchy::heirarchy
::helment::helmet
::halp::help
::hlep::help
::helpped::helped
::helpfull::helpful
::hemmorhage::hemorrhage
::ehr::her
::ehre::here
::heridity::heredity
::heroe::hero
::heros::heroes
::hertzs::hertz
::hesistant::hesitant
::heterogenous::heterogeneous
::heirarchical::hierarchical
::hierachical::hierarchical
::hierarcical::hierarchical
::heirarchies::hierarchies
::hierachies::hierarchies
::heirarchy::hierarchy
::hierachy::hierarchy
::hierarcy::hierarchy
::hieroglph::hieroglyph
::heiroglyphics::hieroglyphics
::hieroglphs::hieroglyphs
::heigher::higher
::higer::higher
::higest::highest
::higway::highway
::hillarious::hilarious
::himselv::himself
::hismelf::himself
::hinderance::hindrance
::hinderence::hindrance
::hindrence::hindrance
::hipopotamus::hippopotamus
::hersuit::hirsute
::hsi::his
::ihs::his
::historicians::historians
::hsitorians::historians
::hstory::history
::hitsingles::hit singles
::hosited::hoisted
::holliday::holiday
::homestate::home state
::homogeneize::homogenize
::homogeneized::homogenized
::honourarium::honorarium
::honory::honorary
::honourific::honorific
::hounour::honour
::horrifing::horrifying
::hospitible::hospitable
::housr::hours
::howver::however
::huminoid::humanoid
::humoural::humoral
::humer::humour
::humerous::humourous
::humurous::humourous
::husban::husband
::hydogen::hydrogen
::hydropile::hydrophile
::hydropilic::hydrophilic
::hydropobe::hydrophobe
::hydropobic::hydrophobic
::hygeine::hygiene
::hypocracy::hypocrisy
::hypocrasy::hypocrisy
::hypocricy::hypocrisy
::hypocrit::hypocrite
::hypocrits::hypocrites
::i"d::I'd
::i"m::I'm
::I"m::I'm
::i"ll::I'll
::i"ve::I've
::ti"s::it's
::iconclastic::iconoclastic
::idae::idea
::idaeidae::idea
::idaes::ideas
::identicial::identical
::identifers::identifiers
::identofy::identify
::idealogies::ideologies
::idealogy::ideology
::idiosyncracy::idiosyncrasy
::ideosyncratic::idiosyncratic
::ignorence::ignorance
::illiegal::illegal
::illegimacy::illegitimacy
::illegitmate::illegitimate
::illess::illness
::ilness::illness
::ilogical::illogical
::ilumination::illumination
::illution::illusion
::imagenary::imaginary
::imagin::imagine
::inbalance::imbalance
::inbalanced::imbalanced
::imediate::immediate
::emmediately::immediately
::imediately::immediately
::imediatly::immediately
::immediatley::immediately
::immediatly::immediately
::immidately::immediately
::immidiately::immediately
::imense::immense
::inmigrant::immigrant
::inmigrants::immigrants
::imanent::imminent
::immunosupressant::immunosuppressant
::inpeach::impeach
::impecabbly::impeccably
::impedence::impedance
::implamenting::implementing
::inpolite::impolite
::importamt::important
::importent::important
::importnat::important
::impossable::impossible
::emprisoned::imprisoned
::imprioned::imprisoned
::imprisonned::imprisoned
::inprisonment::imprisonment
::improvemnt::improvement
::improvment::improvement
::improvments::improvements
::inproving::improving
::improvision::improvisation
::int he::in the
::inteh::in the
::inthe::in the
::inwhich::in which
::inablility::inability
::inaccessable::inaccessible
::inadiquate::inadequate
::inadquate::inadequate
::inadvertant::inadvertent
::inadvertantly::inadvertently
::inappropiate::inappropriate
::inagurated::inaugurated
::inaugures::inaugurates
::inaguration::inauguration
::incarcirated::incarcerated
::incidentially::incidentally
::incidently::incidentally
::includ::include
::includng::including
::incuding::including
::incomptable::incompatible
::incompetance::incompetence
::incompetant::incompetent
::incomptetent::incompetent
::imcomplete::incomplete
::inconsistant::inconsistent
::incorportaed::incorporated
::incorprates::incorporates
::incorperation::incorporation
::incorruptable::incorruptible
::inclreased::increased
::increadible::incredible
::incredable::incredible
::incramentally::incrementally
::incunabla::incunabula
::indefinately::indefinitely
::indefinitly::indefinitely
::indepedence::independence
::independance::independence
::independece::independence
::indipendence::independence
::indepedent::independent
::independant::independent
::independendet::independent
::indipendent::independent
::indpendent::independent
::indepedantly::independently
::independantly::independently
::indipendently::independently
::indpendently::independently
::indecate::indicate
::indite::indict
::indictement::indictment
::indigineous::indigenous
::indispensible::indispensable
::individualy::individually
::indviduals::individuals
::enduce::induce
::indulgue::indulge
::indutrial::industrial
::inudstry::industry
::inefficienty::inefficiently
::unequalities::inequalities
::inevatible::inevitable
::inevitible::inevitable
::inevititably::inevitably
::infalability::infallibility
::infallable::infallible
::infrantryman::infantryman
::infectuous::infectious
::infered::inferred
::infilitrate::infiltrate
::infilitrated::infiltrated
::infilitration::infiltration
::infinit::infinite
::infinitly::infinitely
::enflamed::inflamed
::inflamation::inflammation
::influance::influence
::influented::influenced
::influencial::influential
::infomation::information
::informatoin::information
::informtion::information
::infrigement::infringement
::ingenius::ingenious
::ingreediants::ingredients
::inhabitans::inhabitants
::inherantly::inherently
::inheritence::inheritance
::inital::initial
::intial::initial
::ititial::initial
::initally::initially
::intially::initially
::initation::initiation
::initiaitive::initiative
::inate::innate
::inocence::innocence
::inumerable::innumerable
::innoculate::inoculate
::innoculated::inoculated
::insectiverous::insectivorous
::insensative::insensitive
::inseperable::inseparable
::insistance::insistence
::instatance::instance
::instade::instead
::insted::instead
::institue::institute
::instutionalized::institutionalized
::instuction::instruction
::instuments::instruments
::insufficent::insufficient
::insufficently::insufficiently
::insurence::insurance
::intergrated::integrated
::intergration::integration
::intelectual::intellectual
::inteligence::intelligence
::inteligent::intelligent
::interchangable::interchangeable
::interchangably::interchangeably
::intercontinetal::intercontinental
::intrest::interest
::itnerest::interest
::itnerested::interested
::itneresting::interesting
::itnerests::interests
::interferance::interference
::interfereing::interfering
::interm::interim
::interrim::interim
::interum::interim
::intenational::international
::interational::international
::internation::international
::interpet::interpret
::intepretation::interpretation
::intepretator::interpretor
::interrugum::interregnum
::interelated::interrelated
::interupt::interrupt
::intevene::intervene
::intervines::intervenes
::inot::into
::inctroduce::introduce
::inctroduced::introduced
::intrduced::introduced
::introdued::introduced
::intruduced::introduced
::itnroduced::introduced
::instutions::intuitions
::intutive::intuitive
::intutively::intuitively
::inventer::inventor
::invertibrates::invertebrates
::investingate::investigate
::involvment::involvement
::ironicly::ironically
::irelevent::irrelevant
::irrelevent::irrelevant
::irreplacable::irreplaceable
::iresistable::irresistible
::iresistible::irresistible
::irresistable::irresistible
::iresistably::irresistibly
::iresistibly::irresistibly
::irresistably::irresistibly
::iritable::irritable
::iritated::irritated
::i snot::is not
::isthe::is the
::issueing::issuing
::itis::it is
::itwas::it was
::its a::it's a
::it snot::it's not
::it' snot::it's not
::iits the::it's the
::its the::it's the
::ihaca::Ithaca
::jaques::jacques
::japanes::Japanese
::jeapardy::jeopardy
::jewelery::jewellery
::jewllery::jewellery
::johanine::Johannine
::jospeh::Joseph
::jouney::journey
::journied::journeyed
::journies::journeys
::juadaism::Judaism
::juadism::Judaism
::judgment::judgement
::jugment::judgment
::judical::judicial
::juducial::judicial
::judisuary::judiciary
::iunior::junior
::juristiction::jurisdiction
::juristictions::jurisdictions
::jstu::just
::jsut::just
::kindergarden::kindergarten
::klenex::kleenex
::knive::knife
::knifes::knives
::konw::know
::kwno::know
::nkow::know
::nkwo::know
::knowldge::knowledge
::knowlege::knowledge
::knowlegeable::knowledgeable
::knwon::known
::konws::knows
::labled::labelled
::labratory::laboratory
::labourious::laborious
::layed::laid
::laguage::language
::laguages::languages
::larg::large
::largst::largest
::larrry::larry
::lavae::larvae
::lazer::laser
::lasoo::lasso
::lastr::last
::lsat::last
::lastyear::last year
::lastest::latest
::lattitude::latitude
::launchs::launch
::launhed::launched
::lazyness::laziness
::leage::league
::leran::learn
::learnign::learning
::lerans::learns
::elast::least
::leaded::led
::lefted::left
::legitamate::legitimate
::legitmate::legitimate
::leibnitz::leibniz
::liesure::leisure
::lenght::length
::leathal::lethal
::let's him::lets him
::let's it::lets it
::levle::level
::levetate::levitate
::levetated::levitated
::levetates::levitates
::levetating::levitating
::liasion::liaison
::liason::liaison
::liasons::liaisons
::libell::libel
::libitarianisn::libertarianism
::libary::library
::librarry::library
::librery::library
::lybia::Libya
::lisense::license
::leutenant::lieutenant
::lieutenent::lieutenant
::liftime::lifetime
::lightyear::light year
::lightyears::light years
::lightening::lightning
::liek::like
::liuke::like
::liekd::liked
::likelyhood::likelihood
::likly::likely
::lukid::likud
::lmits::limits
::libguistic::linguistic
::libguistics::linguistics
::linnaena::linnaean
::lippizaner::lipizzaner
::liquify::liquefy
::listners::listeners
::litterally::literally
::litature::literature
::literture::literature
::littel::little
::litttle::little
::liev::live
::lieved::lived
::livley::lively
::liveing::living
::lonelyness::loneliness
::lonley::lonely
::lonly::lonely
::longitudonal::longitudinal
::lookign::looking
::loosing::losing
::lotharingen::lothringen
::loev::love
::lveo::love
::lvoe::love
::lieing::lying
::mackeral::mackerel
::amde::made
::magasine::magazine
::magincian::magician
::magnificient::magnificent
::magolia::magnolia
::mailny::mainly
::mantain::maintain
::mantained::maintained
::maintinaing::maintaining
::maintainance::maintenance
::maintainence::maintenance
::maintance::maintenance
::maintenence::maintenance
::majoroty::majority
::marjority::majority
::amke::make
::mkae::make
::mkea::make
::amkes::makes
::makse::makes
::mkaes::makes
::amking::making
::makeing::making
::mkaing::making
::malcom::Malcolm
::maltesian::Maltese
::mamal::mammal
::mamalian::mammalian
::managable::manageable
::managment::management
::manuver::maneuver
::manoeuverability::maneuverability
::manifestion::manifestation
::manisfestations::manifestations
::manufature::manufacture
::manufacturedd::manufactured
::manufatured::manufactured
::manufaturing::manufacturing
::mrak::mark
::maked::marked
::marketting::marketing
::markes::marks
::marmelade::marmalade
::mariage::marriage
::marrage::marriage
::marraige::marriage
::marryied::married
::marrtyred::martyred
::massmedia::mass media
::massachussets::Massachusetts
::massachussetts::Massachusetts
::masterbation::masturbation
::materalists::materialist
::mathmatically::mathematically
::mathematican::mathematician
::mathmatician::mathematician
::matheticians::mathematicians
::mathmaticians::mathematicians
::mathamatics::mathematics
::mathematicas::mathematics
::may of::may have
::mccarthyst::mccarthyist
::meaninng::meaning
::menat::meant
::mchanics::mechanics
::medieval::mediaeval
::medacine::medicine
::mediciney::mediciny
::medeival::medieval
::medevial::medieval
::medievel::medieval
::mediterainnean::mediterranean
::mediteranean::Mediterranean
::meerkrat::meerkat
::memeber::member
::membranaphone::membranophone
::momento::memento
::rememberable::memorable
::menally::mentally
::maintioned::mentioned
::mercentile::mercantile
::mechandise::merchandise
::merchent::merchant
::mesage::message
::mesages::messages
::messenging::messaging
::messanger::messenger
::metalic::metallic
::metalurgic::metallurgic
::metalurgical::metallurgical
::metalurgy::metallurgy
::metamorphysis::metamorphosis
::methaphor::metaphor
::metaphoricial::metaphorical
::methaphors::metaphors
::mataphysical::metaphysical
::meterologist::meteorologist
::meterology::meteorology
::micheal::Michael
::michagan::Michigan
::micoscopy::microscopy
::midwifes::midwives
::might of::might have
::mileau::milieu
::mileu::milieu
::melieux::milieux
::miliary::military
::miliraty::military
::millitary::military
::miltary::military
::milennia::millennia
::millenia::millennia
::millenial::millennial
::millenialism::millennialism
::milennium::millennium
::millenium::millennium
::milion::million
::millon::million
::millioniare::millionaire
::millepede::millipede
::minerial::mineral
::minature::miniature
::minumum::minimum
::minstries::ministries
::ministery::ministry
::minstry::ministry
::miniscule::minuscule
::mirrorred::mirrored
::miscelaneous::miscellaneous
::miscellanious::miscellaneous
::miscellanous::miscellaneous
::mischeivous::mischievous
::mischevious::mischievous
::mischievious::mischievous
::misdameanor::misdemeanor
::misdemenor::misdemeanor
::misdameanors::misdemeanors
::misdemenors::misdemeanors
::misfourtunes::misfortunes
::mysogynist::misogynist
::mysogyny::misogyny
::misile::missile
::missle::missile
::missonary::missionary
::missisipi::Mississippi
::missisippi::Mississippi
::misouri::Missouri
::mispell::misspell
::mispelled::misspelled
::mispelling::misspelling
::mispellings::misspellings
::mythraic::Mithraic
::missen::mizzen
::modle::model
::moderm::modem
::moil::mohel
::mosture::moisture
::moleclues::molecules
::moent::moment
::monestaries::monasteries
::monestary::monastery
::moeny::money
::monickers::monikers
::monkies::monkeys
::monolite::monolithic
::montypic::monotypic
::mounth::month
::monts::months
::monserrat::Montserrat
::mroe::more
::omre::more
::moreso::more so
::morisette::Morissette
::morrisette::Morissette
::morroccan::moroccan
::morrocco::morocco
::morroco::morocco
::morgage::mortgage
::motiviated::motivated
::mottos::mottoes
::montanous::mountainous
::montains::mountains
::movment::movement
::movei::movie
::mucuous::mucous
::multicultralism::multiculturalism
::multipled::multiplied
::multiplers::multipliers
::muncipalities::municipalities
::muncipality::municipality
::munnicipality::municipality
::muder::murder
::mudering::murdering
::muscial::musical
::muscician::musician
::muscicians::musicians
::muhammadan::muslim
::mohammedans::muslims
::must of::must have
::mutiliated::mutilated
::myu::my
::myraid::myriad
::mysef::myself
::mysefl::myself
::misterious::mysterious
::misteryous::mysterious
::mysterous::mysterious
::mistery::mystery
::naieve::naive
::napoleonian::Napoleonic
::ansalisation::nasalisation
::ansalization::nasalization
::naturual::natural
::naturaly::naturally
::naturely::naturally
::naturually::naturally
::nazereth::Nazareth
::neccesarily::necessarily
::neccessarily::necessarily
::necesarily::necessarily
::nessasarily::necessarily
::neccesary::necessary
::neccessary::necessary
::necesary::necessary
::nessecary::necessary
::necessiate::necessitate
::neccessities::necessities
::ened::need
::neglible::negligible
::negligable::negligible
::negociable::negotiable
::negotiaing::negotiating
::negotation::negotiation
::neigbourhood::neighbourhood
::neolitic::neolithic
::nestin::nesting
::nver::never
::neverthless::nevertheless
::nwe::new
::newyorker::New Yorker
::foundland::Newfoundland
::newletters::newsletters
::enxt::next
::nickle::nickel
::neice::niece
::nightime::nighttime
::ninteenth::nineteenth
::ninties::nineties ; fixed from "1990s": could refer to temperatures too.
::ninty::ninety
::nineth::ninth
::noone::no one
::noncombatents::noncombatants
::nontheless::nonetheless
::unoperational::nonoperational
::nonsence::nonsense
::noth::north
::northereastern::northeastern
::norhern::northern
::northen::northern
::nothern::northern
:C:Nto::Not
:C:nto::not
::noteable::notable
::notabley::notably
::noteably::notably
::nothign::nothing
::notive::notice
::noticable::noticeable
::noticably::noticeably
::noticeing::noticing
::noteriety::notoriety
::notwhithstanding::notwithstanding
::noveau::nouveau
::nowe::now
::nwo::now
::nowdays::nowadays
::nucular::nuclear
::nuculear::nuclear
::nuisanse::nuisance
::nusance::nuisance
::nullabour::Nullarbor
::munbers::numbers
::numberous::numerous
::nuptual::nuptial
::nuremburg::Nuremberg
::nuturing::nurturing
::nutritent::nutrient
::nutritents::nutrients
::obediance::obedience
::obediant::obedient
::obssessed::obsessed
::obession::obsession
::obsolecence::obsolescence
::obstacal::obstacle
::obstancles::obstacles
::obstruced::obstructed
::ocassion::occasion
::occaison::occasion
::occassion::occasion
::ocassional::occasional
::occassional::occasional
::ocassionally::occasionally
::ocassionaly::occasionally
::occassionally::occasionally
::occassionaly::occasionally
::occationally::occasionally
::ocassioned::occasioned
::occassioned::occasioned
::ocassions::occasions
::occassions::occasions
::occour::occur
::occurr::occur
::ocur::occur
::ocurr::occur
::occured::occurred
::ocurred::occurred
::occurence::occurrence
::occurrance::occurrence
::ocurrance::occurrence
::ocurrence::occurrence
::occurences::occurrences
::occurrances::occurrences
::occuring::occurring
::octohedra::octahedra
::octohedral::octahedral
::octohedron::octahedron
::odouriferous::odoriferous
::odourous::odorous
::ouevre::oeuvre
::ofits::of its
::ofthe::of the
::oft he::of the ; Could be legitimate in poetry, but more usually a typo.
::offereings::offerings
::offcers::officers
::offical::official
::offcially::officially
::offically::officially
::officaly::officially
::officialy::officially
::oftenly::often
::omlette::omelette
::omnious::ominous
::omision::omission
::ommision::omission
::omited::omitted
::ommited::omitted
::ommitted::omitted
::omiting::omitting
::ommiting::omitting
::ommitting::omitting
::omniverous::omnivorous
::omniverously::omnivorously
::ont he::on the
::onthe::on the
::oneof::one of
::onepoint::one point
::onyl::only
::onomatopeia::onomatopoeia
::oppenly::openly
::openess::openness
::opperation::operation
::oeprator::operator
::opthalmic::ophthalmic
::opthalmologist::ophthalmologist
::opthamologist::ophthalmologist
::opthalmology::ophthalmology
::oppinion::opinion
::oponent::opponent
::opponant::opponent
::oppononent::opponent
::oppotunities::opportunities
::oportunity::opportunity
::oppertunity::opportunity
::oppotunity::opportunity
::opprotunity::opportunity
::opposible::opposable
::opose::oppose
::oppossed::opposed
::oposite::opposite
::oppasite::opposite
::opposate::opposite
::opposit::opposite
::oposition::opposition
::oppositition::opposition
::opression::oppression
::opressive::oppressive
::optomism::optimism
::optmizations::optimizations
::orded::ordered
::oridinarily::ordinarily
::orginize::organise
::organim::organism
::organiztion::organization
::orginization::organization
::orginized::organized
::orgin::origin
::orginal::original
::origional::original
::orginally::originally
::origanaly::originally
::originall::originally
::originaly::originally
::originially::originally
::originnally::originally
::orignally::originally
::orignially::originally
::orthagonal::orthogonal
::orthagonally::orthogonally
::ohter::other
::otehr::other
::otherw::others
::otu::out
::outof::out of
::overthe::over the
::overthere::over there
::overshaddowed::overshadowed
::overwelming::overwhelming
::overwheliming::overwhelming
::pwn::own
::oxident::oxidant
::oxigen::oxygen
::oximoron::oxymoron
::peageant::pageant
::paide::paid
::payed::paid
::paleolitic::paleolithic
::palistian::Palestinian
::palistinian::Palestinian
::palistinians::Palestinians
::pallete::palette
::pamflet::pamphlet
::pamplet::pamphlet
::pantomine::pantomime
::papanicalou::Papanicolaou
::papaer::paper
::perade::parade
::parrakeets::parakeets
::paralel::parallel
::paralell::parallel
::parralel::parallel
::parrallel::parallel
::parrallell::parallel
::paralelly::parallelly
::paralely::parallelly
::parallely::parallelly
::parrallelly::parallelly
::parrallely::parallelly
::parellels::parallels
::paraphenalia::paraphernalia
::paranthesis::parenthesis
::parliment::parliament
::paliamentarian::parliamentarian
::partof::part of
::partialy::partially
::parituclar::particular
::particualr::particular
::paticular::particular
::particuarly::particularly
::particularily::particularly
::particulary::particularly
::pary::party
::pased::passed
::pasengers::passengers
::passerbys::passersby
::pasttime::pastime
::pastural::pastoral
::pattented::patented
::paitience::patience
::pavillion::pavilion
::paymetn::payment
::paymetns::payments
::peacefuland::peaceful and
::peculure::peculiar
::pedestrain::pedestrian
::perjorative::pejorative
::peloponnes::Peloponnesus
::peleton::peloton
::penatly::penalty
::penerator::penetrator
::penisula::peninsula
::penninsula::peninsula
::pennisula::peninsula
::pensinula::peninsula
::penisular::peninsular
::penninsular::peninsular
::peolpe::people
::peopel::people
::poeple::people
::poeoples::peoples
::percieve::perceive
::percepted::perceived
::percieved::perceived
::percentof::percent of
::percentto::percent to
::precentage::percentage
::perenially::perennially
::performence::performance
::perfomers::performers
::performes::performs
::perhasp::perhaps
::perheaps::perhaps
::perhpas::perhaps
::perphas::perhaps
::preiod::period
::preriod::period
::peripathetic::peripatetic
::perjery::perjury
::permanant::permanent
::permenant::permanent
::perminent::permanent
::permenantly::permanently
::permissable::permissible
::premission::permission
::perpindicular::perpendicular
::perseverence::perseverance
::persistance::persistence
::peristent::persistent
::persistant::persistent
::peronal::personal
::perosnality::personality
::personalyl::personally
::personell::personnel
::personnell::personnel
::prespective::perspective
::pursuade::persuade
::persuded::persuaded
::pursuaded::persuaded
::pursuades::persuades
::pususading::persuading
::pertubation::perturbation
::pertubations::perturbations
::preverse::perverse
::pessiary::pessary
::petetion::petition
::pharoah::Pharaoh
::phenonmena::phenomena
::phenomenonal::phenomenal
::phenomenonly::phenomenally
::phenomenom::phenomenon
::phenomonenon::phenomenon
::phenomonon::phenomenon
::feromone::pheromone
::phillipine::Philippine
::philipines::Philippines
::phillipines::Philippines
::phillippines::Philippines
::philisopher::philosopher
::philospher::philosopher
::philisophical::philosophical
::phylosophical::philosophical
::phillosophically::philosophically
::philosphies::philosophies
::philisophy::philosophy
::philosphy::philosophy
::phonecian::Phoenecian
::pheonix::phoenix ; Not forcing caps, as it could be the bird
::fonetic::phonetic
::phongraph::phonograph
::physicaly::physically
::pciture::picture
::peice::piece
::peices::pieces
::pilgrimmage::pilgrimage
::pilgrimmages::pilgrimages
::pinapple::pineapple
::pinnaple::pineapple
::pinoneered::pioneered
::pich::pitch
::palce::place
::plagarism::plagiarism
::plantiff::plaintiff
::planed::planned
::planation::plantation
::plateu::plateau
::plausable::plausible
::playright::playwright
::playwrite::playwright
::playwrites::playwrights
::pleasent::pleasant
::plesant::pleasant
::plebicite::plebiscite
::peom::poem
::peoms::poems
::peotry::poetry
::poety::poetry
::poisin::poison
::posion::poison
::polical::political
::poltical::political
::politican::politician
::politicans::politicians
::polinator::pollinator
::polinators::pollinators
::polute::pollute
::poluted::polluted
::polutes::pollutes
::poluting::polluting
::polution::pollution
::polyphonyic::polyphonic
::polysaccaride::polysaccharide
::polysaccharid::polysaccharide
::pomegranite::pomegranate
::populare::popular
::popularaty::popularity
::popoulation::population
::poulations::populations
::portayed::portrayed
::potrayed::portrayed
::protrayed::portrayed
::portraing::portraying
::portugese::Portuguese
::portuguease::portuguese
::possition::position
::postion::position
::postition::position
::psoition::position
::postive::positive
::posess::possess
::posessed::possessed
::posesses::possesses
::posseses::possesses
::possessess::possesses
::posessing::possessing
::possesing::possessing
::posession::possession
::possesion::possession
::posessions::possessions
::possiblility::possibility
::possiblilty::possibility
::possable::possible
::possibile::possible
::possably::possibly
::posthomous::posthumous
::potatoe::potato
::potatos::potatoes
::potentialy::potentially
::postdam::Potsdam
::pwoer::power
::poverful::powerful
::poweful::powerful
::powerfull::powerful
::practial::practical
::practially::practically
::practicaly::practically
::practicly::practically
::pratice::practice
::practicioner::practitioner
::practioner::practitioner
::practicioners::practitioners
::practioners::practitioners
::prairy::prairie
::prarie::prairie
::praries::prairies
::pre-Colombian::pre-Columbian
::preample::preamble
::preceed::precede
::preceeded::preceded
::preceeds::precedes
::preceeding::preceding
::precice::precise
::precisly::precisely
::precurser::precursor
::precedessor::predecessor
::predecesors::predecessors
::predicatble::predictable
::predicitons::predictions
::predomiantly::predominately
::preminence::preeminence
::preferrably::preferably
::prefernece::preference
::preferneces::preferences
::prefered::preferred
::prefering::preferring
::pregancies::pregnancies
::pregnent::pregnant
::premeire::premiere
::premeired::premiered
::premillenial::premillennial
::premonasterians::Premonstratensians
::preocupation::preoccupation
::prepartion::preparation
::preperation::preparation
::preperations::preparations
::prepatory::preparatory
::prepair::prepare
::perogative::prerogative
::presance::presence
::presense::presence
::presedential::presidential
::presidenital::presidential
::presidental::presidential
::presitgious::prestigious
::prestigeous::prestigious
::prestigous::prestigious
::presumabely::presumably
::presumibly::presumably
::prevelant::prevalent
::previvous::previous
::priestood::priesthood
::primarly::primarily
::primative::primitive
::primatively::primitively
::primatives::primitives
::primordal::primordial
::pricipal::principal
::priciple::principle
::privte::private
::privelege::privilege
::privelige::privilege
::privilage::privilege
::priviledge::privilege
::privledge::privilege
::priveleged::privileged
::priveliged::privileged
::priveleges::privileges
::priveliges::privileges
::privelleges::privileges
::priviledges::privileges
::protem::pro tem
::probablistic::probabilistic
::probabilaty::probability
::probalibity::probability
::probablly::probably
::probaly::probably
::porblem::problem
::probelm::problem
::porblems::problems
::probelms::problems
::procedger::procedure
::proceedure::procedure
::procede::proceed
::proceded::proceeded
::proceding::proceeding
::procedings::proceedings
::procedes::proceeds
::proccess::process
::proces::process
::proccessing::processing
::processer::processor
::proclamed::proclaimed
::proclaming::proclaiming
::proclaimation::proclamation
::proclomation::proclamation
::proffesed::professed
::profesion::profession
::proffesion::profession
::proffesional::professional
::profesor::professor
::professer::professor
::proffesor::professor
::programable::programmable
::ptogress::progress
::progessed::progressed
::prohabition::prohibition
::prologomena::prolegomena
::preliferation::proliferation
::profilic::prolific
::prominance::prominence
::prominant::prominent
::prominantly::prominently
::promiscous::promiscuous
::promotted::promoted
::pomotion::promotion
::propmted::prompted
::pronomial::pronominal
::pronouced::pronounced
::pronounched::pronounced
::prouncements::pronouncements
::pronounciation::pronunciation
::propoganda::propaganda
::propogate::propagate
::propogates::propagates
::propogation::propagation
::propper::proper
::propperly::properly
::prophacy::prophecy
::poportional::proportional
::propotions::proportions
::propostion::proposition
::propietary::proprietary
::proprietory::proprietary
::proseletyzing::proselytizing
::protaganist::protagonist
::protoganist::protagonist
::protaganists::protagonists
::pretection::protection
::protien::protein
::protocal::protocol
::protruberance::protuberance
::protruberances::protuberances
::proove::prove
::prooved::proved
::porvide::provide
::provded::provided
::provicial::provincial
::provinicial::provincial
::provisonal::provisional
::provacative::provocative
::proximty::proximity
::psuedo::pseudo
::pseudonyn::pseudonym
::pseudononymous::pseudonymous
::psyhic::psychic
::pyscic::psychic
::psycology::psychology
::publically::publicly
::publicaly::publicly
::pucini::Puccini
::puertorrican::Puerto Rican
::puertorricans::Puerto Ricans
::pumkin::pumpkin
::puchasing::purchasing
::puritannical::puritanical
::purpotedly::purportedly
::purposedly::purposely
::persue::pursue
::persued::pursued
::persuing::pursuing
::persuit::pursuit
::persuits::pursuits
::puting::putting
::quantaty::quantity
::quantitiy::quantity
::quarantaine::quarantine
::quater::quarter
::quaters::quarters
::quesion::question
::questoin::question
::quetion::question
::questonable::questionable
::questionnair::questionnaire
::quesions::questions
::questioms::questions
::questiosn::questions
::quetions::questions
::quicklyu::quickly
::quinessential::quintessential
::quitted::quit
::quizes::quizzes
::rabinnical::rabbinical
::radiactive::radioactive
::rancourous::rancorous
::repid::rapid
::rarified::rarefied
::rasberry::raspberry
::ratehr::rather
::radify::ratify
::racaus::raucous
::reched::reached
::reacing::reaching
::readmition::readmission
::rela::real
::relized::realised
::realsitic::realistic
::erally::really
::raelly::really
::realy::really
::realyl::really
::relaly::really
::rebllions::rebellions
::rebounce::rebound
::rebiulding::rebuilding
::reacll::recall
::receeded::receded
::receeding::receding
::receieve::receive
::receivedfrom::received from
::receving::receiving
::rechargable::rechargeable
::recipiant::recipient
::reciepents::recipients
::recipiants::recipients
::recogise::recognise
::recogize::recognize
::reconize::recognize
::reconized::recognized
::reccommend::recommend
::recomend::recommend
::reommend::recommend
::recomendation::recommendation
::recomendations::recommendations
::recommedations::recommendations
::reccommended::recommended
::recomended::recommended
::reccommending::recommending
::recomending::recommending
::recomends::recommends
::reconcilation::reconciliation
::reconaissance::reconnaissance
::reconnaissence::reconnaissance
::recontructed::reconstructed
::recrod::record
::rocord::record
::recordproducer::record producer
::recrational::recreational
::recuiting::recruiting
::rucuperate::recuperate
::recurrance::recurrence
::reoccurrence::recurrence
::reaccurring::recurring
::reccuring::recurring
::recuring::recurring
::recyling::recycling
::reedeming::redeeming
::relected::reelected
::revaluated::reevaluated
::referrence::reference
::refference::reference
::refrence::reference
::refernces::references
::refrences::references
::refedendum::referendum
::referal::referral
::refered::referred
::reffered::referred
::referiang::referring
::refering::referring
::referrs::refers
::refrers::refers
::refect::reflect
::refromist::reformist
::refridgeration::refrigeration
::refridgerator::refrigerator
::refusla::refusal
::irregardless::regardless
::regardes::regards
::regluar::regular
::reguarly::regularly
::regularily::regularly
::regulaion::regulation
::regulaotrs::regulators
::rehersal::rehearsal
::reigining::reigning
::reicarnation::reincarnation
::reenforced::reinforced
::realtions::relations
::relatiopnship::relationship
::realitvely::relatively
::relativly::relatively
::relitavely::relatively
::releses::releases
::relevence::relevance
::relevent::relevant
::relient::reliant
::releive::relieve
::releived::relieved
::releiver::reliever
::religeous::religious
::religous::religious
::religously::religiously
::relinqushment::relinquishment
::reluctent::reluctant
::remaing::remaining
::remeber::remember
::rememberance::remembrance
::remembrence::remembrance
::remenicent::reminiscent
::reminescent::reminiscent
::reminscent::reminiscent
::reminsicent::reminiscent
::remenant::remnant
::reminent::remnant
::renedered::rende
::rendevous::rendezvous
::rendezous::rendezvous
::renewl::renewal
::reknown::renown
::reknowned::renowned
::rentors::renters
::reorganision::reorganisation
::repeteadly::repeatedly
::repentence::repentance
::repentent::repentant
::reprtoire::repertoire
::repetion::repetition
::reptition::repetition
::relpacement::replacement
::reportadly::reportedly
::represnt::represent
::represantative::representative
::representive::representative
::representativs::representatives
::representives::representatives
::represetned::represented
::reproducable::reproducible
::requred::required
::reasearch::research
::reserach::research
::resembelance::resemblance
::resemblence::resemblance
::ressemblance::resemblance
::ressemblence::resemblance
::ressemble::resemble
::ressembled::resembled
::resembes::resembles
::ressembling::resembling
::resevoir::reservoir
::recide::reside
::recided::resided
::recident::resident
::recidents::residents
::reciding::residing
::resignement::resignment
::resistence::resistance
::resistent::resistant
::resistable::resistible
::resollution::resolution
::resorces::resources
::repsectively::respectively
::respectivly::respectively
::respomse::response
::responce::response
::responibilities::responsibilities
::responsability::responsibility
::responisble::responsible
::responsable::responsible
::responsibile::responsible
::resaurant::restaurant
::restaraunt::restaurant
::restauraunt::restaurant
::resteraunt::restaurant
::restuarant::restaurant
::resturant::restaurant
::resturaunt::restaurant
::restaraunts::restaurants
::resteraunts::restaurants
::restaraunteur::restaurateur
::restaraunteurs::restaurateurs
::restauranteurs::restaurateurs
::restauration::restoration
::resticted::restricted
::reult::result
::resurgance::resurgence
::resssurecting::resurrecting
::resurecting::resurrecting
::ressurrection::resurrection
::retalitated::retaliated
::retalitation::retaliation
::retreive::retrieve
::returnd::returned
::reveral::reversal
::reversable::reversible
::reveiw::review
::reveiwing::reviewing
::revolutionar::revolutionary
::rewriet::rewrite
::rewitten::rewritten
::rhymme::rhyme
::rhythem::rhythm
::rhythim::rhythm
::rythem::rhythm
::rythim::rhythm
::rythm::rhythm
::rhytmic::rhythmic
::rythmic::rhythmic
::rythyms::rhythms
::rediculous::ridiculous
::rigourous::rigorous
::rigeur::rigueur
::rininging::ringing
::rockerfeller::Rockefeller
::rococco::rococo
::roomate::roommate
::rised::rose
::rougly::roughly
::rudimentatry::rudimentary
::rulle::rule
::rumers::rumors
::runing::running
::runnung::running
::russina::Russian
::russion::Russian
::sacrafice::sacrifice
::sacrifical::sacrificial
::sacreligious::sacrilegious
::sandess::sadness
::saftey::safety
::safty::safety
::saidhe::said he
::saidit::said it
::saidthat::said that
::saidt he::said the
::saidthe::said the
::salery::salary
::smae::same
::santioned::sanctioned
::sanctionning::sanctioning
::sandwhich::sandwich
::sanhedrim::Sanhedrin
::satelite::satellite
::sattelite::satellite
::satelites::satellites
::sattelites::satellites
::satric::satiric
::satrical::satirical
::satrically::satirically
::satisfactority::satisfactorily
::saterday::Saturday
::saterdays::Saturdays
::svae::save
::svaes::saves
::saxaphone::saxophone
::sasy::says
::syas::says
::scaleable::scalable
::scandanavia::Scandinavia
::scaricity::scarcity
::scavanged::scavenged
::senarios::scenarios
::scedule::schedule
::schedual::schedule
::sceduled::scheduled
::scholarhip::scholarship
::scholarstic::scholastic
::shcool::school
::scince::science
::scinece::science
::scientfic::scientific
::scientifc::scientific
::screenwrighter::screenwriter
::scirpt::script
::scoll::scroll
::scrutinity::scrutiny
::scuptures::sculptures
::seach::search
::seached::searched
::seaches::searches
::secratary::secretary
::secretery::secretary
::sectino::section
::seing::seeing
::segementation::segmentation
::seguoys::segues
::sieze::seize
::siezed::seized
::siezing::seizing
::siezure::seizure
::siezures::seizures
::seldomly::seldom
::selectoin::selection
::seinor::senior
::sence::sense
::senstive::sensitive
::sentance::sentence
::separeate::separate
::sepulchure::sepulchre
::sargant::sergeant
::sargeant::sergeant
::sergent::sergeant
::settelement::settlement
::settlment::settlement
::severeal::several
::severley::severely
::severly::severely
::shaddow::shadow
::seh::she
::shesaid::she said
::sherif::sheriff
::sheild::shield
::shineing::shining
::shiped::shipped
::shiping::shipping
::shopkeeepers::shopkeepers
::shortwhile::short while
::shorly::shortly
::shoudl::should
::Shoudl::Should
::should of::should have
::sohw::show
::showinf::showing
::shreak::shriek
::shrinked::shrunk
::sedereal::sidereal
::sideral::sidereal
::seige::siege
::signitories::signatories
::signitory::signatory
::siginificant::significant
::signficant::significant
::signficiant::significant
::signifacnt::significant
::signifigant::significant
::signifantly::significantly
::significently::significantly
::signifigantly::significantly
::signfies::signifies
::silicone chip::silicon chip
::simalar::similar
::similiar::similar
::simmilar::similar
::similiarity::similarity
::similarily::similarly
::similiarly::similarly
::simplier::simpler
::simpley::simply
::simpyl::simply
::simultanous::simultaneous
::simultanously::simultaneously
::sicne::since
::sincerley::sincerely
::sincerly::sincerely
::singsog::singsong
::sixtin::Sistine
::skagerak::Skagerrak
::skateing::skating
::slaugterhouses::slaughterhouses
::slowy::slowly
::smoothe::smooth
::smoothes::smooths
::sneeks::sneaks
::snese::sneeze
::sot hat::so that
::soical::social
::socalism::socialism
::socities::societies
::sofware::software
::soilders::soldiers
::soliders::soldiers
::soley::solely
::soliliquy::soliloquy
::solatary::solitary
::soluable::soluble
::soem::some
::somene::someone
::somethign::something
::someting::something
::somthing::something
::somtimes::sometimes
::somewaht::somewhat
::somwhere::somewhere
::sophicated::sophisticated
::suphisticated::sophisticated
::sophmore::sophomore
::sorceror::sorcerer
::saught::sought
::seeked::sought
::soudn::sound
::soudns::sounds
::sountrack::soundtrack
::suop::soup
::sourth::south
::sourthern::southern
::souvenier::souvenir
::souveniers::souvenirs
::soverign::sovereign
::sovereignity::sovereignty
::soverignity::sovereignty
::soverignty::sovereignty
::soveits::soviets
::soveits::soviets(x
::spoace::space
::spainish::Spanish
::speciallized::specialised
::speices::species
::specfic::specific
::specificaly::specifically
::specificalyl::specifically
::specifiying::specifying
::speciman::specimen
::spectauclar::spectacular
::spectaulars::spectaculars
::spectum::spectrum
::speach::speech
::sprech::speech
::sppeches::speeches
::spermatozoan::spermatozoon
::spriritual::spiritual
::spritual::spiritual
::spendour::splendour
::sponser::sponsor
::sponsered::sponsored
::sponzored::sponsored
::spontanous::spontaneous
::spoonfulls::spoonfuls
::sportscar::sports car
::spreaded::spread
::spred::spread
::sqaure::square
::stablility::stability
::stainlees::stainless
::stnad::stand
::standars::standards
::strat::start
::statment::statement
::statememts::statements
::statments::statements
::stateman::statesman
::staion::station
::sterotypes::stereotypes
::steriods::steroids
::sitll::still
::stiring::stirring
::stirrs::stirs
::stpo::stop
::storeis::stories
::storise::stories
::sotry::story
::stopry::story
::stoyr::story
::stroy::story
::strnad::strand
::stange::strange
::startegic::strategic
::stratagically::strategically
::startegies::strategies
::stradegies::strategies
::startegy::strategy
::stradegy::strategy
::streemlining::streamlining
::stregth::strength
::strenght::strength
::strentgh::strength
::strenghen::strengthen
::strenghten::strengthen
::strenghened::strengthened
::strenghtened::strengthened
::strengtened::strengthened
::strenghening::strengthening
::strenghtening::strengthening
::strenous::strenuous
::strictist::strictest
::strikely::strikingly
::stingent::stringent
::stong::strong
::stornegst::strongest
::stucture::structure
::sturcture::structure
::stuctured::structured
::struggel::struggle
::strugle::struggle
::stuggling::struggling
::stubborness::stubbornness
::studnet::student
::studdy::study
::studing::studying
::stlye::style
::sytle::style
::stilus::stylus
::subconsiously::subconsciously
::subjudgation::subjugation
::submachne::submachine
::sepina::subpoena
::subsquent::subsequent
::subsquently::subsequently
::subsidary::subsidiary
::subsiduary::subsidiary
::subpecies::subspecies
::substace::substance
::subtances::substances
::substancial::substantial
::substatial::substantial
::substituded::substituted
::subterranian::subterranean
::substract::subtract
::substracted::subtracted
::substracting::subtracting
::substraction::subtraction
::substracts::subtracts
::suburburban::suburban
::suceed::succeed
::succceeded::succeeded
::succedded::succeeded
::succeded::succeeded
::suceeded::succeeded
::suceeding::succeeding
::succeds::succeeds
::suceeds::succeeds
::succsess::success
::sucess::success
::succcesses::successes
::sucesses::successes
::succesion::succession
::sucesion::succession
::sucession::succession
::succesive::successive
::sucessive::successive
::sucessor::successor
::sucessot::successor
::sufferred::suffered
::sufferring::suffering
::suffcient::sufficient
::sufficent::sufficient
::sufficiant::sufficient
::suffciently::sufficiently
::sufficently::sufficiently
::sufferage::suffrage
::suggestable::suggestible
::sucidial::suicidal
::sucide::suicide
::sumary::summary
::sunglases::sunglasses
::superintendant::superintendent
::surplanted::supplanted
::suplimented::supplemented
::supplamented::supplemented
::suppliementing::supplementing
::suppy::supply
::wupport::support
::supose::suppose
::suposed::supposed
::suppoed::supposed
::suppossed::supposed
::suposedly::supposedly
::supposingly::supposedly
::suposes::supposes
::suposing::supposing
::supress::suppress
::surpress::suppress
::supressed::suppressed
::surpressed::suppressed
::supresses::suppresses
::supressing::suppressing
::surley::surely
::surfce::surface
::suprise::surprise
::suprize::surprise
::surprize::surprise
::suprised::surprised
::suprized::surprised
::surprized::surprised
::suprising::surprising
::suprizing::surprising
::surprizing::surprising
::suprisingly::surprisingly
::suprizingly::surprisingly
::surprizingly::surprisingly
::surrended::surrendered
::surrundering::surrendering
::surrepetitious::surreptitious
::surreptious::surreptitious
::surrepetitiously::surreptitiously
::surreptiously::surreptitiously
::suround::surround
::surounded::surrounded
::surronded::surrounded
::surrouded::surrounded
::sorrounding::surrounding
::surounding::surrounding
::surrouding::surrounding
::suroundings::surroundings
::surounds::surrounds
::surveill::surveil
::surveilence::surveillance
::surveyer::surveyor
::survivied::survived
::surviver::survivor
::survivers::survivors
::suseptable::susceptible
::suseptible::susceptible
::suspention::suspension
::swaer::swear
::swaers::swears
::swepth::swept
::swiming::swimming
::symettric::symmetric
::symmetral::symmetric
::symetrical::symmetrical
::symetrically::symmetrically
::symmetricaly::symmetrically
::symetry::symmetry
::synphony::symphony
::sypmtoms::symptoms
::synagouge::synagogue
::syncronization::synchronization
::synonomous::synonymous
::synonymns::synonyms
::syphyllis::syphilis
::syrap::syrup
::sytem::system
::sysmatically::systematically
::tkae::take
::tkaes::takes
::tkaing::taking
::talekd::talked
::talkign::talking
::tlaking::talking
::targetted::targeted
::targetting::targeting
::tast::taste
::tatoo::tattoo
::tattooes::tattoos
::teached::taught
::taxanomic::taxonomic
::taxanomy::taxonomy
::tecnical::technical
::techician::technician
::technitian::technician
::techicians::technicians
::techiniques::techniques
::technnology::technology
::technolgy::technology
::telphony::telephony
::televize::televise
::telelevision::television
::televsion::television
::tellt he::tell the
::temperment::temperament
::tempermental::temperamental
::temparate::temperate
::temerature::temperature
::tempertaure::temperature
::temperture::temperature
::temperarily::temporarily
::tepmorarily::temporarily
::temprary::temporary
::tendancies::tendencies
::tendacy::tendency
::tendancy::tendency
::tendonitis::tendinitis
::tennisplayer::tennis player
::tenacle::tentacle
::tenacles::tentacles
::terrestial::terrestrial
::terriories::territories
::terriory::territory
::territoy::territory
::territorist::terrorist
::terroist::terrorist
::testiclular::testicular
::tahn::than
::thna::than
::thansk::thanks
::taht::that
::tath::that
::thgat::that
::thta::that
::thyat::that
::tyhat::that
::thatt he::that the
::thatthe::that the
::hte::the
::teh::the
::tehw::the
::tghe::the
::theh::the
::thge::the
::thw::the
::tje::the
::tjhe::the
::tthe::the
::tyhe::the
::thecompany::the company
::thefirst::the first
::thegovernment::the government
::thenew::the new
::thesame::the same
::thetwo::the two
::theather::theatre
::theri::their
::thier::their
::there's is::theirs is
::htem::them
::themself::themselves
::themselfs::themselves
::themslves::themselves
::hten::then
::thn::then
::thne::then
::htere::there
::their are::there are
::they're are::there are
::their is::there is
::they're is::there is
::therafter::thereafter
::therby::thereby
::htese::these
::theese::these
::htey::they
::tehy::they
::tyhe::they
::theif::thief
::theives::thieves
::hting::thing
::thign::thing
::thnig::thing
::thigns::things
::thigsn::things
::thnigs::things
::htikn::think
::htink::think
::thikn::think
::thiunk::think
::tihkn::think
::thikning::thinking
::thikns::thinks
::thrid::third
::htis::this
::tghis::this
::thsi::this
::tihs::this
::thisyear::this year
::throrough::thorough
::throughly::thoroughly
::thsoe::those
::threatend::threatened
::threatning::threatening
::threee::three
::threshhold::threshold
::throuhg::through
::thoughout::throughout
::througout::throughout
::tiget::tiger
::tiem::time
::timne::time
::tot he::to the
::tothe::to the
::tabacco::tobacco
::tobbaco::tobacco
::todya::today
::tiogether::together
::togehter::together
::toghether::together
::toldt he::told the
::tolerence::tolerance
::tolkein::Tolkien
::tomatos::tomatoes
::tommorow::tomorrow
::tommorrow::tomorrow
::tomorow::tomorrow
::tounge::tongue
::tongiht::tonight
::tonihgt::tonight
::tormenters::tormentors
::toriodal::toroidal
::torpeados::torpedoes
::torpedos::torpedoes
::totaly::totally
::totalyl::totally
::towrad::toward
::towords::towards
::twon::town
::traditition::tradition
::traditionnal::traditional
::tradionally::traditionally
::traditionaly::traditionally
::traditionalyl::traditionally
::tradtionally::traditionally
::trafic::traffic
::trafficed::trafficked
::trafficing::trafficking
::transcendance::transcendence
::trancendent::transcendent
::transcendant::transcendent
::transcendentational::transcendental
::trancending::transcending
::transending::transcending
::transcripting::transcribing
::transfered::transferred
::transfering::transferring
::tranform::transform
::transformaton::transformation
::tranformed::transformed
::transistion::transition
::translater::translator
::translaters::translators
::transmissable::transmissible
::transporation::transportation
::transesxuals::transsexuals
::tremelo::tremolo
::tremelos::tremolos
::triathalon::triathlon
::tryed::tried
::triguered::triggered
::triology::trilogy
::troling::trolling
::toubles::troubles
::troup::troupe
::truely::truly
::truley::truly
::turnk::trunk
::tust::trust
::trustworthyness::trustworthiness
::tuscon::Tucson
::termoil::turmoil
::twpo::two
::typcial::typical
::typicaly::typically
::tyranies::tyrannies
::tyrranies::tyrannies
::tyrany::tyranny
::tyrrany::tyranny
::tyranical::tyrannical
::ubiquitious::ubiquitous
::ukranian::Ukrainian
::ukelele::ukulele
::alterior::ulterior
::ultimely::ultimately
::unacompanied::unaccompanied
::unanymous::unanimous
::unathorised::unauthorised
::unavailible::unavailable
::unballance::unbalance
::unbeleivable::unbelievable
::uncertainity::uncertainty
::unchallengable::unchallengeable
::unchangable::unchangeable
::uncompetive::uncompetitive
::unconcious::unconscious
::unconciousness::unconsciousness
::uncontitutional::unconstitutional
::unconvential::unconventional
::undecideable::undecidable
::indefineable::undefinable
::undert he::under the
::undreground::underground
::udnerstand::understand
::understnad::understand
::understoon::understood
::undesireable::undesirable
::undetecable::undetectable
::undoubtely::undoubtedly
::unforgetable::unforgettable
::unforgiveable::unforgivable
::unforetunately::unfortunately
::unfortunatley::unfortunately
::unfortunatly::unfortunately
::unfourtunately::unfortunately
::unahppy::unhappy
::unilatreal::unilateral
::unilateraly::unilaterally
::unilatreally::unilaterally
::unihabited::uninhabited
::uninterruped::uninterrupted
::uninterupted::uninterrupted
::unitedstates::United States
::unitesstates::United States
::univeral::universal
::univeristies::universities
::univesities::universities
::univeristy::university
::universtiy::university
::univesity::university
::unviersity::university
::unkown::unknown
::unliek::unlike
::unlikey::unlikely
::unmanouverable::unmanoeuvrable
::unmistakeably::unmistakably
::unneccesarily::unnecessarily
::unneccessarily::unnecessarily
::unnecesarily::unnecessarily
::uneccesary::unnecessary
::unecessary::unnecessary
::unneccesary::unnecessary
::unneccessary::unnecessary
::unnecesary::unnecessary
::unoticeable::unnoticeable
::inofficial::unofficial
::unoffical::unofficial
::unplesant::unpleasant
::unpleasently::unpleasantly
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
::unsuprized::unsurprised
::unsurprized::unsurprised
::unsuprising::unsurprising
::unsuprizing::unsurprising
::unsurprizing::unsurprising
::unsuprisingly::unsurprisingly
::unsuprizingly::unsurprisingly
::unsurprizingly::unsurprisingly
::untill::until
::untranslateable::untranslatable
::unuseable::unusable
::unusuable::unusable
::unwarrented::unwarranted
::unweildly::unwieldy
::unwieldly::unwieldy
::tjpanishad::upanishad
::upcomming::upcoming
::upgradded::upgraded
::useage::usage
::uise::use
::usefull::useful
::usefuly::usefully
::usiing::using
::useing::using
::usally::usually
::usualy::usually
::usualyl::usually
::ususally::usually
::vaccum::vacuum
::vaccume::vacuum
::vaguaries::vagaries
::vailidty::validity
::valetta::valletta
::valuble::valuable
::valueable::valuable
::varient::variant
::varients::variants
::varations::variations
::vaieties::varieties
::varities::varieties
::variey::variety
::varity::variety
::vreity::variety
::vriety::variety
::varous::various
::varing::varying
::vasall::vassal
::vasalls::vassals
::vegitable::vegetable
::vegtable::vegetable
::vegitables::vegetables
::vegatarian::vegetarian
::vehicule::vehicle
::vengance::vengeance
::vengence::vengeance
::venemous::venomous
::verfication::verification
::vermillion::vermilion
::versitilaty::versatility
::versitlity::versatility
::verison::version
::verisons::versions
::veyr::very
::vrey::very
::vyer::very
::vyre::very
::vacinity::vicinity
::vincinity::vicinity
::vitories::victories
::wiew::view
::vigilence::vigilance
::vigourous::vigorous
::villification::vilification
::villify::vilify
::villian::villain
::violentce::violence
::virgina::Virginia
::virutal::virtual
::virtualyl::virtually
::visable::visible
::visably::visibly
::visting::visiting
::vistors::visitors
::volcanoe::volcano
::volkswagon::Volkswagen
::voleyball::volleyball
::volontary::voluntary
::volonteer::volunteer
::volounteer::volunteer
::volonteered::volunteered
::volounteered::volunteered
::volonteering::volunteering
::volounteering::volunteering
::volonteers::volunteers
::volounteers::volunteers
::vulnerablility::vulnerability
::vulnerible::vulnerable
::watn::want
::whant::want
::wnat::want
::wan tit::want it
::wnated::wanted
::whants::wants
::wnats::wants
::wardobe::wardrobe
::warrent::warrant
::warantee::warranty
::warrriors::warriors
::wass::was
::weas::was
::ws::was
::wa snot::was not
::wya::way
::wayword::wayward
::weaponary::weaponry
::wether::weather
::wendsay::Wednesday
::wensday::Wednesday
::wiegh::weigh
::wierd::weird
::vell::well
::werre::were
::waht::what
::whta::what
::wehn::when
::whn::when
::whent he::when the
::wehre::where
::wherre::where
::wereabouts::whereabouts
::wheras::whereas
::wherease::whereas
::whereever::wherever
::whther::whether
::hwich::which
::hwihc::which
::whcih::which
::whic::which
::whihc::which
::whlch::which
::wihch::which
::whicht he::which the
::hwile::while
::woh::who
::hwole::whole
::wohle::whole
::wholey::wholly
::widesread::widespread
::weilded::wielded
::wief::wife
::iwll::will
::wille::will
::wiull::will
::willbe::will be
::willingless::willingness
::windoes::windows
::wintery::wintry
::iwth::with
::whith::with
::wih::with
::wiht::with
::withe::with
::witht::with
::witn::with
::wtih::with
::witha::with a
::witht he::with the
::withthe::with the
::withdrawl::withdrawal
::witheld::withheld
::withold::withhold
::withing::within
::wonderfull::wonderful
::wrod::word
::owrk::work
::wokr::work
::wrok::work
::wokring::working
::wroking::working
::workststion::workstation
::worls::world
::worstened::worsened
::owudl::would
::wuould::would
::wouldbe::would be
::would of::would have
::wresters::wrestlers
::rwite::write
::wriet::write
::wirting::writing
::writting::writing
::writen::written
::wroet::wrote
::x-Box::Xbox
::xenophoby::xenophobia
::yatch::yacht
::yaching::yachting
::eyar::year
::yera::year
::eyars::years
::yeasr::years
::yeras::years
::yersa::years
::yelow::yellow
::eyt::yet
::yeild::yield
::yeilding::yielding
::yoiu::you
::ytou::you
::yuo::you
::youare::you are
::yoru::your
::yuor::your
::youself::yourself
::youseff::yousef
::zeebra::zebra
::sionist::Zionist
::sionists::Zionists

;-------------------------------------------------------------------------------
;  Capitalise dates
;-------------------------------------------------------------------------------
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
;-------------------------------------------------------------------------------
; Anything below this point was added to the script by the user via the Win+H hotkey.
;-------------------------------------------------------------------------------
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
::defualt::default
::rescheulde::reschedule
::mintues::minutes
::machien::machine
::awhiel::awhile
::emial::email
::btter::better
::apprecaite::appreciate
::funciton::function
::srory::sorry
::probalby::probably
::locaation::location
::locaiton::location
::exausted::exhausted
::soem::some
::soemthing::something
::excatly::exactly
::someoen::someone
::determing::determining
::questios::questions
::offerred::offered
::picturs::pictures
::poitn::point
::opint::point
::confsued::confused
::documention::documentation
::cehck::check
::instaed::instead
::confrim::confirm
::ar eyou::are you
::quesiton::question
::advatnage::advantage
::al lthe::all the
::interestin::interest in
::inteeresting::interesting
::implmenetation::implementation
::kown::known
::incompatibiility::incompatibility
::unlcok::unlock
::oyu::you
::yaer::year
::descriptoins::descriptions
::amn::man
::fro::for
::intesreting::interesting
::releated::related
::resset::reset
::machiens::machines
::cuold::could
::confusgin::confusing
::repot::report
::licesne::license
::pilling::piling
::resovle::resolve
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
::thnaks::thanks
::hoep::hope
::presentatino::presentation
::specificed::specified
::dya::day
::docn::documentation
::docs::documents
::doc::document
::votlages::voltages
::deisgn::desIgn
::can not::cannot
::throough::thorough
::si::is
::ompany::company
::ackolwedgement::acknowledgement
::signle::single
::familir::familiar
::tahnks::thanks
::questionaire::questionnaire
::ppl::people
::serach::search
::aroudn::around
::a the::at the
::ist he::is the
::htan::than
::hwoever::however
::Hoewver::However
::insant::instant
::dsp::DSP
::taek::take
::thye::they
::dicussions::discussions
::Techncially::Technically
::tehcncailly::technically
::spreadhsset::spreadsheet
::confirmmed::confirmed
::implmeneted::implemented
::advantges::advantages
::Unforntuately::Unfortunately
::pelase::please
::spreadhseet::spreadsheet
::lsot::lost
::soruce::source
::limitaitons::limitatIons
::asnwer::answer
::nad::and
::trasnceivers::transceivers
::utliamtely::ultimately
::conerns::concerns
::implmenet::implement
::coupel::couple
::Unfortuantley::Unfortunatley
::alogn::along
::thakns::thanks
::respresnted::represented
::challenege::challenge
::appercaite::appreciate
::forsee::foresee
::wsa::was
::jtag::JTAG
::avstx8::AvSTx8
::avstx32::AvSTx32
::pu::up
::opencl::OpenCL
::schedeuled::scheduled
::jesd::JESD
::orf::for
::maek::make
::literaly::literally
::sampel::sample
::seqeuencing::sequencing
::abuot::aboyout
::srue::sure
::intpretation::intepretation
::haering::hearing
::docuemnts::documents
::developemtn::development
::palcement::placement
::pruposes::purposes
::gogin::going
::hweover::however
::juts::just
::curiosu::curious
::simualte::simulate
::deos::does
::ot::to
::salve::slave
::hcange::change
::wuold::woyould
::hcip::chip
::hsoudl::should
::stnadard::standard
::emif::EMIF
::tahnk::thank
::evne::even
::seomthing::soemthing
::pusle::pulse
::bets::best
::fpgas::FPGAs
::opinon::opinIon
::webex::WebEx
::soluations::solutions
::aprt::part
::belwo::below
::hleping::helping
::filse::files
::appreacited::appreciated
::simluations::simulations
::Unfortuatnely::Unfortunately
::cuase::cause
::ahd::had
::pelsae::please
::ilcense::license
::xcvr::XCVR
::xcvrs::XCVRs
::absoutely::absolutely
::shoudl::should
::mhz::Mhz
::quartus::Quartus
::cuodl::could
::dma::DMA
::moer::more
::thoguhts::thoughts
::htme::them
::ehlp::help
::pathc::patch
::awlays::always
::Soc::SoC
::seotmhing::something
::usb::USB
::herad::heard
::awalys::always
::mdoel::model
::repsonses::responses
::diong::doing
::makgni::making
::simplist::simplest
::defintinon::definition
::contniue::continue
::resepct::respect
::fof::for
::ta::at
::quetsions::questions
::oslution::solution
::determininstic::deterministic
::Hye::Hey
::lokoing::looking
::bene::been
::roled::rolled
::noe::one
::ilke::like
::oru::our
::selectino::selection
::meteing::meeting
::quetsion::question
::loking::looking
::isseus::issues
::th e::the
::ucstomers::customers
::ilnks::links
::brining::bringing
::saerch::search
::blieve::believe
::copule::couple
::migth::might
::instructino::instruction
::hlepful::helpful
::qusetions::questions
::drvier::driver
::compelx::complex
::syaing::saying
::logn::long
::anaylsis::analysis
::npoe::nope
::naswers::answers
::ahs::has
::hpoefully::hopefully
::apprecaited::appreciated
::speicifc::specifIc
::tho::though
::prolbem::problem
::haerd::heard
::Godo::Good
::resopnses::responses
::reposne::response
::tgoether::together
::instatiating::instantiating
::gbe::GbE
::Unforutntely::Unfortunately
::resopnd::respond
::Ocne::Once
::Welcoem::Welcome
::osemthing::something
::Stya::Stay
::documetnation::documentation
::udnersatnding::understanding
::transceviers::transceivers
::doucment::document
::shceudled::scheduled
::comopnents::components
::applicatoins::applications
::scheem::scheme
::doucmentaotin::documentation
::diffuclty::difficulty
::Vinec::Vince
::hwat::what
::asap::ASAP
::compliation::compilation
::ntoes::notes
::direcotires::directorIes
::sinec::since
::opporutnities::opportunities
::partioin::partition
::oen::one
::resopnse::response
::compelte::complete
::Quratus::Quartus
::hcnage::change
::opinons::opinIons
::Unforutnately::Unfortunately
::Unforutnatley::Unfortunately
::converstion::conversation
::plyaing::playing
::shcematic::schematic
::itme::time
::ocnversations::conversations
::receivesr::receivers
::shcematics::schematics
::hwy::why
::adddressing::addressing
::disucsison::discussion
::Produciton::ProductIon
::doucments::documents
::exampel::example
::adivsigin::advising
::opporotunity::opportunity
::cocks::clocks
::unknonw::unknown
::tlak::talk
::lien::line
::piont::poInt
::deisng::design
::hps::HPS
::whoel::whole
::cusomter::customer
::asnwers::answers
::conecnered::concerned
::iopll::IOPLL
::Suggesitons::SuggestIons
::Vicne::Vince
::shceduled::scheduled
::quesiton::question
::quesitons::questions
::pgorammer::programmer
::clsoe::close
::Antony::Anthony
::intenral::internal
::knowledgable::knowledgeable
::implciations::implications
::bleieve::believe
::begininning::beginning
::mabye::maybe
::moduel::module
::apges::pages
::sesen::sense
::curiousity::curiosity
::concnered::concerned
::calcualtions::calculations
::discoved::discovered
::possiblites::possibIlites
::coutner::counter
::udpates::updates
::prupose::purpose
::adantages::advantages
::disadvantes::disadvantages
::asme::same
::geos::goes
::watned::wanted
::ugess::guess
::multipel::multiple
::problsme::problems
::thershold::threshold
::componets::components
::axi::AXI
::compnay::company
::evertyhing::everything
::hcnaged::changed
::consdiering::considering
::windriver::Wind River
::WindRiver::Wind River
::persepctive::perspective
::architecutre::architecture
::plesae::please
::levaing::leaving
::leaveing::leaving
::giong::going
::benfits::benefits
::hwen::when
::licnese::license
::mpsoc::MPSoC
::compoents::components
::ubt::but
::artitechture::architecture
::environemental::environemental
::eman::mean
::omve::move
::sepc::spec
::referneced::referenced
::vxworks::VxWorks
::interpretting::interpreting
::characterstics::characteristics
::accomodate::accommodate
::techinques::techniques
::instnace::instance
::undersatnd::understand
::plesae::please
::feb::Feb
::actaully::actually
::Porbably::Probably
::unfotunately::unfortunately
::defitintion::definition
::pusle::pulse
::reporsitory::repository
::expesnive::expensive
::informatin::information
::questino::question
::tomororw::tomorrow
::apparoch::appraoch
::depednencey::dependencey
::direcotry::directory
::minimim::minimum
::fukcing::fucking
::baot::boat
::oover::over
::ecrypted::encrypted
::suhc::such
::NTO::NOT
::canabalize::cannibalize
::versinos::versions
::xilinx::Xilinx
::ocmmands::commands
::acutally::actually
::asusming::assuming
::osme::some
::sepcfiication::specification
::Unfrotuantely::Unfortunately
::alst::last
::thuoght::thought
::cmoe::come
::imprsesion::impression
::unfotunatley::unfortunately
::bascially::basically
::workin::working
::lookin::looking
::checkins::check-ins
::inprecisely::imprecisely
;------------------------------------------------------------------------------
; Generated Misspellings - the main list
;------------------------------------------------------------------------------
#include %A_ScriptDir%\generatedwords.ahk
#If