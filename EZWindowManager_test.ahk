#NoEnv 
#SingleInstance force 
#Persistent 
#InstallKeybdHook
#InstallMouseHook
SetBatchLines, -1
SetWinDelay, -1   ; Makes the below move faster/smoother.
; Thread, interrupt, 0  ; Make all threads IMMEDIATELY interruptible.
Process, Priority,, High
SendMode, Input
SetTitleMatchMode, 2
CoordMode, Mouse, Screen
CoordMode, Pixel, Screen

#Include %A_ScriptDir%\WinGetPosEx.ahk 
; #Include %A_ScriptDir%\RunAsAdmin.ahk
#Include %A_ScriptDir%\UIA_Interface.ahk 

Wheel_disabled := False
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
fifteenMinutes := 1000*60*5

SysGet, MonitorWorkArea, MonitorWorkArea 

WindowArray     := []
PeaksArray      := []
WinBackupXs     := []
WinBackupColors := []
GuisCreated     := []
scannedAhkIds   := []
CmenuArrayIds   := []

minButtonWidth       := 32
percLeft             := 1.0
edgePercentage       := .04
HoveringWinHwnd      := 
lastWindowPeaked     := False
MouseMoveBuffer      := 100
PrintButton          := False
PossiblyChangedSize  := False
ForceButtonRemove    := False
ResetMousePosBkup    := False
ExplorerSpawned      := False
TaskbarPeak          := False
PossiblyMoved        := False
SkipKeepOnTop        := False
SkipRedetectColor    := False
SkipCheckButtonSize  := False
SkipCheckButtonColor := False
SkipWatchmouse       := False
ForceButtonCheck     := False

minDimsAhkId   := {}
maxDimsAhkId   := {}
closeDimsAhkId := {}
cacheRequest   := {}
mEl            := {}
npEl           := {}
minimizeEl     := {}
maximizeEl     := {}
closeEl        := {}
windowEls      := {}

lastActiveWinhwnd  := 
LastRemovedWinHwnd := 
firstButtonPosXOld := 0
winCountOld := 0

BlockInput, On
global UIA       := UIA_Interface()
global tbEl      := UIA.ElementFromHandle("ahk_class Shell_TrayWnd")
global toolbarEl := tbEl.FindFirstBy("ClassName=MSTaskListWClass AND ControlType=Toolbar")
; windowEls := toolbarEl ? toolbarEl.FindAllBy("Name=running", 0x4, 2, True) : tbEl.FindAllBy("ClassName=Taskbar.TaskListButtonAutomationPeer")

Msgbox, 0, EzWindowManager, Detecting Theme Accent Color...%AccentColorHex%, 2
global AccentColorHex := SampleAccentColor()

BlockInput, Off
Tooltip, %AccentColorHex%
WinGet, procName, ProcessName, "7-Zip File Manager"
Tooltip, %procName%
sleep 2000
Tooltip, 

t_KeepOnTop := t_WatchMouse := t_CheckButtonSize := t_ButCapture := t_RedetectColor := t_CheckButtonColor := A_TickCount 
SetTimer, MasterTimer, 20, -1
SetTimer, OtherTimer, 500

Gui +LastFound
hWnd := WinExist()
DetectHiddenWindows, On
DllCall( "RegisterShellHookWindow", UInt,hWnd )
MsgNum := DllCall( "RegisterWindowMessage", Str,"SHELLHOOK" )
OnMessage( MsgNum, "ShellMessage" )

Return

ShellMessage( wParam, lParam ) {
  Local k
  If ( wParam = 1 ) ;  HSHELL_WINDOWCREATED := 1
     {
       WinGetTitle, currentTitle, ahk_id %lParam%
       If currentTitle
       {
           WinGetClass, currentClass, A
           WinGet, currentHwnd, ID, A
           WinGet, currentExe, ProcessName, A
           If ( WinExist(ahk_id %lParam%) 
                &&  (currentClass != "tooltips_class32")
                &&  (currentClass != "Windows.UI.Core.CoreWindow" )
                &&  (currentClass != "ApplicationManager_DesktopShellWindow" )
                &&  (currentClass != "TaskListThumbnailWnd" )
                &&  (currentClass != "MSO_BORDEREFFECT_WINDOW_CLASS" )
                &&  (currentClass != "MultitaskingViewFrame"         )
                &&  (currentClass != "#32768"                        )
                &&  (currentClass != "#32770"                        )
                &&  (currentClass != "Shell_TrayWnd")
                &&  (currentClass != "WorkerW"      ))
           {
               lastGoodHwnd    := currentHwnd
               lastGoodCapture := currentClass
               lastGoodExe     := currentExe
               GoSub, CheckButtonSize
               GoSub, ButCaptureCached
           }
       }
    }
}

OtherTimer:
    MouseGetPos, , , otherMouseWinHwnd
    WinGetClass, otherClass, ahk_id %otherMouseWinHwnd%
    If (lButtonDrag && otherClass == "WorkerW")
    {
        DesktopIcons(True)
    }
Return

MasterTimer:
    MouseGetPos, MXw, MYw, MouseWinHwnd
    WinGetClass, wmClass, ahk_id %MouseWinHwnd%

    If ((wmClass == "WorkerW" || wmClass == "Progman") && MXw == 0 && MYw == 0)
        DesktopIcons(True)
    
    If WinExist("ahk_class #32768")
    {
        WinGet, chwnd, ID, ahk_class #32768
        If !(HasVal(CmenuArrayIds, chwnd))
        {
            CmenuArrayIds.push(chwnd)
            for idx, chwnd in CmenuArrayIds
            {
                If WinExist("ahk_id " . chwnd)
                    WinSet, AlwaysOnTop, On, ahk_id %chwnd%
            }
        }
        ; tooltip, % join(CmenuArrayIds)
    }
    Else
    {
        CmenuArrayIds := []
    }
    
    fileOpHwnd1 := WinExist("ahk_class #32770", "Recycle")
    fileOpHwnd2 := WinExist("ahk_class #32770", "Type of file")
    If (fileOpHwnd1 || fileOpHwnd2)
    {
        WinSet, AlwaysOnTop, On, ahk_id %fileOpHwnd1%
        WinSet, AlwaysOnTop, On, ahk_id %fileOpHwnd2%
    }
    
    If (wmClass == "Shell_TrayWnd")
    {
        SetTimer, MasterTimer, 1, -1
        GoSub, KeepOnTop
        GoSub, WatchMouse
    }
    Else
    {
        SetTimer, MasterTimer, 20, -1
        If ((A_TickCount-t_WatchMouse) >= 80)
        {
            GoSub, WatchMouse
            t_WatchMouse := A_TickCount
        }
        Else If (((A_TickCount-t_CheckButtonSize) >= 200))
        {
            GoSub, CheckButtonSize
            t_CheckButtonSize := A_TickCount
        }
        Else If (((A_TickCount-t_CheckButtonColor) >= 100))
        {
            GoSub, CheckButtonColor
            t_CheckButtonColor := A_TickCount
        }
        Else If (((A_TickCount-t_RedetectColor) >= fifteenMinutes))
        {
            GoSub, ReDetectAccentColor
            t_RedetectColor := A_TickCount
        }
        GoSub, KeepOnTop
    }
Return

ReDetectAccentColor:
    If !SessionIsLocked()
    {
        AccentColorHex := SampleAccentColor()
        ForceButtonRemove := True
    }
Return    
    
LookForExplorerSpawn:
    Winwait, ahk_class CabinetWClass
    Gosub, SendCtrlAdd
    WinWaitClose, ahk_class CabinetWClass
Return

