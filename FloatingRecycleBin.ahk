; gdi+ ahk tutorial 1 written by tic (Tariq Porter)
; Requires Gdip.ahk either in your Lib folder as standard library or using #Include
;
; Tutorial to draw a single ellipse and rectangle to the screen
#SingleInstance, Force
#NoEnv
SetBatchLines, -1
; Uncomment if Gdip.ahk is not in your standard library
#Include, Gdip_All.ahk
; Start gdi+
If !pToken := Gdip_Startup()
{
	MsgBox, 48, gdiplus error!, Gdiplus failed to start. Please ensure you have gdiplus on your system
	ExitApp
}
Else
{
    MsgBox, it worked!
}
OnExit, Exit
; Set the width and height we want as our drawing area, to draw everything in. This will be the dimensions of our bitmap
Width :=1400, Height := 1050
; Create a layered window (+E0x80000 : must be used for UpdateLayeredWindow to work!) that is always on top (+AlwaysOnTop), has no taskbar entry or caption
Gui, 1: -Caption +E0x80000 +LastFound +AlwaysOnTop +ToolWindow +OwnDialogs
; Show the window
; Gui, 1: Show, NA
; Get a handle to this window we have created in order to update it later
hwnd1 := WinExist()
; Create a gdi bitmap with width and height of what we are going to draw into it. This is the entire drawing area for everything
hbm := CreateDIBSection(Width, Height)
; Get a device context compatible with the screen
hdc := CreateCompatibleDC()
; Select the bitmap into the device context
obm := SelectObject(hdc, hbm)
; Get a pointer to the graphics of the bitmap, for use with drawing functions
G := Gdip_GraphicsFromHDC(hdc)
; Set the smoothing mode to antialias = 4 to make shapes appear smother (only used for vector drawing and filling)
Gdip_SetSmoothingMode(G, 4)
; Create a fully opaque red brush (ARGB = Transparency, red, green, blue) to draw a circle
pBrush := Gdip_BrushCreateSolid(0xffff0000)
; Fill the graphics of the bitmap with an ellipse using the brush created
; Filling from coordinates (100,50) an ellipse of 200x300
Gdip_FillEllipse(G, pBrush, 100, 500, 200, 300)
; Delete the brush as it is no longer needed and wastes memory
Gdip_DeleteBrush(pBrush)
; Create a slightly transparent (66) blue brush (ARGB = Transparency, red, green, blue) to draw a rectangle
; pBrush := Gdip_BrushCreateSolid(0x660000ff)
pBrush := Gdip_BrushCreateSolid(0xff0000ff)
; Fill the graphics of the bitmap with a rectangle using the brush created
; Filling from coordinates (250,80) a rectangle of 300x200
Gdip_FillRectangle(G, pBrush, 250, 1000, 300, 200)
; Delete the brush as it is no longer needed and wastes memory
Gdip_DeleteBrush(pBrush)

; Update the specified window we have created (hwnd1) with a handle to our bitmap (hdc), specifying the x,y,w,h we want it positioned on our screen
; So this will position our gui at (0,0) with the Width and Height specified earlier
UpdateLayeredWindow(hwnd1, hdc, 0, 0, Width, Height)

; Select the object back into the hdc
SelectObject(hdc, obm)
; Now the bitmap may be deleted
DeleteObject(hbm)
; Also the device context related to the bitmap may be deleted
DeleteDC(hdc)
; The graphics may now be deleted
Gdip_DeleteGraphics(G)

If !pToken := Gdip_Startup()
{
    MsgBox, 48, gdiplus error!, Gdiplus failed to start. Please ensure you have gdiplus on your system
    ExitApp
}
frameNum1 := Gdip_CreateBitmapFromFile("resources.png") 
Gui, 2: -Caption +E0x80000 +LastFound +OwnDialogs +Owner +AlwaysOnTop
Gui, 2: Show, NA
hwnd1 := WinExist()
Width := Gdip_GetImageWidth(frameNum1), Height := Gdip_GetImageHeight(frameNum1)
hbm := CreateDIBSection(Width, Height)
hdc := CreateCompatibleDC()
obm := SelectObject(hdc, hbm)
G := Gdip_GraphicsFromHDC(hdc)
Gdip_SetInterpolationMode(G, 7)
trans := 1
Gdip_DrawImage(G, frameNum1 , 0, 0, Width/2, Height/3, 0, 0, Width, Height/6, trans)
UpdateLayeredWindow(hwnd1, hdc, 200, 600, Width, Height)

loop
{
    WinSet, AlwaysOnTop, On, ahk_id %hwnd1%
    sleep 20
}
Return

2GuiDropFiles:
; GuiControl,2:,F1
Loop, parse, A_GuiEvent, `n
   ; GuiControl,2:,F1,%A_LoopField%
   MsgBox, 4,, File number %A_Index% is:`n%A_LoopField% `n`nContinue?
   ; IfMsgBox, No, break
return


;#######################################################################
Exit:
; gdi+ may now be shutdown on exiting the program
Gdip_Shutdown(pToken)
ExitApp
Return