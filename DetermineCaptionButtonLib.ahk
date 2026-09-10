; ============================================================================
; DetermineCaptionButtonLib.ahk
; -----------------------------------------------------------------------------
; Dormant general, accessibility, and UI Automation helpers retained as an
; optional library rather than mixed into AutoCorrect_Sept5.ahk's active logic.
; UIA_Interface is included here so importing this library also imports the
; UI Automation implementation used by its UIA-facing helpers.
; ============================================================================
#include %A_ScriptDir%\UIAutomation-main\Lib\UIA_Interface.ahk
; ============================================================================
;
; Host-owned global variables required by selected helpers:
;   UIA                                      UIAutomation interface instance.
;   overlayAlphaCurrent, overlayFadeToken, overlayHwnd,
;   overlayIsReady                           Active overlay state.
;
; AutoHotkey v1 requires each function that reads those globals to declare them
; inside its own body. AutoCorrect_Sept5.ahk continues to initialize the values.
; ============================================================================

; Module handle retained so Acc_Shutdown() can release the oleacc.dll reference loaded by Acc_Init().
Global Acc_ModuleHandle := 0

; +----------------------------------------------------------------------------+
; | Virtual Desktop DLL Bindings                                               |
; | Holds the DLL name/path, module handle, and exported function pointers     |
; | used by the virtual-desktop helpers.                                       |
; +----------------------------------------------------------------------------+
; DLL filename used to construct k_dllPath.
Global k_VDA_DllName := "VirtualDesktopAccessor_Win11.dll"

; Full path of the VirtualDesktopAccessor DLL beside the script or executable.
; This remains after k_VDA_DllName because it derives its value from that name.
Global k_dllPath := A_ScriptDir . "\" . k_VDA_DllName

; Export pointer used to create a virtual desktop.
Global CreateDesktopProc := 0

; Export pointer used to read the current virtual desktop number.
Global GetCurrentDesktopNumberProc := 0

; Export pointer used to read the virtual desktop count.
Global GetDesktopCountProc := 0

; Export pointer used to read a virtual desktop name.
Global GetDesktopNameProc := 0

; Loaded VirtualDesktopAccessor module handle used to resolve exports.
Global hVirtualDesktopAccessor := 0

; Export pointer used to test whether a window is pinned across desktops.
Global IsPinnedWindowProc := 0

; Export pointer used to test whether a window is on the current desktop.
Global IsWindowOnCurrentVirtualDesktopProc := 0

; Export pointer used to test whether a window belongs to a desktop number.
Global IsWindowOnDesktopNumberProc := 0

; Export pointer used to move a window to a desktop number.
Global MoveWindowToDesktopNumberProc := 0

; Export pointer used to remove a virtual desktop.
Global RemoveDesktopProc := 0

; Export pointer used to change a virtual desktop name.
Global SetDesktopNameProc := 0

; Cached height of the current monitor for display-aware callers.
Global currMonHeight := 0

; Cached width of the current monitor for display-aware callers.
Global currMonWidth := 0

; Number of monitor records collected at startup.
Global g_MonitorCount := 0

; Monitor records indexed by the normalized Windows display number.
Global g_MonitorsByDisplayNumber := []

; Normalized display number of the primary monitor.
Global g_PrimaryDisplayNumber := 0

; Cached monitor records and common monitor/display lookups. Resize-specific
; helpers, such as GetMonitorRectsForWindow(), remain with their resize logic.
;------------------------------------------------------------------------------
; Build startup monitor and work-area records with the primary monitor at display #1.
_BuildMonitorDimensions() {
    global g_MonitorCount
    global g_MonitorsByDisplayNumber, g_PrimaryDisplayNumber

    SysGet, primarySysGetNumber, MonitorPrimary
    SysGet, monitorCount, MonitorCount
    monitorsByDisplayNumber := []
    primaryDisplayNumber    := 0

    Loop, %monitorCount% {
        sysGetNumber := A_Index
        SysGet, fullArea, Monitor, %sysGetNumber%
        SysGet, monitorName, MonitorName, %sysGetNumber%
        SysGet, workArea, MonitorWorkArea, %sysGetNumber%

        ; Reserve cache key #1 for the primary monitor. Shift any earlier SysGet
        ; monitor number forward so secondary cache keys remain unique and ordered.
        if (sysGetNumber = primarySysGetNumber)
            displayNumber := 1
        else if (sysGetNumber < primarySysGetNumber)
            displayNumber := sysGetNumber + 1
        else
            displayNumber := sysGetNumber

        ; Cache the native monitor handle with the geometry so window-to-monitor
        ; lookups can compare handles without rebuilding every monitor RECT.
        VarSetCapacity(monitorRect, 16, 0)
        ; Store the monitor's left edge in RECT.left so MonitorFromRect identifies this monitor.
        NumPut(fullAreaLeft,   monitorRect, 0,  "Int")
        ; Store the monitor's top edge in RECT.top so MonitorFromRect identifies this monitor.
        NumPut(fullAreaTop,    monitorRect, 4,  "Int")
        ; Store the monitor's right edge in RECT.right so MonitorFromRect identifies this monitor.
        NumPut(fullAreaRight,  monitorRect, 8,  "Int")
        ; Store the monitor's bottom edge in RECT.bottom so MonitorFromRect identifies this monitor.
        NumPut(fullAreaBottom, monitorRect, 12, "Int")
        monitorHandle := DllCall("MonitorFromRect", "Ptr", &monitorRect, "UInt", 2, "Ptr")

        ; Create the monitor object described beside g_MonitorsByDisplayNumber.
        monitorInfo := { displayNumber: displayNumber
                        , fullArea: { bottom: fullAreaBottom
                                    , height: fullAreaBottom - fullAreaTop
                                    , left: fullAreaLeft
                                    , right: fullAreaRight
                                    , top: fullAreaTop
                                    , width: fullAreaRight - fullAreaLeft }
                        , isPrimary: (sysGetNumber = primarySysGetNumber)
                        , monitorHandle: monitorHandle
                        , monitorName: monitorName
                        , sysGetNumber: sysGetNumber
                        , workArea: { bottom: workAreaBottom
                                    , height: workAreaBottom - workAreaTop
                                    , left: workAreaLeft
                                    , right: workAreaRight
                                    , top: workAreaTop
                                    , width: workAreaRight - workAreaLeft } }
        monitorsByDisplayNumber[displayNumber] := monitorInfo

        if (sysGetNumber = primarySysGetNumber)
            primaryDisplayNumber := displayNumber
    }

    g_MonitorCount              := monitorCount
    g_MonitorsByDisplayNumber   := monitorsByDisplayNumber
    g_PrimaryDisplayNumber      := primaryDisplayNumber
}

; Return the cached monitor record for a display number whose primary monitor is #1.
_GetMonitorRecordByDisplayNumber(displayNumber) {
    global g_MonitorsByDisplayNumber

    if (!g_MonitorsByDisplayNumber.HasKey(displayNumber))
        return ""

    return g_MonitorsByDisplayNumber[displayNumber]
}

; Return the monitor containing a point, or the nearest monitor when requested.
_GetMonitorRecordForPoint(mx, my, useWorkArea := false, useNearestFallback := false) {
    global g_MonitorsByDisplayNumber, g_PrimaryDisplayNumber

    bestDistanceSquared := 0x7FFFFFFF
    bestMonitor         := ""

    for displayNumber, monitorInfo in g_MonitorsByDisplayNumber {
        rectangle := useWorkArea ? monitorInfo.workArea : monitorInfo.fullArea
        if (mx >= rectangle.left && mx < rectangle.right && my >= rectangle.top && my < rectangle.bottom)
            return monitorInfo

        clampedX        := (mx < rectangle.left) ? rectangle.left : (mx > rectangle.right ? rectangle.right : mx)
        clampedY        := (my < rectangle.top) ? rectangle.top : (my > rectangle.bottom ? rectangle.bottom : my)
        deltaX          := mx - clampedX
        deltaY          := my - clampedY
        distanceSquared := deltaX * deltaX + deltaY * deltaY
        if (distanceSquared < bestDistanceSquared) {
            bestDistanceSquared := distanceSquared
            bestMonitor         := monitorInfo
        }
    }

    if (useNearestFallback && IsObject(bestMonitor))
        return bestMonitor

    if (useNearestFallback)
        return _GetMonitorRecordByDisplayNumber(g_PrimaryDisplayNumber)

    return ""
}

; Copy cached full-monitor or work-area bounds into scalar output variables.
_GetMonitorRectangleByDisplayNumber(displayNumber, useWorkArea, ByRef left, ByRef top, ByRef right, ByRef bottom) {
    monitorInfo := _GetMonitorRecordByDisplayNumber(displayNumber)
    if (!IsObject(monitorInfo)) {
        bottom := 0
        left   := 0
        right  := 0
        top    := 0
        return false
    }

    rectangle := useWorkArea ? monitorInfo.workArea : monitorInfo.fullArea
    bottom    := rectangle.bottom
    left      := rectangle.left
    right     := rectangle.right
    top       := rectangle.top
    return true
}

