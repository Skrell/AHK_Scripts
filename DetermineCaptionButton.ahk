; https://www.autohotkey.com/boards/viewtopic.php?t=31119#p145253
;get information from object under cursor, 'AccViewer Basic' (cf. AccViewer.ahk)
; #q::
   ; WinGet, procName, ProcessName, A
   ; If (procName == "chrome.exe") {
        ; MouseGetPos, , , hWnd
        ; Msgbox, % JEE_ChromeGetTabCount(hWnd)
   ; }
; Return

If !A_IsAdmin {
    tooltip, NOT ADMIN!
    sleep, 1000
    tooltip,
    Return
}

#If MouseIsOverTaskbar() || MouseIsOverTaskbarWidgets()
~^lbutton::
    SysGet, MonCount, MonitorCount
    WinGetClass, activeClass, A
    WinGet, activeID, ID, A

    KeyWait, Lbutton, U T3
    sleep, 250
    WinGetClass, targetClass, A
    WinGet, targetID, ID, A
    
    If (targetID != activeID && targetClass != "Windows.UI.Core.CoreWindow" && targetClass != "TaskListThumbnailWnd") {
        WinGet, targetProcess, ProcessName, A
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
Return
#If

#If MouseIsOverTaskbarWidgets()
~lbutton::
    CoordMode, Mouse, Screen
    MouseGetPos, vPosX, vPosY, hWnd

    vName := WhichButton(vPosX, vPosY, hWnd)

    ; vOutput .= "value: " vValue "`r`n"
    ToolTip, % vName
    sleep, 500
    tooltip
    Return
#If

#If MouseIsOverCaptionButtons()
^lbutton up::
    CoordMode, Mouse, Screen
    SysGet, MonCount, MonitorCount
    MouseGetPos, vPosX, vPosY, hWnd

    WinGet, targetProcess, ProcessName, ahk_id %hWnd%
    WinGetClass, targetClass, ahk_id %hWnd%

    If targetProcess == "svchost.exe"
        Return
    
    vName := WhichButton(vPosX, vPosY, hWnd)
    
    If (InStr(vName,"close",false)) {
        tooltip, Closing all windows...
        WinGet, windowsFromProc, list, ahk_exe %targetProcess% ahk_class %targetClass%
        loop % windowsFromProc
        {
            hwndID := windowsFromProc%A_Index%
            If (MonCount > 1) {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
                If currentMonHasActWin
                    WinClose, ahk_id %hwndID%
            }
            Else
                WinClose, ahk_id %hwndID%
        }
    }
    If (InStr(vName,"minimize",false)) {
        tooltip, Minimizing all windows...
        WinGet, windowsFromProc, list, ahk_exe %targetProcess% ahk_class %targetClass%
        loop % windowsFromProc
        {
            hwndID := windowsFromProc%A_Index%
            If (MonCount > 1) {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := IsWindowOnCurrMon(hwndId, currentMon)
                If currentMonHasActWin
                    WinMinimize, ahk_id %hwndId%
            }
            Else {
                WinMinimize, ahk_id %hwndID%
            }
        }
    }
    sleep, 500
    tooltip,
Return

lbutton up::
    CoordMode, Mouse, Screen
    MouseGetPos, vPosX, vPosY, hWnd

    vName := WhichButton(vPosX, vPosY, hWnd)

    If (InStr(vName,"minimize",false)) {
        ; WinMinimize, ahk_id %hWnd%
        Send, {Lbutton Down}{Lbutton Up}
    }
    Else If (InStr(vName,"maximize",false)) {
        ; WinGet, state, MinMax, ahk_id %hWnd%
        ; If (state == 0)
            ; WinMaximize, ahk_id %hWnd%
        ; Else
            ; WinRestore, ahk_id %hWnd%
        Send, {Lbutton Down}{Lbutton Up}
    }
    Else If (InStr(vName,"close",false)) {
        ; WinClose, ahk_id %hWnd%
        Send, {Lbutton Down}{Lbutton Up}
    }
    Else If (InStr(vName,"restore",false)) {
        ; WinRestore, ahk_id %hWnd%
        Send, {Lbutton Down}{Lbutton Up}
    }
    Else If (!InStr(vName,"close",false) && !InStr(vName,"restore",false) && !InStr(vName,"maximize",false) && !InStr(vName,"minimize",false))
        Send, {Lbutton Down}{Lbutton Up}

    ; vOutput .= "value: " vValue "`r`n"
    ToolTip, % vName
    sleep, 500
    tooltip
    Return
#If

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
        
        titlebarHeight := SM_CYMIN-SM_CYSIZEFRAME
        
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
    ; if (vRoleText1 == vRoleText2)
        ; vOutput .= "role text: " vRoleText1 "`r`n"
    ; else
    ; vOutput .= "role text (1): " vRoleText1 "`r`n" "role text (2): " vRoleText2 "`r`n"
    If !errorFound
        vOutput .= "name: " vName ; "`r`n"
    Else
        vOutput .= "error: " vName ; "`r`n"
    Return vOutput
}

