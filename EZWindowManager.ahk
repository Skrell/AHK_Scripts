#Include %A_ScriptDir%\UIA_Interface.ahk
#Include %A_ScriptDir%\WinGetPosEx.ahk
#NoEnv
#Persistent
#SingleInstance force
SetBatchLines, -1
SetWinDelay, -1   ; Makes the below move faster/smoother.
Thread, interrupt, 0  ; Make all threads always-interruptible.
Process, Priority,, High
#InstallKeybdHook
#InstallMouseHook
#UseHook On
SendMode, Input
SetTitleMatchMode, 2 

Wheel_disabled := false
CheckForStuck := false
TransparentValue := 120
KDE_WinUp    := 
KDE_WinLeft  := 
EWD_winId    := 
MonitorWorkArea :=
MButtonPreviousTick :=
DoubleClickTime := DllCall("GetDoubleClickTime")
LButtonPreviousTick := A_TickCount
LookForLeaveWindow := False

SysGet, MonitorWorkArea, MonitorWorkArea 
SetTimer, EmergencyFail, 1000
SetTimer, WatchMouse, 300

WindowArray := []
PeaksArray  := []
WinBackupXs := []
orgX := 0
percLeft := 1.0
edgePercentage := .04
HoveringWinHwnd := 
lastWindowPeaked := False

WatchMouse:
    MouseGetPos, mx, my, MouseWinHwnd
    
    If !LookForLeaveWindow
    {
        for idx, val in PeaksArray
        {
            If (val == ("ahk_id " . MouseWinHwnd))
            {
                winId = ahk_id %MouseWinHwnd%
                percLeft := CalculateWinScreenPercent(winId)
                ; Tooltip, %percLeft%
                ; WinSet, AlwaysOnTop, On, %winId%
                
                WinGet, winHwnd, ID, %winId%
                WinGetPosEx(winHwnd, WinX, WinY, WinW, WinH, offL, OffT, OffR, OffB)
               
                while (A_Index < 10)
                {
                    WinSet, AlwaysOnTop, On, %winId%
                }
                If (WinX < 0) && (lastWindowPeaked ||  ((mx-mxbkup) < -5)) {
                    MoveToTargetSpot(winId, 0-offL, WinX)
                    FadeToTargetTrans(winId, 255, 200)
                    LookForLeaveWindow := True
                    HoveringWinHwnd := MouseWinHwnd
                    lastWindowPeaked := True
                    Break
                }
                Else If (WinX+WinH > A_ScreenWidth) && (lastWindowPeaked ||  ((mx-mxbkup) > 5)) {
                    MoveToTargetSpot(winId, A_ScreenWidth-WinW, WinX)
                    FadeToTargetTrans(winId, 255, 200)
                    LookForLeaveWindow := True
                    HoveringWinHwnd := MouseWinHwnd
                    lastWindowPeaked := True
                    Break
                }
            }
            If idx == (PeaksArray.Length()-1)
                lastWindowPeaked := False
        }
    }
    
    If LookForLeaveWindow && HoveringWinHwnd != MouseWinHwnd
    {
        for k, v in WinBackupXs {
           If (k == HoveringWinHwnd)
           {
              sleep 400
              MouseGetPos, , , MouseTest
              If MouseTest == HoveringWinHwnd
              {
                  mxbkup := mX
                  mybkup := my
                  Return ; last chance to abandon returning window to side
              }
              
              If (percLeft >= edgePercentage) {
                  WinSet, AlwaysOnTop, Off, ahk_id %HoveringWinHwnd%
                  WinSet, Bottom, , ahk_id %HoveringWinHwnd%
              }
              orgX := WinBackupXs[HoveringWinHwnd]
              winId = ahk_id %HoveringWinHwnd%
              WinMove, %winId%,, orgX
              FadeToTargetTrans(winId, 200)
              If MouseTest != HoveringWinHwnd
              {
                 LookForLeaveWindow := False
                 mxbkup := mX
                 mybkup := my
                 Gosub,  WatchMouse ; attempt to detect movement into another peaked window ASAP
              }
              Break
           }
        }
    }
    mxbkup := mX
    mybkup := my
Return

/* ;
*****************************
***** UTILITY FUNCTIONS *****
*****************************
*/

