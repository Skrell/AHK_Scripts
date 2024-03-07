; c = case sensitive
; c1 = ignore the case that was typed, always use the same case for output
; * = immediate change (no need for space, period, or enter)
; ? = triggered even when the character typed immediately before it is alphanumeric
; r = raw output

#include %A_ScriptDir%\_VD.ahk
; #include %A_ScriptDir%\AhkDllThread.ahk

dummyFunction1() {
    static dummyStatic1 := VD.init()
    }

#WinActivateForce
#InstallMouseHook
#InstallKeybdHook
#KeyHistory 0
#WinActivateForce
#NoEnv
#SingleInstance
#MaxHotkeysPerInterval 500

SetBatchLines -1
SetWinDelay   -1
SetControlDelay -1
SetKeyDelay, 0

Global moving := False
Global ComboActive := False
Global skipCheck := False
Global hwndVD
Global forward := True
Global cycling := False
Global cyclingMin := False
Global ValidWindows := []
Global MinnedWindows := []
Global RevMinnedWindows := []
Global PrevActiveWindows := []
Global InitializeActWins := False
Global cycleCount := 1
Global cycleCountMin := 0
Global totalCycleCountMin := 0
Global startHighlight := False
Global border_thickness := 4
Global border_color := 0xFF00FF
Global hitTAB := False
Global hitCAPS := False
Global SearchingWindows := False
Global ReverseSearch    := False
Global UserInputTrimmed := ""
Global memotext := ""
Global totalMenuItemCount := 0
Global onlyTitleFound := ""
Global nil
Global CancelClose := False
Global lastWinMinHwndId := 0x999999
Global DrawingRect := False
Global v1 := 0
Global v2 := 0
Global v3 := 0
Global v4 := 0
        
Process, Priority,, High

Menu, Tray, Icon
Menu, Tray, NoStandard
Menu, Tray, Add, Run at startup, Startup
Menu, Tray, Add, &Suspend, Suspend_label
Menu, Tray, Add, Reload, Reload_label
Menu, Tray, Add, Exit, Exit_label
Menu, Tray, Default, &Suspend
Menu, Tray, Click, 1

SetTimer track, 50
; SetTimer CheckForNewWinSpawn, 300

SysGet, MonNum, MonitorPrimary 
SysGet, MonitorWorkArea, MonitorWorkArea, %MonNum%
SysGet, MonCount, MonitorCount

Tooltip, Total Number of Monitors is %MonCount%
sleep 1500
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
   
Gui +LastFound
hWnd := WinExist()
DllCall( "RegisterShellHookWindow", UInt, hWnd )
MsgNum := DllCall( "RegisterWindowMessage", Str, "SHELLHOOK" )
OnMessage( MsgNum, "ShellMessage" )

Return

;############### CAse COrrector ######################
; For AHK v1.1.31+
; By kunkel321, help from Mikeyww, Rohwedder, Others.
; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=118807
; CaseArr := [] ; Create the array.
; Lowers := "abcdefghijklmnopqrstuvwxyz" ; For If inStr.
; Uppers := "ABCDEFGHIJKLMNOPQRSTUVWXYZ" ; For If inStr.
; EndKeys := "abcdefghijklmnopqrstuvwxyz{Bs}{Space}{Enter}{Tab}=+-_,.?/\&1234567890{{}{}}()[]<>|"
; ccih := InputHook("V I2 E", EndKeys)
; Loop ; WARNING will loop forever until process is killed.
; {
    ; ccih.Start() ; Start the hook.
    ; ccih.Wait() ; Keep hooking until EndKey is pressed, then do stuff below.
    ; CaseArr.Push(ccih.EndKey) ; Push the Key to the back of the array.
    ; If (CaseArr.length() > 3) || (ccih.EndKey = "{Bs}")
        ; CaseArr.RemoveAt(1) ; If array too long, or BS pressed, remove item from front (making room for next push).
        ; ;ToolTip,% CaseArr[1] CaseArr[2] CaseArr[3],
    ; If (inStr(Uppers,CaseArr[1],True) && inStr(Uppers,CaseArr[2],True) && inStr(Lowers,CaseArr[3],True)) && (CaseArr[3] > 0) { ; "True" makes inStr() case-sensitive.
        ; Last2 := CaseArr[2] CaseArr[3] ; Combine in prep for next line.
        ; StringLower, Last2, Last2 
        ; Send, {Backspace 2} ; Do actual correction.
        ; Send, %Last2%
        ; ;SoundBeep
    ; }
; }

#If !hitCAPS || !hitTAB
    CapsLock:: Send {Delete}
    !a:: Send, {home}
    +!a:: Send, {SHIFT down}{home}{SHIFT up}
    !;:: Send, {end}
    +!;:: Send, {SHIFT down}{end}{SHIFT up}
    +!i::   Send {SHIFT down}{UP}{SHIFT up}
    +!k::   Send {SHIFT down}{DOWN}{SHIFT up}
    +!,::   Send {SHIFT down}{DOWN}{SHIFT up}
    +!j::   Send {LCtrl down}{SHIFT down}{LEFT}{SHIFT up}{LCtrl up}
    +!l::   Send {LCtrl down}{SHIFT down}{RIGHT}{SHIFT up}{LCtrl up}
    <^!j::  Send {LCtrl down}{LEFT}{LCtrl up}
    <^!l::  Send {LCtrl down}{RIGHT}{LCtrl up}
    <^!i::  Send {LCtrl down}{UP}{LCtrl up}
    <^!k::  Send {LCtrl down}{DOWN}{LCtrl up}
    <^+!j:: Send {LCtrl down}{LShift down}{LEFT}{LShift up}{LCtrl up}
    <^+!l:: Send {LCtrl down}{LShift down}{RIGHT}{LShift up}{LCtrl up}
    !i:: Send {UP}
    !k:: Send {DOWN}
    !,:: Send {DOWN}
    !j:: Send {LCtrl down}{LEFT}{LCtrl up}
    !l:: Send {LCtrl down}{RIGHT}{LCtrl up}
    LAlt & LButton:: Send {ENTER}
#If



; Ctl+Tab in chrome to goto recent
#If WinActive("ahk_exe Chrome.exe")
    prevChromeTab()
    {
        send ^+a
        loop {
            WinGet, allwindows, List
            loop, %allwindows%
            {
                this_id := "ahk_id " . allwindows%A_Index%
                WinGet, procName, ProcessName, %this_id%
                WinGetTitle, titID, %this_id%
                If (titID == "" && procName == "chrome.exe" && WinActive(this_id))
                {
                    send {BackSpace}
                    send {Enter}
                    Return
                }
            }
        }
    }
    ^Tab::prevChromeTab()
    return
#If

#If !SearchingWindows && !hitTAB && !hitCAPS
~Esc::
    MouseGetPos, , , escHwndID
    If ( A_PriorHotkey == A_ThisHotKey && A_TimeSincePriorHotkey  < 300 && escHwndID == escHwndID_old) {
        GoSub, DrawRect
        KeyWait, Esc, U T10
        GoSub, ClearRect
        Gui, GUI4Boarder: Hide
        If !CancelClose
            WinClose, A
        Else
            CancelClose := False
    }
    escHwndID_old := escHwndID
Return

Esc & x::
CancelClose := True
Return
#If

;https://superuser.com/questions/950452/how-to-quickly-move-current-window-to-another-task-view-desktop-in-windows-10
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer On

!1::
  HideTrayTip() 
If (VD.getCurrentDesktopNum() == 1)
     Return
     
  If GetKeyState("Lbutton", "P")
  {
      BlockInput, MouseMove
      Send {Lbutton up}
      WinGetTitle, Title, A
      WinGet, hwndVD, ID, A
      WinActivate, ahk_class Shell_TrayWnd
      WinSet, AlwaysOnTop , On, %Title%
      loop, 5
      {
        level := 255-(A_Index*50)
        WinSet, Transparent , %level%, %Title%
        sleep, 30
      }
      WinSet, ExStyle, ^0x80, %Title%
      Send {LWin down}{Ctrl down}{Left}{Ctrl up}{LWin up}
      sleep, 250
      Send {LWin down}{Ctrl down}{Left}{Ctrl up}{LWin up}
      sleep, 500
      WinMinimize, ahk_class Shell_TrayWnd
      WinSet, ExStyle, ^0x80, %Title%
      loop, 5
      {
        level := (A_Index*50)
        WinSet, Transparent , %level%, %Title%
        sleep, 30
      }
      WinSet, Transparent , off, %Title%
      WinActivate, %Title%
      Send {Lbutton down}
      BlockInput, MouseMoveOff
      KeyWait, Lbutton, U T10
      Send {Lbutton up}
      WinSet, AlwaysOnTop , Off, %Title%
  }
  Else
  {
      WinActivate, ahk_class Shell_TrayWnd
      If (VD.getCurrentDesktopNum() == 3) {
          Send {LWin down}{LCtrl down}{Left}{LCtrl up}{LWin up}
          sleep 250
          Send {LWin down}{LCtrl down}{Left}{LCtrl up}{LWin up}
      }
      Else If (VD.getCurrentDesktopNum() == 2)
          Send {LWin down}{LCtrl down}{Left}{LCtrl up}{LWin up}
      sleep 250
      WinMinimize, ahk_class Shell_TrayWnd
      WinSet, Transparent, off, ahk_id %hwndVD%
  }
  TrayTip , , Desktop 1, , 16
  sleep 1500
  HideTrayTip() 
Return

!2::
  HideTrayTip() 
  If (VD.getCurrentDesktopNum() == 2)
    Return
    
  If GetKeyState("Lbutton", "P")
  {
      BlockInput, MouseMove
      Send {Lbutton up}
      WinGetTitle, Title, A
      WinGet, hwndVD, ID, A
      WinActivate, ahk_class Shell_TrayWnd
      WinSet, AlwaysOnTop , On, %Title%
      loop, 5
      {
        level := 255-(A_Index*50)
        WinSet, Transparent , %level%, %Title%
        sleep, 30
      }
      WinSet, ExStyle, ^0x80, %Title%
      
      If (VD.getCurrentDesktopNum() == 1)
        Send {LWin down}{Ctrl down}{Right}{Ctrl up}{LWin up}
      Else If (VD.getCurrentDesktopNum() == 3)
        Send {LWin down}{LCtrl down}{Left}{LWin up}{LCtrl up}
        
      sleep, 500
      WinMinimize, ahk_class Shell_TrayWnd
      WinSet, ExStyle, ^0x80, %Title%
      loop, 5
      {
        level := (A_Index*50)
        WinSet, Transparent , %level%, %Title%
        sleep, 30
      }
      WinSet, Transparent , off, %Title%
      WinActivate, %Title%
      Send {Lbutton down}
      BlockInput, MouseMoveOff
      KeyWait, Lbutton, U T10
      Send {Lbutton up}
      WinSet, AlwaysOnTop , Off, %Title%
  }
  else
  {
      WinActivate, ahk_class Shell_TrayWnd
      If (VD.getCurrentDesktopNum() == 1)
        Send {LWin down}{Ctrl down}{Right}{Ctrl up}{LWin up}
      Else If (VD.getCurrentDesktopNum() == 3)
        Send {LWin down}{LCtrl down}{Left}{LCtrl up}{LWin up}
      sleep 250
      WinMinimize, ahk_class Shell_TrayWnd
      WinSet, Transparent, off, ahk_id %hwndVD%
  }
  TrayTip , , Desktop 2, , 16
  sleep 1500
  HideTrayTip() 
Return

!3::
  HideTrayTip() 
  If (VD.getCurrentDesktopNum() == 3)
     Return
    
  If GetKeyState("Lbutton", "P")
  {
      BlockInput, MouseMove
      Send {Lbutton up}
      WinGetTitle, Title, A
      WinGet, hwndVD, ID, A
      WinActivate, ahk_class Shell_TrayWnd
      WinSet, AlwaysOnTop , On, %Title%
      loop, 5
      {
        level := 255-(A_Index*50)
        WinSet, Transparent , %level%, %Title%
        sleep, 30
      }
      WinSet, ExStyle, ^0x80, %Title%
      Send {LWin down}{Ctrl down}{Right}{Ctrl up}{LWin up}
      sleep, 250
      Send {LWin down}{Ctrl down}{Right}{Ctrl up}{LWin up}
      sleep, 500
      WinMinimize, ahk_class Shell_TrayWnd
      WinSet, ExStyle, ^0x80, %Title%
      loop, 5
      {
        level := (A_Index*50)
        WinSet, Transparent , %level%, %Title%
        sleep, 30
      }
      WinSet, Transparent , off, %Title%
      WinActivate, %Title%
      Send {Lbutton down}
      BlockInput, MouseMoveOff
      KeyWait, Lbutton, U T10
      Send {Lbutton up}
      WinSet, AlwaysOnTop , Off, %Title%
  }
  else
  {
      WinActivate, ahk_class Shell_TrayWnd
      If (VD.getCurrentDesktopNum() == 1) {
          Send {LWin down}{LCtrl down}{Right}{LCtrl up}{LWin up}
          sleep, 250
          Send {LWin down}{LCtrl down}{Right}{LCtrl up}{LWin up}
      }
      Else {
          Send {LWin down}{LCtrl down}{Right}{LCtrl up}{LWin up}
      }
      sleep, 250
      
      WinMinimize, ahk_class Shell_TrayWnd
      WinSet, Transparent, off, ahk_id %hwndVD%
  }
  TrayTip , , Desktop 3, , 16
  sleep 1500
  HideTrayTip() 
Return

;============================================================================================================================
CheckForNewWinSpawn:
    DetectHiddenWindows, On
    WinGet, allWindows, List
    loop % allWindows
    {
        hwndID := allWindows%A_Index%
        WinGet, procStr, ProcessName, ahk_id %hwndID%
        WinGetClass, classStr, ahk_id %hwndID%
        If (IsAltTabWindow(hwndID) || (procStr == "OUTLOOK.EXE" && classStr == "#32770")) {
            If (MonCount > 1 && !InitializeActWins) {
                PrevActiveWindows.push(hwndID)
                continue
            }
            Else If (MonCount == 1) {
                Return
            }
            
            WinGet, state, MinMax, ahk_id %hwndID%
            If (state > -1) {
                WinGetTitle, cTitle, ahk_id %hwndID%
                desknum := VD.getDesktopNumOfWindow(cTitle)
                If (desknum == VD.getCurrentDesktopNum()) {
                    If desknum <= 0
                        continue
                    If (!HasVal(PrevActiveWindows, hwndID)) {
                        currentMon := MWAGetMonitorMouseIsIn()
                        currentMonHasActWin := GetFocusWindowMonitorIndex(hwndId, currentMon)
                        If !currentMonHasActWin {
                            WinActivate, ahk_id %hwndID%
                            Send, {LWin down}{LShift down}{Left}{LShift up}{LWin up}
                        }
                        PrevActiveWindows.push(hwndID)
                    }
                }
            }
        }
    }
    for idx, val in PrevActiveWindows {
        If (!WinExist("ahk_id " val))
            PrevActiveWindows.RemoveAt(idx)
    }
    DetectHiddenWindows, Off
    InitializeActWins := True
Return


;============================================================================================================================
FadeInWin1:
    Critical, On
    MouseGetPos, , , lclickHwndId

    If (lclickHwndId != ValidWindows[1])
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[1]
    If (lclickHwndId != ValidWindows[2])
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[2]
    If (lclickHwndId != ValidWindows[3])
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[3]
    
    WinActivate, % "ahk_id " ValidWindows[3]
    WinActivate, % "ahk_id " ValidWindows[2]
    WinActivate, % "ahk_id " ValidWindows[1]
    
    WinActivate, % "ahk_id " lclickHwndId

    If (lclickHwndId != ValidWindows[1]) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[1]
        sleep 20
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[1]
        sleep 20
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[1]
        sleep 20
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[1]
    }
    If (lclickHwndId != ValidWindows[2]) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[2]
        sleep 20
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[2]
        sleep 20
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[2]
        sleep 20
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[2]
    }
    If (lclickHwndId != ValidWindows[3]) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[3]
        sleep 20
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[3]
        sleep 20
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[3]
        sleep 20
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[3]
    }
    ; If (ValidWindows.MaxIndex() >= 4 && lclickHwndId != ValidWindows[4]) {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[4]
    ; }
    Critical, Off
Return

FadeInWin2:
    Critical, On
    If (cycleCount != 1)
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[1]
    If (cycleCount != 2)
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[2]
    If (cycleCount != 3)
        WinSet, Transparent, 0, % "ahk_id " ValidWindows[3]
    
    WinActivate, % "ahk_id " ValidWindows[3]
    WinActivate, % "ahk_id " ValidWindows[2]
    WinActivate, % "ahk_id " ValidWindows[1]
    
    WinActivate, % "ahk_id " ValidWindows[cycleCount]
    
    If (cycleCount != 1) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[1]
        sleep 20
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[1]
        sleep 20
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[1]
        sleep 20
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[1]
    } 
    If (cycleCount != 2) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[2]
        sleep 20
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[2]
        sleep 20
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[2]
        sleep 20
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[2]
    }
    If (cycleCount != 3) {
        WinSet, Transparent, 50,  % "ahk_id " ValidWindows[3]
        sleep 20
        WinSet, Transparent, 100, % "ahk_id " ValidWindows[3]
        sleep 20
        WinSet, Transparent, 200, % "ahk_id " ValidWindows[3]
        sleep 20
        WinSet, Transparent, 255, % "ahk_id " ValidWindows[3]
    }
    ; If (ValidWindows.MaxIndex() >= 4 && cycleCount != 4) {
        ; WinSet, Transparent, 50,  % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 100, % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 200, % "ahk_id " ValidWindows[4]
        ; sleep 10
        ; WinSet, Transparent, 255, % "ahk_id " ValidWindows[4]
    ; }
    Critical, Off
Return

ResetWins:
    If hitCAPS {
        For k, v in RevMinnedWindows 
        {
            WinMinimize, % "ahk_id " RevMinnedWindows[k]
        }
        If hitTAB {
            If (ValidWindows.MaxIndex() >= 4)
                WinActivate, % "ahk_id " ValidWindows[4]
            If (ValidWindows.MaxIndex() >= 3)
                WinActivate, % "ahk_id " ValidWindows[3]
            If (ValidWindows.MaxIndex() >= 2)
                WinActivate, % "ahk_id " ValidWindows[2]
            If (ValidWindows.MaxIndex() >= 1)    
                WinActivate, % "ahk_id " ValidWindows[1]        
        }
    }
    Else {
        If (ValidWindows.MaxIndex() >= 4)
            WinActivate, % "ahk_id " ValidWindows[4]
        If (ValidWindows.MaxIndex() >= 3)
            WinActivate, % "ahk_id " ValidWindows[3]
        If (ValidWindows.MaxIndex() >= 2)
            WinActivate, % "ahk_id " ValidWindows[2]
        If (ValidWindows.MaxIndex() >= 1)    
            WinActivate, % "ahk_id " ValidWindows[1]
    }
Return

#MaxThreadsBuffer Off

#MaxThreadsPerHotkey 2

