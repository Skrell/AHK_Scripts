; c = case sensitive
; c1 = ignore the case that was typed, always use the same case for output
; * = immediate change (no need for space, period, or enter)
; ? = triggered even when the character typed immediately before it is alphanumeric
; r = raw output

#NoEnv
#SingleInstance Force
#InstallKeybdHook
#UseHook
#Include %A_ScriptDir%\ClipjumpCommunicator.ahk
#Include %A_ScriptDir%\..\WinLimit_based\UIA_Interface.ahk
#Include %A_ScriptDir%\..\WinLimit_based\DetermineCaptionButtonLib.ahk
#HotString EndChars ()[]{}:;,.?!`n `t
#MaxhotKeysPerInterval 500
#KeyHistory 10

SendMode, Input ; It injects the whole keystroke atomically, reducing the window where logical/physical can disagree

; SetKeyDelay is not obeyed by SendInput; there is no delay between keystrokes in that mode.
; This same is true for Send when SendMode Input is in effect.
; SetKeyDelay, -1, -1
SetMouseDelay,   -1
SetBatchLines,   -1 ; Remove AHK's built-in "cooperate with the OS" sleeps
SetWinDelay,      1 ;
SetControlDelay,  1 ;

; +----------------------------------------------------------------------------+
; | Typing Auto-Fix, Deferred Rewrite, And Activation State                    |
; | Caches whether typing fixes are allowed, queues short-lived deferred text  |
; | rewrites, and keeps focus/activation bookkeeping cheap while typing or     |
; | clicking into another window.                                              |
; +----------------------------------------------------------------------------+
Global StopAutoFix                                         := False
Global IsPaused                                            := False

; Cache the typing-auto-fix eligibility decision so most keystrokes avoid the
; slower UIA/MSAA focus probes.
; Last allow/deny result returned by the typing-auto-fix gate.
Global c_typingAutoFixAllowed                              := False
; Exact focused control handle associated with the cached decision. ClassNN can
; be reused after a custom control is recreated, so it is not a sufficient key.
Global c_typingAutoFixCtrlHwnd                             := 0
; Focused control name used to decide whether the cached result still applies.
Global c_typingAutoFixCtrlNN                               := ""
; Active window handle associated with the cached focus/editability decision.
Global c_typingAutoFixHwnd                                 := 0
; Short reason string describing why the current cache entry passed or failed.
Global c_typingAutoFixReason                               := ""
; Tick count when the cache entry was last refreshed.
Global c_typingAutoFixTick                                 := 0
; Maximum age for a same-window/same-control fast cache hit.
Global k_typingAutoFixFastTtlMs                            := 125
; Minimum gap before repeating slower UIA/MSAA probes for unchanged focus.
Global k_typingAutoFixSlowPathMs                           := 400
; Tick count of the last slow UIA/MSAA probe attempt.
Global typingAutoFixSlowProbeTick                          := 0
; +----------------------------------------------------------------------------+
; | Typing Auto-Fix Refresh And Prewarm State                                  |
; | Retains the target and sequence snapshots used by deferred editability     |
; | probes after focus, activation, or click changes settle.                   |
; +----------------------------------------------------------------------------+
; Focused control class captured with an async editability-refresh request.
Global typingAutoFixRefreshCtrlClass                       := ""
; Exact focused control handle captured with an async refresh request.
Global typingAutoFixRefreshCtrlHwnd                        := 0
; Focused control name captured when an async editability refresh is queued so
; the timer can confirm the same target still owns focus before probing.
Global typingAutoFixRefreshCtrlNN                          := ""
; Physical typing sequence captured when an async editability probe is queued.
Global typingAutoFixRefreshStartTypingSeq                  := 0
; Hotstring boundary sequence captured with the async editability probe.
Global typingAutoFixRefreshStartHotstringBoundarySeq       := 0
; True when a positive async result must protect against activation mid-word.
Global typingAutoFixRefreshProtectPartialWord              := False
; Short one-shot delay before the async editability refresh runs. This keeps the
; first keypath cheap and spaces the slow probe slightly away from the triggering
; keystroke, while the later A_TimeIdlePhysical retry is what usually keeps the
; refresh from competing with nearby deferred text-rewrite timers.
Global k_typingAutoFixRefreshDelayMs                       := 25
; Active window captured when the async editability refresh is queued.
Global typingAutoFixRefreshHwnd                            := 0
; Monotonic token incremented whenever a newer async editability refresh
; replaces an older queued request.
Global typingAutoFixRefreshId                              := 0
; Tick count recorded when the async editability refresh is queued so the flow
; can be reasoned about against nearby deferred typing timers.
Global typingAutoFixRefreshRequestedTick                   := 0
; Hotstring boundary sequence captured when the current startup/focus/click prewarm was
; scheduled, before a user can begin typing into the newly focused target.
Global typingAutoFixPrewarmStartHotstringBoundarySeq       := 0
; Physical typing sequence captured with the current prewarm request.
Global typingAutoFixPrewarmStartTypingSeq                  := 0
; Short delay that lets a click or activation finish assigning keyboard focus.
Global k_typingAutoFixPrewarmDelayMs                       := 25
; +----------------------------------------------------------------------------+
; | Typing Sequence And Deferred Rewrite State                                 |
; | Coordinates physical typing boundaries and short-lived rewrite callbacks   |
; | so stale corrections cannot land in a newer text context.                  |
; +----------------------------------------------------------------------------+
Global X_PriorPriorHotKey                                  :=
; True while the post-boundary hotstring-buffer reset timer is pending.
Global hotstringResetTimerPending                          := False
; Target hotstringBoundarySeq that schedules a post-boundary Hotstring("Reset").
; Zero means no deferred buffer reset is pending.
Global hotstringResetAtBoundarySeq                         := 0
; Monotonic count of physical text-input key-downs. Async editability probes
; compare this with their queued snapshot to detect typing during the probe.
Global physicalTypingSeq                                   := 0
; Monotonic count of physical keys that exactly match #HotString EndChars.
Global hotstringBoundarySeq                                := 0
; Shared sequence token for deferred typing rewrites so older timer callbacks can
; detect that a newer key event already replaced their context and should win.
Global typingFixSeq                                        := 0
; Maximum lifetime for a deferred typing rewrite before it is discarded. Once a
; queued fix has been tbc longer than this limit, it is assumed the user may
; already be typing in a newer text context, so the delayed Send is skipped.
Global k_tbcTypingFixMaxAgeMs                              := 250
; Let specific call sites opt into a more explicit paste chord when SendInput, ^v
; is occasionally interpreted as a literal v by the target editor.
Global clipPreferExplicitCtrlV                             := False
; Optional focused control HWND for paste targets that ignore foreground Ctrl+V.
Global clipPasteControlHwnd                                := 0
; Last managed clipboard read result. Wrapper hotkeys use this to abort when a
; fallback Ctrl+C did not actually capture the selected text.
Global clipLastReadSucceeded                               := True
; Beyond Compare sometimes exposes its editor focus slightly after the first probe.
Global bcompareFastInsertRetryCount                        := 3
Global bcompareFastInsertRetryDelayMs                      := 50
; True while Clip() has a delayed clipboard restore timer queued.
Global clipRestoreTimerPending                             := False
; True when the wrapper hotkey temporarily disabled Clipjump's full hotkey/clipboard layer.
Global clipjumpWrapperPaused                               := False
; Master logging switch. Leave False for normal use; set True only while diagnosing.
Global allDebugLoggingEnabled                              := True
; Wrapper hotkeys write concise branch/outcome diagnostics here without logging selected text content.
Global wrapDebugEnabled                                    := True
Global wrapDebugLogPath                                    := A_ScriptDir . "\AutoCorrect_WrapDebug.log"
; Temporary slash-fix Enter interception flag. After a qualifying letter + "/",
; this diverts the next Enter into the custom $Enter handler so slash+Enter can
; either commit "{BS}{?}{ENTER}" inline or fall back to one normal Enter, but
; never let both the raw key and the rewrite path fire.
Global disableEnter                                        := False
; Name of the most recently triggered hotkey for repeat-sensitive logic.
Global lastHotkeyTyped                                     := ""
; Tick count of the most recent hotkey-triggered send used by typing heuristics.
Global TimeOfLastHotkeyTyped                               := A_TickCount
; +----------------------------------------------------------------------------+
; | Everything Edit1 Deferred Column Auto-Fit State                            |
; | Debounces native results ListView sizing so it runs after a short pause     |
; | and only while the same Everything Edit1 still owns focus.                  |
; +----------------------------------------------------------------------------+
; Focused control name captured when Everything Edit1 auto-fit is queued so
; the deferred resize can require the same search field before firing.
Global tbcEverythingAdjustCtrlNN                           := ""
; Focused control class captured with the queued Everything auto-fit so the
; flush step can require the same concrete control identity when available.
Global tbcEverythingAdjustCtrlClass                        := ""
; Focused control HWND captured when Everything auto-fit is queued so the flush
; step can reject a later Edit1 from a different control instance.
Global tbcEverythingAdjustCtrlHwnd                         := 0
; Active Everything window captured for the deferred search-box auto-fit resize.
Global tbcEverythingAdjustHwnd                             := 0
; Monotonic token incremented for each newer Everything Edit1 auto-fit request
; so older timer callbacks can detect that typing already superseded them.
Global tbcEverythingAdjustId                               := 0
; Tick count recorded when the Everything Edit1 auto-fit request was queued.
Global tbcEverythingAdjustRequestedTick                    := 0
; Source typing tick associated with the current Everything auto-fit request so
; KeyTrack queues at most one deferred resize request per physical keypress burst update.
Global tbcEverythingAdjustSourceTick                       := 0
; Maximum lifetime for a deferred Everything Edit1 auto-fit request before it
; is dropped as stale rather than sent into a newer typing context.
Global k_tbcEverythingAdjustMaxAgeMs                       := 750
; Short retry delay for the queued Everything Edit1 auto-fit timer while
; waiting for Everything's native results ListView/header to settle.
Global k_tbcEverythingAdjustRetryMs                        := 40
; Debounce interval after an Everything Edit1 typing event before attempting
; native results ListView column sizing.
Global k_tbcEverythingAdjustTypingQuietMs                  := 100
; +----------------------------------------------------------------------------+
; | Explorer Column Auto-Fit Deferred Wheel State                              |
; | Tracks quiet-time gating, supersession tokens, and short-lived target      |
; | caches for the deferred Explorer/file-dialog Ctrl+NumpadAdd send path.     |
; +----------------------------------------------------------------------------+
; Tick count of the most recent qualifying wheel event so AdjustColumns can defer
; work until the user pauses scrolling and cancel if wheel activity resumes.
Global tbcAdjustColumnsLastWheelTick                       := 0
; Monotonic request token incremented on each qualifying wheel event so older
; deferred timers can detect they were superseded and exit without sending.
Global tbcAdjustColumnsRequestId                           := 0
; Brief final hold just before injecting Ctrl+NumpadAdd so a last-moment wheel event
; can update the tbc request state and cause the send to abort cleanly.
Global k_tbcAdjustColumnsSendGuardMs                       := 20
; Keep wheel suppression active briefly after Ctrl+NumpadAdd and immediate Ctrl
; synchronization so delayed physical wheel input cannot escape as Ctrl+Wheel.
Global k_tbcAdjustColumnsPostSendWheelGuardMs              := 20
; +----------------------------------------------------------------------------+
; Deferred typing correction state so punctuation and capitalization rewrites can
; happen just after the live keypress cycle settles instead of on the triggering
; key event itself.
; Slash uses this slot for deferred "/ " rewrites and for slash+Enter in
; non-classic editors. Classic Edit/RichEdit slash+Enter is handled inline by
; the custom $Enter hotkey instead of through this timer.
; +----------------------------------------------------------------------------+
; True when the latest physical slash follows another slash in the current
; whitespace-delimited string, so every FixSlash path can reject path-like input.
Global fixSlashCandidateHasPriorSlash                      := False
; Whitespace-delimited string sequence in which the last physical slash occurred.
Global fixSlashLastSlashStringSeq                          := -1
; Advances on physical Tab, Enter, or Space so slash history cannot cross strings.
Global fixSlashStringBoundarySeq                           := 0
Global tbcFixSlashAction                                   := ""
; Focused control name captured when the "/ " fix is queued so the timer can
; cancel instead of rewriting text after focus moves to another control.
Global tbcFixSlashCtrlNN                                   := ""
; Focused control class captured with the deferred slash-space fix so classic
; Edit/RichEdit targets can use the same safer message-based phase-2 rewrite
; path that Hoty now uses.
Global tbcFixSlashCtrlClass                                := ""
; Focused control HWND captured when the slash-space fix is queued so the flush
; step can require the exact same control instance instead of trusting only the
; ClassNN string.
Global tbcFixSlashCtrlHwnd                                 := 0
; Active top-level window captured when the deferred slash-space rewrite is armed;
; the flush step requires this same window to still be active before sending.
Global tbcFixSlashHwnd                                     := 0
; Sequence token assigned when the slash-space rewrite is queued so older timer
; callbacks can detect that a newer typing event already superseded the work.
Global tbcFixSlashId                                       := 0
; Tick count recorded when the slash-space rewrite is queued, used to drop the
; request once it has been tbc longer than k_tbcTypingFixMaxAgeMs.
Global tbcFixSlashRequestedTick                            := 0
; Focused control name captured when the deferred Hoty capitalization fix is queued
; so the timer only rewrites if the same edit target still owns focus.
Global tbcHotyCtrlNN                                       := ""
; Focused control class captured with the deferred Hoty fix so the flush step can
; choose the safer message-based rewrite path for classic Edit/RichEdit targets.
Global tbcHotyCtrlClass                                    := ""
; Focused control HWND captured when the Hoty fix is queued so the flush step can
; require the exact same control instance, not just the same ClassNN string.
Global tbcHotyCtrlHwnd                                     := 0
; Active top-level window captured for the deferred Hoty fix, preventing the timer
; from replaying a capitalization rewrite into whichever window became active later.
Global tbcHotyHwnd                                         := 0
; Sequence token assigned to the deferred Hoty fix so only the newest queued
; typing rewrite can fire and any older timer callbacks self-cancel.
Global tbcHotyId                                           := 0
; Tick count captured when the Hoty fix is queued, allowing old capitalization fixes
; to expire quickly instead of landing after the surrounding typing context changed.
Global tbcHotyRequestedTick                                := 0
; Replacement character captured from the prior capital hotkey so the deferred Hoty
; flush can send the intended rewrite only after the live key cycle has settled.
Global tbcHotyReplacement                                  := ""
; Current lowercase trigger character captured when the Hoty fix is queued so a
; later classic-control flush can confirm the exact prior-capital + current-letter
; text context before replacing anything.
Global tbcHotyTriggerChar                                  := ""
; +----------------------------------------------------------------------------+
; | Runtime Context And Click/Drag Scratch State                               |
; | Stores the current desktop, monitor, Explorer path, click target, and      |
; | in-progress drag metadata shared across mouse and window-management flows.  |
; +----------------------------------------------------------------------------+
; Lowercase alphabet characters used by text and hotstring helpers.
Global k_keys                                              := "abcdefghijklmnopqrstuvwxyz"
; Decimal digit characters used by text and hotstring helpers.
Global k_numbers                                           := "0123456789"
Global k_DoubleClickTime                                   := DllCall("GetDoubleClickTime")
Global k_SingleClickTime                                   := floor(DllCall("GetDoubleClickTime") * 0.5)
; Global hActWin                                           := DllCall("user32\SetWinEventHook", UInt,0x3, UInt,0x3, Ptr,0, Ptr,RegisterCallback("OnWinActiveChange"), UInt,0, UInt,0, UInt,0, Ptr)
Global UIA                                                 := UIA_Interface() ; Initialize UIA interface
; Turn key blocking ON/OFF
Global StopRecursion                                       := False
Global blockKeys                                           := False
Global blockWheel                                          := False
Global gExiting                                            := False
Global hHookKbd
Global hHookMouse
Global deferredModifierFamilies                            := ""
Global deferredModifierSyncRemaining                       := 0
Global deferredModifierTargetHwnd                          := 0


Process, Priority,, High

UIA.TransactionTimeout := 2000
UIA.ConnectionTimeout  := 20000

Menu, Tray, Icon
Menu, Tray, NoStandard
Menu, Tray, Add, Run at startup, Startup
Menu, Tray, Add, &Suspend, Suspend_label
Menu, Tray, Add, Reload, Reload_label
Menu, Tray, Add, Exit, Exit_label
Menu, Tray, Default, &Suspend
Menu, Tray, Add
Menu, Tray, Add, Key History, keyhist_label
Menu, Tray, Add, List Hotkeys, listHotkeys_label
Menu, Tray, Add, List Vars, listVars_label
Menu, Tray, Add, List Lines, listLines_label
Menu, Tray, Click, 1

; Keep the real Tray menu for AutoHotkey's built-in tray bookkeeping, but show a
; separate normal popup menu when the user right-clicks the icon. A normal menu
; obeys TrackPopupMenuEx alignment flags, which lets us anchor it flush to the
; top edge of the bottom taskbar.
Menu, TrayPopup, Add, Run at startup, Startup
Menu, TrayPopup, Add, &Suspend, Suspend_label
Menu, TrayPopup, Add, Reload, Reload_label
Menu, TrayPopup, Add, Exit, Exit_label
Menu, TrayPopup, Default, &Suspend
Menu, TrayPopup, Add
Menu, TrayPopup, Add, Key History, keyhist_label
Menu, TrayPopup, Add, List Hotkeys, listHotkeys_label
Menu, TrayPopup, Add, List Vars, listVars_label
Menu, TrayPopup, Add, List Lines, listLines_label

link := A_Startup . "\AutoCorrect.lnk"
runAtStartup := FileExist(link) ? 1 : 0
if (runAtStartup)
    Menu, Tray, Check, Run at startup
else
    Menu, Tray, Uncheck, Run at startup

; Mirror the initial check state into TrayPopup so both menus stay visually in
; sync even though only TrayPopup is shown by the custom right-click handler.
if (runAtStartup)
    Menu, TrayPopup, Check, Run at startup
else
    Menu, TrayPopup, Uncheck, Run at startup
; listens for tray icon notifications
; - watch for message 0x404
; - sent to your script window
; - from your script's tray icon registration
OnMessage(0x404, "HandleTrayIconMessage")

;------------------------------------------------------------------------------
; AUto-COrrect TWo COnsecutive CApitals.
; Disabled by default to prevent unwanted corrections such as IfEqual->Ifequal.
; To enable it, remove the /*..*/ symbols around it.
; From Laszlo's script at http://www.autohotkey.com/forum/topic9689.html
;------------------------------------------------------------------------------
; The first line of code below is the set of letters, digits, and/or symbols
; that are eligible for this type of correction.  Customize if you wish:

; Keep these pass-through tracking hooks active in every context. Hoty and
; FixSlash derive their letter/punctuation sequence from A_PriorHotkey; if a
; focus-cache predicate temporarily disables even one tracking hook, that
; sequence is lost and neither correction can recognize its trigger. Their
; labels perform the actual StopAutoFix, editor, timing, and pattern checks.

HotKey, ~/,  Marktime_FixSlash
HotKey, ~',  Marktime_Hoty ;'
HotKey, ~?,  Marktime_Hoty
HotKey, ~!,  Marktime_Hoty
HotKey, ~`,, Marktime_Hoty
HotKey, ~.,  Marktime_Hoty
HotKey, ~_,  Marktime_Hoty
HotKey, ~-,  Marktime_Hoty
Hotkey, ~:,  MarkKeypressTime

Loop Parse, k_keys
{
    Hotkey, %  "~" . A_LoopField, Marktime_Hoty_FixSlash, On
    Hotkey, % "~+" . A_LoopField, Marktime_Hoty_FixSlash, On
}

; Numbers
Loop Parse, k_numbers
{
    Hotkey, % "~" . A_LoopField, Marktime_Hoty_FixSlash, On
}

hHookKbd   := 1
hHookMouse := 1
; Get module handle for this process (needed by SetWindowsHookEx for LL hooks)
hMod        := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")

; Low-level keyboard hook: WH_KEYBOARD_LL = 13
kbdCallback := RegisterCallback("LL_KeyboardHook", "Fast")
hHookKbd    := DllCall("SetWindowsHookEx"
                        , "Int", 13              ; WH_KEYBOARD_LL
                        , "Ptr", kbdCallback
                        , "Ptr", hMod
                        , "UInt", 0
                        , "Ptr")

; Low-level mouse hook: WH_MOUSE_LL = 14
; mouseCallback := RegisterCallback("LL_MouseHook", "Fast")
; hHookMouse    := DllCall("SetWindowsHookEx"
    ; , "Int", 14              ; WH_MOUSE_LL
    ; , "Ptr", mouseCallback
    ; , "Ptr", hMod
    ; , "UInt", 0
    ; , "Ptr")

if (!hHookKbd)
{
    MsgBox, 16, Error, Failed to install the low-level keyboard hook.`nKeyboard: %hHookKbd%
    GoSub, Exit_label
}

OnExit, UnhookHooks

SetTimer KeyTrack, 25

Return

