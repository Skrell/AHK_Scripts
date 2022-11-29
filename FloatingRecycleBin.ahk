#SingleInstance, Force
#Persistent 
#NoEnv
SetBatchLines, -1
SetWinDelay, -1

CoordMode, Mouse, Screen
CoordMode, Pixel, Screen

; Uncomment if Gdip.ahk is not in your standard library
#Include, Gdip_All.ahk
SetTimer, MasterTimer, 100
MoveIncrement := 5
PI := 3.14159265

Menu, MyMenu, Add, Empty Bin, BinMenu

Menu, Tray, NoStandard
Menu, Tray, Add, &Open, LaunchBin
Menu, Tray, Add, Empty Bin, BinMenu
Menu, Tray, Add, Reload, ReloadMenu
Menu, Tray, Add, Exit, ExitMenu
Menu, Tray, Default, &Open
Menu, Tray, Click, 1
Menu, Tray, Tip, % SHQueryRecycleBin("", 3) " files, with a total size of " SHQueryRecycleBin("", 2)
Menu, Tray, Icon, C:\Windows\system32\shell32.dll,32


; Start gdi+
If !pToken := Gdip_Startup()
{
	MsgBox, 48, gdiplus error!, Gdiplus failed to start. Please ensure you have gdiplus on your system
	ExitApp
}
OnExit, Exit
; If the image we want to work with does not exist on disk, then download it...
; If !FileExist("33017060.jpg")
; UrlDownloadToFile, http://img714.imageshack.us/img714/9609/33017060.jpg, 33017060.jpg
; Get a bitmap from the image
; pBitmapFull := Gdip_CreateBitmapFromFile("33017060.jpg")
pBitmapFull  := Gdip_CreateBitmapFromFile(A_WinDir . "\System32\shell32.dll", 33, 128) 
pBitmapEmpty := Gdip_CreateBitmapFromFile(A_WinDir . "\System32\shell32.dll", 32, 128) 
; Create a layered window (+E0x80000 : must be used for UpdateLayeredWindow to work!) that is always on top (+AlwaysOnTop), has no taskbar entry or caption
Gui, 2: -Caption +E0x80000 +LastFound +OwnDialogs +Owner +AlwaysOnTop
; Show the window
Gui, 2: Show, NA
OnMessage(0x201, "WM_LBUTTONDOWN")
OnMessage(0x204, "WM_RBUTTONDOWN")
; Get a handle to this window we have created in order to update it later
hwnd2 := WinExist()
winId2 = ahk_id %hwnd2%
; Check to ensure we actually got a bitmap from the file, in case the file was corrupt or some other error occured
If !pBitmapFull
{
	MsgBox, 48, File loading error!, Could not load the image specified
	ExitApp
}
; Get the width and height of the bitmap we have just created from the file
; This will be the dimensions that the file is
Width := Gdip_GetImageWidth(pBitmapFull), Height := Gdip_GetImageHeight(pBitmapFull)
; Create a gdi bitmap with width and height of what we are going to draw into it. This is the entire drawing area for everything
; We are creating this "canvas" at half the size of the actual image
; We are halving it because we want the image to show in a gui on the screen at half its dimensions
hbm := CreateDIBSection(Width*2, Height*2)
; Get a device context compatible with the screen
hdc := CreateCompatibleDC()
; Select the bitmap into the device context
obm := SelectObject(hdc, hbm)
; Get a pointer to the graphics of the bitmap, for use with drawing functions
G := Gdip_GraphicsFromHDC(hdc)
; We do not need SmoothingMode as we did in previous examples for drawing an image
; Instead we must set InterpolationMode. This specifies how a file will be resized (the quality of the resize)
; Interpolation mode has been set to HighQualityBicubic = 7
; Gdip_SetInterpolationMode(G, 7)
; Gdip_SetSmoothingMode(G, 4)
; Create a green brush (this will be used to fill the background with green). The brush is fully opaque (ARGB)
; pBrush := Gdip_BrushCreateSolid(0x55000000)
; Filll the entire graphics of the bitmap with the green brush (this will be out background colour)
; Gdip_FillRectangle(G, pBrush, 0, 0, Width, Height)
; Delete the brush created to save memory as we don't need the same brush anymore
; Gdip_DeleteBrush(pBrush)
blurpBitmap := Gdip_BlurBitmap(pBitmapEmpty, 4)
; DrawImage will draw the bitmap we took from the file into the graphics of the bitmap we created
; We are wanting to draw the entire image, but at half its size
; Coordinates are therefore taken from (0,0) of the source bitmap and also into the destination bitmap
; The source height and width are specified, and also the destination width and height (half the original)
; Gdip_DrawImage(pGraphics, pBitmapFull, dx, dy, dw, dh, sx, sy, sw, sh, Matrix)
; d is for destination and s is for source. We will not talk about the matrix yet (this is for changing colours when drawing)
; Can be passed in pretty much any format you want with anything used as a separator
; I have made the function use RegExReplace to fix any errors. So you could pass it as 0.9|0|0|0|00|0.9|0|0|00|0|1.5|0|00|0|0|1|0-1|0|5|0|1
MatrixBlur =
(
0.0		0		0		0		0
0		0.0		0		0		0
0		0		0.0		0		0
0		0		0		0.35 	0
0		0		0		0		1
)
MatrixBright =
(
1.25	0		0		0		0
0		1.25	0		0		0
0		0		1.25	0		0
0		0		0		1   	0
0		0		0		0		1
)
; Gdip_DrawImage(G, blurpBitmap, 0, 0, Width, Height, 0, 0, Width, Height, MatrixBlur)
; Gdip_DrawImage(G, pBitmapFull, 0, 0, Width, Height, 0, 0, Width, Height, MatrixBright)
; Update the specified window we have created (hwnd1) with a handle to our bitmap (hdc), specifying the x,y,w,h we want it positioned on our screen
; So this will position our gui at (0,0) with the Width and Height specified earlier (half of the original image)
; UpdateLayeredWindow(hwnd2, hdc, -1*Width, -1*Height, Width, Height)
; Select the object back into the hdc
; SelectObject(hdc, obm)
; Now the bitmap may be deleted
; DeleteObject(hbm)
; Also the device context related to the bitmap may be deleted
; DeleteDC(hdc)
; The graphics may now be deleted
; Gdip_DeleteGraphics(G)
; The bitmap we made from the image may be deleted
; Gdip_DisposeImage(pBitmapFull)
Return 

