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

#Include %A_ScriptDir%\WinGetPosEx_pacobyte.ahk 
#Include %A_ScriptDir%\RunAsAdmin.ahk
#Include %A_ScriptDir%\Bass\BassLib_Me.ahk
#Include %A_ScriptDir%\UIA_Interface.ahk 

FileCreateDir, %A_ScriptDir%\x64
FileInstall, .\Bass\x64\bass.dll, %A_ScriptDir%\x64\bass.dll, 1
If ErrorLevel == 1
    msgbox, "Error bass.dll " %ErrorLevel%
    
FileInstall, PlasticBubbleClick.wav, %A_ScriptDir%\PlasticBubbleClick.wav, 0
If ErrorLevel == 1
    msgbox, "Error installing PlasticBubbleClick.wav " %ErrorLevel%

FileInstall, Null.wav, %A_ScriptDir%\Null.wav, 0
If ErrorLevel == 1
    msgbox, "Error installing Null.wav " %ErrorLevel%
    
global Sound_Close  := "PlasticBubbleClick.wav"
global Null_Snd     := "Null.wav"
    
Wheel_disabled := false
TransparentValue := 120
KDE_WinUp    :=
KDE_WinLeft  :=
EWD_winId    :=
MonitorWorkArea :=
MButtonPreviousTick :=
DoubleClickTime := DllCall("GetDoubleClickTime") 

LookForLeaveWindow := False
winCount := 0
fifteenMinutes := 1000*60*5

SysGet, MonitorWorkArea, MonitorWorkArea 

Menu, Tray, Icon
Menu, Tray, NoStandard
Menu, Tray, Add, Run at startup, strtup
Menu, Tray, Add, Suspend, Suspend_label
Menu, Tray, Add, Reload, Reload_label
Menu, Tray, Add, Exit, Exit_label

WindowArray          := []
PeaksArray           := []
WinVisiblePercArray  := []
WinBackupXs          := []
WinBackupColors      := []
WinBackupTrans       := []
GuisCreated          := []
windowEls            := []

percLeft            := 1.0
edgePercentage      := .04
HoveringWinHwnd     := 
lastWindowPeaked    := False
MouseMoveBuffer     := 50
PrintButton         := False
PossiblyChangedSize := False
ForceButtonUpdate   := False
ResetMousePosBkup   := False
ExplorerSpawned     := False
TaskbarPeak         := False

mEl                := {}
npEl               := {}
minimizeEl         := {}
maximizeEl         := {}
closeEl            := {}
windowEls          := {}
LastRemovedWinHwnd := 
firstButtonPosXOld := 0
winCountOld        := 0

BlockInput, On
global UIA       := UIA_Interface()
global tbEl      := UIA.ElementFromHandle("ahk_class Shell_TrayWnd")
global toolbarEl := tbEl.FindFirstBy("ClassName=MSTaskListWClass AND ControlType=Toolbar")

Msgbox, 0, EzWindowManager, Detecting Theme Accent Color...%AccentColorHex%, 2
global AccentColorHex := SampleAccentColor()

BlockInput, Off
Tooltip, %AccentColorHex%
sleep 2000
Tooltip, 

t_KeepOnTop := t_WatchMouse := t_CheckButtonSize := t_ButCapture := t_RedetectColor := t_CheckButtonColor := A_TickCount 

SetTimer, MasterTimer, 5, -1
SetTimer, OtherTimer, 500

Return

strtup:
    Menu, Tray, Togglecheck, Run at startup
    IfExist, %A_Startup%/EZWindowManager.lnk
        FileDelete, %A_Startup%/EZWindowManager.lnk
    else FileCreateShortcut, % H_Compiled ? A_AhkPath : A_ScriptFullPath, %A_Startup%/EZWindowManager.lnk
Return

Tray_SingleLclick:
    msgbox You left-clicked tray icon
Return
   
Reload_label:
    Reload
Return
  
Suspend_label:
    loop 2
    Settimer, Tray_SingleLclick, Off
    Menu, Tray, Togglecheck, Suspend
    Suspend