Acc_Init()
{
    Static  h
    If Not  h
        h:=DllCall("LoadLibrary","Str","oleacc","Ptr")
}
Acc_ObjectFromEvent(ByRef _idChild_, hWnd, idObject, idChild)
{
    Acc_Init()
    If  DllCall("oleacc\AccessibleObjectFromEvent", "Ptr", hWnd, "UInt", idObject, "UInt", idChild, "Ptr*", pacc, "Ptr", VarSetCapacity(varChild,8+2*A_PtrSize,0)*0+&varChild)=0
    Return  ComObjEnwrap(9,pacc,1), _idChild_:=NumGet(varChild,8,"UInt")
}

Acc_ObjectFromPoint(ByRef _idChild_ = "", x = "", y = "")
{
    Acc_Init()
    If  DllCall("oleacc\AccessibleObjectFromPoint", "Int64", x==""||y==""?0*DllCall("GetCursorPos","Int64*",pt)+pt:x&0xFFFFFFFF|y<<32, "Ptr*", pacc, "Ptr", VarSetCapacity(varChild,8+2*A_PtrSize,0)*0+&varChild)=0
    Return  ComObjEnwrap(9,pacc,1), _idChild_:=NumGet(varChild,8,"UInt")
}

Acc_ObjectFromWindow(hWnd, idObject = -4)
{
    Acc_Init()
    If  DllCall("oleacc\AccessibleObjectFromWindow", "Ptr", hWnd, "UInt", idObject&=0xFFFFFFFF, "Ptr", -VarSetCapacity(IID,16)+NumPut(idObject==0xFFFFFFF0?0x46000000000000C0:0x719B3800AA000C81,NumPut(idObject==0xFFFFFFF0?0x0000000000020400:0x11CF3C3D618736E0,IID,"Int64"),"Int64"), "Ptr*", pacc)=0
    Return  ComObjEnwrap(9,pacc,1)
}

Acc_WindowFromObject(pacc)
{
    If  DllCall("oleacc\WindowFromAccessibleObject", "Ptr", IsObject(pacc)?ComObjValue(pacc):pacc, "Ptr*", hWnd)=0
    Return  hWnd
}

Acc_GetRoleText(nRole)
{
    nSize := DllCall("oleacc\GetRoleText", "Uint", nRole, "Ptr", 0, "Uint", 0)
    VarSetCapacity(sRole, (A_IsUnicode?2:1)*nSize)
    DllCall("oleacc\GetRoleText", "Uint", nRole, "str", sRole, "Uint", nSize+1)
    Return  sRole
}

Acc_GetStateText(nState)
{
    nSize := DllCall("oleacc\GetStateText", "Uint", nState, "Ptr", 0, "Uint", 0)
    VarSetCapacity(sState, (A_IsUnicode?2:1)*nSize)
    DllCall("oleacc\GetStateText", "Uint", nState, "str", sState, "Uint", nSize+1)
    Return  sState
}

Acc_SetWinEventHook(eventMin, eventMax, pCallback)
{
    Return  DllCall("SetWinEventHook", "Uint", eventMin, "Uint", eventMax, "Uint", 0, "Ptr", pCallback, "Uint", 0, "Uint", 0, "Uint", 0)
}

Acc_UnhookWinEvent(hHook)
{
    Return  DllCall("UnhookWinEvent", "Ptr", hHook)
}
/*  Win Events:

    pCallback := RegisterCallback("WinEventProc")
    WinEventProc(hHook, event, hWnd, idObject, idChild, eventThread, eventTime)
    {
        Critical
        Acc := Acc_ObjectFromEvent(_idChild_, hWnd, idObject, idChild)
        ; Code Here:

    }
*/