; ==========================================================================================================================================
; -----------------------------------------------          START OF APPLICATION           --------------------------------------------------
; ==========================================================================================================================================
; --------------------------------------------------
; ---- Low-level hardware key filter ----
; --------------------------------------------------
; Low-level keyboard filtering and physical typing bookkeeping. When blockKeys
; is active, physical key-down events may be swallowed; when it is inactive,
; qualifying physical key-downs are still recorded before being passed through.
;
; Why physical KEYUP events must be allowed through:
;   Normal key lifecycle:
;     physical c down -> WM_KEYDOWN(c) -> WM_CHAR("c") -> WM_KEYUP(c)
;     -> editor/framework closes the c key cycle cleanly
;
;   Broken old blockKeys lifecycle:
;     physical c down -> WM_KEYDOWN(c) -> WM_CHAR("c") -> blockKeys swallows WM_KEYUP(c)
;     -> next input transition arrives (Send / modifier cleanup / next real key)
;     -> editor/framework still has stale "c is down" state
;     -> the app can misread the next input as one extra "c" or a stuck modifier
;
; Many apps assume Windows delivers a sane KEYDOWN -> CHAR -> KEYUP lifecycle.
; Once a low-level hook violates that assumption, behavior becomes framework-specific
; and can show up as duplicate first letters instead of a clean infinite repeat.
; --------------------------------------------------
/*
LL_KeyboardHook hexadecimal lookup (Windows constants)

Used as          Hex             Windows name / concrete meaning
---------------  --------------  ----------------------------------------------
wParam message   0x0100          WM_KEYDOWN
wParam message   0x0101          WM_KEYUP
wParam message   0x0104          WM_SYSKEYDOWN (commonly Alt or F10 processing)
wParam message   0x0105          WM_SYSKEYUP   (commonly Alt or F10 processing)
Hook flag mask   0x10            LLKHF_INJECTED: event was synthetically injected
Key-state mask   0x8000          GetAsyncKeyState high bit: key is currently down

Virtual key      0x08            VK_BACK: Backspace
Virtual key      0x09            VK_TAB: Tab; also a #HotString EndChar
Virtual key      0x0D            VK_RETURN: Enter; also a #HotString EndChar
Virtual key      0x10            VK_SHIFT: used only with GetAsyncKeyState here
Virtual key      0x20            VK_SPACE: Space; also a #HotString EndChar
Virtual-key span 0x30-0x5A       0-9 and A-Z (intervening values are unused)
Virtual-key span 0x60-0x6F       Numpad 0-9 and numpad operators
Virtual-key span 0xBA-0xE2       OEM/layout-dependent range; includes reserved values

Boundary keys below assume a US keyboard layout for the displayed characters:
0xBA = ; or :    0xDB = [ or {    0xDD = ] or }
0x31 = 1 or !    0x30 = 0 or )    0x39 = 9 or (
0xBC = , or <    0xBE = . or >    0xBF = / or ?

The first boundary row is accepted with or without Shift. The second row is
accepted only with Shift. In the third row, comma and period are accepted only
without Shift, while slash is accepted only with Shift. Those choices exactly
match the #HotString EndChars directive near the top of this file.
*/
LL_KeyboardHook(nCode, wParam, lParam)
{
    ; While blockKeys := true, swallow only physical KEYDOWN / SYSKEYDOWN events.
    ; Current behavior lets physical KEYUP / SYSKEYUP pass so the active app can
    ; close the real key cycle cleanly.
    ; The warning below describes the old failure mode that happened when
    ; blockKeys swallowed physical KEYUP. The current hook allows KEYUP through.
    global blockKeys, hHookKbd
    global fixSlashStringBoundarySeq
    global hotstringResetTimerPending
    global hotstringBoundarySeq, hotstringResetAtBoundarySeq
    global physicalTypingSeq
    static blockedPressCount = 0

    ; do not process / do not block / do not modify this event
    if (nCode < 0)
        return DllCall("CallNextHookEx", "Ptr", hHookKbd, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    ; KBDLLHOOKSTRUCT:
    ;   vkCode      (DWORD)  offset 0
    ;   scanCode    (DWORD)  offset 4
    ;   flags       (DWORD)  offset 8
    ;   time        (DWORD)  offset 12
    ;   dwExtraInfo (ULONG_PTR) offset 16

    flags    := NumGet(lParam + 0, 8, "UInt")
    injected := (flags & 0x10)  ; LLKHF_INJECTED

    ; Allow script- or externally-injected events; only physical user input is
    ; used for typing and boundary bookkeeping below.
    if (injected)
        return DllCall("CallNextHookEx", "Ptr", hHookKbd, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    ; If not blocking, finish physical typing/boundary bookkeeping above, then
    ; pass the unchanged event through to the active application.
    if (!blockKeys)
    {
        ; Track physical text-input key-downs separately from the script's exact
        ; #HotString EndChars. An async custom-editor probe compares both counts
        ; to distinguish no typing, a partial word, and a completed word boundary.
        if (wParam = 0x0100 || wParam = 0x0104)  ; WM_KEYDOWN / WM_SYSKEYDOWN
        {
            vkCode := NumGet(lParam + 0, 0, "UInt")
            isTextInputKey := (vkCode = 0x08 || vkCode = 0x09 || vkCode = 0x0D
                || vkCode = 0x20 || (vkCode >= 0x30 && vkCode <= 0x5A)
                || (vkCode >= 0x60 && vkCode <= 0x6F)
                || (vkCode >= 0xBA && vkCode <= 0xE2))
            if (isTextInputKey)
                physicalTypingSeq += 1

            ; Treat whitespace as the end of the current FixSlash string. The
            ; slash hotkey records its candidate before a later separator arrives.
            if (vkCode = 0x09 || vkCode = 0x0D || vkCode = 0x20)
                fixSlashStringBoundarySeq += 1

            isBoundary := (vkCode = 0x09 || vkCode = 0x0D || vkCode = 0x20
                || vkCode = 0xBA || vkCode = 0xDB || vkCode = 0xDD)

            if (!isBoundary && (vkCode = 0x31 || vkCode = 0x30 || vkCode = 0x39
                || vkCode = 0xBC || vkCode = 0xBE || vkCode = 0xBF))
            {
                shiftDown := (DllCall("GetAsyncKeyState", "Int", 0x10, "Short") & 0x8000)
                isBoundary := ((shiftDown && (vkCode = 0x31 || vkCode = 0x30
                    || vkCode = 0x39 || vkCode = 0xBF))
                    || (!shiftDown && (vkCode = 0xBC || vkCode = 0xBE)))
            }

            if (isBoundary) {
                hotstringBoundarySeq += 1
                ; When the requested boundary arrives, defer the buffer reset until
                ; this separator key event has finished. Resetting inside the hook
                ; would modify AutoHotkey's buffer while the event is still processing.
                if (hotstringResetAtBoundarySeq
                    && hotstringBoundarySeq >= hotstringResetAtBoundarySeq
                    && !hotstringResetTimerPending)
                {
                    hotstringResetTimerPending := True
                    SetTimer, ResetHotstringBufferAfterBoundary, -1
                }
            }
        }

        blockedPressCount := 0
        return DllCall("CallNextHookEx", "Ptr", hHookKbd, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    }

    ; Allow physical key-up events through while blocking so real key cycles can complete.
    if (wParam = 0x0101 || wParam = 0x0105)  ; WM_KEYUP / WM_SYSKEYUP
        return DllCall("CallNextHookEx", "Ptr", hHookKbd, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    ; Emergency watchdog for failed or interrupted cleanup that leaves blockKeys
    ; enabled indefinitely. After 20 blocked physical key-down events, forcibly
    ; end blocking and allow the twentieth key through so normal typing resumes.
    ; Key-up events are excluded so complete key cycles do not inflate the count.
    if (wParam = 0x0100 || wParam = 0x0104)  ; WM_KEYDOWN / WM_SYSKEYDOWN
    {
        blockedPressCount += 1

        if (blockedPressCount >= 20)
        {
            EndBlockKeys()
            blockedPressCount := 0

            ; Let this key through so typing resumes immediately
            return DllCall("CallNextHookEx", "Ptr", hHookKbd, "Int", nCode, "UInt", wParam, "Ptr", lParam)
        }
    }

    ; Otherwise block physical key
    return 1  ; non-zero = swallow
}

; --------------------------------------------------
; Dormant low-level mouse-hook implementation retained for possible future use.
; Its registration above is disabled; active wheel suppression uses the
; context-sensitive #If blockWheel hotkeys instead.
; --------------------------------------------------
LL_MouseHook(nCode, wParam, lParam)
{
    global blockWheel, hHookMouse

    if (nCode < 0)
        return DllCall("CallNextHookEx", "Ptr", hHookMouse, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    if (!blockWheel)
        return DllCall("CallNextHookEx", "Ptr", hHookMouse, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    else {
        ; MSLLHOOKSTRUCT:
        ; flags offset 12
        flags    := NumGet(lParam + 0, 12, "UInt")
        injected := (flags & 0x01)  ; LLMHF_INJECTED

        ; wParam: mouse message:
        ;   0x0201 WM_LBUTTONDOWN
        ;   0x0202 WM_LBUTTONUP
        ;   0x0204 WM_RBUTTONDOWN
        ;   0x0205 WM_RBUTTONUP
        ;   0x0207 WM_MBUTTONDOWN
        ;   0x0208 WM_MBUTTONUP
        ;   plus dbl-click messages, etc.
        ;
        ; MSLLHOOKSTRUCT:
        ;   pt          (POINT)  offset 0 (8 bytes)
        ;   mouseData   (DWORD)  offset 8
        ;   flags       (DWORD)  offset 12
        ;   time        (DWORD)  offset 16
        ;   dwExtraInfo (ULONG_PTR) offset 20

        ; Allow injected mouse events (SendInput/Click)
        if (injected)
            return DllCall("CallNextHookEx", "Ptr", hHookMouse, "Int", nCode, "UInt", wParam, "Ptr", lParam)

        ; Suppress wheel input if this dormant hook is explicitly re-enabled.
        if (wParam = 0x020A || wParam = 0x020E)  ; WM_MOUSEWHEEL / WM_MOUSEHWHEEL
            return 1

        ; Otherwise pass through mouse movement and button presses.
        return DllCall("CallNextHookEx", "Ptr", hHookMouse, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    }
}

MarkKeypressTime:
    if (!StopAutoFix && (tbcFixSlashAction || tbcHotyReplacement))
        CancelTbcTypingFixes(True, False)
    TimeOfLastHotkeyTyped := A_TickCount
Return

Marktime_Hoty:
    GoSub, MarkKeypressTime
    GoSub, Hoty
Return

Marktime_Hoty_FixSlash:
    GoSub, MarkKeypressTime
    GoSub, Hoty
    GoSub, FixSlash
Return

Marktime_FixSlash:
    GoSub, MarkKeypressTime
    GoSub, FixSlash
Return

Startup:
    runAtStartup := !runAtStartup

    if (runAtStartup) {

        if (A_IsCompiled)
            target := A_ScriptFullPath
        else
            target := A_AhkPath . " " . A_ScriptFullPath

        FileCreateShortcut, %target%, %link%
        Menu, Tray, Check, Run at startup
        ; Keep the mirrored popup menu's checkmark matched to the real tray item.
        Menu, TrayPopup, Check, Run at startup

    } else {
        IfExist, %link%
            FileDelete, %link%
        Menu, Tray, Uncheck, Run at startup
        ; Keep the mirrored popup menu's checkmark matched to the real tray item.
        Menu, TrayPopup, Uncheck, Run at startup
    }
Return

Tray_SingleLclick:
    msgbox You left-clicked tray icon
Return

Reload_label:
    OnExit,     ; unregister OnExit label
    Gosub, UnhookHooks
    Reload
Return

Suspend_label:
    Menu, Tray, Togglecheck, &Suspend
    ; Toggle the mirrored popup menu too so its state always matches the real
    ; tray item regardless of which menu the user interacted with.
    Menu, TrayPopup, Togglecheck, &Suspend
    Suspend
    If IsPaused {
        SetTimer, KeyTrack, On
        IsPaused := False
    }
Return

Exit_label:
    OnExit,     ; unregister OnExit label
    Gosub, UnhookHooks
    ExitApp
return

keyhist_label:
    KeyHistory
Return

listHotkeys_label:
    ListHotkeys
Return

listVars_label:
    ListVars
Return

listLines_label:
    ListLines
Return

; ==========================================================================================================================================
; -----------------------------------------------          TYPING MANIUPLATION           --------------------------------------------------
; ==========================================================================================================================================
Hoty:
    CapCount := (IsPriorHotKeyCapital() && A_TimeSincePriorHotkey < 999) ? CapCount + 1 : 1 ; note that CapCount is ALWAYS at least 1
    If !IsGoogleDocWindow() && !StopAutoFix && CapCount == 3 && IsThisHotKeyLowerCase()  {
        CancelTbcTypingFixes(False, False)
        typingFixSeq += 1
        CaptureActiveFocusSnapshot(tbcHotyHwnd, tbcHotyCtrlNN, tbcHotyCtrlHwnd, tbcHotyCtrlClass)
        tbcHotyId          := typingFixSeq
        tbcHotyRequestedTick  := A_TickCount
        tbcHotyReplacement := SubStr(A_PriorHotKey,3,1)
        tbcHotyTriggerChar := SubStr(A_ThisHotKey,2,1)
        SetTimer, FlushTbcHotyReplacement, -40
        CapCount := 1
    }
    If StopAutoFix
        X_PriorPriorHotKey :=
Return

; Deferred Hoty rewrite:
; live key event -> store intended replacement -> one-shot timer -> wait for
; brief physical idle -> verify same window/control context still matches ->
; perform a safe rewrite path for that editor type
;
; Why this exists:
; user types      : A  A  a
; immediate fix   :     +--> {Left}{BS}a{Right} while the "a" key cycle may
;                       still be finishing
; risk            : main-thread hotkey gating + live caret movement can make
;                   the rewrite run against a half-settled text state
; result          : delayed output, bursty output, or a garbled correction
;
; Safer path:
; A  A  a
; |  |  +--> queue replacement only
; |  |      +--> timer retries until A_TimeIdlePhysical is calm
; |  |          +--> if same classic control + same text context, replace just the
; |  |               prior capital with EM_SETSEL/EM_REPLACESEL
; |  |          +--> otherwise keep the older blind-send fallback for non-classic
; |  |               editors only
FlushTbcHotyReplacement:
    if (!tbcHotyReplacement)
        Return

    ; Drop the queued rewrite if it has been tbc longer than
    ; k_tbcTypingFixMaxAgeMs. Once that short age budget is exceeded, the user
    ; may already be editing later text and this delayed Send is no longer safe.
    if (tbcHotyRequestedTick && (A_TickCount - tbcHotyRequestedTick) > k_tbcTypingFixMaxAgeMs)
    {
        _ClearTbcHotyState()
        Return
    }

    ; Let the physical key cycle settle before rewriting the prior capital letter.
    if (!_IsDeferredTypingQuiet(40))
    {
        SetTimer, FlushTbcHotyReplacement, -40
        Return
    }

    ; Only allow the queued rewrite when it still belongs to the latest
    ; typing-fix sequence, the same window is still active, the same control
    ; still has focus when we were able to capture one, the exact same control
    ; instance/class still matches when captured, and the queued work is still
    ; within the short freshness budget.
    if (!_IsTbcHotyStillValid())
    {
        _ClearTbcHotyState()
        Return
    }

    ; Classic Edit/RichEdit controls get a precise rewrite: validate that the
    ; text immediately before the caret is still "Capital + current lowercase"
    ; and replace only that prior capital. If that context drifted, cancel
    ; instead of guessing with a blind caret-relative Send.
    if (IsClassicEditControlClass(tbcHotyCtrlClass))
    {
        StopAutoFix := True
        _TryApplyTbcHotyClassicRewrite()
        StopAutoFix := False
        _ClearTbcHotyState()
        Return
    }

    ; Non-classic editors keep the older blind-send fallback because there is no
    ; equally reliable message-based single-character rewrite path available.
    StopAutoFix := True
    Send % "{Left}{BS}" . tbcHotyReplacement . "{Right}"
    StopAutoFix := False
    _ClearTbcHotyState()
Return

; Shared FixSlash queue helper:
; slash+Space and non-classic slash+Enter now follow the same deferred
; queue/idle/validate/apply pattern already used by tbcHoty. The difference
; is that slash+Space lets the real Space land immediately, while slash+Enter
; withholds Enter until the queued slash decision is resolved.
_RequestFixSlash(action) {
    global fixSlashCandidateHasPriorSlash
    global tbcFixSlashAction
    global tbcFixSlashCtrlNN
    global tbcFixSlashCtrlClass
    global tbcFixSlashCtrlHwnd
    global tbcFixSlashHwnd
    global tbcFixSlashId
    global tbcFixSlashRequestedTick
    global typingFixSeq

    if (fixSlashCandidateHasPriorSlash)
        return False

    CancelTbcTypingFixes(False, False)
    typingFixSeq += 1
    tbcFixSlashAction     := action
    CaptureActiveFocusSnapshot(tbcFixSlashHwnd, tbcFixSlashCtrlNN, tbcFixSlashCtrlHwnd, tbcFixSlashCtrlClass)
    tbcFixSlashId         := typingFixSeq
    tbcFixSlashRequestedTick := A_TickCount
    SetTimer, FlushTbcFixSlash, -40
    return True
}

; Record whether the slash just typed follows another slash in the same
; whitespace-delimited string so every FixSlash apply path shares one decision.
_RecordFixSlashCandidate() {
    global fixSlashCandidateHasPriorSlash
    global fixSlashLastSlashStringSeq
    global fixSlashStringBoundarySeq

    fixSlashCandidateHasPriorSlash := (fixSlashLastSlashStringSeq = fixSlashStringBoundarySeq)
    fixSlashLastSlashStringSeq     := fixSlashStringBoundarySeq
}

; Clear slash history when a focus or caret change makes the physical typing
; history unreliable for the newly selected text position.
_ResetFixSlashStringTracking() {
    global fixSlashCandidateHasPriorSlash
    global fixSlashLastSlashStringSeq

    fixSlashCandidateHasPriorSlash := False
    fixSlashLastSlashStringSeq     := -1
}

; Inline slash+Enter fast path for classic edits:
; non-classic editors now defer slash+Enter through the same tbc-work
; pattern as tbcHoty and slash+Space. This helper is kept only for classic
; Edit/RichEdit controls where the old immediate Enter-thread behavior has been
; the lower-risk path.
_CommitFixSlashEnterInline() {
    global StopAutoFix

    settleIdleMs := 30
    settleMaxMs  := 90
    settlePollMs := 5

    slashCommitHwnd := WinExist("A")
    if (!slashCommitHwnd)
        return False

    ControlGetFocus, targetCtrlNN, ahk_id %slashCommitHwnd%
    startTick := A_TickCount

    while (((GetKeyState("Enter", "P") || A_TimeIdlePhysical < settleIdleMs) || StopAutoFix)
        && (A_TickCount - startTick) < settleMaxMs)
        Sleep, %settlePollMs%

    if (StopAutoFix)
        return False

    if (WinExist("A") != slashCommitHwnd)
        return False

    if (targetCtrlNN != "") {
        ControlGetFocus, currentCtrlNN, ahk_id %slashCommitHwnd%
        if (currentCtrlNN != targetCtrlNN)
            return False
    }

    StopAutoFix := True
    Send, % "{BS}{?}{ENTER}"
    StopAutoFix := False
    return True
}

; Returns true only for the exact slash+Enter pattern that FixSlash should own.
; The Enter hotkey uses this shared qualifier first, then decides whether the
; current control can keep the old classic inline fast path or needs the newer
; deferred boundary-key barrier used by non-classic editors.
_ShouldHandleFixSlashEnter() {
    global disableEnter
    global fixSlashCandidateHasPriorSlash
    global k_keys
    global StopAutoFix
    global X_PriorPriorHotKey

    return (disableEnter
         && !IsGoogleDocWindow()
         && !StopAutoFix
         && !fixSlashCandidateHasPriorSlash
         && InStr(k_keys, X_PriorPriorHotKey, False)
         && A_PriorHotKey == "~/"
         && A_ThisHotkey == "$Enter"
         && A_TimeSincePriorHotkey < 999)
}

FixSlash:
    if (!StopAutoFix && A_ThisHotkey == "~/")
        _RecordFixSlashCandidate()

    If !IsGoogleDocWindow() && (!StopAutoFix && IsPriorHotKeyLetterKey()) && A_ThisHotkey == "~/"
        disableEnter := True
    Else If !IsGoogleDocWindow() && (!StopAutoFix && IsThisHotKeyLetterKey())
        disableEnter := False
    ; tooltip, %disableEnter% - %X_PriorPriorHotKey% - %A_PriorHotKey% - %A_ThisHotkey%
    If      (disableEnter && !IsGoogleDocWindow() && (!StopAutoFix && InStr(k_keys, X_PriorPriorHotKey, False) && A_PriorHotKey == "~/" && (A_ThisHotkey == "$~Space" || A_ThisHotkey == "$~+Space") && A_TimeSincePriorHotkey<999)) {
        _RequestFixSlash("space")
        disableEnter              := False
    }
    If IsPriorHotKeyLowerCase()   ; as long as a letter key is pressed we record the priorprior hotkey
        X_PriorPriorHotKey := Substr(A_PriorHotkey,2,1) ; record the letter key pressed
    If IsPriorHotKeyCapital()
        X_PriorPriorHotKey := Substr(A_PriorHotkey,3,1) ; record only the letter key pressed If captialized
Return

; Deferred FixSlash rewrite / boundary-key release:
; tbcHoty, slash+Space, and non-classic slash+Enter now share the same
; broad pattern:
; queue work -> wait for brief physical idle -> revalidate same target ->
; apply precise rewrite when possible, otherwise cancel or use a bounded
; fallback for that editor type
;
; Why this exists:
; immediate slash mutation on a live boundary key can race with:
; - the real punctuation key cycle finishing
; - caret movement caused by the boundary key
; - other typing auto-fix logic already running on the main thread
;
; Timer flow:
; detect slash fix pattern
;         +--> store action + active hwnd + focused control snapshot
;             +--> timer waits for physical idle and StopAutoFix = false
;                 +--> same tbc context still valid?
;                     +--> yes: classic Edit/RichEdit proves live queued slash text and rewrites only slash
;                     +--> yes: non-classic editor uses the older blind-send fallback
;                     +--> yes: queued Enter is released only after that rewrite attempt finishes
;                     +--> no : drop stale rewrite
/*
Example: typing   a / Space
                 ────────
Time (ms)           960       985       1010      1025       1065       1105
                    │         │          │         │          │          │
Physical key         a DOWN    / DOWN     / UP      Space UP   timer      timer
                    │         │                     ▲          callback   callback
                    │         │                     │
                    │         │                     └─ Space itself has already
                    │         │                        reached the target control.
                    │         │
───────────────────────────────────────────────────────────────────────────────────
FixSlash state

X_PriorPriorHotKey   ""        "a"        "a"       "a"        "a"        "a"

disableEnter         false     true       true       false      false      false
                              slash after
                              a letter

fixSlashCandidate
HasPriorSlash        false     false      false      false      false      false
                              first slash in this
                              whitespace-delimited string

A_TimeSincePrior
Hotkey                          0 ms                  40 ms
                                                     slash → Space is under
                                                     the 999 ms limit

tbcFixSlashAction    ""        ""         ""         "space"    "space"    ""
                                                        queued               cleared

tbcFixSlashRequested
Tick                 0         0          0          1025       1025       0

typingFixSeq         41        41         41         42         42         42
                                                        new request token

───────────────────────────────────────────────────────────────────────────────────
/ DOWN at 985
    FixSlash records that this is the first slash in the current string.
    Because its preceding tracked key is a letter, it sets disableEnter := true.

Space DOWN / UP
    $~Space lets the physical Space reach the editor normally.
    FixSlash confirms the slash was the prior hotkey, the prior tracked key was a
    letter, the slash → Space interval is under 999 ms, and this is not a second
    slash in the current whitespace-delimited string.

    _RequestFixSlash("space") stores the target window/control, records the
    request tick, increments typingFixSeq, and schedules FlushTbcFixSlash in 40 ms.

Timer callback
    Replacement is allowed only while the request is at most 250 ms old, physical
    keyboard idle time is at least 40 ms, StopAutoFix is false, the request token
    still matches typingFixSeq, and the original window/control still owns the caret.

    A classic Edit/RichEdit control must also still contain the exact "/ " span at
    its caret. The script then replaces only the slash with "?" and clears the
    queued state. A non-classic editor uses its blind-send fallback instead.

If typing continues before the replacement:

1025                 1065                 1105 ... 1305
queue "/ "           timer sees            keyboard never reaches
                     keyboard active       40 ms idle

                     reschedule ────────> request age exceeds 250 ms
                                           → discard the replacement

For non-classic slash+Enter, the same 999 ms, 40 ms idle, and 250 ms maximum-age
rules apply, except Enter stays withheld until the queued slash rewrite is resolved.
Classic Edit/RichEdit controls use the inline path instead: it polls every 5 ms for
30 ms of physical idleness, up to 90 ms, then sends {BS}{?}{ENTER}.
*/
FlushTbcFixSlash:
    if (!tbcFixSlashAction)
        Return

    tbcAction := tbcFixSlashAction

    ; Drop the queued slash rewrite if it has been tbc longer than
    ; k_tbcTypingFixMaxAgeMs. After that short age budget, skipping the
    ; correction is safer than rewriting text in a newer typing context. For a
    ; queued Enter, release a plain Enter only if the same coarse target is
    ; still active; otherwise cancel it rather than sending Enter somewhere new.
    if (tbcFixSlashRequestedTick && (A_TickCount - tbcFixSlashRequestedTick) > k_tbcTypingFixMaxAgeMs)
    {
        if (tbcAction = "enter")
            _TryReleaseTbcFixSlashEnterFallback()
        _ClearTbcFixSlashState()
        Return
    }

    ; Let the physical boundary-key cycle settle before rewriting slash punctuation.
    if (!_IsDeferredTypingQuiet(40))
    {
        SetTimer, FlushTbcFixSlash, -40
        Return
    }

    ; Only allow the rewrite when this is still the newest queued slash action
    ; and the same focused control identity still owns the caret context.
    if (!_IsTbcFixSlashStillValid())
    {
        if (tbcAction = "enter")
            _TryReleaseTbcFixSlashEnterFallback()
        _ClearTbcFixSlashState()
        Return
    }

    if (tbcAction = "space")
    {
        ; Classic Edit/RichEdit controls get the same phase-2 treatment as
        ; Hoty: prove the live caret/text still show the exact queued "/ "
        ; pattern, then replace only the slash via EM_SETSEL/EM_REPLACESEL. If
        ; proof fails, cancel instead of guessing with a blind caret-relative Send.
        if (IsClassicEditControlClass(tbcFixSlashCtrlClass))
        {
            StopAutoFix := True
            _TryApplyTbcFixSlashClassicRewrite()
            StopAutoFix := False
            _ClearTbcFixSlashState()
            Return
        }

        ; Non-classic editors keep the older blind-send fallback because there is
        ; no equally reliable message-based single-character rewrite path available.
        StopAutoFix := True
        Send, % "{BS}{BS}{?}{SPACE}"
        StopAutoFix := False
        _ClearTbcFixSlashState()
        Return
    }

    if (tbcAction = "enter")
    {
        ; This is the same deferred tbc-work pattern as tbcHoty and
        ; slash+Space, except the boundary key itself is withheld until the
        ; queued slash rewrite has either landed or been explicitly abandoned.
        StopAutoFix := True
        if (IsClassicEditControlClass(tbcFixSlashCtrlClass))
            _TryApplyTbcFixSlashClassicRewrite()
        else {
            Send, % "{BS}{?}"
            Sleep, 15
        }
        Send, {Enter}
        StopAutoFix := False
        _ClearTbcFixSlashState()
        Return
    }

    _ClearTbcFixSlashState()
Return

; Clears the deferred FixSlash slot without invalidating the shared sequence
; token, allowing the caller to decide whether newer timers should also be
; dropped. This now covers both slash+Space rewrites and slash+Enter barriers.
_ClearTbcFixSlashState() {
    global tbcFixSlashAction
    global tbcFixSlashCtrlNN
    global tbcFixSlashCtrlClass
    global tbcFixSlashCtrlHwnd
    global tbcFixSlashHwnd
    global tbcFixSlashId
    global tbcFixSlashRequestedTick

    tbcFixSlashAction     := ""
    tbcFixSlashCtrlNN     := ""
    tbcFixSlashCtrlClass  := ""
    tbcFixSlashCtrlHwnd   := 0
    tbcFixSlashHwnd       := 0
    tbcFixSlashId         := 0
    tbcFixSlashRequestedTick := 0
}

; Clears the deferred capitalization rewrite slot without invalidating the shared
; sequence token, allowing the caller to cancel one slot or both explicitly.
_ClearTbcHotyState() {
    global tbcHotyCtrlNN
    global tbcHotyCtrlClass
    global tbcHotyCtrlHwnd
    global tbcHotyHwnd
    global tbcHotyId
    global tbcHotyRequestedTick
    global tbcHotyReplacement
    global tbcHotyTriggerChar

    tbcHotyCtrlNN      := ""
    tbcHotyCtrlClass   := ""
    tbcHotyCtrlHwnd    := 0
    tbcHotyHwnd        := 0
    tbcHotyId          := 0
    tbcHotyRequestedTick  := 0
    tbcHotyReplacement := ""
    tbcHotyTriggerChar := ""
}

; Cancels deferred typing rewrites and can optionally bump the shared sequence so
; already-scheduled timers know a newer physical action superseded their work.
CancelTbcTypingFixes(invalidateSeq := False, resetDisableEnter := False) {
    global disableEnter
    global typingFixSeq

    if (invalidateSeq)
        typingFixSeq += 1

    _ClearTbcFixSlashState()
    _ClearTbcHotyState()

    if (resetDisableEnter)
        disableEnter := False
}

; Clears an editability decision when a pointer action may have moved focus to a
; different virtual field inside the same outer D3D control. The outer control
; HWND cannot distinguish those fields, so retaining its positive cache entry
; could enable hotstrings in a read-only virtual child.
_ClearTypingAutoFixEligibilityCache() {
    global c_typingAutoFixAllowed
    global c_typingAutoFixCtrlHwnd
    global c_typingAutoFixCtrlNN
    global c_typingAutoFixHwnd
    global c_typingAutoFixReason
    global c_typingAutoFixTick
    global hotstringResetTimerPending
    global hotstringResetAtBoundarySeq

    c_typingAutoFixAllowed                 := false
    c_typingAutoFixCtrlHwnd                := 0
    c_typingAutoFixCtrlNN                  := ""
    c_typingAutoFixHwnd                    := 0
    c_typingAutoFixReason                  := "pointer_context_changed"
    c_typingAutoFixTick                    := 0
    hotstringResetTimerPending             := False
    hotstringResetAtBoundarySeq            := 0
    SetTimer, ResetHotstringBufferAfterBoundary, Off
    Hotstring("Reset")
}

; A pointer action or focus change invalidates queued typing work tied to the
; previous caret or focused control, so discard it before using the new context.
CancelTbcTypingWorkForContextChange() {
    ; Cancel deferred slash/Hoty rewrites and release Enter so old-context work cannot affect the new caret.
    CancelTbcTypingFixes(True, True)
    ; Clear any pending Everything Edit1 auto-fit so it cannot send to a control that is no longer current.
    _ClearTbcEverythingEditAdjustState()
    ; Invalidate cached editability and reset the Hotstring buffer because the active field may have changed.
    _ClearTypingAutoFixEligibilityCache()
    ; Discard the queued eligibility refresh so an old control's result cannot overwrite the new context.
    _ClearTbcTypingAutoFixRefresh()
    ; Forget prior-slash history so text from the previous caret position cannot suppress a valid replacement.
    _ResetFixSlashStringTracking()
    ; Prewarm eligibility for the new focus context so later hotstring checks can use an up-to-date cache.
    _RequestTypingAutoFixPrewarm()
}

; Prewarm the focused-control eligibility cache after startup or a focus/caret
; change. The physical-input snapshots are captured now, before the delayed
; focus lookup, so the async probe can distinguish no typing from a partial word.
_RequestTypingAutoFixPrewarm(delayMs := "") {
    global k_typingAutoFixPrewarmDelayMs
    global hotstringBoundarySeq, physicalTypingSeq
    global typingAutoFixPrewarmStartHotstringBoundarySeq
    global typingAutoFixPrewarmStartTypingSeq

    if (delayMs = "")
        delayMs := k_typingAutoFixPrewarmDelayMs

    typingAutoFixPrewarmStartHotstringBoundarySeq := hotstringBoundarySeq
    typingAutoFixPrewarmStartTypingSeq             := physicalTypingSeq
    SetTimer, PrewarmTypingAutoFixContext, Off
    SetTimer, PrewarmTypingAutoFixContext, % -Max(1, delayMs)
}

; Shared deferred-work focus snapshot:
; capture the active top-level HWND plus the currently focused control identity
; so later timers can cheaply revalidate that they still own the same target
; before attempting any delayed rewrite or synthetic send.
CaptureActiveFocusSnapshot(ByRef targetHwnd, ByRef targetCtrlNN, ByRef targetCtrlHwnd, ByRef targetCtrlClass, activeHwnd := 0) {
    targetHwnd      := 0
    targetCtrlNN    := ""
    targetCtrlHwnd  := 0
    targetCtrlClass := ""

    if (!activeHwnd)
        activeHwnd := WinExist("A")

    if (!activeHwnd)
        return false

    targetHwnd := activeHwnd
    ControlGetFocus, targetCtrlNN, ahk_id %activeHwnd%
    if (targetCtrlNN = "")
        return true

    ControlGet, targetCtrlHwnd, Hwnd,, %targetCtrlNN%, ahk_id %activeHwnd%
    if (!targetCtrlHwnd)
        return true

    WinGetClass, targetCtrlClass, ahk_id %targetCtrlHwnd%
    return true
}

; Shared deferred-work quiet check:
; treat a delayed action as typing-safe only after the physical keyboard has
; been idle for the requested interval and no higher-level typing fix is active.
_IsDeferredTypingQuiet(minIdleMs := 40) {
    global StopAutoFix

    return (!StopAutoFix && A_TimeIdlePhysical >= minIdleMs)
}

; Returns the exact one-shot timer delay needed to reach a quiet threshold.
; Add one millisecond only when the caller requires elapsed time to be greater
; than the threshold; otherwise equality is sufficient. SetTimer receives at
; least one millisecond because zero has control semantics rather than meaning
; "run immediately."
GetRemainingQuietDelayMs(elapsedMs, requiredQuietMs, requireStrictlyGreater := True) {
    boundaryOffsetMs := requireStrictlyGreater ? 1 : 0
    return Max(1, requiredQuietMs - elapsedMs + boundaryOffsetMs)
}

; Shared deferred-work coarse validator:
; require the same active window, optional same focused control name, optional
; same logical request token, and optional freshness window before a delayed
; action is allowed to proceed.
_IsDeferredWorkStillValid(expectedHwnd, expectedCtrlNN := "", expectedId := 0, currentId := 0, requestTick := 0, maxAgeMs := 0) {
    if (!expectedHwnd)
        return false

    if (expectedId && currentId && expectedId != currentId)
        return false

    if (maxAgeMs && requestTick && (A_TickCount - requestTick) > maxAgeMs)
        return false

    if (!WinActive("ahk_id " . expectedHwnd))
        return false

    if (expectedCtrlNN != "")
    {
        ControlGetFocus, currentCtrl, ahk_id %expectedHwnd%
        if (currentCtrl != expectedCtrlNN)
            return false
    }

    return true
}

; Captures the currently focused control identity so deferred typing rewrites can
; require the exact same edit target before they mutate caret-relative text.
TryCaptureActiveFocusSnapshotFull(activeHwnd, ByRef ctrlNN, ByRef ctrlHwnd, ByRef ctrlClass) {
    if !CaptureActiveFocusSnapshot(snapshotHwnd, ctrlNN, ctrlHwnd, ctrlClass, activeHwnd)
        return false

    return (snapshotHwnd && ctrlNN != "" && ctrlHwnd && ctrlClass != "")
}

; Reads the current selection range from a classic Edit/RichEdit control so a
; deferred Hoty flush can verify caret position before issuing EM_REPLACESEL.
_GetClassicControlSelectionRange(controlHwnd, ByRef selStart, ByRef selEnd) {
    static emGetSel := 0x00B0

    selStart := -1
    selEnd := -1
    if !controlHwnd
        return false

    VarSetCapacity(selectionStart, 4, 0)
    VarSetCapacity(selectionEnd, 4, 0)
    DllCall("SendMessage", "Ptr", controlHwnd, "UInt", emGetSel, "Ptr", &selectionStart, "Ptr", &selectionEnd, "Ptr")

    selStart := NumGet(selectionStart, 0, "Int")
    selEnd := NumGet(selectionEnd, 0, "Int")
    return (selStart >= 0 && selEnd >= 0)
}

; Shared tbc typing-fix validator:
; this is the baseline safety check for deferred slash/typing rewrites. It makes
; sure the queued work still belongs to the latest typing-fix sequence, is still
; within the short freshness window, still targets the same active top-level
; window, and still points at the same focused control name when one was captured.
; It is intentionally conservative: if that coarse context no longer matches, the
; delayed rewrite is canceled rather than sent into a newer typing state.
_IsTbcTypingFixStillValid(tbcId, tbcHwnd, tbcCtrl, tbcRequestedTick) {
    global k_tbcTypingFixMaxAgeMs
    global typingFixSeq

    return _IsDeferredWorkStillValid(tbcHwnd, tbcCtrl, tbcId, typingFixSeq, tbcRequestedTick, k_tbcTypingFixMaxAgeMs)
}

; FixSlash tbc-work validator:
; this is the guard that decides whether a queued slash rewrite or slash+Enter
; boundary release is still safe to attempt. It rejects stale or superseded
; work and requires the same active window plus the same focused control identity
; before a delayed rewrite
; can run. The goal is to cancel late fixes rather than let a timer mutate a
; different field/control after the user has already moved on.
_IsTbcFixSlashStillValid() {
    global tbcFixSlashCtrlNN
    global tbcFixSlashCtrlClass
    global tbcFixSlashCtrlHwnd
    global tbcFixSlashHwnd
    global tbcFixSlashId
    global tbcFixSlashRequestedTick

    if !_IsTbcTypingFixStillValid(tbcFixSlashId, tbcFixSlashHwnd, tbcFixSlashCtrlNN, tbcFixSlashRequestedTick)
        return False

    if (!tbcFixSlashCtrlHwnd && tbcFixSlashCtrlClass = "")
        return True

    if !TryCaptureActiveFocusSnapshotFull(tbcFixSlashHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return False

    if (tbcFixSlashCtrlNN != "" && currentCtrlNN != tbcFixSlashCtrlNN)
        return False

    if (tbcFixSlashCtrlHwnd && currentCtrlHwnd != tbcFixSlashCtrlHwnd)
        return False

    if (tbcFixSlashCtrlClass != "" && currentCtrlClass != tbcFixSlashCtrlClass)
        return False

    return True
}

; Coarse slash+Enter fallback:
; if a queued slash+Enter barrier ages out or loses precise slash context, do
; not release Enter into a different window/control. Only send a plain Enter
; when the original active window and focused control name still match.
_TryReleaseTbcFixSlashEnterFallback() {
    global tbcFixSlashCtrlNN
    global tbcFixSlashHwnd
    global StopAutoFix

    if (!tbcFixSlashHwnd || !WinActive("ahk_id " . tbcFixSlashHwnd))
        return False

    if (tbcFixSlashCtrlNN != "")
    {
        ControlGetFocus, currentCtrl, ahk_id %tbcFixSlashHwnd%
        if (currentCtrl != tbcFixSlashCtrlNN)
            return False
    }

    StopAutoFix := True
    Send, {Enter}
    StopAutoFix := False
    return True
}

; Hoty tbc-work validator:
; this is the guard that decides whether a queued Hoty rewrite is still safe to
; attempt. It rejects stale or superseded work and requires the same active
; window plus the same focused control identity before a delayed rewrite can run.
; The goal is to cancel late fixes rather than let a timer mutate a different
; field/control after the user has already moved on.
_IsTbcHotyStillValid() {
    global tbcHotyCtrlNN
    global tbcHotyCtrlClass
    global tbcHotyCtrlHwnd
    global tbcHotyHwnd
    global tbcHotyId
    global tbcHotyRequestedTick

    if !_IsTbcTypingFixStillValid(tbcHotyId, tbcHotyHwnd, tbcHotyCtrlNN, tbcHotyRequestedTick)
        return false

    if (!tbcHotyCtrlHwnd && tbcHotyCtrlClass = "")
        return true

    if !TryCaptureActiveFocusSnapshotFull(tbcHotyHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return false

    if (tbcHotyCtrlNN != "" && currentCtrlNN != tbcHotyCtrlNN)
        return false

    if (tbcHotyCtrlHwnd && currentCtrlHwnd != tbcHotyCtrlHwnd)
        return false

    if (tbcHotyCtrlClass != "" && currentCtrlClass != tbcHotyCtrlClass)
        return false

    return true
}

; Classic-control FixSlash rewrite:
; for Edit/RichEdit targets, do not trust a blind slash rewrite send. Instead,
; inspect the live caret/selection and confirm the exact expected queued slash
; pattern is still present immediately before the caret, then replace only the
; slash with EM_SETSEL/EM_REPLACESEL. If that context no longer matches, cancel
; the fix rather than risk a duplicate or garbled edit.
_TryApplyTbcFixSlashClassicRewrite() {
    static emReplaceSel := 0x00C2
    static emSetSel := 0x00B1
    global tbcFixSlashAction
    global tbcFixSlashCtrlNN
    global tbcFixSlashCtrlClass
    global tbcFixSlashCtrlHwnd
    global tbcFixSlashHwnd

    if (!tbcFixSlashHwnd || !tbcFixSlashCtrlHwnd || tbcFixSlashCtrlClass = "")
        return False

    if !IsClassicEditControlClass(tbcFixSlashCtrlClass)
        return False

    if !TryCaptureActiveFocusSnapshotFull(tbcFixSlashHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return False

    if (currentCtrlNN != tbcFixSlashCtrlNN || currentCtrlHwnd != tbcFixSlashCtrlHwnd || currentCtrlClass != tbcFixSlashCtrlClass)
        return False

    if !_GetClassicControlSelectionRange(tbcFixSlashCtrlHwnd, selStart, selEnd)
        return False

    if (selStart != selEnd)
        return False

    ControlGetText, controlText, , ahk_id %tbcFixSlashCtrlHwnd%
    if (controlText = "" || StrLen(controlText) < selStart)
        return False

    if (tbcFixSlashAction = "space")
    {
        if (selStart < 2)
            return False

        observedSpan := SubStr(controlText, selStart - 1, 2)
        if (observedSpan != "/ ")
            return False

        replaceStart := selStart - 2
        replaceEnd := selStart - 1
        restoreCaretPos := selStart
    }
    else if (tbcFixSlashAction = "enter")
    {
        if (selStart < 1)
            return False

        observedChar := SubStr(controlText, selStart, 1)
        if (observedChar != "/")
            return False

        replaceStart := selStart - 1
        replaceEnd := selStart
        restoreCaretPos := selStart
    }
    else
        return False

    VarSetCapacity(replacementBuffer, (StrLen("?") + 1) * 2, 0)
    StrPut("?", &replacementBuffer, "UTF-16")

    DllCall("SendMessage", "Ptr", tbcFixSlashCtrlHwnd, "UInt", emSetSel, "Ptr", replaceStart, "Ptr", replaceEnd, "Ptr")
    DllCall("SendMessage", "Ptr", tbcFixSlashCtrlHwnd, "UInt", emReplaceSel, "Ptr", 1, "Ptr", &replacementBuffer, "Ptr")
    DllCall("SendMessage", "Ptr", tbcFixSlashCtrlHwnd, "UInt", emSetSel, "Ptr", restoreCaretPos, "Ptr", restoreCaretPos, "Ptr")
    return True
}

; Classic-control Hoty rewrite:
; for Edit/RichEdit targets, do not trust a blind {Left}{BS}...{Right} send.
; Instead, inspect the live caret/selection and confirm the exact expected text
; pattern is still present immediately before the caret, then replace only the
; prior capital with EM_SETSEL/EM_REPLACESEL. If that context no longer matches,
; cancel the fix rather than risk a duplicate or garbled edit.
_TryApplyTbcHotyClassicRewrite() {
    static emReplaceSel := 0x00C2
    static emSetSel := 0x00B1
    global tbcHotyCtrlNN
    global tbcHotyCtrlClass
    global tbcHotyCtrlHwnd
    global tbcHotyHwnd
    global tbcHotyReplacement
    global tbcHotyTriggerChar

    if (!tbcHotyHwnd || !tbcHotyCtrlHwnd || tbcHotyCtrlClass = "")
        return false

    if !IsClassicEditControlClass(tbcHotyCtrlClass)
        return false

    if !TryCaptureActiveFocusSnapshotFull(tbcHotyHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return false

    if (currentCtrlNN != tbcHotyCtrlNN || currentCtrlHwnd != tbcHotyCtrlHwnd || currentCtrlClass != tbcHotyCtrlClass)
        return false

    if !_GetClassicControlSelectionRange(tbcHotyCtrlHwnd, selStart, selEnd)
        return false

    if (selStart != selEnd || selStart < 2)
        return false

    ControlGetText, controlText, , ahk_id %tbcHotyCtrlHwnd%
    if (controlText = "" || StrLen(controlText) < selStart)
        return false

    expectedPriorChar := tbcHotyReplacement
    StringUpper, expectedPriorChar, expectedPriorChar
    expectedSpan      := expectedPriorChar . tbcHotyTriggerChar
    observedSpan      := SubStr(controlText, selStart - 1, 2)
    if (observedSpan != expectedSpan)
        return false

    VarSetCapacity(replacementBuffer, (StrLen(tbcHotyReplacement) + 1) * 2, 0)
    StrPut(tbcHotyReplacement, &replacementBuffer, "UTF-16")

    DllCall("SendMessage", "Ptr", tbcHotyCtrlHwnd, "UInt", emSetSel, "Ptr", selStart - 2, "Ptr", selStart - 1, "Ptr")
    DllCall("SendMessage", "Ptr", tbcHotyCtrlHwnd, "UInt", emReplaceSel, "Ptr", 1, "Ptr", &replacementBuffer, "Ptr")
    DllCall("SendMessage", "Ptr", tbcHotyCtrlHwnd, "UInt", emSetSel, "Ptr", selStart, "Ptr", selStart, "Ptr")
    return true
}

IsPriorHotKeyLetterKey() {
    Return (IsPriorHotKeyCapital() || IsPriorHotKeyLowerCase())
}
IsThisHotKeyLetterKey() {
    Return (IsThisHotKeyCapital() || IsThisHotKeyLowerCase())
}
IsPriorHotKeyCapital() {
    global k_keys
    Return (StrLen(A_PriorHotkey) == 3 && SubStr(A_PriorHotKey,1,1)!="!" && SubStr(A_PriorHotKey,2,1)="+" && InStr(k_keys, Substr(A_PriorHotkey,3,1), False))
}
IsPriorHotKeyLowerCase() {
    global k_keys
    Return (StrLen(A_PriorHotkey) == 2 && InStr(k_keys, Substr(A_PriorHotkey,2,1), False))
}
IsThisHotKeyCapital() {
    global k_keys
    Return (StrLen(A_ThisHotKey) == 3 && SubStr(A_ThisHotKey,1,1)!="!" && SubStr(A_ThisHotKey,2,1)="+" && InStr(k_keys, Substr(A_ThisHotKey,3,1), False))
}
IsThisHotKeyLowerCase() {
    global k_keys
    Return (StrLen(A_ThisHotKey) == 2 && InStr(k_keys, Substr(A_ThisHotKey,2,1), False))
}

DoNothing() {
    Return
}

; --------------------------------------------------
; Unhook on exit
; --------------------------------------------------
UnhookHooks:
    global gExiting
    global StopRecursion
    global hActWin, hHookKbd, hHookMouse

    if (gExiting) {
        return
    }

    gExiting      := True
    StopRecursion := True
    Thread, NoTimers, True

    if (hActWin) {
        DllCall("user32\UnhookWinEvent", "Ptr", hActWin)
        hActWin := 0
    }

    if (hHookKbd) {
        DllCall("user32\UnhookWindowsHookEx", "Ptr", hHookKbd)
        hHookKbd := 0
    }

    if (hHookMouse) {
        DllCall("user32\UnhookWindowsHookEx", "Ptr", hHookMouse)
        hHookMouse := 0
    }

    ; --- Release UIA/COM objects before COM teardown ---
    global UIA, comInitd
    UIA := ""  ; drop UIA COM refs first

    ; --- Balance our manual CoInitializeEx call ---
    ; InitCOM_STA() sets comInitd := 2 (S_OK) or 1 (S_FALSE) on success.
    if (comInitd = 1 || comInitd = 2) {
        DllCall("ole32\CoUninitialize")
        comInitd := ""  ; prevent double-uninit on repeated exit paths
    }
    ; IMPORTANT: Do NOT call FreeLibrary on VirtualDesktopAccessor here; it can hang on Win11.
return

$~^Enter::
    DetectHiddenWindows, Off
    WinGet, myWindow, List
    Loop, %myWindow%
    {
        ControlGet, myOkay, Hwnd,, OK, % "ahk_id " myWindow%A_Index%
        If (myOkay) {
            ControlClick,, ahk_id %myOkay%,,,2
            hwndID := "ahk_id " myWindow%A_Index%
            sleep, 400
            If WinExist(hwndID)
                Send, !{o}
            break
        }
    }
Return

;===============================================================
;    Neuter Win Key Combos!!
;===============================================================
LWin & WheelUp::Send {Volume_Up}
LWin & WheelDown::Send {Volume_Down}
RWin & WheelUp::Send {Volume_Up}
RWin & WheelDown::Send {Volume_Down}

LWin::Return
RWin::Return

; --- Allow only volume control while Win is held ---
#If GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
; Block common keys while either Win key is held
*a::Return
*b::Return
*c::Return
*d::Return
*e::Return
*f::Return
*g::Return
*h::Return
*i::Return
*j::Return
*k::Return
*l::Return
*m::Return
*n::Return
*o::Return
*p::Return
*q::Return
*r::Return
*s::Return
*t::Return
*u::Return
*v::Return
*w::Return
*x::Return
*y::Return
*z::Return
#If
;================================================================
#If (!WinActive("ahk_exe notepad++.exe") && !WinActive("ahk_exe Everything.exe") && !WinActive("ahk_exe Code.exe") && !WinActive("ahk_exe EXCEL.EXE") && !IsEditFieldActive())
^+d::
    if (WinExist("ahk_class rctrl_renwnd32") && ControlExist("OOCWindow1", "ahk_class rctrl_renwnd32")) {
        Send, {Esc}
    }

    ctrlShiftDModifierTargetHwnd := DllCall("user32\GetForegroundWindow", "Ptr")
    Critical, On
    StopAutoFix                 := True
    caretRectKeyBeforeMove      := ""
    try {
        ; Let the trigger key finish before entering blocked mode so held modifiers
        ; can remain down while repeated D taps still retrigger the hotkey cleanly.
        KeyWait, d, T0.25
        BeginBlockKeys()

        ; Keep the trigger's held Ctrl+Shift logically released during the edit
        ; burst so plain navigation/Delete cannot inherit them between sends.
        GetActiveCaretRectKey(caretRectKeyBeforeMove)
        Send, {Ctrl Up}{Shift Up}{Down}
        WaitForActiveCaretRectChangeAndSettle(caretRectKeyBeforeMove, 35, 2, 10)
        GetActiveCaretRectKey(caretRectKeyBeforeMove)
        Send, {Ctrl Up}{Shift Up}{Home}{Home}
        WaitForActiveCaretRectChangeAndSettle(caretRectKeyBeforeMove, 35, 2, 10)
        GetActiveCaretRectKey(caretRectKeyBeforeMove)
        ; Use explicit Shift down/up pairs instead of +{Up}/+{Home} so the
        ; synthetic selection does not leave Shift logically stuck afterward.
        Send, {Ctrl Up}{Shift Down}{Up}{Shift Up}
        WaitForActiveCaretRectChangeAndSettle(caretRectKeyBeforeMove, 35, 2, 10)
        GetActiveCaretRectKey(caretRectKeyBeforeMove)
        Send, {Ctrl Up}{Shift Down}{Home}{Shift Up}
        ; Send, {End}
        ; Send, +{Home}+{Home}+{Home}
        WaitForActiveCaretRectChangeAndSettle(caretRectKeyBeforeMove, 35, 2, 10)
        Send, {Ctrl Up}{Shift Up}{Delete}

        ; Your environment reset
        Hotstring("Reset")
    } finally {
        ; Always release the input guard and repair every modifier family this
        ; hotkey explicitly releases, even if navigation or caret work fails.
        EndBlockKeys()
        StopAutoFix := False
        try {
            SyncModifierSidesToPhys("Shift Alt Ctrl", ctrlShiftDModifierTargetHwnd)
            ScheduleModifierSync("Shift Alt Ctrl", 6, ctrlShiftDModifierTargetHwnd)
        } finally {
            Critical, Off
        }
    }
Return

^d::
    if (WinExist("ahk_class rctrl_renwnd32") && ControlExist("OOCWindow1", "ahk_class rctrl_renwnd32")) {
        Send, {Esc}
    }

    ctrlDModifierTargetHwnd     := DllCall("user32\GetForegroundWindow", "Ptr")
    Critical, On
    StopAutoFix                 := True
    caretRectKeyBeforeMove      := ""
    try {
        ; If there's no caret (e.g., not in a text field), pass through native Ctrl+D.
        if (A_CaretX = "")
        {
            StopAutoFix := False
            Critical, Off
            Send ^d
            Return
        }
        ; Let the trigger key finish before entering blocked mode so held Ctrl can
        ; remain down while repeated D taps still retrigger the hotkey cleanly.
        KeyWait, d, T0.25
        BeginBlockKeys()

        didFastInsert                  := False
        didRestoreCaretWithMessages    := False
        fastInsertControlHwnd          := 0
        fastInsertResult               := "target_gone"
        fastInsertWindowId             := DllCall("user32\GetForegroundWindow", "Ptr")
        originalFastInsertLineStartIdx := -1
        if (_GetFastInsertWrappedTextTarget(fastInsertWindowId, fastInsertControlHwnd) = "classic_edit")
            ; Save the exact original line-start index so the fast message-based
            ; insert path can put the caret back on that same logical line later.
            _GetCurrentLineStartIndexInClassicControl(fastInsertWindowId, fastInsertControlHwnd, originalFastInsertLineStartIdx)

        ; 1) Go to absolute start of the line and select it with one plain-navigation
        ; burst so held Ctrl cannot slip back in between the selection keys.
        GetActiveCaretRectKey(caretRectKeyBeforeMove)
        Send, {Ctrl Up}{Home}{Home}{Shift Down}{End}{Shift Up}
        EndBlockKeys()
        SyncModifierSidesToPhys("Ctrl", ctrlDModifierTargetHwnd)
        WaitForActiveCaretRectChangeAndSettle(caretRectKeyBeforeMove, 35, 2, 10)

        ; 2) Copy the line text via your clipboard-safe helper
        lineText                    := Clip("", "", "", "Shift Alt Ctrl Win", fastInsertWindowId)   ; returns the copied text, clipboard will auto-restore later
        if (lineText = "")
        {
            ; Abort before the Enter step if selection/copy failed so this hotkey
            ; does not degrade into inserting blank lines on repeated presses.
            Clip("", "", "RESTORE")
            Hotstring("Reset")
            Return
        }

        ; 3) Insert a newline and paste the duplicate line BELOW
        BeginBlockKeys()
        GetActiveCaretRectKey(caretRectKeyBeforeMove)
        Send, {Ctrl Up}{End}{Enter}{Shift Down}{Home}{Shift Up}
        EndBlockKeys()
        SyncModifierSidesToPhys("Ctrl", ctrlDModifierTargetHwnd)
        WaitForActiveCaretRectChangeAndSettle(caretRectKeyBeforeMove, 90, 2, 60)
        GetActiveCaretRectKey(caretRectKeyBeforeMove)
        if (fastInsertControlHwnd)
            fastInsertResult := _FastInsertWrappedTextIntoClassicControl(fastInsertWindowId, fastInsertControlHwnd, lineText)

        didFastInsert := (fastInsertResult = "inserted")
        if (!didFastInsert && fastInsertResult != "message_uncertain" && IsForegroundWindow(fastInsertWindowId))
        {
            ; Some editors are picky about paste timing/chords here, so force the
            ; clipboard helper onto the stricter explicit Ctrl+V path for this step.
            ; A timed-out EM_REPLACESEL is deliberately excluded: it might have
            ; completed just before SendMessageTimeoutW returned, so Ctrl+V could
            ; duplicate the line.
            clipPreferExplicitCtrlV := True
            try {
                Clip(lineText, "", "", "Shift Alt Ctrl Win", fastInsertWindowId)
            } finally {
                clipPreferExplicitCtrlV := False
            }
        }
        WaitForActiveCaretRectChangeAndSettle(caretRectKeyBeforeMove, 90, 2, 30)
        if (didFastInsert && originalFastInsertLineStartIdx >= 0)
            ; After a fast EM_REPLACESEL insert, restore directly to the saved line
            ; start instead of trying to infer the original position by keystrokes.
            didRestoreCaretWithMessages := _MoveCaretToIndexInClassicControl(fastInsertWindowId, fastInsertControlHwnd, originalFastInsertLineStartIdx)

        ; 4) Return caret to the original line at column 1 (reliably cross-editor)
        if !didRestoreCaretWithMessages
        {
            BeginBlockKeys()
            GetActiveCaretRectKey(caretRectKeyBeforeMove)
            Send, {Ctrl Up}{Up} ; {Home}{Home}
            EndBlockKeys()
            SyncModifierSidesToPhys("Ctrl", ctrlDModifierTargetHwnd)
            WaitForActiveCaretRectChangeAndSettle(caretRectKeyBeforeMove, 60, 2, 100)
        }
        ; Optional                  : if you prefer immediate clipboard restore instead of the ~700ms timer, uncomment:
        ; Clip("", "", "RESTORE")

        ; Your environment reset
        Hotstring("Reset")
    } finally {
        ; This finalizer covers every early return and any unexpected failure in
        ; focus, clipboard, caret, or direct-control work.
        EndBlockKeys()
        StopAutoFix := False
        try {
            SyncModifierSidesToPhys("Shift Alt Ctrl", ctrlDModifierTargetHwnd)
            ScheduleModifierSync("Shift Alt Ctrl", 6, ctrlDModifierTargetHwnd)
        } finally {
            Critical, Off
        }
    }
Return

#If

ControlExist(ctrlNN, winTitle := "", winText := "") {
    ControlGet, hCtl, Hwnd,, %ctrlNN%, %winTitle%, %winText%
    Return !!hCtl
}

; Replaces the current selection in a still-focused classic Edit/RichEdit HWND
; using a bounded message send. Returns "inserted", "not_classic", "target_gone",
; or "message_uncertain". The last state must not fall back to Ctrl+V because the
; target may have processed EM_REPLACESEL just before the timeout was reported.
_FastInsertWrappedTextIntoClassicControl(windowId, controlHwnd, text) {
    static emReplaceSel := 0x00C2
    static smtoAbortIfHung := 0x0002

    if !_IsExpectedFocusedControl(windowId, controlHwnd)
        return "target_gone"

    replacementText := StrReplace(text, "`r")
    replacementText := StrReplace(replacementText, "`n", "`r`n")

    VarSetCapacity(replacementBuffer, (StrLen(replacementText) + 1) * 2, 0)
    StrPut(replacementText, &replacementBuffer, "UTF-16")

    ; Bound the message send to 250 ms. A zero result does not tell us whether
    ; EM_REPLACESEL ran, so callers treat it as "message_uncertain" and never
    ; follow it with a Ctrl+V fallback.
    messageResult := 0
    return DllCall("user32\SendMessageTimeoutW"
        , "Ptr", controlHwnd
        , "UInt", emReplaceSel
        , "Ptr", 1
        , "Ptr", &replacementBuffer
        , "UInt", smtoAbortIfHung
        , "UInt", 250
        , "Ptr*", messageResult
        , "Ptr") ? "inserted" : "message_uncertain"
}

; Resolves the originally active window's focused target without using a
; ClassNN. Custom GPU controls such as Intermediate D3D Window are classified
; as not_classic and use the managed clipboard path instead of EM_REPLACESEL.
_GetFastInsertWrappedTextTarget(windowId, ByRef controlHwnd) {
    controlHwnd := 0
    if !IsForegroundWindow(windowId)
        return "target_gone"

    windowTid := DllCall("user32\GetWindowThreadProcessId", "Ptr", windowId, "UInt*", 0, "UInt")
    if !windowTid
        return "target_gone"

    focusedHwnd := GetThreadFocusHwnd(windowTid)
    if !focusedHwnd
        return "target_gone"

    if !DllCall("user32\IsWindow", "Ptr", focusedHwnd, "Int")
        return "target_gone"

    if (focusedHwnd != windowId && !DllCall("user32\IsChild", "Ptr", windowId, "Ptr", focusedHwnd, "Int"))
        return "target_gone"

    if !IsForegroundWindow(windowId)
        return "target_gone"

    controlHwnd := focusedHwnd
    controlClassName := GetWindowClassName(controlHwnd)
    if !_IsExpectedFocusedControl(windowId, controlHwnd)
        return "target_gone"

    return IsClassicEditControlClass(controlClassName) ? "classic_edit" : "not_classic"
}

_TryGetBCompareTextEditorControl(windowId, ByRef controlHwnd) {
    controlHwnd := 0
    if !IsWindowProcessName(windowId, "BCompare.exe")
        return false

    targetState := _GetFastInsertWrappedTextTarget(windowId, controlHwnd)
    controlClass := controlHwnd ? GetWindowClassName(controlHwnd) : ""
    WrapDebugLog("bcompare controlsend targetState=" . targetState . " controlHwnd=" . controlHwnd . " controlClass=" . controlClass . " hwnd=" . windowId)
    return (targetState = "not_classic" && controlHwnd && controlClass = "TTextEditor")
}
; Asks the currently focused child control to copy its selection without using a
; keyboard shortcut. This is used only after keyboard-copy paths fail.
_TryCopyFocusedControlSelectionWithWmCopy(windowId) {
    static WM_COPY := 0x0301
    static SMTO_ABORTIFHUNG_AND_BLOCK := 0x0003

    targetState := _GetFastInsertWrappedTextTarget(windowId, controlHwnd)
    controlClass := controlHwnd ? GetWindowClassName(controlHwnd) : ""
    WrapDebugLog("clip_read retry=wm_copy targetState=" . targetState . " controlHwnd=" . controlHwnd . " controlClass=" . controlClass . " hwnd=" . windowId)
    if (targetState = "target_gone" || !controlHwnd)
        return false

    if !IsForegroundWindow(windowId)
        return false

    messageResult := 0
    sent := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", controlHwnd
        , "UInt", WM_COPY
        , "Ptr", 0
        , "Ptr", 0
        , "UInt", SMTO_ABORTIFHUNG_AND_BLOCK
        , "UInt", 250
        , "Ptr*", messageResult
        , "Ptr")
    WrapDebugLog("clip_read wm_copy sent=" . sent . " messageResult=" . messageResult . " controlClass=" . controlClass . " hwnd=" . windowId)
    return !!sent
}
; Captures the exact logical line-start caret index in a classic Edit/RichEdit
; control so later restoration can return to the original line precisely.
_GetCurrentLineStartIndexInClassicControl(windowId, controlHwnd, ByRef lineStartIndex) {
    static emGetSel       := 0x00B0
    static emLineFromChar := 0x00C9
    static emLineIndex    := 0x00BB
    lineStartIndex        := -1

    if !_IsExpectedFocusedControl(windowId, controlHwnd)
        return false

    VarSetCapacity(selectionStart, 4, 0)
    VarSetCapacity(selectionEnd, 4, 0)
    DllCall("SendMessage", "Ptr", controlHwnd, "UInt", emGetSel, "Ptr", &selectionStart, "Ptr", &selectionEnd, "Ptr")

    caretIndex := NumGet(selectionStart, 0, "Int")
    if (caretIndex < 0)
        return false

    currentLineNumber := DllCall("SendMessage", "Ptr", controlHwnd, "UInt", emLineFromChar, "Ptr", caretIndex, "Ptr", 0, "Int")
    if (currentLineNumber < 0)
        return false

    lineStartIndex := DllCall("SendMessage", "Ptr", controlHwnd, "UInt", emLineIndex, "Ptr", currentLineNumber, "Ptr", 0, "Int")
    if (lineStartIndex < 0)
        return false

    return true
}

; Moves the caret to an exact character index in a classic Edit/RichEdit
; control after a synchronous EM_REPLACESEL insertion.
_MoveCaretToIndexInClassicControl(windowId, controlHwnd, caretIndex) {
    static emSetSel := 0x00B1

    if (caretIndex < 0)
        return false

    if !_IsExpectedFocusedControl(windowId, controlHwnd)
        return false

    DllCall("SendMessage", "Ptr", controlHwnd, "UInt", emSetSel, "Ptr", caretIndex, "Ptr", caretIndex, "Ptr")
    return true
}

; Reads a Win32 window class without a ClassNN lookup, which can become stale
; while a custom control is rebuilding its child-window hierarchy.
GetWindowClassName(windowHwnd) {

    if (!windowHwnd || !DllCall("user32\IsWindow", "Ptr", windowHwnd, "Int"))
        return ""

    VarSetCapacity(className, 512 * 2, 0)
    if !DllCall("user32\GetClassNameW", "Ptr", windowHwnd, "Ptr", &className, "Int", 512, "Int")
        return ""

    return StrGet(&className, "UTF-16")
}

; Verifies that the captured top-level target is still foreground and that the
; same child HWND still owns keyboard focus before a direct edit message runs.
_IsExpectedFocusedControl(windowId, controlHwnd) {
    if (!IsForegroundWindow(windowId) || !controlHwnd)
        return false

    if !DllCall("user32\IsWindow", "Ptr", controlHwnd, "Int")
        return false

    if (controlHwnd != windowId && !DllCall("user32\IsChild", "Ptr", windowId, "Ptr", controlHwnd, "Int"))
        return false

    windowTid := DllCall("user32\GetWindowThreadProcessId", "Ptr", windowId, "UInt*", 0, "UInt")
    return (windowTid && GetThreadFocusHwnd(windowTid) = controlHwnd)
}

; Returns true for standard Win32 Edit and RichEdit window classes that support
; the EM_GETSEL, EM_SETSEL, and EM_REPLACESEL operations used by direct classic-
; control rewrites and fast insertion.
IsClassicEditControlClass(controlClassName) {
    return (controlClassName = "Edit" || RegExMatch(controlClassName, "i)^RICHEDIT\w*$"))
}

; Confirms that a clipboard chord will still go to the captured foreground
; window. A different foreground HWND means the operation must be cancelled.
IsForegroundWindow(windowId) {
    return (windowId && DllCall("user32\IsWindow", "Ptr", windowId, "Int")
        && DllCall("user32\GetForegroundWindow", "Ptr") = windowId)
}

IsWindowClassName(windowId, className) {
    if (!windowId || className = "")
        return false

    try
        WinGetClass, windowClassName, ahk_id %windowId%
    catch
        return false

    return (windowClassName = className)
}

GetWindowProcessName(windowId) {
    if (!windowId)
        return ""

    try
        WinGet, windowProcessName, ProcessName, ahk_id %windowId%
    catch
        return ""

    return windowProcessName
}

IsWindowProcessName(windowId, processName) {
    return (processName != "" && GetWindowProcessName(windowId) = processName)
}

WrapDebugLog(message) {
    global allDebugLoggingEnabled, wrapDebugEnabled, wrapDebugLogPath

    if (!allDebugLoggingEnabled || !wrapDebugEnabled)
        return

    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    line := stamp . " " . message . "`n"
    try {
        FileAppend, %line%, %wrapDebugLogPath%
    } catch e {
    }
}

ClipjumpApiCall(functionName, param1 := "") {
    code := "API:" . functionName
    if (param1 != "")
        code .= "`r" . param1

    result := ClipjumpSendCopyData(code)
    WrapDebugLog("clipjump api=" . functionName . " param=" . param1 . " result=" . result)
    return result
}

ClipjumpFindWindowId() {
    local prevDetectHiddenWindows, prevTitleMatchMode, windowList, hwnd, title, processName

    prevDetectHiddenWindows := A_DetectHiddenWindows
    prevTitleMatchMode := A_TitleMatchMode
    DetectHiddenWindows, On
    SetTitleMatchMode, 2

    WinGet, windowList, List, ahk_class AutoHotkey
    Loop, %windowList% {
        hwnd := windowList%A_Index%
        WinGetTitle, title, ahk_id %hwnd%
        WinGet, processName, ProcessName, ahk_id %hwnd%
        if (processName = "Clipjump.exe" || InStr(title, "\Clipjump.exe") || InStr(title, "\Clipjump.ahk") || InStr(title, "Clipjump.exe -") || InStr(title, "Clipjump.ahk -")) {
            DetectHiddenWindows, %prevDetectHiddenWindows%
            SetTitleMatchMode, %prevTitleMatchMode%
            WrapDebugLog("clipjump target hwnd=" . hwnd . " title=" . title . " process=" . processName)
            return hwnd
        }
    }

    DetectHiddenWindows, %prevDetectHiddenWindows%
    SetTitleMatchMode, %prevTitleMatchMode%
    WrapDebugLog("clipjump target not_found")
    return 0
}

ClipjumpSendCopyData(ByRef code) {
    local clipjumpWindowId, copyDataStruct, prevDetectHiddenWindows, prevTitleMatchMode, sendResult, waitStartTick, ackPath

    clipjumpWindowId := ClipjumpFindWindowId()
    if (!clipjumpWindowId)
        return -1

    ackPath := A_Temp . "\clipjumpcom.txt"
    FileDelete, %ackPath%

    VarSetCapacity(copyDataStruct, 3*A_PtrSize, 0)
    sizeInBytes := (StrLen(code) + 1) * (A_IsUnicode ? 2 : 1)
    NumPut(sizeInBytes, copyDataStruct, A_PtrSize)
    NumPut(&code, copyDataStruct, 2*A_PtrSize)

    prevDetectHiddenWindows := A_DetectHiddenWindows
    prevTitleMatchMode := A_TitleMatchMode
    DetectHiddenWindows, On
    SetTitleMatchMode, 2

    SendMessage, 0x4a, 0, &copyDataStruct,, ahk_id %clipjumpWindowId%,,,, 250
    sendResult := ErrorLevel

    DetectHiddenWindows, %prevDetectHiddenWindows%
    SetTitleMatchMode, %prevTitleMatchMode%

    if (sendResult = "FAIL") {
        WrapDebugLog("clipjump send failed hwnd=" . clipjumpWindowId)
        return -1
    }

    waitStartTick := A_TickCount
    while (!FileExist(ackPath) && (A_TickCount - waitStartTick < 1000))
        Sleep, 25

    if (!FileExist(ackPath)) {
        WrapDebugLog("clipjump send ack_timeout hwnd=" . clipjumpWindowId . " sendResult=" . sendResult)
        return -1
    }

    FileDelete, %ackPath%
    return 1
}
ClipjumpApiGetVar(varName) {
    returnPath := A_Temp . "\cjcb.txt"
    FileDelete, %returnPath%

    result := ClipjumpApiCall("getVar", varName)
    if (result != 1) {
        WrapDebugLog("clipjump getvar fail var=" . varName . " result=" . result)
        return ""
    }

    waitStartTick := A_TickCount
    while (!FileExist(returnPath) && (A_TickCount - waitStartTick < 300))
        Sleep, 10

    if (!FileExist(returnPath)) {
        WrapDebugLog("clipjump getvar fail var=" . varName . " reason=no_return_file")
        return ""
    }

    FileRead, returnValue, %returnPath%
    FileDelete, %returnPath%
    returnValue := Trim(returnValue, "`r`n`t ")
    WrapDebugLog("clipjump getvar var=" . varName . " value=" . returnValue)
    return returnValue
}

ClipjumpPauseForWrapper() {
    global clipjumpWrapperPaused

    clipjumpWrapperPaused := False
    status := ClipjumpApiGetVar("CLIPJUMP_STATUS")
    if (status = "0") {
        WrapDebugLog("clipjump pause skipped reason=already_disabled")
        return
    }

    if (ClipjumpApiCall("disable", "1") = 1) {
        clipjumpWrapperPaused := True
        WrapDebugLog("clipjump pause ok priorStatus=" . (status = "" ? "unknown" : status))
    } else {
        WrapDebugLog("clipjump pause failed priorStatus=" . (status = "" ? "unknown" : status))
    }
}

ClipjumpRestoreAfterWrapper() {
    global clipjumpWrapperPaused

    if (!clipjumpWrapperPaused)
        return

    clipjumpWrapperPaused := False
    result := ClipjumpApiCall("disable", "0")
    WrapDebugLog("clipjump restore result=" . result)
}


_WaitForWrapperTriggerRelease(timeoutSeconds := 0.12) {
    startTick := A_TickCount
    waitOptions := "T" . timeoutSeconds

    KeyWait, LAlt, %waitOptions%
    KeyWait, RAlt, %waitOptions%
    KeyWait, LShift, %waitOptions%
    KeyWait, RShift, %waitOptions%

    elapsedMs := A_TickCount - startTick
    altDown   := (GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P")) ? 1 : 0
    shiftDown := (GetKeyState("LShift", "P") || GetKeyState("RShift", "P")) ? 1 : 0
    WrapDebugLog("release_wait hotkey=" . A_ThisHotkey . " elapsedMs=" . elapsedMs . " altDown=" . altDown . " shiftDown=" . shiftDown)
}
_IsUIASelectedTextTarget(windowId) {
    return (IsWindowClassName(windowId, "MozillaWindowClass")
        || IsWindowProcessName(windowId, "notepad.exe"))
}
; Auto-fit Everything's native results ListView without changing keyboard focus
; or injecting Ctrl+NumpadAdd into the live search-box typing stream.
_TryAutoFitEverythingResultsColumns(everythingHwnd, mode := "header_no_fill") {
    if (!everythingHwnd || !IsForegroundWindow(everythingHwnd))
        return False

    try {
        ControlGet, listViewHwnd, Hwnd,, SysListView321, ahk_id %everythingHwnd%
    } catch {
        return False
    }
    if (!listViewHwnd || !DllCall("user32\IsChild", "Ptr", everythingHwnd, "Ptr", listViewHwnd, "Int"))
        return False

    return AutoFitSysListViewColumns(listViewHwnd, mode)
}

; Auto-fit every column in a native SysListView32 report view without requiring
; keyboard focus. Mode "content" uses LVSCW_AUTOSIZE; mode "header" uses
; LVSCW_AUTOSIZE_USEHEADER, including its final-column fill behavior. Mode
; "header_no_fill" uses header sizing except for the final column, where content
; sizing prevents Windows from stretching that column across the remaining width.
; Every cross-process message has a short timeout so an unresponsive target cannot
; hang this script. True means all columns accepted the requested width; False lets
; callers use their existing keyboard fallback.
AutoFitSysListViewColumns(listViewHwnd, mode := "header_no_fill", timeoutMs := 75) {
    static HDM_GETITEMCOUNT           := 0x1200
    static LVM_GETHEADER              := 0x101F
    static LVM_GETCOLUMNWIDTH         := 0x101D
    static LVM_SETCOLUMNWIDTH         := 0x101E
    ; Size a column to the widest text in its item contents.
    static LVSCW_AUTOSIZE             := -1
    ; Size a column to its header text; the final column may fill remaining space.
    static LVSCW_AUTOSIZE_USEHEADER   := -2
    static SMTO_ABORTIFHUNG_AND_BLOCK := 0x0003

    if (!listViewHwnd || !DllCall("user32\IsWindow", "Ptr", listViewHwnd, "Int"))
        return False
    if (GetWindowClassName(listViewHwnd) != "SysListView32")
        return False
    try {
        if !IsSysListViewReportView(listViewHwnd)
            return False
    } catch {
        return False
    }

    if (mode = "content")
        requestedWidth := LVSCW_AUTOSIZE
    else if (mode = "header")
        requestedWidth := LVSCW_AUTOSIZE_USEHEADER
    else if (mode = "header_no_fill")
        requestedWidth := LVSCW_AUTOSIZE_USEHEADER
    else
        return False

    headerHwnd := 0
    if !DllCall("user32\SendMessageTimeoutW"
        , "Ptr", listViewHwnd, "UInt", LVM_GETHEADER, "Ptr", 0, "Ptr", 0
        , "UInt", SMTO_ABORTIFHUNG_AND_BLOCK, "UInt", timeoutMs, "Ptr*", headerHwnd, "Ptr")
        return False
    if (!headerHwnd || !DllCall("user32\IsWindow", "Ptr", headerHwnd, "Int"))
        return False

    columnCount := 0
    if !DllCall("user32\SendMessageTimeoutW"
        , "Ptr", headerHwnd, "UInt", HDM_GETITEMCOUNT, "Ptr", 0, "Ptr", 0
        , "UInt", SMTO_ABORTIFHUNG_AND_BLOCK, "UInt", timeoutMs, "Ptr*", columnCount, "Ptr")
        return False
    if (columnCount < 1)
        return False

    Loop, %columnCount% {
        columnIndex := A_Index - 1
        ; Preserve zero-width columns, including the final column, without any resize write.
        currentWidth := 0
        if !DllCall("user32\SendMessageTimeoutW"
            , "Ptr", listViewHwnd, "UInt", LVM_GETCOLUMNWIDTH
            , "Ptr", columnIndex, "Ptr", 0
            , "UInt", SMTO_ABORTIFHUNG_AND_BLOCK, "UInt", timeoutMs, "Ptr*", currentWidth, "Ptr")
            return False
        if (currentWidth = 0)
            continue

        columnWidth := (mode = "header_no_fill" && columnIndex = columnCount - 1)
            ? LVSCW_AUTOSIZE : requestedWidth
        messageResult := 0
        if !DllCall("user32\SendMessageTimeoutW"
            , "Ptr", listViewHwnd, "UInt", LVM_SETCOLUMNWIDTH
            , "Ptr", columnIndex, "Ptr", columnWidth
            , "UInt", SMTO_ABORTIFHUNG_AND_BLOCK, "UInt", timeoutMs, "Ptr*", messageResult, "Ptr")
            return False
        if (!messageResult)
            return False
    }

    return True
}

; Return true when the native SysListView32 type bits select Details/Report view.
; Only LVS_TYPEMASK belongs in this decision; normal window ExStyle bits are not
; interchangeable with the separate ListView extended-style bitfield.
IsSysListViewReportView(controlHwnd) {
    static LVS_TYPEMASK := 0x0003
    static LVS_REPORT   := 0x0001

    if (!controlHwnd || !DllCall("user32\IsWindow", "Ptr", controlHwnd, "Int"))
        return False

    WinGet, controlStyle, Style, ahk_id %controlHwnd%
    return ((controlStyle & LVS_TYPEMASK) = LVS_REPORT)
}
; Attempts a fast classic-control replacement. "not_classic" and "target_gone"
; leave Clip() to make the foreground-guarded clipboard-paste decision. A
; "message_uncertain" result does not: the direct message may already have run.
_TryFastInsertWrappedText(windowId, text) {
    targetState := _GetFastInsertWrappedTextTarget(windowId, controlHwnd)
    controlClass := controlHwnd ? GetWindowClassName(controlHwnd) : ""
    if (targetState != "classic_edit") {
        if (targetState = "not_classic" && IsWindowProcessName(windowId, "BCompare.exe") && controlClass = "TTextEditor") {
            WrapDebugLog("insert path=fast target=bcompare_ttexteditor action=skip_em_replacesel controlHwnd=" . controlHwnd . " hwnd=" . windowId)
            return targetState
        }
        return targetState
    }

    return _FastInsertWrappedTextIntoClassicControl(windowId, controlHwnd, text)
}

; Reads highlighted text directly from classic Edit/RichEdit controls so wrapper
; hotkeys do not depend on a timing-sensitive Ctrl+C when a native selection is available.
_TryGetClassicSelectedText(windowId, ByRef selectedText) {
    selectedText := ""
    targetState := _GetFastInsertWrappedTextTarget(windowId, controlHwnd)
    if (targetState != "classic_edit")
        return false

    if (GetWindowClassName(controlHwnd) != "Edit")
        return false

    if !_GetClassicControlSelectionRange(controlHwnd, selStart, selEnd)
        return false
    if (selStart = selEnd)
        return false

    ControlGetText, controlText, , ahk_id %controlHwnd%
    if (StrLen(controlText) < selEnd)
        return false

    selectedText := SubStr(controlText, selStart + 1, selEnd - selStart)
    if InStr(selectedText, "`r")
        selectedText := StrReplace(selectedText, "`r")
    return true
}

; Reads highlighted text from selected custom editors through UIA before
; falling back to clipboard copy. This avoids targets that ignore synthetic Ctrl+C.
_TryGetUIASelectedText(windowId, ByRef selectedText) {
    global UIA

    selectedText := ""
    if !IsForegroundWindow(windowId) {
        WrapDebugLog("uia skip reason=not_foreground hwnd=" . windowId)
        return false
    }
    if !_IsUIASelectedTextTarget(windowId) {
        WrapDebugLog("uia skip reason=not_target hwnd=" . windowId . " process=" . GetWindowProcessName(windowId) . " class=" . GetWindowClassName(windowId))
        return false
    }
    if !IsObject(UIA) {
        WrapDebugLog("uia fail reason=no_uia hwnd=" . windowId)
        return false
    }

    focusEl := ""
    try
        focusEl := UIA.GetFocusedElement()
    catch e {
        WrapDebugLog("uia fail reason=focused_exception hwnd=" . windowId)
        return false
    }
    if !IsObject(focusEl) {
        WrapDebugLog("uia fail reason=focused_empty hwnd=" . windowId)
        return false
    }

    focusClass := ""
    focusFramework := ""
    focusProcessId := ""
    try
        focusClass := focusEl.CurrentClassName
    catch
        focusClass := ""
    try
        focusFramework := focusEl.CurrentFrameworkId
    catch
        focusFramework := ""
    try
        focusProcessId := focusEl.CurrentProcessId
    catch
        focusProcessId := ""
    WrapDebugLog("uia focus class=" . focusClass . " framework=" . focusFramework . " processId=" . focusProcessId . " hwnd=" . windowId)

    for patternIndex, patternMode in ["TextEdit", "Text"]
    {
        textPat := ""
        try
            textPat := focusEl.GetCurrentPatternAs(patternMode)
        catch
            textPat := ""
        if !IsObject(textPat) {
            WrapDebugLog("uia pattern=" . patternMode . " result=unavailable hwnd=" . windowId)
            continue
        }

        selectionRanges := ""
        try
            selectionRanges := textPat.GetSelection()
        catch e {
            WrapDebugLog("uia pattern=" . patternMode . " result=selection_exception hwnd=" . windowId)
            selectionRanges := ""
        }
        if !IsObject(selectionRanges) {
            WrapDebugLog("uia pattern=" . patternMode . " result=selection_empty hwnd=" . windowId)
            continue
        }

        rangeCount := 0
        try
            rangeCount := selectionRanges.Length
        catch
            rangeCount := 0
        WrapDebugLog("uia pattern=" . patternMode . " rangeCount=" . rangeCount . " hwnd=" . windowId)
        if (rangeCount < 1)
            continue

        selectedRange := ""
        try
            selectedRange := selectionRanges.GetElement(0)
        catch e {
            WrapDebugLog("uia pattern=" . patternMode . " result=range_exception hwnd=" . windowId)
            selectedRange := ""
        }
        if !IsObject(selectedRange)
            continue

        rangeText := ""
        try
            rangeText := selectedRange.GetText(-1)
        catch e {
            WrapDebugLog("uia pattern=" . patternMode . " result=get_text_exception hwnd=" . windowId)
            rangeText := ""
        }
        WrapDebugLog("uia pattern=" . patternMode . " textLen=" . StrLen(rangeText) . " hwnd=" . windowId)
        if (rangeText = "")
            continue

        if !IsForegroundWindow(windowId) {
            WrapDebugLog("uia fail reason=foreground_lost_after_read hwnd=" . windowId)
            return false
        }
        selectedText := rangeText
        if InStr(selectedText, "`r")
            selectedText := StrReplace(selectedText, "`r")
        WrapDebugLog("uia success pattern=" . patternMode . " len=" . StrLen(selectedText) . " hwnd=" . windowId)
        return true
    }

    WrapDebugLog("uia fail reason=no_selected_text hwnd=" . windowId)
    return false
}
; Wraps clipboard text', preserving a single trailing space outside the wrapper,
; and prefers direct classic-control replacement before clipboard paste fallback.
WrapClipboardText(leftText, rightText) {
    global clipLastReadSucceeded, bcompareFastInsertRetryCount, bcompareFastInsertRetryDelayMs, clipPasteControlHwnd
    ; These hotkeys are Alt+Shift chords. Keep those modifiers logically up
    ; after the managed Ctrl+C send and any clipboard-paste fallback so
    ; applications cannot treat a following key as an Alt menu accelerator or
    ; Shift-modified shortcut.
    modifiersToSync  := ""
    targetWindowId   := DllCall("user32\GetForegroundWindow", "Ptr")
    targetProcess    := GetWindowProcessName(targetWindowId)
    targetClass      := GetWindowClassName(targetWindowId)
    readSource       := ""
    isNotepadTarget  := (targetProcess = "notepad.exe")

    WrapDebugLog("start hotkey=" . A_ThisHotkey . " hwnd=" . targetWindowId . " process=" . targetProcess . " class=" . targetClass . " leftLen=" . StrLen(leftText) . " rightLen=" . StrLen(rightText))

    if _TryGetClassicSelectedText(targetWindowId, clipboardText) {
        readSource := "classic"
    } else if _TryGetUIASelectedText(targetWindowId, clipboardText) {
        readSource := "uia"
    } else {
        clipboardText := Clip("", "", "", modifiersToSync, targetWindowId)
        if (!clipLastReadSucceeded) {
            WrapDebugLog("abort read=clipboard_failed hwnd=" . targetWindowId . " process=" . targetProcess . " class=" . targetClass)
            Clip("", "", "RESTORE")
            return
        }
        readSource := "clipboard"
    }
    WrapDebugLog("read source=" . readSource . " len=" . StrLen(clipboardText) . " hwnd=" . targetWindowId . " process=" . targetProcess)

    hasTrailingSpace := SubStr(clipboardText, 0) == " "
    wrappedText      := RTrim(clipboardText, " ")

    wrappedText := leftText . wrappedText . rightText
    if (hasTrailingSpace)
        wrappedText .= " "

    if (isNotepadTarget) {
        WrapDebugLog("insert path=clipboard_notepad len=" . StrLen(wrappedText) . " hwnd=" . targetWindowId)
        Clip(wrappedText, "", "", modifiersToSync, targetWindowId)
        return
    }

    insertResult := _TryFastInsertWrappedText(targetWindowId, wrappedText)
    WrapDebugLog("insert path=fast result=" . insertResult . " len=" . StrLen(wrappedText) . " hwnd=" . targetWindowId . " process=" . targetProcess)
    if (targetProcess = "BCompare.exe" && (insertResult = "not_classic" || insertResult = "target_gone")) {
        Loop, %bcompareFastInsertRetryCount% {
            Sleep, %bcompareFastInsertRetryDelayMs%
            insertResult := _TryFastInsertWrappedText(targetWindowId, wrappedText)
            WrapDebugLog("insert path=fast retry=bcompare attempt=" . A_Index . " result=" . insertResult . " len=" . StrLen(wrappedText) . " hwnd=" . targetWindowId)
            if (insertResult != "not_classic" && insertResult != "target_gone")
                break
        }
    }
    ; "not_classic" means the focused control is not a recognized Win32
    ; Edit/RichEdit class, so the direct EM_REPLACESEL path is not attempted.
    ; "target_gone" means the direct HWND path cannot identify the focused child.
    ; Clip() rechecks targetWindowId immediately before Ctrl+V, so either state
    ; can use the managed clipboard path without pasting into another app.
    ; "message_uncertain" is intentionally excluded because EM_REPLACESEL may
    ; already have changed the selection before its bounded send timed out.
    if (insertResult = "not_classic" || insertResult = "target_gone") {
        WrapDebugLog("insert path=clipboard_fallback reason=" . insertResult . " len=" . StrLen(wrappedText) . " hwnd=" . targetWindowId)
        Clip(wrappedText, "", "", modifiersToSync, targetWindowId)
    }

}

; Runs a wrapper hotkey with input blocking and typing fixes temporarily disabled.
; The finally block always releases the keyboard block, even when clipboard or
; target-control work raises an error before the normal cleanup path runs.
_RunWrapClipboardText(leftText, rightText) {
    global StopAutoFix, clipRestoreTimerPending

    Critical, On
    StopAutoFix := True
    wrapperWindowId := DllCall("user32\GetForegroundWindow", "Ptr")
    wrapperProcess := GetWindowProcessName(wrapperWindowId)
    releaseWaitSeconds := (wrapperProcess = "BCompare.exe") ? 0.75 : 0.12
    WrapDebugLog("release_wait_config process=" . wrapperProcess . " timeoutSeconds=" . releaseWaitSeconds . " hwnd=" . wrapperWindowId)
    ClipjumpPauseForWrapper()
    _WaitForWrapperTriggerRelease(releaseWaitSeconds)
    BeginBlockKeys()
    try {
        WrapClipboardText(leftText, rightText)
    } finally {
        ; Release input-state guards before optional cleanup so a failure here
        ; cannot leave physical key-down events permanently blocked.
        EndBlockKeys()
        StopAutoFix := False
        try {
            ; If Clip() queued a restore, ClipRestore will re-enable Clipjump
            ; after the target app has had time to consume the paste.
            if (!clipRestoreTimerPending)
                ClipjumpRestoreAfterWrapper()
        } finally {
            try {
                Hotstring("Reset")
            } finally {
                Critical, Off
            }
        }
    }
}

; Swap a selected true/false literal to the opposite value while preserving only
; the exact lower/title-case forms supported by this hotkey.
_SwapSelectedBooleanLiteral() {
    global clipPreferExplicitCtrlV

    ; Alt is still physically held by the !s hotkey. Do not synthesize an Alt
    ; down event after Ctrl+C or Ctrl+V; its later physical release could then
    ; activate the target application's menu bar.
    modifiersToSync := ""
    targetWindowId := DllCall("user32\GetForegroundWindow", "Ptr")
    selectedText   := Clip("", "", "", modifiersToSync, targetWindowId)
    if (selectedText = "")
        return false

    if (selectedText      == "true")
        replacementText := "false"
    else if (selectedText == "True")
        replacementText := "False"
    else if (selectedText == "false")
        replacementText := "true"
    else if (selectedText == "False")
        replacementText := "True"
    else
        return false

    insertResult := _TryFastInsertWrappedText(targetWindowId, replacementText)
    if (insertResult = "not_classic") {
        clipPreferExplicitCtrlV := True
        try {
            Clip(replacementText, "", "", modifiersToSync, targetWindowId)
        } finally {
            clipPreferExplicitCtrlV := False
        }
        return true
    }

    return (insertResult = "inserted")
}

!a::
    StopAutoFix := True
    Send, {Home}
    Hotstring("Reset")
    StopAutoFix := False
Return

; Swap a selected true/false literal and keep its capitalization style.
!s::
    Critical, On
    StopAutoFix := True
    ; Let the trigger key finish before the explicit paste/send path runs so
    ; Alt+S is less likely to leave a stale modifier state behind.
    KeyWait, s, T0.25
    try {
        BeginBlockKeys()
        if !_SwapSelectedBooleanLiteral()
            Clip("", "", "RESTORE")

        Hotstring("Reset")
    } finally {
        ; Keep Alt logically up as required by _SwapSelectedBooleanLiteral(), but
        ; never leave the shared input or auto-fix guards enabled after a failure.
        EndBlockKeys()
        StopAutoFix := False
        Critical, Off
    }
Return

!;::
    StopAutoFix := True
    Send, {End}
    Hotstring("Reset")
    StopAutoFix := False
Return

!+;::
    StopAutoFix := True
    If (A_PriorHotKey == A_ThisHotKey && A_TimeSincePriorHotkey < k_DoubleClickTime) {
        Send, {Home}
        Send, +{End}
    }
    Else {
        Send, +{End}
    }
    Hotstring("Reset")
    StopAutoFix := False
Return

!+i::
    StopAutoFix := True
    Send +{UP}
    Hotstring("Reset")
    StopAutoFix := False
Return

!+k::
    StopAutoFix := True
    Send +{Down}
    Hotstring("Reset")
    StopAutoFix := False
Return

!+':: ;'
    _RunWrapClipboardText("""", """")
Return

!+[::
    _RunWrapClipboardText("{", "}")
Return

!+]::
    _RunWrapClipboardText("{", "}")
Return

!+<::
    _RunWrapClipboardText("<", ">")
Return

!+>::
    _RunWrapClipboardText("<", ">")
Return

!+(::
    _RunWrapClipboardText("(", ")")
Return

!+)::
    _RunWrapClipboardText("(", ")")
Return

!+sc029::
    _RunWrapClipboardText("``", "``")
Return

!+b::
    _RunWrapClipboardText("\b", "\b")
Return

!+5::
    _RunWrapClipboardText("%", "%")
Return

$!i::
    StopAutoFix := True
    Send, {UP}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!k::
    StopAutoFix := True
    SendLevel, 1
    SendEvent, {Down}
    SendLevel, 0
    Hotstring("Reset")
    StopAutoFix := False
Return

$!j::
    StopAutoFix := True
    Send, ^{Left}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!+j::
    StopAutoFix := True
    Send, ^+{Left}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!l::
    StopAutoFix := True
    Send, ^{Right}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!+l::
    StopAutoFix := True
    Send ^+{Right}
    Hotstring("Reset")
    StopAutoFix := False
Return

$!h::
    Send, {Left}
Return

#If disableEnter
$Enter::
    if (_ShouldHandleFixSlashEnter()) {
        currentFixSlashEnterHwnd      := WinExist("A")
        currentFixSlashEnterCtrlNN    := ""
        currentFixSlashEnterCtrlHwnd  := 0
        currentFixSlashEnterCtrlClass := ""

        if (TryCaptureActiveFocusSnapshotFull(currentFixSlashEnterHwnd, currentFixSlashEnterCtrlNN, currentFixSlashEnterCtrlHwnd, currentFixSlashEnterCtrlClass)
            && IsClassicEditControlClass(currentFixSlashEnterCtrlClass)) {
            ; Classic Edit/RichEdit keeps the older immediate Enter-thread path.
            ; Non-classic editors cannot prove the rewrite inline as reliably, so
            ; those fall through to the deferred barrier below.
            CancelTbcTypingFixes(True, False)
            if (!_CommitFixSlashEnterInline()) {
                Send, {Enter}
            }
        }
        else {
            ; This mirrors tbcHoty and deferred slash+Space: queue intent,
            ; wait for brief idle, revalidate the same target, then apply or
            ; cancel. The extra rule here is that Enter itself stays withheld
            ; until the queued slash rewrite has been resolved.
            if (!_RequestFixSlash("enter"))
                Send, {Enter}
        }
    }
    else {
        Send, {Enter}
    }
    disableEnter := False
Return
#If

; =========================================================

$~Space::
    GoSub, Marktime_Hoty_FixSlash
Return

$!Space::
    Send, {Space}
Return

; duplicate hotkey in case shift is accidentally  held as a result of attempting to type a '?'
$~+Space::
    GoSub, Marktime_Hoty_FixSlash
Return

$~^Backspace::
    CancelTbcTypingFixes(True, True)
    _ResetFixSlashStringTracking()
    Hotstring("Reset")
Return

; Editing or moving the caret invalidates the remembered prior-letter context used
; by FixSlash, so clear it here rather than letting a later "/" rewrite qualify
; against text the user has already changed or navigated away from.
$~Backspace::
    CancelTbcTypingFixes(True, True)
    _ResetFixSlashStringTracking()
    TimeOfLastHotkeyTyped := A_TickCount
    X_PriorPriorHotKey :=
Return

$~Left::
    CancelTbcTypingFixes(True, True)
    _ResetFixSlashStringTracking()
    X_PriorPriorHotKey :=
Return

$~Right::
    CancelTbcTypingFixes(True, True)
    _ResetFixSlashStringTracking()
    X_PriorPriorHotKey :=
Return


; Windows normally enters menu-key mode only when Alt is pressed and released without another key event.
; The synthetic vkE8 occurs while Alt is down, so Windows treats Alt as having participated in a key
; combination and does not activate the menu on release. {Blind} preserves Alt’s modifier state, so
; real Alt shortcuts continue to work.
; ~LAlt::Send {Blind}{vkE8}

; ~LAlt Up::
; Return

; Purpose        : support the typing/editability gate by answering whether the
; currently focused UIA element should be treated as an editable text target.
; Why this exists: the script needs one policy decision for "editable" that
; combines control-type and pattern checks instead of spreading raw focused-
; element inspection logic across typing hotpaths.
; Scope          : feature-specific helper.
UIA_IsFocusedEditable() {
    global UIA
    static c_preferredEditablePatternMode := ""

    if !IsObject(UIA)
        return false

    focusEl := ""
    try
        focusEl := UIA.GetFocusedElement()
    catch
        return false

    if !IsObject(focusEl)
        return false

    info := SafeUIA_GetElementSnapshot(focusEl, "isEnabled")
    if (info.isEnabled = "" || info.isEnabled == 0)
        return false

    result := false
    patternOrder := []
    if (c_preferredEditablePatternMode != "")
        patternOrder.Push(c_preferredEditablePatternMode)
    for patternIndex, patternMode in ["Value", "TextEdit"]
    {
        if (patternMode != c_preferredEditablePatternMode)
            patternOrder.Push(patternMode)
    }

    for patternIndex, patternMode in patternOrder
    {
        if (patternMode = "Value")
        {
            valuePat := ""
            try
                valuePat := focusEl.GetCurrentPatternAs("Value")
            catch
                valuePat := ""

            if IsObject(valuePat)
            {
                isReadOnly := ""
                isReadOnlyKnown := false
                try {
                    isReadOnly := valuePat.CurrentIsReadOnly
                    isReadOnlyKnown := true
                }
                catch
                    isReadOnly := ""

                if (isReadOnlyKnown && isReadOnly == 0) {
                    c_preferredEditablePatternMode := "Value"
                    result := true
                    break
                }
            }
        }
        else if (patternMode = "TextEdit")
        {
            textEditPat := ""
            try
                textEditPat := focusEl.GetCurrentPatternAs("TextEdit")
            catch
                textEditPat := ""

            ; TextPattern is also exposed by read-only viewers. TextEditPattern
            ; specifically identifies an element that supports text editing.
            if IsObject(textEditPat) {
                c_preferredEditablePatternMode := "TextEdit"
                result := true
                break
            }
        }
    }

    if (!result)
        return false

    ; A positive pattern result belongs only to the element inspected above.
    ; If UIA focus moved during the calls, do not cache that old element's answer.
    currentFocusEl := ""
    sameFocus := false
    try {
        currentFocusEl := UIA.GetFocusedElement()
        if IsObject(currentFocusEl)
            sameFocus := UIA.CompareElements(focusEl, currentFocusEl)
    }
    catch
        sameFocus := false

    return sameFocus
}

; Returns the currently focused MSAA child/object without interpreting its role.
; Resolving this twice lets the caller reject a stale result if accessibility
; focus changes while the first target is being inspected.
_MSAAGetFocusedTarget() {
    if !IsFunc("Acc_RoleIdSafe")
        return ""

    accRoot := ""
    try
        accRoot := Acc_GetFocusedObject()
    catch
        return ""

    if !IsObject(accRoot)
        return ""

    accFocus := ""
    try {
        accFocus := accRoot.accFocus
    } catch {
        accFocus := ""
    }

    accObj := accRoot

    if IsObject(accFocus)
        return accFocus
    else if (accFocus != "")
    {
        childNum := accFocus + 0
        if !(childNum = 0 && accFocus != 0 && accFocus != "0")
            return Acc_CreateChildRef(accRoot, childNum)
    }

    return accRoot
}

; Returns true only for an MSAA ROLE_SYSTEM_TEXT target that does not report
; STATE_SYSTEM_READONLY. Exact numeric role matching avoids broad role-name
; substrings that can classify unrelated accessible objects as editors.
_MSAAIsEditableTarget(accObj) {
    if !Acc_ResolveTarget(accObj, iaObj, childId)
        return false

    stateRead := false
    try {
        state := iaObj.accState(childId)
        stateRead := true
    }
    catch
        return false

    ; STATE_SYSTEM_READONLY means the object can expose text without accepting
    ; edits. Reject it before considering its role an editable text target.
    if (!stateRead || ((state + 0) & 0x40))
        return false

    return (Acc_RoleIdSafe(accObj) = 42) ; ROLE_SYSTEM_TEXT
}

MSAA_IsFocusedEditable() {
    firstTarget := _MSAAGetFocusedTarget()
    if (!_MSAAIsEditableTarget(firstTarget))
        return false

    ; Re-read focus after the first role/state calls. A positive answer is cached
    ; only if the currently focused target is still independently editable.
    currentTarget := _MSAAGetFocusedTarget()
    return _MSAAIsEditableTarget(currentTarget)
}

GetThreadFocusHwnd(tid)
{
    ; GUITHREADINFO = two DWORDs, six HWNDs, and one RECT. hwndFocus follows
    ; hwndActive, so its offset is 8 + one pointer on both architectures.
    size := 24 + (A_PtrSize * 6)
    VarSetCapacity(gui, size, 0)
    ; Set GUITHREADINFO.cbSize so GetGUIThreadInfo accepts the allocated structure.
    NumPut(size, gui, 0, "UInt")

    ok := DllCall("user32\GetGUIThreadInfo", "UInt", tid, "Ptr", &gui, "Int")
    if (!ok)
        return 0

    return NumGet(gui, 8 + A_PtrSize, "Ptr") ; hwndFocus
}

ControlGetFocusEx(tidTarget, hwndTarget, timeoutMs := 15)
{
    if !DllCall("user32\IsWindow", "Ptr", hwndTarget, "Int")
        return false

    hwndFocus := GetThreadFocusHwnd(tidTarget)
    if (hwndFocus && (hwndFocus = hwndTarget || DllCall("user32\IsChild", "Ptr", hwndTarget, "Ptr", hwndFocus, "Int")))
        return true

    if (timeoutMs <= 0)
        return false

    start := A_TickCount
    Loop
    {
        hwndFocus := GetThreadFocusHwnd(tidTarget)
        if (hwndFocus && (hwndFocus = hwndTarget || DllCall("user32\IsChild", "Ptr", hwndTarget, "Ptr", hwndFocus, "Int")))
            return true

        if ((A_TickCount - start) >= timeoutMs)
            break

        Sleep, 0
    }
    return false
}

; Returns a stable string key for the active thread's caret rectangle, if exposed.
GetActiveCaretRectKey(ByRef caretRectKey, ByRef caretHwnd := 0)
{
    WinGet, activeHwnd, ID, A
    if !activeHwnd {
        caretHwnd := 0
        caretRectKey := ""
        return false
    }

    tid := DllCall("user32\GetWindowThreadProcessId", "Ptr", activeHwnd, "UInt*", 0, "UInt")
    if !tid
    {
        caretHwnd := 0
        caretRectKey := ""
        return false
    }

    size := 8 + (A_PtrSize * 6) + 16
    VarSetCapacity(gui, size, 0)
    ; Set GUITHREADINFO.cbSize so GetGUIThreadInfo accepts the allocated structure.
    NumPut(size, gui, 0, "UInt")

    ok := DllCall("user32\GetGUIThreadInfo", "UInt", tid, "Ptr", &gui, "Int")
    if (!ok)
    {
        caretHwnd := 0
        caretRectKey := ""
        return false
    }

    caretHwnd := NumGet(gui, 8 + (A_PtrSize * 5), "Ptr")
    if !caretHwnd
    {
        caretRectKey := ""
        return false
    }

    rectOffset := 8 + (A_PtrSize * 6)
    caretLeft   := NumGet(gui, rectOffset + 0,  "Int")
    caretTop    := NumGet(gui, rectOffset + 4,  "Int")
    caretRight  := NumGet(gui, rectOffset + 8,  "Int")
    caretBottom := NumGet(gui, rectOffset + 12, "Int")

    caretRectKey := caretHwnd "|" caretLeft "|" caretTop "|" caretRight "|" caretBottom
    return true
}

~Lbutton::
    CancelTbcTypingWorkForContextChange()
    If (IsWindowFullScreen( "A" ))
    {
        SetTimer, KeyTrack, Off
        IsPaused := True
        Menu, Tray, Togglecheck, &Suspend
        Suspend
        exit

    }
Return

; Waits for the active caret rectangle to change and then stabilize, with a sleep fallback.
WaitForActiveCaretRectChangeAndSettle(caretRectKeyBeforeMove := "", timeoutMs := 35, stablePollCount := 2, fallbackSleepMs := 10)
{
    if (caretRectKeyBeforeMove = "")
    {
        ; If the editor never exposed a caret rect, use the configured fallback
        ; sleep immediately instead of burning the full polling timeout first.
        if (fallbackSleepMs > 0)
            Sleep, %fallbackSleepMs%
        return false
    }

    currentCaretRectKey := ""
    lastMovedCaretRectKey := ""
    sawCaretMove := false
    stableSampleCount := 0
    startTick := A_TickCount

    Loop
    {
        if GetActiveCaretRectKey(currentCaretRectKey)
        {
            if (sawCaretMove || currentCaretRectKey != caretRectKeyBeforeMove)
            {
                sawCaretMove := true

                ; Require the moved caret rect to stay unchanged for multiple
                ; polls so we do not advance on an intermediate animation step.
                if (currentCaretRectKey = lastMovedCaretRectKey)
                    stableSampleCount += 1
                else {
                    lastMovedCaretRectKey := currentCaretRectKey
                    stableSampleCount := 1
                }

                if (stableSampleCount >= stablePollCount)
                    return true
            }
        }

        if ((A_TickCount - startTick) >= timeoutMs)
            break

        Sleep, 0
    }

    if (fallbackSleepMs > 0)
        Sleep, %fallbackSleepMs%

    return false
}

; --------------------------------------------------------------------------------
; --------------------   ChatGPT -------------------------------------------------
; --------------------------------------------------------------------------------
BeginBlockKeys() {
    Global blockKeys

    ; Start a new key-blocking session. Modifier cleanup is now handled only
    ; by explicit call sites, not implicitly by the keyboard hook.
    blockKeys := True
}

BeginBlockWheel() {
    Global blockWheel

    ; Start a wheel-only blocking session covering the synthetic Ctrl chord,
    ; immediate Ctrl synchronization, and short post-send delivery guard.
    blockWheel := True
}

EndBlockKeys() {
    Global blockKeys

    ; End the current key-blocking session.
    blockKeys := False
}

EndBlockWheel() {
    Global blockWheel

    ; End the current wheel-only blocking session.
    blockWheel := False
}

; When a guarded column-adjust send is requested, wait one last short moment and
; re-check the current request token, quiet window, and active window immediately
; before injecting Ctrl+NumpadAdd. This lets a just-arrived WheelUp/WheelDown event
; abort the send instead of being interpreted alongside a synthetic Ctrl chord.
SendCtrlNumpadAdd(syncPassCount := 6, guardRequestId := 0, guardQuietMs := 0, guardHwnd := 0) {
    global tbcAdjustColumnsLastWheelTick, tbcAdjustColumnsRequestId
    global k_tbcAdjustColumnsPostSendWheelGuardMs, k_tbcAdjustColumnsSendGuardMs

    if (guardRequestId || guardQuietMs || guardHwnd) {
        Sleep, %k_tbcAdjustColumnsSendGuardMs%

        if (guardRequestId && tbcAdjustColumnsRequestId != guardRequestId)
            return false

        if (guardQuietMs && (A_TickCount - tbcAdjustColumnsLastWheelTick) < guardQuietMs)
            return false

        if (guardHwnd && WinExist("A") != guardHwnd)
            return false
    }

    targetWindowId := DllCall("user32\GetForegroundWindow", "Ptr")
    if (!targetWindowId)
        return false

    BeginBlockWheel()
    try {
        BeginBlockKeys()
        try {
            Send, ^{NumpadAdd}
        } finally {
            EndBlockKeys()
        }

        ; Keep wheel events suppressed until the application's logical Ctrl state
        ; matches the physical keyboard, then cover a short post-send delivery gap.
        SyncModifierSidesToPhys("Ctrl", targetWindowId)
        Sleep, %k_tbcAdjustColumnsPostSendWheelGuardMs%
    } finally {
        EndBlockWheel()
    }

    ScheduleModifierSync("Ctrl", syncPassCount, targetWindowId)
    return true
}

; Send a clean synthetic Ctrl chord without losing the user's physically held
; modifiers. Sending {Ctrl Up}, {Shift Up}, and similar events changes the
; modifier state seen by the target application even if the user still holds
; the physical key. Because that key never physically transitions up and down,
; Windows does not send a replacement key-down event. Without sync,
; a later D press while Ctrl is still physically held can arrive as plain D
; instead of Ctrl+D.
;
; The inverse race can leave a modifier logically stuck: the script restores a
; synthetic modifier-down, then the user releases the real key just after the
; sequence. The immediate and deferred sync passes make the target
; application's modifier state match the physical keyboard state again.
_SendManagedCtrlChord(chordKey, syncPassCount := 6, explicitCtrlPath := False, modifiersToSync := "Shift Alt Ctrl Win", expectedWindowId := 0) {
    targetWindowId := expectedWindowId ? expectedWindowId : DllCall("user32\GetForegroundWindow", "Ptr")

    ; Recheck immediately before injection. Clipboard preparation can take long
    ; enough for a different application to become foreground in the meantime.
    if (!IsForegroundWindow(targetWindowId))
        return false

    SendInput, {Blind}{sc02A up}{sc036 up}{sc01D up}{sc11D up}{sc038 up}{sc138 up}{sc15B up}{sc15C up}
    if (explicitCtrlPath)
        SendInput, {Ctrl Down}%chordKey%{Ctrl Up}
    else
        SendInput, ^%chordKey%

    ; A modifier pressed while SendInput runs can be physically down before
    ; the target application receives its real key-down event. Live sync can
    ; then send one duplicate down event in that tiny buffered-input window.
    ; This is an intentional tradeoff for the simpler, live-state behavior.
    ;
    ; Callers whose hotkey itself holds Alt or Shift can pass an empty set so
    ; those modifiers stay logically up instead of activating app menu shortcuts.
    if (modifiersToSync != "") {
        SyncModifierSidesToPhys(modifiersToSync, targetWindowId)
        ScheduleModifierSync(modifiersToSync, syncPassCount, targetWindowId)
    }
    return true
}

; Synchronize named modifier sides with the physical keyboard state. Every
; requested side is sent down if physically held, otherwise up. This repairs
; modifiers synthetically released by navigation and modifiers left logically
; down after the user has physically released them. When expectedWindowId is
; supplied, cancel if that window is no longer foreground so cleanup intended
; for one application cannot inject modifier events into another application.
SyncModifierSidesToPhys(modifiers := "Shift Alt Ctrl Win", expectedWindowId := 0) {
    if (expectedWindowId && !IsForegroundWindow(expectedWindowId))
        return false

    sendSequence := "{Blind}"
    if (InStr(modifiers, "Shift")) {
        isPhysicallyHeld := GetKeyState("LShift", "P")
        keyState := isPhysicallyHeld ? "down" : "up"
        sendSequence .= "{sc02A " . keyState . "}"

        isPhysicallyHeld := GetKeyState("RShift", "P")
        keyState := isPhysicallyHeld ? "down" : "up"
        sendSequence .= "{sc036 " . keyState . "}"
    }

    if (InStr(modifiers, "Ctrl")) {
        isPhysicallyHeld := GetKeyState("LCtrl", "P")
        keyState := isPhysicallyHeld ? "down" : "up"
        sendSequence .= "{sc01D " . keyState . "}"

        isPhysicallyHeld := GetKeyState("RCtrl", "P")
        keyState := isPhysicallyHeld ? "down" : "up"
        sendSequence .= "{sc11D " . keyState . "}"
    }

    if (InStr(modifiers, "Alt")) {
        isPhysicallyHeld := GetKeyState("LAlt", "P")
        keyState := isPhysicallyHeld ? "down" : "up"
        sendSequence .= "{sc038 " . keyState . "}"

        isPhysicallyHeld := GetKeyState("RAlt", "P")
        keyState := isPhysicallyHeld ? "down" : "up"
        sendSequence .= "{sc138 " . keyState . "}"
    }

    if (InStr(modifiers, "Win")) {
        isPhysicallyHeld := GetKeyState("LWin", "P")
        keyState := isPhysicallyHeld ? "down" : "up"
        sendSequence .= "{sc15B " . keyState . "}"

        isPhysicallyHeld := GetKeyState("RWin", "P")
        keyState := isPhysicallyHeld ? "down" : "up"
        sendSequence .= "{sc15C " . keyState . "}"
    }

    if (sendSequence = "{Blind}")
        return true

    ; Build one sequence, then perform the final foreground check immediately
    ; before one SendInput call. This minimizes the remaining check-to-send race.
    if (expectedWindowId && !IsForegroundWindow(expectedWindowId))
        return false

    SendInput, %sendSequence%
    return true
}

; Clear every field associated with the current target-bound deferred sync and
; cancel its pending timer.
_ClearDeferredModifierSync() {
    Global deferredModifierFamilies
    Global deferredModifierSyncRemaining
    Global deferredModifierTargetHwnd

    SetTimer, RunDeferredModifierSync, Off
    deferredModifierFamilies      := ""
    deferredModifierSyncRemaining := 0
    deferredModifierTargetHwnd    := 0
}

; Re-check modifier state shortly after a hotkey returns so a physical key-up
; that happens just after the immediate sync still gets applied. Cancel the
; cleanup window if its original target is no longer the foreground window.
RunDeferredModifierSync() {
    Global deferredModifierFamilies
    Global deferredModifierSyncRemaining
    Global deferredModifierTargetHwnd

    if (deferredModifierFamilies = "" || deferredModifierSyncRemaining <= 0 || !deferredModifierTargetHwnd) {
        _ClearDeferredModifierSync()
        return
    }

    if (!IsForegroundWindow(deferredModifierTargetHwnd)) {
        _ClearDeferredModifierSync()
        return
    }

    if (!SyncModifierSidesToPhys(deferredModifierFamilies, deferredModifierTargetHwnd)) {
        _ClearDeferredModifierSync()
        return
    }

    deferredModifierSyncRemaining -= 1
    if (deferredModifierSyncRemaining > 0)
        SetTimer, RunDeferredModifierSync, -75
    else
        _ClearDeferredModifierSync()
}

; Queue one or more delayed modifier sync passes after the immediate
; cleanup has already run. This gives AutoHotkey time to observe physical
; key-up events that may land just after the hotkey/send sequence finishes.
;
; modifiers:
;     Space-delimited modifier families to re-check on each deferred pass.
;     Only those families are examined, so call sites can limit sync
;     to the modifiers they may have disturbed.
;
; deferredRuns:
;     How many total deferred re-checks should still run for the current
;     cleanup window. Multiple passes matter because a synthetic send can end
;     before Windows/AutoHotkey reports the user's real modifier release, so a
;     single delayed check can still be too early. More passes extend the
;     sync window without blocking the caller.
;
; targetWindowId:
;     Foreground window that received the synthetic chord. The timer cancels
;     instead of injecting if another application becomes foreground.
ScheduleModifierSync(modifiers := "Shift Alt Ctrl", deferredRuns := 6, targetWindowId := 0) {
    Global deferredModifierFamilies
    Global deferredModifierSyncRemaining
    Global deferredModifierTargetHwnd

    if (!targetWindowId)
        targetWindowId := DllCall("user32\GetForegroundWindow", "Ptr")
    if (!IsForegroundWindow(targetWindowId)) {
        _ClearDeferredModifierSync()
        return false
    }

    ; Always use the latest requested modifier set so the timer re-checks the
    ; modifiers most relevant to the newest send/hotkey sequence.
    deferredModifierFamilies := modifiers
    ; A different target starts a new cleanup window. For the same target, only
    ; grow the remaining pass budget so a later request cannot shorten it.
    if (deferredModifierTargetHwnd != targetWindowId)
        deferredModifierSyncRemaining := deferredRuns
    else if (deferredModifierSyncRemaining < deferredRuns)
        deferredModifierSyncRemaining := deferredRuns
    deferredModifierTargetHwnd := targetWindowId

    ; Start the first delayed pass soon after the caller returns. Follow-up
    ; passes are scheduled by RunDeferredModifierSync().
    SetTimer, RunDeferredModifierSync, -40
    return true
}

; Clears the queued Everything Edit1 auto-fit state so context changes or a
; completed send do not leave a stale deferred Ctrl+NumpadAdd request behind.
_ClearTbcEverythingEditAdjustState(preserveSourceTick := False) {
    global tbcEverythingAdjustCtrlNN
    global tbcEverythingAdjustCtrlClass
    global tbcEverythingAdjustCtrlHwnd
    global tbcEverythingAdjustHwnd
    global tbcEverythingAdjustId
    global tbcEverythingAdjustRequestedTick
    global tbcEverythingAdjustSourceTick

    tbcEverythingAdjustCtrlNN        := ""
    tbcEverythingAdjustCtrlClass     := ""
    tbcEverythingAdjustCtrlHwnd      := 0
    tbcEverythingAdjustHwnd          := 0
    tbcEverythingAdjustId            := 0
    tbcEverythingAdjustRequestedTick := 0
    if (!preserveSourceTick)
        tbcEverythingAdjustSourceTick := 0
}

; Queues a deferred Everything Edit1 column auto-fit request:
; capture or accept the current search-box focus context, stamp the latest
; typing tick, and let a short timer coalesce rapid typing before native sizing.
_RequestEverythingEditAdjust(sourceTick, capturedHwnd := 0, capturedCtrlNN := "", capturedCtrlHwnd := 0, capturedCtrlClass := "") {
    global k_tbcEverythingAdjustTypingQuietMs
    global tbcEverythingAdjustCtrlNN
    global tbcEverythingAdjustCtrlClass
    global tbcEverythingAdjustCtrlHwnd
    global tbcEverythingAdjustHwnd
    global tbcEverythingAdjustId
    global tbcEverythingAdjustRequestedTick
    global tbcEverythingAdjustSourceTick

    if (!sourceTick)
        return false

    targetHwnd      := capturedHwnd
    targetCtrlNN    := capturedCtrlNN
    targetCtrlHwnd  := capturedCtrlHwnd
    targetCtrlClass := capturedCtrlClass

    if (!targetHwnd) {
        if !CaptureActiveFocusSnapshot(targetHwnd, targetCtrlNN, targetCtrlHwnd, targetCtrlClass)
            return false
    }

    if (!targetHwnd || targetCtrlNN != "Edit1")
        return false

    tbcEverythingAdjustHwnd       := targetHwnd
    tbcEverythingAdjustCtrlNN     := targetCtrlNN
    tbcEverythingAdjustCtrlHwnd   := targetCtrlHwnd
    tbcEverythingAdjustCtrlClass  := targetCtrlClass
    tbcEverythingAdjustId += 1
    tbcEverythingAdjustRequestedTick := A_TickCount
    tbcEverythingAdjustSourceTick := sourceTick
    SetTimer, FlushTbcEverythingEditAdjust, % -k_tbcEverythingAdjustTypingQuietMs
    return true
}

; Returns true only for key events that should arm Everything's deferred
; search-box auto-fit path. Keep this trigger list separate from KeyTrack() so
; the queueing decision is documented once and can be tuned in one place.
_IsEverythingEditAdjustTrigger(hotkey) {
    global k_keys
    global k_numbers

    if (hotkey = "" || hotkey = "Enter" || hotkey = "LButton")
        return false

    hotkeyKey := SubStr(hotkey, 2)
    return (   InStr(k_keys, hotkeyKey, False)
            || InStr(k_numbers, hotkeyKey, False)
            || hotkey == "~:"
            || hotkey == "~/"
            || hotkey == "$~Space"
            || hotkey == "$CapsLock"
            || hotkey == "$~Backspace")
}

; KeyTrack() queue helper for Everything Edit1:
; allow one deferred auto-fit request per typing tick, require a qualifying
; trigger hotkey, capture the exact current Edit1 identity once, and then hand
; that context to the shared deferred-send queue.
_TryRequestEverythingEditAdjust(sourceTick, hotkey, activeHwnd := 0) {
    global tbcEverythingAdjustSourceTick

    ; Reject a missing or already-handled typing tick so one physical event cannot schedule duplicate adjustment requests.
    if (!sourceTick || tbcEverythingAdjustSourceTick = sourceTick)
        return false

    ; Ignore hotkeys that do not edit Everything's search text because they do not require a deferred column adjustment.
    if (!_IsEverythingEditAdjustTrigger(hotkey))
        return false

    ; Require an exact active-window and focused-control snapshot so deferred work is never armed for an ambiguous target.
    if !CaptureActiveFocusSnapshot(targetHwnd, targetCtrlNN, targetCtrlHwnd, targetCtrlClass, activeHwnd)
        return false

    ; Restrict this typing-driven adjustment to Everything's Edit1 search field so other focused controls remain unaffected.
    if (targetCtrlNN != "Edit1")
        return false

    return _RequestEverythingEditAdjust(sourceTick, targetHwnd, targetCtrlNN, targetCtrlHwnd, targetCtrlClass)
}

; Everything Edit1 tbc-work validator:
; require the same active search box, the same request token, and when possible
; the same exact control HWND/class before the deferred Ctrl+NumpadAdd send runs.
_IsTbcEverythingEditAdjustStillValid(expectedId := 0) {
    global k_tbcEverythingAdjustMaxAgeMs
    global tbcEverythingAdjustCtrlNN
    global tbcEverythingAdjustCtrlClass
    global tbcEverythingAdjustCtrlHwnd
    global tbcEverythingAdjustHwnd
    global tbcEverythingAdjustId
    global tbcEverythingAdjustRequestedTick

    currentId := tbcEverythingAdjustId
    if (!expectedId)
        expectedId := currentId

    ; Reject replaced, expired, or retargeted work so a stale deferred callback cannot adjust the wrong window or control.
    if !_IsDeferredWorkStillValid(tbcEverythingAdjustHwnd, tbcEverythingAdjustCtrlNN, expectedId, currentId, tbcEverythingAdjustRequestedTick, k_tbcEverythingAdjustMaxAgeMs)
        return false

    ; Accept the basic window/ClassNN validation when no exact control HWND or class metadata was captured for comparison.
    if (!tbcEverythingAdjustCtrlHwnd && tbcEverythingAdjustCtrlClass = "")
        return true

    ; Capture the current active-window and focused-control identity so the saved exact target metadata can be revalidated.
    if !TryCaptureActiveFocusSnapshotFull(tbcEverythingAdjustHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return false

    ; Reject a different focused ClassNN so the deferred adjustment remains tied to the originally focused control slot.
    if (tbcEverythingAdjustCtrlNN != "" && currentCtrlNN != tbcEverythingAdjustCtrlNN)
        return false

    ; Reject a different focused HWND so a replacement control with the same ClassNN cannot inherit the pending adjustment.
    if (tbcEverythingAdjustCtrlHwnd && currentCtrlHwnd != tbcEverythingAdjustCtrlHwnd)
        return false

    ; Reject a changed control class so the pending adjustment cannot run against a different kind of focused control.
    if (tbcEverythingAdjustCtrlClass != "" && currentCtrlClass != tbcEverythingAdjustCtrlClass)
        return false

    return true
}

; Deferred Everything Edit1 native column auto-fit flush:
; after a short debounce, confirm the same search field still owns focus, then
; resize the results ListView without keyboard injection.
FlushTbcEverythingEditAdjust:
    currentRequestId := tbcEverythingAdjustId
    ; Stop when no deferred request or target window remains because a previously armed timer may fire after state was cleared.
    if (!currentRequestId || !tbcEverythingAdjustHwnd)
        Return

    ; Reject an invalid target, token, or request age before waiting or sending so stale work cannot reach the wrong context.
    if (!_IsTbcEverythingEditAdjustStillValid(currentRequestId))
    {
        ; Clear invalid state only while this callback still owns the request slot so a newer replacement request is preserved.
        if (currentRequestId = tbcEverythingAdjustId)
            _ClearTbcEverythingEditAdjustState()
        Return
    }

    ; Resize the native results ListView directly so the search Edit1 never receives NumpadAdd as typed text.
    if (_TryAutoFitEverythingResultsColumns(tbcEverythingAdjustHwnd))
    {
        ; Clear completed state only while this callback still owns the request slot so a newer request remains pending.
        if (currentRequestId = tbcEverythingAdjustId)
            _ClearTbcEverythingEditAdjustState(True)
        Return
    }

    ; Stop if a newer request replaced this one during the send attempt so this stale callback cannot alter its state or timer.
    if (currentRequestId != tbcEverythingAdjustId)
        Return

    ; Revalidate after the failed direct resize because its guarded checks may have outlived the original focus or request lifetime.
    if (!_IsTbcEverythingEditAdjustStillValid(currentRequestId))
    {
        _ClearTbcEverythingEditAdjustState()
        Return
    }

    ; Retry briefly while Everything's results ListView/header are still settling.
    if ((A_TickCount - tbcEverythingAdjustRequestedTick) < k_tbcEverythingAdjustMaxAgeMs) {
        SetTimer, FlushTbcEverythingEditAdjust, % -k_tbcEverythingAdjustRetryMs
        Return
    }

    ; A valid Everything window without a ready native results ListView should not fall back to
    ; Ctrl+NumpadAdd while Edit1 is focused, because that can type a literal "+" into search.
    _ClearTbcEverythingEditAdjustState(True)
Return

KeyTrack() {
    global StopAutoFix, TimeOfLastHotkeyTyped

    ListLines, Off

    activeHwnd := WinExist("A")
    WinGetClass, currClass, ahk_id %activeHwnd%
    If (InStr(currClass, "EVERYTHING", True)) {
        StopAutoFix := True
        ; Everything/Edit1 qualifies the key event, captures the exact
        ; current search-box identity once, and lets the debounce timer resize
        ; the native results ListView after the search text has had a moment
        ; to settle.
        if (!_TryRequestEverythingEditAdjust(TimeOfLastHotkeyTyped, A_ThisHotkey, activeHwnd))
        {
            if (!_IsDeferredWorkStillValid(activeHwnd, "Edit1"))
                _ClearTbcEverythingEditAdjustState()
        }
        StopAutoFix := False
    }
    Else If (currClass == "XLMAIN") {
        _ClearTbcEverythingEditAdjustState()
        StopAutoFix := True
    }
    Else {
        _ClearTbcEverythingEditAdjustState()
        StopAutoFix := False
    }

    ListLines, On
Return
}


; Retry plain-text clipboard writes a few times so transient clipboard locks do
; not terminate the script with a SetClipboardData exception.
_TrySetClipboardText(text, retries := 6, sleepMs := 15)
{
    Loop, %retries% {
        try {
            Clipboard := text
            ClipWait, 0.1
            if (Clipboard == text)
                return True
        } catch e {
        }
        Sleep, %sleepMs%
    }
    return False
}

; Copies the selection or pastes text through a managed Ctrl chord.
; modifiersToSync selects the physical modifier families reasserted after the
; chord; an empty string leaves them logically up for Alt/Shift hotkey callers.
; expectedWindowId cancels the chord if a different window becomes foreground.
Clip(Text := "", Reselect := "", Restore := "", modifiersToSync := "Shift Alt Ctrl Win", expectedWindowId := 0)
{
    global clipPreferExplicitCtrlV, clipPasteControlHwnd, clipLastReadSucceeded, clipRestoreTimerPending
    static BackUpClip := "", Stored := False, LastClip := "", Restored := ""

    if (Restore) {
        if (Clipboard == LastClip)
            Clipboard := BackUpClip
        BackUpClip := "", LastClip := "", Stored := ""
        SetTimer, ClipRestore, Off
        clipRestoreTimerPending := False
        Return
    } else {
        clipResult := ""
        isReadCall := (Text = "")
        if (isReadCall)
            clipLastReadSucceeded := False
        isExplicitCopyReadTarget := (isReadCall && expectedWindowId && (IsWindowClassName(expectedWindowId, "MozillaWindowClass") || IsWindowProcessName(expectedWindowId, "notepad.exe")))

        if (expectedWindowId && !IsForegroundWindow(expectedWindowId))
            return ""

        if !Stored {
            Stored := True
            ; ClipboardAll must be on its own line in v1
            BackUpClip := ClipboardAll
        } else {
            ; cancel any tbc restore before starting a new clipboard transaction
            SetTimer, ClipRestore, Off
            clipRestoreTimerPending := False
        }

        if (isReadCall) {
            ; Clear only before reads so ClipWait measures the fresh managed
            ; copy result. Write calls can replace the clipboard directly
            ; without this extra churn.
            clearStartTick := A_TickCount
            Clipboard := ""
            clearMs := A_TickCount - clearStartTick

            ; A copy chord after a focus change would read from an unrelated
            ; application, so restore the saved clipboard and stop instead.
            if (expectedWindowId && !IsForegroundWindow(expectedWindowId)) {
                Clip("", "", "RESTORE")
                return ""
            }

            WrapDebugLog("clip_read send explicit=" . isExplicitCopyReadTarget . " hwnd=" . expectedWindowId . " process=" . GetWindowProcessName(expectedWindowId) . " class=" . GetWindowClassName(expectedWindowId))
            if !_SendManagedCtrlChord("c", 6, isExplicitCopyReadTarget, modifiersToSync, expectedWindowId) {
                WrapDebugLog("clip_read send_failed hwnd=" . expectedWindowId . " process=" . GetWindowProcessName(expectedWindowId))
                Clip("", "", "RESTORE")
                return ""
            }
            if (isExplicitCopyReadTarget) {
                ClipWait, 1.0, 1
            } else if (clearMs > 50) {
                ClipWait, 0.6, 1
            } else {
                ClipWait, 0.2, 1
            }
            clipLastReadSucceeded := !ErrorLevel
            WrapDebugLog("clip_read wait_done success=" . clipLastReadSucceeded . " errorLevel=" . ErrorLevel . " textLen=" . StrLen(Clipboard) . " hwnd=" . expectedWindowId . " process=" . GetWindowProcessName(expectedWindowId))

            if (!clipLastReadSucceeded && IsWindowProcessName(expectedWindowId, "notepad.exe")) {
                Clipboard := ""
                WrapDebugLog("clip_read retry=ctrl_insert hwnd=" . expectedWindowId . " process=" . GetWindowProcessName(expectedWindowId))
                if (expectedWindowId && !IsForegroundWindow(expectedWindowId)) {
                    Clip("", "", "RESTORE")
                    return ""
                }
                if _SendManagedCtrlChord("{Insert}", 6, True, modifiersToSync, expectedWindowId) {
                    ClipWait, 1.0, 1
                    clipLastReadSucceeded := !ErrorLevel
                    WrapDebugLog("clip_read retry_done method=ctrl_insert success=" . clipLastReadSucceeded . " errorLevel=" . ErrorLevel . " textLen=" . StrLen(Clipboard) . " hwnd=" . expectedWindowId)
                } else {
                    WrapDebugLog("clip_read retry_send_failed method=ctrl_insert hwnd=" . expectedWindowId)
                }

                if (!clipLastReadSucceeded) {
                    Clipboard := ""
                    if _TryCopyFocusedControlSelectionWithWmCopy(expectedWindowId) {
                        ClipWait, 1.0, 1
                        clipLastReadSucceeded := !ErrorLevel
                        WrapDebugLog("clip_read retry_done method=wm_copy success=" . clipLastReadSucceeded . " errorLevel=" . ErrorLevel . " textLen=" . StrLen(Clipboard) . " hwnd=" . expectedWindowId)
                    } else {
                        WrapDebugLog("clip_read retry_send_failed method=wm_copy hwnd=" . expectedWindowId)
                    }
                }
            }
        } else {
            LastClip := Text
            if !_TrySetClipboardText(Text) {
                Clip("", "", "RESTORE")
                return ""
            }
            ClipWait, 10

            ; Clipboard writes can take long enough for the user to change
            ; windows. Never send Ctrl+V to that newly foreground target.
            if (expectedWindowId && !IsForegroundWindow(expectedWindowId)) {
                Clip("", "", "RESTORE")
                return ""
            }

            if (expectedWindowId && IsWindowProcessName(expectedWindowId, "BCompare.exe")) {
                bcompareAltPhysical   := (GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P")) ? 1 : 0
                bcompareShiftPhysical := (GetKeyState("LShift", "P") || GetKeyState("RShift", "P")) ? 1 : 0
                bcompareAltLogical    := (GetKeyState("LAlt") || GetKeyState("RAlt")) ? 1 : 0
                bcompareShiftLogical  := (GetKeyState("LShift") || GetKeyState("RShift")) ? 1 : 0
                WrapDebugLog("clip_write paste bcompare_pre altP=" . bcompareAltPhysical . " shiftP=" . bcompareShiftPhysical . " altL=" . bcompareAltLogical . " shiftL=" . bcompareShiftLogical . " hwnd=" . expectedWindowId)
                SendInput, {Blind}{sc02A up}{sc036 up}{sc038 up}{sc138 up}
                Sleep, 20
                SendEvent, ^v
                didPaste := IsForegroundWindow(expectedWindowId)
                WrapDebugLog("clip_write paste method=sendevent_ctrl_v didPaste=" . didPaste . " hwnd=" . expectedWindowId . " process=" . GetWindowProcessName(expectedWindowId))
            } else if (clipPasteControlHwnd) {
                if _IsExpectedFocusedControl(expectedWindowId, clipPasteControlHwnd) {
                    ControlSend,, ^v, ahk_id %clipPasteControlHwnd%
                    controlSendError := ErrorLevel
                    didPaste := !controlSendError
                    WrapDebugLog("clip_write paste controlsend_steps method=controlsend_chord error=" . controlSendError . " hwnd=" . expectedWindowId)
                } else {
                    controlSendError := "target_gone"
                    didPaste := False
                }
                WrapDebugLog("clip_write paste path=controlsend controlHwnd=" . clipPasteControlHwnd . " controlClass=" . GetWindowClassName(clipPasteControlHwnd) . " error=" . controlSendError . " didPaste=" . didPaste . " hwnd=" . expectedWindowId . " process=" . GetWindowProcessName(expectedWindowId))
            } else if (clipPreferExplicitCtrlV)
                ; Some modern editors misread {Blind}v and occasionally type
                ; a literal v, so use an explicit managed Ctrl+V chord.
                didPaste := _SendManagedCtrlChord("v", 6, True, modifiersToSync, expectedWindowId)
            else
                didPaste := _SendManagedCtrlChord("v", 6, False, modifiersToSync, expectedWindowId)
            if (!clipPasteControlHwnd)
                WrapDebugLog("clip_write paste explicit=" . clipPreferExplicitCtrlV . " didPaste=" . didPaste . " hwnd=" . expectedWindowId . " process=" . GetWindowProcessName(expectedWindowId))
            if !didPaste {
                Clip("", "", "RESTORE")
                return ""
            }
            Sleep, 20  ; small buffer in case more keystrokes (e.g., Enter) follow a paste
        }

        ; schedule a one-shot restore in ~700ms
        WrapDebugLog("clip_restore schedule delayMs=700 isRead=" . isReadCall . " hwnd=" . expectedWindowId . " process=" . GetWindowProcessName(expectedWindowId))
        SetTimer, ClipRestore, -700
        clipRestoreTimerPending := True

        if (isReadCall) {
            ; return the copied text, normalizing CR only when present
            clipResult := Clipboard
            if InStr(clipResult, "`r")
                clipResult := StrReplace(clipResult, "`r")
            LastClip := clipResult
        } else {
            if ((Reselect = True) || (Reselect && (StrLen(Text) < 3000))) {
                Text := StrReplace(Text, "`r")
                SendInput, % "{Shift Down}{Left " StrLen(Text) "}{Shift Up}"
            }
        }
    }
    return clipResult
}
ClipRestore:
    Clip("", "", "RESTORE")
    ClipjumpRestoreAfterWrapper()
return

IsEditFieldActive() {
    ControlGetFocus, FocusedControl, A
    If (RegExMatch(FocusedControl, "^Edit\d+$"))
        Return True
    Else
        Return False
}
IsGoogleDocWindow() {
    WinGetTitle, title, A
    If InStr(title, "Google Sheets", False) || InStr(title, "Google Docs", False)
        Return True
    Else
        Return False
}

; Startup, activation, and pointer-focus changes prewarm the hotstring
; eligibility cache after focus settles. Slow UIA/MSAA checks run later through
; FlushTypingAutoFixRefresh, never inside ShouldRunHotstringAutoCorrect(). If a
; hotstring is evaluated first, an unknown custom control remains eligible while
; GetHotstringEligibilityFastOrQueue() queues the same background check.

; Prewarm the eligibility cache before a hotstring needs to evaluate it. Startup,
; activation, and pointer-focus changes all schedule this label after focus settles.
PrewarmTypingAutoFixContext:
    prewarmStartHotstringBoundarySeq  := typingAutoFixPrewarmStartHotstringBoundarySeq
    prewarmStartTypingSeq             := typingAutoFixPrewarmStartTypingSeq
    WinGet, prewarmHwnd, ID, A
    if (!prewarmHwnd)
        Return

    if !_TypingAutoFixTryGetFocusedControlIdentity(prewarmHwnd, prewarmCtrlNN , prewarmCtrlHwnd, prewarmCtrlClass)
        Return

    GetTypingAutoFixEligibilityFastOrQ(prewarmHwnd, prewarmCtrlNN
        , prewarmCtrlHwnd, prewarmCtrlClass, A_TickCount
        , prewarmStartTypingSeq, prewarmStartHotstringBoundarySeq)
Return

; Runs after the requested separator key event completes, then discards the
; hotstring recognition buffer so the following word starts with a clean buffer.
ResetHotstringBufferAfterBoundary:
    hotstringResetTimerPending := False
    if (hotstringResetAtBoundarySeq && hotstringBoundarySeq >= hotstringResetAtBoundarySeq)
    {
        hotstringResetAtBoundarySeq := 0
        Hotstring("Reset")
    }
Return

FlushTypingAutoFixRefresh:
    tbcRefreshCtrlClass                  := typingAutoFixRefreshCtrlClass
    tbcRefreshCtrlHwnd                   := typingAutoFixRefreshCtrlHwnd
    tbcRefreshCtrlNN                     := typingAutoFixRefreshCtrlNN
    tbcRefreshHwnd                       := typingAutoFixRefreshHwnd
    tbcRefreshId                         := typingAutoFixRefreshId
    tbcRefreshProtectPartialWord         := typingAutoFixRefreshProtectPartialWord
    tbcRefreshRequestedTick                 := typingAutoFixRefreshRequestedTick
    tbcRefreshStartHotstringBoundarySeq  := typingAutoFixRefreshStartHotstringBoundarySeq
    tbcRefreshStartTypingSeq             := typingAutoFixRefreshStartTypingSeq

    if (!tbcRefreshHwnd)
        Return

    ; Retry while physical typing is still in flight so the slow accessibility
    ; probe does not jump back onto the same burst of live key handling.
    if (!_IsDeferredTypingQuiet(k_typingAutoFixRefreshDelayMs))
    {
        SetTimer, FlushTypingAutoFixRefresh, % -k_typingAutoFixRefreshDelayMs
        Return
    }

    ; ClassNN alone can be reused when a custom control is recreated. Require
    ; the exact top-level window, control name, control HWND, and control class.
    if !_TypingAutoFixTargetStillFocused(tbcRefreshHwnd, tbcRefreshCtrlNN , tbcRefreshCtrlHwnd, tbcRefreshCtrlClass)
    {
        if (tbcRefreshId = typingAutoFixRefreshId)
            _ClearTbcTypingAutoFixRefresh()
        Return
    }

    ; If a newer async refresh request replaced this one, exit without touching
    ; the cache so only the newest focus context can update it.
    if (tbcRefreshCtrlClass                  != typingAutoFixRefreshCtrlClass
     || tbcRefreshCtrlHwnd                   != typingAutoFixRefreshCtrlHwnd
     || tbcRefreshCtrlNN                     != typingAutoFixRefreshCtrlNN
     || tbcRefreshHwnd                       != typingAutoFixRefreshHwnd
     || tbcRefreshId                         != typingAutoFixRefreshId
     || tbcRefreshProtectPartialWord         != typingAutoFixRefreshProtectPartialWord
     || tbcRefreshRequestedTick              != typingAutoFixRefreshRequestedTick
     || tbcRefreshStartHotstringBoundarySeq  != typingAutoFixRefreshStartHotstringBoundarySeq
     || tbcRefreshStartTypingSeq             != typingAutoFixRefreshStartTypingSeq)
        Return

    RefreshTypingAutoFixContext(tbcRefreshHwnd, tbcRefreshCtrlNN
        , tbcRefreshCtrlHwnd, tbcRefreshCtrlClass
        , tbcRefreshProtectPartialWord, tbcRefreshStartTypingSeq
        , tbcRefreshStartHotstringBoundarySeq)

    if (tbcRefreshId = typingAutoFixRefreshId)
        _ClearTbcTypingAutoFixRefresh()
Return

; Recompute the cached typing-auto-fix eligibility decision for the current
; focused window/control using a cheap-first/slow-fallback split.
;
; What this function does:
; 1) refreshes the cached context fields (allowed, hwnd, ctrlNN, control HWND,
;    reason, tick)
; 2) returns the final allowed boolean for this focused target
;
; Flow shape inside this function:
; 1) cheap exclusions and classic Edit/RichEdit checks run first
; 2) unchanged context can reuse the cached decision for a short interval
; 3) only then does the function pay for the slower UIA/MSAA editability checks
;
; Within the typing-auto-fix gating flow, this is the only path that should pay
; for the slower UIA/MSAA editability checks. Other helpers may still call the
; same probes for unrelated caret/edit-detection logic.
RefreshTypingAutoFixContext(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass
    , protectPartialWord := false, startTypingSeq := 0
    , startHotstringBoundarySeq := 0, nowTick := "") {
    global c_typingAutoFixAllowed
    global c_typingAutoFixCtrlHwnd
    global c_typingAutoFixCtrlNN
    global c_typingAutoFixHwnd
    global c_typingAutoFixReason
    global c_typingAutoFixTick
    global k_typingAutoFixSlowPathMs
    global typingAutoFixSlowProbeTick

    ; Normalize the timestamp so all cache writes for this pass share one tick value.
    if (nowTick = "")
        nowTick := A_TickCount

    if !activeHwnd
        return _TypingAutoFixSetCache(0, "", 0, false, "no_active_window", nowTick)

    ; Do not inspect accessibility state unless the exact queued control still
    ; owns focus. A failed ControlGetFocus/ControlGet is treated as not proven.
    if !_TypingAutoFixTargetStillFocused(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass)
        return false

    ; Cheap process-level exclusions should exit before any focus/editability probing.
    WinGet, processName, ProcessName, ahk_id %activeHwnd%
    if (_TypingAutoFixIsExcludedProcess(processName))
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, false, "excluded_process", nowTick)

    ; Google Docs/Sheets keep their own editing model and are intentionally excluded.
    WinGetTitle, title, ahk_id %activeHwnd%
    if (InStr(title, "Google Sheets", False) || InStr(title, "Google Docs", False))
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, false, "google_docs", nowTick)

    ; Classic Win32 edit controls are the cheapest positive match, so allow them immediately.
    if (IsClassicEditControlClass(ctrlClass)) {
        hotstringResetAtBoundarySeq := 0
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, true, "classic_edit", nowTick)
    }

    ; Once the window/control pair is unchanged, reuse the prior decision until the
    ; slower UIA/MSAA re-probe interval expires. A queued "tbc_refresh"
    ; context is the exception because that marker means this focus target still
    ; needs one real probe before cached reuse is allowed.
    contextChanged := (activeHwnd != c_typingAutoFixHwnd
        || ctrlNN != c_typingAutoFixCtrlNN
        || ctrlHwnd != c_typingAutoFixCtrlHwnd)
    tbcRefreshContext := (c_typingAutoFixReason = "tbc_refresh")
    if (!contextChanged && !tbcRefreshContext && (nowTick - typingAutoFixSlowProbeTick) < k_typingAutoFixSlowPathMs)
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd , c_typingAutoFixAllowed, c_typingAutoFixReason, nowTick)

    ; A new context or expired slow-path TTL means it is time to refresh accessibility state.
    typingAutoFixSlowProbeTick := nowTick

    ; UIA is the preferred slow-path signal for custom editors that expose editability.
    uiaEditable := UIA_IsFocusedEditable()
    if !_TypingAutoFixTargetStillFocused(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass)
        return false

    if (uiaEditable) {
        _SetHotstringResetTimingAfterAsyncProbe(protectPartialWord , startTypingSeq, startHotstringBoundarySeq)
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, true, "uia_editable", nowTick)
    }

    ; MSAA stays as a weaker fallback when UIA is missing or incomplete.
    msaaEditable := MSAA_IsFocusedEditable()
    if !_TypingAutoFixTargetStillFocused(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass)
        return false

    if (msaaEditable) {
        _SetHotstringResetTimingAfterAsyncProbe(protectPartialWord , startTypingSeq, startHotstringBoundarySeq)
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, true, "msaa_editable", nowTick)
    }

    ; No writable ValuePattern, TextEditPattern, or non-read-only MSAA text/edit
    ; role was found. Cache this exact target as ineligible so
    ; ShouldRunHotstringAutoCorrect() rejects its hotstrings.
    return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, false, "not_editable", nowTick)
}