WatchMouse:
    If ResetMousePosBkup
    {
        MXw_bkup := MXw
        MYw_bkup := MYw
        ResetMousePosBkup := False
    }
    
    FinishedLoop := True 
   
    If ((wmClass == "TaskListThumbnailWnd" || wmClass == "Windows.UI.Core.CoreWindow" || wmClass == "Notepad++" || wmClass == "#32770"))
    {
        try {
            mEl         := UIA.ElementFromPoint(MXw,MYw)
            minimizeEl  := mEl.FindFirstByNameAndType("Minimize", "Button", 2, False)
            maximizeEl  := mEl.FindFirstByNameAndType("Maximize", "Button", 2, False)
            closeEl     := mEl.FindFirstByNameAndType("Close",    "Button", 2, False)
            overSpecial := True
        }
        catch e {
        }
    }
    Else
    {
        overSpecial := False
    }
    
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
                WinGetPosEx(winHwnd, WinX, WinY, WinW, WinH, OffL, OffT, OffR, OffB)
                
                If (WinX < 0) && (lastWindowPeaked ||  ((MXw-MXw_bkup) < (-1*MouseMoveBuffer)) || (MXw == 0 &&  MXw_bkup == 0)) 
                {
                    WinSet, AlwaysOnTop, On, %winId%
                    LookForLeaveWindow := True
                    HoveringWinHwnd    := MouseWinHwnd
                    MoveToTargetSpot(winId, 0-offL, WinX)
                    FadeToTargetTrans(winId, 255, 200)
                    FileAppend, WatchMouse - %LookForLeaveWindow%`n, C:\Users\vbonaven\Desktop\log.txt
                    lastWindowPeaked   := True
                    WinGetPosEx(winHwnd, WinX2, WinY2, WinW2, WinH2)
                    AdjustWinDims(winId, WinX2-WinX, WinY2-WinY)
                    Break
                }
                Else If (WinX+WinH > A_ScreenWidth) && (lastWindowPeaked ||  ((MXw-MXw_bkup) > MouseMoveBuffer) || (MXw >= (A_ScreenWidth-2) && MXw_bkup >= (A_ScreenWidth-2))) 
                {
                    WinSet, AlwaysOnTop, On, %winId%
                    LookForLeaveWindow := True
                    HoveringWinHwnd    := MouseWinHwnd
                    MoveToTargetSpot(winId, A_ScreenWidth-WinW-OffR, WinX)
                    FadeToTargetTrans(winId, 255, 200)
                    FileAppend, WatchMouse1 - %LookForLeaveWindow%`n, C:\Users\vbonaven\Desktop\log.txt
                    WinGetPosEx(winHwnd, WinX2, WinY2, WinW2, WinH2)
                    lastWindowPeaked   := True
                    AdjustWinDims(winId, WinX2-WinX, WinY2-WinY)
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
            MXwOffset := -50 ; now create a large offset to see If perhaps the window we're next to offscreen is a peaked one
        }
        Else If (MXw >= (A_ScreenWidth-2) && MXw_bkup >= (A_ScreenWidth-2) && MYw == MYw_bkup)
        {
            MXwOffset := 50 ; now create a large offset to see If perhaps the window we're next to offscreen is a peaked one
        }
        
        If (MXwOffset != 0) ; so we've decided to check offscreen
        {
            for idx, val in PeaksArray
            {
                WinGet, winHwnd, ID, %val%
                WinGetPosEx(winHwnd, WinX, WinY, WinW, WinH, OffL, OffT, OffR, OffB)
                If (((MXw+MXwOffset) > WinX) && ((MXw+MXwOffset) < (WinX+WinW)) && (MYw > WinY) && (MYw < (WinY+WinH))) ; turns out there is an offscreen peaked window
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
    
    If (LookForLeaveWindow && MouseWinHwnd && HoveringWinHwnd) 
    {
        If (HoveringWinHwnd != MouseWinHwnd)
        {
            WinGetTitle, ti, ahk_id %MouseWinHwnd%
            WinGetClass, cl, ahk_id %MouseWinHwnd%  
            FileAppend, % "Hovering over " ti "-" cl "- size: " GetSize(WinBackupXs) "`n", C:\Users\vbonaven\Desktop\log.txt
            for k, v in WinBackupXs 
            {
               If (k == HoveringWinHwnd)
               {
                  WinGetTitle, title, ahk_id %HoveringWinHwnd%
                  FileAppend, Found Hovered %title%`n, C:\Users\vbonaven\Desktop\log.txt
                  ; tooltip, 4
                  winId = ahk_id %HoveringWinHwnd%
                  WinGet, winHwnd, ID, %winId%
                  WinGetPosEx(winHwnd, WinX, WinY, WinW, WinH, OffL, OffT, OffR, OffB)
                  ; Make sure we've moved the mouse outside the window we're hovering over
                  If (MXw < WinX || Mxw > (WinX+WinW) || MYw < WinY || MYw > (WinY+WinH))
                  {
                      ; Tooltip, %percLeft%
                      If (!lastWindowPeaked)
                      {
                         sleep 350
                      }
                      ; double check that we haven't re-entered the peaked window and hence cancel the re-hide   
                      MouseGetPos, MXw2, MYw2,
                      If (MXw2 >= WinX && MXw2 <= (WinX+WinW) && MYw2 >= WinY && MYw2 <= (WinY+WinH))
                      {
                         Return
                      }
                      ;fixes added for resizing windows while it's being peaked
                      orgX := WinBackupXs[HoveringWinHwnd]
                      newOrgX := orgX
                      
                      If PossiblyChangedSize
                      {
                          If (orgX < 0)
                            newOrgX := ceil((percLeft*((WinW*WinH)/WinH))-WinW)
                          Else
                            newOrgX := A_ScreenWidth-ceil(percLeft*(WinW*WinH)/WinH)

                          WinBackupXs[HoveringWinHwnd] := newOrgX
                          xsize := GetSize(WinBackupXs)
                          FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - size: %xsize%`n, C:\Users\vbonaven\Desktop\log.txt
                          PossiblyChangedSize := False
                      }

                      WinSet, Bottom, , %winId%
                      WinGet, except, ProcessName, %winId%
                      If (except == "Signal.exe")
                         OffR := 0
                      
                      WinMove, %winId%,, newOrgX-OffR
                      If (percLeft < 0.10)
                        FadeToTargetTrans(winId, 100)
                      Else
                        FadeToTargetTrans(winId, 200)
                      LookForLeaveWindow := False
                      FileAppend, WatchMouse2 - %LookForLeaveWindow%`n, C:\Users\vbonaven\Desktop\log.txt
                      WinSet, Bottom, , %winId%
                  }
                  Break
               }
            }
        }
    }
    MXw_bkup := MXw
    MYw_bkup := MYw
Return

ResetPeakedWindows: 
    If (TaskbarPeak)
    {
        TaskbarPeak := False
        for k, v in WinBackupXs 
        {
            WinGetPosEx(k, , , , , OffL, OffT, OffR, OffB)
            winId = ahk_id %k%
            orgX := WinBackupXs[k]
            newOrgX := orgX
            
            WinSet, Bottom, , %winId%
            WinGet, except, ProcessName, %winId%
            If (except == "Signal.exe")
               OffR := 0
            
            WinMove, %winId%,, newOrgX-OffR
            FadeToTargetTrans(winId, 200)
            WinSet, Bottom, , %winId%
            sleep 200
         }
         LookForLeaveWindow := False
         FileAppend, ResetPeakedWindows - %LookForLeaveWindow%`n, C:\Users\vbonaven\Desktop\log.txt
    }
Return

/* ;
*****************************
***** UTILITY FUNCTIONS *****
*****************************
*/

ExtractAppTitle(FullTitle)
{   
    AppTitle := SubStr(FullTitle, InStr(FullTitle, " ", False, -1) + 1)
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

!WheelUp::
    MouseGetPos, , , wheelhwnd
    WinActivate, ahk_id %wheelhwnd%
    Send, {PgUp}
return

!WheelDown::
    MouseGetPos, , , wheelhwnd
    WinActivate, ahk_id %wheelhwnd%
    Send, {PgDn}
return

KeepOnTop:
    for guiHwnd, winHwnd in GuisCreated
    {
        ; FileAppend, %guihwnd%`n, C:\Users\vbonaven\Desktop\log.txt
        WinSet, AlwaysOnTop, on, ahk_id %guiHwnd%
    }
Return

CheckButtonSize: 
    firstButtonPosX := 0
    
    windowEls := toolbarEl ? toolbarEl.FindAllBy("Name=running", 0x4, 2, True) : tbEl.FindAllBy("ClassName=Taskbar.TaskListButtonAutomationPeer")
    buttonsElAr := toolbarEl.FindAllBy("ControlType=Button")
    If (buttonsElAr.length() > 0)
    {
        taskButton1ElPos := buttonsElAr[buttonsElAr.MaxIndex()].CurrentBoundingRectangle
        firstButtonPosX := taskButton1ElPos.l
    }
    
    If ((firstButtonPosXOld != firstButtonPosX) || ForceButtonRemove)
    {  
        If ForceButtonRemove
        {
            FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - ForceButtonRemove`n, C:\Users\vbonaven\Desktop\log.txt
            RangeTip( , , , , , , Format("{:#x}", LastRemovedWinHwnd), True)
            ForceButtonRemove := False
        }
        
        for guiHwnd, winHwnd in GuisCreated
        {
            WinClose, ahk_id %guiHwnd%
        }
        
        FoundStray := False
        ; tooltip, % join(WinBackupXs)
        for winHwnd, winx in WinBackupXs {
            winHwndX := Format("{:#x}", winHwnd)
             If (!WinExist("ahk_id " . winHwndX))
             {
                FoundStray := True
                break
             }
        }
        If FoundStray
        {
           arr := join(WinBackupXs)
           FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - XArray: %arr%`n, C:\Users\vbonaven\Desktop\log.txt
           FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - Stray %winHwndX%`n, C:\Users\vbonaven\Desktop\log.txt
           WinBackupXs.remove(winHwndX)
           FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - FoundStray`n, C:\Users\vbonaven\Desktop\log.txt
           RangeTip( , , , , , , Format("{:#x}", winHwndX), False)
        }
        
        If (WinBackupXs.MaxIndex() > 0)
        {
            arr := join(WinBackupXs)
            FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - XArray: %arr%`n, C:\Users\vbonaven\Desktop\log.txt
        }
        
        for winHwnd, winXpos in WinBackupXs {
             winHwndX := Format("{:#x}", winHwnd)
             If !winHwndX
                continue 
             ; FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - %winHwndX%`n, C:\Users\vbonaven\Desktop\log.txt
             buttonMargin := 0
             buttonWinId = ahk_id %winHwnd%
             WinGet, wProcess, ProcessName, %buttonWinId%

             WinGetTitle, wTitle, %buttonWinId%
             preparedTitle1 := StrReplace(wTitle, "\", "\\")
             preparedTitle2 := StrReplace(preparedTitle1, ".", "\.")
             regexTitle := preparedTitle2 . ".*running"
             buttonEl := toolbarEl.FindFirstByNameAndType(regexTitle, "Button", 0x4, "RegEx", False)
             ; FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - %regexTitle%`n, C:\Users\vbonaven\Desktop\log.txt
             
             If (!buttonEl)
             {
                for index, subtitle in StrSplit(wTitle, [" - ", " | ", " "])
                {
                    preparedTitle1 := StrReplace(subtitle, "\", "\\")
                    preparedTitle2 := StrReplace(preparedTitle1, ".", "\.")
                    regexSub := preparedTitle2 . ".*running"
                    buttonEl := toolbarEl.FindFirstByNameAndType(regexSub, "Button", 0x4, "RegEx", False)
                    If (!buttonEl)
                        buttonEl := toolbarEl.FindFirstByNameAndType(regexTitle, "MenuItem", 0x4, "RegEx", False)
                    Else If (buttonEl != "")
                    {
                        ; If !InStr(buttonEl.CurrentName, "1 running")
                            ; groupedWindows := True
                        break
                    }
                }
             }
             
             If (!buttonEl)
             {
                procNameArray  := StrSplit(wProcess, ".")
                preparedTitle1 := StrReplace(procNameArray[1], "\", "\\")
                preparedTitle2 := StrReplace(preparedTitle1, ".", "\.")
                regexTitle := "i).*" . preparedTitle2 . ".*running"
                buttonEl := toolbarEl.FindFirstByNameAndType(regexTitle, "Button", 0x4, "RegEx", False)
                
                If (!buttonEl)
                    buttonEl := toolbarEl.FindFirstByNameAndType(regexTitle, "MenuItem", 0x4, "RegEx", False)
             }
             ; Else
             ; {
                ; If !InStr(buttonEl.CurrentName, "1 running")
                    ; groupedWindows := True
             ; }
             
             If (!buttonEl)
             {
                typeString := % "AutomationId=" wProcess " OR Automation=" procNameArray[1]
                buttonEl := toolbarEl.FindFirstBy(typeString, 0x4, 2, False)
             }
             ; Else
             ; {
                ; If !InStr(buttonEl.CurrentName, "1 running")
                    ; groupedWindows := True
             ; }
             
             If (buttonEl)
             {
                 taskButtonElPos := buttonEl.CurrentBoundingRectangle
                 If (taskButtonElPos.l != 0)
                 {
                     FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - Normal`n, C:\Users\vbonaven\Desktop\log.txt
                     targetColor := SampleAccentColor(taskButtonElPos.l)
                     RangeTip(taskButtonElPos.l, taskButtonElPos.t, taskButtonElPos.r-taskButtonElPos.l-buttonMargin, taskButtonElPos.b-taskButtonElPos.t, targetColor, 2, winHwndX, True)
                 }
             }
        }
    }
    firstButtonPosXOld := firstButtonPosX
Return 

CheckButtonColor:
    for winHwnd, winXpos in WinBackupXs {
         groupedWindows := False
         buttonMargin := 0
         buttonWinId = ahk_id %winHwnd%
         WinGet, wProcess, ProcessName, %buttonWinId%
         WinGetTitle, wTitle, %buttonWinId%
         preparedTitle1 := StrReplace(wTitle, "\", "\\")
         preparedTitle2 := StrReplace(preparedTitle1, ".", "\.")
         regexTitle := preparedTitle2 . ".*running"
         winHwndX := Format("{:#x}", winHwnd)
         buttonEl := toolbarEl.FindFirstByNameAndType(regexTitle, "Button", 0x4, "RegEx", False)
         
         If (!buttonEl)
         {
            for index, subtitle in StrSplit(wTitle, [" - ", " | ", " "])
            {
                preparedTitle1 := StrReplace(subtitle, "\", "\\")
                preparedTitle2 := StrReplace(preparedTitle1, ".", "\.")
                regexSub := preparedTitle2 . ".*running"
                buttonEl := toolbarEl.FindFirstByNameAndType(regexSub, "Button", 0x4, "RegEx", False)
                If (!buttonEl)
                    buttonEl := toolbarEl.FindFirstByNameAndType(regexTitle, "MenuItem", 0x4, "RegEx", False)
                Else If (buttonEl != "")
                {
                    ; If !InStr(buttonEl.CurrentName, "1 running")
                        ; groupedWindows := True
                    break
                }
            }
         }
         
         If (!buttonEl)
         {
            procNameArray  := StrSplit(wProcess, ".")
            preparedTitle1 := StrReplace(procNameArray[1], "\", "\\")
            preparedTitle2 := StrReplace(preparedTitle1, ".", "\.")
            regexTitle := "i).*" . preparedTitle2 . ".*running"
            buttonEl := toolbarEl.FindFirstByNameAndType(regexTitle, "Button", 0x4, "RegEx", False)
            
            If (!buttonEl)
                buttonEl := toolbarEl.FindFirstByNameAndType(regexTitle, "MenuItem", 0x4, "RegEx", False)
         }
         ; Else
         ; {
            ; If !InStr(buttonEl.CurrentName, "1 running")
                ; groupedWindows := True
         ; }
         
         If (!buttonEl)
         {
            typeString := % "AutomationId=" wProcess " OR Automation=" procNameArray[1]
            buttonEl := toolbarEl.FindFirstBy(typeString, 0x4, 2, False)
         }
         ; Else
         ; {
            ; If !InStr(buttonEl.CurrentName, "1 running")
                ; groupedWindows := True
         ; }
             
         If (buttonEl)
         {
             taskButtonElPos := buttonEl.CurrentBoundingRectangle
             If (taskButtonElPos.l != 0)
             {
                 targetColor := SampleAccentColor(taskButtonElPos.l)

                 If !(HasKey(WinBackupColors, winHwnd))
                 {
                    ; tooltip, % "1)"targetColor "-" AccentColorHex "-" bla
                    WinBackupColors[winHwnd] := targetColor
                 }
                 Else
                 {
                     storedColor := WinBackupColors[winHwnd]

                     If (targetColor != storedColor)
                     {
                        FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - CheckButtonColor - %targetColor% vs %storedColor%`n, C:\Users\vbonaven\Desktop\log.txt
                        WinBackupColors[winHwnd] := targetColor
                        RangeTip(taskButtonElPos.l, taskButtonElPos.t, taskButtonElPos.r-taskButtonElPos.l-buttonMargin, taskButtonElPos.b-taskButtonElPos.t, targetColor, 2, winHwndX, True, False)
                     }
                 }
                 
             }
         }
    }
    If ForceButtonCheck
    {
        ForceButtonCheck := False
    }
Return

$MButton::
    SetTimer, MasterTimer, Off
    DesktopIcons(False)

    EWD_MouseOrgX := 0
    EWD_MouseOrgY := 0
    EWD_MouseX := 0
    EWD_MouseY := 0
    
    MouseGetPos, MX, MY, EWD_MouseWinHwnd ; Get cursor position
    EWD_winId = ahk_id %EWD_MouseWinHwnd% ; Get the active window's title
    WinGet, EWD_winHwnd, ID, %EWD_winId% ; Get the title's text
    WinGet, EWD_WinState, MinMax, %EWD_winId% ; Get window state
    WinGetClass, EWD_winClass, %EWD_winId%
    
    EWD_MouseX      := MX 
    EWD_MouseOrgX   := MX 
    EWD_MouseY      := MY 
    EWD_MouseOrgY   := MY 
    
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
    
    If (EWD_winClass == "WorkerW")
    {
        KeyWait, MButton, T3
        send, {MButton}
        Return
    }
    
    Wheel_disabled := True
    WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, EWD_OffL, EWD_OffT, EWD_OffR, EWD_OffB)
    EWD_WinXorg := EWD_WinX
    EWD_WinWorg := EWD_WinW
    EWD_WinYorg := EWD_WinY
    EWD_WinHorg := EWD_WinH
    
    If (MX < (EWD_WinX + (EWD_WinW / 2)))
       KDE_WinLeft := 1
    Else
       KDE_WinLeft := -1
    
    If (MY < (EWD_WinY + (EWD_WinH / 2)))
       KDE_WinUp := 1
    Else
       KDE_WinUp := -1

    WinActivate, %EWD_winId%
    If (WinActive("ahk_class " EWD_winClass) && EWD_winClass != "Shell_TrayWnd")
    {
        WinGet, lastActiveWinhwnd, ID, ahk_class %EWD_winClass%
    }
    SetTimer, EWD_WatchDrag, 10 ; Track the mouse as the user drags it.
    SetTimer, CheckforTransparent, 50
    
    KeyWait, MButton, T30
    If ((MX == EWD_MouseX) && (MY == EWD_MouseY))
    {
        ; Tooltip, here %MX% : %MY% : %EWD_MouseX% : %EWD_MouseY%
        WinSet, Transparent, Off, %EWD_winId%
        SetTimer, EWD_WatchDrag, Off
        SetTimer, CheckforTransparent, Off
        If (IsOverTitleBar(MX, MY, EWD_MouseWinHwnd)==1 && !ToggledOnTop) {
            Send !{F4}
            CleanUpStoredWindow(EWD_winId, EWD_MouseWinHwnd)
        }
        Else If (!ToggledOnTop) {
            Send, {MButton}
        }
    }
    Else
    {
       WinGetTitle, currentTitle, A
       WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, EWD_OffL, EWD_OffT, EWD_OffR, EWD_OffB)
       If currentTitle
       {
           WinGet, currentHwnd, ID, A
           ahkid = ahk_id %currentHwnd% 
           AdjustWinDims(ahkid, (EWD_WinX+EWD_WinW)-(EWD_WinXorg+EWD_WinWorg), EWD_WinY-EWD_WinYorg)
       }
    }
    Wheel_disabled := False
    SetTimer, MasterTimer, On
Return 

EWD_WatchDrag:
    If (!(GetKeyState("MButton", "P")) && !(GetKeyState("RButton", "P"))) 
    { 
           SetTimer, CheckforTransparent, Off
           SetTimer, EWD_WatchDrag, Off
           percentageLeft := CalculateWinScreenPercent(EWD_winId)
           
           If (percentageLeft < 0.40)
           {
              If (percentageLeft < 0.10)
                FadeToTargetTrans(EWD_winId, 100, TransparentValue)
              Else
                FadeToTargetTrans(EWD_winId, 200, TransparentValue)
              PeaksArray.push(EWD_winId)
              WinBackupXs[EWD_MouseWinHwnd] := EWD_WinX
              xsize := GetSize(WinBackupXs)
              FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - Make %EWD_MouseWinHwnd%:%EWD_WinX% size: %xsize%`n, C:\Users\vbonaven\Desktop\log.txt
              ForceButtonRemove := True
              ResetMousePosBkup := True
              WinSet, Bottom, , %EWD_winId%
              sleep 1000
              Return
           }
           
            ; CORRECTIONS FOR LEFT AND RIGHT EDGES OF WINDOW
            WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, EWD_OffL, EWD_OffT, EWD_OffR, EWD_OffB)
            If ((EWD_WinX == 0)) ; && EWD_WinY == 0) || (EWD_WinX == 0 && EWD_WinB == MonitorWorkAreaBottom))
                WinLEdge := True
            Else If (((EWD_WinX+EWD_WinW) == A_ScreenWidth)) ;&& EWD_WinY == 0) || ((EWD_WinX+EWD_WinW) == A_ScreenWidth && EWD_WinB == MonitorWorkAreaBottom))
                WinREdge := True
            
           removePeakedWin := False

           If ((percentageLeft >= 0.40) && !WinLEdge && !WinREdge)
           {
              removeId := False
              removeIdx := 0
                
              for idx, val in PeaksArray {
                 If (val == EWD_winId)
                 {
                     WinSet, AlwaysOnTop, off, %EWD_winId%
                     removeIdx := idx
                     removeId := True
                     Break
                 }
              }
              
              If removeId
              {
                 LastRemovedWinHwnd := EWD_MouseWinHwnd
                 ForceButtonRemove  := True
                 removePeakedWin    := True
                 LookForLeaveWindow := False
                 FileAppend, EWD_WatchDrag - %LookForLeaveWindow%`n, C:\Users\vbonaven\Desktop\log.txt
                 PeaksArray.remove(removeIdx)
                 WinBackupXs.remove(EWD_MouseWinHwnd)
                 xsize := GetSize(WinBackupXs)
                 FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - size: %xsize%`n, C:\Users\vbonaven\Desktop\log.txt
              }
              
           }
           Else If ((percentageLeft >= 0.40) && (WinLEdge || WinREdge))
           {
              for k, v in WinBackupXs {
                 If (k == EWD_MouseWinHwnd)
                 {
                     ; tooltip, window edging!
                     LookForLeaveWindow  := True
                     FileAppend, EWD_WatchDrag2 - %LookForLeaveWindow%`n, C:\Users\vbonaven\Desktop\log.txt
                     HoveringWinHwnd     := EWD_MouseWinHwnd
                     PossiblyChangedSize := True
                     Break
                 }
              }
           }
           
           If MouseMoved
              FadeToTargetTrans(EWD_winId, 255, TransparentValue)
   
           If removePeakedWin
              lastWindowPeaked := False
           
           Return
        }
           
        MouseGetPos, EWD_MouseX, EWD_MouseY
        If (((EWD_MouseX != EWD_MouseOrgX) || (EWD_MouseY != EWD_MouseOrgY)) && !registerRbutton)
            MouseMoved := True
        
        If ((EWD_MouseX == MX) && (EWD_MouseY == MY))
        {
            If ((A_TickCount - TimeSinceStop) > 1100)
            {
                SetTimer, EWD_WatchDrag, off
                WinSet, AlwaysOnTop, toggle, %EWD_winId%
                Tooltip, Top State Toggled!
                ToggledOnTop := True
                Return
            }
        }
        Else
        {
            TimeSinceStop := A_TickCount
        }
        WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, EWD_OffL, EWD_OffT, EWD_OffR, EWD_OffB)
        EWD_WinXF := EWD_WinX-EWD_OffL
        ; Otherwise, reposition the window to match the change in mouse coordinates
        ; caused by the user having dragged the mouse:
        ; winX := winW := offL := offR := 0
        ; WinGetPos, wX, wY, wW, wH, ahk_id %EWD_MouseWinHwnd%
        EWD_WinB := EWD_WinY + EWD_WinH
        EWD_WinWF := EWD_WinW + EWD_OffL + EWD_OffR
        ; EWD_WinH := EWD_WinH + offB
        ; ToolTip, %EWD_WinX% : %wX% : %EWD_WinW% : %wW% : %EWD_WinB% : %MonitorWorkAreaBottom%
        ; ToolTip, %wH% : %EWD_WinH% : %MonitorWorkAreaBottom%
        ; Diff :=  EWD_MouseY - EWD_MouseOrgY
        ; ToolTip, %Diff%

        DiffX :=  EWD_MouseX - EWD_MouseOrgX ; Obtain an offset from the initial mouse position.
        DiffY :=  EWD_MouseY - EWD_MouseOrgY
        
        If (GetKeyState("RButton", "P"))
        {
            registerRbutton := True
        }
        Else If (registerRbutton)
        {
            registerRbutton := False
            SetTimer, EWD_WatchDrag, on
        }
        ; CORRECTIONS FOR TOP AND BOTTOM OF WINDOW
        If (EWD_WinH > MonitorWorkAreaBottom && !registerRbutton) ; fix too tall window
        {
            WinMove, %EWD_winId%,, , 0 , , MonitorWorkAreaBottom+EWD_OffB
            EWD_WinB := MonitorWorkAreaBottom
        }
        Else If ((EWD_WinY+DiffY) < 0 && !registerRbutton)
        {
            WinMove, %EWD_winId%,,,0
            EWD_WinY := 0
        }
        Else If ((EWD_WinB+DiffY) > MonitorWorkAreaBottom && !registerRbutton)
        {
            WinMove, %EWD_winId%,,,(MonitorWorkAreaBottom-EWD_WinH)
            EWD_WinB := MonitorWorkAreaBottom
        }
        ; CORRECTIONS FOR LEFT AND RIGHT EDGES OF WINDOW
        If ((EWD_WinX == 0)) ; && EWD_WinY == 0) || (EWD_WinX == 0 && EWD_WinB == MonitorWorkAreaBottom))
            WinLEdge := True
        Else If (((EWD_WinX+EWD_WinW) == A_ScreenWidth)) ;&& EWD_WinY == 0) || ((EWD_WinX+EWD_WinW) == A_ScreenWidth && EWD_WinB == MonitorWorkAreaBottom))
            WinREdge := True
        
            
        ; MOVE ADJUSTMENTS
        If !registerRbutton && MouseMoved
        {
            If (WinLEdge && (EWD_MouseX - EWD_MouseOrgX) <= 0) 
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
            Else If (WinREdge && (EWD_MouseX - EWD_MouseOrgX) >= 0) 
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
            Else If (WinLEdge) ; && (EWD_MouseX - EWD_MouseOrgX) > 0)
            {
                If ((EWD_MouseX - EWD_MouseOrgX) > floor(MouseMoveBuffer/5))
                {
                    ; Tooltip, "3"
                    WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX), EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                    WinLEdge := False
                }
                MButtonPreviousTick := A_TickCount
            }
            Else If (WinREdge) ; && (EWD_MouseX - EWD_MouseOrgX) < 0) 
            {
                If ((EWD_MouseX - EWD_MouseOrgX) < ceil(-1*MouseMoveBuffer/5))
                {
                    ; Tooltip, "4"
                    WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX), EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                    WinREdge := False
                }
                MButtonPreviousTick := A_TickCount
            }
            Else If (EWD_WinY = 0 && EWD_WinH >= (MonitorWorkAreaBottom-10) && (EWD_MouseX != EWD_MouseOrgX)) ; moving window that's height of screen
            {
                ; Tooltip, "5"
                WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX), , , MonitorWorkAreaBottom+EWD_OffB
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
                WinMove, %EWD_winId%,, 0-EWD_OffL, , EWD_WinX+EWD_WinW-0+EWD_OffL+EWD_OffR, ;original right edge minus distance to 0 + offL to account fo shadow
                EWD_WinX := 0
            }
            Else If (((EWD_WinX + EWD_WinW + DiffX) > A_ScreenWidth) && ((EWD_WinX + EWD_WinW) != A_ScreenWidth) && KDE_WinLeft == -1)
            {
                WinMove, %EWD_winId%,, , , (A_ScreenWidth-EWD_WinX)+EWD_OffL+EWD_OffR
                EWD_WinX := A_ScreenWidth
                EWD_WinW := 0
            }
            ;  CORRECTIONS for Y SIZING 
            If ((EWD_WinY+DiffY) < 0 && (EWD_WinY != 0) && (KDE_WinUp == 1))
            {
                WinMove, %EWD_winId%,, , 0, , EWD_WinH+EWD_OffB+(EWD_WinY-0)
                EWD_WinY := 0
            }
            Else If (((EWD_WinB + DiffY) > MonitorWorkAreaBottom) && ((EWD_WinB) != MonitorWorkAreaBottom))
            {
                WinMove, %EWD_winId%,, , , , (MonitorWorkAreaBottom-EWD_WinY)+EWD_OffB, 
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
                                      , (EWD_WinH + EWD_OffB) - KDE_WinUp *DiffY  ; H of resized window
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
                ChangedDims := False
            }
            Else If ((abs(DiffX) < abs(DiffY)) && (EWD_WinY >= 0) && (EWD_WinB <= MonitorWorkAreaBottom) && (KDE_WinUp == -1))
            {
                ; Tooltip, 7
                WinMove, %EWD_winId%, , ;EWD_WinX + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , ;EWD_WinY  +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , ;EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , (EWD_WinH + EWD_OffB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := True
            }
            Else If ((abs(DiffX) > abs(DiffY)) && (EWD_WinX != 0) && (EWD_WinX + EWD_WinW) != A_ScreenWidth)
            {
                Tooltip, 5
                WinMove, %EWD_winId%, , EWD_WinXF + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , ; EWD_WinY +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , ; (EWD_WinH + offB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := True
            }
            Else If ((abs(DiffX) < abs(DiffY)) && (EWD_WinY > 0) && (EWD_WinB < MonitorWorkAreaBottom))
            {
                Tooltip, 8
                WinMove, %EWD_winId%, , ;EWD_WinX + (KDE_WinLeft+1)/2*DiffX  ; X of resized window
                                      , EWD_WinY +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , ;EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , (EWD_WinH + EWD_OffB) - KDE_WinUp *DiffY  ; H of resized window
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
        }

        EWD_MouseOrgX := EWD_MouseX, EWD_MouseOrgY := EWD_MouseY ; Update for the next timer-call to this subroutine.
Return

IsOverTitleBar(x, y, hWnd) {
    SendMessage, 0x84,, (x & 0xFFFF) | (y & 0xFFFF) << 16,, ahk_id %hWnd%
    If ErrorLevel in 2
        Return 1
    Else
        Return 0
}

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
        Return 1.0
        
    Return abs(visibleWindowArea/totalWindowArea)
}

FadeToTargetTrans(winId, targetValue := 255, startValue := 255)
{
    Critical On
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
        loop % (ceil((255 - startValue)/transIncrement))
        {
            sleep, 1
            init := init + transIncrement
            WinSet, Transparent, %init%, %winId%
        }
    }
    Critical Off
   Return
}

