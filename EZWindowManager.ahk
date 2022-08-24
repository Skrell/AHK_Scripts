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
CoordMode, Mouse, Screen

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
winCount := 0
winCountOld := 0

SysGet, MonitorWorkArea, MonitorWorkArea 
SetTimer, EmergencyFail, 1000, 0
SetTimer, WatchMouse, 100, 0
SetTimer, ButCapture, 35, 0
SetTimer, CheckButtonSize, 105, 0

WindowArray := []
PeaksArray  := []
WinBackupXs := []
winList     := []

percLeft := 1.0
edgePercentage := .04
HoveringWinHwnd := 
lastWindowPeaked := False
MouseMoveBuffer := 10
PrintButton := False
PossiblyChangedSize := False
mEl := {}
minimizeEl := ""
maximizeEl := ""
closeEl    := ""

AccentColorHex := GetAccentColor()
WinGet, winList, List,,,
WinGet, winCount, Count,,,
winCountOld := winCount
 
tbEl := UIA.ElementFromHandle("ahk_class Shell_TrayWnd")
 
WatchMouse:
    global LookForLeaveWindow, lastWindowPeaked, WinBackupXs
    MouseGetPos, MXw, MYw, MouseWinHwnd

    FinishedLoop := True 
    
    for idx, val in PeaksArray
    {
        If (val == ("ahk_id " . MouseWinHwnd))
        {
            ; tooltip, 1
            FinishedLoop := False
            If !LookForLeaveWindow
            {
                winId = ahk_id %MouseWinHwnd%
                percLeft := CalculateWinScreenPercent(winId)
                
                WinGet, winHwnd, ID, %winId%
                WinGetPosEx(winHwnd, WinX, WinY, WinW, WinH, offL, OffT, OffR, OffB)
               
                If (WinX < 0) && (lastWindowPeaked ||  ((MXw-MXw_bkup) < -MouseMoveBuffer/2)) {
                    WinSet, AlwaysOnTop, On, %winId%
                    SetTimer, ButCapture, Off
                    MoveToTargetSpot(winId, 0-offL, WinX)
                    FadeToTargetTrans(winId, 255, 200)
                    LookForLeaveWindow := True
                    HoveringWinHwnd := MouseWinHwnd
                    lastWindowPeaked := True
                    Break
                }
                Else If (WinX+WinH > A_ScreenWidth) && (lastWindowPeaked ||  ((MXw-MXw_bkup) > MouseMoveBuffer/2)) {
                    WinSet, AlwaysOnTop, On, %winId%
                    SetTimer, ButCapture, Off
                    MoveToTargetSpot(winId, A_ScreenWidth-WinW-OffR, WinX)
                    FadeToTargetTrans(winId, 255, 200)
                    LookForLeaveWindow := True
                    HoveringWinHwnd := MouseWinHwnd
                    lastWindowPeaked := True
                    Break
                }
            }
        }
    }
    
    If (FinishedLoop) 
    {
        ; tooltip, 2
        MXwOffset := 0
        lastWindowPeaked := False ; clearly the last loop completed and hence we weren't hovering on a peaked window
        If (MXw == 0 && MXw_bkup == 0 && MYw == MYw_bkup)
        {
            MXwOffset := -50 ; now create a large offset to see if perhaps the window we're next to offscreen is a peaked one
        }
        Else If (MXw >= (A_ScreenWidth-2) && MXw_bkup >= (A_ScreenWidth-2) && MYw == MYw_bkup)
        {
            MXwOffset := 50 ; now create a large offset to see if perhaps the window we're next to offscreen is a peaked one
        }
        
        If (MXwOffset != 0) ; so we've decided to check offscreen
        {
            for idx, val in PeaksArray
            {
                WinGet, winHwnd, ID, %val%
                WinGetPosEx(winHwnd, WinX, WinY, WinW, WinH, offL, OffT, OffR, OffB)
                If (((MXw+MXwOffset) > WinX) && (MYw > WinY) && (MYw < (WinY+WinH))) ; turns out there is an offscreen peaked window
                {
                    WinActivate, %val%
                    WinSet, AlwaysOnTop, On, %val%
                    WinSet, AlwaysOnTop, off, %val%
                    lastWindowPeaked := True
                    break
                }
             }
        }
    }
    
    If (LookForLeaveWindow && HoveringWinHwnd != MouseWinHwnd)
    {
        ; tooltip, 3
        for k, v in WinBackupXs {
           If (k == HoveringWinHwnd)
           {
              ; tooltip, 4
              winId = ahk_id %HoveringWinHwnd%
              WinGet, winHwnd, ID, %winId%
              WinGetPosEx(winHwnd, WinX, WinY, WinW, WinH, offL, OffT, OffR, OffB)
              ; Make sure we've moved the mouse outside the window we're hovering over
              If (MXw < WinX || Mxw > (WinX+WinW) || MYw < WinY || MYw > (WinY+WinH))
              {
                  ; Tooltip, %percLeft%
                  If (!lastWindowPeaked)
                  {
                     sleep 350
                  }
                  ; double check that we haven't re-entered the peaked window and hence cancel the re-hide   
                  MouseGetPos, , , MouseTest
                  If (MouseTest == HoveringWinHwnd)
                  {
                      Break
                  }
                  
                  ; If !(percLeft < edgePercentage) 
                  ; {
                      ; WinSet, AlwaysOnTop, Off, %winId%
                      ; sleep 10
                  ; }
                  ;fixes added for resizing windows while it's being peaked
                  orgX := WinBackupXs[HoveringWinHwnd]
                  newOrgX := orgX
                  
                  If PossiblyChangedSize
                  {
                      If (orgX < 0)
                        newOrgX := ((percLeft*((WinW*WinH)/WinH))-WinW)
                      Else
                        newOrgX := A_ScreenWidth-(percLeft*(WinW*WinH)/WinH)

                      WinBackupXs[HoveringWinHwnd] := newOrgX
                      PossiblyChangedSize := False
                  }

                  WinSet, Bottom, , %winId%
                  WinMove, %winId%,, newOrgX-offL
                  FadeToTargetTrans(winId, 200)
                  LookForLeaveWindow := False
                  WinSet, Bottom, , %winId%
              }
              Break
           }
        }
        SetTimer, ButCapture, On
    }
    MXw_bkup := MXw
    MYw_bkup := MYw
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