; Resolve one VirtualDesktopAccessor export from the loaded library module.
_gp(name)
{
    global hVirtualDesktopAccessor
    ; NO InitVDA() here.
    return DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", name, "Ptr")
}

; Wrap an MSAA parent object and child ID so callers can retain a child reference.
Acc_CreateChildRef(parentIA, childId) {
    local childRef := {}

    ; Create an ordinary AutoHotkey object to represent an MSAA child without losing its parent object.
    ; Mark this object so the safe MSAA helpers can distinguish it from a native MSAA object.
    childRef.__accChildRef := true
    ; Keep the parent IAccessible object because MSAA exposes some children only by numeric ID.
    childRef.acc := parentIA
    ; Preserve the numeric child ID that identifies this child within its parent.
    childRef.child := childId
    return childRef
}

; Purpose        : Walk up an accessibility parent chain to find a header-like
;                  object associated with the current accessibility target.
; Why this exists: normal header roles are not always exposed consistently by
;                  classic #32770 file dialogs.
Acc_FindHeaderObject(accObj, cls, outlineRole, colHeaderRole, menuPopupRole, directUIHwnd := 0) {
    local cur, role, needQuirkCheck, hostHwnd, checked

    if !IsObject(accObj) {
        ; A missing accessibility object cannot have a header ancestor.
        return 0
    }

    ; #32770 is the Windows class used by standard common file dialogs.
    needQuirkCheck := (cls = "#32770")
    ; Start at the supplied accessibility target and follow its parent links.
    checked := 0
    cur := accObj

    ; Stop after ten ancestors so an unusual provider cannot cause an unbounded walk.
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

        ; MSAA roles describe a control's semantic type, such as a column header or outline.
        role := Acc_RoleIdSafe(cur)

        if (!role) {
            ; Skip objects that do not report a usable role and continue toward their parent.
            cur := Acc_ParentSafe(cur)
            continue
        }

        if (role = colHeaderRole || role = outlineRole) {
            ; The target itself is a header-like control, so return the matching MSAA object.
            return cur
        }

        if (needQuirkCheck && role = menuPopupRole) {
            ; Some standard file dialogs expose a column header as a menu popup instead.
            if (Acc_NameIsKnownColumnSafe(cur)) {
                return cur
            }
        }

        ; Move upward through the MSAA tree to inspect the next containing control.
        cur := Acc_ParentSafe(cur)
    }
    return 0
}