MoveToTargetSpot(winId, targetX, orgX)
{
   Critical On
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
   Critical Off
   Return
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

~Enter::
    Gosub, SendCtrlAdd
Return

!LButton::
~LButton::
    SetTimer, MasterTimer, Off
    lButtonDrag          := True
    showDesktopD         := False
    showDesktopU         := False
    savedWin             := False
    PossiblyChangedSize  := False
    LButtonPreviousTick1 := A_TickCount
    MouseGetPos, lmx, lmy, ClickedWinHwnd
    WinGetClass, class, ahk_id %ClickedWinHwnd%
    mWinClickedID = ahk_id %ClickedWinHwnd%
    WinGet, mWinClickeHwnd, ID, %mWinClickedID%
    WinGetPos, lb_x, lb_y, lb_w, lb_h, %mWinClickedID%
    
    If (class == "WorkerW" || class == "Progman")
        showDesktopD := True
    Else If (class == "#32768")
    {
        lButtonDrag := False
        SetTimer, MasterTimer, On
        return
    }
    
    If (WinActive("ahk_class " class) && class != "Shell_TrayWnd")
    {
        WinGet, lastActiveWinhwnd, ID, ahk_class %class%
    }
    
    for idx, val in PeaksArray {
        If (val == ("ahk_id " . ClickedWinHwnd)) {
            savedWin := True
            break
        }
    }

    If !savedWin ; didn't left click on a peaked window
    { 
        lastWindowPeaked := False
        
        If (class == "Shell_TrayWnd")
        {
            ; j := join(GuisCreated, True)
            ; FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - %j%`n, C:\Users\vbonaven\Desktop\log.txt
            
            for guiHwnd, winHwnd in GuisCreated
            {
                winHwndx := Format("{:#x}", winHwnd)
                
                winHwndx_ID = ahk_id %winHwndx%
                WinGetPos, gx, gy, gw, gh, ahk_id %guiHwnd%
                WinGet, state, MinMax, %winHwndx_ID%
                
                If (lmx > gx && lmx < (gx+gw) && state == 0 && winHwndx != lastActiveWinhwnd)
                {
                    tooltip, % winHwndx "-" lastActiveWinhwnd
                    WinGetPosEx(winHwndx, WinX, WinY, WinW, WinH, OffL, OffT, OffR, OffB)
                    
                    If (WinX < 0) {
                        WinSet, AlwaysOnTop, On, %winHwndx_ID%
                        MoveToTargetSpot(winHwndx_ID, 0-offL, WinX)
                        FadeToTargetTrans(winHwndx_ID, 255, 200)
                        TaskbarPeak := True
                        Break
                    }
                    Else If (WinX+WinH > A_ScreenWidth) {
                        WinSet, AlwaysOnTop, On, %winHwndx_ID%
                        MoveToTargetSpot(winHwndx_ID, A_ScreenWidth-WinW-OffR, WinX)
                        FadeToTargetTrans(winHwndx_ID, 255, 200)
                        TaskbarPeak := True
                        Break
                    }
                }
            }
        }
        Else If TaskbarPeak
        {
            Gosub, ResetPeakedWindows
        }
    }
    
    loop
    {
        LButtonPreviousTick2 := A_TickCount
        If !GetKeyState("LButton", "P")
            break
        Else
        {
            ; MouseGetPos, lmx2, lmy2, ClickedWinHwndU
            ; WinGetClass, classU, ahk_id %ClickedWinHwndU%
            MouseGetPos, MXw, MYw, MouseWinHwnd
            WinGetClass, wmClass, ahk_id %MouseWinHwnd%
            GoSub, WatchMouse
            sleep 100
        }
    }
    
    If (wmClass == "WorkerW" || wmClass == "Progman")
        showDesktopU := True
    
    If showDesktopD && showDesktopU
        DesktopIcons(True)
    Else If (!showDesktopD && showDesktopU && (lmx != MXw || lmy != MYw))
        DesktopIcons(True)
    Else
    {
        If (wmClass != "#32770")
            DesktopIcons(False)

        If ((LButtonPreviousTick2 - LButtonPreviousTick2_old) < DoubleClickTime)
            Gosub, SendCtrlAdd
        
        WinGetPos, lb_x2, lb_y2, lb_w2, lb_h2, %mWinClickedID%
        
        If (savedWin && (lb_w != lb_w2 || lb_h != lb_h2))
        {
            PossiblyChangedSize := True
            LookForLeaveWindow := True
            HoveringWinHwnd := ClickedWinHwnd
        }
        
        lb_xw  := lb_x + lb_w
        lb_xw2 := lb_x2 + lb_w2
        If ((abs(lb_xw - lb_xw2) > 5 || abs(lb_y - lb_y2) > 5) && (LButtonPreviousTick2-LButtonPreviousTick1) > 250)
        {
            foundClickedId := False
            for shwnds, c in scannedAhkIds
            {
                If (shwnds == mWinClickedID)
                {
                    foundClickedId := True
                    break
                }
            }
            
            If foundClickedId
                AdjustWinDims(mWinClickedID, lb_xw2-lb_xw, lb_y2-lb_y)
            Else
            {
                WinGetTitle, currentTitle, %mWinClickedID%
                If currentTitle
                {
                    WinGet, currentExe, ProcessName, %mWinClickedID%
                    If ( WinExist(mWinClickedID) 
                         &&  (class != "tooltips_class32")
                         &&  (class != "Windows.UI.Core.CoreWindow" )
                         &&  (class != "TaskListThumbnailWnd" )
                         &&  (class != "MSO_BORDEREFFECT_WINDOW_CLASS" )
                         &&  (class != "MultitaskingViewFrame"         )
                         &&  (class != "#32768"                        )
                         &&  (class != "#32770"                        )
                         &&  (class != "Shell_TrayWnd")
                         &&  (class != "WorkerW"      ))
                     {
                         lastGoodHwnd    := mWinClickeHwnd
                         lastGoodCapture := class
                         lastGoodExe     := currentExe
                         GoSub, ButCaptureCached
                     }
                }
            }
        }
        Else 
        {
            PrintButton := True
            Gosub, ButCaptureCached
        }
    }    
        
    lButtonDrag := False
    LButtonPreviousTick2_old := LButtonPreviousTick2
    Wheel_disabled :=  False ; catchall in case for some reason wheel is still disabled
    ForceButtonCheck := True
    SetTimer, MasterTimer, On
Return 

SendCtrlAdd:
    If (WinActive("ahk_class CabinetWClass"))
    {
        sleep 200
        Send ^{NumpadAdd}
    }
Return

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
        winId = ahk_id %WindowUnderMouseID2%
        WinClose , %winId%
    }
Return

;===========================================================================================================
;ElementFromPoint is the original Microsoft implementation, but it has the drawback of sometimes not 
; returning the actual smallest element at the point. For example it might return a container element 
; (Pane, Group etc) instead, while there might be a CheckBox or Button under the point (which are 
; contained in the container element). The same issue is described here: 
; https://arstechnica.com/civis/viewtopic.php?f=20&t=1467202.
;
;SmallestElementFromPoint is a workaround for this issue: it first uses ElementFromPoint, and then drills 
; down until it finds the actual smallest element at that point. This is what UIAViewer uses internally.
;
;SmallestElementFromPoint also has the windowEl argument, which if provided checks the whole window for 
; elements other than ElementFromPoint element that contain the point. This is what UIAViewer uses if the
; "Deep search (slower)" checkbox is checked. To see why this is needed, try to inspect Chrome's 
; min-max buttons: without "Deep search" you cannot find them (because ElementFromPoint returns an element 
; that doesn't contain those buttons...), but with "Deep search" they are found.
;===========================================================================================================
ButCapture:
    MouseGetPos, mXbc, mYbc, mHwnd, mCtrl
    mWinID = ahk_id %mHwnd%
    WinGetClass, wClass, %mWinID%
    
    If (GetKeyState("MButton", "P") || (wClass == "WorkerW") || (wClass == "Shell_TrayWnd"))
    {
        Return 
    }
    
    WinGet, winHwndbc, ID, %mWinID%
    WinGet, winExe, ProcessName, %mWinID%
    WinGetTitle, winTitle, %mWinID%

    WinGetPosEx(winHwndbc, X, Y, W, H, offL, OffT, OffR, OffB)

    If (!PrintButton && (mXbc_bkup != mXbc || mYbc_bkup != mXYc))
    {
        If ((mXbc > ((X+W)-215)) && (mXbc < (X+W)) && (mYbc > Y) && (mYbc < (Y+32)))
        {
            try {
                   If (wClass == "Chrome_WidgetWin_1" && winTitle != "Messages for web")
                   {
                      ; tooltip, 0
                       If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                       {
                           mEl := UIA.SmallestElementFromPoint(mXbc, mYbc, True, UIA.ElementFromHandle(mHwnd))
                           ; WindowArray["ahk_id " . mHwnd] := mEl
                       }
                       Else
                           mEl := WindowArray["ahk_id " . mHwnd]
                       
                       ; minimizeEl := mEl.FindFirstByNameAndType("Minimize", "Button")
                       ; maximizeEl := mEl.FindFirstByNameAndType("Maximize", "Button")
                       ; closeEl    := mEl.FindFirstByNameAndType("Close", "Button")
                       ; If (minimizeEl || maximizeEl || closeEl)
                           ; sleep 50
                       
                   }
                   Else If (winTitle == "Messages for web")
                   {
                      ; tooltip, 0
                       If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                       {
                           mEl := UIA.SmallestElementFromPoint(mXbc, mYbc, True, "")
                           ; WindowArray["ahk_id " . mHwnd] := mEl
                       }
                       Else
                           mEl := WindowArray["ahk_id " . mHwnd]
                       
                       ; minimizeEl := mEl.FindFirstByNameAndType("Minimize", "Button")
                       ; maximizeEl := mEl.FindFirstByNameAndType("Maximize", "Button")
                       ; closeEl    := mEl.FindFirstByNameAndType("Close", "Button")
                       ; If (minimizeEl || maximizeEl || closeEl)
                           ; sleep 50
                   }
                   Else If (winExe == "notepad++.exe")
                   {
                       If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                       {
                           mEl := UIA.ElementFromPoint(mXbc, mYbc)
                           ; WindowArray["ahk_id " . mHwnd] := mEl
                       }
                       Else
                           mEl := WindowArray["ahk_id " . mHwnd]
                   }
                   Else
                   {
                       ; tooltip, 2
                       If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                       {
                          mEl := UIA.ElementFromPoint(mXbc, mYbc)
                          ; WindowArray["ahk_id " . mHwnd] := mEl
                       }
                       Else
                          mEl := WindowArray["ahk_id " . mHwnd]
                          
                       minimizeEl := mEl.FindFirstByNameAndType("Minimize", "Button")
                       maximizeEl := mEl.FindFirstByNameAndType("Maximize", "Button")
                       closeEl    := mEl.FindFirstByNameAndType("Close", "Button")

                       If (!minimizeEl && !maximizeEl && !closeEl)
                       {
                           If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
                           {
                              mEl := UIA.SmallestElementFromPoint(mXbc, mYbc, False, "")
                              ; WindowArray["ahk_id " . mHwnd] := mEl  
                           }
                           Else
                              mEl := WindowArray["ahk_id " . mHwnd]
                       }
                   }
                } catch e {
                        ; If InStr(e.Message, "0x80070005")
                            ; Tooltip, "Try running UIAViewer with Admin privileges"
                }
        }
        Else If ((wClass == "TaskListThumbnailWnd" || wClass == "Windows.UI.Core.CoreWindow" || wClass == "CabinetWClass") && winExe != "notepad++.exe")
        {
         try{
            If (IsUIAObjSaved("ahk_id " . mHwnd) == False)
            {
                mEl := UIA.ElementFromPoint(mXbc, mYbc, False)
                ; WindowArray["ahk_id " . mHwnd] := mEl
            }
            Else
                mEl := WindowArray["ahk_id " . mHwnd]
            } catch e {
                    ; If InStr(e.Message, "0x80070005")
                       ; Tooltip, "Try running UIAViewer with Admin privileges"
            }
        }
    }
    Else
    {
       try {     
            
            If InStr(mEl.CurrentName, "Close")
            {
                removeId  := False
                removeIdx := 0

                for idx, val in PeaksArray {
                  If (val == mWinID) {
                      WinSet, AlwaysOnTop, off, %mWinID%
                      LookForLeaveWindow := False
                      FileAppend, ButCapture - %LookForLeaveWindow%`n, C:\Users\vbonaven\Desktop\log.txt
                      removeId           := True
                      removeIdx          := idx
                      Break
                     }
                  }
                  
                If removeId
                {
                    PeaksArray.remove(removeIdx)
                    WinBackupXs.remove(mHwnd)
                    xsize := GetSize(WinBackupXs)
                    FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - size: %xsize%`n, C:\Users\vbonaven\Desktop\log.txt
                    LastRemovedWinHwnd :=mHwnd
                    ForceButtonRemove  := True
                }
                Tooltip, %wClass% " closed! " %LastRemovedWinHwnd%
                mEl := {}
            }
            Else If InStr(mEl.CurrentName, "Maximize")
            {
                Tooltip, %wClass% " maximize!"
                mEl := {}
            }
            Else If InStr(mEl.CurrentName, "Minimize")
            {
                Tooltip, %wClass% " minimize!"
                mEl := {}
            }
            
            If GetKeyState("Alt", "P")
                Tooltip, % mEl.CurrentAutomationId " : " mEl.CurrentName " : " mEl.CurrentControlType
        } catch e {
        
        }
        PrintButton := False
        sleep 500
        Tooltip, 
    }    
    mXbc_bkup := mXbc
    mYbc_bkup := mYbc
Return

ButCaptureCached:
    Critical
    
    If (!PrintButton && lastGoodExe && lastGoodCapture)
    {
        sleep 500
        mWinIdbc2 = ahk_id %lastGoodHwnd%
        ; FileAppend,  %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - START ========================================`n, C:\Users\vbonaven\Desktop\log2.txt 
        try {
            ; FileAppend,  %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - %previousClass% - %lastGoodCapture%`n, C:\Users\vbonaven\Desktop\log2.txt 
            prevCached := False
            
            for shwnds, c in scannedAhkIds
            {
                If (mWinIdbc2 == shwnds)
                {
                    prevCached := True
                    break
                }
            }
            ; tooltip, 00
            If !prevCached
            {
                cacheRequest := UIA.CreateCacheRequest()
                cacheRequest.TreeScope := 5 ; Set TreeScope to include the starting element and all descendants as well
                cacheRequest.AddProperty("ControlType") ; Add all the necessary properties that DumpAll uses: ControlType, LocalizedControlType, AutomationId, Name, Value, ClassName, AcceleratorKey
                cacheRequest.AddProperty("Name")
                cacheRequest.AddProperty("AutomationId")
            }
            Else
            {
                Return
            }
           ; tooltip, 0
            If (lastGoodCapture == "Chrome_WidgetWin_1" && (lastGoodExe == "chrome.exe" || lastGoodExe == "msedge.exe"))
            {
                WinGetPos, wX, wY, , , %mWinIdbc2%
                If (lastGoodExe == "msedge.exe")
                    offsetX := 4
                Else
                    offsetX := 9
                
                If !prevCached
                    npEl := UIA.ElementFromPointBuildCache(wX+offsetX, wY+1, cacheRequest)
                Else
                    npEl.BuildUpdatedCache(cacheRequest)
                    
                regexMin := "Name=Minimize AND ControlType=button"
                regexMax := "Name=Maximize AND ControlType=button"
                regexClo := "Name=Close AND (ControlType=button OR ControlType=ListItem)"
                minimizeElAr := npEl.FindAllBy(regexMin, 0x4, 2, False, cacheRequest)
                maximizeElAr := npEl.FindAllBy(regexMax, 0x4, 2, False, cacheRequest)
                closeElAr    := npEl.FindAllBy(regexClo, 0x4, 2, False, cacheRequest)
                
                for idx, result in minimizeElAr
                {
                    If (minimizeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                    {
                        minimizeEl := result
                        break
                    }
                }
                for idx, result in maximizeElAr
                {
                    If (maximizeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                    {
                        maximizeEl := result
                        break
                    }
                }
                for idx, result in closeElAr
                {
                    If (closeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                    {
                        closeEl := result
                        break
                    }
                }
                tooltip, done0!
            }
            Else
            {
                If !prevCached
                    npEl := UIA.ElementFromHandleBuildCache(mWinIdbc2, cacheRequest) ; Get element and also build the cache
                Else
                    npEl.BuildUpdatedCache(cacheRequest)
                
                regexMin := "Name=Minimize AND ControlType=button AND ClassName=NetUIAppFrameHelper)"
                regexMax := "Name=Maximize AND ControlType=button AND ClassName=NetUIAppFrameHelper)"
                regexClo := "Name=Close AND (ControlType=button OR ControlType=ListItem) AND ClassName=NetUIAppFrameHelper"
                minimizeElAr := npEl.FindAllBy(regexMin, 0x4, 2, False, cacheRequest)
                maximizeElAr := npEl.FindAllBy(regexMax, 0x4, 2, False, cacheRequest)
                closeElAr    := npEl.FindAllBy(regexClo, 0x4, 2, False, cacheRequest)
                
                If (minimizeElAr.length() > 0)
                {
                    for idx, result in minimizeElAr
                    {
                        If (minimizeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                        {
                            minimizeEl := result
                            break
                        }
                    }
                    for idx, result in maximizeElAr
                    {
                        If (maximizeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                        {
                            maximizeEl := result
                            break
                        }
                    }
                    for idx, result in closeElAr
                    {
                        If (closeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                        {
                            closeEl := result
                            break
                        }
                    }
                }
                ; tooltip, % "done1! " minimizeElAr.length() "-" minimizeEl.GetCurrentPos("screen").x "-" minimizeEl.GetCurrentPos("screen").w "-" minimizeEl.GetCurrentPos("screen").y "-" minimizeEl.GetCurrentPos("screen").h 
                Else If (minimizeElAr.length() == 0)
                {
                    regexMin := "Name=Minimize AND ControlType=button AND (AutomationId=Minimize OR AutomationId=view_2)"
                    regexMax := "Name=Maximize AND ControlType=button AND (AutomationId=Maximize OR AutomationId=view_2)"
                    regexClo := "Name=Close AND (ControlType=button OR ControlType=ListItem) AND (AutomationId=Close OR AutomationId=view_2)"
                    minimizeElAr := npEl.FindAllBy(regexMin, 0x4, 2, False, cacheRequest)
                    maximizeElAr := npEl.FindAllBy(regexMax, 0x4, 2, False, cacheRequest)
                    closeElAr    := npEl.FindAllBy(regexClo, 0x4, 2, False, cacheRequest)
                    
                    for idx, result in minimizeElAr
                    {
                        If (minimizeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                        {
                            minimizeEl := result
                            break
                        }
                    }
                    for idx, result in maximizeElAr
                    {
                        If (maximizeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                        {
                            maximizeEl := result
                            break
                        }
                    }
                    for idx, result in closeElAr
                    {
                        If (closeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                        {
                            closeEl := result
                            break
                        }
                    }
                    tooltip, done2!
                }
                Else If (minimizeElAr.length() == 0)
                {
                    regexMin := "Name=Minimize AND ControlType=button"
                    regexMax := "Name=Maximize AND ControlType=button"
                    regexClo := "Name=Close AND (ControlType=button OR ControlType=ListItem)"
                    minimizeElAr := npEl.FindAllBy(regexMin, 0x4, 2, False, cacheRequest)
                    maximizeElAr := npEl.FindAllBy(regexMax, 0x4, 2, False, cacheRequest)
                    closeElAr    := npEl.FindAllBy(regexClo, 0x4, 2, False, cacheRequest)
                    
                    for idx, result in minimizeElAr
                    {
                        If (minimizeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                        {
                            minimizeEl := result
                            break
                        }
                    }
                    for idx, result in maximizeElAr
                    {
                        If (maximizeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                        {
                            maximizeEl := result
                            break
                        }
                    }
                    for idx, result in closeElAr
                    {
                        If (closeElAr[idx].GetCurrentPos("screen").w > minButtonWidth)
                        {
                            closeEl := result
                            break
                        }
                    }
                    tooltip, done3!
                }
            }
            ; tooltip, 1
            
            ; tooltip, 2
            If (!minimizeEl && !maximizeEl && !closeEl)
            {
                tooltip, dammit! %lastGoodCapture% %lastGoodExe%
                FileAppend, % npEl.DumpAll() "`n", C:\Users\vbonaven\Desktop\log2.txt 
                scannedAhkIds.remove(mWinIdbc2)
            }
            Else
            {
                ; minimizePos := minimizeEl.GetCurrentPos("screen")
                ; maximizePos := maximizeEl.GetCurrentPos("screen")
                ; closePos    := closeEl.GetCurrentPos("screen")
                
                minX        := minimizeEl.GetCurrentPos("screen").x
                minXW       := minimizeEl.GetCurrentPos("screen").x+minimizeEl.GetCurrentPos("screen").w
                minY        := minimizeEl.GetCurrentPos("screen").y
                minYH       := minimizeEl.GetCurrentPos("screen").y+minimizeEl.GetCurrentPos("screen").h
                
                maxX        := maximizeEl.GetCurrentPos("screen").x
                maxXW       := maximizeEl.GetCurrentPos("screen").x+maximizeEl.GetCurrentPos("screen").w
                maxY        := maximizeEl.GetCurrentPos("screen").y
                maxYH       := maximizeEl.GetCurrentPos("screen").y+maximizeEl.GetCurrentPos("screen").h
                
                closeX      := closeEl.GetCurrentPos("screen").x
                closeXW     := closeEl.GetCurrentPos("screen").x+closeEl.GetCurrentPos("screen").w
                closeY      := closeEl.GetCurrentPos("screen").y
                closeYH     := closeEl.GetCurrentPos("screen").y+closeEl.GetCurrentPos("screen").h
                
                tooltip, % minX "-" minXW "-" minY "-" minYH 
                scannedAhkIds[mWinIdbc2] := cacheRequest
                
                Array := {"X": minX, "XW": minXW, "Y": minY, "YH": minYH}
                minDimsAhkId[mWinIdbc2] := Array
                Array := {"X": maxX, "XW": maxXW, "Y": maxY, "YH": maxYH}
                maxDimsAhkId[mWinIdbc2] := Array
                Array := {"X": closeX, "XW": closeXW, "Y": closeY, "YH": closeYH}
                closeDimsAhkId[mWinIdbc2] := Array
                
                minimizeEl   := {}
                maximizeEl   := {}
                closeEl      := {}
                ; tooltip, stored!
            }
            
        } catch e {
        
        }
    }
    Else
    {
        try {   
            If (overSpecial)
            {
                If InStr(mEl.CurrentName, "Close")
                {
                    Tooltip, %wClass% " closed! " %LastRemovedWinHwnd%
                    mEl := {}
                }
                Else If InStr(mEl.CurrentName, "Maximize")
                {
                    Tooltip, %wClass% " maximize!"
                    mEl := {}
                }
                Else If InStr(mEl.CurrentName, "Minimize")
                {
                    Tooltip, %wClass% " minimize!"
                    mEl := {}
                }
            }
            Else
            {
                CoordMode, Mouse, Screen
                MouseGetPos, mXbc2, mYbc2, 
                
                for element in minDimsAhkId
                {
                    If (mWinClickedID == element)
                    {
                        ; tooltip, % minDimsAhkId[element].X " " minDimsAhkId[element].Y " " minDimsAhkId[element].XW " " minDimsAhkId[element].YH "|" mXbc2 " " mYbc2
                        If ((mXbc2 >= minDimsAhkId[element].X) && (mXbc2 <= minDimsAhkId[element].XW) && (mYbc2 >= minDimsAhkId[element].Y) && (mYbc2 <= minDimsAhkId[element].YH))
                        {
                            ToolTip, minimize!
                            PrintButton := False
                            sleep 750
                            Tooltip, 
                            Return
                        }    
                    }
                }
                
                for element in maxDimsAhkId
                {
                    If (mWinClickedID == element)
                    {
                        If ((mXbc2 >= maxDimsAhkId[element].X) && (mXbc2 <= maxDimsAhkId[element].XW) && (mYbc2 >= maxDimsAhkId[element].Y) && (mYbc2 <= maxDimsAhkId[element].YH))
                        {
                            ToolTip, maximize!
                            ; FileAppend,  %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - MAXIMIZE`n, C:\Users\vbonaven\Desktop\log2.txt 
                            PrintButton := False
                            sleep 750
                            Tooltip, 
                            Return
                        }            
                    }
                }
                    
                for element in closeDimsAhkId
                {
                    If (mWinClickedID == element)
                    {
                        If ((mXbc2 >= closeDimsAhkId[element].X) && (mXbc2 <= closeDimsAhkId[element].XW) && (mYbc2 >= closeDimsAhkId[element].Y) && (mYbc2 <= closeDimsAhkId[element].YH))
                        {
                            ToolTip, % "close! " closeDimsAhkId[element].X " " closeDimsAhkId[element].XW " " closeDimsAhkId[element].Y " " closeDimsAhkId[element].YH
                            ; FileAppend,  %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - CLOSE`n, C:\Users\vbonaven\Desktop\log2.txt 
                            PrintButton := False
                            CleanUpStoredWindow(mWinClickedID, lastGoodHwnd)
                            sleep 750
                            Tooltip, 
                            Return
                        }
                    }
                }   
            }
            PrintButton := False
            sleep 750 
            Tooltip, 
         ; FileAppend,  %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - DONE1 ========================================`n, C:\Users\vbonaven\Desktop\log2.txt 
        } catch e {
        
        }
    }    
Return

CleanUpStoredWindow(ahkId := "", hwnd := "")
{
    global ForceButtonRemove, LastRemovedWinHwnd, PeaksArray, WinBackupXs
    
    removeId := False
    removeIdx := 0

    for idx, val in PeaksArray {
      If (val == ahkId) {
          WinSet, AlwaysOnTop, off, %ahkId%
          removeId  := True
          removeIdx := idx
          Break
         }
      }
      
    If removeId
    {
        PeaksArray.remove(removeIdx)
        WinBackupXs.remove(hwnd)
        WinBackupColors.remove(hwnd)
        LastRemovedWinHwnd := hwnd
        LookForLeaveWindow := False
        FileAppend, CleanUpStoredWindow - %LookForLeaveWindow% - %ahkId% - %hwnd%`n, C:\Users\vbonaven\Desktop\log.txt
        ForceButtonRemove  := True
    }
    Return
}