LaunchBin:
    Run, explorer.exe shell:RecycleBinFolder
Return

2GuiDropFiles:
    TotalFiles   := SHQueryRecycleBin("", 3)
    TotalSize    := SHQueryRecycleBin("", 1)
    Tooltip, Moving Files...
    Loop, parse, A_GuiEvent, `n
    {
       ; MsgBox, 4,, File number %A_Index% is:`n%A_LoopField% `n`nContinue?
       FileRecycle, %A_LoopField% 
       if ErrorLevel   ; i.e. it's not blank or zero.
          MsgBox, % "Failed to Recycle " A_LoopField
    }
    
    If (TotalFiles == 0 && TotalSize == 0)
    {
        ; Select the object back into the hdc
        SelectObject(hdc, obm)
        ; Now the bitmap may be deleted
        DeleteObject(hbm)
        ; Also the device context related to the bitmap may be deleted
        DeleteDC(hdc)
        
        hbm := CreateDIBSection(Width*2, Height*2)
        ; Get a device context compatible with the screen
        hdc := CreateCompatibleDC()
        ; Select the bitmap into the device context
        obm := SelectObject(hdc, hbm)
        ; Get a pointer to the graphics of the bitmap, for use with drawing functions
        G := Gdip_GraphicsFromHDC(hdc)
        ; Gdip_SetInterpolationMode(G, 7)
        Gdip_SetSmoothingMode(G, 4)
        Gdip_GraphicsClear(G)
        Gdip_DrawImage(G, blurpBitmap, 4, 4, Width, Height, 0, 0, Width, Height, MatrixBlur)
        Gdip_DrawImage(G, pBitmapFull, 0, 0, Width, Height, 0, 0, Width, Height, MatrixBright)
    }
    Tooltip, 