ExtractAppTitle(FullTitle)
{   
    AppTitle := SubStr(FullTitle, InStr(FullTitle, " ", false, -1) + 1)
    Return AppTitle
}

/* ;
***********************************
***** SHORTCUTS CONFIGURATION *****
***********************************
*/

; Alt + ` -  Activate NEXT Window of same type (title checking) of the current APP
!`::
WinGet, ActiveProcess, ProcessName, A
WinGet, OpenWindowsAmount, Count, ahk_exe %ActiveProcess%
If OpenWindowsAmount = 1  ; If only one Window exist, do nothing
    Return
    
Else
    {
        WinGetTitle, FullTitle, A
        AppTitle := ExtractAppTitle(FullTitle)
        SetTitleMatchMode, 2        
        WinGet, WindowsWithSameTitleList, List, %AppTitle%
        
        If WindowsWithSameTitleList > 1 ; If several Window of same type (title checking) exist
        {
            WinActivate, % "ahk_id " WindowsWithSameTitleList%WindowsWithSameTitleList% ; Activate next Window  
        }
    }
Return

#If (Wheel_disabled)
    WheelUp::Return 
    WheelDown::Return
    *RButton::Return
    MButton & RButton::Return
    RButton & MButton::Return
#If

+WheelUp::
Send {WheelLeft}
Return

+WheelDown::
Send {WheelRight}
Return

MButton::
    CoordMode, Mouse, Screen
    MouseGetPos, MX, MY, EWD_MouseWinHwnd ; Get cursor position
    EWD_MouseX := EWD_MouseOrgX := MX 
    EWD_MouseY := EWD_MouseOrgY := MY 
    MButtonPreviousTick := A_TickCount
    EWD_winId = ahk_id %EWD_MouseWinHwnd% ; Get the active window's title
    
    WinGet, EWD_winHwnd, ID, %EWD_winId% ; Get the title's text
    WinGet, EWD_WinState, MinMax, %EWD_winId% ; Get window state
    WinGetClass, EWD_winClass, %EWD_winId%
    
    WinMoved := False
    
    If (EWD_WinState = 1)
    {
        Return
    }
    
    If (EWD_winClass = "WorkerW")
    {
        KeyWait, MButton, U
        send, {MButton}
        Return
    }
    
    WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, offL, OffT, OffR, OffB)
    ; EWD_OriginalPosX := EWD_WinX
    ; EWD_OriginalPosY := EWD_WinY
    ; W := EWD_WinW
    ; H := EWD_WinH
    
    If (EWD_MouseX < EWD_WinX + (EWD_WinW / 2))
       KDE_WinLeft := 1
    Else
       KDE_WinLeft := -1
    
    If (EWD_MouseY < EWD_WinY + (EWD_WinH / 2))
       KDE_WinUp := 1
    Else
       KDE_WinUp := -1
    ; WinGetPos, EWD_OriginalPosX, EWD_OriginalPosY,W,H, %EWD_winId% ; Get window position
    ; If (EWD_MouseOrgX > (EWD_OriginalPosX+margin) && EWD_MouseOrgX < (EWD_OriginalPosX+W-margin) && EWD_MouseOrgY > (EWD_OriginalPosY+margin) && EWD_MouseOrgY < (EWD_OriginalPosY+H-margin))
    WinActivate, ahk_id %EWD_MouseWinHwnd%
    SetTimer, EWD_WatchDrag, 15 ; Track the mouse as the user drags it.
    SetTimer, CheckforTransparent, 50
    SetTimer, WatchMouse, Off
    
    KeyWait, MButton, U
    If ((MX - EWD_MouseX) = 0 && (MY - EWD_MouseY) = 0)
    {
        WinSet, Transparent, Off, %EWD_winId%
        SetTimer, EWD_WatchDrag, Off
        SetTimer, CheckforTransparent, Off
        send, {MButton}
        SetTimer, WatchMouse, On
    }
Return 