; Written by jethrow
Acc_Role(Acc, ChildId=0) {
    try return ComObjType(Acc,"Name")="IAccessible"?Acc_GetRoleText(Acc.accRole(ChildId)):"invalid object"
}
Acc_State(Acc, ChildId=0) {
    try return ComObjType(Acc,"Name")="IAccessible"?Acc_GetStateText(Acc.accState(ChildId)):"invalid object"
}
Acc_Location(Acc, ChildId=0, byref Position="") { ; adapted from Sean's code
    try Acc.accLocation(ComObj(0x4003,&x:=0), ComObj(0x4003,&y:=0), ComObj(0x4003,&w:=0), ComObj(0x4003,&h:=0), ChildId)
    catch
        return
    Position := "x" NumGet(x,0,"int") " y" NumGet(y,0,"int") " w" NumGet(w,0,"int") " h" NumGet(h,0,"int")
    return  {x:NumGet(x,0,"int"), y:NumGet(y,0,"int"), w:NumGet(w,0,"int"), h:NumGet(h,0,"int")}
}
Acc_Parent(Acc) { 
    try parent:=Acc.accParent
    return parent?Acc_Query(parent):
}
Acc_Child(Acc, ChildId=0) {
    try child:=Acc.accChild(ChildId)
    return child?Acc_Query(child):
}
Acc_Query(Acc) { ; thanks Lexikos - www.autohotkey.com/forum/viewtopic.php?t=81731&p=509530#509530
    try return ComObj(9, ComObjQuery(Acc,"{618736e0-3c3d-11cf-810c-00aa00389b71}"), 1)
}
Acc_Error(p="") {
    static setting:=0
    return p=""?setting:setting:=p
}
Acc_Children(Acc) {
    if ComObjType(Acc,"Name") != "IAccessible"
        ErrorLevel := "Invalid IAccessible Object"
    else {
        Acc_Init(), cChildren:=Acc.accChildCount, Children:=[]
        if DllCall("oleacc\AccessibleChildren", "Ptr",ComObjValue(Acc), "Int",0, "Int",cChildren, "Ptr",VarSetCapacity(varChildren,cChildren*(8+2*A_PtrSize),0)*0+&varChildren, "Int*",cChildren)=0 {
            Loop %cChildren%
                i:=(A_Index-1)*(A_PtrSize*2+8)+8, child:=NumGet(varChildren,i), Children.Insert(NumGet(varChildren,i-8)=9?Acc_Query(child):child), NumGet(varChildren,i-8)=9?ObjRelease(child):
            return Children.MaxIndex()?Children:
        } else
            ErrorLevel := "AccessibleChildren DllCall Failed"
    }
    if Acc_Error()
        throw Exception(ErrorLevel,-1)
}
Acc_ChildrenByRole(Acc, Role) {
    if ComObjType(Acc,"Name")!="IAccessible"
        ErrorLevel := "Invalid IAccessible Object"
    else {
        Acc_Init(), cChildren:=Acc.accChildCount, Children:=[]
        if DllCall("oleacc\AccessibleChildren", "Ptr",ComObjValue(Acc), "Int",0, "Int",cChildren, "Ptr",VarSetCapacity(varChildren,cChildren*(8+2*A_PtrSize),0)*0+&varChildren, "Int*",cChildren)=0 {
            Loop %cChildren% {
                i:=(A_Index-1)*(A_PtrSize*2+8)+8, child:=NumGet(varChildren,i)
                if NumGet(varChildren,i-8)=9
                    AccChild:=Acc_Query(child), ObjRelease(child), Acc_Role(AccChild)=Role?Children.Insert(AccChild):
                else
                    Acc_Role(Acc, child)=Role?Children.Insert(child):
            }
            return Children.MaxIndex()?Children:, ErrorLevel:=0
        } else
            ErrorLevel := "AccessibleChildren DllCall Failed"
    }
    if Acc_Error()
        throw Exception(ErrorLevel,-1)
}
Acc_Get(Cmd, ChildPath="", ChildID=0, WinTitle="", WinText="", ExcludeTitle="", ExcludeText="") {
    static properties := {Action:"DefaultAction", DoAction:"DoDefaultAction", Keyboard:"KeyboardShortcut"}
    AccObj :=   IsObject(WinTitle)? WinTitle
            :   Acc_ObjectFromWindow( WinExist(WinTitle, WinText, ExcludeTitle, ExcludeText), 0 )
    if ComObjType(AccObj, "Name") != "IAccessible"
        ErrorLevel := "Could not access an IAccessible Object"
    else {
        StringReplace, ChildPath, ChildPath, _, %A_Space%, All
        AccError:=Acc_Error(), Acc_Error(true)
        Loop Parse, ChildPath, ., %A_Space%
            try {
                if A_LoopField is digit
                    Children:=Acc_Children(AccObj), m2:=A_LoopField ; mimic "m2" output in else-statement
                else
                    RegExMatch(A_LoopField, "(\D*)(\d*)", m), Children:=Acc_ChildrenByRole(AccObj, m1), m2:=(m2?m2:1)
                if Not Children.HasKey(m2)
                    throw
                AccObj := Children[m2]
            } catch {
                ErrorLevel:="Cannot access ChildPath Item #" A_Index " -> " A_LoopField, Acc_Error(AccError)
                if Acc_Error()
                    throw Exception("Cannot access ChildPath Item", -1, "Item #" A_Index " -> " A_LoopField)
                return
            }
        Acc_Error(AccError)
        StringReplace, Cmd, Cmd, %A_Space%, , All
        properties.HasKey(Cmd)? Cmd:=properties[Cmd]:
        try {
            if (Cmd = "Location")
                AccObj.accLocation(ComObj(0x4003,&x:=0), ComObj(0x4003,&y:=0), ComObj(0x4003,&w:=0), ComObj(0x4003,&h:=0), ChildId)
              , ret_val := "x" NumGet(x,0,"int") " y" NumGet(y,0,"int") " w" NumGet(w,0,"int") " h" NumGet(h,0,"int")
            else if (Cmd = "Object")
                ret_val := AccObj
            else if Cmd in Role,State
                ret_val := Acc_%Cmd%(AccObj, ChildID+0)
            else if Cmd in ChildCount,Selection,Focus
                ret_val := AccObj["acc" Cmd]
            else
                ret_val := AccObj["acc" Cmd](ChildID+0)
        } catch {
            ErrorLevel := """" Cmd """ Cmd Not Implemented"
            if Acc_Error()
                throw Exception("Cmd Not Implemented", -1, Cmd)
            return
        }
        return ret_val, ErrorLevel:=0
    }
    if Acc_Error()
        throw Exception(ErrorLevel,-1)
}

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

