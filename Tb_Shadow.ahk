#NoEnv 
#SingleInstance force 
#Persistent 
SetBatchLines, -1
SetWinDelay, -1   ; Makes the below move faster/smoother.
Process, Priority,, High
SysGet, MonitorWorkArea, MonitorWorkArea 
SysGet, MonitorArea, Monitor 
CmenuArrayIds        := []

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
Gui, -Caption +ToolWindow +Lastfound -Border +E0x08000000 +AlwaysOnTop
Gui, Color, FF00FF
Gui, Show, Center w%MonitorWorkAreaWidth% h%TaskBarHeight%  y%TaskBarYPosition%, AHK GUI1
FrameShadow(IGUI1)

WinSet, TransColor, FF00FF, ahk_id %IGUI1%
WinSet, Bottom, , ahk_id %IGUI1%

Gui, Shadow2:New
Gui, +HwndIGUI2
Gui, -Caption +ToolWindow +Lastfound -Border +E0x08000000 +AlwaysOnTop
Gui, Color, FF00FF
Gui, Show, Center w%MonitorWorkAreaWidth% h%TaskBarHeight% y%TaskBarYPosition%, AHK GUI2
FrameShadow(IGUI2)

WinSet, TransColor, FF00FF, ahk_id %IGUI2%
WinSet, Bottom, , ahk_id %IGUI2%

Gui, Shadow3:New
Gui, +HwndIGUI3
Gui, -Caption +ToolWindow +Lastfound -Border +E0x08000000 +AlwaysOnTop
Gui, Color, FF00FF
Gui, Show, Center w%MonitorWorkAreaWidth% h%TaskBarHeight% y%TaskBarYPosition%, AHK GUI3
FrameShadow(IGUI3)

WinSet, TransColor, FF00FF, ahk_id %IGUI3%
WinSet, Bottom, , ahk_id %IGUI3%

Gui, ShadowRM:New
Gui, +HwndIGUIR
Gui, -Caption +ToolWindow +Lastfound -Border +E0x08000000
WinSet, TransColor, F2F2F2 0, ahk_id %IGUIR%
Gui, Color, F2F2F2
Gui,Margin,0,0

WinSet, ExStyle, +0x20, ahk_id %IGUIR%
WinSet, AlwaysOnTop, On, ahk_id %IGUIR%

SetTimer, LookForMenu, 100
Return

~LButton::
    Gui, ShadowRM: Hide
    WinSet, TransColor, F2F2F2 0, ahk_id %IGUIR%
Return

~RButton::
    Gui, ShadowRM: Hide
    WinSet, TransColor, F2F2F2 0, ahk_id %IGUIR%
Return

LookForMenu:
    If (WinExist("ahk_class #32768"))
    {
        MouseGetPos , , , mId
        WinGetClass, mClass, ahk_id %mid%
        WinGet, winId, ID, ahk_class #32768
        
        WinGetPos, x, y, w, h, ahk_id %winId%
        If ((oldId != winId) && x && y && w && h)
        {
            Gui, ShadowRM: Hide
            
            rmenuX := x
            rmenuY := y
            rmenuW := w ;- 2
            rmenuH := h ;- 2
            
            Gui, ShadowRM:Show, NA x%rmenuX% y%rmenuY% w%rmenuW% h%rmenuH%, AHK GUI3 
            FrameShadow(IGUIR)
            WinSet, TransColor, F2F2F2 0, ahk_id %IGUIR%
            WinSet, AlwaysOnTop, On, ahk_id %IGUIR%
            
            transLevel := 0
            If !(HasVal(CmenuArrayIds, winId))
            {
                CmenuArrayIds.push(winId)
            }
            for idx, wid in CmenuArrayIds
            {
                If WinExist("ahk_id " . wid)
                    WinSet, AlwaysOnTop, On, ahk_id %wid%
            }
            loop % 30
            {
                sleep 5
                transLevel += 9
                If transLevel > 255
                    transLevel := 255
                WinSet, TransColor, F2F2F2 %transLevel%, ahk_id %IGUIR%
            }
        }
        oldId := winId
    }
    Else
    {
        Gui, ShadowRM: Hide
        WinSet, TransColor, F2F2F2 0, ahk_id %IGUIR%
        CmenuArrayIds := []
    }
Return

DefaultShadow:
    Menu, Tray, Check, Default Shadow
    Menu, Tray, UnCheck, Bold Shadow
    Gui, Shadow3:Hide
Return
    
BoldShadow:
    Menu, Tray, Check, Bold Shadow
    Menu, Tray, UnCheck, Default Shadow
    Gui, Shadow3:Show
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

HasVal(haystack, needle) {
    for index, value in haystack
        if (value == needle)
            return True
    if !(IsObject(haystack))
        throw Exception("Bad haystack!", -1, haystack)
    return False
}

;If !pToken := Gdip_Startup()
;{
;    MsgBox, 48, gdiplus error!, Gdiplus failed to start. Please ensure you have gdiplus on your system
;    ExitApp
;}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;https://www.autohotkey.com/boards/viewtopic.php?p=264086&force_isolation=true#p264086
;#NoEnv
;CS_DROPSHADOW := 0x00020000
;ClassStyle := GetGuiClassStyle()
;Gui, New, +hwndHGUI
;SetGuiClassStyle(HGUI, ClassStyle | CS_DROPSHADOW)
;Gui, Show, x100 y100 w250 h200, Test 1
;SetGuiClassStyle(HGUI, ClassStyle)
;Gui, New
;Gui, Show, x400 y100 w250 h200, Test 2
;Gui, New, +hwndHGUI
;SetGuiClassStyle(HGUI, ClassStyle | CS_DROPSHADOW)
;Gui, Show, x700 y100 w250 h200, Test 3
;SetGuiClassStyle(HGUI, ClassStyle)
;Return
;GuiClose:
;GuiEscape:
;ExitApp
;GetGuiClassStyle() {
;   Gui, GetGuiClassStyleGUI:Add, Text
;   Module := DllCall("GetModuleHandle", "Ptr", 0, "UPtr")
;   VarSetCapacity(WNDCLASS, A_PtrSize * 10, 0)
;   ClassStyle := DllCall("GetClassInfo", "Ptr", Module, "Str", "AutoHotkeyGUI", "Ptr", &WNDCLASS, "UInt")
;                 ? NumGet(WNDCLASS, "Int")
;                 : ""
;   Gui, GetGuiClassStyleGUI:Destroy
;   Return ClassStyle
;}
;SetGuiClassStyle(HGUI, Style) {
;   Return DllCall("SetClassLong" . (A_PtrSize = 8 ? "Ptr" : ""), "Ptr", HGUI, "Int", -26, "Ptr", Style, "UInt")
;}