/*
Hotstring eligibility flow
==========================

startup / window activation / pointer-focus change
    |
    +--> PrewarmTypingAutoFixContext
            |
            +--> GetTypingAutoFixEligibilityFastOrQ
                    |
                    +--> use a cheap known result, or cache the new target
                    |    as unconfirmed while queueing its refresh
                    +--> QueueTypingAutoFixRefresh
                            |
                            +--> FlushTypingAutoFixRefresh
                                    |
                                    +--> RefreshTypingAutoFixContext
                                            |
                                            +--> cache eligible/ineligible for
                                                 the exact window/control HWND

hotstring trigger
    |
    +--> #If ShouldRunHotstringAutoCorrect()
            |
            +--> reject immediate exclusions
            +--> allow a classic RichEdit control
            +--> GetHotstringEligibilityFastOrQueue
                    |
                    +--> confirmed exact-target cache --> return cached result
                    +--> unconfirmed custom control ---> queue/reuse the refresh
                                                         and return true (fail open)

The live #If path never runs UIA/MSAA. Unknown custom controls fail open while
their background probe is pending, preventing a slow accessibility call from
blocking keyboard input or disabling the hotstring table globally. The prewarm
cache may temporarily contain false for that target, but the live predicate
does not use that unconfirmed value until the probe produces a confirmed result.
*/

