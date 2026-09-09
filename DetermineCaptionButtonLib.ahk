; ============================================================================
; DetermineCaptionButtonLib.ahk
; -----------------------------------------------------------------------------
; Dormant general, accessibility, and UI Automation helpers retained as an
; optional library rather than mixed into AutoCorrect_Sept5.ahk's active logic.
;
; Host-owned global variables required by selected helpers:
;   UIA                                      UIAutomation interface instance.
;   overlayAlphaCurrent, overlayHwnd,
;   overlayIsReady                           Active overlay state.
;
; AutoHotkey v1 requires each function that reads those globals to declare them
; inside its own body. AutoCorrect_Sept5.ahk continues to initialize the values.
; Other helper dependencies remain in AutoCorrect_Sept5.ahk, so this file must
; be included by that script rather than run independently.
; ============================================================================

; Purpose        : Walk up an accessibility parent chain to find a header-like
;                  object associated with the current accessibility target.
; Why this exists: normal header roles are not always exposed consistently by
;                  classic #32770 file dialogs.
Acc_FindHeaderObject(accObj, cls, outlineRole, colHeaderRole, menuPopupRole, directUIHwnd := 0) {

    if !IsObject(accObj) {
        return 0
    }

    needQuirkCheck := (cls = "#32770")
    checked := 0
    cur := accObj

    Loop, 10
    {
        if !IsObject(cur) {
            break
        }

        ; Limit native ownership checks because each one calls a Windows API.
        if (directUIHwnd && checked < 2) {
            hostHwnd := Acc_WindowFromObjectSafe(cur)
            checked += 1
            if (hostHwnd && hostHwnd != directUIHwnd) {
                break
            }
        }

        role := Acc_RoleIdSafe(cur)

        if (!role) {
            cur := Acc_ParentSafe(cur)
            continue
        }

        if (role = colHeaderRole || role = outlineRole) {
            return cur
        }

        if (needQuirkCheck && role = menuPopupRole) {
            if (Acc_NameIsKnownColumnSafe(cur)) {
                return cur
            }
        }

        cur := Acc_ParentSafe(cur)
    }
    return 0
}