Return
  
Exit_label:
    exitapp
Return  

OtherTimer:
    MouseGetPos, omx, omy, otherMouseWinHwnd
    WinGetClass, otherClass, ahk_id %otherMouseWinHwnd%
    If ((abs(omx - omx2) > 10 || abs(omy != omy2) > 10) && otherClass == "WorkerW" && GetKeyState("LButton", "P"))
    {
        DesktopIcons(True)
    }
    omx2 := omx
    omy2 := omy
Return

MasterTimer:
    If (GetKeyState("MButton", "P"))
    {
        sleep 1000
        Return
    }
    
    MouseGetPos, MXw, MYw, MouseWinHwnd
    winId = ahk_id %MouseWinHwnd%
    WinGet, winHwnd, ID, %winId%
    WinGetClass, mtClass, %winId%
    WinGetPosEx(winHwnd, WinX, WinY, WinW, WinH, OffL, OffT, OffR, OffB)
                
    If (((A_TickCount-t_ButCapture) >= 50 && (((MXw > ((WinX+WinW)-215)) && (MXw < (WinX+WinW)) && (MYw > WinY) && (MYw < (WinY+32)))) && mtClass != "Shell_TrayWnd") || (mtClass == "TaskListThumbnailWnd" || mtClass == "Windows.UI.Core.CoreWindow" || mtClass == "#32770"))
    {
        GoSub, ButCapture
        t_ButCapture := A_TickCount
    }
    Else If ((A_TickCount-t_WatchMouse) >= 100)
    {
        GoSub, WatchMouse
        t_WatchMouse := A_TickCount
    }
    Else If (((A_TickCount-t_ButCapture) >= 50 && (((MXw > ((WinX+WinW)-215)) && (MXw < (WinX+WinW)) && (MYw > WinY) && (MYw < (WinY+32))) && mtClass != "Shell_TrayWnd") || (mtClass == "TaskListThumbnailWnd" || mtClass == "Windows.UI.Core.CoreWindow" || mtClass == "#32770")))
    {
        GoSub, ButCapture
        t_ButCapture := A_TickCount
    }
    Else If ((A_TickCount-t_CheckButtonSize) >= 200)
    {
        GoSub, CheckButtonSize
        t_CheckButtonSize := A_TickCount
    }
    Else If ((A_TickCount-t_CheckButtonColor) >= 100)
    {
        GoSub, CheckButtonColor
        t_CheckButtonColor := A_TickCount
    }    
    Else If ((A_TickCount-t_RedetectColor) >= fifteenMinutes)
    {
        GoSub, ReDetectAccentColor
        t_RedetectColor := A_TickCount
    }
    Else
    {
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
                
                If (WinX < 0) && (lastWindowPeaked ||  ((MXw-MXw_bkup) < -1*MouseMoveBuffer)) {
                    WinSet, AlwaysOnTop, On, %winId%
                    LookForLeaveWindow := True
                    HoveringWinHwnd    := MouseWinHwnd
                    MoveToTargetSpot(winId, 0-offL, WinX)
                    FadeToTargetTrans(winId, 255, 200)
                    lastWindowPeaked   := True
                    Break
                }
                Else If (WinX+WinH > A_ScreenWidth) && (lastWindowPeaked ||  ((MXw-MXw_bkup) > MouseMoveBuffer)) {
                    WinSet, AlwaysOnTop, On, %winId%
                    LookForLeaveWindow := True
                    HoveringWinHwnd    := MouseWinHwnd
                    MoveToTargetSpot(winId, A_ScreenWidth-WinW-OffR, WinX)
                    FadeToTargetTrans(winId, 255, 200)
                    lastWindowPeaked   := True
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
            WinGetTitle, title, ahk_id %MouseWinHwnd%
            for k, v in WinBackupXs 
            {
               If (k == HoveringWinHwnd)
               {
                  WinGetTitle, title, ahk_id %HoveringWinHwnd%
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
            kx := Format("{:#x}", k)
            winId = ahk_id %kx%
            orgX := WinBackupXs[k]
            
            WinSet, Bottom, , %winId%
            WinGet, except, ProcessName, %winId%
            If (except == "Signal.exe")
               OffR := 0
            
            WinMove, %winId%,, orgX-OffR
            transLevel := WinBackupTrans[winId]
            FadeToTargetTrans(winId, transLevel)
            WinSet, Bottom, , %winId%
            sleep 200
         }
         LookForLeaveWindow := False
    }
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
           FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - Array: %arr%`n, C:\Users\vbonaven\Desktop\log.txt
           FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - Stray %winHwndX%`n, C:\Users\vbonaven\Desktop\log.txt
           WinBackupXs.remove(winHwndX)
           RangeTip( , , , , , , Format("{:#x}", winHwndX), False)
        }
        
        If (WinBackupXs.MaxIndex() > 0)
        {
            arr := join(WinBackupXs)
            FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - Array: %arr%`n, C:\Users\vbonaven\Desktop\log.txt
        }
        
        for winHwnd, winXpos in WinBackupXs {
             winHwndX := Format("{:#x}", winHwnd)
             ; FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - %winHwndX%`n, C:\Users\vbonaven\Desktop\log.txt
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
                    ; FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - %regexSub%`n, C:\Users\vbonaven\Desktop\log.txt
                    If (buttonEl != "")
                        break
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
                ; FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - %regexTitle%`n, C:\Users\vbonaven\Desktop\log.txt
             If (!buttonEl)
             {
                typeString := % "AutomationId=" wProcess " OR Automation=" procNameArray[1]
                buttonEl := toolbarEl.FindFirstBy(typeString, 0x4, 2, False)
             }
             
             If (buttonEl)
             {
                 taskButtonElPos := buttonEl.CurrentBoundingRectangle
                 If (taskButtonElPos.l != 0)
                 {
                     targetColor := SampleAccentColor(taskButtonElPos.l)
                     RangeTip(taskButtonElPos.l, taskButtonElPos.t, taskButtonElPos.r-taskButtonElPos.l, taskButtonElPos.b-taskButtonElPos.t, targetColor, 2, winHwndX, True)
                 }
             }
        }
    }
    firstButtonPosXOld := firstButtonPosX