; Returns a confirmed cached editability answer for the exact focused target
; without running UIA/MSAA on the hotstring key path. A new or unclassified
; custom target remains enabled while one matching background probe is pending;
; a later "not_editable" result disables hotstrings for that exact target.
GetHotstringEligibilityFastOrQueue(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass
    , nowTick := "") {
    global c_typingAutoFixAllowed
    global c_typingAutoFixCtrlHwnd
    global c_typingAutoFixCtrlNN
    global c_typingAutoFixHwnd
    global c_typingAutoFixReason
    global c_typingAutoFixTick
    global k_typingAutoFixFastTtlMs
    global typingAutoFixRefreshCtrlHwnd
    global typingAutoFixRefreshCtrlNN
    global typingAutoFixRefreshHwnd

    if (nowTick = "")
        nowTick := A_TickCount

    sameContext := (activeHwnd = c_typingAutoFixHwnd
        && ctrlNN = c_typingAutoFixCtrlNN
        && ctrlHwnd = c_typingAutoFixCtrlHwnd)
    confirmedReason := (c_typingAutoFixReason = "classic_edit"
        || c_typingAutoFixReason = "excluded_process"
        || c_typingAutoFixReason = "google_docs"
        || c_typingAutoFixReason = "msaa_editable"
        || c_typingAutoFixReason = "not_editable"
        || c_typingAutoFixReason = "uia_editable")
    confirmedContext := (sameContext && confirmedReason)

    cacheExpired := (!confirmedContext || (nowTick - c_typingAutoFixTick) > k_typingAutoFixFastTtlMs)
    sameRefreshPending := (activeHwnd = typingAutoFixRefreshHwnd
        && ctrlNN = typingAutoFixRefreshCtrlNN
        && ctrlHwnd = typingAutoFixRefreshCtrlHwnd)

    ; Do not keep resetting the one-shot timer while the user is typing. The
    ; existing matching request will run as soon as physical input is quiet.
    if (cacheExpired && !sameRefreshPending)
        QueueTypingAutoFixRefresh(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass , nowTick, false)

    if (confirmedContext)
        return c_typingAutoFixAllowed

    ; Failing open here prevents an unknown custom editor from globally
    ; suppressing hotstrings before its deferred accessibility check completes.
    return true
}