return

MasterTimer:
    TotalFiles   := SHQueryRecycleBin("", 3)
    TotalSize    := SHQueryRecycleBin("", 1)
    MouseGetPos, mtX, mtY, mthwnd
    WinGetPos, wtx, wty , , , %winId2%
        
    If (!IsFullScreen(mthwnd) && mtX <= 3 && mtY <= 3 && wtx < 0)
    {
        If (TotalFiles == 0 && TotalSize == 0)
        {
            ; Select the object back into the hdc
            SelectObject(hdc, obm)
            ; Now the bitmap may be deleted
            DeleteObject(hbm)
            ; Also the device context related to the bitmap may be deleted
            DeleteDC(hdc)
            
            hbm := CreateDIBSection(Width*2, Height*2)
            ; Get a device context compatible with the screen
            hdc := CreateCompatibleDC()
            ; Select the bitmap into the device context
            obm := SelectObject(hdc, hbm)
            ; Get a pointer to the graphics of the bitmap, for use with drawing functions
            G := Gdip_GraphicsFromHDC(hdc)
            ; Gdip_SetInterpolationMode(G, 7)
            Gdip_SetSmoothingMode(G, 4)
            Gdip_GraphicsClear(G)
            Gdip_DrawImage(G, blurpBitmap,  4, 4, Width, Height, 0, 0, Width, Height, MatrixBlur)
            Gdip_DrawImage(G, pBitmapEmpty, 0, 0, Width, Height, 0, 0, Width, Height, MatrixBright)
        }
        Else
        {
            ; Select the object back into the hdc
            SelectObject(hdc, obm)
            ; Now the bitmap may be deleted
            DeleteObject(hbm)
            ; Also the device context related to the bitmap may be deleted
            DeleteDC(hdc)
            
            hbm := CreateDIBSection(Width*2, Height*2)
            ; Get a device context compatible with the screen
            hdc := CreateCompatibleDC()
            ; Select the bitmap into the device context
            obm := SelectObject(hdc, hbm)
            ; Get a pointer to the graphics of the bitmap, for use with drawing functions
            G := Gdip_GraphicsFromHDC(hdc)
            ; Gdip_SetInterpolationMode(G, 7)
            Gdip_SetSmoothingMode(G, 4)
            Gdip_GraphicsClear(G)
            Gdip_DrawImage(G, blurpBitmap, 4, 4, Width, Height, 0, 0, Width, Height, MatrixBlur)
            Gdip_DrawImage(G, pBitmapFull, 0, 0, Width, Height, 0, 0, Width, Height, MatrixBright)
        }
        UpdateLayeredWindow(hwnd2, hdc, -1*Width, -1*Height, Width, Height, 0)   
        MoveToTargetSpot(winId2, MoveIncrement, 0, -1*Width, 0, -1*Height, "in")
    }
    Else 
    {   
        If (mtX == 0 && mtY >= 100 && wtx >= 0)
        {
            MoveToTargetSpot(winId2, MoveIncrement, -1*Width, 0, -1*Height , 0, "out")
        }
    }
    
    If (TotalFiles == 0 && TotalSize == 0)
    {
        Menu, Tray, Icon, C:\Windows\system32\shell32.dll,32
    }
    Else
    {
        Menu, Tray, Icon, C:\Windows\system32\shell32.dll,33
    }
    
    Menu, Tray, Tip, % SHQueryRecycleBin("", 3) " files, with a total size of " SHQueryRecycleBin("", 2)
Return