IsUIAObjSaved(idstring := "")
{
    global WindowArray
    ; Tooltip, % WindowArray.Length()
    for k, v in WindowArray {
          If (k == idstring)
            Return True
    }
    Return False
}

RangeTip(x:="", y:="", w:="", h:="", color:=0x0, d:=2, winHwnd:=0, print:=False, fadeTrans:=True) ; from the FindText library, credit goes to feiyue
{
    ;I guess since ALL subroutines can see all other subroutines variables it was resetting mX and mY?? 
    ;As I said at the beginning, the global declarations have no purpose without functions. Only functions have local variables. Variables do not belong to subroutines.
    ;Only functions have a defined body, starting with { and ending with }. Subroutines have only a starting point (a label). You might think of Return as the ending point, but it is just one way to transfer control, like goto, and it can be conditional (If). Subroutines can also overlap, either intentionally or If you forget Return.
    ;My new understanding, is ALL variables are global to ALL subroutines but global variables are ONLY usable in functions If you list them at the top of the function as global? 
    ;Don't conflate subroutines with variables - whether a variable is accessible has nothing to do with subroutines. Global variables are global. Only functions affect scope; only functions can have local variables. Functions can also contain subroutines, and those subroutines can access local/static variables (with caveats); but those are local to the function, not the subroutine.

    global GuisCreated
    static id:=0
    
    If (winHwnd == 0)
    {
        Return
    }
    Else If (x == "")
    {
      id:=0
      If print
          FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - deleting Range_%winHwnd%_3`n, C:\Users\vbonaven\Desktop\log.txt
      Gui, Range_%winHwnd%_3: Destroy
      Return
    }
    Else
    {
        If print
           FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - creating Range_%winHwnd%_3`n, C:\Users\vbonaven\Desktop\log.txt
           
        Gui, Range_%winHwnd%_3:New, +AlwaysOnTop -Caption +ToolWindow +HwndLinesHwnd -DPIScale +E0x08000000 +E0x20 -Caption +Owner +LastFound
        
        i:=3
        , x1:=(i=2 ? x+w : x-d)
        , y1:=(i=3 ? y+h : y-d)
        , w1:=(i=1 or i=3 ? w+2*d : d)
        , h1:=(i=2 or i=4 ? h+2*d : d)
        x1s := x1 + 2
        w1s := w1 - 5
        y1s := y1 - 4
        Gui, Range_%winHwnd%_%i%: Color, %color%
        
        LinesId = ahk_id %LinesHwnd%
        If fadeTrans
            WinSet, Transparent, 100, %LinesId%
            
        Gui, Range_%winHwnd%_%i%: Show, NA x%x1s% y%y1s% w%w1s% h%h1%
        
        GuisCreated[LinesHwnd] := winHwnd
        If fadeTrans
            FadeToTargetTrans(LinesId, 255, 100)
        WinSet, AlwaysOnTop, on, %LinesId%
    }
    Return
}