; Returns true only when the large hotstring autocorrect table should be active
; for the current focus target.
ShouldRunHotstringAutoCorrect() {
    global SearchingWindows
    global hitTAB
    global hitTilde
    global StopAutoFix

    ; Suspend the hotstring table during window-search / Alt-Tab style modes and while
    ; the script is intentionally suppressing auto-fix side effects.
    if (SearchingWindows || hitTAB || hitTilde || StopAutoFix)
        return false

    ; Modifier-held states are intentionally excluded so navigation chords do not
    ; accidentally trigger word replacements.
    if (GetKeyState("LAlt", "P") || GetKeyState("Control", "P"))
        return false

    ; Browser-based Google editors have their own text stack and are intentionally excluded.
    if (IsGoogleDocWindow())
        return false

    ; If there is no active window, there is no hotstring context to attach to.
    WinGet, activeHwnd, ID, A
    if !activeHwnd
        return false

    ; Cheap process exclusions keep the giant hotstring table out of terminals and
    ; known apps where raw typing stability matters more.
    WinGet, processName, ProcessName, ahk_id %activeHwnd%
    if (_HotstringAutoCorrectIsExcludedProcess(processName) || _TypingAutoFixIsExcludedProcess(processName))
        return false

    ; Capture one guarded identity snapshot. A transient focus lookup failure is
    ; treated as unknown and therefore must not disable every hotstring.
    if !_TypingAutoFixTryGetFocusedControlIdentity(activeHwnd, ctrlNN , ctrlHwnd, ctrlClass)
        return true

    ; Preserve the long-standing exclusion for plain Edit controls while still
    ; allowing RichEdit controls and accessibility-backed custom editors.
    if (InStr(ctrlNN, "Edit", True) && !InStr(ctrlNN, "Rich", True))
        return false

    if (IsClassicEditControlClass(ctrlClass))
        return true

    return GetHotstringEligibilityFastOrQueue(activeHwnd, ctrlNN, ctrlHwnd , ctrlClass, A_TickCount)
}

; Keep the hotstring table out of console/terminal-style apps where raw typing
; stability matters more than word replacement.
_HotstringAutoCorrectIsExcludedProcess(processName) {
    return (processName = "bash.exe"
         || processName = "cmd.exe"
         || processName = "Code.exe"
         || processName = "Conhost.exe"
         || processName = "mintty.exe"
         || processName = "notepad++.exe")
}

_TypingAutoFixIsExcludedProcess(processName) {
    return (processName = "Code.exe"
         || processName = "EXCEL.EXE"
         || processName = "notepad++.exe"
         || processName = "WINWORD.EXE")
}

; Clears the queued async editability refresh so an older focus context cannot
; continue to hold onto a probe request after the caller already resolved the
; current window/control state through a cheap live-key classification.
_ClearTbcTypingAutoFixRefresh() {
    global typingAutoFixRefreshCtrlClass
    global typingAutoFixRefreshCtrlHwnd
    global typingAutoFixRefreshCtrlNN
    global typingAutoFixRefreshHwnd
    global typingAutoFixRefreshProtectPartialWord
    global typingAutoFixRefreshRequestedTick
    global typingAutoFixRefreshStartHotstringBoundarySeq
    global typingAutoFixRefreshStartTypingSeq

    typingAutoFixRefreshCtrlClass                  := ""
    typingAutoFixRefreshCtrlHwnd                   := 0
    typingAutoFixRefreshCtrlNN                     := ""
    typingAutoFixRefreshHwnd                       := 0
    typingAutoFixRefreshProtectPartialWord         := False
    typingAutoFixRefreshRequestedTick              := 0
    typingAutoFixRefreshStartHotstringBoundarySeq  := 0
    typingAutoFixRefreshStartTypingSeq             := 0
}

; Returns quickly on the prewarm/focus-change path by using cheap exclusions and
; the cached result first, then queueing any slower UIA/MSAA refresh onto a short
; timer. The live #If predicate uses GetHotstringEligibilityFastOrQueue().
; Eligibility bridge:
; A new control is temporarily cached as false while deferred UIA/MSAA
; editability is checked. The queued refresh compares its captured physical
; typing/boundary counters with the counters maintained by LL_KeyboardHook().
; If typing began during the probe, the next EndChar schedules a deferred buffer
; reset after that key event finishes.
GetTypingAutoFixEligibilityFastOrQ(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass
    , nowTick := "", protectStartTypingSeq := ""
    , protectStartHotstringBoundarySeq := "") {
    global c_typingAutoFixAllowed
    global c_typingAutoFixCtrlHwnd
    global c_typingAutoFixCtrlNN
    global c_typingAutoFixHwnd
    global c_typingAutoFixTick
    global hotstringResetAtBoundarySeq
    global k_typingAutoFixFastTtlMs
    global k_typingAutoFixSlowPathMs
    global typingAutoFixSlowProbeTick

    if (nowTick = "")
        nowTick := A_TickCount

    if !activeHwnd {
        _ClearTbcTypingAutoFixRefresh()
        hotstringResetAtBoundarySeq := 0
        return _TypingAutoFixSetCache(0, "", 0, false, "no_active_window", nowTick)
    }

    ; Fast same-target reuse keeps most keystrokes off the slower probe path.
    if (activeHwnd = c_typingAutoFixHwnd
     && ctrlNN     = c_typingAutoFixCtrlNN
     && ctrlHwnd   = c_typingAutoFixCtrlHwnd
     && (nowTick - c_typingAutoFixTick) <= k_typingAutoFixFastTtlMs)
        return c_typingAutoFixAllowed

    ; Cheap process exclusions resolve synchronously and do not need an async probe.
    WinGet, processName, ProcessName, ahk_id %activeHwnd%
    if (_TypingAutoFixIsExcludedProcess(processName)) {
        _ClearTbcTypingAutoFixRefresh()
        hotstringResetAtBoundarySeq := 0
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, false, "excluded_process", nowTick)
    }

    ; Google Docs/Sheets keep their own editing model and are intentionally excluded.
    WinGetTitle, title, ahk_id %activeHwnd%
    if (InStr(title, "Google Sheets", False) || InStr(title, "Google Docs", False)) {
        _ClearTbcTypingAutoFixRefresh()
        hotstringResetAtBoundarySeq := 0
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, false, "google_docs", nowTick)
    }

    ; Classic Win32 edit controls are still the cheapest positive match.
    if (IsClassicEditControlClass(ctrlClass)) {
        _ClearTbcTypingAutoFixRefresh()
        hotstringResetAtBoundarySeq := 0
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, true, "classic_edit", nowTick)
    }

    contextChanged := (activeHwnd != c_typingAutoFixHwnd
        || ctrlNN != c_typingAutoFixCtrlNN
        || ctrlHwnd != c_typingAutoFixCtrlHwnd)
    if (contextChanged) {
        QueueTypingAutoFixRefresh(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass
            , nowTick, true, protectStartTypingSeq
            , protectStartHotstringBoundarySeq)
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, false, "tbc_refresh", nowTick)
    }

    ; Same context but older cache: keep the current answer for this keypress and
    ; refresh in the background once the slower probe interval has expired.
    if ((nowTick - typingAutoFixSlowProbeTick) >= k_typingAutoFixSlowPathMs)
        QueueTypingAutoFixRefresh(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass, nowTick)

    return c_typingAutoFixAllowed
}

; Persist the current typing-auto-fix decision so the hotkey predicate can usually
; return with a cheap same-window/same-control cache hit.
;
; `allowed` is decided by the caller before this helper runs. In the current flow,
; it becomes true when any one of the following applies:
; 1) the focused control is a classic Edit/RichEdit-style class
; 2) UIA reports a writable ValuePattern or a TextEditPattern on the same element
; 3) MSAA reports a non-read-only text/edit role on the same focused control
; 4) the same window/control context is being reused and the cached allowed value
;    was already true
_TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, allowed, reason , nowTick := "") {
    global c_typingAutoFixAllowed
    global c_typingAutoFixCtrlHwnd
    global c_typingAutoFixCtrlNN
    global c_typingAutoFixHwnd
    global c_typingAutoFixReason
    global c_typingAutoFixTick

    if (nowTick = "")
        nowTick := A_TickCount

    c_typingAutoFixAllowed  := allowed
    c_typingAutoFixCtrlHwnd := ctrlHwnd
    c_typingAutoFixCtrlNN   := ctrlNN
    c_typingAutoFixHwnd     := activeHwnd
    c_typingAutoFixReason   := reason
    c_typingAutoFixTick     := nowTick

    return allowed
}