#If !SearchingWindows
;https://superuser.com/questions/1261225/prevent-alttab-from-switching-to-minimized-windows
~Alt Up::
    If !(hitCAPS && !hitTAB) {
        WinGet, actWndID, ID, A
        If (GetKeyState("Lbutton","P") && cycling && (ValidWindows.length() > 2)) {
            If ((actWndID == ValidWindows[1]) || (ValidWindows.length() <= 1)) {
                Gui, GUI4Boarder: Hide
            }
            Else If (startHighlight) {
                BlockInput, MouseMove
                GoSub, DrawRect
                Send, {Lbutton Up}
                ; v1 := ValidWindows[1]
                ; v2 := ValidWindows[2]
                ; v3 := ValidWindows[3]
                ; MouseGetPos, , , lclickHwndId
                
                ; script =
                ; (
                    ; #NoTrayIcon
                    ; Process, Priority,, High
                    ; If (%lclickHwndId% != %v1%)
                        ; WinSet, Transparent, 0, ahk_id %v1%
                    ; If (%lclickHwndId% != %v2%)
                        ; WinSet, Transparent, 0, ahk_id %v2%
                    ; If (%lclickHwndId% != %v3%)
                        ; WinSet, Transparent, 0, ahk_id %v3%
                    
                    ; WinActivate, ahk_id %v3%
                    ; WinActivate, ahk_id %v2%
                    ; WinActivate, ahk_id %v1%
                    
                    ; WinActivate, ahk_id %lclickHwndId%

                    ; If (%lclickHwndId% != %v1%) {
                        ; WinSet, Transparent, 50,  ahk_id %v1%
                        ; sleep 20
                        ; WinSet, Transparent, 100, ahk_id %v1%
                        ; sleep 20                        
                        ; WinSet, Transparent, 200, ahk_id %v1%
                        ; sleep 20                        
                        ; WinSet, Transparent, 255, ahk_id %v1%
                    ; }
                    ; If (%lclickHwndId% != %v2%) {
                        ; WinSet, Transparent, 50,  ahk_id %v2%
                        ; sleep 20
                        ; WinSet, Transparent, 100, ahk_id %v2%
                        ; sleep 20                         
                        ; WinSet, Transparent, 200, ahk_id %v2%
                        ; sleep 20                         
                        ; WinSet, Transparent, 255, ahk_id %v2%
                    ; }
                    ; If (%lclickHwndId% != %v3%) {
                        ; WinSet, Transparent, 50,  ahk_id %v3%
                        ; sleep 20
                        ; WinSet, Transparent, 100, ahk_id %v3%
                        ; sleep 20                         
                        ; WinSet, Transparent, 200, ahk_id %v3%
                        ; sleep 20                         
                        ; WinSet, Transparent, 255, ahk_id %v3%
                    ; }
                ; )
                ; DynaRun(script, dynaRunName)
                GoSub, FadeInWin1

                BlockInput, MouseMoveOff
            }
        }
        Else {
            If (GetKeyState("x","P") || (actWndID == ValidWindows[1]) || (ValidWindows.length() <= 1)) {
                If (GetKeyState("x","P")) {
                    Gui, GUI4Boarder: Hide
                    GoSub, ResetWins
                }
            }
            Else If (hitTAB && hitCAPS) {
                Critical On
                WinGet, actMinID, ID, A
                
                If (ValidWindows.MaxIndex() >= 4)
                    WinActivate, % "ahk_id " ValidWindows[4]
                If (ValidWindows.MaxIndex() >= 3)
                    WinActivate, % "ahk_id " ValidWindows[3]
                If (ValidWindows.MaxIndex() >= 2)
                    WinActivate, % "ahk_id " ValidWindows[2]
                If (ValidWindows.MaxIndex() >= 1)    
                    WinActivate, % "ahk_id " ValidWindows[1]
                WinActivate, % "ahk_id " actMinID
                Critical Off
            }
            Else If (cycling && startHighlight && (ValidWindows.length() > 2))
            {
                GoSub, FadeInWin2
                WinActivate, % "ahk_id " ValidWindows[cycleCount]
            }
            Else If (!cycling && !startHighlight)
            {
                Critical On
                WinGet, allWindows, List
                loop % allWindows
                {
                    hwndID := allWindows%A_Index%
                    
                    If (A_Index > 10)
                        break
                    If (MonCount > 1) {
                        currentMon := MWAGetMonitorMouseIsIn()
                        currentMonHasActWin := GetFocusWindowMonitorIndex(hwndId, currentMon)
                    }
                    Else {
                        currentMonHasActWin := True
                    }
                    If (currentMonHasActWin) {
                        WinGet, state, MinMax, ahk_id %hwndID%
                        If (state > -1) {
                            WinGetTitle, cTitle, ahk_id %hwndID%
                            If (IsAltTabWindow(actWndID)) {
                                desknum := VD.getDesktopNumOfWindow(cTitle)
                                If desknum <= 0
                                    continue   
                                If (desknum == VD.getCurrentDesktopNum()) {
                                    WinActivate, % "ahk_id " hwndID
                                    GoSub, DrawRect
                                    break
                                }
                            }
                        }
                    }
                }
                Critical Off
            }
        }
    }
    
    cycleCount     := 1
    cycleCountMin  := 1
    If (totalCycleCountMin >= 2)
        ReverseSearch := True
    Else
        ReverseSearch := False
        
    totalCycleCountMin  := 0
    ValidWindows   := {}
    MinnedWindows  := {}
    RevMinnedWindows  := {}
    cycling        := False
    cyclingMin     := False
    KeyWait, x, U T1
    hitTAB         := False
    hitCAPS        := False
    ; while (DrawingRect == True) {
        ; sleep, 100
    ; }
    Gosub, ClearRect
    startHighlight := False
    Gui, GUI4Boarder: Hide
return
#If 

#If (hitTAB || hitCAPS)
!x::
    Tooltip, Cancelled!
    SetTimer, ClearRect, -50
    Gui, GUI4Boarder: Hide
    If (hitCAPS && !hitTAB)
        GoSub, ResetWins
    sleep, 3000
    Tooltip
Return
#If

#If (hitTAB || hitCAPS)
x::
Return
#If

#If hitTAB
~!LButton::
    SetTimer, DrawRect, -50
Return
#If

!CapsLock::CycleMin(forward)
!+CapsLock::CycleMin(!forward)

CycleMin(direction)
{
    Global cyclingMin
    Global cycleCountMin
    Global totalCycleCountMin
    Global MonCount
    Global startHighlight
    Global hitCAPS
    Global RevMinnedWindows
    Global MinnedWindows
    Global ReverseSearch
    Global lastWinMinHwndId
    
    hitCAPS := True
            
    Gui, GUI4Boarder: Hide
            
    If !cyclingMin
    {
        Critical On
            
        WinGet, allWindows, List
        loop % allWindows
        {
            If !(GetKeyState("LAlt","P"))
            {
                Critical Off
                Return
            }
            
            hwndID := allWindows%A_Index%
            
            WinGetTitle, cTitle, ahk_id %hwndID%
            If (IsAltTabWindow(hwndID)) {
                WinGet, state, MinMax, ahk_id %hwndID%
                If (state == -1) {
                    desknum := VD.getDesktopNumOfWindow(cTitle)
                    If (desknum == VD.getCurrentDesktopNum()) {
                        If (desknum <= 0)
                            continue
                        MinnedWindows.push(hwndID)
                        cyclingMin := True
                    }
                }
            }
            Tooltip, 
        }
        
        If ReverseSearch {
           
            brr := MinnedWindows.clone()
            for k in MinnedWindows.clone()
                RevMinnedWindows[k] := brr.pop()
        }
        Else {
            RevMinnedWindows := MinnedWindows
        }
        ; tooltip, % join(RevMinnedWindows)
        loop % RevMinnedWindows.length()
        {
            currentVal := RevMinnedWindows[A_Index]
            ; tooltip, %lastWinMinHwndId% vs %currentVal%
            If (lastWinMinHwndId == currentVal) {
                ; tooltip, found it %currentVal%
                WinActivate, % "ahk_id " lastWinMinHwndId
                sleep 100
                startHighlight := True
                GoSub, DrawRect
                break
            }
            Else {
                cycleCountMin += 1
                currentVal := RevMinnedWindows[cycleCountMin]
            }
            ; sleep, 1000
        }
        Critical Off
    }
    
    totalCycleCountMin += 1
    
    If ((RevMinnedWindows.length() >= 1 && totalCycleCountMin > 1) || (RevMinnedWindows.length() >= 1 && !startHighlight))
    {
        If direction
        {
            If (cycleCountMin > RevMinnedWindows.MaxIndex())
                cycleCountMin := 1
            Else
                cycleCountMin += 1
            
            PrevCount := cycleCountMin-1
            If (PrevCount < 1)
                PrevCount := RevMinnedWindows.MaxIndex()
                
            WinMinimize,% "ahk_id " RevMinnedWindows[PrevCount]
            lastWinMinHwndId := RevMinnedWindows[PrevCount]
            If hitCAPS
                sleep, 200
            ; WinRestore, % "ahk_id " RevMinnedWindows[cycleCountMin]
            WinActivate, % "ahk_id " RevMinnedWindows[cycleCountMin]
            startHighlight := True
            If (startHighlight) {
                sleep 100
                GoSub, DrawRect
            }
        }
        Else
        {
            If (cycleCountMin < 1)
                cycleCountMin := RevMinnedWindows.MaxIndex()
            Else
                cycleCountMin -= 1
            
            PrevCount := cycleCountMin+1
            If (PrevCount > RevMinnedWindows.MaxIndex())
                PrevCount := 1
                
            WinMinimize,% "ahk_id " RevMinnedWindows[PrevCount]
            lastWinMinHwndId := RevMinnedWindows[PrevCount]
            If hitCAPS
                sleep, 200
            ; WinRestore, % "ahk_id " RevMinnedWindows[cycleCountMin]
            WinActivate, % "ahk_id " RevMinnedWindows[cycleCountMin]
            startHighlight := True
            If (startHighlight) {
                sleep 100
                GoSub, DrawRect
            }
        }
    }
    
    Return
}

!Tab::Cycle(forward)
!+Tab::Cycle(!forward)

