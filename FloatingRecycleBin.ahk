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
; Get a handle to this window we have created in order to update it later
hwnd1 := WinExist()
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
UpdateLayeredWindow(hwnd1, hdc, 0, 0, Width, Height)

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

2GuiDropFiles:
Loop, parse, A_GuiEvent, `n
   ; MsgBox, 4,, File number %A_Index% is:`n%A_LoopField% `n`nContinue?
   FileRecycle, %A_LoopField% 
   if ErrorLevel   ; i.e. it's not blank or zero.
      MsgBox, % "Failed to Recycle " A_LoopField
return


;#######################################################################
Exit:
; gdi+ may now be shutdown on exiting the program
Gdip_Shutdown(pToken)
ExitApp
Return