; After a protected async probe, arrange a clean hotstring buffer boundary if
; physical typing began before the editor result was available.
_SetHotstringResetTimingAfterAsyncProbe(protectPartialWord, startTypingSeq , startHotstringBoundarySeq) {
    global hotstringBoundarySeq, hotstringResetAtBoundarySeq
    global hotstringResetTimerPending
    global physicalTypingSeq

    if (!protectPartialWord)
        return

    SetTimer, ResetHotstringBufferAfterBoundary, Off
    hotstringResetTimerPending := False

    ; No physical text arrived, or the user already completed a separator. The
    ; positive result can be used immediately without carrying a word fragment.
    if (physicalTypingSeq <= startTypingSeq || hotstringBoundarySeq > startHotstringBoundarySeq)
    {
        hotstringResetAtBoundarySeq := 0
        Hotstring("Reset")
        return
    }

    ; Text arrived without a separator, so reset the recognition buffer after the
    ; next physical EndChar finishes processing.
    hotstringResetAtBoundarySeq := hotstringBoundarySeq + 1
}

; Stores the latest async editability-refresh request and resets the one-shot
; timer so newer focus contexts supersede older queued probes. The optional
; physical-input snapshots preserve whether typing began before focus settled.
QueueTypingAutoFixRefresh(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass
    , nowTick := "", protectPartialWord := false, startTypingSeq := ""
    , startHotstringBoundarySeq := "") {
    global hotstringBoundarySeq, hotstringResetAtBoundarySeq
    global hotstringResetTimerPending
    global physicalTypingSeq
    global typingAutoFixRefreshCtrlClass
    global typingAutoFixRefreshCtrlHwnd
    global typingAutoFixRefreshCtrlNN
    global k_typingAutoFixRefreshDelayMs
    global typingAutoFixRefreshHwnd
    global typingAutoFixRefreshId
    global typingAutoFixRefreshProtectPartialWord
    global typingAutoFixRefreshRequestedTick
    global typingAutoFixRefreshStartHotstringBoundarySeq
    global typingAutoFixRefreshStartTypingSeq

    if (nowTick = "")
        nowTick := A_TickCount

    if (startTypingSeq = "")
        startTypingSeq := physicalTypingSeq
    if (startHotstringBoundarySeq = "")
        startHotstringBoundarySeq := hotstringBoundarySeq

    if (protectPartialWord) {
        ; A newer focus context supersedes any pending buffer reset belonging to
        ; the prior control. The probe result will choose the new reset timing.
        SetTimer, ResetHotstringBufferAfterBoundary, Off
        hotstringResetTimerPending := False
        hotstringResetAtBoundarySeq := 0
        Hotstring("Reset")
    }

    typingAutoFixRefreshId                 += 1
    typingAutoFixRefreshCtrlClass          := ctrlClass
    typingAutoFixRefreshCtrlHwnd           := ctrlHwnd
    typingAutoFixRefreshCtrlNN             := ctrlNN
    typingAutoFixRefreshHwnd               := activeHwnd
    typingAutoFixRefreshProtectPartialWord := protectPartialWord
    typingAutoFixRefreshRequestedTick         := nowTick
    typingAutoFixRefreshStartHotstringBoundarySeq := startHotstringBoundarySeq
    typingAutoFixRefreshStartTypingSeq             := startTypingSeq
    SetTimer, FlushTypingAutoFixRefresh, % -k_typingAutoFixRefreshDelayMs
}

; Captures one exact focused-control identity for live typing predicates. A
; ControlGetFocus/ControlGet failure returns false instead of terminating the
; current hotkey thread while a custom control is being created or destroyed.
; Chromium/Electron windows can keep Win32 keyboard focus on the top-level
; window while UIA reports an editable descendant. In that specific case,
; ControlGetFocus returns blank, so use the active window itself as the exact
; HWND/class identity and let the later UIA/MSAA probe decide editability.
_TypingAutoFixTryGetFocusedControlIdentity(activeHwnd, ByRef ctrlNN
    , ByRef ctrlHwnd, ByRef ctrlClass) {
    ctrlNN := ""
    ctrlHwnd := 0
    ctrlClass := ""

    if (!activeHwnd || !WinActive("ahk_id " . activeHwnd))
        return false

    try
        ControlGetFocus, ctrlNN, ahk_id %activeHwnd%
    catch
        return false

    if (ctrlNN = "") {
        ctrlHwnd := activeHwnd
    } else {
        try
            ControlGet, ctrlHwnd, Hwnd,, %ctrlNN%, ahk_id %activeHwnd%
        catch
            return false
    }

    if (!ctrlHwnd)
        return false

    try
        WinGetClass, ctrlClass, ahk_id %ctrlHwnd%
    catch
        return false

    return (ctrlClass != "")
}