AdjustWinDims(ahkId := "", x_delta := 0, y_delta := 0)
{
    global minDimsAhkId, maxDimsAhkId, closeDimsAhkId
        
    for element in minDimsAhkId
    {
        If (ahkId == element)
        {  
        
            minDimsAhkId[element].X   :=   minDimsAhkId[element].X   + x_delta
            minDimsAhkId[element].XW  :=   minDimsAhkId[element].XW  + x_delta
            minDimsAhkId[element].Y   :=   minDimsAhkId[element].Y   + y_delta
            minDimsAhkId[element].YH  :=   minDimsAhkId[element].YH  + y_delta
            break
        }
    }
    
    for element in maxDimsAhkId
    {
        If (ahkId == element)
        {  
            maxDimsAhkId[element].X   :=   maxDimsAhkId[element].X   + x_delta
            maxDimsAhkId[element].XW  :=   maxDimsAhkId[element].XW  + x_delta
            maxDimsAhkId[element].Y   :=   maxDimsAhkId[element].Y   + y_delta
            maxDimsAhkId[element].YH  :=   maxDimsAhkId[element].YH  + y_delta
            break
        }
    }
            
    for element in closeDimsAhkId
    {
        If (ahkId == element)
        {         
            closeDimsAhkId[element].X  := closeDimsAhkId[element].X   + x_delta
            closeDimsAhkId[element].XW := closeDimsAhkId[element].XW  + x_delta
            closeDimsAhkId[element].Y  := closeDimsAhkId[element].Y   + y_delta
            closeDimsAhkId[element].YH := closeDimsAhkId[element].YH  + y_delta
            break
        }
    }
    Return
}

