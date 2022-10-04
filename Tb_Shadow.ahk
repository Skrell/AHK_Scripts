#NoEnv 
#SingleInstance force 
#Persistent 
SetTitleMatchMode RegEx

SysGet, MonitorWorkArea, MonitorWorkArea 
SysGet, MonitorArea, Monitor 

MonitorWorkAreaWidth := MonitorWorkAreaRight - MonitorWorkAreaLeft

If (MonitorWorkAreaTop == 0)
{
    TaskBarHeight := MonitorAreaBottom - MonitorWorkAreaBottom
    TaskBarYPosition := MonitorWorkAreaBottom
}
Else
{
    TaskBarHeight := MonitorWorkAreaTop - MonitorAreaTop
    TaskBarYPosition := 0
}

Menu, Tray, Icon
Menu, Tray, NoStandard
Menu, Tray, Add, Run at Startup, strtup
Menu, Tray, Add, Reload, Reload_label
Menu, Tray, Add, Suspend, Suspend_label
Menu, Tray, Add, Default Shadow, DefaultShadow
Menu, Tray, Add, Bold Shadow, BoldShadow
Menu, Tray, Add, Exit, Exit_label
Menu, Tray, Check, Bold Shadow
IfExist, %A_Startup%/Tb_Shadow.lnk
    Menu, Tray, Check, Run at Startup


Gui, Shadow1:New
Gui, +HwndIGUI1
Gui, -Caption +ToolWindow +Lastfound -Border
Gui, Color, FF00FF
Gui, Show, Center w%MonitorWorkAreaWidth% h%TaskBarHeight%  y%TaskBarYPosition%, AHK GUI1
FrameShadow(IGUI1)

WinSet, TransColor, FF00FF, ahk_id %IGUI1%
WinSet, Bottom, , ahk_id %IGUI1%

WinSet_Click_Through(IGUI1,"On")

Gui, Shadow2:New
Gui, +HwndIGUI2
Gui, -Caption +ToolWindow +Lastfound -Border
Gui, Color, FF00FF
Gui, Show, Center w%MonitorWorkAreaWidth% h%TaskBarHeight% y%TaskBarYPosition%, AHK GUI2
FrameShadow(IGUI2)

WinSet, TransColor, FF00FF, ahk_id %IGUI2%
WinSet, Bottom, , ahk_id %IGUI2%

WinSet_Click_Through(IGUI2,"On")
Return

DefaultShadow:
    Menu, Tray, Check, Default Shadow
    Menu, Tray, UnCheck, Bold Shadow
    Gui, Shadow2:Hide
Return
    
BoldShadow:
    Menu, Tray, Check, Bold Shadow
    Menu, Tray, UnCheck, Default Shadow
    Gui, Shadow2:Show
Return

strtup:
    Menu, Tray, Togglecheck, Run at Startup
    IfExist, %A_Startup%/Tb_Shadow.lnk
        FileDelete, %A_Startup%/Tb_Shadow.lnk
    else FileCreateShortcut, % H_Compiled ? A_AhkPath : A_ScriptFullPath, %A_Startup%/Tb_Shadow.lnk
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

/*
WinSet_Click_Through - Makes a window unclickable.

I - ID of the window to set as unclickable.

T - The transparency to set the window. Leaving it blank will set it to 254. It can also be set On or Off. Any numbers lower then 0 or greater then 254 will simply be changed to 254.

If the window ID doesn't exist, it returns 0.
*/

WinSet_Click_Through(IDHWND, T="254") {
    IfWinExist, % "ahk_id " I
    {
        If (T == "Off")
        {
            WinSet, AlwaysOnTop, Off, % "ahk_id " I
            WinSet, Transparent, Off, % "ahk_id " I
            WinSet, ExStyle, -0x20, % "ahk_id " I
        }
        Else
        {
            WinSet, AlwaysOnTop, On, % "ahk_id " I
            If(T < 0 || T > 254 || T == "On")
                T := 254
            WinSet, Transparent, % T, % "ahk_id " I
            WinSet, ExStyle, +0x20, % "ahk_id " I
        }
    }
    Else
        Return 0
}


ShadowBorder(handle)
{
    DllCall("user32.dll\SetClassLongPtr", "ptr", handle, "int", -26, "ptr", DllCall("user32.dll\GetClassLongPtr", "ptr", handle, "int", -26, "uptr") | 0x20000)
}

FrameShadow(handle) {
    DllCall("dwmapi\DwmIsCompositionEnabled","IntP",_ISENABLED) ; Get if DWM Manager is Enabled
    if !_ISENABLED ; if DWM is not enabled, Make Basic Shadow
        DllCall("SetClassLong","UInt",handle,"Int",-26,"Int",DllCall("GetClassLong","UInt",handle,"Int",-26)|0x20000)
    else {
        VarSetCapacity(_MARGINS,16)
        NumPut(1,&_MARGINS,0,"UInt")
        NumPut(1,&_MARGINS,4,"UInt")
        NumPut(1,&_MARGINS,8,"UInt")
        NumPut(1,&_MARGINS,12,"UInt")
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", handle, "UInt", 2, "Int*", 2, "UInt", 4)
        DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", handle, "Ptr", &_MARGINS)
    }
}