CheckButtonSize: 
    global tbEl
    SetFormat, Integer, D
    WinGet, winCount, Count,,,   ;list of windows (exclude the desktop)
    ; tooltip, %winCount%
    if (winCountOld != winCount)
    {  
        loop %winList%
        {
            winId := winList%A_Index%
            Gui, Range_%winId%_3: Destroy 
        }
        
        for winHwnd, v in WinBackupXs {
             buttonWinId = ahk_id %winHwnd%
             WinGetTitle, wTitle, %buttonWinId%
             buttonEl := tbEl.FindFirstByNameAndType(wTitle, "Button", 0x4, 2, False)
             taskButtonElPos := buttonEl.CurrentBoundingRectangle
            
             SetFormat, Integer, D
             RangeTip(taskButtonElPos.l, taskButtonElPos.t, taskButtonElPos.r-taskButtonElPos.l, taskButtonElPos.b-taskButtonElPos.t, AccentColorHex, 2, winHwnd)
          }
          WinGet, winList, List,,,
    }
    winCountOld := winCount    ;always keep up to date
Return 

MButton::
    global WinBackupXs, PeaksArray
    
    SetTimer, ButCapture, Off
    SetTimer, WatchMouse, Off
    MX := 0
    MY := 0
    EWD_MouseOrgX := 0
    EWD_MouseOrgY := 0
    EWD_MouseX := 0
    EWD_MouseY := 0
    
    MouseGetPos, EWD_MouseX, EWD_MouseY, EWD_MouseWinHwnd ; Get cursor position
    EWD_winId = ahk_id %EWD_MouseWinHwnd% ; Get the active window's title
    WinGet, EWD_winHwnd, ID, %EWD_winId% ; Get the title's text
    WinGet, EWD_WinState, MinMax, %EWD_winId% ; Get window state
    WinGetClass, EWD_winClass, %EWD_winId%
    
    EWD_MouseOrgX := EWD_MouseX 
    EWD_MouseOrgY := EWD_MouseY 
    MX := EWD_MouseX
    MY := EWD_MouseY
    MButtonPreviousTick := A_TickCount
    
    MouseMoved := False
    registerRbutton := False
    TimeSinceStop := A_TickCount
    ToggledOnTop  := False
    ChangedDims   := False
    WinLEdge    := False
    WinREdge    := False
    
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
    SetTimer, EWD_WatchDrag, 10 ; Track the mouse as the user drags it.
    SetTimer, CheckforTransparent, 50
    Wheel_disabled := true
    
    KeyWait, MButton, U
    If ((MX == EWD_MouseX) && (MY == EWD_MouseY))
    {
        ; Tooltip, here %MX% : %MY% : %EWD_MouseX% : %EWD_MouseY%
        WinSet, Transparent, Off, %EWD_winId%
        SetTimer, EWD_WatchDrag, Off
        SetTimer, CheckforTransparent, Off
        If !ToggledOnTop
            send, {MButton}
    }
    SetTimer, WatchMouse, On
    SetTimer, ButCapture, On