; https://msdn.microsoft.com/en-us/library/windows/desktop/ms724371(v=vs.85).aspx
; MsgBox % GetSysColor(13) . "`n" . GetSysColor(29)
GetSysColor(n)
{
    Local BGR := DllCall("User32.dll\GetSysColor", "Int", n, "UInt")
        , RGB := (BGR & 255) << 16 | (BGR & 65280) | (BGR >> 16)
    Return Format("0x{:06X}", RGB)
} 

HexToDec(hex)
{
    VarSetCapacity(dec, 66, 0)
    , val := DllCall("msvcrt.dll\_wcstoui64", "Str", hex, "UInt", 0, "UInt", 16, "CDECL Int64")
    , DllCall("msvcrt.dll\_i64tow", "Int64", val, "Str", dec, "UInt", 10, "CDECL")
    Return dec
}

SampleAccentColor(startingX := 0)
{
    global AccentColorHex, toolbarEl
    
    HexColor  :=
    buttonEl := toolbarEl.FindFirstBy("Name=running AND NOT Name=complete AND (ControlType=Button OR ControlType=MenuItem)", 0x4, 2, False)
    If buttonEl
    {
        taskButtonElPos := buttonEl.CurrentBoundingRectangle
        If (startingX > 0)
            x_coord := startingX+10
        Else
            x_coord := taskButtonElPos.l+10
        y_coord := taskButtonElPos.b-1
        PixelGetColor, HexColor, %x_coord%, %y_coord%, RGB
    }
    Else
    {
        HexColor := AccentColorHex
    }
    Return HexColor
}