; Confirms that an async accessibility answer still belongs to the exact control
; captured before the probe. ClassNN alone is insufficient because applications
; can destroy and recreate a custom control under the same ClassNN.
_TypingAutoFixTargetStillFocused(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass) {
    if (!_TypingAutoFixTryGetFocusedControlIdentity(activeHwnd
        , currentCtrlNN, currentCtrlHwnd, currentCtrlClass))
        return false

    return (currentCtrlNN = ctrlNN
        && currentCtrlHwnd = ctrlHwnd
        && currentCtrlClass = ctrlClass)
}
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; CHANGELOG:
;
; Sep 13 2007: Added more misspellings.
;              Added fix for -ign -> -ing that ignores words like "sign".
;              Added word beginnings/endings sections to cover more options.
;              Added auto-accents sectikse by Jim Biancolo (http://www.biancolo.com)
;
; INTRODUCTION
;
; This is an AutoHotKey script that implements AutoCorrect against several
; "Lists of common misspellings":
;
; This does not replace a proper spellchecker such as in Firefox, Word, etc.
; It is usually better to have uncertain typos highlighted by a spellchecker
; than to "correct" them incorrectly so  that they are no longer even caught by
; a spellchecker: it is not the job of an autocorrector to correct *all*
; misspellings, but only those which are very obviously incorrect.
;
; The original Win+H correction-entry feature is retained below as disabled
; reference code. This script does not currently register that hotkey.
;
; Some entries have more than one possible resolution (achive->achieve/archive)
; or are clearly a matter of deliberate personal writing style (wanna, colour)
;
; These have been placed at the end of this file and commented out, so you can
; easily edit and add them back in as you like, tailored to your preferences.
;
; SOURCES
;
; http://en.wikipedia.org/wiki/Wikipedia:Lists_of_common_misspellings
; http://en.wikipedia.org/wiki/Wikipedia:Typo
; Microsoft Office autocorrect list
; Script by jaco0646 http://www.autohotkey.com/forum/topic8057.html
; OpenOffice autocorrect list
; TextTrust press release
; User suggestions.
;
; CONTENTS
;
;   Settings
;   Auto-correct two consecutive capitals (commented out by default)
;   Disabled Win+H reference code
;   Fix for -ign instead of -ing
;   Word endings
;   Word beginnings
;   Accented English words
;   Common Misspellings - the main list
;   Ambiguous entries - commented out
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; Hotstring table
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; Disabled reference: Win+H correction-entry implementation.
;------------------------------------------------------------------------------
; LWin & h::
    ; ; Get the selected text. The clipboard is used instead of "ControlGet Selected"
    ; ; as it works in more editors and word processors, java apps, etc. Save the
    ; ; current clipboard contents to be restored later.
    ; AutoTrim On  ; Delete any leading and trailing whitespace on the clipboard.  Why would you want this?
    ; ClipboardOld = %ClipboardAll%
    ; Clipboard =  ; Must start off blank for detection to work.
    ; Send ^c
    ; ClipWait 1
    ; If ErrorLevel  ; ClipWait timed out.
        ; Return
    ; ; Replace CRLF and/or LF with `n for use in a "send-raw" hotstring:
    ; ; The same is done for any other characters that might otherwise
    ; ; be a problem in raw mode:
    ; StringReplace, Hotstring, Clipboard, ``, ````, All  ; Do this replacement first to avoid interfering with the others below.
    ; StringReplace, Hotstring, Hotstring, `r`n, ``r, All  ; Using `r works better than `n in MS Word, etc.
    ; StringReplace, Hotstring, Hotstring, `n, ``r, All
    ; StringReplace, Hotstring, Hotstring, %A_Tab%, ``t, All
    ; StringReplace, Hotstring, Hotstring, `;, ```;, All
    ; Clipboard = %ClipboardOld%  ; Restore previous contents of clipboard.
    ; ; This will move the InputBox's caret to a more friendly position:
    ; SetTimer, MoveCaret, 10
    ; ; Show the InputBox, providing the default hotstring:
    ; InputBox, Hotstring, New Hotstring, Provide the corrected word on the right side. You can also edit the left side If you wish.`n`nExample entry:`n::teh::the,,,,,,,, ::%Hotstring%::%Hotstring%

    ; If ErrorLevel <> 0  ; The user pressed Cancel.
        ; Return
    ; ; Otherwise, add the hotstring and reload the script:
    ; FileAppend, `n%Hotstring%, %A_ScriptFullPath%  ; Put a `n at the beginning in case file lacks a blank line at its end.
    ; ; it would be best If it overwrote the string you had highlighted with the replacement you just typed in
    ; Reload
    ; Sleep 3000 ; If successful, the reload will close this instance during the Sleep, so the line below will never be reached.
    ; MsgBox, 4,, The hotstring just added appears to be improperly formatted.  Would you like to open the script for editing? Note that the bad hotstring is at the bottom of the script.
    ; IfMsgBox, Yes, Edit
    ; Return

; MoveCaret:
    ; IfWinNotActive, New Hotstring
        ; Return
    ; ; Otherwise, move the InputBox's insertion point to where the user will type the abbreviation.
    ; Send {HOME}
    ; Loop % StrLen(Hotstring) + 4
        ; Send {Right}e
    ; SetTimer, MoveCaret, Off
; Return


#InputLevel 10
#If ShouldRunHotstringAutoCorrect()
#Hotstring R  ; Treat replacement text literally unless a later option overrides it.

;------------------------------------------------------------------------------
; Fix for -ign instead of -ing.
; Words to exclude: (could probably do this by Return without rewrite)
; From: http://www.morewords.com/e nds-with/gn/
;------------------------------------------------------------------------------

#Hotstring B0  ; Turns off automatic backspacing for the following hotstrings.

; Can be suffix exceptions, too, but should correct "-aling" without correcting "-align".
::'ing::
::align::
::antiforeign::
::arming::
::arose::
::arraign::
::assign::
::begin::
::benign::
::bot::
::bots::
::caching::
::campaign::
::cases::
::champaign::
::cite::
::cites::
::codesign::
::coign::
::complain::
::compose::
::condign::
::consign::
::constrain::
::coreign::
::cosign::
::countersign::
::deign::
::deraign::
::design::
::digidesign::
::diner::
::dunk::
::eloign::
::ensign::
::exiting::
::feign::
::foreign::
::indign::
::ing::
::inlined::
::inlining::
::login::
::malign::
::mic::
::misalign::
::outdesign::
::overdesign::
::plugin::
::poke::
::preassign::
::rake::
::realign::
::reassign::
::redesign::
::reign::
::resets::
::resign::
::sings::
::slam::
::slop::
::sovereign::
::tick::
::unalign::
::unbenign::
::verisign::
::inlining::
::inlined::
::peaks::
::posed::
::tier::
::tiers::
;------------------------------------------------------------------------------
; Special Exceptions
;------------------------------------------------------------------------------
::chats::
::stdio::
::yt::
::git::
::fats::
::gg::
::hah::
::haha::
::meh::
::coop::
::json::
::hell::
::hm::
::ugh::
::ggi::
::i.e::
::shit::
::gcc::
::g++::
::dll::
::impl::
::ouch::
::dug::
::owe::
::lag::
::i.e.::
::mma::
::MMA::
::lame::
::shit::
::fuck::
::ether::
::rot::
::SXe::
::IPs::
::VMware::
::VMs::
::ah::
::eh::
::np::
::ty::
::go::
::qt::
::vs::
::oem::
::dl::
::huh::
::bing::
::spit::
::comon::
::app::
::nap::
::cunt::
::cunts::
::cocks::
::apps::
::cue::
::jest::
::alien::
::aliens::
::shits::
::cock::
::anal::
::ass::
::suck::
::sucks::
::crap::
::matte::
::fag::
::butt::
::fags::
::itch::
;------------------------------------------------------------------------------
; Special Exceptions - File Types
;------------------------------------------------------------------------------
::3g2::
::3gp::
::7z ::
::ai::
::aif::
::apk::
::arj::
::asp::
::avi::
::bak::
::bat::
::bin::
::bmp::
::c::
::cc::
::cab::
::cda::
::cer::
::cfg::
::cfm::
::cgi::
::class::
::com::
::cpl::
::cpp::
::cs::
::css::
::csv::
::cur::
::dat::
::db::
::deb::
::dmg::
::dmp::
::doc::
::drv::
::elf::
::email::
::eml::
::emlx::
::exe::
::flv::
::fnt::
::fon::
::gadget::
::gif::
::gz::
::h264::
::h::
::htm::
::icns::
::ico::
::ini::
::iso::
::jar::
::java::
::jpeg::
::js::
::jsp::
::key::
::lnk::
::log::
::m4v::
::mdb::
::mid::
::mkv::
::mov::
::mp3::
::mp4::
::mpa::
::mpg::
::msg::
::msi::
::net::
::odp::
::ods::
::odt::
::oft::
::ogg::
::org::
::ost::
::otf::
::part::
::pdf::
::php::
::pkg::
::png::
::pps::
::ppt::
::pptx::
::pri::
::ps::
::psd::
::pst::
::py::
::rar::
::rm::
::rpm::
::rss::
::rtf::
::sav::
::sh::
::sql::
::svg::
::swf::
::swift::
::sys::
::tar::
::tex::
::tif::
::tmp::
::toast::
::ttf::
::txt::
::vb::
::vcd::
::vcf::
::vob::
::wad::
::wav::
::webm::
::webp::
::wma::
::wmv::
::wpd::
::wpl::
::wsf::
::xhtml::
::xls::
::xlsm::
::xlsx::
::xml::
::zip::
Return  ; This makes the above hotstrings do nothing so that they override the ign->ing rule below.

#Hotstring B T C k-1 ; Set the default to be "raw mode" (might not actually be relied upon by anything yet).; Turn back on automatic backspacing for all subsequent hotstrings.
::vms::VMs
::VMs::VMs
::VMware::VMware
::sxe::SXe
::SXe::SXe
::ips::IPs
::IPs::IPs
::vmware::VMware
::VMware::VMware
::CMake::CMake
::ie::i.e.
::eg::e.g.
::lossing::losing
::leiu::lieu
::suck::suck
::sucks::sucks
::appraoch::approach
::Su::Us
::Ym::My
::yB::By
::tI::It
::sI::Is
::eW::We
::eM::Me
::oT::To
::oF::Of
::nI::In
::fI::If
::nO::On
::pU::Up
::oN::No
::oD::Do
::rO::Or
::sA::As
::tA::At
::nA::An
::mA::Am
::eB::Be
::eH::He
::oS::So
::iH::Hi
::su::us
::ym::my
::yb::by
::ti::it
::si::is
::ew::we
::ot::to
::fo::of
::ni::in
::fi::if
::pu::up
::od::do
::ro::or
::sa::as
::ta::at
::na::an
::ma::am
::eb::be
::eh::he
::ih::hi
::bc::because
::cb::because
::qt::Qt::
::ato::to
::bto::to
::cto::to
::dto::to
::eto::to
::fto::to
::gto::to
::hto::to
::ito::to
::jto::to
::kto::to
::lto::to
::mto::to
::oto::to
::qto::to
::rto::to
::sto::to
::tto::to
::uto::to
::vto::to
::wto::to
::yto::to
::zto::to
::ou::you
::u::you
;------------------------------------------------------------------------------
; Word endings
;------------------------------------------------------------------------------
:?:uccessful::successful
:?:sccessful::successful
:?:sucessful::successful
:?:succssful::successful
:?:succesful::successful
:?:successul::successful
:?:successfl::successful
:?:successfu::successful
:?:usccessful::successful
:?:scucessful::successful
:?:sucecssful::successful
:?:succsesful::successful
:?:succesfsul::successful
:?:successufl::successful
:?:successflu::successful
:?:uccessfully::successfully
:?:sccessfully::successfully
:?:sucessfully::successfully
:?:succssfully::successfully
:?:succesfully::successfully
:?:successully::successfully
:?:successflly::successfully
:?:successfuly::successfully
:?:successfull::successfully
:?:usccessfully::successfully
:?:scucessfully::successfully
:?:sucecssfully::successfully
:?:succsesfully::successfully
:?:succesfsully::successfully
:?:successuflly::successfully
:?:successfluly::successfully
:?:successfulyl::successfully
:?:bilites::bilities
:?:bilties::bilities
:?:blities::bilities
:?:bilty::bility
:?:blity::bility
:?:, btu::, but
:?:; btu::; but
:?:n;t::n't
:?:nt'::n't
:?:;ll::'ll
:?:ll'::'ll
:?:;re::'re
:?:re'::'re
:?:;ve::'ve
:?:ve'::'ve
:?:;nt::'nt
:?:;d::'d
:?:;s::'s
:?:'ts::t's
:?:sice::sive
:?:t hem::them
:?:toin::tion
:?:iotn::tion
:?:soin::sion
:?:itons::tions
:?:emnt::ment
:?:mnet::ment
:?:metn::ment
:?:emtn::ment
:?:emtns::ments
:?:emnts::ments
:?:oitn::oint
:?:kgin::king
:?:ferance::ference
:?:dya::day
:?:mhz::Mhz
:?:toins::tions
:?:ghz::Ghz
:?:aition::ation
:?:aotin::ation
:?:gbe::GbE
:?:noin::nion
:?:iosn::ions
:?:gbps::Gbps
:?:gpbs::Gbps
:?:lien::line
:?:liens::lines
:?:oen::one
:?:iaion::iation
:?:cims::cisms
:?:lyl::lly
:?:aingin::aining
:?:ainign::aining
:?:gni::ing
:?:ign::ing
:?:ngi::ing
:?:yda::day
:?:gound::ground
:?:grund::ground
:?:grond::ground
:?:groud::ground
:?:groun::ground
:?:rgound::ground
:?:gorund::ground
:?:gruond::ground
:?:gronud::ground
:?:groudn::ground
:?:gounds::grounds
:?:grunds::grounds
:?:gronds::grounds
:?:grouds::grounds
:?:grouns::grounds
:?:rgounds::grounds
:?:gorunds::grounds
:?:gruonds::grounds
:?:gronuds::grounds
:?:groudns::grounds
:?:grounsd::grounds
:?:aliyt::ality
:?:laity::ality
:?:altiy::ality
:?:alit::ality
:?:daiton::dation
:?:aiton::ation
:?:ioins::ions
:?:ceis::cies
:?:tn::nt
:?:toir::itor
;------------------------------------------------------------------------------
; Word beginnings
;------------------------------------------------------------------------------
:*:abondon::abandon
:*:abreviat::abbreviat
:*:accomadat::accommodat
:*:accomodat::accommodat
:*:acheiv::achiev
:*:achievment::achievement
:*:acquaintence::acquaintance
:*:adquir::acquir
:*:aquisition::acquisition
:*:agravat::aggravat
:*:allign::align
:*:ameria::America
:*:archaelog::archaeolog
:*:archtyp::archetyp
:*:archetect::architect
:*:arguement::argument
:*:assasin::assassin
:*:asociat::associat
:*:assymetr::asymmet
:*:atempt::attempt
:*:atribut::attribut
:*:avaialb::availab
:*:comision::commission
:*:contien::conscien
:*:critisi::critici
:*:crticis::criticis
:*:critiz::criticiz
:*:desicant::desiccant
:*:desicat::desiccat
:*:diar::diarrhea
:*:dissapoint::disappoint
:*:divsion::division
:*:dcument::document
:*:embarass::embarrass
:*:emminent::eminent
:*:empahs::emphas
:*:enlargment::enlargement
:*:envirom::environm
:*:enviorment::environment
:*:excede::exceed
:*:exilerat::exhilarat
:*:extraterrestial::extraterrestrial
:*:faciliat::facilitat
:*:garantee::guaranteed
:*:guerrila::guerrilla
:*:guidlin::guidelin
:*:girat::gyrat
:*:harasm::harassm
:*:immitat::imitat
:*:imigra::immigra
:*:impliment::implement
:*:inlcud::includ
:*:indenpenden::independen
:*:indisputib::indisputab
:*:insitut::institut
:*:knwo::know
:*:lsit::list
:*:mountian::mountain
:*:nmae::name
:*:necassa::necessa
:*:negociat::negotiat
:*:neigbor::neighbour
:*:noticibl::noticeabl
:*:ocasion::occasion
:*:occuranc::occurrence
:*:priveledg::privileg
:*:recie::recei
:*:recived::received
:*:reciver::receiver
:*:recepient::recipient
:*:reccomend::recommend
:*:recquir::requir
:*:respomd::respond
:*:repons::respons
:*:ressurect::resurrect
:*:seperat::separat
:*:sevic::servic
:*:smoe::some
:*:supercede::supersede
:*:superceed::supersede
:*:weild::wield
:*:nay::any
:*:soem::some
:*:seom::some
:*:cmakel::CMakeLists.txt
:*:cmaket::CMakeLists.txt
:*:unfo::unfortunately, `
:*:Unfo::Unfortunately, `
:*:chara::character
:*:chars::characters
:*:privi::privilege `
:*:prive::privilege `
:*:envi::environment `
:*:simult::simultaneous`
:*:follwo::follow
:*:ncorrect::incorrect
:*:icorrect::incorrect
:*:inorrect::incorrect
:*:incrrect::incorrect
:*:incorect::incorrect
:*:incorrct::incorrect
:*:incorret::incorrect
:*:incorrec::incorrect
:*:nicorrect::incorrect
:*:icnorrect::incorrect
:*:inocrrect::incorrect
:*:incrorect::incorrect
:*:incorerct::incorrect
:*:incorrcet::incorrect
:*:incorretc::incorrect
:*:methodo::methodology `
:*:orthog::orthogonal
:*:pecifi::specifi
:*:secifi::specifi
:*:spcifi::specifi
:*:speifi::specifi
:*:specfi::specifi
:*:specii::specifi
:*:psecifi::specifi
:*:sepcifi::specifi
:*:spceifi::specifi
:*:speicfi::specifi
:*:specfii::specifi
:*:speciif::specifi
:*:fucn::func
:*:retreiv::retriev
;------------------------------------------------------------------------------
; Word middles
;------------------------------------------------------------------------------
:?*:compatab::compatib  ; Covers incompat* and compat*
:?*:isgn::sign  ; Covers subcatagories and catagories.
:?*:sgin::sign  ; Covers subcatagories and catagories.
:?*:fortuante::fortunate  ; Covers subcatagories and catagories.
:?*:laod::load
:?*:olad::load
:?*:loda::load
:?*:isntall::install
:?*:insatll::install
:?*:istall::install
:?*:intall::install
:?*:usou::uous
;------------------------------------------------------------------------------
; Common Misspellings - the main list
;------------------------------------------------------------------------------
::fullfill::fulfill
::requiremts::requirement
::requireement::requirement
::termainl::terminal
::onesself::oneself
::violance::violence
::stuats::status
::claend::cleaned
::its he::is the
::itwas::it was
::Shoudl::Should
::a mnot::am not
::a tthat::at that
::not hat::on that
::aanother::another
::abandonned::abandoned
::abbout::about
::abbreviatoin::abbreviation
::abcense::absense
::aberation::aberration
::aborigene::aborigine
::abortificant::abortifacient
::abou tit::about it
::abouta::about a
::aboutit::about it
::aboutthe::about the
::abscence::absence
::absense::absence
::absorbsion::absorption
::absorbtion::absorption
::abundacies::abundances
::abundancies::abundances
::abundunt::abundant
::abutts::abuts
::acadamy::academy
::accademic::academic
::accademy::academy
::acccused::accused
::accelleration::acceleration
::accension::accession
::acceotable::acceptable
::acceptence::acceptance
::acceptible::acceptable
::accesorise::accessorise
::accessable::accessible
::accidant::accident
::accidentaly::accidentally
::accidently::accidentally
::accidnetally::accidentally
::acclimitization::acclimatization
::accomdate::accommodate
::accomodated::accommodated
::accomodates::accommodates
::accomodating::accommodating
::accompanyed::accompanied
::accordeon::accordion
::accordian::accordion
::accordians::accordions
::accordingto::according to
::accoustic::acoustic
::accquainted::acquainted
::accross::across
::accussed::accused
::acedemic::academic
::achive::achieve
::acide::acid
::acknowledgeing::acknowledging
::acomodate::accommodate
::acquiantence::acquaintance
::acquiantences::acquaintances
::acquited::acquitted
::acused::accused
::acustom::accustom
::acustommed::accustomed
::acutaly::actually
::acutlaly::actually
::ad::Ad
::adaption::adaptation
::adaptions::adaptations
::adavanced::advanced
::adbandon::abandon
::addmission::admission
::addopt::adopt
::addopted::adopted
::addoptive::adoptive
::addresable::addressable
::addressess::addresses
::adecuate::adequate
::adequit::adequate
::adequite::adequate
::adhearing::adhering
::adherance::adherence
::adjusmenet::adjustment
::adjustement::adjustment
::adjustemnet::adjustment
::adjustmenet::adjustment
::admendment::amendment
::admininistrative::administrative
::admissability::admissibility
::admissable::admissible
::admitedly::admittedly
::adres::address
::adresable::addressable
::adresing::addressing
::adressable::addressable
::adventrous::adventurous
::advesary::adversary
::adviced::advised
::aeriel::aerial
::aeriels::aerials
::afficianados::aficionados
::afficionado::aficionado
::afficionados::aficionados
::affilliate::affiliate
::affraid::afraid
::aforememtioned::aforementioned
::afterthe::after the
::againnst::against
::againstt he::against the
::aggaravates::aggravates
::aggreed::agreed
::aggreement::agreement
::aggregious::egregious
::aggrevate::aggravate
::agreeement::agreement
::agreemeent::agreement
::agreemeents::agreements
::agregates::aggregates
::agreing::agreeing
::agressor::aggressor
::agrieved::aggrieved
::ahev::have
::airbourne::airborne
::aircrafts::aircraft
::airporta::airports
::airrcraft::aircraft
::aisian::Asian
::albiet::albeit
::alchohol::alcohol
::alchoholic::alcoholic
::alcholic::alcoholic
::alcohal::alcohol
::alcoholical::alcoholic
::aledge::allege
::aledged::alleged
::aledges::alleges
::alegience::allegiance
::algebraical::algebraic
::algorhitms::algorithms
::alientating::alienating
::all the itme::all the time
::alledge::allege
::alledged::alleged
::alledgedly::allegedly
::alledges::alleges
::allegedely::allegedly
::allegence::allegiance
::allegience::allegiance
::alliviate::alleviate
::allopone::allophone
::allopones::allophones
::allready::already
::allthough::although
::alltime::all-time
::allwasy::always
::allwyas::always
::alonw::alone
::alotted::allotted
::alrigth::alright
::alriht::alright
::alsation::Alsatian
::alse::else
::alseep::asleep
::alsot::also
::alterior::ulterior
::alternitives::alternatives
::altho::although
::althought::although
::altogehter::altogether
::alwats::always
::alwayus::always
::amalgomated::amalgamated
::amendmant::amendment
::amerliorate::ameliorate
::ammend::amend
::ammended::amended
::ammendment::amendment
::ammendments::amendments
::ammount::amount
::ammused::amused
::amoung::among
::amoungst::amongst
::amplfieir::amplifier
::ampliotude::amplitude
::amploitude::amplitude
::amploitudes::amplitudes
::amplotude::amplitude
::amplotuide::amplitude
::amung::among
::an dgot::and got
::analagous::analogous
::analitic::analytic
::analogeous::analogous
::analyse::analyze
::anarchim::anarchism
::anarchistm::anarchism
::anbd::and
::ancestory::ancestry
::ancilliary::ancillary
::Andone::and one
::Anroid::Android
::Andoid::Android
::Andrid::Android
::Androd::Android
::Androi::Android
::Android::Android
::nAdroid::Android
::Adnroid::Android
::Anrdoid::Android
::Andorid::Android
::Andriod::Android
::Androdi::Android
::androgenous::androgynous
::androgeny::androgyny
::andt he::and the
::andteh::and the
::andthe::and the
::anihilation::annihilation
::anmd::and
::annoint::anoint
::annointed::anointed
::annointing::anointing
::annoints::anoints
::annuled::annulled
::anomolies::anomalies
::anomolous::anomalous
::anomoly::anomaly
::anonimity::anonymity
::ansalisation::nasalisation
::ansalization::nasalization
::ansestors::ancestors
::antartic::antarctic
::anthromorphisation::anthropomorphisation
::anthromorphization::anthropomorphization
::anti-semetic::anti-Semitic
::anticlimatic::anticlimactic
::anulled::annulled
::anuthing::anything
::anyother::any other
::anythihng::anything
::anytying::anything
::aparmtnet::apartment
::apenines::Apennines
::apolegetics::apologetics
::apparant::apparent
::apparantly::apparently
::apparnelty::apparently
::apparntely::apparently
::apparrent::apparent
::appart::apart
::appartment::apartment
::appartments::apartments
::appealling::appealing
::appeareance::appearance
::appearence::appearance
::appearences::appearances
::appeares::appears
::appenines::Apennines
::apperances::appearances
::appluied::applied
::applyed::applied
::appointiment::appointment
::appologies::apologies
::appology::apology
::apprearance::appearance
::apprieciate::appreciate
::appropropiate::appropriate
::approproximate::approximate
::approrpriate::appropriate
::approxamately::approximately
::approximitely::approximately
::aprehensive::apprehensive
::aquaintance::acquaintance
::aquainted::acquainted
::aquiantance::acquaintance
::aquit::acquit
::aquitted::acquitted
::arbouretum::arboretum
::archetectural::architectural
::archetecturally::architecturally
::archetecture::architecture
::archiac::archaic
::archictect::architect
::archimedian::Archimedean
::architechturally::architecturally
::architechture::architecture
::architechtures::architectures
::areodynamics::aerodynamics
::argubly::arguably
::arguements::arguments
::arised::arose
::armamant::armament
::armistace::armistice
::around ot::around to
::arragnemetn::arrangement
::arragnemnet::arrangement
::arround::around
::artical::article
::artifically::artificially
::artillary::artillery
::asdvertising::advertising
::asetic::ascetic
::askt he::ask the
::asphyxation::asphyxiation
::assassintation::assassination
::assemple::assemble
::assertation::assertion
::asside::aside
::assisnate::assassinate
::assistent::assistant
::assosication::assassination
::asssassans::assassins
::assualted::assaulted
::asteriod::asteroid
::asthe::as the
::asthetic::aesthetic
::asthetical::aesthetic
::asthetically::aesthetically
::aswell::as well
::atheistical::atheistic
::athenean::Athenian
::atheneans::Athenians
::athiesm::atheism
::athiest::atheist
::attatch::attach
::attendence::attendance
::attendent::attendant
::attendents::attendants
::attension::attention
::attentioin::attention
::atthe::at the
::attitide::attitude
::attributred::attributed
::attrocities::atrocities
::audiance::audience
::austrailia::Australia
::austrailian::Australian
::auther::author
::authobiographic::autobiographic
::authobiography::autobiography
::authorative::authoritative
::authorithy::authority
::authoritiers::authorities
::authoritive::authoritative
::authrorities::authorities
::autochtonous::autochthonous
::autoctonous::autochthonous
::automaticly::automatically
::automibile::automobile
::automonomous::autonomous
::auxilary::auxiliary
::auxillaries::auxiliaries
::auxillary::auxiliary
::auxilliaries::auxiliaries
::auxilliary::auxiliary
::availablility::availability
::availaible::available
::availiable::available
::availible::available
::avalance::avalanche
::ave::have
::avengence::a vengeance
::averageed::averaged
::aweomse::awesome
::awesomoe::awesome
::aywa::away
::aziumth::azimuth
::baceause::because
::balence::balance
::ballance::balance
::banannas::bananas
::barbeque::barbecue
::barcod::barcode
::basicly::basically
::batteryes::batteries
::bceayuse::because
::beachead::beachhead
::beacues::because
::beastiality::bestiality
::beaurocracy::bureaucracy
::beaurocratic::bureaucratic
::beautyfull::beautiful
::becamae::became
::becausea::because a
::becauseof::because of
::becausethe::because the
::becauseyou::because you
::becayse::because
::beccause::because
::beceause::because
::becomeing::becoming
::becomming::becoming
::becouse::because
::bedore::before
::begginer::beginner
::begginers::beginners
::beggining::beginning
::begginings::beginnings
::beggins::begins
::beginining::beginning
::behavour::behaviour
::beleagured::beleaguered
::beleiev::believe
::beleieve::believe
::beleiving::believing
::beligum::belgium
::belligerant::belligerent
::bellweather::bellwether
::bemusemnt::bemusement
::beneficary::beneficiary
::benificial::beneficial
::benifit::benefit
::benifits::benefits
::bergamont::bergamot
::bernouilli::Bernoulli
::beseige::besiege
::beseiged::besieged
::beseiging::besieging
::betweeen::between
::bicep::biceps
::bilateraly::bilaterally
::billingualism::bilingualism
::binominal::binomial
::bizzare::bizarre
::blaim::blame
::blaimed::blamed
::blessure::blessing
::blitzkreig::Blitzkrieg
::bodydbuilder::bodybuilder
::bombardement::bombardment
::bonnano::Bonanno
::bootlaoder::bootloader
::bouat::about
::bouy::buoy
::bouyancy::buoyancy
::bouyant::buoyant
::boyant::buoyant
::boyfriedn::boyfriend
::brasillian::Brazilian
::breakthough::breakthrough
::breakthroughts::breakthroughs
::brethen::brethren
::bretheren::brethren
::brigthness::brightness
::brimestone::brimstone
::brittish::British
::broacasted::broadcast
::broadacasting::broadcasting
::broady::broadly
::brocolli::broccoli
::buddah::Buddha
::bufferring::buffering
::buisnessman::businessman
::buit::but
::buoancy::buoyancy
::burried::buried
::bussiness::business
::butthe::but the
::bve::be
::bweteen::between
::byt he::by the
::cacuses::caucuses
::caeser::caesar
::caffeien::caffeine
::caharcter::character
::calander::calendar
::calcullated::calculated
::calculs::calculus
::calenders::calendars
::califronian::Californian
::caligraphy::calligraphy
::callipigian::callipygian
::caluculate::calculate
::caluculated::calculated
::camoflage::camouflage
::candadate::candidate
::candidiate::candidate
::canidtes::candidates
::cannister::canister
::cannisters::canisters
::cannnot::cannot
::cannonical::canonical
::cannotation::connotation
::cannotations::connotations
::cantalope::cantaloupe
::capacitro::capacitor
::capcaitors::capacitors
::caperbility::capability
::capetown::Cape Town
::capible::capable
::carachter::character
::caracterised::characterised
::carcas::carcass
::cardiod::cardioid
::cardiodi::cardioid
::cardoid::cardioid
::carefull::careful
::careing::caring
::caridoid::cardioid
::carismatic::charismatic
::carmalite::Carmelite
::carniverous::carnivorous
::carreer::career
::carrers::careers
::carribbean::Caribbean
::carribean::Caribbean
::cartdridge::cartridge
::carthagian::Carthaginian
::carthographer::cartographer
::cartilege::cartilage
::cartilidge::cartilage
::casion::caisson
::cassawory::cassowary
::cassowarry::cassowary
::casulaties::casualties
::casulaty::casualty
::catagories::categories
::catagory::category
::categiory::category
::catelog::catalog
::catagorize::categorize
::catholocism::catholicism
::catterpilar::caterpillar
::catterpilars::caterpillars
::cattleship::battleship
::caucasion::Caucasian
::causalities::casualties
::causeing::causing
::ceasar::Caesar
::celcius::Celsius
::cellpading::cellpadding
::cementary::cemetery
::cemetarey::cemetery
::cemetaries::cemeteries
::cemetary::cemetery
::cencus::census
::cententenial::centennial
::cerimonial::ceremonial
::cerimonies::ceremonies
::cerimonious::ceremonious
::cerimony::ceremony
::ceromony::ceremony
::certainity::certainty
::challange::challenge
::challanged::challenged
::challanges::challenges
::changable::changeable
::changeing::changing
::charachter::character
::charachters::characters
::charactersistic::characteristic
::charactor::character
::charactors::characters
::charasmatic::charismatic
::charaterised::characterised
::charecter::character
::charector::character
::charistics::characteristics
::chcance::chance
::checmicals::chemicals
::chemestry::chemistry
::childbird::childbirth
::chilli::chili
::choosen::chosen
::cilinder::cylinder
::cincinatti::Cincinnati
::cincinnatti::Cincinnati
::circumfrence::circumference
::circumsicion::circumcision
::ciricuit::circuit
::ciriculum::curriculum
::cirtus::citrus
::civillian::civilian
::claerer::clearer
::claimes::claims
::clasically::classically
::cleareance::clearance
::cliant::client
::clinicaly::clinically
::clipipng::clipping
::clippin::clipping
::closeing::closing
::co-incided::coincided
::cognizent::cognizant
::coincedentally::coincidentally
::colaborations::collaborations
::colateral::collateral
::collaberative::collaborative
::collectable::collectible
::collonade::colonnade
::collonies::colonies
::collony::colony
::collosal::colossal
::colonisators::colonisers
::colonizators::colonizers
::comando::commando
::comandos::commandos
::comapany::company
::comback::comeback
::combanations::combinations
::combintation::combination
::combusion::combustion
::comdemnation::condemnation
::comeing::coming
::comemmorate::commemorate
::comemmorates::commemorates
::comemoretion::commemoration
::comissioning::commissioning
::comited::committed
::comiting::committing
::commandoes::commandos
::commedic::comedic
::commemerative::commemorative
::commemmorate::commemorate
::commemmorating::commemorating
::commerically::commercially
::commericial::commercial
::commericially::commercially
::commerorative::commemorative
::comming::coming
::comminication::communication
::commisioning::commissioning
::committment::commitment
::committments::commitments
::committy::committee
::commiunicating::communicating
::commmemorated::commemorated
::commongly::commonly
::commuinications::communications
::communiucating::communicating
::comntain::contain
::comntains::contains
::compability::compatibility
::compair::compare
::comparision::comparison
::comparisions::comparisons
::comparitive::comparative
::comparitively::comparatively
::compatiable::compatible
::compatioble::compatible
::compensantion::compensation
::competance::competence
::competant::competent
::competative::competitive
::competitiion::competition
::competive::competitive
::competiveness::competitiveness
::comphrehensive::comprehensive
::compitent::competent
::compleated::completed
::compleatly::completely
::compleatness::completeness
::completedthe::completed the
::completelyl::completely
::completetion::completion
::completness::completeness
::componant::component
::composate::composite
::comprimise::compromise
::compulsary::compulsory
::compulsery::compulsory
::computarised::computerised
::computarized::computerized
::comtain::contain
::comtains::contains
::concensus::consensus
::concider::consider
::concidered::considered
::concidering::considering
::conciders::considers
::concieted::conceited
::conciously::consciously
::condamned::condemned
::condemmed::condemned
::condensor::condenser
::condidtion::condition
::condidtions::conditions
::condolances::condolences
::conesencus::consensus
::conferance::conference
::confidentally::confidentially
::confids::confides
::configuraoitn::configuration
::configureable::configurable
::confirmmation::confirmation
::confortable::comfortable
::confusnig::confusing
::congradulations::congratulations
::conived::connived
::conjecutre::conjecture
::conotations::connotations
::conquerd::conquered
::conquerer::conqueror
::conquerers::conquerors
::conqured::conquered
::conscent::consent
::consdider::consider
::consdidered::considered
::consectutive::consecutive
::consenquently::consequently
::consentrate::concentrate
::consentrated::concentrated
::consentrates::concentrates
::consept::concept
::consequentually::consequently
::consequeseces::consequences
::consern::concern
::conserned::concerned
::conserning::concerning
::conservitive::conservative
::consiciousness::consciousness
::consideres::considered
::considerit::considerate
::considerite::considerate
::consistant::consistent
::consistantly::consistently
::consistnelty::consistently
::consistntely::consistently
::consolodate::consolidate
::consolodated::consolidated
::consonent::consonant
::consonents::consonants
::consorcium::consortium
::conspiracys::conspiracies
::conspiriator::conspirator
::conspiricy::conspiracy
::constarnation::consternation
::constinually::continually
::constituant::constituent
::constituants::constituents
::consttruction::construction
::consultent::consultant
::consumate::consummate
::consumated::consummated
::consumber::consumer
::contaiminate::contaminate
::containes::contains
::contamporaries::contemporaries
::contamporary::contemporary
::contemporaneus::contemporaneous
::contempory::contemporary
::contendor::contender
::continueing::continuing
::contravercial::controversial
::contraversy::controversy
::contributer::contributor
::contributers::contributors
::contritutions::contributions
::controll::control
::controlls::controls
::controvercial::controversial
::controvercy::controversy
::controvertial::controversial
::convenant::covenant
::convential::conventional
::convertable::convertible
::convertables::convertibles
::convertion::conversion
::convertor::converter
::convertors::converters
::conveyer::conveyor
::convienient::convenient
::cooparate::cooperate
::cooporate::cooperate
::coorperations::corporations
::copywrite::copyright
::coridal::cordial
::corosion::corrosion
::corparate::corporate
::corperations::corporations
::correcters::correctors
::correposding::corresponding
::correspondant::correspondent
::correspondants::correspondents
::corridoors::corridors
::corrispond::correspond
::corrispondant::correspondent
::corrispondants::correspondents
::corrisponded::corresponded
::corrisponding::corresponding
::corrisponds::corresponds
::corruptable::corruptible
::corrolary::corollary
::corralary::corollary
::corallary::corollary
::cotten::cotton
::couldthe::could the
::countains::contains
::counterfiet::counterfeit
::coururier::courier
::cpacitor::capacitor
::creaeted::created
::creedence::credence
::critereon::criterion
::criterias::criteria
::criticing::criticising
::criticists::critics
::critised::criticised
::crockodiles::crocodiles
::crucifiction::crucifixion
::crystalisation::crystallisation
::culiminating::culminating
::cumulatative::cumulative
::curcuit::circuit
::curiousity::curiosity
::curriculem::curriculum
::currnets::currents
::cxan::can
::cxan::cyan
::cyclinder::cylinder
::dakiri::daiquiri
::dalmation::dalmatian
::damenor::demeanor
::damenor::demeanour
::damenour::demeanour
::danceing::dancing
::dardenelles::Dardanelles
::debateable::debatable
::decaffinated::decaffeinated
::decathalon::decathlon
::decendant::descendant
::decendants::descendants
::decendent::descendant
::decendents::descendants
::decideable::decidable
::decidely::decidedly
::decieved::deceived
::decomissioned::decommissioned
::decomposit::decompose
::decomposited::decomposed
::decompositing::decomposing
::decomposits::decomposes
::decress::decrees
::dectect::detect
::defencive::defensive
::defendent::defendant
::defendents::defendants
::deffensively::defensively
::deffine::define
::deffined::defined
::definance::defiance
::definate::definite
::definately::definitely
::definatly::definitely
::definetly::definitely
::definining::defining
::defintioin::definition
::degrate::degrade
::degredation::degradation
::delagates::delegates
::delapidated::dilapidated
::delerious::delirious
::delevopment::development
::delusionally::delusively
::demenor::demeanor
::demenour::demeanour
::demographical::demographic
::demolision::demolition
::demorcracy::democracy
::denegrating::denigrating
::dependance::dependence
::dependancy::dependency
::dependant::dependent
::depricate::deprecate
::depricated::deprecated
::deprication::deprecation
::deptartment::department
::deriviated::derived
::derivitive::derivative
::derogitory::derogatory
::descendands::descendants
::descision::decision
::descisions::decisions
::descriibes::describes
::descripters::descriptors
::desctruction::destruction
::descuss::discuss
::desease::disease
::desicion::decision
::desicions::decisions
::deside::decide
::desigining::designing
::desintegrated::disintegrated
::desintegration::disintegration
::desireable::desirable
::desision::decision
::desisions::decisions
::desitned::destined
::desktiop::desktop
::desorder::disorder
::desoriented::disoriented
::desparate::desperate
::desparately::desperately
::despatched::dispatched
::despict::depict
::despiration::desperation
::dessicated::desiccated
::dessigned::designed
::destablised::destabilised
::destablized::destabilized
::detailled::detailed
::detatched::detached
::deteoriated::deteriorated
::deteriate::deteriorate
::deterioriating::deteriorating
::determinining::determining
::detremental::detrimental
::devasted::devastated
::develeoprs::developers
::devellop::develop
::develloped::developed
::develloper::developer
::devellopers::developers
::develloping::developing
::devellopment::development
::devellopments::developments
::devellops::develop
::developor::developer
::developors::developers
::developped::developed
::devels::delves
::devestated::devastated
::devestating::devastating
::devide::divide
::devided::divided
::devistating::devastating
::devolopement::development
::diablical::diabolical
::diaplay::display
::diarhea::diarrhoea
::dichtomy::dichotomy
::diciplin::discipline
::diconnects::disconnects
::dicovering::discovering
::dicovers::discovers
::didnot::did not
::dieing::dying
::dieties::deities
::diety::deity
::diferrent::different
::differance::difference
::differances::differences
::differant::different
::differemt::different
::differentiatiations::differentiations
::difficulity::difficulty
::digestable::digestible
::dimention::dimension
::dimentional::dimensional
::dimentions::dimensions
::diminuitive::diminutive
::diosese::diocese
::diphtong::diphthong
::diphtongs::diphthongs
::diplomancy::diplomacy
::diptheria::diphtheria
::dipthong::diphthong
::dipthongs::diphthongs
::directer::director
::directers::directors
::directiosn::direction
::dirived::derived
::disagreeed::disagreed
::disapear::disappear
::disapeared::disappeared
::disapointing::disappointing
::disappearred::disappeared
::disaproval::disapproval
::disasterous::disastrous
::disatisfaction::dissatisfaction
::disatisfied::dissatisfied
::disatrous::disastrous
::discontentment::discontent
::discrepencies::discrepancies
::discrepency::discrepancy
::discribe::describe
::discribed::described
::discribes::describes
::discribing::describing
::disctinction::distinction
::disctinctive::distinctive
::disemination::dissemination
::disenchanged::disenchanted
::disign::design
::disiplined::disciplined
::disobediance::disobedience
::disobediant::disobedient
::dispair::despair
::disparingly::disparagingly
::dispeled::dispelled
::dispeling::dispelling
::dispell::dispel
::dispells::dispels
::dispence::dispense
::dispenced::dispensed
::dispencing::dispensing
::dispicable::despicable
::dispite::despite
::disproportiate::disproportionate
::disputandem::disputandum
::dissagreement::disagreement
::dissapear::disappear
::dissapearance::disappearance
::dissapeared::disappeared
::dissapearing::disappearing
::dissapears::disappears
::dissappear::disappear
::dissappears::disappears
::dissappointed::disappointed
::dissarray::disarray
::dissobediance::disobedience
::dissobediant::disobedient
::dissobedience::disobedience
::dissobedient::disobedient
::dissonent::dissonant
::distingish::distinguish
::distingishes::distinguishes
::distingishing::distinguishing
::distingquished::distinguished
::distribusion::distribution
::distrubution::distribution
::distruction::destruction
::distructive::destructive
::divice::device
::doccument::document
::doccumented::documented
::doccuments::documents
::docuement::documents
::doe snot::does not ; *could* be legitimate... but very unlikely!
::doese::does
::dogin::doing
::doimg::doing
::doind::doing
::dollers::dollars
::dominent::dominant
::dominiant::dominant
::don't no::don't know
::draughtman::draughtsman
::dravadian::Dravidian
::driveing::driving
::druming::drumming
::drummless::drumless
::drunkeness::drunkenness
::dukeship::dukedom
::dumbell::dumbbell
::durring::during
::duting::during
::eachotehr::eachother
::earnt::earned
::ebceause::because
::ecclectic::eclectic
::eceonomy::economy
::ecidious::deciduous
::ecomonic::economic
::eearly::early
::efel::evil
::effeciency::efficiency
::effecient::efficient
::effeciently::efficiently
::effulence::effluence
::eight o::eight o
::eigth::eighth
::electricly::electrically
::eleminated::eliminated
::eleminating::eliminating
::eles::eels
::elicided::elicited
::eligable::eligible
::elimentary::elementary
::ellected::elected
::embargos::embargoes
::embarras::embarrass
::embarrased::embarrassed
::embarrasing::embarrassing
::embarrasment::embarrassment
::embezelled::embezzled
::emblamatic::emblematic
::eminate::emanate
::eminated::emanated
::emited::emitted
::emiting::emitting
::emmediately::immediately
::emmigrated::emigrated
::emmisaries::emissaries
::emmisarries::emissaries
::emmisarry::emissary
::emmisary::emissary
::emmision::emission
::emmisions::emissions
::emmited::emitted
::emmiting::emitting
::emmitted::emitted
::emmitting::emitting
::emnity::enmity
::emperical::empirical
::emphaised::emphasised
::emphysyma::emphysema
::emprisoned::imprisoned
::enameld::enamelled
::enchancement::enhancement
::encryptiion::encryption
::endevors::endeavors
::endevour::endeavour
::endevours::endeavours
::endolithes::endoliths
::enduce::induce
::enflamed::inflamed
::enforceing::enforcing
::engeneer::engineer
::engeneering::engineering
::engieneer::engineer
::engieneers::engineers
::enought::enough
::enourmous::enormous
::enourmously::enormously
::ensconsed::ensconced
::entaglements::entanglements
::entitity::entity
::entitlied::entitled
::enviornmentalist::environmentalist
::envolutionary::evolutionary
::epidsodes::episodes
::epsidoe::episode
::equippment::equipment
::equitorial::equatorial
::equivalant::equivalent
::equivelant::equivalent
::equivelent::equivalent
::equivilant::equivalent
::equivilent::equivalent
::equivlalent::equivalent
::eratic::erratic
::eratically::erratically
::eraticly::erratically
::errupted::erupted
::esctasy::ecstasy
::espesially::especially
::essencial::essential
::essense::essence
::essentual::essential
::essesital::essential
::ethnocentricm::ethnocentrism
::europian::European
::europians::Europeans
::evenhtually::eventually
::eventially::eventually
::everytime::every time
::evidentally::evidently
::exagerate::exaggerate
::exagerated::exaggerated
::exagerates::exaggerates
::exagerating::exaggerating
::exagerrate::exaggerate
::exagerrated::exaggerated
::exagerrates::exaggerates
::exagerrating::exaggerating
::examinated::examined
::exampt::exempt
::exapansion::expansion
::excact::exact
::excecute::execute
::excecuted::executed
::excecutes::executes
::excecuting::executing
::excecution::execution
::excedded::exceeded
::excell::excel
::excellance::excellence
::excellant::excellent
::excells::excels
::excercise::exercise
::exchanching::exchanging
::excisted::existed
::exculsivly::exclusively
::execising::exercising
::exeedingly::exceedingly
::exelent::excellent
::exemple::example
::exerbate::exacerbate
::exerbated::exacerbated
::exerciese::exercises
::exerpts::excerpts
::exersize::exercise
::exerternal::external
::exhalted::exalted
::exinct::extinct
::exisiting::existing
::existance::existence
::existant::existent
::existince::existence
::exliled::exiled
::exonorate::exonerate
::exoskelaton::exoskeleton
::expecially::especially
::expeditonary::expeditionary
::expell::expel
::expells::expels
::experiance::experience
::experianced::experienced
::expiditions::expeditions
::expierence::experience
::explaination::explanation
::exploititive::exploitative
::expresso::espresso
::expropiated::expropriated
::expropiation::expropriation
::extention::extension
::extentions::extensions
::extered::exerted
::extermist::extremist
::extradiction::extradition
::extravagent::extravagant
::extrememly::extremely
::extremeophile::extremophile
::extrordinarily::extraordinarily
::facia::fascia
::facillitate::facilitate
::facinated::fascinated
::facist::fascist
::familliar::familiar
::fammiliar::familiar
::famoust::famous
::fanatism::fanaticism
::farenheit::Fahrenheit
::fascitious::facetious
::fascitis::fasciitis
::faught::fought
::favoutrable::favourable
::feasable::feasible
::fedreally::federally
::feromone::pheromone
::fertily::fertility
::fi::If
::fianite::finite
::ficed::fixed
::ficticious::fictitious
::fictious::fictitious
::fiercly::fiercely
::fightings::fighting
::filiament::filament
::fimilies::families
::firc::furc
::firey::fiery
::fisionable::fissionable
::flamable::flammable
::flawess::flawless
::flemmish::Flemish
::florescent::fluorescent
::flourescent::fluorescent
::flouride::fluoride
::fluorish::flourish
::focussed::focused
::focusses::focuses
::focussing::focusing
::fonetic::phonetic
::foootball::football
::ofr::for
::fora::for a
::forbad::forbade
::foreward::foreword
::forfiet::forfeit
::forhead::forehead
::formalhaut::Fomalhaut
::formallise::formalise
::formallised::formalised
::formallize::formalize
::formallized::formalized
::formaly::formally
::formelly::formerly
::formost::foremost
::forsaw::foresaw
::forseeable::foreseeable
::fortelling::foretelling
::forthe::for the
::forunner::forerunner
::forwrds::forwards
::foundaries::foundries
::foundary::foundry
::foundland::Newfoundland
::fourties::forties
::fourty::forty
::fowards::forwards
::fransiscan::Franciscan
::fransiscans::Franciscans
::frequentily::frequently
::frome::from
::fromt he::from the
::fromthe::from the
::fucniton::function
::fued::feud
::funguses::fungi
::furneral::funeral
::furuther::further
::galatic::galactic
::galations::Galatians
::gallaxies::galaxies
::galvinised::galvanised
::galvinized::galvanized
::gameboy::Game Boy
::ganes::games
::ganster::gangster
::garnison::garrison
::gauarana::guarana
::gaurentee::guarantee
::gaurenteed::guaranteed
::gaurentees::guarantees
::gemeral::general
::geneological::genealogical
::geneologies::genealogies
::geneology::genealogy
::generatting::generating
::genialia::genitalia
::geographicial::geographical
::geometrician::geometer
::geometricians::geometers
::ghandi::Gandhi
::giid::good
::giveing::giving
::glight::flight
::gnawwed::gnawed
::godess::goddess
::godesses::goddesses
::godounov::Godunov
::gothenberg::Gothenburg
::gottleib::Gottlieb
::gouvener::governor
::govement::government
::governer::governor
::govorment::government
::govormental::governmental
::govornment::government
::gracefull::graceful
::graffitti::graffiti
::grafitti::graffiti
::gramatically::grammatically
::grammaticaly::grammatically
::grammer::grammar
::gratuitious::gratuitous
::greatful::grateful
::greatfully::gratefully
::greif::grief
::gridles::griddles
::guadulupe::Guadalupe
::guarentee::guarantee
::guarenteed::guaranteed
::guarentees::guarantees
::guatamala::Guatemala
::guatamalan::Guatemalan
::guidence::guidance
::guilia::Giulia
::guiliani::Giuliani
::guilio::Giulio
::guiness::Guinness
::guiseppe::Giuseppe
::gunanine::guanine
::guttaral::guttural
::gutteral::guttural
::haad::had
::habaeus::habeas
::habeus::habeas
::habsbourg::Habsburg
::hace::hare
::hadbeen::had been
::haemorrage::haemorrhage
::hallowean::Halloween
::halp::help
::happended::happened
::happenned::happened
::harased::harassed
::harases::harasses
::harassement::harassment
::harras::harass
::harrased::harassed
::harrases::harasses
::harrasing::harassing
::harrasment::harassment
::harrasments::harassments
::harrassed::harassed
::harrasses::harassed
::harrassing::harassing
::harrassment::harassment
::harrassments::harassments
::hasbeen::has been
::havebeen::have been
::haveing::having
::avhe::have
::haviest::heaviest
::headquater::headquarter
::headquatered::headquartered
::healthercare::healthcare
::heared::heard
::heidelburg::Heidelberg
::heigher::higher
::heirarchies::hierarchies
::heirarchy::heirarchy
::heiroglyphics::hieroglyphics
::helment::helmet
::helpfull::helpful
::helpped::helped
::hemmorhage::hemorrhage
::herf::href
::heridity::heredity
::heroe::hero
::heros::heroes
::hersuit::hirsute
::hertzs::hertz
::hesaid::he said
::hesistant::hesitant
::heterogenous::heterogeneous
::hewas::he was
::hge::he
::hier::heir
::hierachies::hierarchies
::hieroglph::hieroglyph
::hieroglphs::hieroglyphs
::hillarious::hilarious
::himselv::himself
::hinderance::hindrance
::hinderence::hindrance
::hindrence::hindrance
::hipopotamus::hippopotamus
::historicians::historians
::hitsingles::hit singles
::holliday::holiday
::homestate::home state
::homogeneize::homogenize
::homogeneized::homogenized
::honory::honorary
::honourarium::honorarium
::honourific::honorific
::hosited::hoisted
::hospitible::hospitable
::hounour::honour
::hsitorians::historians
::htikn::think
::htp:::http:
::http:\\::http://
::httpL::http:
::humer::humour
::humerous::humourous
::huminoid::humanoid
::humoural::humoral
::humurous::humourous
::hwihc::which
::hydropile::hydrophile
::hydropilic::hydrophilic
::hydropobe::hydrophobe
::hydropobic::hydrophobic
::hypocracy::hypocrisy
::hypocrasy::hypocrisy
::hypocricy::hypocrisy
::hypocrit::hypocrite
::hypocrits::hypocrites
::i snot::is not
::i"d::I'd
::i"ll::I'll
::i"m::I'm
::i"ve::I've
::i::I
::I"m::I'm ; "
::iconclastic::iconoclastic
::idaeidae::idea
::idealogies::ideologies
::idealogy::ideology
::identicial::identical
::identifers::identifiers
::identofy::identify
::ideosyncratic::idiosyncratic
::idiosyncracy::idiosyncrasy
::ignorence::ignorance
::ihaca::Ithaca
::iits the::it's the
::illegimacy::illegitimacy
::illiegal::illegal
::illution::illusion
::ilogical::illogical
::imagenary::imaginary
::imanent::imminent
::imcomplete::incomplete
::imediatly::immediately
::imense::immense
::immidately::immediately
::immidiately::immediately
::immunosupressant::immunosuppressant
::impecabbly::impeccably
::impedence::impedance
::implamenting::implementing
::imploys::employs
::importamt::important
::importent::important
::impossable::impossible
::imprioned::imprisoned
::imprisonned::imprisoned
::improvision::improvisation
::inablility::inability
::inaccessable::inaccessible
::inadiquate::inadequate
::inadquate::inadequate
::inadvertant::inadvertent
::inadvertantly::inadvertently
::inagurated::inaugurated
::inaguration::inauguration
::inaugures::inaugurates
::inbalance::imbalance
::inbalanced::imbalanced
::inbetween::between
::incarcirated::incarcerated
::incidentially::incidentally
::incidently::incidentally
::inclreased::increased
::incompetance::incompetence
::incompetant::incompetent
::incomptable::incompatible
::incomptetent::incompetent
::inconsistant::inconsistent
::incorperation::incorporation
::incorruptable::incorruptible
::incramentally::incrementally
::increadible::incredible
::incredable::incredible
::inctroduce::introduce
::inctroduced::introduced
::incunabla::incunabula
::indecate::indicate
::indefinately::indefinitely
::indefineable::undefinable
::indepedantly::independently
::independance::independence
::independant::independent
::independantly::independently
::independendet::independent
::indictement::indictment
::indigineous::indigenous
::indipendence::independence
::indipendent::independent
::indipendently::independently
::indispensible::indispensable
::indite::indict
::indulgue::indulge
::inefficienty::inefficiently
::inevatible::inevitable
::inevitible::inevitable
::inevititably::inevitably
::infalability::infallibility
::infallable::infallible
::infectuous::infectious
::infilitrate::infiltrate
::infilitrated::infiltrated
::infilitration::infiltration
::infinitly::infinitely
::inflamation::inflammation
::influance::influence
::influencial::influential
::influented::influenced
::infrantryman::infantryman
::ingreediants::ingredients
::inhabitans::inhabitants
::inherantly::inherently
::inheritence::inheritance
::initation::initiation
::initiaitive::initiative
::inmigrant::immigrant
::inmigrants::immigrants
::innoculate::inoculate
::innoculated::inoculated
::inocence::innocence
::inofficial::unofficial
::inpeach::impeach
::inpolite::impolite
::inprisonment::imprisonment
::inproving::improving
::insectiverous::insectivorous
::insensative::insensitive
::inseperable::inseparable
::insistance::insistence
::instade::instead
::instatance::instance
::instutionalized::institutionalized
::instutions::intuitions
::insurence::insurance
::int he::in the
::inteh::in the
::intepretator::interpretor
::interchangable::interchangeable
::interchangably::interchangeably
::intercontinetal::intercontinental
::interferance::interference
::interfereing::interfering
::intergrated::integrated
::intergration::integration
::internation::international
::interrim::interim
::interrugum::interregnum
::intertaining::entertaining
::interum::interim
::interupt::interrupt
::intervines::intervenes
::inthe::in the
::intruduced::introduced
::intrusted::entrusted
::inumerable::innumerable
::inventer::inventor
::invertibrates::invertebrates
::investingate::investigate
::inwhich::in which
::irelevent::irrelevant
::iresistable::irresistible
::iresistably::irresistibly
::iresistible::irresistible
::iresistibly::irresistibly
::iritable::irritable
::iritated::irritated
::ironicly::ironically
::irregardless::regardless
::irrelevent::irrelevant
::irreplacable::irreplaceable
::irresistable::irresistible
::irresistably::irresistibly
::issueing::issuing
::isthe::is the
::it snot::it's not
::it' snot::it's not
::itis::it is
::ititial::initial
::and it's::and its
::to it's::to its
::it's appearance::its appearance
::it's color::its color
::it's config::its config
::it's configuration::its configuration
::it's data::its data
::it's design::its design
::it's effect::its effect
::it's egg::its egg
::it's failure::its failure
::it's function::its function
::it's functionality::its functionality
::it's fur::its fur
::it's habitat::its habitat
::it's impact::its impact
::it's influence::its influence
::it's interface::its interface
::it's limits::its limits
::it's location::its location
::it's mate::its mate
::it's meaning::its meaning
::it's name::its name
::it's nest::its nest
::it's network::its network
::it's operation::its operation
::it's object::its object
::it's origin::its origin
::it's output::its output
::it's own::its own
::it's parts::its parts
::it's performance::its performance
::it's position::its position
::it's potential::its potential
::it's prey::its prey
::it's process::its process
::it's purpose::its purpose
::it's reputation::its reputation
::it's role::its role
::it's shape::its shape
::it's size::its size
::it's smell::its smell
::it's sound::its sound
::it's structure::its structure
::it's success::its success
::it's surface::its surface
::it's system::its system
::it's tail::its tail
::it's taste::its taste
::it's territory::its territory
::it's texture::its texture
::it's time::its time
::it's users::its users
::it's utility::its utility
::it's value::its value
::it's values::its values
::it's weight::its weight
::it's wings::its wings
::it's young::its young
::upon it's::upon its
::of it's::of its
::its a::it's a
::its always::it's always
::its an::it's an
::its as::it's as
::its apparently::it's apparently
::its the::it's the
::its any::it's any
::its available::it's available
::its beautiful::it's beautiful
::its because::it's because
::its been::it's been
::its broken::it's broken
::its called::it's called
::its changed::it's changed
::its clear::it's clear
::its cold::it's cold
::its communicated::it's communicated
::its complicated::it's complicated
::its developed::it's developed
::its difficult:: it's difficult
::its doing::it's doing
::its done::it's done
::its down::it's down
::its easy:: it's easy
::its easiest:: it's easiest
::its evolved::it's evolved
::its false::it's false
::its fine::it's fine
::its finished::it's finished
::its given::it's given
::its gone::it's gone
::its great::it's great
::its grown::it's grown
::its happened::it's happened
::its happening::it's happening
::its hard:: it's hard
::its here:: it's here
::its her::it's her
::its his::it's his
::its hot::it's hot
::its increased::it's increased
::its important::it's important
::its improved::it's improved
::its in::it's in
::its just::it's just
::its late::it's late
::its lacking::it's lacking
::its left::it's left
::its new::it's new
::its none::it's none
::its not::it's not
::its nothing::it's nothing
::its of::it's of
::its off::it's off
::its okay::it's okay
::its old::it's old
::its on::it's on
::its our::it's our
::its over::it's over
::its possible::it's possible
::its raining::it's raining
::its ready::it's ready
::its really::it's really
::its run::it's run
::its safe::it's safe
::its something::it's something
::its still::it's still
::its started::it's started
::its sunny::it's sunny
::its there::it's there
::its time::it's time
::its true::it's true
::its under::it's under
::its up::it's up
::its used::it's used
::its using::it's using
::its very::it's very
::its working::it's working
::its written::it's written
::its your::it's your
::its yours::it's yours
::iunior::junior
::jaques::jacques
::jeapardy::jeopardy
::jewelery::jewellery
::jewllery::jewellery
::johanine::Johannine
::journied::journeyed
::journies::journeys
::jstu::just
::juadaism::Judaism
::juadism::Judaism
::judgment::judgement
::judisuary::judiciary
::juducial::judicial
::juristiction::jurisdiction
::juristictions::jurisdictions
::kindergarden::kindergarten
::klenex::kleenex
::knifes::knives
::knive::knife
::knowlegeable::knowledgeable
::kwno::know
::labled::labelled
::labourious::laborious
::larrry::larry
::lasoo::lasso
::lastest::latest
::lastr::last
::lastyear::last year
::lattitude::latitude
::launchs::launch
::lavae::larvae
::layed::laid
::lazer::laser
::lazyness::laziness
::leaded::led
::leathal::lethal
::lefted::left
::legitamate::legitimate
::legitamite::legitimate
::leibnitz::leibniz
::lerans::learns
::lets'::let's
::let's him::lets him
::let's it::lets it
::leutenant::lieutenant
::levetate::levitate
::levetated::levitated
::levetates::levitates
::levetating::levitating
::liasion::liaison
::liason::liaison
::liasons::liaisons
::libell::libel
::libguistic::linguistic
::libguistics::linguistics
::libitarianisn::libertarianism
::librarry::library
::librery::library
::lieing::lying
::lieutenent::lieutenant
::lieved::lived
::lightening::lightning
::lightyear::light year
::lightyears::light years
::likelyhood::likelihood
::linnaena::linnaean
::lippizaner::lipizzaner
::liquify::liquefy
::lisense::license
::listners::listeners
::litature::literature
::litterally::literally
::litttle::little
::liuke::like
::liveing::living
::livley::lively
::lonelyness::loneliness
::longitudonal::longitudinal
::loosing::losing
::lotharingen::lothringen
::lukid::likud
::lveo::love
::lybia::Libya
::mackeral::mackerel
::magasine::magazine
::magincian::magician
::magnificient::magnificent
::magolia::magnolia
::maintainance::maintenance
::maintainence::maintenance
::maintance::maintenance
::maintenence::maintenance
::maintinaing::maintaining
::maintioned::mentioned
::majoroty::majority
::makeing::making
::malcom::Malcolm
::maltesian::Maltese
::mamal::mammal
::mamalian::mammalian
::managable::manageable
::manifestion::manifestation
::manisfestations::manifestations
::manoeuverability::maneuverability
::manufacturedd::manufactured
::manuver::maneuver
::marjority::majority
::markes::marks
::marketting::marketing
::marmelade::marmalade
::marrtyred::martyred
::marryied::married
::massachussets::Massachusetts
::massachussetts::Massachusetts
::massmedia::mass media
::masterbation::masturbation
::mataphysical::metaphysical
::materalists::materialist
::mathamatics::mathematics
::mathematicas::mathematics
::matheticians::mathematicians
::may of::may have
::mccarthyst::mccarthyist
::meaninng::meaning
::medacine::medicine
::medevial::medieval
::mediciney::mediciny
::medieval::mediaeval
::medievel::medieval
::mediterainnean::mediterranean
::meerkrat::meerkat
::melieux::milieux
::membranaphone::membranophone
::memeber::member
::mercentile::mercantile
::merchent::merchant
::messanger::messenger
::messenging::messaging
::metalurgic::metallurgic
::metalurgical::metallurgical
::metalurgy::metallurgy
::metamorphysis::metamorphosis
::metaphoricial::metaphorical
::meterologist::meteorologist
::meterology::meteorology
::methaphor::metaphor
::methaphors::metaphors
::michagan::Michigan
::micoscopy::microscopy
::midwifes::midwives
::might of::might have
::mileau::milieu
::milennia::millennia
::mileu::milieu
::miliraty::military
::millenia::millennia
::millenial::millennial
::millenialism::millennialism
::millepede::millipede
::millioniare::millionaire
::millitary::military
::minerial::mineral
::miniscule::minuscule
::ministery::ministry
::minumum::minimum
::mirrorred::mirrored
::miscellanious::miscellaneous
::mischeivous::mischievous
::mischevious::mischievous
::mischievious::mischievous
::misdameanor::misdemeanor
::misdameanors::misdemeanors
::misdemenor::misdemeanor
::misdemenors::misdemeanors
::misfourtunes::misfortunes
::mispell::misspell
::mispelled::misspelled
::mispelling::misspelling
::mispellings::misspellings
::missen::mizzen
::missisipi::Mississippi
::missonary::missionary
::misterious::mysterious
::mistery::mystery
::misteryous::mysterious
::mkea::make
::moderm::modem
::mohammedans::muslims
::moil::mohel
::momento::memento
::monestaries::monasteries
::monestary::monastery
::monickers::monikers
::monkies::monkeys
::monolite::monolithic
::monserrat::Montserrat
::montanous::mountainous
::montypic::monotypic
::moreso::more so
::morisette::Morissette
::morrisette::Morissette
::morroccan::moroccan
::morrocco::morocco
::morroco::morocco
::motiviated::motivated
::mottos::mottoes
::mounth::month
::mucuous::mucous
::mudering::murdering
::muhammadan::muslim
::multicultralism::multiculturalism
::multipled::multiplied
::multiplers::multipliers
::munbers::numbers
::muncipalities::municipalities
::munnicipality::municipality
::muscician::musician
::muscicians::musicians
::must of::must have
::mutiliated::mutilated
::myraid::myriad
::mysogynist::misogynist
::mysogyny::misogyny
::mythraic::Mithraic
::myu::my
::naieve::naive
::napoleonian::Napoleonic
::naturely::naturally
::naturual::natural
::naturually::naturally
::naywya::anyway
::nazereth::Nazareth
::neccesarily::necessarily
::neccesary::necessary
::neccessarily::necessarily
::neccessary::necessary
::neccessities::necessities
::necessiate::necessitate
::neglible::negligible
::negligable::negligible
::negociable::negotiable
::neice::niece
::neigbourhood::neighbourhood
::neolitic::neolithic
::nessasarily::necessarily
::nessecary::necessary
::nestin::nesting
::newyorker::New Yorker
::nightime::nighttime
::nineth::ninth
::ninteenth::nineteenth
::ninties::nineties ; fixed from "1990s": could refer to temperatures too.
::ninty::ninety
::nkwo::know
::noncombatents::noncombatants
::nonsence::nonsense
::nontheless::nonetheless
::noone::no one
::northereastern::northeastern
::notabley::notably
::noteable::notable
::noteably::notably
::noteriety::notoriety
::noticable::noticeable
::noticably::noticeably
::noticeing::noticing
::notive::notice
::notwhithstanding::notwithstanding
::noveau::nouveau
::nowdays::nowadays
::nowe::now
::nucular::nuclear
::nuculear::nuclear
::nuisanse::nuisance
::nullabour::Nullarbor
::numberous::numerous
::nuptual::nuptial
::nuremburg::Nuremberg
::nusance::nuisance
::nutritent::nutrient
::nutritents::nutrients
::nuturing::nurturing
::obediance::obedience
::obediant::obedient
::obession::obsession
::obsolecence::obsolescence
::obssessed::obsessed
::obstacal::obstacle
::obstancles::obstacles
::obstruced::obstructed
::ocassion::occasion
::ocassional::occasional
::ocassionally::occasionally
::ocassionaly::occasionally
::ocassioned::occasioned
::ocassions::occasions
::occassion::occasion
::occassional::occasional
::occassionally::occasionally
::occassionaly::occasionally
::occassioned::occasioned
::occassions::occasions
::occationally::occasionally
::occour::occur
::occurr::occur
::occurrance::occurrence
::occurrances::occurrences
::octohedra::octahedra
::octohedral::octahedral
::octohedron::octahedron
::ocurr::occur
::ocurring::occurring
::ocuring::occurring
::ocurrance::occurrence
::odouriferous::odoriferous
::odourous::odorous
::offereings::offerings
::offerred::offered
::oferred::offered
::officaly::officially
::ofits::of its
::oft he::of the ; Could be legitimate in poetry, but more usually a typo.
::oftenly::often
::ofthe::of the
::omision::omission
::omited::omitted
::omiting::omitting
::omlette::omelette
::ommision::omission
::ommited::omitted
::ommiting::omitting
::ommitted::omitted
::ommitting::omitting
::omnious::ominous
::omniverous::omnivorous
::omniverously::omnivorously
::oneof::one of
::onepoint::one point
::onomatopeia::onomatopoeia
::ont he::on the
::onthe::on the
::openess::openness
::opose::oppose
::oppasite::opposite
::oppenly::openly
::opperation::operation
::oppertunity::opportunity
::oppinion::opinion
::opponant::opponent
::oppononent::opponent
::opposate::opposite
::opposible::opposable
::oppositition::opposition
::oppossed::opposed
::opression::oppression
::opressive::oppressive
::opthalmic::ophthalmic
::opthalmologist::ophthalmologist
::opthalmology::ophthalmology
::opthamologist::ophthalmologist
::optmizations::optimizations
::optomism::optimism
::orded::ordered
::organim::organism
::orginization::organization
::orginize::organise
::orginized::organized
::oridinarily::ordinarily
::origanaly::originally
::originially::originally
::originnally::originally
::origional::original
::orthagonal::orthogonal
::orthagonally::orthogonally
::otherw::others
::ouevre::oeuvre
::outliar::outlier
::outof::out of
::outtage::outage
::overshaddowed::overshadowed
::overthe::over the
::overthere::over there
::overwelming::overwhelming
::overwheliming::overwhelming
::owudl::would
::oxident::oxidant
::oxigen::oxygen
::oximoron::oxymoron
::paide::paid
::paitience::patience
::paleolitic::paleolithic
::paliamentarian::parliamentarian
::palistian::Palestinian
::palistinian::Palestinian
::palistinians::Palestinians
::pallete::palette
::pamflet::pamphlet
::pamplet::pamphlet
::pantomine::pantomime
::papaer::paper
::papanicalou::Papanicolaou
::paralelly::parallelly
::paralely::parallelly
::parallely::parallelly
::paranthesis::parenthesis
::parantheses::parentheses
::paraphenalia::paraphernalia
::parellels::parallels
::parituclar::particular
::parrakeets::parakeets
::parralel::parallel
::parrallel::parallel
::parrallell::parallel
::parrallelly::parallelly
::parrallely::parallelly
::particularily::particularly
::partof::part of
::passerbys::passersby
::pasttime::pastime
::pastural::pastoral
::pattented::patented
::pavillion::pavilion
::payed::paid
::peacefuland::peaceful and
::peageant::pageant
::peculure::peculiar
::pedestrain::pedestrian
::peleton::peloton
::peloponnes::Peloponnesus
::penerator::penetrator
::penisular::peninsular
::penninsula::peninsula
::penninsular::peninsular
::pensinula::peninsula
::perade::parade
::percentof::percent of
::percentto::percent to
::percepted::perceived
::percieve::perceive
::perenially::perennially
::perfomers::performers
::performence::performance
::performes::performs
::perheaps::perhaps
::peripathetic::peripatetic
::perjery::perjury
::perjorative::pejorative
::permanant::permanent
::permenant::permanent
::permenantly::permanently
::perminent::permanent
::permissable::permissible
::perogative::prerogative
::perphas::perhaps
::perpindicular::perpendicular
::perseverence::perseverance
::persistance::persistence
::persistant::persistent
::personell::personnel
::personnell::personnel
::persuded::persuaded
::persue::pursue
::persued::pursued
::persuing::pursuing
::persuit::pursuit
::persuits::pursuits
::pertubation::perturbation
::pertubations::perturbations
::pessiary::pessary
::petetion::petition
::pharoah::Pharaoh
::phenomenom::phenomenon
::phenomenonal::phenomenal
::phenomenonly::phenomenally
::phenomonenon::phenomenon
::phenomonon::phenomenon
::phenonmena::phenomena
::pheonix::phoenix ; Not forcing caps, as it could be the bird
::philisopher::philosopher
::philisophical::philosophical
::philisophy::philosophy
::phillipine::Philippine
::phillipines::Philippines
::phillippines::Philippines
::phillosophically::philosophically
::philosphies::philosophies
::phonecian::Phoenecian
::phongraph::phonograph
::phylosophical::philosophical
::pilgrimmage::pilgrimage
::pilgrimmages::pilgrimages
::pinapple::pineapple
::pinnaple::pineapple
::pinoneered::pioneered
::plagarism::plagiarism
::planation::plantation
::plateu::plateau
::plausable::plausible
::playright::playwright
::playwrite::playwright
::playwrites::playwrights
::pleasent::pleasant
::plebicite::plebiscite
::poeoples::peoples
::poisin::poison
::polical::political
::polinator::pollinator
::polinators::pollinators
::politican::politician
::polute::pollute
::polyphonyic::polyphonic
::polysaccaride::polysaccharide
::polysaccharid::polysaccharide
::pomegranite::pomegranate
::popoulation::population
::popularaty::popularity
::populare::popular
::portayed::portrayed
::portraing::portraying
::portuguease::portuguese
::posessed::possessed
::posesses::possesses
::posessing::possessing
::posessions::possessions
::possable::possible
::possably::possibly
::posseses::possesses
::possesing::possessing
::possessess::possesses
::possibile::possible
::possiblility::possibility
::possiblilty::possibility
::possition::position
::postdam::Potsdam
::posthomous::posthumous
::postition::position
::potatoe::potato
::potrayed::portrayed
::poverful::powerful
::powerfull::powerful
::practially::practically
::practicaly::practically
::practicioner::practitioner
::practicioners::practitioners
::practicly::practically
::practioner::practitioner
::practioners::practitioners
::prairy::prairie
::praries::prairies
::pre-Colombian::pre-Columbian
::preample::preamble
::precedessor::predecessor
::preceeded::preceded
::preceeding::preceding
::precice::precise
::precident::precedent
::precurser::precursor
::predecesors::predecessors
::predicatble::predictable
::predomiantly::predominately
::prefering::preferring
::preferrably::preferably
::pregancies::pregnancies
::pregnent::pregnant
::preliferation::proliferation
::premeired::premiered
::premillenial::premillennial
::preminence::preeminence
::premonasterians::Premonstratensians
::preocupation::preoccupation
::prepair::prepare
::prepatory::preparatory
::preperation::preparation
::preperations::preparations
::preriod::period
::presance::presence
::presedential::presidential
::presense::presence
::prestigeous::prestigious
::presumabely::presumably
::presumibly::presumably
::pretection::protection
::prevelant::prevalent
::preverse::perverse
::previvous::previous
::priestood::priesthood
::primative::primitive
::primatively::primitively
::primatives::primitives
::primordal::primordial
::privelege::privilege
::priveleged::privileged
::priveleges::privileges
::privelige::privilege
::priveliged::privileged
::priveliges::privileges
::privelleges::privileges
::privilage::privilege
::priviledge::privilege
::priviledges::privileges
::privledge::privilege
::privledges::privileges
::probabilaty::probability
::probablistic::probabilistic
::probablly::probably
::probalibity::probability
::proccess::process
::proccessing::processing
::procedger::procedure
::proceedure::procedure
::processer::processor
::proclaimation::proclamation
::proclomation::proclamation
::professer::professor
::proffesed::professed
::proffesion::profession
::proffesional::professional
::proffesor::professor
::profilic::prolific
::progessed::progressed
::programable::programmable
::prohabition::prohibition
::prologomena::prolegomena
::prominance::prominence
::prominant::prominent
::prominantly::prominently
::promiscous::promiscuous
::promotted::promoted
::pronomial::pronominal
::pronouced::pronounced
::pronounched::pronounced
::pronounciation::pronunciation
::proove::prove
::prooved::proved
::prophacy::prophecy
::propmted::prompted
::propoganda::propaganda
::propogate::propagate
::propogates::propagates
::propogation::propagation
::propper::proper
::propperly::properly
::proprietory::proprietary
::proseletyzing::proselytizing
::protaganist::protagonist
::protaganists::protagonists
::protem::pro tem
::protocal::protocol
::protoganist::protagonist
::protrayed::portrayed
::protruberance::protuberance
::protruberances::protuberances
::prouncements::pronouncements
::provacative::provocative
::provinicial::provincial
::provisonal::provisional
::proximty::proximity
::pseudononymous::pseudonymous
::pseudonyn::pseudonym
::psuedo::pseudo
::psyhic::psychic
::ptogress::progress
::publically::publicly
::publicaly::publicly
::pucini::Puccini
::puertorrican::Puerto Rican
::puertorricans::Puerto Ricans
::pumkin::pumpkin
::puritannical::puritanical
::purposedly::purposely
::purpotedly::purportedly
::pursuade::persuade
::pursuaded::persuaded
::pursuades::persuades
::pususading::persuading
::pwn::own
::pyscic::psychic
::quantaty::quantity
::quantitiy::quantity
::quarantaine::quarantine
::questioms::questions
::questonable::questionable
::quicklyu::quickly
::quinessential::quintessential
::quitted::quit
::rabinnical::rabbinical
::racaus::raucous
::radiactive::radioactive
::radify::ratify
::rancourous::rancorous
::rarified::rarefied
::rasberry::raspberry
::reaccurring::recurring
::readmition::readmission
::realitvely::relatively
::reasearch::research
::rebiulding::rebuilding
::rebounce::rebound
::reccommend::recommend
::reccommended::recommended
::reccommending::recommending
::reccuring::recurring
::receeded::receded
::receeding::receding
::receieve::receive
::receivedfrom::received from
::rechargable::rechargeable
::recide::reside
::recided::resided
::recident::resident
::recidents::residents
::reciding::residing
::reciepents::recipients
::recipiant::recipient
::recipiants::recipients
::recogise::recognise
::recomending::recommending
::reconaissance::reconnaissance
::reconcilation::reconciliation
::reconnaissence::reconnaissance
::recontructed::reconstructed
::recordproducer::record producer
::recurrance::recurrence
::rediculous::ridiculous
::redudently::redundantly
::reedeming::redeeming
::reenforced::reinforced
::refedendum::referendum
::referiang::referring
::referrence::reference
::referrs::refers
::reffered::referred
::refference::reference
::refrers::refers
::refridgeration::refrigeration
::refridgerator::refrigerator
::refromist::reformist
::refusla::refusal
::regardes::regards
::regulaotrs::regulators
::regularily::regularly
::rehersal::rehearsal
::reicarnation::reincarnation
::reigining::reigning
::reknown::renown
::reknowned::renowned
::relatiopnship::relationship
::relected::reelected
::releive::relieve
::releived::relieved
::releiver::reliever
::relevence::relevance
::relevent::relevant
::relient::reliant
::religeous::religious
::religously::religiously
::relinqushment::relinquishment
::relitavely::relatively
::relized::realised
::reluctent::reluctant
::remaing::remaining
::rememberable::memorable
::rememberance::remembrance
::remembrence::remembrance
::remenant::remnant
::remenicent::reminiscent
::reminent::remnant
::reminescent::reminiscent
::reminscent::reminiscent
::reminsicent::reminiscent
::rendevous::rendezvous
::rendezous::rendezvous
::renedered::rende
::rentors::renters
::reoccurrence::recurrence
::reorganision::reorganisation
::repentence::repentance
::repentent::repentant
::repeteadly::repeatedly
::repetion::repetition
::repid::rapid
::reportadly::reportedly
::represantative::representative
::representive::representative
::representives::representatives
::reproducable::reproducible
::reprtoire::repertoire
::reptition::repetition
::resembelance::resemblance
::resembes::resembles
::resemblence::resemblance
::resignement::resignment
::resistable::resistible
::resistence::resistance
::resistent::resistant
::resollution::resolution
::respomse::response
::responce::response
::responsability::responsibility
::responsable::responsible
::responsibile::responsible
::ressemblance::resemblance
::ressemble::resemble
::ressembled::resembled
::ressemblence::resemblance
::ressembling::resembling
::resssurecting::resurrecting
::ressurrection::resurrection
::restaraunt::restaurant
::restaraunteur::restaurateur
::restaraunteurs::restaurateurs
::restaraunts::restaurants
::restauranteurs::restaurateurs
::restauration::restoration
::restauraunt::restaurant
::resteraunt::restaurant
::resteraunts::restaurants
::resturaunt::restaurant
::resurecting::resurrecting
::resurgance::resurgence
::retalitated::retaliated
::retalitation::retaliation
::reuse::re-use
::revaluated::reevaluated
::reversable::reversible
::rewitten::rewritten
::rewriet::rewrite
::rhymme::rhyme
::rhythem::rhythm
::rhythim::rhythm
::rigeur::rigueur
::rigourous::rigorous
::rininging::ringing
::rised::rose
::rockerfeller::Rockefeller
::rococco::rococo
::rocord::record
::rucuperate::recuperate
::rudimentatry::rudimentary
::rulle::rule
::rumers::rumors
::runnung::running
::russion::Russian
::ry::try
::rythem::rhythm
::rythim::rhythm
::rythyms::rhythms
::sacrafice::sacrifice
::sacreligious::sacrilegious
::sacrifical::sacrificial
::saidhe::said he
::saidit::said it
::saidt he::said the
::saidthat::said that
::saidthe::said the
::salery::salary
::sanctionning::sanctioning
::sandess::sadness
::sandwhich::sandwich
::sanhedrim::Sanhedrin
::sargant::sergeant
::sargeant::sergeant
::saterday::Saturday
::saterdays::Saturdays
::satisfactority::satisfactorily
::satric::satiric
::satrical::satirical
::satrically::satirically
::sattelite::satellite
::sattelites::satellites
::saught::sought
::saxaphone::saxophone
::scaleable::scalable
::scandanavia::Scandinavia
::scaricity::scarcity
::scavanged::scavenged
::schedual::schedule
::scholarstic::scholastic
::screenwrighter::screenwriter
::scrutinity::scrutiny
::scuptures::sculptures
::secratary::secretary
::secretery::secretary
::sedereal::sidereal
::seeked::sought
::segementation::segmentation
::seguoys::segues
::seige::siege
::seldomly::seldom
::sence::sense
::sensure::censure
::sentance::sentence
::separeate::separate
::sepina::subpoena
::sepulchure::sepulchre
::sercumstances::circumstances
::sergent::sergeant
::settelement::settlement
::severeal::several
::severley::severely
::severly::severely
::shaddow::shadow
::shesaid::she said
::shineing::shining
::shopkeeepers::shopkeepers
::shortwhile::short while
::shoudlnt::shouldn't
::should of::should have
::showinf::showing
::shreak::shriek
::shrinked::shrunk
::sideral::sidereal
::sieze::seize
::siezed::seized
::siezing::seizing
::siezure::seizure
::siezures::seizures
::siginificant::significant
::signficiant::significant
::signifacnt::significant
::signifantly::significantly
::significently::significantly
::signifigant::significant
::signifigantly::significantly
::signitories::signatories
::signitory::signatory
::silicone chip::silicon chip
::simalar::similar
::similarily::similarly
::similiar::similar
::similiarity::similarity
::similiarly::similarly
::simmilar::similar
::simpley::simply
::simplier::simpler
::sincerley::sincerely
::sincerly::sincerely
::singsog::singsong
::sionist::Zionist
::sionists::Zionists
::sixtin::Sistine
::skagerak::Skagerrak
::skateing::skating
::slaugterhouses::slaughterhouses
::smoothe::smooth
::smoothes::smooths
::sneeks::sneaks
::snese::sneeze
::socalism::socialism
::soilders::soldiers
::solatary::solitary
::soliliquy::soliloquy
::soluable::soluble
::sophicated::sophisticated
::sophmore::sophomore
::sorceror::sorcerer
::sorrounding::surrounding
::sot hat::so that
::sourth::south
::sourthern::southern
::souvenier::souvenir
::souveniers::souvenirs
::soveits::soviets
::soveits::soviets(x
::sovereignity::sovereignty
::soverignity::sovereignty
::spainish::Spanish
::speach::speech
::speciallized::specialised
::specifiying::specifying
::speciman::specimen
::spectaulars::spectaculars
::spendour::splendour
::spermatozoan::spermatozoon
::spoace::space
::sponser::sponsor
::sponsered::sponsored
::sponzored::sponsored
::spoonfulls::spoonfuls
::sportscar::sports car
::sppeches::speeches
::spreaded::spread
::sprech::speech
::spriritual::spiritual
::stablility::stability
::stainlees::stainless
::stateman::statesman
::statememts::statements
::steriods::steroids
::stilus::stylus
::stingent::stringent
::stiring::stirring
::stirrs::stirs
::stopry::story
::stornegst::strongest
::stradegies::strategies
::stradegy::strategy
::stratagically::strategically
::streemlining::streamlining
::strenghened::strengthened
::strenghtened::strengthened
::strengtened::strengthened
::strenous::strenuous
::strictist::strictest
::strikely::strikingly
::stubborness::stubbornness
::studdy::study
::stuggling::struggling
::subconsiously::subconsciously
::subjudgation::subjugation
::submachne::submachine
::subpecies::subspecies
::subsiduary::subsidiary
::substancial::substantial
::substituded::substituted
::substract::subtract
::substracted::subtracted
::substracting::subtracting
::substraction::subtraction
::substracts::subtracts
::subterranian::subterranean
::suburburban::suburban
::succceeded::succeeded
::succcesses::successes
::succedded::succeeded
::succeded::succeeded
::succeds::succeeds
::succesion::succession
::succesive::successive
::succsess::success
::suceeded::succeeded
::suceeding::succeeding
::suceeds::succeeds
::sucesion::succession
::sucesses::successes
::sucession::succession
::sucessive::successive
::sucessor::successor
::sucessot::successor
::sucidial::suicidal
::sufferage::suffrage
::sufferred::suffered
::sufferring::suffering
::sufficiant::sufficient
::suggestable::suggestible
::superintendant::superintendent
::suphisticated::sophisticated
::suplimented::supplemented
::suposedly::supposedly
::suposes::supposes
::suposing::supposing
::supplamented::supplemented
::suppliementing::supplementing
::supposingly::supposedly
::suppossed::supposed
::suprisingly::surprisingly
::suprize::surprise
::suprized::surprised
::suprizing::surprising
::suprizingly::surprisingly
::suroundings::surroundings
::surounds::surrounds
::surplanted::supplanted
::surpress::suppress
::surpressed::suppressed
::surprize::surprise
::surprized::surprised
::surprizing::surprising
::surprizingly::surprisingly
::surrended::surrendered
::surrepetitious::surreptitious
::surrepetitiously::surreptitiously
::surreptious::surreptitious
::surreptiously::surreptitiously
::surrundering::surrendering
::surveilence::surveillance
::surveill::surveil
::surveyer::surveyor
::surviver::survivor
::survivers::survivors
::survivied::survived
::suseptable::susceptible
::suseptible::susceptible
::suspention::suspension
::swaer::swear
::swaers::swears
::swepth::swept
::symetrical::symmetrical
::symetrically::symmetrically
::symetry::symmetry
::symettric::symmetric
::symmetral::symmetric
::symmetricaly::symmetrically
::synagouge::synagogue
::syncronization::synchronization
::synonomous::synonymous
::synonymns::synonyms
::synphony::symphony
::syphyllis::syphilis
::syrap::syrup
::sysmatically::systematically
::tabacco::tobacco
::targetted::targeted
::targetting::targeting
::tarrif::tariff
::tarrifs::tariffs
::tath::that
::tattooes::tattoos
::taxanomic::taxonomic
::taxanomy::taxonomy
::teached::taught
::techiniques::techniques
::technitian::technician
::technnology::technology
::tehw::the
::telelevision::television
::televize::televise
::tellt he::tell the
::temparate::temperate
::temperarily::temporarily
::temperment::temperament
::tempermental::temperamental
::tenacle::tentacle
::tenacles::tentacles
::tendacy::tendency
::tendancies::tendencies
::tendancy::tendency
::tendonitis::tendinitis
::tennisplayer::tennis player
::termoil::turmoil
::terrestial::terrestrial
::territorist::terrorist
::testiclular::testicular
::tghe::the
::tghis::this
::tshi::this
::thsi::this
::th::the
::thatt he::that the
::thatthe::that the
::theather::theatre
::thecompany::the company
::theese::these
::thefirst::the first
::thegovernment::the government
::theh::the
::theif::thief
::their are::there are
::their is::there is
::theives::thieves
::themself::themselves
::themselfs::themselves
::thenew::the new
::there's is::theirs is
::thesame::the same
::thetwo::the two
::they're are::there are
::they're is::there is
::thgat::that
::thge::the
::thigsn::things
::thisyear::this year
::thiunk::think
::thoguth::thought
::threee::three
::threshhold::threshold
::throrough::thorough
::thw::the
::thyat::that
::ti"s::it's ; "
::tiget::tiger
::tihkn::think
::timne::time
::tiogether::together
::tje::the
::tjhe::the
::tjpanishad::upanishad
::tobbaco::tobacco
::toghether::together
::toldt he::told the
::tolerence::tolerance
::tolkein::Tolkien
::tommorow::tomorrow
::tommorrow::tomorrow
::toriodal::toroidal
::tormenters::tormentors
::torpeados::torpedoes
::torpedos::torpedoes
::tot he::to the
::tothe::to the
::toubles::troubles
::tounge::tongue
::towords::towards
::tradionally::traditionally
::traditionnal::traditional
::traditition::tradition
::trafficed::trafficked
::trafficing::trafficking
::trancendent::transcendent
::trancending::transcending
::transcendance::transcendence
::transcendant::transcendent
::transcendentational::transcendental
::transcripting::transcribing
::transending::transcending
::transistion::transition
::translater::translator
::translaters::translators
::transmissable::transmissible
::tremelo::tremolo
::tremelos::tremolos
::triathalon::triathlon
::triguered::triggered
::triology::trilogy
::troling::trolling
::troup::troupe
::truely::truly
::truley::truly
::trustworthyness::trustworthiness
::tryed::tried
::tthe::the
::twpo::two
::tyhat::that
::tyhe::the
::tyhe::they
::tyranical::tyrannical
::tyranies::tyrannies
::tyrany::tyranny
::tyrranies::tyrannies
::tyrrany::tyranny
::ubiquitious::ubiquitous
::ucould::could
::uise::use
::ukelele::ukulele
::ukranian::Ukrainian
::ultimely::ultimately
::unahppy::unhappy
::unanymous::unanimous
::unavailible::unavailable
::unballance::unbalance
::unbeleivable::unbelievable
::uncertainity::uncertainty
::unchallengable::unchallengeable
::unchangable::unchangeable
::uncompetive::uncompetitive
::unconcious::unconscious
::unconciousness::unconsciousness
::unconfortability::discomfort
::unconvential::unconventional
::undecideable::undecidable
::understoon::understood
::undert he::under the
::undesireable::undesirable
::undetecable::undetectable
::undoubtely::undoubtedly
::uneccesary::unnecessary
::unequalities::inequalities
::unforetunately::unfortunately
::unforgetable::unforgettable
::unforgiveable::unforgivable
::unfourtunately::unfortunately
::unihabited::uninhabited
::unilateraly::unilaterally
::unilatreal::unilateral
::unilatreally::unilaterally
::uninterruped::uninterrupted
::uninterupted::uninterrupted
::unitedstates::United States
::unitesstates::United States
::unmanouverable::unmanoeuvrable
::unmistakeably::unmistakably
::unneccesarily::unnecessarily
::unneccesary::unnecessary
::unneccessarily::unnecessarily
::unneccessary::unnecessary
::unnecesarily::unnecessarily
::unoffical::unofficial
::unoperational::nonoperational
::unoticeable::unnoticeable
::unplease::displease
::unpleasently::unpleasantly
::unplesant::unpleasant
::unprecendented::unprecedented
::unprecidented::unprecedented
::unrepentent::unrepentant
::unrepetant::unrepentant
::unrepetent::unrepentant
::unsubstanciated::unsubstantiated
::unsuccesful::unsuccessful
::unsuccessfull::unsuccessful
::unsucesful::unsuccessful
::unsucessful::unsuccessful
::unsucessfull::unsuccessful
::unsuprised::unsurprised
::unsuprising::unsurprising
::unsuprisingly::unsurprisingly
::unsuprized::unsurprised
::unsuprizing::unsurprising
::unsuprizingly::unsurprisingly
::unsurprized::unsurprised
::unsurprizing::unsurprising
::unsurprizingly::unsurprisingly
::untill::until
::untranslateable::untranslatable
::unuseable::unusable
::unusuable::unusable
::unwarrented::unwarranted
::unweildly::unwieldy
::unwieldly::unwieldy
::upcomming::upcoming
::upgradded::upgraded
::useage::usage
::usefull::useful
::usefuly::usefully
::useing::using
::usiing::using
::ususally::usually
::ut::but
::vaccum::vacuum
::vaccume::vacuum
::vacinity::vicinity
::vaguaries::vagaries
::vaialable::available
::vailidty::validity
::valetta::valletta
::valueable::valuable
::varient::variant
::varients::variants
::vasall::vassal
::vasalls::vassals
::vegatarian::vegetarian
::vegitable::vegetable
::vegitables::vegetables
::vehicule::vehicle
::vell::well
::venemous::venomous
::vengance::vengeance
::vengence::vengeance
::vermillion::vermilion
::versitilaty::versatility
::versitlity::versatility
::vetween::between
::vigilence::vigilance
::vigourous::vigorous
::villian::villain
::villification::vilification
::villify::vilify
::vincinity::vicinity
::violentce::violence
::visable::visible
::visably::visibly
::vitories::victories
::volcanoe::volcano
::volkswagon::Volkswagen
::volontary::voluntary
::volonteer::volunteer
::volonteered::volunteered
::volonteering::volunteering
::volonteers::volunteers
::volounteer::volunteer
::volounteered::volunteered
::volounteering::volunteering
::volounteers::volunteers
::vreity::variety
::vulnerablility::vulnerability
::vulnerible::vulnerable
::vyer::very
::vyre::very
::wa snot::was not
::waas::was
::wan tit::want it
::warantee::warranty
::wardobe::wardrobe
::warrent::warrant
::warrriors::warriors
::wass::was
::wayword::wayward
::weaponary::weaponry
::weas::was
::weilded::wielded
::wendsay::Wednesday
::wensday::Wednesday
::wereabouts::whereabouts
::werre::were
::wether::weather
::whant::want
::whants::wants
::whent he::when the
::wherease::whereas
::whereever::wherever
::wherre::where
::whicht he::which the
::whith::with
::whlch::which
::wholey::wholly
::wiegh::weigh
::wiew::view
::willbe::will be
::wille::will
::willingless::willingness
::windoes::windows
::wintery::wintry
::witha::with a
::withe::with
::witheld::withheld
::withing::within
::withold::withhold
::witht he::with the
::witht::with
::withthe::with the
::witn::with
::wiull::will
::wonderfull::wonderful
::workststion::workstation
::worls::world
::worstened::worsened
::would of::would have
::wouldbe::would be
::wresters::wrestlers
::writting::writing
::ws::was
::wuould::would
::wupport::support
::x-Box::Xbox
::xenophoby::xenophobia
::xomplex::complex
::yaching::yachting
::yatch::yacht
::yeilding::yielding
::yersa::years
::yoiu::you
::youare::you are
::youseff::yousef
::ytou::you
::zeebra::zebra
:C:Nto::Not
:C:nto::not
;------------------------------------------------------------------------------
;  Capitalise dates
;------------------------------------------------------------------------------
::monday::Monday
::tuesday::Tuesday
::wednesday::Wednesday
::thursday::Thursday
::friday::Friday
::saturday::Saturday
::sunday::Sunday
::january::January
::february::February
::april::April
::june::June
::july::July
::august::August
::september::September
::october::October
::november::November
::december::December
::fpga::FPGA
::pcie::PCIe
::icd::ICD
::fw::FW
::scadapp::SCADApp
::scad::SCAD
;------------------------------------------------------------------------------
; Anything below this point was added to the script by the user via the Win+H hotkey.
;------------------------------------------------------------------------------
::nd::and
::hilighting::highlighting
::ahven't::haven't
::ahvent::haven't
::arent'::aren't
::arent::aren't
::arn't::aren't
::cant'::can't
::cant::can't
::childrens::children's
::companys::company's
::coudln't::couldn't
::coudn't::couldn't
::couldnt::couldn't
::coudlnt::couldn't
::didint::didn't
::didnt::didn't
::dint::didn't
::didtn::didn't
::dno't::don't
::dnot::don't
::do'nt::don't
::deosnt::doesn't
::doens't::doesn't
::doens::doesn't
::doenst::doesn't
::does't::doesn't
::doesnt::doesn't
::doest::doesn't
::doestn::doesn't
::doent::doesn't
::dosnt::doesn't
::dont::don't
::dosen't::doesn't
::dosn't::doesn't
::dotn::don't
::gentlemens::gentlemen's
::hadnt::hadn't
::hasnt::hasn't
::havent::haven't
::heres::here's
::hes::he's
::hsan't::hasn't
::i'd::I'd
::i'll::I'll
::Ill'::I'll
::i'm::I'm
::Im'::I'm
::i've::I've
::id'::I'd
::Id'::I'd
::im::I'm
::isnt'::isn't
::isnt::isn't
::istn::isn't
::Istn::Isn't
::its'::it's
::iv'e::I've
::ive::I've
::lets::let's
::odnt::don't
::taht's::that's
::thast::that's
::thats::that's
::theres::there's
::theyd::they'd
::theyll::they'll
::theyl'l::they'll
::theyll'::they'll
::theyre::they're
::theyr'e::they're
::theyre'::they're
::theyve::they've
::theyv'e::they've
::theyve'::they've
::ti's::it's
::todays::today's
::w'ere::we're
::wasnt::wasn't
::wer'e::we're
::wern't::weren't
::werent::weren't
::whats::what's
::whats'::what's
::wnot::won't
::wo'nt::won't
::womens::women's
::wont::won't
::wotn::won't
::woudln't::wouldn't
::woudlnt::wouldn't
::woudn't::wouldn't
::wouldnt::wouldn't
::yorue::you're
::you'er::you're
::you're call::your call
::youd::you'd
::youe'r::you're
::youer::you're
::youll::you'll
::your'e::you're
::youre::you're
::youv'e::you've
::youve::you've
::repetative::repetitive
::repetetive::repetitive
::deterant::deterrent
::deterants::deterrents
::inprecise::imprecise
::god::God
::ram::RAM
::rescheulde::reschedule
::awhiel::awhile
::determing::determining
::documention::documentation
::ar eyou::are you
::al lthe::all the
::interestin::interest in
::implmenetation::implementation
::intesreting::interesting
::releated::related
::confusgin::confusing
::your a::you're a
::your an::you're an
::your her::you're her
::your here::you're here
::your his::you're his
::your my::you're my
::your the::you're the
::your their::you're their
::your your::you're your
::you're own::your own
::you're time::your time
::Suggetsions::Suggestions
::specificed::specified
::docn::documentation
::docs::documents
::doc::document
::votlages::voltages
::can not::cannot
::ackolwedgement::acknowledgement
::questionaire::questionnaire
::ppl::people
::a the::at the
::ist he::is the
::Hoewver::However
::dsp::DSP
::Techncially::Technically
::tehcncailly::technically
::spreadhsset::spreadsheet
::implmeneted::implemented
::Unforntuately::Unfortunately
::spreadhseet::spreadsheet
::trasnceivers::transceivers
::utliamtely::ultimately
::implmenet::implement
::Unfortuantley::Unfortunatley
::respresnted::represented
::challenege::challenge
::appercaite::appreciate
::forsee::foresee
::jtag::JTAG
::avstx8::AvSTx8
::avstx32::AvSTx32
::opencl::OpenCL
::schedeuled::scheduled
::jesd::JESD
::orf::for
::seqeuencing::sequencing
::abuot::aboyout
::intpretation::intepretation
::developemtn::development
::gogin::going
::hweover::however
::deos::does
::wuold::woyould
::hsoudl::should
::emif::EMIF
::seomthing::soemthing
::bets::best
::fpgas::FPGAs
::webex::WebEx
::soluations::solutions
::appreacited::appreciated
::Unfortuatnely::Unfortunately
::pelsae::please
::xcvr::XCVR
::xcvrs::XCVRs
::mhz::Mhz
::quartus::Quartus
::cuodl::could
::dma::DMA
::htme::them
::Soc::SoC
::seotmhing::something
::usb::USB
::awalys::always
::makgni::making
::simplist::simplest
::defintinon::definition
::fof::for
::determininstic::deterministic
::Hye::Hey
::th e::the
::npoe::nope
::speicifc::specifIc
::tho::though
::Godo::Good
::resopnses::responses
::reposne::response
::instatiating::instantiating
::gbe::GbE
::Unforutntely::Unfortunately
::Ocne::Once
::Welcoem::Welcome
::osemthing::something
::Stya::Stay
::udnersatnding::understanding
::undertsands::understands
::transceviers::transceivers
::shceudled::scheduled
::doucmentaotin::documentation
::diffuclty::difficulty
::Vinec::Vince
::asap::ASAP
::direcotires::directorIes
::partioin::partition
::Quratus::Quartus
::hcnage::change
::opinons::opinIons
::Unforutnately::Unfortunately
::Unforutnatley::Unfortunately
::shcematic::schematic
::shcematics::schematics
::hwy::why
::disucsison::discussion
::Produciton::ProductIon
::doucments::documents
::adivsigin::advising
::opporotunity::opportunity
::cocks::clocks
::piont::poInt
::deisng::design
::hps::HPS
::cusomter::customer
::conecnered::concerned
::iopll::IOPLL
::Suggesitons::SuggestIons
::Vicne::Vince
::pgorammer::programmer
::Antony::Anthony
::knowledgable::knowledgeable
::begininning::beginning
::sesen::sense
::concnered::concerned
::calcualtions::calculations
::discoved::discovered
::possiblites::possibIlites
::disadvantes::disadvantages
::problsme::problems
::componets::components
::axi::AXI
::hcnaged::changed
::consdiering::considering
::windriver::Wind River
::WindRiver::Wind River
::levaing::leaving
::leaveing::leaving
::mpsoc::MPSoC
::artitechture::architecture
::environemental::environemental
::vxworks::VxWorks
::interpretting::interpreting
::feb::Feb
::Porbably::Probably
::defitintion::definition
::reporsitory::repository
::apparoch::appraoch
::depednencey::dependencey
::minimim::minimum
::fukcing::fucking
::ecrypted::encrypted
::NTO::NOT
::canabalize::cannibalize
::xilinx::Xilinx
::sepcfiication::specification
::Unfrotuantely::Unfortunately
::thuoght::thought
::imprsesion::impression
::unfotunatley::unfortunately
::bascially::basically
::checkins::check-ins
::inprecisely::imprecisely
::youa re::you are
::asychronously::asynchronously
::depdenency::dependency
::incredably::incredibly
::os::so
::HSL::HLS
::hls::HLS
::disparite::disparate
::formated::formatted
;------------------------------------------------------------------------------
; Generated Misspellings - the main list
;------------------------------------------------------------------------------
#include %A_ScriptDir%\generatedwords.ahk
#If