Return 

EWD_WatchDrag:
        If (!(GetKeyState("MButton", "P")) && !(GetKeyState("RButton", "P"))) { 
           SetTimer, CheckButtonSize, Off
           SetTimer, CheckforTransparent, Off
           SetTimer, EWD_WatchDrag, Off
           percentageLeft := CalculateWinScreenPercent(EWD_winId)
           
           Tooltip, 
           
           If (percentageLeft < 0.40)
           {
              FadeToTargetTrans(EWD_winId, 200, TransparentValue)
              PeaksArray.push(EWD_winId)
              WinBackupXs[EWD_MouseWinHwnd] := EWD_WinX
              WinGetTitle, wTitle, %EWD_winId%
              ; wTitle := """" . wTitle . """"
              buttonEl := tbEl.FindFirstByNameAndType(wTitle, "Button", 0x4, 2, False)
              taskButtonElPos := buttonEl.CurrentBoundingRectangle
              
              SetFormat, Integer, D
              RangeTip(taskButtonElPos.l, taskButtonElPos.t, taskButtonElPos.r-taskButtonElPos.l, taskButtonElPos.b-taskButtonElPos.t, AccentColorHex, 2, EWD_MouseWinHwnd)
           }
           
            ; CORRECTIONS FOR LEFT AND RIGHT EDGES OF WINDOW
            WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, offL, OffT, OffR, OffB)
            If ((EWD_WinX == 0)) ; && EWD_WinY == 0) || (EWD_WinX == 0 && EWD_WinB == MonitorWorkAreaBottom))
                WinLEdge := True
            Else If (((EWD_WinX+EWD_WinW) == A_ScreenWidth)) ;&& EWD_WinY == 0) || ((EWD_WinX+EWD_WinW) == A_ScreenWidth && EWD_WinB == MonitorWorkAreaBottom))
                WinREdge := True
            
           removePeakedWin := False

           If ((percentageLeft >= 0.40) && !WinLEdge && !WinREdge)
           {
              
              for idx, val in PeaksArray {
                 If (val == EWD_winId)
                 {
                     PeaksArray.remove(idx)
                     ; PeaksArray.remove(val)
                     LookForLeaveWindow := False
                     WinSet, AlwaysOnTop, off, %EWD_winId%
                     removePeakedWin := True
                     Break
                 }
              }
              for k, v in WinBackupXs {
                 If (k == EWD_MouseWinHwnd)
                 {
                     WinBackupXs.remove(k)
                     RangeTip(, , , , , , k)
                     removePeakedWin := True
                     Break
                 }
              }
              If MouseMoved
                FadeToTargetTrans(EWD_winId, 255, TransparentValue)
           }
           Else If ((percentageLeft >= 0.40) && (WinLEdge || WinREdge))
           {
              for k, v in WinBackupXs {
                 If (k == EWD_MouseWinHwnd)
                 {
                     tooltip, window edging!
                     LookForLeaveWindow := True
                     HoveringWinHwnd := EWD_MouseWinHwnd
                     PossiblyChangedSize := True
                     Break
                 }
              }
           }
           
           If removePeakedWin
              lastWindowPeaked := False
           
           Wheel_disabled := false
           SetTimer, ButCapture, On
           SetTimer, CheckButtonSize, On
           Return
        }
           
        MouseGetPos, EWD_MouseX, EWD_MouseY
        If (((EWD_MouseX != EWD_MouseOrgX) || (EWD_MouseY != EWD_MouseOrgY)) && !registerRbutton)
            MouseMoved := true
        
        If ((EWD_MouseX == MX) && (EWD_MouseY == MY))
        {
            If ((A_TickCount - TimeSinceStop) > 1100)
            {
                WinSet, AlwaysOnTop, toggle, %EWD_winId%
                Tooltip, Top State Toggled!
                TimeSinceStop := A_TickCount
                ToggledOnTop := True
                Return
            }
        }
        Else
        {
            TimeSinceStop := A_TickCount
        }
        
        WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, offL, OffT, OffR, OffB)
        EWD_WinXF := EWD_WinX-offL
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

        DiffX :=  EWD_MouseX - EWD_MouseOrgX ; Obtain an offset from the initial mouse position.
        DiffY :=  EWD_MouseY - EWD_MouseOrgY
        ; CORRECTIONS FOR TOP AND BOTTOM OF WINDOW
        If (EWD_WinH > MonitorWorkAreaBottom) ; fix too tall window
        {
            WinMove, %EWD_winId%,, , 0 , , MonitorWorkAreaBottom+offB
            EWD_WinB := MonitorWorkAreaBottom
        }
        Else If ((EWD_WinY+DiffY) < 0)
        {
            WinMove, %EWD_winId%,,,0
            EWD_WinY := 0
        }
        Else If ((EWD_WinB+DiffY) > MonitorWorkAreaBottom)
        {
            WinMove, %EWD_winId%,,,(MonitorWorkAreaBottom-EWD_WinH)
            EWD_WinB := MonitorWorkAreaBottom
        }
        ; CORRECTIONS FOR LEFT AND RIGHT EDGES OF WINDOW
        If ((EWD_WinX == 0)) ; && EWD_WinY == 0) || (EWD_WinX == 0 && EWD_WinB == MonitorWorkAreaBottom))
            WinLEdge := True
        Else If (((EWD_WinX+EWD_WinW) == A_ScreenWidth)) ;&& EWD_WinY == 0) || ((EWD_WinX+EWD_WinW) == A_ScreenWidth && EWD_WinB == MonitorWorkAreaBottom))
            WinREdge := True
        
        If (GetKeyState("RButton", "P"))
        {
            registerRbutton := true
        }
        Else If (registerRbutton)
        {
            registerRbutton := false
            SetTimer, EWD_WatchDrag, on
        }
            
        ; MOVE ADJUSTMENTS
        If !registerRbutton && MouseMoved
        {
            If (WinLEdge && (EWD_MouseX - EWD_MouseOrgX) < 0) 
            {
                ; Tooltip, "1"
                If (EWD_WinY >= 0 && EWD_WinB < MonitorWorkAreaBottom && (EWD_MouseY - EWD_MouseOrgY) > 0)
                {
                    WinMove, %EWD_winId%,, , EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                }
                Else If (EWD_WinB <= MonitorWorkAreaBottom && EWD_WinY > 0 && (EWD_MouseY - EWD_MouseOrgY) < 0)
                {
                    WinMove, %EWD_winId%,, , EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                }
                MButtonPreviousTick := A_TickCount
            }
            Else If (WinREdge && (EWD_MouseX - EWD_MouseOrgX) > 0) 
            {
                ; Tooltip, "2"
                If (EWD_WinY >= 0 && EWD_WinB < MonitorWorkAreaBottom && (EWD_MouseY - EWD_MouseOrgY) > 0)
                {
                    WinMove, %EWD_winId%,, , EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                }
                Else If (EWD_WinB <= MonitorWorkAreaBottom && EWD_WinY > 0 && (EWD_MouseY - EWD_MouseOrgY) < 0)
                {
                    WinMove, %EWD_winId%,, , EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                }
                MButtonPreviousTick := A_TickCount
            }
            Else If (WinLEdge && (EWD_MouseX - EWD_MouseOrgX) > 0)
            {
                If ((EWD_MouseX - EWD_MouseOrgX) > MouseMoveBuffer)
                {
                    ; Tooltip, "3"
                    WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX), EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                    WinLEdge := False
                }
                MButtonPreviousTick := A_TickCount
            }
            Else If (WinREdge && (EWD_MouseX - EWD_MouseOrgX) < 0) 
            {
                If ((EWD_MouseX - EWD_MouseOrgX) < -1*MouseMoveBuffer)
                {
                    ; Tooltip, "4"
                    WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX), EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                    WinREdge := False
                }
                MButtonPreviousTick := A_TickCount
            }
            Else If (EWD_WinY = 0 && EWD_WinH >= (MonitorWorkAreaBottom-MouseMoveBuffer) && (EWD_MouseX != EWD_MouseOrgX)) ; moving window that's height of screen
            {
                ; Tooltip, "5"
                WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX), , , MonitorWorkAreaBottom+OffB
                MButtonPreviousTick := A_TickCount
            }
            Else If (EWD_WinB = MonitorWorkAreaBottom && (EWD_MouseY - EWD_MouseOrgY) > 0) ;moving mouse down from window touchign bottom of screen
            {
                ; Tooltip, "6"
                WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX),
                MButtonPreviousTick := A_TickCount
            }
            Else If (EWD_WinY = 0 && (EWD_MouseY - EWD_MouseOrgY) < 0) ;moving mouse up from window touchign top of screen
            {
                ; Tooltip, "3"
                WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX),
                MButtonPreviousTick := A_TickCount
            }
            Else If ((EWD_MouseX != EWD_MouseOrgX) || (EWD_MouseY != EWD_MouseOrgY))
            {
                ; Tooltip, "5"
                WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX), EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                MButtonPreviousTick := A_TickCount
            }
        }
        Else
        {
            If (abs(DiffX) > abs(DiffY))
            {
                If DiffX < 0
                    DiffX := DiffX + -1*abs(DiffY)
                Else
                    DiffX := DiffX + abs(DiffY)
            }
            Else
            {
                If DiffY < 0 
                    DiffY := DiffY + -1*abs(DiffX)
                Else
                    DiffY := DiffY + abs(DiffX)
            }            
                    
            ; CORRECTIONS FOR X SIZING
            If ((EWD_WinX+DiffX) < 0 && (EWD_WinX != 0) && KDE_WinLeft == 1)
            {
                WinMove, %EWD_winId%,, 0-offL, , EWD_WinX+EWD_WinW-0+offL+offR, ;original right edge minus distance to 0 + offL to account fo shadow
                EWD_WinX := 0
            }
            Else If (((EWD_WinX + EWD_WinW + DiffX) > A_ScreenWidth) && ((EWD_WinX + EWD_WinW) != A_ScreenWidth) && KDE_WinLeft == -1)
            {
                WinMove, %EWD_winId%,, , , (A_ScreenWidth-EWD_WinX)+offL+offR
                EWD_WinX := A_ScreenWidth
                EWD_WinW := 0
            }
            ;  CORRECTIONS for Y SIZING 
            If ((EWD_WinY+DiffY) < 0 && (EWD_WinY != 0) && (KDE_WinUp == 1))
            {
                WinMove, %EWD_winId%,, , 0, , EWD_WinH+offB+(EWD_WinY-0)
                EWD_WinY := 0
            }
            Else If (((EWD_WinB + DiffY) > MonitorWorkAreaBottom) && ((EWD_WinB) != MonitorWorkAreaBottom))
            {
                WinMove, %EWD_winId%,, , , , (MonitorWorkAreaBottom-EWD_WinY)+offB, 
                EWD_WinB := MonitorWorkAreaBottom
            }

            ; SIZE ADJUSTMENTS
            If ((EWD_WinB == MonitorWorkAreaBottom) && (EWD_WinH == MonitorWorkAreaBottom) && ((EWD_WinX + EWD_WinW) < A_ScreenWidth) && (KDE_WinLeft == -1))
            {
                ; Tooltip, 1
                WinMove, %EWD_winId%, , EWD_WinXF + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      ,   ; Y of resized window
                                      , EWD_WinWF -     KDE_WinLeft*DiffX  ; W of resized window
                                      ,   ; H of resized window
                ChangedDims := True
            }
            Else If ((EWD_WinB == MonitorWorkAreaBottom) && (EWD_WinH == MonitorWorkAreaBottom) && (EWD_WinX > 0) && (KDE_WinLeft == 1))
            {
                ; Tooltip, 2
                WinMove, %EWD_winId%, , EWD_WinXF + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      ,   ; Y of resized window
                                      , EWD_WinWF -     KDE_WinLeft*DiffX  ; W of resized window
                                      ,   ; H of resized window
                ChangedDims := True
            }
            Else If ((abs(DiffX) > abs(DiffY)) && ((EWD_WinX + EWD_WinW) == A_ScreenWidth) && (KDE_WinLeft == 1))
            {
                ; Tooltip, 3
                WinMove, %EWD_winId%, , EWD_WinXF + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , ; EWD_WinY +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , ; (EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := True
            }
            Else If ((abs(DiffX) > abs(DiffY)) && (EWD_WinX == 0) && (KDE_WinLeft == -1))
            {
                ; Tooltip, 4
                WinMove, %EWD_winId%, , EWD_WinXF + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , ; EWD_WinY +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , ; (EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := True
            }
            Else If ((abs(DiffX) < abs(DiffY)) && (EWD_WinY >= 0) && (EWD_WinB == MonitorWorkAreaBottom) && (KDE_WinUp == 1))
            {
                ; Tooltip, 6
                WinMove, %EWD_winId%, , ;EWD_WinX + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , EWD_WinY +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , ;EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , (EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := True
            }
            Else If ((abs(DiffX) < abs(DiffY)) && (EWD_WinY == 0) && (EWD_WinB <= MonitorWorkAreaBottom) && (KDE_WinUp == 1))
            {
                ; Tooltip, 6a
            }
            Else If ((abs(DiffX) < abs(DiffY)) && (EWD_WinY >= 0) && (EWD_WinB == MonitorWorkAreaBottom) && (KDE_WinUp == -1))
            {
                ; Tooltip, 6b
                WinMove, %EWD_winId%, , ;EWD_WinX + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      ,  EWD_WinY  ;+   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , ;EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , ;(EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := 
            }
            Else If ((abs(DiffX) < abs(DiffY)) && (EWD_WinY >= 0) && (EWD_WinB <= MonitorWorkAreaBottom) && (KDE_WinUp == -1))
            {
                ; Tooltip, 7
                WinMove, %EWD_winId%, , ;EWD_WinX + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      ,  EWD_WinY  +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , ;EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , (EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := True
            }
            Else If ((abs(DiffX) > abs(DiffY)) && (EWD_WinX != 0) && (EWD_WinX + EWD_WinW) != A_ScreenWidth)
            {
                ; Tooltip, 5
                WinMove, %EWD_winId%, , EWD_WinXF + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , ; EWD_WinY +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , ; (EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := True
            }
            Else If ((abs(DiffX) < abs(DiffY)) && (EWD_WinY > 0) && (EWD_WinB < MonitorWorkAreaBottom))
            {
                ; Tooltip, 8
                WinMove, %EWD_winId%, , ;EWD_WinX + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , EWD_WinY +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , ;EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , (EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := True
            }
            
            
            If (ChangedDims)
            {
                ; Tooltip, 9
                WinGetPosEx(EWD_winHwnd, newX, newY, newW, newH)
                newB := newY+newH    
                If  ((EWD_WinX > 0 && newX == 0) or ((EWD_WinX+EWD_WinW) < A_ScreenWidth && (newX+newW) == A_ScreenWidth))
                {
                    sleep 400
                }
                Else If ((EWD_WinY > 0 && newY == 0) or (EWD_WinB < MonitorWorkAreaBottom && newB == MonitorWorkAreaBottom))
                {
                    sleep 400
                }
                
                PossiblyChangedSize := True
                ChangedDims := False
            }
            ; Tooltip, 
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

FadeToTargetTrans(winId, targetValue := 255, startValue := 255)
{
    transIncrement := 10
    If (targetValue != 255)
    {   
        maxValue := startValue
        loop % (abs(startValue - targetValue)/transIncrement)
        {   
            sleep, 1
            If (startValue > targetValue)
                maxValue := maxValue - transIncrement
            Else
                maxValue := maxValue + transIncrement
            WinSet, Transparent, %maxValue%, %winId%
        }
    }
    Else ;target MUST be 255 opaque
    {
        init := startValue
        loop % (abs(255 - startValue)/transIncrement)
        {
            sleep, 1
            init := init + transIncrement
            WinSet, Transparent, %init%, %winId%
        }
    }
   return
}

MoveToTargetSpot(winId, targetX, orgX)
{
   If (targetX > orgX)
      moveIncrement := 120
   Else
      moveIncrement := -120
      
   If WinExist(winId)
   {
       loopCount := floor(abs((targetX-orgX)/moveIncrement))
       newX := orgX
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
    If Wheel_disabled && MouseMoved
    {
        If ((A_TickCount - MButtonPreviousTick) > 1000)
        {
            FadeToTargetTrans(EWD_winId, 255, TransparentValue)
            MouseMoved := False
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

; #If !WinActive("ahk_exe onenote.exe") and !WinActive("ahk_exe OUTLOOK.EXE")) and !WinActive("ahk_exe Teams.exe")
!$LButton::
~$LButton::
    global HoveringWinHwnd, PrintButton, PeaksArray, lastWindowPeaked, PossiblyChangedSize
    savedWin := False
    MouseGetPos, , , ClickedWinHwnd
    PrintButton := True
    PossiblyChangedSize := False
    
    for idx, val in PeaksArray {
        If (val == ("ahk_id " . ClickedWinHwnd)) {
            savedWin := True
            HoveringWinHwnd := ClickedWinHwnd
            LookForLeaveWindow := True
            PossiblyChangedSize := True
            break
        }
    }
    
    If !savedWin ; didn't left click on a peaked window
    {
        lastWindowPeaked := False
    }
    
    SetTimer, WatchMouse, On ; catchall in case for some reason timer isn't running
    Wheel_disabled :=  False ; catchall in case for some reason wheel is still disabled
Return 
; #If

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
    global WindowArray, PrintButton, mEl, WinBackupXs, PeaksArray
    
    If (GetKeyState("MButton", "P"))
    {
        Sleep, 100
        Return 
    }
        
    MouseGetPos, mX, mY, mHwnd, mCtrl
    mWinID = ahk_id %mHwnd%
    WinGetClass, wClass, %mWinID%
    WinGetPos, X, Y, W, H, ahk_id %mHwnd%
    
    If (!PrintButton)
    {
        If ((mX != mXOld || mY != mYOld) && wClass != "Chrome_WidgetWin_1" && wClass != "Notepad++" )
        {
          try {
            If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                mEl := UIA.ElementFromPoint(mX, mY)
            Else
                mEl := WindowArray["ahk_id " . mHwnd]
          } catch e {
                ; If InStr(e.Message, "0x80070005")
                        ; Msgbox, "Try running UIAViewer with Admin privileges"
          }
        }
        Else If ((mX != mXOld || mY != mYOld) && (mX > (X+W-215)) && (mX < (X+W)) && (mY > Y) && (mY < (Y+32)))
        {
            try {
                    If (wClass == "Chrome_WidgetWin_1" || wClass == "Chrome_WidgetWin_0")
                    {
                        ; mEl        := UIA.ElementFromHandle(WinExist("ahk_id " . mHwnd), True)
                        If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                            mEl        := UIA.SmallestElementFromPoint(X+9, Y+2, True, "")
                        Else
                            mEl := WindowArray["ahk_id " . mHwnd]

                        minimizeEl := mEl.FindFirstByNameAndType("Minimize", "Button")
                        maximizeEl := mEl.FindFirstByNameAndType("Maximize", "Button")
                        closeEl    := mEl.FindFirstByNameAndType("Close", "Button")
                        If (minimizeEl || maximizeEl || closeEl)
                            sleep 50
                    }
                    Else 
                    {
                        ; mEl        := UIA.ElementFromHandle(WinExist("ahk_id " . mHwnd), True)
                        If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                            mEl        := UIA.SmallestElementFromPoint(mX, mY, False, "")
                        Else
                            mEl := WindowArray["ahk_id " . mHwnd]

                        minimizeEl := mEl.FindFirstByNameAndType("Minimize", "Button")
                        maximizeEl := mEl.FindFirstByNameAndType("Maximize", "Button")
                        closeEl    := mEl.FindFirstByNameAndType("Close", "Button")
                        If (minimizeEl || maximizeEl || closeEl)
                            sleep 50
                    }
           } catch e {
                    ; If InStr(e.Message, "0x80070005")
                        ; Msgbox, "Try running UIAViewer with Admin privileges"
           }
        }
    }
    
    If (PrintButton)
    {
        SetTimer, CheckButtonSize, Off
        ; WinGetTitle, wTitle, ahk_id %mHwnd%
        ; WinGetPos, wX, wY, wW, wH, ahk_id %mHwnd%
        ; WinGetText, wText, ahk_id %mHwnd%
        ; WinGet, wProc, ProcessName, ahk_id %mHwnd%
        ; WinGet, wProcID, PID, ahk_id %mHwnd%
        ; Tooltip,

        try {     
            ;;If (mEl.CurrentControlType = 50004) && MouseIsOver("ahk_class CabinetWClass")
            ;;{
            ;;    SetTimer, SendCtrlAdd, -300
            ;;    Return
            ;;}
            If (wClass == "Chrome_WidgetWin_1" || wClass == "Chrome_WidgetWin_0")
            {
                minimizePos := minimizeEl.GetCurrentPos()
                maximizePos := maximizeEl.GetCurrentPos()
                closePos    := closeEl.GetCurrentPos()
                If ((mX >= minimizePos.x) && (mX <= (minimizePos.x+minimizePos.w)) && (mY >= minimizePos.y) && (mY <= (minimizePos.y+minimizePos.h)))
                    ToolTip, minimize!
                Else If ((mX >= maximizePos.x) && (mX <= (maximizePos.x+maximizePos.w)) && (mY >= maximizePos.y) && (mY <= (maximizePos.y+maximizePos.h)))
                    ToolTip, maximize!
                Else If ((mX >= closePos.x) && (mX <= (closePos.x+closePos.w)) && (mY >= closePos.y) && (mY <= (closePos.y+closePos.h)))
                {
                    ToolTip, close!
                    for idx, val in PeaksArray {
                      If (val == mWinID) {
                          PeaksArray.remove(idx)
                          ; PeaksArray.remove(val)
                          LookForLeaveWindow := False
                          WinSet, AlwaysOnTop, off, %mWinID%
                          Break
                         }
                      }
                    for k, v in WinBackupXs {
                       If (k == mHwnd) {
                           WinBackupXs.remove(k)
                           RangeTip(, , , , , , k)
                           Break
                       }
                    }
                }
            }
            Else
            {
                If InStr(mEl.CurrentName, "Close")
                {
                    Tooltip, %wClass% " close!"
                    for idx, val in PeaksArray {
                      If (val == mWinID) {
                          PeaksArray.remove(idx)
                          ; PeaksArray.remove(val)
                          LookForLeaveWindow := False
                          WinSet, AlwaysOnTop, off, %mWinID%
                          Break
                         }
                      }
                    for k, v in WinBackupXs {
                       If (k == mHwnd) {
                           WinBackupXs.remove(k)
                           RangeTip(, , , , , , k)
                           Break
                       }
                    }
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
        PrintButton := False
        SetTimer, CheckButtonSize, On
    }    
    mXOld := mX
    mYOld := mY
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

RangeTip(x:="", y:="", w:="", h:="", color:="Red", d:=2, winId:=0) ; from the FindText library, credit goes to feiyue
{
  static id:=0
  ; tooltip, % winId
  
  If (x="")
  {
    id:=0
    SetFormat, Integer, D
    ; Loop 4
       Gui, Range_%winId%_3: Destroy
    Return
  }
  
  if (!id)
  {
    ; Loop 4
      Gui, Range_%winId%_3:New, +AlwaysOnTop -Caption +ToolWindow +HwndLinesId -DPIScale +E0x08000000
  }
  x:=Floor(x), y:=Floor(y), w:=Floor(w), h:=Floor(h), d:=Floor(d)
  ; Loop 4
  ; {
    i:=3
    , x1:=(i=2 ? x+w : x-d)
    , y1:=(i=3 ? y+h : y-d)
    , w1:=(i=1 or i=3 ? w+2*d : d)
    , h1:=(i=2 or i=4 ? h+2*d : d)
    x1s := x1 + 2
    w1s := w1 - 4
    Gui, Range_%winId%_%i%: Color, %color%
    Gui, Range_%winId%_%i%: Show, NA x%x1s% y%y1% w%w1s% h%h1%
    
    WinSet, AlwaysOnTop, on, ahk_id %LinesId%
  ; }
  Return
}

; MsgBox % GetSysColor(13) . "`n" . GetSysColor(29)
GetSysColor(n)
{
    Local BGR := DllCall("User32.dll\GetSysColor", "Int", n, "UInt")
        , RGB := (BGR & 255) << 16 | (BGR & 65280) | (BGR >> 16)
    Return Format("0x{:06X}", RGB)
} ; https://msdn.microsoft.com/en-us/library/windows/desktop/ms724371(v=vs.85).aspx

HexToDec(hex)
{
    VarSetCapacity(dec, 66, 0)
    , val := DllCall("msvcrt.dll\_wcstoui64", "Str", hex, "UInt", 0, "UInt", 16, "CDECL Int64")
    , DllCall("msvcrt.dll\_i64tow", "Int64", val, "Str", dec, "UInt", 10, "CDECL")
    return dec
}

GetAccentColor()
{
    RegRead, CheckReg, HKCU\SOFTWARE\Microsoft\Windows\DWM, ColorizationColor
    SetFormat, integer, hex
    CheckReg := Checkreg+10659224
    StringRight, CheckReg, CheckReg, 6
    ; msgbox % CheckReg
    Return CheckReg
}