; Search a bounded accessibility subtree for text that resembles an address bar
; or breadcrumb marker without allowing an unexpectedly large traversal.
Acc_FindLikelyAddressMarker(rootAcc, maxNodes := 60) {

    if !IsObject(rootAcc)
        return false

    queueList.Push(rootAcc)

    while (queueIndex <= queueList.Length() && seenCount < maxNodes)
    {
        currentAcc := queueList[queueIndex]
        queueIndex += 1
        seenCount += 1

        currentValue := Acc_ValueSafe(currentAcc)
        if (currentValue != "")
        {
            if (InStr(currentValue, ":\")
             || InStr(currentValue, "\\")
             || InStr(currentValue, "Breadcrumb")
             || InStr(currentValue, "Address"))
                return true
        }

        currentName := Acc_NameSafe(currentAcc)
        if (currentName != "")
        {
            if (InStr(currentName, ":\")
             || InStr(currentName, "\\")
             || InStr(currentName, "Breadcrumb")
             || InStr(currentName, "Address"))
                return true
        }

        childrenList := Acc_GetChildrenListSafe(currentAcc)
        for childIndex, childAcc in childrenList
        {
            if IsObject(childAcc)
                queueList.Push(childAcc)
        }
    }

    return false
}

; Return the accessibility object under a screen point, with a native hit-test
; fallback for providers that do not answer Acc_ObjectFromPoint directly.
Acc_GetObjectAtScreenPoint(xPos, yPos) {

    accObj := Acc_ObjectFromPoint(, xPos, yPos)
    if IsObject(accObj)
        return accObj

    ; Some providers reject the direct lookup, so identify the native host and
    ; ask its accessibility root to hit-test the same screen coordinates.
    VarSetCapacity(pointStruct, 8, 0)
    NumPut(xPos, pointStruct, 0, "Int")
    NumPut(yPos, pointStruct, 4, "Int")

    hwndUnder := DllCall("user32\WindowFromPoint", "Ptr", &pointStruct, "Ptr")
    if (!hwndUnder)
        return ""

    accRoot := Acc_ObjectFromWindow(hwndUnder)
    if !IsObject(accRoot)
        return ""

    hitVal := ""

    ; accHitTest may return either an accessibility object or a numeric child ID.
    try
        hitVal := accRoot.accHitTest(xPos, yPos)
    catch
        return ""

    if IsObject(hitVal)
        return hitVal

    if (hitVal = "" || hitVal = 0 || hitVal = "0")
        return ""

    childId := hitVal + 0
    if (childId = 0 && hitVal != 0 && hitVal != "0")
        return ""

    try
        childObj := accRoot.accChild(childId)
    catch
        childObj := ""

    if IsObject(childObj)
        return childObj

    return Acc_CreateChildRef(accRoot, childId)
}

; Return whether a screen point lies inside an accessibility object's visible
; screen rectangle; fail closed if the provider cannot report one.
Acc_PointInAccRect(accObj, sx, sy) {

    if (!Acc_LocationSafe(accObj, ax, ay, aw, ah))
        return false

    if (aw <= 0 || ah <= 0)
        return false

    ; A missing or empty rectangle cannot establish that the point is inside.
    return (sx >= ax && sx < ax + aw && sy >= ay && sy < ay + ah)
}

; Return a readable MSAA role name only when the target can be resolved safely.
Acc_RoleNameSafe(accObj) {

    if !Acc_ResolveTarget(accObj, iaObj, childId)
        return ""

    try
        roleValue := iaObj.accRole(childId)
    catch
        return ""

    roleNumber := roleValue + 0
    if (roleNumber = 0 && roleValue != 0 && roleValue != "0")
        return ""

    return Acc_GetRoleText(roleNumber)
}

; Query an object for IAccessible while converting unsupported-provider failures
; into a zero result instead of allowing an exception to escape.
Acc_TryGetIAccessibleSafe(accObj) {

    if !IsObject(accObj)
        return 0

    try {
        iAccessiblePtr := ComObjQuery(accObj, "{618736E0-3C3D-11CF-810C-00AA00389B71}")
        if !iAccessiblePtr
            return 0

        return ComObjEnwrap(9, iAccessiblePtr, 1)
    }
    catch {
        return 0
    }
}

; Show the MSAA role ancestry beneath the mouse for manual diagnostics.
DebugRolesUnderMouse() {

    CoordMode, Mouse, Screen
    MouseGetPos, fn_DebugRolesUnderMouse_mx, fn_DebugRolesUnderMouse_my
    childId := 0
    acc := Acc_ObjectFromPoint(childId, fn_DebugRolesUnderMouse_mx, fn_DebugRolesUnderMouse_my)
    if !IsObject(acc) {
        MsgBox, No acc object
        return
    }

    out := ""
    cur := acc
    Loop, 20
    {
        if !IsObject(cur)
            break

        role := ""
        try role := cur.accRole(0)
        catch
            break

        out .= "Level " . A_Index . ": " . role . "`n"

        parent := ""
        try parent := cur.accParent
        cur := parent
    }
    MsgBox, %out%
}

; Return the paths selected in the foreground desktop or Explorer shell view.
Explorer_GetSelection() {

   WinGetClass, winClass, % "ahk_id" . hWnd := WinExist("A")
   If !(winClass ~= "^(Progman|WorkerW|(Cabinet|Explore)WClass)$")
      Return

   shellWindows := ComObjCreate("Shell.Application").Windows
   If (winClass ~= "Progman|WorkerW")
      shellFolderView := shellWindows.Item( ComObject(VT_UI4 := 0x13, SWC_DESKTOP := 0x8) ).Document
   Else {
      for window in shellWindows
         If (hWnd = window.HWND) && (shellFolderView := window.Document)
            break
   }

   ; An Explorer window can close or stop exposing a Shell view during iteration.
   if !IsObject(shellFolderView)
      Return ""

   for item in shellFolderView.SelectedItems
      result .= (result = "" ? "" : "`n") . item.Path
   Return result
}

; Return the second eligible window on a display, or the first one after ref_hwndID.
FindSecondMostWindow(ref_hwndID := "", displayNumber := 0) {

    monitorCount := GetMonitorCount()
    DetectHiddenWindows, Off

    firstFound := False
    targetID   := 0

    WinGet, winList, List,
    if (!displayNumber)
        displayNumber := GetMouseDisplayNumber()

    Loop, %winList%
    {
        fn_FindSecondMostWindow_hwndID := winList%A_Index%
        If IsAltTabWindow(fn_FindSecondMostWindow_hwndID) && !IsAlwaysOnTop(fn_FindSecondMostWindow_hwndID) {
            WinGet, mmState, MinMax, ahk_id %fn_FindSecondMostWindow_hwndID%

            If (mmState > -1) {
                If (monitorCount > 1) {
                    fn_FindSecondMostWindow_currentMonHasActWin := IsWindowOnDisplayNumber(fn_FindSecondMostWindow_hwndID, displayNumber)
                }
                Else {
                    fn_FindSecondMostWindow_currentMonHasActWin := True
                }

                if !ref_hwndID {
                    ; With no reference, skip the first eligible window and
                    ; return the second eligible window in Z order.
                    If (!firstFound && fn_FindSecondMostWindow_currentMonHasActWin)
                        firstFound := True
                    Else If (firstFound && fn_FindSecondMostWindow_currentMonHasActWin) {
                        targetID := fn_FindSecondMostWindow_hwndID
                        break
                    }
                }
                Else {
                    ; With a reference, begin considering eligible windows only
                    ; after that window has appeared in the Z-order enumeration.
                    If (fn_FindSecondMostWindow_hwndID == ref_hwndID) {
                        firstFound := True
                    }
                    Else If (firstFound && fn_FindSecondMostWindow_currentMonHasActWin) {
                        targetID := fn_FindSecondMostWindow_hwndID
                        break
                    }
                }
            }
        }
    }
    Return targetID
}

; Compute the second alpha value required for two layered windows to produce a
; requested combined opacity.
Get2ndAlphaForTransparencyTarget(alphaPrimary, alphaTarget) {
    alphaPrimary := ClampAlpha(alphaPrimary)
    alphaTarget := ClampAlpha(alphaTarget)

    ; Layered alpha combines through the remaining transparent fraction, not by
    ; simply adding the two alpha values.
    remainingPrimary255 := 255 - alphaPrimary
    requiredBackground255 := 255 - alphaTarget

    ; A fully opaque primary window forces the stacked result to full opacity.
    if (remainingPrimary255 <= 0)
    {
        return 0
    }

    ; Solve the required remaining transparency for the second layer.
    remainingOther := requiredBackground255 / (remainingPrimary255 * 1.0)

    ; Keep rounding or out-of-range inputs from producing an invalid alpha.
    if (remainingOther < 0.0)
    {
        remainingOther := 0.0
    }
    else if (remainingOther > 1.0)
    {
        remainingOther := 1.0
    }

    opacityOther := 1.0 - remainingOther
    alphaOther := Round(opacityOther * 255.0)

    return ClampAlpha(alphaOther)
}

; Return whether the control beneath the mouse exposes a standard scroll style.
IsWindowScrollable() {

    MouseGetPos, , , hwnd, ctrlN
    WinGet, ExControlStyle, ExStyle, ahk_id %hwnd%
    ControlGet, ControlStyle, Style,, %ctrlN%, ahk_id %hwnd%
    If (((ControlStyle & 0x100000) || (ControlStyle & 0x200000)) || (ExControlStyle & 0x4000)) {
        Return True
    }
    Else {
        Return False
    }
}

; Return whether the pointer is over a taskbar button group rather than the tray.
MouseIsOverTaskbarButtonGroup() {

    CoordMode, Mouse, Screen
    MouseGetPos, x, y, WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId != "TrayNotifyWnd1") {
        fn_MouseIsOverTaskbarButtonGroup_pt := SafeUIA_ElementFromPoint(x,y, "", 2000)
        fn_MouseIsOverTaskbarButtonGroup_ctype := SafeUIA_GetControlType(fn_MouseIsOverTaskbarButtonGroup_pt)
        Return (fn_MouseIsOverTaskbarButtonGroup_ctype == 50000)
    }
    Else
        Return False
}

; Return whether the pointer is over the notification-area child of a taskbar.
MouseIsOverTaskbarTray() {

    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    Return (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId == "TrayNotifyWnd1")
}

; Move to the actual default enabled button of a standard, non-resizable dialog.
MoveMouseToDefaultDialogButton(hwndDlg := "", moveSpeed := 0) {

    static BS_DEFPUSHBUTTON  := 0x00000001
    static BS_DEFSPLITBUTTON := 0x0000000D
    static BS_DEFCOMMANDLINK := 0x0000000F
    static BS_TYPEMASK       := 0x0000000F

    static DC_HASDEFID       := 0x534B
    static DM_GETDEFID       := 0x0400
    static GWL_STYLE         := -16
    static SMTO_ABORTIFHUNG  := 0x0002
    static WS_MAXIMIZEBOX    := 0x00010000
    static WS_MINIMIZEBOX    := 0x00020000

    ; An omitted handle means operate on the dialog the user is currently using.
    if (!hwndDlg)
        WinGet, hwndDlg, ID, A

    if (!hwndDlg || !DllCall("user32\IsWindow", "Ptr", hwndDlg, "Int"))
        return 0

    ; Dialog-manager default-button messages apply only to classic dialog windows.
    if (GetClassName(hwndDlg) != "#32770")
        return 0

    dialogStyle := DllCall(A_PtrSize = 8 ? "user32\GetWindowLongPtrW" : "user32\GetWindowLongW"
        , "Ptr", hwndDlg
        , "Int", GWL_STYLE
        , "Ptr")

    ; Exclude dialogs that expose caption Minimize or Maximize buttons.
    if (dialogStyle & (WS_MINIMIZEBOX | WS_MAXIMIZEBOX))
        return 0

    btnHwnd       := 0
    msgResult     := 0
    defaultCtrlId := 0

    ; DM_GETDEFID is the dialog manager's authoritative default-button choice;
    ; use a timeout so an unresponsive dialog cannot stall the script.
    ok := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", hwndDlg
        , "UInt", DM_GETDEFID
        , "Ptr", 0
        , "Ptr", 0
        , "UInt", SMTO_ABORTIFHUNG
        , "UInt", 100
        , "UPtr*", msgResult)

    if (ok && (((msgResult >> 16) & 0xFFFF) = DC_HASDEFID))
        defaultCtrlId := msgResult & 0xFFFF

    if (defaultCtrlId) {
        h := DllCall("user32\GetDlgItem", "Ptr", hwndDlg, "Int", defaultCtrlId, "Ptr")

        if (IsUsableDialogPushButton(h)) {
            btnHwnd := h
        }
    }

    ; If the dialog manager did not identify a usable control, find a button
    ; whose own style marks it as the default.
    if (!btnHwnd) {
        WinGet, listH, ControlListHwnd, ahk_id %hwndDlg%

        Loop, Parse, listH, `n, `r
        {
            h := A_LoopField + 0
            if (!h)
                continue

            if (!IsUsableDialogPushButton(h))
                continue

            style := DllCall(A_PtrSize = 8 ? "user32\GetWindowLongPtrW" : "user32\GetWindowLongW"
                , "Ptr", h
                , "Int", GWL_STYLE
                , "Ptr")

            buttonType := style & BS_TYPEMASK

            if (buttonType = BS_DEFPUSHBUTTON
             || buttonType = BS_DEFSPLITBUTTON
             || buttonType = BS_DEFCOMMANDLINK) {
                btnHwnd := h
                break
            }
        }
    }

    ; Never guess an arbitrary button: a dialog without an actual default button
    ; must leave the cursor where it is.
    if (!btnHwnd)
        return 0

    WinGetPos, bx, by, bw, bh, ahk_id %btnHwnd%
    if (bw = "" || bh = "" || bw <= 0 || bh <= 0)
        return 0

    fn_MoveMouseToDefaultDialogButton_targetPosX := bx + Floor(bw / 2)
    fn_MoveMouseToDefaultDialogButton_targetPosY := by + Floor(bh / 2)

    if (moveSpeed > 0) {
        oldCoordModeMouse := A_CoordModeMouse
        CoordMode, Mouse, Screen
        MouseMove, %fn_MoveMouseToDefaultDialogButton_targetPosX%, %fn_MoveMouseToDefaultDialogButton_targetPosY%, %moveSpeed%
        CoordMode, Mouse, %oldCoordModeMouse%
    }
    else {
        DllCall("user32\SetCursorPos", "Int", fn_MoveMouseToDefaultDialogButton_targetPosX, "Int", fn_MoveMouseToDefaultDialogButton_targetPosY)
    }

    return btnHwnd
}