Return 

CheckButtonColor:
    for winHwnd, winXpos in WinBackupXs {
         winHwndX := Format("{:#x}", winHwnd)
         buttonWinId = ahk_id %winHwnd%
         WinGet, wProcess, ProcessName, %buttonWinId%
         WinGetTitle, wTitle, %buttonWinId%
         preparedTitle1 := StrReplace(wTitle, "\", "\\")
         preparedTitle2 := StrReplace(preparedTitle1, ".", "\.")
         regexTitle := preparedTitle2 . ".*running"
         wtf := Format("{:#x}", winHwnd)
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
                    break
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
         
         If (!buttonEl)
         {
            typeString := % "AutomationId=" wProcess " OR Automation=" procNameArray[1]
            buttonEl := toolbarEl.FindFirstBy(typeString, 0x4, 2, False)
         }
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
                        ; tooltip, % "2)"targetColor "-" AccentColorHex "-" storedColor
                        WinBackupColors[winHwnd] := targetColor
                        RangeTip(taskButtonElPos.l, taskButtonElPos.t, taskButtonElPos.r-taskButtonElPos.l, taskButtonElPos.b-taskButtonElPos.t, targetColor, 2, wtf, True, False)
                     }
                 }
             }
         }
    }
Return

$MButton::
    SetTimer, MasterTimer, Off
    EWD_MouseOrgX       := 0
    EWD_MouseOrgY       := 0
    EWD_MouseX          := 0
    EWD_MouseY          := 0
    
    MouseGetPos, MX, MY, EWD_MouseWinHwnd ; Get cursor position
    EWD_winId = ahk_id %EWD_MouseWinHwnd% ; Get the active window's title
    WinGet, EWD_winHwnd, ID, %EWD_winId% ; Get the title's text
    WinGet, EWD_WinState, MinMax, %EWD_winId% ; Get window state
    WinGetClass, EWD_winClass, %EWD_winId%
    
    EWD_MouseX          := MX 
    EWD_MouseOrgX       := MX 
    EWD_MouseY          := MY 
    EWD_MouseOrgY       := MY 
    
    MButtonPreviousTick := A_TickCount
    
    MouseMoved          := False
    registerRbutton     := False
    TimeSinceStop       := A_TickCount
    ToggledOnTop        := False
    ChangedDims         := False
    WinLEdge            := False
    WinREdge            := False
    
    If (EWD_WinState = 1)
    {
        Return
    }
    
    If (EWD_winClass == "WorkerW")
    {
        KeyWait, MButton, T3
        Send {MButton}
        Return
    }
    
    Wheel_disabled := true
    WinGetPosEx(EWD_winHwnd, EWD_WinX, EWD_WinY, EWD_WinW, EWD_WinH, EWD_OffL, EWD_OffT, EWD_OffR, EWD_OffB)
    
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
            BASS_Play(Null_Snd, 1.0)
            BASS_Play(Sound_Close, 1.0)
            Send !{F4}
            CleanUpStoredWindow(EWD_winId, EWD_MouseWinHwnd)
        }
        Else If (!ToggledOnTop) {
            Send {MButton}
        }
    }
    Wheel_disabled := false
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
              {
                 FadeToTargetTrans(EWD_winId, 100, TransparentValue)
                 WinBackupTrans[EWD_winId] := 100
              }
              Else
              {
                 FadeToTargetTrans(EWD_winId, 200, TransparentValue)
                 WinBackupTrans[EWD_winId] := 200
              }
              PeaksArray.push(EWD_winId)
              WinBackupXs[EWD_MouseWinHwnd] := EWD_WinX
              FileAppend, %A_MM%/%A_DD%/%A_YYYY% @ %A_Hour%:%A_Min%:%A_Sec% - Make %EWD_MouseWinHwnd%:%EWD_WinX%`n, C:\Users\vbonaven\Desktop\log.txt
              ForceButtonRemove := True
              ResetMousePosBkup := True
              WinSet, Bottom, , %EWD_winId%
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
                 PeaksArray.remove(removeIdx)
                 WinBackupXs.remove(EWD_MouseWinHwnd)
              }
              
           }
           Else If ((percentageLeft >= 0.40) && (WinLEdge || WinREdge))
           {
              for k, v in WinBackupXs {
                 If (k == EWD_MouseWinHwnd)
                 {
                     ; tooltip, window edging!
                     LookForLeaveWindow  := True
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
        If (((EWD_MouseX != EWD_MouseOrgX) || (EWD_MouseY != EWD_MouseOrgY)))
        {
            MouseMoved := true
            MButtonPreviousTick := A_TickCount
        }
        
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
        ; CORRECTIONS FOR TOP AND BOTTOM OF WINDOW
        If (EWD_WinH > MonitorWorkAreaBottom) ; fix too tall window
        {
            WinMove, %EWD_winId%,, , 0 , , MonitorWorkAreaBottom+EWD_OffB
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
            registerRbutton := true
        Else
            registerRbutton := false
            
        ; MOVE ADJUSTMENTS
        If (!registerRbutton && MouseMoved)
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
                If ((EWD_MouseX - EWD_MouseOrgX) > floor(MouseMoveBuffer/3))
                {
                    ; Tooltip, "3"
                    WinMove, %EWD_winId%,, EWD_WinXF + (EWD_MouseX - EWD_MouseOrgX), EWD_WinY + (EWD_MouseY - EWD_MouseOrgY)
                    WinLEdge := False
                }
                MButtonPreviousTick := A_TickCount
            }
            Else If (WinREdge) ; && (EWD_MouseX - EWD_MouseOrgX) < 0) 
            {
                If ((EWD_MouseX - EWD_MouseOrgX) < ceil(-1*MouseMoveBuffer/3))
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
        Else If (registerRbutton && MouseMoved)
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
                                      ,  EWD_WinY  +   (KDE_WinUp+1)/2*DiffY  ; Y of resized window
                                      , ;EWD_WinWF -     KDE_WinLeft *DiffX  ; W of resized window
                                      , (EWD_WinH + EWD_OffB) - KDE_WinUp *DiffY  ; H of resized window
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
                                      , (EWD_WinH + EWD_OffB) - KDE_WinUp *DiffY  ; H of resized window
                ChangedDims := True
            }
            
            If (ChangedDims)
            {
                ; Tooltip, 9
                WinGetPosEx(EWD_winHwnd, newX, newY, newW, newH)
                newB := newY+newH    
                If  ((EWD_WinX > 0 && newX == 0) || ((EWD_WinX+EWD_WinW) < A_ScreenWidth && (newX+newW) == A_ScreenWidth))
                {
                    sleep 400
                }
                Else If ((EWD_WinY > 0 && newY == 0) || (EWD_WinB < MonitorWorkAreaBottom && newB == MonitorWorkAreaBottom))
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

!LButton::
~LButton::
    SetTimer, MasterTimer, Off
    savedWin := False
    showDesktopD := False
    showDesktopU := False
    PossiblyChangedSize := False
    MouseGetPos, lmx, lmy, ClickedWinHwnd
    WinGetClass, class, ahk_id %ClickedWinHwnd%
    mWinClickedID = ahk_id %ClickedWinHwnd%
    WinGet, mWinClickeHwnd, ID, %mWinClickedID%
    WinGetPos, lb_x, lb_y, lb_w, lb_h, %mWinClickedID%
    
    If (class == "WorkerW")
        showDesktopD := True
        
    If (IsWindowFullScreen(ClickedWinHwnd, lb_w, lb_h))
    {
      Menu, Tray, Togglecheck, Suspend
      Suspend
      exit
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
    
    PrintButton := True
    Gosub, ButCapture
    
    KeyWait, LButton, T30
    MouseGetPos, lmx2, lmy2, ClickedWinHwndU
    WinGetClass, classU, ahk_id %ClickedWinHwndU%
    
    If (classU == "WorkerW")
        showDesktopU := True
    
    If showDesktopD && showDesktopU
        DesktopIcons(True)
    Else If (!showDesktopD && showDesktopU && (lmx != lmx2 || lmy != lmy2))
        DesktopIcons(True)
    Else
    {    
        DesktopIcons(False)
        
        WinGetPos, lb_x2, lb_y2, lb_w2, lb_h2, %mWinClickedID%
        If (savedWin && (lb_w != lb_w2 || lb_h != lb_h2))
        {
            PossiblyChangedSize := True
            LookForLeaveWindow := True
            HoveringWinHwnd := ClickedWinHwnd
        }
        Wheel_disabled :=  False ; catchall in case for some reason wheel is still disabled
    }
    
    SetTimer, MasterTimer, On
Return 

SendCtrlAdd:
    If (WinActive("ahk_class CabinetWClass"))
    {
        sleep 200
        Send ^{NumpadAdd}
    }
Return

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
        BASS_Play(Null_Snd, 1.0)
        BASS_Play(Sound_Close, 1.0)
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
    If (GetKeyState("MButton", "P") || (mtClass == "WorkerW") || (mtClass == "Shell_TrayWnd"))
    {
        Return 
    }
    
    WinGet, winExe, ProcessName, %winId%
    WinGetTitle, winTitle, %winId%

    If (!PrintButton && winExe != "Spotify.exe")
    {
        try {
               If (mtClass == "Chrome_WidgetWin_1" && winTitle != "Messages for web")
               {
                    mEl := UIA.SmallestElementFromPoint(MXw, MYw, True, UIA.ElementFromHandle(winId))
               }
               Else If (winExe == "notepad++.exe")
               {
                    mEl := UIA.ElementFromPoint(MXw, MYw)
               }
               Else If (winTitle)
               {
                    mEl := UIA.SmallestElementFromPoint(MXw, MYw, True, "")
               }
               Else
               {
                   mEl := UIA.ElementFromPoint(MXw, MYw)
               }       
            } catch e {
            
            }
    }
    Else
    {
       try {     
            ;---------------------------------------------------------------------------------------------------------------------------------------
            ;minimizePos := minimizeEl.GetCurrentPos()
            ;maximizePos := maximizeEl.GetCurrentPos()
            ;closePos    := closeEl.GetCurrentPos()
            ;If ((mX >= minimizePos.x) && (mX <= (minimizePos.x+minimizePos.w)) && (mY >= minimizePos.y) && (mY <= (minimizePos.y+minimizePos.h)))
            ;    ToolTip, minimize!
            ;Else If ((mX >= maximizePos.x) && (mX <= (maximizePos.x+maximizePos.w)) && (mY >= maximizePos.y) && (mY <= (maximizePos.y+maximizePos.h)))
            ;    ToolTip, maximize!
            ;Else If ((mX >= closePos.x) && (mX <= (closePos.x+closePos.w)) && (mY >= closePos.y) && (mY <= (closePos.y+closePos.h)))
            ;{
            ;    ToolTip, close!
            ;}
            ;---------------------------------------------------------------------------------------------------------------------------------------
            
            If InStr(mEl.CurrentName, "Close")
            {
                BASS_Play(Null_Snd, 1.0)
                BASS_Play(Sound_Close, 1.0)
                removeId  := False
                removeIdx := 0

                for idx, val in PeaksArray {
                  If (val == winId) {
                      WinSet, AlwaysOnTop, off, %winId%
                      LookForLeaveWindow := False
                      removeId           := True
                      removeIdx          := idx
                      Break
                     }
                  }
                  
                If removeId
                {
                    PeaksArray.remove(removeIdx)
                    WinBackupXs.remove(mHwnd)
                    LastRemovedWinHwnd :=mHwnd
                    ForceButtonRemove  := True
                }
                ; Tooltip, %mtClass% " closed! " %LastRemovedWinId%
                ; sleep 700
                ; Tooltip, 
                mEl := {}
            }
            Else If InStr(mEl.CurrentName, "Maximize")
            {
                Tooltip, %mtClass% " maximize!"
                sleep 500
                Tooltip, 
                mEl := {}
            }
            Else If InStr(mEl.CurrentName, "Minimize")
            {
                Tooltip, %mtClass% " minimize!"
                sleep 500
                Tooltip, 
                mEl := {}
            }
        } catch e {
        
        }
        PrintButton := False
    }    
Return

CleanUpStoredWindow(ahkId := "", hwnd := "")
{
    global ForceButtonRemove, LastRemovedWinHwnd, PeaksArray, WinBackupXs, WinBackupColors, WinBackupTrans
    
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
        WinBackupTrans.remove(ahkId)
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
           
        Gui, Range_%winHwnd%_3:New, +AlwaysOnTop -Caption +ToolWindow +HwndLinesHwnd -DPIScale +E0x08000000
        
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
        WinSet, ExStyle, +0x20, %LinesId%
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

IsWindowFullScreen(WinID, winW, winH) 
{
    WinGetClass, wclass, ahk_id %WinID%
    If !(WinExist("ahk_id " . WinID))
        Return
        
    WinGet, wstyle, Style, ahk_id %WinID%
    ; WinGetPos ,,,winW,winH, %winTitle%
    ;; 0x800000 is WS_BORDER.
    ;; 0x20000000 is WS_MINIMIZE.
    ;; no border and not minimized
    ;Return ((style & 0x20800000) or winH < A_ScreenHeight or winW < A_ScreenWidth) ? False : True
    If ((winW >= A_ScreenWidth && winH >= A_ScreenHeight) && !(wstyle & 0x20800000) && (wclass != "WorkerW"))
    {
        WinGetTitle, EWD_winTitleText, ahk_id %WinID% ; Get the title's text
        ; MsgBox, %winTitle% - %EWD_winTitleText%
        SoundBeep, 400, 40
        Return True
    }
    Else
    {
        Return False
    }
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