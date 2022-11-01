/*
MANPAGE:
Function: Load Bitmap from DLL
Name: GAPFromDll --> Gui Add Picture From Dll
USAGE: GAPFromDll(<GUIID>, <X>, <Y>, <Width>, <Height>, <DllFile>, <BitmapID>, <Variable>, <G-Label>)
	
	GUIID	...	For Multiple GUI's, For GUI1: "1", for GUI2: "2", ...
	X		...	Specify the X-Position in the GUI
	Y		... Specify the Y-Position in the GUI
	Width	...	Specify the Width of the Image. The Image will be resized
	Height	...	Specify the Height of the Image. The Image will be resized
	DllFile	...	Specify the .dll-File where the Bitmaps are included
	BitmapID...	Specify the ID of the Bitmap you want to show
	Variable...	Specify the Variable-Name for the Image
	G-Label	... Specify the G-Label-Name for the Image
Special Thanks to SKAN from www.autohotkey.com
http://www.autohotkey.com/forum/viewtopic.php?t=27410
*/
Gui, -Caption +AlwaysOnTop -Border -ToolWindow
Gui, Margin, 0, 0
GAPFromDll("1", "0", "0",   "500", "90", "images.dll", "1", "Test", "RunCMD")
GAPFromDll("1", "0", "100", "500", "90", "images.dll", "5", "Test2", "")
Gui, Show
Return

RunCMD:
Run, %comspec%, C:\
Return

GAPFromDll(GuiID, X, Y, W, H, DllFile, DllID, V, G, flags=0x0) {
	global
	Gui, %GuiID%:Add, Picture, x%X% y%Y% w%W% h%H% +0xE v%V% g%G% hWndPic1
	hModule := DllCall( "LoadLibrary", Str, DllFile )
	hBitmap := DllCall( "LoadImageA", UInt, hModule, UInt, DllID, UInt, (IMAGE_BITMAP:=0x0)
						, UInt, W, UInt, H, UInt, (LR_SHARED := 0x8000))
	SendMessage, 0x172, flags, hBitmap, , ahk_id %Pic1%
	DllCall("FreeLibrary", "UInt", hModule)
	Return, %Errorlevel%
	}
    
GuiEscape:
GuiClose:
ExitApp