; Set the active overlay's opacity immediately or request a fade to it.
Overlay_SetOpacity(alphaVal, fadeMs := 0) {
    global overlayHwnd, overlayIsReady, overlayAlphaCurrent

    if (!overlayIsReady || !overlayHwnd || !DllCall("IsWindow", "ptr", overlayHwnd))
        return 0

    if (alphaVal < 0)
        alphaVal := 0
    else if (alphaVal > 255)
        alphaVal := 255

    ; Cancel a prior fade so its timer cannot overwrite this newer opacity request.
    Overlay_CancelFade()

    if (fadeMs > 0) {
        ; Fade from the live overlay alpha rather than an assumed starting value.
        Overlay_FadeTo(overlayHwnd, alphaVal, fadeMs, overlayAlphaCurrent)
    } else {
        ; No duration means the caller needs the new opacity immediately.
        Overlay_SetAlpha(overlayHwnd, alphaVal)
    }

    return 1
}

/*
    Read the UIA ClassName property, which is the provider-reported class label
    such as UIItem, UIItemsView, DirectUI, or another framework-specific name.

    Parameters:
    el            = UIA element to read from.
    default := "" = fallback value if the property cannot be read.
*/
SafeUIA_GetClassName(el, default := "") {
    if !IsObject(el)
        return default
    try
        return el.CurrentClassName
    catch e
        return default
}