MouseIsOverTitlebar(xPos := "", yPos := "") {

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
    
    If !JEE_WinHasAltTabIcon(WindowUnderMouseID)
        Return
    
    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    If    ((mClass != "Shell_TrayWnd") 
        && (mClass != "WorkerW")  
        && (mClass != "ProgMan")   
        && (mClass != "TaskListThumbnailWnd") 
        && (!WinExist("ahk_class #32768")) 
        && (mClass != "Net UI Tool Window")) {
        
        try {
            oAcc := Acc_ObjectFromPoint(vChildId)
            If oAcc {
                vAccRoleText := Acc_GetRoleText(oAcc.accRole(vChildId))
                
                If (InStr(vAccRoleText,"title bar",false)) {
                    Return True
                }
            }
        }
        catch e {
            tooltip, error thrown
            sleep, 500
        }
        
        oAcc := ""
        
        WinGetPosEx(WindowUnderMouseID,x,y,w,h)
        SendMessage, 0x84, 0, (xPos & 0xFFFF) | (yPos & 0xFFFF)<<16,, ahk_id %WindowUnderMouseID%, , , , 500
        If ((yPos > y) && (yPos < (y+titlebarHeight)) && (xPos < (x+w-(3*45))) && (ErrorLevel == 2))
            Return True
        Else If ((ErrorLevel != 12) 
                && (mClass != "Chrome_WidgetWin_1") 
                && (yPos > y) && (yPos < (y+titlebarHeight)) && (xPos < (x+w-(3*45)))) {
            ; tooltip, %SM_CXBORDER% - %SM_CYBORDER% : %SM_CXFIXEDFRAME% - %SM_CYFIXEDFRAME%
            Return True
        }
        Else
            Return False
    }
    Else
        Return False
}