BinMenu:
    TotalFiles   := SHQueryRecycleBin("", 3)
    TotalSizeMB  := SHQueryRecycleBin("", 2)
    TotalSize    := SHQueryRecycleBin("", 1)
    MsgBox, 4, Confirm Delete, % TotalFiles " files, with a total size of " TotalSizeMB
    IfMsgBox Yes
    {
        SetTimer, CheckProgress, -1
        ; FileRecycleEmpty
        ; Run, %A_ScriptDir%\nircmd.exe emptybin
        Run, powershell.exe -command Clear-RecycleBin -Force,, 'hide'
    }
Return

ReloadMenu:
    Reload
Return

ExitMenu:
    ExitApp
Return

CheckProgress:
    previousAmount := -1
    Gui, 3: New, +AlwaysOnTop, Deleting Files...
    Gui, 3: Add, Progress, w400 h20 c06AA24 vMyProgress, 0
    Gui, 3: Show, 
    loop
    {
        FilesRemaining := SHQueryRecycleBin("", 3)
        SizeRemaining  := SHQueryRecycleBin("", 1)
        amountLeft := 100 - ceil(100 * (SizeRemaining/TotalSize))
        If (previousAmount != amountLeft)
            GuiControl, 3:, MyProgress, %amountLeft% ; Set the position of the bar to 50%.
        Else
            GuiControl, 3:, MyProgress, +1
        sleep 750
        If (FilesRemaining == 0)
            break
        previousAmount := amountLeft
    }
    GuiControl, 3:, MyProgress, 100
    Gui, 3: Destroy
Return

WM_RBUTTONDOWN(wParam, lParam)
{
    X := lParam & 0xFFFF
    Y := lParam >> 16
    if A_GuiControl
        Control := "`n(in control " . A_GuiControl . ")"
    ; ToolTip You left-clicked in Gui window #%A_Gui% at client coordinates %X%x%Y%.%Control%
    Menu, MyMenu, Show
}

WM_LBUTTONDOWN(wParam, lParam)
{
    global hwnd2
    X := lParam & 0xFFFF
    Y := lParam >> 16
    if A_GuiControl
        Control := "`n(in control " . A_GuiControl . ")"
    ; ToolTip You left-clicked in Gui window #%A_Gui% at client coordinates %X%x%Y%.%Control%
    MouseGetPos, , , currentHwnd
    WinGet, whwnd, ID, ahk_id %currentHwnd%
    If (whwnd == hwnd2)
    {
        Run, explorer.exe shell:RecycleBinFolder
    }
}

~LButton::
    SetTimer, MasterTimer, Off
    MouseGetPos, lmx, lmy, ClickedWinHwnd, CtrlClass
    WinGetClass, wmClassD, ahk_id %ClickedWinHwnd%
    WinGetPos, wx, wy , , ,%winId2%
        
    If (!IsMouseOverIcon(wmClassD, CtrlClass) || (GetKeyState("Shift", "P")))
    {
        WinGetPos, wx, wy , , ,%winId2%
        If (wx >= 0)
        {
            MoveToTargetSpot(winId2, MoveIncrement, -1*Width, 0, -1*Height , 0, "out")
        }
        SetTimer, MasterTimer, On
        Return
    }
        
    If (IsMouseOverIcon(wmClassD, CtrlClass))
    {
        loop
        {
            If GetKeyState("LButton", "P")
            {
                MouseGetPos, MXw, MYw, MouseWinHwnd
                WinGetClass, wmClassU, ahk_id %MouseWinHwnd%
                If (wx < 0 && (lmx > MXw && lmy > MYw) && MXw < A_ScreenWidth/3 && MYw < A_ScreenHeight/3)
                {
                    MoveToTargetSpot(winId2, MoveIncrement, 0, -1*Width, 0, -1*Height, "in")
                    break
                }
                lmx := MXw
                lmy := MYw
                sleep 100
            }
            else
                Break
        }
    }
    KeyWait, LButton, T30
    WinGetPos, wx, wy , , ,%winId2%
    If (wx >= 0)
    {
        sleep 500
        MoveToTargetSpot(winId2, MoveIncrement, -1*Width, 0, -1*Height , 0, "out")
    }
    SetTimer, MasterTimer, On
