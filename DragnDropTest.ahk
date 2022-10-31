;-- example Drag & Drop picture  with freeware Irfanview
;-- use commandlines to convert / resize etc Pictures/Photos's
modified=20140225
;- irfanview drag&drop resize convert
;- http://www.irfanview.com/
filename1=Irfanview_Drag&Drop convert resize
PR=%A_ProgramFiles%\IrfanView\i_view32.exe
Gui,2: Font, default, FixedSys
Gui,2:add,button  , x840 y15 h22 w100  gStart1       ,Start
Gui,2:Show, x50 y10 w970 h50,%Filename1%
Gui,2:add,edit    , x10 y10 h35 w820   vF1,Drag&Drop picture here
return

2Guiclose:
exitapp

start1:
Gui,2:submit,nohide
GuiControlGet,F1
SplitPath, F1, name, dir, ext, name_no_ext, drive
If Ext Not In jpg,bmp,tif
{
msgbox, 262192, Picture MESSAGE,Only pictures tif bmp jpg
return
}
;-- resize a picture
;new=%a_scriptdir%\%name_no_ext%_new.%ext%
;aa=/resize=(800,0) /aspectratio /convert=%new%
;- convert to pdf -------
;new=%a_scriptdir%\%name_no_ext%_new.pdf
;aa=/convert=%new%
;- convert to ico -------
new=%a_desktop%\%name_no_ext%_new.ico
;aa= /aspectratio /resize=(138`,0) /gray /convert=%new%
aa= /aspectratio /resize=(138`,0) /convert=%new%
runwait,%PR% %F1% %aa%
ifexist,%new%
    run,%new%
return

2GuiDropFiles:
; GuiControl,2:,F1
Loop, parse, A_GuiEvent, `n
   ; GuiControl,2:,F1,%A_LoopField%
   MsgBox, 4,, File number %A_Index% is:`n%A_LoopField%.`n`nContinue?
   ; IfMsgBox, No, break
return
;=============== end script ==============