/*
    Read the UIA IsContentElement flag. This helps distinguish UI content from
    provider plumbing when inspecting elements under the pointer.

    Parameters:
    el           = UIA element to read from.
    default := 0 = fallback value if the property cannot be read.
*/
SafeUIA_GetIsContentElement(el, default := 0) {
    if !IsObject(el)
        return default
    try
        return el.CurrentIsContentElement
    catch e
        return default
}

/*
    Read the UIA IsControlElement flag. This identifies elements exposed as
    interactive controls when inspecting the UI Automation tree.

    Parameters:
    el           = UIA element to read from.
    default := 0 = fallback value if the property cannot be read.
*/
SafeUIA_GetIsControlElement(el, default := 0) {
    if !IsObject(el)
        return default
    try
        return el.CurrentIsControlElement
    catch e
        return default
}

/*
    Read the UIA Orientation property, which tells whether the provider exposes
    a control as horizontal, vertical, or with no reported orientation.

    Parameters:
    el          = UIA element to read from.
    default := 0 = fallback value if the property cannot be read.
*/
SafeUIA_GetOrientation(el, default := 0) {
    if !IsObject(el)
        return default
    try
        return el.CurrentOrientation
    catch e
        return default
}

/*
    Return a UIA element's parent while treating provider disconnection as a
    normal lookup failure rather than an unhandled script exception.

    Parameters:
    el = UIA element whose parent is needed.
*/
SafeUIA_GetParent(el) {
    if !IsObject(el)
        return ""
    try
        return el.Parent
    catch e
        return ""
}

