#SingleInstance, Force
#NoEnv
SetBatchLines, -1
SetWinDelay, -1
; Uncomment if Gdip.ahk is not in your standard library
#Include, Gdip_All.ahk
SetTimer, MasterTimer, 100
SetTimer, CheckProgress, 100, 1

SetTimer, CheckProgress, Off

DoubleClickTime := DllCall("GetDoubleClickTime")
Menu, MyMenu, Add, Empty Bin, BinMenu

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
; pBitmap := Gdip_CreateBitmapFromFile("33017060.jpg")
pBitmap := Gdip_CreateBitmapFromFile(A_WinDir . "\System32\shell32.dll", 33, 128) 
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
If !pBitmap
{
	MsgBox, 48, File loading error!, Could not load the image specified
	ExitApp
}
; Get the width and height of the bitmap we have just created from the file
; This will be the dimensions that the file is
Width := Gdip_GetImageWidth(pBitmap), Height := Gdip_GetImageHeight(pBitmap)
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
Gdip_SetInterpolationMode(G, 7)
Gdip_SetSmoothingMode(G, 4)

; Create a green brush (this will be used to fill the background with green). The brush is fully opaque (ARGB)
; pBrush := Gdip_BrushCreateSolid(0x55000000)

; Filll the entire graphics of the bitmap with the green brush (this will be out background colour)
; Gdip_FillRectangle(G, pBrush, 0, 0, Width, Height)

; Delete the brush created to save memory as we don't need the same brush anymore
; Gdip_DeleteBrush(pBrush)

blurpBitmap := Gdip_BlurBitmap(pBitmap, 8)

; DrawImage will draw the bitmap we took from the file into the graphics of the bitmap we created
; We are wanting to draw the entire image, but at half its size
; Coordinates are therefore taken from (0,0) of the source bitmap and also into the destination bitmap
; The source height and width are specified, and also the destination width and height (half the original)
; Gdip_DrawImage(pGraphics, pBitmap, dx, dy, dw, dh, sx, sy, sw, sh, Matrix)
; d is for destination and s is for source. We will not talk about the matrix yet (this is for changing colours when drawing)
; Can be passed in pretty much any format you want with anything used as a separator
; I have made the function use RegExReplace to fix any errors. So you could pass it as 0.9|0|0|0|00|0.9|0|0|00|0|1.5|0|00|0|0|1|0-1|0|5|0|1
Matrix =
(
0.0		0		0		0		0
0		0.0		0		0		0
0		0		0.0		0		0
0		0		0		0.75	0
0		0		0		0		1
)
Gdip_DrawImage(G, blurpBitmap, 0, 0, Width, Height, 0, 0, Width, Height, Matrix)
Gdip_DrawImage(G, pBitmap, 0, 0, Width, Height, 0, 0, Width, Height, 1)
; Update the specified window we have created (hwnd1) with a handle to our bitmap (hdc), specifying the x,y,w,h we want it positioned on our screen
; So this will position our gui at (0,0) with the Width and Height specified earlier (half of the original image)
UpdateLayeredWindow(hwnd2, hdc, -1*Width, -1*Height, Width, Height)
; Select the object back into the hdc
SelectObject(hdc, obm)
; Now the bitmap may be deleted
DeleteObject(hbm)
; Also the device context related to the bitmap may be deleted
DeleteDC(hdc)
; The graphics may now be deleted
Gdip_DeleteGraphics(G)
; The bitmap we made from the image may be deleted
Gdip_DisposeImage(pBitmap)
Return 

2GuiDropFiles:
Loop, parse, A_GuiEvent, `n
   ; MsgBox, 4,, File number %A_Index% is:`n%A_LoopField% `n`nContinue?
   FileRecycle, %A_LoopField% 
   if ErrorLevel   ; i.e. it's not blank or zero.
      MsgBox, % "Failed to Recycle " A_LoopField
return

MasterTimer:
    MouseGetPos, mtX, mtY, MouseWinHwnd
    WinGetClass, mtClass, ahk_id %MouseWinHwnd%

    If ((mtClass == "WorkerW" || mtClass == "Progman") && mtX <= 3 && mtY <= 3)
    {
        MoveToTargetSpot(winId2, 10, 0, -1*Width, 0, -1*Height)
        SetTimer, MasterTimer, Off
    }
Return

BinMenu:
    TotalFiles := SHQueryRecycleBin("C:\", 3)
    TotalSize  := SHQueryRecycleBin("C:\", 2)
    MsgBox, 4, Confirm Delete, % TotalFiles " files, with a total size of " TotalSize
    IfMsgBox Yes
    {
        SetTimer, CheckProgress, on
        FileRecycleEmpty
        SetTimer, CheckProgress, off
    }
Return

CheckProgress:
    Gui, 3: New, -Caption +AlwaysOnTop
    Gui, 3: Add, Progress, w200 h20 cLime vMyProgress, 0
    Gui, 3: Show, NA
    loop
    {
        SizeRemaining := SHQueryRecycleBin("C:\", 2)
        GuiControl,, MyProgress, 100 - ceil(100 * (SizeRemaining/TotalSize)) ; Set the position of the bar to 50%.
        If ((100 * (SizeRemaining/TotalSize)) > 99)
            break
    }
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
    MouseGetPos, lmx, lmy, ClickedWinHwnd
    WinGetClass, wmClassD, ahk_id %ClickedWinHwnd%
        
    If (wmClassD == "CabinetWClass" || wmClassD == "WorkerW" || wmClassD == "Progman")
    {
        loop
        {
            If GetKeyState("LButton", "P")
            {
                ; MouseGetPos, lmx2, lmy2, ClickedWinHwndU
                ; WinGetClass, classU, ahk_id %ClickedWinHwndU%
                MouseGetPos, MXw, MYw, MouseWinHwnd
                WinGetClass, wmClassU, ahk_id %MouseWinHwnd%
                If (wmClassU != "CabinetWClass" && (lmx > MXw))
                {
                    MoveToTargetSpot(winId2, 10, 0, -1*Width, 0, -1*Height)
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
        MoveToTargetSpot(winId2, 10, -1*Width, 0, -1*Height , 0)
    }
    SetTimer, MasterTimer, On
Return

;#######################################################################
Exit:
; gdi+ may now be shutdown on exiting the program
Gdip_Shutdown(pToken)
    ExitApp
Return

MoveToTargetSpot(winId, moveincrement, targetX, orgX, targetY := -1, orgY := -1)
{
   Critical On
   loopCount := 0
   xIsFurther := False
   yIsFurther := False
   
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
       
       If (targetY == -1)
       {
           newX := orgX
           loop % loopCount
           {   
               newX := newX + moveIncrementX
               sleep, 1
               WinMove, %winId%,, newX 
           }
           WinMove, %winId%,, targetX
       }
       Else
       {
          newX := orgX
          newY := orgY
          loop % loopCount
          {   
              If (xIsFurther)
              {
                  tooltip, % adjustedIncPerc
                  newX := newX + moveIncrementX
                  newY := newY + ceil(moveIncrementY*adjustedIncPerc)
              }
              Else
              {
                  newX := newX + ceil(moveIncrementX*adjustedIncPerc)
                  newY := newY + moveIncrementY
              }
              sleep, 1
              WinMove, %winId%,, newX, newY 
          }
          WinMove, %winId%,, targetX, targetY
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