MouseIsOverCaptionButtons(xPos := "", yPos := "") {

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
    
    If !JEE_WinHasAltTabIcon(WindowUnderMouseID)
        Return
    
    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    
    If    ((mClass != "Shell_TrayWnd") 
        && (mClass != "WorkerW")  
        && (mClass != "ProgMan")   
        && (mClass != "TaskListThumbnailWnd") 
        && (mClass != "#32768") 
        && (mClass != "Net UI Tool Window")) {
        
        WinGetPosEx(WindowUnderMouseID,x,y,w,h)
        SendMessage, 0x84, 0, (xPos & 0xFFFF) | (yPos & 0xFFFF)<<16,, ahk_id %WindowUnderMouseID%, , , , 500
        If (((yPos > y) && (yPos < (y+titlebarHeight))) && ((ErrorLevel == 8) || (ErrorLevel == 9) || (ErrorLevel == 20)))
            Return True
        Else If ((ErrorLevel != 12) 
                && (yPos > y) && (yPos < (y+titlebarHeight)) && (xPos > (x+w-(3*45)))) {
            ; tooltip, %SM_CXBORDER% - %SM_CYBORDER% : %SM_CXFIXEDFRAME% - %SM_CYFIXEDFRAME%
            Return True
        }
        Else
            Return False
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

MouseIsOverTaskbar() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID, CtrlUnderMouseId
    
    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (InStr(mClass,"TrayWnd",false) && InStr(mClass,"Shell",false) && CtrlUnderMouseId != "ToolbarWindow323" && CtrlUnderMouseId != "TrayNotifyWnd1")
        Return True
    Else
        Return False
}

MouseIsOverBlankTaskbar() {
    oAcc := Acc_ObjectFromPoint(vChildId)
    vAccRoleNum := oAcc.accRole(vChildId)
    vAccName := oAcc.accName(vChildId)
    oAcc := ""
    
    tooltip, %vAccRoleNum% and %vAccName%
    
    ;ROLE_SYSTEM_TOOLBAR := 0x16
    if (vAccRoleNum = 0x16) && (vAccName = "Running applications")
        MsgBox, % "is empty part of taskbar: y"
    else
        MsgBox, % "is empty part of taskbar: n"
    return
}

; https://www.autohotkey.com/boards/viewtopic.php?t=37184
;gives you roughly the correct results (tested on Windows 7)
;JEE_WinIsAltTab
JEE_WinHasAltTabIcon(hWnd)
{
    local
    if !(DllCall("user32\GetDesktopWindow", "Ptr") = DllCall("user32\GetAncestor", "Ptr",hWnd, "UInt",1, "Ptr")) ;GA_PARENT := 1
    ;|| DllCall("user32\GetWindow", "Ptr",hWnd, "UInt",4, "Ptr") ;GW_OWNER := 4 ;affects taskbar but not alt-tab
        return 0+
        
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

; https://www.autohotkey.com/boards/viewtopic.php?t=26700
JEE_AhkIsAdmin()
{
    ;see AHK source code: os_version.h
    ;see also:
    ;Operating System Version (Windows)
    ;https://msdn.microsoft.com/en-gb/library/windows/desktop/ms724832(v=vs.85).aspx
    ;Using the Windows Headers (Windows)
    ;https://msdn.microsoft.com/en-us/library/windows/desktop/aa383745(v=vs.85).aspx
    vVersion := DllCall("kernel32\GetVersion", "UInt")
    if (vVersion & 0xFF < 5)
        return 1

    ;SC_MANAGER_LOCK := 0x8
    hSC := DllCall("advapi32\OpenSCManager", "Ptr",0, "Ptr",0, "UInt",0x8, "Ptr")
    vRet := 0
    if hSC
    {
        if (vLock := DllCall("advapi32\LockServiceDatabase", "Ptr",hSC, "Ptr"))
        {
            DllCall("advapi32\UnlockServiceDatabase", "Ptr",vLock)
            vRet := 1
        }
        else
        {
            vLastError := DllCall("kernel32\GetLastError", "UInt")
            ;ERROR_SERVICE_DATABASE_LOCKED := 1055
            if (vLastError = 1055)
                vRet := 1
        }
        DllCall("advapi32\CloseServiceHandle", "Ptr",hSC)
    }
    return vRet
}

; https://www.autohotkey.com/boards/viewtopic.php?t=43417
JEE_ProcessIsElevated(vPID)
{
    ;PROCESS_QUERY_LIMITED_INFORMATION := 0x1000
    if !(hProc := DllCall("kernel32\OpenProcess", "UInt",0x1000, "Int",0, "UInt",vPID, "Ptr"))
        return -1
    ;TOKEN_QUERY := 0x8
    hToken := 0
    if !(DllCall("advapi32\OpenProcessToken", "Ptr",hProc, "UInt",0x8, "Ptr*",hToken))
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

;https://stackoverflow.com/questions/59883798/determine-which-monitor-the-focus-window-is-on
IsWindowOnCurrMon(thisWindowHwnd, currentMonNum := 0) {
    WinGet, state, MinMax, ahk_id %thisWindowHwnd%

    If (state == -1)
        Return True

    If (state == 1)
        buffer := 8
    Else
        buffer := 0
    ;Get number of monitor
    SysGet, monCount, MonitorCount

    WinGetPos, X, Y, W, H, ahk_id %thisWindowHwnd%
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