GetAccentColor()
{
    ; RegRead, CheckReg, HKCU\SOFTWARE\Microsoft\Windows\DWM, ColorizationColor
    RegRead, CheckReg, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Accent, AccentPalette
    ; CheckRegHex := int2hex(Checkreg)
    CheckRegHex := SubStr(CheckReg, 25 , 6)
    ; StringRight, CheckRegHex, CheckRegHex, 7
    ; CheckRegDec := ceil(HexToDec(CheckRegHex)*2.26578842)
    ; CheckRegFinal := int2hex(CheckRegHex)
    ; Tooltip, %CheckReg% - %CheckRegfinal% - %CheckRegHex%
    Return CheckRegHex
}

join( strArray, allHex := False )
{
    s := ""
    for i,v in strArray
    {   If allHex
            s .= ", "  Format("{:#x}", i) . ":" . Format("{:#x}", v)
        Else    
            s .= ", "  Format("{:#x}", i) . ":" . v
    }
    Return substr(s, 3)
}

SessionIsLocked()
{
    static WTS_CURRENT_SERVER_HANDLE := 0, WTSSessionInfoEx := 25, WTS_SESSIONSTATE_LOCK := 0x00000000, WTS_SESSIONSTATE_UNLOCK := 0x00000001 ;, WTS_SESSIONSTATE_UNKNOWN := 0xFFFFFFFF
    ret := False
    If (DllCall("ProcessIdToSessionId", "UInt", DllCall("GetCurrentProcessId", "UInt"), "UInt*", sessionId)
     && DllCall("wtsapi32\WTSQuerySessionInformation", "Ptr", WTS_CURRENT_SERVER_HANDLE, "UInt", sessionId, "UInt", WTSSessionInfoEx, "Ptr*", sesInfo, "Ptr*", BytesReturned)) {
        SessionFlags := NumGet(sesInfo+0, 16, "Int")
        ; "Windows Server 2008 R2 and Windows 7: Due to a code defect, the usage of the WTS_SESSIONSTATE_LOCK and WTS_SESSIONSTATE_UNLOCK flags is reversed."
        ret := A_OSVersion != "WIN_7" ? SessionFlags == WTS_SESSIONSTATE_LOCK : SessionFlags == WTS_SESSIONSTATE_UNLOCK
        DllCall("wtsapi32\WTSFreeMemory", "Ptr", sesInfo)
    }
    Return ret
}