Return

;#######################################################################
Exit:
    ; gdi+ may now be shutdown on exiting the program
    Gdip_Shutdown(pToken)
    ExitApp
Return

;#######################################################################
MoveToTargetSpot(winId, moveincrement, targetX, orgX, targetY := -1, orgY := -1, fade := "na")
{
   global hwnd2, hdc, PI
   Critical On
   loopCount     := 0
   startTrans    := 0
   loopCountInit := loopCount
   xIsFurther    := False
   yIsFurther    := False
   
   If (targetX > orgX)
      moveIncrementX := moveincrement
   Else
      moveIncrementX := -1*moveincrement
      
   If (targetY > orgY)
      moveIncrementY := moveincrement
   Else
      moveIncrementY := -1*moveincrement
      
   If WinExist(winId)
   {
       If (abs(targetX-orgX) > abs(targetY-orgY))
       {
            loopCount := floor(abs((targetX-orgX)/moveIncrementX))
            xIsFurther := True
            adjustedIncPerc := abs(targetY-orgY)/abs(targetX-orgX)
       }
       Else
       {
            loopCount := floor(abs((targetY-orgY)/moveIncrementY))
            yIsFurther := True
            adjustedIncPerc := abs(targetX-orgX)/abs(targetY-orgY)
       }
       
       If (fade != "na" && loopCount < 255)
       {
            fadeIncr := (PI/2/loopCount) ;;floor(255/loopCount)
            If (fade == "out")
            {
                fadeIncr := -1 * fadeIncr
                startTrans := 255
            }
            else
            {
                startTrans := 0
            }
       }
       
       If (targetY == -1)
       {
          newX := orgX
          loop % loopCount
          {   
              newX := newX + moveIncrementX
              sleep, 10
              WinMove, %winId%,, newX 
              
              If (fade == "in")
              {
                 UpdateLayeredWindow(hwnd2, hdc, , , , , startTrans)   
                 startTrans := floor(255*(sin((3*PI/2) + (A_Index*fadeIncr)))) + 255
              }
              Else If (fade == "out")
              {
                 UpdateLayeredWindow(hwnd2, hdc, , , , , startTrans)   
                 startTrans := floor(255*(sin((2*PI) + (A_Index*fadeIncr)))) + 255
              }
          }
          
          WinMove, %winId%,, targetX
                     
          If (fade == "in")
             UpdateLayeredWindow(hwnd2, hdc, , , , , 255)
          Else If (fade == "out")
             UpdateLayeredWindow(hwnd2, hdc, , , , , 0)
       }
       Else
       {
          newX := orgX
          newY := orgY
          loop % loopCount
          {   
              If (xIsFurther)
              {
                  newX := newX + moveIncrementX
                  newY := newY + ceil(moveIncrementY*adjustedIncPerc)
              }
              Else
              {
                  newX := newX + ceil(moveIncrementX*adjustedIncPerc)
                  newY := newY + moveIncrementY
              }
              sleep, 10
              WinMove, %winId%,, newX, newY 
             
              If (fade == "in")
              {
                 UpdateLayeredWindow(hwnd2, hdc, , , , , startTrans)   
                 startTrans := floor(255*(sin((3*PI/2) + (A_Index*fadeIncr)))) + 255
              }
              Else If (fade == "out")
              {
                 UpdateLayeredWindow(hwnd2, hdc, , , , , startTrans)   
                 startTrans := floor(255*(sin((2*PI) + (A_Index*fadeIncr)))) + 255
              }
          }
          
          WinMove, %winId%,, targetX, targetY
          
          If (fade == "in")
             UpdateLayeredWindow(hwnd2, hdc, , , , , 255)
          Else If (fade == "out")
             UpdateLayeredWindow(hwnd2, hdc, , , , , 0)
       }
   }
   Else
   {
      Msgbox, "Window doesn't exist"
   }
   Critical Off
   Return
}
/*
======================================================
https://www.autohotkey.com/boards/viewtopic.php?f=6&t=62224
======================================================
*/
IsMouseOverIcon(WinClass, CtrlClass) {
   try if (WinClass = "CabinetWClass" && CtrlClass = "DirectUIHWND2") {
      oAcc := Acc_ObjectFromPoint()
      Name := Acc_Parent(oAcc).accValue(0)
      Name := Name ? Name : oAcc.accValue(0)
      Return  Name ? true : false
   } else if (WinClass = "Progman" || WinClass = "WorkerW") {
      oAcc := Acc_ObjectFromPoint(ChildID)
      Return  ChildID ? true : false
   }
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
	return parent?Acc_Query(parent):
}
Acc_Query(Acc) { ; thanks Lexikos - www.autohotkey.com/forum/viewtopic.php?t=81731&p=509530#509530
	try return ComObj(9, ComObjQuery(Acc,"{618736e0-3c3d-11cf-810c-00aa00389b71}"), 1)
}
/*
======================================================
Find RecycleBin Size
https://www.autohotkey.com/boards/viewtopic.php?f=5&t=3463&p=17525#p17525
======================================================
*/
SHQueryRecycleBin(pszRootPath, Param) {
	VarSetCapacity(SHQUERYRBINFO, 24, 0) ; Create SHQUERYRBINFO structure
	NumPut(24, SHQUERYRBINFO, "UInt") ; Fill cbSize member
	DllCall("Shell32.dll\SHQueryRecycleBin" . ((A_IsUnicode = 1) ? "W" : "A"), "Str", pszRootPath, ((A_PtrSize = 8) ? "Ptr" : "UInt"), &SHQUERYRBINFO, "UInt") ; Call function
	ByteSize := NumGet(SHQUERYRBINFO, ((A_PtrSize = 8) ? "8" : "4"), "Int64") ; Retrieve data size (bytes)
	NumItems := NumGet(SHQUERYRBINFO, ((A_PtrSize = 8) ? "16" : "12"), "Int64") ; Retrieve item count
	VarSetCapacity(BININFOFORMAT, 32, 0) ; Create BININFOFORMAT structure
	DllCall("Shlwapi.dll\StrFormatByteSize64A", "Int64", ByteSize, "UInt", &BININFOFORMAT, "UInt", 32, ((A_IsUnicode = 1) ? "AStr" : "Str")) ; Format data size
	FormatSize := StrGet(&BININFOFORMAT, "CP0") ; Retrieve data size (bytes, KB, MB, GB, etc...)
	Array := [ByteSize, FormatSize, NumItems] ; Create array for retrieving the data
	return Result := Array[Param] ; Return the value for the specified parameter
}

/*!  
======================================================
    Checks if a window is in fullscreen mode.
    ______________________________________________________________________________________________________________
	Usage: isFullScreen()
	Return: True/False
	GitHub Repo: https://github.com/Nigh/isFullScreen
======================================================
*/
IsFullScreen(hWnd) {
   static nonFullScreenStyles := (WS_CAPTION := 0xC00000) | (WS_THICKFRAME := 0x40000)
        , nonFullScreenExStyles := (WS_EX_WINDOWEDGE := 0x100) | (WS_EX_CLIENTEDGE := 0x200) | (WS_EX_STATICEDGE := 0x20000)
   local wClass
   
   WinGetClass, wClass, ahk_id %hWnd%
   
   If (wClass == "WorkerW" || wClass == "Progman")
     Return False
   Else
   {
       WinGet, styles, Style, ahk_id %hWnd%
       WinGet, exStyles, ExStyle, ahk_id %hWnd%
       Return !(styles & nonFullScreenStyles || exStyles & nonFullScreenExStyles)
   }
}