; Search a bounded accessibility subtree for text that resembles an address bar
; or breadcrumb marker without allowing an unexpectedly large traversal.
Acc_FindLikelyAddressMarker(rootAcc, maxNodes := 60) {
    local queueList := []
    local queueIndex := 1
    local seenCount := 0
    local currentAcc, currentName, currentValue
    local childrenList, childIndex, childAcc

    if !IsObject(rootAcc)
        ; A missing root has no subtree to search.
        return false

    ; Use a queue to visit controls breadth-first, starting with the supplied root.
    queueList.Push(rootAcc)

    while (queueIndex <= queueList.Length() && seenCount < maxNodes)
    {
        currentAcc := queueList[queueIndex]
        queueIndex += 1
        seenCount += 1

        ; MSAA providers may expose visible text as either a Value or a Name property.
        currentValue := Acc_ValueSafe(currentAcc)
        if (currentValue != "")
        {
            if (InStr(currentValue, ":\")
             || InStr(currentValue, "\\")
             || InStr(currentValue, "Breadcrumb")
             || InStr(currentValue, "Address"))
                return true
        }

        ; Check the Name property too because it is commonly used for static labels.
        currentName := Acc_NameSafe(currentAcc)
        if (currentName != "")
        {
            if (InStr(currentName, ":\")
             || InStr(currentName, "\\")
             || InStr(currentName, "Breadcrumb")
             || InStr(currentName, "Address"))
                return true
        }

        ; Add only real child objects so the next loop iteration can examine them safely.
        childrenList := Acc_GetChildrenListSafe(currentAcc)
        for childIndex, childAcc in childrenList
        {
            if IsObject(childAcc)
                queueList.Push(childAcc)
        }
    }

    return false
}

; Find path-like text in a bounded MSAA subtree.
Acc_FindLikelyPathText(rootAcc, maxNodes := 140) {
    local queueList := []
    local queueIndex := 1
    local seenCount := 0
    local currentAcc, currentName, currentValue
    local childrenList, childIndex, childAcc

    ; Search with a queue so the closest descendants are considered before deeper controls.

    if !IsObject(rootAcc)
        ; There is no path text to find without an MSAA root object.
        return ""

    queueList.Push(rootAcc)

    while (queueIndex <= queueList.Length() && seenCount < maxNodes)
    {
        currentAcc := queueList[queueIndex]
        queueIndex += 1
        seenCount += 1

        ; Prefer a Value because editable address controls usually expose their text there.
        currentValue := Acc_ValueSafe(currentAcc)
        if (currentValue != "" && currentValue != "Address Band" && Acc_LooksLikePath(currentValue))
            return currentValue

        ; Fall back to Name because read-only breadcrumb controls commonly use that property.
        currentName := Acc_NameSafe(currentAcc)
        if (currentName != "" && currentName != "Address Band" && Acc_LooksLikePath(currentName))
            return currentName

        ; Continue through child controls while Acc_GetChildrenListSafe limits provider output.
        childrenList := Acc_GetChildrenListSafe(currentAcc)
        for childIndex, childAcc in childrenList
        {
            if IsObject(childAcc)
                queueList.Push(childAcc)
        }
    }

    return ""
}

; Return the MSAA object associated with a window handle.
Acc_FromWindow(hWnd, objID, ByRef acc) {
    ; Cache the 16-byte IAccessible interface identifier after it is first converted.
    static iid
    static iidReady := false
    local pacc := 0

    if (!iidReady) {
        ; Reserve memory for the Windows GUID that identifies the IAccessible COM interface.
        VarSetCapacity(iid, 16, 0)
        ; Convert the readable GUID into the binary form required by AccessibleObjectFromWindow.
        DllCall("ole32\CLSIDFromString" , "WStr", "{618736E0-3C3D-11CF-810C-00AA00389B71}" , "Ptr", &iid)
        iidReady := true
    }

    ; Ask Windows for the requested accessibility object associated with this window handle.
    if (DllCall("oleacc\AccessibleObjectFromWindow"
        , "Ptr", hWnd
        , "UInt", objID
        , "Ptr", &iid
        , "Ptr*", pacc
        , "Int") = 0)
    {
        ; Wrap the returned COM pointer so AutoHotkey manages it as an MSAA object.
        acc := ComObjEnwrap(9, pacc, 1)
        return true
    }

    return false
}

; Collect MSAA children while converting provider errors to an empty list.
Acc_GetChildrenListSafe(accObj, maxChildren := 60) {
    local iaObj, childrenCount := 0, fetchedCount := 0
    local fetchCount, cbVariant, bufferBytes
    local childIndex, offsetBytes, variantType
    local childId, dispatchPointer, outputList := []
    local resultCode := 0
    local buf

    ; Start with an empty list so every failure path can return a safe, iterable value.

    if !IsObject(accObj)
        ; A missing MSAA object cannot report children.
        return outputList

    ; A child-reference wrapper stores its actual MSAA interface in its acc property.
    iaObj := Acc_IsChildRef(accObj) ? accObj.acc : accObj
    if !IsObject(iaObj)
        return outputList

    try
        ; accChildCount is the MSAA property that reports how many immediate children exist.
        childrenCount := iaObj.accChildCount
    catch
        return outputList

    if (childrenCount <= 0)
        return outputList

    ; Honor the caller's cap because third-party controls can report very large child counts.
    fetchCount := childrenCount
    if (maxChildren > 0 && fetchCount > maxChildren)
        fetchCount := maxChildren

    ; AccessibleChildren writes one VARIANT structure per child; its size differs by CPU bitness.
    cbVariant := (A_PtrSize = 8) ? 24 : 16
    bufferBytes := fetchCount * cbVariant
    ; Allocate zeroed raw memory for the VARIANT structures Windows will fill in.
    VarSetCapacity(buf, bufferBytes, 0)

    try
    {
        ; Ask the MSAA provider to write up to fetchCount immediate children into the buffer.
        resultCode := DllCall("oleacc\AccessibleChildren"
            , "Ptr", ComObjValue(iaObj)
            , "Int", 0
            , "Int", fetchCount
            , "Ptr", &buf
            , "Int*", fetchedCount
            , "Int")
    }
    catch
        return outputList

    if (resultCode != 0 || fetchedCount <= 0)
        ; A nonzero HRESULT or zero fetched count means no usable child records were returned.
        return outputList

    ; Pre-size the AutoHotkey array to avoid repeatedly growing it while decoding child records.
    outputList.Capacity := fetchedCount

    Loop, %fetchedCount%
    {
        childIndex := A_Index - 1
        offsetBytes := childIndex * cbVariant
        ; Each VARIANT begins with a type code that tells us how to interpret its payload.
        variantType := NumGet(buf, offsetBytes + 0, "UShort")

        if (variantType = 9) ; VT_DISPATCH
        {
            ; VT_DISPATCH contains a COM pointer to a child with its own MSAA object.
            dispatchPointer := NumGet(buf, offsetBytes + 8, "Ptr")
            if (dispatchPointer)
                outputList.Push(ComObjEnwrap(9, dispatchPointer, 1))
        }
        else if (variantType = 3) ; VT_I4
        {
            ; VT_I4 contains a numeric child ID that must keep using the parent's MSAA object.
            childId := NumGet(buf, offsetBytes + 8, "Int")
            outputList.Push(Acc_CreateChildRef(iaObj, childId))
        }
    }

    return outputList
}

; Return a focused MSAA child when the provider exposes one.
Acc_GetFocusedObject() {
    ; These negative IDs ask MSAA for the text caret and the window's main client content.
    static OBJID_CARET  := 0xFFFFFFF8
    static OBJID_CLIENT := 0xFFFFFFFC

    ; Obtain the native handle of the foreground window before asking MSAA about it.
    WinGet, hWnd, ID, A
    if !hWnd
        return ""

    ; Prefer the caret object because it identifies the control that is currently accepting text.
    if (Acc_FromWindow(hWnd, OBJID_CARET, acc))
        return acc

    ; Fall back to the window's client object when no separate caret object is available.
    if (Acc_FromWindow(hWnd, OBJID_CLIENT, acc))
        return acc

    return ""
}

; Return the accessibility object under a screen point, with a native hit-test
; fallback for providers that do not answer Acc_ObjectFromPoint directly.
Acc_GetObjectAtScreenPoint(xPos, yPos) {
    local accObj, pointStruct, hwndUnder, accRoot, hitVal, childId, childObj

    ; First use MSAA's direct screen-coordinate lookup, which is the fastest path when supported.
    accObj := Acc_ObjectFromPoint(, xPos, yPos)
    if IsObject(accObj)
        return accObj

    ; Some providers reject the direct lookup, so identify the native host and
    ; ask its accessibility root to hit-test the same screen coordinates.
    VarSetCapacity(pointStruct, 8, 0)
    ; Store the screen X coordinate in POINT.x so WindowFromPoint can hit-test this location.
    NumPut(xPos, pointStruct, 0, "Int")
    ; Store the screen Y coordinate in POINT.y so WindowFromPoint can hit-test this location.
    NumPut(yPos, pointStruct, 4, "Int")

    ; Ask Windows which native window contains these screen coordinates.
    hwndUnder := DllCall("user32\WindowFromPoint", "Ptr", &pointStruct, "Ptr")
    if (!hwndUnder)
        return ""

    ; Obtain that window's top-level MSAA object before asking it to perform the hit test.
    accRoot := Acc_ObjectFromWindow(hwndUnder)
    if !IsObject(accRoot)
        return ""

    ; Keep the result separate because accHitTest can return two different kinds of values.
    hitVal := ""

    ; accHitTest may return either an accessibility object or a numeric child ID.
    try
        hitVal := accRoot.accHitTest(xPos, yPos)
    catch
        return ""

    if IsObject(hitVal)
        return hitVal

    if (hitVal = "" || hitVal = 0 || hitVal = "0")
        ; An empty or zero result does not identify a child control.
        return ""

    ; Convert the provider's numeric result into the child ID used by accChild.
    childId := hitVal + 0
    if (childId = 0 && hitVal != 0 && hitVal != "0")
        return ""

    ; Request the child object when the provider gave an ID instead of an object directly.
    try
        childObj := accRoot.accChild(childId)
    catch
        childObj := ""

    if IsObject(childObj)
        return childObj

    return Acc_CreateChildRef(accRoot, childId)
}

; Cache and return the readable MSAA role text for a numeric role identifier.
Acc_GetRoleText(nRole) {
    ; Keep prior translations because Windows role IDs repeat frequently during tree searches.
    static c_role := {}
    local textSize, roleText

    if (c_role.HasKey(nRole))
        ; Return the saved readable name instead of calling Windows again.
        return c_role[nRole]

    ; First ask Windows how many characters are needed for this role's localized text.
    textSize := DllCall("oleacc\GetRoleText", "UInt", nRole, "Ptr", 0, "UInt", 0)
    ; Reserve a string buffer large enough for that text and its terminating null character.
    VarSetCapacity(roleText, (A_IsUnicode ? 2 : 1) * (textSize + 1), 0)
    ; Ask Windows to copy the localized role name into the allocated buffer.
    DllCall("oleacc\GetRoleText", "UInt", nRole, "Str", roleText, "UInt", textSize + 1)

    ; Save the translated text so the next request for this numeric role can return immediately.
    c_role[nRole] := roleText
    return roleText
}

; Read visible Explorer address-bar text from a toolbar accessibility object.
Acc_GetToolbarAddressPath(tbHwnd) {
    ; Obtain the toolbar's MSAA root before searching its descendant controls for path text.
    acc := Acc_ObjectFromWindow(tbHwnd)
    if !IsObject(acc)
        return ""

    ; Limit the traversal to 140 controls so an unusual toolbar cannot delay the caller.
    return Acc_FindLikelyPathText(acc, 140)
}

; ============================================================================
; Library-owned classic accessibility dependencies
; ============================================================================

; Load oleacc.dll once so the library can call Microsoft Active Accessibility APIs.
Acc_Init() {
    global Acc_ModuleHandle

    if (Acc_ModuleHandle)
        ; A nonzero module handle means the MSAA functions are already available.
        return true

    ; Load the Windows library that implements the classic Microsoft Active Accessibility APIs.
    Acc_ModuleHandle := DllCall("kernel32\LoadLibrary", "Str", "oleacc.dll", "Ptr")
    return (Acc_ModuleHandle != 0)
}

; Identify the MSAA child-reference wrapper returned by Acc_CreateChildRef().
Acc_IsChildRef(accObj) {
    ; The marker identifies the wrapper used when MSAA returned only a child ID, not an object.
    return IsObject(accObj) && ObjHasKey(accObj, "__accChildRef") && (accObj.__accChildRef = true)
}

; Read an MSAA target rectangle without allowing a provider exception to escape.
Acc_LocationSafe(accObj, ByRef xPos, ByRef yPos, ByRef wid, ByRef hei, childId := "") {
    local iaObj, childVal, childNum

    ; Clear every output first so a failed provider call cannot leave stale screen coordinates.
    xPos := ""
    yPos := ""
    wid  := ""
    hei  := ""

    if !IsObject(accObj)
        return false

    if (Acc_IsChildRef(accObj)) {
        ; Use the saved parent interface and child ID for a wrapper returned by Acc_CreateChildRef.
        iaObj := accObj.acc
        childVal := accObj.child
    }
    else {
        ; A direct MSAA object addresses itself with child ID zero unless the caller supplied one.
        iaObj := accObj
        childVal := (childId = "") ? 0 : childId
    }

    ; Reject a nonnumeric child value rather than passing an invalid identifier to the COM method.
    childNum := childVal + 0
    if (childNum = 0 && childVal != 0 && childVal != "0")
        return false

    try {
        ; accLocation asks MSAA for the control's screen-relative left, top, width, and height.
        iaObj.accLocation(xPos, yPos, wid, hei, ComObjParameter(3, childNum))
        return true
    } catch {
        ; Clear partial output because inaccessible or stale controls can throw while reporting bounds.
        xPos := ""
        yPos := ""
        wid := ""
        hei := ""
        return false
    }
}

; Recognize strings that represent file-system or shell path text.
Acc_LooksLikePath(s) {
    ; Reject blank values and Explorer's generic label before checking for actual path separators.
    if (s = "" || s = "Address Band")
        return false

    ; A drive letter followed by a backslash identifies a local Windows path such as C:\Folder.
    if InStr(s, ":\")
        return true

    ; Two leading backslashes identify a network path such as \\server\share.
    if InStr(s, "\\")
        return true

    ; Treat remaining backslash-separated breadcrumbs as paths unless they are known UI labels.
    if (InStr(s, "\") && !InStr(s, "Address Band") && !InStr(s, "Toolbar") && !InStr(s, "Ribbon"))
        return true

    return false
}

; Identify known file-dialog column names through safe MSAA name access.
Acc_NameIsKnownColumnSafe(accObj) {
    ; List labels used by common Windows file dialogs for their details-view columns.
    static knownNames := { "Name": true
                        , "Date modified": true
                        , "Type": true
                        , "Size": true
                        , "Date created": true
                        , "Authors": true
                        , "Title": true }

    local nameStr

    ; Do not query MSAA when no accessibility object was supplied.
    if !IsObject(accObj)
        return 0

    ; Read the accessible label through the exception-safe helper.
    nameStr := Acc_NameSafe(accObj)
    if (nameStr = "")
        return 0

    ; The lookup table returns true only for recognized column-header labels.
    return knownNames.HasKey(nameStr)
}

; Read an MSAA name while converting provider errors to an empty value.
Acc_NameSafe(accObj) {
    local iaObj, childId, nameStr := ""

    ; Resolve either a full MSAA object or a child-reference wrapper before reading its name.

    if !Acc_ResolveTarget(accObj, iaObj, childId)
        return ""

    try
        ; accName is the MSAA property commonly used for a control's visible label.
        nameStr := iaObj.accName(childId)
    catch
        return ""

    return nameStr
}

; Resolve the MSAA object under a screen point and preserve its child identifier.
Acc_ObjectFromPoint(ByRef childIdOut := "", xPos := "", yPos := "") {
    local pointStruct, xVal, yVal, pt64, hr, pacc := 0, vt
    local varChild

    ; Hold the raw COM pointer returned by Windows until it is wrapped as an AutoHotkey object.

    ; Ensure the MSAA DLL is loaded before calling one of its exported functions.
    Acc_Init()

    ; Reserve a VARIANT buffer because Windows returns the hit child as a typed native value.
    VarSetCapacity(varChild, (A_PtrSize = 8) ? 24 : 16, 0)

    if (xPos = "" || yPos = "") {
        ; Allocate the native POINT structure used by GetCursorPos when no point was supplied.
        VarSetCapacity(pointStruct, 8, 0)
        ; Read the current mouse position in screen coordinates from Windows.
        if !DllCall("user32\GetCursorPos", "Ptr", &pointStruct)
        {
            childIdOut := 0
            return
        }
        ; Decode the two 32-bit coordinates that Windows stored in the POINT structure.
        xVal := NumGet(pointStruct, 0, "Int")
        yVal := NumGet(pointStruct, 4, "Int")
    }
    else {
        ; Convert explicit AutoHotkey values to integers for the native accessibility API.
        xVal := xPos + 0
        yVal := yPos + 0
    }

    ; Pack POINT into 64-bit because AccessibleObjectFromPoint accepts both coordinates together.
    pt64 := (xVal & 0xFFFFFFFF) | ((yVal & 0xFFFFFFFF) << 32)

    ; Ask MSAA for the accessibility object and child located at the selected screen point.
    hr := DllCall("oleacc\AccessibleObjectFromPoint" , "Int64", pt64 , "Ptr*", pacc , "Ptr", &varChild , "Int")

    if (hr != 0 || !pacc) {
        ; A nonzero HRESULT or missing pointer means MSAA could not identify a target there.
        childIdOut := 0
        return
    }

    ; Read the VARIANT type to determine whether the returned child payload is a numeric ID.
    vt := NumGet(varChild, 0, "UShort")
    childIdOut := (vt = 3) ? NumGet(varChild, 8, "Int") : 0

    try
        ; Wrap the raw IAccessible COM pointer so callers can use MSAA properties safely.
        return ComObjEnwrap(9, pacc, 1)
    catch {
        childIdOut := 0
        return
    }
}

; Resolve an MSAA root object for a window handle.
Acc_ObjectFromWindow(hWnd, idObject := 0xFFFFFFFC) {
    ; Start with a blank result so callers receive an empty string if Windows cannot supply MSAA.
    local accObj := ""

    ; Ensure the classic accessibility library is ready before resolving the window handle.
    Acc_Init()

    ; Reuse Acc_FromWindow because it converts the native COM pointer into an AutoHotkey object.
    if (Acc_FromWindow(hWnd, idObject, accObj))
        return accObj

    return ""
}

; Read an MSAA parent while converting provider errors to an empty value.
Acc_ParentSafe(accObj) {
    ; Initialize an empty result for missing objects and providers that reject the parent request.
    local parentObj := ""

    if !IsObject(accObj)
        return ""

    if (Acc_IsChildRef(accObj))
        ; A numeric child has the saved parent object as its immediate MSAA parent.
        return accObj.acc

    try
        ; accParent is the MSAA property that points to the containing accessible control.
        parentObj := accObj.accParent
    catch
        return ""

    return parentObj
}

; Return whether a screen point lies inside an accessibility object's visible
; screen rectangle; fail closed if the provider cannot report one.
Acc_PointInAccRect(accObj, sx, sy) {
    local ax, ay, aw, ah

    if (!Acc_LocationSafe(accObj, ax, ay, aw, ah))
        return false

    ; Ignore controls with no visible area because they cannot contain a screen point.
    if (aw <= 0 || ah <= 0)
        return false

    ; A missing or empty rectangle cannot establish that the point is inside.
    return (sx >= ax && sx < ax + aw && sy >= ay && sy < ay + ah)
}

; Resolve an MSAA object or child-reference wrapper into object and child values.
Acc_ResolveTarget(accObj, ByRef iaObj, ByRef childId) {
    ; Reject an absent target before attempting to read MSAA properties from it.
    if !IsObject(accObj)
        return false

    if (Acc_IsChildRef(accObj)) {
        ; Unwrap the parent interface and child ID that together describe this virtual MSAA child.
        iaObj := accObj.acc
        childId := accObj.child
        return true
    }

    ; A direct MSAA object uses child ID zero to mean the object itself.
    iaObj := accObj
    childId := 0
    return true
}

; Read an MSAA role identifier while converting provider errors to zero.
Acc_RoleIdSafe(accObj) {
    ; Store the MSAA role value before validating that it can be interpreted as a numeric ID.
    local iaObj, childId, roleVal := "", roleNum

    if !Acc_ResolveTarget(accObj, iaObj, childId)
        return 0

    try
        ; accRole reports the semantic control type, such as button, text, or column header.
        roleVal := iaObj.accRole(childId)
    catch
        return 0

    ; Convert the provider's return value while rejecting text that is not a valid role number.
    roleNum := roleVal + 0
    if (roleNum = 0 && roleVal != 0 && roleVal != "0")
        return 0

    return roleNum
}

; Return a readable MSAA role name only when the target can be resolved safely.
Acc_RoleNameSafe(accObj) {
    local iaObj, childId, roleValue := "", roleNumber

    if !Acc_ResolveTarget(accObj, iaObj, childId)
        return ""

    try
        ; Read the numeric MSAA role before converting it to localized human-readable text.
        roleValue := iaObj.accRole(childId)
    catch
        return ""

    ; Convert the provider value only when it represents a valid numeric role identifier.
    roleNumber := roleValue + 0
    if (roleNumber = 0 && roleValue != 0 && roleValue != "0")
        return ""

    ; Translate the numeric MSAA role through Windows' localized role-name table.
    return Acc_GetRoleText(roleNumber)
}

; Release the library-owned oleacc.dll reference after no shutdown code can use MSAA.
Acc_Shutdown() {
    global Acc_ModuleHandle

    if (!Acc_ModuleHandle)
        return true

    ; Release only the module reference acquired by Acc_Init() during this script process.
    if !DllCall("kernel32\FreeLibrary", "Ptr", Acc_ModuleHandle, "Int")
        return false

    Acc_ModuleHandle := 0
    return true
}

; Query an object for IAccessible while converting unsupported-provider failures
; into a zero result instead of allowing an exception to escape.
Acc_TryGetIAccessibleSafe(accObj) {
    local iAccessiblePtr := 0

    if !IsObject(accObj)
        return 0

    try {
        ; Query the COM object for IAccessible when the provider exposes more than one interface.
        iAccessiblePtr := ComObjQuery(accObj, "{618736E0-3C3D-11CF-810C-00AA00389B71}")
        if !iAccessiblePtr
            return 0

        ; Wrap the returned COM pointer so AutoHotkey releases it correctly after use.
        return ComObjEnwrap(9, iAccessiblePtr, 1)
    }
    catch {
        return 0
    }
}

; Read an MSAA value while converting provider errors to an empty value.
Acc_ValueSafe(accObj) {
    ; Start blank because many controls do not expose a separate accessible value.
    local iaObj, childId, valueStr := ""

    if !Acc_ResolveTarget(accObj, iaObj, childId)
        return ""

    try
        ; accValue usually contains editable text, such as the contents of an address field.
        valueStr := iaObj.accValue(childId)
    catch
        return ""

    return valueStr
}

; Return an MSAA object owner window without propagating provider errors.
Acc_WindowFromObjectSafe(accObj) {
    local iaObj, hwnd, hr

    ; A missing object cannot be associated with a native Windows handle.
    if !IsObject(accObj)
        return 0

    ; Begin with the supplied MSAA object and unwrap a child reference when necessary.
    iaObj := accObj

    if (Acc_IsChildRef(accObj))
        iaObj := accObj.acc

    ; Initialize native outputs so a failed accessibility call cannot return a stale handle.
    hwnd := 0
    hr := 0

    try
    {
        ; Ask Windows which native window owns this accessible COM object.
        hr := DllCall("oleacc\WindowFromAccessibleObject" , "Ptr", ComObjValue(iaObj) , "Ptr*", hwnd , "Int")
    }
    catch
        return 0

    if (hr != 0)
        ; A nonzero HRESULT means Windows could not map this accessible object to a window.
        return 0

    return hwnd
}

; Limit an overlay alpha value to the valid 0 through 255 range.
ClampAlpha(alphaValue) {
    if (alphaValue < 0)
        return 0
    if (alphaValue > 255)
        return 255

    return alphaValue
}

; Show the MSAA role ancestry beneath the mouse for manual diagnostics.
DebugRolesUnderMouse() {
    local acc, childId, cur, fn_DebugRolesUnderMouse_mx, fn_DebugRolesUnderMouse_my
    local out, parent, role

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

   for item in shellFolderView.SelectedItems
      result .= (result = "" ? "" : "`n") . item.Path
   Return result
}

; Return the second eligible window on a display, or the first one after ref_hwndID.
FindSecondMostWindow(ref_hwndID := "", displayNumber := 0) {
    local firstFound, fn_FindSecondMostWindow_currentMonHasActWin, fn_FindSecondMostWindow_hwndID
    local mmState, monitorCount, targetID, winList

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
    local alphaOther, opacityOther, remainingOther, remainingPrimary255, requiredBackground255

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

; Return a window class name through GetClassNameW.
GetClassName(hwnd) {
    VarSetCapacity(className, 256 * 2, 0)

    len := DllCall("user32\GetClassNameW" , "Ptr", hwnd , "Ptr", &className , "Int", 256 , "Int")

    if (!len)
        return ""

    return StrGet(&className, len, "UTF-16")
}

; Return the cached display number for the monitor containing the mouse.
GetCurrentDisplayNumber(){
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my

    monitorInfo := _GetMonitorRecordForPoint(mx, my)
    return IsObject(monitorInfo) ? monitorInfo.displayNumber : 0
}

; Return the monitor count captured during script startup.
GetMonitorCount() {
    global g_MonitorCount

    return g_MonitorCount
}

; Choose the monitor containing the mouse. If none contains it (rare with odd layouts),
; pick the nearest monitor by distance.
; Summary
; First preference: the monitor that actually contains the mouse.
; Else: the nearest monitor rectangle (useful if the mouse is exactly outside due to odd DPI layouts, mis-alignment, or negative coords).
; The function returns the rectangle by reference into L, T, R, B.
; So in your drag script, every frame we call this with the current mouse (mx, my), and get the correct monitor bounds whether your monitors
; are side-by-side, stacked vertically, diagonal, or even negative-coordinate setups.

; (rLeft, rTop) ----------------- (rRight, rTop)
       ; |                        |
       ; |                        |
       ; |        Monitor         |
       ; |                        |
; (rLeft, rBottom) ------------- (rRight, rBottom)

GetMonitorRectForMouse(mx, my, useWorkArea, ByRef L, ByRef T, ByRef R, ByRef B) {
    ; Select by full monitor bounds so a cursor over a taskbar still maps to
    ; that monitor before the caller requests its smaller work area.
    monitorInfo := _GetMonitorRecordForPoint(mx, my, false, true)
    if (!IsObject(monitorInfo)) {
        B := 0
        L := 0
        R := 0
        T := 0
        return 0
    }

    rectangle := useWorkArea ? monitorInfo.workArea : monitorInfo.fullArea
    B := rectangle.bottom
    L := rectangle.left
    R := rectangle.right
    T := rectangle.top
    return monitorInfo.displayNumber
}

; Return the cached display number for the monitor containing the mouse.
GetMouseDisplayNumber(buffer := 0)
{
    global currMonHeight, currMonWidth, g_MonitorsByDisplayNumber

    Coordmode, Mouse, Screen
    MouseGetPos, mouseX, mouseY

    for displayNumber, monitorInfo in g_MonitorsByDisplayNumber {
        fullArea := monitorInfo.fullArea
        If ( mouseX >= (fullArea.left + buffer) ) && ( mouseX < (fullArea.right - buffer) ) && ( mouseY >= (fullArea.top + buffer) ) && ( mouseY < (fullArea.bottom - buffer) )
        {
            currMonHeight := fullArea.height
            currMonWidth  := fullArea.width
            return displayNumber
        }
    }

    return 0
}

; Return the cached display number for a window's current or restored monitor.
GetWindowDisplayNumber(windowHwnd) {
    global g_MonitorsByDisplayNumber
    static monitorDefaultToNearest := 2  ; MONITOR_DEFAULTTONEAREST
    static windowPlacementSize := 44
    static swShowMinimized := 2

    if !windowHwnd
        return 0

    VarSetCapacity(windowPlacement, windowPlacementSize, 0)
    ; Set WINDOWPLACEMENT.length so GetWindowPlacement accepts the caller-provided structure.
    NumPut(windowPlacementSize, windowPlacement, 0, "UInt")

    if !DllCall("GetWindowPlacement", "Ptr", windowHwnd, "Ptr", &windowPlacement)
        return 0

    showCmd := NumGet(windowPlacement, 8, "UInt")

    VarSetCapacity(targetRect, 16, 0)

    if (showCmd = swShowMinimized) {
        ; Use restored position for minimized windows.
        windowLeft   := NumGet(windowPlacement, 28, "Int")
        windowTop    := NumGet(windowPlacement, 32, "Int")
        windowRight  := NumGet(windowPlacement, 36, "Int")
        windowBottom := NumGet(windowPlacement, 40, "Int")

        ; Store the restored window's left edge in RECT.left for the caller's target bounds.
        NumPut(windowLeft,   targetRect, 0,  "Int")
        ; Store the restored window's top edge in RECT.top for the caller's target bounds.
        NumPut(windowTop,    targetRect, 4,  "Int")
        ; Store the restored window's right edge in RECT.right for the caller's target bounds.
        NumPut(windowRight,  targetRect, 8,  "Int")
        ; Store the restored window's bottom edge in RECT.bottom for the caller's target bounds.
        NumPut(windowBottom, targetRect, 12, "Int")
    } else {
        ; Use actual current rect for normal/maximized windows.
        if !DllCall("GetWindowRect", "Ptr", windowHwnd, "Ptr", &targetRect)
            return 0
    }

    targetMonitorHandle := DllCall("MonitorFromRect", "Ptr", &targetRect, "UInt", monitorDefaultToNearest, "Ptr")
    if !targetMonitorHandle
        return 0

    for displayNumber, monitorInfo in g_MonitorsByDisplayNumber {
        if (monitorInfo.monitorHandle = targetMonitorHandle)
            return displayNumber
    }

    return 0
}

; Load VirtualDesktopAccessor and cache its exports before virtual-desktop lookups.
InitVDA()
{
    global hVirtualDesktopAccessor, k_dllPath
    global GetDesktopCountProc, GetCurrentDesktopNumberProc
    global IsWindowOnCurrentVirtualDesktopProc, IsWindowOnDesktopNumberProc, MoveWindowToDesktopNumberProc
    global IsPinnedWindowProc, GetDesktopNameProc, SetDesktopNameProc
    global CreateDesktopProc, RemoveDesktopProc

    static initializing := false
    if (initializing)
        return false

    ; already initialized (core proc exists)
    if (IsWindowOnDesktopNumberProc)
        return true

    initializing := true

    if !FileExist(k_dllPath)
    {
        initializing := false
        MsgBox % "VDA DLL missing:`n" k_dllPath
        return false
    }

    if (!hVirtualDesktopAccessor)
    {
        hVirtualDesktopAccessor := DllCall("LoadLibrary", "Str", k_dllPath, "Ptr")
        if (!hVirtualDesktopAccessor)
        {
            initializing := false
            MsgBox % "LoadLibrary failed:`n" k_dllPath "`nA_LastError=" A_LastError
            return false
        }
    }

    ; --- core exports (require these) ---
    GetDesktopCountProc                 := _gp("GetDesktopCount")
    GetCurrentDesktopNumberProc         := _gp("GetCurrentDesktopNumber")
    IsWindowOnCurrentVirtualDesktopProc := _gp("IsWindowOnCurrentVirtualDesktop")
    IsWindowOnDesktopNumberProc         := _gp("IsWindowOnDesktopNumber")
    MoveWindowToDesktopNumberProc       := _gp("MoveWindowToDesktopNumber")
    IsPinnedWindowProc                  := _gp("IsPinnedWindow")

    ; --- optional exports (may be missing detbc on build/OS) ---
    GetDesktopNameProc                  := _gp("GetDesktopName")
    SetDesktopNameProc                  := _gp("SetDesktopName")
    CreateDesktopProc                   := _gp("CreateDesktop")
    RemoveDesktopProc                   := _gp("RemoveDesktop")

    initializing := false

    ; only require "core" to succeed
    if !(GetDesktopCountProc
      && GetCurrentDesktopNumberProc
      && IsWindowOnCurrentVirtualDesktopProc
      && IsWindowOnDesktopNumberProc
      && MoveWindowToDesktopNumberProc
      && IsPinnedWindowProc)
    {
        MsgBox % "InitVDA: missing required export(s).`n" . "Check DLL path/bitness/version.`n" . "A_PtrSize=" A_PtrSize
        return false
    }

    return true
}

; Decide whether this script will treat a window as an independent Alt+Tab candidate.
;
; hWnd is a window handle: the numeric ID Windows uses to identify one window.
; The Boolean return value is the decision.  The ByRef "why" parameter is also
; filled with the rule that accepted or rejected the window for diagnostics.
;
; This function calls Win32 APIs directly through DllCall.  A parent describes
; where a window sits in the window hierarchy; an owner describes which top-level
; window an auxiliary or pop-up window belongs to.  Those are separate relationships.
IsAltTabWindow(hWnd, ByRef why := "") {
    ; WS_EX_* constants are bits in a window's "extended style" number.  The
    ; script tests individual bits to learn how Windows expects the window to act.
    ; APPWINDOW forces a visible top-level window onto the taskbar.  This function
    ; additionally chooses to treat that style as a strong Alt+Tab signal.
    static WS_EX_APPWINDOW       := 0x40000
    ; TOOLWINDOW identifies an auxiliary palette/tool window normally omitted
    ; from Alt+Tab.
    static WS_EX_TOOLWINDOW      := 0x80
    ; DWM "cloaking" keeps a window object alive while the desktop compositor
    ; deliberately hides its visual surface.  Attribute 14 reports that state.
    static DWMWA_CLOAKED         := 14
    ; A cloaking value of 2 means the Windows shell hid the window.
    static DWM_CLOAKED_SHELL     := 2
    ; NOACTIVATE means clicking the window does not make it the foreground window;
    ; code can still activate it explicitly through other Windows APIs.
    static WS_EX_NOACTIVATE      := 0x8000000
    ; GetAncestor(..., GA_PARENT) asks for the immediate parent window.
    static GA_PARENT             := 1
    ; GetWindow(..., GW_OWNER) asks for the owner of a top-level/pop-up window.
    static GW_OWNER              := 4
    ; Retained monitor-API constant: return no monitor when there is no match.
    ; No call in this function currently uses it.
    static MONITOR_DEFAULTTONULL := 0
    ; Cache whether this Windows build meets the script's threshold for attempting
    ; virtual-desktop filtering.  The helper can still be unavailable and fail open.
    static VirtualDesktopExist := ""
    ; RegisterCallback exposes the AHK PropEnumProcEx function as a function
    ; pointer that the Windows EnumPropsEx API can call.
    static PropEnumProcEx        := RegisterCallback("PropEnumProcEx", "Fast", 4)
    ; WINDOWEDGE requests a raised border around the window.
    static WS_EX_WINDOWEDGE      := 0x100
    ; CONTROLPARENT marks a container that participates in dialog navigation.
    static WS_EX_CONTROLPARENT   := 0x10000
    ; DLGMODALFRAME requests a dialog-style frame.  Its test remains disabled
    ; later in this function, matching the existing selection policy.
    static WS_EX_DLGMODALFRAME   := 0x00000001

    ; Clear the caller's previous diagnostic before evaluating this window.
    why := ""

    ; Read the window's visible caption and registered class name.  A class name
    ; identifies the Windows UI implementation, not the application executable.
    WinGetTitle, hasTitle, ahk_id %hWnd%
    WinGetClass, winClass, ahk_id %hWnd%

    ; Normalize a Windows Terminal/Cascadia handle to the root top-level window.
    ; GetAncestor(..., GA_ROOT=2) walks upward until there is no higher parent,
    ; after which the class and title must be reread for the replacement handle.
    if (winClass = "CASCADIA_HOSTING_WINDOW_CLASS") {
        hWnd := DllCall("GetAncestor", "uptr", hWnd, "uint", 2, "ptr")
        WinGetClass, winClass, ahk_id %hWnd%
        WinGetTitle, hasTitle, ahk_id %hWnd%
        why := "CASCADIA content -> host via GA_ROOT"
    }

    ; This script requires a caption before accepting a normal candidate; Windows
    ; itself does not impose that rule.  Cascadia is the explicit class exception.
    if (!hasTitle && winClass != "CASCADIA_HOSTING_WINDOW_CLASS") {
        why := "no title (class=" . winClass . ")"
        return False
    }

    ; Build 14393 is this script's threshold for attempting the virtual-desktop
    ; check below.  Store that decision once instead of parsing A_OSVersion each call.
    if (VirtualDesktopExist = "") {
        OSbuildNumber := StrSplit(A_OSVersion, ".")[3]
        if (OSbuildNumber < 14393)
            VirtualDesktopExist := 0
        else
            VirtualDesktopExist := 1
    }

    ; IsWindowVisible can be false for a minimized window.  IsIconic separately
    ; reports minimization, so a minimized application is not rejected merely
    ; because its normal on-screen surface is hidden.
    isMinimized := DllCall("IsIconic", "uptr", hWnd)

    if (!DllCall("IsWindowVisible", "uptr", hWnd) && !isMinimized) {
        why := "not visible and not minimized"
        return False
    }

    ; Ask Desktop Window Manager whether the shell has cloaked this window.
    ; "uint*" supplies a four-byte output variable that the API writes into.
    cloaked := 0
    DllCall("DwmApi\DwmGetWindowAttribute", "uptr", hWnd, "uint", DWMWA_CLOAKED, "uint*", cloaked, "uint", 4)
    if (cloaked = DWM_CLOAKED_SHELL) {
        why := "cloaked shell"
        return False
    }

    ; Alt+Tab candidates are top-level windows.  A top-level window's immediate
    ; parent is the desktop window; a child control instead has another window
    ; as its parent.  realHwnd() converts both handles to the same unsigned
    ; 32-bit representation before comparison.
    if (realHwnd(DllCall("GetAncestor", "uptr", hWnd, "uint", GA_PARENT, "ptr")) != realHwnd(DllCall("GetDesktopWindow", "ptr"))) {
        why := "parent not desktop"
        return False
    }

    ; Reject classes explicitly excluded by this script.  Shell*TrayWnd, ProgMan,
    ; and WorkerW are shell desktop/taskbar infrastructure.  CoreWindow can also
    ; belong to a modern application, but this selection policy still excludes it.
    if (   winClass = "Windows.UI.Core.CoreWindow"
        || (InStr(winClass, "Shell", False) && InStr(winClass, "TrayWnd", False))
        || winClass == "ProgMan"
        || winClass == "WorkerW") {

        why := "blocked class=" . winClass
        return False
    }

    ; ApplicationFrameWindow is the legacy host used by some packaged apps.
    ; EnumPropsEx asks Windows to enumerate that window's named properties;
    ; PropEnumProcEx records ApplicationViewCloakType in this four-byte buffer.
    if (winClass = "ApplicationFrameWindow") {
        VarSetCapacity(ApplicationViewCloakType, 4, 0)
        DllCall("EnumPropsEx", "uptr", hWnd, "ptr", PropEnumProcEx, "ptr", &ApplicationViewCloakType)
        ; ApplicationViewCloakType is an internal window-property convention, not
        ; a general Win32 eligibility guarantee.  This script interprets value 1
        ; as a reason to exclude the frame even if visibility checks passed.
        if (NumGet(ApplicationViewCloakType, 0, "int") = 1) {
            why := "ApplicationFrameWindow cloaked (ApplicationViewCloakType=1)"
            return False
        }
    }

    ; Retrieve all extended-style bits once for the remaining bit-mask tests.
    WinGet, exStyles, ExStyle, ahk_id %hWnd%

    ; WS_EX_APPWINDOW forces a visible top-level window onto the taskbar.  This
    ; script also accepts it as an Alt+Tab signal, subject to the checks below.
    if (exStyles & WS_EX_APPWINDOW) {
        ; ITaskList_Deleted is an internal named-property convention rather than
        ; a documented Win32 guarantee.  When present, this script treats the
        ; window as removed from the task list, overriding APPWINDOW.
        if DllCall("GetProp", "uptr", hWnd, "str", "ITaskList_Deleted", "ptr") {
            why := "WS_EX_APPWINDOW but ITaskList_Deleted"
            return False
        }

        ; Below the configured OS-build threshold, this script does not attempt
        ; virtual-desktop filtering, so APPWINDOW is sufficient here.
        if (VirtualDesktopExist = 0) {
            why := "passes via WS_EX_APPWINDOW (desktop filtering not attempted on this OS build)"
            return True
        }

        ; The helper returns true when the window is on the current desktop, but
        ; deliberately also returns true when its VDA DLL/function is unavailable.
        ; That fail-open behavior prevents an unavailable helper from hiding windows.
        if IsWindowOnCurrentVirtualDesktop(hWnd) {
            why := "passes via WS_EX_APPWINDOW (desktop check passed or VDA unavailable)"
            return True
        }

        why := "WS_EX_APPWINDOW but not on current virtual desktop"
        return False
    }

    ; Without APPWINDOW's explicit override, tool and non-activating windows are
    ; auxiliary UI and are rejected before the more general tests below.
    if (exStyles & WS_EX_TOOLWINDOW) {
        why := "toolwindow"
        return False
    }

    if (exStyles & WS_EX_NOACTIVATE) {
        why := "noactivate"
        return False
    }

    ; A modal-frame style alone intentionally does not decide eligibility.
    ; This disabled condition is retained to document that policy choice.
    ; if (exStyles & WS_EX_DLGMODALFRAME)
    ;     ...

    ; The existing policy accepts ordinary bordered windows and dialog-control
    ; containers directly.  The bitwise OR forms one mask containing either flag.
    if (exStyles & (WS_EX_WINDOWEDGE | WS_EX_CONTROLPARENT)) {
        why := "passes: WS_EX_WINDOWEDGE/WS_EX_CONTROLPARENT"
        return True
    }

    ; No style made the decision, so follow the ownership chain.  Ownership is
    ; common for dialogs and pop-ups: it links them to a top-level window without
    ; making them child controls.  GetWindow(..., GW_OWNER) returns 0 at the end.
    Loop
    {
        ; Preserve the current candidate because hWnd is about to be replaced by
        ; its owner.  The final candidate is what the task-list and desktop tests use.
        hWndPrev := hWnd
        hWnd := DllCall("GetWindow", "uptr", hWnd, "uint", GW_OWNER, "ptr")

        ; Reaching owner 0 means hWndPrev is the root of this ownership chain.
        if (!hWnd) {
            ; If the ownership root has the internal ITaskList_Deleted property,
            ; this script excludes the candidate represented by that chain.
            if DllCall("GetProp", "uptr", hWndPrev, "str", "ITaskList_Deleted", "ptr") {
                why := "owner-walk end: ITaskList_Deleted on " . hWndPrev
                return False
            }

            ; Apply the same build threshold and fail-open VDA policy used by the
            ; APPWINDOW path, but to the last real window in the ownership chain.
            if (VirtualDesktopExist = 0) {
                why := "owner-walk end: passes (desktop filtering not attempted on this OS build) prev=" . hWndPrev
                return True
            }

            if IsWindowOnCurrentVirtualDesktop(hWndPrev) {
                why := "owner-walk end: passes (desktop check passed or VDA unavailable) prev=" . hWndPrev
                return True
            }

            why := "owner-walk end: not on current virtual desktop prev=" . hWndPrev
            return False
        }

        ; A visible owner represents this owned window in Alt+Tab, so do not add
        ; a second independent entry for the owned window.  Unlike the candidate
        ; visibility test above, this deliberately does not exempt minimized owners.
        if DllCall("IsWindowVisible", "uptr", hWnd) {
            why := "fails: visible owner=" . hWnd
            return False
        }

        ; Read each owner's styles as the walk proceeds.  A hidden tool/noactivate
        ; owner disqualifies the chain unless APPWINDOW explicitly overrides it.
        WinGet, exStyles, ExStyle, ahk_id %hWnd%
        if ((exStyles & WS_EX_TOOLWINDOW) or (exStyles & WS_EX_NOACTIVATE)) and !(exStyles & WS_EX_APPWINDOW) {
            why := "fails: owner is toolwindow/noactivate (owner=" . hWnd . ")"
            return False
        }
    }
}

; Return whether a window has the layered extended style used by this script.
IsAlwaysOnTop(hwndID) {
    WinGet, ExStyle, ExStyle, ahk_id %hwndID% ; 0x8 is WS_EX_LAYERED.
    If (ExStyle & 0x8)
        Return True
    Else
        Return False
}
;------------------------------------------------------------------------------

; Return whether a dialog button is visible, enabled, and push-button-like.
IsUsableDialogPushButton(h) {
    static GWL_STYLE         := -16
    static BS_PUSHBUTTON     := 0x00000000
    static BS_DEFPUSHBUTTON  := 0x00000001
    static BS_SPLITBUTTON    := 0x0000000C
    static BS_DEFSPLITBUTTON := 0x0000000D
    static BS_COMMANDLINK    := 0x0000000E
    static BS_DEFCOMMANDLINK := 0x0000000F
    static BS_TYPEMASK       := 0x0000000F

    if (!h)
        return false

    if (!DllCall("user32\IsWindow", "Ptr", h, "Int"))
        return false

    if (GetClassName(h) != "Button")
        return false

    if (!DllCall("user32\IsWindowVisible", "Ptr", h, "Int"))
        return false

    if (!DllCall("user32\IsWindowEnabled", "Ptr", h, "Int"))
        return false

    style := DllCall(A_PtrSize = 8 ? "user32\GetWindowLongPtrW" : "user32\GetWindowLongW"
        , "Ptr", h
        , "Int", GWL_STYLE
        , "Ptr")

    buttonType := style & BS_TYPEMASK

    ; Only accept push-like buttons.
    ; This avoids accidentally targeting checkboxes, radio buttons, or group boxes.
    return (buttonType = BS_PUSHBUTTON
         || buttonType = BS_DEFPUSHBUTTON
         || buttonType = BS_SPLITBUTTON
         || buttonType = BS_DEFSPLITBUTTON
         || buttonType = BS_COMMANDLINK
         || buttonType = BS_DEFCOMMANDLINK)
}

; Return whether a window belongs to the active virtual desktop.
IsWindowOnCurrentVirtualDesktop(hwnd) {
    global IsWindowOnCurrentVirtualDesktopProc

    ; Fail-open: if VDA is unavailable, don't incorrectly exclude windows
    if (!InitVDA() || !IsWindowOnCurrentVirtualDesktopProc)
        return true
    return DllCall(IsWindowOnCurrentVirtualDesktopProc, "Ptr", hwnd, "Int")
}

; Return true when a window is mostly inside the requested Windows display number.
IsWindowOnDisplayNumber(thisWindowHwnd, targetDisplayNumber := 0) {
    X := Y := W := H := 0
    WinGet, state, MinMax, ahk_id %thisWindowHwnd%

    if (targetDisplayNumber < 1)
        Return False

    ; Minimized windows do not have a meaningful current on-screen rect, so use
    ; their restored placement monitor instead of claiming they belong to every
    ; monitor.
    If (state == -1)
        Return (GetWindowDisplayNumber(thisWindowHwnd) = targetDisplayNumber)

    ; WinGetPos, X, Y, W, H, ahk_id %thisWindowHwnd%
    WinGetPosEx(thisWindowHwnd, X, Y, W, H)
    if (W <= 0 || H <= 0)
        Return False

    if !_GetMonitorRectangleByDisplayNumber(targetDisplayNumber, false, monitorLeft, monitorTop, monitorRight, monitorBottom)
        return false

    Critical, On

    ;Check If the focus window in on the requested monitor index
    ; https://math.stackexchange.com/questions/2449221/calculating-percentage-of-overlap-between-two-rectangles
    overlapRatio := ((max(X, monitorLeft) - min(X+W, monitorRight)) * (max(Y, monitorTop) - min(Y+H, monitorBottom))) / (W * H)
    Critical, Off
    Return (overlapRatio > 0.50)
}

; Return whether the control beneath the mouse exposes a standard scroll style.
IsWindowScrollable() {
    local ControlStyle, ctrlN, ExControlStyle, hwnd

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

; Return the larger of two numeric values for geometry calculations.
Max(a,b) {
    Return (a > b) ? a : b
}
; Return the smaller of two numeric values for geometry calculations.
Min(a,b) {
    Return (a < b) ? a : b
}

; Return whether the pointer is over a taskbar button group rather than the tray.
MouseIsOverTaskbarButtonGroup() {
    local CtrlUnderMouseId, ctype, mClass, pt, WindowUnderMouseID, x, y

    CoordMode, Mouse, Screen
    MouseGetPos, x, y, WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId != "TrayNotifyWnd1") {
        pt := SafeUIA_ElementFromPoint(x,y, "", 2000)
        ctype := SafeUIA_GetControlType(pt)
        Return (ctype == 50000)
    }
    Else
        Return False
}

; Return whether the pointer is over the notification-area child of a taskbar.
MouseIsOverTaskbarTray() {
    local CtrlUnderMouseId, mClass, WindowUnderMouseID

    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    Return (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId == "TrayNotifyWnd1")
}

; Move to the actual default enabled button of a standard, non-resizable dialog.
MoveMouseToDefaultDialogButton(hwndDlg := "", moveSpeed := 0) {

    local bh, btnHwnd, buttonType, bw, bx, by, defaultCtrlId, dialogStyle, h, listH
    local msgResult, ok, oldCoordModeMouse, style, targetPosX, targetPosY

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

    targetPosX := bx + Floor(bw / 2)
    targetPosY := by + Floor(bh / 2)

    if (moveSpeed > 0) {
        oldCoordModeMouse := A_CoordModeMouse
        CoordMode, Mouse, Screen
        MouseMove, %targetPosX%, %targetPosY%, %moveSpeed%
        CoordMode, Mouse, %oldCoordModeMouse%
    }
    else {
        DllCall("user32\SetCursorPos", "Int", targetPosX, "Int", targetPosY)
    }

    return btnHwnd
}

; Invalidate prior overlay fade loops so only the current transition can update alpha.
Overlay_CancelFade() {
    global overlayFadeToken
    ; Every new show/hide request bumps the token so older fade loops stop
    ; writing alpha immediately. This prevents two overlapping animations from
    ; fighting each other and producing flicker or abrupt opacity jumps.
    overlayFadeToken++
    return overlayFadeToken
}

; Fade the existing overlay to a target alpha without allowing old fades to interfere.
Overlay_FadeTo(overlayHwnd, alphaTarget, fadeMs := 100, alphaStart := "", allowModifierAbort := True) {
    global overlayFadeToken, overlayAlphaCurrent

    localFadeToken := Overlay_CancelFade()

    if (alphaStart = "")
        alphaStart := overlayAlphaCurrent

    alphaStart  := ClampAlpha(alphaStart)
    alphaTarget := ClampAlpha(alphaTarget)

    ; Guard: avoid divide-by-zero and negative durations
    if (fadeMs < 1)
        fadeMs := 1

    ; Break the fade into small ~5 ms steps so opacity ramps gradually instead
    ; of jumping straight to the end state. Starting from the current alpha also
    ; means a new fade can continue seamlessly from whatever frame was already on
    ; screen, which avoids a visible snap when the user cycles quickly.
    iterations := ceil(fadeMs/5)
    if (iterations > 0) {
        transIncr  := (alphaTarget - alphaStart)/iterations
        alphaNow   := alphaStart + transIncr

        Loop, %iterations%
        {
            ; If a newer fade started, stop ASAP so only one animation source is
            ; updating opacity. That keeps the transition coherent during rapid
            ; Alt+Tab / Alt+` input.
            If (localFadeToken != overlayFadeToken)
                return

            ; Show/preview fades should stop immediately once the cycle keys are up,
            ; but hide fades are allowed to finish unless a newer fade supersedes them.
            ; The effect is that the overlay appears responsive on release while the
            ; fade-out can still visually taper off instead of disappearing hard.
            If (allowModifierAbort && !GetKeyState("LAlt","P") && !GetKeyState("Esc","P")) {
                Overlay_SetAlpha(overlayHwnd, alphaTarget)
                break
            }

            Overlay_SetAlpha(overlayHwnd, alphaNow)
            if(A_Index < iterations) {
                ; Yield briefly between frames so Windows can present the updated
                ; alpha and make the fade read as motion rather than one delayed jump.
                sleep, 5
                alphaNow += transIncr
            }
        }
    }
}

; alphaPrimary is the transparency of the top window.
; alphaTarget is the final combined opacity you want after both windows are layered.
; The function first clamps both values into the valid 0..255 range.
; It figures out how much of the background still shows through the first window.
; Then it computes how transparent the second window must be so the total visible background matches the target.
; It clamps that result to a valid range, converts it back to an AHK alpha value, rounds it, and returns it.

; ------------------------------------------------------------
; Shows an existing (already-created) Overlay GUI and updates
; the hole rectangle + transparency without recreating the GUI.
;
; Notes:
; - Assumes the GUI and the Progress control already exist.
; - Changing clickThrough is supported via ExStyle toggling.
; - If you need to change overlayColor dynamically, we set it here.
; ------------------------------------------------------------
; Apply one alpha value to the existing overlay window.
Overlay_SetAlpha(overlayHwnd, alphaVal) {
    global overlayAlphaCurrent

    alphaVal := ClampAlpha(alphaVal)

    ; Keep the overlay as a layered window so the compositor can blend opacity
    ; changes against the already-existing surface. That lets fades happen as
    ; cheap alpha updates instead of forcing hide/show or full window rebuilds,
    ; which is what keeps the dimming transition visually smooth.
    WinSet, ExStyle, +0x80000, ahk_id %overlayHwnd%  ; WS_EX_LAYERED

    ; Apply only a new per-window alpha value. Because the same HWND stays alive,
    ; each fade step modifies the current frame in place and avoids the flash that
    ; would come from recreating the overlay window between animation frames.
    DllCall("user32\SetLayeredWindowAttributes"
        , "ptr", overlayHwnd
        , "uint", 0
        , "uchar", alphaVal
        , "uint", 0x2)

    overlayAlphaCurrent := alphaVal
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


; Read the ApplicationView cloak property while enumerating a window's properties.
PropEnumProcEx(hWnd, lpszString, hData, dwData)
{
   If (strget(lpszString, "UTF-16") = "ApplicationViewCloakType")
   {
      ; Store the matching property data in the caller's result slot so cloak state can be read.
      numput(hData, dwData+0, 0, "int")
      Return False
   }
   Return True
}

; Normalize an HWND value to the UInt representation used by legacy window APIs.
realHwnd(hwnd)
{
   varsetcapacity(var, 8, 0)
   ; Store the HWND as an unsigned 64-bit value so NumGet can normalize it to legacy UInt form.
   numput(hwnd, var, 0, "uint64")
   Return numget(var, 0, "uint")
}

; Return the UI Automation element at a screen point while containing provider failures.
SafeUIA_ElementFromPoint(x, y, default := "", transactionTimeout := 250, connectionTimeout := 20000, retryAfterFailure := True) {
    global UIA
    priorConnectionTimeout  := ""
    priorTransactionTimeout := ""
    result := default

    if (transactionTimeout <= 0)
        transactionTimeout := 250
    if (connectionTimeout <= 0)
        connectionTimeout  := 20000

    if (!IsObject(UIA))
        UIA := UIA_Interface()

    ; Keep fast point probes self-contained so their short timeout does not
    ; leak into later Explorer/SendCtrlAdd UIA work on the shared UIA object.
    try
        priorTransactionTimeout := UIA.TransactionTimeout
    catch e
        priorTransactionTimeout := ""
    try
        priorConnectionTimeout := UIA.ConnectionTimeout
    catch e
        priorConnectionTimeout := ""

    try {
        UIA.TransactionTimeout := transactionTimeout
        UIA.ConnectionTimeout  := connectionTimeout
        result := UIA.ElementFromPoint(x, y, False)
    } catch {
        UIA := ""
        if (retryAfterFailure) {
            try
                UIA := UIA_Interface()
            catch e
                UIA := ""

            if IsObject(UIA) {
                try
                    UIA.TransactionTimeout := transactionTimeout
                catch e {
                }
                try
                    UIA.ConnectionTimeout  := connectionTimeout
                catch e {
                }

                try
                    result := UIA.ElementFromPoint(x, y, False)
                catch
                    result := default
            }
        }
    }

    try {
        if (priorTransactionTimeout != "")
            UIA.TransactionTimeout := priorTransactionTimeout
    } catch e {
    }
    try {
        if (priorConnectionTimeout != "")
            UIA.ConnectionTimeout := priorConnectionTimeout
    } catch e {
    }

    return result
}

/*
    Read the UIA ClassName property, which is the provider-reported class label
    such as UIItem, UIItemsView, DirectUI, or another framework-specific name.

    Parameters:
    el            = UIA element to read from.
    default := "" = fallback value if the property cannot be read.
*/
SafeUIA_GetClassName(el, default := "") {
    local e

    if !IsObject(el)
        return default
    try
        return el.CurrentClassName
    catch e
        return default
}

; Read a UI Automation control type while converting provider failures to the default value.
SafeUIA_GetControlType(el, default := "") {
    if !IsObject(el)
        return default
    try
        return el.CurrentControlType
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
    local e

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
    local e

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
    local e

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
    local e

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

; * 20150906: The "dwmapi\DwmGetWindowAttribute" function can Return odd errors
;   if DWM is not enabled.  One error I've discovered is a Return code of
;   0x80070006 with a last error code of 6, i.e. ERROR_INVALID_HANDLE or "The
;   handle is invalid."  To keep the function operational during this types of
;   conditions, the function has been modified to assume that all unexpected
;   Return codes mean that DWM is not available and continue to process without
;   it.  When DWM is a possibility (i.e. Vista+), a developer-friendly messsage
;   will be dumped to the debugger when these errors occur.
;
; Credit:
;
;   Idea and some code from *KaFu* (AutoIt forum)
;
; Author:
;
;    jballi
;
; Forum Link:
;
;    https://autohotkey.com/boards/viewtopic.php?t=3392
;-------------------------------------------------------------------------------
WinGetPosEx(hWindow,ByRef X="",ByRef Y="",ByRef Width="",ByRef Height="",ByRef Offset_X="",ByRef Offset_Y="") {
    static RECTPlus, S_OK := 0x0, DWMWA_EXTENDED_FRAME_BOUNDS := 9

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

    If (DWMRC <> S_OK)
        {
        If ErrorLevel in -3,-4  ;-- Dll or function not found (older than Vista)
            {
            ;-- Do nothing Else (for now)
            }
         Else {
            OutputDebug, % "Function: " . A_ThisFunc
                . " - Unknown error calling ""dwmapi\DwmGetWindowAttribute""."
                . " RC=" . DWMRC
                . ", ErrorLevel=" . ErrorLevel
                . ", A_LastError=" . A_LastError
                . ". ""GetWindowRect"" used instead."
         }

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
    If (DWMRC<>S_OK)
        Return &RECTPlus

    ;-- Collect dimensions via GetWindowRect
    VarSetCapacity(RECT,16,0)
    DllCall("GetWindowRect",PtrType,hWindow,PtrType,&RECT)
    GWR_Width :=NumGet(RECT,8,"Int")-NumGet(RECT,0,"Int")
        ;-- Right minus Left
    GWR_Height:=NumGet(RECT,12,"Int")-NumGet(RECT,4,"Int")
        ;-- Bottom minus Top

    ;-- Calculate offsets and update output variables
    ; Store the horizontal centering offset in RECTPlus so the caller can position the window.
    NumPut(Offset_X:=(Width-GWR_Width)//2,RECTPlus,16,"Int")
    ; Store the vertical centering offset in RECTPlus so the caller can position the window.
    NumPut(Offset_Y:=(Height-GWR_Height)//2,RECTPlus,20,"Int")
    Return &RECTPlus
}