Cycle(direction)
{
    Global cycling
    Global cycleCount
    Global ValidWindows
    Global MonCount
    Global startHighlight
    Global hitTAB
    Global RevMinnedWindows
    
    hitTAB := True
    
    If hitCAPS {
        For k, v in RevMinnedWindows 
        {
            WinMinimize, % "ahk_id " RevMinnedWindows[k]
        }
        hitCAPS := False
    }
    
    If !cycling
    {
        Critical On
        DetectHiddenWindows, Off
        skipFirst := True
        WinGetPos,,,,currActHeight, A
            
        WinGet, allWindows, List
        loop % allWindows
        {
            If !(GetKeyState("LAlt","P"))
            {
                Critical Off
                Return
            }
            
            hwndID := allWindows%A_Index%
            If (MonCount > 1) {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := GetFocusWindowMonitorIndex(hwndId, currentMon)
            }
            Else {
                currentMonHasActWin := True
            }
            
            If (currentMonHasActWin) {
                WinGetTitle, cTitle, ahk_id %hwndID%
                If (IsAltTabWindow(hwndID)) {
                    WinGet, state, MinMax, ahk_id %hwndID%
                    If (state > -1) {
                        desknum := VD.getDesktopNumOfWindow(cTitle)
                        If (desknum == VD.getCurrentDesktopNum()) {
                            If desknum <= 0
                                continue
                            ValidWindows.push(hwndID)
                            If (ValidWindows.MaxIndex() == 2) {
                                WinActivate, % "ahk_id " hwndID
                                cycleCount := 2
                                ; WinGetTitle, tit1, % "ahk_id " ValidWindows[1]
                                ; WinGetTitle, tit2, % "ahk_id " ValidWindows[2]
                                ; tooltip, %tit1%  `n %tit2%
                                GoSub, DrawRect
                            }
                        }
                    }
                }
            }
            ; Tooltip, 
        }
        Critical Off
    }
    
    If (ValidWindows.length() == 1) {
        tooltip, % "Only " ValidWindows.length() " Window to Show..." 
        sleep, 1000
        tooltip,
        Return
    }
        
    
    If (ValidWindows.length() >= 2 && cycling) 
    {
        If direction
        {
            If (cycleCount == ValidWindows.MaxIndex())
                cycleCount := 1
            Else
                cycleCount += 1
            WinActivate, % "ahk_id " ValidWindows[cycleCount]
            ; If (startHighlight)
            GoSub, DrawRect
        }
        Else
        {
            If (cycleCount == 1)
                cycleCount := ValidWindows.MaxIndex()
            Else
                cycleCount -= 1
            WinActivate, % "ahk_id " ValidWindows[cycleCount]
            ; If (startHighlight)
            GoSub, DrawRect
        }
    }
    If (cycleCount > 2)
        startHighlight := True
    cycling := True
    Return
}

ClearRect:

    loop 25 {
        If (hitTAB || hitCAPS) || GetKeyState("LAlt", "P") {
            ; Gui, GUI4Boarder: Hide
            WinSet, Transparent, 255, ahk_id %Highlighter%
            Return
        }
        sleep, 10
    }
        
    WinSet, Transparent, 225, ahk_id %Highlighter%
    loop 6 {
        If (hitTAB || hitCAPS) || GetKeyState("LAlt", "P") {
            ; Gui, GUI4Boarder: Hide
            WinSet, Transparent, 255, ahk_id %Highlighter%
            Return
        }
        sleep 10
    }
    WinSet, Transparent, 200, ahk_id %Highlighter%
    loop 4 {
        If (hitTAB || hitCAPS) || GetKeyState("LAlt", "P") {
            ; Gui, GUI4Boarder: Hide
            WinSet, Transparent, 255, ahk_id %Highlighter%
            Return
        }
        sleep 10
    }
    WinSet, Transparent, 175, ahk_id %Highlighter%
    loop 4 {
        If (hitTAB || hitCAPS) || GetKeyState("LAlt", "P") {
            ; Gui, GUI4Boarder: Hide
            WinSet, Transparent, 255, ahk_id %Highlighter%
            Return
        }
        sleep 10
    }
    WinSet, Transparent, 125, ahk_id %Highlighter%
    loop 4 {
        If (hitTAB || hitCAPS) || GetKeyState("LAlt", "P") {
            ; Gui, GUI4Boarder: Hide
            WinSet, Transparent, 255, ahk_id %Highlighter%
            Return
        }
        sleep 10
    }
    WinSet, Transparent, 50, ahk_id %Highlighter%
    loop 4 {
        If (hitTAB || hitCAPS) || GetKeyState("LAlt", "P") {
            ; Gui, GUI4Boarder: Hide
            WinSet, Transparent, 255, ahk_id %Highlighter%
            Return
        }
        sleep 10
    }
    Gui, GUI4Boarder: Hide
Return

; https://www.autohotkey.com/boards/viewtopic.php?t=110505
DrawRect:
    Critical, On
    DrawingRect := True
    ; WinGetPos, x, y, w, h, A
    WinGet, activeWin, ID, A
    If !IsAltTabWindow(activeWin)
        Return
    WinGetPosEx(activeWin, x, y, w, h)
    
    if (x="")
        return
    Gui, GUI4Boarder: +Lastfound +AlwaysOnTop +Toolwindow hWndHighlighter

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
        WinGet, myState, MinMax, A
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

    Gui, GUI4Boarder: Color, %border_color%
    Gui, GUI4Boarder: -Caption

    ;WinSet, Region, 0-0 %w%-0 %w%-%h% 0-%h% 0-0 %border_thickness%-%border_thickness% %iw%-%border_thickness% %iw%-%ih% %border_thickness%-%ih% %border_thickness%-%border_thickness%
     WinSet, Region, %outerX%-%outerY% %outerX2%-%outerY% %outerX2%-%outerY2% %outerX%-%outerY2% %outerX%-%outerY%    %innerX%-%innerY% %innerX2%-%innerY% %innerX2%-%innerY2% %innerX%-%innerY2% %innerX%-%innerY% 

    ;Gui, Show, w%w% h%h% x%x% y%y% NoActivate, Table awaiting Action
    Gui,GUI4Boarder: Show, w%newW% h%newH% x%newX% y%newY% NoActivate, Table awaiting Action
    WinSet, Transparent, off, ahk_id %Highlighter%
    DrawingRect := False
    Critical, Off
return

UpdateInputBoxTitle:
    If WinExist("Type Up to 3 Letters of a Window Title to Search") {
        WinActivate, Type Up to 3 Letters of a Window Title to Search
        WinSet, AlwaysOnTop, On, Type Up to 3 Letters of a Window Title to Search
    }
         
    ControlGetText, memotext, Edit1, Type Up to 3 Letters of a Window Title to Search
    StringLen, memolength, memotext
    
    If (memolength >= 3 || InStr(memotext, " ")) {
        UserInputTrimmed := Trim(memotext)
        Send, {ENTER}
    }
    else {
        UserInputTrimmed := UserInput
    }
return

#If SearchingWindows
Esc::
    Send, {ENTER}
Return
#If


#MaxThreadsPerHotkey 1
; https://superuser.com/questions/1603554/autohotkey-find-and-focus-windows-by-name-accross-virtual-desktops
$!`::
    Send, {LAlt}{up}
    SearchingWindows := True
    SetTimer, UpdateInputBoxTitle, 50
    InputBox, UserInput, Type Up to 3 Letters of a Window Title to Search, , , 340, 100, CoordXCenterScreen()-(340/2), CoordYCenterScreen()-(100/2)
    SetTimer, UpdateInputBoxTitle, off
    SearchingWindows := False
    
    If ErrorLevel
    {
        return
    }   
    else
    {
        DetectHiddenWindows, On
        ; Critical On
        totalMenuItemCount := 0
        onlyTitleFound := ""
        winArray := []
        winAssoc := {}
        winArraySort := []
        
        WinGet, id, list
        Loop, %id%
        {
            this_ID := id%A_Index%
            WinGetTitle, title, ahk_id %this_ID%
            WinGet, procName, ProcessName , ahk_id %this_ID%
            
            ; If (title = "" || title = "Microsoft Text Input Application")
                ; continue            
            ; If (!IsWindow(WinExist("ahk_id" . this_ID)) && !InStr(title, "Inbox")) 
                ; continue

            If !IsAltTabWindow(this_ID)
                continue
                
            desknum := VD.getDesktopNumOfWindow(title)
            If desknum <= 0
                continue
            finalTitle := % "Desktop " desknum " ↑ " procName " ↑ " title "^" this_ID
            winArray.Push(finalTitle)
        }
        
        For k, v in winArray 
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
            If (minState == -1 && VD.getDesktopNumOfWindow(titleEntry) == VD.getCurrentDesktopNum())
                finalEntry   := % desktopEntry " : [" titleEntry "] (" procEntry ")"
            Else 
                finalEntry   := % desktopEntry " : " titleEntry " (" procEntry ")"

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
        ; Critical Off
        If (totalMenuItemCount == 1 && onlyTitleFound != "") {
            GoSub, ActivateWindow
        }
        Else {
            CoordMode, Mouse, Screen
            CoordMode, Menu, Screen
            ; https://www.autohotkey.com/boards/viewtopic.php?style=17&t=107525#p478308
            ; drawX := A_ScreenWidth/2
            ; drawY := A_ScreenHeight/2
            drawX := CoordXCenterScreen()
            drawY := CoordYCenterScreen()
            Gui, ShadowFrFull:  Show, x%drawX% y%drawY% h1 y1
            Gui, ShadowFrFull2: Show, x%drawX% y%drawY% h1 y1
            
            ; DllCall("SetTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 1, "UInt", 10, "Ptr", RegisterCallback("MyFader", "F"))
            DllCall("SetTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 2, "UInt", 150, "Ptr", RegisterCallback("MyTimer", "F"))
            
            ShowMenu(MenuGetHandle("windows"), False, drawX, drawY, 0x14)
            
            Gui, ShadowFrFull:  Hide
            Gui, ShadowFrFull2: Hide
        }
        Menu, windows, deleteAll
    }
return

ActivateWindow:
    Gui, ShadowFrFull:  Hide
    Gui, ShadowFrFull2: Hide
    DetectHiddenWindows, On
    thisMenuItem := ""
    
    If (totalMenuItemCount == 1 && onlyTitleFound != "")
        thisMenuItem := onlyTitleFound
    Else
        thisMenuItem := A_ThisMenuItem
        
    SetTitleMatchMode, 3
    
    
    fulltitle := RegExReplace(thisMenuItem, "\(\S+\.\S+\)$", "")
    fulltitle := Trim(fulltitle)
    ; msgbox, %fulltitle%
    fulltitle := RegExReplace(fulltitle, "^Desktop\s\d+\s*\:\s?", "")
    fulltitle := Trim(fulltitle)
    ; msgbox, %fulltitle%
    fulltitle := RegExReplace(fulltitle, "^\[?", "")
    fulltitle := Trim(fulltitle)
    ; msgbox, %fulltitle%
    fulltitle := RegExReplace(fulltitle, "\]?$", "")
    fulltitle := Trim(fulltitle)
    ; msgbox, %fulltitle%
    
    cdt := VD.getCurrentDesktopNum()
    desknum := VD.getDesktopNumOfWindow(fulltitle)
    WinGet, vState, MinMax, %fulltitle%
    If (desknum < cdt)
    {
        WinGetPos, vwx,vwy,vww,, %fulltitle%
        WinSet, Transparent, 0, %fulltitle%
        VD.MoveWindowToCurrentDesktop(fulltitle)
        If (vState > -1) {
            ; WinRestore , %fulltitle%
            WinActivate, %fulltitle%
            offscreenX := -1*vww
            
            WinMove, %fulltitle%,, %offscreenX%, , , ,
           
            WinSet, Transparent, 255, %fulltitle%
            loopCount := (vwx+abs(offscreenX))/100

            loop, %loopCount%
            {
                offscreenX := offscreenX + 100
                WinMove, %fulltitle%,, offscreenX, , , , 
                sleep 1
            }
            WinMove, %fulltitle%,, vwx, , , , 
        }
        else {
            sleep 500
            WinMinimize, %fulltitle% 
            WinSet, Transparent, 255, %fulltitle%
            ; WinRestore , %fulltitle%
            WinActivate, %fulltitle%
        }
    }
    else If (desknum > cdt)
    {
        WinGetPos, vwx,vwy,vww,, %fulltitle%
        WinSet, Transparent, 0, %fulltitle%
        VD.MoveWindowToCurrentDesktop(fulltitle)
        If (vState > -1) {
            ; WinRestore , %fulltitle%
            WinActivate, %fulltitle%
            offscreenX := A_ScreenWidth
            
            WinMove, %fulltitle%,, %offscreenX%, , , ,
            
            WinSet, Transparent, 255, %fulltitle%
            loopCount := (A_ScreenWidth-vwx)/100
            ; tooltip, %loopCount%
            loop, %loopCount%
            {
                offscreenX := offscreenX - 100
                WinMove, %fulltitle%,, offscreenX, , , , 
                sleep 1
            }
            WinMove, %fulltitle%,, vwx, , , , 
        }
        else {
            sleep 500
            WinMinimize, %fulltitle% 
            WinSet, Transparent, 255, %fulltitle%
            ; WinRestore , %fulltitle%
            WinActivate, %fulltitle%
        }
    }
    else
    {
        ; If (vState == -1) {
            ; WinRestore , %fulltitle%
        ; }
        WinActivate, %fulltitle%
        WinGet, hwndId, ID, A
        currentMon := MWAGetMonitorMouseIsIn()
        currentMonHasActWin := GetFocusWindowMonitorIndex(hwndId, currentMon)
        If !currentMonHasActWin {
            Send, {LWin down}{LShift down}{Left}{LShift up}{LWin up}
            sleep, 150
         }
        GoSub, DrawRect
        GoSub, ClearRect
        Gui, GUI4Boarder: Hide
    }
return

#If moving
~RButton::Return
#If

#If !VolumeHover()
~LButton::
   MouseGetPos, X, Y
   PixelGetColor, HexColor, %X%, %Y%, RGB
   If (A_PriorHotkey == A_ThisHotkey && A_TimeSincePriorHotkey < 400 && (hWnd := WinActive("ahk_class CabinetWClass")) && IsEmptySpace() && HexColor == 0xFFFFFF)
   { 
        Send !{Up}
        sleep, 200
   }
   Gui, GUI4Boarder: Hide
   DrawingRect := False
   Return
#If

LWin & WheelUp::send {Volume_Up}
LWin & WheelDown::send {Volume_Down}

#If VolumeHover()
WheelUp::send {Volume_Up}
WheelDown::send {Volume_Down}

LButton::
    Run, C:\Windows\System32\SndVol.exe
    WinWait, ahk_exe SndVol.exe
    WinGetPos, sx, sy, sw, sh, ahk_exe SndVol.exe
    sw := sw + 200
    WinMove, ahk_exe SndVol.exe, , A_ScreenWidth-sw, MonitorWorkAreaBottom-sh, sw
    WinActivate, ahk_exe SndVol.exe
    x_coord := A_ScreenWidth - floor((sx+sw)/2)
    y_coord := MonitorWorkAreaBottom - 30
    CoordMode, Pixel, Screen
    sleep 300
    Critical On
    loop
    {
        PixelGetColor, HexColor, %x_coord%, %y_coord%, RGB
        ; msgbox, %HexColor% - %x_coord% - %y_coord%
        newX := A_ScreenWidth-sw-(10*A_Index)
        newW := sw + (10*A_Index)
        If (HexColor == 0xCDCDCD || HexColor == 0xF0F0F0)
            WinMove, ahk_exe SndVol.exe, , %newX%, , %newW% 
        Else
            break
    }
    Critical Off
Return
#If 

#If !moving
$RButton::
    ComboActive := False
    loop {
        If !(GetKeyState("RButton", "P"))
        {
            break
        }
        sleep 20
    }
    If !ComboActive
    {
        Send, {Click, Right}
        ComboActive := False
    }
Return
#If

#If !moving
RButton & WheelUp::
    ComboActive := True
    MouseGetPos, , , target
    WinActivate, ahk_id %target%
    Send {PgUp}
Return
#If

#If !moving
RButton & WheelDown::
    ComboActive := True
    MouseGetPos, , , target
    WinActivate, ahk_id %target%
    Send {PgDn}
Return
#If

~$WheelUp::
    Hotkey, $WheelUp, Off
    MouseGetPos, , , wuID
    WinGetClass, wuClass, ahk_id %wuID%
    If (wuClass == "Shell_TrayWnd" && !moving && !VolumeHover())
    {
        Send {LWin down}{LCtrl down}{Left}{LWin up}{LCtrl up}
        sleep, 750
    }
    Hotkey, $WheelUp, On
Return

~$WheelDown::
    Hotkey, $WheelDown, Off
    MouseGetPos, , , wdID
    WinGetClass, wdClass, ahk_id %wdID%
    If (wdClass == "Shell_TrayWnd" && !moving && !VolumeHover())
    {
        Send {LWin down}{LCtrl down}{Right}{LWin up}{LCtrl up}
        sleep, 750
    }
    Hotkey, $WheelDown, On
Return



/* ;
***********************************
***** SHORTCUTS CONFIGURATION *****
***** https://github.com/JuanmaMenendez/AutoHotkey-script-Open-Show-Apps/blob/master/Switch-opened-windows-of-same-App.ahk ****
***********************************
*/
VolumeHover() {
    ControlGetText, toolText,, ahk_class tooltips_class32
    If (InStr(toolText, "Speakers") || InStr(toolText, "Headphones"))
        Return True
    Else
        Return False
}

IsEmptySpace() {
   static ROLE_SYSTEM_LIST := 0x21
   CoordMode, Mouse
   MouseGetPos, X, Y
   AccObj := AccObjectFromPoint(idChild, X, Y)
   Return (AccObj.accRole(0) == ROLE_SYSTEM_LIST)
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

IsWindow(hWnd){
    WinGet, dwStyle, Style, ahk_id %hWnd%
    If ((dwStyle&0x08000000) || !(dwStyle&0x10000000)) {
        return False
    }
    WinGet, dwExStyle, ExStyle, ahk_id %hWnd%
    If (dwExStyle & 0x00000080) {
        return False
    }
    WinGetClass, szClass, ahk_id %hWnd%
    If (szClass = "TApplication") {
        return False
    }
    WinGetPos,,,W,H, ahk_id %hWnd%
    WinGet, state, MinMax, ahk_id %hWnd%
    If (H < 375 && state > -1 || W < 290 && state > -1) {
        return False
    }
    return True
}

; https://www.autohotkey.com/boards/search.php?style=17&author_id=62433&sr=posts
MyTimer() {
   Global IGUIF
   Global IGUIF2
   DllCall("KillTimer", "Ptr", A_ScriptHwnd, "Ptr", id := 2)
   
   run, C:\Users\vbonaventura\Programs\SendDownKey.ahk
   WinGetPos, menux, menuy, menuw, menuh, ahk_class #32768
   WinMove, ahk_id %IGUIF%  , ,menux, menuy, menuw, menuh, 
   WinMove, ahk_id %IGUIF2%  , ,menux, menuy, menuw, menuh, 
   
   WinSet, TransColor, FF00FF 254, ahk_id %IGUIF% 
   WinSet, TransColor, FF00FF 254, ahk_id %IGUIF2% 
   ; Gui, ShadowFrFull: Show, x%menux% w%menuw% h%menuh% y%menuy%
   WinSet, AlwaysOnTop, on,  ahk_class #32768
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
    return (( Mon1Right-Mon1Left ) / 2) + Mon1Left
}

CoordYCenterScreen()
{
    ScreenNumber := GetCurrentMonitorIndex()
    SysGet, Mon1, Monitor, %ScreenNumber%
    return ((Mon1Bottom-Mon1Top - 30) / 2) + Mon1Top
}

; https://www.autohotkey.com/boards/viewtopic.php?p=96016#p96016
ProcessIsElevated(vPID)
{
    ;PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    If !(hProc := DllCall("kernel32\OpenProcess", "UInt",0x1000, "Int",0, "UInt",vPID, "Ptr"))
        return -1
    ;TOKEN_QUERY := 0x8
    hToken := 0
    If !(DllCall("advapi32\OpenProcessToken", "Ptr",hProc, "UInt",0x8, "Ptr*",hToken))
    {
        DllCall("kernel32\CloseHandle", "Ptr",hProc)
        return -1
    }
    ;TokenElevation := 20
    vIsElevated := vSize := 0
    vRet := (DllCall("advapi32\GetTokenInformation", "Ptr",hToken, "Int",20, "UInt*",vIsElevated, "UInt",4, "UInt*",vSize))
    DllCall("kernel32\CloseHandle", "Ptr",hToken)
    DllCall("kernel32\CloseHandle", "Ptr",hProc)
    return vRet ? vIsElevated : -1
}

; https://www.autohotkey.com/boards/viewtopic.php?t=26700#p176849
IsAltTabWindow(hWnd)
{
   DetectHiddenWindows, On
   
   WinGetTitle, tit, ahk_id %hWnd%
   WinGet, vPID, PID, % "ahk_id " hWnd
   WinGet, vProc, ProcessName, ahk_id %hWnd%
   
   If (tit == "" or vProc == "qrivi_ssam.exe")
      return
      
   If (ProcessIsElevated(vPID))
      return
      
   static WS_EX_APPWINDOW := 0x40000, WS_EX_TOOLWINDOW := 0x80, DWMWA_CLOAKED := 14, DWM_CLOAKED_SHELL := 2, WS_EX_NOACTIVATE := 0x8000000, GA_PARENT := 1, GW_OWNER := 4, MONITOR_DEFAULTTONULL := 0, VirtualDesktopExist, PropEnumProcEx := RegisterCallback("PropEnumProcEx", "Fast", 4)
   If (VirtualDesktopExist = "")
   {
      OSbuildNumber := StrSplit(A_OSVersion, ".")[3]
      If (OSbuildNumber < 14393)
         VirtualDesktopExist := 0
      else
         VirtualDesktopExist := 1
   }
   If !DllCall("IsWindowVisible", "uptr", hWnd)
      return
   DllCall("DwmApi\DwmGetWindowAttribute", "uptr", hWnd, "uint", DWMWA_CLOAKED, "uint*", cloaked, "uint", 4)
   ; If (cloaked = DWM_CLOAKED_SHELL)
   ; return
   If (realHwnd(DllCall("GetAncestor", "uptr", hwnd, "uint", GA_PARENT, "ptr")) != realHwnd(DllCall("GetDesktopWindow", "ptr")))
      return
   WinGetClass, winClass, ahk_id %hWnd%
   If (winClass = "Windows.UI.Core.CoreWindow")
      return
   If (winClass = "ApplicationFrameWindow")
   {
      varsetcapacity(ApplicationViewCloakType, 4, 0)
      DllCall("EnumPropsEx", "uptr", hWnd, "ptr", PropEnumProcEx, "ptr", &ApplicationViewCloakType)
      If (numget(ApplicationViewCloakType, 0, "int") = 1)   ; https://github.com/kvakulo/Switcheroo/commit/fa526606d52d5ba066ba0b2b5aa83ed04741390f
         return
   }
   ; If !DllCall("MonitorFromWindow", "uptr", hwnd, "uint", MONITOR_DEFAULTTONULL, "ptr")   ; test If window is shown on any monitor. alt-tab shows any window even If window is out of monitor.
   ;   return
   WinGet, exStyles, ExStyle, ahk_id %hWnd%
   If (exStyles & WS_EX_APPWINDOW)
   {
      If DllCall("GetProp", "uptr", hWnd, "str", "ITaskList_Deleted", "ptr")
         return
      If (VirtualDesktopExist == 0) or IsWindowOnCurrentVirtualDesktop(hwnd)
         return true
      else If (VD.getDesktopNumOfWindow(tit) > 0)
            return true
      else
         return
   }
   If (exStyles & WS_EX_TOOLWINDOW) or (exStyles & WS_EX_NOACTIVATE)
      return
   loop
   {
      hwndPrev := hwnd
      hwnd := DllCall("GetWindow", "uptr", hwnd, "uint", GW_OWNER, "ptr")
      If !hwnd
      {
         If DllCall("GetProp", "uptr", hwndPrev, "str", "ITaskList_Deleted", "ptr")
            return
         If (VirtualDesktopExist == 0) or IsWindowOnCurrentVirtualDesktop(hwndPrev)
            return true
         else If (VD.getDesktopNumOfWindow(tit) > 0)
            return true
         else
            return
      }
      If DllCall("IsWindowVisible", "uptr", hwnd)
         return
      WinGet, exStyles, ExStyle, ahk_id %hwnd%
      If ((exStyles & WS_EX_TOOLWINDOW) or (exStyles & WS_EX_NOACTIVATE)) and !(exStyles & WS_EX_APPWINDOW)
         return
   }
}

GetLastActivePopup(hwnd)
{
   static GA_ROOTOWNER := 3
   hwnd := DllCall("GetAncestor", "uptr", hwnd, "uint", GA_ROOTOWNER, "ptr")
   hwnd := DllCall("GetLastActivePopup", "uptr", hwnd, "ptr")
   return hwnd
}

IsWindowOnCurrentVirtualDesktop(hwnd)
{
   static IVirtualDesktopManager
   If !IVirtualDesktopManager
      IVirtualDesktopManager := ComObjCreate(CLSID_VirtualDesktopManager := "{AA509086-5CA9-4C25-8F95-589D3C07B48A}", IID_IVirtualDesktopManager := "{A5CD92FF-29BE-454C-8D04-D82879FB3F1B}")
   DllCall(NumGet(NumGet(IVirtualDesktopManager+0), 3*A_PtrSize), "ptr", IVirtualDesktopManager, "uptr", hwnd, "int*", onCurrentDesktop)   ; IsWindowOnCurrentVirtualDesktop
   return onCurrentDesktop
}

PropEnumProcEx(hWnd, lpszString, hData, dwData)
{
   If (strget(lpszString, "UTF-16") = "ApplicationViewCloakType")
   {
      numput(hData, dwData+0, 0, "int")
      return false
   }
   return true
}

realHwnd(hwnd)
{
   varsetcapacity(var, 8, 0)
   numput(hwnd, var, 0, "uint64")
   return numget(var, 0, "uint")
}


; Alt + ` - hotkey to activate NEXT Window of same type of the current App or Chrome Website Shortcut
#If !moving
RButton & LButton::
    ComboActive := True
    MouseGetPos, , , belowID
    WinGet, activeProcessName, ProcessName, ahk_id %belowID%
    WinGetTitle, FullTitle, ahk_id %belowID%
    WinGetClass, FullClass, ahk_id %belowID%
    If (activeProcessName = "chrome.exe") {
        HandleChromeWindowsWithSameTitle(FullTitle)
    } else {
        HandleWindowsWithSameProcessAndClass(activeProcessName, FullClass)
    }
    Return
#If

/* ;
*****************************
***** UTILITY FUNCTIONS *****
*****************************
*/


; Extracts the application title from the window's full title
ExtractAppTitle(FullTitle) {
    return SubStr(FullTitle, InStr(FullTitle, " ", False, -1) + 1)
}

; Switch a "Chrome App or Chrome Website Shortcut" open windows based on the same application title
HandleChromeWindowsWithSameTitle(title := "") {
    currentMon := MWAGetMonitorMouseIsIn()
    AppTitle := ExtractAppTitle(title)
    SetTitleMatchMode, 2
    ; WinGet, windowsWithSameTitleList, List, %AppTitle%
    WinGet, windowsWithSameTitleList, List, ahk_exe chrome.exe
    counter := 2
    
    numWindows := windowsWithSameTitleList
    tooltip, %numWindows% found!
    
    hwndId := windowsWithSameTitleList%counter%
    loop  {
        If !(GetFocusWindowMonitorIndex(hwndId, currentMon)) {
            counter++
            If (counter > numWindows)
            {
                counter := 1
            }
            hwndId := windowsWithSameTitleList%counter%
        }
        Else
            break
    }
    If (counter > numWindows)
    {
        counter := 1
    }
    WinActivate, % "ahk_id " windowsWithSameTitleList%counter%
    
    KeyWait, LButton, U
    
    counter++
    
    hwndId := windowsWithSameTitleList%counter%
    loop  {
        If !(GetFocusWindowMonitorIndex(hwndId, currentMon)) {
            counter++
            If (counter > numWindows)
            {
                counter := 1
            }
            hwndId := windowsWithSameTitleList%counter%
        }
        Else
            break
    }
    If (counter > numWindows)
    {
        counter := 1
    }
    loop
    {
        KeyWait, LButton, D T0.25
        If !ErrorLevel
        {
            tooltip, Windows # %counter%
            WinActivate, % "ahk_id " windowsWithSameTitleList%counter%    
            KeyWait, LButton, U T0.25
            If !ErrorLevel
            {
                counter++
                hwndId := windowsWithSameTitleList%counter%
                loop  {
                    If !(GetFocusWindowMonitorIndex(hwndId, currentMon)) {
                        counter++
                        If (counter > numWindows)
                        {
                            counter := 1
                        }
                        hwndId := windowsWithSameTitleList%counter%
                    }
                    Else
                        break
                }
                If (counter > numWindows)
                {
                    counter := 1
                }
            }
        }
    }
    until (!GetKeyState("RButton", "P"))
    tooltip,
}

; Switch "App" open windows based on the same process and class
HandleWindowsWithSameProcessAndClass(activeProcessName, activeClass) {
    currentMon := MWAGetMonitorMouseIsIn()
    WinGet, windowsListWithSameProcessAndClass, List, ahk_exe %activeProcessName% ahk_class %activeClass%
    counter := 2
    
    WinActivate, % "ahk_id " windowsListWithSameProcessAndClass%counter%
    numWindows := windowsListWithSameProcessAndClass
    
    tooltip, %numWindows% found!
    KeyWait, LButton, U
    
    counter++
    
    hwndId := windowsListWithSameProcessAndClass%counter%
    loop  {
        If !(GetFocusWindowMonitorIndex(hwndId, currentMon)) {
            counter++
            If (counter > numWindows)
            {
                counter := 1
            }
            hwndId := windowsListWithSameProcessAndClass%counter%
        }
        Else
            break
    }
    If (counter > numWindows)
    {
        counter := 1
    }
    loop
    {
        KeyWait, LButton, D T.25
        If !ErrorLevel
        {
            tooltip, Windows # %counter%
            WinActivate, % "ahk_id " windowsListWithSameProcessAndClass%counter%    
            KeyWait, LButton, U T.25
            If !ErrorLevel 
            {
                counter++
                hwndId := windowsListWithSameProcessAndClass%counter%    
                loop  {
                    If !(GetFocusWindowMonitorIndex(hwndId, currentMon)) {
                        counter++
                        If (counter > numWindows)
                        {
                            counter := 1
                        }
                        hwndId := windowsListWithSameProcessAndClass%counter%
                    }
                    Else
                        break
                }
                If (counter > numWindows)
                {
                    counter := 1
                }
            }
        }
    }
    until (!GetKeyState("RButton", "P"))
    tooltip,
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

Startup:
    Menu, Tray, Togglecheck, Run at startup
    IfExist, %A_Startup%/AutoCorrect.lnk
        FileDelete, %A_Startup%/AutoCorrect.lnk
    else FileCreateShortcut, % H_Compiled ? A_AhkPath : A_ScriptFullPath, %A_Startup%/AutoCorrect.lnk
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

track() {
    Static x, y, lastX, lastY, lastMon, currentMon, taskview, LastActiveWinHwnd1, LastActiveWinHwnd2, LastActiveWinHwnd3, LastActiveWinHwnd4
    Static LbuttonHeld := False
    Global MonCount
    
    CoordMode Mouse
    lastX := x, lastY := y, 
    
    If (currentMon > 0)
        lastMon := currentMon
    
    MouseGetPos x, y, hwndId
    WinGetClass, classId, ahk_id %hwndId%
    WinGet, hwndId, ID, A
    currentVD := VD.getCurrentDesktopNum()
    SysGet, MonCount, MonitorCount
    
    If (currentVd < VD.getCount())
        nextVD := currentVD + 1
    Else
        nextVD := currentVD
        
    If (currentVd > 1)
        prevVD := currentVD - 1
    Else
        prevVD := currentVD    
    
    If (LbuttonHeld && !GetKeyState("Lbutton", "P"))
    {
        LbuttonHeld := False
        Send {Lbutton up}
    }
    
    If ((abs(x - lastX) > 5 || abs(y - lastY) > 5) && lastX != "") {
        moving := True
        If (classId == "CabinetWClass" || classId == "Progman" || classId == "WorkerW")
            sleep 250
        ; ToolTip Moving
    } Else {
        moving := False
        ; ToolTip
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
            && x >= A_ScreenWidth-3 && y < A_ScreenHeight-200  
            && GetKeyState("Lbutton", "P") 
            && MouseIsOverTitleBar())
    {
        KeyWait, Lbutton, T0.2
        MouseGetPos nx, ny
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
            VD.PinWindow(Title)
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
            VD.UnPinWindow(Title)
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
            && x <= 3 && y < A_ScreenHeight-200  
            && GetKeyState("Lbutton", "P") 
            && MouseIsOverTitleBar())
    {
        KeyWait, Lbutton, T0.2
        MouseGetPos nx, ny
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
           
            VD.PinWindow(Title)
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
            VD.UnPinWindow(Title)
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
    ; Else
    ; {
        ; If (MonCount == 1 && x >= A_ScreenWidth-3 && y >= A_ScreenHeight-3 )
        ; {
            ; sleep 250
            ; MouseGetPos x, y, hwndId
            ; If (x >= A_ScreenWidth-3 && y >= A_ScreenHeight-3)
            ; {   
                ; Send {LWin down}{LCtrl down}{Right}{LWin up}{LCtrl up}
                ; sleep 700
            ; }
        ; }
        ; Else If (MonCount == 1 && x <= 3 && y >= A_ScreenHeight-3 )
        ; {
            ; sleep 250
            ; MouseGetPos x, y, hwndId
            ; If (x <= 3 && y >= A_ScreenHeight-3)
            ; {
                ; Send {LWin down}{LCtrl down}{Left}{LWin up}{LCtrl up}
                ; sleep 700
            ; }
        ; }
    ; }
    
    If (MonCount == 1 &&  x > 3 && y > 3 && x < A_ScreenWidth-3 && y < A_ScreenHeight-3)
    {
        taskview := False
        skipCheck := False
    }
    
    If (MonCount > 1) {
        currentMon := MWAGetMonitorMouseIsIn(40)
        If (currentMon > 0) {
            currentMonHasActWin := GetFocusWindowMonitorIndex(hwndId, currentMon)
            
            If (currentMon == 1 && currentMonHasActWin && IsAltTabWindow(hwndId)) {
                LastActiveWinHwnd1 := hwndId
            }
            Else If (currentMon == 2 && currentMonHasActWin && IsAltTabWindow(hwndId)) {
                LastActiveWinHwnd2 := hwndId
            }
            Else If (currentMon == 3 && currentMonHasActWin && IsAltTabWindow(hwndId)) {
                LastActiveWinHwnd3 := hwndId
            }
            Else If (currentMon == 4 && currentMonHasActWin && IsAltTabWindow(hwndId)) {
                LastActiveWinHwnd4 := hwndId
            }
            
            LastActiveWinHwnd := LastActiveWinHwnd%currentMon%
            WinGet, State, MinMax, ahk_id %LastActiveWinHwnd%
            ; tooltip, %LastActiveWinHwnd% "-" %hwndId%
            If (lastMon != currentMon 
                && WinExist("ahk_id " . LastActiveWinHwnd) 
                && State != -1 
                && !GetKeyState("Lbutton", "P")) {
                    WinActivate, ahk_id %LastActiveWinHwnd%
                    GoSub, DrawRect
                    GoSub, ClearRect
                    Gui, GUI4Boarder: Hide
                }
        }
    }
}

;https://www.autohotkey.com/boards/search.php?author_id=139004&sr=posts&sid=13343c88f1a3953143867b71b22fdafc
MouseIsOverTitleBar() {
    CoordMode, Mouse, Screen 
    MouseGetPos, xPos, yPos, WindowUnderMouseID
    WinGetClass, class, ahk_id %WindowUnderMouseID%
    SendMessage, 0x84, , ( yPos << 16 )|xPos, , ahk_id %WindowUnderMouseID%
    return (class <> "Shell_TrayWnd") && (ErrorLevel = 2)
}

;https://stackoverflow.com/questions/59883798/determine-which-monitor-the-focus-window-is-on
GetFocusWindowMonitorIndex(thisWindowHwnd, currentMonNum := 0) {
    WinGet, state, MinMax, ahk_id %thisWindowHwnd% 
    If (state == -1)
        return True
    
    ;Get number of monitor
    SysGet, monCount, MonitorCount
    
    ;Iterate through each monitor
    Loop %monCount%{
        Critical, On
        ;Get Monitor working area
        SysGet, workArea, Monitor, % A_Index
        
        ;Get the position of the focus window
        WinGetPos, X, Y, W, , ahk_id %thisWindowHwnd%
        X += floor(W/2)
        Y += 8
        ;Check If the focus window in on the current monitor index
        If ((A_Index == currentMonNum) && (X >= workAreaLeft && X < workAreaRight && Y >= workAreaTop && Y < workAreaBottom )){
            ; tooltip, %X%  %Y% %workAreaLeft% %workAreaTop% %workAreaBottom% %workAreaRight%
            ;Return the monitor index since it's within that monitors borders.
            ; return % A_Index
            Critical, Off
            return True
        }
    }
    Critical, Off
    return False
}

;https://www.autohotkey.com/boards/viewtopic.php?f=6&t=54557
MWAGetMonitorMouseIsIn(buffer := 0) ; we didn't actually need the "Monitor = 0"
{
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
            ActiveMon := A_Index
            break
        }
    }
    return ActiveMon
}


join( strArray )
{
  s := ""
  for i,v in strArray
    s .= ", " . v
  return substr(s, 3)
}

ShellMessage( wParam,lParam )
{
    Global nil, lastWinMinHwndId, PrevActiveWindows, VD, MonCount
    If (wParam == 5)  ;HSHELL_GETMINRECT
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
    If (wParam=1) ;  HSHELL_WINDOWCREATED := 1
     {
         ID:=lParam
         WinGetTitle, title, Ahk_id %ID%
         WinGet, procStr, ProcessName, Ahk_id %ID%
         WinGet, hwndID, ID, Ahk_id %ID%
         WinGetClass, classStr, Ahk_id %ID%
         If (IsAltTabWindow(hwndID) || (procStr == "OUTLOOK.EXE" && classStr == "#32770")) {
             If (MonCount > 1) {
                 PrevActiveWindows.push(hwndID)
             }
             Else If (MonCount == 1) {
                 Return
             }
             
             WinGet, state, MinMax, Ahk_id %ID%
             If (state > -1) {
                 desknum := VD.getDesktopNumOfWindow(title)
                 If (desknum == VD.getCurrentDesktopNum()) {
                     If desknum <= 0
                         Return
                         currentMon := MWAGetMonitorMouseIsIn()
                         currentMonHasActWin := GetFocusWindowMonitorIndex(hwndId, currentMon)
                         If !currentMonHasActWin {
                             WinActivate, Ahk_id %ID%
                             Send, {LWin down}{LShift down}{Left}{LShift up}{LWin up}
                     }
                 }
             }
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

HasVal(haystack, needle) {
    If !(IsObject(haystack)) || (haystack.Length() = 0)
        return 0
    for index, value in haystack
        If (value = needle)
            return index
    return 0
}
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
; * 20150906: The "dwmapi\DwmGetWindowAttribute" function can return odd errors
;   if DWM is not enabled.  One error I've discovered is a return code of
;   0x80070006 with a last error code of 6, i.e. ERROR_INVALID_HANDLE or "The
;   handle is invalid."  To keep the function operational during this types of
;   conditions, the function has been modified to assume that all unexpected
;   return codes mean that DWM is not available and continue to process without
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
; AUto-COrrect TWo COnsecutive CApitals.
; Disabled by default to prevent unwanted corrections such as IfEqual->Ifequal.
; To enable it, remove the /*..*/ symbols around it.
; From Laszlo's script at http://www.autohotkey.com/forum/topic9689.html
;------------------------------------------------------------------------------

; The first line of code below is the set of letters, digits, and/or symbols
; that are eligible for this type of correction.  Customize If you wish:
/*
keys = abcdefghijklmnopqrstuvwxyz
Loop Parse, keys
    HotKey ~+%A_LoopField%, Hoty
Hoty:
    CapCount := SubStr(A_PriorHotKey,2,1)="+" && A_TimeSincePriorHotkey<999 ? CapCount+1 : 1
    If CapCount = 2
        SendInput % "{BS}" . SubStr(A_ThisHotKey,3,1)
    else If CapCount = 3
        SendInput % "{Left}{BS}+" . SubStr(A_PriorHotKey,3,1) . "{Right}"
Return
*/


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
        ; return
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
        ; return
    ; ; Otherwise, add the hotstring and reload the script:
    ; FileAppend, `n%Hotstring%, %A_ScriptFullPath%  ; Put a `n at the beginning in case file lacks a blank line at its end.
    ; ; it would be best If it overwrote the string you had highlighted with the replacement you just typed in
    ; Reload
    ; Sleep 3000 ; If successful, the reload will close this instance during the Sleep, so the line below will never be reached.
    ; MsgBox, 4,, The hotstring just added appears to be improperly formatted.  Would you like to open the script for editing? Note that the bad hotstring is at the bottom of the script.
    ; IfMsgBox, Yes, Edit
    ; return

; MoveCaret:
    ; IfWinNotActive, New Hotstring
        ; return
    ; ; Otherwise, move the InputBox's insertion point to where the user will type the abbreviation.
    ; Send {HOME}
    ; Loop % StrLen(Hotstring) + 4
        ; SendInput {Right}e
    ; SetTimer, MoveCaret, Off
; return

#If !WinActive("ahk_exe notepad++.exe") 
        && !WinActive("ahk_exe Code.exe") 
        && !WinActive("ahk_exe cmd.exe") 
        && !WinActive("ahk_exe Everything.exe") 
        && !WinActive("ahk_exe Conhost.exe") 
        && !WinActive("ahk_exe bash.exe") 
        && !WinActive("ahk_exe mintty.exe")
        && !SearchingWindows
        && !hitCAPS
        && !hitTAB
        && !GetKeyState("LAlt","P")
        
#Hotstring EndChars ()[]{};"/\,?!`n `t
#Hotstring R  ; Set the default to be "raw mode" (might not actually be relied upon by anything yet).
;------------------------------------------------------------------------------
; Fix for -ign instead of -ing.
; Words to exclude: (could probably do this by return without rewrite)
; From: http://www.morewords.com/e nds-with/gn/
;------------------------------------------------------------------------------
#Hotstring B0  ; Turns off automatic backspacing for the following hotstrings.
; Can be suffix exceptions, too, but should correct "-aling" without correcting "-align".
::align::
::antiforeign::
::arraign::
::assign::
::benign::
:?:campaign:: ; covers "countercampaign". no such words as -campaing
::champaign::
::codesign::
::coign::
::condign::
::consign::
::coreign::
::cosign::
;::countercampaign::
::countersign::
::deign::
::deraign::
::design::
::digidesign:: ; Company name
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
:*:hm::
::ugh::
:*:ugh::
::ggi::
:?*:_::
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
;------------------------------------------------------------------------------
; Special Exceptions - File Types
;------------------------------------------------------------------------------
:?:.org::
:?:.com::
:?:.net::
:?:.txt::
:?:.aif::
:?:.cda::
:?:.mid::
:?:.mp3::
:?:.mpa::
:?:.ogg::
:?:.wav::
:?:.wma::
:?:.wpl::
:?:.7z ::
:?:.arj::
:?:.deb::
:?:.pkg::
:?:.rar::
:?:.rpm::
:?:.tar.gz::
:?:.z::
:?:.zip::
:?:.bin::
:?:.dmg::
:?:.iso::
:?:.toast::
:?:.vcd::
:?:.csv::
:?:.dat::
:?:.db::
:?:.log::
:?:.mdb::
:?:.sav::
:?:.sql::
:?:.tar::
:?:.xml::
:?:.email::
:?:.eml::
:?:.emlx::
:?:.msg::
:?:.oft::
:?:.ost::
:?:.pst::
:?:.vcf::
:?:.apk::
:?:.bat::
:?:.bin::
:?:.cgi::
:?:.com::
:?:.exe::
:?:.elf::
:?:.gadget::
:?:.jar::
:?:.msi::
:?:.py::
:?:.wsf::
:?:.fnt::
:?:.fon::
:?:.otf::
:?:.ttf::
:?:.ai::
:?:.bmp::
:?:.gif::
:?:.ico::
:?:.jpeg::
:?:.png::
:?:.ps::
:?:.psd::
:?:.svg::
:?:.tif::
:?:.webp::
:?:.asp::
:?:.cer::
:?:.cfm::
:?:.cgi::
:?:.css::
:?:.htm::
:?:.js::
:?:.jsp::
:?:.part::
:?:.php::
:?:.py::
:?:.rss::
:?:.pri::
:?:.xhtml::
:?:.key::
:?:.odp::
:?:.pps::
:?:.ppt::
:?:.pptx::
:?:.c::
:?:.cgi::
:?:.class::
:?:.cpp::
:?:.cs::
:?:.h::
:?:.java::
:?:.php::
:?:.py::
:?:.sh::
:?:.swift::
:?:.vb::
:?:.ods::
:?:.xls::
:?:.xlsm::
:?:.xlsx::
:?:.bak::
:?:.cab::
:?:.cfg::
:?:.cpl::
:?:.cur::
:?:.dll::
:?:.dmp::
:?:.drv::
:?:.icns::
:?:.ico::
:?:.ini::
:?:.lnk::
:?:.msi::
:?:.sys::
:?:.tmp::
:?:.3g2::
:?:.3gp::
:?:.avi::
:?:.flv::
:?:.h264::
:?:.m4v::
:?:.mkv::
:?:.mov::
:?:.mp4::
:?:.mpg::
:?:.rm::
:?:.swf::
:?:.vob::
:?:.webm::
:?:.wmv::
:?:.doc::
:?:.odt::
:?:.pdf::
:?:.rtf::
:?:.tex::
:?:.txt::
:?:.wpd::
:?:.json::
return  ; This makes the above hotstrings do nothing so that they override the ign->ing rule below.

#Hotstring B T C k-1 ; Set the default to be "raw mode" (might not actually be relied upon by anything yet).; Turn back on automatic backspacing for all subsequent hotstrings.
::vms::VMs
::VMs::VMs
::VMware::VMware
::sxe::SXe
::SXe::SXe
::ips::IPs
::IPs::IPs
::vmware::VMware
::VMware::VMware
::ie::i.e.
;------------------------------------------------------------------------------
; Word endings
;------------------------------------------------------------------------------
:?:bilites::bilities
:?:bilties::bilities
:?:blities::bilities
:?:bilty::bility
:?:blity::bility
:?:, btu::, but ; Not just replacing "btu", as that is a unit of heat.
:?:; btu::; but
:?:n;t::n't
:?:nt'::n't
:?:;ll::'ll
:?:ll'::'ll
:?:;re::'re
:?:re'::'re
:?:;ve::'ve
:?:ve'::'ve
::sice::since  ; Must precede the following line!
:?:sice::sive
;:?:t eh:: the   ; converts "but eh" to "bu the"
:?:t hem:: them
:?:toin::tion
:?:iotn::tion
:?:soin::sion
:?:aition::ation
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
:?:/::?
:?:aingin::aining
:?:ainign::aining
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
::develope::develop  ; Omit asterisk so that it doesn't disrupt the typing of developed/developer.
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
:*:isntall::install
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
:*:requirment::requirement
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
:*:tyr::try
:*:cmakel::CMakeLists.txt
:*:cmaket::CMakeLists.txt
:*:unfo::unfortunately, `
:*:Unfo::Unfortunately, `
:*:priv::privilege `
:*:envi::environment `
:*:simult::simultaneously `
;------------------------------------------------------------------------------
; Word middles
;------------------------------------------------------------------------------
:?*:compatab::compatib  ; Covers incompat* and compat*
:?*:catagor::categor  ; Covers subcatagories and catagories.
:?*:isgn::sign  ; Covers subcatagories and catagories.
:?*:sgin::sign  ; Covers subcatagories and catagories.
:?*:fortuante::fortunate  ; Covers subcatagories and catagories.
:?*:laod::load

;------------------------------------------------------------------------------
; Common Misspellings - the main list
;------------------------------------------------------------------------------
::htp:::http:
::http:\\::http://
::httpL::http:
::herf::href
::deprication::deprecation
::depricated::deprecated
::depricate::deprecate

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
::arn't::aren't
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
:c:eb::be ; EB is legit?
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
::childrens::children's
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
::company;s::company's
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
::coudln't::couldn't
::coudn't::couldn't
::couldnt::couldn't
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
::didint::didn't
::didnt::didn't
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
::doens::doesn't
::doese::does
::doe snot::does not ; *could* be legitimate... but very unlikely!
::does't::doesn't
::doest::doesn't
::doens't::doesn't
::doesnt::doesn't
::dosen't::doesn't
::doenst::doesn't
::dosn't::doesn't
::doign::doing
::doimg::doing
::doind::doing
::donig::doing
::dollers::dollars
::dominent::dominant
::dominiant::dominant
::dominaton::domination
::dno't::don't
::do'nt::don't
::dont::don't
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
::futher::further
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
::gentlemens::gentlemen's
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
:c:hda::had
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
::hasnt::hasn't
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
::here;s::here's
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
::id'::I'd
::i;d::I'd
::i"d::I'd
::i'd::I'd
::i"m::I'm
::i'm::I'm
::I"m::I'm
::im::I'm
::i"ll::I'll
::i'll::I'll
::i"ve::I've
::i've::I've
::iv'e::I've
::ive::I've
::its'::it's
::ti's::it's
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
::instaleld::installed
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
::isnt::isn't
::isnt'::isn't
::issueing::issuing
::itis::it is
::itwas::it was
::it;s::it's
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
::judgement::judgment ;  "without the -e is preferred in law globally, and in American English"
::judgements::judgments ;  "without the -e is preferred in law globally, and in American English"
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
::let;s::let's
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
; ::miliary::military ; miliary dermatitis
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
; ::originall::originally, original
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
; ::snese::sneeze ; More likely to be mistyped "sense" than misspelled "sneeze"
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
; ::strat::start   Stratocaster
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
::succesful::successful
::successfull::successful
::succsessfull::successful
::sucesful::successful
::sucessful::successful
::sucessfull::successful
::succesfully::successfully
::succesfuly::successfully
::successfuly::successfully
::successfulyl::successfully
::successully::successfully
::sucesfully::successfully
::sucesfuly::successfully
::sucessfully::successfully
::sucessfuly::successfully
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
::thast::that's
::thats::that's
::taht's::that's
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
::they;l::they'll
::theyll::they'll
::they;r::they're
::they;v::they've
::theyve::they've
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
;::thru::through       ;used as an alternate spelling in some contexts
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
::todays::today's
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
::unsuccesfully::unsuccessfully
::unsucesfuly::unsuccessfully
::unsucessfully::unsuccessfully
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
; ::wanna::want to ;INTENTIONAL
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
::wasnt::wasn't
::wya::way
::wayword::wayward
::we;d::we'd
::we;re::we're
::wer'e::we're
::w'ere::we're
::weaponary::weaponry
;::wether::weather   ; ambiguous: leave uncorrected
::wendsay::Wednesday
::wensday::Wednesday
::wiegh::weigh
::wierd::weird
::vell::well
::werre::were
::wern't::weren't
::waht::what
::whta::what
::what;s::what's
::wehn::when
::whn::when
::whent he::when the
::wehre::where
::wherre::where
::where;s::where's
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
::who;s::who's
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
;::will of::will have  ; "will of the voters"
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
::womens::women's
::wo'nt::won't
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
::owuld::would
::woudl::would
::wuould::would
::wouldbe::would be
::would of::would have
::woudln't::wouldn't
::wouldnt::wouldn't
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
::youd::you'd
::youve::you've
::yoru::your
::yuor::your
::youself::yourself
::youseff::yousef
::zeebra::zebra
::sionist::Zionist
::sionists::Zionists

;------------------------------------------------------------------------------
; Ambiguous entries.  Where desired, pick the one that's best for you, edit,
; and move into the above list or, preferably, the autocorrect user file.
;------------------------------------------------------------------------------
/*
:*:cooperat::coöperat
::(c)::©
::(r)::®
::(tm)::™
::a gogo::à gogo
::abbe::abbé
::accension::accession, ascension
::achive::achieve, archive
::achived::achieved, archived
::ackward::awkward, backward
::addres::address, adders
::adress::address, A dress
::adressing::addressing, dressing
::afair::affair, afar, Afar (African place), a fair, acronym "as far as I recall"
::affort::afford, effort
::agin::again, a gin, aging
::agina::again, angina
::ago-go::àgo-go
::aledge::allege, a ledge
::alot::a lot, allot
::alusion::allusion, illusion
::amature::armature, amateur
::anu::añu
::anual::annual, anal
::anual::annual, manual
::aparent::apparent, a parent
::apon::upon, apron
::appealling::appealing, appalling
::archaoelogy::archeology, archaeology
::archaology::archeology, archaeology
::archeaologist::archeologist, archaeologist
::archeaologists::archeologists, archaeologists
::assosication::assassination, association
::attaindre::attainder, attained
::attened::attended or attend
::baout::about, bout
::beggin::begin, begging
::behavour::behavior, behaviour
::belives::believes, beliefs
::boaut::bout, boat, about
::Bon::Bön

::assasined::assassinated ; Broken by ":*:assasin::", but no great loss.
::Bootes::Boötes
::bric-a-brac::bric-à-brac
::buring::burying, burning, burin, during
::busineses::business, businesses
::cafe::café
::calaber::caliber, calibre
::calander::calendar, calender, colander
::cancelled::canceled  ; commonwealth vs US
::cancelling::canceling  ; commonwealth vs US
::canon::cañon
::cant::cannot, can not, can't
::carcas::carcass, Caracas
::carmel::caramel, carmel-by-the-sea
::Cataline::Catiline, Catalina
::censur::censor, censure
::ceratin::certain, keratin
::cervial::cervical, servile, serval
::chasr::chaser, chase
::clera::clear, sclera
::comander::commander, commandeer
::competion::competition, completion
::continuum::continuüm
::coopt::coöpt
::coordinat::coördinat
::coorperation::cooperation, corporation
::coudl::could, cloud
::councellor::councillor, counselor, councilor
::councellors::councillors, counselors, councilors
::coururier::courier, couturier
::coverted::converted, covered, coveted
::cpoy::coy, copy
::creme::crème
::dael::deal, dial, dahl
::deram::dram, dream
::desparate::desperate, disparate
::diea::idea, die
::dieing::dying, dyeing
::diversed::diverse, diverged
::divorce::divorcé
::Dona::Doña
::doub::doubt, daub
::dyas::dryas, Dyas (Robert Dyas is a hardware chain), dais
::efford::effort, afford
::effords::efforts, affords
::eigth::eighth, eight
::electic::eclectic, electric
::electon::election, electron
::elite::élite
::emition::emission, emotion
::emminent::eminent, imminent
::empirial::empirical, imperial
::Enlish::English, enlist
::erally::orally, really
::erested::arrested, erected
::ethose::those, ethos
::etude::étude
::expose::exposé
::extint::extinct, extant
::eyar::year, eyas
::eyars::years, eyas
::eyasr::years, eyas
::fiel::feel, field, file, phial
::fiels::feels, fields, files, phials
::firts::flirts, first
::fleed::fled, freed
::fomr::from, form
::fontrier::fontier, frontier
::fro::for, to and fro, (a)fro
::futhroc::futhark, futhorc
::gae::game, Gael, gale
::gaurd::guard, gourd
::gogin::going, Gauguin
::Guaduloupe::Guadalupe, Guadeloupe
::Guadulupe::Guadalupe, Guadeloupe
::guerrila::guerilla, guerrilla
::guerrilas::guerillas, guerrillas
::haev::have, heave
::Hallowean::Hallowe'en, Halloween
::herad::heard, Hera
::housr::hours, house
::hten::then, hen, the
::htere::there, here
::humer::humor, humour
::humerous::humorous, humourous, humerus
::hvea::have, heave
::idesa::ideas, ides
::imaginery::imaginary, imagery
::imanent::eminent, imminent
::iminent::eminent, imminent, immanent
::indispensable::indispensible ; commonwealth vs US?
::indispensible::indispensable ; commonwealth vs US?
::inheritage::heritage, inheritance
::inspite::in spite, inspire
::interbread::interbreed, interbred
::intered::interred, interned
::inumerable::enumerable, innumerable
::israelies::Israelis, Israelites
::labatory::lavatory, laboratory
::labled::labelled, labeled
::lame::lamé
::leanr::lean, learn, leaner
::lible::libel, liable
::liscense::license, licence
::lisence::license, licence
::lisense::license, licence
::lonly::lonely, only
::maked::marked, made
::managable::manageable, manageably
::manoeuver::maneuver ; Commonwealth vs US?
::manouver::maneuver, manoeuvre
::manouver::manoeuvre ; Commonwealth vs US?
::manouverability::maneuverability, manoeuvrability, manoeuverability
::manouverable::maneuverable, manoeuvrable
::manouvers::maneuvers, manoeuvres
::manuever::maneuver, manoeuvre
::manuevers::maneuvers, manoeuvres
::mear::wear, mere, mare
::meranda::veranda, Miranda
::Metis::Métis
::mit::mitt, M.I.T., German "with"
::monestary::monastery, monetary
::moreso::more, more so
::muscels::mussels, muscles
::ne::né
::neice::niece, nice
::neigbour::neighbour, neighbor
::neigbouring::neighbouring, neighboring
::neigbours::neighbours, neighbors
::nto:: not ; Replaced with case sensitive for NTO acronym.
::od::do
::oging::going, ogling
::ole::olé
::onot::note, not
::opium::opïum
::ore::öre
::ore::øre
::orgin::origin, organ
::palce::place, palace
::pate::pâte
::pate::pâté
::performes::performed, performs
::personel::personnel, personal
::positon::position, positron
::preëmpt
::premiere::première
::premiered::premièred
::premieres::premières
::premiering::premièring
::procede::proceed, precede
::proceded::proceeded, preceded
::procedes::proceeds, precedes
::proceding::proceeding, preceding
::profesion::profusion, profession
::progrom::pogrom, program
::progroms::pogroms, programs
::prominately::prominently, predominately
::qtuie::quite, quiet
::qutie::quite, quiet
::reenter::reënter
::relized::realised, realized
::repatition::repetition, repartition
::residuum::residuüm
::restraunt::restraint, restaurant
::resume::résumé
::rigeur::rigueur, rigour, rigor
::role::rôle
::rose::rosé
::sasy::says, sassy
::scholarstic::scholastic, scholarly
::secceeded::seceded, succeeded
::seceed::succeed, secede
::seceeded::succeeded, seceded
::sepulchure::sepulchre, sepulcher
::sepulcre::sepulchre, sepulcher
::shamen::shaman, shamans
::sheat::sheath, sheet, cheat
::sieze::seize, size
::siezed::seized, sized
::siezing::seizing, sizing
::sinse::sines, since
::snese::sneeze, sense
::sotyr::satyr, story
::sould::could, should, sold
::speciallized::specialised, specialized
::specif::specific, specify
::spects::aspects, expects
::strat::start, strata
::stroy::story, destroy
::surley::surly, surely
::surrended::surrounded, surrendered
::thast::that, that's
::theather::theater, theatre
::ther::there, their, the
::thse::these, those
::thikning::thinking, thickening
::throught::thought, through, throughout
::tiem::time, Tim
::tiome::time, tome
::tourch::torch, touch
::transcripting::transcribing, transcription
::travelling::traveling   ; commonwealth vs US
::troups::troupes, troops
::turnk::turnkey, trunk
::uber::über
::unmanouverable::unmaneuverable, unmanoeuvrable
::unsed::used, unused, unsaid
::vigeur::vigueur, vigour, vigor
::villin::villi, villain, villein
::vistors::visitors, vistas
::wanna::want to - often deliberate
::weild::wield, wild
::wholy::wholly, holy
::wich::which, witch
::withdrawl::withdrawal, withdraw
::woulf::would, wolf
::ws::was, www.example.ws
::Yementite::Yemenite, Yemeni
:?:oology::oölogy
:?:t he:: the  ; Can't use this. Needs to be cleverer.
*/

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
; ::march::March  ; Commented out because it matches the common word "march".
::april::April
; ::may::May  ; Commented out because it matches the common word "may".
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
::repetative::repetitive
::repetetive::repetitive
::deterant::deterrent
::deterants::deterrents
::inprecise::imprecise
::woudlnt::wouldn't 
::ti::it
::god::God
::ram::RAM
::defualt::default
::rescheulde::reschedule
::mintues::minutes
::theyre::they're
::theyll::they'll
::theyd::they'd
::machien::machine
::i::I
::fo::of
::fi::If
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
::confsued::confused
::documention::documentation
::cehck::check
::instaed::instead
::confrim::confirm
::havent::haven't
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
::installa::installation
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
::wont::won't
::resovle::resolve
::cant::can't
::cant'::can't
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
::youre::you're
::your'e::you're
::youe'r::you're
::you'er::you're
::youer::you're
::yorue::you're
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
::youv'e::you've
::ahvent::haven't
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
::theres::there's
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
::woudn't::wouldn't
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
::werent::weren't
::hweover::however
::juts::just
::curiosu::curious
::dotn::don't
::simualte::simulate
::deos::does
::ot::to
::salve::slave
::hcange::change
::wuold::woyould
::hcip::chip
::hsoudl::should
::wnot::won't
::stnadard::standard
::emif::EMIF
::tahnk::thank
::evne::even
::seomthing::soemthing
::pusle::pulse
::hes::he's
::bets::best
::fpgas::FPGAs
::opinon::opinIon
::webex::WebEx
::soluations::solutions
::aprt::part
::belwo::below
::dnot::don't
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
::optino::option
::dma::DMA
::moer::more
::thoguhts::thoughts
::htme::them
::ehlp::help
::pathc::patch
::awlays::always
::youll::you'll
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
::optinos::options
::defintinon::definition
::requriements::requirements
::didtn::didn't
::contniue::continue
::resepct::respect
::fof::for
::ta::at
::quetsions::questions
::oslution::solution
::determininstic::deterministic
::Hye::Hey
::lokoing::looking
::hsan't::hasn't
::bene::been
::roled::rolled
::noe::one
::ilke::like
::oru::our
::selectino::selection
::meteing::meeting
::quetsion::question
::whats::what's
::loking::looking
::isseus::issues
::th e::the
::ucstomers::customers
::ilnks::links
::youv'e::you've
::brining::bringing
::saerch::search
::blieve::believe
::copule::couple
::hadnt::hadn't
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
::lets::let's
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
::wotn::won't
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
::ahven't::haven't
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
::youv'e::you've
::clsoe::close
::Antony::Anthony
::intenral::internal
::knowledgable::knowledgeable
::implciations::implications
::bleieve::believe
::begininning::beginning
::doestn::doesn't
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
::odnt::don't
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
::isntall::install
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
::arent::aren't
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


; custom made based on frequently used
::thena::Athena
::Ahena::Athena
::Atena::Athena
::Athna::Athena
::Athea::Athena
::Athen::Athena
::tAhena::Athena
::thAena::Athena
::theAna::Athena
::thenAa::Athena
::thenaA::Athena
::Ahtena::Athena
::Ahetna::Athena
::Ahenta::Athena
::Ahenat::Athena
::Atehna::Athena
::Atenha::Athena
::Atenah::Athena
::Athnea::Athena
::Athnae::Athena
::Athean::Athena
::Hrris::Harris
::Haris::Harris
::Harrs::Harris
::Harri::Harris
::aHrris::Harris
::arHris::Harris
::arrHis::Harris
::arriHs::Harris
::arrisH::Harris
::Hraris::Harris
::Hrrais::Harris
::Hrrias::Harris
::Hrrisa::Harris
::Harirs::Harris
::Harisr::Harris
::Harrsi::Harris
::ach::Zach
::Zch::Zach
::Zah::Zach
::Zac::Zach
::aZch::Zach
::acZh::Zach
::achZ::Zach
::Zcah::Zach
::Zcha::Zach
::Zahc::Zach
::nterrupt::interrupt
::iterrupt::interrupt
::inerrupt::interrupt
::intrrupt::interrupt
::interupt::interrupt
::interrpt::interrupt
::interrut::interrupt
::interrup::interrupt
::niterrupt::interrupt
::ntierrupt::interrupt
::nteirrupt::interrupt
::nterirupt::interrupt
::nterriupt::interrupt
::nterruipt::interrupt
::nterrupit::interrupt
::nterrupti::interrupt
::itnerrupt::interrupt
::itenrrupt::interrupt
::iternrupt::interrupt
::iterrnupt::interrupt
::iterrunpt::interrupt
::iterrupnt::interrupt
::iterruptn::interrupt
::inetrrupt::interrupt
::inertrupt::interrupt
::inerrtupt::interrupt
::inerrutpt::interrupt
::inerruptt::interrupt
::intrerupt::interrupt
::intrreupt::interrupt
::intrruept::interrupt
::intrrupet::interrupt
::intrrupte::interrupt
::interurpt::interrupt
::interuprt::interrupt
::interuptr::interrupt
::interrput::interrupt
::interrptu::interrupt
::interrutp::interrupt
::avi::Ravi
::Rvi::Ravi
::Rai::Ravi
::Rav::Ravi
::aRvi::Ravi
::avRi::Ravi
::aviR::Ravi
::Rvai::Ravi
::Rvia::Ravi
::Raiv::Ravi
::icole::Nicole
::Ncole::Nicole
::Niole::Nicole
::Nicle::Nicole
::Nicoe::Nicole
::Nicol::Nicole
::iNcole::Nicole
::icNole::Nicole
::icoNle::Nicole
::icolNe::Nicole
::icoleN::Nicole
::Nciole::Nicole
::Ncoile::Nicole
::Ncolie::Nicole
::Ncolei::Nicole
::Niocle::Nicole
::Niolce::Nicole
::Niolec::Nicole
::Nicloe::Nicole
::Nicleo::Nicole
::Nicoel::Nicole
::Gry::Gary
::Gay::Gary
::Gar::Gary
::aGry::Gary
::arGy::Gary
::aryG::Gary
::Gray::Gary
::Grya::Gary
::Gayr::Gary
::ubmodule::submodule
::sbmodule::submodule
::sumodule::submodule
::subodule::submodule
::submdule::submodule
::submoule::submodule
::submodle::submodule
::submodue::submodule
::submodul::submodule
::usbmodule::submodule
::ubsmodule::submodule
::ubmsodule::submodule
::ubmosdule::submodule
::ubmodsule::submodule
::ubmodusle::submodule
::ubmodulse::submodule
::ubmodules::submodule
::sbumodule::submodule
::sbmuodule::submodule
::sbmoudule::submodule
::sbmoduule::submodule
::sumbodule::submodule
::sumobdule::submodule
::sumodbule::submodule
::sumoduble::submodule
::sumodulbe::submodule
::sumoduleb::submodule
::subomdule::submodule
::subodmule::submodule
::subodumle::submodule
::subodulme::submodule
::subodulem::submodule
::submdoule::submodule
::submduole::submodule
::submduloe::submodule
::submduleo::submodule
::submoudle::submodule
::submoulde::submodule
::submouled::submodule
::submodlue::submodule
::submodleu::submodule
::submoduel::submodule
::eatrice::Beatrice
::Batrice::Beatrice
::Betrice::Beatrice
::Bearice::Beatrice
::Beatice::Beatrice
::Beatrce::Beatrice
::Beatrie::Beatrice
::Beatric::Beatrice
::eBatrice::Beatrice
::eaBtrice::Beatrice
::eatBrice::Beatrice
::eatrBice::Beatrice
::eatriBce::Beatrice
::eatricBe::Beatrice
::eatriceB::Beatrice
::Baetrice::Beatrice
::Baterice::Beatrice
::Batreice::Beatrice
::Batriece::Beatrice
::Batricee::Beatrice
::Betarice::Beatrice
::Betraice::Beatrice
::Betriace::Beatrice
::Betricae::Beatrice
::Betricea::Beatrice
::Beartice::Beatrice
::Bearitce::Beatrice
::Bearicte::Beatrice
::Bearicet::Beatrice
::Beatirce::Beatrice
::Beaticre::Beatrice
::Beaticer::Beatrice
::Beatrcie::Beatrice
::Beatrcei::Beatrice
::Beatriec::Beatrice
::Jke::Jake
::Jae::Jake
::Jak::Jake
::aJke::Jake
::akJe::Jake
::akeJ::Jake
::Jkae::Jake
::Jkea::Jake
::Jaek::Jake
::ahena::athena
::atena::athena
::athna::athena
::athea::athena
::athen::athena
::tahena::athena
::thaena::athena
::theana::athena
::thenaa::athena
::ahtena::athena
::ahetna::athena
::ahenta::athena
::ahenat::athena
::atehna::athena
::atenha::athena
::atenah::athena
::athnea::athena
::athnae::athena
::athean::athena
::Dve::Dave
::Dae::Dave
::Dav::Dave
::aDve::Dave
::avDe::Dave
::aveD::Dave
::Dvae::Dave
::Dvea::Dave
::Daev::Dave
::Mke::Mike
::Mie::Mike
::Mik::Mike
::iMke::Mike
::ikMe::Mike
::ikeM::Mike
::Mkie::Mike
::Mkei::Mike
::Miek::Mike
::Jmie::Jamie
::Jaie::Jamie
::Jame::Jamie
::Jami::Jamie
::aJmie::Jamie
::amJie::Jamie
::amiJe::Jamie
::amieJ::Jamie
::Jmaie::Jamie
::Jmiae::Jamie
::Jmiea::Jamie
::Jaime::Jamie
::Jaiem::Jamie
::Jamei::Jamie
::otepad::notepad
::ntepad::notepad
::noepad::notepad
::notpad::notepad
::notead::notepad
::notepd::notepad
::notepa::notepad
::ontepad::notepad
::otnepad::notepad
::otenpad::notepad
::otepnad::notepad
::otepand::notepad
::otepadn::notepad
::ntoepad::notepad
::nteopad::notepad
::ntepoad::notepad
::ntepaod::notepad
::ntepado::notepad
::noetpad::notepad
::noeptad::notepad
::noepatd::notepad
::noepadt::notepad
::notpead::notepad
::notpaed::notepad
::notpade::notepad
::noteapd::notepad
::noteadp::notepad
::notepda::notepad
::onfluence::confluence
::cnfluence::confluence
::cofluence::confluence
::conluence::confluence
::confuence::confluence
::conflence::confluence
::conflunce::confluence
::confluece::confluence
::confluene::confluence
::confluenc::confluence
::ocnfluence::confluence
::oncfluence::confluence
::onfcluence::confluence
::onflcuence::confluence
::onflucence::confluence
::onfluecnce::confluence
::onfluencce::confluence
::cnofluence::confluence
::cnfoluence::confluence
::cnflouence::confluence
::cnfluoence::confluence
::cnflueonce::confluence
::cnfluenoce::confluence
::cnfluencoe::confluence
::cnfluenceo::confluence
::cofnluence::confluence
::coflnuence::confluence
::coflunence::confluence
::cofluennce::confluence
::conlfuence::confluence
::conlufence::confluence
::conluefnce::confluence
::conluenfce::confluence
::conluencfe::confluence
::conluencef::confluence
::confulence::confluence
::confuelnce::confluence
::confuenlce::confluence
::confuencle::confluence
::confuencel::confluence
::confleunce::confluence
::conflenuce::confluence
::conflencue::confluence
::conflenceu::confluence
::conflunece::confluence
::confluncee::confluence
::confluecne::confluence
::confluecen::confluence
::confluenec::confluence
::CADApp::SCADApp
::SADApp::SCADApp
::SCDApp::SCADApp
::SCAApp::SCADApp
::SCADpp::SCADApp
::SCADAp::SCADApp
::CSADApp::SCADApp
::CASDApp::SCADApp
::CADSApp::SCADApp
::CADASpp::SCADApp
::CADApSp::SCADApp
::CADAppS::SCADApp
::SACDApp::SCADApp
::SADCApp::SCADApp
::SADACpp::SCADApp
::SADApCp::SCADApp
::SADAppC::SCADApp
::SCDAApp::SCADApp
::SCAADpp::SCADApp
::SCAApDp::SCADApp
::SCAAppD::SCADApp
::SCADpAp::SCADApp
::SCADppA::SCADApp
::lorida::Florida
::Forida::Florida
::Flrida::Florida
::Floida::Florida
::Florda::Florida
::Floria::Florida
::Florid::Florida
::lForida::Florida
::loFrida::Florida
::lorFida::Florida
::loriFda::Florida
::loridFa::Florida
::loridaF::Florida
::Folrida::Florida
::Forlida::Florida
::Forilda::Florida
::Foridla::Florida
::Foridal::Florida
::Flroida::Florida
::Flrioda::Florida
::Flridoa::Florida
::Flridao::Florida
::Floirda::Florida
::Floidra::Florida
::Floidar::Florida
::Flordia::Florida
::Flordai::Florida
::Floriad::Florida
::gmil::gmail
::gmal::gmail
::gmai::gmail
::mgail::gmail
::magil::gmail
::maigl::gmail
::mailg::gmail
::gamil::gmail
::gaiml::gmail
::gailm::gmail
::gmial::gmail
::gmila::gmail
::gmali::gmail
::itbucket::bitbucket
::btbucket::bitbucket
::bibucket::bitbucket
::bitucket::bitbucket
::bitbcket::bitbucket
::bitbuket::bitbucket
::bitbucet::bitbucket
::bitbuckt::bitbucket
::bitbucke::bitbucket
::ibtbucket::bitbucket
::itbbucket::bitbucket
::btibucket::bitbucket
::btbiucket::bitbucket
::btbuicket::bitbucket
::btbuciket::bitbucket
::btbuckiet::bitbucket
::btbuckeit::bitbucket
::btbucketi::bitbucket
::bibtucket::bitbucket
::bibutcket::bitbucket
::bibuctket::bitbucket
::bibucktet::bitbucket
::bibuckett::bitbucket
::bitubcket::bitbucket
::bitucbket::bitbucket
::bituckbet::bitbucket
::bituckebt::bitbucket
::bitucketb::bitbucket
::bitbcuket::bitbucket
::bitbckuet::bitbucket
::bitbckeut::bitbucket
::bitbcketu::bitbucket
::bitbukcet::bitbucket
::bitbukect::bitbucket
::bitbuketc::bitbucket
::bitbucekt::bitbucket
::bitbucetk::bitbucket
::bitbuckte::bitbucket
::ompilation::compilation
::cmpilation::compilation
::copilation::compilation
::comilation::compilation
::complation::compilation
::compiation::compilation
::compiltion::compilation
::compilaion::compilation
::compilaton::compilation
::compilatin::compilation
::compilatio::compilation
::ocmpilation::compilation
::omcpilation::compilation
::ompcilation::compilation
::ompiclation::compilation
::ompilcation::compilation
::ompilaction::compilation
::ompilatcion::compilation
::ompilaticon::compilation
::ompilatiocn::compilation
::ompilationc::compilation
::cmopilation::compilation
::cmpoilation::compilation
::cmpiolation::compilation
::cmpiloation::compilation
::cmpilaotion::compilation
::cmpilatoion::compilation
::cmpilatioon::compilation
::copmilation::compilation
::copimlation::compilation
::copilmation::compilation
::copilamtion::compilation
::copilatmion::compilation
::copilatimon::compilation
::copilatiomn::compilation
::copilationm::compilation
::comiplation::compilation
::comilpation::compilation
::comilaption::compilation
::comilatpion::compilation
::comilatipon::compilation
::comilatiopn::compilation
::comilationp::compilation
::compliation::compilation
::complaition::compilation
::complatiion::compilation
::compialtion::compilation
::compiatlion::compilation
::compiatilon::compilation
::compiatioln::compilation
::compiationl::compilation
::compiltaion::compilation
::compiltiaon::compilation
::compiltioan::compilation
::compiltiona::compilation
::compilaiton::compilation
::compilaiotn::compilation
::compilaiont::compilation
::compilatoin::compilation
::compilatoni::compilation
::compilatino::compilation
::bjects::objects
::ojects::objects
::obects::objects
::objcts::objects
::objecs::objects
::bojects::objects
::bjoects::objects
::bjeocts::objects
::bjecots::objects
::bjectos::objects
::bjectso::objects
::ojbects::objects
::ojebcts::objects
::ojecbts::objects
::ojectbs::objects
::ojectsb::objects
::obejcts::objects
::obecjts::objects
::obectjs::objects
::obectsj::objects
::objcets::objects
::objctes::objects
::objctse::objects
::objetcs::objects
::objetsc::objects
::objecst::objects
::truct::struct
::sruct::struct
::stuct::struct
::strct::struct
::struc::struct
::tsruct::struct
::trsuct::struct
::trusct::struct
::trucst::struct
::tructs::struct
::srtuct::struct
::srutct::struct
::sructt::struct
::sturct::struct
::stucrt::struct
::stuctr::struct
::strcut::struct
::strctu::struct
::strutc::struct
::ypedef::typedef
::tpedef::typedef
::tyedef::typedef
::typdef::typedef
::typeef::typedef
::typedf::typedef
::typede::typedef
::ytpedef::typedef
::yptedef::typedef
::ypetdef::typedef
::ypedtef::typedef
::ypedetf::typedef
::ypedeft::typedef
::tpyedef::typedef
::tpeydef::typedef
::tpedyef::typedef
::tpedeyf::typedef
::tpedefy::typedef
::tyepdef::typedef
::tyedpef::typedef
::tyedepf::typedef
::tyedefp::typedef
::typdeef::typedef
::typeedf::typedef
::typeefd::typedef
::typedfe::typedef
::Nte::Note
::Noe::Note
::oNte::Note
::otNe::Note
::oteN::Note
::Ntoe::Note
::Nteo::Note
::Noet::Note
::nterrupts::interrupts
::iterrupts::interrupts
::inerrupts::interrupts
::intrrupts::interrupts
::interupts::interrupts
::interrpts::interrupts
::interruts::interrupts
::interrups::interrupts
::niterrupts::interrupts
::ntierrupts::interrupts
::nteirrupts::interrupts
::nterirupts::interrupts
::nterriupts::interrupts
::nterruipts::interrupts
::nterrupits::interrupts
::nterruptis::interrupts
::nterruptsi::interrupts
::itnerrupts::interrupts
::itenrrupts::interrupts
::iternrupts::interrupts
::iterrnupts::interrupts
::iterrunpts::interrupts
::iterrupnts::interrupts
::iterruptns::interrupts
::iterruptsn::interrupts
::inetrrupts::interrupts
::inertrupts::interrupts
::inerrtupts::interrupts
::inerrutpts::interrupts
::inerruptts::interrupts
::intrerupts::interrupts
::intrreupts::interrupts
::intrruepts::interrupts
::intrrupets::interrupts
::intrruptes::interrupts
::intrruptse::interrupts
::interurpts::interrupts
::interuprts::interrupts
::interuptrs::interrupts
::interuptsr::interrupts
::interrputs::interrupts
::interrptus::interrupts
::interrptsu::interrupts
::interrutps::interrupts
::interrutsp::interrupts
::interrupst::interrupts
::Des::Does
::Dos::Does
::Doe::Does
::oDes::Does
::oeDs::Does
::oesD::Does
::Deos::Does
::Deso::Does
::Dose::Does
::egister::register
::rgister::register
::reister::register
::regster::register
::regiter::register
::regiser::register
::registr::register
::registe::register
::ergister::register
::egrister::register
::egirster::register
::egisrter::register
::egistrer::register
::egisterr::register
::rgeister::register
::rgiester::register
::rgiseter::register
::rgisteer::register
::reigster::register
::reisgter::register
::reistger::register
::reistegr::register
::reisterg::register
::regsiter::register
::regstier::register
::regsteir::register
::regsteri::register
::regitser::register
::regitesr::register
::regiters::register
::regisetr::register
::regisert::register
::registre::register
::thenau::athenau
::ahenau::athenau
::atenau::athenau
::athnau::athenau
::atheau::athenau
::athenu::athenau
::tahenau::athenau
::thaenau::athenau
::theanau::athenau
::thenaau::athenau
::ahtenau::athenau
::ahetnau::athenau
::ahentau::athenau
::ahenatu::athenau
::ahenaut::athenau
::atehnau::athenau
::atenhau::athenau
::atenahu::athenau
::atenauh::athenau
::athneau::athenau
::athnaeu::athenau
::athnaue::athenau
::atheanu::athenau
::atheaun::athenau
::athenua::athenau
::vFrame::AvFrame
::AFrame::AvFrame
::Avrame::AvFrame
::AvFame::AvFrame
::AvFrme::AvFrame
::AvFrae::AvFrame
::AvFram::AvFrame
::vAFrame::AvFrame
::vFArame::AvFrame
::vFrAame::AvFrame
::vFraAme::AvFrame
::vFramAe::AvFrame
::vFrameA::AvFrame
::AFvrame::AvFrame
::AFrvame::AvFrame
::AFravme::AvFrame
::AFramve::AvFrame
::AFramev::AvFrame
::AvrFame::AvFrame
::AvraFme::AvFrame
::AvramFe::AvFrame
::AvrameF::AvFrame
::AvFarme::AvFrame
::AvFamre::AvFrame
::AvFamer::AvFrame
::AvFrmae::AvFrame
::AvFrmea::AvFrame
::AvFraem::AvFrame
::thenaU::AthenaU
::AhenaU::AthenaU
::AtenaU::AthenaU
::AthnaU::AthenaU
::AtheaU::AthenaU
::AthenU::AthenaU
::tAhenaU::AthenaU
::thAenaU::AthenaU
::theAnaU::AthenaU
::thenAaU::AthenaU
::thenaAU::AthenaU
::thenaUA::AthenaU
::AhtenaU::AthenaU
::AhetnaU::AthenaU
::AhentaU::AthenaU
::AhenatU::AthenaU
::AhenaUt::AthenaU
::AtehnaU::AthenaU
::AtenhaU::AthenaU
::AtenahU::AthenaU
::AtenaUh::AthenaU
::AthneaU::AthenaU
::AthnaeU::AthenaU
::AthnaUe::AthenaU
::AtheanU::AthenaU
::AtheaUn::AthenaU
::AthenUa::AthenaU
::sbmodules::submodules
::sumodules::submodules
::subodules::submodules
::submdules::submodules
::submoules::submodules
::submodles::submodules
::submodues::submodules
::submoduls::submodules
::usbmodules::submodules
::ubsmodules::submodules
::ubmsodules::submodules
::ubmosdules::submodules
::ubmodsules::submodules
::ubmodusles::submodules
::ubmodulses::submodules
::ubmoduless::submodules
::sbumodules::submodules
::sbmuodules::submodules
::sbmoudules::submodules
::sbmoduules::submodules
::sumbodules::submodules
::sumobdules::submodules
::sumodbules::submodules
::sumodubles::submodules
::sumodulbes::submodules
::sumodulebs::submodules
::sumodulesb::submodules
::subomdules::submodules
::subodmules::submodules
::subodumles::submodules
::subodulmes::submodules
::subodulems::submodules
::subodulesm::submodules
::submdoules::submodules
::submduoles::submodules
::submduloes::submodules
::submduleos::submodules
::submduleso::submodules
::submoudles::submodules
::submouldes::submodules
::submouleds::submodules
::submoulesd::submodules
::submodlues::submodules
::submodleus::submodules
::submodlesu::submodules
::submoduels::submodules
::submoduesl::submodules
::submodulse::submodules
::onitorChannels::MonitorChannels
::MnitorChannels::MonitorChannels
::MoitorChannels::MonitorChannels
::MontorChannels::MonitorChannels
::MoniorChannels::MonitorChannels
::MonitrChannels::MonitorChannels
::MonitoChannels::MonitorChannels
::Monitorhannels::MonitorChannels
::MonitorCannels::MonitorChannels
::MonitorChnnels::MonitorChannels
::MonitorChanels::MonitorChannels
::MonitorChannls::MonitorChannels
::MonitorChannes::MonitorChannels
::MonitorChannel::MonitorChannels
::oMnitorChannels::MonitorChannels
::onMitorChannels::MonitorChannels
::oniMtorChannels::MonitorChannels
::onitMorChannels::MonitorChannels
::onitoMrChannels::MonitorChannels
::onitorMChannels::MonitorChannels
::onitorCMhannels::MonitorChannels
::onitorChMannels::MonitorChannels
::onitorChaMnnels::MonitorChannels
::onitorChanMnels::MonitorChannels
::onitorChannMels::MonitorChannels
::onitorChanneMls::MonitorChannels
::onitorChannelMs::MonitorChannels
::onitorChannelsM::MonitorChannels
::MnoitorChannels::MonitorChannels
::MniotorChannels::MonitorChannels
::MnitoorChannels::MonitorChannels
::MointorChannels::MonitorChannels
::MoitnorChannels::MonitorChannels
::MoitonrChannels::MonitorChannels
::MoitornChannels::MonitorChannels
::MoitorCnhannels::MonitorChannels
::MoitorChnannels::MonitorChannels
::MoitorChannnels::MonitorChannels
::MontiorChannels::MonitorChannels
::MontoirChannels::MonitorChannels
::MontoriChannels::MonitorChannels
::MontorCihannels::MonitorChannels
::MontorChiannels::MonitorChannels
::MontorChainnels::MonitorChannels
::MontorChaninels::MonitorChannels
::MontorChanniels::MonitorChannels
::MontorChanneils::MonitorChannels
::MontorChannelis::MonitorChannels
::MontorChannelsi::MonitorChannels
::MoniotrChannels::MonitorChannels
::MoniortChannels::MonitorChannels
::MoniorCthannels::MonitorChannels
::MoniorChtannels::MonitorChannels
::MoniorChatnnels::MonitorChannels
::MoniorChantnels::MonitorChannels
::MoniorChanntels::MonitorChannels
::MoniorChannetls::MonitorChannels
::MoniorChannelts::MonitorChannels
::MoniorChannelst::MonitorChannels
::MonitroChannels::MonitorChannels
::MonitrCohannels::MonitorChannels
::MonitrChoannels::MonitorChannels
::MonitrChaonnels::MonitorChannels
::MonitrChanonels::MonitorChannels
::MonitrChannoels::MonitorChannels
::MonitrChanneols::MonitorChannels
::MonitrChannelos::MonitorChannels
::MonitrChannelso::MonitorChannels
::MonitoCrhannels::MonitorChannels
::MonitoChrannels::MonitorChannels
::MonitoCharnnels::MonitorChannels
::MonitoChanrnels::MonitorChannels
::MonitoChannrels::MonitorChannels
::MonitoChannerls::MonitorChannels
::MonitoChannelrs::MonitorChannels
::MonitoChannelsr::MonitorChannels
::MonitorhCannels::MonitorChannels
::MonitorhaCnnels::MonitorChannels
::MonitorhanCnels::MonitorChannels
::MonitorhannCels::MonitorChannels
::MonitorhanneCls::MonitorChannels
::MonitorhannelCs::MonitorChannels
::MonitorhannelsC::MonitorChannels
::MonitorCahnnels::MonitorChannels
::MonitorCanhnels::MonitorChannels
::MonitorCannhels::MonitorChannels
::MonitorCannehls::MonitorChannels
::MonitorCannelhs::MonitorChannels
::MonitorCannelsh::MonitorChannels
::MonitorChnanels::MonitorChannels
::MonitorChnnaels::MonitorChannels
::MonitorChnneals::MonitorChannels
::MonitorChnnelas::MonitorChannels
::MonitorChnnelsa::MonitorChannels
::MonitorChanenls::MonitorChannels
::MonitorChanelns::MonitorChannels
::MonitorChanelsn::MonitorChannels
::MonitorChannles::MonitorChannels
::MonitorChannlse::MonitorChannels
::MonitorChannesl::MonitorChannels
::ulleted::bulleted
::blleted::bulleted
::buleted::bulleted
::bullted::bulleted
::bulleed::bulleted
::bulletd::bulleted
::bullete::bulleted
::ublleted::bulleted
::ulbleted::bulleted
::ullbeted::bulleted
::ullebted::bulleted
::ulletbed::bulleted
::ulletebd::bulleted
::ulletedb::bulleted
::bluleted::bulleted
::bllueted::bulleted
::blleuted::bulleted
::blletued::bulleted
::blleteud::bulleted
::blletedu::bulleted
::bulelted::bulleted
::buletled::bulleted
::buleteld::bulleted
::buletedl::bulleted
::bullteed::bulleted
::bulleetd::bulleted
::bulleedt::bulleted
::bulletde::bulleted
::efs::defs
::dfs::defs
::edfs::defs
::efds::defs
::efsd::defs
::dfes::defs
::dfse::defs
::desf::defs
::thenau_develop::athenau_develop
::ahenau_develop::athenau_develop
::atenau_develop::athenau_develop
::athnau_develop::athenau_develop
::atheau_develop::athenau_develop
::athenu_develop::athenau_develop
::athena_develop::athenau_develop
::athenaudevelop::athenau_develop
::athenau_evelop::athenau_develop
::athenau_dvelop::athenau_develop
::athenau_deelop::athenau_develop
::athenau_devlop::athenau_develop
::athenau_deveop::athenau_develop
::athenau_develp::athenau_develop
::athenau_develo::athenau_develop
::tahenau_develop::athenau_develop
::thaenau_develop::athenau_develop
::theanau_develop::athenau_develop
::thenaau_develop::athenau_develop
::ahtenau_develop::athenau_develop
::ahetnau_develop::athenau_develop
::ahentau_develop::athenau_develop
::ahenatu_develop::athenau_develop
::ahenaut_develop::athenau_develop
::ahenau_tdevelop::athenau_develop
::ahenau_dtevelop::athenau_develop
::ahenau_detvelop::athenau_develop
::ahenau_devtelop::athenau_develop
::ahenau_devetlop::athenau_develop
::ahenau_develtop::athenau_develop
::ahenau_develotp::athenau_develop
::ahenau_developt::athenau_develop
::atehnau_develop::athenau_develop
::atenhau_develop::athenau_develop
::atenahu_develop::athenau_develop
::atenauh_develop::athenau_develop
::atenau_hdevelop::athenau_develop
::atenau_dhevelop::athenau_develop
::atenau_dehvelop::athenau_develop
::atenau_devhelop::athenau_develop
::atenau_devehlop::athenau_develop
::atenau_develhop::athenau_develop
::atenau_develohp::athenau_develop
::atenau_developh::athenau_develop
::athneau_develop::athenau_develop
::athnaeu_develop::athenau_develop
::athnaue_develop::athenau_develop
::athnau_edevelop::athenau_develop
::athnau_deevelop::athenau_develop
::atheanu_develop::athenau_develop
::atheaun_develop::athenau_develop
::atheau_ndevelop::athenau_develop
::atheau_dnevelop::athenau_develop
::atheau_denvelop::athenau_develop
::atheau_devnelop::athenau_develop
::atheau_devenlop::athenau_develop
::atheau_develnop::athenau_develop
::atheau_develonp::athenau_develop
::atheau_developn::athenau_develop
::athenua_develop::athenau_develop
::athenu_adevelop::athenau_develop
::athenu_daevelop::athenau_develop
::athenu_deavelop::athenau_develop
::athenu_devaelop::athenau_develop
::athenu_devealop::athenau_develop
::athenu_develaop::athenau_develop
::athenu_develoap::athenau_develop
::athenu_developa::athenau_develop
::athena_udevelop::athenau_develop
::athena_duevelop::athenau_develop
::athena_deuvelop::athenau_develop
::athena_devuelop::athenau_develop
::athena_deveulop::athenau_develop
::athena_develuop::athenau_develop
::athena_develoup::athenau_develop
::athena_developu::athenau_develop
::athenaud_evelop::athenau_develop
::athenaude_velop::athenau_develop
::athenaudev_elop::athenau_develop
::athenaudeve_lop::athenau_develop
::athenaudevel_op::athenau_develop
::athenaudevelo_p::athenau_develop
::athenaudevelop_::athenau_develop
::athenau_edvelop::athenau_develop
::athenau_evdelop::athenau_develop
::athenau_evedlop::athenau_develop
::athenau_eveldop::athenau_develop
::athenau_evelodp::athenau_develop
::athenau_evelopd::athenau_develop
::athenau_dveelop::athenau_develop
::athenau_deevlop::athenau_develop
::athenau_deelvop::athenau_develop
::athenau_deelovp::athenau_develop
::athenau_deelopv::athenau_develop
::athenau_devleop::athenau_develop
::athenau_devloep::athenau_develop
::athenau_devlope::athenau_develop
::athenau_deveolp::athenau_develop
::athenau_deveopl::athenau_develop
::athenau_develpo::athenau_develop
::ose::Jose
::Jse::Jose
::Jos::Jose
::oJse::Jose
::osJe::Jose
::oseJ::Jose
::Jsoe::Jose
::Jseo::Jose
::Joes::Jose
::msked::masked
::maked::masked
::maskd::masked
::maske::masked
::amsked::masked
::asmked::masked
::askmed::masked
::askemd::masked
::askedm::masked
::msaked::masked
::mskaed::masked
::mskead::masked
::mskeda::masked
::maksed::masked
::makesd::masked
::makeds::masked
::masekd::masked
::masedk::masked
::maskde::masked
::reezing::freezing
::frezing::freezing
::freezng::freezing
::freezig::freezing
::freezin::freezing
::rfeezing::freezing
::refezing::freezing
::reefzing::freezing
::reezfing::freezing
::reezifng::freezing
::reezinfg::freezing
::reezingf::freezing
::ferezing::freezing
::feerzing::freezing
::feezring::freezing
::feezirng::freezing
::feezinrg::freezing
::feezingr::freezing
::frezeing::freezing
::frezieng::freezing
::frezineg::freezing
::frezinge::freezing
::freeizng::freezing
::freeinzg::freezing
::freeingz::freezing
::freeznig::freezing
::freezngi::freezing
::freezign::freezing
::orting::sorting
::srting::sorting
::soting::sorting
::sortng::sorting
::sortig::sorting
::sortin::sorting
::osrting::sorting
::orsting::sorting
::ortsing::sorting
::ortisng::sorting
::ortinsg::sorting
::ortings::sorting
::sroting::sorting
::srtoing::sorting
::srtiong::sorting
::srtinog::sorting
::srtingo::sorting
::sotring::sorting
::sotirng::sorting
::sotinrg::sorting
::sotingr::sorting
::soritng::sorting
::sorintg::sorting
::soringt::sorting
::sortnig::sorting
::sortngi::sorting
::sortign::sorting
::stro::astro
::atro::astro
::asro::astro
::asto::astro
::astr::astro
::satro::astro
::staro::astro
::strao::astro
::stroa::astro
::atsro::astro
::atrso::astro
::atros::astro
::asrto::astro
::asrot::astro
::orecfg::corecfg
::crecfg::corecfg
::coecfg::corecfg
::corcfg::corecfg
::corefg::corecfg
::corecg::corecfg
::corecf::corecfg
::ocrecfg::corecfg
::orcecfg::corecfg
::oreccfg::corecfg
::croecfg::corecfg
::creocfg::corecfg
::crecofg::corecfg
::crecfog::corecfg
::crecfgo::corecfg
::coercfg::corecfg
::coecrfg::corecfg
::coecfrg::corecfg
::coecfgr::corecfg
::corcefg::corecfg
::corcfeg::corecfg
::corcfge::corecfg
::corefcg::corecfg
::corefgc::corecfg
::corecgf::corecfg
::mplitude::amplitude
::aplitude::amplitude
::amlitude::amplitude
::ampitude::amplitude
::ampltude::amplitude
::ampliude::amplitude
::amplitde::amplitude
::amplitue::amplitude
::amplitud::amplitude
::maplitude::amplitude
::mpalitude::amplitude
::mplaitude::amplitude
::mpliatude::amplitude
::mplitaude::amplitude
::mplituade::amplitude
::mplitudae::amplitude
::mplitudea::amplitude
::apmlitude::amplitude
::aplmitude::amplitude
::aplimtude::amplitude
::aplitmude::amplitude
::aplitumde::amplitude
::aplitudme::amplitude
::aplitudem::amplitude
::amlpitude::amplitude
::amliptude::amplitude
::amlitpude::amplitude
::amlitupde::amplitude
::amlitudpe::amplitude
::amlitudep::amplitude
::ampiltude::amplitude
::ampitlude::amplitude
::ampitulde::amplitude
::ampitudle::amplitude
::ampitudel::amplitude
::ampltiude::amplitude
::ampltuide::amplitude
::ampltudie::amplitude
::ampltudei::amplitude
::ampliutde::amplitude
::ampliudte::amplitude
::ampliudet::amplitude
::amplitdue::amplitude
::amplitdeu::amplitude
::amplitued::amplitude
::ttenuation::attenuation
::atenuation::attenuation
::attnuation::attenuation
::atteuation::attenuation
::attenation::attenuation
::attenution::attenuation
::attenuaion::attenuation
::attenuaton::attenuation
::attenuatin::attenuation
::attenuatio::attenuation
::tatenuation::attenuation
::ttaenuation::attenuation
::tteanuation::attenuation
::ttenauation::attenuation
::ttenuaation::attenuation
::atetnuation::attenuation
::atentuation::attenuation
::atenutation::attenuation
::atenuattion::attenuation
::attneuation::attenuation
::attnueation::attenuation
::attnuaetion::attenuation
::attnuateion::attenuation
::attnuatieon::attenuation
::attnuatioen::attenuation
::attnuatione::attenuation
::atteunation::attenuation
::atteuantion::attenuation
::atteuatnion::attenuation
::atteuatinon::attenuation
::atteuationn::attenuation
::attenaution::attenuation
::attenatuion::attenuation
::attenatiuon::attenuation
::attenatioun::attenuation
::attenationu::attenuation
::attenutaion::attenuation
::attenutiaon::attenuation
::attenutioan::attenuation
::attenutiona::attenuation
::attenuaiton::attenuation
::attenuaiotn::attenuation
::attenuaiont::attenuation
::attenuatoin::attenuation
::attenuatoni::attenuation
::attenuatino::attenuation
::apl::aapl
::aal::aapl
::aap::aapl
::apal::aapl
::apla::aapl
::aalp::aapl
::lue::clue
::cle::clue
::clu::clue
::lcue::clue
::cule::clue
::cuel::clue
::cleu::clue
::nitial::initial
::iitial::initial
::intial::initial
::iniial::initial
::inital::initial
::initil::initial
::initia::initial
::niitial::initial
::iintial::initial
::iitnial::initial
::iitinal::initial
::iitianl::initial
::iitialn::initial
::intiial::initial
::iniital::initial
::iniiatl::initial
::iniialt::initial
::initail::initial
::initali::initial
::initila::initial
::emaphors::semaphors
::smaphors::semaphors
::seaphors::semaphors
::semphors::semaphors
::semahors::semaphors
::semapors::semaphors
::semaphrs::semaphors
::semaphos::semaphors
::semaphor::semaphors
::esmaphors::semaphors
::emsaphors::semaphors
::emasphors::semaphors
::emapshors::semaphors
::emaphsors::semaphors
::emaphosrs::semaphors
::emaphorss::semaphors
::smeaphors::semaphors
::smaephors::semaphors
::smapehors::semaphors
::smapheors::semaphors
::smaphoers::semaphors
::smaphores::semaphors
::smaphorse::semaphors
::seamphors::semaphors
::seapmhors::semaphors
::seaphmors::semaphors
::seaphomrs::semaphors
::seaphorms::semaphors
::seaphorsm::semaphors
::sempahors::semaphors
::semphaors::semaphors
::semphoars::semaphors
::semphoras::semaphors
::semphorsa::semaphors
::semahpors::semaphors
::semahoprs::semaphors
::semahorps::semaphors
::semahorsp::semaphors
::semapohrs::semaphors
::semaporhs::semaphors
::semaporsh::semaphors
::semaphros::semaphors
::semaphrso::semaphors
::semaphosr::semaphors
::ooks::looks
::loks::looks
::oloks::looks
::oolks::looks
::ookls::looks
::ooksl::looks
::lokos::looks
::lokso::looks
::loosk::looks
::eman::mean
::eamn::mean
::eanm::mean
::maen::mean
::mena::mean
::cheduled::scheduled
::sheduled::scheduled
::sceduled::scheduled
::schduled::scheduled
::schedled::scheduled
::schedued::scheduled
::scheduld::scheduled
::csheduled::scheduled
::chseduled::scheduled
::chesduled::scheduled
::chedsuled::scheduled
::chedusled::scheduled
::chedulsed::scheduled
::chedulesd::scheduled
::cheduleds::scheduled
::shceduled::scheduled
::shecduled::scheduled
::shedculed::scheduled
::sheducled::scheduled
::shedulced::scheduled
::shedulecd::scheduled
::sheduledc::scheduled
::scehduled::scheduled
::scedhuled::scheduled
::sceduhled::scheduled
::scedulhed::scheduled
::scedulehd::scheduled
::sceduledh::scheduled
::schdeuled::scheduled
::schdueled::scheduled
::schduleed::scheduled
::scheudled::scheduled
::scheulded::scheduled
::scheuledd::scheduled
::schedlued::scheduled
::schedleud::scheduled
::schedledu::scheduled
::schedueld::scheduled
::scheduedl::scheduled
::schedulde::scheduled
::Tam::Team
::Tem::Team
::Tea::Team
::eTam::Team
::eaTm::Team
::eamT::Team
::Taem::Team
::Tame::Team
::Tema::Team
::wrte::write
::wrie::write
::rwite::write
::riwte::write
::ritwe::write
::ritew::write
::wirte::write
::witre::write
::witer::write
::wrtie::write
::wrtei::write
::wriet::write
::ets::gets
::gts::gets
::ges::gets
::egts::gets
::etgs::gets
::etsg::gets
::gtes::gets
::gtse::gets
::clls::calls
::cals::calls
::aclls::calls
::alcls::calls
::allcs::calls
::allsc::calls
::clals::calls
::cllas::calls
::cllsa::calls
::calsl::calls
::uon::upon
::upn::upon
::puon::upon
::poun::upon
::ponu::upon
::uopn::upon
::uonp::upon
::upno::upon
::teir::their
::thei::their
::hteir::their
::hetir::their
::heitr::their
::heirt::their
::tehir::their
::teihr::their
::teirh::their
::thier::their
::thire::their
::theri::their
::ublic::public
::pblic::public
::pulic::public
::publc::public
::publi::public
::upblic::public
::ubplic::public
::ublpic::public
::ublipc::public
::ublicp::public
::pbulic::public
::pbluic::public
::pbliuc::public
::pblicu::public
::pulbic::public
::pulibc::public
::pulicb::public
::pubilc::public
::pubicl::public
::publci::public
::nmes::names
::naes::names
::anmes::names
::amnes::names
::nmaes::names
::nmeas::names
::nmesa::names
::naems::names
::naesm::names
::namse::names
::suff::stuff
::stff::stuff
::stuf::stuff
::tsuff::stuff
::tusff::stuff
::tufsf::stuff
::sutff::stuff
::suftf::stuff
::sufft::stuff
::stfuf::stuff
::stffu::stuff
::drvers::drivers
::drivrs::drivers
::rdivers::drivers
::ridvers::drivers
::rivders::drivers
::rivedrs::drivers
::riverds::drivers
::riversd::drivers
::dirvers::drivers
::divrers::drivers
::diverrs::drivers
::drviers::drivers
::drveirs::drivers
::drveris::drivers
::drversi::drivers
::drievrs::drivers
::driervs::drivers
::driersv::drivers
::drivres::drivers
::drivrse::drivers
::drivesr::drivers
::ernel::Kernel
::Krnel::Kernel
::Kenel::Kernel
::Kerel::Kernel
::Kernl::Kernel
::Kerne::Kernel
::eKrnel::Kernel
::erKnel::Kernel
::ernKel::Kernel
::erneKl::Kernel
::ernelK::Kernel
::Krenel::Kernel
::Krneel::Kernel
::Kenrel::Kernel
::Kenerl::Kernel
::Kenelr::Kernel
::Kerenl::Kernel
::Kereln::Kernel
::Kernle::Kernel
::cquisition::acquisition
::aquisition::acquisition
::acuisition::acquisition
::acqisition::acquisition
::acqusition::acquisition
::acquiition::acquisition
::acquistion::acquisition
::acquisiion::acquisition
::acquisiton::acquisition
::acquisitin::acquisition
::acquisitio::acquisition
::caquisition::acquisition
::cqauisition::acquisition
::cquaisition::acquisition
::cquiasition::acquisition
::cquisaition::acquisition
::cquisiation::acquisition
::cquisitaion::acquisition
::cquisitiaon::acquisition
::cquisitioan::acquisition
::cquisitiona::acquisition
::aqcuisition::acquisition
::aqucisition::acquisition
::aquicsition::acquisition
::aquiscition::acquisition
::aquisiction::acquisition
::aquisitcion::acquisition
::aquisiticon::acquisition
::aquisitiocn::acquisition
::aquisitionc::acquisition
::acuqisition::acquisition
::acuiqsition::acquisition
::acuisqition::acquisition
::acuisiqtion::acquisition
::acuisitqion::acquisition
::acuisitiqon::acquisition
::acuisitioqn::acquisition
::acuisitionq::acquisition
::acqiusition::acquisition
::acqisuition::acquisition
::acqisiution::acquisition
::acqisituion::acquisition
::acqisitiuon::acquisition
::acqisitioun::acquisition
::acqisitionu::acquisition
::acqusiition::acquisition
::acquiistion::acquisition
::acquiitsion::acquisition
::acquiitison::acquisition
::acquiitiosn::acquisition
::acquiitions::acquisition
::acquistiion::acquisition
::acquisiiton::acquisition
::acquisiiotn::acquisition
::acquisiiont::acquisition
::acquisitoin::acquisition
::acquisitoni::acquisition
::acquisitino::acquisition
::onstruction::construction
::cnstruction::construction
::costruction::construction
::contruction::construction
::consruction::construction
::constuction::construction
::constrction::construction
::constrution::construction
::construcion::construction
::constructon::construction
::constructin::construction
::constructio::construction
::ocnstruction::construction
::oncstruction::construction
::onsctruction::construction
::onstcruction::construction
::onstrcuction::construction
::onstrucction::construction
::cnostruction::construction
::cnsotruction::construction
::cnstoruction::construction
::cnstrouction::construction
::cnstruoction::construction
::cnstrucotion::construction
::cnstructoion::construction
::cnstructioon::construction
::cosntruction::construction
::costnruction::construction
::costrnuction::construction
::costrunction::construction
::costrucntion::construction
::costructnion::construction
::costructinon::construction
::costructionn::construction
::contsruction::construction
::contrsuction::construction
::contrusction::construction
::contrucstion::construction
::contructsion::construction
::contructison::construction
::contructiosn::construction
::contructions::construction
::consrtuction::construction
::consrutction::construction
::consructtion::construction
::consturction::construction
::constucrtion::construction
::constuctrion::construction
::constuctiron::construction
::constuctiorn::construction
::constuctionr::construction
::constrcution::construction
::constrctuion::construction
::constrctiuon::construction
::constrctioun::construction
::constrctionu::construction
::construtcion::construction
::construticon::construction
::construtiocn::construction
::construtionc::construction
::construciton::construction
::construciotn::construction
::construciont::construction
::constructoin::construction
::constructoni::construction
::constructino::construction
::ounds::Sounds
::Sunds::Sounds
::Sonds::Sounds
::Souds::Sounds
::Souns::Sounds
::Sound::Sounds
::oSunds::Sounds
::ouSnds::Sounds
::ounSds::Sounds
::oundSs::Sounds
::oundsS::Sounds
::Suonds::Sounds
::Sunods::Sounds
::Sundos::Sounds
::Sundso::Sounds
::Sonuds::Sounds
::Sondus::Sounds
::Sondsu::Sounds
::Soudns::Sounds
::Soudsn::Sounds
::Sounsd::Sounds
::nless::unless
::uless::unless
::uness::unless
::unlss::unless
::unles::unless
::nuless::unless
::nluess::unless
::nleuss::unless
::nlesus::unless
::nlessu::unless
::ulness::unless
::ulenss::unless
::ulesns::unless
::ulessn::unless
::unelss::unless
::unesls::unless
::unessl::unless
::unlses::unless
::unlsse::unless
::Aso::Also
::Alo::Also
::Als::Also
::lAso::Also
::lsAo::Also
::lsoA::Also
::Aslo::Also
::Asol::Also
::Alos::Also
::undle::bundle
::bndle::bundle
::budle::bundle
::bunle::bundle
::bunde::bundle
::bundl::bundle
::ubndle::bundle
::unbdle::bundle
::undble::bundle
::undlbe::bundle
::undleb::bundle
::bnudle::bundle
::bndule::bundle
::bndlue::bundle
::bndleu::bundle
::budnle::bundle
::budlne::bundle
::budlen::bundle
::bunlde::bundle
::bunled::bundle
::bundel::bundle
::rpos::repos
::reos::repos
::erpos::repos
::epros::repos
::epors::repos
::eposr::repos
::rpeos::repos
::rpoes::repos
::rpose::repos
::reops::repos
::reosp::repos
::repso::repos
::SAL::OSAL
::OAL::OSAL
::OSL::OSAL
::OSA::OSAL
::SOAL::OSAL
::SAOL::OSAL
::SALO::OSAL
::OASL::OSAL
::OALS::OSAL
::OSLA::OSAL
::ource::source
::surce::source
::sorce::source
::souce::source
::soure::source
::sourc::source
::osurce::source
::ousrce::source
::oursce::source
::ourcse::source
::ources::source
::suorce::source
::suroce::source
::surcoe::source
::surceo::source
::soruce::source
::sorcue::source
::sorceu::source
::soucre::source
::soucer::source
::sourec::source
::eferencePlatforms::ReferencePlatforms
::RferencePlatforms::ReferencePlatforms
::ReerencePlatforms::ReferencePlatforms
::RefrencePlatforms::ReferencePlatforms
::RefeencePlatforms::ReferencePlatforms
::ReferncePlatforms::ReferencePlatforms
::ReferecePlatforms::ReferencePlatforms
::ReferenePlatforms::ReferencePlatforms
::ReferencPlatforms::ReferencePlatforms
::Referencelatforms::ReferencePlatforms
::ReferencePatforms::ReferencePlatforms
::ReferencePltforms::ReferencePlatforms
::ReferencePlaforms::ReferencePlatforms
::ReferencePlatorms::ReferencePlatforms
::ReferencePlatfrms::ReferencePlatforms
::ReferencePlatfoms::ReferencePlatforms
::ReferencePlatfors::ReferencePlatforms
::ReferencePlatform::ReferencePlatforms
::eRferencePlatforms::ReferencePlatforms
::efRerencePlatforms::ReferencePlatforms
::efeRrencePlatforms::ReferencePlatforms
::eferRencePlatforms::ReferencePlatforms
::efereRncePlatforms::ReferencePlatforms
::eferenRcePlatforms::ReferencePlatforms
::eferencRePlatforms::ReferencePlatforms
::eferenceRPlatforms::ReferencePlatforms
::eferencePRlatforms::ReferencePlatforms
::eferencePlRatforms::ReferencePlatforms
::eferencePlaRtforms::ReferencePlatforms
::eferencePlatRforms::ReferencePlatforms
::eferencePlatfRorms::ReferencePlatforms
::eferencePlatfoRrms::ReferencePlatforms
::eferencePlatforRms::ReferencePlatforms
::eferencePlatformRs::ReferencePlatforms
::eferencePlatformsR::ReferencePlatforms
::RfeerencePlatforms::ReferencePlatforms
::ReefrencePlatforms::ReferencePlatforms
::ReerfencePlatforms::ReferencePlatforms
::ReerefncePlatforms::ReferencePlatforms
::ReerenfcePlatforms::ReferencePlatforms
::ReerencfePlatforms::ReferencePlatforms
::ReerencefPlatforms::ReferencePlatforms
::ReerencePflatforms::ReferencePlatforms
::ReerencePlfatforms::ReferencePlatforms
::ReerencePlaftforms::ReferencePlatforms
::ReerencePlatfforms::ReferencePlatforms
::RefreencePlatforms::ReferencePlatforms
::RefeerncePlatforms::ReferencePlatforms
::RefeenrcePlatforms::ReferencePlatforms
::RefeencrePlatforms::ReferencePlatforms
::RefeencerPlatforms::ReferencePlatforms
::RefeencePrlatforms::ReferencePlatforms
::RefeencePlratforms::ReferencePlatforms
::RefeencePlartforms::ReferencePlatforms
::RefeencePlatrforms::ReferencePlatforms
::RefeencePlatfrorms::ReferencePlatforms
::RefeencePlatforrms::ReferencePlatforms
::RefernecePlatforms::ReferencePlatforms
::RefernceePlatforms::ReferencePlatforms
::ReferecnePlatforms::ReferencePlatforms
::ReferecenPlatforms::ReferencePlatforms
::ReferecePnlatforms::ReferencePlatforms
::ReferecePlnatforms::ReferencePlatforms
::ReferecePlantforms::ReferencePlatforms
::ReferecePlatnforms::ReferencePlatforms
::ReferecePlatfnorms::ReferencePlatforms
::ReferecePlatfonrms::ReferencePlatforms
::ReferecePlatfornms::ReferencePlatforms
::ReferecePlatformns::ReferencePlatforms
::ReferecePlatformsn::ReferencePlatforms
::ReferenecPlatforms::ReferencePlatforms
::ReferenePclatforms::ReferencePlatforms
::ReferenePlcatforms::ReferencePlatforms
::ReferenePlactforms::ReferencePlatforms
::ReferenePlatcforms::ReferencePlatforms
::ReferenePlatfcorms::ReferencePlatforms
::ReferenePlatfocrms::ReferencePlatforms
::ReferenePlatforcms::ReferencePlatforms
::ReferenePlatformcs::ReferencePlatforms
::ReferenePlatformsc::ReferencePlatforms
::ReferencPelatforms::ReferencePlatforms
::ReferencPleatforms::ReferencePlatforms
::ReferencPlaetforms::ReferencePlatforms
::ReferencPlateforms::ReferencePlatforms
::ReferencPlatfeorms::ReferencePlatforms
::ReferencPlatfoerms::ReferencePlatforms
::ReferencPlatforems::ReferencePlatforms
::ReferencPlatformes::ReferencePlatforms
::ReferencPlatformse::ReferencePlatforms
::ReferencelPatforms::ReferencePlatforms
::ReferencelaPtforms::ReferencePlatforms
::ReferencelatPforms::ReferencePlatforms
::ReferencelatfPorms::ReferencePlatforms
::ReferencelatfoPrms::ReferencePlatforms
::ReferencelatforPms::ReferencePlatforms
::ReferencelatformPs::ReferencePlatforms
::ReferencelatformsP::ReferencePlatforms
::ReferencePaltforms::ReferencePlatforms
::ReferencePatlforms::ReferencePlatforms
::ReferencePatflorms::ReferencePlatforms
::ReferencePatfolrms::ReferencePlatforms
::ReferencePatforlms::ReferencePlatforms
::ReferencePatformls::ReferencePlatforms
::ReferencePatformsl::ReferencePlatforms
::ReferencePltaforms::ReferencePlatforms
::ReferencePltfaorms::ReferencePlatforms
::ReferencePltfoarms::ReferencePlatforms
::ReferencePltforams::ReferencePlatforms
::ReferencePltformas::ReferencePlatforms
::ReferencePltformsa::ReferencePlatforms
::ReferencePlaftorms::ReferencePlatforms
::ReferencePlafotrms::ReferencePlatforms
::ReferencePlafortms::ReferencePlatforms
::ReferencePlaformts::ReferencePlatforms
::ReferencePlaformst::ReferencePlatforms
::ReferencePlatofrms::ReferencePlatforms
::ReferencePlatorfms::ReferencePlatforms
::ReferencePlatormfs::ReferencePlatforms
::ReferencePlatormsf::ReferencePlatforms
::ReferencePlatfroms::ReferencePlatforms
::ReferencePlatfrmos::ReferencePlatforms
::ReferencePlatfrmso::ReferencePlatforms
::ReferencePlatfomrs::ReferencePlatforms
::ReferencePlatfomsr::ReferencePlatforms
::ReferencePlatforsm::ReferencePlatforms
::obust::robust
::rbust::robust
::robst::robust
::robut::robust
::robus::robust
::orbust::robust
::obrust::robust
::oburst::robust
::obusrt::robust
::obustr::robust
::rboust::robust
::rbuost::robust
::rbusot::robust
::rbusto::robust
::roubst::robust
::rousbt::robust
::roustb::robust
::robsut::robust
::robstu::robust
::robuts::robust
::erviceTimer::ServiceTimer
::SrviceTimer::ServiceTimer
::SeviceTimer::ServiceTimer
::SericeTimer::ServiceTimer
::ServceTimer::ServiceTimer
::ServieTimer::ServiceTimer
::ServicTimer::ServiceTimer
::Serviceimer::ServiceTimer
::ServiceTmer::ServiceTimer
::ServiceTier::ServiceTimer
::ServiceTimr::ServiceTimer
::ServiceTime::ServiceTimer
::eSrviceTimer::ServiceTimer
::erSviceTimer::ServiceTimer
::ervSiceTimer::ServiceTimer
::erviSceTimer::ServiceTimer
::ervicSeTimer::ServiceTimer
::erviceSTimer::ServiceTimer
::erviceTSimer::ServiceTimer
::erviceTiSmer::ServiceTimer
::erviceTimSer::ServiceTimer
::erviceTimeSr::ServiceTimer
::erviceTimerS::ServiceTimer
::SreviceTimer::ServiceTimer
::SrveiceTimer::ServiceTimer
::SrvieceTimer::ServiceTimer
::SrviceeTimer::ServiceTimer
::SevriceTimer::ServiceTimer
::SevirceTimer::ServiceTimer
::SevicreTimer::ServiceTimer
::SevicerTimer::ServiceTimer
::SeviceTrimer::ServiceTimer
::SeviceTirmer::ServiceTimer
::SeviceTimrer::ServiceTimer
::SeviceTimerr::ServiceTimer
::SerivceTimer::ServiceTimer
::SericveTimer::ServiceTimer
::SericevTimer::ServiceTimer
::SericeTvimer::ServiceTimer
::SericeTivmer::ServiceTimer
::SericeTimver::ServiceTimer
::SericeTimevr::ServiceTimer
::SericeTimerv::ServiceTimer
::ServcieTimer::ServiceTimer
::ServceiTimer::ServiceTimer
::ServceTiimer::ServiceTimer
::ServiecTimer::ServiceTimer
::ServieTcimer::ServiceTimer
::ServieTicmer::ServiceTimer
::ServieTimcer::ServiceTimer
::ServieTimecr::ServiceTimer
::ServieTimerc::ServiceTimer
::ServicTeimer::ServiceTimer
::ServicTiemer::ServiceTimer
::ServicTimeer::ServiceTimer
::ServiceiTmer::ServiceTimer
::ServiceimTer::ServiceTimer
::ServiceimeTr::ServiceTimer
::ServiceimerT::ServiceTimer
::ServiceTmier::ServiceTimer
::ServiceTmeir::ServiceTimer
::ServiceTmeri::ServiceTimer
::ServiceTiemr::ServiceTimer
::ServiceTierm::ServiceTimer
::ServiceTimre::ServiceTimer
::ndependence::Independence
::Idependence::Independence
::Inependence::Independence
::Indpendence::Independence
::Indeendence::Independence
::Indepndence::Independence
::Indepedence::Independence
::Indepenence::Independence
::Independnce::Independence
::Independece::Independence
::Independene::Independence
::Independenc::Independence
::nIdependence::Independence
::ndIependence::Independence
::ndeIpendence::Independence
::ndepIendence::Independence
::ndepeIndence::Independence
::ndepenIdence::Independence
::ndependIence::Independence
::ndependeInce::Independence
::ndependenIce::Independence
::ndependencIe::Independence
::ndependenceI::Independence
::Idnependence::Independence
::Idenpendence::Independence
::Idepnendence::Independence
::Idepenndence::Independence
::Inedpendence::Independence
::Inepdendence::Independence
::Inepedndence::Independence
::Inependdence::Independence
::Indpeendence::Independence
::Indeepndence::Independence
::Indeenpdence::Independence
::Indeendpence::Independence
::Indeendepnce::Independence
::Indeendenpce::Independence
::Indeendencpe::Independence
::Indeendencep::Independence
::Indepnedence::Independence
::Indepndeence::Independence
::Indepednence::Independence
::Indepedennce::Independence
::Indepenednce::Independence
::Indepenendce::Independence
::Indepenencde::Independence
::Indepenenced::Independence
::Independnece::Independence
::Independncee::Independence
::Independecne::Independence
::Independecen::Independence
::Independenec::Independence
::EVER::NEVER
::NVER::NEVER
::NEER::NEVER
::NEVR::NEVER
::NEVE::NEVER
::ENVER::NEVER
::EVNER::NEVER
::EVENR::NEVER
::EVERN::NEVER
::NVEER::NEVER
::NEEVR::NEVER
::NEERV::NEVER
::NEVRE::NEVER
::eing::being
::beng::being
::beig::being
::ebing::being
::eibng::being
::einbg::being
::eingb::being
::bieng::being
::bineg::being
::benig::being
::bengi::being
::beign::being
::rTimer::MrTimer
::MTimer::MrTimer
::Mrimer::MrTimer
::MrTmer::MrTimer
::MrTier::MrTimer
::MrTimr::MrTimer
::MrTime::MrTimer
::rMTimer::MrTimer
::rTMimer::MrTimer
::rTiMmer::MrTimer
::rTimMer::MrTimer
::rTimeMr::MrTimer
::rTimerM::MrTimer
::MTrimer::MrTimer
::MTirmer::MrTimer
::MTimrer::MrTimer
::MTimerr::MrTimer
::MriTmer::MrTimer
::MrimTer::MrTimer
::MrimeTr::MrTimer
::MrimerT::MrTimer
::MrTmier::MrTimer
::MrTmeir::MrTimer
::MrTmeri::MrTimer
::MrTiemr::MrTimer
::MrTierm::MrTimer
::MrTimre::MrTimer
::sde::side
::sie::side
::isde::side
::idse::side
::sdie::side
::sdei::side
::sied::side
::eceiver::receiver
::rceiver::receiver
::reeiver::receiver
::reciver::receiver
::recever::receiver
::receier::receiver
::receivr::receiver
::erceiver::receiver
::ecreiver::receiver
::eceriver::receiver
::eceirver::receiver
::eceivrer::receiver
::eceiverr::receiver
::rceeiver::receiver
::reeciver::receiver
::reeicver::receiver
::reeivcer::receiver
::reeivecr::receiver
::reeiverc::receiver
::reciever::receiver
::reciveer::receiver
::recevier::receiver
::receveir::receiver
::receveri::receiver
::receievr::receiver
::receierv::receiver
::receivre::receiver
#If