; Return the center and width of the current taskbar Start button when UIA can
; locate it through a stable AutomationId or localized name fallback.
UIA_GetStartButtonCenter(ByRef sx, ByRef sy, ByRef buttonWidth) {
    global UIA

    try {
        hTask := WinExist("ahk_class Shell_TrayWnd")
        if !hTask
            return False

        tb := UIA.ElementFromHandle(hTask)
        if (IsObject(tb)) {
            ; AutomationId avoids localized labels; name lookups cover taskbars
            ; that do not expose that stable identifier.
            startEl := tb.FindFirstBy("AutomationId=StartButton")

            if !IsObject(startEl)
                startEl := tb.FindFirstByNameAndType("Start", "Button")
            if !IsObject(startEl)
                startEl := tb.FindFirstByNameAndType("Start menu", "Button")
            if !IsObject(startEl)
                return False

            ; Read the provider's bounds, accepting older UIA_Interface property
            ; shapes before deriving the button's screen center below.
            rect := startEl.CurrentBoundingRectangle
            if (!IsObject(rect) && rect == "") {
                rect := startEl.BoundingRectangle ? startEl.BoundingRectangle : startEl.GetBoundingRectangle()
            }
        }
        else {
            tooltip, no taskbar found...
            sleep, 1500
            tooltip,
        }

        if (IsObject(rect)) {
            sx := round(rect.l + (rect.r-rect.l)/2)
            sy := round(rect.t + (rect.b-rect.t)/2)
            buttonWidth := rect.r-rect.l
            return true
        }
        else
            return False

    } catch e {
        return False
    }
}