HasVal(haystack, needle) {
    for index, value in haystack
        if (value == needle)
            return True
    if !(IsObject(haystack))
        throw Exception("Bad haystack!", -1, haystack)
    return False
}
HasKey(haystack, needle) {
    for index, value in haystack
        if (index == needle)
            return True
    if !(IsObject(haystack))
        throw Exception("Bad haystack!", -1, haystack)
    return False
}

GetSize(haystack)
{
    size := 0
    for index, value in haystack
        size += 1
    return size
}

DesktopIcons( Show:=-1 )                  ; By SKAN for ahk/ah2 on D35D/D495 @ tiny.cc/desktopicons
{
    Local hProgman := WinExist("ahk_class WorkerW", "FolderView") ? WinExist()
                   :  WinExist("ahk_class Progman", "FolderView")
    Local hShellDefView := DllCall("user32.dll\GetWindow", "ptr",hProgman,      "int",5, "ptr")
    Local hSysListView  := DllCall("user32.dll\GetWindow", "ptr",hShellDefView, "int",5, "ptr")
    If ( DllCall("user32.dll\IsWindowVisible", "ptr",hSysListView) != Show )
         DllCall("user32.dll\SendMessage", "ptr",hShellDefView, "ptr",0x111, "ptr",0x7402, "ptr",0)
}