EWD_WatchDrag:
        CoordMode, Mouse, Screen
        Wheel_disabled := true
        
        If (GetKeyState("RButton", "P"))
        {
            registerRbutton := true
        }
        Else
        {
            registerRbutton := false
        }
        
        If !(GetKeyState("MButton", "P")) { 
           SetTimer, CheckforTransparent, Off
           SetTimer, EWD_WatchDrag, Off
           Wheel_disabled := false
           perc := CalculateWinScreenPercent(EWD_winId)
           Tooltip, 
           If (perc < edgePercentage)
           {
              FadeToTargetTrans(EWD_winId, 200)
              WinSet, AlwaysOnTop, On, %EWD_winId% 
              PeaksArray.push(EWD_winId)
              WinBackupXs[EWD_MouseWinHwnd] := EWD_WinX
           }
           Else If (perc < 0.40)
           {
              FadeToTargetTrans(EWD_winId, 200)
              PeaksArray.push(EWD_winId)
              WinBackupXs[EWD_MouseWinHwnd] := EWD_WinX
           }
           Else
           {
              for idx, val in PeaksArray {
                 If (val == EWD_winId)
                 {
                     PeaksArray.remove(idx)
                     ; PeaksArray.remove(val)
                     LookForLeaveWindow := False
                     WinSet, AlwaysOnTop, off, %EWD_winId%
                     Break
                 }
              }
              for k, v in WinBackupXs {
                 If (k == EWD_MouseWinHwnd)
                 {
                     WinBackupXs.remove(k)
                     Break
                 }
              }
              
              If WinMoved
                 FadeToTargetTrans(EWD_winId, 255, 200)
           }
           SetTimer, WatchMouse, On
           Return
        }
           
        MouseGetPos, EWD_MouseX, EWD_MouseY
        If ((EWD_MouseX != EWD_MouseOrgX) || (EWD_MouseY != EWD_MouseOrgY)) && !registerRbutton
            WinMoved := true
        
        WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, offL, OffT, OffR, OffB)
        EWD_WinX := EWD_WinX-offL
        ; Otherwise, reposition the window to match the change in mouse coordinates
        ; caused by the user having dragged the mouse:
        ; winX := winW := offL := offR := 0
        ; WinGetPos, wX, wY, wW, wH, ahk_id %EWD_MouseWinHwnd%
        EWD_WinB := EWD_WinY + EWD_WinH
        EWD_WinWF := EWD_WinW + offL + offR
        ; EWD_WinH := EWD_WinH + offB
        ; ToolTip, %EWD_WinX% : %wX% : %EWD_WinW% : %wW% : %EWD_WinB% : %MonitorWorkAreaBottom%
        ; ToolTip, %wH% : %EWD_WinH% : %MonitorWorkAreaBottom%
        ; Diff :=  EWD_MouseY - EWD_MouseOrgY
        ; ToolTip, %Diff%

        If (EWD_WinH > MonitorWorkAreaBottom)
        {
            WinMove, %EWD_winId%,, , 0 , , MonitorWorkAreaBottom+offB
            EWD_WinB := MonitorWorkAreaBottom
        }
        
        If (EWD_WinY < 0)
        {
            WinMove, %EWD_winId%,,,0
            EWD_WinY := 0
        }
        
        If (EWD_WinB > MonitorWorkAreaBottom)
        {
            WinMove, %EWD_winId%,,,(MonitorWorkAreaBottom-EWD_WinH)
            EWD_WinB := MonitorWorkAreaBottom
        }
        
        If !registerRbutton
        {
            If (EWD_WinY = 0 && EWD_WinH >= (MonitorWorkAreaBottom-10) && (EWD_MouseX != EWD_MouseOrgX)) ; moving window that's height of screen
            {
                ; Tooltip, "1"
                WinMove, %EWD_winId%,, EWD_WinX + (EWD_MouseX - EWD_MouseOrgX), , , MonitorWorkAreaBottom+OffB
                MButtonPreviousTick := A_TickCount
            }
            Else If (EWD_WinB = MonitorWorkAreaBottom && (EWD_MouseY - EWD_MouseOrgY) > 0) ;moving mouse down from window touchign bottom of screen
            {
                ; Tooltip, "2"
                WinMove, %EWD_winId%,, EWD_WinX + (EWD_MouseX - EWD_MouseOrgX),
                MButtonPreviousTick := A_TickCount
            }
            Else If (EWD_WinY = 0 && (EWD_MouseY - EWD_MouseOrgY) < 0) ;moving mouse up from window touchign top of screen
            {
                ; Tooltip, "3"
                WinMove, %EWD_winId%,, EWD_WinX + (EWD_MouseX - EWD_MouseOrgX),
                MButtonPreviousTick := A_TickCount
            }
            Else If (EWD_WinY = 0 && (EWD_MouseY - EWD_MouseOrgY) > 0) ; moving mouse down from window touching top of screen
            {
                ; Tooltip, "4"
                WinMove, %EWD_winId%,, EWD_WinX + (EWD_MouseX - EWD_MouseOrgX), EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                MButtonPreviousTick := A_TickCount
            }
            Else If ((EWD_MouseX != EWD_MouseOrgX) || (EWD_MouseY != EWD_MouseOrgY))
            {
                ; Tooltip, "5"
                WinMove, %EWD_winId%,, EWD_WinX + (EWD_MouseX - EWD_MouseOrgX), EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                MButtonPreviousTick := A_TickCount
            }
        }
        Else
        {
            DiffX :=  EWD_MouseX - EWD_MouseOrgX ; Obtain an offset from the initial mouse position.
            DiffY :=  EWD_MouseY - EWD_MouseOrgY
            
            ; Tooltip, %DiffX% : %DiffY%
            ; Then, act accordinEWD_MouseOrgYg to the defined region.
            If (EWD_WinB = MonitorWorkAreaBottom && (EWD_WinH >= MonitorWorkAreaBottom)) 
            {
                WinMove, %EWD_winId%, , EWD_WinX + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      ,   ; Y of resized window
                                      , EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      ,   ; H of resized window
            }
            Else If (EWD_WinB <= MonitorWorkAreaBottom && (abs(DiffX) > abs(DiffY)))
            {
                WinMove, %EWD_winId%, , EWD_WinX + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , ; EWD_WinY +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , ; (EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
            }
            Else
            {
                WinMove, %EWD_winId%, , ;EWD_WinX + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , EWD_WinY +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , ;EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , (EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
            }
        }
        
        EWD_MouseOrgX := EWD_MouseX, EWD_MouseOrgY := EWD_MouseY ; Update for the next timer-call to this subroutine.
Return

CalculateWinScreenPercent(winId)
{
    visibleWindowArea := 0
    WinGet, EWD_winHwnd, ID, %winId%
    WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, offL, OffT, OffR, OffB)
    totalWindowArea := EWD_WinW * EWD_WinH
    
    If (EWD_WinX < 0) ; hanging over left side
        visibleWindowArea := (EWD_WinW+EWD_WinX) * EWD_WinH
    Else If ((EWD_WinX+EWD_WinW) > A_ScreenWidth)
        visibleWindowArea := (EWD_WinX-A_ScreenWidth) * EWD_WinH
    Else
        return 1.0
        
    return abs(visibleWindowArea/totalWindowArea)
}

FadeToTargetTrans(winId, targetValue := 255, startValue := 0)
{
    transIncrement := 5
    If (targetValue != 255)
    {   
        maxValue := 255
        loop % ((255 - targetValue)/transIncrement)
        {   
            sleep, 4
            maxValue := maxValue - transIncrement
            WinSet, Transparent, %maxValue%, %winId%
        }
    }
    Else
    {
        init := startValue
        loop % ((255 - startValue)/transIncrement)
        {
            sleep, 4
            init := init + transIncrement
            WinSet, Transparent, %init%, %winId%
        }
    }
   return
}

MoveToTargetSpot(winId, targetX, orgX)
{
   stringId := """ . %winId% . """
   If (targetX > orgX)
      moveIncrement := 120
   Else
      moveIncrement := -120
      
   If WinExist(winId)
   {
       loopCount := floor(abs((targetX-orgX)/moveIncrement))
       newX := orgX
       ; tooltip, %stringId% & %loopCount%
       loop % loopCount
       {   
           newX := newX + moveIncrement
           sleep, 1
           WinMove, %winId%,, newX 
       }
       WinMove, %winId%,, targetX
   }
   return
}

CheckforTransparent:
    If Wheel_disabled && WinMoved
    {
        If ((A_TickCount - MButtonPreviousTick) > 750)
        {
            WinSet, Transparent, Off, %EWD_winId%
            WinMoved := False
        }
        Else
        {
            WinSet, Transparent, %TransparentValue%, %EWD_winId%
        }
    }
Return

EmergencyFail:
    If (CheckForStuck) { 
        If ((A_TickCount - PreviousTick) >= 6000) {
            WinGet, win, list
            Loop % win
                WinSet, Transparent, Off, % "ahk_id" win%a_index%
            Reload
        }
        ; If !(GetKeyState("MButton", "P")) { 
            ; WinSet, Transparent, Off, %EWD_winId%
            ; Wheel_disabled := false
        ; }
    }
    Else
        PreviousTick := A_TickCount
Return

#If (!WinActive("ahk_exe onenotem.exe") and !WinActive("ahk_exe onenote.exe") and !WinActive("ahk_exe OUTLOOK.EXE")) and !WinActive("ahk_exe Teams.exe")
!$LButton::
$LButton::
    global HoveringWinHwnd, LookForLeaveWindow
    doubleClick := (A_TickCount - LButtonPreviousTick) < DoubleClickTime
    If (doubleClick)
    {
        SetTimer, SendCtrlAdd, -300
        sleep 35
        If !(GetKeyState("LButton", "P"))
        {
            MouseGetPos, , , ClickedWinHwnd
            SendEvent {Click}
            savedWin := False
            for idx, val in PeaksArray
            {
                If (val == ("ahk_id " . ClickedWinHwnd))
                {
                    savedWin := True
                    HoveringWinHwnd := ClickedWinHwnd
                }
            }
            Return
        }
    }
    SetTimer, ButCapture, -1    
    
    LButtonPreviousTick := A_TickCount
    
    SetTimer, WatchMouse, Off
    If !doubleClick
        sleep 35
    If (GetKeyState("LButton", "P")) 
    {
      SendEvent {LButton down}
      CheckForStuck := true
      
      KeyWait, LButton, U T5
      SendEvent {LButton Up}
      CheckForStuck := false
    }
    Else
    {
        SendEvent {Click}
    }
    
    MouseGetPos, , , ClickedWinHwnd
    savedWin := False
    for idx, val in PeaksArray
    {
        If (val == ("ahk_id " . ClickedWinHwnd))
        {
            savedWin := True
            HoveringWinHwnd := ClickedWinHwnd
        }
    }
    If !savedWin
        lastWindowPeaked := False
    SetTimer, WatchMouse, On
Return 
#IfWinNotActive

SendCtrlAdd:
    If (MouseIsOver("ahk_class CabinetWClass"))
    {
        Send ^{NumpadAdd}
        KeyWait, NumpadAdd, U
    }
Return

#If MouseIsOver("ahk_class CabinetWClass")  ; only in File Explorer's windows
$WheelDown::
$WheelUp:: ; Scroll left in File Explorer
    If (A_PriorKey = A_ThisHotkey && (A_TickCount - %A_ThisHotkey%PreviousTick) < 100)
    {
        Send {%A_ThisHotkey%}
    }
    Else
    {
        ControlFocus DirectUIHWND2, ahk_class CabinetWClass     
        ; ControlSend  ToolbarWindow321, ^{NumpadAdd}, ahk_class CabinetWClass      
        Send ^{NumpadAdd}
        %A_ThisHotkey%previousTick := A_TickCount
        Send {%A_ThisHotkey%}
    }
Return
#IfWinActive

MouseIsOver(WinTitle) {
    MouseGetPos, , , Win
    Return WinExist(WinTitle . " ahk_id " . Win)
}

;==================================================
~Esc::  ; <-- CLOSE WITH DOUBLE ESCAPE
    If (A_PriorHotkey <> A_ThisHotKey or A_TimeSincePriorHotkey > DllCall("GetDoubleClickTime"))
    {
        MouseGetPos, mousePosX, mousePosY, WindowUnderMouseID1
        KeyWait, Esc
        Return
    }
    MouseGetPos, mousePosX, mousePosY, WindowUnderMouseID2
    If (WindowUnderMouseID1 = WindowUnderMouseID2)
    {
        WinClose , ahk_id %WindowUnderMouseID2%
    }
Return

ButCapture:
{
    global WindowArray, 
    CoordMode, Mouse, Screen
    MouseGetPos, mX, mY, mHwnd, mCtrl
    WinGetClass, wClass, ahk_id %mHwnd%
    mEl := {}

    ; If (IsUIAObjSaved("ahk_id " . mHwnd))
    ; {  
        ; mEl := WindowArray["ahk_id " . mHwnd]
        ; ; Tooltip, "yep"
    ; }
    ; Else
    ; {
        ; Tooltip, "nope!"
    try {
            If (wClass == "Chrome_WidgetWin_1")
            {
                WinGetPos, X, Y, W, H, ahk_id %mHwnd%
                ; mEl        := UIA.ElementFromHandle(WinExist("ahk_id " . mHwnd), True)
                If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                    mEl        := UIA.ElementFromPoint(X+9, Y + 2)
                Else
                    mEl := WindowArray["ahk_id " . mHwnd]
                ; paneEl     := mEl.FindFirstByNameAndType("Google Chrome", "Pane")
                ; paneEl     := mEl.FindFirstByType("TitleBar")
                ; paneEl     := mEl.FindFirstByType("TitleBar")
                minimizeEl := mEl.FindFirstByNameAndType("Minimize", "Button")
                maximizeEl := mEl.FindFirstByNameAndType("Maximize", "Button")
                closeEl    := mEl.FindFirstByNameAndType("Close", "Button")
            }
            Else
            {
                If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                    mEl := UIA.ElementFromPoint(mX, mY)
                Else
                    mEl := WindowArray["ahk_id " . mHwnd]
            }

        } catch e {
            If InStr(e.Message, "0x80070005")
                Msgbox, "Try running UIAViewer with Admin privileges"
        }
    ; }
    
    ; paneEl     := mEl.FindFirstByType("TitleBar")
    ; minimizeEl := paneEl.FindFirstByNameAndType("Minimize", "Button")
    ; maximizeEl := paneEl.FindFirstByNameAndType("Maximize", "Button")
    ; closeEl    := paneEl.FindFirstByNameAndType("Close", "Button")

    WinGet, cList, ControlList, ahk_id %mHwnd%
    If InStr(cList, "Chrome_RenderWidgetHostHWND1")
        SendMessage, WM_GETOBJECT := 0x003D, 0, 1, Chrome_RenderWidgetHostHWND1, ahk_id %mHwnd%
    
    ; WinGetTitle, wTitle, ahk_id %mHwnd%
    ; WinGetPos, wX, wY, wW, wH, ahk_id %mHwnd%
    ; WinGetText, wText, ahk_id %mHwnd%
    ; WinGet, wProc, ProcessName, ahk_id %mHwnd%
    ; WinGet, wProcID, PID, ahk_id %mHwnd%
    Tooltip,

    try {     

        If (mEl.CurrentControlType = 50004) && MouseIsOver("ahk_class CabinetWClass")
        {
            SetTimer, SendCtrlAdd, -300
            Return
        }
        
        If (wClass == "Chrome_WidgetWin_1")
        {
            minimizePos := minimizeEl.GetCurrentPos()
            closePos    := closeEl.GetCurrentPos()
            If ((mx >= minimizePos.x) && (mx <= (minimizePos.x+minimizePos.w)) && (my >= minimizePos.y) && (my <= (minimizePos.y+minimizePos.h)))
                ToolTip, minimize!
            Else If ((mx >= closePos.x) && (mx <= (closePos.x+closePos.w)) && (my >= closePos.y) && (my <= (closePos.y+closePos.h)))
                ToolTip, close!
        }
        Else
        {
            If InStr(mEl.CurrentName, "Close")
            {
                Tooltip, %wClass% " close!"
            }
            Else If InStr(mEl.CurrentName, "Maximize")
            {
                Tooltip, %wClass% " maximize!"
            }
            Else If InStr(mEl.CurrentName, "Minimize")
            {
                Tooltip, %wClass% " minimize!"
            }
            
            If GetKeyState("Alt", "P")
                Tooltip, % mEl.CurrentAutomationId " : " mEl.CurrentName " : " mEl.CurrentControlType
        }
    }
Return
}

IsUIAObjSaved(idstring := "")
{
    global WindowArray
    ; Tooltip, % WindowArray.Length()
    for k, v in WindowArray {
          If (k == idstring)
            return True
    }
    return False
}
