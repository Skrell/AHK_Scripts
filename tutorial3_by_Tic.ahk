; gdi+ ahk tutorial 3 written by tic (Tariq Porter)
; Requires Gdip.ahk either in your Lib folder as standard library or using #Include
;
; BACKGROUND ===============================================================================
; 0,0	1,0	2,0	3,0	4,0
; 0,1	1,1	2,1	3,1	4,1
; 0,2	1,2	2,2	3,2	4,2
; 0,3	1,3	2,3	3,3	4,3
; 0,4	1,4	2,4	3,4	4,4
; 0,0 = Multiply R values
; 1,1 = Multiply G values
; 2,2 = Multiply B values
; 3,3 = Multiply A values
; For example, if a pixel had red component of 100 (0-255) then if 0,0 was 0.5, it would become 50, so 1/2 the redness for that pixel
; By that logic, 2 will double it
; Note that 1 as any of these values will keep the original value unchanged
; Negative values here will invert the value, so if R=50 and you put 0,0 as -0.5 it would become 255-(50*0.5)=230
; 0,4 = Adjust R values
; 1,4 = Adjust G values
; 2,4 = Adjust B values
; 3,4 = Adjust A values
; For example, if a pixel had a red component of 100 (0-255) then if 0,4 was 0.5, it would become R+(0.5*255)=R+128
; Use negative numbers to subtract from the original value
; Note that there is a clamp between 0 and 255, so no matter which matrix you use, the value will be between 0 and 255
; ============================================================================================
; Tutorial to take make a gui from an existing image on disk
; For the example we will use png as it can handle transparencies. The image will also be halved in size
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
; Create a layered window (+E0x80000 : must be used for UpdateLayeredWindow to work!) that is always on top (+AlwaysOnTop), has no taskbar entry or caption
Gui, 1: -Caption +E0x80000 +LastFound +AlwaysOnTop +ToolWindow +OwnDialogs
; Show the window
Gui, 1: Show, NA
; Get a handle to this window we have created in order to update it later
hwnd1 := WinExist()
; If the image we want to work with does not exist on disk, then download it...
; If !FileExist("33017060.jpg")
; UrlDownloadToFile, http://img714.imageshack.us/img714/9609/33017060.jpg, 33017060.jpg
; Get a bitmap from the image
; pBitmap := Gdip_CreateBitmapFromFile("33017060.jpg")
pBitmap := Gdip_CreateBitmapFromFile(A_WinDir . "\System32\shell32.dll", 33, 128) 
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
hbm := CreateDIBSection(Width, Height)
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
0.9		0		0		0		0
0		0.9		0		0		0
0		0		1.5		0		0
0		0		0		1		0
-1		0		5		0		1
)
Gdip_DrawImage(G, pBitmap, 0, 0, Width, Height, 0, 0, Width, Height, Matrix)
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
Return
;#######################################################################
Exit:
; gdi+ may now be shutdown on exiting the program
Gdip_Shutdown(pToken)
ExitApp
Return
