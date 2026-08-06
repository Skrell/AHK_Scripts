; c = case sensitive
; c1 = ignore the case that was typed, always use the same case for output
; * = immediate change (no need for space, period, or enter)
; ? = triggered even when the character typed immediately before it is alphanumeric
; r = raw output

; the auto-exec section ends at the first hotkey/hotstring or return or exit or at the script end - whatever comes first; function definitions get ignored by the execution flow.

#NoEnv
#SingleInstance Force
#InstallMouseHook
#InstallKeybdHook
#UseHook
#include %A_ScriptDir%\UIAutomation-main\Lib\UIA_Interface.ahk
; #include %A_ScriptDir%\Acc.ahk
#HotString EndChars ()[]{}:;,.?!`n `t
#MaxhotKeysPerInterval 500
#KeyHistory 25

; #include %A_ScriptDir%\_VD.ahk
; +----------------------------------------------------------------------------+
; | Virtual Desktop DLL Bindings                                               |
; | Holds the DLL name/path, module handle, and exported function pointers     |
; | used by the virtual-desktop helpers.                                       |
; +----------------------------------------------------------------------------+
Global k_VDA_DllName                                 := "VirtualDesktopAccessor_Win11.dll"
Global k_dllPath                                     := A_ScriptDir . "\" . k_VDA_DllName  ; destination: next to EXE/script
Global hVirtualDesktopAccessor                       := 0
Global GetDesktopCountProc                           := 0
Global GoToDesktopNumberProc                         := 0
Global GetCurrentDesktopNumberProc                   := 0
Global IsWindowOnCurrentVirtualDesktopProc           := 0
Global IsWindowOnDesktopNumberProc                   := 0
Global MoveWindowToDesktopNumberProc                 := 0
Global IsPinnedWindowProc                            := 0
Global GetDesktopNameProc                            := 0
Global SetDesktopNameProc                            := 0
Global CreateDesktopProc                             := 0
Global RemoveDesktopProc                             := 0

SendMode, Input ; It injects the whole keystroke atomically, reducing the window where logical/physical can disagree

; SetKeyDelay is not obeyed by SendInput; there is no delay between keystrokes in that mode.
; This same is true for Send when SendMode Input is in effect.
; SetKeyDelay, -1, -1
SetMouseDelay,   -1
SetBatchLines,   -1 ; Remove AHK's built-in "cooperate with the OS" sleeps
SetWinDelay,      1 ;
SetControlDelay,  1 ;

; +----------------------------------------------------------------------------+
; | Window, Search, And Selection State                                        |
; | Tracks the live window lists, Alt+Tab-style cycling, popup-selection UI,   |
; | and other top-level state shared by the window-management hotkeys.          |
; +----------------------------------------------------------------------------+
Global CurrentDesktop                                      := 1
Global mouseMoving                                         := False
Global CanceledWinSwap                                     := False
Global ValidWindows                                        := []
Global GroupedWindows                                      := []
Global MinimizedWindows                                    := []
Global PrevActiveWindows                                   := []
Global allWinArray                                         := []
Global cycleCount                                          := 1
; Alt+Tab/Alt+` can receive the next cycle key while DrawWindowTitlePopup() is still
; building the GUI. Buffer that press here so the loop consumes it instead of losing it.
Global bufferedCycleAdvance                                := False
Global startHighlight                                      := False
Global k_border_thickness                                  := 4
Global k_border_color                                      := 0xFF00FF
Global hitTAB                                              := False
Global hitTilde                                            := False
Global SearchingWindows                                    := False
Global UserInputTrimmed                                    := ""
Global memotext                                            := ""
Global totalMenuItemCount                                  := 0
Global onlyTitleFound                                      := ""
Global CancelClose                                         := False
Global DrawingRect                                         := False
Global LclickSelected                                      := False
; +----------------------------------------------------------------------------+
; | Measurement Overlay State                                                  |
; | Backs the temporary pixel-measure tool so one drag can reuse lightweight    |
; | GUI overlays instead of rebuilding them on every mouse move.               |
; +----------------------------------------------------------------------------+
; True while the pixel-measure drag tool owns the current LButton hold.
Global measureActive                                       := False
; Tracks whether the three lightweight measurement GUIs have already been created.
Global measureGuiReady                                     := False
; GUI control variable backing the live X/Y pixel readout.
Global MeasureText                                         := ""
; Screen-space mouse-down origin for the current measurement drag.
Global measureStartX                                       := 0
; Screen-space mouse-down origin for the current measurement drag.
Global measureStartY                                       := 0
; Thickness in pixels for the horizontal and vertical measurement guides.
Global k_measureThickness                                  := 3
Global currMonHeight                                       := 0
Global currMonWidth                                        := 0
Global LbuttonEnabled                                      := True
; +----------------------------------------------------------------------------+
; | Typing Auto-Fix, Deferred Rewrite, And Activation State                    |
; | Caches whether typing fixes are allowed, queues short-lived deferred text   |
; | rewrites, and keeps focus/activation bookkeeping cheap while typing or      |
; | clicking into another window.                                               |
; +----------------------------------------------------------------------------+
Global X_PriorPriorHotKey                                  :=
Global StopAutoFix                                         := False
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
; True while the post-boundary hotstring-buffer reset timer is pending.
Global hotstringResetTimerPending                          := False
; Target hotstringBoundarySeq that schedules a post-boundary Hotstring("Reset").
; Zero means no deferred buffer reset is pending.
Global hotstringResetAtBoundarySeq                         := 0
; Maximum age for a same-window/same-control fast cache hit.
Global k_typingAutoFixFastTtlMs                            := 125
; Minimum gap before repeating slower UIA/MSAA probes for unchanged focus.
Global k_typingAutoFixSlowPathMs                           := 400
; Tick count of the last slow UIA/MSAA probe attempt.
Global typingAutoFixSlowProbeTick                          := 0
; Monotonic count of physical text-input key-downs. Async editability probes
; compare this with their queued snapshot to detect typing during the probe.
Global physicalTypingSeq                                   := 0
; Monotonic count of physical keys that exactly match #HotString EndChars.
Global hotstringBoundarySeq                                := 0
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
; Temporary slash-fix Enter interception flag. After a qualifying letter + "/",
; this diverts the next Enter into the custom $Enter handler so slash+Enter can
; either commit "{BS}{?}{ENTER}" inline or fall back to one normal Enter, but
; never let both the raw key and the rewrite path fire.
Global disableEnter                                        := False
; +----------------------------------------------------------------------------+
; | Everything Edit1 Deferred Column Auto-Fit State                            |
; | Queues Ctrl+NumpadAdd for Everything's search box so the send runs only    |
; | after typing has gone quiet and the same Edit1 still owns focus.           |
; +----------------------------------------------------------------------------+
; Focused control name captured when Everything Edit1 auto-fit is queued so
; the deferred send can require the same search field before firing.
Global tbcEverythingAdjustCtrl                             := ""
; Focused control class captured with the queued Everything auto-fit so the
; flush step can require the same concrete control identity when available.
Global tbcEverythingAdjustCtrlClass                        := ""
; Focused control HWND captured when Everything auto-fit is queued so the flush
; step can reject a later Edit1 from a different control instance.
Global tbcEverythingAdjustCtrlHwnd                         := 0
; Active Everything window captured for the deferred search-box auto-fit send.
Global tbcEverythingAdjustHwnd                             := 0
; Monotonic token incremented for each newer Everything Edit1 auto-fit request
; so older timer callbacks can detect that typing already superseded them.
Global tbcEverythingAdjustId                               := 0
; Tick count recorded when the Everything Edit1 auto-fit request was queued.
Global tbcEverythingAdjustRequestedTick                    := 0
; Source typing tick associated with the current Everything auto-fit request so
; KeyTrack queues at most one deferred send per physical keypress burst update.
Global tbcEverythingAdjustSourceTick                       := 0
; Maximum lifetime for a deferred Everything Edit1 auto-fit request before it
; is dropped as stale rather than sent into a newer typing context.
Global k_tbcEverythingAdjustMaxAgeMs                       := 750
; Fallback retry delay used only when StopAutoFix, rather than insufficient
; physical idle time, temporarily prevents Everything's typing-quiet gate.
Global k_tbcEverythingAdjustRetryMs                        := 40
; Minimum physical-idle gap required before Everything Edit1 is allowed to
; receive the deferred Ctrl+NumpadAdd column auto-fit chord.
Global k_tbcEverythingAdjustTypingQuietMs                  := 180
; +----------------------------------------------------------------------------+
; | Explorer Column Auto-Fit Deferred Wheel State                              |
; | Tracks quiet-time gating, supersession tokens, and short-lived target      |
; | caches for the deferred Explorer/file-dialog Ctrl+NumpadAdd send path.     |
; +----------------------------------------------------------------------------+
; Window class for the most recent Explorer/file-dialog wheel target so the
; deferred adjust step can confirm the queued request still points at the same shell UI.
Global tbcAdjustColumnsClass                               := ""
; Control under the mouse when the wheel event was queued; used as a hint before
; resolving the final DirectUI/ListView target at send time.
Global tbcAdjustColumnsCtrl                                := ""
; Top-level Explorer or #32770 dialog HWND that should receive the deferred
; Ctrl+NumpadAdd once scrolling has gone quiet.
Global tbcAdjustColumnsHwnd                                := 0
; Tick count of the most recent qualifying wheel event so WheelSendCtrlAdd can defer
; work until the user pauses scrolling and cancel if wheel activity resumes.
Global tbcAdjustColumnsLastWheelTick                       := 0
; Minimum quiet period after the last wheel event before attempting Explorer
; column auto-fit; this avoids interrupting fast continuous scrolling.
Global k_tbcAdjustColumnsQuietMs                           := 240
; Stronger quiet period for #32770 file dialogs, where DirectUI scroll activity and
; deferred Ctrl+NumpadAdd sends are more likely to overlap visibly.
Global k_tbcAdjustColumnsDialogQuietMs                     := 240
; Monotonic request token incremented on each qualifying wheel event so older
; deferred timers can detect they were superseded and exit without sending.
Global tbcAdjustColumnsRequestId                           := 0
; Brief final hold just before injecting Ctrl+NumpadAdd so a last-moment wheel event
; can update the tbc request state and cause the send to abort cleanly.
Global k_tbcAdjustColumnsSendGuardMs                       := 20
; Keep wheel suppression active briefly after Ctrl+NumpadAdd and immediate Ctrl
; synchronization so delayed physical wheel input cannot escape as Ctrl+Wheel.
Global k_tbcAdjustColumnsPostSendWheelGuardMs              := 20
; Cached final Explorer target ClassNN for the most recent wheel-adjust window so
; repeated pause/resume cycles can skip DirectUI/ListView rediscovery work.
Global c_tbcAdjustColumnsTargetCtrl                        := ""
; Top-level window HWND that owns the cached Explorer target ClassNN; the cache is
; only valid when a later wheel-adjust request points at this same shell window.
Global c_tbcAdjustColumnsTargetHwnd                        := 0
; Tick count when the cached Explorer target was last confirmed, limiting reuse to
; a short burst where the folder view structure is unlikely to have changed.
Global c_tbcAdjustColumnsTargetTick                        := 0
; Maximum age for the cached Explorer target before WheelSendCtrlAdd falls back to
; full target resolution to avoid using a stale DirectUI/ListView guess.
Global k_tbcAdjustColumnsTargetTtlMs                       := 350
; +----------------------------------------------------------------------------+
; Deferred typing correction state so punctuation and capitalization rewrites can
; happen just after the live keypress cycle settles instead of on the triggering
; key event itself.
; Slash uses this slot for deferred "/ " rewrites and for slash+Enter in
; non-classic editors. Classic Edit/RichEdit slash+Enter is handled inline by
; the custom $Enter hotkey instead of through this timer.
; +----------------------------------------------------------------------------+
Global tbcFixSlashAction                                   := ""
; Focused control name captured when the "/ " fix is queued so the timer can
; cancel instead of rewriting text after focus moves to another control.
Global tbcFixSlashCtrl                                     := ""
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
Global tbcHotyCtrl                                         := ""
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
; | Post-Activation Explorer Click Recovery                                    |
; | Captures the first click into an inactive Explorer/file-dialog window so a |
; | short timer can re-check that now-active shell target and recover the      |
; | expected Ctrl+NumpadAdd behavior without slowing the activation click path. |
; +----------------------------------------------------------------------------+
; Top-level window HWND that received the activation click. The timer requires
; this same window to become active before attempting any delayed shell action.
Global postActivationLButtonHwnd                           := 0
; Header action identified at mouse-down so the deferred activation path can
; reuse the completed click's classification without another UIA lookup.
Global postActivationLButtonHeaderKind                     := ""
; Directory reported when the activation click began. Deferred tree/header
; navigation must advance beyond this value before columns are adjusted.
Global postActivationLButtonInitialPath                    := ""
; ClassNN under the pointer when the activation click happened, used to limit
; the recovery path to shell headers and shell-view controls only.
Global postActivationLButtonCtrl                           := ""
; Screen X coordinate of the activation click so the timer can re-run title-bar
; and blank-space checks against the original click location.
Global postActivationLButtonX                              := 0
; Screen Y coordinate of the activation click so the deferred recovery inspects
; the same area the user originally clicked.
Global postActivationLButtonY                              := 0
; Monotonic token incremented for each pending activation click so an older timer
; can detect it was superseded by a newer click and exit safely.
Global postActivationLButtonId                             := 0
; Deadline for waiting non-blockingly until the clicked window is active and
; LButton has been released.
Global postActivationLButtonDeadlineTick                   := 0
; Initial delay that gives Windows time to begin activation/focus transfer.
Global k_postActivationLButtonDelayMs                      := 35
; Retry interval while activation or physical mouse release is still pending.
Global k_postActivationLButtonPollMs                       := 15
; Maximum lifetime of one deferred inactive-window click snapshot.
Global k_postActivationLButtonTimeoutMs                    := 1000
; +----------------------------------------------------------------------------+
; | Explorer CtrlAdd Request State                                             |
; | Coordinates guarded header attempts and timer-verified readiness sends    |
; | before delegating each column adjustment to SendCtrlAdd().                 |
; +----------------------------------------------------------------------------+
; True only for header-button requests. These requests may make a guarded send
; before UIA and one final guarded send when UIA cannot prove readiness.
Global explorerCtrlAddRequestAllowBestEffortSend           := False
; True only for confirmed #32770 activation requests. If every folder-identity
; backend returns empty, Details mode plus visible UIA content may authorize alignment.
Global explorerCtrlAddRequestAllowPathlessContentReady     := False
; True only for confirmed #32770 header navigation. An unavailable post-click
; path may use guarded early, verified, and final alignment attempts.
Global explorerCtrlAddRequestAllowUnresolvedPathFallback   := False
; Class of the Explorer or file-dialog window that owns the pending request.
Global explorerCtrlAddRequestClass                         := ""
; Latest tick at which the pending request may call SendCtrlAdd().
Global explorerCtrlAddRequestDeadlineTick                  := 0
; Earliest tick when a startup or Refresh Details/content probe may begin.
Global explorerCtrlAddRequestEarliestContentProbeTick      := 0
; Shorter directory-path polling interval used during every changed-path
; request's bounded fast-start window.
Global explorerCtrlAddRequestFastPathPollIntervalMs        := 0
; Tick when the current changed-path request's fast polling window ends.
Global explorerCtrlAddRequestFastPathPollUntilTick         := 0
; Top-level Explorer or file-dialog HWND that owns the pending request.
Global explorerCtrlAddRequestHwnd                          := 0
; True until a Refresh request makes its early best-effort alignment attempt.
; The request remains active afterward for the verified Details/content attempt.
Global explorerCtrlAddRequestImmediateSendPending          := False
; Monotonic token incremented for every request so an earlier timer
; callback exits when a newer navigation request supersedes it.
Global explorerCtrlAddRequestId                            := 0
; Directory reported before a path-changing navigation click. The timer requires
; GetExplorerPath() to return a different nonempty directory before sampling UIA.
Global explorerCtrlAddRequestInitialPath                   := ""
; Directory source that most recently succeeded for this request. A #32770 timer
; retries that source first instead of repeating a known-failing native/message probe.
Global explorerCtrlAddRequestLocationResolver              := ""
; True after GetExplorerPath() confirms that the pending path-changing request
; reached a different directory from explorerCtrlAddRequestInitialPath.
Global explorerCtrlAddRequestPathChangeConfirmed           := False
; True after a permitted #32770 activation could not obtain a path and switched
; to its bounded Details-mode plus visible-content readiness proof.
Global explorerCtrlAddRequestPathlessContentFallbackActive := False
; True until a path-changing header request makes its one pre-UIA alignment.
; UIA still runs afterward so a verified send can correct a rebuilt file view.
Global explorerCtrlAddRequestPreProbeSendPending           := False
; Directory returned by the preceding startup-path sample.
Global explorerCtrlAddRequestPreviousPath                  := ""
; Whether this request must prove a directory change before adjusting columns.
; Refresh requests leave this false because Refresh keeps the same directory.
Global explorerCtrlAddRequestRequirePathChange             := False
; Whether this request must observe the same nonempty directory twice before
; authorizing its Details/content result. Startup Explorer/file-dialog requests
; use this condition.
Global explorerCtrlAddRequestRequireStablePath             := False
; False only for header-navigation requests, whose completed column adjustment
; must not restore a previously focused SysTreeView32 control.
Global explorerCtrlAddRequestRestoreTreeFocus              := True
; Tick when the current request was published, used only to report elapsed
; request timing in the buffered Explorer CtrlAdd trace.
Global explorerCtrlAddRequestStartTick                     := 0
; Focused source control captured for a tree click; SendCtrlAdd restores it
; after adjusting the Details columns when it is still appropriate.
Global explorerCtrlAddRequestSourceCtrl                    := ""
; True after a startup request observes the same nonempty directory twice.
Global explorerCtrlAddRequestStablePathConfirmed           := False
; Number of consecutive startup samples returning the same nonempty directory.
Global explorerCtrlAddRequestStablePathHitCount            := 0
; Buffered Explorer CtrlAdd trace text. Terminal outcomes flush this buffer so
; ordinary timer probes do not add a disk write to every readiness check.
Global explorerCtrlAddTraceBuffer                          := ""
; Fast directory-change polling used by every changed-path navigation request.
Global k_explorerCtrlAddFastPathPollMs                     := 15
; After this bounded fast window, directory-change polling uses
; k_explorerCtrlAddPollMs.
Global k_explorerCtrlAddFastPathWindowMs                   := 300
; Minimum non-blocking settle before a new Explorer or newly tracked file-dialog
; activation may sample its destination path and file-view readiness.
Global k_newExplorerCtrlAddMinimumWaitMs                   := 300
; Maximum non-blocking wait for a startup request to expose a stable path.
Global k_newExplorerCtrlAddTimeoutMs                       := 5000
; Timer interval for non-blocking Details/content readiness probes.
Global k_explorerCtrlAddPollMs                             := 50
; Shared UIA transaction budget for each Details/content readiness probe.
Global k_explorerCtrlAddPollUIATimeoutMs                   := 150
; Maximum wait for Details mode and UIA item/empty-result evidence after path
; readiness or an applicable minimum settling delay.
Global k_explorerCtrlAddTimeoutMs                          := 1200
; Maximum buffered trace characters before a safety flush. Normal requests
; flush at their terminal outcome, keeping file I/O out of readiness timing.
Global k_explorerCtrlAddTraceBufferChars                   := 65536
; Enables the detailed Explorer/file-dialog CtrlAdd timing trace.
Global k_explorerCtrlAddTraceEnabled                       := True
; Persistent trace location beside this script so it is easy to find.
Global k_explorerCtrlAddTraceFile                          := A_ScriptDir . "\AutoCorrect_ExplorerCtrlAddTrace.log"
; Minimum non-blocking settle after Refresh before probing the file view.
Global k_explorerCtrlAddRefreshMinimumWaitMs               := 300
; Shared UIA evidence accepted as proof that an Items View exposes either an
; item or a recognized empty-result message.
Global k_explorerItemsViewContentEvidenceCondition         := "ControlType=ListItem OR Name=This folder is empty. OR Name=No items match your search."
; +----------------------------------------------------------------------------+
; | Runtime Context And Click/Drag Scratch State                               |
; | Stores the current desktop, monitor, Explorer path, click target, and      |
; | in-progress drag metadata shared across mouse and window-management flows. |
; +----------------------------------------------------------------------------+
; Platform/runtime flags cached once for OS-specific behavior.
Global k_isWin11                                           := DetectWin11()
; True when Explorer is using the modern Windows 11 implementation.
Global k_isModernExplorerInReg                             := IsExplorerModern()
; System double-click interval cached once for click timing logic.
Global k_DoubleClickTime                                   := DllCall("GetDoubleClickTime")
; Half-double-click interval used as the script's single-click timing threshold.
Global k_SingleClickTime                                   := floor(DllCall("GetDoubleClickTime") * 0.5)
; Lowercase alphabet characters used by text and hotstring helpers.
Global k_keys                                              := "abcdefghijklmnopqrstuvwxyz"
; Selects whether native SysListView32 columns fit their item content or header
; text while the direct-message auto-fit experiment is enabled.
Global k_nativeSysListViewColumnAutoFitMode                := "header_no_fill"
; Decimal digit characters used by text and hotstring helpers.
Global k_numbers                                           := "0123456789"
; Maximum time SendCtrlAdd() waits for MouseGetPos to identify a specific child
; when Explorer initially reports the generic ShellTabWindowClass1 host.
Global k_sendCtrlAddShellTabProbeTimeoutMs                 := 50
; Enables direct LVM_SETCOLUMNWIDTH auto-fit for native SysListView32 targets.
; False restores the existing focus plus Ctrl+NumpadAdd behavior unchanged.
Global k_useNativeSysListViewColumnAutoFit                 := True
; +----------------------------------------------------------------------------+
; | Monitor/Desktop/Context State                                              |
; | Shared monitor, desktop, Explorer-path, and click-position context reused  |
; | across window activation, taskbar, and shell-navigation flows.             |
; +----------------------------------------------------------------------------+
; Monitor index currently targeted by monitor-aware window flows.
Global currentMon                                          := 0
; Previously targeted monitor index for cross-monitor transitions.
Global previousMon                                         := 0
; Virtual desktop index being targeted by desktop-switching logic.
Global targetDesktop                                       := 0
; Current Explorer path snapshot used by folder-aware actions.
Global currentPath                                         := ""
; Previous Explorer path snapshot used for path-change comparisons.
Global prevPath                                            := ""
; Cached taskbar height used by taskbar-aware positioning logic.
Global TaskBarHeight                                       := 0
; Screen X coordinate of the last taskbar/tray click.
Global trayClickPosX                                       := 0
; Screen Y coordinate of the last taskbar/tray click.
Global trayClickPosY                                       := 0
; Cached Win+Ctrl+D helper state used by desktop creation logic.
Global _winCtrlD                                           := ""
; +----------------------------------------------------------------------------+
; | Window/UI State                                                            |
; | Shared HWNDs and retained popup content reused across activation and cycle |
; | UI updates.                                                                |
; +----------------------------------------------------------------------------+
; HWND of the last active window tracked by activation logic.
Global lastActWinID                                        :=
; HWND whose LButton-driven column alignment is blocked after a SysHeader drag.
; A qualifying double-click in that window's SysListView clears the block.
Global disableSendCtrlHwnd                                 := ""
; HWND of the retained WindowTitle popup GUI.
Global WindowTitleID                                       :=
; Current icon source spec shown in the WindowTitle popup.
Global WindowTitleIcon                                     := ""
; Current text shown in the WindowTitle popup.
Global WindowTitleText                                     := ""
; True once the retained WindowTitle popup GUI has been created.
Global WindowTitleGuiReady                                 := False
; +----------------------------------------------------------------------------+
; | Input/Gesture State                                                        |
; | Shared typing, click, and drag flags that let separate hotkeys and mouse   |
; | handlers coordinate one in-progress gesture.                               |
; +----------------------------------------------------------------------------+
; Master toggle that lets custom click logic emit double-clicks.
Global allowDoubleClicks                                   := True
; True while the custom live window-drag flow is in progress.
Global DraggingWindow                                      := False
; Name of the most recently triggered hotkey for repeat-sensitive logic.
Global lastHotkeyTyped                                     := ""
; True when MButton should behave like Enter for the current gesture.
Global MbuttonIsEnter                                      := False
; Temporarily suppresses native RButton handling during MButton drag flows.
Global suspendRightButtonForMButtonDrag                    := False
; Tick count of the most recent hotkey-triggered send used by typing heuristics.
Global TimeOfLastHotkeyTyped                               := A_TickCount
; +----------------------------------------------------------------------------+
; | Live-Resize And Cursor-Clamp State                                         |
; | Shared per-drag state for synced left-button resize and the temporary      |
; | bottom-taskbar window-edge boundary enforced through cursor confinement.  |
; +----------------------------------------------------------------------------+
; True while this script owns a bottom-edge native-resize ClipCursor boundary.
Global bottomResizeCursorClampActive                       := False
; Top-level window handle whose native bottom-edge resize owns the cursor clamp.
Global bottomResizeCursorClampHwnd                         := 0
; True while the synced left-button resize workflow is armed and running.
Global lButtonResizeSyncActive                             := False
; HWND of the actively dragged window in the synced resize workflow.
Global lButtonResizeSyncDraggedHwnd                        := 0
; Whether the dragged window started the resize already topmost.
Global lButtonResizeSyncDraggedStartedAlwaysOnTop          := False
; Whether the dragged window has been made transparent during synced resize.
Global lButtonResizeSyncDraggedTransparent                 := False
; Monotonic suffix used to generate unique resize-ghost GUI names.
Global lButtonResizeGhostSeq                               := 0
; Hit-test code for the edge or corner currently being dragged.
Global lButtonResizeSyncHit                                := 0
; Last tracked dragged-window height during synced resize.
Global lButtonResizeSyncLastDraggedH                       := ""
; Last tracked dragged-window width during synced resize.
Global lButtonResizeSyncLastDraggedW                       := ""
; Last tracked dragged-window X position during synced resize.
Global lButtonResizeSyncLastDraggedX                       := ""
; Last tracked dragged-window Y position during synced resize.
Global lButtonResizeSyncLastDraggedY                       := ""
; Active follower-window records participating in synced resize.
Global lButtonResizeSyncPartners                           := []
; Original AlwaysOnTop states captured for synced-resize cleanup.
Global lButtonResizeSyncTopmostStates                      := {}

; +----------------------------------------------------------------------------+
; | Hook, UIA, And Input-Guard State                                           |
; | Owns the foreground-window hook, UIA interface, low-level hook handles,    |
; | and key/mouse blocking state used to keep synthetic input predictable.      |
; +----------------------------------------------------------------------------+
Global hActWin                                             := DllCall("user32\SetWinEventHook", UInt,0x3, UInt,0x3, Ptr,0, Ptr,RegisterCallback("OnWinActiveChange"), UInt,0, UInt,0, UInt,0, Ptr)
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
; +----------------------------------------------------------------------------+
; | Window Snap And Drag Configuration                                         |
; | These are the coarse behavior knobs for snapping, monitor work-area rules, |
; | classes that should never be drag-managed, and overlay dimming strength.   |
; +----------------------------------------------------------------------------+
Global k_UseWorkArea                                       := true   ; true = monitor work area (ignores taskbar). false = full monitor.
Global k_SnapRange                                         := 20     ; px: distance from edge to begin snapping
Global k_BreakAway                                         := 80     ; px: while snapped, drag this far further TOWARD the outside to push past edge
Global k_ReleaseAway                                       := 24     ; px: while snapped, drag this far AWAY from the edge to release the snap

; Skip dragging these classes (taskbar/desktop)
Global k_skipClasses                                       := { "Shell_TrayWnd":1, "Shell_SecondaryTrayWnd":1, "Progman":1, "WorkerW":1 }

Global k_Opacity                                           := 220     ; 255=opaque black; try 200 to "dim" instead of fully black

; +----------------------------------------------------------------------------+
; | Right-Button State Machine                                                 |
; | Remembers whether the script has started, consumed, or should suppress the |
; | native right-click flow so custom RButton chords do not leak shell input.  |
; +----------------------------------------------------------------------------+
; Right-button state machine:
; - held/nativeDown track whether we have started a real OS-level right-click yet.
; - comboUsed suppresses the fallback Click, Right path when the hold was consumed by a combo.
; - suppressMenuOnUp dismisses the shell context menu after a successful RButton+wheel action.
; - taskbarPassthrough keeps the entire custom RButton state machine out of taskbar
;   and desktop-shell clicks so those surfaces stay fully native.
Global rightButtonHeld                                     := false
Global rightButtonComboUsed                                := false
Global rightButtonNativeDown                               := false
Global rightButtonSuppressMenuOnUp                         := false
Global rightButtonTaskbarPassthrough                       := false
Global swallowNextRButtonUpFromMButtonDrag                 := false

; Used by explicit LButton+RButton chords that should consume the normal
; right-click flow, such as the title-bar toggle and clear-edit gesture.
Global suppressRightButtonLogic                            := false

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

SysGet, MonNum, MonitorPrimary
SysGet, MonitorWorkArea, MonitorWorkArea, %MonNum%
SysGet, MonCount, MonitorCount

leftArrow  := Chr(0x2190)  ; ←
rightArrow := Chr(0x2192)  ; →
upArrow    := Chr(0x2191)  ; ↑
downArrow  := Chr(0x2193)  ; ↓

GetDesktopEdges(ByRef leftEdge, ByRef topEdge, ByRef rightEdge, ByRef bottomEdge) {
    SysGet, monCount, MonitorCount

    leftEdge  := ""
    topEdge   := ""
    rightEdge := ""
    bottomEdge:= ""

    Loop, %monCount% {
        ; "mon" is the prefix; SysGet will set monLeft, monTop, monRight, monBottom
        SysGet, mon, Monitor, %A_Index%

        if (A_Index = 1) {
            leftEdge   := monLeft
            topEdge    := monTop
            rightEdge  := monRight
            bottomEdge := monBottom
        } else {
            if (monLeft < leftEdge)
                leftEdge := monLeft
            if (monTop < topEdge)
                topEdge := monTop
            if (monRight > rightEdge)
                rightEdge := monRight
            if (monBottom > bottomEdge)
                bottomEdge := monBottom
        }
    }
}

totalVirtualDesktops := getTotalDesktops()
GetDesktopEdges(G_DisplayLeftEdge, G_DisplayTopEdge, G_DisplayRightEdge, G_DisplayBottomEdge)

line1  := "Total Number of Monitors is " MonCount " with Primary being " MonNum
line1a := "Desktop edges: " leftArrow . "(" . G_DisplayLeftEdge . "," . G_DisplayRightEdge . ")" . rightArrow
line1b := "Desktop edges: " upArrow . "(" . G_DisplayTopEdge . "," . G_DisplayBottomEdge . ")" . downArrow
line2  := "Current Mon is     " GetCurrentMonitorIndex()
line3  := "Win11 is           " k_isWin11
line4  := "Modern Explorer is " k_isModernExplorerInReg
line5  := "Total # of Desktops " totalVirtualDesktops
Tooltip, % line1 "`n" line1a "`n" line1b "`n" line2 "`n" line3 "`n" line4 "`n" line5
Sleep 5000
Tooltip
; MsgBox % "A_PtrSize=" A_PtrSize "`n(dll must match: 8=64-bit, 4=32-bit)"

Gui, ShadowFrFull: New
Gui, ShadowFrFull: +HwndIGUIF
Gui, ShadowFrFull: +AlwaysOnTop +ToolWindow -DPIScale +E0x08000000 +E0x20 -Caption +Owner +LastFound
Gui, ShadowFrFull: Color, FF00FF
FrameShadow(IGUIF)

Gui, ShadowFrFull2: New
Gui, ShadowFrFull2: +HwndIGUIF2
Gui, ShadowFrFull2: +AlwaysOnTop +ToolWindow -DPIScale +E0x08000000 +E0x20 -Caption +Owner +LastFound
Gui, ShadowFrFull2: Color, FF00FF
FrameShadow(IGUIF2)

Gui, GUIHighlighter: New
Gui, GUIHighlighter: +HwndHighlighter
Gui, GUIHighlighter: +AlwaysOnTop +Toolwindow -Caption +Owner +Lastfound
Gui, GUIHighlighter: Color, %k_border_color%

; --- Overlay GUI init (create once at startup) ---
;
; Overlay lifecycle for !Tab / !`:
;   Script startup
;      |
;      +--> Gui, Overlay:New
;      |
;      +--> Overlay_Prewarm()
;            |
;            +--> Overlay_SetAlpha(0)
;            +--> Gui, Overlay:Show 1x1 transparent
;
;   First real preview during !Tab / !`
;      |
;      +--> Overlay_ShowHole(...)
;            |
;            +--> Overlay_CancelFade()
;            +--> Gui, Overlay:Show on target monitor
;            +--> Overlay_SetHoleRegion_WorkArea(...)
;            +--> Overlay_FadeTo(..., allowModifierAbort := True)
;
;   Repeated cycling while Alt remains held
;      |
;      +--> Overlay_MoveHole(...)
;            |
;            +--> reuse the same overlay window
;            +--> update the hole region in place
;
;   Alt released / cycle ends
;      |
;      +--> Overlay_Hide(...)
;            |
;            +--> Overlay_FadeTo(..., allowModifierAbort := False)
;            +--> reset full region
;            +--> Gui, Overlay:Hide
;
;   Fresh !Tab / !` during hide fade
;      |
;      +--> Overlay_ShowHole(...)
;            |
;            +--> Overlay_CancelFade() stops the old hide fade
;            +--> new preview takes over immediately
global overlayFadeToken    := 0
global overlayAlphaCurrent := 0
global overlayHwnd         := 0
global overlayKeyColor     := "FF00FF"      ; RGB hex string
global overlayIsReady      := False

Gui, Overlay:New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +HwndoverlayHwnd
Gui, Overlay:Color, 000000

; Solid filled rectangle in key color
Gui, Overlay:Add, Text, x0 y0 w1 h1 Background%overlayKeyColor%

Overlay_Prewarm()
overlayIsReady := True

WinGet, allwindows, List
Loop, %allwindows%
{
    winID := allWindows%A_Index%
    WinGet, minState, MinMax, ahk_id %winID%

    If (minState > -1 && IsAltTabWindow(winID)) {
        prevActiveWindows.push(winID)
    }
}

WinFindExpr =
(
    #NoEnv
    #NoTrayIcon
    #KeyHistory 0
    #SingleInstance, Force
    ; #Persistent ; already the default
    #WinActivateForce
    SetBatchLines -1
    ListLines Off
    ; DetectHiddenWindows, Off ; already the default

    WinWait, ahk_class #32768,, 3

    If ErrorLevel
        ExitApp

    SendInput, {DOWN}
    ; https://www.autohotkey.com/board/topic/11157-popup-menu-sometimes-doesnt-have-focus/page-2
    ; MouseMove, %x%, %y%

    ; Input, SingleKey, L1, {Lbutton}{ESC}{ENTER}, *
    Return

    $~ENTER::
        ExitApp
    Return

    $~ESC::
        ExitApp
    Return

    $~*LBUTTON::
        ExitApp
    Return

    $SPACE::
        SendInput, {DOWN}
    Return
)

TooltipExpr =
(
    #NoEnv
    #NoTrayIcon
    #KeyHistory 0
    #SingleInstance, Off
    ; #Persistent ; already the default
    SetBatchLines -1
    ListLines Off

    tooltip, Navigating Up...
    sleep, 1000
    tooltip
    ExitApp
)

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

Send #^{Left}
sleep, 50
Send #^{Left}
sleep, 50
Send #^{Left}
sleep, 50
Send #^{Left}
sleep, 50

WinGetPos, , , , TaskBarHeight, ahk_class Shell_TrayWnd

If (MonCount > 1) {
    currentMon := MWAGetMonitorMouseIsIn()
    previousMon := currentMon
}


hHookKbd   := 1
hHookMouse := 1
; Get module handle for this process (needed by SetWindowsHookEx for LL hooks)
hMod := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")

; Low-level keyboard hook: WH_KEYBOARD_LL = 13
kbdCallback := RegisterCallback("LL_KeyboardHook", "Fast")
hHookKbd   := DllCall("SetWindowsHookEx"
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

vdaInitd := InitVDA()
comInitd := InitCOM_STA()
accInitd := Acc_Init()

10_Minutes := 60000*10
SetTimer MouseTrack, 20
SetTimer KeyTrack, 25
SetTimer MasterTimer, %10_Minutes%
_RequestTypingAutoFixPrewarm()

Return

DisableTimers:
    SetTimer, KeyTrack,   Off
    SetTimer, MouseTrack, Off
Return

EnableTimers:
    SetTimer, KeyTrack,   On
    SetTimer, MouseTrack, On
Return

WatchBottomResizeCursorClamp:
    if (   !bottomResizeCursorClampActive
        || !GetKeyState("LButton", "P")
        || !WinExist("ahk_id " . bottomResizeCursorClampHwnd))
        EndBottomResizeCursorClamp()
Return

WatchLButtonResizeSync:
    if (!lButtonResizeSyncActive) {
        EndLButtonResizeSync()
        SetTimer, WatchLButtonResizeSync, Off
        GoSub, EnableTimers
        return
    }

    if !GetKeyState("LButton", "P") {
        _FinalizeLButtonResizeSync()
        EndLButtonResizeSync()
        SetTimer, WatchLButtonResizeSync, Off
        GoSub, EnableTimers
        return
    }

    UpdateLButtonResizeSync()
Return
; ==========================================================================================================================================
; -----------------------------------------------          START OF APPLICATION           --------------------------------------------------
; ==========================================================================================================================================
MasterTimer:
    KillOtherAutoHotkeyU64_NotThisScript(true)
Return

HandleTrayIconMessage(wParam, lParam, msg, hwnd) {
    static WM_RBUTTONDOWN := 0x204
    static WM_RBUTTONUP   := 0x205

    ; 0x404 is the script's tray-icon callback message. Windows calls us here
    ; whenever the user interacts with the tray icon, and lParam tells us which
    ; mouse message triggered the callback.
    if (lParam = WM_RBUTTONDOWN)
        ; Swallow the native tray right-button-down because we want to fully own
        ; the menu behavior and position it ourselves instead of using the stock
        ; AutoHotkey tray popup location.
        return 1

    if (lParam = WM_RBUTTONUP) {
        ; Show the tray menu on button-up, which matches normal shell behavior.
        ; At this point we capture the click position and queue the popup for the
        ; next tick so the shell callback can unwind before TrackPopupMenuEx runs.
        CoordMode, Mouse, Screen
        MouseGetPos, trayClickPosX, trayClickPosY
        SetTimer, __DeferredShowTrayMenuAtTaskbar, -1
        return 1
    }
}

__DeferredShowTrayMenuAtTaskbar:
    ; Queue the popup outside the tray callback itself so the shell can finish
    ; delivering the click message before TrackPopupMenuEx starts its modal loop.
    ShowTrayMenuAtTaskbar("TrayPopup", trayClickPosX, trayClickPosY)
Return

; Return the primary or secondary taskbar containing the original click point.
; WindowFromPoint preserves the correct taskbar even if the mouse moves before
; the deferred popup runs; the primary taskbar is the safe fallback.
FindTaskbarAtPoint(clickX, clickY) {
    pointValue  := (clickX & 0xFFFFFFFF) | ((clickY & 0xFFFFFFFF) << 32)
    pointHwnd   := DllCall("user32\WindowFromPoint", "Int64", pointValue, "Ptr")
    taskbarHwnd := DllCall("user32\GetAncestor", "Ptr", pointHwnd, "UInt", 2, "Ptr")

    if (taskbarHwnd) {
        WinGetClass, taskbarClass, ahk_id %taskbarHwnd%
        if (taskbarClass = "Shell_TrayWnd" || taskbarClass = "Shell_SecondaryTrayWnd")
            return taskbarHwnd
    }

    return WinExist("ahk_class Shell_TrayWnd")
}

; Show any named AHK popup menu against the inward-facing edge of the taskbar
; containing the click. Horizontal taskbars use xOffset to align the popup with
; the tray icon; vertical taskbars anchor the popup at the click's Y coordinate.
ShowTrayMenuAtTaskbar(menuName, clickX, clickY, xOffset := 12) {
    static TPM_BOTTOMALIGN := 0x20
    static TPM_RIGHTALIGN  := 0x08

    taskbarHwnd := FindTaskbarAtPoint(clickX, clickY)
    if (!taskbarHwnd) {
        return ShowMenuX(menuName, clickX, clickY, TPM_BOTTOMALIGN)
    }

    WinGetPos, taskbarX, taskbarY, taskbarWidth, taskbarHeight, ahk_id %taskbarHwnd%
    if (taskbarWidth <= 0 || taskbarHeight <= 0) {
        return ShowMenuX(menuName, clickX, clickY, TPM_BOTTOMALIGN)
    }

    GetMonitorRectForMouse(clickX, clickY, False
        , monitorLeft, monitorTop, monitorRight, monitorBottom)

    if (taskbarWidth >= taskbarHeight) {
        menuX := clickX - xOffset
        if ((taskbarY + taskbarHeight / 2) < (monitorTop + monitorBottom) / 2) {
            ; Top taskbar: align the menu's top with the taskbar's bottom.
            menuY := taskbarY + taskbarHeight
            menuFlags := 0
        } else {
            ; Bottom taskbar: align the menu's bottom with the taskbar's top.
            menuY := taskbarY
            menuFlags := TPM_BOTTOMALIGN
        }
    } else {
        menuY := clickY
        if ((taskbarX + taskbarWidth / 2) < (monitorLeft + monitorRight) / 2) {
            ; Left taskbar: align the menu's left with the taskbar's right.
            menuX := taskbarX + taskbarWidth
            menuFlags := 0
        } else {
            ; Right taskbar: align the menu's right with the taskbar's left.
            menuX := taskbarX
            menuFlags := TPM_RIGHTALIGN
        }
    }

    return ShowMenuX(menuName, menuX, menuY, menuFlags)
}

; Helper to resolve exports
_gp(name)
{
    global hVirtualDesktopAccessor
    ; NO InitVDA() here.
    return DllCall("GetProcAddress", "Ptr", hVirtualDesktopAccessor, "AStr", name, "Ptr")
}

InitVDA()
{
    global hVirtualDesktopAccessor, k_dllPath
    global GetDesktopCountProc, GoToDesktopNumberProc, GetCurrentDesktopNumberProc
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
    GoToDesktopNumberProc               := _gp("GoToDesktopNumber")
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
      && GoToDesktopNumberProc
      && GetCurrentDesktopNumberProc
      && IsWindowOnCurrentVirtualDesktopProc
      && IsWindowOnDesktopNumberProc
      && MoveWindowToDesktopNumberProc
      && IsPinnedWindowProc)
    {
        MsgBox % "InitVDA: missing required export(s).`n"
             . "Check DLL path/bitness/version.`n"
             . "A_PtrSize=" A_PtrSize
        return false
    }

    return true
}

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
    lastHotkeyTyped       := A_ThisHotkey
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
        CaptureActiveFocusSnapshot(tbcHotyHwnd, tbcHotyCtrl, tbcHotyCtrlHwnd, tbcHotyCtrlClass)
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
    global tbcFixSlashAction
    global tbcFixSlashCtrl
    global tbcFixSlashCtrlClass
    global tbcFixSlashCtrlHwnd
    global tbcFixSlashHwnd
    global tbcFixSlashId
    global tbcFixSlashRequestedTick
    global typingFixSeq

    CancelTbcTypingFixes(False, False)
    typingFixSeq += 1
    tbcFixSlashAction     := action
    CaptureActiveFocusSnapshot(tbcFixSlashHwnd, tbcFixSlashCtrl, tbcFixSlashCtrlHwnd, tbcFixSlashCtrlClass)
    tbcFixSlashId         := typingFixSeq
    tbcFixSlashRequestedTick := A_TickCount
    SetTimer, FlushTbcFixSlash, -40
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

    targetHwnd := WinExist("A")
    if (!targetHwnd)
        return False

    ControlGetFocus, targetCtrlNN, ahk_id %targetHwnd%
    startTick := A_TickCount

    while (((GetKeyState("Enter", "P") || A_TimeIdlePhysical < settleIdleMs) || StopAutoFix)
        && (A_TickCount - startTick) < settleMaxMs)
        Sleep, %settlePollMs%

    if (StopAutoFix)
        return False

    if (WinExist("A") != targetHwnd)
        return False

    if (targetCtrlNN != "") {
        ControlGetFocus, currentCtrlNN, ahk_id %targetHwnd%
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
    global k_keys
    global StopAutoFix
    global X_PriorPriorHotKey

    return (disableEnter
         && !IsGoogleDocWindow()
         && !StopAutoFix
         && InStr(k_keys, X_PriorPriorHotKey, False)
         && A_PriorHotKey == "~/"
         && A_ThisHotkey == "$Enter"
         && A_TimeSincePriorHotkey < 999)
}

FixSlash:
    If !IsGoogleDocWindow() && (!StopAutoFix && IsPriorHotKeyLetterKey()) && A_ThisHotkey == "~/"
        disableEnter := True
    Else If !IsGoogleDocWindow() && (!StopAutoFix && IsThisHotKeyLetterKey())
        disableEnter := False
    ; tooltip, %disableEnter% - %X_PriorPriorHotKey% - %A_PriorHotKey% - %A_ThisHotkey%
    If      (disableEnter && !IsGoogleDocWindow() && (!StopAutoFix && InStr(k_keys, X_PriorPriorHotKey, False) && A_PriorHotKey == "~/" && A_ThisHotkey == "$~Space" && A_TimeSincePriorHotkey<999)) {
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
        else
        {
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
    global tbcFixSlashCtrl
    global tbcFixSlashCtrlClass
    global tbcFixSlashCtrlHwnd
    global tbcFixSlashHwnd
    global tbcFixSlashId
    global tbcFixSlashRequestedTick

    tbcFixSlashAction     := ""
    tbcFixSlashCtrl       := ""
    tbcFixSlashCtrlClass  := ""
    tbcFixSlashCtrlHwnd   := 0
    tbcFixSlashHwnd       := 0
    tbcFixSlashId         := 0
    tbcFixSlashRequestedTick := 0
}

; Clears the deferred capitalization rewrite slot without invalidating the shared
; sequence token, allowing the caller to cancel one slot or both explicitly.
_ClearTbcHotyState() {
    global tbcHotyCtrl
    global tbcHotyCtrlClass
    global tbcHotyCtrlHwnd
    global tbcHotyHwnd
    global tbcHotyId
    global tbcHotyRequestedTick
    global tbcHotyReplacement
    global tbcHotyTriggerChar

    tbcHotyCtrl        := ""
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
    CancelTbcTypingFixes(True, True)
    _ClearTbcEverythingEditAdjustState()
    _ClearTypingAutoFixEligibilityCache()
    _ClearTbcTypingAutoFixRefresh()
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
TryCaptureCompleteFocusSnapshot(activeHwnd, ByRef ctrlNN, ByRef ctrlHwnd, ByRef ctrlClass) {
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
    global tbcFixSlashCtrl
    global tbcFixSlashCtrlClass
    global tbcFixSlashCtrlHwnd
    global tbcFixSlashHwnd
    global tbcFixSlashId
    global tbcFixSlashRequestedTick

    if !_IsTbcTypingFixStillValid(tbcFixSlashId, tbcFixSlashHwnd, tbcFixSlashCtrl, tbcFixSlashRequestedTick)
        return False

    if (!tbcFixSlashCtrlHwnd && tbcFixSlashCtrlClass = "")
        return True

    if !TryCaptureCompleteFocusSnapshot(tbcFixSlashHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return False

    if (tbcFixSlashCtrl != "" && currentCtrlNN != tbcFixSlashCtrl)
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
    global tbcFixSlashCtrl
    global tbcFixSlashHwnd
    global StopAutoFix

    if (!tbcFixSlashHwnd || !WinActive("ahk_id " . tbcFixSlashHwnd))
        return False

    if (tbcFixSlashCtrl != "")
    {
        ControlGetFocus, currentCtrl, ahk_id %tbcFixSlashHwnd%
        if (currentCtrl != tbcFixSlashCtrl)
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
    global tbcHotyCtrl
    global tbcHotyCtrlClass
    global tbcHotyCtrlHwnd
    global tbcHotyHwnd
    global tbcHotyId
    global tbcHotyRequestedTick

    if !_IsTbcTypingFixStillValid(tbcHotyId, tbcHotyHwnd, tbcHotyCtrl, tbcHotyRequestedTick)
        return false

    if (!tbcHotyCtrlHwnd && tbcHotyCtrlClass = "")
        return true

    if !TryCaptureCompleteFocusSnapshot(tbcHotyHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return false

    if (tbcHotyCtrl != "" && currentCtrlNN != tbcHotyCtrl)
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
    global tbcFixSlashCtrl
    global tbcFixSlashCtrlClass
    global tbcFixSlashCtrlHwnd
    global tbcFixSlashHwnd

    if (!tbcFixSlashHwnd || !tbcFixSlashCtrlHwnd || tbcFixSlashCtrlClass = "")
        return False

    if !IsClassicEditControlClass(tbcFixSlashCtrlClass)
        return False

    if !TryCaptureCompleteFocusSnapshot(tbcFixSlashHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return False

    if (currentCtrlNN != tbcFixSlashCtrl || currentCtrlHwnd != tbcFixSlashCtrlHwnd || currentCtrlClass != tbcFixSlashCtrlClass)
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
    global tbcHotyCtrl
    global tbcHotyCtrlClass
    global tbcHotyCtrlHwnd
    global tbcHotyHwnd
    global tbcHotyReplacement
    global tbcHotyTriggerChar

    if (!tbcHotyHwnd || !tbcHotyCtrlHwnd || tbcHotyCtrlClass = "")
        return false

    if !IsClassicEditControlClass(tbcHotyCtrlClass)
        return false

    if !TryCaptureCompleteFocusSnapshot(tbcHotyHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return false

    if (currentCtrlNN != tbcHotyCtrl || currentCtrlHwnd != tbcHotyCtrlHwnd || currentCtrlClass != tbcHotyCtrlClass)
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

DoNothing:
    Return
; ==========================================================================================================================================
; ==========================================================================================================================================
WhichButton(vPosX, vPosY, hWnd) {

    errorFound := False
    vName := "",

    try {
        oAcc := Acc_ObjectFromPoint(vChildID)
        If oAcc
            vName := oAcc.accName(vChildID)
    }
    catch e {
        tooltip, error thrown
        errorFound := True
    }

    If (vName == "" || (!InStr(vName,"close",false) && !InStr(vName,"restore",false) && !InStr(vName,"maximize",false) && !InStr(vName,"minimize",false))) {
        SendMessage, 0x84, 0, (vPosX & 0xFFFF) | (vPosY & 0xFFFF)<<16,, ahk_id %hWnd%, , , , 500
        If (ErrorLevel == 8)
            vName := "minimize"
        Else If (ErrorLevel == 9)
            vName := "maximize"
        Else If (ErrorLevel == 20)
            vName := "close"
        ; msgbox, 1 - %vName%
    }

    isAltTab := JEE_WinHasAltTabIcon(hWnd)
    If (isAltTab && vName == "") { ; || (!InStr(vName,"close",false) && !InStr(vName,"restore",false) && !InStr(vName,"maximize",false) && !InStr(vName,"minimize",false)))) {
        wx := wy := ww := wh := 0
        SysGet, SM_CXBORDER, 5
        SysGet, SM_CYBORDER, 6
        SysGet, SM_CXFIXEDFRAME, 7
        SysGet, SM_CYFIXEDFRAME, 8
        SysGet, SM_CXMIN, 28
        SysGet, SM_CYMIN, 29
        SysGet, SM_CXSIZE, 30
        SysGet, SM_CYSIZE , 31
        SysGet, SM_CXSIZEFRAME, 32
        SysGet, SM_CYSIZEFRAME , 33

        WinGet, isMax, MinMax, ahk_id %WindowUnderMouseID%

        titlebarHeight := SM_CYMIN-SM_CYSIZEFRAME
        If (isMax == 1)
            titlebarHeight := SM_CYSIZE

        WinGetPosEx(hWnd, wx, wy, ww, wh)

        If      ((vPosY > wy) && (vPosY < (wy+titlebarHeight)) && (vPosX > (wx+ww-SM_CXBORDER-(45*3)) && (vPosX < (wx+ww-SM_CXBORDER-(45*2)))))
            vName := "minimize"
        Else If ((vPosY > wy) && (vPosY < (wy+titlebarHeight)) && (vPosX > (wx+ww-SM_CXBORDER-(45*2)) && (vPosX < (wx+ww-SM_CXBORDER-(45*1)))))
            vName := "maximize"
        Else If ((vPosY > wy) && (vPosY < (wy+titlebarHeight)) && (vPosX > (wx+ww-SM_CXBORDER-(45*1)) && (vPosX < (wx+ww-SM_CXBORDER-(45*0)))))
            vName := "close"
        ; msgbox, 2 - %vName% - %wx% %wy% %ww% %wh%
    }

    ; vValue := "", try vValue := oAcc.accValue(vChildID)
    oAcc := ""

    vOutput := ""
    ; vOutput := "role: " vRole "`r`n"
    ; If (vRoleText1 == vRoleText2)
        ; vOutput .= "role text: " vRoleText1 "`r`n"
    ; Else
    ; vOutput .= "role text (1): " vRoleText1 "`r`n" "role text (2): " vRoleText2 "`r`n"
    If !errorFound
        vOutput .= "name: " vName ; "`r`n"
    Else
        vOutput .= "error: " vName ; "`r`n"
    Return vOutput
}

DetectWin11() {
    ; Get version via WMI to capture the build number
    version := ""
    buildNumber := ""
    try {
        wmi := ComObjGet("winmgmts:\\.\root\cimv2")
        for os in wmi.ExecQuery("Select * from Win32_OperatingSystem")
        {
            version := os.Version  ; e.g., "10.0.22621"
            buildNumber := os.BuildNumber  ; e.g., "22621"
            break
        }
    } catch e {
        MsgBox, Failed to query OS version.`nError: %e%
        Return False
    }

    If (SubStr(version, 1, 4) = "10.0" && buildNumber >= 22000)
        Return True
    Else
        Return False
}

KillOtherAutoHotkeyU64_NotThisScript(terminateUnknownTitle := false) {
    ; Each running AHK script has a hidden main window of class "AutoHotkey".
    ; We enumerate those windows, filter to AutoHotkeyU64.exe, then compare the title to our script path.

    DetectHiddenWindows, On

    currentPid := A_Pid
    currentScript := A_ScriptFullPath
    killed := 0

    WinGet, hwndList, List, ahk_class AutoHotkey

    Loop, %hwndList%
    {
        hwnd := hwndList%A_Index%

        WinGet, pid, PID, ahk_id %hwnd%
        if (pid = currentPid) {
            continue
        }

        WinGet, procName, ProcessName, ahk_id %hwnd%
        if (procName != "AutoHotkeyU64.exe") {
            continue
        }

        WinGetTitle, title, ahk_id %hwnd%

        ; Most AHK instances include the script full path in the hidden window title.
        ; If we can't read a title, only terminate if terminateUnknownTitle := true.
        if (title != "") {
            if (InStr(title, currentScript)) {
                continue
            }
        }
        else {
            if (!terminateUnknownTitle) {
                continue
            }
        }

        Process, Close, %pid%
        if (!ErrorLevel) {
            killed++
        }
    }

    return killed
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
    SysGet, count, MonitorCount
    bestDist := 0x7FFFFFFF, found := false

    Loop, %count%
    {
        idx := A_Index
        ; Switch between full monitor bounds and the work area that excludes taskbars/docked bars.
        if (useWorkArea)
            SysGet, r, MonitorWorkArea, %idx%
        else
            SysGet, r, Monitor, %idx%

        ; Fast path: return immediately when the mouse is already inside this monitor rectangle.
        if (mx >= rLeft && mx < rRight && my >= rTop && my < rBottom) {
            L := rLeft, T := rTop, R := rRight, B := rBottom
            return
        }

        ; Clamp the mouse point to the nearest point on this rectangle, then compare squared distance.
        ; Using squared distance avoids the cost of Sqrt while still preserving the ordering.
        cx := (mx < rLeft) ? rLeft : (mx > rRight ? rRight : mx)
        cy := (my < rTop)  ? rTop  : (my > rBottom ? rBottom : my)
        dx := mx - cx, dy := my - cy
        dist2 := dx*dx + dy*dy
        if (dist2 < bestDist) {
            ; Keep the closest monitor as a fallback when the mouse is between or just outside monitors.
            bestDist := dist2
            L := rLeft, T := rTop, R := rRight, B := rBottom
            found := true
        }
    }
    if (!found) {
        ; Fallback to primary
        if (useWorkArea)
            SysGet, r, MonitorWorkArea, 1
        else
            SysGet, r, Monitor, 1
        L := rLeft, T := rTop, R := rRight, B := rBottom
    }
}

;------------------------------------------------------------------------------
;https://www.autohotkey.com/boards/viewtopic.php?t=51265
;------------------------------------------------------------------------------
; Classify a Win32 dialog for the activation path. "unknown" prevents an
; incomplete child scan from being treated as "plain".
ClassifyDialog32770(hWnd, windowClass := "", windowStyle := "") {
    if (!hWnd || !WinExist("ahk_id " . hWnd))
        return "unknown"

    if (windowClass = "")
        WinGetClass, windowClass, ahk_id %hWnd%

    if (windowClass = "")
        return "unknown"
    if (windowClass != "#32770")
        return "not_dialog"

    if (windowStyle = "")
        WinGet, windowStyle, Style, ahk_id %hWnd%

    if (windowStyle = "")
        return "unknown"

    ; Keep dialogs with min/max buttons out of the "plain" classification.
    ; Preserve the former non-plain result for these windows until the style
    ; heuristic is replaced by stronger positive file-dialog evidence.
    if (windowStyle & 0x00010000)  ; WS_MAXIMIZEBOX
        return "file_dialog"
    if (windowStyle & 0x00020000)  ; WS_MINIMIZEBOX
        return "file_dialog"

    ; Do NOT reject WS_THICKFRAME / WS_SIZEBOX here,
    ; so Notepad++ Find (0x94CC004C) will pass.

    ; A complete child-control scan distinguishes plain utility dialogs from
    ; shell-style dialogs containing a file or namespace view.
    WinGet, ctrlList, ControlList, ahk_id %hWnd%
    if (ErrorLevel || ctrlList = "")
        return "unknown"

    ; Classes that are strong indicators of a file view or shell namespace view.
    static suspectPattern := "i)^(SysListView32|SHELLDLL_DefView|DirectUIHWND|NamespaceTreeControl|SysTreeView32|CabinetWClass)"

    Loop, Parse, ctrlList, `n
    {
        ctrlNN := A_LoopField
        ; Match the complete ClassNN prefix. Stripping at the first digit would
        ; turn SysListView321 into SysListView and miss the SysListView32 class.
        if RegExMatch(ctrlNN, suspectPattern)
            return "file_dialog"
    }
    return "plain"
}

; Returns true when the window appears to host the kind of DirectUI/ListView
; target that SendCtrlAdd() may need to focus immediately after activation. The
; goal is to pay the fade-settle wait only for windows where early focus/send
; attempts are known to be unreliable, while keeping unrelated activations cheap.
NeedsSendCtrlAddFadeWait(hParent, focusedCtrlNN := "") {
    if (!hParent || !WinExist("ahk_id " . hParent))
        return False

    if (focusedCtrlNN = "")
        ControlGetFocus, focusedCtrlNN, ahk_id %hParent%

    if (InStr(focusedCtrlNN, "SysListView32", True) || InStr(focusedCtrlNN, "DirectUIHWND", True))
        return True

    WinGet, ctrlList, ControlList, ahk_id %hParent%
    if (ErrorLevel)
        return False

    Loop, Parse, ctrlList, `n
    {
        ctrlNN := A_LoopField
        if (InStr(ctrlNN, "SysListView32", True) || InStr(ctrlNN, "DirectUIHWND", True))
            return True
    }
    return False
}

; Returns true when activation-time SendCtrlAdd() should use the heavier
; WaitForExplorerLoad() path before sending Ctrl+NumpadAdd. This exists because
; real Explorer/open/save hosts can start with focus on breadcrumb/address/toolbar
; controls even though the actual file view still needs to finish loading. The
; decision therefore uses shell-host identity plus a previously captured target
; scan, instead of trusting transient initial focus alone.
_ShouldForceExplorerLoadOnActivate(topClass, targetScan := "", topProc := "", topTitle := "") {
    if (topClass != "CabinetWClass" && topClass != "#32770")
        return False

    ; Only force the activation-time Explorer load wait for windows that still
    ; look like real shell hosts and that actually contain a likely shell-view
    ; content target. This avoids basing the decision on transient initial
    ; focus such as the breadcrumb bar or address field.
    if (!(topClass == "CabinetWClass"
       || InStr(topProc, "explorer.exe", False)
       || InStr(topTitle, "Save", True)
       || InStr(topTitle, "Open", True)))
        return False

    if (!IsObject(targetScan))
        return False

    return targetScan.hasSysList
        || targetScan.hasDirect2
        || targetScan.hasDirect3
        || targetScan.hasDirect4
        || targetScan.hasDirect6
        || targetScan.hasDirect8
}

; Activation callback hot path:
; users often type immediately after Alt+Tab, WinActivate, or a click-driven
; focus change. Any slow work done directly in this callback can keep the
; script thread busy long enough for those first physical keystrokes to queue up
; and then flush late, which looks like bursty or garbled typing. The strategy
; here is therefore:
; 1) cancel stale typing work from the previous focus target immediately
; 2) keep the synchronous activation path limited to cheap classification and
;    minimal setup
; 3) avoid holding timers off across slower waits/probes
; 4) gate heavier shell-specific follow-up so only windows that truly need it
;    pay that cost
OnWinActiveChange(hWinEventHook, vEvent, hWnd)
{
    global StopRecursion

    if (StopRecursion || hitTab || !hWnd)
        return

    ; A focus change means any deferred typing rewrite or async editability probe
    ; belongs to the previous target, so cancel that work immediately.
    CancelTbcTypingWorkForContextChange()

    DetectHiddenWindows, Off
    ; Only hold timers off while capturing the initial activation snapshot and
    ; rejecting unsupported windows. Slower fade waits and send-path setup must
    ; not block unrelated deferred typing timers or the first queued typing work
    ; that may arrive immediately after this activation.
    Thread, NoTimers, True

    Loop, 500 {
        WinGetClass, vWinClass, % "ahk_id " hWnd
        WinGetTitle, vWinTitle, % "ahk_id " hWnd
        WinGet, vWinProc, ProcessName, ahk_id %hWnd%
        If (vWinClass != "" || vWinTitle != "" || WinExist("ahk_class #32768") || WinExist("ahk_class MsoCommandBarPopup"))
            break
        sleep, 1
    }

    If !(vWinClass == "#32770" && vWinTitle == "Run") {
        WinGet, vWinStyle, Style, % "ahk_id " hWnd
        dialogKind := ClassifyDialog32770(hWnd, vWinClass, vWinStyle)

        ; A missing or empty child snapshot is inconclusive. Abandon this
        ; activation attempt rather than incorrectly treating it as "plain".
        if (dialogKind == "unknown") {
            Thread, NoTimers, False
            Return
        }

        If (   IsOverException(hWnd)
            || dialogKind == "plain"
            || ((vWinStyle & 0xFFF00000 == 0x94C00000) && vWinClass != "#32770")
            || !WinExist("ahk_id " hWnd)) {
            If (vWinClass == "#32768" || vWinClass == "OperationStatusWindow") {
                WinSet, AlwaysOnTop, On, ahk_id %hWnd%
            }
            If (dialogKind == "plain") {
                ; WinActivate, ahk_id %hWnd%
                WinSet, AlwaysOnTop, On, ahk_id %hWnd%
                WinSet, AlwaysOnTop, Off, ahk_id %hWnd%
            }
            Thread, NoTimers, False
            Return
        }
    }

    Thread, NoTimers, False

    initFocusedCtrlForWait := ""
    ControlGetFocus, initFocusedCtrlForWait, ahk_id %hWnd%
    ; Base the fade-settle wait on the actual control shape that SendCtrlAdd()
    ; targets, so SysListView32-hosting apps such as 7-Zip still wait even
    ; when their top-level class is not Explorer or #32770. Windows that do not
    ; expose a likely shell/list target skip this wait so activation stays
    ; cheaper for the first keystrokes typed right after focus lands.
    if (NeedsSendCtrlAddFadeWait(hWnd, initFocusedCtrlForWait)) {
        WaitForFadeInStop(hWnd)
    }

    LbuttonEnabled := False

    isFirstTrackedActivation := !HasVal(prevActiveWindows, hWnd)
    if ( isFirstTrackedActivation || vWinClass == "#32770" || vWinClass == "CabinetWClass" ) {
        Critical, On
        prevActiveWindows.push(hWnd)
        Critical, Off

        WinGet, state, MinMax, ahk_id %hWnd%
        If (state > -1 && vWinTitle != "" && MonCount > 1) {
            currentMon := MWAGetMonitorMouseIsIn()
            currentMonHasActWin := IsWindowOnMonNum(hWnd, currentMon)
            If !currentMonHasActWin {
                WinActivate, ahk_id %hWnd%
                Send, #+{Left}
            }
        }

        If (vWinClass == "#32770") {
            WinSet, AlwaysOnTop, On, ahk_id %hWnd%
        }
        Else If (vWinClass != "#32770" && WinExist("ahk_class #32770")) {
            WinSet, AlwaysOnTop, On,  ahk_id %hWnd%
            WinSet, AlwaysOnTop, Off, ahk_class #32770
            WinSet, AlwaysOnTop, Off, ahk_id %hWnd%
        }

        If (InStr(vWinTitle, "Save", False) && vWinClass != "#32770") {
            LbuttonEnabled := True
            Thread, NoTimers, False
            WinSet, AlwaysOnTop, On,  ahk_id %hWnd%
            WinSet, AlwaysOnTop, Off, ahk_id %hWnd%
            Return
        }

        sendCtrlAddTargetScan := ""
        if (vWinClass == "#32770" || vWinClass == "CabinetWClass")
            sendCtrlAddTargetScan := GetSendCtrlAddTargetScan(hWnd, vWinClass)

        initFocusedCtrl := initFocusedCtrlForWait
        if (initFocusedCtrl == "") {
            Loop, 99 {
                sleep, 1
                ControlGetFocus, initFocusedCtrl, ahk_id %hWnd%
                If (initFocusedCtrl != "")
                    break
            }
        }

        LbuttonEnabled := True
        Thread, NoTimers, False

        ; New Explorer windows require a stable reported folder before the shared
        ; Details/content proof. Confirmed #32770 file dialogs normally do the same,
        ; but may use that proof alone when no folder-identity backend returns a path.
        if (dialogKind == "file_dialog") {
            minimumContentProbeDelayMs := isFirstTrackedActivation
                ? k_newExplorerCtrlAddMinimumWaitMs
                : 0
            _RequestExplorerCtrlAdd(hWnd, vWinClass, initFocusedCtrl, 0, "", False, True
                , minimumContentProbeDelayMs, True, False, False, True)
        }
        else if (vWinClass == "CabinetWClass" && isFirstTrackedActivation) {
            _RequestExplorerCtrlAdd(hWnd, vWinClass, initFocusedCtrl, 0, "", False, True
                , k_newExplorerCtrlAddMinimumWaitMs)
        }
        else {
            ; tooltip, sent to %initFocusedCtrl%
            SendCtrlAdd(hWnd, vWinClass, initFocusedCtrl
                , _ShouldForceExplorerLoadOnActivate(vWinClass, sendCtrlAddTargetScan, vWinProc, vWinTitle)
                , sendCtrlAddTargetScan)
        }

        DetectHiddenWindows, On
        i := 1
        while (i <= prevActiveWindows.MaxIndex()) {
            checkID := prevActiveWindows[i]
            If !WinExist("ahk_id " checkID)
                prevActiveWindows.RemoveAt(i)
            Else
                ++i
            If (GetKeyState("Lbutton", "P")) {
                break
            }
        }
        DetectHiddenWindows, Off
    }
    Else {
        Thread, NoTimers, False
    }

    LbuttonEnabled := True
}

WaitForFadeInStop(hwnd) {
    previousColor     := ""
    stableSampleCount := 0

    WinGetPos, sx, sy, sw, sh, ahk_id %hwnd%
    sampleX := (sx + sw)/2
    sampleY := (sy + 13)
    CoordMode, Pixel, Screen
    Loop, 500
    {
        PixelGetColor, currentColor, %sampleX%, %sampleY%, RGB

        ; Count consecutive identical samples instead of copying one new color
        ; into several "history" variables. Any color change resets the run to
        ; one, so this wait can finish only after five uninterrupted samples of
        ; the same pixel color rather than after merely one repeated sample.
        if (currentColor == previousColor)
            stableSampleCount += 1
        else
            stableSampleCount := 1

        previousColor := currentColor
        if (stableSampleCount >= 5)
            break

        sleep, 1
    }
    CoordMode, Mouse, screen
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

    ; Never leave Windows cursor confinement active when this script exits or reloads.
    EndBottomResizeCursorClamp()

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
    ; IMPORTANT:
    ; Do NOT call CoUninitialize here (not required for clean process exit)
    ; Do NOT call FreeLibrary on VirtualDesktopAccessor here (can hang on Win11)
return

; Purpose        : support the taskbar/Start-button workflow that needs a reliable
; screen coordinate target for the current Start button.
; Why this exists: centralizes the script's Start-button lookup policy and its
; fallback queries instead of scattering raw UIA taskbar probing inline.
; Scope          : feature-specific helper.
UIA_GetStartButtonCenter(ByRef sx, ByRef sy, ByRef buttonWidth) {
    global UIA

    try {
        hTask := WinExist("ahk_class Shell_TrayWnd")
        if !hTask
            return False

        tb := UIA.ElementFromHandle(hTask)
        if (IsObject(tb)) {
            ; Try several robust queries (name is localized; AutomationId often stable)
            startEl := tb.FindFirstBy("AutomationId=StartButton")

            if !IsObject(startEl)
                startEl := tb.FindFirstByNameAndType("Start", "Button")
            if !IsObject(startEl)
                startEl := tb.FindFirstByNameAndType("Start menu", "Button")
            if !IsObject(startEl)
                return False

            ; Get bounding rectangle and compute center
            ; UIA_Interface exposes CurrentBoundingRectangle (object with x,y,w,h)
            rect := startEl.CurrentBoundingRectangle
            if (!IsObject(rect) && rect == "") {
                ; Older versions may expose .BoundingRectangle or GetBoundingRectangle()
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

; Hotkeys for demo
F9::Overlay_ShowHole(500, 300, 400, 300, k_Opacity)  ; show again
F10::Overlay_Hide()                             ; hide

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
#If VolumeHover()
$WheelUp::send {Volume_Up}
$WheelDown::send {Volume_Down}

#If MouseIsOverAnyTaskbarSurface() || MouseIsOverDesktopShellSurface()
/*
HIGH-LEVEL HOTKEY RELATIONSHIPS
===============================
                                   Physical mouse input
                                            |
         +----------------------------------+----------------------------------+
         |                                  |                                  |
         |                                  |                                  |
         |                                  |                                  |
   LButton + RButton                    MButton                           RButton
   chord                                pressed                           pressed
         |                                  |                                  |
         |                                  |                                  |
         v                                  v                                  v

A) Special LButton+RButton         B) MButton move/resize               C) RButton system
---------------------------        ----------------------               ------------------

only title-bar chord exists        $*MButton:: begins                  every press first hits
in current code                           |                            passive ~*RButton tracker
         |                                  |                                  |
         +--> over title bar?               +--> sets temporary                +--> MButton-mode dedicated
         |        |                               RButton ownership                 RButton capture active?
         |        +--> YES                         during drag/resize               |
         |        |      set                                                    +--> YES
         |        |      suppressRightButtonLogic                                 |    #If suspendRightButton...
         |        |      rightButtonComboUsed                                     |    dedicated $*RButton:: / Up::
         |        |      title-bar action                                         |    consume this hold/release
         |        |
         |        +--> if standalone $*RButton:: also runs                     +--> NO
         |               it sees suppressRightButtonLogic                            |
         |               and exits early as consumed                                 v
         |
         +--> not over title bar?                                            taskbar or desktop shell?
                  |                                                                  |
                  +--> no special LButton+RButton action                             +--> YES
                                                                                     |    ~*RButton tracker still runs
                                                                                     |    no normal custom $*RButton::
                                                                                     |    native Windows RButton path
                                                                                     |    RButton+Wheel stays native
                                                                                     |
                                                                                     +--> NO
                                                                                          |
                                                                                          v
                                                                                     normal scoped $*RButton:: decides


MButton move/resize details
===========================
$*MButton::
        |
        +--> sets:
        |     suspendRightButtonForMButtonDrag
        |     swallowNextRButtonUpFromMButtonDrag := false
        |     WatchMButtonOverrideState
        |
        +--> while active:
        |     dedicated #If suspendRightButtonForMButtonDrag
        |     $*RButton:: / $*RButton Up:: get first claim
        |
        +--> if RButton participates in resize gesture
        |     mark next RButton Up to swallow
        |
        +--> drag loop chooses move vs resize
        |     and keeps monitor-boundary normalization in sync
        |
        +--> on release:
              |
              +--> quick title-bar tap?
              |        |
              |        +--> YES -> SwitchDesktop
              |
              +--> else quick non-drag tap?
              |        |
              |        +--> YES -> Send {MButton}
              |
              +--> else nearly full monitor height?
              |        |
              |        +--> YES -> normalize height to monitor bounds
              |
              +--> if a real move/resize happened
                       FitMovedWindowAgainstOthers(...)


Normal RButton system
=====================
scoped $*RButton::  (#If !MouseIsOverAnyTaskbarSurface() && !MouseIsOverDesktopShellSurface())
        |
        +--> special LButton+RButton chord already claimed this press?
        |        |
        |        +--> YES
        |        |      mark hold consumed
        |        |      start WatchRightButtonState
        |        |      return
        |
        +--> otherwise start normal custom RButton hold
                 |
                 +--> over shell item?
                 |        |
                 |        +--> YES
                 |        |      send native {RButton Down} immediately
                 |        |      so Explorer/Desktop right-drag works
                 |        |      mark hold as already consumed by special path
                 |        |
                 |        +--> NO
                 |               keep hold script-owned
                 |               wait for:
                 |               - RButton Up
                 |               - RButton + Wheel
                 |
                 +--> start WatchRightButtonState


RButton + Wheel
===============
WheelUp:: / WheelDown:: while RButton is physically down
        |
        +--> hold marked as taskbar/desktop passthrough,
        |    or mouse currently over taskbar/desktop shell?
        |        |
        |        +--> YES -> send native wheel
        |
        +--> otherwise
                 try custom navigation action
                 |
                 +--> if action will execute
                          rightButtonComboUsed := true
                          rightButtonSuppressMenuOnUp := true
                          send replacement navigation keys


Release ownership
=================
$*RButton Up::
        |
        +--> MButton-mode dedicated capture owns this release?
        |        |
        |        +--> YES -> consume there and return
        |
        +--> else special LButton+RButton chord claimed the hold?
        |        |
        |        +--> YES -> _ResetRightButtonState(false)
        |
        +--> else normal RButton release path:
                 |
                 +--> native {RButton Down} had been sent earlier?
                 |        |
                 |        +--> YES
                 |        |      send matching {RButton Up}
                 |        |      maybe send {Esc}
                 |        |
                 |        +--> NO
                 |               if hold was not consumed
                 |                   Click, Right
                 |
                 +--> _ResetRightButtonState(false)


Watchdogs
=========
WatchRightButtonState
        |
        +--> protects custom RButton state
        +--> if physical RButton is up but state is still latched
        +--> _ResetRightButtonState(true)

WatchMButtonOverrideState
        |
        +--> protects temporary MButton ownership state
        +--> if physical MButton is up
        +--> clear DraggingWindow / StopRecursion / suspendRightButtonForMButtonDrag


ONE-SENTENCE MENTAL MODEL
=========================

- `LButton + RButton` currently has one special path: the title-bar chord.
- `MButton` temporarily installs a top-priority RButton owner during move/resize mode.
- every `RButton` press is passively tracked, but the custom `$*RButton::` state machine only exists off taskbar/desktop shell surfaces.
*/

#If suspendRightButtonForMButtonDrag
$*RButton::
    ; Give MButton move/resize mode first claim on RButton everywhere, including
    ; Explorer/taskbar-adjacent surfaces where the normal RButton state machine
    ; may not be eligible. This keeps the resize chord from leaking a plain
    ; right-click when the physical release arrives later.
    swallowNextRButtonUpFromMButtonDrag := true
return

$*RButton Up::
    if (swallowNextRButtonUpFromMButtonDrag)
        swallowNextRButtonUpFromMButtonDrag := false

    if (!GetKeyState("MButton", "P")) {
        suspendRightButtonForMButtonDrag := false
        SetTimer, WatchMButtonOverrideState, Off
    }
return

#If

~*RButton::
    ; Track taskbar/desktop-shell holds without taking ownership of the click itself.
    ; The tilde lets Windows receive the real right-click natively on those surfaces.
    rightButtonTaskbarPassthrough := true
return

#If

~*RButton Up::
    if (rightButtonTaskbarPassthrough)
        rightButtonTaskbarPassthrough := false
return

#If !MouseIsOverAnyTaskbarSurface() && !MouseIsOverDesktopShellSurface()
$*RButton::
    ; tooltip, % "DOWN sr=" suppressRightButtonLogic " held=" rightButtonHeld " native=" rightButtonNativeDown

    ; While MButton window-drag mode is active, ignore plain RButton handling entirely.
    if (suspendRightButtonForMButtonDrag) {
        ; Latch the consume-on-release flag from the actual RButton hotkey too so
        ; MButton resize cannot miss a quick Explorer right-press between loop polls.
        swallowNextRButtonUpFromMButtonDrag := true
        if (!GetKeyState("MButton", "P")) {
            suspendRightButtonForMButtonDrag := false
            SetTimer, WatchMButtonOverrideState, Off
        }
        return
    }

    if (suppressRightButtonLogic && !GetKeyState("LButton", "P"))
        suppressRightButtonLogic := false

    ; Heal any stale state before starting a fresh hold.
    if (rightButtonHeld || rightButtonComboUsed || rightButtonNativeDown)
        _ResetRightButtonState(true)

    ; Special LButton+RButton chords consume the hold, so keep the watchdog
    ; running but skip normal right-click behavior.
    if (suppressRightButtonLogic) {
        rightButtonHeld      := true
        rightButtonComboUsed := true
        SetTimer, WatchRightButtonState, 15
        return
    }

    ; Start a new script-owned hold. We only send a real RButton down immediately
    ; when the pointer is already over a shell item that must support right-drag.
    rightButtonHeld             := true
    rightButtonComboUsed        := false
    rightButtonNativeDown       := false
    rightButtonSuppressMenuOnUp := false
    SetTimer, WatchRightButtonState, 15

    if (IsMouseOverShellItemForRButton()) {
        ; Shell items need a real right-button-down immediately so Explorer/Desktop can start
        ; a native right-drag from the item itself. rightButtonNativeDown is what makes the
        ; up-handler send the balancing {RButton Up}; comboUsed is kept as a safety/intent
        ; marker so this hold is treated as already consumed by a special path.
        rightButtonComboUsed  := true
        rightButtonNativeDown := true
        SendInput, {RButton Down}
        return
    }

    ; Non-shell-item holds never become native drags. We keep the hold in script
    ; state only so wheel combos can consume it; otherwise release falls back to
    ; a plain Click, Right.
return

$*RButton Up::
    ; tooltip, % "UP sr=" suppressRightButtonLogic " held=" rightButtonHeld " native=" rightButtonNativeDown

    ; MButton resize/move mode may intentionally suppress RButton on the way down.
    ; If that gesture used RButton, consume the matching up-event here so it does
    ; not fall through to the normal Click, Right completion path.
    if (swallowNextRButtonUpFromMButtonDrag) {
        swallowNextRButtonUpFromMButtonDrag := false
        return
    }

    ; MButton drag mode owns the hold, so an RButton release should not complete a click here.
    if (suspendRightButtonForMButtonDrag) {
        if (!GetKeyState("MButton", "P")) {
            suspendRightButtonForMButtonDrag := false
            SetTimer, WatchMButtonOverrideState, Off
        }
        return
    }

    if (suppressRightButtonLogic) {
        _ResetRightButtonState(false)
        return
    }

    SetTimer, WatchRightButtonState, Off

    ; If we already emitted a native RButton down, always balance it here. This is why
    ; the shell-item fast path sets rightButtonNativeDown immediately on button-down.
    ; Successful wheel combos then dismiss the menu with Esc so mouse movement does not matter.
    if (rightButtonNativeDown) {
        SendInput, {RButton Up}
        if (rightButtonSuppressMenuOnUp)
            SendInput, {Esc}
    }
    else if (!rightButtonComboUsed)
        Click, Right

    _ResetRightButtonState(false)
return

#If MouseIsOverTitleBar()
~LButton & RButton::
    suppressRightButtonLogic := true
    rightButtonComboUsed     := true

    MouseGetPos,,, hwndId
    WinGetTitle, winTitle, ahk_id %hwndId%
    WinGet, exStyle, ExStyle, ahk_id %hwndId%

    if IsAlwaysOnTop(hwndId) {
        Gui, GUIHighlighter: Color, 0x00FF00
        WinSet, Transparent, Off, ahk_id %hwndId%
    }
    else {
        Gui, GUIHighlighter: Color, 0xFF0000
        transDelta := 5
        iterations := (255 - k_Opacity) / transDelta
        transVal := 255
        transVal -= transDelta

        Critical, On
        Loop, %iterations%
        {
            WinSet, Transparent, %transVal%, ahk_id %hwndId%
            transVal -= transDelta
            Sleep, 20
        }
        Critical, Off
    }

    BlockInput, MouseMove
    GoSub, DrawRect
    Sleep, 200
    ClearRect()
    BlockInput, MouseMoveOff
    Gui, GUIHighlighter: Color, %k_border_color%
    WinSet, AlwaysOnTop, Toggle, ahk_id %hwndId%
return

#If

#If GetKeyState("RButton", "P")

WheelUp::
    ; If the hold started on the taskbar or desktop shell, keep the entire
    ; RButton+wheel gesture native instead of repurposing it into the custom path.
    if (rightButtonTaskbarPassthrough || MouseIsOverAnyTaskbarSurface() || MouseIsOverDesktopShellSurface()) {
        SendInput, {WheelUp}
        return
    }

    ; RButton+WheelUp scrolls/paginates while the hold remains "consumed" until release.
    if (!VolumeHover() && !IsOverException() && !DraggingWindow) {
        SetTimer, SendCtrlAddLabel, Off

        targetHwnd   := 0
        targetPosX   := ""
        targetPosY   := ""
        targetWidth  := ""
        targetHeight := ""
        zoneWidth    := ""

        isInScrollZone := IsMouseInVScrollZone_WinGetPosEx_Sys(10, 14, 12
            , targetHwnd, true
            , targetPosX, targetPosY, targetWidth, targetHeight
            , zoneWidth)

        if (!targetHwnd)
            return

        WinGetClass, currentClass, ahk_id %targetHwnd%

        if !WinActive("ahk_id " . targetHwnd) {
            WinActivate, ahk_id %targetHwnd%
            WinWaitActive, ahk_id %targetHwnd%,, 0.15
            if !WinActive("ahk_id " . targetHwnd)
                return
        }

        ; Latch the combo only after we know the wheel action is going to execute.
        rightButtonComboUsed := true
        rightButtonSuppressMenuOnUp := true

        if (isInScrollZone) {
            if (currentClass == "CASCADIA_HOSTING_WINDOW_CLASS") {
                Send, ^+{Home}
            }
            else {
                Send, ^{Home}
                Send, {Home}
            }
        }
        else if (currentClass == "CASCADIA_HOSTING_WINDOW_CLASS") {
            Send, ^+{PgUp}
            Sleep, 50
        }
        else {
            Send, {PgUp}
            Sleep, 50
        }
        return
    }
return

WheelDown::
    ; Same bypass as WheelUp: preserve normal wheel behavior whenever this RButton hold
    ; belongs to the taskbar or desktop shell instead of the custom combo logic.
    if (rightButtonTaskbarPassthrough || MouseIsOverAnyTaskbarSurface() || MouseIsOverDesktopShellSurface()) {
        SendInput, {WheelDown}
        return
    }

    ; Same idea as WheelUp, but for downward paging/end navigation.
    if (!VolumeHover() && !IsOverException() && !DraggingWindow) {
        SetTimer, SendCtrlAddLabel, Off

        targetHwnd   := 0
        targetPosX   := ""
        targetPosY   := ""
        targetWidth  := ""
        targetHeight := ""
        zoneWidth    := ""

        isInScrollZone := IsMouseInVScrollZone_WinGetPosEx_Sys(10, 14, 12
            , targetHwnd, true
            , targetPosX, targetPosY, targetWidth, targetHeight
            , zoneWidth)

        if (!targetHwnd)
            return

        WinGetClass, currentClass, ahk_id %targetHwnd%

        if !WinActive("ahk_id " . targetHwnd) {
            WinActivate, ahk_id %targetHwnd%
            WinWaitActive, ahk_id %targetHwnd%,, 0.15
            if !WinActive("ahk_id " . targetHwnd)
                return
        }

        ; Latch the combo only after we know the wheel action is going to execute.
        rightButtonComboUsed := true
        rightButtonSuppressMenuOnUp := true

        if (isInScrollZone) {
            if (currentClass == "CASCADIA_HOSTING_WINDOW_CLASS") {
                Send, ^+{End}
            }
            else {
                Send, ^{End}
                Send, {End}
            }
        }
        else if (currentClass == "CASCADIA_HOSTING_WINDOW_CLASS") {
            Send, ^+{PgDn}
            Sleep, 50
        }
        else {
            Send, {PgDn}
            Sleep, 50
        }
        return
    }
return

#If

#If blockWheel
; Swallow plain and Ctrl-modified physical wheel events only while a synthetic
; Ctrl+NumpadAdd sequence and its immediate Ctrl cleanup are active.
$WheelUp::Return
$WheelDown::Return
$^WheelUp::Return
$^WheelDown::Return
#If

#If !GetKeyState("RButton", "P")

$^WheelUp::
    if (IsConsoleWindow() && !MouseIsOverTitleBar()) {
        stopRecursion := true
        SetTimer, MbuttonTimer, Off
        Send, {Up}
        Sleep, 125
        SetTimer, MbuttonTimer, -1
        stopRecursion := false
    }
    else {
        Send, ^{WheelUp}
    }
return

$^WheelDown::
    if (IsConsoleWindow() && !MouseIsOverTitleBar()) {
        stopRecursion := true
        SetTimer, MbuttonTimer, Off
        Send, {Down}
        Sleep, 125
        SetTimer, MbuttonTimer, -1
        stopRecursion := false
    }
    else {
        Send, ^{WheelDown}
    }
return

$~WheelUp::
    stopRecursion := true
    Critical, Off
    Sleep, -1

    MouseGetPos,,, windowId, wheelControl
    WinGetClass, hoverClass, ahk_id %windowId%
    WinGetClass, activeClass, A
    isWheelOverTitleBar := MouseIsOverTitleBar()
    wheelCanAdjustColumns := (wheelControl == "SysListView321")
                          || ((wheelControl == "DirectUIHWND2" || wheelControl == "DirectUIHWND3")
                           && (hoverClass == "CabinetWClass" || hoverClass == "#32770"))

    if (hoverClass != "ProgMan"
     && hoverClass != "WorkerW"
     && hoverClass != "CASCADIA_HOSTING_WINDOW_CLASS"
     && !(hoverClass == "CabinetWClass" && isWheelOverTitleBar)
     && activeClass != "CASCADIA_HOSTING_WINDOW_CLASS"
     && wheelCanAdjustColumns)
    {
        tbcAdjustColumnsClass         := hoverClass
        tbcAdjustColumnsCtrl          := wheelControl
        tbcAdjustColumnsHwnd          := windowId
        tbcAdjustColumnsLastWheelTick := A_TickCount
        tbcAdjustColumnsRequestId += 1
        SetTimer, WheelSendCtrlAdd, Off
        SetTimer, WheelSendCtrlAdd, -110
    }
    else if (MouseIsOverTaskbarBlank())
    {
        Send, #^{Left}
        Sleep, 1000
    }
    else {
        tbcAdjustColumnsRequestId :=
        tbcAdjustColumnsHwnd      :=
        tbcAdjustColumnsCtrl      := ""
    }

    Thread, NoTimers, False
    stopRecursion := false
return

$~WheelDown::
    stopRecursion := true
    Critical, Off
    Sleep, -1

    MouseGetPos,,, windowId, wheelControl
    WinGetClass, hoverClass, ahk_id %windowId%
    WinGetClass, activeClass, A
    isWheelOverTitleBar := MouseIsOverTitleBar()
    wheelCanAdjustColumns := (wheelControl == "SysListView321")
                          || (InStr(wheelControl, "DirectUIHWND", True)
                           && (hoverClass == "CabinetWClass" || hoverClass == "#32770"))

    if (hoverClass != "ProgMan"
     && hoverClass != "WorkerW"
     && hoverClass != "CASCADIA_HOSTING_WINDOW_CLASS"
     && !(hoverClass == "CabinetWClass" && isWheelOverTitleBar)
     && activeClass != "CASCADIA_HOSTING_WINDOW_CLASS"
     && wheelCanAdjustColumns)
    {
        tbcAdjustColumnsClass         := hoverClass
        tbcAdjustColumnsCtrl          := wheelControl
        tbcAdjustColumnsHwnd          := windowId
        tbcAdjustColumnsLastWheelTick := A_TickCount
        tbcAdjustColumnsRequestId += 1
        SetTimer, WheelSendCtrlAdd, Off
        SetTimer, WheelSendCtrlAdd, -110
    }
    else if (isWheelOverTitleBar)
    {
        MouseGetPos,,, windowHwnd, controlHwnd, 2
        rootHwnd := DllCall("GetAncestor", "ptr", windowHwnd, "uint", 2, "ptr")
        WinMinimize, ahk_id %rootHwnd%
        Sleep, 500
        return
    }
    else if (MouseIsOverTaskbarBlank())
    {
        Send, #^{Right}
        Sleep, 1000
    }
    else {
        tbcAdjustColumnsRequestId :=
        tbcAdjustColumnsHwnd      :=
        tbcAdjustColumnsCtrl      := ""
    }

    Thread, NoTimers, False
    stopRecursion := false
return

#If

; Reset right-button script state if an up transition is missed.
_ResetRightButtonState(sendNativeUp := false) {
    global rightButtonHeld, rightButtonComboUsed, rightButtonNativeDown, rightButtonSuppressMenuOnUp, rightButtonTaskbarPassthrough, suppressRightButtonLogic, swallowNextRButtonUpFromMButtonDrag

    SetTimer, WatchRightButtonState, Off

    ; Optionally emit the missing native button-up so the shell is never left thinking
    ; RButton is still physically held.
    if (sendNativeUp && rightButtonNativeDown) {
        SendInput, {RButton Up}
        if (rightButtonSuppressMenuOnUp)
            SendInput, {Esc}
    }

    rightButtonHeld                     := false
    rightButtonComboUsed                := false
    rightButtonNativeDown               := false
    rightButtonSuppressMenuOnUp         := false
    rightButtonTaskbarPassthrough       := false
    suppressRightButtonLogic            := false
    swallowNextRButtonUpFromMButtonDrag := false
}

WatchRightButtonState:
    ; Self-heal if the physical RButton is no longer down but our script state is still latched.
    if (GetKeyState("RButton", "P"))
        return

    if (rightButtonHeld || rightButtonComboUsed || rightButtonNativeDown || suppressRightButtonLogic)
        _ResetRightButtonState(true)
return

; Wheel-driven column auto-fit is deferred onto this timer instead of sending
; Ctrl+NumpadAdd directly from WheelUp/WheelDown.
;
; High-level flow:
; 1) wait for wheel input to go quiet
; 2) confirm the same hovered window is still active
; 3) reuse or resolve the column target
; 4) auto-fit a native SysListView32 Details view directly when possible
; 5) otherwise focus the target for the keyboard fallback
; 6) re-check that the same wheel request is still current
; 7) send Ctrl+NumpadAdd as late as possible
;
; This keeps rapid wheel bursts responsive while making the final column-fit send
; happen only after scrolling has settled and the target window/control still match.
WheelSendCtrlAdd:
    currentRequestId  := 0
    isExplorerLikeWin := False
    isPlainListView   := False
    requiredQuietMs   := 0
    TargetControl     := ""
    TargetControlHwnd := 0

    ; Stage 1: basic request validation.
    ; If the wheel hook never captured a valid target, there is nothing to do.
    if (!tbcAdjustColumnsRequestId || !tbcAdjustColumnsHwnd || tbcAdjustColumnsCtrl == "")
        return

    ; Snapshot the request token once so every later stage can cheaply detect whether
    ; a newer wheel event replaced this tbc work item.
    currentRequestId := tbcAdjustColumnsRequestId
    requiredQuietMs  := (tbcAdjustColumnsClass == "#32770")
                       ? k_tbcAdjustColumnsDialogQuietMs
                       : k_tbcAdjustColumnsQuietMs

    ; Stage 2: quiet-gap gating.
    ; Do not focus or send anything until wheel input has paused for the required
    ; quiet window. If scrolling resumes, schedule the next check for the exact
    ; remaining quiet time instead of adding a fixed retry interval.
    elapsedQuietMs := A_TickCount - tbcAdjustColumnsLastWheelTick
    if (elapsedQuietMs <= requiredQuietMs) {
        remainingQuietMs := GetRemainingQuietDelayMs(elapsedQuietMs, requiredQuietMs)
        SetTimer, WheelSendCtrlAdd, % -remainingQuietMs
        return
    }

    ; Stage 3: same-window validation.
    ; Only operate on the same active window that originally queued
    ; this request. If activation changed, cancel instead of mutating a stale target.
    if (WinExist("A") != tbcAdjustColumnsHwnd)
        return

    WinGetClass, adjustClassNow, ahk_id %tbcAdjustColumnsHwnd%
    isExplorerLikeWin := (adjustClassNow == "CabinetWClass" || adjustClassNow == "#32770")
    isPlainListView   := (tbcAdjustColumnsCtrl == "SysListView321")

    if (adjustClassNow != tbcAdjustColumnsClass)
        return

    ; Plain SysListView32 targets can use the generic quiet-gap path in any app.
    ; DirectUI targets remain limited to Explorer/open-save style shell hosts where
    ; the shared chooser knows how to resolve the real Ctrl+NumpadAdd destination.
    if (!isPlainListView && !isExplorerLikeWin)
        return

    ; Stage 4: target resolution.
    ; First try the short-lived target cache for this same window. That avoids
    ; repeating target discovery during stop-and-go wheel bursts.
    ; The cache is only reused if the control still belongs to this window and its
    ; live HWND still exists.
    if (c_tbcAdjustColumnsTargetHwnd = tbcAdjustColumnsHwnd
     && c_tbcAdjustColumnsTargetCtrl != ""
     && (A_TickCount - c_tbcAdjustColumnsTargetTick) < k_tbcAdjustColumnsTargetTtlMs) {
        ControlGet, TargetControlHwnd, Hwnd,, % c_tbcAdjustColumnsTargetCtrl, ahk_id %tbcAdjustColumnsHwnd%
        if (TargetControlHwnd)
            TargetControl := c_tbcAdjustColumnsTargetCtrl
    }

    ; If the cache is not usable, pick the lightest resolution path that matches
    ; the hovered control shape:
    ; - plain SysListView32: trust the captured control directly
    ; - Explorer/dialog DirectUI: reuse the shared shell scan + chooser
    if (TargetControl == "") {
        if (isPlainListView) {
            TargetControl := tbcAdjustColumnsCtrl
        }
        else {
            targetScan := GetSendCtrlAddTargetScan(tbcAdjustColumnsHwnd, adjustClassNow)
            ; Wheel hover can transiently report DirectUIHWND2/3 even when a different
            ; pane is the real Ctrl+NumpadAdd target, so do not blindly trust those two
            ; names here. Let the shared chooser resolve the final target instead.
            TargetControl := ChooseSendCtrlAddTarget(tbcAdjustColumnsHwnd, adjustClassNow, tbcAdjustColumnsCtrl, targetScan, False)
        }
    }

    ; Stage 5: native auto-fit or keyboard-fallback preparation.
    ; If a target was resolved, first try direct column sizing for a native
    ; SysListView32 Details view. Direct sizing does not require focus, the 20 ms
    ; synthetic-send guard, or injected Ctrl state. If it is unavailable or fails,
    ; preserve the existing focus plus Ctrl+NumpadAdd fallback.
    ; If no target was resolved, do not hard-fail here: the older behavior of sending
    ; Ctrl+NumpadAdd to the active window still sometimes succeeds when the target
    ; view already has usable item focus and only the explicit control lookup missed it.
    if (TargetControl != "") {
        ; Resolve the target HWND once so the cache and later focus work use a live control.
        if (!TargetControlHwnd)
            ControlGet, TargetControlHwnd, Hwnd,, %TargetControl%, ahk_id %tbcAdjustColumnsHwnd%

        if (TargetControlHwnd) {
            ; Publish the resolved target briefly so the next wheel pause in this same
            ; window can skip shell-control discovery if nothing structural changed.
            c_tbcAdjustColumnsTargetCtrl := TargetControl
            c_tbcAdjustColumnsTargetHwnd := tbcAdjustColumnsHwnd
            c_tbcAdjustColumnsTargetTick := A_TickCount

            ; Abort if a newer wheel event superseded this request while target discovery
            ; was running. Old timers should not continue into focus work.
            if (tbcAdjustColumnsRequestId != currentRequestId)
                return

            ; Re-check the quiet gap and foreground window immediately before direct
            ; sizing. A wheel hotkey can update the timestamp just before it increments
            ; the request token, so both checks are required to reject partial updates.
            elapsedQuietMs := A_TickCount - tbcAdjustColumnsLastWheelTick
            if (elapsedQuietMs < requiredQuietMs) {
                remainingQuietMs := GetRemainingQuietDelayMs(elapsedQuietMs, requiredQuietMs, False)
                SetTimer, WheelSendCtrlAdd, % -remainingQuietMs
                return
            }

            if (WinExist("A") != tbcAdjustColumnsHwnd)
                return

            if (k_useNativeSysListViewColumnAutoFit
             && InStr(TargetControl, "SysListView32", True)
             && DllCall("user32\IsChild", "Ptr", tbcAdjustColumnsHwnd, "Ptr", TargetControlHwnd, "Int")) {
                if AutoFitSysListViewColumns(TargetControlHwnd, k_nativeSysListViewColumnAutoFitMode)
                    return
            }

            ; Use the same explicit ClassNN focus step as the known-good SendCtrlAdd()
            ; Explorer path. Modern Explorer may report focus inside DirectUI while still
            ; ignoring Ctrl+NumpadAdd unless the exact target control is actively focused.
            EnsureFocusedCtrlNN(tbcAdjustColumnsHwnd, TargetControl, 60, 15)
        }
    }

    ; Stage 6: final stale-work and quiet-gap checks.
    ; Re-check both the request token and the quiet gap after focus work, because
    ; wheel input may have resumed while this timer was still running.
    if (tbcAdjustColumnsRequestId != currentRequestId)
        return

    elapsedQuietMs := A_TickCount - tbcAdjustColumnsLastWheelTick
    if (elapsedQuietMs < requiredQuietMs) {
        remainingQuietMs := GetRemainingQuietDelayMs(elapsedQuietMs, requiredQuietMs, False)
        SetTimer, WheelSendCtrlAdd, % -remainingQuietMs
        return
    }

    ; Reconfirm the same window is still active immediately before the synthetic send.
    if (WinExist("A") != tbcAdjustColumnsHwnd)
        return

    ; Stage 7: final send.
    ; Keep the actual key injection small and late so all expensive decisions happen
    ; before this point and Ctrl+NumpadAdd is emitted only for a still-current request.
    _SendCtrlNumpadAddIfStillValid(6, currentRequestId, requiredQuietMs, tbcAdjustColumnsHwnd)
return

MbuttonTimer:
    MbuttonIsEnter := True
    sleep, 1500
    MbuttonIsEnter := False
Return

#If MbuttonIsEnter
Mbutton::
    Send, {Enter}
    SetTimer, MbuttonTimer, Off
    SetTimer, MbuttonTimer, -1
Return
#If

IsConsoleWindow() {
    WinGetClass, targetClass, A
    If (targetClass == "mintty" || targetClass == "CASCADIA_HOSTING_WINDOW_CLASS" || targetClass == "ConsoleWindowClass")
        Return True
    Else
        Return False
}

IsWindowScrollable() {
    MouseGetPos, , , hwnd, ctrlN
    WinGet, ExControlStyle, ExStyle, ahk_id %hwnd%
    ControlGet, ControlStyle, Style,, %ctrlN%, ahk_id %hwnd%
    If (((ControlStyle & 0x100000) || (ControlStyle & 0x200000)) || (ExControlStyle & 0x4000)) {
        ; tooltip, is scrollable %ControlStyle%
        Return True
    }
    Else {
        ; tooltip, NOT scrollable %ControlStyle%
        Return False
    }
}

ForceRedrawWindow(hwnd) {
    static RDW_INVALIDATE := 0x0001
    static RDW_UPDATENOW  := 0x0100
    static RDW_ALLCHILDREN := 0x0080

    return DllCall("user32\RedrawWindow"
        , "Ptr", hwnd
        , "Ptr", 0
        , "Ptr", 0
        , "UInt", RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN)
}

#If !MbuttonIsEnter && !MouseIsOverTaskbar()
$*MButton::
    global DraggingWindow

    StopRecursion := True
    swallowNextRButtonUpFromMButtonDrag := false
    ; While MButton window-drag mode is active, plain RButton should never enter its
    ; normal click/drag state machine. The watchdog clears this if MButton is released.
    suspendRightButtonForMButtonDrag := true
    ; Thread, NoTimers, True
    SetTimer, WatchMButtonOverrideState, 25

    MouseGetPos, mx0, my0, hWnd, ctrlNN, 2
    isOverTitleBar        := MouseIsOverTitleBar(mx0, my0)
    checkClickMx          := mx0
    checkClickMy          := my0
    wx0                   := 0
    wy0                   := 0
    ww                    := 0
    wh                    := 0
    virtwx0               := 0
    virtwy0               := 0
    offsetX               := 0
    offsetY               := 0
    deltaPxTrig           := 5
    windowSnapped         := False
    TL                    := False
    TR                    := False
    BL                    := False
    BR                    := False
    snapShotX             := 0
    snapShotY             := 0
    adjustSize            := False
    isRbutton             := False
    switchingBackToMove   := False
    switchingBacktoResize := False
    startedAlwaysOnTop    := False

    If (!hWnd || !JEE_WinHasAltTabIcon(hWnd)) {
        ; Nothing draggable here, so release the temporary RButton suppression immediately.
        StopRecursion                    := False
        suspendRightButtonForMButtonDrag := false
        SetTimer, WatchMButtonOverrideState, Off
        return
    }

    initTime := A_TickCount

    WinGet, isMax, MinMax, ahk_id %hWnd%
    WinGetClass, cls, ahk_id %hWnd%
    If (k_skipClasses.HasKey(cls)) {
        ; For excluded classes, fall back to a normal MButton click and tear down the
        ; temporary RButton suppression state on the way out.
        KeyWait, Mbutton, U T3
        Send, {Mbutton}
        StopRecursion                    := False
        suspendRightButtonForMButtonDrag := false
        SetTimer, WatchMButtonOverrideState, Off
        return
    }

    BlockInput, MouseMove
    WinGetPosEx(hWnd, wx0, wy0, ww, wh, offsetX, offsetY)
    If (ww = "" || wh = "") {
        BlockInput, MouseMoveOff
        KeyWait, Mbutton, U T3
        Send, {Mbutton}
        StopRecursion                    := False
        suspendRightButtonForMButtonDrag := false
        SetTimer, WatchMButtonOverrideState, Off
        return
    }

    snapState     := ""   ; "", "left", "right"
    dragStartX    := wx0
    dragStartY    := wy0
    dragStartW    := ww
    dragStartH    := wh
    mxPrev        := mx0  ; track prior mouse X to know approach direction
    myPrev        := my0  ; track prior mouse X to know approach direction

    leftWinEdge   := wx0
    topWinEdge    := wy0
    rightWinEdge  := wx0 + ww
    bottomWinEdge := wy0 + wh

    ; Resolve the monitor/work-area rectangle under the initial press point.
    ; These bounds become the reference frame for early snap-state detection:
    ; compare the window's current left/right edges against monL/monR to see
    ; whether the drag started already docked near the monitor edge.
    ; msgbox, % leftWinEdge "," rightWinEdge "-" topWinEdge "," bottomWinEdge ":" offsetX " & " offsetY
    GetMonitorRectForMouse(mx0, my0, k_UseWorkArea, monL, monT, monR, monB)
    If ((leftWinEdge - monL) <= k_SnapRange && (leftWinEdge - monL) >= 0) {
        snapState := "left"
    } Else If ((rightWinEdge - monR) <= k_SnapRange && (rightWinEdge - monR) >= 0) {
        snapState := "right"
    }

    If      (mx0 <= leftWinEdge + floor(ww/2) && my0 <= wy0 + floor(wh/2))
        TL := True
    Else If (mx0 >  leftWinEdge + floor(ww/2) && my0 <= wy0 + floor(wh/2))
        TR := True
    Else If (mx0 <= leftWinEdge + floor(ww/2) && my0 >  wy0 + floor(wh/2))
        BL := True
    Else If (mx0 >  leftWinEdge + floor(ww/2) && my0 >  wy0 + floor(wh/2))
        BR := True

    BlockInput, MouseMoveOff

    startedAlwaysOnTop := IsAlwaysOnTop(hWnd)
    If !startedAlwaysOnTop
        WinSet, Transparent, 255, ahk_id %hWnd%

    Critical, On
    while GetKeyState("MButton", "P") {

        If (A_TickCount - initTime < k_SingleClickTime && !GetKeyState("LShift","P"))
            continue

        DraggingWindow := True
        isRbutton := GetKeyState("Rbutton","P")
        if (isRbutton)
            swallowNextRButtonUpFromMButtonDrag := true
        If (!isRbutton && isRbutton_last) {
            BlockInput, MouseMove
            sleep, 150
            BlockInput, MouseMoveOff
            switchingBackToMove := True
        }
        Else
            switchingBackToMove := False

        If (isRbutton && !isRbutton_last) {
            switchingBacktoResize := True
        }
        Else
            switchingBacktoResize := False

        isRbutton_last := isRbutton

        windowSnapped := False

        MouseGetPos, mx, my,

        If switchingBackToMove {
            mx0 := mx
            my0 := my
            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
        }
        Else If switchingBacktoResize {
            mx0 := mx
            my0 := my
            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
        }

        If (isMax == 1 && (abs(mx - mx0) > deltaPxTrig || abs(my - my0) > deltaPxTrig)) {
            BlockInput, Mousemove
            xRatio := (mx-monL)/ww
            yRatio := (my-monT)/wh
            ; Guard against weirdness
            if (xRatio < 0)
                xRatio := 0
            if (xRatio > 1)
                xRatio := 1
            if (yRatio < 0)
                yRatio := 0
            if (yRatio > 1)
                yRatio := 1

            WinRestore, ahk_id %hWnd%
            WaitForStableWindow(hWnd)

            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
            moveToX := Round(mx - xRatio * ww)
            moveToY := Round(my - yRatio * wh)

            WinMove, ahk_id %hWnd%,, %moveToX%, %moveToY%
            WaitForStableWindow(hWnd)

            isMax == 0
            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
            MouseGetPos, mx, my,
            BlockInput, MouseMoveOff
        }

        dragHorz := ""
        dragVert := ""
        If      ((my - myPrev) < 0 && abs(my - my0) > deltaPxTrig && abs(my - myPrev) > abs(mx - mxPrev))   {
            dragVert := "up"
        }
        Else If ((my - myPrev) > 0 && abs(my - my0) > deltaPxTrig && abs(my - myPrev) > abs(mx - mxPrev))  {
            dragVert := "down"
        }
        Else If ((mx - mxPrev) > 0 && abs(mx - mx0) > deltaPxTrig) {
            dragHorz := "right"
        }
        Else If ((mx - mxPrev) < 0 && abs(mx - mx0) > deltaPxTrig) {
            dragHorz := "left"
        }
        mxPrev := mx
        myPrev := my

        If (dragHorz_prev != "" && dragHorz != "" && dragHorz_prev != dragHorz)
        || (dragVert_prev != "" && dragVert != "" && dragVert_prev != dragVert) {
            mx0 := mx
            my0 := my
            WinGetPosEx(hWnd, wx0, wy0, ww, wh, null, null)
        }

        If WinExist("ahk_class tooltips_class32")
            WinClose, ahk_class tooltips_class32

        If dragHorz
            dragHorz_prev := dragHorz
        If dragVert
            dragVert_prev := dragVert

        dx := mx - mx0
        dy := my - my0

        If !startedAlwaysOnTop {
            WinGet, trans, Transparent, ahk_id %hWnd%
            If (trans == 255 && (abs(dx) > deltaPxTrig || abs(dy) > deltaPxTrig)) {
                targetTrans := 170
                WinSet, Transparent, %targetTrans%, ahk_id %hWnd%
            }
        }

        ; Re-resolve the monitor/work-area rectangle under the current mouse
        ; position. During a cross-monitor drag, monL/monT/monR/monB can change
        ; from one loop iteration to the next, so all snap thresholds, max
        ; travel distances, and confinement math below stay tied to the monitor
        ; the cursor is currently in rather than the one where the drag started.
        GetMonitorRectForMouse(mx, my, k_UseWorkArea, monL, monT, monR, monB)
        ; monW/monH are the active monitor dimensions used by the near-full-
        ; height heuristic and the later mouse-confinement calls.
        monW  := monR-monL
        monH  := monB-monT
        ; Compare the live window height against the active monitor height so
        ; nearly full-height drags stay pinned vertically to this monitor's
        ; top/bottom work-area bounds instead of floating freely.
        isNearFullMonitorHeight := (wh / Abs(monB - monT) > 0.90)
        ; Translate the returned monitor edges into the window's legal travel
        ; box on this monitor. minX/minY anchor movement to monL/monT, while
        ; maxY/maxHD/maxHU/maxWL/maxWR limit how far the window can move or grow
        ; before it would overshoot monR/monB or the opposite monitor edge.
        ;
        ; Current monitor/work area                Current window outer frame
        ; monL                                  monR
        ;  |--------------------------------------|
        ;  |   wx0                         wx0+ww |
        ;  |    |----------------------------|    |
        ;  |    |                            |    |
        ;  |    |                            |    |
        ;  |    |----------------------------|    |
        ;  |   wy0                      wy0+wh    |
        ;  |                                      |
        ; monT                                  monB
        ;
        ; maxHD = monB      - wy0      ; top edge down to monitor bottom
        ; maxHU = (wy0+wh)  - monT     ; window bottom up to monitor top
        ; maxWL = (wx0+ww)  - monL     ; window right edge left to monitor left
        ; maxWR = monR      - wx0      ; monitor right edge right from window left
        ; Vertical allowable range for current monitor
        minX  := monL
        minY  := monT
        if (isNearFullMonitorHeight) {
            maxY := monT
        } else {
            maxY := monB - wh
        }
        maxHD := (monB - wy0)
        maxHU := (wy0+wh - monT)
        maxWL := (wx0 + ww) - monL
        maxWR := (monR - wx0)

        ; virtwx0 is continuously changing with your mouse and represents the current theoretical value of the window's x coordinate.
        ; it's "theoretical" because the window may be "snapped" but this value will still change as the mouse moves which
                ; is why you can compare virtwx0 against the difference between monL and k_BreakAway/k_ReleaseAway distances
        ; monL is fixed to the active monitor's left edge.
        virtwx0 := wx0 + dx ; (original window X) + (how far the mouse has moved in X since drag start)
        virtwy0 := wy0 + dy

        If !isRbutton {
            If !GetKeyState("LShift","P")
                WinSet, AlwaysOnTop, On, ahk_id %hWnd%

            UnclipCursor()
            ; --- One-way vertical clamp (top/bottom) ---
            If (virtwy0 < minY)
                newY := minY
            Else If (virtwy0 > maxY)
                newY := maxY
            Else
                newY := virtwy0

            ; --- Horizontal snapping with pass-through ---
            leftWinEdge   := virtwx0
            rightWinEdge  := virtwx0 + ww

            rightSnapX    := monR - ww  ; X that places the right edge at monitor's right

            WinGetPosEx(hWnd, null, null, ww, wh, null, null)
            If (snapState = "left") {
                ; While snapped left:
                ; - Push-through: keep dragging left until virtwx0 <= monL - k_BreakAway to break snap
                ; - Release: drag right until virtwx0 >= monL + k_ReleaseAway to release snap
                ; ie Have you moved (virtwx0) far enough past the monitor edge (monL) → k_BreakAway/k_ReleaseAway
                If (virtwx0 <= monL - k_BreakAway || virtwx0 >= monL + k_ReleaseAway) {
                    snapState := ""
                    newX := virtwx0
                } Else {
                    newX := monL
                }
            } Else If (snapState = "right") {
                ; While snapped right (window's right edge at monR):
                ; - Push-through: keep dragging right until virtwx0 >= rightSnapX + k_BreakAway to break snap
                ; - Release: drag left until virtwx0 <= rightSnapX - k_ReleaseAway to release snap
                If (virtwx0 >= rightSnapX + k_BreakAway || virtwx0 <= rightSnapX - k_ReleaseAway) {
                    snapState := ""
                    newX := virtwx0
                } Else {
                    newX := rightSnapX
                }
            } Else {
                ; Not currently snapped: check proximity to edges to start snapping
                If (Abs(leftWinEdge - monL) <= k_SnapRange && dragHorz == "left") {
                    snapState := "left"
                    windowSnapped := True
                    newX := monL
                    ; tooltip, snapState %snapState%
                } Else If (Abs(rightWinEdge - monR) <= k_SnapRange && dragHorz == "right") {
                    snapState := "right"
                    windowSnapped := True
                    newX := rightSnapX
                    ; tooltip, snapState %snapState%
                } Else {
                    newX := virtwx0
                    ; tooltip, snapState "none" - %virtwx0% - %dx% - %dy%
                }
            }

            ; correct for windows' shadows
            newX := newX + offsetX
            ; No horizontal clamping otherwise: allow off-screen left/right
            WinMove, ahk_id %hWnd%, , %newX%, %newY%
        }
        Else {
            gridSize := k_SnapRange

            gridDx := ceil(dx/gridSize) * gridSize
            gridDy := ceil(dy/gridSize) * gridSize

            If      (TL || TR) && (dragVert == "up"   || dragVert == "down") {
                WinGetPosEx(hWnd, tx, ty, tw, th, null, null)
                If (dragVert == "up" && ty == minY) {
                    adjustSize := False
                    BlockInput, MouseMove
                    MouseMove, mx, my
                    ConfineMouseToCurrentMonitorArea( "work", 0, my, monW, monH-my)
                    sleep, 250
                    BlockInput, MouseMoveOff
                }
                Else {
                    If (dragVert == "up") {
                        virtwy0 := wy0 - abs(gridDy)
                        virtwh0 := wh  + abs(gridDy)
                        If ((virtwh0 > maxHU - k_SnapRange) || (virtwy0 < minY + k_SnapRange)) {
                            virtwy0 := minY
                            virtwh0 := maxHU
                        }
                    }
                    Else If (dragVert == "down") {
                        virtwh0 := wh - abs(dy)
                    }

                    adjustSize := True
                    newX :=
                    newY := virtwy0
                    newW :=
                    newH := virtwh0 + 2*abs(offsetY) + 1 ; these adjustments are ONLY needed for WinMove, WinGetPosEx is 100% accurate
                }
            }
            Else If (BL || BR) && (dragVert == "up"   || dragVert == "down") {
                WinGetPosEx(hWnd, tx, ty, tw, th, null, null)
                If (dragVert == "down" && th == maxHD) {
                    adjustSize := False
                    BlockInput, MouseMove
                    MouseMove, mx, my
                    ConfineMouseToCurrentMonitorArea( "work", 0, 0, monW, my)
                    sleep, 250
                    BlockInput, MouseMoveOff
                }
                Else {
                    If (dragVert == "down") {
                        ; virtwy0 doesnt matter since it remains fixed when adjusting width
                        virtwh0 := wh + abs(gridDy)
                        If (virtwh0 > maxHD - k_SnapRange)
                            virtwh0 := maxHD
                    }
                    Else If (dragVert == "up") {
                        virtwh0 := wh - abs(dy)
                    }

                    adjustSize := True
                    newX :=
                    newY :=
                    newW :=
                    newH := virtwh0 + 2*abs(offsetY) + 1 ; these adjustments are ONLY needed for WinMove, WinGetPosEx is 100% accurate
                }
            }
            Else If (TL || BL) && (dragHorz == "left" || dragHorz == "right") {
                WinGetPosEx(hWnd, tx, ty, tw, th, null, null)
                If (dragHorz == "left" && tx == minX) {
                    adjustSize := False
                    BlockInput, MouseMove
                    MouseMove, mx, my
                    ConfineMouseToCurrentMonitorArea( "work", mx, 0, monW-mx, monH)
                    sleep, 250
                    BlockInput, MouseMoveOff
                }
                Else {
                    If (dragHorz == "left") {
                        virtwx0 := wx0 - abs(gridDx)
                        virtww0 := ww  + abs(gridDx)
                        If ((virtww0 > (maxWL - k_SnapRange)) || (virtwx0 < (minX + k_SnapRange))) {
                            virtwx0 := minX
                            virtww0 := maxWL
                        }
                    }
                    Else If (dragHorz == "right") {
                        virtww0 := ww - abs(dx)
                    }

                    adjustSize := True
                    newX := virtwx0 + offsetX
                    newY :=
                    newW := virtww0  + 2*abs(offsetX)
                    newH :=
                }
            }
            Else If (TR || BR) && (dragHorz == "left" || dragHorz == "right") {
                WinGetPosEx(hWnd, tx, ty, tw, th, null, null)
                If (dragHorz == "right" && tx+tw == monR) {
                    adjustSize := False
                    BlockInput, MouseMove
                    MouseMove, mx, my
                    ConfineMouseToCurrentMonitorArea( "work", 0, 0, mx, monH)
                    sleep, 250
                    BlockInput, MouseMoveOff
                }
                Else {
                    If (dragHorz == "right") {
                        ; virtwx0 doesnt matter since it remains fixed when adjusting width
                        virtww0 := ww + abs(gridDx)
                        If (virtww0 > (maxWR - k_SnapRange))
                            virtww0 := maxWR
                    }
                    Else If (dragHorz == "left") {
                        virtww0 := ww - abs(dx)
                    }

                    adjustSize := True
                    newX :=
                    newY :=
                    newW :=virtww0 + 2*abs(offsetX)
                    newH :=
                }
            }

            ; correct for windows' shadows
            If adjustSize {
                WinMove, ahk_id %hWnd%, , %newX%, %newY%, %newW%, %newH%
            }
        }

        If (windowSnapped) {
            BlockInput, MouseMove
            sleep, 250
            BlockInput, MouseMoveOff
        }
    }
    Critical, Off

    rlsTime := A_TickCount
    stopMon := MWAGetMonitorMouseIsIn()
    If (!startedAlwaysOnTop)
        ForceRedrawWindow(hWnd)

    If (rlsTime - initTime < k_SingleClickTime
        && isOverTitleBar
        && (abs(checkClickMx - mx0) <= deltaPxTrig)
        && (abs(checkClickMy - my0) <= deltaPxTrig)) {

        WinSet, Transparent, Off, ahk_id %hWnd%
        GoSub, SwitchDesktop
    }
    Else If (rlsTime - initTime < k_SingleClickTime
            && (abs(checkClickMx - mx0) <= deltaPxTrig)
            && (abs(checkClickMy - my0) <= deltaPxTrig)) {
        Send, {Mbutton}
    }
    Else If (wh/abs(monB-monT) > 0.90) {
        ; Normalize nearly full-height windows before the post-move fit helper runs.
        ; Waiting here avoids sampling stale geometry immediately after this WinMove.
        WinMove, ahk_id %hWnd%, , , %monT%, , abs(monB-monT) + 2*abs(offsetY) + 1
        WaitForStableWindow(hWnd)
        WinGetPosEx(hWnd, wx0, wy0, ww, wh, offsetX, offsetY)
    }

    If !startedAlwaysOnTop {
        WinSet, AlwaysOnTop, Off, ahk_id %hWnd%
        WinSet, Transparent, Off, ahk_id %hWnd%
    }

    WinGetPosEx(hWnd, finalWindowX, finalWindowY, finalWindowW, finalWindowH, null, null)
    didMoveWindow := ( Abs(finalWindowX - dragStartX) > deltaPxTrig
                    || Abs(finalWindowY - dragStartY) > deltaPxTrig
                    || Abs(finalWindowW - dragStartW) > deltaPxTrig
                    || Abs(finalWindowH - dragStartH) > deltaPxTrig)

    if (didMoveWindow)
        FitMovedWindowAgainstOthers(hWnd, stopMon, 100, 100)

    ; Normal exit: restore plain RButton handling before leaving MButton drag mode.
    StopRecursion := False
    suspendRightButtonForMButtonDrag := false
    ; Thread, NoTimers, False
    SetTimer, WatchMButtonOverrideState, Off
    DraggingWindow := False
Return
#If

WatchMButtonOverrideState:
    ; MButton window-drag temporarily suppresses plain RButton handling. This watchdog
    ; clears that suppression as soon as the physical middle button is released.
    if (GetKeyState("MButton", "P"))
        return

    DraggingWindow                   := False
    StopRecursion                    := False
    suspendRightButtonForMButtonDrag := false
    SetTimer, WatchMButtonOverrideState, Off
return
WaitForStableWindow(hwnd, delay := 30, timeout := 1000) {
    lastW := lastH := 0
    elapsed := 0
    Loop
    {
        WinGetPos,,, w, h, ahk_id %hwnd%
        if (w = lastW && h = lastH)
            return true
        lastW := w, lastH := h
        Sleep, delay
        elapsed += delay
        if (elapsed > timeout)
            return false
    }
}

; =========================
; ConfineMouseToCurrentMonitorArea(area, x, y, w, h)
; =========================
; area  - "work" (exclude taskbar) or "monitor" (full monitor). Default = "work".
; x, y  - offset from top-left corner of chosen area (in pixels)
; w, h  - width and height of the box (in pixels)
ConfineMouseToCurrentMonitorArea(area := "work", x := 0, y := 0, w := 0, h := 0) {
    ; Get current mouse position
    MouseGetPos, mx, my

    ; Get monitor handle under cursor
    hMon := DllCall("user32\MonitorFromPoint", "int64", (my << 32) | (mx & 0xFFFFFFFF), "uint", 2, "ptr")
    if !hMon
        return 0

    ; Prepare MONITORINFO structure
    VarSetCapacity(mi, 40, 0)
    NumPut(40, mi, 0, "UInt")

    if !DllCall("user32\GetMonitorInfo", "ptr", hMon, "ptr", &mi)
        return 0

    ; rcMonitor (offset 4), rcWork (offset 20)
    monL  := NumGet(mi,  4, "Int"), monT  := NumGet(mi,  8, "Int")
    monR  := NumGet(mi, 12, "Int"), monB  := NumGet(mi, 16, "Int")
    workL := NumGet(mi, 20, "Int"), workT := NumGet(mi, 24, "Int")
    workR := NumGet(mi, 28, "Int"), workB := NumGet(mi, 32, "Int")

    ; Determine which area to use
    area := (area = "MONITOR" || area = "monitor") ? "monitor" : "work"
    if (area = "monitor") {
        baseL := monL, baseT := monT, baseR := monR, baseB := monB
    } else {
        baseL := workL, baseT := workT, baseR := workR, baseB := workB
    }

    baseW := baseR - baseL
    baseH := baseB - baseT

    ; Clamp the box within monitor boundaries
    if (w <= 0) || (w > baseW)
        w := baseW
    if (h <= 0) || (h > baseH)
        h := baseH
    if (x < 0)
        x := 0
    if (y < 0)
        y := 0
    if (x + w > baseW)
        x := baseW - w
    if (y + h > baseH)
        y := baseH - h

    ; Compute absolute screen coords
    left   := baseL + x
    top    := baseT + y
    right  := left + w
    bottom := top + h

    ; Build RECT and clip
    VarSetCapacity(rc, 16, 0)
    NumPut(left,   rc,  0, "Int")
    NumPut(top,    rc,  4, "Int")
    NumPut(right,  rc,  8, "Int")
    NumPut(bottom, rc, 12, "Int")

    return DllCall("user32\ClipCursor", "ptr", &rc) ? 1 : 0
}

; Unclip
UnclipCursor() {
    return DllCall("user32\ClipCursor", "ptr", 0) ? 1 : 0
}

$^+Esc::
    Run, C:\Program Files\SystemInformer\SystemInformer.exe
Return

$CapsLock::
    TimeOfLastHotkeyTyped := A_TickCount
    Send {Delete}
    lastHotkeyTyped := "CapsLock"
Return

#If (!WinActive("ahk_exe notepad++.exe") && !WinActive("ahk_exe Everything.exe") && !WinActive("ahk_exe Code.exe") && !WinActive("ahk_exe EXCEL.EXE") && !IsEditFieldActive())
^+d::
    if (WinExist("ahk_class rctrl_renwnd32") && ControlExist("OOCWindow1", "ahk_class rctrl_renwnd32"))
        Send, {Esc}

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
    if (WinExist("ahk_class rctrl_renwnd32") && ControlExist("OOCWindow1", "ahk_class rctrl_renwnd32"))
        Send, {Esc}

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
; using a bounded message send. Returns "inserted", "target_gone", or
; "message_uncertain". The last state must not fall back to Ctrl+V because the
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

; Attempts a fast classic-control replacement. "not_classic" and "target_gone"
; leave Clip() to make the foreground-guarded clipboard-paste decision. A
; "message_uncertain" result does not: the direct message may already have run.
_TryFastInsertWrappedText(windowId, text) {
    targetState := _GetFastInsertWrappedTextTarget(windowId, controlHwnd)
    if (targetState != "classic_edit")
        return targetState

    return _FastInsertWrappedTextIntoClassicControl(windowId, controlHwnd, text)
}

; Wraps clipboard text, preserving a single trailing space outside the wrapper,
; and prefers direct classic-control replacement before clipboard paste fallback.
WrapClipboardText(leftText, rightText) {
    ; These hotkeys are Alt+Shift chords. Keep those modifiers logically up
    ; after the managed Ctrl+C send and any clipboard-paste fallback so
    ; applications cannot treat a following key as an Alt menu accelerator or
    ; Shift-modified shortcut.
    modifiersToSync  := ""
    targetWindowId   := DllCall("user32\GetForegroundWindow", "Ptr")
    clipboardText    := Clip("", "", "", modifiersToSync, targetWindowId)

    hasTrailingSpace := SubStr(clipboardText, 0) == " "
    wrappedText      := RTrim(clipboardText, " ")

    wrappedText := leftText . wrappedText . rightText
    if (hasTrailingSpace)
        wrappedText .= " "

    insertResult := _TryFastInsertWrappedText(targetWindowId, wrappedText)
    ; "not_classic" means the focused control is not a recognized Win32
    ; Edit/RichEdit class, so the direct EM_REPLACESEL path is not attempted.
    ; "target_gone" means the direct HWND path cannot identify the focused child.
    ; Clip() rechecks targetWindowId immediately before Ctrl+V, so either state
    ; can use the managed clipboard path without pasting into another app.
    ; "message_uncertain" is intentionally excluded because EM_REPLACESEL may
    ; already have changed the selection before its bounded send timed out.
    if (insertResult = "not_classic" || insertResult = "target_gone")
        Clip(wrappedText, "", "", modifiersToSync, targetWindowId)

}

; Runs a wrapper hotkey with input blocking and typing fixes temporarily disabled.
; The finally block always releases the keyboard block, even when clipboard or
; target-control work raises an error before the normal cleanup path runs.
_RunWrapClipboardText(leftText, rightText) {
    global StopAutoFix

    Critical, On
    StopAutoFix := True
    BeginBlockKeys()
    try {
        WrapClipboardText(leftText, rightText)
    } finally {
        ; Release input-state guards before optional cleanup so a failure here
        ; cannot leave physical key-down events permanently blocked.
        EndBlockKeys()
        StopAutoFix := False
        try {
            Hotstring("Reset")
        } finally {
            Critical, Off
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
    Send, {Down}
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

        if (TryCaptureCompleteFocusSnapshot(currentFixSlashEnterHwnd, currentFixSlashEnterCtrlNN, currentFixSlashEnterCtrlHwnd, currentFixSlashEnterCtrlClass)
            && IsClassicEditControlClass(currentFixSlashEnterCtrlClass)) {
            ; Classic Edit/RichEdit keeps the older immediate Enter-thread path.
            ; Non-classic editors cannot prove the rewrite inline as reliably, so
            ; those fall through to the deferred barrier below.
            CancelTbcTypingFixes(True, False)
            if (!_CommitFixSlashEnterInline())
                Send, {Enter}
        }
        else {
            ; This mirrors tbcHoty and deferred slash+Space: queue intent,
            ; wait for brief idle, revalidate the same target, then apply or
            ; cancel. The extra rule here is that Enter itself stays withheld
            ; until the queued slash rewrite has been resolved.
            _RequestFixSlash("enter")
        }
    }
    else
        Send, {Enter}
    disableEnter := False
Return
#If

; =========================================================

#If !disableEnter && (WinActive("ahk_class CabinetWClass") || WinActive("ahk_class #32770"))
$~Enter::
    ControlGetFocus, entCtrl, A
    WinGetClass, entCl, A
    WinGetTitle, entTi, A
    WinGet, entID, ID, A
    If     (entCl == "CabinetWClass" && InStr(entCtrl, "Edit", True))
        || (entCl == "#32770" && InStr(entCtrl, "Edit", True) && (InStr(entTi, "Save", True) || InStr(entTi, "Open", True))) {

        Keywait, Enter, U T3

        WinGet, checkID, ID, A
        If (checkID == entID)
            SendCtrlAdd(entID, entCl)
        }
Return

$~F2::
    Critical, On
    LbuttonEnabled := False
    StopRecursion  := True

    KeyWait, F2, U T3

    Loop, 10000
    {
        If (GetKeyState("Enter") || GetKeyState("Lbutton") || GetKeyState("Esc"))
            break
        sleep, 1
    }

    LbuttonEnabled := True
    StopRecursion  := False
    Critical, Off
Return
#If

$~Space::
    GoSub, Marktime_Hoty_FixSlash
    lastHotkeyTyped := "~Space"
Return

$!Space::
    Send, {Space}
    lastHotkeyTyped := "~Space"
Return

; duplicate hotkey in case shift is accidentally  held as a result of attempting to type a '?'
$~+Space::
    GoSub, Marktime_Hoty_FixSlash
    lastHotkeyTyped := "~Space"
Return

$~^Backspace::
    CancelTbcTypingFixes(True, True)
    Hotstring("Reset")
Return

; Editing or moving the caret invalidates the remembered prior-letter context used
; by FixSlash, so clear it here rather than letting a later "/" rewrite qualify
; against text the user has already changed or navigated away from.
$~Backspace::
    CancelTbcTypingFixes(True, True)
    TimeOfLastHotkeyTyped := A_TickCount
    lastHotkeyTyped := "~Backspace"
    X_PriorPriorHotKey :=
Return

$~Left::
    CancelTbcTypingFixes(True, True)
    X_PriorPriorHotKey :=
Return

$~Right::
    CancelTbcTypingFixes(True, True)
    X_PriorPriorHotKey :=
Return

; Ctl+Tab in chrome to goto recent
prevChromeTab()
{
    global StopRecursion
    StopRecursion := True
    DetectHiddenWindows, Off
    Send, ^+{a}
    Loop, 100
    {
        WinGet, allChromeWindows, List, ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe
        Loop, %allChromeWindows%
        {
            this_id := allChromeWindows%A_Index%
            WinGetTitle, titID, ahk_id %this_id%
            If (titID == "")
                break
        }
        If (titID == "")
            break
        sleep, 20
        If (A_Index == 99) {
            StopRecursion := False
            Return
        }
    }
    sleep, 250
    WinActivate, ahk_id %this_id%
    ; ControlFocus, Chrome_RenderWidgetHostHWND1, ahk_id %this_id%
    Send, {Enter}
    sleep, 150
    If WinExist("ahk_id " . this_id) && WinActive("ahk_id " . this_id)
        Send, {tab}{tab}{Enter}
    tooltip, switched!
    sleep, 1000
    tooltip,
    StopRecursion := False
}

#If WinActive("ahk_exe Chrome.exe")
    ^Tab::
        prevChromeTab()
    Return

    ^f::
        Send, {Esc}
        Send, ^{f}
    Return
#If

GetVisibleHwndByPartialClass(classPart) {
    WinGet, idList, List
    Loop, %idList%
    {
        hWnd := idList%A_Index%

        WinGet, isMin, MinMax, ahk_id %hWnd%
        if (isMin = -1)  ; -1 = minimized (skip)
            continue

        WinGet, styleNum, Style, ahk_id %hWnd%
        if !(styleNum & 0x10000000) ; WS_VISIBLE
            continue

        WinGetClass, winClass, ahk_id %hWnd%
        if InStr(winClass, classPart)
            return hWnd
    }
    return
}
#If !SearchingWindows && !hitTAB
; A second Esc press on the same foremost window opens close confirmation.
; Pressing x while that second Esc remains held cancels the close.
$Esc::
    StopRecursion := True
    SetTimer, EscTimer, Off

    escHwndID := FindTopMostWindow()
    WinGetTitle, escTitle, ahk_id %escHwndID%

    If (A_PriorHotKey == A_ThisHotKey && A_TimeSincePriorHotkey  < k_DoubleClickTime && escHwndID == escHwndID_old && escTitle == escTitle_old) {

        DetectHiddenWindows, Off
        executedOnce   := False

        If IsAltTabWindow(escHwndID) {
            WinActivate, ahk_id %escHwndID%
            WinGet, pp, ProcessPath , ahk_id %escHwndID%
            Hotkey, x, DoNothing, On
            WinGetPosEx(escHwndID, wx, wy, ww, wh, null, null)
            Overlay_ShowHole(wx, wy, ww, wh, k_Opacity,, 40)
            DrawWindowTitlePopup(escHwndID, "Close?", pp, True)

            Loop
            {
                ; tooltip Close `"%escTitle%`" ? ;"
                sleep, 1
                If !GetKeyState("Esc","P")
                    break
                If GetKeyState("x","P") {
                    Tooltip, Canceled!
                    Overlay_Hide(30)
                    ClearWindowTitlePopup()
                    CancelClose := True
                    sleep, 1500
                    Tooltip,
                    StopRecursion := False
                }
            }
            Hotkey, x, DoNothing, Off
            If !CancelClose {
                Winclose, ahk_id %escHwndID%

                Loop, 10
                {
                    ; tooltip, Waiting for `"%escTitle%`" to close... ; "
                    If (!WinExist("ahk_id " . escHwndID)) {
                        Overlay_Hide(30)
                        ClearWindowTitlePopup()
                        ActivateTopMostWindow()
                        break
                    }
                    sleep, 125

                    testhwndID := GetVisibleHwndByPartialClass("Dialog")
                    If ((WinExist("ahk_class #32770") || WinExist("ahk_class NUIDialog") || testhwndID) && !executedOnce) {
                        If (testhwndID)
                            WinGet, dialog_hwndID, ID, ahk_id %testhwndID%
                        Else If (WinExist("ahk_class NUIDialog"))
                            WinGet, dialog_hwndID, ID, ahk_class NUIDialog
                        Else
                            WinGet, dialog_hwndID, ID, ahk_class #32770

                        executedOnce := True
                        WinSet, AlwaysOnTop, On, ahk_id %dialog_hwndID%
                        ; tooltip, waiting...
                        WinWaitClose, ahk_id %dialog_hwndID%
                        break
                    }
                }
                sleep, 125
                If (WinExist("ahk_id " . escHwndID) && !executedOnce) {
                    WinGet, kill_pid, PID, ahk_id %escHwndID%
                    Process, Close, %kill_pid%
                }

                If (WinExist("ahk_id " . escHwndID) && !executedOnce) {
                    WinKill , ahk_id %escHwndID%
                    Loop, 50
                    {
                        If !WinExist("ahk_id " . escHwndID) {
                            Overlay_Hide(30)
                            ClearWindowTitlePopup()
                            ActivateTopMostWindow()
                            break
                        }
                        sleep 125
                        WinKill , ahk_id %escHwndID%
                    }
                }
                Else {
                    ; tooltip, tried to clear
                    Overlay_Hide(30)
                    ClearWindowTitlePopup()
                    ActivateTopMostWindow()
                }
            }
            Else
                CancelClose := False
        }
        tooltip
        StopRecursion := False
        Return
    }

    delayValue := -1*(k_DoubleClickTime/2)
    SetTimer, EscTimer, %delayValue%
    escTitle_old  := escTitle
    escHwndID_old := escHwndID
    StopRecursion := False
Return

#If

EscTimer:
    tooltip, escaped!
    Send, {Esc}
    sleep, 1500
    tooltip,
Return

;https://superuser.com/questions/950452/how-to-quickly-move-current-window-to-another-task-view-desktop-in-windows-10

!0::
    DetectHiddenWindows, On
    wndIdOnDesk := getForemostWindowIdOnDesktop(2)
    WinGetClass, cl, ahk_id %wndIdOnDesk%
    total := GetDesktopCount()
    tooltip, class is %cl% of %total% desktops
    DetectHiddenWindows, Off
Return

#1::
    Critical, On
    StopRecursion := True
    GoSub, SwitchToVD1
    StopRecursion := False
    SyncModifierSidesToPhys("Ctrl Win")
    Critical, Off
Return

SwitchToVD1:
    CurrentDesktop := GetCurrentDesktopNumber() + 1
    testDesktop := CurrentDesktop
    while (CurrentDesktop < 1) {
        Send #^{Right}
        while (CurrentDesktop == testDesktop) {
            sleep, 100
            testDesktop := GetCurrentDesktopNumber() + 1
        }
        CurrentDesktop := GetCurrentDesktopNumber() + 1
    }
    while (CurrentDesktop > 1) {
        Send #^{Left}
        while (CurrentDesktop == testDesktop) {
            sleep, 100
            testDesktop := GetCurrentDesktopNumber() + 1
        }
        CurrentDesktop := GetCurrentDesktopNumber() + 1
    }
Return

#2::
    Critical, On
    StopRecursion := True
    GoSub, SwitchToVD2
    StopRecursion := False
    SyncModifierSidesToPhys("Ctrl Win")
    Critical, Off
Return

SwitchToVD2:
    If  (GetDesktopCount() >= 2) {
        CurrentDesktop := GetCurrentDesktopNumber() + 1
        testDesktop := CurrentDesktop
        while (CurrentDesktop < 2) {
            Send #^{Right}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
        while (CurrentDesktop > 2) {
            Send #^{Left}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
    }
Return

#3::
    Critical, On
    StopRecursion := True
    GoSub, SwitchToVD3
    SyncModifierSidesToPhys("Ctrl Win")
    StopRecursion := False
    Critical, Off
Return

SwitchToVD3:
    If  (GetDesktopCount() >= 3) {
        CurrentDesktop := GetCurrentDesktopNumber() + 1
        testDesktop := CurrentDesktop
        while (CurrentDesktop < 3) {
            Send #^{Right}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
        while (CurrentDesktop > 3) {
            Send #^{Left}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
    }
Return

#4::
    Critical, On
    StopRecursion := True
    GoSub, SwitchToVD4
    StopRecursion := False
    SyncModifierSidesToPhys("Ctrl Win")
    Critical, Off
Return

SwitchToVD4:
    If  (GetDesktopCount() >= 4) {
        CurrentDesktop := GetCurrentDesktopNumber() + 1
        testDesktop := CurrentDesktop
        while (CurrentDesktop < 4) {
            Send #^{Right}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
        while (CurrentDesktop > 4) {
            Send #^{Left}
            while (CurrentDesktop == testDesktop) {
                sleep, 100
                testDesktop := GetCurrentDesktopNumber() + 1
            }
            CurrentDesktop := GetCurrentDesktopNumber() + 1
        }
    }
Return

;https://superuser.com/questions/1261225/prevent-alttab-from-switching-to-minimized-windows
Altup:
    global bufferedCycleAdvance, cycleCount, ValidWindows, GroupedWindows, startHighlight, hitTAB, hitTilde, LclickSelected, blockKeys, CanceledWinSwap

    If startHighlight && !CanceledWinSwap {
        WinGet, actWndID, ID, A
        If (LclickSelected && hitTAB && !hitTilde && (GroupedWindows.length() > 2) && actWndID != ValidWindows[1]) {
            BeginBlockKeys()
            GoSub, SortAllWins
            EndBlockKeys()
        }
        Else If ((GroupedWindows.length() > 2)  && actWndID != ValidWindows[1]) {
            BeginBlockKeys()
            GoSub, SortGroupedWins ; currently, GroupedWindows == ValidWindows for alt+tab but not for alt+`
            EndBlockKeys()
        }
    }
Return

AltupCleanup:
    global bufferedCycleAdvance, cycleCount, ValidWindows, GroupedWindows, startHighlight, hitTAB, hitTilde, LclickSelected, blockKeys, CanceledWinSwap

    Critical, On
    hitTAB               := False
    hitTilde             := False
    bufferedCycleAdvance := False
    cycleCount           := 1
    ValidWindows         := []
    GroupedWindows       := []
    MinimizedWindows     := []
    lastActWinID         :=
    startHighlight       := False
    LclickSelected       := False
    CanceledWinSwap      := False
    StopRecursion        := False
    Thread, NoTimers, False
    Critical, Off
    HideWindowTitlePopup()
    GoSub, EnableTimers
Return
;============================================================================================================================
SortAllWins:
    Critical, On

    WinSet, AlwaysOnTop, Off, ahk_id %_winIdD%
    WinSet, AlwaysOnTop, On,  ahk_id %_winIdD%

    If (_winIdD != ValidWindows[4] && ValidWindows.MaxIndex() >= 4) {
            WinActivate, % "ahk_id " ValidWindows[4]
    }
    If (_winIdD != ValidWindows[3] && ValidWindows.MaxIndex() >= 3) {
            WinActivate, % "ahk_id " ValidWindows[3]
    }
    If (_winIdD != ValidWindows[2] && ValidWindows.MaxIndex() >= 2) {
            WinActivate, % "ahk_id " ValidWindows[2]
    }
    If (_winIdD != ValidWindows[1] && ValidWindows.MaxIndex() >= 1) {
            WinActivate, % "ahk_id " ValidWindows[1]
    }

    WinSet, AlwaysOnTop, On, ahk_id %_winIdD%
    WinActivate, % "ahk_id " _winIdD

    WinSet, AlwaysOnTop, Off , % "ahk_id " _winIdD
    Critical, Off
Return

SortGroupedWins:
    Critical, On
    WinSet, AlwaysOnTop, Off, % "ahk_id " GroupedWindows[cycleCount]
    WinSet, AlwaysOnTop, On,  % "ahk_id " GroupedWindows[cycleCount]

    If (ValidWindows.MaxIndex() >= 4 && GroupedWindows[cycleCount] != ValidWindows[4]) {
        WinActivate, % "ahk_id " ValidWindows[4]
    }
    If (ValidWindows.MaxIndex() >= 3 && GroupedWindows[cycleCount] != ValidWindows[3]) {
        WinActivate, % "ahk_id " ValidWindows[3]
    }
    If (ValidWindows.MaxIndex() >= 2 && GroupedWindows[cycleCount] != ValidWindows[2]) {
        WinActivate, % "ahk_id " ValidWindows[2]
    }
    If (ValidWindows.MaxIndex() >= 1 && GroupedWindows[cycleCount] != ValidWindows[1]) {
        WinActivate, % "ahk_id " ValidWindows[1]
    }

    WinSet, AlwaysOnTop, On, % "ahk_id " GroupedWindows[cycleCount]
    WinActivate, % "ahk_id " GroupedWindows[cycleCount]

    WinSet, AlwaysOnTop, Off, % "ahk_id " GroupedWindows[cycleCount]
    Critical, Off
Return

ResetWins:
    If MinimizedWindows.length() > 0 {
        Loop, % MinimizedWindows.length()
        {
            minHwndID := MinimizedWindows[A_Index]
            WinMinimize, ahk_id %minHwndID%
        }
    }
    If (ValidWindows.MaxIndex() >= 4)
        WinActivate, % "ahk_id " ValidWindows[4]
    If (ValidWindows.MaxIndex() >= 3)
        WinActivate, % "ahk_id " ValidWindows[3]
    If (ValidWindows.MaxIndex() >= 2)
        WinActivate, % "ahk_id " ValidWindows[2]
    If (ValidWindows.MaxIndex() >= 1)
        WinActivate, % "ahk_id " ValidWindows[1]
Return

$!Tab::
$!+Tab::
    If !hitTAB {
        Thread, NoTimers, True
        StopRecursion   := True

        ; !Tab overlay sequencing:
        ;   hotkey -> Cycle() picks/activates target -> Overlay_ShowHole(...)
        ;          -> repeated Tab presses call Overlay_MoveHole(...)
        ;          -> release Alt calls Overlay_Hide(...)
        ;
        ; The preview/show fades are modifier-abortable so they stop once the
        ; cycle keys are no longer held. The hide fade is the opposite: it is
        ; allowed to finish after Alt release unless a fresh cycle cancels it.
        firstDraw       := True
        hitTAB          := True

        cycleCount := Cycle()

        If !LclickSelected {
            lastActWinID := GroupedWindows[cycleCount]
            ClearWindowTitlePopup()
        }
        ; tooltip, %cycleCount%
        If !CanceledWinSwap {
            If (cycleCount > 2) {
                startHighlight := True
                Overlay_FadeTo(overlayHwnd, 255, 5)
            }

            GoSub, Altup
        }

        Overlay_Hide(30)

        GoSub, AltupCleanup

        SyncModifierSidesToPhys("Alt")
    }
Return

!sc029::
    If !hitTilde {
        Thread, NoTimers, True
        StopRecursion  := True

        ; !` uses the same overlay flow as !Tab:
        ;   CycleAppWindows() activates the sibling window and calls
        ;   Overlay_ShowHole(...), later ` presses move the existing hole via
        ;   Overlay_MoveHole(...), and release/cancel routes through Overlay_Hide(...).
        firstDraw       := True
        hitTilde        := True
        hitTab          := False

        tildeHwndID := FindTopMostWindow()
        WinGet, activeProcessName, ProcessName, ahk_id %tildeHwndID%
        WinGetClass, activeClassName, ahk_id %tildeHwndID%
        WinGet, allWindows, List
        Loop, %allWindows%
        {
            hwndID := allWindows%A_Index%

            If (MonCount > 1) {
                currentMon := MWAGetMonitorMouseIsIn()
                currentMonHasActWin := IsWindowOnMonNum(hwndID, currentMon)
            }
            Else {
                currentMonHasActWin := True
            }

            If (currentMonHasActWin) {
                If (IsAltTabWindow(hwndID)) {
                    WinGet, state, MinMax, ahk_id %hwndID%
                    If (state > -1) {
                        ValidWindows.push(hwndID)
                    }
                }
            }
        }

        cycleCount := CycleAppWindows(activeProcessName, activeClassName)
        If !LclickSelected {
            lastActWinID := GroupedWindows[cycleCount]
            ClearWindowTitlePopup()
        }

        If !CanceledWinSwap {
            If (cycleCount > 2) {
                startHighlight := True
                Overlay_FadeTo(overlayHwnd, 255, 5)
            }

            GoSub, Altup
        }

        Overlay_Hide(30)

        GoSub, AltupCleanup

        SyncModifierSidesToPhys("Alt")
    }
Return

#If hitTAB || hitTilde
$!x::
    tooltip, Canceled Operation!
    CanceledWinSwap := True
    Gui, GUIHighlighter: Hide
    HideWindowTitlePopup()

    lastActWinID := GroupedWindows[cycleCount]
    WinSet, AlwaysOnTop, Off, ahk_id %lastActWinID%

    GoSub, ResetWins
    Overlay_Hide(30)
    sleep, 1000
    tooltip,
    GoSub, Altup
    GoSub, AltupCleanup
    SyncModifierSidesToPhys("Alt")
Return
#If

$!Lbutton::
    If (hitTab || hitTilde) {
        LclickSelected := True

        MouseGetPos, , , _winIdD,
        WinActivate, ahk_id %_winIdD%
        WinGetTitle, actTitle, ahk_id %_winIdD%
        WinGet, pp, ProcessPath , ahk_id %_winIdD%

        lastActWinID := _winIdD
        startHighlight := True

        WinGetPosEx(_winIdD, wx, wy, ww, wh, null, null)
        Overlay_MoveHole(wx, wy, ww, wh)
        DrawWindowTitlePopup(_winIdD, actTitle, pp)

        Loop
        {
            If (!GetKeyState("Lbutton","P") && !GetKeyState("LAlt","P")) {
                Overlay_FadeTo(overlayHwnd, 255, 10)
                ClearWindowTitlePopup()

                GoSub, Altup

                Overlay_Hide(30)

                GoSub, AltupCleanup

                SyncModifierSidesToPhys("Alt")
                break
            }
            sleep, 5
        }
    }
    Else If (A_PriorHotkey == A_ThisHotkey && (A_TimeSincePriorHotkey < 550)) {
        BeginBlockKeys()
        Send, {LAlt UP}
        Send, {Click, left}
        Send, {ENTER}
        EndBlockKeys()
        sleep, 275
    }
Return

RunDynaWinFind:
    DynaRun(WinFindExpr, Expr_Name)
Return

; RunDynaAltUp:
    ; DynaRun(ExprAltUp, ExprAltUp_Name)
; Return

RunDynaExprTimeout:
    DynaRun(TooltipExpr, ExprTimeout_Name)
Return

RunDynaExprCenter:
    DynaRun(CenterExpr, CenterTimeout_Name)
Return

IsWindowElevated(hwnd)
{
    WinGet, pid, PID, ahk_id %hwnd%
    if (!pid)
    {
        return false
    }
    return IsProcessElevated(pid)
}

IsProcessElevated(pid)
{
    ; Open the process with limited query rights (works more often cross-integrity)
    hProc := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
    if (!hProc)
    {
        ; If we can't even open it, assume it's elevated (or protected) and skip it
        return true
    }

    hToken := 0
    ok := DllCall("Advapi32.dll\OpenProcessToken", "Ptr", hProc, "UInt", 0x0008, "Ptr*", hToken)  ; TOKEN_QUERY
    if (!ok)
    {
        DllCall("CloseHandle", "Ptr", hProc)
        return true
    }

    elevation := 0
    size := 0
    ok := DllCall("Advapi32.dll\GetTokenInformation"
        , "Ptr", hToken
        , "Int", 20                    ; TokenElevation
        , "UInt*", elevation
        , "UInt", 4
        , "UInt*", size)

    DllCall("CloseHandle", "Ptr", hToken)
    DllCall("CloseHandle", "Ptr", hProc)

    if (!ok)
    {
        return true
    }

    return (elevation != 0)
}

; Uses SysGet(SM_CXVSCROLL) to size the right-edge zone.
; extraW lets you widen beyond the system metric (useful for overlay scrollbars).

; Requires your WinGetPosEx() function to be present.

; Uses SysGet(SM_CXVSCROLL) to size the right-edge zone.
; extraW lets you widen beyond the system metric (useful for overlay scrollbars).
IsMouseInVScrollZone_WinGetPosEx_Sys(zonePadTop := 10, zonePadBot := 14
    , extraW := 6
    , ByRef hitHwnd := 0, useRoot := true
    , ByRef winPosX := "", ByRef winPosY := "", ByRef winWidth := "", ByRef winHeight := ""
    , ByRef zoneWidth := "")
{
    isScrollbar := false

    SysGet, scrollWidth, 2
    if (scrollWidth <= 0)
        scrollWidth := 17

    zoneWidth := scrollWidth + extraW

    MouseGetPos, mousePosX, mousePosY, winHwnd
    if (!winHwnd)
        return false

    hitHwnd := winHwnd

    if (useRoot)
    {
        rootHwnd := DllCall("GetAncestor", "ptr", hitHwnd, "uint", 2, "ptr")
        if (rootHwnd)
            hitHwnd := rootHwnd
    }

    WinGetPosEx(hitHwnd, winPosX, winPosY, winWidth, winHeight)

    if (winWidth <= 0 || winHeight <= 0)
        return false

    rightEdge := winPosX + winWidth
    bottomEdge := winPosY + winHeight

    if (mousePosY >= winPosY + zonePadTop && mousePosY < bottomEdge - zonePadBot)
    {
        if (mousePosX >= rightEdge - zoneWidth && mousePosX < rightEdge)
            isScrollbar := true
    }

    if !isScrollbar
    {
        pt := SafeUIA_ElementFromPoint(mousePosX, mousePosY, "", 2000)
        autoId := SafeUIA_GetAutoId(pt)
        if (InStr(autoId, "DownPage", false) || InStr(autoId, "UpPage", false))
            return true
    }

    return isScrollbar
}

Cycle() {
    global ValidWindows, GroupedWindows, MonCount, LclickSelected, CanceledWinSwap, k_Opacity, bufferedCycleAdvance

    prev_exe             :=
    prev_cl              :=
    cycleCount           := 1
    ; Start each Alt+Tab session with an empty buffer. DrawWindowTitlePopup() will set
    ; this if a fast second Tab lands before KeyWait, Tab, D gets a chance to see it.
    bufferedCycleAdvance := False

    DetectHiddenWindows, Off
    failedSwitch := False
    why := ""
    currentMon := MWAGetMonitorMouseIsIn()
    WinGet, actId, ID, A
    WinGet, allWindows, List

    Loop, %allWindows%
    {
        Critical On
        hwndID := allWindows%A_Index%

        If (MonCount > 1) {
            currentMonHasActWin := IsWindowOnMonNum(hwndID, currentMon)
        }
        Else {
            currentMonHasActWin := True
        }

        If (currentMonHasActWin) {
            ; If (!IsWindowElevated(hwndID) && IsAltTabWindow(hwndID)) {
            If (IsAltTabWindow(hwndID)) {
                WinGet, state, MinMax, ahk_id %hwndID%
                If (state > -1) {
                    ValidWindows.push(hwndID)
                    ; If (prev_cl != cl || prev_exe != exe) {
                    GroupedWindows.push(hwndID)

                    If (GroupedWindows.MaxIndex() == 2) {
                        WinActivate, % "ahk_id " hwndID
                        cycleCount := 2
                        If (hwndID == actId) {
                            failedSwitch := True
                        }
                        Else {
                            Critical, Off

                            WinGetPosEx(hwndID, wx, wy, ww, wh, null, null)
                            Overlay_ShowHole(wx, wy, ww, wh, k_Opacity,, 30)

                            If !GetKeyState("LAlt","P")
                                Return 0
                        }
                    }
                    If (GroupedWindows.MaxIndex() == 3 && failedSwitch) {
                        WinActivate, % "ahk_id " hwndID
                        cycleCount := 3
                        Critical, Off

                        Overlay_ShowHole(wx, wy, ww, wh, k_Opacity,, 30)

                        If !GetKeyState("LAlt","P")
                            Return 0
                    }
                    If ((GroupedWindows.MaxIndex() > 3) && (!GetKeyState("LAlt","P"))) {
                        Critical, Off
                        Return 0
                    }
                    ; }
                    ; prev_exe := exe
                    ; prev_cl  := cl
                }
            }
        }
    }
    Critical, Off

    If (GroupedWindows.length() <= 1) {
        tooltip, % "Only " GroupedWindows.length() " Window to Show..."
        sleep, 1000
        tooltip,
        Return 1
    }
    gwHwndId   := GroupedWindows[cycleCount]

    KeyWait, Tab, U

    If !GetKeyState("LAlt","P")
        Return 0

    ; WinGetTitle, tits, ahk_id %gwHwndId%
    WinGet, pp, ProcessPath , ahk_id %gwHwndId%
    tits := GetAppDisplayNameFromHwnd(gwHwndId)
    DrawWindowTitlePopup(gwHwndId, tits, pp)

    Loop
    {
        If LclickSelected || CanceledWinSwap
            break

        If (GroupedWindows.length() >= 2)
        {
            ; A quick second Tab can happen while DrawWindowTitlePopup() is still running.
            ; If that happened, consume the buffered press here instead of waiting for a new one.
            bufferedAdvance      := bufferedCycleAdvance
            bufferedCycleAdvance := False
            If !bufferedAdvance
                KeyWait, Tab, D T0.1

            If (bufferedAdvance || !ErrorLevel)
            {
                If !GetKeyState("LShift","P") {
                    If (cycleCount == GroupedWindows.MaxIndex())
                        cycleCount := 1
                    Else
                        cycleCount += 1
                }
                Else If GetKeyState("LShift","P") {
                    If (cycleCount == 1)
                        cycleCount := GroupedWindows.MaxIndex()
                    Else
                        cycleCount -= 1
                }

                gwHwndId := GroupedWindows[cycleCount]
                WinActivate,   ahk_id %gwHwndId%
                WinGetPosEx(gwHwndId, wx, wy, ww, wh, null, null)
                Overlay_MoveHole(wx, wy, ww, wh)

                KeyWait, Tab, U

                ; WinGetTitle, tits,ahk_id %gwHwnd%
                WinGet, pp, ProcessPath , ahk_id %gwHwndId%
                tits := GetAppDisplayNameFromHwnd(gwHwndId)
                DrawWindowTitlePopup(gwHwndId, tits, pp)
            }
        }
    }
    until (!GetKeyState("LAlt", "P"))

    Return cycleCount
}

; Switch "App" open windows based on the same process and class
CycleAppWindows(activeProcessName, activeClass) {

    global MonCount, GroupedWindows, MinimizedWindows, LclickSelected, startHighlight, k_Opacity, bufferedCycleAdvance

    activeCurrentMonitorWindowIndex := 0
    CurrentMonitorMinimizedWindows  := []
    CurrentMonitorWindows           := []
    OtherMonitorMinimizedWindows    := []
    windowsToMinimize               := []
    ; Same buffering idea as Cycle(): Alt+` can miss a fast repeat while the popup GUI is drawing.
    bufferedCycleAdvance            := False
    currentMon                      := MWAGetMonitorMouseIsIn()
    cycleCount                      := 2
    GroupedWindows                  := [] ; GroupedWindows = [active visible, other visible, current-monitor minimized, other-monitor minimized]
    MinimizedWindows                := []

    UpdateValidWindows()

    WinGet, activeHwndID, ID, A
    WinGet, windowsListWithSameProcessAndClass, List, ahk_exe %activeProcessName% ahk_class %activeClass%

    ; Build three explicit cycle phases:
    ; 1) visible sibling windows on the current monitor
    ; 2) minimized sibling windows whose restored monitor is the current monitor
    ; 3) minimized sibling windows whose restored monitor is another monitor
    ; This keeps minimized windows out of the cycle until the visible current-
    ; monitor sibling windows have already been shown.
    Critical, On
    Loop, %windowsListWithSameProcessAndClass%
    {
        hwndID := windowsListWithSameProcessAndClass%A_Index%
        WinGetTitle, tit, ahk_id %hwndID%
        WinGet, mmState, MinMax, ahk_id %hwndID%

        If (mmState == -1) {
            ; Minimized windows are classified by the monitor they would restore
            ; onto, not by their current minimized icon state.
            restoredMon := GetWindowMonitorNumber(hwndID)
            If (restoredMon = currentMon)
                CurrentMonitorMinimizedWindows.Push(hwndID)
            Else
                OtherMonitorMinimizedWindows.Push(hwndID)
            continue
        }

        If (MonCount > 1) {
            currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
        }
        Else {
            currentMonHasActWin := True
        }

        If (currentMonHasActWin && tit != "")
            CurrentMonitorWindows.Push(hwndID)
    }
    ; Rotate phase 1 so the active window becomes GroupedWindows[1]. Since the
    ; cycle starts from slot 2, the first Alt+` advance lands on the next visible
    ; current-monitor sibling window instead of immediately restoring a minimized
    ; sibling from phases 2 or 3.
    for idx, grpHwndID in CurrentMonitorWindows {
        If (grpHwndID = activeHwndID) {
            activeCurrentMonitorWindowIndex := idx
            break
        }
    }
    If (activeCurrentMonitorWindowIndex > 0) {
        ; Rebuild phase 1 starting from the active visible sibling window.
        ; This makes GroupedWindows[1] the active window, so the existing
        ; cycleCount := 2 startup behavior advances first to the next visible
        ; current-monitor sibling instead of jumping into a minimized phase.
        Loop, % CurrentMonitorWindows.Length()
        {
            ; Walk forward from the active window's array position and wrap back
            ; to the front once we pass the end. The result is a rotated copy of
            ; CurrentMonitorWindows that preserves the original sibling order.
            reorderedIndex := activeCurrentMonitorWindowIndex + A_Index - 1
            If (reorderedIndex > CurrentMonitorWindows.Length())
                reorderedIndex := reorderedIndex - CurrentMonitorWindows.Length()
            GroupedWindows.Push(CurrentMonitorWindows[reorderedIndex])
        }
    }
    Else {
        for idx, grpHwndID in CurrentMonitorWindows
            GroupedWindows.Push(grpHwndID)
    }
    ; Append the minimized phases only after the visible phase. MinimizedWindows
    ; tracks exactly which windows should be returned to the minimized state when
    ; the user releases Alt after previewing them in the cycle.
    for idx, minHwndID in CurrentMonitorMinimizedWindows {
        GroupedWindows.Push(minHwndID)
        MinimizedWindows.Push(minHwndID)
    }
    for idx, minHwndID in OtherMonitorMinimizedWindows {
        GroupedWindows.Push(minHwndID)
        MinimizedWindows.Push(minHwndID)
    }
    Critical, Off

    numWindows := GroupedWindows.length()
    If (numWindows <= 1) {
        Loop, 100
        {
            Tooltip, Only %numWindows% Window(s) found!
            sleep, 10
        }
        Tooltip,
        Return
    }

    gwHwndId := GroupedWindows[cycleCount] ; get ready to activate next window

    WinGet, mmState, MinMax, ahk_id %gwHwndId%
    If (MonCount > 1 && mmState == -1) {
        windowsToMinimize.push(GroupedWindows[cycleCount])
    }
    WinActivate, ahk_id %gwHwndId%

    WinGetPosEx(gwHwndId, wx, wy, ww, wh, null, null)
    Overlay_ShowHole(wx, wy, ww, wh, k_Opacity,, 30)

    lastActWinID := gwHwndId

    KeyWait, ``, U

    If !GetKeyState("LAlt","P")
        Return 0

    WinGetTitle, tits, ahk_id %gwHwndId%
    WinGet, pp, ProcessPath , ahk_id %gwHwndId%
    DrawWindowTitlePopup(gwHwndId, tits, pp)

    cycleCount++
    If (cycleCount > numWindows) {
        cycleCount := 1
    }
    gwHwndId   := GroupedWindows[cycleCount]

    Loop
    {
        If LclickSelected || CanceledWinSwap
            break

        ; Consume any cycle key that arrived during DrawWindowTitlePopup() before waiting
        ; on a brand-new ` press. This is what prevents the missed second-key problem.
        bufferedAdvance      := bufferedCycleAdvance
        bufferedCycleAdvance := False
        If !bufferedAdvance
            KeyWait, ``, D T0.1

        If (bufferedAdvance || !ErrorLevel)
        {
            WinGet, mmState, MinMax, ahk_id %gwHwndId%
            If (MonCount > 1 && mmState == -1) {
                windowsToMinimize.push(gwHwndId)
            }
            WinActivate, ahk_id %gwHwndId%

            WinGetPosEx(gwHwndId, wx, wy, ww, wh, null, null)
            Overlay_MoveHole(wx, wy, ww, wh)

            lastActWinID := gwHwndId

            KeyWait, ``, U

            WinGetTitle, tits, ahk_id %gwHwndId%
            WinGet, pp, ProcessPath , ahk_id %gwHwndId%
            DrawWindowTitlePopup(gwHwndId, tits, pp)

            cycleCount++
            If (cycleCount > numWindows) {
                cycleCount := 1
            }
            gwHwndId   := GroupedWindows[cycleCount]

            Loop
            {
                WinGet, mmState, MinMax, ahk_id %gwHwndId%
                ; Flattening the three phases into GroupedWindows means phase 3 can
                ; legally contain minimized windows restored to another monitor.
                ; Only visible windows are still constrained to the current monitor.
                If (mmState > -1 && !IsWindowOnMonNum(gwHwndId, currentMon)) {
                    cycleCount++
                    If (cycleCount > numWindows)
                        cycleCount := 1
                    gwHwndId := GroupedWindows[cycleCount]
                }
                Else
                    break
            }
        }
    }
    until (!GetKeyState("LAlt", "P"))

    Loop, % windowsToMinimize.length()
    {
        tempId := windowsToMinimize[A_Index]
        If (tempId != lastActWinID) {
            WinMinimize, ahk_id %tempId%
            sleep, 100
        }
        Else {
            If !IsWindowOnMonNum(tempId, currentMon) {
                WinActivate, ahk_id %tempId%
                Send, #+{Left}
            }
        }
    }

    cycleCount := cycleCount - 1 ; correct for final increment of cycleCount++
    If (cycleCount <= 0)
        cycleCount := GroupedWindows.MaxIndex()

    Return cycleCount
}

; https://superuser.com/questions/1603554/autohotkey-find-and-focus-windows-by-name-accross-virtual-desktops
$~Ctrl::
    GoSub, LaunchWinFind
Return

RegExEscape(s) {
    return RegExReplace(s, "([\\.^$|?*+(){}\[\]-])", "\$1")
}

LaunchWinFind:
    If (A_PriorHotkey = "$~Ctrl" && A_TimeSincePriorHotkey < (0.75*(k_DoubleClickTime/2))) {
        StopRecursion   := True
        SetTimer, KeyTrack,   Off
        ; SetTimer, MouseTrack, Off

        UserInputTrimmed :=
        StopCheck        := False
        SearchingWindows := True
        SetTimer, UpdateInputBoxTitle, 5
        InputBox, UserInput, Type Up to 3 Letters of a Window Title to Search, , , 340, 100, CoordXCenterScreen()-(340/2), CoordYCenterScreen()-(100/2)
        SetTimer, UpdateInputBoxTitle, off

        If ErrorLevel
        {
            StopRecursion    := False
            SearchingWindows := False
            GoSub, EnableTimers
            Return
        }
        Else
        {
            DetectHiddenWindows, On
            totalMenuItemCount := 0
            onlyTitleFound     := ""
            allWinArray        := []
            winAssoc           := {}
            winArraySort       := []

            SetTitleMatchMode, RegEx
            needle := "i)" . RegExEscape(UserInputTrimmed)  ; contains, case-insensitive
            WinGet, id, List, % needle

            SetTitleMatchMode, 3
            SetTitleMatchMode, Fast
            totalCount := id
            Loop, %id%
            {
                this_ID := id%A_Index%

                If !JEE_WinHasAltTabIcon(this_ID)
                    continue

                WinGetTitle, title, ahk_id %this_ID%
                WinGet, procName, ProcessName , ahk_id %this_ID%
                desknum := findDesktopWindowIsOn(this_ID)

                If desknum <= 0
                    continue
                finalTitle := % "Desktop " desknum " ↑ " procName " ↑ " title "^" this_ID
                allWinArray.Push(finalTitle)
            }

            If (allWinArray.length() == 0) {
                ToolTip, % "No matches found for """ UserInputTrimmed """ out of " totalCount "..."
                Sleep, 1500
                Tooltip,

                StopRecursion := False
                SearchingWindows := False
                GoSub, EnableTimers
                Return
            }

            Critical On
            For k, v in allWinArray
            {
                winAssoc[v] := k
            }

            For k, v in winAssoc
            {
                winArraySort.Push(k)
            }

            desktopEntryLast := ""

            Menu, windows, Add
            Menu, windows, deleteAll
            For k, ft in winArraySort
            {
                splitEntry1 := StrSplit(ft , "^")
                entry := splitEntry1[1]
                ahkid := splitEntry1[2]

                WinGet, minState, MinMax, ahk_id %ahkid%

                splitEntry2    := StrSplit(entry, "↑")
                desktopEntry   := splitEntry2[1]
                procEntry      := Trim(splitEntry2[2])
                titleEntry     := Trim(splitEntry2[3])

                WinGet, Path, ProcessPath, ahk_exe %procEntry%
                If (minState == -1 )
                    finalEntry   := % desktopEntry ":  [" titleEntry "] (" procEntry ")"
                Else
                    finalEntry   := % desktopEntry ":  " titleEntry " (" procEntry ")"

                If (desktopEntryLast != ""  && (desktopEntryLast != desktopEntry)) {
                    Menu, windows, Add
                }
                If (finalEntry != "" && titleEntry != "") {
                    totalMenuItemCount := totalMenuItemCount + 1
                    onlyTitleFound := finalEntry

                    Menu, windows, Add, %finalEntry%, ActivateWindow
                    Try
                        Menu, windows, Icon, %finalEntry%, %Path%,, 32
                    Catch
                        Menu, windows, Icon, %finalEntry%, %A_WinDir%\System32\SHELL32.dll, 3, 32
                }
                desktopEntryLast := desktopEntry
            }
            Critical Off

            If (totalMenuItemCount == 1 && onlyTitleFound != "") {
                ; tooltip, total found windows : %totalMenuItemCount%
                GoSub, ActivateWindow
            }
            Else If (totalMenuItemCount > 1) {
                SetTimer, RunDynaWinFind, -1

                CoordMode, Mouse, Screen
                CoordMode, Menu, Screen
                ; https://www.autohotkey.com/boards/viewtopic.php?style=17&t=107525#p478308
                drawX := CoordXCenterScreen()
                drawY := CoordYCenterScreen()
                Gui, ShadowFrFull:  Show, x%drawX% y%drawY% h0 w0
                ; Gui, ShadowFrFull2: Show, x%drawX% y%drawY% h1 y1
                ; sleep, 100
                ; Menu, windows, show, % A_ScreenWidth/4, % A_ScreenHeight/3
                ShowMenuX("windows", drawX, drawY, 0x14)
                ; Gui, ShadowFrFull:  Hide
                Menu, windows, deleteAll
            }
            Else {
                Loop,100 {
                    tooltip, No windows found!
                    sleep, 10
                }
                tooltip,
            }
        }

        SearchingWindows := False
        StopRecursion    := False
        GoSub, EnableTimers
    }
    KeyWait, Ctrl, U T10
Return

ActivateWindow:
    Gui, ShadowFrFull:  Hide
    DetectHiddenWindows, On
    thisMenuItem := ""
    result       := {}
    CalcID       :=

    If (totalMenuItemCount == 1 && onlyTitleFound != "")
        thisMenuItem := onlyTitleFound
    Else
        thisMenuItem := A_ThisMenuItem

    fulltitle := RegExReplace(thisMenuItem, "\(\S+\.\S+\)$", "")
    fulltitle := Trim(fulltitle)
    ; msgbox, %fulltitle%
    fulltitle := RegExReplace(fulltitle, "^Desktop\s\d+\s*\:\s?", "")
    fulltitle := Trim(fulltitle)
    RegExMatch(fulltitle, "O)(\]$)", result)
    ; msgbox, % fulltitle " with " result.Count()
    If (result.Count() > 0) {
        fulltitle := RegExReplace(fulltitle, "^\[", "")
        fulltitle := Trim(fulltitle)
        fulltitle := RegExReplace(fulltitle, "\]?\s*$", "")
        fulltitle := Trim(fulltitle)
    }

    If (fulltitle == "Calculator") {
        ; https://www.autohotkey.com/boards/viewtopic.php?t=43997
        WinGet, CalcIDs, List, Calculator
        If (CalcIDs = 1) ; Calc is NOT minimized
            CalcID := CalcIDs1
        Else
            CalcID := CalcIDs2 ; Calc is Minimized use 2nd ID
        WinActivate, ahk_id %CalcID%
        WinSet, AlwaysOnTop, On, ahk_id %CalcID%
    }
    Else {
        WinActivate, %fulltitle%
        WinSet, AlwaysOnTop, On, %fulltitle%
    }

    If (CalcID)
        WinGet, hwndOfTitle, ID, %CalcID%
    Else
        WinGet, hwndOfTitle, ID, %fulltitle%

    ; DrawBlackMonitor_aot(hwndOfTitle)
    WinGetPosEx(hwndOfTitle, wx, wy, ww, wh, null, null)
    Overlay_ShowHole(wx, wy, ww, wh, k_Opacity,, 60)

    WinGet, actWinState, MinMax, %fulltitle%
    If (actWinState == -1)
        sleep, 125

    sleep, 400
    Overlay_Hide(30)

    Process, Close, Expr_Name
    Process, Close, ExprAltUp_Name

    If IsAlwaysOnTop(hwndOfTitle)
        WinSet, AlwaysOnTop, Off, ahk_id %hwndOfTitle%

Return

; ========================================================================================================
; ------------------------------------  Drawing Functions ------------------------------------------------
; ========================================================================================================
ClearRect(hwnd := "") {
    global DrawingRect, Highlighter, GUIHighlighter

    If DrawingRect {
        Critical, On
        Loop, 5
        {
            DrawingRect := False
            If (GetKeyState("LAlt", "P") || GetKeyState("LButton", "P")) {
                Critical, Off
                Gui, GUIHighlighter: Hide
                WinSet, Transparent, 255, ahk_id %Highlighter%
                WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
                Return
            }
            WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
            sleep, 5
        }

        decrement_amount := 15
        Loop, % floor(255/decrement_amount)
        {
            current_trans := 255-(decrement_amount * A_Index)
            WinSet, Transparent, %current_trans%, ahk_id %Highlighter%
            If (GetKeyState("LAlt", "P") || GetKeyState("LButton", "P")) {
                Critical, Off
                Gui, GUIHighlighter: Hide
                WinSet, Transparent, 255, ahk_id %Highlighter%
                WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
                Return
            }
            If (hwnd != "" && !WinExist("ahk_id " . hwnd)) {
                Critical, Off
                Gui, GUIHighlighter: Hide
                WinSet, Transparent, 255, ahk_id %Highlighter%
                WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
                Return
            }
            WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
            sleep 10
        }
        Gui, GUIHighlighter: Hide
        Critical, Off
    }
Return
}

; https://www.autohotkey.com/boards/viewtopic.php?t=110505
DrawRect:
    Gui, GUIHighlighter: Hide
    DrawingRect := True
    WinGet, activeWin, ID, A
    x := y := w := h := 0
    WinGetPosEx(activeWin, x, y, w, h)

    If (x="")
        Return

    borderType := "inside"                ; set to inside, outside, or both

    If (borderType = "outside") {
        outerX      := 0
        outerY      := 0
        outerX2     := w+2*k_border_thickness
        outerY2     := h+2*k_border_thickness

        innerX      := k_border_thickness
        innerY      := k_border_thickness
        innerX2     := k_border_thickness+w
        innerY2     := k_border_thickness+h

        newX        := x-k_border_thickness
        newY        := y-k_border_thickness
        newW        := w+2*k_border_thickness
        newH        := h+2*k_border_thickness

    } Else If (borderType="inside") {
        ; WinGet, myState, MinMax, A
        ; If (myState == 1)
            ; offset:=8
        ; Else
        offset      := 0

        outerX      := offset
        outerY      := offset
        outerX2     := w-offset
        outerY2     := h-offset

        innerX      := k_border_thickness+offset
        innerY      := k_border_thickness+offset
        innerX2     := w-k_border_thickness-offset
        innerY2     := h-k_border_thickness-offset

        newX        := x
        newY        := y
        newW        := w
        newH        := h

    } Else If (borderType="both") {
        outerX      := 0
        outerY      := 0
        outerX2     := w+2*k_border_thickness
        outerY2     := h+2*k_border_thickness

        innerX      := k_border_thickness*2
        innerY      := k_border_thickness*2
        innerX2     := w
        innerY2     := h

        newX        := x-k_border_thickness
        newY        := y-k_border_thickness
        newW        := w+4*k_border_thickness
        newH        := h+4*k_border_thickness
    }

    Critical, On
    Gui,GUIHighlighter: Show, w%newW% h%newH% x%newX% y%newY% NA, Table awaiting Action
    WinSet, Region, %outerX%-%outerY%  %outerX2%-%outerY%  %outerX2%-%outerY2%  %outerX%-%outerY2%  %outerX%-%outerY%  %innerX%-%innerY%  %innerX2%-%innerY%  %innerX2%-%innerY2%  %innerX%-%innerY2%  %innerX%-%innerY%, ahk_id %Highlighter%

    WinSet, Transparent, Off, ahk_id %Highlighter%
    WinSet, AlwaysOnTop, Off, ahk_id %Highlighter%
    WinSet, AlwaysOnTop, On, ahk_id %Highlighter%
    WinActivate, ahk_id %activeWin%
    Critical, Off
Return
; ------------------  ChatGPT ------------------------------------------------------------------
; ========================================================================================================
; ------------------------------------  Pixel Measure Tool -----------------------------------------------
; ========================================================================================================
Measure_UpdateTick:
    ; Keep the timer label tiny and delegate the real work to the function so the
    ; measurement logic stays in one place.
    Measure_Update()
Return

; Start the isolated pixel-measure drag tool at the current mouse position and arm
; a fast timer so the two orthogonal guide legs track smoothly while LButton stays down.
Measure_Begin() {
    global measureActive, measureStartX, measureStartY

    if (measureActive)
        return

    ; Read the drag origin in screen coordinates so the guides line up with the
    ; always-on-top GUIs regardless of which window is under the cursor.
    oldCoordModeMouse := A_CoordModeMouse
    CoordMode, Mouse, Screen
    MouseGetPos, measureStartX, measureStartY
    CoordMode, Mouse, %oldCoordModeMouse%

    ; Build the GUIs on first use, draw one frame immediately, then let the timer
    ; keep the overlay in sync until LButton is released.
    measureActive := True
    Measure_EnsureGui()
    Measure_Update()
    SetTimer, Measure_UpdateTick, 10
}

; Hide the measurement guides and stop the drag timer so the tool leaves no overlay
; behind after the mouse button is released.
Measure_End() {
    global measureActive, measureGuiReady

    measureActive := False
    SetTimer, Measure_UpdateTick, Off

    if (!measureGuiReady)
        return

    ; Hide all three windows together so a partial overlay never gets left behind.
    Gui, GUIMeasureH: Hide
    Gui, GUIMeasureText: Hide
    Gui, GUIMeasureV: Hide
}

; Lazily create the small click-through GUIs used by the measurement tool so the
; feature stays self-contained and does not interfere with Overlay_* or GUIHighlighter.
Measure_EnsureGui() {
    global MeasureText, measureGuiReady

    if (measureGuiReady)
        return

    ; Horizontal guide: spans from the drag origin to the current X position.
    Gui, GUIMeasureH: New
    Gui, GUIMeasureH: +AlwaysOnTop +ToolWindow -Caption -DPIScale +E0x20 +LastFound
    Gui, GUIMeasureH: Color, FFAA00
    WinSet, Transparent, 210

    ; Vertical guide: drops from the horizontal endpoint to the current Y position.
    Gui, GUIMeasureV: New
    Gui, GUIMeasureV: +AlwaysOnTop +ToolWindow -Caption -DPIScale +E0x20 +LastFound
    Gui, GUIMeasureV: Color, FFAA00
    WinSet, Transparent, 210

    ; Readout window: shows the live horizontal and vertical pixel distances.
    Gui, GUIMeasureText: New
    Gui, GUIMeasureText: +AlwaysOnTop +ToolWindow -Caption -DPIScale +Border +E0x20 +LastFound
    Gui, GUIMeasureText: Color, 111111
    Gui, GUIMeasureText: Font, s10 cFFFFFF, Segoe UI
    Gui, GUIMeasureText: Margin, 8, 4
    Gui, GUIMeasureText: Add, Text, vMeasureText, X: 0 px | Y: 0 px

    measureGuiReady := True
}

; Recompute the current mouse delta, resize the horizontal and vertical guide legs,
; and refresh the live pixel readout until the physical LButton is released.
Measure_Update() {
    global MeasureText, measureActive, measureStartX, measureStartY, k_measureThickness

    if (!measureActive)
        return

    if (!GetKeyState("LButton", "P")) {
        Measure_End()
        return
    }

    ; Re-read the cursor in screen space so the overlay math matches the GUI
    ; positions exactly.
    oldCoordModeMouse := A_CoordModeMouse
    CoordMode, Mouse, Screen
    MouseGetPos, curX, curY
    CoordMode, Mouse, %oldCoordModeMouse%

    ; Signed deltas are kept for geometry, while the on-screen label shows the
    ; absolute distance in each axis.
    dx := curX - measureStartX
    dy := curY - measureStartY

    ; The horizontal leg always starts at the lesser X so it renders correctly
    ; whether the drag moves left or right.
    hX := (dx >= 0) ? measureStartX : curX
    hY := measureStartY - Floor(k_measureThickness / 2)
    hW := Abs(dx) + 1

    ; The vertical leg is anchored at the current X so the two guides form a clean
    ; L-shape that ends exactly at the cursor.
    vX := curX - Floor(k_measureThickness / 2)
    vY := (dy >= 0) ? measureStartY : curY
    vH := Abs(dy) + 1

    ; Resize and reposition the two guide windows in place instead of recreating
    ; them on every tick.
    Gui, GUIMeasureH: Show, % "x" hX " y" hY " w" hW " h" k_measureThickness " NA"
    Gui, GUIMeasureV: Show, % "x" vX " y" vY " w" k_measureThickness " h" vH " NA"

    ; Keep the readout near the cursor so the measurement stays readable while dragging.
    GuiControl, GUIMeasureText:, MeasureText, % "X: " Abs(dx) " px | Y: " Abs(dy) " px"
    Gui, GUIMeasureText: Show, % "x" (curX + 18) " y" (curY + 18) " NA AutoSize"
}

ClampAlpha(alphaValue) {
    if (alphaValue < 0)
        return 0
    if (alphaValue > 255)
        return 255

    return alphaValue
}

; alphaPrimary is the transparency of the top window.
; alphaTarget is the final combined opacity you want after both windows are layered.
; The function first clamps both values into the valid 0..255 range.
; It figures out how much of the background still shows through the first window.
; Then it computes how transparent the second window must be so the total visible background matches the target.
; It clamps that result to a valid range, converts it back to an AHK alpha value, rounds it, and returns it.
Get2ndAlphaForTransparencyTarget(alphaPrimary, alphaTarget) {
    ; alphaPrimary: 0..255 (WinSet alpha for primary window)
    ; alphaTarget:  0..255 (desired combined opacity of the two stacked windows)

    alphaPrimary := ClampAlpha(alphaPrimary)
    alphaTarget := ClampAlpha(alphaTarget)

    remainingPrimary255 := 255 - alphaPrimary
    requiredBackground255 := 255 - alphaTarget  ; how much background must still show through both

    ; If primary is fully opaque, combined opacity is forced to 255 no matter what the other is.
    if (remainingPrimary255 <= 0)
    {
        return (alphaTarget = 255) ? 0 : 0
    }

    ; backgroundThroughOther = requiredBackground / remainingPrimary
    remainingOther := requiredBackground255 / (remainingPrimary255 * 1.0)

    ; Clamp to [0,1]
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

; ------------------------------------------------------------
; Shows an existing (already-created) Overlay GUI and updates
; the hole rectangle + transparency without recreating the GUI.
;
; Notes:
; - Assumes the GUI and the Progress control already exist.
; - Changing clickThrough is supported via ExStyle toggling.
; - If you need to change overlayColor dynamically, we set it here.
; ------------------------------------------------------------
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

Overlay_CancelFade() {
    global overlayFadeToken
    ; Every new show/hide request bumps the token so older fade loops stop
    ; writing alpha immediately. This prevents two overlapping animations from
    ; fighting each other and producing flicker or abrupt opacity jumps.
    overlayFadeToken++
    return overlayFadeToken
}

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

Overlay_GetWorkArea(monNum, ByRef areaLeft, ByRef areaTop, ByRef areaRight, ByRef areaBottom) {
    ; SysGet MonitorWorkArea returns variables: MonLeft/Top/Right/Bottom
    SysGet, monArea, MonitorWorkArea, %monNum%
    areaLeft   := monAreaLeft
    areaTop    := monAreaTop
    areaRight  := monAreaRight
    areaBottom := monAreaBottom

    ; SysGet, monFull, Monitor, %monNum%
    ; MsgBox, % "Full Left: " monFullLeft
        ; . "`nFull Top: " monFullTop
        ; . "`nFull Right: " monFullRight
        ; . "`nFull Bottom: " monFullBottom
        ; . "`nWork Left: " monAreaLeft
        ; . "`nWork Top: " monAreaTop
        ; . "`nWork Right: " monAreaRight
        ; . "`nWork Bottom: " monAreaBottom
}

Overlay_ShowHole(holePosX, holePosY, holeSizeW, holeSizeH, overlayAlpha := 180, clickThrough := True, fadeMs := 100) {
    global overlayHwnd, overlayIsReady, overlayAlphaCurrent
    static HWND_TOPMOST   := -1
    static SWP_NOMOVE     := 0x0002
    static SWP_NOACTIVATE := 0x0010
    static SWP_NOSIZE     := 0x0001
    static SWP_SHOWWINDOW := 0x0040

    if (!overlayIsReady || !overlayHwnd || !DllCall("IsWindow", "ptr", overlayHwnd))
        return 0

    ; Stop any older show/hide fade before positioning the next preview. This
    ; keeps the new overlay from inheriting stale alpha writes from the previous
    ; cycle and removes the "rubber-band" feeling during rapid window switching.
    Overlay_CancelFade()

    If !GetKeyState("LAlt","P") && !GetKeyState("Esc","P")
        return 0

    ; Toggle click-through.
    if (clickThrough)
        WinSet, ExStyle, +0x20, ahk_id %overlayHwnd%
    else
        WinSet, ExStyle, -0x20, ahk_id %overlayHwnd%

    ; Pick the monitor from the mouse position.
    monNum := MWAGetMonitorMouseIsIn()
    Overlay_GetWorkArea(monNum, areaLeft, areaTop, areaRight, areaBottom)

    areaWidth  := areaRight  - areaLeft
    areaHeight := areaBottom - areaTop

    ; Reject invalid work area.
    if (areaWidth <= 0 || areaHeight <= 0) {
        Gui, Overlay:Hide
        overlayAlphaCurrent := 0
        return 0
    }

    If !GetKeyState("LAlt","P") && !GetKeyState("Esc","P")
        return 0

    ; Incoming hole rectangle is in screen coordinates.
    holeLeft     := holePosX
    holeTop      := holePosY
    holeRight    := holePosX + holeSizeW
    holeBottom   := holePosY + holeSizeH

    ; Track whether any portion of the requested hole lies outside the current monitor.
    shouldRedraw := False
    if (holeLeft < areaLeft)
        shouldRedraw := True
    else if (holeTop < areaTop)
        shouldRedraw := True
    else if (holeRight > areaRight)
        shouldRedraw := True
    else if (holeBottom > areaBottom)
        shouldRedraw := True

    If !GetKeyState("LAlt","P") && !GetKeyState("Esc","P")
        return 0

    ; Intersect the hole rectangle with the selected monitor's work area.
    ; This is what makes non-zero monitor origins and negative coords safe.
    clipLeft     := (holeLeft > areaLeft) ? holeLeft : areaLeft
    clipTop      := (holeTop > areaTop) ? holeTop : areaTop
    clipRight    := (holeRight < areaRight) ? holeRight : areaRight
    clipBottom   := (holeBottom < areaBottom) ? holeBottom : areaBottom

    clippedHoleW := clipRight  - clipLeft
    clippedHoleH := clipBottom - clipTop

    ; If the window does not overlap the mouse monitor's work area,
    ; hide the overlay instead of covering the window.
    if (clippedHoleW <= 0 || clippedHoleH <= 0) {
        Gui, Overlay:Hide
        overlayAlphaCurrent := 0
        return 0
    }

    If !GetKeyState("LAlt","P") && !GetKeyState("Esc","P")
        return 0

    ; Show overlay exactly over the selected monitor's work area.
    ; Keeping the overlay sized to the active monitor minimizes the surface area
    ; Windows has to composite on each alpha step, which helps the fade feel more
    ; immediate and reduces the chance of cross-monitor redraw artifacts.
    Gui, Overlay:Show, % "x" areaLeft " y" areaTop " w" areaWidth " h" areaHeight " NA"
    ; Reassert this dimmer HWND in the topmost band each time it is shown so the
    ; retained WindowTitle popup cannot leave the hole-overlay visually buried.
    DllCall("user32\SetWindowPos"
        , "ptr", overlayHwnd
        , "ptr", HWND_TOPMOST
        , "int", 0
        , "int", 0
        , "int", 0
        , "int", 0
        , "uint", SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW)

    ; If currently transparent, reset alpha baseline.
    ; This guarantees the fade always starts from a known invisible state after a
    ; hide, rather than briefly reusing an older partially visible alpha level.
    if (overlayAlphaCurrent < 1)
        Overlay_SetAlpha(overlayHwnd, 0)

    ; Convert clipped screen coords to overlay-relative coords.
    ; This correctly handles monitors whose origin is not 0,0.
    holeRelX := clipLeft - areaLeft
    holeRelY := clipTop  - areaTop

    ; Update the cut-out before the fade ramps in so the first visible frame is
    ; already aligned to the target window. That avoids a one-frame flash where a
    ; full-screen dimmer appears before the hole is carved out.
    Overlay_SetHoleRegion_WorkArea(overlayHwnd, areaWidth, areaHeight, holeRelX, holeRelY, clippedHoleW, clippedHoleH)

    ; Force repaint only if part of the requested hole was outside the monitor edges.
    ; Redrawing only on geometry edge cases avoids unnecessary extra paint work on
    ; every cycle step, which helps the repeated overlay moves stay fluid.
    if (shouldRedraw)
        WinSet, Redraw,, ahk_id %overlayHwnd%

    If !GetKeyState("LAlt","P") && !GetKeyState("Esc","P")
        return 0

    ; Fade from the current alpha instead of toggling visibility in one shot so
    ; the overlay eases in smoothly even when the previous cycle left it mid-fade.
    Overlay_FadeTo(overlayHwnd, overlayAlpha, fadeMs, overlayAlphaCurrent)

    return overlayHwnd
}

Overlay_SetHoleRegion_WorkArea(overlayHwnd, areaWidth, areaHeight, holeX, holeY, holeW, holeH) {
    local regFull
    local regHole
    local holeRight
    local holeBottom

    ; Clamp overlay bounds.
    if (areaWidth < 1 || areaHeight < 1)
        return 0

    ; Clamp hole origin.
    if (holeX < 0)
        holeX := 0
    if (holeY < 0)
        holeY := 0

    ; Clamp hole size.
    if (holeW < 0)
        holeW := 0
    if (holeH < 0)
        holeH := 0

    holeRight := holeX + holeW
    holeBottom := holeY + holeH

    ; Clamp hole extents to overlay bounds.
    if (holeRight > areaWidth)
        holeRight := areaWidth
    if (holeBottom > areaHeight)
        holeBottom := areaHeight

    ; Create region covering the full overlay.
    regFull := DllCall("gdi32\CreateRectRgn"
        , "int", 0
        , "int", 0
        , "int", areaWidth
        , "int", areaHeight
        , "ptr")

    ; Create the hole region.
    regHole := DllCall("gdi32\CreateRectRgn"
        , "int", holeX
        , "int", holeY
        , "int", holeRight
        , "int", holeBottom
        , "ptr")

    ; Subtract the hole from the full region.
    ; This updates the visible "donut" shape on the same overlay HWND, which is
    ; smoother than destroying and rebuilding a GUI around the highlighted window
    ; every time the selection changes.
    DllCall("gdi32\CombineRgn"
        , "ptr", regFull
        , "ptr", regFull
        , "ptr", regHole
        , "int", 4) ; RGN_DIFF

    ; Apply the region to the overlay.
    ; Windows takes ownership of regFull after SetWindowRgn succeeds.
    ; Because the region swap happens in-place on the existing overlay window, the
    ; hole can track the selection with much less visual popping than a hide/show
    ; approach.
    DllCall("user32\SetWindowRgn"
        , "ptr", overlayHwnd
        , "ptr", regFull
        , "int", True)

    ; We still own regHole and must delete it.
    DllCall("gdi32\DeleteObject", "ptr", regHole)

    return 1
}

Overlay_MoveHole(holePosX := "", holePosY := "", holeSizeW := "", holeSizeH := "", doRedraw := True) {
    global overlayHwnd, overlayIsReady
    static HWND_TOPMOST   := -1
    static SWP_NOMOVE     := 0x0002
    static SWP_NOACTIVATE := 0x0010
    static SWP_NOSIZE     := 0x0001
    static SWP_SHOWWINDOW := 0x0040

    static lastHolePosX  := 0
    static lastHolePosY  := 0
    static lastHoleSizeW := 0
    static lastHoleSizeH := 0
    static hasLastHole   := False

    if (!overlayIsReady || !overlayHwnd || !DllCall("IsWindow", "ptr", overlayHwnd))
        return 0

    ; If any values are omitted, reuse prior ones.
    if (holePosX = "" || holePosY = "" || holeSizeW = "" || holeSizeH = "") {
        if (!hasLastHole)
            return 0

        if (holePosX = "")
            holePosX := lastHolePosX
        if (holePosY = "")
            holePosY := lastHolePosY
        if (holeSizeW = "")
            holeSizeW := lastHoleSizeW
        if (holeSizeH = "")
            holeSizeH := lastHoleSizeH
    } else {
        lastHolePosX  := holePosX
        lastHolePosY  := holePosY
        lastHoleSizeW := holeSizeW
        lastHoleSizeH := holeSizeH
        hasLastHole   := True
    }

    ; Pick the monitor from the mouse position.
    monNum := MWAGetMonitorMouseIsIn()
    Overlay_GetWorkArea(monNum, areaLeft, areaTop, areaRight, areaBottom)

    areaWidth    := areaRight - areaLeft
    areaHeight   := areaBottom - areaTop

    if (areaWidth <= 0 || areaHeight <= 0)
        return 0

    ; Treat incoming hole rect as screen coordinates.
    holeLeft     := holePosX
    holeTop      := holePosY
    holeRight    := holePosX + holeSizeW
    holeBottom   := holePosY + holeSizeH

    ; Intersect hole rect with the selected monitor's work area.
    clipLeft     := (holeLeft > areaLeft) ? holeLeft : areaLeft
    clipTop      := (holeTop > areaTop) ? holeTop : areaTop
    clipRight    := (holeRight < areaRight) ? holeRight : areaRight
    clipBottom   := (holeBottom < areaBottom) ? holeBottom : areaBottom

    clippedHoleW := clipRight - clipLeft
    clippedHoleH := clipBottom - clipTop

    ; If the target rect does not overlap this monitor's work area,
    ; hide the overlay instead of covering the window.
    if (clippedHoleW <= 0 || clippedHoleH <= 0) {
        Gui, Overlay:Hide
        return 0
    }

    ; Reuse the same overlay window and just move its region to the next target.
    ; Avoiding window recreation here is the main reason repeated cycle presses
    ; feel like a continuous animation instead of a series of flashes.
    ; Make sure the overlay is positioned on the selected monitor's work area.
    Gui, Overlay:Show, % "x" areaLeft " y" areaTop " w" areaWidth " h" areaHeight " NA"
    ; Reassert the overlay here too because repeated Alt+Tab moves reuse the same
    ; HWND and must keep it above normal windows even after other popups reshuffle z-order.
    DllCall("user32\SetWindowPos"
        , "ptr", overlayHwnd
        , "ptr", HWND_TOPMOST
        , "int", 0
        , "int", 0
        , "int", 0
        , "int", 0
        , "uint", SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW)

    ; Convert screen coords to overlay-relative coords.
    holeRelX := clipLeft - areaLeft
    holeRelY := clipTop - areaTop

    ; Apply the updated donut region using overlay-relative coordinates so the
    ; highlight moves by reshaping the same surface already on screen. That keeps
    ; movement smooth because only the hole geometry changes between frames.
    Overlay_SetHoleRegion_WorkArea(overlayHwnd, areaWidth, areaHeight, holeRelX, holeRelY, clippedHoleW, clippedHoleH)

    ; Skip forced redraws when not needed so high-frequency cycle input does not
    ; pay an extra repaint cost on every step.
    if (doRedraw)
        WinSet, Redraw,, ahk_id %overlayHwnd%

    return 1
}

Overlay_Prewarm() {
    global overlayAlphaCurrent, overlayHwnd

    if (!overlayHwnd || !DllCall("IsWindow", "ptr", overlayHwnd))
        return 0

    ; Pre-show the overlay once at startup as a tiny fully transparent window.
    ; This "warms" the HWND, its layered-window state, and the compositor path
    ; before the user ever sees it. Doing that startup work early removes the
    ; first-use hitch that would otherwise make the first overlay animation feel
    ; noticeably rougher than later ones.
    regFull := DllCall("gdi32\CreateRectRgn"
        , "int", 0, "int", 0
        , "int", 1, "int", 1
        , "ptr")
    DllCall("user32\SetWindowRgn", "ptr", overlayHwnd, "ptr", regFull, "int", True)

    Overlay_SetAlpha(overlayHwnd, 0)
    Gui, Overlay:Show, x0 y0 w1 h1 NA
    overlayAlphaCurrent := 0

    return 1
}

Overlay_Hide(fadeMs := 100) {
    global overlayHwnd, overlayIsReady, overlayAlphaCurrent

    if (!overlayIsReady || !overlayHwnd || !DllCall("IsWindow", "ptr", overlayHwnd))
        return

    ; Let the hide fade continue after Alt/Esc release. That gives the overlay a
    ; short tail-off instead of an abrupt vanish, while the fade token still lets
    ; a new preview interrupt immediately if the user starts cycling again.
    Overlay_CancelFade()
    ; Fade all the way back to alpha 0 here so the next Cycle() preview can start
    ; from a fully transparent baseline and draw in with a clean fade-in instead
    ; of inheriting leftover opacity from the previous overlay instance.
    Overlay_FadeTo(overlayHwnd, 0, fadeMs, overlayAlphaCurrent, False)

    ; Reset to a full region only after the fade logic runs so the next show starts
    ; from a clean surface without having to rebuild the overlay from scratch.
    regFull := DllCall("gdi32\CreateRectRgn"
        , "int", 0, "int", 0
        , "int", A_ScreenWidth, "int", A_ScreenHeight
        , "ptr")
    DllCall("user32\SetWindowRgn", "ptr", overlayHwnd, "ptr", regFull, "int", True)

    ; Overlay_SetAlpha(overlayHwnd, 0)

    Gui, Overlay:Hide
}

Overlay_SetOpacity(alphaVal, fadeMs := 0) {
    global overlayHwnd, overlayIsReady, overlayAlphaCurrent

    if (!overlayIsReady || !overlayHwnd || !DllCall("IsWindow", "ptr", overlayHwnd))
        return 0

    if (alphaVal < 0)
        alphaVal := 0
    else if (alphaVal > 255)
        alphaVal := 255

    ; Cancel any in-progress fade (reuses your existing fade-cancel logic)
    Overlay_CancelFade()

    if (fadeMs > 0) {
        ; Fade from current alpha to the requested alpha
        Overlay_FadeTo(overlayHwnd, alphaVal, fadeMs, overlayAlphaCurrent)
    } else {
        ; Set immediately
        Overlay_SetAlpha(overlayHwnd, alphaVal)
    }

    return 1
}

; Finds the monitor + work area rect that contains the center of the given window.
GetMonitorRectsForWindow(hWnd, ByRef monX, ByRef monY, ByRef monW, ByRef monH
                             , ByRef workX, ByRef workY, ByRef workW, ByRef workH) {
    ; WinGetPos, wx, wy, ww, wh, ahk_id %hWnd%
    WinGetPosEx(hWnd, wx, wy, ww, wh)
    if (wx = "")
        return false
    cx := round((wx + ww)/2)
    cy := round((wy + wh)/2)

    SysGet, MonCount, MonitorCount
    Loop, %MonCount%
    {
        SysGet, Mon,  Monitor,         %A_Index% ; MonLeft/MonTop/MonRight/MonBottom
        SysGet, Work, MonitorWorkArea, %A_Index% ; WorkLeft/WorkTop/WorkRight/WorkBottom
        if (cx >= MonLeft && cx < MonRight && cy >= MonTop && cy < MonBottom) {
            monX  := MonLeft,   monY := MonTop,   monW := MonRight - MonLeft,    monH := MonBottom - MonTop
            workX := WorkLeft, workY := WorkTop, workW := WorkRight - WorkLeft, workH := WorkBottom - WorkTop
            return true
        }
    }
    Return false
}

Max(a,b) {
    Return (a > b) ? a : b
}
Min(a,b) {
    Return (a < b) ? a : b
}
; -------------------------------------------------------------------------------------------
#If MouseIsOverCaptionButtons()
^Lbutton Up::
    StopRecursion := True
    DetectHiddenWindows, Off
    CoordMode, Mouse, Screen
    SysGet, MonCount, MonitorCount
    MouseGetPos, vPosX, vPosY, hWnd

    WinGet, targetProcess, ProcessName, ahk_id %hWnd%
    WinGetClass, targetClass, ahk_id %hWnd%

    If targetProcess == "svchost.exe"
        Return

    vName := WhichButton(vPosX, vPosY, hWnd)

    If (InStr(vName,"close",false)) {
        tooltip, Closing all windows...
        WinGet, windowsFromProc, list, ahk_exe %targetProcess% ahk_class %targetClass%
        currentMon := MWAGetMonitorMouseIsIn()
        loop % windowsFromProc
        {
            hwndID := windowsFromProc%A_Index%
            If (MonCount > 1) {
                currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
                If currentMonHasActWin {
                    WinClose, ahk_id %hwndID%
                    sleep, 100
                }
            }
            Else {
                WinClose, ahk_id %hwndID%
                sleep, 100
            }
        }
    }
    If (InStr(vName,"minimize",false)) {
        tooltip, Minimizing all windows...
        WinGet, windowsFromProc, list, ahk_exe %targetProcess% ahk_class %targetClass%
        currentMon := MWAGetMonitorMouseIsIn()
        loop % windowsFromProc
        {
            hwndID := windowsFromProc%A_Index%
            If (MonCount > 1) {
                currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
                If currentMonHasActWin {
                    WinMinimize, ahk_id %hwndId%
                    sleep, 100
                }
            }
            Else {
                WinMinimize, ahk_id %hwndID%
                sleep, 100
            }
        }
    }
    StopRecursion := False
    sleep, 500
    tooltip,
Return

Lbutton Up::
    CoordMode, Mouse, Screen
    MouseGetPos, vPosX, vPosY, hWnd

    KeyWait, LButton, U T1
    vName := WhichButton(vPosX, vPosY, hWnd)

    If (InStr(vName,"minimize",false)) {
        WinMinimize, ahk_id %hWnd%
        ; Send, {Click, left}
    }
    Else If (InStr(vName,"maximize",false)) {
        WinGet, state, MinMax, ahk_id %hWnd%
        If (state == 0)
            WinMaximize, ahk_id %hWnd%
        Else
            WinRestore, ahk_id %hWnd%
        ; Send, {Click, left}
    }
    Else If (InStr(vName,"close",false)) {
        WinClose, ahk_id %hWnd%
        ; Send, {Click, left}
    }
    Else If (InStr(vName,"restore",false)) {
        WinRestore, ahk_id %hWnd%
        ; Send, {Click, left}
    }
    ; Else If (!InStr(vName,"close",false) && !InStr(vName,"restore",false) && !InStr(vName,"maximize",false) && !InStr(vName,"minimize",false))
    ; Send, {Click, left}

    ; ToolTip, % vName
    ; sleep, 1000
    ; tooltip
    Return
#If

#If MouseIsOverTaskbarWidgets()
$~^LButton::
    global MonCount
    Thread, NoTimers, True
    StopRecursion := True

    DetectHiddenWindows, Off
    SysGet, MonCount, MonitorCount

    Send, {Ctrl UP}

    KeyWait, LButton, U T3
    Sleep, 125

    targetID := FindTopMostWindow()
    WinGetClass, targetClass, ahk_id %targetID%
    WinSet, AlwaysOnTop, On, ahk_id %targetID%

    if (targetClass != "Windows.UI.Core.CoreWindow"
    &&  targetClass != "TaskListThumbnailWnd"
    &&  targetClass != "XamlExplorerHostIslandWindow") {

        WinGet, targetProcess, ProcessName, ahk_id %targetID%

        WinGet, windowList, List, ahk_exe %targetProcess% ahk_class %targetClass%
        listCount := windowList

        if (listCount < 2) {
            Tooltip, Only %listCount% Window(s) found!
            sleep, 1500
            Tooltip,
        }
        else {
            currentMon := MWAGetMonitorMouseIsIn()
            Loop, %windowList%
            {
                windowID := windowList%A_Index%
                WinGet, windowState, MinMax, ahk_id %windowID%

                if (windowState == -1) {
                    winMonNum := GetWindowMonitorNumber(windowID)

                    If (winMonNum == currentMon) {
                        WinRestore, ahk_id %windowID%
                        sleep, 100
                    }
                }
                    else if (windowState == 0) {
                    if (MonCount > 1) {
                        currentMonHasActWin := IsWindowOnMonNum(windowID, currentMon)
                        if currentMonHasActWin
                            ; WinActivate, ahk_id %windowID%
                            WinSet, AlwaysOnTop, On,  ahk_id %windowID%
                            WinSet, AlwaysOnTop, Off, ahk_id %windowID%
                    }
                    else {
                        WinSet, AlwaysOnTop, On,  ahk_id %windowID%
                        WinSet, AlwaysOnTop, Off, ahk_id %windowID%
                    }
                }
            }
            WinActivate, ahk_id %targetID%
            WinSet, AlwaysOnTop, Off, ahk_id %targetID%
        }
    }

    KeyWait, Ctrl, U
    SyncModifierSidesToPhys("Ctrl")

    StopRecursion := False
    Thread, NoTimers, False
Return
#If

#If MouseIsOverTitleBar()
$^LButton::
    Thread, NoTimers, True
    StopRecursion := True

    Send, {Ctrl UP}

    MouseGetPos, , , targetID
    WinActivate, ahk_id %targetID%
    WinGetClass, targetClass, ahk_id %targetID%
    WinGet, targetProcess, ProcessName, ahk_id %targetID%
    currentMon := MWAGetMonitorMouseIsIn()

    BringAppWindowsOnMonitorToTop(targetProcess, targetClass, currentMon, targetID)

    KeyWait, Ctrl, U
    SyncModifierSidesToPhys("Ctrl")
    StopRecursion := False
    Thread, NoTimers, False
return
#If

; Hold Ctrl+Shift, then drag with LButton to measure horizontal and vertical distance
; from the mouse-down origin.
$^+LButton::
    Measure_Begin()
return

BringAppWindowsOnMonitorToTop(targetProcess, targetClass, monitorNum, targetID) {
    DetectHiddenWindows, Off

    WinGet, windowList, List, ahk_exe %targetProcess% ahk_class %targetClass%
    orderedList := []

    Loop, %windowList%
    {
        windowID := windowList%A_Index%

        WinGet, windowState, MinMax, ahk_id %windowID%
        if (windowState != 0)
            continue

        currentMonHasActWin := IsWindowOnMonNum(windowID, monitorNum)
        if !currentMonHasActWin
            continue

        orderedList.Push(windowID)
    }

    listCount := orderedList.Length()
    if (listCount < 2) {
        Tooltip, Only %listCount% Window(s) found!
        sleep, 1500
        Tooltip,
        return
    }

    WinSet, AlwaysOnTop, On, ahk_id %targetID%

    Loop, %listCount%
    {
        listIndex := listCount - A_Index + 1
        windowID := orderedList[listIndex]

        if (windowID = targetID)
            continue

        ; WinActivate, ahk_id %windowID%
        ; WinWaitActive, ahk_id %windowID%,, 0.15
        WinSet, AlwaysOnTop, On,  ahk_id %windowID%
        WinSet, AlwaysOnTop, Off, ahk_id %windowID%
    }

    WinActivate, ahk_id %targetID%
    WinWaitActive, ahk_id %targetID%,, 0.15

    WinSet, AlwaysOnTop, Off, ahk_id %targetID%
}

#If MouseIsOverTaskbarBlank()
$~Lbutton::
    MouseGetPos, expX1, expY1,
    If (A_PriorHotkey == A_ThisHotkey
        && (A_TimeSincePriorHotkey < k_DoubleClickTime)
        && (abs(expX1-expX2) < 20 && abs(expY1-expY2) < 20)) {
        run, explorer.exe
        expX2 := 0
        expY2 := 0
        Return
    }

    KeyWait, LButton, U T5
    MouseGetPos, expX2, expY2,
Return
#If

; ----------------------- EXAMPLE USAGE ----------------------------
; clickType := ExplorerHitTestType()
    ; ; --- Handle double-click on BLANK SPACE ---
    ; if (clickType = "blank") {
        ; if (A_PriorHotkey = "~LButton" && A_TimeSincePriorHotkey < 300) {
            ; ; >>> YOUR DOUBLE-CLICK-BLANK ACTION HERE <<<
            ; Tooltip, Double-click on blank space
; ------------------------------------------------------------------
ExplorerHitTestType() {
    /*
        Returns one of:
            "blank"         - blank space in file list
            "item"          - file/folder item
            "columnHeader"  - column header in Details view
            "navTreeItem"   - probable left navigation tree item (heuristic)
            "breadcrumb"    - breadcrumb / address bar segment (heuristic)
            "other"         - anything else, or not Explorer
    */

    static ROLE_SYSTEM_LIST        := 0x21
    static ROLE_SYSTEM_LISTITEM    := 0x22
    static ROLE_SYSTEM_OUTLINEITEM := 0x24
    static ROLE_SYSTEM_COLUMNHEADER:= 0x19
    static ROLE_SYSTEM_TOOLBAR     := 0x16
    static ROLE_SYSTEM_PUSHBUTTON  := 0x2B
    static ROLE_SYSTEM_LINK        := 0x1E
    static ROLE_SYSTEM_SEPARATOR   := 0x0C

    CoordMode, Mouse, Screen
    MouseGetPos, x, y, winHwnd, ctrlNN
    if (!winHwnd)
        return "other"

    WinGetClass, cls, ahk_id %winHwnd%
    if (cls != "CabinetWClass" && cls != "ExplorerWClass" && cls != "#32770" && cls != "Progman" && cls != "ProgMan" && cls != "WorkerW")
        return "other"

    ; Get MSAA object under cursor
    childId := 0
    acc := Acc_ObjectFromPoint(childId, x, y)
    if !IsObject(acc)
        return "other"

    if (childId > 0)
        acc := Acc_CreateChildRef(acc, childId)

    ; Collect this object + its parents up to a small depth
    objs := []
    roles := []
    cur := acc

    Loop, 8 {
        if !IsObject(cur)
            break
        r := Explorer__GetRoleNum(cur)
        objs.Push(cur)
        roles.Push(r)
        try
            cur := cur.accParent
        catch
        {
            cur := ""
            break
        }
    }

    if (roles.Length() = 0)
        return "other"

    startRole := roles[1]

    hasOutlineItem := False
    hasToolbar     := False

    for i, r in roles {
        if (r = ROLE_SYSTEM_OUTLINEITEM)
            hasOutlineItem := true
        else if (r = ROLE_SYSTEM_TOOLBAR)
            hasToolbar := true
    }

    ; --- Left navigation tree ---
    ; Modern shell views can sometimes expose actual file/folder items as OUTLINEITEM
    ; too, especially through SysListView-based desktop/file views. Treat OUTLINEITEM
    ; as navigation-tree only when the underlying control is not a list view.
    if (hasOutlineItem && !InStr(ctrlNN, "SysListView32", True))
        return "navTreeItem"

    if (startRole = ROLE_SYSTEM_OUTLINEITEM)
        return "item"

    ; --- Direct checks on the object under cursor ---
    if (startRole = ROLE_SYSTEM_LIST)
        return "blank"

    if (startRole = ROLE_SYSTEM_LISTITEM)
        return "item"

    if (startRole = ROLE_SYSTEM_COLUMNHEADER)
        return "columnHeader"

    ; --- Breadcrumb / address bar (heuristic) ---
    ; Typically a PUSHBUTTON / LINK / SEPARATOR on a toolbar above the list.
    if (hasToolbar
        && (startRole = ROLE_SYSTEM_PUSHBUTTON
         || startRole = ROLE_SYSTEM_LINK
         || startRole = ROLE_SYSTEM_SEPARATOR))
    {
        return "breadcrumb"
    }

    return "other"
}

IsMouseOverShellItemForRButton() {
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my, hwnd, ctrlNN

    if (!hwnd)
        return false

    WinGetClass, winClass, ahk_id %hwnd%

    if (winClass != "CabinetWClass" && winClass != "ExplorerWClass" && winClass != "#32770" && winClass != "Progman" && winClass != "ProgMan" && winClass != "WorkerW")
        return false
    ; tooltip, testing for icon...
    if (InStr(ctrlNN, "DirectUIHWND", True)) {
        if (winClass = "#32770")
            return (DialogClickClassify(mx, my, ctrlNN) = "item")
        return (ExplorerClickClassify(mx, my, ctrlNN) = "item")
    }

    if (InStr(ctrlNN, "SysListView32", True)) {
        return (ExplorerHitTestType() = "item")
    }


    return false
}
; ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
Explorer__GetRoleNum(ByRef accObj := "") {
    if (accObj == "")
        accObj := Acc_ObjectFromPoint()

    if !accObj
        return
    ; Safely get numeric MSAA role
    role := ""
    try
        role := accObj.accRole(0)
    catch
        return 0

    ; Sometimes Acc.ahk may return a string; handle that as a fallback
    if role is Integer
        return role

    ; String fallback, normalized
    r := Trim(role)
    StringLower, r, r

    ; Role Constant             Hex     Meaning
    ; ROLE_SYSTEM_LIST          0x21    The container list
    ; ROLE_SYSTEM_LISTITEM      0x22    A file/folder in Explorer
    ; ROLE_SYSTEM_OUTLINE       0x23    The outline/tree container
    ; ROLE_SYSTEM_OUTLINEITEM   0x24    Tree-view style item
    ; ROLE_SYSTEM_COLUMNHEADER  0x19    Column header: Name, Date Modified, Type, etc.
    ; ROLE_SYSTEM_PUSHBUTTON    0x2B    Buttons
    ; ROLE_SYSTEM_LINK          0x1E    Hyperlink-like UI elements
    if (r == "list")
        return 0x21
    if (r == "list item" || r == "listitem")
        return 0x22
    if (r == "outline")
        return 0x23
    if (r == "outline item" || r == "outlineitem")
        return 0x24
    if (r == "columnheader" || r == "column header")
        return 0x19
    if (r == "toolbar")
        return 0x16
    if (r == "push button" || r == "pushbutton")
        return 0x2B
    if (r == "link")
        return 0x1E
    if (r == "separator")
        return 0x0C
    ; In Explorer, distinguishing between:
    ; List (0x21)         ← blank area
    ; ListItem (0x22)     ← real file/folder
    ; ColumnHeader (0x19) ← click on a sort header

    ; Explorer's modern implementation sometimes reports:
        ; ROLE_SYSTEM_OUTLINE (0x23) for the whole file-view region
        ; ROLE_SYSTEM_OUTLINEITEM (0x24) for individual files/folders
        ; Instead of using classic LIST (0x21) / LISTITEM (0x22)
    ; This happens frequently in:
        ; Windows 11's XAML Explorer
        ; WebView-backed folder views
        ; File dialogs using UIA → MSAA proxying
    return 0
}

; ------------------------------------------------------------------

; Classify a point inside a SysListView32 using MSAA roles. Returning "unknown"
; lets the public blank-space check use its theme-independent pixel fallback
; without mistaking a positively identified item or header for blank space.
_GetSysListViewClickType(xPos, yPos) {
    static ROLE_SYSTEM_LIST         := 0x21
    static ROLE_SYSTEM_LISTITEM     := 0x22
    static ROLE_SYSTEM_OUTLINEITEM  := 0x24
    static ROLE_SYSTEM_COLUMNHEADER := 0x19
    static ROLE_SYSTEM_OUTLINE      := 0x23

    childId := 0
    acc := Acc_ObjectFromPoint(childId, xPos, yPos)
    if !IsObject(acc)
        return "unknown"

    role := Explorer__RoleValueToNum(Explorer__AccRoleSafe(acc, childId))
    if (role = ROLE_SYSTEM_LISTITEM || role = ROLE_SYSTEM_OUTLINEITEM)
        return "content"
    if (role = ROLE_SYSTEM_COLUMNHEADER)
        return "content"
    if (role = ROLE_SYSTEM_LIST || role = ROLE_SYSTEM_OUTLINE)
        return "blank"

    cur := acc
    Loop, 15
    {
        if !IsObject(cur)
            break

        role := Explorer__GetRoleNum(cur)
        if (role = ROLE_SYSTEM_LISTITEM || role = ROLE_SYSTEM_OUTLINEITEM)
            return "content"
        if (role = ROLE_SYSTEM_COLUMNHEADER)
            return "content"
        if (role = ROLE_SYSTEM_LIST || role = ROLE_SYSTEM_OUTLINE)
            return "blank"

        parent := ""
        try
            parent := cur.accParent
        catch
            parent := ""

        cur := parent
    }

    return "unknown"
}

; Return true only when the supplied SysListView32 point appears to be blank.
; Prefer MSAA's item/header/list roles; if MSAA cannot classify the point, compare
; the surrounding pixels with the clicked pixel instead of assuming a white theme.
IsSysListViewBlankSpaceClick(xPos, yPos) {
    clickType := _GetSysListViewClickType(xPos, yPos)
    if (clickType == "blank")
        return True
    if (clickType == "content")
        return False

    return AreaLooksUniformFast(xPos, yPos)
}

Explorer__AccRoleSafe(ByRef accObj, childId := 0) {
    try
        return accObj.accRole(childId)
    catch
        return ""
}

Explorer__RoleValueToNum(role) {
    if role is Integer
        return role + 0

    r := Trim(role)
    StringLower, r, r

    if (r == "list")
        return 0x21
    if (r == "list item" || r == "listitem")
        return 0x22
    if (r == "outline")
        return 0x23
    if (r == "outline item" || r == "outlineitem")
        return 0x24
    if (r == "columnheader" || r == "column header")
        return 0x19

    return 0
}

; ------------------------------------------------------------------

; Purpose        : support point-probe-based UIA features that need a short, readable
; adapter when sampling elements under the mouse or a computed dialog point.
; Why this exists: keeps the calling code terse while forcing those call sites
; onto the shared SafeUIA timeout/exception-handling path instead of direct
; raw UIA point lookups.
; Scope          : generic helper.
UIA_SafeElementFromPoint_(x, y, transactionTimeout := 2000, uiaDeadlineTick := 0) {
    ; Requires: #Include UIA_Interface.ahk
    ; Returns a UIA element or "" if it fails.
    effectiveTimeoutMs := _ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout)
    if (!effectiveTimeoutMs)
        return ""
    return SafeUIA_ElementFromPoint(x, y, "", effectiveTimeoutMs)
}

; Resolve a #32770 file dialog's Items View from proportional screen points.
; This is the fallback when native child-HWND scoping cannot find the file panel.
_ResolveDialogItemsViewByPoint(dlgHwnd, ByRef itemsEl, transactionTimeout
    , uiaDeadlineTick, useCachedItems, ByRef resolutionReason) {
    static c_cachedItemsDlgHwnd  := 0
    static c_cachedItemsEl       := ""
    static c_cachedItemsTick     := 0
    static k_cachedItemsTtlMs    := 250
    static primaryProbes         := [[70,45],[60,45],[80,45],[70,55]]
    static fallbackProbes        := [[75,35],[75,65]]

    global UIA
    resolutionReason := ""
    itemsEl := ""
    if (!IsObject(UIA)) {
        try
            UIA := UIA_Interface()
        catch e
            UIA := ""
    }
    if !IsObject(UIA) {
        resolutionReason := "uia_unavailable"
        return false
    }

    if (!dlgHwnd) {
        resolutionReason := "dialog_hwnd_unavailable"
        return false
    }
    if (transactionTimeout <= 0)
        transactionTimeout := 1
    if (!uiaDeadlineTick)
        uiaDeadlineTick := A_TickCount + transactionTimeout

    items := ""
    resolvedFromCache := False
    if (useCachedItems && c_cachedItemsDlgHwnd = dlgHwnd && (A_TickCount - c_cachedItemsTick) <= k_cachedItemsTtlMs && IsObject(c_cachedItemsEl)) {
        if (_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout)) {
            info := SafeUIA_GetElementSnapshot(c_cachedItemsEl, "className|controlType|name")
            if (info.className = "UIItemsView" || (info.controlType = 50008 && info.name = "Items View")) {
                items := c_cachedItemsEl
                resolvedFromCache := True
            }
        }
    }

    if !IsObject(items) {
        WinGetPos, wx, wy, ww, wh, ahk_id %dlgHwnd%
        if (ww <= 0 || wh <= 0) {
            resolutionReason := "dialog_rect_unavailable"
            return false
        }
        for probeListIndex, probeList in [primaryProbes, fallbackProbes]
        {
            for probeIndex, p in probeList
            {
                px := wx + (ww * p[1] // 100)
                py := wy + (wh * p[2] // 100)

                el := UIA_SafeElementFromPoint_(px, py, transactionTimeout, uiaDeadlineTick)
                if !IsObject(el)
                    continue

                items := UIA_WalkUpToUIItemsView_(el, uiaDeadlineTick, transactionTimeout)
                if IsObject(items)
                    break
            }

            if IsObject(items)
                break
        }
    }

    if !IsObject(items) {
        if (A_TickCount >= uiaDeadlineTick)
            resolutionReason := "uia_budget_exhausted_during_point_lookup"
        else
            resolutionReason := "items_view_not_found_by_point"
        return false
    }

    c_cachedItemsDlgHwnd := dlgHwnd
    c_cachedItemsEl := items
    c_cachedItemsTick := A_TickCount
    itemsEl := items
    resolutionReason := resolvedFromCache
        ? "cached_items_view"
        : "screen_point_items_view"

    return true
}

; Resolve a #32770 file dialog's Items View below its most likely native file-
; panel controls. At most two candidates share a short sub-budget so the point
; fallback retains time when a provider does not expose the native subtree.
_ResolveDialogItemsViewFromNativeControls(dlgHwnd, ByRef itemsEl
    , transactionTimeout, uiaDeadlineTick, ByRef candidateCount
    , ByRef resolutionReason, ByRef resolvedCtrlNN := ""
    , ByRef resolvedCtrlHwnd := 0) {
    ; Clear every output first so a failed lookup cannot expose stale data to its fallback caller.
    itemsEl := ""
    candidateCount := 0
    resolutionReason := ""
    resolvedCtrlNN := ""
    resolvedCtrlHwnd := 0
    ; A live dialog root is required because every candidate ClassNN and HWND is resolved beneath it.
    if (!dlgHwnd) {
        resolutionReason := "dialog_hwnd_unavailable"
        return false
    }

    ; Enumerate both native file-panel families once so candidate selection does not rescan the dialog.
    targetScan := GetSendCtrlAddTargetScan(dlgHwnd, "#32770")
    ; Read the current ClassNN because an already-focused file panel is the strongest first candidate.
    ControlGetFocus, focusedCtrlNN, ahk_id %dlgHwnd%
    ; Apply the same target preference used by SendCtrlAdd() so readiness and alignment inspect one panel.
    preferredCtrlNN := ChooseSendCtrlAddTarget(dlgHwnd, "#32770"
        , focusedCtrlNN, targetScan)

    ; Preserve candidate priority in an array while the map prevents duplicate UIA searches by ClassNN.
    candidateCtrlNNs := []
    seenCtrlNNs := {}
    ; Put the preferred control first so the shortest UIA budget is spent on the most likely Items View.
    if (preferredCtrlNN != "") {
        candidateCtrlNNs.Push(preferredCtrlNN)
        seenCtrlNNs[preferredCtrlNN] := True
    }
    ; Preserve the existing target preference: native ListViews first, then the
    ; DirectUI control numbers already recognized by ChooseSendCtrlAddTarget().
    for ctrlIndex, candidateCtrlNN in StrSplit(targetScan.sysListCtrls, A_Space)
    {
        if (candidateCtrlNN = "" || seenCtrlNNs.HasKey(candidateCtrlNN))
            continue
        candidateCtrlNNs.Push(candidateCtrlNN)
        seenCtrlNNs[candidateCtrlNN] := True
    }
    for ctrlIndex, candidateCtrlNN in ["DirectUIHWND2", "DirectUIHWND3"
        , "DirectUIHWND4", "DirectUIHWND6", "DirectUIHWND8"]
    {
        if (!InStr(A_Space . targetScan.directCtrls . A_Space
            , A_Space . candidateCtrlNN . A_Space, True)
         || seenCtrlNNs.HasKey(candidateCtrlNN))
            continue
        candidateCtrlNNs.Push(candidateCtrlNN)
        seenCtrlNNs[candidateCtrlNN] := True
    }
    ; Retain any less common DirectUI numbering after the known priorities so
    ; candidateCount still describes the complete native scan for diagnostics.
    for ctrlIndex, candidateCtrlNN in StrSplit(targetScan.directCtrls, A_Space)
    {
        if (candidateCtrlNN = "" || seenCtrlNNs.HasKey(candidateCtrlNN))
            continue
        candidateCtrlNNs.Push(candidateCtrlNN)
        seenCtrlNNs[candidateCtrlNN] := True
    }

    ; Report the full native candidate count so diagnostics can distinguish discovery from UIA failure.
    candidateCount := candidateCtrlNNs.Length()
    if (!candidateCount) {
        resolutionReason := "native_candidates_unavailable"
        return false
    }

    ; Honor the caller's shared deadline so this preferred native lookup cannot starve the point fallback.
    remainingMs := uiaDeadlineTick
        ? uiaDeadlineTick - A_TickCount
        : transactionTimeout
    if (remainingMs <= 0) {
        resolutionReason := "uia_budget_exhausted_before_native_lookup"
        return false
    }

    ; Spend at most 60 ms and half the remaining budget here, reserving time for compatibility probing.
    nativeBudgetMs := Min(60, Max(1, remainingMs // 2))
    nativeDeadlineTick := A_TickCount + nativeBudgetMs
    ; Never extend a locally calculated deadline beyond the request's absolute UIA deadline.
    if (uiaDeadlineTick)
        nativeDeadlineTick := Min(nativeDeadlineTick, uiaDeadlineTick)

    attemptedCount := 0
    ; Probe only the two strongest candidates because slow UIA providers can consume the whole request budget.
    attemptLimit := Min(2, candidateCount)
    Loop, %attemptLimit%
    {
        candidateCtrlNN := candidateCtrlNNs[A_Index]
        ; Convert the ClassNN into a native HWND because the UIA search must be scoped to a concrete subtree.
        ControlGet, candidateHwnd, Hwnd,, %candidateCtrlNN%, ahk_id %dlgHwnd%
        ; Skip controls destroyed during dialog reconstruction instead of querying UIA with a stale HWND.
        if (!candidateHwnd || !DllCall("user32\IsWindow", "Ptr", candidateHwnd, "Int"))
            continue

        ; Reject an unexpected reused ClassNN so only known file-panel control families authorize readiness.
        candidateClass := GetClassName(candidateHwnd)
        if (SubStr(candidateClass, 1, 13) != "SysListView32"
         && SubStr(candidateClass, 1, 12) != "DirectUIHWND")
            continue

        attemptedCount++
        ; Search below this HWND to avoid the slower and less precise dialog-wide UIA traversal.
        items := FindExplorerItemsViewElement(candidateHwnd, transactionTimeout
            , nativeDeadlineTick)
        if IsObject(items) {
            ; Return the resolved element plus its native source so later traces can explain the successful path.
            itemsEl := items
            resolvedCtrlNN := candidateCtrlNN
            resolvedCtrlHwnd := candidateHwnd
            resolutionReason := "control=" . candidateCtrlNN
                . " hwnd=" . candidateHwnd
                . " attempted=" . attemptedCount
            return true
        }

        ; Stop immediately when the native sub-budget expires so the caller retains its fallback opportunity.
        if (A_TickCount >= nativeDeadlineTick)
            break
    }

    ; Preserve counts and timeout state so logs distinguish absent UIA content from an exhausted budget.
    resolutionReason := "candidate_count=" . candidateCount
        . " attempted=" . attemptedCount
        . (A_TickCount >= nativeDeadlineTick
            ? " native_budget_exhausted"
            : " native_items_view_not_found")
    return false
}

; Resolve the current Explorer/file-dialog Items View without deciding whether
; it is in Details mode or has visible content. #32770 dialogs first search the
; subtree of likely native file-panel HWNDs, then retain proportional point
; probing as a compatibility fallback. Explorer windows use their window root.
ResolveExplorerItemsView(targetHwndID, ByRef itemsEl := ""
    , transactionTimeout := 2000, uiaDeadlineTick := 0
    , useCachedDialogItems := True, ByRef resolver := ""
    , ByRef candidateCount := 0, ByRef resolutionReason := ""
    , ByRef resolvedCtrlNN := "", ByRef resolvedCtrlHwnd := 0) {
    global UIA

    itemsEl := ""
    resolver := ""
    candidateCount := 0
    resolutionReason := ""
    resolvedCtrlNN := ""
    resolvedCtrlHwnd := 0
    if (!targetHwndID) {
        resolutionReason := "target_hwnd_unavailable"
        return false
    }
    if (transactionTimeout <= 0)
        transactionTimeout := 1
    if (!uiaDeadlineTick)
        uiaDeadlineTick := A_TickCount + transactionTimeout

    if !IsObject(UIA) {
        try
            UIA := UIA_Interface()
        catch e
            UIA := ""
    }
    if !IsObject(UIA) {
        resolutionReason := "uia_unavailable"
        return false
    }

    WinGetClass, targetClass, ahk_id %targetHwndID%
    if (targetClass = "CabinetWClass" || targetClass = "ExplorerWClass") {
        itemsEl := FindExplorerItemsViewElement(targetHwndID
            , transactionTimeout, uiaDeadlineTick)
        resolver := IsObject(itemsEl) ? "window_scoped" : "unresolved"
        resolutionReason := IsObject(itemsEl)
            ? "explorer_window_root"
            : "items_view_not_found_below_window"
        return IsObject(itemsEl)
    }

    if (targetClass != "#32770") {
        resolutionReason := "unsupported_window_class=" . targetClass
        return false
    }

    nativeReason := ""
    if (_ResolveDialogItemsViewFromNativeControls(targetHwndID, itemsEl
        , transactionTimeout, uiaDeadlineTick, candidateCount, nativeReason
        , resolvedCtrlNN, resolvedCtrlHwnd)) {
        resolver := "native_scoped"
        resolutionReason := nativeReason
        return true
    }

    pointReason := ""
    if (_ResolveDialogItemsViewByPoint(targetHwndID, itemsEl
        , transactionTimeout, uiaDeadlineTick, useCachedDialogItems
        , pointReason)) {
        resolver := "point_fallback"
        resolutionReason := "native=[" . nativeReason . "] point=["
            . pointReason . "]"
        return true
    }

    resolver := "unresolved"
    resolutionReason := "native=[" . nativeReason . "] point=["
        . pointReason . "]"
    return false
}

; Purpose        : support higher-level UIA detectors that only need a yes/no answer
; about whether a subtree contains a given control type.
; Why this exists: hides the library/fork differences in control-type search
; APIs so feature code can ask one narrow question without repeating fallback
; condition-building logic inline.
; Scope          : generic helper.
UIA_FindFirstByControlTypeAny_(rootEl, ctlTypeId) {
    ; Returns true if a descendant with ControlType == ctlTypeId exists.
    ; Uses UIA_Interface.ahk (CreatePropertyCondition + FindFirst) with a couple fallbacks.

    global UIA
    static TreeScope_Subtree := 0x4
    static UIA_ControlTypePropertyId := 30003

    if !IsObject(rootEl)
        return false

    cond := ""
    try
        cond := UIA.CreatePropertyCondition(UIA_ControlTypePropertyId, ctlTypeId)
    catch
        cond := ""

    if IsObject(cond)
    {
        found := ""
        try
            found := rootEl.FindFirst(TreeScope_Subtree, cond)
        catch
            found := ""

        if IsObject(found)
            return true
    }

    ; Some forks expose convenience search methods
    found2 := ""
    try
        found2 := rootEl.FindFirstByControlType(ctlTypeId)
    catch
        found2 := ""

    return IsObject(found2)
}

; Return the GridPattern column count through the UIA wrapper's supported access
; variants, or -1 when the provider exposes no compatible GridPattern entry point.
UIA_TryGetGridColumnCountAny_(el) {
    static UIA_GridPatternId := 10006
    static c_preferredGridPatternMode := ""

    if !IsObject(el)
        return -1

    modeOrder := []
    if (c_preferredGridPatternMode != "")
        modeOrder.Push(c_preferredGridPatternMode)
    for modeIndex, mode in ["current_id", "id", "current_name", "name"]
    {
        if (mode != c_preferredGridPatternMode)
            modeOrder.Push(mode)
    }

    pat := ""
    for modeIndex, mode in modeOrder
    {
        pat := ""
        if (mode = "current_id") {
            try
                pat := el.GetCurrentPattern(UIA_GridPatternId)
            catch
                pat := ""
        }
        else if (mode = "id") {
            try
                pat := el.GetPattern(UIA_GridPatternId)
            catch
                pat := ""
        }
        else if (mode = "current_name") {
            try
                pat := el.GetCurrentPattern("Grid")
            catch
                pat := ""
        }
        else if (mode = "name") {
            try
                pat := el.GetPattern("Grid")
            catch
                pat := ""
        }

        if IsObject(pat) {
            c_preferredGridPatternMode := mode
            break
        }
    }

    if !IsObject(pat)
        return -1

    try
        count := pat.CurrentColumnCount
    catch
        count := -1

    return count
}

; Purpose        : support UIA feature checks that depend on a specific named control
; existing within a subtree, such as Explorer/details-view heuristics.
; Why this exists: encapsulates the combined type-plus-name lookup and its
; compatibility fallbacks so those policy checks stay readable at the call site.
; Scope          : generic helper.
UIA_FindFirstByControlTypeAndNameAny_(rootEl, ctlTypeId, wantName) {
    ; Returns true if a descendant exists with:
        ; ControlType == ctlTypeId AND Name == wantName
    ; Uses UIA_Interface.ahk (CreateAndCondition + FindFirst) with fallbacks.

    static c_preferredFindModeByKey := {}
    global UIA
    static TreeScope_Subtree := 0x4
    static UIA_ControlTypePropertyId := 30003
    static UIA_NamePropertyId := 30005

    if !IsObject(rootEl)
        return false
    if (ctlTypeId = "" || wantName = "")
        return false

    modeKey := ctlTypeId . "|" . wantName
    preferredMode := c_preferredFindModeByKey.HasKey(modeKey) ? c_preferredFindModeByKey[modeKey] : ""
    modeOrder := []
    if (preferredMode != "")
        modeOrder.Push(preferredMode)
    for modeIndex, mode in ["condition", "name"]
    {
        if (mode != preferredMode)
            modeOrder.Push(mode)
    }

    for modeIndex, mode in modeOrder
    {
        if (mode = "condition")
        {
            condAnd := ""
            condName := ""
            condType := ""
            try
                condType := UIA.CreatePropertyCondition(UIA_ControlTypePropertyId, ctlTypeId)
            catch
                condType := ""
            try
                condName := UIA.CreatePropertyCondition(UIA_NamePropertyId, wantName)
            catch
                condName := ""

            if (IsObject(condType) && IsObject(condName))
            {
                try
                    condAnd := UIA.CreateAndCondition(condType, condName)
                catch
                    condAnd := ""

                if IsObject(condAnd)
                {
                    found := ""
                    try
                        found := rootEl.FindFirst(TreeScope_Subtree, condAnd)
                    catch
                        found := ""

                    if IsObject(found) {
                        c_preferredFindModeByKey[modeKey] := "condition"
                        return true
                    }
                }
            }
        }
        else if (mode = "name")
        {
            found2 := ""
            try
                found2 := rootEl.FindFirstByName(wantName)
            catch
                found2 := ""

            if IsObject(found2) {
                info := SafeUIA_GetElementSnapshot(found2, "controlType")
                if (info.controlType = ctlTypeId) {
                    c_preferredFindModeByKey[modeKey] := "name"
                    return true
                }
            }
        }
    }

    return false
}

; Purpose        : support Explorer/file-dialog view detection by locating the nearest
; Items View container above a probed descendant element.
; Why this exists: the details-view heuristics operate on the shell view root,
; not on an arbitrary leaf element, so this concentrates the upward-walk policy
; in one place instead of repeating it around each probe sequence.
; Scope          : feature-specific helper.
UIA_WalkUpToUIItemsView_(el, uiaDeadlineTick := 0, transactionTimeout := 2000) {
    ; Walk up until we hit ClassName UIItemsView OR Name Items View (List)
    static UIA_ListTypeId := 50008

    cur := el
    Loop, 25
    {
        if (!_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout))
            break
        info := SafeUIA_GetElementSnapshot(cur, "className|controlType|name")

        if (info.className = "UIItemsView")
            return cur

        if (info.controlType = UIA_ListTypeId && info.name = "Items View")
            return cur

        if (!_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout))
            break
        next := ""
        try
            next := cur.GetParent()
        catch
            next := ""

        if !IsObject(next)
            break

        cur := next
    }

    return ""
}

IsDetailsView_ExplorerCOM(winHwnd := "", ByRef detailsReason := "") {
    static FVM_DETAILS := 4  ; FOLDERVIEWMODE.FVM_DETAILS

    detailsReason := ""
    if (!winHwnd)
        WinGet, winHwnd, ID, A
    if (!winHwnd) {
        detailsReason := "explorer_hwnd_unavailable"
        return false
    }

    try {
        shell := ComObjCreate("Shell.Application")
        for oWin in shell.Windows
        {
            h := ""
            try
                h := oWin.Hwnd
            catch
            {
                try
                    h := oWin.HWND
                catch
                    h := ""
            }

            if (h = winHwnd)
            {
                try {
                    currentViewMode := oWin.Document.CurrentViewMode
                    detailsReason := "current_view_mode=" . currentViewMode
                    return (currentViewMode = FVM_DETAILS)
                }
                catch {
                    detailsReason := "current_view_mode_unavailable"
                    return false
                }
            }
        }
    } catch e {
        detailsReason := "explorer_com_exception"
        return false
    }

    detailsReason := "explorer_com_window_not_found"
    return false
}

IsDetailsView(winHwnd := "", ByRef itemsEl := "", transactionTimeout := 2000
    , uiaDeadlineTick := 0, useCachedDialogItems := True
    , ByRef detailsReason := "", ByRef itemsViewResolver := ""
    , ByRef itemsViewCandidateCount := 0
    , ByRef itemsViewResolutionReason := "", ByRef resolvedCtrlNN := ""
    , ByRef resolvedCtrlHwnd := 0) {
    detailsReason := ""
    itemsEl := ""
    itemsViewResolver := ""
    itemsViewCandidateCount := 0
    itemsViewResolutionReason := ""
    resolvedCtrlNN := ""
    resolvedCtrlHwnd := 0
    if (!winHwnd)
        WinGet, winHwnd, ID, A
    if (!winHwnd) {
        detailsReason := "window_hwnd_unavailable"
        return false
    }

    WinGetClass, cls, ahk_id %winHwnd%

    if (cls = "CabinetWClass" || cls = "ExplorerWClass")
        return IsDetailsView_ExplorerCOM(winHwnd, detailsReason)

    if (cls = "#32770") {
        if !ResolveExplorerItemsView(winHwnd, itemsEl, transactionTimeout
            , uiaDeadlineTick, useCachedDialogItems, itemsViewResolver
            , itemsViewCandidateCount, itemsViewResolutionReason
            , resolvedCtrlNN, resolvedCtrlHwnd) {
            detailsReason := "items_view_resolution_failed"
            return false
        }
        if ExplorerItemsViewHasDetailsSignals(itemsEl, uiaDeadlineTick
            , transactionTimeout, detailsReason)
            return true

        ; A native candidate can expose a different List beneath an ambiguous
        ; DirectUI host. Preserve point probing as the final authority before
        ; concluding that the current #32770 file panel is not in Details mode.
        if (itemsViewResolver = "native_scoped") {
            nativeDetailsReason := detailsReason
            pointItemsEl := ""
            pointReason := ""
            if (_ResolveDialogItemsViewByPoint(winHwnd, pointItemsEl
                , transactionTimeout, uiaDeadlineTick, useCachedDialogItems
                , pointReason)) {
                itemsEl := pointItemsEl
                ; The accepted point-resolved element is no longer proven to belong
                ; to the native candidate returned by the first resolver.
                resolvedCtrlNN := ""
                resolvedCtrlHwnd := 0
                itemsViewResolver := "point_fallback_after_native_rejection"
                itemsViewResolutionReason .= " native_details=["
                    . nativeDetailsReason . "] point=[" . pointReason . "]"
                return ExplorerItemsViewHasDetailsSignals(itemsEl
                    , uiaDeadlineTick, transactionTimeout, detailsReason)
            }
            itemsViewResolutionReason .= " native_details=["
                . nativeDetailsReason . "] point=[" . pointReason . "]"
            detailsReason := nativeDetailsReason
        }
        return false
    }

    detailsReason := "unsupported_window_class=" . cls
    return false
}

DebugRolesUnderMouse() {
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    acc := Acc_ObjectFromPoint(mx, my)
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

ExplorerClickClassify(xPos, yPos, winCtrlNN) {
    global UIA
    static headerCtlId := 0
    static headerItemCtlId := 0

    if (!headerCtlId || !headerItemCtlId) {
        try {
            headerCtlId     := UIA.ControlTypeId("Header")
            headerItemCtlId := UIA.ControlTypeId("HeaderItem")
        } catch {
            headerCtlId     := 50034
            headerItemCtlId := 50035
        }
    }

    ; Early gate: only handle shell view clicks
    if !InStr(winCtrlNN, "DirectUIHWND", True)
        return "other"

    ; This classification supplements click gestures; path change remains the
    ; authoritative proof of DirectUI folder navigation. Use one short lookup so
    ; an unresponsive UIA provider cannot hold up the second physical click.
    hitEl := SafeUIA_ElementFromPoint(xPos, yPos, "", 250, 250, False)
    if !IsObject(hitEl)
        return "other"

    ; Use one snapshot-driven parent walk so header/item/blank classification
    ; stays ordered while avoiding multiple UIA ancestry/property passes.
    blankFound := False
    itemFound  := False
    walkEl     := hitEl
    depth      := 0

    while (IsObject(walkEl) && depth < 18)
    {
        info := SafeUIA_GetElementSnapshot(walkEl, "autoId|className|controlType")

        if ((depth < 12 && info.className = "UIColumnHeader")
         || (depth < 16 && (info.controlType = headerItemCtlId || info.controlType = headerCtlId)))
            return "header"

        if (!itemFound
         && (info.className = "UIItem" || (depth = 0 && info.autoId = "System.ItemNameDisplay")))
            itemFound := True

        if (!blankFound && info.className = "UIItemsView")
            blankFound := True

        walkEl := ExplorerClickClassify_GetParentTW(walkEl)
        depth++
    }

    if (itemFound)
        return "item"

    if (blankFound)
        return "blank"

    return "other"
}

/*
    Walk a standard #32770 file dialog's hit element ancestry and classify
    whether the click landed on a header, an item, or the blank file area.
*/
_DialogClickClassifyWalkParents(hitEl) {
    static dataGridCtlId   := 50028
    static dataItemCtlId   := 50029
    static headerCtlId     := 50034
    static headerItemCtlId := 50035
    static listCtlId       := 50008
    static listItemCtlId   := 50007
    static tableCtlId      := 50036
    static treeItemCtlId   := 50024

    walkEl := hitEl
    depth := 0

    while (IsObject(walkEl) && depth < 20)
    {
        ; Read the properties this classifier needs once per ancestor to keep
        ; dialog click classification cheaper on repeated click activity.
        info        := SafeUIA_GetElementSnapshot(walkEl, "autoId|className|controlType|name")
        autoId      := info.autoId
        className   := info.className
        controlType := info.controlType
        elementName := info.name

        if (className = "UIColumnHeader" || controlType = headerCtlId || controlType = headerItemCtlId)
            return "header"

        if (className = "UIItem"
         || controlType = dataItemCtlId
         || controlType = listItemCtlId
         || controlType = treeItemCtlId
         || autoId = "System.ItemNameDisplay")
            return "item"

        if (className = "UIItemsView"
         || controlType = dataGridCtlId
         || controlType = listCtlId
         || controlType = tableCtlId
         || elementName = "Items View")
            return "blank"

        walkEl := ExplorerClickClassify_GetParentTW(walkEl)
        depth++
    }

    return "other"
}

/*
    Classify clicks in standard #32770 file dialogs without assuming the
    Explorer-specific UIItemsView ancestry always exists.
*/
DialogClickClassify(xPos, yPos, winCtrlNN) {
    if !InStr(winCtrlNN, "DirectUIHWND", True)
        return "other"

    ; This classification supplements click gestures; path change remains the
    ; authoritative proof of DirectUI folder navigation. Use one short lookup so
    ; an unresponsive UIA provider cannot hold up the second physical click.
    hitEl := SafeUIA_ElementFromPoint(xPos, yPos, "", 250, 250, False)
    if !IsObject(hitEl)
        return "other"

    return _DialogClickClassifyWalkParents(hitEl)
}

ExplorerClickClassify_GetParentTW(el) {
    global UIA
    if !IsObject(el)
        return ""
    try
        return UIA.TreeWalkerTrue.GetParentElement(el)
    catch exception
        return ""
}

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
    try
    {
        accFocus := accRoot.accFocus
    }
    catch
    {
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
    try
    {
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

F8::
    WinGet, hwnd, ID, A
    WinGetClass, windowClass, ahk_id %hwnd%
    isDetails := IsDetailsView(hwnd)
    ToolTip % "HWND: " . hwnd
        . "`nWindow class: " . windowClass
        . "`nDetails?: " . (isDetails ? "YES" : "NO")
return

GetThreadFocusHwnd(tid)
{
    ; GUITHREADINFO = two DWORDs, six HWNDs, and one RECT. hwndFocus follows
    ; hwndActive, so its offset is 8 + one pointer on both architectures.
    size := 24 + (A_PtrSize * 6)
    VarSetCapacity(gui, size, 0)
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
    if !activeHwnd
    {
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

EnsureFocusedHwnd(hwndTarget, totalMs := 60, refocusEveryMs := 15)
{
    if !DllCall("user32\IsWindow", "Ptr", hwndTarget, "Int")
        return false

    tidTarget := DllCall("user32\GetWindowThreadProcessId", "Ptr", hwndTarget, "UInt*", 0, "UInt")

    ; already focused?
    if (ControlGetFocusEx(tidTarget, hwndTarget, 0))
        return true

    start         := A_TickCount
    nextRefocus   := 0
    didForeground := false

    Loop
    {
        now := A_TickCount
        if ((now - start) >= totalMs)
            break

        if (now >= nextRefocus)
        {
            ; Foreground only once, retries are cheap (ensureForeground := false)
            FocusHwndFast(hwndTarget, false, !didForeground)
            didForeground := true
            nextRefocus := now + refocusEveryMs
        }

        if (ControlGetFocusEx(tidTarget, hwndTarget, 0))
            return true

        Sleep, 0
    }

    return ControlGetFocusEx(tidTarget, hwndTarget, 0)
}

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
                else
                {
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
; Resolve the ClassNN once, then let EnsureFocusedHwnd() retry focus for at most
; totalMs. Success includes focus on the target HWND or one of its descendants,
; which supports composite controls such as DirectUIHWND*.
EnsureFocusedCtrlNN(hwndTop, ctrlNN, totalMs := 60, refocusEveryMs := 15)
{
    ControlGet, hCtl, Hwnd,, %ctrlNN%, ahk_id %hwndTop%
    if (!hCtl)
        return false
    return EnsureFocusedHwnd(hCtl, totalMs, refocusEveryMs)
}

; Resolve a ClassNN to its current child HWND for focus checks, then fall back
; to ClassNN-based focusing when no stable native handle is available.
EnsureFocusedCtrlTarget(hwndTop, ctrlNN, totalMs := 60, refocusEveryMs := 15, topClass := "")
{
    hCtl := ResolveFocusTargetHwnd(hwndTop, ctrlNN, topClass)
    if (hCtl)
        return EnsureFocusedHwnd(hCtl, totalMs, refocusEveryMs)
    return EnsureFocusedCtrlNN(hwndTop, ctrlNN, totalMs, refocusEveryMs)
}

; Capture the first click on an Explorer/file-dialog DirectUI Items View and
; return that immutable snapshot only when the next physical click matches the
; same HWND and CtrlNN within Windows' double-click time and distance limits.
; Because initialPath is captured before UIA classification, a slow or unknown
; UIA result cannot prevent the later before/after path proof.
_CaptureExplorerDirectUIDoubleClick(hwnd, windowClass, ctrlNN, x, y, initialPath) {
    global k_DoubleClickTime
    static firstClick := ""

    isEligible := (windowClass == "CabinetWClass" || windowClass == "#32770")
               && InStr(ctrlNN, "DirectUIHWND", True)
    if (!isEligible) {
        firstClick := ""
        return ""
    }

    currentTick := A_TickCount
    if IsObject(firstClick) {
        elapsedMs := currentTick - firstClick.tick
        if (elapsedMs < 0)
            elapsedMs += 0x100000000

        maxDeltaX := Max(1, Floor(DllCall("user32\GetSystemMetrics", "Int", 36, "Int") / 2))
        maxDeltaY := Max(1, Floor(DllCall("user32\GetSystemMetrics", "Int", 37, "Int") / 2))
        if (firstClick.hwnd == hwnd
         && firstClick.ctrlNN == ctrlNN
         && firstClick.windowClass == windowClass
         && elapsedMs <= k_DoubleClickTime
         && Abs(x - firstClick.x) <= maxDeltaX
         && Abs(y - firstClick.y) <= maxDeltaY) {
            matchedClick := firstClick
            firstClick   := ""
            return matchedClick
        }
    }

    firstClick := { ctrlNN: ctrlNN
                  , hwnd: hwnd
                  , initialPath: initialPath
                  , tick: currentTick
                  , windowClass: windowClass
                  , x: x
                  , y: y }
    return ""
}

; Classify a UIA hit in an Explorer/file-dialog navigation header. The literal
; return value tells callers whether the hit keeps the same directory (Refresh),
; changes directory, is unrelated, or could not be read safely.
_GetExplorerHeaderNavigationKind(screenX, screenY, timeoutMs := 250) {
    hitEl := SafeUIA_ElementFromPoint(screenX, screenY, "", timeoutMs)
    controlType := SafeUIA_GetControlType(hitEl)
    if (controlType = "")
        return "unavailable"

    controlName          := SafeUIA_GetName(hitEl)
    localizedControlType := SafeUIA_GetLocalizedControlType(hitEl)
    if !_IsHeaderNavigationCtrlAddCandidate(controlType, controlName, localizedControlType)
        return "none"

    if (controlType == 50000 && InStr(controlName, "Refresh", True))
        return "refresh"

    return "path_change"
}

; Return true for the ClassNNs that host Explorer/file-dialog navigation header
; buttons and breadcrumb elements. SysHeader32 is intentionally excluded because
; it is the Details column header, not the window navigation header.
_IsExplorerNavigationHeaderCtrl(ctrlNN) {
    return (   InStr(ctrlNN, "ToolbarWindow32", True)
            || InStr(ctrlNN, "ReBarWindow32", True)
            || InStr(ctrlNN, "Microsoft.UI.Content.DesktopChildSiteBridge", True)
            || InStr(ctrlNN, "Windows.UI.Composition.DesktopWindowContentBridge", True))
}

; Return true when a click can start either tree-folder or header navigation in
; Explorer or a file dialog. This is also the narrow scope in which capturing the
; current directory during an activation click is worth the additional work.
_IsExplorerNavigationSurfaceCtrl(ctrlNN) {
    return InStr(ctrlNN, "SysTreeView32", True) || _IsExplorerNavigationHeaderCtrl(ctrlNN)
}

#MaxThreadsPerHotkey 2
#If
; Schedule a conservative post-activation recovery for the first click into an
; inactive Explorer/file-dialog window. The live $~LButton path captures the
; directory baseline and header action when the ClassNN is a tree/header surface,
; then returns without running the heavier blank-space or SendCtrlAdd
; classification. This helper preserves that narrow snapshot so bounded timer
; retries can wait for both window activation and physical mouse release.
_RequestPostActivationLButtonCheck(hwnd, ctrlNN, clickX, clickY, initialPath := "", headerKind := "") {
    global k_postActivationLButtonDelayMs
    global k_postActivationLButtonTimeoutMs
    global postActivationLButtonCtrl
    global postActivationLButtonDeadlineTick
    global postActivationLButtonHeaderKind
    global postActivationLButtonHwnd
    global postActivationLButtonId
    global postActivationLButtonInitialPath
    global postActivationLButtonX
    global postActivationLButtonY

    ; Publish one complete snapshot of the activation click. The timer copies
    ; this into locals immediately so later clicks cannot partially mutate its
    ; decision state.
    postActivationLButtonId          += 1
    postActivationLButtonCtrl        := ctrlNN
    postActivationLButtonDeadlineTick := A_TickCount + k_postActivationLButtonTimeoutMs
    postActivationLButtonHeaderKind  := headerKind
    postActivationLButtonHwnd        := hwnd
    postActivationLButtonInitialPath := initialPath
    postActivationLButtonX           := clickX
    postActivationLButtonY           := clickY
    SetTimer, PostActivationLButtonCheck, % -k_postActivationLButtonDelayMs
}

; Flush buffered Explorer CtrlAdd trace lines to the configured file. The
; buffer is detached while Critical is active so another AHK thread can append
; new events without losing them during the disk write.
_FlushExplorerCtrlAddTrace() {
    global explorerCtrlAddTraceBuffer
    global k_explorerCtrlAddTraceEnabled
    global k_explorerCtrlAddTraceFile

    if (!k_explorerCtrlAddTraceEnabled || explorerCtrlAddTraceBuffer = "")
        return

    Critical, On
    traceChunk := explorerCtrlAddTraceBuffer
    explorerCtrlAddTraceBuffer := ""
    Critical, Off

    FileAppend, %traceChunk%, %k_explorerCtrlAddTraceFile%, UTF-8
    if ErrorLevel {
        ; Preserve the unwritten lines for the next flush attempt rather than
        ; silently losing the evidence when the file is temporarily unavailable.
        Critical, On
        explorerCtrlAddTraceBuffer := traceChunk . explorerCtrlAddTraceBuffer
        Critical, Off
    }
}

; Add one timestamped event to the low-overhead Explorer CtrlAdd trace. Events
; remain in memory until a terminal outcome or the safety limit requests a flush.
_TraceExplorerCtrlAdd(eventName, details := "", flushNow := False, requestId := "") {
    global explorerCtrlAddRequestId
    global explorerCtrlAddTraceBuffer
    global k_explorerCtrlAddTraceBufferChars
    global k_explorerCtrlAddTraceEnabled

    static sessionHeaderWritten := False

    if !k_explorerCtrlAddTraceEnabled
        return

    if (requestId = "")
        requestId := explorerCtrlAddRequestId

    ; A_Now avoids a FormatTime call on every probe, keeping trace overhead out
    ; of the sub-100 ms timing differences this log is intended to measure.
    wallTime := A_Now
    details := StrReplace(StrReplace(details, "`r", "<CR>"), "`n", "<LF>")
    traceLine := wallTime . "." . A_MSec
              . " tick=" . A_TickCount
              . " req=" . requestId
              . " event=" . eventName
    if (details != "")
        traceLine .= " " . details

    Critical, On
    if !sessionHeaderWritten {
        explorerCtrlAddTraceBuffer .= "`r`n=== Explorer CtrlAdd trace session pid="
            . DllCall("kernel32\GetCurrentProcessId", "UInt")
            . " script=" . Chr(34) . A_ScriptFullPath . Chr(34) . " ===`r`n"
        sessionHeaderWritten := True
    }
    explorerCtrlAddTraceBuffer .= traceLine . "`r`n"
    shouldFlush := flushNow
                || StrLen(explorerCtrlAddTraceBuffer) >= k_explorerCtrlAddTraceBufferChars
    Critical, Off

    if shouldFlush
        _FlushExplorerCtrlAddTrace()
}

; Schedule another callback only while requestId still identifies the current
; request. The short Critical section prevents a newer request from being
; published between this validation and the one-shot timer update.
_ScheduleExplorerCtrlAddRetry(requestId, delayMs) {
    global explorerCtrlAddRequestId

    delayMs := Max(1, delayMs)
    Critical, On
    requestIsCurrent := (requestId = explorerCtrlAddRequestId)
    if requestIsCurrent
        SetTimer, RunExplorerCtrlAddWhenReady, % -delayMs
    Critical, Off

    if !requestIsCurrent {
        _TraceExplorerCtrlAdd("request_aborted"
            , "reason=superseded_before_retry_schedule currentRequestId="
            . explorerCtrlAddRequestId, True, requestId)
    }

    return requestIsCurrent
}

; Resolve one request's current directory and retain only that request's successful
; #32770 source preference. The request-ID check prevents a slow stale probe from
; publishing its resolver into a newer navigation request.
_GetExplorerCtrlAddRequestPath(targetHwnd, windowClass, requestId, ByRef requestIsCurrent) {
    global explorerCtrlAddRequestId
    global explorerCtrlAddRequestLocationResolver

    preferredResolver := explorerCtrlAddRequestLocationResolver
    if (windowClass == "#32770") {
        location    := _ResolveDialogFolderLocation(targetHwnd, preferredResolver, requestId)
        currentPath := location.path
        resolver    := location.resolver
    }
    else {
        currentPath := GetExplorerPath(targetHwnd, requestId)
        resolver    := "shell"
    }

    Critical, On
    requestIsCurrent := (requestId = explorerCtrlAddRequestId)
    if (requestIsCurrent && resolver != "")
        explorerCtrlAddRequestLocationResolver := resolver
    Critical, Off

    return currentPath
}

; Start or replace one non-blocking Explorer CtrlAdd request for CabinetWClass
; or #32770. The request covers these scenarios:
; 1. First activation of a new Explorer window: require the same nonempty path
;    twice because there is no prior directory to compare. Confirmed #32770 file
;    dialogs use the same rule when a path is available, but may use Details mode
;    plus visible UIA content when every folder-identity backend returns empty.
; 2. Other path-changing navigation--Back, Forward, Up, breadcrumb,
;    Quick Access/SysTreeView32, and generic file-view double-clicks--requires a
;    nonempty path different from initialPath before examining the destination.
;    Confirmed #32770 header navigation may instead continue when its post-click
;    path remains unavailable after the short initial guard.
; 3. Header navigation: attempt alignment as soon as the required path gate is
;    satisfied, then retain the UIA follow-up so Explorer rebuilds are corrected.
;    Any header click without a usable pre-click path uses guarded early,
;    verified, and final attempts without a path comparison. Confirmed #32770
;    header navigation also uses those attempts if its post-click path is unavailable.
;    Refresh attempts immediately because its path does not change.
; 4. #32770 SysTreeView32 folder navigation: use the same changed-path,
;    Details-mode, and UIA item/empty-result proof as other navigation.
;
; Every verified alignment requires IsDetailsView() plus one UIA ListItem or a
; recognized empty-result message. Header requests additionally make guarded
; best-effort sends so a slow UIA provider cannot delay the first alignment or
; prevent a final attempt. Every changed-path request starts promptly and uses
; the shared bounded fast path-poll profile. A newer call replaces the single
; pending request, and its ID invalidates stale callbacks.
_RequestExplorerCtrlAdd(hwnd, windowClass, sourceCtrlNN := "", delayMs := 0, initialPath := "", requirePathChange := False, requireStablePath := False, minimumContentProbeDelayMs := 0, restoreTreeFocus := True, attemptImmediateSend := False, allowBestEffortSend := False, allowPathlessContentReady := False, allowUnresolvedPathFallback := False) {
    global explorerCtrlAddRequestAllowBestEffortSend
    global explorerCtrlAddRequestAllowPathlessContentReady
    global explorerCtrlAddRequestAllowUnresolvedPathFallback
    global explorerCtrlAddRequestClass
    global explorerCtrlAddRequestDeadlineTick
    global explorerCtrlAddRequestEarliestContentProbeTick
    global explorerCtrlAddRequestFastPathPollIntervalMs
    global explorerCtrlAddRequestFastPathPollUntilTick
    global explorerCtrlAddRequestHwnd
    global explorerCtrlAddRequestImmediateSendPending
    global explorerCtrlAddRequestId
    global explorerCtrlAddRequestInitialPath
    global explorerCtrlAddRequestLocationResolver
    global explorerCtrlAddRequestPathChangeConfirmed
    global explorerCtrlAddRequestPathlessContentFallbackActive
    global explorerCtrlAddRequestPreProbeSendPending
    global explorerCtrlAddRequestPreviousPath
    global explorerCtrlAddRequestRequirePathChange
    global explorerCtrlAddRequestRequireStablePath
    global explorerCtrlAddRequestRestoreTreeFocus
    global explorerCtrlAddRequestStartTick
    global explorerCtrlAddRequestSourceCtrl
    global explorerCtrlAddRequestStablePathConfirmed
    global explorerCtrlAddRequestStablePathHitCount
    global k_explorerCtrlAddFastPathPollMs
    global k_explorerCtrlAddFastPathWindowMs
    global k_explorerCtrlAddPollMs
    global k_explorerCtrlAddTimeoutMs
    global k_newExplorerCtrlAddTimeoutMs

    if (!hwnd || !(windowClass == "CabinetWClass" || windowClass == "#32770")) {
        _TraceExplorerCtrlAdd("request_rejected"
            , "reason=invalid_window hwnd=" . hwnd . " class=[" . windowClass . "]"
            , True)
        return
    }

    ; Generic path-changing callers require a pre-click directory. The header
    ; wrapper converts only a confirmed header hit without a baseline into a
    ; guarded request before it reaches this validation.
    if (requirePathChange && initialPath = "") {
        _TraceExplorerCtrlAdd("request_rejected"
            , "reason=missing_initial_path hwnd=" . hwnd . " class=" . windowClass
            , True)
        return
    }

    ; A request must either prove a changed path or establish a stable startup
    ; path; requiring both would give the timer contradictory completion rules.
    if (requirePathChange && requireStablePath) {
        _TraceExplorerCtrlAdd("request_rejected"
            , "reason=contradictory_path_gates hwnd=" . hwnd . " class=" . windowClass
            , True)
        return
    }

    if (requireStablePath) {
        readinessTimeoutMs := k_newExplorerCtrlAddTimeoutMs
    }
    else {
        ; A minimum settling delay must not consume the subsequent bounded
        ; Details/content probe window.
        readinessTimeoutMs := k_explorerCtrlAddTimeoutMs + Max(0, minimumContentProbeDelayMs)
    }

    useFastPathPolling := requirePathChange

    requestStartTick                              := A_TickCount
    explorerCtrlAddRequestAllowBestEffortSend     := allowBestEffortSend
    explorerCtrlAddRequestAllowPathlessContentReady := allowPathlessContentReady
    explorerCtrlAddRequestAllowUnresolvedPathFallback := allowUnresolvedPathFallback
    explorerCtrlAddRequestClass                   := windowClass
    explorerCtrlAddRequestDeadlineTick            := requestStartTick + readinessTimeoutMs
    explorerCtrlAddRequestEarliestContentProbeTick := requestStartTick + Max(0, minimumContentProbeDelayMs)
    explorerCtrlAddRequestFastPathPollIntervalMs  := useFastPathPolling ? k_explorerCtrlAddFastPathPollMs : 0
    explorerCtrlAddRequestFastPathPollUntilTick   := useFastPathPolling ? requestStartTick + k_explorerCtrlAddFastPathWindowMs : 0
    explorerCtrlAddRequestHwnd                    := hwnd
    explorerCtrlAddRequestImmediateSendPending    := attemptImmediateSend
    explorerCtrlAddRequestId                      += 1
    explorerCtrlAddRequestInitialPath             := initialPath
    explorerCtrlAddRequestLocationResolver        := ""
    explorerCtrlAddRequestPathChangeConfirmed     := !requirePathChange
    explorerCtrlAddRequestPathlessContentFallbackActive := False
    explorerCtrlAddRequestPreProbeSendPending     := allowBestEffortSend && !attemptImmediateSend
    explorerCtrlAddRequestPreviousPath            := ""
    explorerCtrlAddRequestRequirePathChange       := requirePathChange
    explorerCtrlAddRequestRequireStablePath       := requireStablePath
    explorerCtrlAddRequestRestoreTreeFocus        := restoreTreeFocus
    explorerCtrlAddRequestStartTick               := requestStartTick
    explorerCtrlAddRequestSourceCtrl              := sourceCtrlNN
    explorerCtrlAddRequestStablePathConfirmed     := !requireStablePath
    explorerCtrlAddRequestStablePathHitCount      := 0
    ; Changed-path checks start at the next timer opportunity. Other requests use
    ; the shared poll interval and schedule exact remaining minimum-gate delays.
    initialPollMs := (useFastPathPolling || attemptImmediateSend) ? 1 : k_explorerCtrlAddPollMs
    timerDelay    := (delayMs > 0) ? -delayMs : -initialPollMs
    _TraceExplorerCtrlAdd("request_started"
        , "hwnd=" . hwnd
        . " class=" . windowClass
        . " sourceCtrl=[" . sourceCtrlNN . "]"
        . " initialPath=[" . initialPath . "]"
        . " requirePathChange=" . requirePathChange
        . " requireStablePath=" . requireStablePath
        . " restoreTreeFocus=" . restoreTreeFocus
        . " attemptImmediateSend=" . attemptImmediateSend
        . " allowBestEffortSend=" . allowBestEffortSend
        . " allowPathlessContentReady=" . allowPathlessContentReady
        . " allowUnresolvedPathFallback=" . allowUnresolvedPathFallback
        . " minimumContentProbeDelayMs=" . minimumContentProbeDelayMs
        . " timeoutMs=" . readinessTimeoutMs
        . " firstTimerMs=" . Abs(timerDelay))
    SetTimer, RunExplorerCtrlAddWhenReady, %timerDelay%
}

; Request the common non-blocking follow-up for navigation commands in an
; Explorer or file dialog header. Trace the classified command and its baseline
; before publishing the request so failures before request creation remain visible.
; Directory-changing commands normally advance beyond the path captured before
; the click. Any header request without a pre-click baseline uses guarded early,
; verified, and final attempts without a path comparison. When a baseline exists,
; only confirmed #32770 header navigation may continue if the post-click path is
; unavailable. A nonempty unchanged path still must change.
; Refresh can attempt immediately because it has no changed-path gate.
_RequestHeaderNavigationCtrlAdd(hwnd, windowClass, initialPath := "", requirePathChange := False, minimumContentProbeDelayMs := 0, attemptImmediateSend := False) {
    headerWithoutBaseline      := requirePathChange && initialPath = ""
    effectiveRequirePathChange := requirePathChange && !headerWithoutBaseline
    headerKind                 := headerWithoutBaseline
        ? "path_change_no_baseline"
        : (requirePathChange ? "path_change" : "refresh")
    _TraceExplorerCtrlAdd("header_request_prepare"
        , "hwnd=" . hwnd
        . " class=" . windowClass
        . " headerKind=" . headerKind
        . " initialPath=[" . initialPath . "]"
        . " rejectionReason=[]")
    _RequestExplorerCtrlAdd(hwnd, windowClass, "", 0, initialPath, effectiveRequirePathChange
        , False, minimumContentProbeDelayMs, False, attemptImmediateSend, True
        , False, windowClass == "#32770" && requirePathChange)
}

; Focus and verify the supplied ClassNN, then use the shared immediate
; Ctrl+NumpadAdd path so click handlers reuse the same modifier cleanup.
_SendFocusedCtrlAdd(hwndTop, ctrlNN, totalMs := 60, refocusEveryMs := 15, syncPassCount := 6) {
    if !EnsureFocusedCtrlNN(hwndTop, ctrlNN, totalMs, refocusEveryMs)
        return False
    return SendCtrlNumpadAdd(syncPassCount)
}

; Return true only for header-region UIA hits that match known Explorer/file-dialog
; controls which should start a deferred CtrlAdd request after navigation begins.
_IsHeaderNavigationCtrlAddCandidate(controlType, controlName := "", localizedControlType := "") {
    if (controlType == 50000)
        return (InStr(controlName, "Back", True)
             || InStr(controlName, "Forward", True)
             || InStr(controlName, "Up", True)
             || InStr(controlName, "Refresh", True))

    if (controlType == 50011 || controlType == 50020)
        return True

    ; Accept split-button hits unless UIA identifies the Open split button itself.
    if (controlType == 50031)
        return !(InStr(controlName, "Open", True) && InStr(localizedControlType, "split", True))

    return False
}

; Recheck the pending Explorer CtrlAdd request until its required path, minimum
; settling delay, Details-mode, and UIA item/empty-result conditions are
; satisfied, then call SendCtrlAdd().
; The request is processed according to its source scenario:
; 1. New Explorer activation: sample the same nonempty GetExplorerPath() result
;    twice before checking the file view. Confirmed #32770 activation may use the
;    same Details/content proof without a path when every path backend returns empty.
; 2. Other path-changing navigation: require a nonempty path different from the
;    path captured before the click so the old directory cannot authorize it.
; 3. Header navigation: send once after its path gate, then align again after the
;    shared file-view readiness proof. Any header request without a pre-click
;    baseline uses the same guarded sends without a path comparison. Only confirmed
;    #32770 header navigation may also continue when its post-click path is
;    unavailable. A nonempty unchanged path remains gated.
;    Refresh makes its first send immediately.
; 4. #32770 SysTreeView32 navigation: use the same changed-path and file-view
;    readiness proof as the other path-changing scenarios.
;
; Every verified send requires IsDetailsView() to report Details mode and UIA to
; expose one ListItem or a recognized empty-result message. Header requests also
; make guarded best-effort sends before UIA and after a failed final probe, so a
; provider timeout cannot delay the first alignment or suppress every attempt.
; Each retry uses a one-shot SetTimer rather than a Sleep loop.
RunExplorerCtrlAddWhenReady:
    requestAllowBestEffortSend       := explorerCtrlAddRequestAllowBestEffortSend
    requestAllowPathlessContentReady := explorerCtrlAddRequestAllowPathlessContentReady
    requestAllowUnresolvedPathFallback := explorerCtrlAddRequestAllowUnresolvedPathFallback
    requestWindowClass                := explorerCtrlAddRequestClass
    requestDeadlineTick               := explorerCtrlAddRequestDeadlineTick
    requestEarliestContentProbeTick   := explorerCtrlAddRequestEarliestContentProbeTick
    requestFastPathPollMs             := explorerCtrlAddRequestFastPathPollIntervalMs
    requestFastPathUntilTick          := explorerCtrlAddRequestFastPathPollUntilTick
    requestTargetHwnd                 := explorerCtrlAddRequestHwnd
    requestImmediateSendPending       := explorerCtrlAddRequestImmediateSendPending
    requestId                         := explorerCtrlAddRequestId
    requestInitialPath                := explorerCtrlAddRequestInitialPath
    requestPreProbeSendPending        := explorerCtrlAddRequestPreProbeSendPending
    requestRequiresPathChange         := explorerCtrlAddRequestRequirePathChange
    requestRequiresStablePath         := explorerCtrlAddRequestRequireStablePath
    requestRestoreTreeFocus           := explorerCtrlAddRequestRestoreTreeFocus
    requestStartTick                  := explorerCtrlAddRequestStartTick
    requestSourceCtrl                 := explorerCtrlAddRequestSourceCtrl
    ; Track the independent startup-path gate: even when the current file view
    ; passes the Details/content probe, alignment must wait for a second timer
    ; sample proving that the same nonempty startup path still owns it.
    waitingForSecondStartupPathSample := False

    requestElapsedMs := A_TickCount - requestStartTick
    _TraceExplorerCtrlAdd("timer_enter"
        , "elapsedMs=" . requestElapsedMs
        . " deadlineRemainingMs=" . (requestDeadlineTick - A_TickCount)
        . " pathConfirmed=" . explorerCtrlAddRequestPathChangeConfirmed
        . " stablePathConfirmed=" . explorerCtrlAddRequestStablePathConfirmed
        . " lbutton=" . GetKeyState("LButton", "P")
        , False, requestId)

    targetExists := requestTargetHwnd && WinExist("ahk_id " . requestTargetHwnd)
    activeHwnd   := WinExist("A")
    if (!requestTargetHwnd || !targetExists || activeHwnd != requestTargetHwnd) {
        _TraceExplorerCtrlAdd("request_aborted"
            , "reason=target_not_foreground_or_gone targetHwnd=" . requestTargetHwnd
            . " targetExists=" . (targetExists ? 1 : 0) . " activeHwnd=" . activeHwnd
            , True, requestId)
        Return
    }

    if (requestId != explorerCtrlAddRequestId) {
        _TraceExplorerCtrlAdd("request_aborted"
            , "reason=superseded currentRequestId=" . explorerCtrlAddRequestId
            , True, requestId)
        Return
    }

    ; A held button is a drag or another click still in progress. Defer this
    ; same request instead of cancelling it; stop retrying at its existing
    ; deadline so a stuck or prolonged press cannot keep the timer alive.
    if GetKeyState("LButton", "P") {
        if (A_TickCount < requestDeadlineTick) {
            lButtonPollMs := (requestFastPathPollMs > 0 && A_TickCount < requestFastPathUntilTick)
                ? requestFastPathPollMs
                : k_explorerCtrlAddPollMs
            _TraceExplorerCtrlAdd("request_wait"
                , "reason=lbutton_held nextTimerMs=" . lButtonPollMs
                , False, requestId)
            _ScheduleExplorerCtrlAddRetry(requestId, lButtonPollMs)
        }
        else
            _TraceExplorerCtrlAdd("request_aborted"
                , "reason=lbutton_held_at_deadline", True, requestId)
        Return
    }

    WinGetClass, currentClass, ahk_id %requestTargetHwnd%
    if (currentClass != requestWindowClass || !(currentClass == "CabinetWClass" || currentClass == "#32770")) {
        _TraceExplorerCtrlAdd("request_aborted"
            , "reason=window_class_changed expected=" . requestWindowClass
            . " actual=" . currentClass, True, requestId)
        Return
    }

    ; Refresh has no changed-path signal, and its pre-refresh view may already
    ; satisfy the Details/content probe. Make an early best-effort alignment for
    ; responsiveness, but do not complete the request: the delayed verified send
    ; remains responsible for correcting an alignment overwritten by rebuilding.
    if (requestImmediateSendPending) {
        Critical, On
        immediateSendClaimed := (requestId = explorerCtrlAddRequestId
            && explorerCtrlAddRequestImmediateSendPending)
        if (immediateSendClaimed)
            explorerCtrlAddRequestImmediateSendPending := False
        Critical, Off

        if (immediateSendClaimed) {
            immediateResolvedTarget := _ResolveCtrlAddTargetForSend(requestTargetHwnd
                , currentClass, requestSourceCtrl, requestId)
            _TraceExplorerCtrlAdd("sendctrladd_immediate"
                , "elapsedMs=" . (A_TickCount - requestStartTick)
                . " hasResolvedTarget=" . IsObject(immediateResolvedTarget)
                , False, requestId)
            SendCtrlAdd(requestTargetHwnd, currentClass, requestSourceCtrl, False, ""
                , requestRestoreTreeFocus, immediateResolvedTarget, requestId)
            if (requestId != explorerCtrlAddRequestId) {
                _TraceExplorerCtrlAdd("request_aborted"
                    , "reason=superseded_during_immediate_send currentRequestId="
                    . explorerCtrlAddRequestId, True, requestId)
                Return
            }
        }
    }

    ; A startup request has no previous directory to compare. After the settling
    ; period, require the same nonempty path on two timer samples before checking
    ; Details mode and UIA item/empty-result evidence.
    if (requestRequiresStablePath && !explorerCtrlAddRequestStablePathConfirmed
     && !explorerCtrlAddRequestPathlessContentFallbackActive) {
        if (A_TickCount < requestEarliestContentProbeTick) {
            remainingContentProbeDelayMs := Max(1, requestEarliestContentProbeTick - A_TickCount)
            _TraceExplorerCtrlAdd("request_wait"
                , "reason=startup_minimum_delay nextTimerMs=" . remainingContentProbeDelayMs
                , False, requestId)
            _ScheduleExplorerCtrlAddRetry(requestId, remainingContentProbeDelayMs)
            Return
        }

        pathProbeStartTick := A_TickCount
        pathProbeRequestIsCurrent := False
        currentPath := _GetExplorerCtrlAddRequestPath(requestTargetHwnd
            , requestWindowClass, requestId, pathProbeRequestIsCurrent)
        pathProbeElapsedMs := A_TickCount - pathProbeStartTick
        if !pathProbeRequestIsCurrent {
            _TraceExplorerCtrlAdd("request_aborted"
                , "reason=superseded_during_startup_path_probe currentRequestId="
                . explorerCtrlAddRequestId, True, requestId)
            Return
        }
        _TraceExplorerCtrlAdd("path_probe"
            , "scenario=startup elapsedMs=" . pathProbeElapsedMs
            . " path=[" . currentPath . "]", False, requestId)

        if (currentPath = "") {
            explorerCtrlAddRequestPreviousPath             := ""
            explorerCtrlAddRequestStablePathHitCount       := 0
            if (requestAllowPathlessContentReady && requestWindowClass == "#32770") {
                ; A confirmed file dialog may expose a valid Details Items View even
                ; when CDM_GETFOLDERPATH and breadcrumb identity resolution both fail.
                explorerCtrlAddRequestPathlessContentFallbackActive := True
                explorerCtrlAddRequestDeadlineTick := A_TickCount + k_explorerCtrlAddTimeoutMs
                requestDeadlineTick                := explorerCtrlAddRequestDeadlineTick
                _TraceExplorerCtrlAdd("startup_pathless_content_fallback"
                    , "newContentDeadlineMs=" . k_explorerCtrlAddTimeoutMs
                    , False, requestId)
            }
            else if (A_TickCount < requestDeadlineTick) {
                _TraceExplorerCtrlAdd("request_wait"
                    , "reason=startup_path_empty nextTimerMs=" . k_explorerCtrlAddPollMs
                    , False, requestId)
                _ScheduleExplorerCtrlAddRetry(requestId, k_explorerCtrlAddPollMs)
            }
            else
                _TraceExplorerCtrlAdd("request_aborted"
                    , "reason=startup_path_empty_at_deadline", True, requestId)
            if (!explorerCtrlAddRequestPathlessContentFallbackActive)
                Return
        }
        else if (currentPath = explorerCtrlAddRequestPreviousPath) {
            explorerCtrlAddRequestStablePathHitCount += 1
        }
        else {
            explorerCtrlAddRequestPreviousPath             := currentPath
            explorerCtrlAddRequestStablePathHitCount       := 1
        }

        if !explorerCtrlAddRequestPathlessContentFallbackActive {
            if (explorerCtrlAddRequestStablePathHitCount < 2) {
                waitingForSecondStartupPathSample := True
                _TraceExplorerCtrlAdd("startup_path_sampled"
                    , "hits=" . explorerCtrlAddRequestStablePathHitCount
                    . " path=[" . currentPath . "]", False, requestId)
            }
            else {
                ; Give the confirmed startup directory its own bounded file-view
                ; readiness window.
                explorerCtrlAddRequestDeadlineTick        := A_TickCount + k_explorerCtrlAddTimeoutMs
                requestDeadlineTick                       := explorerCtrlAddRequestDeadlineTick
                explorerCtrlAddRequestStablePathConfirmed := True
                _TraceExplorerCtrlAdd("startup_path_confirmed"
                    , "path=[" . currentPath . "] newContentDeadlineMs="
                    . k_explorerCtrlAddTimeoutMs, False, requestId)
            }
        }
    }
    else if (requestRequiresStablePath
     && !explorerCtrlAddRequestPathlessContentFallbackActive) {
        ; Keep proving that the same startup destination remains current. If
        ; Explorer changes paths, restart the non-blocking startup readiness check.
        pathProbeStartTick := A_TickCount
        pathProbeRequestIsCurrent := False
        currentPath := _GetExplorerCtrlAddRequestPath(requestTargetHwnd
            , requestWindowClass, requestId, pathProbeRequestIsCurrent)
        pathProbeElapsedMs := A_TickCount - pathProbeStartTick
        if !pathProbeRequestIsCurrent {
            _TraceExplorerCtrlAdd("request_aborted"
                , "reason=superseded_during_startup_revalidation currentRequestId="
                . explorerCtrlAddRequestId, True, requestId)
            Return
        }
        _TraceExplorerCtrlAdd("path_probe"
            , "scenario=startup_revalidate elapsedMs=" . pathProbeElapsedMs
            . " path=[" . currentPath . "]", False, requestId)

        if (currentPath = "" || currentPath != explorerCtrlAddRequestPreviousPath) {
            explorerCtrlAddRequestDeadlineTick             := A_TickCount + k_newExplorerCtrlAddTimeoutMs
            explorerCtrlAddRequestEarliestContentProbeTick := A_TickCount + k_newExplorerCtrlAddMinimumWaitMs
            explorerCtrlAddRequestPreviousPath             := currentPath
            explorerCtrlAddRequestStablePathConfirmed      := False
            explorerCtrlAddRequestStablePathHitCount       := (currentPath = "") ? 0 : 1
            _TraceExplorerCtrlAdd("startup_path_reset"
                , "path=[" . currentPath . "] nextTimerMs=" . k_explorerCtrlAddPollMs
                , False, requestId)
            _ScheduleExplorerCtrlAddRetry(requestId, k_explorerCtrlAddPollMs)
            Return
        }
    }

    ; Back, Forward, Up, breadcrumb, and SysTreeView32 navigation normally must
    ; report a different nonempty directory before alignment. A confirmed #32770
    ; header request may bypass only an unavailable post-click path after the
    ; short guard; a nonempty unchanged path remains gated to protect the old view.
    if (requestRequiresPathChange && !explorerCtrlAddRequestPathChangeConfirmed) {
        pathProbeStartTick := A_TickCount
        pathProbeRequestIsCurrent := False
        currentPath := _GetExplorerCtrlAddRequestPath(requestTargetHwnd
            , requestWindowClass, requestId, pathProbeRequestIsCurrent)
        pathProbeElapsedMs := A_TickCount - pathProbeStartTick
        if !pathProbeRequestIsCurrent {
            _TraceExplorerCtrlAdd("request_aborted"
                , "reason=superseded_during_navigation_path_probe currentRequestId="
                . explorerCtrlAddRequestId, True, requestId)
            Return
        }
        _TraceExplorerCtrlAdd("path_probe"
            , "scenario=navigation elapsedMs=" . pathProbeElapsedMs
            . " initialPath=[" . requestInitialPath . "]"
            . " currentPath=[" . currentPath . "]", False, requestId)

        if (currentPath = "" && requestAllowUnresolvedPathFallback
         && requestWindowClass == "#32770") {
            ; Match the existing no-baseline header timing rather than sending at
            ; the first 1 ms path poll. This gives the dialog one short opportunity
            ; to publish a comparable destination before guarded alignment proceeds.
            ; Recalculate elapsed time after path resolution so a slow resolver does
            ; not add an unnecessary timer interval to this short safety guard.
            unresolvedPathGuardRemainingMs := k_explorerCtrlAddPollMs
                - (A_TickCount - requestStartTick)
            if (unresolvedPathGuardRemainingMs > 0) {
                _TraceExplorerCtrlAdd("request_wait"
                    , "reason=unresolved_path_fallback_guard nextTimerMs="
                    . unresolvedPathGuardRemainingMs, False, requestId)
                _ScheduleExplorerCtrlAddRetry(requestId, unresolvedPathGuardRemainingMs)
                Return
            }

            ; The confirmed header hit, foreground-window guard, and subsequent
            ; Details/content probe now authorize the same pathless flow used when
            ; no pre-click baseline was available. Give that probe a fresh window.
            explorerCtrlAddRequestDeadlineTick       := A_TickCount + k_explorerCtrlAddTimeoutMs
            explorerCtrlAddRequestRequirePathChange  := False
            requestDeadlineTick                      := explorerCtrlAddRequestDeadlineTick
            requestRequiresPathChange                := False
            _TraceExplorerCtrlAdd("navigation_unresolved_path_fallback"
                , "initialPath=[" . requestInitialPath . "] newContentDeadlineMs="
                . k_explorerCtrlAddTimeoutMs, False, requestId)
        }
        else if (currentPath = "" || currentPath = requestInitialPath) {
            if (A_TickCount < requestDeadlineTick) {
                pathPollMs := (requestFastPathPollMs > 0 && A_TickCount < requestFastPathUntilTick)
                    ? requestFastPathPollMs
                    : k_explorerCtrlAddPollMs
                _TraceExplorerCtrlAdd("request_wait"
                    , "reason=path_not_changed nextTimerMs=" . pathPollMs
                    , False, requestId)
                _ScheduleExplorerCtrlAddRetry(requestId, pathPollMs)
            }
            else
                _TraceExplorerCtrlAdd("request_aborted"
                    , "reason=path_not_changed_at_deadline initialPath=["
                    . requestInitialPath . "] currentPath=[" . currentPath . "]"
                    , True, requestId)
            Return
        }

        else {
            ; Give the destination file view its own bounded Details/content window.
            ; Otherwise a slow path change could consume the original deadline.
            explorerCtrlAddRequestDeadlineTick        := A_TickCount + k_explorerCtrlAddTimeoutMs
            requestDeadlineTick                       := explorerCtrlAddRequestDeadlineTick
            explorerCtrlAddRequestPathChangeConfirmed := True
            _TraceExplorerCtrlAdd("path_change_confirmed"
                , "currentPath=[" . currentPath . "] newContentDeadlineMs="
                . k_explorerCtrlAddTimeoutMs, False, requestId)
        }

    }

    ; Startup and Refresh requests honor their minimum settling gate before any
    ; Details/content UIA probe. Schedule the exact remaining delay so the timer
    ; does not overshoot the requested gate by a full polling interval.
    if (A_TickCount < requestEarliestContentProbeTick) {
        remainingContentProbeDelayMs := Max(1, requestEarliestContentProbeTick - A_TickCount)
        _TraceExplorerCtrlAdd("request_wait"
            , "reason=minimum_content_probe_delay nextTimerMs=" . remainingContentProbeDelayMs
            , False, requestId)
        _ScheduleExplorerCtrlAddRetry(requestId, remainingContentProbeDelayMs)
        Return
    }

    ; Do not spend the UIA budget on the first startup path sample: that probe
    ; result would not be retained and therefore could never authorize alignment.
    if (waitingForSecondStartupPathSample) {
        if (A_TickCount < requestDeadlineTick) {
            nextPollMs := Min(k_explorerCtrlAddPollMs
                , Max(1, requestDeadlineTick - A_TickCount))
            _TraceExplorerCtrlAdd("request_wait"
                , "reason=second_startup_path_sample nextTimerMs="
                . nextPollMs, False, requestId)
            _ScheduleExplorerCtrlAddRetry(requestId, nextPollMs)
        }
        else
            _TraceExplorerCtrlAdd("request_aborted"
                , "reason=second_startup_path_sample_missed_deadline"
                , True, requestId)
        Return
    }

    ; A header request either proved a changed path, lacked a pre-click baseline,
    ; or entered through the permitted #32770 post-click path fallback. Align once
    ; before synchronous UIA so a
    ; slow provider cannot delay the user-visible result; retain the request for
    ; the verified corrective send after the file view exposes content.
    if (requestPreProbeSendPending) {
        preProbeTargetExists := requestTargetHwnd && WinExist("ahk_id " . requestTargetHwnd)
        preProbeActiveHwnd   := WinExist("A")
        if (!preProbeTargetExists || preProbeActiveHwnd != requestTargetHwnd) {
            _TraceExplorerCtrlAdd("request_aborted"
                , "reason=pre_probe_target_not_foreground_or_gone targetHwnd="
                . requestTargetHwnd . " targetExists=" . (preProbeTargetExists ? 1 : 0)
                . " activeHwnd=" . preProbeActiveHwnd, True, requestId)
            Return
        }
        if GetKeyState("LButton", "P") {
            if (A_TickCount < requestDeadlineTick) {
                _TraceExplorerCtrlAdd("request_wait"
                    , "reason=pre_probe_lbutton_held nextTimerMs=" . k_explorerCtrlAddPollMs
                    , False, requestId)
                _ScheduleExplorerCtrlAddRetry(requestId, k_explorerCtrlAddPollMs)
            }
            else
                _TraceExplorerCtrlAdd("request_aborted"
                    , "reason=pre_probe_lbutton_held_at_deadline", True, requestId)
            Return
        }

        Critical, On
        preProbeSendClaimed := (requestId = explorerCtrlAddRequestId
            && explorerCtrlAddRequestPreProbeSendPending)
        if (preProbeSendClaimed)
            explorerCtrlAddRequestPreProbeSendPending := False
        Critical, Off

        if (preProbeSendClaimed) {
            preProbeResolvedTarget := _ResolveCtrlAddTargetForSend(requestTargetHwnd
                , currentClass, requestSourceCtrl, requestId)
            _TraceExplorerCtrlAdd("sendctrladd_pre_probe"
                , "elapsedMs=" . (A_TickCount - requestStartTick)
                . " hasResolvedTarget=" . IsObject(preProbeResolvedTarget)
                , False, requestId)
            SendCtrlAdd(requestTargetHwnd, currentClass, requestSourceCtrl, False, ""
                , requestRestoreTreeFocus, preProbeResolvedTarget, requestId)
            if (requestId != explorerCtrlAddRequestId) {
                _TraceExplorerCtrlAdd("request_aborted"
                    , "reason=superseded_during_pre_probe_send currentRequestId="
                    . explorerCtrlAddRequestId, True, requestId)
                Return
            }
        }
    }

    ; Confirm the file panel is in Details mode and exposes either one ListItem
    ; or a recognized empty-result message. Each attempt has a short UIA budget;
    ; an incomplete view is retried by this timer until the request deadline.
    contentProbeStartTick := A_TickCount
    contentProbe := _ProbeExplorerDetailsContentReady(requestTargetHwnd
        , k_explorerCtrlAddPollUIATimeoutMs, requestId)
    contentProbeElapsedMs := A_TickCount - contentProbeStartTick
    contentProbeDetailsReason := contentProbe.HasKey("detailsReason")
        ? contentProbe.detailsReason
        : ""
    contentProbeItemsViewCandidateCount := contentProbe.HasKey("itemsViewCandidateCount")
        ? contentProbe.itemsViewCandidateCount
        : 0
    contentProbeItemsViewResolutionReason := contentProbe.HasKey("itemsViewResolutionReason")
        ? contentProbe.itemsViewResolutionReason
        : ""
    contentProbeItemsViewResolver := contentProbe.HasKey("itemsViewResolver")
        ? contentProbe.itemsViewResolver
        : ""
    contentProbeResolvedTarget := contentProbe.HasKey("resolvedTarget")
        ? contentProbe.resolvedTarget
        : ""
    if (requestId != explorerCtrlAddRequestId) {
        _TraceExplorerCtrlAdd("request_aborted"
            , "reason=superseded_during_content_probe currentRequestId="
            . explorerCtrlAddRequestId
            . " probeElapsedMs=" . contentProbeElapsedMs
            , True, requestId)
        Return
    }
    _TraceExplorerCtrlAdd("details_content_probe"
        , "elapsedMs=" . contentProbeElapsedMs
        . " timeoutMs=" . k_explorerCtrlAddPollUIATimeoutMs
        . " state=" . contentProbe.state
        . " reason=" . contentProbe.reason
        . " detailsReason=[" . contentProbeDetailsReason . "]"
        . " resolver=" . contentProbeItemsViewResolver
        . " candidateCount=" . contentProbeItemsViewCandidateCount
        . " resolutionReason=[" . contentProbeItemsViewResolutionReason . "]"
        , False, requestId)

    if (contentProbe.state != "ready" && A_TickCount < requestDeadlineTick) {
        nextPollMs := Min(k_explorerCtrlAddPollMs
            , Max(1, requestDeadlineTick - A_TickCount))
        _TraceExplorerCtrlAdd("request_wait"
            , "reason=details_content_not_ready nextTimerMs=" . nextPollMs
            . " probeReason=" . contentProbe.reason
            . " detailsReason=[" . contentProbeDetailsReason . "]"
            , False, requestId)
        _ScheduleExplorerCtrlAddRetry(requestId, nextPollMs)
        Return
    }

    if (contentProbe.state != "ready") {
        if !requestAllowBestEffortSend {
            _TraceExplorerCtrlAdd("request_aborted"
                , "reason=details_or_content_not_ready_at_deadline probeReason="
                . contentProbe.reason
                . " detailsReason=[" . contentProbeDetailsReason . "]"
                , True, requestId)
            Return
        }

        ; Header requests already passed button and target classification. Their
        ; path-changing request either proved the destination changed or entered
        ; the #32770 unresolved-path fallback. If UIA cannot prove content by the
        ; deadline, make one final attempt only while that same window is
        ; foreground and no physical click is active.
        finalTargetExists := requestTargetHwnd && WinExist("ahk_id " . requestTargetHwnd)
        finalActiveHwnd   := WinExist("A")
        finalClass        := ""
        WinGetClass, finalClass, ahk_id %requestTargetHwnd%
        if (!finalTargetExists || finalActiveHwnd != requestTargetHwnd
         || finalClass != requestWindowClass || GetKeyState("LButton", "P")) {
            _TraceExplorerCtrlAdd("request_aborted"
                , "reason=best_effort_guard_failed targetExists="
                . (finalTargetExists ? 1 : 0)
                . " activeHwnd=" . finalActiveHwnd
                . " expectedClass=" . requestWindowClass
                . " actualClass=" . finalClass
                . " lbutton=" . GetKeyState("LButton", "P")
                . " probeReason=" . contentProbe.reason
                , True, requestId)
            Return
        }

        bestEffortDispatchElapsedMs := A_TickCount - requestStartTick
        bestEffortSendStartTick := A_TickCount
        bestEffortResolvedTarget := _ResolveCtrlAddTargetForSend(requestTargetHwnd
            , finalClass, requestSourceCtrl, requestId, contentProbeResolvedTarget)
        _TraceExplorerCtrlAdd("sendctrladd_best_effort"
            , "elapsedMs=" . bestEffortDispatchElapsedMs
            . " probeReason=" . contentProbe.reason
            . " detailsReason=[" . contentProbeDetailsReason . "]"
            . " hasResolvedTarget=" . IsObject(bestEffortResolvedTarget)
            , False, requestId)
        SendCtrlAdd(requestTargetHwnd, finalClass, requestSourceCtrl, False, ""
            , requestRestoreTreeFocus, bestEffortResolvedTarget, requestId)
        _TraceExplorerCtrlAdd("sendctrladd_best_effort_dispatch"
            , "elapsedMs=" . bestEffortDispatchElapsedMs
            . " sendElapsedMs=" . (A_TickCount - bestEffortSendStartTick)
            . " probeReason=" . contentProbe.reason
            . " detailsReason=[" . contentProbeDetailsReason . "]"
            , True, requestId)
        Return
    }

    if (requestId != explorerCtrlAddRequestId) {
        _TraceExplorerCtrlAdd("request_aborted"
            , "reason=superseded_after_details_content_probe currentRequestId="
            . explorerCtrlAddRequestId, True, requestId)
        Return
    }

    ; Issue the alignment before synchronously flushing its terminal trace, so
    ; disk or antivirus latency cannot delay the user-visible column adjustment.
    sendCtrlAddDispatchElapsedMs := A_TickCount - requestStartTick
    sendCtrlAddStartTick := A_TickCount
    verifiedResolvedTarget := _ResolveCtrlAddTargetForSend(requestTargetHwnd
        , currentClass, requestSourceCtrl, requestId, contentProbeResolvedTarget)
    SendCtrlAdd(requestTargetHwnd, currentClass, requestSourceCtrl, False, ""
        , requestRestoreTreeFocus, verifiedResolvedTarget, requestId)
    _TraceExplorerCtrlAdd("sendctrladd_dispatch"
        , "elapsedMs=" . sendCtrlAddDispatchElapsedMs
        . " sendElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
        . " readyReason=" . contentProbe.reason
        . " detailsReason=[" . contentProbeDetailsReason . "]"
        . " hasResolvedTarget=" . IsObject(verifiedResolvedTarget)
        , True, requestId)
Return

; Deferred recovery for a first click into an inactive Explorer/file-dialog
; window. This intentionally does not replay the full $~LButton handler: by the
; time this timer runs, the original physical click already went to Windows, so
; the only safe follow-up is the narrow shell case where Ctrl+NumpadAdd was the
; already-expected result. Deferring that shell-only work keeps the activation
; click path cheap, which reduces the chance that immediate post-activation
; typing inherits a long synchronous shell probe and appears delayed or garbled.
PostActivationLButtonCheck:
    ; Copy the pending snapshot first; every later guard validates that it still
    ; describes the current foreground target.
    queuedId           := postActivationLButtonId
    deadlineTick       := postActivationLButtonDeadlineTick
    targetCtrl         := postActivationLButtonCtrl
    capturedHeaderKind := postActivationLButtonHeaderKind
    targetHwnd         := postActivationLButtonHwnd
    initialPath        := postActivationLButtonInitialPath
    clickX             := postActivationLButtonX
    clickY             := postActivationLButtonY

    ; A newer inactive-window click replaced this snapshot, so let the newer
    ; timer instance make the decision.
    if (queuedId != postActivationLButtonId)
        Return

    if (!targetHwnd || !WinExist("ahk_id " . targetHwnd))
        Return

    ; Activation and mouse release do not have deterministic timing. Retry this
    ; one-shot timer until both are complete, but abandon the stale snapshot at
    ; its deadline so no delayed send can reach a later foreground window.
    if (WinExist("A") != targetHwnd || GetKeyState("LButton", "P")) {
        if (A_TickCount < deadlineTick)
            SetTimer, PostActivationLButtonCheck, % -k_postActivationLButtonPollMs
        Return
    }

    ; Keep the delayed recovery scoped to Explorer and common file dialogs, the
    ; only windows where this first-click Ctrl+NumpadAdd behavior is intended.
    WinGetClass, targetClass, ahk_id %targetHwnd%
    if !(targetClass == "CabinetWClass" || targetClass == "#32770")
        Return

    ; Ignore unrelated controls in those windows. The deferred path must stay
    ; narrower than the normal click handler because it runs after activation.
    if  !(InStr(targetCtrl, "DirectUIHWND", True)
       || InStr(targetCtrl, "SysListView32", True)
       || InStr(targetCtrl, "SysHeader32", True)
       || _IsExplorerNavigationSurfaceCtrl(targetCtrl))
        Return

    ; Re-run title-bar filtering after activation so caption/title clicks do not
    ; get mistaken for shell-view clicks.
    titleBarState := _GetTitleBarProbeState(clickX, clickY, False, targetHwnd, targetCtrl, targetClass)
    if (titleBarState == "caption")
        Return

    if (titleBarState == "other"
     && WindowNeedsTitleBarUIA(targetHwnd, targetClass)
     && MouseIsOverTitleBarDeferred(clickX, clickY, False, targetHwnd, targetCtrl, targetClass))
        Return

    ; Any completed SysTreeView32 click may select a Quick Access folder. Avoid
    ; UIA hit classification: only a changed path can authorize column alignment,
    ; so expand/collapse and same-folder clicks expire without calling SendCtrlAdd().
    if (InStr(targetCtrl, "SysTreeView32", True)) {
        _RequestExplorerCtrlAdd(targetHwnd, targetClass, targetCtrl, 0, initialPath, True)
        Return
    }

    ; Prefer the completed click's mouse-down classification to avoid another UIA
    ; lookup. Fall back to a live classification when that probe was inconclusive.
    if (_IsExplorerNavigationHeaderCtrl(targetCtrl)) {
        headerKind := capturedHeaderKind
        if !(headerKind = "refresh" || headerKind = "path_change")
            headerKind := _GetExplorerHeaderNavigationKind(clickX, clickY, 250)
        if (queuedId != postActivationLButtonId)
            Return

        if !(headerKind = "refresh" || headerKind = "path_change") {
            rejectionReason := (headerKind = "unavailable")
                ? "header_kind_unavailable"
                : "header_kind_not_navigation"
            _TraceExplorerCtrlAdd("header_request_rejected"
                , "hwnd=" . targetHwnd
                . " class=" . targetClass
                . " sourceCtrl=[" . targetCtrl . "]"
                . " headerKind=" . headerKind
                . " initialPath=[" . initialPath . "]"
                . " rejectionReason=" . rejectionReason
                , True)
            Return
        }

        if (headerKind = "refresh") {
            _RequestHeaderNavigationCtrlAdd(targetHwnd, targetClass, initialPath, False
                , k_explorerCtrlAddRefreshMinimumWaitMs, True)
        }
        else if (headerKind = "path_change")
            _RequestHeaderNavigationCtrlAdd(targetHwnd, targetClass, initialPath, True)
        Return
    }

    ; Header clicks are the clearest safe case: once the target is active, focus
    ; the captured header control and send the normal auto-fit command.
    if (InStr(targetCtrl, "SysHeader32", True)) {
        _SendFocusedCtrlAdd(targetHwnd, targetCtrl)
        Return
    }

    ; For Explorer/file-dialog item-list controls, only recover blank-space
    ; clicks. Item clicks may select or navigate, and replaying that broader
    ; logic here would be more invasive than this activation-click fix should be.
    postActivationBlankClick := False
    if (InStr(targetCtrl, "DirectUIHWND", True)) {
        if (targetClass == "#32770")
            clickKind := DialogClickClassify(clickX, clickY, targetCtrl)
        else
            clickKind := ExplorerClickClassify(clickX, clickY, targetCtrl)

        if (clickKind == "header") {
            _SendFocusedCtrlAdd(targetHwnd, targetCtrl)
            Return
        }
        else if (clickKind == "blank")
            postActivationBlankClick := True
        else if (targetClass == "#32770" && clickKind == "")
            postActivationBlankClick := AreaLooksUniformFast(clickX, clickY)
    }
    else if (InStr(targetCtrl, "SysListView32", True)) {
        ; Classify the captured click point, so moving the pointer while the
        ; activation timer is pending cannot change which pixels are inspected.
        postActivationBlankClick := IsSysListViewBlankSpaceClick(clickX, clickY)
    }

    ; Force the shell-view wait path because this recovery runs immediately after
    ; activation and may need the target to settle before Ctrl+NumpadAdd is useful.
    if (postActivationBlankClick)
        SendCtrlAdd(targetHwnd, targetClass, targetCtrl, True)
Return

; Recognize a same-control double-click using Windows' configured time and
; distance limits, then clear the window's manual-column-resize block. The first
; click is retained briefly; other clicks reset that candidate without clearing
; the block. Return true so the caller can request alignment after mouse-up.
_TryClearSendCtrlBlockOnListViewDoubleClick(windowHwnd, ctrlNN, clickX, clickY) {
    global disableSendCtrlHwnd

    static firstClickCtrlNN := ""
    static firstClickHwnd   := 0
    static firstClickTick   := 0
    static firstClickX      := 0
    static firstClickY      := 0

    if (disableSendCtrlHwnd != windowHwnd || !InStr(ctrlNN, "SysListView32", True)) {
        firstClickCtrlNN := ""
        firstClickHwnd   := 0
        firstClickTick   := 0
        firstClickX      := 0
        firstClickY      := 0
        return False
    }

    doubleClickHeight := DllCall("user32\GetSystemMetrics", "Int", 37, "Int")
    doubleClickTime   := DllCall("user32\GetDoubleClickTime", "UInt")
    doubleClickWidth  := DllCall("user32\GetSystemMetrics", "Int", 36, "Int")
    elapsedMs         := A_TickCount - firstClickTick

    if (firstClickHwnd == windowHwnd
     && firstClickCtrlNN == ctrlNN
     && elapsedMs >= 0
     && elapsedMs <= doubleClickTime
     && Abs(clickX - firstClickX) <= Floor(doubleClickWidth / 2)
     && Abs(clickY - firstClickY) <= Floor(doubleClickHeight / 2)) {
        disableSendCtrlHwnd := ""
        firstClickCtrlNN    := ""
        firstClickHwnd      := 0
        firstClickTick      := 0
        firstClickX         := 0
        firstClickY         := 0
        return True
    }

    firstClickCtrlNN := ctrlNN
    firstClickHwnd   := windowHwnd
    firstClickTick   := A_TickCount
    firstClickX      := clickX
    firstClickY      := clickY
    return False
}

#MaxThreadsPerHotkey 2
#If !VolumeHover() && !IsOverException() && LbuttonEnabled && !hitTAB && !MouseIsOverTitleBarFast(,,False) && !MouseIsOverTaskbarWidgets() && !MouseIsOverCaptionButtons()
$~LButton::
    CoordMode, Mouse, Screen
    MouseGetPos, lbX1, lbY1, _winIdD, _winCtrlD
    activeBeforeLButton := WinExist("A")
    ; The first blank click defers alignment for 125 ms so a second click can
    ; cancel that pending single-click action before double-click navigation.
    SetTimer, SendCtrlAddLabel, Off
    CancelTbcTypingWorkForContextChange()

    WinGetClass, _winClassD, ahk_id %_winIdD%
    isExplorerDirectUIClick := (_winClassD == "CabinetWClass" || _winClassD == "#32770")
                            && InStr(_winCtrlD, "DirectUIHWND", True)
    isExplorerNavigationHeader := (_winClassD == "CabinetWClass" || _winClassD == "#32770")
                               && _IsExplorerNavigationHeaderCtrl(_winCtrlD)

    ; Classify a header click before any directory lookup. A recognized Refresh
    ; keeps the same directory, so it skips GetExplorerPath() entirely.
    navigationHeaderKind := ""
    if (isExplorerNavigationHeader)
        navigationHeaderKind := _GetExplorerHeaderNavigationKind(lbX1, lbY1, 250)

    navigationStartPath := ""
    shouldCaptureNavigationPath := ((_winClassD == "CabinetWClass" || _winClassD == "#32770")
        && (isExplorerDirectUIClick
         || (!isExplorerNavigationHeader && _IsExplorerNavigationSurfaceCtrl(_winCtrlD))
         || (isExplorerNavigationHeader && navigationHeaderKind != "refresh")))
    if (shouldCaptureNavigationPath)
        navigationStartPath := GetExplorerPath(_winIdD)

    ; Match DirectUI double-clicks from immutable first-click identity and path
    ; data. UIA below may refine blank/item/header behavior, but it no longer
    ; decides whether a native folder navigation receives a path-change watcher.
    explorerDirectUIDoubleClick := _CaptureExplorerDirectUIDoubleClick(_winIdD, _winClassD, _winCtrlD, lbX1, lbY1, navigationStartPath)

    ; If this press is aimed at a different top-level window, defer all UIA hit
    ; testing and column work until Windows completes the focus change.
    if (_winIdD && activeBeforeLButton && _winIdD != activeBeforeLButton) {
        _RequestPostActivationLButtonCheck(_winIdD, _winCtrlD, lbX1, lbY1, navigationStartPath, navigationHeaderKind)
        Return
    }

    titleBarState := _GetTitleBarProbeState(lbX1, lbY1, False, _winIdD, _winCtrlD, _winClassD)

    if (titleBarState == "caption")
        Return

    if (titleBarState == "other"
     && WindowNeedsTitleBarUIA(_winIdD, _winClassD)
     && MouseIsOverTitleBarDeferred(lbX1, lbY1, False, _winIdD, _winCtrlD, _winClassD)) {
        Return
    }

    tooltip,
    GoSub, DisableTimers

    HotString("Reset")

    ; During a native bottom-edge or bottom-corner resize, derive the pointer
    ; limit that stops the window's bottom edge at the top of a bottom taskbar.
    TryStartBottomResizeCursorClamp(lbX1, lbY1, _winIdD)

    ; When the press starts on a plain resizable edge that is already flush to a
    ; visible adjacent window, let the native resize happen and mirror the
    ; partner window with a short timer until LButton is released.
    if (TryStartLButtonResizeSync(lbX1, lbY1, _winIdD))
        return

    clearedSendCtrlBlock := False
    If (disableSendCtrlHwnd != "")
        clearedSendCtrlBlock := _TryClearSendCtrlBlockOnListViewDoubleClick(_winIdD, _winCtrlD, lbX1, lbY1)

    ; A qualifying double-click inside the blocked SysListView re-enables
    ; automatic alignment and requests it if the captured ListView remains eligible.
    ; Wait for mouse-up because SendCtrlAdd() rejects sends while LButton is down;
    ; the native clicks still reach the target through the `~` hotkey prefix.
    If clearedSendCtrlBlock {
        KeyWait, LButton, U T3

        If !GetKeyState("LButton", "P") {
            If (_winClassD == "CabinetWClass" || _winClassD == "#32770") {
                SendCtrlAdd(_winIdD, _winClassD, _winCtrlD)
            }
            Else {
                ControlGet, controlHwnd, Hwnd,, %_winCtrlD%, ahk_id %_winIdD%
                If IsSysListViewReportView(controlHwnd)
                    SendCtrlAdd(_winIdD, _winClassD, _winCtrlD)
            }
        }

        GoSub, EnableTimers
        Return
    }

    If (disableSendCtrlHwnd == _winIdD) {
        GoSub, EnableTimers
        Return
    }
    Else If (!WinExist("ahk_id " . disableSendCtrlHwnd))
        disableSendCtrlHwnd := ""

    ; Chromium webpage clicks do not benefit from the generic non-Explorer
    ; blank-space classification or SendCtrlAdd() flow. The hotkey predicate
    ; already kept title-bar and caption-button clicks out of this branch.
    if (IsChromiumContentClick(_winIdD, _winClassD, _winCtrlD)) {
        GoSub, EnableTimers
        Return
    }

    initTime := A_TickCount

    isLegacyDoubleClick := !isExplorerDirectUIClick
                        && (A_PriorHotkey == A_ThisHotkey)
                        && (A_TimeSincePriorHotkey <= k_DoubleClickTime)
                        && (Abs(lbX1-lbX2) < 25 && Abs(lbY1-lbY2) < 25)
                        && (InStr(_winCtrlD, "SysListView32", True) || InStr(_winCtrlD, "DirectUIHWND", True))
    If (allowDoubleClicks && (IsObject(explorerDirectUIDoubleClick) || isLegacyDoubleClick)) {

        allowDoubleClicks := False
        ; tooltip, %isBlankSpaceExplorer% - %isBlankSpaceNonExplorer%
        If (isBlankSpaceExplorer || isBlankSpaceNonExplorer) {
            If (InStr(_winCtrlD, "SysListView32", True)) {
                Send, {Backspace}
                SetTimer, RunDynaExprTimeout, -1
            }
            Else {
                Send, !{Up}
                SetTimer, RunDynaExprTimeout, -1
            }
        }

        KeyWait, Lbutton, U T3

        If (_winClassD == "CabinetWClass" || _winClassD == "#32770") {
            ; Every DirectUI shell double-click now uses its captured mouse-down
            ; path and the shared changed-path plus Details/content proof. Keep
            ; prevPath only as the legacy fallback for other shell controls.
            doubleClickStartPath := IsObject(explorerDirectUIDoubleClick)
                ? explorerDirectUIDoubleClick.initialPath
                : prevPath
            if (doubleClickStartPath != "")
                _RequestExplorerCtrlAdd(_winIdD, _winClassD, _winCtrlD, 0, doubleClickStartPath, True)
        }
        Else {
            If InStr(_winCtrlD, "SysListView32", True) {
                ControlGet, controlHwnd, Hwnd,, %_winCtrlD%, ahk_id %_winIdD%
                If IsSysListViewReportView(controlHwnd)
                    SendCtrlAdd(_winIdD, _winClassD)
            }
            Else
                SendCtrlAdd(_winIdD, _winClassD)
        }

        GoSub, EnableTimers
        If isBlankSpaceNonExplorer
            isBlankSpaceNonExplorer := False
        If isBlankSpaceExplorer
            isBlankSpaceExplorer    := False
        Return
    }

    isBlankSpaceExplorer    := False
    isBlankSpaceNonExplorer := False
    isColumnHeader          := False
    isItemClick             := False

    If (!allowDoubleClicks && A_TimeSincePriorHotkey > k_DoubleClickTime) ; basically a single click
        allowDoubleClicks := True

    prevPath := ""
    If (_winClassD == "CabinetWClass" || _winClassD == "#32770") {
        If (InStr(_winCtrlD, "SysHeader32", True)) {
            isColumnHeader := True
        }
        Else {
            If (InStr(_winCtrlD, "DirectUIHWND", True)) {
                if (_winClassD == "#32770")
                    result := DialogClickClassify(lbX1, lbY1, _winCtrlD)
                else
                    result := ExplorerClickClassify(lbX1, lbY1, _winCtrlD)

                if (result == "header") {
                    isColumnHeader := True
                    isBlankSpaceExplorer := False
                }
                else if (result == "item") {
                    isItemClick := True
                    isBlankSpaceExplorer := False
                }
                else if (result == "blank") {
                    isBlankSpaceExplorer := True
                }
                else if (_winClassD == "#32770") {
                    isBlankSpaceExplorer := AreaLooksUniformFast(lbX1, lbY1)
                }
                ; tooltip, %result%
            }
            Else If (InStr(_winCtrlD, "SysListView32", True)) {
                isBlankSpaceExplorer := IsSysListViewBlankSpaceClick(lbX1, lbY1)
            }

            If (!isColumnHeader && (isBlankSpaceExplorer || isItemClick)) {
                Loop,20 {
                    If (WinExist("A") != _winIdD) {
                        GoSub, EnableTimers
                        Return
                    }
                    prevPath := GetExplorerPath(_winIdD)
                    If (prevPath != "")
                        break

                    Sleep, 15
                }
            }
        }
    }

    KeyWait, LButton, U T5

    If !(_winClassD == "CabinetWClass" || _winClassD == "#32770")  {
        If (InStr(_winCtrlD,"SysHeader32", True)) {
            isColumnHeader := True
        }
        if (InStr(_winCtrlD, "SysListView32", True))
            isBlankSpaceNonExplorer := IsSysListViewBlankSpaceClick(lbX1, lbY1)
        else
            isBlankSpaceNonExplorer := AreaLooksUniformFast(lbX1, lbY1, 0xFFFFFF)
    }

    MouseGetPos, lbX2, lbY2, _winIdU, _winCtrlU

    rlsTime  := A_TickCount
    timeDiff := rlsTime - initTime

    ; Quick Access needs no UIA hit lookup. Every completed SysTreeView32 click
    ; starts the changed-path watcher; only a current path different from the
    ; mouse-down path can ultimately authorize SendCtrlAdd().
    if ((_winClassD == "CabinetWClass" || _winClassD == "#32770")
     && InStr(_winCtrlD, "SysTreeView32", True)) {
        if (!GetKeyState("LButton", "P") && _winIdU = _winIdD)
            _RequestExplorerCtrlAdd(_winIdD, _winClassD, _winCtrlD, 0, navigationStartPath, True)

        GoSub, EnableTimers
        Return
    }

    ; tickTotalEnd := A_TickCount
    ; traceText .= "TOTAL dt=" (tickTotalEnd - tickTotalStart) "ms`n"
    ; ToolTip, %traceText%
    ; tooltip, %isColumnHeader%
    ; tooltip, %timeDiff% ms-allowDoubleclick:%allowDoubleClicks%-isBlankSpaceExplorer:%isBlankSpaceExplorer%-isItemClick:%isItemClick% - isColumnHeader:%isColumnHeader% ; - %_winClassD% - %_winCtrlU% - %LBD_HexColor1% - %LBD_HexColor2% - %LBD_HexColor3% - %lbX1% - %lbX2%

    If (timeDiff < floor(k_DoubleClickTime/2) && (abs(lbX1-lbX2) < 15 && abs(lbY1-lbY2) < 15)) {

        If (   (InStr(_winCtrlU, "SysListView32", True) || InStr(_winCtrlU, "DirectUIHWND", True))
            && (isBlankSpaceExplorer || isBlankSpaceNonExplorer) ) {


            If InStr(_winCtrlU, "SysListView32", True) {
                If (_winClassD == "CabinetWClass" || _winClassD == "#32770") {
                    SetTimer, SendCtrlAddLabel, -125
                }
                Else {
                    ControlGet, controlHwnd, Hwnd,, %_winCtrlU%, ahk_id %_winIdU%
                    If IsSysListViewReportView(controlHwnd)
                        SetTimer, SendCtrlAddLabel, -125
                }
            }
            Else
                SetTimer, SendCtrlAddLabel, -125
        }
        Else If ( isColumnHeader && !isItemClick) {

            If (_winClassD == "CabinetWClass" && k_isWin11 && k_isModernExplorerInReg) {

                _SendFocusedCtrlAdd(_winIdU, _winCtrlU)
            }
            Else {
                ; Get UIA element
                pt    := SafeUIA_ElementFromPoint(lbX2, lbY2, "", 2000)
                ctype := SafeUIA_GetControlType(pt)
                ; Optional if used later
                ; cname := SafeUIA_GetName(pt, "")
                ; Cache risky UIA properties ONCE
                ; tooltip, % "line4 - " pt.CurrentControlType
                if (_winClassD == "CabinetWClass"
                 && k_isWin11
                 && k_isModernExplorerInReg
                 && InStr(_winCtrlU, "DirectUIHWND", True)
                 && ctype == 50026) {
                    EnsureFocusedCtrlNN(_winIdU, _winCtrlU, 60, 15)
                    Sleep, 75
                    SendCtrlNumpadAdd()
                    return
                }

                If (ctype == "" || ctype > 50035 || (ctype > 50008 && ctype < 50031)) {
                    ; DO NOTHING
                }
                Else {
                    If (ctype  == 50031 || ctype  == 50008) && (_winClassD == "#32770" || InStr(_winCtrlU,"DirectUIHWND3", True)) {
                        _SendFocusedCtrlAdd(_winIdU, _winCtrlU)
                    }
                    Else If (ctype  == 50035) { ; this most likely would indicate an SysListView based window like 7-zip
                        If !k_isWin11
                            Send, {F5}

                        SendCtrlNumpadAdd()
                    }
                    Else If ((ctype == 50033) && (InStr(_winCtrlU, "DirectUIHWND", True))) {

                        SendCtrlNumpadAdd()
                    }
                }
            }
        }
        Else If ( (_winClassD == "CabinetWClass" || _winClassD == "#32770")
               && _IsExplorerNavigationHeaderCtrl(_winCtrlU)) {

            ; Reuse the mouse-down classification only for a completed click near
            ; the same point. A drag or release elsewhere must not inherit the
            ; original button action.
            useCapturedHeaderKind := (   _winIdU = _winIdD
                                      && Abs(lbX1 - lbX2) <= 12
                                      && Abs(lbY1 - lbY2) <= 12
                                      && (navigationHeaderKind = "refresh" || navigationHeaderKind = "path_change"))
            headerKind := useCapturedHeaderKind
                        ? navigationHeaderKind
                        : _GetExplorerHeaderNavigationKind(lbX2, lbY2, 2000)
            if !(headerKind = "refresh" || headerKind = "path_change") {
                rejectionReason := (headerKind = "unavailable")
                    ? "header_kind_unavailable"
                    : "header_kind_not_navigation"
                _TraceExplorerCtrlAdd("header_request_rejected"
                    , "hwnd=" . _winIdU
                    . " class=" . _winClassD
                    . " sourceCtrl=[" . _winCtrlU . "]"
                    . " headerKind=" . headerKind
                    . " initialPath=[" . navigationStartPath . "]"
                    . " rejectionReason=" . rejectionReason
                    , True)

                GoSub, EnableTimers
                Return
            }

            if (headerKind = "refresh") {
                _RequestHeaderNavigationCtrlAdd(_winIdU, _winClassD, navigationStartPath, False
                    , k_explorerCtrlAddRefreshMinimumWaitMs, True)
            }
            else if (headerKind = "path_change")
                _RequestHeaderNavigationCtrlAdd(_winIdU, _winClassD, navigationStartPath, True)
        }
    }
    ; A SysHeader drag of at least 15 pixels blocks this window's LButton-driven
    ; alignment until a qualifying double-click in its SysListView clears it.
    Else If (InStr(_winCtrlU, "SysHeader", True) && (abs(lbX1-lbX2) >= 15 || abs(lbY1-lbY2) >= 15)) {
        disableSendCtrlHwnd := _winIdU
    }

    GoSub, EnableTimers
Return
#If

; FocusHwndFast(hwnd)
; - Activates the top-level window, brings it to foreground safely, and sets keyboard focus to 'hwnd'.
; - Pure Win32, avoids UIA. Works only for HWND-backed controls.
; Fast, reliable focus with minimal overhead
FocusHwndFast(hwndTarget, verify := true, ensureForeground := true)
{
    if !DllCall("IsWindow", "Ptr", hwndTarget)
        return false

    ; Return immediately when this thread already has focus on the target HWND.
    if (DllCall("GetFocus", "Ptr") = hwndTarget)
        return true

    hwndTop := DllCall("GetAncestor", "Ptr", hwndTarget, "UInt", 2, "Ptr")
    if (!hwndTop)
        hwndTop := hwndTarget

    if (DllCall("IsIconic", "Ptr", hwndTop))
        DllCall("ShowWindowAsync", "Ptr", hwndTop, "Int", 9)

    hFG    := DllCall("GetForegroundWindow", "Ptr")
    tidAHK := DllCall("GetCurrentThreadId", "UInt")
    tidTW  := DllCall("GetWindowThreadProcessId", "Ptr", hwndTop, "UInt*", 0, "UInt")

    attachedToTW := false
    if (tidTW != tidAHK)
    {
        DllCall("AttachThreadInput", "UInt", tidTW, "UInt", tidAHK, "Int", 1)
        attachedToTW := true
    }

    attachedToFG := false
    if (ensureForeground && hFG != hwndTop)
    {
        tidFG := DllCall("GetWindowThreadProcessId", "Ptr", hFG, "UInt*", 0, "UInt")
        if (tidFG != tidAHK)
        {
            DllCall("AttachThreadInput", "UInt", tidFG, "UInt", tidAHK, "Int", 1)
            attachedToFG := true
        }

        DllCall("SetForegroundWindow", "Ptr", hwndTop)
    }

    DllCall("SetActiveWindow", "Ptr", hwndTop)
    DllCall("SetFocus", "Ptr", hwndTarget, "Ptr")

    success := true
    if (verify)
        success := (DllCall("GetFocus", "Ptr") = hwndTarget)

    if (attachedToFG)
        DllCall("AttachThreadInput", "UInt", tidFG, "UInt", tidAHK, "Int", 0)

    if (attachedToTW)
        DllCall("AttachThreadInput", "UInt", tidTW, "UInt", tidAHK, "Int", 0)

    return success
}

GetItemsViewHwndFromUIA(shellEl)
{
    hCtl := 0

    ; Most UIA wrappers expose CurrentNativeWindowHandle
    try
        hCtl := shellEl.CurrentNativeWindowHandle
    catch e
        hCtl := 0

    return hCtl
}

; Cap the next UIA transaction and provider connection to the time remaining in
; one Explorer readiness probe. A zero return prevents a new call after the deadline.
_ApplyExplorerUIABudget(uiaDeadlineTick, requestedTimeoutMs := 2000) {
    global UIA

    if (requestedTimeoutMs <= 0)
        requestedTimeoutMs := 1

    effectiveTimeoutMs := requestedTimeoutMs
    if (uiaDeadlineTick) {
        remainingMs := uiaDeadlineTick - A_TickCount
        if (remainingMs <= 0)
            return 0
        effectiveTimeoutMs := Min(effectiveTimeoutMs, remainingMs)
    }

    effectiveTimeoutMs := Max(1, effectiveTimeoutMs)
    if IsObject(UIA) {
        try
            UIA.TransactionTimeout := effectiveTimeoutMs
        if (uiaDeadlineTick) {
            try
                UIA.ConnectionTimeout := effectiveTimeoutMs
        }
    }
    return effectiveTimeoutMs
}

; Confirm the two conditions required before an Explorer/file-dialog request may
; call SendCtrlAdd(): the current file panel is in Details mode, and UIA exposes
; either one ListItem or a recognized empty-result message. One shared deadline
; bounds all UIA work; the timer caller retries a not-ready result. detailsReason
; records the Details-mode result, while itemsViewResolver, candidate count, and
; resolution reason identify how the current Items View was (or was not) found.
_ProbeExplorerDetailsContentReady(targetHwndID, transactionTimeout := 150
    , requestId := "") {
    global UIA
    global k_explorerItemsViewContentEvidenceCondition

    if (!targetHwndID || !WinExist("ahk_id " . targetHwndID))
        return { state: "not_ready", reason: "target_gone" }
    if (transactionTimeout <= 0)
        transactionTimeout := 1

    priorConnectionTimeout  := ""
    priorTransactionTimeout := ""
    uiaDeadlineTick         := A_TickCount + transactionTimeout

    if !IsObject(UIA) {
        try
            UIA := UIA_Interface()
        catch e
            UIA := ""
    }
    if !IsObject(UIA)
        return { state: "not_ready", reason: "uia_unavailable" }

    try {
        try
            priorConnectionTimeout := UIA.ConnectionTimeout
        catch e
            priorConnectionTimeout := ""
        try
            priorTransactionTimeout := UIA.TransactionTimeout
        catch e
            priorTransactionTimeout := ""

        detailsReason := ""
        itemsEl := ""
        itemsViewCandidateCount := 0
        itemsViewResolutionReason := ""
        itemsViewResolver := ""
        resolvedCtrlHwnd := 0
        resolvedCtrlNN := ""
        ; Force #32770 to inspect its current Items View. Its 250 ms cache may
        ; still refer to the outgoing folder after the dialog path changes.
        if !IsDetailsView(targetHwndID, itemsEl, transactionTimeout
            , uiaDeadlineTick, False, detailsReason, itemsViewResolver
            , itemsViewCandidateCount, itemsViewResolutionReason
            , resolvedCtrlNN, resolvedCtrlHwnd)
            return { state: "not_ready", reason: "not_details_view"
                , detailsReason: detailsReason
                , itemsViewCandidateCount: itemsViewCandidateCount
                , itemsViewResolutionReason: itemsViewResolutionReason
                , itemsViewResolver: itemsViewResolver }

        ; #32770 returns the Items View already inspected for Details mode.
        ; CabinetWClass uses COM for that mode check, so resolve its UIA file
        ; panel separately through the same shared resolver.
        if !IsObject(itemsEl) {
            ResolveExplorerItemsView(targetHwndID, itemsEl
                , transactionTimeout, uiaDeadlineTick, False
                , itemsViewResolver, itemsViewCandidateCount
                , itemsViewResolutionReason, resolvedCtrlNN, resolvedCtrlHwnd)
        }
        if !IsObject(itemsEl)
            return { state: "not_ready", reason: "items_view_unavailable"
                , detailsReason: detailsReason
                , itemsViewCandidateCount: itemsViewCandidateCount
                , itemsViewResolutionReason: itemsViewResolutionReason
                , itemsViewResolver: itemsViewResolver }

        if (!_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout))
            return { state: "not_ready", reason: "uia_budget_exhausted"
                , detailsReason: detailsReason
                , itemsViewCandidateCount: itemsViewCandidateCount
                , itemsViewResolutionReason: itemsViewResolutionReason
                , itemsViewResolver: itemsViewResolver }

        contentEvidenceEl := ""
        try
            contentEvidenceEl := itemsEl.FindFirstBy(k_explorerItemsViewContentEvidenceCondition)
        catch e
            contentEvidenceEl := ""

        if IsObject(contentEvidenceEl) {
            readyResult := { state: "ready", reason: "details_content_visible"
                , detailsReason: detailsReason
                , itemsViewCandidateCount: itemsViewCandidateCount
                , itemsViewResolutionReason: itemsViewResolutionReason
                , itemsViewResolver: itemsViewResolver }
            if (resolvedCtrlNN != "" && resolvedCtrlHwnd)
                readyResult.resolvedTarget := { ctrlNN: resolvedCtrlNN
                    , hwnd: resolvedCtrlHwnd + 0, requestId: requestId }
            return readyResult
        }

        return { state: "not_ready", reason: "content_not_visible"
            , detailsReason: detailsReason
            , itemsViewCandidateCount: itemsViewCandidateCount
            , itemsViewResolutionReason: itemsViewResolutionReason
            , itemsViewResolver: itemsViewResolver }
    } catch e {
        return { state: "not_ready", reason: "probe_exception" }
    } finally {
        try {
            if (priorTransactionTimeout != "" && IsObject(UIA))
                UIA.TransactionTimeout := priorTransactionTimeout
        } catch e {
        }
        try {
            if (priorConnectionTimeout != "" && IsObject(UIA))
                UIA.ConnectionTimeout := priorConnectionTimeout
        } catch e {
        }
    }
}

; Resolve Explorer's main item container with a cheap-to-broad lookup:
; 1) accept the supplied native control itself when UIA exposes it as an item view
; 2) search its descendants by the common shell item-container control types
; 3) use the legacy "Items View" name lookup as the broad fallback
; transactionTimeout caps each lookup when no shared deadline is supplied.
; uiaDeadlineTick instead makes every root and descendant lookup consume one
; shared remaining-time budget.
FindExplorerItemsViewElement(targetHwndID, transactionTimeout := 2000, uiaDeadlineTick := 0)
{
    effectiveTimeoutMs := _ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout)
    if (!effectiveTimeoutMs)
        return ""

    if (uiaDeadlineTick)
        exEl := SafeUIA_ElementFromHandle(targetHwndID, "", False
            , effectiveTimeoutMs, effectiveTimeoutMs, False)
    else
        exEl := SafeUIA_ElementFromHandle(targetHwndID, "", False
            , effectiveTimeoutMs)
    if !IsObject(exEl)
        return ""

    ; A native-scoped SysListView32 can itself be the UIA List. Accepting that
    ; root avoids searching below the exact file-panel control we just resolved.
    if (!_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout))
        return ""
    rootInfo := SafeUIA_GetElementSnapshot(exEl, "className|controlType|name")
    if (rootInfo.className = "UIItemsView"
     || rootInfo.controlType = 50008
     || rootInfo.controlType = 50028
     || rootInfo.controlType = 50036)
        return exEl

    ; These symbolic UIA_*ControlTypeId names are intentional: UIA_Interface
    ; resolves them inside FindFirstBy("ControlType=...") just like the
    ; equivalent numeric IDs, which keeps this search readable.
    for controlTypeIndex, ctlType in ["UIA_ListControlTypeId", "UIA_DataGridControlTypeId", "UIA_TableControlTypeId"] {
        if (!_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout))
            return ""

        itemsEl := ""
        try
            itemsEl := exEl.FindFirstBy("ControlType=" . ctlType)
        catch e
            itemsEl := ""

        if IsObject(itemsEl)
            return itemsEl
    }

    if (!_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout))
        return ""
    return SafeUIA_FindFirstByNameFast(exEl, "Items View")
}

; Return true when the resolved #32770 Items View exposes Details-mode evidence:
; a Header, Grid.ColumnCount >= 2, or a Name split-button header. detailsReason
; records which signal succeeded or which check/budget gate failed.
ExplorerItemsViewHasDetailsSignals(shellEl, uiaDeadlineTick := 0, transactionTimeout := 2000, ByRef detailsReason := "") {
    static UIA_HeaderTypeId      := 50034
    static UIA_SplitButtonTypeId := 50031

    detailsReason := ""
    if !IsObject(shellEl) {
        detailsReason := "items_view_unavailable"
        return false
    }

    if (!_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout)) {
        detailsReason := "uia_budget_exhausted_before_header_check"
        return false
    }
    if (UIA_FindFirstByControlTypeAny_(shellEl, UIA_HeaderTypeId)) {
        detailsReason := "header_found"
        return true
    }

    if (!_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout)) {
        detailsReason := "uia_budget_exhausted_before_grid_check"
        return false
    }
    cols := UIA_TryGetGridColumnCountAny_(shellEl)
    if (cols >= 2) {
        detailsReason := "grid_column_count=" . cols
        return true
    }

    if (!_ApplyExplorerUIABudget(uiaDeadlineTick, transactionTimeout)) {
        detailsReason := "uia_budget_exhausted_before_name_header_check"
        return false
    }
    if (UIA_FindFirstByControlTypeAndNameAny_(shellEl, UIA_SplitButtonTypeId, "Name")) {
        detailsReason := "name_split_button_found"
        return true
    }

    detailsReason := "header=0 grid_column_count=" . cols . " name_split_button=0"
    return false
}

; Resolve the real Explorer Items View HWND with a cheap-first split:
; 1) reuse a short-lived cached HWND when the same window was just resolved
; 2) otherwise pay for fresh UIA discovery and extract the native handle
; This keeps repeat focus checks cheap while still falling back to the more
; accurate UIA path when the cache is missing or stale.
GetItemsViewHwnd(targetHwndID)
{
    static cache := {}

    if (!targetHwndID)
        return 0

    cacheKey := targetHwndID
    if (cache.HasKey(cacheKey)) {
        cacheItem := cache[cacheKey]
        if ((A_TickCount - cacheItem.tick) < 250 && DllCall("user32\IsWindow", "Ptr", cacheItem.hwnd, "Int"))
            return cacheItem.hwnd
    }

    hCtl := 0

    shellEl := FindExplorerItemsViewElement(targetHwndID)

    if IsObject(shellEl)
        hCtl := GetItemsViewHwndFromUIA(shellEl)

    if (hCtl)
        cache[cacheKey] := { hwnd: hCtl, tick: A_TickCount }

    return hCtl
}

; Resolve a focus target to a native HWND with a cheap-first/fallback split:
; 1) for shell DirectUI targets, prefer the resolved Items View HWND so focus
;    checks survive Win11 DirectUIHWND renumbering
; 2) if that richer shell-specific path does not produce a handle, fall back to
;    a direct ControlGet on the caller's CtrlNN
; Explorer and file dialogs therefore get the more accurate subtree-aware path,
; while other windows still keep the simpler CtrlNN-based fallback.
ResolveFocusTargetHwnd(hwndTop, ctrlNN, topClass := "")
{
    static cache := {}

    if (!hwndTop || ctrlNN = "")
        return 0

    cacheKey := hwndTop "|" ctrlNN
    if (cache.HasKey(cacheKey)) {
        cacheItem := cache[cacheKey]
        if ((A_TickCount - cacheItem.tick) < 250 && DllCall("user32\IsWindow", "Ptr", cacheItem.hwnd, "Int"))
            return cacheItem.hwnd
    }

    if (topClass = "")
        WinGetClass, topClass, ahk_id %hwndTop%

    hCtl := 0
    if ((topClass = "CabinetWClass" || topClass = "#32770") && InStr(ctrlNN, "DirectUIHWND", True))
        hCtl := GetItemsViewHwnd(hwndTop)

    if (!hCtl)
        ControlGet, hCtl, Hwnd,, %ctrlNN%, ahk_id %hwndTop%

    if (hCtl)
        cache[cacheKey] := { hwnd: hCtl, tick: A_TickCount }

    return hCtl
}

; UIA-based Explorer readiness wait:
; 1) locate the shell Items View element
; 2) wait for either a UIA ListItem or a known empty/search-result message
; 3) when this caller needs focus inside the view, perform the slower UIA-backed
;    focus confirmation/retry path instead of trusting only control-level signals
WaitForExplorerLoad(targetHwndID, skipFocus := False, isCabinetWClass10 := False) {
    global UIA
    global k_explorerItemsViewContentEvidenceCondition

    try {
        shellEl := FindExplorerItemsViewElement(targetHwndID)

        if !IsObject(shellEl) {
            ; UIA couldn't find it by name; don't explode, just skip the wait/focus part
            return
        }

        SafeUIA_WaitElementExistFast(shellEl, k_explorerItemsViewContentEvidenceCondition, "", 200, 5000)

        If (!isCabinetWClass10 && !skipFocus) {
            hCtl := GetItemsViewHwndFromUIA(shellEl)

            if (!hCtl)
                ControlGet, hCtl, Hwnd,, DirectUIHWND2, ahk_id %targetHwndID%

            if (!hCtl)
                return

            tidTarget := DllCall("GetWindowThreadProcessId", "Ptr", hCtl, "UInt*", 0, "UInt")

            ; if already focused inside the view, skip everything
            if (ControlGetFocusEx(tidTarget, hCtl, 0))
                return

            ; expensive once
            FocusHwndFast(hCtl, false, true)
            if (ControlGetFocusEx(tidTarget, hCtl, 15))
                return

            ; cheap retry (usually 1-2 is enough)
            Loop, 2
            {
                FocusHwndFast(hCtl, false, false)
                if (ControlGetFocusEx(tidTarget, hCtl, 15))
                    break
                Sleep, 1
            }
        }

    } catch e {
        tooltip, 4: UIA TIMED OUT!!!!
        WinGetClass, wndClass, ahk_id %targetHwndID%
        MsgBox % "Exception caught:`n"
            . "targetHwndID: " targetHwndID "`n"
            . "Class: " wndClass "`n"
            . "Message: " e.Message "`n"
            . "What: " e.What "`n"
            . "File: " e.File "`n"
            . "Line: " e.Line "`n"
            . "Extra: " e.Extra
        UIA :=  ;// set to a different value
        ; VarSetCapacity(UIA, 0) ;// set capacity to zero
        UIA := UIA_Interface() ; Initialize UIA interface
        UIA.TransactionTimeout := 2000
        UIA.ConnectionTimeout  := 20000
        LbuttonEnabled := True
    }
    Return
}

SendCtrlAddLabel:
    SendCtrlAdd(_winIdU, _winClassD, _winCtrlU)
Return

#MaxThreadsPerHotkey 1
UpdateInputBoxTitle:
    WinSet, ExStyle, +0x80, ahk_class #32770 ; 0x80 is WS_EX_TOOLWINDOW
    If (WinExist("Type Up to 3 Letters of a Window Title to Search") && !StopCheck) {
        WinSet, AlwaysOnTop, On, Type Up to 3 Letters of a Window Title to Search
        StopCheck := True
    }

    ControlGetText, memotext, Edit1, Type Up to 3 Letters of a Window Title to Search
    StringLen, memolength, memotext

    If ((memolength >= 3 && (A_TickCount-TimeOfLastHotkeyTyped > 400)) || (memolength >= 1 && InStr(memotext, " "))) {
        UserInputTrimmed := Trim(memotext)
        Send, {ENTER}
        SetTimer, UpdateInputBoxTitle, off
        Return
    }
    Else {
        UserInputTrimmed := Trim(memotext)
    }
Return

SwitchDesktop:
    global movehWndId
    global GoToDesktop := False

    Thread, NoTimers, True
    StopRecursion := True

    MouseGetPos, , , movehWndId
    WinActivate, ahk_id %movehWndId%
    CurrentDesktop := GetCurrentDesktopNumber() + 1
    Menu, vdeskMenu, Add
    Menu, vdeskMenu, DeleteAll
    Loop,% getTotalDesktops()
    {
        If (CurrentDesktop != A_Index)
        {
            Menu, vdeskMenu, Add,  Move to Desktop %A_Index%, SendWindow
            ; Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_WinDir%\System32\imageres.dll, 290, 32
            If ( A_Index == 1)
                Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_ScriptDir%\1-move-blk.ico, , 32
            Else If (A_Index == 2)
                Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_ScriptDir%\2-move-blk.ico, , 32
            Else If (A_Index == 3)
                Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_ScriptDir%\3-move-blk.ico, , 32
            Else If (A_Index == 4)
                Menu, vdeskMenu, Icon, Move to Desktop %A_Index%, %A_ScriptDir%\4-move-blk.ico, , 32

            Menu, vdeskMenu, Add,  Move and Go to Desktop %A_Index%, SendWindowAndGo
            ; Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_WinDir%\System32\imageres.dll, 290, 32
            If ( A_Index == 1)
                Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_ScriptDir%\1-moveswitch-blk.ico, , 32
            Else If (A_Index == 2)
                Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_ScriptDir%\2-moveswitch-blk.ico, , 32
            Else If (A_Index == 3)
                Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_ScriptDir%\3-moveswitch-blk.ico, , 32
            Else If (A_Index == 4)
                Menu, vdeskMenu, Icon, Move and Go to Desktop %A_Index%, %A_ScriptDir%\4-moveswitch-blk.ico, , 32
        }
    }
    Menu, vdeskMenu, Show

    If GoToDesktop
        sleep, 1000

    StopRecursion := False
    Thread, NoTimers, False
Return

SendWindow:
    global movehWndId
    global targetDesktop
    moveLeftConst  := -1
    moveRightConst := 1
    moveConst      := 0

    DetectHiddenWindows, On

    InitialDesktop := GetCurrentDesktopNumber() + 1

    If      (A_ThisMenuItem == "Move to Desktop 1") || (A_ThisMenuItem == "Move and Go to Desktop 1")
        targetDesktop := 1
    Else If (A_ThisMenuItem == "Move to Desktop 2") || (A_ThisMenuItem == "Move and Go to Desktop 2")
        targetDesktop := 2
    Else If (A_ThisMenuItem == "Move to Desktop 3") || (A_ThisMenuItem == "Move and Go to Desktop 3")
        targetDesktop := 3
    Else If (A_ThisMenuItem == "Move to Desktop 4") || (A_ThisMenuItem == "Move and Go to Desktop 4")
        targetDesktop := 4
    Else If (A_ThisMenuItem == "Move to Desktop 5") || (A_ThisMenuItem == "Move and Go to Desktop 5")
        targetDesktop := 5
    Else If (A_ThisMenuItem == "Move to Desktop 6") || (A_ThisMenuItem == "Move and Go to Desktop 6")
        targetDesktop := 6
    Else If (A_ThisMenuItem == "Move to Desktop 7") || (A_ThisMenuItem == "Move and Go to Desktop 7")
        targetDesktop := 7
    Else If (A_ThisMenuItem == "Move to Desktop 8") || (A_ThisMenuItem == "Move and Go to Desktop 8")
        targetDesktop := 8

    WinGetPos, sw_x, sw_y, sw_h, sw_w, ahk_id %movehWndId%
    If (targetDesktop < InitialDesktop)
        MoveAndFadeWindow(movehWndId, sw_x, False)
    Else
        MoveAndFadeWindow(movehWndId, sw_x, True)

    If      (A_ThisMenuItem == "Move to Desktop 1") || (A_ThisMenuItem == "Move and Go to Desktop 1")
        MoveCurrentWindowToDesktop(1)
    Else If (A_ThisMenuItem == "Move to Desktop 2") || (A_ThisMenuItem == "Move and Go to Desktop 2")
        MoveCurrentWindowToDesktop(2)
    Else If (A_ThisMenuItem == "Move to Desktop 3") || (A_ThisMenuItem == "Move and Go to Desktop 3")
        MoveCurrentWindowToDesktop(3)
    Else If (A_ThisMenuItem == "Move to Desktop 4") || (A_ThisMenuItem == "Move and Go to Desktop 4")
        MoveCurrentWindowToDesktop(4)
    Else If (A_ThisMenuItem == "Move to Desktop 5") || (A_ThisMenuItem == "Move and Go to Desktop 5")
        MoveCurrentWindowToDesktop(5)
    Else If (A_ThisMenuItem == "Move to Desktop 6") || (A_ThisMenuItem == "Move and Go to Desktop 6")
        MoveCurrentWindowToDesktop(6)
    Else If (A_ThisMenuItem == "Move to Desktop 7") || (A_ThisMenuItem == "Move and Go to Desktop 7")
        MoveCurrentWindowToDesktop(7)
    Else If (A_ThisMenuItem == "Move to Desktop 8") || (A_ThisMenuItem == "Move and Go to Desktop 8")
        MoveCurrentWindowToDesktop(8)

    If !GoToDesktop
        WinSet, Transparent, 255, ahk_id %movehWndId%

    DetectHiddenWindows, Off
Return

SendWindowAndGo:
    global movehWndId, targetDesktop

    GoToDesktop := True
    GoSub, SendWindow

    GoSub, SwitchToVD%targetDesktop%
    sleep, 400

    WinGetPos, sw_x, sw_y, sw_h, sw_w, ahk_id %movehWndId%
    If (targetDesktop < InitialDesktop)
        MoveAndFadeWindow(movehWndId, sw_x, False, "in")
    Else
        MoveAndFadeWindow(movehWndId, sw_x, True, "in")

    GoToDesktop := False
Return

; → Returns the entire window’s bounding box in screen coordinates.
; What it measures
; The outer rectangle of a window/control: includes title bar, borders, shadows, scrollbars, etc.
; Coordinates (L, T, R, B) are relative to the screen (top-left of the monitor).
GetWindowRectEx(hWnd, ByRef L, ByRef T, ByRef R, ByRef B) {
    VarSetCapacity(RECT, 16, 0)
    ; BOOL GetWindowRect(HWND hWnd, LPRECT lpRect)
    ok := DllCall("GetWindowRect", "ptr", hWnd, "ptr", &RECT, "int")
    if (!ok)
        return false
    L := NumGet(RECT, 0,  "Int")
    T := NumGet(RECT, 4,  "Int")
    R := NumGet(RECT, 8,  "Int")
    B := NumGet(RECT, 12, "Int")
    return true
}

; Returns true if subkey (like "Software\Classes\CLSID\{...}\InProcServer32") exists under HKCU
KeyExistsInHKCU(subkey) {
    ; constants
    HKEY_CURRENT_USER := 0x80000001
    KEY_READ := 0x20019

    ; try to open the subkey (Unicode)
    hKey := 0
    ret := DllCall("Advapi32\RegOpenKeyExW", "Ptr", HKEY_CURRENT_USER, "WStr", subkey, "UInt", 0, "UInt", KEY_READ, "PtrP", hKey)

    if (ret == 0) { ; ERROR_SUCCESS
        ; close handle and return true
        DllCall("Advapi32\RegCloseKey", "Ptr", hKey)
        return true
    }
    return false
}

; IsExplorerModern() -> returns true if modern (Windows 11) Explorer UI is active,
;                      false if classic (Windows 10) Explorer UI is active.
HasWin10ExplorerOverride() {
    win10ExplorerGUIDs := ["{2aa9162e-c906-4dd9-ad0b-3d24a8eef5a0}", "{6480100b-5a83-4d1e-9f69-8ae5a88e9a33}"]
    base := "Software\Classes\CLSID\"
    for explorerGuidIndex, guid in win10ExplorerGUIDs {
        subkey := base . guid . "\InProcServer32"
        if (KeyExistsInHKCU(subkey))
            return true
    }
    return false
}
IsExplorerModern() {
    return !HasWin10ExplorerOverride()
}

GetCtrlNNsByPrefix(hwndTop, classPrefix)
{
    static cache := {}

    if (!hwndTop)
        return ""

    cacheKey := hwndTop "|" classPrefix
    if (cache.HasKey(cacheKey)) {
        cacheItem := cache[cacheKey]
        if ((A_TickCount - cacheItem.tick) < 250 && WinExist("ahk_id " . hwndTop))
            return cacheItem.value
    }

    WinGet, listC, ControlList,     ahk_id %hwndTop%
    WinGet, listH, ControlListHwnd, ahk_id %hwndTop%
    prefixLen := StrLen(classPrefix)
    ctrlNNs := StrSplit(RTrim(listC, "`r`n"), "`n", "`r")
    ctrlHwnds := StrSplit(RTrim(listH, "`r`n"), "`n", "`r")

    out := ""
    Loop, % ctrlHwnds.Length()
    {
        hCtl := ctrlHwnds[A_Index] + 0
        if (!hCtl)
            continue

        cls := GetClassName(hCtl)
        if (SubStr(cls, 1, prefixLen) != classPrefix)
            continue

        ctrlNN := (A_Index <= ctrlNNs.Length()) ? ctrlNNs[A_Index] : ""
        if (ctrlNN != "")
            out .= ctrlNN " "
    }

    out := RTrim(out, " ")
    cache[cacheKey] := { tick: A_TickCount, value: out }
    return out
}

; This helper exists because some non-shell windows expose multiple child controls
; with the same class prefix, but only the large pane-sized ones are real
; file/details views that should receive Ctrl+NumpadAdd or related focus logic.
; Without this size filter, callers could accidentally target tiny helper hosts,
; side panes, or decorative DirectUI/ListView children that match by class name
; but are not the main content surface.
GetCtrlNNsByPrefixMinSize(hwndTop, classPrefix, minWidth := 400, minHeight := 180)
{
    static cache := {}

    ; The caller gives us a top-level window HWND and asks:
    ;   "Which child controls in this window have a class name that starts with
    ;    classPrefix and are at least minWidth x minHeight?"
    ; Return format is a space-delimited CtrlNN list such as:
    ;   "DirectUIHWND2 DirectUIHWND3"

    if (!hwndTop)
        return ""

    ; Cache by full query shape because this helper can be called repeatedly
    ; while Explorer/dialog UI is settling. The cache is intentionally short-
    ; lived so rapidly repeated probes can reuse the last scan without letting
    ; stale control layouts linger for long.
    cacheKey := hwndTop "|" classPrefix "|" minWidth "|" minHeight
    if (cache.HasKey(cacheKey)) {
        cacheItem := cache[cacheKey]
        if ((A_TickCount - cacheItem.tick) < 250 && WinExist("ahk_id " . hwndTop))
            return cacheItem.value
    }

    ; Pull both the textual CtrlNN list and the HWND list from the same window.
    ; These two lists are positionally aligned, so entry N in ControlList should
    ; correspond to entry N in ControlListHwnd.
    WinGet, listC, ControlList,     ahk_id %hwndTop%
    WinGet, listH, ControlListHwnd, ahk_id %hwndTop%
    prefixLen := StrLen(classPrefix)
    ctrlNNs   := StrSplit(RTrim(listC, "`r`n"), "`n", "`r")
    ctrlHwnds := StrSplit(RTrim(listH, "`r`n"), "`n", "`r")

    ; Build the output as a flat space-delimited list because the current call
    ; sites mainly use InStr(...) membership checks against specific CtrlNNs.
    out := ""
    Loop, % ctrlHwnds.Length()
    {
        ; ControlListHwnd can contain blank/non-numeric entries in edge cases.
        ; Normalize to a numeric HWND and skip anything invalid.
        hCtl := ctrlHwnds[A_Index] + 0
        if (!hCtl)
            continue

        ; Filter first by the real runtime class name from the child HWND
        ; rather than trusting the CtrlNN text alone.
        cls := GetClassName(hCtl)
        if (SubStr(cls, 1, prefixLen) != classPrefix)
            continue

        ; Map the matching HWND back to its CtrlNN name from the parallel list.
        ctrlNN := (A_Index <= ctrlNNs.Length()) ? ctrlNNs[A_Index] : ""
        if (ctrlNN = "")
            continue

        ; Ignore tiny helper/host controls. The caller only wants substantial
        ; panes such as the main Explorer/list content regions.
        ControlGetPos, , , ctrlWidth, ctrlHeight, %ctrlNN%, ahk_id %hwndTop%
        if (ctrlWidth >= minWidth && ctrlHeight >= minHeight)
            out .= ctrlNN " "
    }

    ; Trim the trailing separator, then cache the completed result for the next
    ; near-term identical query.
    out := RTrim(out, " ")
    cache[cacheKey] := { tick: A_TickCount, value: out }
    return out
}

; Capture the DirectUI/ListView child-control snapshot once so multiple callers
; can reuse the same discovery result while choosing a Ctrl+NumpadAdd target.
; Explorer/file-dialog windows keep the full shell control set; other windows
; filter to large panes only so tiny helper hosts do not qualify as targets.
GetSendCtrlAddTargetScan(hwndTop, topClass := "", minWidth := 400, minHeight := 180)
{
    if (!hwndTop)
        return { directCtrls: "", hasDirect2: 0, hasDirect3: 0, hasDirect4: 0, hasDirect6: 0, hasDirect8: 0
               , hasSysList: 0, isShellLike: False, sysListCtrls: "", topClass: "" }

    if (topClass = "")
        WinGetClass, topClass, ahk_id %hwndTop%

    isShellLike := (topClass == "CabinetWClass" || topClass == "#32770")
    if (isShellLike) {
        directCtrls  := GetCtrlNNsByPrefix(hwndTop, "DirectUIHWND")
        sysListCtrls := GetCtrlNNsByPrefix(hwndTop, "SysListView32")
    }
    else {
        directCtrls  := GetCtrlNNsByPrefixMinSize(hwndTop, "DirectUIHWND", minWidth, minHeight)
        sysListCtrls := GetCtrlNNsByPrefixMinSize(hwndTop, "SysListView32", minWidth, minHeight)
    }

    return { directCtrls: directCtrls
           , hasDirect2: InStr(directCtrls,  "DirectUIHWND2", False) > 0
           , hasDirect3: InStr(directCtrls,  "DirectUIHWND3", False) > 0
           , hasDirect4: InStr(directCtrls,  "DirectUIHWND4", False) > 0
           , hasDirect6: InStr(directCtrls,  "DirectUIHWND6", False) > 0
           , hasDirect8: InStr(directCtrls,  "DirectUIHWND8", False) > 0
           , hasSysList: InStr(sysListCtrls, "SysListView32", False) > 0
           , isShellLike: isShellLike
           , sysListCtrls: sysListCtrls
           , topClass: topClass }
}

; Pick the CtrlNN that should receive Ctrl+NumpadAdd from either the current
; focused control or a previously captured child-control scan. Callers can
; disable direct trust of DirectUIHWND2/3 when those names are too ambiguous.
ChooseSendCtrlAddTarget(hwndTop, topClass := "", focusedCtrlNN := "", targetScan := "", allowFocusedDirect23 := True)
{
    global k_isModernExplorerInReg, k_isWin11

    if (!hwndTop)
        return ""

    if (topClass = "") {
        if (IsObject(targetScan) && targetScan.topClass != "")
            topClass := targetScan.topClass
        else
            WinGetClass, topClass, ahk_id %hwndTop%
    }

    isShellLike := (topClass == "CabinetWClass" || topClass == "#32770")
    if (!IsObject(targetScan)) {
        if (focusedCtrlNN = "")
            return ""

        if (InStr(focusedCtrlNN, "SysListView32", True)
         || focusedCtrlNN == "DirectUIHWND4"
         || focusedCtrlNN == "DirectUIHWND6"
         || focusedCtrlNN == "DirectUIHWND8"
         || (allowFocusedDirect23 && (focusedCtrlNN == "DirectUIHWND2" || focusedCtrlNN == "DirectUIHWND3"))) {
            if (!isShellLike) {
                ControlGetPos, , , ctrlWidth, ctrlHeight, %focusedCtrlNN%, ahk_id %hwndTop%
                if (ctrlWidth < 400 || ctrlHeight < 180)
                    return ""
            }
            return focusedCtrlNN
        }
        return ""
    }

    if (InStr(focusedCtrlNN, "SysListView32", True) && targetScan.hasSysList)
        return focusedCtrlNN
    if (focusedCtrlNN == "DirectUIHWND4" && targetScan.hasDirect4)
        return focusedCtrlNN
    if (focusedCtrlNN == "DirectUIHWND6" && targetScan.hasDirect6)
        return focusedCtrlNN
    if (focusedCtrlNN == "DirectUIHWND8" && targetScan.hasDirect8)
        return focusedCtrlNN
    if (allowFocusedDirect23 && focusedCtrlNN == "DirectUIHWND2" && targetScan.hasDirect2)
        return focusedCtrlNN
    if (allowFocusedDirect23 && focusedCtrlNN == "DirectUIHWND3" && targetScan.hasDirect3)
        return focusedCtrlNN

    if (!(targetScan.hasSysList || targetScan.hasDirect2 || targetScan.hasDirect3 || targetScan.hasDirect4 || targetScan.hasDirect6 || targetScan.hasDirect8))
        return ""

    if (targetScan.hasSysList)
        return "SysListView321"

    if (isShellLike
     && targetScan.hasDirect2
     && targetScan.hasDirect3
     && !targetScan.hasDirect4
     && !targetScan.hasDirect6
     && !targetScan.hasDirect8) {
        OutHeight2 := 0
        OutHeight3 := 0

        if k_isWin11 {
            ControlGet, hCtl, Hwnd,, DirectUIHWND2, ahk_id %hwndTop%
            if (GetWindowRectEx(hCtl, L, T, R, B))
                OutHeight2 := B - T
        }
        else {
            ControlGetPos, , , , OutHeight2, DirectUIHWND2, ahk_id %hwndTop%, , , ,
        }

        if (topClass == "CabinetWClass" && !k_isModernExplorerInReg)
            ControlGetPos, , , , OutHeight3, DirectUIHWND3, ahk_id %hwndTop%, , , ,

        if (topClass == "CabinetWClass" && (!k_isWin11 || !k_isModernExplorerInReg))
            return "DirectUIHWND3"

        return "DirectUIHWND2"
    }

    if (targetScan.hasDirect2)
        return "DirectUIHWND2"
    if (targetScan.hasDirect3)
        return "DirectUIHWND3"
    if (isShellLike && targetScan.hasDirect4)
        return "DirectUIHWND4"
    if (isShellLike && targetScan.hasDirect6)
        return "DirectUIHWND6"
    if (isShellLike && targetScan.hasDirect8)
        return "DirectUIHWND8"

    return ""
}

; Resolve the best CtrlNN target for Ctrl+NumpadAdd while keeping the common
; "focused control is already correct" case cheap. If that quick check fails,
; this helper falls back to the shared child-control scan + chooser path.
GetSendCtrlAddTargetCtrl(hwndTop, initFocusedCtrlNN := "", topClass := "", targetScan := "", allowFocusedDirect23 := True)
{
    if (!hwndTop)
        return ""

    if (topClass = "") {
        if (IsObject(targetScan) && targetScan.topClass != "")
            topClass := targetScan.topClass
        else
            WinGetClass, topClass, ahk_id %hwndTop%
    }

    if (initFocusedCtrlNN = "")
        ControlGetFocus, initFocusedCtrlNN, ahk_id %hwndTop%

    TargetControl := ChooseSendCtrlAddTarget(hwndTop, topClass, initFocusedCtrlNN, "", allowFocusedDirect23)
    if (TargetControl != "")
        return TargetControl

    if (!IsObject(targetScan))
        targetScan := GetSendCtrlAddTargetScan(hwndTop, topClass)

    return ChooseSendCtrlAddTarget(hwndTop, topClass, initFocusedCtrlNN, targetScan, allowFocusedDirect23)
}

; Focus the exact request-scoped native child when one was resolved. Callers
; without a resolved HWND retain the existing ClassNN resolution fallback.
_EnsureFocusedCtrlAddTarget(hwndTop, ctrlNN, resolvedHwnd := 0
    , hasResolvedTarget := False, totalMs := 60, refocusEveryMs := 15
    , topClass := "") {
    if (hasResolvedTarget && resolvedHwnd)
        return EnsureFocusedHwnd(resolvedHwnd, totalMs, refocusEveryMs)
    return EnsureFocusedCtrlTarget(hwndTop, ctrlNN, totalMs, refocusEveryMs, topClass)
}

; Resolve and revalidate one native file-view child immediately before dispatch.
; A stale preferred target falls back to the ordinary structural control scan.
_ResolveCtrlAddTargetForSend(hwndTop, windowClass, sourceCtrlNN := ""
    , requestId := "", preferredTarget := "") {
    if (!hwndTop || !WinExist("ahk_id " . hwndTop))
        return ""

    if IsObject(preferredTarget) {
        candidate := { ctrlNN: preferredTarget.ctrlNN
            , hwnd: preferredTarget.hwnd + 0, requestId: requestId }
        if (_ValidateResolvedCtrlAddTarget(hwndTop, candidate) != "")
            return candidate
    }

    targetScan := GetSendCtrlAddTargetScan(hwndTop, windowClass)
    targetCtrlNN := ChooseSendCtrlAddTarget(hwndTop, windowClass
        , sourceCtrlNN, targetScan)
    if (targetCtrlNN = "")
        return ""

    ControlGet, targetHwnd, Hwnd,, %targetCtrlNN%, ahk_id %hwndTop%
    resolvedTarget := { ctrlNN: targetCtrlNN
        , hwnd: targetHwnd + 0, requestId: requestId }
    if (_ValidateResolvedCtrlAddTarget(hwndTop, resolvedTarget) = "")
        return ""
    return resolvedTarget
}

; Resolve a native SysListView32 ClassNN and try the isolated direct-message
; column auto-fit path. False means the caller must retain its existing focus
; preparation and synthetic Ctrl+NumpadAdd fallback.
_TryAutoFitResolvedSysListView(hwndTop, targetCtrlNN, mode := "header_no_fill") {
    if (!hwndTop || !IsForegroundWindow(hwndTop) || !InStr(targetCtrlNN, "SysListView32", True))
        return False

    ControlGet, listViewHwnd, Hwnd,, %targetCtrlNN%, ahk_id %hwndTop%
    if (!listViewHwnd || !DllCall("user32\IsChild", "Ptr", hwndTop, "Ptr", listViewHwnd, "Int"))
        return False

    return AutoFitSysListViewColumns(listViewHwnd, mode)
}

; Revalidate a UIA-resolved Details target immediately before SendCtrlAdd()
; uses it. The CtrlNN must still name the same live child HWND and that child
; must still be a supported native file-view host.
_ValidateResolvedCtrlAddTarget(hwndTop, resolvedTarget) {
    traceRequestId := IsObject(resolvedTarget) ? resolvedTarget.requestId : ""
    if (!hwndTop || !IsObject(resolvedTarget)) {
        _TraceExplorerCtrlAdd("resolved_target_invalid"
            , "reason=missing_top_or_target hwnd=" . hwndTop
            , False, traceRequestId)
        return ""
    }

    targetCtrlNN   := resolvedTarget.ctrlNN
    targetCtrlHwnd := resolvedTarget.hwnd + 0
    targetExists   := targetCtrlHwnd
                   && DllCall("user32\IsWindow", "Ptr", targetCtrlHwnd, "Int")
    targetIsChild  := targetExists
                   && DllCall("user32\IsChild", "Ptr", hwndTop, "Ptr", targetCtrlHwnd, "Int")
    if (targetCtrlNN = "" || !targetCtrlHwnd || !targetExists || !targetIsChild) {
        _TraceExplorerCtrlAdd("resolved_target_invalid"
            , "reason=target_gone_or_not_child targetCtrl=[" . targetCtrlNN . "]"
            . " targetHwnd=" . targetCtrlHwnd
            . " targetExists=" . targetExists
            . " targetIsChild=" . targetIsChild
            , False, traceRequestId)
        return ""
    }

    ControlGet, currentCtrlHwnd, Hwnd,, %targetCtrlNN%, ahk_id %hwndTop%
    if (currentCtrlHwnd != targetCtrlHwnd) {
        _TraceExplorerCtrlAdd("resolved_target_invalid"
            , "reason=classnn_rebound targetCtrl=[" . targetCtrlNN . "]"
            . " expectedHwnd=" . targetCtrlHwnd
            . " actualHwnd=" . currentCtrlHwnd
            , False, traceRequestId)
        return ""
    }

    targetClass := GetClassName(targetCtrlHwnd)
    if (targetClass != "SysListView32" && targetClass != "DirectUIHWND") {
        _TraceExplorerCtrlAdd("resolved_target_invalid"
            , "reason=unsupported_class targetCtrl=[" . targetCtrlNN . "]"
            . " targetClass=" . targetClass
            , False, traceRequestId)
        return ""
    }

    _TraceExplorerCtrlAdd("resolved_target_valid"
        , "targetCtrl=[" . targetCtrlNN . "] targetHwnd=" . targetCtrlHwnd
        . " targetClass=" . targetClass
        , False, traceRequestId)

    return targetCtrlNN
}

; Adjust columns for the resolved file-view control. resolvedTarget optionally
; supplies a pre-resolved control; traceRequestId only enables diagnostic timing
; and must never influence target selection or validation.
SendCtrlAdd(initTargetHwnd := "", initTargetClass := "", initFocusedCtrlNN := "", waitForExplorerLoad := False, targetScan := "", restoreTreeFocus := True, resolvedTarget := "", traceRequestId := "") {
    global k_explorerCtrlAddTraceEnabled, k_nativeSysListViewColumnAutoFitMode
    global k_sendCtrlAddShellTabProbeTimeoutMs, k_useNativeSysListViewColumnAutoFit

    sendCtrlAddStartTick := A_TickCount
    hasResolvedTarget    := IsObject(resolvedTarget)
    if (traceRequestId = "" && hasResolvedTarget)
        traceRequestId := resolvedTarget.requestId
    traceThisCall := k_explorerCtrlAddTraceEnabled && traceRequestId != ""
    resolvedCtrl  := hasResolvedTarget ? resolvedTarget.ctrlNN : ""
    resolvedHwnd  := hasResolvedTarget ? resolvedTarget.hwnd : 0
    if traceThisCall
        _TraceExplorerCtrlAdd("sendctrladd_enter"
            , "targetHwnd=" . initTargetHwnd
            . " targetClass=" . initTargetClass
            . " sourceCtrl=[" . initFocusedCtrlNN . "]"
            . " waitForExplorerLoad=" . waitForExplorerLoad
            . " restoreTreeFocus=" . restoreTreeFocus
            . " hasTargetScan=" . IsObject(targetScan)
            . " hasResolvedTarget=" . hasResolvedTarget
            . " resolvedCtrl=[" . resolvedCtrl . "]"
            . " resolvedHwnd=" . resolvedHwnd
            , False, traceRequestId)

    TargetControl     := hasResolvedTarget
        ? _ValidateResolvedCtrlAddTarget(initTargetHwnd, resolvedTarget)
        : ""
    if (hasResolvedTarget && TargetControl = "") {
        _TraceExplorerCtrlAdd("sendctrladd_aborted"
            , "reason=resolved_target_validation_failed totalElapsedMs="
            . (A_TickCount - sendCtrlAddStartTick), False, traceRequestId)
        Return
    }

    If (initTargetClass == "")
        WinGetClass, lClassCheck, ahk_id %initTargetHwnd%
    Else
        lClassCheck := initTargetClass

    initTargetTid := DllCall("user32\GetWindowThreadProcessId", "Ptr", initTargetHwnd, "UInt*", 0, "UInt")
    initFocusedHwnd := initTargetTid ? GetThreadFocusHwnd(initTargetTid) : 0

    if traceThisCall
        _TraceExplorerCtrlAdd("sendctrladd_context_resolved"
            , "elapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
            . " targetClass=" . lClassCheck
            . " targetTid=" . initTargetTid
            . " initialFocusedHwnd=" . initFocusedHwnd
            , False, traceRequestId)

    WinGet, quickCheckID, ID, A
    If (quickCheckID != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd)) {
        SetTimer, SendCtrlAddLabel, Off
        WinGetClass, lClassCheck, ahk_id %initTargetHwnd%
        if traceThisCall
            _TraceExplorerCtrlAdd("sendctrladd_aborted"
                , "reason=target_not_foreground_or_gone activeHwnd=" . quickCheckID
                . " targetHwnd=" . initTargetHwnd
                . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                , False, traceRequestId)
        Return
    }
    if (GetKeyState("LShift", "P")) {
        if traceThisCall
            _TraceExplorerCtrlAdd("sendctrladd_aborted"
                , "reason=physical_lshift_held totalElapsedMs="
                . (A_TickCount - sendCtrlAddStartTick), False, traceRequestId)
        Return
    }
    If (!GetKeyState("LShift","P" )) {
        focusDiscoveryStartTick := A_TickCount
        If (initFocusedCtrlNN == "") {
            ; Prefer the focused child reported by the target window itself.
            ; Use one immediate mouse lookup when focus is blank or still too
            ; generic and readiness did not already resolve the exact target.
            ControlGetFocus, initFocusedCtrlNN, ahk_id %initTargetHwnd%
            if (TargetControl = ""
             && (initFocusedCtrlNN == "" || initFocusedCtrlNN == "ShellTabWindowClass1")) {
                MouseGetPos, , , , initFocusedCtrlNN

                hasScannedTarget := IsObject(targetScan)
                                 && (targetScan.hasSysList
                                  || targetScan.hasDirect2
                                  || targetScan.hasDirect3
                                  || targetScan.hasDirect4
                                  || targetScan.hasDirect6
                                  || targetScan.hasDirect8)

                ; Repeated mouse polling is needed only when no captured scan can
                ; resolve a pointer that remains over ShellTabWindowClass1.
                if (initFocusedCtrlNN == "ShellTabWindowClass1" && !hasScannedTarget) {
                    shellTabProbeDeadline := A_TickCount + k_sendCtrlAddShellTabProbeTimeoutMs
                    while (initFocusedCtrlNN == "ShellTabWindowClass1"
                        && A_TickCount < shellTabProbeDeadline) {
                        MouseGetPos, , , , initFocusedCtrlNN
                        sleep, 1
                    }
                }
            }
        }
        if traceThisCall
            _TraceExplorerCtrlAdd("sendctrladd_focus_discovery"
                , "elapsedMs=" . (A_TickCount - focusDiscoveryStartTick)
                . " focusedCtrl=[" . initFocusedCtrlNN . "]"
                . " targetAlreadyResolved=" . (TargetControl != "")
                , False, traceRequestId)

        If (GetKeyState("LButton","P") || WinExist("A") != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd))
        {
            if traceThisCall
                _TraceExplorerCtrlAdd("sendctrladd_aborted"
                    , "reason=pre_target_resolution_guard lbutton="
                    . GetKeyState("LButton", "P")
                    . " activeHwnd=" . WinExist("A")
                    . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                    , False, traceRequestId)
            Return
        }

        targetResolutionStartTick := A_TickCount
        if (TargetControl = "")
            TargetControl := GetSendCtrlAddTargetCtrl(initTargetHwnd, initFocusedCtrlNN, lClassCheck, targetScan)
        if traceThisCall
            _TraceExplorerCtrlAdd("sendctrladd_target_resolution"
                , "elapsedMs=" . (A_TickCount - targetResolutionStartTick)
                . " source=" . (hasResolvedTarget ? "pre_resolved" : "runtime")
                . " targetCtrl=[" . TargetControl . "]"
                , False, traceRequestId)

        If (GetKeyState("LButton","P") || WinExist("A") != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd))
        {
            if traceThisCall
                _TraceExplorerCtrlAdd("sendctrladd_aborted"
                    , "reason=post_target_resolution_guard lbutton="
                    . GetKeyState("LButton", "P")
                    . " activeHwnd=" . WinExist("A")
                    . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                    , False, traceRequestId)
            Return
        }

        If (GetKeyState("LButton","P") || TargetControl == "" || WinExist("A") != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd))
        {
            if traceThisCall
                _TraceExplorerCtrlAdd("sendctrladd_aborted"
                    , "reason=missing_or_invalid_target targetCtrl=[" . TargetControl . "]"
                    . " lbutton=" . GetKeyState("LButton", "P")
                    . " activeHwnd=" . WinExist("A")
                    . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                    , False, traceRequestId)
            Return
        }

        ; Native report-view ListViews accept column-width messages directly,
        ; so their columns can be adjusted without changing keyboard focus or
        ; injecting Ctrl. Navigation still uses the existing shell-readiness
        ; wait. Disabling the feature flag, or any direct-message failure,
        ; falls through to the original focus-and-chord path below.
        if (k_useNativeSysListViewColumnAutoFit && InStr(TargetControl, "SysListView32", True)) {
            if (waitForExplorerLoad && (lClassCheck == "CabinetWClass" || lClassCheck == "#32770")) {
                explorerLoadStartTick := A_TickCount
                WaitForExplorerLoad(initTargetHwnd, (TargetControl == initFocusedCtrlNN), False)
                if traceThisCall
                    _TraceExplorerCtrlAdd("sendctrladd_explorer_load_wait"
                        , "elapsedMs=" . (A_TickCount - explorerLoadStartTick)
                        . " branch=native_syslist targetCtrl=[" . TargetControl . "]"
                        , False, traceRequestId)
            }

            nativeAutoFitStartTick := A_TickCount
            nativeAutoFitSucceeded := _TryAutoFitResolvedSysListView(initTargetHwnd
                , TargetControl, k_nativeSysListViewColumnAutoFitMode)
            if traceThisCall
                _TraceExplorerCtrlAdd("native_autofit_result"
                    , "elapsedMs=" . (A_TickCount - nativeAutoFitStartTick)
                    . " succeeded=" . nativeAutoFitSucceeded
                    . " mode=" . k_nativeSysListViewColumnAutoFitMode
                    . " targetCtrl=[" . TargetControl . "]"
                    , False, traceRequestId)
            if nativeAutoFitSucceeded {
                if traceThisCall
                    _TraceExplorerCtrlAdd("sendctrladd_complete"
                        , "outcome=native_autofit totalElapsedMs="
                        . (A_TickCount - sendCtrlAddStartTick)
                        , False, traceRequestId)
                Return
            }
        }

        If (TargetControl == "DirectUIHWND3" && (lClassCheck == "#32770" || lClassCheck == "CabinetWClass")) {
            if (waitForExplorerLoad) {
                explorerLoadStartTick := A_TickCount
                WaitForExplorerLoad(initTargetHwnd, False, True)
                if traceThisCall
                    _TraceExplorerCtrlAdd("sendctrladd_explorer_load_wait"
                        , "elapsedMs=" . (A_TickCount - explorerLoadStartTick)
                        . " branch=DirectUIHWND3 targetCtrl=[" . TargetControl . "]"
                        , False, traceRequestId)
            }
            If (hasResolvedTarget || TargetControl != initFocusedCtrlNN) {

                focusStartTick := A_TickCount
                focusSucceeded := _EnsureFocusedCtrlAddTarget(initTargetHwnd, TargetControl
                    , resolvedHwnd, hasResolvedTarget, 60, 15, lClassCheck)
                if traceThisCall
                    _TraceExplorerCtrlAdd("sendctrladd_focus_result"
                        , "elapsedMs=" . (A_TickCount - focusStartTick)
                        . " succeeded=" . focusSucceeded
                        . " branch=DirectUIHWND3 targetCtrl=[" . TargetControl . "]"
                        , False, traceRequestId)
                if !focusSucceeded {
                    if traceThisCall
                        _TraceExplorerCtrlAdd("sendctrladd_aborted"
                            , "reason=focus_failed branch=DirectUIHWND3"
                            . " elapsedMs=" . (A_TickCount - focusStartTick)
                            . " targetCtrl=[" . TargetControl . "]"
                            . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                            , False, traceRequestId)
                    Return
                }
            }
        }
        Else If (TargetControl == "DirectUIHWND2" && (lClassCheck == "#32770" || lClassCheck == "CabinetWClass")) {
            if (waitForExplorerLoad) {
                explorerLoadStartTick := A_TickCount
                WaitForExplorerLoad(initTargetHwnd, True, False)
                if traceThisCall
                    _TraceExplorerCtrlAdd("sendctrladd_explorer_load_wait"
                        , "elapsedMs=" . (A_TickCount - explorerLoadStartTick)
                        . " branch=DirectUIHWND2 targetCtrl=[" . TargetControl . "]"
                        , False, traceRequestId)
            }
            If (hasResolvedTarget || TargetControl != initFocusedCtrlNN) {

                focusStartTick := A_TickCount
                focusSucceeded := _EnsureFocusedCtrlAddTarget(initTargetHwnd, TargetControl
                    , resolvedHwnd, hasResolvedTarget, 60, 15, lClassCheck)
                if traceThisCall
                    _TraceExplorerCtrlAdd("sendctrladd_focus_result"
                        , "elapsedMs=" . (A_TickCount - focusStartTick)
                        . " succeeded=" . focusSucceeded
                        . " branch=DirectUIHWND2 targetCtrl=[" . TargetControl . "]"
                        , False, traceRequestId)
                if !focusSucceeded {
                    if traceThisCall
                        _TraceExplorerCtrlAdd("sendctrladd_aborted"
                            , "reason=focus_failed branch=DirectUIHWND2"
                            . " elapsedMs=" . (A_TickCount - focusStartTick)
                            . " targetCtrl=[" . TargetControl . "]"
                            . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                            , False, traceRequestId)
                    Return
                }
            }
        }
        Else If (lClassCheck == "CabinetWClass" || lClassCheck == "#32770") {
            if (waitForExplorerLoad) {
                ; This fallback shell branch already resolved a real content target.
                ; Skip the slower UIA focus-confirmation part when focus is already
                ; on that target and only the content-readiness wait still matters.
                explorerLoadStartTick := A_TickCount
                WaitForExplorerLoad(initTargetHwnd, (TargetControl == initFocusedCtrlNN), False)
                if traceThisCall
                    _TraceExplorerCtrlAdd("sendctrladd_explorer_load_wait"
                        , "elapsedMs=" . (A_TickCount - explorerLoadStartTick)
                        . " branch=shell_fallback targetCtrl=[" . TargetControl . "]"
                        , False, traceRequestId)
            }
            if (hasResolvedTarget || TargetControl != initFocusedCtrlNN) {

                focusStartTick := A_TickCount
                focusSucceeded := _EnsureFocusedCtrlAddTarget(initTargetHwnd, TargetControl
                    , resolvedHwnd, hasResolvedTarget, 60, 15, lClassCheck)
                if traceThisCall
                    _TraceExplorerCtrlAdd("sendctrladd_focus_result"
                        , "elapsedMs=" . (A_TickCount - focusStartTick)
                        . " succeeded=" . focusSucceeded
                        . " branch=shell_fallback targetCtrl=[" . TargetControl . "]"
                        , False, traceRequestId)
                if !focusSucceeded {
                    if traceThisCall
                        _TraceExplorerCtrlAdd("sendctrladd_aborted"
                            , "reason=focus_failed branch=shell_fallback"
                            . " elapsedMs=" . (A_TickCount - focusStartTick)
                            . " targetCtrl=[" . TargetControl . "]"
                            . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                            , False, traceRequestId)
                    Return
                }
            }
        }
        Else {
            If (hasResolvedTarget || TargetControl != initFocusedCtrlNN) {
                focusStartTick := A_TickCount
                focusSucceeded := _EnsureFocusedCtrlAddTarget(initTargetHwnd, TargetControl
                    , resolvedHwnd, hasResolvedTarget, 60, 15, lClassCheck)
                if traceThisCall
                    _TraceExplorerCtrlAdd("sendctrladd_focus_result"
                        , "elapsedMs=" . (A_TickCount - focusStartTick)
                        . " succeeded=" . focusSucceeded
                        . " branch=non_shell targetCtrl=[" . TargetControl . "]"
                        , False, traceRequestId)
                if !focusSucceeded {
                    ; Everything accepts Ctrl+NumpadAdd while Edit1 is focused whereas most other applications don't
                    WinGet, focusFailureProcess, ProcessName, ahk_id %initTargetHwnd%
                    if (focusFailureProcess != "Everything.exe") {
                        if traceThisCall
                            _TraceExplorerCtrlAdd("sendctrladd_aborted"
                                , "reason=focus_failed branch=non_shell"
                                . " process=" . focusFailureProcess
                                . " targetCtrl=[" . TargetControl . "]"
                                . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                                , False, traceRequestId)
                        Return
                    }
                    if traceThisCall
                        _TraceExplorerCtrlAdd("sendctrladd_focus_failure_tolerated"
                            , "process=" . focusFailureProcess
                            . " targetCtrl=[" . TargetControl . "]"
                            , False, traceRequestId)
                }
            }
        }

        If (GetKeyState("LButton","P") || TargetControl == "" || WinExist("A") != initTargetHwnd || !WinExist("ahk_id " . initTargetHwnd))
        {
            if traceThisCall
                _TraceExplorerCtrlAdd("sendctrladd_aborted"
                    , "reason=final_pre_send_guard targetCtrl=[" . TargetControl . "]"
                    . " lbutton=" . GetKeyState("LButton", "P")
                    . " activeHwnd=" . WinExist("A")
                    . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                    , False, traceRequestId)
            Return
        }

        If (InStr(TargetControl, "SysListView32", True) || InStr(TargetControl,  "DirectUIHWND", True)) {
            BeginBlockKeys()
            try {
                ctrlNumpadAddStartTick := A_TickCount
                if traceThisCall
                    _TraceExplorerCtrlAdd("ctrl_numpadadd_send"
                        , "targetCtrl=[" . TargetControl . "]"
                        . " initialFocus=[" . initFocusedCtrlNN . "]"
                        , False, traceRequestId)
                Send, ^{NumpadAdd}
                if traceThisCall
                    _TraceExplorerCtrlAdd("ctrl_numpadadd_sent"
                        , "elapsedMs=" . (A_TickCount - ctrlNumpadAddStartTick)
                        . " targetCtrl=[" . TargetControl . "]"
                        , False, traceRequestId)

                If ((InStr(initFocusedCtrlNN,"Edit",True)
                  || (restoreTreeFocus && InStr(initFocusedCtrlNN,"Tree",True)))
                 && initFocusedCtrlNN != TargetControl) {
                    ; Skip the heavier restore path when Ctrl+NumpadAdd already left
                    ; focus on the original control/window.
                    focusRestoreDecisionStartTick := A_TickCount
                    restoreNeeded := True
                    currentFocusedCtrlNN := ""
                    currentFocusedHwnd := ""
                    if (initTargetTid) {
                        currentFocusedHwnd := GetThreadFocusHwnd(initTargetTid)
                        if (initFocusedHwnd && currentFocusedHwnd = initFocusedHwnd)
                            restoreNeeded := False
                    }
                    if (restoreNeeded) {
                        ControlGetFocus, currentFocusedCtrlNN, ahk_id %initTargetHwnd%
                        if (currentFocusedCtrlNN = initFocusedCtrlNN)
                            restoreNeeded := False
                    }
                    if traceThisCall
                        _TraceExplorerCtrlAdd("focus_restore_decision"
                            , "elapsedMs=" . (A_TickCount - focusRestoreDecisionStartTick)
                            . " needed=" . restoreNeeded
                            . " initialFocusHwnd=" . initFocusedHwnd
                            . " currentFocusHwnd=" . currentFocusedHwnd
                            . " initialFocusCtrl=[" . initFocusedCtrlNN . "]"
                            . " currentFocusCtrl=[" . currentFocusedCtrlNN . "]"
                            , False, traceRequestId)

                    if (restoreNeeded) {
                        focusRestoreDelayStartTick := A_TickCount
                        sleep, 125
                        EndBlockKeys()
                        if traceThisCall
                            _TraceExplorerCtrlAdd("focus_restore_delay"
                                , "elapsedMs=" . (A_TickCount - focusRestoreDelayStartTick)
                                , False, traceRequestId)

                        If (GetKeyState("LButton","P") || WinExist("A") != initTargetHwnd) {
                            if traceThisCall
                                _TraceExplorerCtrlAdd("focus_restore_skipped"
                                    , "reason=lbutton_or_foreground_changed lbutton="
                                    . GetKeyState("LButton", "P")
                                    . " activeHwnd=" . WinExist("A")
                                    . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                                    , False, traceRequestId)
                            Return
                        }

                        ; Use bounded focus+verify instead of 200 iterations.
                        focusRestoreStartTick := A_TickCount
                        if (initFocusedHwnd && DllCall("user32\IsWindow", "Ptr", initFocusedHwnd, "Int")) {
                            focusRestoreMethod := "hwnd"
                            focusRestoreSucceeded := EnsureFocusedHwnd(initFocusedHwnd, 120, 15)
                        }
                        else {
                            focusRestoreMethod := "ctrlnn"
                            focusRestoreSucceeded := EnsureFocusedCtrlTarget(initTargetHwnd
                                , initFocusedCtrlNN, 120, 15, lClassCheck)
                        }
                        if traceThisCall
                            _TraceExplorerCtrlAdd("focus_restore_result"
                                , "elapsedMs=" . (A_TickCount - focusRestoreStartTick)
                                . " succeeded=" . focusRestoreSucceeded
                                . " method=" . focusRestoreMethod
                                . " targetHwnd=" . initFocusedHwnd
                                . " targetCtrl=[" . initFocusedCtrlNN . "]"
                                , False, traceRequestId)
                    }
                }
            } finally {
                ; Always release blocking and synchronize Ctrl, including when
                ; focus restoration exits early after the synthetic chord.
                modifierCleanupStartTick := A_TickCount
                EndBlockKeys()
                SyncModifierSidesToPhys("Ctrl", initTargetHwnd)
                ScheduleModifierSync("Ctrl", 6, initTargetHwnd)
                if traceThisCall {
                    _TraceExplorerCtrlAdd("modifier_cleanup_complete"
                        , "elapsedMs=" . (A_TickCount - modifierCleanupStartTick)
                        . " targetHwnd=" . initTargetHwnd
                        , False, traceRequestId)
                    _TraceExplorerCtrlAdd("ctrl_numpadadd_complete"
                        , "outcome=ctrl_numpadadd targetCtrl=[" . TargetControl . "]"
                        . " focusRestoreCandidate="
                        . ((InStr(initFocusedCtrlNN, "Edit", True)
                         || (restoreTreeFocus && InStr(initFocusedCtrlNN, "Tree", True)))
                         && initFocusedCtrlNN != TargetControl)
                        . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                        , False, traceRequestId)
                }
            }
        }
        else if traceThisCall
            _TraceExplorerCtrlAdd("sendctrladd_aborted"
                , "reason=unsupported_target_control targetCtrl=[" . TargetControl . "]"
                . " totalElapsedMs=" . (A_TickCount - sendCtrlAddStartTick)
                , False, traceRequestId)
    }
Return
}

IsAlwaysOnTop(hwndID) {
    WinGet, ExStyle, ExStyle, ahk_id %hwndId% ; 0x8 is WS_EX_LAYERED.
    If (ExStyle & 0x8)
        Return True
    Else
        Return False
}

/* ;
***********************************
***** SHORTCUTS CONFIGURATION *****
***** https://github.com/JuanmaMenendez/AutoHotkey-script-Open-Show-Apps/blob/master/Switch-opened-windows-of-same-App.ahk ****
***********************************
*/
VolumeHover() {
    If WinExist("ahk_class tooltips_class32") {
        ControlGetText, toolText,, ahk_class tooltips_class32
        If (InStr(toolText, "Speakers",False) || InStr(toolText, "Headphones",False) || (InStr(toolText, "Audio",False) && InStr(toolText, "Output",False))) {
            Return True
        }
    }
    Else {
        Return False
    }
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
IsOverException(hWnd := "") {
    If (hWnd == "")
        MouseGetPos, , , hwndID, ctrlNN
    Else
        hwndID := hWnd

    WinGetTitle, tit, ahk_id %hwndID%
    WinGetClass, cl, ahk_id %hwndID%
    WinGet, proc, ProcessName, ahk_id %hwndID%

    If (   proc == "peazip.exe"
        || proc == "SndVol.exe"
        || ((InStr("File Explorer", tit, True) || proc == "explorer.exe") && (InStr("Home", tit, True) || InStr("This PC", tit, True) || InStr("Gallery", tit, True)))
        || (InStr("InstallShield", tit, True))
        || InStr(ctrlNN, "SysTabControl", True)
        || cl == "#32768"
        || cl == "MsoCommandBarPopup"
        || cl == "Autohotkey"
        || cl == "AutohotkeyGUI"
        || cl == "SysShadow"
        || cl == "TaskListThumbnailWnd"
        || cl == "Windows.UI.Core.CoreWindow"
        || cl == "ProgMan"
        || cl == "WorkerW"
        || cl == "tooltips_class32"
        || cl == "DropDown"
        || cl == "Microsoft.UI.Content.PopupWindowSiteBridge"
        || cl == "TopLevelWindowForOverflowXamlIsland"
        || cl == "OperationStatusWindow"
        || cl == "NativeHWNDHost"
        || cl == "Net UI Tool Window"
        || cl == "SDL_app"
        || cl == "DV2ControlHost"
        || cl == "TfrmSafelyRemoveMenu"
        || cl == "Qt6101QWindowIcon"
        || (cl != "#32770" && cl != "CabinetWClass" && InStr(tit, "VirtualBox",True)))
        Return True
    Else
        Return False
}

IsChromiumBrowserWindow(windowHwnd, windowClass := "") {
    if (!windowHwnd)
        return False

    if (windowClass == "")
        WinGetClass, windowClass, ahk_id %windowHwnd%

    if (windowClass != "Chrome_WidgetWin_1")
        return False

    WinGet, processName, ProcessName, ahk_id %windowHwnd%
    return (processName == "chrome.exe" || processName == "msedge.exe")
}

IsChromiumContentClick(windowHwnd, windowClass := "", ctrlNN := "") {
    if (!IsChromiumBrowserWindow(windowHwnd, windowClass))
        return False

    ; Chromium web content usually reports the renderer host control directly,
    ; but some builds return no child ClassNN for the same content surface.
    if (ctrlNN == "")
        return True

    return (   InStr(ctrlNN, "Chrome_RenderWidgetHostHWND", True)
            || InStr(ctrlNN, "Intermediate D3D Window", True))
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
    static LVM_SETCOLUMNWIDTH         := 0x101E
    ; Size a column to the widest text in its item contents.
    static LVSCW_AUTOSIZE             := -1
    ; Size a column to its header text; the final column may fill remaining space.
    static LVSCW_AUTOSIZE_USEHEADER   := -2
    static SMTO_ABORTIFHUNG_AND_BLOCK := 0x0003

    if (!listViewHwnd || !DllCall("user32\IsWindow", "Ptr", listViewHwnd, "Int"))
        return False
    if (GetWindowClassName(listViewHwnd) != "SysListView32" || !IsSysListViewReportView(listViewHwnd))
        return False

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
; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=81064#p533551
ShowMenuX(hMenu, X := "", Y := "", Flags := 0) {   ; Show popup menu by handle or by AHK menu name.
                                                   ; Based on ShowMenu v0.63 by SKAN.
    Local

    ; If hMenu is not already a numeric HMENU handle,
    ; assume it is an AutoHotkey menu name like "Tray" or "windows"
    ; and convert it to the underlying Win32 menu handle.
    If hMenu Is Not Integer
        hMenu := MenuGetHandle(hMenu)

    ; If X or Y was not provided, use the current mouse position.
    ; Temporarily switch mouse CoordMode to Screen so the popup
    ; position is based on absolute screen coordinates.
    If (X = "" Or Y = "") {
        CMM := A_CoordModeMouse
        CoordMode, Mouse, Screen
        MouseGetPos, XX, YY
        CoordMode, Mouse, %CMM%

        ; Only fill in whichever coordinate was omitted.
        X := X = "" ? XX : X
        Y := Y = "" ? YY : Y
    }

    ; Strip out flags this wrapper does not want the caller using:
    ; 0x100 = TPM_RETURNCMD
    ; 0x080 = TPM_NONOTIFY
    ; This function expects normal menu command handling instead.
    Flags &= ~0x180

    ; Remember the window that currently has focus so it can be restored later.
    pWnd := DllCall("User32\GetForegroundWindow", "Ptr")

    ; Set the script window as foreground.
    ; This is important for proper popup-menu behavior and dismissal.
    DllCall("User32\SetForegroundWindow", "Ptr", mWnd := A_ScriptHwnd)

    ; These were likely considered to prevent interruption while the menu is shown.
    ; Old_IsCritical := A_IsCritical
    ; Critical On

    ; Show the popup menu at screen position X,Y using the requested flags.
    ; hMenu must be a real HMENU handle at this point.
    ; mWnd is used as the owner window for the popup.
    R := DllCall("User32\TrackPopupMenuEx"
        , "Ptr", hMenu
        , "UInt", Flags
        , "Int", X
        , "Int", Y
        , "Ptr", mWnd
        , "Ptr", 0
        , "UInt")

    ; Give AutoHotkey a moment to receive/process the WM_COMMAND
    ; generated by the selected menu item.
    Sleep, 10

    ; Post a null message to help the popup menu fully close/settle.
    DllCall("User32\PostMessage", "Ptr", mWnd, "Int", 0, "Ptr", 0, "Ptr", 0)

    ; If the script window is still foreground but not actually active,
    ; restore the previously focused window.
    If DllCall("User32\GetForegroundWindow", "Ptr") = mWnd And Not WinActive("ahk_id " mWnd)
        DllCall("User32\SetForegroundWindow", "Ptr", pWnd)

    ; Restore previous Critical state if you decide to enable it above.
    ; Critical %Old_IsCritical%

    Return R
}


; https://www.autohotkey.com/boards/viewtopic.php?f=6&t=31716
GetCurrentMonitorIndex(){
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my
    SysGet, monitorsCount, 80

    Loop, %monitorsCount% {
        SysGet, monitor, Monitor, %A_Index%
        If (monitorLeft <= mx && mx <= monitorRight && monitorTop <= my && my <= monitorBottom){
            Return A_Index
        }
    }
    Return 0
}

CoordXCenterScreen()
{
    ScreenNumber := GetCurrentMonitorIndex()
    SysGet, Mon1, Monitor, %ScreenNumber%
    Return (( Mon1Right-Mon1Left ) / 2) + Mon1Left
}

CoordYCenterScreen()
{
    ScreenNumber := GetCurrentMonitorIndex()
    SysGet, Mon1, Monitor, %ScreenNumber%
    Return ((Mon1Bottom-Mon1Top - 30) / 2) + Mon1Top
}

; https://www.autohotkey.com/boards/viewtopic.php?t=37184
; gives you roughly the correct results (tested on Windows 7)
; The function approximates Windows' Alt-Tab eligibility:
; Include: visible, enabled, top-level windows; anything explicitly marked WS_EX_APPWINDOW.
; Exclude: child/owned/tool windows, non-activating windows, disabled/invisible windows, and some known host processes.
JEE_WinHasAltTabIcon(hWnd)
{
    local
    If !(DllCall("user32\GetDesktopWindow", "Ptr") = DllCall("user32\GetAncestor", "Ptr",hWnd, "UInt",1, "Ptr")) ;GA_PARENT := 1
    ;|| DllCall("user32\GetWindow", "Ptr",hWnd, "UInt",4, "Ptr") ;GW_OWNER := 4 ;affects taskbar but not alt-tab
        Return 0

    WinGet, vWinProc, ProcessName, % "ahk_id " hWnd
    If InStr(vWinProc, "InputHost.exe") || InStr(vWinProc, "App.exe")
        Return 0

    WinGet, vWinStyle, Style, % "ahk_id " hWnd
    If !vWinStyle
    || !(vWinStyle & 0x10000000) ;WS_VISIBLE := 0x10000000
    || (vWinStyle & 0x8000000) ;WS_DISABLED := 0x8000000 ;affects alt-tab but not taskbar
        Return 0
    WinGet, vWinExStyle, ExStyle, % "ahk_id " hWnd
    If (vWinExStyle & 0x40000) ;WS_EX_APPWINDOW := 0x40000
        Return 1
    If (vWinExStyle & 0x80) ;WS_EX_TOOLWINDOW := 0x80
    || (vWinExStyle & 0x8000000) ;WS_EX_NOACTIVATE := 0x8000000 ;affects alt-tab but not taskbar
        Return 0
    Return 1
}

IsAltTabWindow_Why(hWnd)
{
    static WS_EX_APPWINDOW     := 0x40000
    static WS_EX_TOOLWINDOW    := 0x80
    static DWMWA_CLOAKED       := 14
    static DWM_CLOAKED_SHELL   := 2
    static WS_EX_NOACTIVATE    := 0x8000000
    static GA_PARENT           := 1
    static GW_OWNER            := 4
    static WS_EX_WINDOWEDGE    := 0x100
    static WS_EX_CONTROLPARENT := 0x10000
    static WS_EX_DLGMODALFRAME := 0x00000001

    WinGetTitle, hasTitle, ahk_id %hWnd%
    if (!hasTitle)
        return "no title"

    if !DllCall("IsWindowVisible", "uptr", hWnd)
        return "not visible"

    DllCall("DwmApi\DwmGetWindowAttribute", "uptr", hWnd, "uint", DWMWA_CLOAKED, "uint*", cloaked, "uint", 4)
    if (cloaked = DWM_CLOAKED_SHELL)
        return "cloaked shell"

    parent := DllCall("GetAncestor", "uptr", hWnd, "uint", GA_PARENT, "ptr")
    if (parent && realHwnd(parent) != realHwnd(DllCall("GetDesktopWindow", "ptr")))
        return "parent not desktop"

    WinGetClass, winClass, ahk_id %hWnd%
    if (winClass = "Windows.UI.Core.CoreWindow" || winClass = "ProgMan" || winClass = "WorkerW")
        return "blocked class: " . winClass

    WinGet, exStyles, ExStyle, ahk_id %hWnd%
    if (exStyles & WS_EX_APPWINDOW)
        return "passes via WS_EX_APPWINDOW"

    if (exStyles & WS_EX_TOOLWINDOW)
        return "toolwindow"
    if (exStyles & WS_EX_NOACTIVATE)
        return "noactivate"
    if (exStyles & WS_EX_DLGMODALFRAME)
        return "dlgmodalframe"

    if (exStyles & (WS_EX_WINDOWEDGE | WS_EX_CONTROLPARENT))
        return "passes via edge/controlparent"

    hwnd2 := hWnd
    Loop
    {
        prev := hwnd2
        hwnd2 := DllCall("GetWindow", "uptr", hwnd2, "uint", GW_OWNER, "ptr")
        if (!hwnd2)
            return "passes via owner-walk end (prev=" . prev . ")"

        if DllCall("IsWindowVisible", "uptr", hwnd2)
            return "visible owner: " . hwnd2
    }
}

IsAltTabWindow_Why2(hWnd)
{
    static WS_EX_APPWINDOW       := 0x40000
    static WS_EX_TOOLWINDOW      := 0x80
    static DWMWA_CLOAKED         := 14
    static DWM_CLOAKED_SHELL     := 2
    static WS_EX_NOACTIVATE      := 0x8000000
    static GA_PARENT             := 1
    static GW_OWNER              := 4
    static WS_EX_WINDOWEDGE      := 0x100
    static WS_EX_CONTROLPARENT   := 0x10000

    WinGetTitle, hasTitle, ahk_id %hWnd%
    WinGetClass, winClass, ahk_id %hWnd%

    if (!hasTitle && winClass != "CASCADIA_HOSTING_WINDOW_CLASS")
        return "no title (class=" . winClass . ")"

    isMinimized := DllCall("IsIconic", "uptr", hWnd)
    if (!DllCall("IsWindowVisible", "uptr", hWnd) && !isMinimized)
        return "not visible (and not minimized)"

    cloaked := 0
    DllCall("DwmApi\DwmGetWindowAttribute", "uptr", hWnd, "uint", DWMWA_CLOAKED, "uint*", cloaked, "uint", 4)
    if (cloaked = DWM_CLOAKED_SHELL)
        return "cloaked shell"

    if (realHwnd(DllCall("GetAncestor", "uptr", hWnd, "uint", GA_PARENT, "ptr")) != realHwnd(DllCall("GetDesktopWindow", "ptr")))
        return "parent not desktop"

    if (winClass = "Windows.UI.Core.CoreWindow"
        || (InStr(winClass, "Shell", False) && InStr(winClass, "TrayWnd", False))
        || winClass == "ProgMan"
        || winClass == "WorkerW")
        return "blocked class=" . winClass

    WinGet, exStyles, ExStyle, ahk_id %hWnd%

    if (exStyles & WS_EX_APPWINDOW)
        return "passes: WS_EX_APPWINDOW"

    if (exStyles & WS_EX_TOOLWINDOW)
        return "fails: WS_EX_TOOLWINDOW"

    if (exStyles & WS_EX_NOACTIVATE)
        return "fails: WS_EX_NOACTIVATE"

    if (exStyles & (WS_EX_WINDOWEDGE | WS_EX_CONTROLPARENT))
        return "passes: WS_EX_WINDOWEDGE/WS_EX_CONTROLPARENT"

    hWnd2 := hWnd
    Loop
    {
        prev := hWnd2
        hWnd2 := DllCall("GetWindow", "uptr", hWnd2, "uint", GW_OWNER, "ptr")
        if (!hWnd2)
            return "owner-walk ended => would pass (prev=" . prev . ")"

        if (DllCall("IsWindowVisible", "uptr", hWnd2))
            return "fails: visible owner=" . hWnd2 . " (prev=" . prev . ")"
    }
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
    static VirtualDesktopExist
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


GetLastActivePopup(hwnd)
{
   static GA_ROOTOWNER := 3
   hwnd := DllCall("GetAncestor", "uptr", hwnd, "uint", GA_ROOTOWNER, "ptr")
   hwnd := DllCall("GetLastActivePopup", "uptr", hwnd, "ptr")
   Return hwnd
}

PropEnumProcEx(hWnd, lpszString, hData, dwData)
{
   If (strget(lpszString, "UTF-16") = "ApplicationViewCloakType")
   {
      numput(hData, dwData+0, 0, "int")
      Return False
   }
   Return True
}

realHwnd(hwnd)
{
   varsetcapacity(var, 8, 0)
   numput(hwnd, var, 0, "uint64")
   Return numget(var, 0, "uint")
}

GetDesktopCount() {
    global GetDesktopCountProc

    if (!InitVDA() || !GetDesktopCountProc)
        return 1
    return DllCall(GetDesktopCountProc, "Int")
}

GoToDesktopNumber(num) {
    global GoToDesktopNumberProc

    if (!InitVDA() || !GoToDesktopNumberProc)
        return false

    ; Caller passes 1-based. DLL expects 0-based.
    correctDesktopNumber := num - 1
    if (correctDesktopNumber < 0)
        correctDesktopNumber := 0

    return DllCall(GoToDesktopNumberProc, "Int", correctDesktopNumber, "Int")
}

GetCurrentDesktopNumber() {
    global GetCurrentDesktopNumberProc

    if (!InitVDA() || !GetCurrentDesktopNumberProc)
        return 1
    return DllCall(GetCurrentDesktopNumberProc, "Int")
}

GoToPrevDesktop() {
    global GetCurrentDesktopNumberProc

    if (!InitVDA() || !GetCurrentDesktopNumberProc)
        return false

    current := GetCurrentDesktopNumber() ; typically 0-based
    last_desktop := GetDesktopCount() - 1                  ; 0-based max index

    if (last_desktop < 0)
        last_desktop := 0

    ; If current desktop is 0, go to last desktop
    if (current = 0) {
        MoveOrGotoDesktopNumber(last_desktop)
    } else {
        MoveOrGotoDesktopNumber(current - 1)
    }
    return true
}

GoToNextDesktop() {
    global GetCurrentDesktopNumberProc

    if (!InitVDA() || !GetCurrentDesktopNumberProc)
        return false

    current := GetCurrentDesktopNumber() ; typically 0-based
    last_desktop := GetDesktopCount() - 1                  ; 0-based max index

    if (last_desktop < 0)
        last_desktop := 0

    ; If current desktop is last, go to first desktop
    if (current = last_desktop) {
        MoveOrGotoDesktopNumber(0)
    } else {
        MoveOrGotoDesktopNumber(current + 1)
    }
    return true
}

IsWindowOnCurrentVirtualDesktop(hwnd) {
    global IsWindowOnCurrentVirtualDesktopProc

    ; Fail-open: if VDA is unavailable, don't incorrectly exclude windows
    if (!InitVDA() || !IsWindowOnCurrentVirtualDesktopProc)
        return true
    return DllCall(IsWindowOnCurrentVirtualDesktopProc, "Ptr", hwnd, "Int")
}
; ---- Window/Desktop queries ----
IsWindowOnDesktopNumber(hwnd, desktopNumber)
{
    global IsWindowOnDesktopNumberProc
    if (!InitVDA() || !IsWindowOnDesktopNumberProc)
        return 0

    return DllCall(IsWindowOnDesktopNumberProc
        , "Int"            ; return type
        , "Ptr", hwnd
        , "Int", desktopNumber)
}


MoveWindowToDesktopNumber(hwnd, desktopNumber)
{
    global MoveWindowToDesktopNumberProc
    ; Fail-open: if VDA is unavailable, don't incorrectly exclude windows
    if (!InitVDA() || !MoveWindowToDesktopNumberProc)
        return true
    return DllCall(MoveWindowToDesktopNumberProc
        , "Ptr", hwnd
        , "Int", desktopNumber
        , "Int") ; return i32
}

IsPinnedWindow(hwnd)
{
    global IsPinnedWindowProc
    ; Fail-open: if VDA is unavailable, don't incorrectly exclude windows
    if (!InitVDA() || !IsPinnedWindowProc)
        return true
    return DllCall(IsPinnedWindowProc
        , "Ptr", hwnd
        , "Int") ; return i32 (typically 1/0)
}

; ---- Desktop naming (Win11-only exports in this DLL) ----

GetDesktopName(desktopNumber, bufSize := 1024)
{
    global GetDesktopNameProc
    ; Fail-open: if VDA is unavailable, don't incorrectly exclude windows
    if (!InitVDA() || !GetDesktopNameProc)
        return true

    VarSetCapacity(utf8_buffer, bufSize, 0)
    ran := DllCall(GetDesktopNameProc
        , "Int", desktopNumber
        , "Ptr", &utf8_buffer
        , "Ptr", bufSize
        , "Int") ; return i32

    ; If you care about ran, you can check it here.
    return StrGet(&utf8_buffer, bufSize, "UTF-8")
}

SetDesktopName(desktopNumber, name)
{
    ; NOTE: for UTF-8 literals to work correctly, save this .ahk as UTF-8 with BOM.
    global SetDesktopNameProc
    ; Fail-open: if VDA is unavailable, don't incorrectly exclude windows
    if (!InitVDA() || !SetDesktopNameProc)
        return true
    VarSetCapacity(name_utf8, 1024, 0)
    StrPut(name, &name_utf8, "UTF-8")

    return DllCall(SetDesktopNameProc
        , "Int", desktopNumber
        , "Ptr", &name_utf8
        , "Int") ; return i32
}

; ---- Desktop creation/removal (Win11-only exports in this DLL) ----

CreateDesktop()
{
    global CreateDesktopProc
    ; Fail-open: if VDA is unavailable, don't incorrectly exclude windows
    if (!InitVDA() || !CreateDesktopProc)
        return true
    return DllCall(CreateDesktopProc
        , "Int") ; return i32 (often new desktop number, or -1 on failure)
}

RemoveDesktop(removeDesktopNumber, fallbackDesktopNumber)
{
    global RemoveDesktopProc
    ; Fail-open: if VDA is unavailable, don't incorrectly exclude windows
    if (!InitVDA() || !RemoveDesktopProc)
        return true
    return DllCall(RemoveDesktopProc
        , "Int", removeDesktopNumber
        , "Int", fallbackDesktopNumber
        , "Int") ; return i32 (often 1/0)
}

MoveCurrentWindowToDesktopAndSwitch(desktopNumber) {
    global MoveWindowToDesktopNumberProc, GoToDesktopNumberProc

    if (!InitVDA() || !MoveWindowToDesktopNumberProc || !GoToDesktopNumberProc)
        return false

    ; desktopNumber is already zero-based; pass it directly to both DLL procedures.
    WinGet, activeHwnd, ID, A
    DllCall(MoveWindowToDesktopNumberProc, "Ptr", activeHwnd, "Int", desktopNumber, "Int")
    return DllCall(GoToDesktopNumberProc, "Int", desktopNumber, "Int")
}

MoveCurrentWindowToDesktop(num) {
    global MoveWindowToDesktopNumberProc

    if (!InitVDA() || !MoveWindowToDesktopNumberProc)
        return false

    ; Caller passes 1-based. DLL expects 0-based.
    correctDesktopNumber := num - 1
    if (correctDesktopNumber < 0)
        correctDesktopNumber := 0

    WinGet, activeHwnd, ID, A
    return DllCall(MoveWindowToDesktopNumberProc, "Ptr", activeHwnd, "Int", correctDesktopNumber, "Int")
}

MoveOrGotoDesktopNumber(num) {
    global MoveWindowToDesktopNumberProc, GoToDesktopNumberProc
    ; num is a zero-based desktop index produced by GoToPrevDesktop() or
    ; GoToNextDesktop(), so pass it directly to the zero-based DLL procedures.

    if (!InitVDA() || !GoToDesktopNumberProc)
        return false

    if (GetKeyState("LButton")) {
        if (!MoveWindowToDesktopNumberProc)
            return false
        WinGet, activeHwnd, ID, A
        DllCall(MoveWindowToDesktopNumberProc, "Ptr", activeHwnd, "Int", num, "Int")
        return DllCall(GoToDesktopNumberProc, "Int", num, "Int")
    } else {
        return DllCall(GoToDesktopNumberProc, "Int", num, "Int")
    }
}

getForemostWindowIdOnDesktop(n)
{
    global IsWindowOnDesktopNumberProc

    n := n - 1 ; Desktops start at 0, while in script it's 1

    ; winIDList contains a list of windows IDs ordered from the top to the bottom for each desktop.
    WinGet winIDList, list
    Loop, %winIDList% {
        windowID := winIDList%A_Index%
        windowIsOnDesktop := DllCall(IsWindowOnDesktopNumberProc, "Ptr", windowID, "UInt", n, "Int")
        ; Select the first (and foremost) window which is in the specified desktop.
        If (windowIsOnDesktop == 1) {
            Return windowID
        }
    }
}

findDesktopWindowIsOn(hwnd)
{
    global IsWindowOnDesktopNumberProc

    hwnd := hwnd + 0  ; force numeric
    Loop, % getTotalDesktops()
    {
        desktop := A_Index - 1
        ret := DllCall(IsWindowOnDesktopNumberProc, "Ptr", hwnd, "Int", desktop, "Int")
        if (ErrorLevel)
        {
            MsgBox % "DllCall failed. ErrorLevel=" ErrorLevel "`nA_LastError=" A_LastError
            return 0
        }
        if (ret)
            return A_Index
    }
    return 0
}

/* ;
*****************************
***** UTILITY FUNCTIONS *****
*****************************
*/
UpdateValidWindows() {
    global ValidWindows, MonCount

    currentMon := MWAGetMonitorMouseIsIn()
    WinGet, allWindows, List
    Loop, %allWindows%
    {
        hwndID := allWindows%A_Index%

        If (IsAltTabWindow(hwndID)) {
            WinGet, state, MinMax, ahk_id %hwndID%
            If (MonCount > 1 && state > -1) {
                currentMonHasActWin := IsWindowOnMonNum(hwndId, currentMon)
            }
            Else If (state > -1) {
                currentMonHasActWin := True
            }
            If (currentMonHasActWin && state > -1) {
                ValidWindows.push(hwndID)
            }
        }
    }
Return
}

FrameShadow(HGui) {
    DllCall("dwmapi\DwmIsCompositionEnabled","IntP",_ISENABLED) ; Get If DWM Manager is Enabled
    If !_ISENABLED ; If DWM is not enabled, Make Basic Shadow
        DllCall("SetClassLong","UInt",HGui,"Int",-26,"Int",DllCall("GetClassLong","UInt",HGui,"Int",-26)|0x20000)
    Else {
        VarSetCapacity(_MARGINS,16)
        NumPut(1,&_MARGINS,0,"UInt")
        NumPut(1,&_MARGINS,4,"UInt")
        NumPut(1,&_MARGINS,8,"UInt")
        NumPut(1,&_MARGINS,12,"UInt")
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", HGui, "UInt", 2, "Int*", 2, "UInt", 4)
        DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", HGui, "Ptr", &_MARGINS)
    }
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
_ClearTbcEverythingEditAdjustState() {
    global tbcEverythingAdjustCtrl
    global tbcEverythingAdjustCtrlClass
    global tbcEverythingAdjustCtrlHwnd
    global tbcEverythingAdjustHwnd
    global tbcEverythingAdjustId
    global tbcEverythingAdjustRequestedTick
    global tbcEverythingAdjustSourceTick

    tbcEverythingAdjustCtrl       := ""
    tbcEverythingAdjustCtrlClass  := ""
    tbcEverythingAdjustCtrlHwnd   := 0
    tbcEverythingAdjustHwnd       := 0
    tbcEverythingAdjustId         := 0
    tbcEverythingAdjustRequestedTick := 0
    tbcEverythingAdjustSourceTick := 0
}

; Queues a deferred Everything Edit1 column auto-fit request:
; capture or accept the current search-box focus context, stamp the latest
; typing tick, and let a short timer enforce a stronger typing-quiet pause
; before sending.
_RequestEverythingEditAdjust(sourceTick, capturedHwnd := 0, capturedCtrlNN := "", capturedCtrlHwnd := 0, capturedCtrlClass := "") {
    global k_tbcEverythingAdjustTypingQuietMs
    global tbcEverythingAdjustCtrl
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
    tbcEverythingAdjustCtrl       := targetCtrlNN
    tbcEverythingAdjustCtrlHwnd   := targetCtrlHwnd
    tbcEverythingAdjustCtrlClass  := targetCtrlClass
    tbcEverythingAdjustId += 1
    tbcEverythingAdjustRequestedTick := A_TickCount
    tbcEverythingAdjustSourceTick := sourceTick
    remainingQuietMs := GetRemainingQuietDelayMs(A_TimeIdlePhysical, k_tbcEverythingAdjustTypingQuietMs, False)
    SetTimer, FlushTbcEverythingEditAdjust, % -remainingQuietMs
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

    if (!sourceTick || tbcEverythingAdjustSourceTick = sourceTick)
        return false

    if (!_IsEverythingEditAdjustTrigger(hotkey))
        return false

    if !CaptureActiveFocusSnapshot(targetHwnd, targetCtrlNN, targetCtrlHwnd, targetCtrlClass, activeHwnd)
        return false

    if (targetCtrlNN != "Edit1")
        return false

    return _RequestEverythingEditAdjust(sourceTick, targetHwnd, targetCtrlNN, targetCtrlHwnd, targetCtrlClass)
}

; Everything Edit1 tbc-work validator:
; require the same active search box, the same request token, and when possible
; the same exact control HWND/class before the deferred Ctrl+NumpadAdd send runs.
_IsTbcEverythingEditAdjustStillValid(expectedId := 0) {
    global k_tbcEverythingAdjustMaxAgeMs
    global tbcEverythingAdjustCtrl
    global tbcEverythingAdjustCtrlClass
    global tbcEverythingAdjustCtrlHwnd
    global tbcEverythingAdjustHwnd
    global tbcEverythingAdjustId
    global tbcEverythingAdjustRequestedTick

    currentId := tbcEverythingAdjustId
    if (!expectedId)
        expectedId := currentId

    if !_IsDeferredWorkStillValid(tbcEverythingAdjustHwnd, tbcEverythingAdjustCtrl, expectedId, currentId, tbcEverythingAdjustRequestedTick, k_tbcEverythingAdjustMaxAgeMs)
        return false

    if (!tbcEverythingAdjustCtrlHwnd && tbcEverythingAdjustCtrlClass = "")
        return true

    if !TryCaptureCompleteFocusSnapshot(tbcEverythingAdjustHwnd, currentCtrlNN, currentCtrlHwnd, currentCtrlClass)
        return false

    if (tbcEverythingAdjustCtrl != "" && currentCtrlNN != tbcEverythingAdjustCtrl)
        return false

    if (tbcEverythingAdjustCtrlHwnd && currentCtrlHwnd != tbcEverythingAdjustCtrlHwnd)
        return false

    if (tbcEverythingAdjustCtrlClass != "" && currentCtrlClass != tbcEverythingAdjustCtrlClass)
        return false

    return true
}

; Shared guarded Ctrl+NumpadAdd wrapper:
; re-check any queued work token, optional focused control, optional typing-quiet
; gate, and then delegate to the low-level send helper only if the action is
; still safe for the original deferred target.
_SendCtrlNumpadAddIfStillValid(syncPassCount := 6, guardRequestId := 0, guardQuietMs := 0, guardHwnd := 0, guardCtrlNN := "", requiredTypingQuietMs := 0, expectedDeferredId := 0, currentDeferredId := 0, requestTick := 0, maxAgeMs := 0) {
    if ((guardHwnd || guardCtrlNN != "" || expectedDeferredId || requestTick || maxAgeMs)
     && !_IsDeferredWorkStillValid(guardHwnd, guardCtrlNN, expectedDeferredId, currentDeferredId, requestTick, maxAgeMs))
        return false

    if (requiredTypingQuietMs && !_IsDeferredTypingQuiet(requiredTypingQuietMs))
        return false

    return SendCtrlNumpadAdd(syncPassCount, guardRequestId, guardQuietMs, guardHwnd)
}

; Deferred Everything Edit1 Ctrl+NumpadAdd flush:
; wait for a stronger post-typing idle window, confirm the same search field
; still owns focus, then send the column auto-fit chord as late as possible.
FlushTbcEverythingEditAdjust:
    currentRequestId := tbcEverythingAdjustId
    if (!currentRequestId || !tbcEverythingAdjustHwnd)
        Return

    if (!_IsTbcEverythingEditAdjustStillValid(currentRequestId))
    {
        if (currentRequestId = tbcEverythingAdjustId)
            _ClearTbcEverythingEditAdjustState()
        Return
    }

    if (!_IsDeferredTypingQuiet(k_tbcEverythingAdjustTypingQuietMs))
    {
        ; Physical idle time has an exact deadline. The fixed fallback remains
        ; only for the separate StopAutoFix gate, which has no known end tick.
        remainingQuietMs := (A_TimeIdlePhysical < k_tbcEverythingAdjustTypingQuietMs)
                          ? GetRemainingQuietDelayMs(A_TimeIdlePhysical, k_tbcEverythingAdjustTypingQuietMs, False)
                          : k_tbcEverythingAdjustRetryMs
        SetTimer, FlushTbcEverythingEditAdjust, % -remainingQuietMs
        Return
    }

    if (_SendCtrlNumpadAddIfStillValid(6, 0, 0, tbcEverythingAdjustHwnd, tbcEverythingAdjustCtrl, k_tbcEverythingAdjustTypingQuietMs, currentRequestId, tbcEverythingAdjustId, tbcEverythingAdjustRequestedTick, k_tbcEverythingAdjustMaxAgeMs))
    {
        if (currentRequestId = tbcEverythingAdjustId)
            _ClearTbcEverythingEditAdjustState()
        Return
    }

    if (currentRequestId != tbcEverythingAdjustId)
        Return

    if (!_IsTbcEverythingEditAdjustStillValid(currentRequestId))
    {
        _ClearTbcEverythingEditAdjustState()
        Return
    }

    if (!_IsDeferredTypingQuiet(k_tbcEverythingAdjustTypingQuietMs)) {
        remainingQuietMs := (A_TimeIdlePhysical < k_tbcEverythingAdjustTypingQuietMs)
                          ? GetRemainingQuietDelayMs(A_TimeIdlePhysical, k_tbcEverythingAdjustTypingQuietMs, False)
                          : k_tbcEverythingAdjustRetryMs
        SetTimer, FlushTbcEverythingEditAdjust, % -remainingQuietMs
    }
Return

KeyTrack() {
    global StopAutoFix, TimeOfLastHotkeyTyped

    ListLines, Off

    activeHwnd := WinExist("A")
    WinGetClass, currClass, ahk_id %activeHwnd%
    If (InStr(currClass, "EVERYTHING", True)) {
        StopAutoFix := True
        ; Everything/Edit1 now follows the same shared deferred-work shape as
        ; the typing rewrite timers: qualify the key event, capture the exact
        ; current search-box identity once, queue the work, and let the timer
        ; handle the stronger quiet-gap revalidation before sending.
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

MouseTrack() {
    global MonCount, currentMon, previousMon, StopRecursion, TaskBarHeight
    static x, y, lastX, lastY, taskview
    static timeOfLastMove

    ListLines Off
    If (MonCount > 1 && !GetKeyState("LButton","P")) {
        currentMon := MWAGetMonitorMouseIsIn(TaskBarHeight)
        If (currentMon > 0 && previousMon != currentMon && previousMon > 0) {
            StopRecursion := True
            DetectHiddenWindows, Off

            escHwndID := FindTopMostWindow()
            WinActivate, ahk_id %escHwndID%
            GoSub, DrawRect
            ClearRect()
            Gui, GUIHighlighter: Hide

            previousMon := currentMon
            StopRecursion := False
        }
    }
    ListLines On
}

MouseIsOverTitleBarFast(xPos := "", yPos := "", excludeCaptions := True) {
    if !( GetKeyState("Wheeldown","P") || GetKeyState("Wheelup","P") || GetKeyState("LButton","P") || GetKeyState("RButton","P") || GetKeyState("MButton","P") )
        return False

    return (_GetTitleBarProbeState(xPos, yPos, excludeCaptions) == "caption")
}

MouseIsOverTitleBar(xPos := "", yPos := "", excludeCaptions := True) {
    CoordMode, Mouse, Screen
    If (xPos != "" && yPos != "")
        MouseGetPos, , , WindowUnderMouseID, ctrlnnUnderMouse
    Else
        MouseGetPos, xPos, yPos, WindowUnderMouseID, ctrlnnUnderMouse

    if (!WindowUnderMouseID || !IsAltTabWindow(WindowUnderMouseID))
        return False

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    if (   MouseIsOverTaskbar()
        || (mClass == "WorkerW")
        || (mClass == "ProgMan")
        || (mClass == "TaskListThumbnailWnd")
        || (mClass == "#32768")
        || (mClass == "MsoCommandBarPopup")
        || (mClass == "Net UI Tool Window"))
        return False

    static HTCAPTION     := 2   ; Non-client title bar.
    static HTCLOSE       := 20  ; Non-client close button.
    static HTHELP        := 21  ; Non-client help button.
    static HTMAXBUTTON   := 9   ; Non-client maximize button.
    static HTMINBUTTON   := 8   ; Non-client minimize button.
    static HTBOTTOM      := 15  ; Non-client bottom resize border.
    static HTBOTTOMLEFT  := 16 ; Non-client bottom-left resize corner.
    static HTBOTTOMRIGHT := 17 ; Non-client bottom-right resize corner.
    static HTLEFT        := 10  ; Non-client left resize border.
    static HTRIGHT       := 11  ; Non-client right resize border.
    static HTTOP         := 12  ; Non-client top resize border.
    static HTTOPLEFT     := 13  ; Non-client top-left resize corner.
    static HTTOPRIGHT    := 14  ; Non-client top-right resize corner.

    hitVal := IsPointOnCaption(xPos, yPos, WindowUnderMouseID)
    if (hitVal = HTCAPTION)
        return True

    if (   hitVal = HTMINBUTTON
        || hitVal = HTMAXBUTTON
        || hitVal = HTCLOSE
        || hitVal = HTHELP
        || hitVal = HTLEFT
        || hitVal = HTRIGHT
        || hitVal = HTTOP
        || hitVal = HTBOTTOM
        || hitVal = HTTOPLEFT
        || hitVal = HTTOPRIGHT
        || hitVal = HTBOTTOMLEFT
        || hitVal = HTBOTTOMRIGHT)
        return False

    titleBarState := _GetTitleBarProbeState(xPos, yPos, excludeCaptions, WindowUnderMouseID, ctrlnnUnderMouse, mClass)
    if (titleBarState == "caption")
        return True

    if (mClass == "CabinetWClass"
     && _IsPointInWindowTopStrip(xPos, yPos, WindowUnderMouseID, excludeCaptions)
     && _IsModernExplorerTopStripControl(ctrlnnUnderMouse))
        return True

    if (titleBarState != "other")
        return False

    return MouseIsOverTitleBarDeferred(xPos, yPos, excludeCaptions, WindowUnderMouseID, ctrlnnUnderMouse, mClass, True, 750)
}

_IsModernExplorerTopStripControl(ctrlNN := "") {
    if (ctrlNN == "")
        return False

    return (   InStr(ctrlNN, "Microsoft.UI.Content.DesktopChildSiteBridge", True)
            || InStr(ctrlNN, "Windows.UI.Composition.DesktopWindowContentBridge", True)
            || InStr(ctrlNN, "XamlExplorerHostIslandWindow", True))
}

_IsPointInWindowTopStrip(xPos, yPos, windowHwnd, excludeCaptions := True) {
    if (!windowHwnd)
        return False

    SysGet, SM_CXBORDER, 5
    SysGet, SM_CXMIN, 28
    SysGet, SM_CYMIN, 29
    SysGet, SM_CYSIZE, 31
    SysGet, SM_CYSIZEFRAME, 33

    if excludeCaptions
        widthOfCaptions := SM_CXBORDER + (45 * 3)
    else
        widthOfCaptions := 0

    WinGet, isMax, MinMax, ahk_id %windowHwnd%
    titlebarHeight := SM_CYMIN - SM_CYSIZEFRAME
    if (isMax == 1)
        titlebarHeight := SM_CYSIZE

    if !WinGetPosEx(windowHwnd, x, y, w, h)
        return False

    return ((yPos > y) && (yPos < (y + titlebarHeight)) && (xPos > x) && (xPos < (x + w - widthOfCaptions)))
}

_GetTitleBarProbeState(xPos := "", yPos := "", excludeCaptions := True, windowUnderMouseID := "", ctrlnnUnderMouse := "", mClass := "") {
    CoordMode, Mouse, Screen
    if (xPos != "" && yPos != "") {
        if (windowUnderMouseID == "" || ctrlnnUnderMouse == "")
            MouseGetPos, , , windowUnderMouseID, ctrlnnUnderMouse
    }
    else
        MouseGetPos, xPos, yPos, windowUnderMouseID, ctrlnnUnderMouse

    if (!windowUnderMouseID || !IsAltTabWindow(windowUnderMouseID))
        return ""

    if (mClass == "")
        WinGetClass, mClass, ahk_id %windowUnderMouseID%

    if (   MouseIsOverTaskbar()
        || (mClass == "WorkerW")
        || (mClass == "ProgMan")
        || (mClass == "TaskListThumbnailWnd")
        || (mClass == "#32768")
        || (mClass == "MsoCommandBarPopup")
        || (mClass == "Net UI Tool Window"))
        return ""

    SysGet, SM_CXBORDER, 5
    SysGet, SM_CYBORDER, 6
    SysGet, SM_CXMIN, 28
    SysGet, SM_CYMIN, 29
    SysGet, SM_CYSIZE, 31
    SysGet, SM_CYSIZEFRAME, 33

    if excludeCaptions
        widthOfCaptions := SM_CXBORDER + (45 * 3)
    else
        widthOfCaptions := 0

    WinGet, isMax, MinMax, ahk_id %windowUnderMouseID%
    titlebarHeight := SM_CYMIN - SM_CYSIZEFRAME
    if (isMax == 1)
        titlebarHeight := SM_CYSIZE

    WinGetPosEx(windowUnderMouseID, x, y, w, h)
    if !((yPos > y) && (yPos < (y + titlebarHeight)) && (xPos > x) && (xPos < (x + w - widthOfCaptions)))
        return ""

    if (ctrlnnUnderMouse == "DRAG_BAR_WINDOW_CLASS1")
        return "caption"

    nonClientZone := _GetMouseWindowNonClientZone(xPos, yPos, windowUnderMouseID)
    if (nonClientZone != "")
        return nonClientZone

    return "other"
}

WindowNeedsTitleBarUIA(windowHwnd, windowClass := "") {
    if (!windowHwnd)
        return False

    if (windowClass == "")
        WinGetClass, windowClass, ahk_id %windowHwnd%

    return (   IsChromiumBrowserWindow(windowHwnd, windowClass)
            || windowClass == "ApplicationFrameWindow"
            || windowClass == "CASCADIA_HOSTING_WINDOW_CLASS")
}

MouseIsOverTitleBarDeferred(xPos, yPos, excludeCaptions := True, windowUnderMouseID := "", ctrlnnUnderMouse := "", mClass := "", allowAnyClass := False, transactionTimeout := 250) {
    static cacheMs   := 75
    static c_lastKey := ""
    static lastTick  := 0
    static lastValue := False

    if (!windowUnderMouseID)
        return False

    if (mClass == "")
        WinGetClass, mClass, ahk_id %windowUnderMouseID%

    if (!allowAnyClass && !WindowNeedsTitleBarUIA(windowUnderMouseID, mClass))
        return False

    cacheKey := windowUnderMouseID "|" xPos "|" yPos "|" excludeCaptions "|" allowAnyClass "|" transactionTimeout
    if (cacheKey == c_lastKey && (A_TickCount - lastTick) <= cacheMs)
        return lastValue

    pt := SafeUIA_ElementFromPoint(xPos, yPos, "", transactionTimeout)
    ; This deferred title-bar path can still run frequently, so snapshot the
    ; few properties we need instead of issuing separate UIA COM reads.
    ptInfo := SafeUIA_GetElementSnapshot(pt, "className|controlType")
    ctype  := ptInfo.controlType
    ccname := ptInfo.className
    result := False

    if (mClass == "Chrome_WidgetWin_1" && ctype == 50033)
        result := (ccname == "FrameGrabHandle")
    else if ((ctype == 50037) || (ctype == 50026) || (ctype == 50033))
        result := True

    c_lastKey := cacheKey
    lastTick  := A_TickCount
    lastValue := result
    return result
}

IsPointOnCaption(x := "", y := "", hwnd := "") {
    CoordMode, Mouse, Screen

    ; Get mouse position / window if not provided
    if (x = "" || y = "" || hwnd = "") {
        MouseGetPos, x, y, hwnd
        if !hwnd
            return False
    }

    ; Always hit-test against the top-level window (Chrome needs this)
    hwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")  ; GA_ROOT = 2
    if !hwnd
        return False

    ; Pack screen coords into LPARAM (low word = x, high word = y)
    ; signed 16-bit is fine for normal monitor layouts
    x16 := x & 0xFFFF
    y16 := y & 0xFFFF
    lParam := x16 | (y16 << 16)

    WM_NCHITTEST := 0x84
    hit := DllCall("SendMessage"
        , "ptr",  hwnd
        , "uint", WM_NCHITTEST
        , "ptr",  0
        , "ptr",  lParam
        , "int")

    if (hit != "" && hit > 0)
        return hit
    else
        return 0
}

; Return a reliable plain-edge resize hit for live resize arming. For most
; windows this is just WM_NCHITTEST. For CabinetWClass on Windows 11, fall back
; to a tight outer-frame geometry test when the current cursor already shows a
; plain north/south or east/west resize shape.
_GetReliableResizeEdgeHit(x := "", y := "", hwnd := "") {
    static HTBOTTOM := 15  ; Non-client bottom resize border.
    static HTLEFT   := 10  ; Non-client left resize border.
    static HTRIGHT  := 11  ; Non-client right resize border.
    static HTTOP    := 12  ; Non-client top resize border.
    static IDC_SIZENS := 32645
    static IDC_SIZEWE := 32644
    static fallbackEdgeTolerance := 6

    if (x = "" || y = "" || hwnd = "") {
        MouseGetPos, x, y, hwnd
        if !hwnd
            return 0
    }

    hwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")  ; GA_ROOT = 2
    if !hwnd
        return 0

    hitVal := IsPointOnCaption(x, y, hwnd)
    if (hitVal = HTLEFT || hitVal = HTRIGHT || hitVal = HTTOP || hitVal = HTBOTTOM)
        return hitVal

    WinGetClass, windowClass, ahk_id %hwnd%
    if (windowClass != "CabinetWClass")
        return hitVal

    cursorInfoSize := (A_PtrSize = 8) ? 24 : 20
    VarSetCapacity(cursorInfo, cursorInfoSize, 0)
    NumPut(cursorInfoSize, cursorInfo, 0, "UInt")
    if !DllCall("user32\GetCursorInfo", "ptr", &cursorInfo)
        return hitVal

    hCursor := NumGet(cursorInfo, A_PtrSize, "ptr")
    if !hCursor
        return hitVal

    cursorNs := DllCall("user32\LoadCursor", "ptr", 0, "ptr", IDC_SIZENS, "ptr")
    cursorWe := DllCall("user32\LoadCursor", "ptr", 0, "ptr", IDC_SIZEWE, "ptr")
    if (hCursor != cursorNs && hCursor != cursorWe)
        return hitVal

    if !WinGetPosEx(hwnd, winX, winY, winW, winH, null, null)
        return hitVal

    winRightEdge  := winX + winW
    winBottomEdge := winY + winH
    distLeft      := Abs(x - winX)
    distRight     := Abs(x - winRightEdge)
    distTop       := Abs(y - winY)
    distBottom    := Abs(y - winBottomEdge)

    if (hCursor = cursorNs) {
        topWithinTolerance    := (distTop <= fallbackEdgeTolerance)
        bottomWithinTolerance := (distBottom <= fallbackEdgeTolerance)
        if (topWithinTolerance || bottomWithinTolerance)
            return (distTop <= distBottom) ? HTTOP : HTBOTTOM
    }

    if (hCursor = cursorWe) {
        leftWithinTolerance  := (distLeft <= fallbackEdgeTolerance)
        rightWithinTolerance := (distRight <= fallbackEdgeTolerance)
        if (leftWithinTolerance || rightWithinTolerance)
            return (distLeft <= distRight) ? HTLEFT : HTRIGHT
    }

    return hitVal
}

; Classify the native non-client mouse zone for the top-level window under the
; pointer so resize edges can take priority over titlebar heuristics.
_GetMouseWindowNonClientZone(x := "", y := "", hwnd := "") {
    static HTBOTTOM      := 15  ; Non-client bottom resize border.
    static HTBOTTOMLEFT  := 16  ; Non-client bottom-left resize corner.
    static HTBOTTOMRIGHT := 17  ; Non-client bottom-right resize corner.
    static HTCAPTION     := 2   ; Non-client title bar.
    static HTCLOSE       := 20  ; Non-client close button.
    static HTHELP        := 21  ; Non-client help button.
    static HTLEFT        := 10  ; Non-client left resize border.
    static HTMAXBUTTON   := 9   ; Non-client maximize button.
    static HTMINBUTTON   := 8   ; Non-client minimize button.
    static HTRIGHT       := 11  ; Non-client right resize border.
    static HTTOP         := 12  ; Non-client top resize border.
    static HTTOPLEFT     := 13  ; Non-client top-left resize corner.
    static HTTOPRIGHT    := 14  ; Non-client top-right resize corner.

    hitVal := _GetReliableResizeEdgeHit(x, y, hwnd)
    if (hitVal = HTCAPTION)
        return "caption"

    if (hitVal = HTMINBUTTON || hitVal = HTMAXBUTTON || hitVal = HTCLOSE || hitVal = HTHELP)
        return "caption_button"

    if (   hitVal = HTLEFT
        || hitVal = HTRIGHT
        || hitVal = HTTOP
        || hitVal = HTBOTTOM
        || hitVal = HTTOPLEFT
        || hitVal = HTTOPRIGHT
        || hitVal = HTBOTTOMLEFT
        || hitVal = HTBOTTOMRIGHT)
        return "resize_edge"

    return "other"
}

; Return the fixed outer edge a live-resize target should preserve while the
; dragged window drives its shared edge. Peer targets preserve the far edge on
; the same side as the dragged window, while opposite targets preserve the far
; edge away from the dragged window.
_GetLiveResizeSyncFixedEdge(targetX, targetY, targetW, targetH, edgeHit, targetRole := "opposite") {
    static HTBOTTOM := 15  ; Non-client bottom resize border.
    static HTLEFT   := 10  ; Non-client left resize border.
    static HTRIGHT  := 11  ; Non-client right resize border.
    static HTTOP    := 12  ; Non-client top resize border.

    targetRightEdge  := targetX + targetW
    targetBottomEdge := targetY + targetH

    if (targetRole = "peer") {
        if (edgeHit = HTLEFT)
            return targetRightEdge
        else if (edgeHit = HTRIGHT)
            return targetX
        else if (edgeHit = HTTOP)
            return targetBottomEdge
        else if (edgeHit = HTBOTTOM)
            return targetY
    }
    else {
        if (edgeHit = HTLEFT)
            return targetX
        else if (edgeHit = HTRIGHT)
            return targetRightEdge
        else if (edgeHit = HTTOP)
            return targetY
        else if (edgeHit = HTBOTTOM)
            return targetBottomEdge
    }

    return ""
}

; Return true when the window already spans the monitor work area from top to
; bottom within a strict 3px monitor-edge dock tolerance, so vertical live
; cluster resize can suppress it while still allowing horizontal cluster
; behavior.
_IsFullMonitorHeightWindow(hwndID, monitorNum) {
    strictDockEdgeTolerance := 3

    if (!hwndID || monitorNum < 1)
        return false

    SysGet, monInfo, MonitorWorkArea, %monitorNum%
    if !WinGetPosEx(hwndID, winX, winY, winW, winH, null, null)
        return false

    winBottomEdge := winY + winH
    return (   Abs(winY - monInfoTop) <= strictDockEdgeTolerance
            && Abs(winBottomEdge - monInfoBottom) <= strictDockEdgeTolerance)
}

; Return true when the window already looks like a left- or right-side
; 3-edge dock during live-resize arm time: full monitor height plus the named
; outer monitor edge. This is the shape that should make the opposite pane act
; like a side follower instead of a split pane.
_IsLiveResizeThreeEdgeDockedOnSide(hwndID, monitorNum, dockSide, refX := "", refY := "", refW := "", refH := "") {
    liveResizeThreeEdgeDockTolerance := 10

    if (!hwndID || monitorNum < 1)
        return false

    if (refX = "" || refY = "" || refW = "" || refH = "") {
        if !WinGetPosEx(hwndID, refX, refY, refW, refH, null, null)
            return false
    }

    SysGet, monInfo, MonitorWorkArea, %monitorNum%
    refRightEdge  := refX + refW
    refBottomEdge := refY + refH

    if (   Abs(refY - monInfoTop) > liveResizeThreeEdgeDockTolerance
        || Abs(refBottomEdge - monInfoBottom) > liveResizeThreeEdgeDockTolerance)
        return false

    if (dockSide = "left")
        return (Abs(refX - monInfoLeft) <= liveResizeThreeEdgeDockTolerance)
    if (dockSide = "right")
        return (Abs(refRightEdge - monInfoRight) <= liveResizeThreeEdgeDockTolerance)

    return false
}

; Decide whether two windows belong to the same live-resize peer group for the
; dragged edge. Horizontal drags group vertically contiguous windows whose left
; and right edges already match closely; vertical drags do the mirror image for
; top and bottom edges.
_IsLiveResizePeerMatch(anchorX, anchorY, anchorW, anchorH, candidateX, candidateY, candidateW, candidateH, edgeHit, sharedEdgeTolerance := 25, peerGapTolerance := 100) {
    static HTBOTTOM := 15  ; Non-client bottom resize border.
    static HTLEFT   := 10  ; Non-client left resize border.
    static HTRIGHT  := 11  ; Non-client right resize border.
    static HTTOP    := 12  ; Non-client top resize border.

    anchorRightEdge     := anchorX + anchorW
    anchorBottomEdge    := anchorY + anchorH
    candidateRightEdge  := candidateX + candidateW
    candidateBottomEdge := candidateY + candidateH

    if (edgeHit = HTLEFT || edgeHit = HTRIGHT) {
        if (Abs(anchorX - candidateX) > sharedEdgeTolerance)
            return false
        if (Abs(anchorRightEdge - candidateRightEdge) > sharedEdgeTolerance)
            return false

        verticalSeparation := Max(anchorY, candidateY) - Min(anchorBottomEdge, candidateBottomEdge)
        return (verticalSeparation <= peerGapTolerance)
    }

    if (edgeHit = HTTOP || edgeHit = HTBOTTOM) {
        if (Abs(anchorY - candidateY) > sharedEdgeTolerance)
            return false
        if (Abs(anchorBottomEdge - candidateBottomEdge) > sharedEdgeTolerance)
            return false

        horizontalSeparation := Max(anchorX, candidateX) - Min(anchorRightEdge, candidateRightEdge)
        return (horizontalSeparation <= peerGapTolerance)
    }

    return false
}

; Build the same-side live-resize peer group for the dragged window by walking
; outward through windows that already occupy the same column or row geometry.
; This grouping is geometry-based rather than z-order-based so stacked peers
; such as windows #1 and #2 can resize together while also driving the opposite
; partner window #3.
_BuildLiveResizePeerHwndIDs(draggedHwndID, monitorNum, edgeHit, sharedEdgeTolerance := 25, peerGapTolerance := 100) {
    SysGet, MonCount, MonitorCount
    DetectHiddenWindows, Off

    peerHwndIDs := []
    peerHwndIDs.Push(draggedHwndID)
    peerHwndMap := {}
    peerHwndMap[draggedHwndID] := true

    WinGet, winList, List,
    queueIndex := 1
    while (queueIndex <= peerHwndIDs.MaxIndex()) {
        anchorHwndID := peerHwndIDs[queueIndex]
        queueIndex++

        if !WinGetPosEx(anchorHwndID, anchorX, anchorY, anchorW, anchorH, null, null)
            continue

        Loop, %winList%
        {
            candidateHwndID := winList%A_Index%

            if (!candidateHwndID || candidateHwndID = anchorHwndID || peerHwndMap.HasKey(candidateHwndID))
                continue

            if !IsAltTabWindow(candidateHwndID)
                continue

            if (IsAlwaysOnTop(candidateHwndID))
                continue

            WinGet, mmState, MinMax, ahk_id %candidateHwndID%
            if (mmState <= -1)
                continue

            if (MonCount > 1 && !IsWindowOnMonNum(candidateHwndID, monitorNum))
                continue

            if (   (edgeHit = HTTOP || edgeHit = HTBOTTOM)
                && _IsFullMonitorHeightWindow(candidateHwndID, monitorNum))
                continue

            if !WinGetPosEx(candidateHwndID, candidateX, candidateY, candidateW, candidateH, null, null)
                continue

            if !_IsLiveResizePeerMatch(anchorX, anchorY, anchorW, anchorH, candidateX, candidateY, candidateW, candidateH, edgeHit, sharedEdgeTolerance, peerGapTolerance)
                continue

            if !_HasVisibleExposedAreaWindow(candidateHwndID, candidateX, candidateY, candidateW, candidateH)
                continue

            peerHwndMap[candidateHwndID] := true
            peerHwndIDs.Push(candidateHwndID)
        }
    }

    return peerHwndIDs
}

; Apply the live-resize partner updates, preserving partial-axis WinMove calls
; when shared-edge sync is only supposed to affect width or height.
_ApplyLiveResizeSyncTbcMoves(tbcMoves) {
    if (!IsObject(tbcMoves) || !tbcMoves.MaxIndex())
        return false

    hasAxisSpecificMove := false
    for tbcIndex, tbcMove in tbcMoves {
        if (tbcMove.axis = "horizontal" || tbcMove.axis = "vertical") {
            hasAxisSpecificMove := true
            break
        }
    }

    ; Horizontal shared-edge sync must not touch height, and vertical sync must
    ; not touch width. Move-only horizontal updates are stricter still: they
    ; must not pass width at all. If any tbc move is axis-specific, apply
    ; the whole set with WinMove so blank parameters preserve the untouched axis
    ; exactly.
    if (hasAxisSpecificMove) {
        for tbcIndex, tbcMove in tbcMoves {
            tbcAxis   := tbcMove.axis
            tbcHwndID := tbcMove.hwnd

            if (tbcAxis = "horizontal") {
                tbcX := tbcMove.x
                if (tbcMove.moveOnly) {
                    WinMove, ahk_id %tbcHwndID%, , %tbcX%
                    continue
                }

                tbcW := tbcMove.w
                WinMove, ahk_id %tbcHwndID%, , %tbcX%, , %tbcW%
                continue
            }

            if (tbcAxis = "vertical") {
                tbcH := tbcMove.h
                tbcY := tbcMove.y
                WinMove, ahk_id %tbcHwndID%, , , %tbcY%, , %tbcH%
                continue
            }

            tbcH := tbcMove.h
            tbcW := tbcMove.w
            tbcX := tbcMove.x
            tbcY := tbcMove.y
            WinMove, ahk_id %tbcHwndID%, , %tbcX%, %tbcY%, %tbcW%, %tbcH%
        }

        return true
    }

    static SWP_NOACTIVATE   := 0x0010
    static SWP_NOOWNERZORDER := 0x0200
    static SWP_NOZORDER     := 0x0004

    swpFlags := SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOZORDER
    hdwp := DllCall("BeginDeferWindowPos", "Int", tbcMoves.MaxIndex(), "Ptr")
    if (hdwp) {
        for tbcIndex, tbcMove in tbcMoves {
            hdwp := DllCall("DeferWindowPos"
                , "Ptr", hdwp
                , "Ptr", tbcMove.hwnd
                , "Ptr", 0
                , "Int", tbcMove.x
                , "Int", tbcMove.y
                , "Int", tbcMove.w
                , "Int", tbcMove.h
                , "UInt", swpFlags
                , "Ptr")
            if (!hdwp)
                break
        }

        if (hdwp && DllCall("EndDeferWindowPos", "Ptr", hdwp))
            return true
    }

    for tbcIndex, tbcMove in tbcMoves {
        tbcHwndID := tbcMove.hwnd
        tbcH      := tbcMove.h
        tbcW      := tbcMove.w
        tbcX      := tbcMove.x
        tbcY      := tbcMove.y
        WinMove, ahk_id %tbcHwndID%, , %tbcX%, %tbcY%, %tbcW%, %tbcH%
    }

    return true
}

; During live drag, drive lightweight overlay cards for any follower window that
; was successfully made fully transparent, and fall back to real WinMove only for followers that
; could not be converted into an overlay-backed preview surface.
_ApplyLButtonResizeSyncPreviewMoves(tbcMoves) {
    if (!IsObject(tbcMoves) || !tbcMoves.MaxIndex())
        return false

    realTbcMoves := []
    for tbcIndex, tbcMove in tbcMoves {
        partnerInfo   := tbcMove.partnerInfo
        ghostCardInfo := IsObject(partnerInfo) ? partnerInfo.ghostCardInfo : ""
        tbcHwndID     := tbcMove.hwnd

        if !IsObject(ghostCardInfo) {
            realTbcMoves.Push(tbcMove)
            continue
        }

        ; The move plan stores real-window WinMove coordinates, but the gray
        ; follower card is later moved as a GUI that should visually match the
        ; outer frame reported by WinGetPosEx(). Example: if WinMove needs
        ; x=92/w=516 for a window whose visible frame is really x=100/w=500,
        ; feeding 92/516 straight into the overlay would make the gray card
        ; hang 8 px across the shared edge. Reverse that offset math here so
        ; the overlay GUI is moved in visible-frame coordinates, while the real
        ; follower window still keeps the original WinMove rect.
        if !WinGetPosEx(tbcHwndID, currentX, currentY, currentW, currentH, partnerOffsetX, partnerOffsetY) {
            _ReleaseLButtonResizeSyncFollower(partnerInfo)
            realTbcMoves.Push(tbcMove)
            continue
        }

        targetX := ghostCardInfo.x
        targetY := ghostCardInfo.y
        targetW := ghostCardInfo.w
        targetH := ghostCardInfo.h

        if (tbcMove.axis = "horizontal") {
            targetX := tbcMove.x - partnerOffsetX
            if (!tbcMove.moveOnly)
                targetW := tbcMove.w - 2*Abs(partnerOffsetX)
        }
        else if (tbcMove.axis = "vertical") {
            targetY := tbcMove.y
            targetH := tbcMove.h - 2*Abs(partnerOffsetY) - 1
        }
        else {
            targetH := tbcMove.h - 2*Abs(partnerOffsetY) - 1
            targetW := tbcMove.w - 2*Abs(partnerOffsetX)
            targetX := tbcMove.x - partnerOffsetX
            targetY := tbcMove.y
        }

        if (_UpdateLButtonResizeSyncGhostCardRect(ghostCardInfo, targetX, targetY, targetW, targetH))
            continue

        _ReleaseLButtonResizeSyncFollower(partnerInfo)
        realTbcMoves.Push(tbcMove)
    }

    if (!realTbcMoves.MaxIndex())
        return true

    return _ApplyLiveResizeSyncTbcMoves(realTbcMoves)
}

; Build one live-resize move plan from the dragged window's current geometry so
; both the timer-driven updates and the final LButton-up safety net can enforce
; the same shared-edge flush rules.
_BuildLButtonResizeSyncMovePlan(draggedX, draggedY, draggedW, draggedH) {
    global lButtonResizeSyncHit
    global lButtonResizeSyncPartners

    static HTBOTTOM := 15  ; Non-client bottom resize border.
    static HTLEFT   := 10  ; Non-client left resize border.
    static HTRIGHT  := 11  ; Non-client right resize border.
    static HTTOP    := 12  ; Non-client top resize border.

    draggedRightEdge  := draggedX + draggedW
    draggedBottomEdge := draggedY + draggedH
    didResizeAny      := false
    tbcMoves      := []
    validPartners     := []

    for partnerIndex, partnerInfo in lButtonResizeSyncPartners {
        partnerHwndID      := partnerInfo.hwnd
        partnerFixedEdge   := partnerInfo.fixedEdge
        partnerMoveOnly    := partnerInfo.useMoveOnly
        partnerRole        := partnerInfo.role
        usedMoveOnlyPartnerHandling := false
        ; Only issue WinMove when the target rect actually changed. This avoids
        ; redundant no-op resizes, which is especially important for heavier
        ; windows like Explorer that repaint more expensively.
        shouldMovePartner  := false

        if (!partnerHwndID || !WinExist("ahk_id " . partnerHwndID))
            continue

        ; partnerOffsetX / partnerOffsetY convert between the visual outer edges
        ; we reason about and the window rect coordinates WinMove expects.
        if !WinGetPosEx(partnerHwndID, partnerX, partnerY, partnerW, partnerH, partnerOffsetX, partnerOffsetY)
            continue

        if (lButtonResizeSyncHit = HTRIGHT) {
            if (partnerRole = "peer") {
                ; Same-side peers keep their far-left edge fixed and directly
                ; mirror the dragged right edge so the whole column stays the
                ; same width during live edge resizing.
                targetLeftEdge  := partnerFixedEdge
                targetRightEdge := draggedRightEdge
            }
            else if (partnerMoveOnly) {
                ; Full-height horizontal drags that started without a docked far
                ; edge only slide opposite-side followers whose own far edge is
                ; still floating. Opposite-side panes that are actually
                ; anchored on their far edge resize instead.
                targetMoveX       := draggedRightEdge + partnerOffsetX
                usedMoveOnlyPartnerHandling := true
                shouldMovePartner := (partnerX != targetMoveX)
                if (shouldMovePartner)
                    tbcMoves.Push({ axis: "horizontal", hwnd: partnerHwndID, moveOnly: true, partnerInfo: partnerInfo, x: targetMoveX })
            }
            else {
                ; Opposite-side partners keep their far-right edge fixed and
                ; slide only the shared left edge so it stays flush with the
                ; dragged window's right edge.
                targetLeftEdge  := draggedRightEdge
                targetRightEdge := partnerFixedEdge
            }

            if (!usedMoveOnlyPartnerHandling) {
                targetOuterWidth  := targetRightEdge - targetLeftEdge
                if (targetOuterWidth <= 0)
                    continue

                targetMoveX       := targetLeftEdge + partnerOffsetX
                targetMoveWidth   := targetOuterWidth + 2*Abs(partnerOffsetX)
                shouldMovePartner := (partnerX != targetMoveX || partnerW != targetMoveWidth)
                if (shouldMovePartner)
                    tbcMoves.Push({ axis: "horizontal", hwnd: partnerHwndID, partnerInfo: partnerInfo, w: targetMoveWidth, x: targetMoveX })
            }
        }
        else if (lButtonResizeSyncHit = HTLEFT) {
            if (partnerRole = "peer") {
                ; Same-side peers keep their far-right edge fixed and directly
                ; mirror the dragged left edge so the whole column stays the
                ; same width during live edge resizing.
                targetLeftEdge  := draggedX
                targetRightEdge := partnerFixedEdge
            }
            else if (partnerMoveOnly) {
                ; Mirror the right-edge rule above for opposite-side followers
                ; whose own far edge is floating: preserve width and shift the
                ; whole window so its right edge stays flush to the dragged
                ; left edge.
                partnerOuterWidth := partnerW - 2*Abs(partnerOffsetX)
                if (partnerOuterWidth <= 0)
                    continue

                targetLeftEdge    := draggedX - partnerOuterWidth
                targetMoveX       := targetLeftEdge + partnerOffsetX
                usedMoveOnlyPartnerHandling := true
                shouldMovePartner := (partnerX != targetMoveX)
                if (shouldMovePartner)
                    tbcMoves.Push({ axis: "horizontal", hwnd: partnerHwndID, moveOnly: true, partnerInfo: partnerInfo, x: targetMoveX })
            }
            else {
                ; Opposite-side partners keep their far-left edge fixed and
                ; slide only the shared right edge so it stays flush with the
                ; dragged window's left edge.
                targetLeftEdge  := partnerFixedEdge
                targetRightEdge := draggedX
            }

            if (!usedMoveOnlyPartnerHandling) {
                targetOuterWidth  := targetRightEdge - targetLeftEdge
                if (targetOuterWidth <= 0)
                    continue

                targetMoveX       := targetLeftEdge + partnerOffsetX
                targetMoveWidth   := targetOuterWidth + 2*Abs(partnerOffsetX)
                shouldMovePartner := (partnerX != targetMoveX || partnerW != targetMoveWidth)
                if (shouldMovePartner)
                    tbcMoves.Push({ axis: "horizontal", hwnd: partnerHwndID, partnerInfo: partnerInfo, w: targetMoveWidth, x: targetMoveX })
            }
        }
        else if (lButtonResizeSyncHit = HTBOTTOM) {
            if (partnerRole = "peer") {
                ; Same-side peers keep their far-top edge fixed and directly
                ; mirror the dragged bottom edge so the whole row stays the
                ; same height during live edge resizing.
                targetTopEdge    := partnerFixedEdge
                targetBottomEdge := draggedBottomEdge
            }
            else {
                ; Opposite-side partners keep their far-bottom edge fixed and
                ; move only the shared top edge so it stays flush with the
                ; dragged window's bottom edge.
                targetTopEdge    := draggedBottomEdge
                targetBottomEdge := partnerFixedEdge
            }

            targetOuterHeight := targetBottomEdge - targetTopEdge
            if (targetOuterHeight <= 0)
                continue

            targetMoveY       := targetTopEdge
            ; The script's vertical offset conversion needs the established +1
            ; pixel compensation. Without it, the visual bottom edge commonly
            ; lands one pixel short after the frame-offset math is applied.
            targetMoveHeight  := targetOuterHeight + 2*Abs(partnerOffsetY) + 1
            shouldMovePartner := (partnerY != targetMoveY || partnerH != targetMoveHeight)
            if (shouldMovePartner)
                tbcMoves.Push({ axis: "vertical", h: targetMoveHeight, hwnd: partnerHwndID, partnerInfo: partnerInfo, y: targetMoveY })
        }
        else if (lButtonResizeSyncHit = HTTOP) {
            if (partnerRole = "peer") {
                ; Same-side peers keep their far-bottom edge fixed and directly
                ; mirror the dragged top edge so the whole row stays the same
                ; height during live edge resizing.
                targetTopEdge    := draggedY
                targetBottomEdge := partnerFixedEdge
            }
            else {
                ; Opposite-side partners keep their far-top edge fixed and move
                ; only the shared bottom edge so it stays flush with the dragged
                ; window's top edge.
                targetTopEdge    := partnerFixedEdge
                targetBottomEdge := draggedY
            }

            targetOuterHeight := targetBottomEdge - targetTopEdge
            if (targetOuterHeight <= 0)
                continue

            targetMoveY       := targetTopEdge
            ; As above, preserve the script's vertical offset conversion pattern,
            ; including the +1 pixel bottom-edge compensation.
            targetMoveHeight  := targetOuterHeight + 2*Abs(partnerOffsetY) + 1
            shouldMovePartner := (partnerY != targetMoveY || partnerH != targetMoveHeight)
            if (shouldMovePartner)
                tbcMoves.Push({ axis: "vertical", h: targetMoveHeight, hwnd: partnerHwndID, partnerInfo: partnerInfo, y: targetMoveY })
        }
        else
            return false

        if (shouldMovePartner)
            didResizeAny := true

        validPartners.Push(partnerInfo)
    }

    return { didResizeAny: didResizeAny, tbcMoves: tbcMoves, validPartners: validPartners }
}

; Run one last shared-edge sync after LButton-up so any partner that
; lagged or overshot during the native drag animation is snapped flush before
; the temporary resize state is torn down.
_FinalizeLButtonResizeSync() {
    global lButtonResizeSyncActive
    global lButtonResizeSyncDraggedHwnd
    global lButtonResizeSyncPartners

    if (!lButtonResizeSyncActive || !IsObject(lButtonResizeSyncPartners) || !lButtonResizeSyncPartners.MaxIndex())
        return false

    if (!WinExist("ahk_id " . lButtonResizeSyncDraggedHwnd))
        return false

    if !WinGetPosEx(lButtonResizeSyncDraggedHwnd, draggedX, draggedY, draggedW, draggedH, null, null)
        return false

    movePlan := _BuildLButtonResizeSyncMovePlan(draggedX, draggedY, draggedW, draggedH)
    if !IsObject(movePlan)
        return false

    if (movePlan.tbcMoves.MaxIndex())
        _ApplyLiveResizeSyncTbcMoves(movePlan.tbcMoves)

    _ReleaseLButtonResizeSyncDroppedFollowers(lButtonResizeSyncPartners, movePlan.validPartners)
    lButtonResizeSyncPartners := movePlan.validPartners
    return movePlan.didResizeAny
}

; Build one opaque preview card for a synced follower window so the live drag
; can animate a cheap surface instead of continuously resizing the real window.
_CreateLButtonResizeSyncGhostCard(hwndID, ghostX, ghostY, ghostW, ghostH) {
    global lButtonResizeGhostSeq

    if (!hwndID || ghostW <= 0 || ghostH <= 0)
        return false

    lButtonResizeGhostSeq++
    resizeGhostGuiName  := "LButtonResizeSyncOverlay" . lButtonResizeGhostSeq
    iconSpec            := _GetLButtonResizeSyncGhostCardSpec(hwndID)
    iconSize            := _GetLButtonResizeSyncGhostCardIconSize(ghostW, ghostH)
    iconX               := Floor((ghostW - iconSize) / 2)
    iconY               := Floor((ghostH - iconSize) / 2)

    followerGhostHwnd := 0
    ghostIconHwnd     := 0

    ; Keep the follower card HWND isolated from the global Alt+Tab ghost HWND.
    Gui, %resizeGhostGuiName%: New, +AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +HwndfollowerGhostHwnd
    Gui, %resizeGhostGuiName%: Margin, 0, 0
    Gui, %resizeGhostGuiName%: Color, 4A4A4A

    if (IsObject(iconSpec) && iconSpec.path != "") {
        iconControlOptions := "hwndghostIconHwnd x" . iconX . " y" . iconY . " w" . iconSize . " h" . iconSize
        if (iconSpec.options != "")
            iconControlOptions .= " " . iconSpec.options
        Gui, %resizeGhostGuiName%: Add, Picture, %iconControlOptions%, % iconSpec.path
    }

    Gui, %resizeGhostGuiName%: Show, NA x%ghostX% y%ghostY% w%ghostW% h%ghostH%
    return { guiName: resizeGhostGuiName, hwnd: followerGhostHwnd, iconHwnd: ghostIconHwnd, restoreTransparency: "", w: ghostW, x: ghostX, y: ghostY, h: ghostH }
}

; Read one follower window's icon source so the ghost card can still identify
; the visually removed app even while the real window stays transparent underneath it.
_GetLButtonResizeSyncGhostCardSpec(hwndID) {
    if (!hwndID)
        return { options: "Icon3", path: A_WinDir . "\System32\SHELL32.dll" }

    WinGet, processPath, ProcessPath, ahk_id %hwndID%
    if (processPath != "")
        return { options: "", path: processPath }

    return { options: "Icon3", path: A_WinDir . "\System32\SHELL32.dll" }
}

; Size the follower ghost icon conservatively so small panes still get an
; identifiable app glyph without the placeholder card feeling crowded.
_GetLButtonResizeSyncGhostCardIconSize(ghostW, ghostH) {
    shortestEdge := Min(ghostW, ghostH)
    return Max(32, Min(72, Floor(shortestEdge / 5)))
}

; Make each synced follower window fully transparent and swap in an overlay
; placeholder so the live timer no longer forces heavy apps to repaint on every drag tick.
_PrepareLButtonResizeSyncGhostCards(ByRef resizeTargets) {
    if !IsObject(resizeTargets)
        return false

    preparedAnyFollower := false
    for resizeTargetIndex, resizeTargetInfo in resizeTargets {
        followerHwndID := resizeTargetInfo.hwnd
        if (!followerHwndID || !WinExist("ahk_id " . followerHwndID))
            continue

        if !WinGetPosEx(followerHwndID, followerX, followerY, followerW, followerH, null, null)
            continue

        ghostCardInfo := _CreateLButtonResizeSyncGhostCard(followerHwndID, followerX, followerY, followerW, followerH)
        if !IsObject(ghostCardInfo)
            continue

        WinGet, followerTransparency, Transparent, ahk_id %followerHwndID%
        ghostCardInfo.restoreTransparency := followerTransparency
        WinSet, Transparent, 0, ahk_id %followerHwndID%

        resizeTargetInfo.ghostCardInfo := ghostCardInfo
        resizeTargets[resizeTargetIndex] := resizeTargetInfo
        preparedAnyFollower := true
    }

    return preparedAnyFollower
}

; Restore any follower that fell out of the active sync set mid-drag so it does
; not remain transparent once the geometry no longer qualifies for live tracking.
_ReleaseLButtonResizeSyncDroppedFollowers(previousPartners, currentPartners) {
    if !IsObject(previousPartners)
        return false

    currentPartnerMap := {}
    if (IsObject(currentPartners)) {
        for currentPartnerIndex, currentPartnerInfo in currentPartners {
            if (currentPartnerInfo.hwnd)
                currentPartnerMap[currentPartnerInfo.hwnd] := true
        }
    }

    releasedAnyFollower := false
    for previousPartnerIndex, previousPartnerInfo in previousPartners {
        if (previousPartnerInfo.hwnd && currentPartnerMap.HasKey(previousPartnerInfo.hwnd))
            continue

        if (_ReleaseLButtonResizeSyncFollower(previousPartnerInfo)) {
            previousPartners[previousPartnerIndex] := previousPartnerInfo
            releasedAnyFollower := true
        }
    }

    return releasedAnyFollower
}

; Restore one follower window's previous transparency state and destroy the
; matching overlay card so cleanup can run both on button-up and on mid-drag drop-out.
_ReleaseLButtonResizeSyncFollower(ByRef partnerInfo) {
    if !IsObject(partnerInfo)
        return false

    ghostCardInfo := partnerInfo.ghostCardInfo
    if !IsObject(ghostCardInfo)
        return false

    resizeGhostGuiName := ghostCardInfo.guiName
    if (resizeGhostGuiName != "")
        Gui, %resizeGhostGuiName%: Destroy

    followerHwndID := partnerInfo.hwnd
    if (followerHwndID && WinExist("ahk_id " . followerHwndID)) {
        if (ghostCardInfo.restoreTransparency = "")
            WinSet, Transparent, Off, ahk_id %followerHwndID%
        else
            WinSet, Transparent, % ghostCardInfo.restoreTransparency, ahk_id %followerHwndID%
        WinSet, Redraw,, ahk_id %followerHwndID%
    }

    partnerInfo.ghostCardInfo := ""
    return true
}

; Restore every follower window still participating in the live resize cohort.
_ReleaseLButtonResizeSyncGhostCards(ByRef resizeTargets) {
    if !IsObject(resizeTargets)
        return false

    releasedAnyFollower := false
    for resizeTargetIndex, resizeTargetInfo in resizeTargets {
        if (_ReleaseLButtonResizeSyncFollower(resizeTargetInfo)) {
            resizeTargets[resizeTargetIndex] := resizeTargetInfo
            releasedAnyFollower := true
        }
    }

    return releasedAnyFollower
}

; Resize and reposition one follower overlay card while keeping its centered app
; icon aligned to the current preview rect.
_UpdateLButtonResizeSyncGhostCardRect(ByRef ghostCardInfo, ghostX, ghostY, ghostW, ghostH) {
    if !IsObject(ghostCardInfo)
        return false

    followerGhostHwnd := ghostCardInfo.hwnd
    if (!followerGhostHwnd || !WinExist("ahk_id " . followerGhostHwnd) || ghostW <= 0 || ghostH <= 0)
        return false

    WinMove, ahk_id %followerGhostHwnd%, , %ghostX%, %ghostY%, %ghostW%, %ghostH%

    if (ghostCardInfo.iconHwnd && DllCall("IsWindow", "ptr", ghostCardInfo.iconHwnd)) {
        iconSize := _GetLButtonResizeSyncGhostCardIconSize(ghostW, ghostH)
        iconX := Floor((ghostW - iconSize) / 2)
        iconY := Floor((ghostH - iconSize) / 2)
        DllCall("MoveWindow", "ptr", ghostCardInfo.iconHwnd, "int", iconX, "int", iconY, "int", iconSize, "int", iconSize, "int", True)
    }

    ghostCardInfo.x := ghostX
    ghostCardInfo.y := ghostY
    ghostCardInfo.w := ghostW
    ghostCardInfo.h := ghostH
    return true
}

; Capture the original topmost state for the dragged window and every active
; live-resize target, then temporarily force them into the topmost band until
; the resize ends. The actively dragged window is promoted last so it stays
; above the rest of the temporary resize cohort.
_CaptureLiveResizeSyncTopmostStates(draggedHwndID, resizeTargets) {
    topmostStates := {}

    if (draggedHwndID && WinExist("ahk_id " . draggedHwndID))
        topmostStates[draggedHwndID] := IsAlwaysOnTop(draggedHwndID)

    if (IsObject(resizeTargets)) {
        for resizeTargetIndex, resizeTargetInfo in resizeTargets
            _TrackLiveResizeSyncTopmostState(resizeTargetInfo.hwnd, topmostStates)
    }

    if (draggedHwndID && WinExist("ahk_id " . draggedHwndID))
        WinSet, AlwaysOnTop, On, ahk_id %draggedHwndID%

    return topmostStates
}

; Restore each live-resize window to the exact topmost state it had before the
; resize began so temporary z-order promotion does not leak past LButton-up.
; Restore the actively dragged window last so it remains highest in z-order
; within the former resize cohort after the temporary topmost band is removed.
_RestoreLiveResizeSyncTopmostStates(topmostStates, draggedHwndID := 0) {
    if !IsObject(topmostStates)
        return false

    restoredAnyWindow := false
    for hwndID, startedAlwaysOnTop in topmostStates {
        if (draggedHwndID && hwndID = draggedHwndID)
            continue

        if (!hwndID || !WinExist("ahk_id " . hwndID))
            continue

        if (startedAlwaysOnTop)
            WinSet, AlwaysOnTop, On, ahk_id %hwndID%
        else
            WinSet, AlwaysOnTop, Off, ahk_id %hwndID%
        restoredAnyWindow := true
    }

    if (draggedHwndID && topmostStates.HasKey(draggedHwndID) && WinExist("ahk_id " . draggedHwndID)) {
        if (topmostStates[draggedHwndID])
            WinSet, AlwaysOnTop, On, ahk_id %draggedHwndID%
        else
            WinSet, AlwaysOnTop, Off, ahk_id %draggedHwndID%
        restoredAnyWindow := true
    }

    return restoredAnyWindow
}

; Record one live-resize window's starting topmost state once, then force it
; topmost immediately so the active resize cohort stays visually on top.
_TrackLiveResizeSyncTopmostState(hwndID, ByRef topmostStates) {
    if (!hwndID || !IsObject(topmostStates))
        return false

    if (topmostStates.HasKey(hwndID))
        return true

    if !WinExist("ahk_id " . hwndID)
        return false

    topmostStates[hwndID] := IsAlwaysOnTop(hwndID)
    WinSet, AlwaysOnTop, On, ahk_id %hwndID%
    return true
}

; Live Edge Resize

; User drags a resize edge
        ; |
        ; v
; +-------------------------------+
; | Detect which edge was grabbed |
; | HTLEFT / HTRIGHT / HTTOP /    |
; | HTBOTTOM                      |
; | CabinetWClass fallback:       |
; | - outer-frame geometry        |
; | - matching resize cursor      |
; +-------------------------------+
        ; |
        ; v
; +----------------------------------+
; | Vertical full-height guard       |
; |                                  |
; | TOP/BOTTOM drag on a full-       |
; | monitor-height window does not   |
; | arm cluster resize               |
; +----------------------------------+
        ; |
        ; v
; +----------------------------------+
; | Build same-side peer group       |
; |                                  |
; | LEFT/RIGHT drag:                 |
; | - windows with matching left+    |
; |   right edges                    |
; | - vertically contiguous/near     |
; |                                  |
; | TOP/BOTTOM drag:                 |
; | - windows with matching top+     |
; |   bottom edges                   |
; | - horizontally contiguous/near   |
; +----------------------------------+
        ; |
        ; v
; +----------------------------------+
; | Find opposite-side partners      |
; | for each peer                    |
; |                                  |
; | LEFT/RIGHT drag:                 |
; | - windows touching the moving    |
; |   vertical boundary              |
; |                                  |
; | TOP/BOTTOM drag:                 |
; | - windows touching the moving    |
; |   horizontal boundary            |
; +----------------------------------+
        ; |
        ; v
; +----------------------------------+
; | Temporarily raise resize cohort  |
; |                                  |
; | - peers/partners promoted first  |
; | - dragged window promoted last   |
; | - dragged window fades once a    |
; |   real resize is underway        |
; +----------------------------------+
        ; |
        ; v
; +----------------------------------+
; | Apply live resize                |
; |                                  |
; | peer windows:                    |
; | - mirror the dragged edge        |
; |                                  |
; | opposite-side partners:          |
; | - anchored far edge: resize      |
; |   against that fixed far edge    |
; | - floating far edge: keep width  |
; |   and slide with the boundary    |
; +----------------------------------+
        ; |
        ; v
; Release LButton
        ; |
        ; v
; Restore temporary resize state
; - peers/partners restored first
; - dragged window restored last
; Example: #1/#2 stacked on the left, #3 on the right

; +-------------+  +-----------+
; |     #1      |  |           |
; +-------------+  |    #3     |
; |     #2      |  |           |
; +-------------+  +-----------+
; Drag #1 or #2 right edge:
; #1 and #2 resize together as peers
; #3 follows as the opposite-side partner
; Drag #2 top edge:
; #1 follows on its bottom edge
; #3 should not be involved
; Moved Window Release Fit

; Bottom line

; Live edge resize is cluster-based: peers mirror, opposite-side partners follow the shared boundary.
; Release-time moved-window fit is two-phase: adjacent geometry first, then one docked window below in z-order as a width/height template fallback.

; Release this bottom-resize path's cursor clamp. The flag records whether its
; ClipCursor() call succeeded; it does not identify the global cursor owner.
EndBottomResizeCursorClamp() {
    global bottomResizeCursorClampActive
    global bottomResizeCursorClampHwnd

    ; Disable the watcher first so a timer callback cannot reenter cleanup while state is being cleared.
    SetTimer, WatchBottomResizeCursorClamp, Off
    ; Snapshot successful installation before resetting globals so cleanup can report whether it acted.
    hadActiveClamp := bottomResizeCursorClampActive
    ; Call the global cursor release only after this bottom-resize path successfully called ClipCursor().
    if (hadActiveClamp)
        UnclipCursor()

    ; Clear both fields on every path so a later resize cannot inherit an obsolete window handle.
    bottomResizeCursorClampActive := False
    bottomResizeCursorClampHwnd   := 0
    ; Return the prior state so callers can distinguish actual release from idempotent cleanup.
    return hadActiveClamp
}

; For a native bottom-edge or bottom-corner resize, confine the pointer at the
; position that places the window's bottom exactly at the taskbar's top. The
; initial window-bottom-to-pointer offset keeps the window edge authoritative;
; a lightweight timer only watches for LButton-up or target loss.
TryStartBottomResizeCursorClamp(xPos := "", yPos := "", hwnd := "") {
    global bottomResizeCursorClampActive
    global bottomResizeCursorClampHwnd

    static HTBOTTOM      := 15  ; Non-client bottom resize border.
    static HTBOTTOMLEFT  := 16  ; Non-client bottom-left resize corner.
    static HTBOTTOMRIGHT := 17  ; Non-client bottom-right resize corner.

    if (bottomResizeCursorClampActive)
        EndBottomResizeCursorClamp()

    if (xPos = "" || yPos = "" || hwnd = "")
        MouseGetPos, xPos, yPos, hwnd

    if (!hwnd)
        return false

    resizeHwnd := DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")  ; GA_ROOT = 2
    if (!resizeHwnd)
        return false

    edgeHit := _GetReliableResizeEdgeHit(xPos, yPos, resizeHwnd)
    if (edgeHit != HTBOTTOM && edgeHit != HTBOTTOMLEFT && edgeHit != HTBOTTOMRIGHT)
        return false

    pointValue := (xPos & 0xFFFFFFFF) | ((yPos & 0xFFFFFFFF) << 32)
    monitorHandle := DllCall("user32\MonitorFromPoint", "Int64", pointValue, "UInt", 2, "Ptr")  ; MONITOR_DEFAULTTONEAREST = 2
    if (!monitorHandle)
        return false

    VarSetCapacity(monitorInfo, 40, 0)
    NumPut(40, monitorInfo, 0, "UInt")
    if !DllCall("user32\GetMonitorInfo", "Ptr", monitorHandle, "Ptr", &monitorInfo)
        return false

    monitorLeft   := NumGet(monitorInfo,  4, "Int")
    monitorTop    := NumGet(monitorInfo,  8, "Int")
    monitorRight  := NumGet(monitorInfo, 12, "Int")
    monitorBottom := NumGet(monitorInfo, 16, "Int")
    workBottom    := NumGet(monitorInfo, 32, "Int")

    ; A lower work-area boundary proves that a taskbar or another reserved
    ; appbar occupies the bottom of this monitor. Otherwise no clamp is needed.
    if (workBottom >= monitorBottom || workBottom <= monitorTop)
        return false

    ; Use the DWM-visible frame so an invisible resize border cannot make the
    ; window appear to reach the taskbar while its visible bottom remains above it.
    if !WinGetPosEx(resizeHwnd, null, windowY, null, windowHeight)
        return false
    windowBottom := windowY + windowHeight

    ; Native bottom resizing preserves this pointer-to-window-edge offset. Set
    ; the pointer's maximum Y so windowBottom can reach, but never exceed,
    ; workBottom. Add one because a Win32 RECT's bottom coordinate is exclusive.
    cursorToWindowBottomOffset := windowBottom - yPos
    clipBottom := workBottom - cursorToWindowBottomOffset + 1
    clipBottom := Min(clipBottom, monitorBottom)
    if (clipBottom <= monitorTop)
        return false

    VarSetCapacity(clipRect, 16, 0)
    NumPut(monitorLeft,  clipRect,  0, "Int")
    NumPut(monitorTop,   clipRect,  4, "Int")
    NumPut(monitorRight, clipRect,  8, "Int")
    NumPut(clipBottom,   clipRect, 12, "Int")
    if !DllCall("user32\ClipCursor", "Ptr", &clipRect)
        return false

    bottomResizeCursorClampActive := True
    bottomResizeCursorClampHwnd   := resizeHwnd
    SetTimer, WatchBottomResizeCursorClamp, 10
    return true
}

; Arm a temporary live-resize sync group only when the current LButton press
; starts on a plain left/right/top/bottom resize edge and that edge is already
; part of a plausible peer/partner dock relationship.
TryStartLButtonResizeSync(xPos := "", yPos := "", hwnd := "") {
    global lButtonResizeSyncActive
    global lButtonResizeSyncDraggedHwnd
    global lButtonResizeSyncDraggedStartedAlwaysOnTop
    global lButtonResizeSyncDraggedTransparent
    global lButtonResizeSyncHit
    global lButtonResizeSyncLastDraggedH
    global lButtonResizeSyncLastDraggedW
    global lButtonResizeSyncLastDraggedX
    global lButtonResizeSyncLastDraggedY
    global lButtonResizeSyncPartners
    global lButtonResizeSyncTopmostStates

    static HTBOTTOM := 15  ; Non-client bottom resize border.
    static HTLEFT   := 10  ; Non-client left resize border.
    static HTRIGHT  := 11  ; Non-client right resize border.
    static HTTOP    := 12  ; Non-client top resize border.

    if (xPos = "" || yPos = "" || hwnd = "")
        MouseGetPos, xPos, yPos, hwnd

    if (!hwnd)
        return false

    draggedHwndID := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    if (!draggedHwndID)
        return false

    if !WinGetPosEx(draggedHwndID, draggedX, draggedY, draggedW, draggedH, null, null)
        return false

    edgeHit := _GetReliableResizeEdgeHit(xPos, yPos, draggedHwndID)
    if (edgeHit != HTLEFT && edgeHit != HTRIGHT && edgeHit != HTTOP && edgeHit != HTBOTTOM)
        return false

    monitorNum := GetWindowMonitorNumber(draggedHwndID)
    if (monitorNum < 1)
        return false

    draggedIsFullHeight := (   (edgeHit = HTLEFT || edgeHit = HTRIGHT)
                            && _IsFullMonitorHeightWindow(draggedHwndID, monitorNum))

    ; Live resize-sync should only arm when the partner already looks flush to
    ; the dragged edge, so use tighter edge/gap tolerances than the broader
    ; post-release fit helpers use.
    liveResizeEdgeGapTolerance        := 10
    liveResizePeerEdgeTolerance       := 25
    liveResizePeerGapTolerance        := 100
    liveResizeEdgeTouchTolerance      := 10
    suppressVerticalFullHeightCluster := (edgeHit = HTTOP || edgeHit = HTBOTTOM)

    if (   suppressVerticalFullHeightCluster
        && _IsFullMonitorHeightWindow(draggedHwndID, monitorNum))
        return false

    partnerSearchMode := ""
    if (edgeHit = HTLEFT)
        partnerSearchMode := "right"
    else if (edgeHit = HTRIGHT)
        partnerSearchMode := "left"
    else if (edgeHit = HTTOP)
        partnerSearchMode := "bottom"
    else if (edgeHit = HTBOTTOM)
        partnerSearchMode := "top"

    lButtonResizeSyncPartners := []
    resizeTargetHwndMap := {}
    sameSidePeerHwndIDs := _BuildLiveResizePeerHwndIDs(draggedHwndID, monitorNum, edgeHit, liveResizePeerEdgeTolerance, liveResizePeerGapTolerance)
    if (!IsObject(sameSidePeerHwndIDs) || !sameSidePeerHwndIDs.MaxIndex())
        sameSidePeerHwndIDs := [draggedHwndID]

    sameSidePeerHwndMap := {}
    for sameSidePeerIndex, sameSidePeerHwndID in sameSidePeerHwndIDs
        sameSidePeerHwndMap[sameSidePeerHwndID] := true

    ; Same-side peers mirror the exact edge the user is dragging so windows in
    ; the same column or row stay aligned while the opposite-side partners react
    ; to the shared boundary movement.
    for sameSidePeerIndex, sameSidePeerHwndID in sameSidePeerHwndIDs {
        if (!sameSidePeerHwndID || sameSidePeerHwndID = draggedHwndID)
            continue

        if !WinGetPosEx(sameSidePeerHwndID, sameSidePeerX, sameSidePeerY, sameSidePeerW, sameSidePeerH, null, null)
            continue

        ; Cache the peer's "full monitor height" state once at arm time so the
        ; live-resize plan can distinguish true split panes from floating side
        ; followers without recomputing geometry on every timer tick.
        resizeTargetInfo := { hwnd: sameSidePeerHwndID, isFullHeight: _IsFullMonitorHeightWindow(sameSidePeerHwndID, monitorNum), role: "peer" }
        resizeTargetInfo.fixedEdge := _GetLiveResizeSyncFixedEdge(sameSidePeerX, sameSidePeerY, sameSidePeerW, sameSidePeerH, edgeHit, "peer")
        lButtonResizeSyncPartners.Push(resizeTargetInfo)
        resizeTargetHwndMap[sameSidePeerHwndID] := true
    }

    for sameSidePeerIndex, sameSidePeerHwndID in sameSidePeerHwndIDs {
        if !WinGetPosEx(sameSidePeerHwndID, sameSidePeerX, sameSidePeerY, sameSidePeerW, sameSidePeerH, null, null)
            continue

        partnerHwndIDs := Find2DEdgePartnerWindows(sameSidePeerHwndID, monitorNum, liveResizeEdgeTouchTolerance, 1, 100, 100, partnerSearchMode, liveResizeEdgeGapTolerance, sameSidePeerX, sameSidePeerY, sameSidePeerW, sameSidePeerH)
        if (!IsObject(partnerHwndIDs) || !partnerHwndIDs.MaxIndex())
            continue

        for partnerIndex, partnerHwndID in partnerHwndIDs {
            if (!partnerHwndID)
                continue
            if (partnerHwndID = draggedHwndID)
                continue
            partnerIsFullHeight := _IsFullMonitorHeightWindow(partnerHwndID, monitorNum)
            if (   suppressVerticalFullHeightCluster
                && partnerIsFullHeight)
                continue
            if (sameSidePeerHwndMap.HasKey(partnerHwndID))
                continue
            if (resizeTargetHwndMap.HasKey(partnerHwndID))
                continue
            if !WinGetPosEx(partnerHwndID, partnerX, partnerY, partnerW, partnerH, null, null)
                continue

            ; Cache the partner's current geometry traits at arm time. The
            ; actual horizontal move-vs-resize choice is made below from this
            ; partner's own far-edge anchor state, not from height alone.
            resizeTargetInfo := { hwnd: partnerHwndID, isFullHeight: partnerIsFullHeight, role: "opposite" }
            resizeTargetInfo.fixedEdge := _GetLiveResizeSyncFixedEdge(partnerX, partnerY, partnerW, partnerH, edgeHit, "opposite")
            lButtonResizeSyncPartners.Push(resizeTargetInfo)
            resizeTargetHwndMap[partnerHwndID] := true
        }
    }

    if (!lButtonResizeSyncPartners.MaxIndex())
        return false

    draggedOuterDockSide := ""
    if (edgeHit = HTRIGHT)
        draggedOuterDockSide := "left"
    else if (edgeHit = HTLEFT)
        draggedOuterDockSide := "right"

    draggedStartsAsSideDock := (   draggedOuterDockSide != ""
                                && _IsLiveResizeThreeEdgeDockedOnSide(draggedHwndID, monitorNum, draggedOuterDockSide, draggedX, draggedY, draggedW, draggedH))

    liveResizeMoveSupportTolerance := 10
    SysGet, monInfo, MonitorWorkArea, %monitorNum%

    ; Horizontal opposite-side followers should move by default when the
    ; dragged window is a true left/right 3-edge dock. Only keep them in the
    ; resize path when their own far side is backed by a true 3-edge dock,
    ; either directly or through the next flush pane on that far side.
    for resizeTargetIndex, resizeTargetInfo in lButtonResizeSyncPartners {
        if (resizeTargetInfo.role != "opposite") {
            resizeTargetInfo.useMoveOnly := false
            continue
        }

        if (!draggedStartsAsSideDock || (edgeHit != HTLEFT && edgeHit != HTRIGHT)) {
            resizeTargetInfo.useMoveOnly := false
            continue
        }

        if !WinGetPosEx(resizeTargetInfo.hwnd, partnerX, partnerY, partnerW, partnerH, null, null) {
            resizeTargetInfo.useMoveOnly := false
            continue
        }

        partnerBottomEdge       := partnerY + partnerH
        partnerTouchesTopOrBottom := (   Abs(partnerY - monInfoTop) <= liveResizeMoveSupportTolerance
                                      || Abs(partnerBottomEdge - monInfoBottom) <= liveResizeMoveSupportTolerance)

        if (!partnerTouchesTopOrBottom) {
            resizeTargetInfo.useMoveOnly := false
            continue
        }

        partnerFarDockSide          := (edgeHit = HTRIGHT) ? "right" : "left"
        partnerFarNeighborTargetEdge := (edgeHit = HTRIGHT) ? "left" : "right"
        partnerBackedByThreeEdgeDock := _IsLiveResizeThreeEdgeDockedOnSide(resizeTargetInfo.hwnd, monitorNum, partnerFarDockSide, partnerX, partnerY, partnerW, partnerH)

        if (!partnerBackedByThreeEdgeDock) {
            farSidePartnerHwndIDs := Find2DEdgePartnerWindows(resizeTargetInfo.hwnd, monitorNum, liveResizeEdgeTouchTolerance, 0, 0, 100, partnerFarNeighborTargetEdge, liveResizeEdgeGapTolerance, partnerX, partnerY, partnerW, partnerH)
            if (IsObject(farSidePartnerHwndIDs) && farSidePartnerHwndIDs.MaxIndex()) {
                for farSidePartnerIndex, farSidePartnerHwndID in farSidePartnerHwndIDs {
                    if (!farSidePartnerHwndID || farSidePartnerHwndID = resizeTargetInfo.hwnd)
                        continue
                    if !WinGetPosEx(farSidePartnerHwndID, farSidePartnerX, farSidePartnerY, farSidePartnerW, farSidePartnerH, null, null)
                        continue
                    if (_IsLiveResizeThreeEdgeDockedOnSide(farSidePartnerHwndID, monitorNum, partnerFarDockSide, farSidePartnerX, farSidePartnerY, farSidePartnerW, farSidePartnerH)) {
                        partnerBackedByThreeEdgeDock := true
                        break
                    }
                }
            }
        }

        resizeTargetInfo.useMoveOnly := !partnerBackedByThreeEdgeDock
    }

    lButtonResizeSyncActive                    := true
    lButtonResizeSyncDraggedHwnd               := draggedHwndID
    lButtonResizeSyncDraggedStartedAlwaysOnTop := IsAlwaysOnTop(draggedHwndID)
    lButtonResizeSyncDraggedTransparent        := false
    lButtonResizeSyncHit                       := edgeHit
    lButtonResizeSyncLastDraggedH              := draggedH
    lButtonResizeSyncLastDraggedW              := draggedW
    lButtonResizeSyncLastDraggedX              := draggedX
    lButtonResizeSyncLastDraggedY              := draggedY
    lButtonResizeSyncTopmostStates             := _CaptureLiveResizeSyncTopmostStates(draggedHwndID, lButtonResizeSyncPartners)
    _PrepareLButtonResizeSyncGhostCards(lButtonResizeSyncPartners)

    SetTimer, WatchLButtonResizeSync, 10
    return true
}

; Clear the temporary state used to mirror same-side peers and opposite-side
; partners during a native LButton edge resize. Timer shutdown and timer
; re-enabling are handled by the caller so this helper can also be used as an
; internal guard path.
EndLButtonResizeSync() {
    global lButtonResizeSyncActive
    global lButtonResizeSyncDraggedHwnd
    global lButtonResizeSyncDraggedStartedAlwaysOnTop
    global lButtonResizeSyncDraggedTransparent
    global lButtonResizeSyncHit
    global lButtonResizeSyncLastDraggedH
    global lButtonResizeSyncLastDraggedW
    global lButtonResizeSyncLastDraggedX
    global lButtonResizeSyncLastDraggedY
    global lButtonResizeSyncPartners
    global lButtonResizeSyncTopmostStates

    if (   lButtonResizeSyncDraggedHwnd
        && lButtonResizeSyncDraggedTransparent
        && !lButtonResizeSyncDraggedStartedAlwaysOnTop
        && WinExist("ahk_id " . lButtonResizeSyncDraggedHwnd))
        WinSet, Transparent, Off, ahk_id %lButtonResizeSyncDraggedHwnd%

    _ReleaseLButtonResizeSyncGhostCards(lButtonResizeSyncPartners)
    _RestoreLiveResizeSyncTopmostStates(lButtonResizeSyncTopmostStates, lButtonResizeSyncDraggedHwnd)
    lButtonResizeSyncActive                    := false
    lButtonResizeSyncDraggedHwnd               := 0
    lButtonResizeSyncDraggedStartedAlwaysOnTop := false
    lButtonResizeSyncDraggedTransparent        := false
    lButtonResizeSyncHit                       := 0
    lButtonResizeSyncLastDraggedH              := ""
    lButtonResizeSyncLastDraggedW              := ""
    lButtonResizeSyncLastDraggedX              := ""
    lButtonResizeSyncLastDraggedY              := ""
    lButtonResizeSyncPartners                  := []
    lButtonResizeSyncTopmostStates             := {}
}

; While a native edge resize is in progress, keep each matched same-side peer
; and opposite-side partner in sync with the dragged window. Peers mirror the
; dragged edge directly, while opposite-side partners either preserve their far
; edge and resize, or preserve width and slide, based on the partner's cached
; arm-time far-edge anchor state.
UpdateLButtonResizeSync() {
    global lButtonResizeSyncActive
    global lButtonResizeSyncDraggedHwnd
    global lButtonResizeSyncDraggedStartedAlwaysOnTop
    global lButtonResizeSyncDraggedTransparent
    global lButtonResizeSyncHit
    global lButtonResizeSyncLastDraggedH
    global lButtonResizeSyncLastDraggedW
    global lButtonResizeSyncLastDraggedX
    global lButtonResizeSyncLastDraggedY
    global lButtonResizeSyncPartners

    static HTBOTTOM := 15  ; Non-client bottom resize border.
    static HTLEFT   := 10  ; Non-client left resize border.
    static HTRIGHT  := 11  ; Non-client right resize border.
    static HTTOP    := 12  ; Non-client top resize border.

    if (!lButtonResizeSyncActive || !IsObject(lButtonResizeSyncPartners) || !lButtonResizeSyncPartners.MaxIndex())
        return false

    ; The dragged window owns the live edge being moved by the user. If it goes
    ; away mid-resize, stop driving partner windows immediately.
    if (!WinExist("ahk_id " . lButtonResizeSyncDraggedHwnd)) {
        EndLButtonResizeSync()
        return false
    }

    ; Refresh the dragged window's geometry on each timer tick so every partner
    ; follows the exact edge the user is currently moving.
    if !WinGetPosEx(lButtonResizeSyncDraggedHwnd, draggedX, draggedY, draggedW, draggedH, null, null) {
        EndLButtonResizeSync()
        return false
    }

    if (draggedX = lButtonResizeSyncLastDraggedX
     && draggedY = lButtonResizeSyncLastDraggedY
     && draggedW = lButtonResizeSyncLastDraggedW
     && draggedH = lButtonResizeSyncLastDraggedH)
        return false

    lButtonResizeSyncLastDraggedH := draggedH
    lButtonResizeSyncLastDraggedW := draggedW
    lButtonResizeSyncLastDraggedX := draggedX
    lButtonResizeSyncLastDraggedY := draggedY

    movePlan := _BuildLButtonResizeSyncMovePlan(draggedX, draggedY, draggedW, draggedH)
    if !IsObject(movePlan) {
        EndLButtonResizeSync()
        return false
    }

    if (movePlan.tbcMoves.MaxIndex())
        _ApplyLButtonResizeSyncPreviewMoves(movePlan.tbcMoves)

    _ReleaseLButtonResizeSyncDroppedFollowers(lButtonResizeSyncPartners, movePlan.validPartners)
    lButtonResizeSyncPartners := movePlan.validPartners
    if (!lButtonResizeSyncPartners.MaxIndex()) {
        EndLButtonResizeSync()
        return false
    }

    return movePlan.didResizeAny
}

MouseIsOverCaptionButtons(xPos := "", yPos := "") {
    SysGet, SM_CXBORDER, 5
    SysGet, SM_CYBORDER, 6
    SysGet, SM_CXFIXEDFRAME, 7
    SysGet, SM_CYFIXEDFRAME, 8
    SysGet, SM_CXMIN, 28
    SysGet, SM_CYMIN, 29
    SysGet, SM_CXSIZE, 30
    SysGet, SM_CYSIZE , 31
    SysGet, SM_CXSIZEFRAME, 32
    SysGet, SM_CYSIZEFRAME , 33

    titlebarHeight := SM_CYMIN-SM_CYSIZEFRAME

    CoordMode, Mouse, Screen
    if (xPos = "" || yPos = "") {
        MouseGetPos, xPos, yPos, windowUnderMouseId, ctrlNNUnderMouse
    } else {
        MouseGetPos, , , windowUnderMouseId, ctrlNNUnderMouse
    }

    If (!IsAltTabWindow(WindowUnderMouseID))
        Return False

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    If    ((mClass != "Shell_TrayWnd")
        && (mClass != "WorkerW")
        && (mClass != "ProgMan")
        && (mClass != "TaskListThumbnailWnd")
        && (mClass != "#32768")
        && (mClass != "MsoCommandBarPopup")
        && (mClass != "Net UI Tool Window")) {

        WinGetPosEx(WindowUnderMouseID,x,y,w,h)
        SendMessage, 0x84, 0, (xPos & 0xFFFF) | (yPos & 0xFFFF)<<16,, ahk_id %WindowUnderMouseID%, , , , 500
        If (((yPos > y) && (yPos < (y+titlebarHeight))) && ((ErrorLevel == 8) || (ErrorLevel == 9) || (ErrorLevel == 20)))
            Return True
        ; Only run the WhichButton() fallback inside the actual top-right caption-button strip.
        ; Otherwise text under the mouse (for example source code containing the word
        ; "minimize") can be mistaken for a caption button name.
        Else If (ctrlNNUnderMouse != ""
                && (yPos > y) && (yPos < (y+titlebarHeight))
                && (xPos > (x+w-(3*45)))) {
            vName := WhichButton(xPos, yPos, windowUnderMouseId)
            if (   InStr(vName, "minimize", false)
                || InStr(vName, "maximize", false)
                || InStr(vName, "restore",  false)
                || InStr(vName, "close",    false))
                Return True
            Return False
        }
        Else If ((ErrorLevel != 12)
                && (yPos > y) && (yPos < (y+titlebarHeight)) && (xPos > (x+w-(3*45)))) {
            ; tooltip, %SM_CXBORDER% - %SM_CYBORDER% : %SM_CXFIXEDFRAME% - %SM_CYFIXEDFRAME%
            Return True
        }
        Else
            Return False
    }
    Else
        Return False
}

;https://stackoverflow.com/questions/59883798/determine-which-monitor-the-focus-window-is-on
IsWindowOnMonNum(thisWindowHwnd, targetMonNum := 0) {
    X := Y := W := H := 0
    WinGet, state, MinMax, ahk_id %thisWindowHwnd%

    if (targetMonNum < 1)
        Return False

    ; Minimized windows do not have a meaningful current on-screen rect, so use
    ; their restored placement monitor instead of claiming they belong to every
    ; monitor.
    If (state == -1)
        Return (GetWindowMonitorNumber(thisWindowHwnd) = targetMonNum)

    ; WinGetPos, X, Y, W, H, ahk_id %thisWindowHwnd%
    WinGetPosEx(thisWindowHwnd, X, Y, W, H)
    if (W <= 0 || H <= 0)
        Return False

    Critical, On
    SysGet, workArea, Monitor, %targetMonNum%

    ;Check If the focus window in on the requested monitor index
    ; https://math.stackexchange.com/questions/2449221/calculating-percentage-of-overlap-between-two-rectangles
    overlapRatio := ((max(X, workAreaLeft) - min(X+W, workAreaRight)) * (max(Y, workAreaTop) - min(Y+H, workAreaBottom))) / (W * H)
    Critical, Off
    Return (overlapRatio > 0.50)
}

GetWindowMonitorNumber(windowHwnd) {
    static monitorDefaultToNearest := 2  ; MONITOR_DEFAULTTONEAREST
    static windowPlacementSize := 44
    static rectSize := 16
    static swShowMinimized := 2

    if !windowHwnd
        return 0

    VarSetCapacity(windowPlacement, windowPlacementSize, 0)
    NumPut(windowPlacementSize, windowPlacement, 0, "UInt")

    if !DllCall("GetWindowPlacement", "Ptr", windowHwnd, "Ptr", &windowPlacement)
        return 0

    showCmd := NumGet(windowPlacement, 8, "UInt")

    VarSetCapacity(targetRect, rectSize, 0)

    if (showCmd = swShowMinimized) {
        ; Use restored position for minimized windows.
        windowLeft   := NumGet(windowPlacement, 28, "Int")
        windowTop    := NumGet(windowPlacement, 32, "Int")
        windowRight  := NumGet(windowPlacement, 36, "Int")
        windowBottom := NumGet(windowPlacement, 40, "Int")

        NumPut(windowLeft,   targetRect, 0,  "Int")
        NumPut(windowTop,    targetRect, 4,  "Int")
        NumPut(windowRight,  targetRect, 8,  "Int")
        NumPut(windowBottom, targetRect, 12, "Int")
    } else {
        ; Use actual current rect for normal/maximized windows.
        if !DllCall("GetWindowRect", "Ptr", windowHwnd, "Ptr", &targetRect)
            return 0
    }

    targetMonitorHandle := DllCall("MonitorFromRect", "Ptr", &targetRect, "UInt", monitorDefaultToNearest, "Ptr")
    if !targetMonitorHandle
        return 0

    SysGet, monitorCount, MonitorCount
    Loop, %monitorCount% {
        SysGet, monitorArea, Monitor, %A_Index%

        VarSetCapacity(monitorRect, rectSize, 0)
        NumPut(monitorAreaLeft,   monitorRect, 0,  "Int")
        NumPut(monitorAreaTop,    monitorRect, 4,  "Int")
        NumPut(monitorAreaRight,  monitorRect, 8,  "Int")
        NumPut(monitorAreaBottom, monitorRect, 12, "Int")

        currentMonitorHandle := DllCall("MonitorFromRect", "Ptr", &monitorRect, "UInt", monitorDefaultToNearest, "Ptr")
        if (currentMonitorHandle = targetMonitorHandle)
            return A_Index
    }

    return 0
}

;https://www.autohotkey.com/boards/viewtopic.php?f=6&t=54557
MWAGetMonitorMouseIsIn(buffer := 0) ; we didn't actually need the "Monitor = 0"
{
    global currMonWidth, currMonHeight
    static cachedMonitorCount := 0
    static cachedMonitors := []
    ; get the mouse coordinates first
    Coordmode, Mouse, Screen    ; use Screen, so we can compare the coords with the sysget information`
    MouseGetPos, Mx, My
    ActiveMon := 0

    SysGet, MonitorCount, 80    ; monitorcount, so we know how many monitors there are, and the number of loops we need to do
    if (MonitorCount != cachedMonitorCount || cachedMonitors.MaxIndex() != MonitorCount) {
        cachedMonitors := []
        Loop, %MonitorCount%
        {
            SysGet, mon, Monitor, %A_Index%    ; "Monitor" will get the total desktop space of the monitor, including taskbars
            cachedMonitors[A_Index] := { "left": monLeft
                , "top": monTop
                , "right": monRight
                , "bottom": monBottom }
        }
        cachedMonitorCount := MonitorCount
    }

    Loop, %MonitorCount%
    {
        mon := cachedMonitors[A_Index]
        If ( Mx >= (mon.left + buffer) ) && ( Mx < (mon.right - buffer) ) && ( My >= (mon.top + buffer) ) && ( My < (mon.bottom - buffer) )
        {
            currMonHeight := abs(mon.bottom - mon.top)
            currMonWidth  := abs(mon.right  - mon.left)
            ActiveMon := A_Index
            break
        }
    }
    Return ActiveMon
}

join( strArray )
{
  s := ""
  for i,v in strArray
    s .= ", " . v
  Return substr(s, 3)
}

MoveAndFadeWindow(Hwnd, initPosx, toRight := True, fadeInOut := "out") {
    DetectHiddenWindows, On
    Critical, On
    If toRight
        moveConst := 1
    Else
        moveConst := -1

    If (fadeInOut == "out") {
        temp_x := initPosx

        WinSet, Transparent, 225, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 200, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 175, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 150, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 100, ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 50,  ahk_id %Hwnd%
        temp_x += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x%
        sleep, 20
        WinSet, Transparent, 0,   ahk_id %Hwnd%
        sleep, 20
        WinMove, ahk_id %Hwnd%,, %initPosx%
    }
    Else {
        If toRight
            temp_x_start := initPosx-(15 * 6)
        Else
            temp_x_start := initPosx+(15 * 6)

        WinSet, Transparent, 0, ahk_id %Hwnd%

        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 50, ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 100, ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 150, ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 175, ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 200,  ahk_id %Hwnd%
        temp_x_start += 15*moveConst
        WinMove, ahk_id %Hwnd%,, %temp_x_start%
        sleep, 20
        WinSet, Transparent, 225, ahk_id %Hwnd%
        sleep, 20
        WinSet, Transparent, 255, ahk_id %Hwnd%
    }

    Critical, Off
    Return
}

DesktopIcons(FadeIn := True) ; lParam, wParam, Msg, hWnd
{
    ControlGet, hwndProgman, Hwnd,, SysListView321, ahk_class Progman
    ; Toggle See through icons.
    If !FadeIn
    {
        Critical, On
        If hwndProgman=
        {
            WinSet, Trans, 200, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 150, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 100, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 75, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 25, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 0, ahk_class WorkerW
        }
        Else
        {
            WinSet, Trans, 200, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 150, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 100, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 75, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 25, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 0, ahk_id %hwndProgman%
            sleep, 20
        }
        Critical, Off
    }
    Else
    {
        Critical, On
        If hwndProgman=
        {
            WinSet, Trans, OFF, ahk_class WorkerW
            WinSet, Trans, 25, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 75, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 100, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 150, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 200, ahk_class WorkerW
            sleep, 20
            WinSet, Trans, 255, ahk_class WorkerW
        }
        Else
        {
            WinSet, Trans, OFF, ahk_id %hwndProgman%
            WinSet, Trans, 25, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 75, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 100, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 150, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 200, ahk_id %hwndProgman%
            sleep, 20
            WinSet, Trans, 255, ahk_id %hwndProgman%
        }
        Critical, Off
    }
}

;https://www.autohotkey.com/boards/search.php?author_id=139004&sr=posts&sid=13343c88f1a3953143867b71b22fdafc
HasVal(haystack, needle) {
    If !(IsObject(haystack)) || (haystack.Length() = 0)
        Return 0
    for index, value in haystack
        If (value = needle)
            Return index
    Return 0
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
    global clipPreferExplicitCtrlV
    static BackUpClip := "", Stored := False, LastClip := "", Restored := ""

    if (Restore) {
        if (Clipboard == LastClip)
            Clipboard := BackUpClip
        BackUpClip := "", LastClip := "", Stored := ""
        SetTimer, ClipRestore, Off
        Return
    } else {
        clipResult := ""
        isReadCall := (Text = "")

        if (expectedWindowId && !IsForegroundWindow(expectedWindowId))
            return ""

        if !Stored {
            Stored := True
            ; ClipboardAll must be on its own line in v1
            BackUpClip := ClipboardAll
        } else {
            ; cancel any tbc restore before starting a new clipboard transaction
            SetTimer, ClipRestore, Off
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

            if !_SendManagedCtrlChord("c", 6, False, modifiersToSync, expectedWindowId) {
                Clip("", "", "RESTORE")
                return ""
            }
            if (clearMs > 50) {
                ClipWait, 0.6, 1
            } else {
                ClipWait, 0.2, 1
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

            if (clipPreferExplicitCtrlV)
                ; Some modern editors misread {Blind}v and occasionally type
                ; a literal v, so use an explicit managed Ctrl+V chord.
                didPaste := _SendManagedCtrlChord("v", 6, True, modifiersToSync, expectedWindowId)
            else
                didPaste := _SendManagedCtrlChord("v", 6, False, modifiersToSync, expectedWindowId)
            if !didPaste {
                Clip("", "", "RESTORE")
                return ""
            }
            Sleep, 20  ; small buffer in case more keystrokes (e.g., Enter) follow a paste
        }

        ; schedule a one-shot restore in ~700ms
        SetTimer, ClipRestore, -700

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
return

;-------------------------------------------------------------------------------
; https://github.com/radosi/virtualdesktop/tree/main
;-------------------------------------------------------------------------------
getTotalDesktops()
{
    global DesktopCount

    mapDesktopsFromRegistry()
    Return DesktopCount
}

; This function examines the registry to build an accurate list of the current virtual desktops and which one we're currently on.
; Current desktop UUID appears to be in HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\VirtualDesktops
; List of desktops appears to be in HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops
; On Windows 11 the current desktop UUID appears to be in the same location
; On previous versions in HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\VirtualDesktops
;
mapDesktopsFromRegistry()
{
    global CurrentDesktop, DesktopCount

    ; Get the current desktop UUID. Length should be 32 always, but there's no guarantee this couldn't change in a later Windows release so we check.
    IdLength := 32
    SessionId := getSessionId()
    If (SessionId) {

        ; Older windows 10 version
        ;RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\VirtualDesktops, CurrentVirtualDesktop

        ; Windows 10
        ;RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\%SessionId%\VirtualDesktops, CurrentVirtualDesktop

        ; Windows 11
        RegRead, CurrentDesktopId, HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops, CurrentVirtualDesktop
        If ErrorLevel {
            RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\%SessionId%\VirtualDesktops, CurrentVirtualDesktop
        }

        If (CurrentDesktopId) {
            IdLength := StrLen(CurrentDesktopId)
        }
    }

    ; Get a list of the UUIDs for all virtual desktops on the system
    RegRead, DesktopList, HKEY_CURRENT_USER, SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops, VirtualDesktopIDs
    If (DesktopList) {
        DesktopListLength := StrLen(DesktopList)
        ; Figure out how many virtual desktops there are
        DesktopCount := floor(DesktopListLength / IdLength)
    }
    Else {
        DesktopCount := 1
    }

    ; Parse the REG_DATA string that stores the array of UUID's for virtual desktops in the registry.
    i := 0
    while (CurrentDesktopId and i < DesktopCount) {
        StartPos := (i * IdLength) + 1
        DesktopIter := SubStr(DesktopList, StartPos, IdLength)
        OutputDebug, The iterator is pointing at %DesktopIter% and count is %i%.

        ; Break out If we find a match in the list. If we didn't find anything, keep the
        ; old guess and pray we're still correct :-D.
        If (DesktopIter = CurrentDesktopId) {
            CurrentDesktop := i + 1
            OutputDebug, Current desktop number is %CurrentDesktop% with an ID of %DesktopIter%.
            break
        }
        i++
    }
}

;
; This functions finds out ID of current session.
;
getSessionId()
{
    ProcessId := DllCall("GetCurrentProcessId", "UInt")
    If ErrorLevel {
        OutputDebug, Error getting current process id: %ErrorLevel%
        Return
    }
    OutputDebug, Current Process Id: %ProcessId%

    DllCall("ProcessIdToSessionId", "UInt", ProcessId, "UInt*", SessionId)
    If ErrorLevel {
        OutputDebug, Error getting session id: %ErrorLevel%
        Return
    }
    OutputDebug, Current Session Id: %SessionId%
    Return SessionId
}

WinSetAlphaTopmost(guiHwnd, transparencyLevel := 220, isTopmost := true)
{
    ; Clamp alpha to 0..255
    if (transparencyLevel < 0)
    {
        transparencyLevel := 0
    }
    else if (transparencyLevel > 255)
    {
        transparencyLevel := 255
    }

    ; --- Make sure WS_EX_LAYERED is enabled ---
    gWlExstyle := -20
    wsExLayered := 0x00080000

    exstyleValue := DllCall("GetWindowLong"
        , "Ptr", guiHwnd
        , "Int", gWlExstyle
        , "Ptr")

    if ((exstyleValue & wsExLayered) = 0)
    {
        DllCall("SetWindowLong"
            , "Ptr", guiHwnd
            , "Int", gWlExstyle
            , "Ptr", (exstyleValue | wsExLayered)
            , "Ptr")
    }

    ; --- Set alpha (LWA_ALPHA) ---
    lwaAlpha := 0x2
    DllCall("SetLayeredWindowAttributes"
        , "Ptr", guiHwnd
        , "UInt", 0
        , "UChar", transparencyLevel
        , "UInt", lwaAlpha)

    ; --- Set/clear topmost ---
    hwndTopmost := -1
    hwndNoTopmost := -2
    swpNoMove := 0x0002
    swpNoSize := 0x0001
    swpNoActivate := 0x0010
    swpNoOwnerZOrder := 0x0200

    swpFlags := swpNoMove | swpNoSize | swpNoActivate | swpNoOwnerZOrder

    insertAfterHwnd := isTopmost ? hwndTopmost : hwndNoTopmost

    DllCall("SetWindowPos"
        , "Ptr", guiHwnd
        , "Ptr", insertAfterHwnd
        , "Int", 0
        , "Int", 0
        , "Int", 0
        , "Int", 0
        , "UInt", swpFlags)

    return true
}

ActivateTopMostWindow() {
    hwndID := FindTopMostWindow()
    If hwndID
        WinActivate, ahk_id %hwndID% Off
    Else {
        tooltip, no topmost window!
        sleep, 2000
        tooltip,
    }
    Return
}

FindTopMostWindow() {
    SysGet, MonCount, MonitorCount
    DetectHiddenWindows, Off
    Critical, On

    targetID := 0

    WinGet, winList, List,
    Loop, %winList%
    {
        hwndID := winList%A_Index%
        If IsAltTabWindow(hwndID) && !IsAlwaysOnTop(hwndID) {
            WinGet, mmState, MinMax, ahk_id %hwndID%
            ; WinGet, procName, ProcessName, ahk_id %hwndID%
            ; WinGet, ExStyle, ExStyle, ahk_id %hwndID%
            ; If (procName == "Zoom.exe" || (ExStyle & 0x8))
                ; continue

            If (mmState > -1) {
                If (MonCount > 1) {
                    currentMon          := MWAGetMonitorMouseIsIn()
                    currentMonHasActWin := IsWindowOnMonNum(hwndID, currentMon)
                }
                Else
                    currentMonHasActWin := True

                If currentMonHasActWin {
                    targetID := hwndID
                    break
                }
            }
        }
    }
    Critical, Off
    Return targetID
}

FindSecondMostWindow(ref_hwndID := "", monitorNum := 0) {
    SysGet, MonCount, MonitorCount
    DetectHiddenWindows, Off

    firstFound := False
    targetID   := 0

    WinGet, winList, List,
    if (!monitorNum)
        monitorNum := MWAGetMonitorMouseIsIn()

    Loop, %winList%
    {
        hwndID := winList%A_Index%
        If IsAltTabWindow(hwndId) && !IsAlwaysOnTop(hwndID) {
            WinGet, mmState, MinMax, ahk_id %hwndId%
            ; WinGet, procName, ProcessName, ahk_id %hwndId%
            ; WinGet, ExStyle, ExStyle, ahk_id %hwndId%
            ; If (procName == "Zoom.exe" || (ExStyle & 0x8)) ; skip If zoom or always on top window
                ; continue

            If (mmState > -1) {
                If (MonCount > 1) {
                    currentMonHasActWin := IsWindowOnMonNum(hwndId, monitorNum)
                }
                Else {
                    currentMonHasActWin := True
                }
                ; ref_hwndID is an optional anchor window:
                ; - blank: return the second eligible window overall
                ; - non-blank: return the first eligible window after ref_hwndID
                If !ref_hwndID {
                    If (!firstFound && currentMonHasActWin)
                        firstFound := True
                    Else If (firstFound && currentMonHasActWin) {
                        targetID := hwndID
                        break
                    }
                }
                Else {
                    If (hwndID == ref_hwndID) {
                        firstFound := True
                    }
                    Else If (firstFound && currentMonHasActWin) {
                        targetID := hwndID
                        break
                    }
                }
            }
        }
    }
    Return targetID
}

; Count how many work-area edges of the target monitor a window touches within a
; strict 3px tolerance. Edge-partner searches use this to distinguish docked
; windows from arbitrary floating candidates.
_GetWindowMonitorEdgeTouchCount(windowHwnd, monitorNum := 0) {
    strictDockEdgeTolerance := 3

    if (!windowHwnd)
        return 0

    if (!monitorNum)
        monitorNum := GetWindowMonitorNumber(windowHwnd)

    if (monitorNum < 1)
        return 0

    SysGet, monInfo, MonitorWorkArea, %monitorNum%

    if !WinGetPosEx(windowHwnd, windowX, windowY, windowW, windowH, null, null)
        return 0

    windowRightEdge  := windowX + windowW
    windowBottomEdge := windowY + windowH
    edgeTouchCount   := 0

    if (Abs(windowX - monInfoLeft) <= strictDockEdgeTolerance)
        edgeTouchCount++
    if (Abs(windowRightEdge - monInfoRight) <= strictDockEdgeTolerance)
        edgeTouchCount++
    if (Abs(windowY - monInfoTop) <= strictDockEdgeTolerance)
        edgeTouchCount++
    if (Abs(windowBottomEdge - monInfoBottom) <= strictDockEdgeTolerance)
        edgeTouchCount++

    return edgeTouchCount
}

; Probe a small grid of candidate points inside the lower-z-order window. If
; WindowFromPoint can still hit the candidate at any sampled point, then some
; portion of it is actually exposed to the user on the desktop right now.
;
; Visibility probe overview:
;
;   candidate rect
;   +-----------------------------------------------------------+
;   |       10%        30%        50%        70%        90%     |
;   |        o----------o----------o----------o----------o      |
;   |        |          |          |          |          |      |
;   |  10%   o----------o----------o----------o----------o      |
;   |        |          |          |          |          |      |
;   |  30%   o----------o----------o----------o----------o      |
;   |        |          |          |          |          |      |
;   |  50%   o----------o----------o----------o----------o      |
;   |        |          |          |          |          |      |
;   |  70%   o----------o----------o----------o----------o      |
;   |        |          |          |          |          |      |
;   |  90%   o----------o----------o----------o----------o      |
;   +-----------------------------------------------------------+
;
;   For each sampled point:
;       (sampleX, sampleY)
;            |
;            +--> WindowFromPoint(sample)
;            |        |
;            |        +--> no hwnd      -> candidateVisibleHits unchanged
;            |        +--> hwnd found
;            |               |
;            |               +--> GetAncestor(hwnd, GA_ROOT)
;            |               |
;            |               +--> root = candidate hwnd ?
;            |                        |
;            |                        +--> YES -> candidateVisibleHits++
;            |                        +--> NO  -> try next sample
;            |
;       neededHits := ceil(requiredVisiblePercent * totalSamplePoints / 100)
;            |
;            +--> during sampling:
;            |        |
;            |        +--> candidateVisibleHits >= neededHits ?
;            |        |           |
;            |        |           +--> YES -> return true early
;            |        |
;            |        +--> candidateVisibleHits + remainingSamplePoints < neededHits ?
;            |                    |
;            |                    +--> YES -> return false early
;            |
;       visiblePercent := candidateVisibleHits / totalSamplePoints * 100
;            |
;            +--> visiblePercent >= requiredVisiblePercent ?
;                        |
;                        +--> YES -> return true
;                        +--> NO  -> return false
_HasVisibleExposedAreaWindow(candidateHwndID, candidateX := "", candidateY := "", candidateW := "", candidateH := "", requiredVisiblePercent := 20, visibilityGridSize := 5, ByRef visiblePercent := "", ByRef visiblePercentBoundType := "") {
    if (!candidateHwndID)
        return false

    if (candidateX = "" || candidateY = "" || candidateW = "" || candidateH = "") {
        if !WinGetPosEx(candidateHwndID, candidateX, candidateY, candidateW, candidateH, null, null)
            return false
    }

    if (candidateW <= 0 || candidateH <= 0)
        return false

    requiredVisiblePercent := Max(0, Min(100, requiredVisiblePercent))
    visibilityGridSize := Max(1, Floor(visibilityGridSize))
    VarSetCapacity(pointStruct, 8, 0)

    candidateVisibleHits := 0
    checkedSamplePoints  := 0
    neededHits           := 0
    totalSamplePoints := visibilityGridSize * visibilityGridSize
    visiblePercentBoundType := ""
    neededHits := Ceil((requiredVisiblePercent * totalSamplePoints) / 100.0)

    if (neededHits <= 0) {
        visiblePercent := 0
        visiblePercentBoundType := "min"
        return true
    }

    Loop, %visibilityGridSize%
    {
        ; Sample the interior at evenly spaced midpoints so the probe stays off
        ; the exact outer frame while still covering the full client footprint.
        sampleColumn := A_Index
        sampleX := candidateX + Floor((candidateW - 1) * ((sampleColumn * 2) - 1) / (visibilityGridSize * 2))

        Loop, %visibilityGridSize%
        {
            sampleRow := A_Index
            sampleY := candidateY + Floor((candidateH - 1) * ((sampleRow * 2) - 1) / (visibilityGridSize * 2))
            checkedSamplePoints++

            NumPut(sampleX, pointStruct, 0, "Int")
            NumPut(sampleY, pointStruct, 4, "Int")
            pointValue := NumGet(pointStruct, 0, "Int64")
            hitHwndID  := DllCall("user32\WindowFromPoint", "Int64", pointValue, "Ptr")
            if (hitHwndID) {
                hitRootHwndID := DllCall("GetAncestor", "Ptr", hitHwndID, "UInt", 2, "Ptr")
                if (hitRootHwndID = candidateHwndID)
                    candidateVisibleHits++
            }

            if (candidateVisibleHits >= neededHits) {
                visiblePercent := (candidateVisibleHits * 100.0) / totalSamplePoints
                visiblePercentBoundType := "min"
                return true
            }

            remainingSamplePoints := totalSamplePoints - checkedSamplePoints
            if ((candidateVisibleHits + remainingSamplePoints) < neededHits) {
                visiblePercent := ((candidateVisibleHits + remainingSamplePoints) * 100.0) / totalSamplePoints
                visiblePercentBoundType := "max"
                return false
            }
        }
    }

    visiblePercent := totalSamplePoints > 0 ? ((candidateVisibleHits * 100.0) / totalSamplePoints) : 0
    visiblePercentBoundType := ""
    return (visiblePercent >= requiredVisiblePercent)
}

; Scan every visible window except the reference window, applying the shared
; monitor, docking, overlap/gap, and exposed-area filters. Callers either rank
; the returned candidates or use the complete geometric set.
_FindVisibleEdgeTouchingWindowsCore(refHwndID, monitorNum := 0, edgeTouchTolerance := 50, minEdgesTouched := 2, minHorizontalOverlap := 100, minVerticalOverlap := 100, candidateTargetEdge := "", edgeGapTolerance := 100, refX := "", refY := "", refW := "", refH := "", collectDebugTrace := false, requiredVisiblePercent := 20, visibilityGridSize := 5) {
    SysGet, MonCount, MonitorCount
    DetectHiddenWindows, Off

    result := { debugText: "", matches: [] }

    if (!refHwndID)
        return result

    if (!monitorNum)
        monitorNum := GetWindowMonitorNumber(refHwndID)

    if (monitorNum < 1)
        return result

    ; Default to the live reference window rect, but allow the caller to pin the
    ; comparison rect to the original release geometry for multi-edge fits.
    if (refX = "" || refY = "" || refW = "" || refH = "") {
        if !WinGetPosEx(refHwndID, refX, refY, refW, refH, null, null)
            return result
    }

    debugLineCount := 0
    debugMaxLines  := 6
    refBottomEdge  := refY + refH
    refRightEdge   := refX + refW

    ; WinGet List supplies deterministic z-order. This core retains every
    ; passing candidate; release fitting ranks them afterward, while live resize
    ; uses the complete geometric set.
    WinGet, winList, List,
    Loop, %winList%
    {
        hwndID := winList%A_Index%

        if (hwndID == refHwndID)
            continue

        edgeTouchCount    := "-"
        edgeGap           := "-"
        hasExposedArea    := "-"
        horizontalOverlap := "-"
        rejectReason      := ""
        sameMonitor       := True
        verticalOverlap   := "-"
        visiblePercent    := "-"
        visiblePercentBoundType := ""
        WinGetTitle, candidateTitle, ahk_id %hwndID%
        if (candidateTitle = "")
            candidateTitle := "<untitled window>"

        candidateTitle := StrReplace(candidateTitle, "`r", " ")
        candidateTitle := StrReplace(candidateTitle, "`n", " ")

        ; Keep the cheap exclusion checks first so obviously bad candidates do
        ; not reach the heavier geometry and visibility probes.
        if !IsAltTabWindow(hwndID)
            rejectReason := "not-alt-tab"

        if (rejectReason = "" && IsAlwaysOnTop(hwndID))
            rejectReason := "always-on-top"

        WinGet, mmState, MinMax, ahk_id %hwndID%
        if (rejectReason = "" && mmState <= -1)
            rejectReason := "minimized"

        if (rejectReason = "" && MonCount > 1) {
            sameMonitor := IsWindowOnMonNum(hwndID, monitorNum)
            if (!sameMonitor)
                rejectReason := "wrong-monitor"
        }

        if (rejectReason = "" && !WinGetPosEx(hwndID, candidateX, candidateY, candidateW, candidateH, null, null))
            rejectReason := "no-rect"

        if (rejectReason = "") {
            ; Require the candidate to feel anchored to the monitor rather than
            ; being an arbitrary floating window in the middle of the desktop.
            edgeTouchCount := _GetWindowMonitorEdgeTouchCount(hwndID, monitorNum)
            if (edgeTouchCount < minEdgesTouched)
                rejectReason := "edges=" edgeTouchCount
        }

        if (rejectReason = "") {
            candidateRightEdge  := candidateX + candidateW
            candidateBottomEdge := candidateY + candidateH
            horizontalOverlap   := Min(refRightEdge,   candidateRightEdge) - Max(refX, candidateX)
            verticalOverlap     := Min(refBottomEdge, candidateBottomEdge) - Max(refY, candidateY)

            ; candidateTargetEdge narrows the generic overlap check into the
            ; exact relationship needed for that resize direction. This core
            ; only accepts or rejects candidates; callers perform any ranking.
            if (candidateTargetEdge = "top") {
                ; Top-fit candidates must share enough left-to-right span with
                ; the dragged window to count as the window on its bottom side
                ; rather than an unrelated window off to the left or right.
                ; reject:hov in the debug output means this horizontal-overlap
                ; check failed.
                if (horizontalOverlap < minHorizontalOverlap)
                    rejectReason := "hov"
                else {
                    edgeGap := candidateY - refBottomEdge
                    if (edgeGap < -edgeTouchTolerance || edgeGap > edgeGapTolerance)
                        rejectReason := "gap=" edgeGap
                }
            }
            else if (candidateTargetEdge = "bottom") {
                if (horizontalOverlap < minHorizontalOverlap)
                    rejectReason := "hov"
                else {
                    edgeGap := refY - candidateBottomEdge
                    if (edgeGap < -edgeTouchTolerance || edgeGap > edgeGapTolerance)
                        rejectReason := "gap=" edgeGap
                }
            }
            else if (candidateTargetEdge = "left") {
                if (verticalOverlap < minVerticalOverlap)
                    rejectReason := "vov"
                else {
                    edgeGap := candidateX - refRightEdge
                    if (edgeGap < -edgeTouchTolerance || edgeGap > edgeGapTolerance)
                        rejectReason := "gap=" edgeGap
                }
            }
            else if (candidateTargetEdge = "right") {
                if (verticalOverlap < minVerticalOverlap)
                    rejectReason := "vov"
                else {
                    edgeGap := refX - candidateRightEdge
                    if (edgeGap < -edgeTouchTolerance || edgeGap > edgeGapTolerance)
                        rejectReason := "gap=" edgeGap
                }
            }
            else if (horizontalOverlap < minHorizontalOverlap && verticalOverlap < minVerticalOverlap)
                rejectReason := "overlap"
        }

        if (rejectReason = "") {
            ; Even if the candidate is valid geometrically, reject it unless a
            ; meaningful sampled percentage of it is still visible on screen.
            hasExposedArea := _HasVisibleExposedAreaWindow(hwndID, candidateX, candidateY, candidateW, candidateH, requiredVisiblePercent, visibilityGridSize, visiblePercent, visiblePercentBoundType)
            if !hasExposedArea
                rejectReason := "visible" ((visiblePercentBoundType = "max") ? "<=" : "=") Round(visiblePercent, 1) "%"
        }

        if (collectDebugTrace && debugLineCount < debugMaxLines) {
            ; Keep a short trace of the first few candidates so it is easy to
            ; see which filter stage disqualified each window while debugging.
            debugLineCount++
            if (rejectReason = "")
                candidateStatus := "MATCH"
                else
                candidateStatus := "reject:" rejectReason

            if (visiblePercent = "-")
                displayVisiblePercent := visiblePercent
            else if (visiblePercentBoundType = "min")
                displayVisiblePercent := ">=" Round(visiblePercent, 1) "%"
            else if (visiblePercentBoundType = "max")
                displayVisiblePercent := "<=" Round(visiblePercent, 1) "%"
            else
                displayVisiblePercent := Round(visiblePercent, 1) "%"
            result.debugText .= debugLineCount ". " candidateTitle " | edges=" edgeTouchCount " | hov=" horizontalOverlap " | vov=" verticalOverlap " | gap=" edgeGap " | visible=" displayVisiblePercent " | " candidateStatus "`n"
        }

        if (rejectReason != "")
            continue

        result.matches.Push(hwndID)
    }

    return result
}

; Hierarchy step 3: rank the visible adjacent candidates found in step 2.
; Return the best visible geometry match for the requested edge relationship.
; Prefer the nearest eligible lower-z-order window; if none qualifies, use the
; best higher-z-order match. Break equal z-order preference by the smallest
; absolute gap and then the largest overlap in the active dimension.
_FindBestVisibleEdgeTouchingWindow(refHwndID, monitorNum := 0, edgeTouchTolerance := 50, minEdgesTouched := 0, minHorizontalOverlap := 100, minVerticalOverlap := 100, candidateTargetEdge := "", edgeGapTolerance := 100, refX := "", refY := "", refW := "", refH := "", collectDebugTrace := false, requiredVisiblePercent := 20, visibilityGridSize := 5) {
    global lastDockPartnerSearchDebug

    scanResult := _FindVisibleEdgeTouchingWindowsCore(refHwndID, monitorNum, edgeTouchTolerance, minEdgesTouched, minHorizontalOverlap, minVerticalOverlap, candidateTargetEdge, edgeGapTolerance, refX, refY, refW, refH, collectDebugTrace, requiredVisiblePercent, visibilityGridSize)
    if (collectDebugTrace)
        lastDockPartnerSearchDebug := scanResult.debugText
    else
        lastDockPartnerSearchDebug := ""

    if (!scanResult.matches.MaxIndex())
        return 0

    if (refX = "" || refY = "" || refW = "" || refH = "") {
        if !WinGetPosEx(refHwndID, refX, refY, refW, refH, null, null)
            return 0
    }

    bestAbsGap         := ""
    bestHwndID         := 0
    bestLowerZDistance := ""
    bestOverlap        := ""
    refBottomEdge      := refY + refH
    refRightEdge       := refX + refW

    WinGet, winList, List,
    refZOrderIndex := 0
    zOrderIndexByHwnd := {}
    Loop, %winList%
    {
        hwndID := winList%A_Index%
        zOrderIndexByHwnd[hwndID] := A_Index
        if (hwndID = refHwndID)
            refZOrderIndex := A_Index
    }

    for _, candidateHwndID in scanResult.matches {
        if !WinGetPosEx(candidateHwndID, candidateX, candidateY, candidateW, candidateH, null, null)
            continue

        candidateBottomEdge := candidateY + candidateH
        candidateRightEdge  := candidateX + candidateW
        horizontalOverlap   := Min(refRightEdge, candidateRightEdge) - Max(refX, candidateX)
        verticalOverlap     := Min(refBottomEdge, candidateBottomEdge) - Max(refY, candidateY)

        if (candidateTargetEdge = "top") {
            edgeGap      := candidateY - refBottomEdge
            overlapScore := horizontalOverlap
        }
        else if (candidateTargetEdge = "bottom") {
            edgeGap      := refY - candidateBottomEdge
            overlapScore := horizontalOverlap
        }
        else if (candidateTargetEdge = "left") {
            edgeGap      := candidateX - refRightEdge
            overlapScore := verticalOverlap
        }
        else if (candidateTargetEdge = "right") {
            edgeGap      := refX - candidateRightEdge
            overlapScore := verticalOverlap
        }
        else {
            edgeGap      := 0
            overlapScore := Max(horizontalOverlap, verticalOverlap)
        }

        absGap := Abs(edgeGap)
        candidateZOrderIndex := zOrderIndexByHwnd.HasKey(candidateHwndID) ? zOrderIndexByHwnd[candidateHwndID] : 0
        candidateLowerZDistance := ""
        if (refZOrderIndex && candidateZOrderIndex > refZOrderIndex)
            candidateLowerZDistance := candidateZOrderIndex - refZOrderIndex

        if (   !bestHwndID
            || (candidateLowerZDistance != "" && bestLowerZDistance = "")
            || (candidateLowerZDistance != "" && bestLowerZDistance != "" && candidateLowerZDistance < bestLowerZDistance)
            || (candidateLowerZDistance = bestLowerZDistance && absGap < bestAbsGap)
            || (candidateLowerZDistance = bestLowerZDistance && absGap = bestAbsGap && overlapScore > bestOverlap))
        {
            bestAbsGap         := absGap
            bestHwndID         := candidateHwndID
            bestLowerZDistance := candidateLowerZDistance
            bestOverlap        := overlapScore
        }
    }

    return bestHwndID
}

; Compute the active-axis gap and overlap score for a candidate that already
; passed the visible edge-touching geometry filters.
_GetEdgeTouchingWindowScore(refX, refY, refW, refH, candidateHwndID, candidateTargetEdge, ByRef absGap, ByRef overlapScore) {
    if !WinGetPosEx(candidateHwndID, candidateX, candidateY, candidateW, candidateH, null, null)
        return false

    candidateBottomEdge := candidateY + candidateH
    candidateRightEdge  := candidateX + candidateW
    refBottomEdge       := refY + refH
    refRightEdge        := refX + refW
    horizontalOverlap   := Min(refRightEdge, candidateRightEdge) - Max(refX, candidateX)
    verticalOverlap     := Min(refBottomEdge, candidateBottomEdge) - Max(refY, candidateY)

    if (candidateTargetEdge = "top") {
        edgeGap      := candidateY - refBottomEdge
        overlapScore := horizontalOverlap
    }
    else if (candidateTargetEdge = "bottom") {
        edgeGap      := refY - candidateBottomEdge
        overlapScore := horizontalOverlap
    }
    else if (candidateTargetEdge = "left") {
        edgeGap      := candidateX - refRightEdge
        overlapScore := verticalOverlap
    }
    else if (candidateTargetEdge = "right") {
        edgeGap      := refX - candidateRightEdge
        overlapScore := verticalOverlap
    }
    else
        return false

    absGap := Abs(edgeGap)
    return true
}

; Hierarchy step 5: run only when no adjacent candidate survived steps 2-3.
; Return only the first docked window below the reference window in z-order
; that also overlaps the reference window on at least one axis.
; Unlike the edge-touching finders, this fallback helper does not require any
; directional edge-gap relationship or exposed visible area up front.
; The caller applies the per-axis edge-pair tolerance checks afterward.
_FindFirstDockedWindowBelowInZOrder(refHwndID, monitorNum := 0, minEdgesTouched := 2, collectDebugTrace := false) {
    global lastDockPartnerSearchDebug
    SysGet, MonCount, MonitorCount
    DetectHiddenWindows, Off

    if (!refHwndID)
        return 0

    if (!monitorNum)
        monitorNum := GetWindowMonitorNumber(refHwndID)

    if (monitorNum < 1)
        return 0

    if !WinGetPosEx(refHwndID, refX, refY, refW, refH, null, null)
        return 0

    refRightEdge  := refX + refW
    refBottomEdge := refY + refH

    debugLineCount := 0
    debugMaxLines  := 6
    debugText      := ""
    firstFound     := false

    WinGet, winList, List,
    Loop, %winList%
    {
        hwndID := winList%A_Index%

        if (!firstFound) {
            if (hwndID == refHwndID)
                firstFound := true
            continue
        }

        edgeTouchCount := "-"
        horizontalOverlap := "-"
        rejectReason   := ""
        sameMonitor    := True
        verticalOverlap := "-"
        WinGetTitle, candidateTitle, ahk_id %hwndID%
        if (candidateTitle = "")
            candidateTitle := "<untitled window>"

        candidateTitle := StrReplace(candidateTitle, "`r", " ")
        candidateTitle := StrReplace(candidateTitle, "`n", " ")

        if !IsAltTabWindow(hwndID)
            rejectReason := "not-alt-tab"

        if (rejectReason = "" && IsAlwaysOnTop(hwndID))
            rejectReason := "always-on-top"

        WinGet, mmState, MinMax, ahk_id %hwndID%
        if (rejectReason = "" && mmState <= -1)
            rejectReason := "minimized"

        if (rejectReason = "" && MonCount > 1) {
            sameMonitor := IsWindowOnMonNum(hwndID, monitorNum)
            if (!sameMonitor)
                rejectReason := "wrong-monitor"
        }

        if (rejectReason = "" && !WinGetPosEx(hwndID, candidateX, candidateY, candidateW, candidateH, null, null))
            rejectReason := "no-rect"

        if (rejectReason = "") {
            candidateRightEdge := candidateX + candidateW
            candidateBottomEdge := candidateY + candidateH
            horizontalOverlap := Min(refRightEdge, candidateRightEdge) - Max(refX, candidateX)
            verticalOverlap := Min(refBottomEdge, candidateBottomEdge) - Max(refY, candidateY)
            if (horizontalOverlap <= 0 && verticalOverlap <= 0)
                rejectReason := "overlap"
        }

        if (rejectReason = "") {
            edgeTouchCount := _GetWindowMonitorEdgeTouchCount(hwndID, monitorNum)
            if (edgeTouchCount < minEdgesTouched)
                rejectReason := "edges=" edgeTouchCount
        }

        if (collectDebugTrace && debugLineCount < debugMaxLines) {
            debugLineCount++
            if (rejectReason = "")
                candidateStatus := "MATCH"
            else
                candidateStatus := "reject:" rejectReason

            debugText .= debugLineCount ". " candidateTitle " | edges=" edgeTouchCount " | hov=" horizontalOverlap " | vov=" verticalOverlap " | " candidateStatus "`n"
        }

        if (rejectReason != "")
            continue

        lastDockPartnerSearchDebug := collectDebugTrace ? debugText : ""
        return hwndID
    }

    lastDockPartnerSearchDebug := collectDebugTrace ? debugText : ""
    return 0
}

; Collect every visible 2D edge-partner candidate that passes the same geometry
; and visibility checks, without restricting the candidate pool by z-order.
Find2DEdgePartnerWindows(refHwndID, monitorNum := 0, edgeTouchTolerance := 50, minEdgesTouched := 2, minHorizontalOverlap := 100, minVerticalOverlap := 100, candidateTargetEdge := "", edgeGapTolerance := 100, refX := "", refY := "", refW := "", refH := "", requiredVisiblePercent := 20, visibilityGridSize := 5) {
    scanResult := _FindVisibleEdgeTouchingWindowsCore(refHwndID, monitorNum, edgeTouchTolerance, minEdgesTouched, minHorizontalOverlap, minVerticalOverlap, candidateTargetEdge, edgeGapTolerance, refX, refY, refW, refH, false, requiredVisiblePercent, visibilityGridSize)
    return scanResult.matches
}

RemoveToolTip:
    ToolTip,
return

; User drags/moves a window
        ; |
        ; v
;    Release mouse
        ; |
        ; v
; 📌 In every case, `minEdgesTouched` applies to the **`[candidate]`** window only, never the `[moved/reference]` window.

; ```text
; LEGEND
; - [moved/reference] = the window being released and evaluated for fitting
; - [candidate]       = the other window being tested as a possible fit partner
; - minEdgesTouched   = how many monitor/work-area edges the [candidate] must touch
; - ASCII "gap"       = the measured edge-to-edge distance between [moved/reference]
;                       and [candidate] on the active fit axis
; - active fit axis   = vertical for CASE 1 / CASE 2, horizontal for CASE 3 / CASE 4
;                       and CASE 3A / CASE 4A
; - edgeTouchTolerance = allowed edge overlap / near-touch tolerance
;                        for the ASCII "gap" when the windows slightly overlap
; - edgeGapTolerance   = allowed positive gap between the two windows
;                        in the ASCII "gap" space
; - candidateTargetEdge = which candidate edge forms that ASCII "gap" measurement:
;                         "top", "bottom", "left", or "right"

; FIT-PARTNER SELECTION HIERARCHY
; 1. Continue only if the released [moved/reference] window touches at least one
;    monitor work-area edge within strictDockEdgeTolerance.
; 2. Search the applicable axes for visible adjacent [candidate] windows that
;    satisfy that CASE's monitor-edge, overlap, and edge-gap requirements.
; 3. Rank candidates within each adjacent search: prefer the nearest eligible
;    lower-z-order window; if none qualifies, use the best higher-z-order match;
;    then prefer the smallest absolute gap and largest active-axis overlap.
; 4. Apply the selected adjacent vertical and horizontal fits independently.
;    Finding either adjacent partner prevents the CASE 5 fallback.
; 5. Only when neither adjacent search found a partner, inspect the first docked
;    lower-z-order window that overlaps [moved/reference] on at least one axis.
; 6. Treat that CASE 5 window only as a size template: copy width and/or height
;    only when the corresponding released edge pairs already align within
;    edgeTouchTolerance.
;
; The numbered references beside the implementation below connect each branch
; to this hierarchy; the CASE sections retain the branch-specific geometry.


; CASE 1: Top-docked window looking downward for a vertical fit partner
; minEdgesTouched applies to: [candidate]
; Required here: minEdgesTouched = 2

; Primary vertical fit monitor work area
; +--------------------------------------------------------------+
; | |   [moved/reference]  |                                     |
; | |                      |                                     |
; | |                      |                                     |
; | +----------------------+  ref bottom edge                    |
; |            |                                                 |
; |            | edgeGap / overlap check                         |
; |            v                                                 |
; | +----------------------+                                     |
; | |     [candidate]      |  must touch at least 2 monitor edges
; | +----------------------+                                     |
; +--------------------------------------------------------------+
;
; Separate side-partner check for this same top-docked release:
; minEdgesTouched applies to: [side candidate]
; Required here: minEdgesTouched = 1
; +--------------------------------------------------------------+
; | |                      |    gap    +----------------------+  |
; | |   [moved/reference]  |<--------->|   [side candidate]   |  |
; | |                      |           |                      |  |
; | +----------------------+           +----------------------+  |
; |                                      must touch at least 1   |
; |                                      monitor edge            |
; +--------------------------------------------------------------+

; Checks:
; - candidateTargetEdge = "top"
; - minHorizontalOverlap must pass
; - ASCII "gap" here means candidate top edge minus moved bottom edge
; - edgeGap must be within:
; - overlap side: edgeTouchTolerance
; - gap side: edgeGapTolerance
; - [candidate] must touch at least 2 monitor edges
; - Being near the left/right monitor edge alone does NOT trigger resize-to-monitor-edge
; - A separate left/right side-partner check can still apply horizontal fitting
; - CASE 1 side-partner result for a top-only release: move-first, resize only on monitor overflow
; - CASE 1 corner-docked mirrored side-fit result: keep the dropped left/right side fixed and move the opposite side to the partner edge
; - Otherwise, the window must already count as left-docked or right-docked within strictDockEdgeTolerance for monitor-edge width fitting to apply


; CASE 2: Bottom-docked window looking upward for a vertical fit partner
; minEdgesTouched applies to: [candidate]
; Required here: minEdgesTouched = 2

; Primary vertical fit monitor work area
; +--------------------------------------------------------------+
; | +----------------------+                                     |
; | |     [candidate]      |  must touch at least 2 monitor edges
; | +----------------------+                                     |
; |            ^                                                 |
; |            | edgeGap / overlap check                         |
; |            |                                                 |
; | +----------------------+  ref top edge                       |
; | |                      |                                     |
; | | [moved/reference]    |                                     |
; | |                      |                                     |
; +--------------------------------------------------------------+
;
; Separate side-partner check for this same bottom-docked release:
; minEdgesTouched applies to: [side candidate]
; Required here: minEdgesTouched = 1
; +--------------------------------------------------------------+
; | +----------------------+    gap                              |
; | |   [side candidate]   |<--------->+----------------------+  |
; | |                      |           |   [moved/reference]  |  |
; | +----------------------+           |                      |  |
; | must touch at least 1              |                      |  |
; | monitor edge                       |                      |  |
; +--------------------------------------------------------------+

; Checks:
; - candidateTargetEdge = "bottom"
; - minHorizontalOverlap must pass
; - ASCII "gap" here means moved top edge minus candidate bottom edge
; - edgeGap must be within:
; - overlap side: edgeTouchTolerance
; - gap side: edgeGapTolerance
; - [candidate] must touch at least 2 monitor edges
; - Being near the left/right monitor edge alone does NOT trigger resize-to-monitor-edge
; - A separate left/right side-partner check can still apply horizontal fitting
; - CASE 2 side-partner result for a bottom-only release: move-first, resize only on monitor overflow
; - CASE 2 corner-docked mirrored side-fit result: keep the dropped left/right side fixed and move the opposite side to the partner edge
; - Otherwise, the window must already count as left-docked or right-docked within strictDockEdgeTolerance for monitor-edge width fitting to apply


; CASE 3: Left-docked window looking rightward for a normal side fit partner
; minEdgesTouched applies to: [candidate]
; Required here: minEdgesTouched = 1

; Monitor work area
; +--------------------------------------------------------------+
; |---------------+            gap           +-----------------+ |
; |  [moved/ref]  |<--- vertical overlap --->|                 | |
; |               |                          |   [candidate]   | |
; |---------------+                          +-----------------+ |
; |                        must touch at least 1 monitor edge    |
; +--------------------------------------------------------------+

; Checks:
; - candidateTargetEdge = "left"
; - minVerticalOverlap must pass
; - ASCII "gap" here means candidate left edge minus moved right edge
; - edgeGap must be within:
; - overlap side: edgeTouchTolerance
; - gap side: edgeGapTolerance
; - [candidate] must touch at least 1 monitor edge
; - normal result: resize to fit


; CASE 3A: Full-height window, not left-docked, looking rightward for side fit
; minEdgesTouched applies to: [candidate]
; Required here: minEdgesTouched = 1

; Monitor work area
; +--------------------------------------------------------------+
; | [moved/reference is full-height: touches top and bottom]     |
; | +---------------+            gap         +--------------+    |
; | |               |<-- vertical overlap -->| [candidate]   |   |
; | | [moved/ref]   |                        +---------------+   |
; | |               |                        must touch at least |
; | +---------------+                         1 monitor edge     |
; +--------------------------------------------------------------+

; Move-first behavior:
; 1. Find the side [candidate]
; 2. If [moved/reference] is NOT already left-docked to the monitor,
   ; shift the whole moved window right/left so its right edge becomes
   ; flush with the candidate's left edge
; 3. If that shift would push any part off-monitor, fall back to resize

; Checks:
; - candidateTargetEdge = "left"
; - minVerticalOverlap must pass
; - ASCII "gap" here means candidate left edge minus moved right edge
; - edgeGap must be within:
; - overlap side: edgeTouchTolerance
; - gap side: edgeGapTolerance
; - [candidate] must touch at least 1 monitor edge
; - special result: move-only first, resize only on monitor overflow


; CASE 4: Right-docked window looking leftward for a normal side fit partner
; minEdgesTouched applies to: [candidate]
; Required here: minEdgesTouched = 1

; Monitor work area
; +--------------------------------------------------------------+
; | +---------------+          gap               +---------------|
; | | [candidate]   |<---- vertical overlap ---->|               |
; | |               |                            | [moved/ref]   |
; | +---------------+                            +---------------|
; | must touch at least 1 monitor edge                           |
; +--------------------------------------------------------------+

; Checks:
; - candidateTargetEdge = "right"
; - minVerticalOverlap must pass
; - ASCII "gap" here means moved left edge minus candidate right edge
; - edgeGap must be within:
; - overlap side: edgeTouchTolerance
; - gap side: edgeGapTolerance
; - [candidate] must touch at least 1 monitor edge
; - normal result: resize to fit


; CASE 4A: Full-height window, not right-docked, looking leftward for side fit
; minEdgesTouched applies to: [candidate]
; Required here: minEdgesTouched = 1

; Monitor work area
; +--------------------------------------------------------------+
; | [moved/reference is full-height: touches top and bottom]     |
; | +---------------+            gap          +---------------+  |
; | | [candidate]   |<-- vertical overlap --> |               |  |
; | +---------------+                         | [moved/ref]   |  |
; | must touch at least 1 monitor edge        +---------------+  |
; +--------------------------------------------------------------+

; Move-first behavior:
; 1. Find the side [candidate]
; 2. If [moved/reference] is NOT already right-docked to the monitor,
   ; shift the whole moved window so its left edge becomes flush with
   ; the candidate's right edge
; 3. If that shift would push any part off-monitor, fall back to resize

; Checks:
; - candidateTargetEdge = "right"
; - minVerticalOverlap must pass
; - ASCII "gap" here means moved left edge minus candidate right edge
; - edgeGap must be within:
; - overlap side: edgeTouchTolerance
; - gap side: edgeGapTolerance
; - [candidate] must touch at least 1 monitor edge
; - special result: move-only first, resize only on monitor overflow


; CASE 5: Z-order fallback template match (hierarchy steps 5-6)
; minEdgesTouched applies to: [candidate fallback window]
; Required here: minEdgesTouched = 2

; This path is different from the adjacent side/top/bottom partner scan.

; Monitor work area
; +--------------------------------------------------------------+
; | [moved/reference]                                            |
; |                                                              |
; | [candidate fallback window below in z-order]                 |
; | must touch at least 2 monitor edges                          |
; +--------------------------------------------------------------+

; Checks:
; 1. Scan downward in z-order for the first docked [candidate]
; 2. [candidate] must touch at least 2 monitor edges
; 3. Then compare released edge alignment using edgeTouchTolerance
; 4. If those edge pairs are already close enough, copy that size
; ```
FitMovedWindowAgainstOthers(movedHwndID, monitorNum := 0, edgeGapTolerance := 100, edgeTouchTolerance := 50, collectDebugTrace := false) {
    global lastDockPartnerSearchDebug
    if (!movedHwndID)
        return false

    if (!monitorNum)
        monitorNum := MWAGetMonitorMouseIsIn()

    ; Use the monitor work area so "touching the edge" means touching the usable
    ; desktop edge rather than the monitor's raw pixel bounds.
    SysGet, monInfo, MonitorWorkArea, %monitorNum%

    if !WinGetPosEx(movedHwndID, movedX, movedY, movedW, movedH, movedOffsetX, movedOffsetY)
        return false

    ; Hierarchy step 1: only try to auto-fit when the moved window looks intentionally
    ; docked to the left, right, top, or bottom edge of the current monitor.
    strictDockEdgeTolerance    := 3
    ; Released right edge of the moved window.
    c_movedRightEdge           := movedX + movedW
    ; Released bottom edge of the moved window.
    c_movedBottomEdge          := movedY + movedH
    ; True when the released left edge counts as docked to the monitor work area.
    movedDocksToLeft           := Abs(movedX          - monInfoLeft)   <= strictDockEdgeTolerance
    ; True when the released right edge counts as docked to the monitor work area.
    movedDocksToRight          := Abs(c_movedRightEdge  - monInfoRight)  <= strictDockEdgeTolerance
    ; True when the released top edge counts as docked to the monitor work area.
    movedDocksToTop            := Abs(movedY          - monInfoTop)    <= strictDockEdgeTolerance
    ; True when the released bottom edge counts as docked to the monitor work area.
    movedDocksToBottom         := Abs(c_movedBottomEdge - monInfoBottom) <= strictDockEdgeTolerance
    ; True when the moved window spans the monitor's full work-area height.
    isFullHeightWindow         := _IsFullMonitorHeightWindow(movedHwndID, monitorNum)
    ; True when the moved window is docked to both left and right monitor edges.
    isFullWidthWindow          := (movedDocksToLeft && movedDocksToRight)
    ; Selects the CASE 3A / CASE 4A special full-height side-fit branch.
    fullHeightSideFitMode      := (isFullHeightWindow && !isFullWidthWindow)
    ; Selects the CASE 1 / CASE 2 move-first side-fit branch for top-only or
    ; bottom-only releases that are not also left/right-docked.
    topBottomOnlySideMoveMode  := (!isFullHeightWindow && (movedDocksToTop || movedDocksToBottom) && !movedDocksToLeft && !movedDocksToRight)

    ; Preserve the release-time geometry so each candidate search evaluates the
    ; same original dropped position, even if the first fit branch already moved
    ; or resized the live window.
    c_originalMovedH := movedH
    c_originalMovedW := movedW

    if (!movedDocksToLeft && !movedDocksToRight && !movedDocksToTop && !movedDocksToBottom)
        return false

    ; Chosen horizontal adjacent-fit partner window ID.
    adjacentSideHwndID                   := 0
    ; Chosen vertical adjacent-fit partner window ID.
    adjacentVerticalHwndID               := 0
    ; True once any fit action actually moved or resized the window.
    didFitWindow                         := false
    ; True once a horizontal side fit succeeded.
    didSideFit                           := false
    ; True once a vertical top/bottom fit succeeded.
    didVerticalFit                       := false
    ; True when Phase 1 found any adjacent partner before CASE 5 fallback.
    didFindAdjacentPartner               := false
    ; First docked lower-z-order window chosen for CASE 5 template matching.
    fallbackTemplateHwndID               := 0
    ; Accumulated debug text describing candidate-search results.
    fitDebugText                         := ""
    ; Candidate edge that must face the moved window on the horizontal axis.
    horizontalPartnerEdgeToMatch         := ""
    ; Debug label for the active horizontal fit branch.
    sideFitLabel                         := ""
    ; True when the horizontal fit keeps the dropped left/right side fixed
    ; while moving the opposite side to the chosen partner edge.
    sideFitAnchorsDroppedLeftOrRightSide := false
    ; Move-first X position to try before falling back to resize.
    sideMoveOnlyTargetX                  := ""
    ; Cached bottom edge of the chosen side partner.
    c_sidePartnerBottomEdge              := ""
    ; Cached height of the chosen side partner.
    c_sidePartnerH                       := ""
    ; Cached Y position of the chosen side partner.
    c_sidePartnerY                       := ""
    ; True when a move-first side fit succeeded and later resize fallback
    ; should be skipped.
    usedSideMoveOnlyFit                  := false
    ; Candidate edge that must face the moved window on the vertical axis.
    verticalPartnerEdgeToMatch           := ""
    ; True when the vertical fit keeps the dropped top/bottom side fixed
    ; while moving the opposite side to the chosen partner edge.
    verticalFitUsesReleasedOuterEdge     := false
    ; Cached right edge of the chosen vertical partner.
    c_verticalPartnerRightEdge           := ""
    ; Cached width of the chosen vertical partner.
    c_verticalPartnerW                   := ""
    ; Cached X position of the chosen vertical partner.
    c_verticalPartnerX                   := ""

    ; Resolve candidate directions first so the adjacent phase can inspect both
    ; axes before deciding whether the lower-z-order docked fallback is needed.
    ; CASE 1 / CASE 2 selector:
    ; vertical adjacent-fit path for top-docked or bottom-docked moved windows.
    if (!fullHeightSideFitMode) {
        if (movedDocksToTop)
            verticalPartnerEdgeToMatch := "top"
        else if (movedDocksToBottom)
            verticalPartnerEdgeToMatch := "bottom"
    }

    ; CASE 3 / CASE 4 selector:
    ; normal left-docked or right-docked side-fit path.
    if (!fullHeightSideFitMode) {
        if (movedDocksToLeft) {
            horizontalPartnerEdgeToMatch := "left"
            sideFitLabel                 := "Left-edge"
        }
        else if (movedDocksToRight) {
            horizontalPartnerEdgeToMatch := "right"
            sideFitLabel                 := "Right-edge"
        }
    }

    ; Hierarchy steps 2-3 / Phase 1: find adjacent visible windows by geometry,
    ; then rank the qualifying candidates. The selector strings identify which
    ; partner edge must face the moved window
    ; on that axis. Candidates must still touch the required monitor edges for
    ; that branch, then satisfy the normal overlap and edge-gap tolerances for
    ; that direction.
    ; If the moved window touches only one monitor axis, the mirrored CASE 1 /
    ; CASE 2 branch on the other axis can still fit against a partner.
    ; Top-only/bottom-only releases use move-first there, while corner-docked
    ; releases keep the dropped left/right side fixed and move the opposite
    ; side to that partner edge.
    ; CASE 1 / CASE 2:
    ; top-docked or bottom-docked moved window searches for one vertical partner.
    if (verticalPartnerEdgeToMatch != "") {
        adjacentVerticalHwndID := _FindBestVisibleEdgeTouchingWindow(movedHwndID, monitorNum, edgeTouchTolerance, 2, 100, 100, verticalPartnerEdgeToMatch, edgeGapTolerance, movedX, movedY, movedW, movedH, collectDebugTrace)
        if (collectDebugTrace) {
            if (verticalPartnerEdgeToMatch = "top")
                verticalDebugText := "Top-edge adjacent fit candidate:`n" lastDockPartnerSearchDebug
            else
                verticalDebugText := "Bottom-edge adjacent fit candidate:`n" lastDockPartnerSearchDebug
            fitDebugText := verticalDebugText
        }
    }
    else if ((movedDocksToLeft || movedDocksToRight) && !fullHeightSideFitMode) {
        topSideCandidateHwndID    := _FindBestVisibleEdgeTouchingWindow(movedHwndID, monitorNum, edgeTouchTolerance, 1, 60, 60, "bottom", edgeGapTolerance, movedX, movedY, c_originalMovedW, c_originalMovedH, collectDebugTrace)
        if (collectDebugTrace)
            topSideDebugText := "Top-side adjacent fit candidate:`n" lastDockPartnerSearchDebug
        else
            topSideDebugText := ""

        bottomSideCandidateHwndID := _FindBestVisibleEdgeTouchingWindow(movedHwndID, monitorNum, edgeTouchTolerance, 1, 60, 60, "top", edgeGapTolerance, movedX, movedY, c_originalMovedW, c_originalMovedH, collectDebugTrace)
        if (collectDebugTrace)
            bottomSideDebugText := "Bottom-side adjacent fit candidate:`n" lastDockPartnerSearchDebug
        else
            bottomSideDebugText := ""

        bottomSideGap := ""
        bottomSideOverlap := ""
        topSideGap := ""
        topSideOverlap := ""

        if (topSideCandidateHwndID)
            _GetEdgeTouchingWindowScore(movedX, movedY, c_originalMovedW, c_originalMovedH, topSideCandidateHwndID, "bottom", topSideGap, topSideOverlap)
        if (bottomSideCandidateHwndID)
            _GetEdgeTouchingWindowScore(movedX, movedY, c_originalMovedW, c_originalMovedH, bottomSideCandidateHwndID, "top", bottomSideGap, bottomSideOverlap)

        if (topSideCandidateHwndID && bottomSideCandidateHwndID) {
            if (topSideGap < bottomSideGap || (topSideGap = bottomSideGap && topSideOverlap >= bottomSideOverlap)) {
                adjacentVerticalHwndID           := topSideCandidateHwndID
                verticalFitUsesReleasedOuterEdge := true
                verticalPartnerEdgeToMatch       := "bottom"
            }
            else {
                adjacentVerticalHwndID           := bottomSideCandidateHwndID
                verticalFitUsesReleasedOuterEdge := true
                verticalPartnerEdgeToMatch       := "top"
            }
        }
        else if (topSideCandidateHwndID) {
            adjacentVerticalHwndID           := topSideCandidateHwndID
            verticalFitUsesReleasedOuterEdge := true
            verticalPartnerEdgeToMatch       := "bottom"
        }
        else if (bottomSideCandidateHwndID) {
            adjacentVerticalHwndID           := bottomSideCandidateHwndID
            verticalFitUsesReleasedOuterEdge := true
            verticalPartnerEdgeToMatch       := "top"
        }

        if (collectDebugTrace) {
            if (fitDebugText = "")
                fitDebugText := topSideDebugText
            else if (topSideDebugText != "")
                fitDebugText .= "`n`n" topSideDebugText

            if (fitDebugText = "")
                fitDebugText := bottomSideDebugText
            else if (bottomSideDebugText != "")
                fitDebugText .= "`n`n" bottomSideDebugText
        }
    }

    ; CASE 3 / CASE 4:
    ; normal left-docked or right-docked moved window searches for one side partner.
    if (horizontalPartnerEdgeToMatch != "") {
        adjacentSideHwndID := _FindBestVisibleEdgeTouchingWindow(movedHwndID, monitorNum, edgeTouchTolerance, 1, 100, 100, horizontalPartnerEdgeToMatch, edgeGapTolerance, movedX, movedY, c_originalMovedW, c_originalMovedH, collectDebugTrace)
        if (collectDebugTrace) {
            sideDebugText := sideFitLabel " adjacent fit candidate:`n" lastDockPartnerSearchDebug
            if (fitDebugText = "")
                fitDebugText := sideDebugText
            else
                fitDebugText .= "`n`n" sideDebugText
        }
    }
    ; CASE 3A / CASE 4A:
    ; full-height moved window probes both side candidates first, then either
    ; shifts the whole window or falls back to resize on monitor overflow.
    else if (fullHeightSideFitMode) {
        minHorizontalOverlap := 60
        minVerticalOverlap   := 60
        l_edgeGapTolerance   := 50
        l_edgeTouchTolerance := 50

        leftSideCandidateHwndID  := _FindBestVisibleEdgeTouchingWindow(movedHwndID, monitorNum, l_edgeTouchTolerance, 1, minHorizontalOverlap, minVerticalOverlap, "right", l_edgeGapTolerance, movedX, movedY, c_originalMovedW, c_originalMovedH, collectDebugTrace)
        if (collectDebugTrace)
            leftSideDebugText := "Full-height left-side adjacent fit candidate:`n" lastDockPartnerSearchDebug
        else
            leftSideDebugText := ""

        rightSideCandidateHwndID := _FindBestVisibleEdgeTouchingWindow(movedHwndID, monitorNum, l_edgeTouchTolerance, 1, minHorizontalOverlap, minVerticalOverlap,  "left", l_edgeGapTolerance, movedX, movedY, c_originalMovedW, c_originalMovedH, collectDebugTrace)
        if (collectDebugTrace)
            rightSideDebugText := "Full-height right-side adjacent fit candidate:`n" lastDockPartnerSearchDebug
        else
            rightSideDebugText := ""

        leftSideGap := ""
        leftSideOverlap := ""
        rightSideGap := ""
        rightSideOverlap := ""

        if (leftSideCandidateHwndID)
            _GetEdgeTouchingWindowScore(movedX, movedY, c_originalMovedW, c_originalMovedH, leftSideCandidateHwndID, "right", leftSideGap, leftSideOverlap)
        if (rightSideCandidateHwndID)
            _GetEdgeTouchingWindowScore(movedX, movedY, c_originalMovedW, c_originalMovedH, rightSideCandidateHwndID, "left", rightSideGap, rightSideOverlap)

        if (leftSideCandidateHwndID && rightSideCandidateHwndID) {
            if (leftSideGap < rightSideGap || (leftSideGap = rightSideGap && leftSideOverlap >= rightSideOverlap)) {
                adjacentSideHwndID           := leftSideCandidateHwndID
                horizontalPartnerEdgeToMatch := "right"
                sideFitLabel                 := "Full-height left-side"
            }
            else {
                adjacentSideHwndID           := rightSideCandidateHwndID
                horizontalPartnerEdgeToMatch := "left"
                sideFitLabel                 := "Full-height right-side"
            }
        }
        else if (leftSideCandidateHwndID) {
            adjacentSideHwndID           := leftSideCandidateHwndID
            horizontalPartnerEdgeToMatch := "right"
            sideFitLabel                 := "Full-height left-side"
        }
        else if (rightSideCandidateHwndID) {
            adjacentSideHwndID           := rightSideCandidateHwndID
            horizontalPartnerEdgeToMatch := "left"
            sideFitLabel                 := "Full-height right-side"
        }

        if (collectDebugTrace) {
            if (fitDebugText = "")
                fitDebugText := leftSideDebugText
            else if (leftSideDebugText != "")
                fitDebugText .= "`n`n" leftSideDebugText

            if (fitDebugText = "")
                fitDebugText := rightSideDebugText
            else if (rightSideDebugText != "")
                fitDebugText .= "`n`n" rightSideDebugText
        }
    }
    else if (movedDocksToTop || movedDocksToBottom) {
        leftSideCandidateHwndID  := _FindBestVisibleEdgeTouchingWindow(movedHwndID, monitorNum, edgeTouchTolerance, 1, 60, 60, "right", edgeGapTolerance, movedX, movedY, c_originalMovedW, c_originalMovedH, collectDebugTrace)
        if (collectDebugTrace)
            leftSideDebugText := "Left-side adjacent fit candidate:`n" lastDockPartnerSearchDebug
        else
            leftSideDebugText := ""

        rightSideCandidateHwndID := _FindBestVisibleEdgeTouchingWindow(movedHwndID, monitorNum, edgeTouchTolerance, 1, 60, 60, "left", edgeGapTolerance, movedX, movedY, c_originalMovedW, c_originalMovedH, collectDebugTrace)
        if (collectDebugTrace)
            rightSideDebugText := "Right-side adjacent fit candidate:`n" lastDockPartnerSearchDebug
        else
            rightSideDebugText := ""

        leftSideGap := ""
        leftSideOverlap := ""
        rightSideGap := ""
        rightSideOverlap := ""

        if (leftSideCandidateHwndID)
            _GetEdgeTouchingWindowScore(movedX, movedY, c_originalMovedW, c_originalMovedH, leftSideCandidateHwndID, "right", leftSideGap, leftSideOverlap)
        if (rightSideCandidateHwndID)
            _GetEdgeTouchingWindowScore(movedX, movedY, c_originalMovedW, c_originalMovedH, rightSideCandidateHwndID, "left", rightSideGap, rightSideOverlap)

        if (leftSideCandidateHwndID && rightSideCandidateHwndID) {
            if (leftSideGap < rightSideGap || (leftSideGap = rightSideGap && leftSideOverlap >= rightSideOverlap)) {
                adjacentSideHwndID           := leftSideCandidateHwndID
                horizontalPartnerEdgeToMatch := "right"
                sideFitLabel                 := "Left-side"
                sideFitAnchorsDroppedLeftOrRightSide := true
            }
            else {
                adjacentSideHwndID           := rightSideCandidateHwndID
                horizontalPartnerEdgeToMatch := "left"
                sideFitLabel                 := "Right-side"
                sideFitAnchorsDroppedLeftOrRightSide := true
            }
        }
        else if (leftSideCandidateHwndID) {
            adjacentSideHwndID          := leftSideCandidateHwndID
            horizontalPartnerEdgeToMatch := "right"
            sideFitLabel                 := "Left-side"
            sideFitAnchorsDroppedLeftOrRightSide := true
        }
        else if (rightSideCandidateHwndID) {
            adjacentSideHwndID           := rightSideCandidateHwndID
            horizontalPartnerEdgeToMatch := "left"
            sideFitLabel                 := "Right-side"
            sideFitAnchorsDroppedLeftOrRightSide := true
        }

        if (collectDebugTrace) {
            if (fitDebugText = "")
                fitDebugText := leftSideDebugText
            else if (leftSideDebugText != "")
                fitDebugText .= "`n`n" leftSideDebugText

            if (fitDebugText = "")
                fitDebugText := rightSideDebugText
            else if (rightSideDebugText != "")
                fitDebugText .= "`n`n" rightSideDebugText
        }
    }

    didFindAdjacentPartner := (adjacentVerticalHwndID || adjacentSideHwndID)

    ; Hierarchy step 5 / Phase 2: only if no adjacent partner qualified on either
    ; axis, fall back to the first docked window below the moved window in z-order
    ; that overlaps the moved window on at least one axis. Only that one window is
    ; inspected, and it donates width and/or height only when the released
    ; window's corresponding edge pairs are already within tolerance.
    ; CASE 5:
    ; if no adjacent partner matched, inspect the first docked lower-z-order
    ; template window and only borrow width/height when edge pairs already align.
    if (!didFindAdjacentPartner) {
        fallbackTemplateHwndID := _FindFirstDockedWindowBelowInZOrder(movedHwndID, monitorNum, 2, collectDebugTrace)
        if (collectDebugTrace) {
            fallbackDebugText := "Lower-z-order docked fallback candidate:`n" lastDockPartnerSearchDebug
            if (fitDebugText = "")
                fitDebugText := fallbackDebugText
            else
                fitDebugText .= "`n`n" fallbackDebugText
        }
    }

    verticalHwndID := adjacentVerticalHwndID
    sideHwndID     := adjacentSideHwndID

    ; Hierarchy step 4: resolve and apply vertical fitting first. Top/bottom-docked
    ; windows span from the monitor edge to the opposing partner. Left/right-only
    ; windows use the mirrored special case: keep the dropped top/bottom side fixed
    ; while
    ; moving the opposite side to an above/below partner edge.
    if (!fullHeightSideFitMode && verticalHwndID && verticalHwndID != movedHwndID && WinGetPosEx(verticalHwndID, verticalWinX, verticalWinY, verticalWinW, verticalWinH, null, null)) {
        c_verticalPartnerRightEdge := verticalWinX + verticalWinW
        c_verticalPartnerW         := verticalWinW
        c_verticalPartnerX         := verticalWinX
        c_verticalWinBottomEdge    := verticalWinY + verticalWinH

        if (verticalFitUsesReleasedOuterEdge) {
            if (verticalPartnerEdgeToMatch = "top") {
                ; Left/right-docked moved window: keep its released top edge
                ; fixed and resize its bottom edge until it reaches the partner
                ; below it.
                targetTopEdge     := movedY
                targetBottomEdge  := verticalWinY
                targetOuterHeight := targetBottomEdge - targetTopEdge
            }
            else {
                ; Left/right-docked moved window: keep its released bottom edge
                ; fixed and move/resize its top edge until it reaches the
                ; partner above it.
                targetTopEdge     := c_verticalWinBottomEdge
                targetBottomEdge  := c_movedBottomEdge
                targetOuterHeight := targetBottomEdge - targetTopEdge
            }
        }
        else if (verticalPartnerEdgeToMatch = "top") {
            ; Top-docked moved window: place it at the monitor's visual top edge
            ; and size it down until its bottom edge lands flush against the
            ; bottom-side partner.
            targetTopEdge     := monInfoTop
            targetBottomEdge  := verticalWinY
            targetOuterHeight := targetBottomEdge - targetTopEdge
        }
        else {
            ; Bottom-docked moved window: place it at the partner's lower edge,
            ; then let it span down to the monitor bottom.
            targetTopEdge     := c_verticalWinBottomEdge
            targetBottomEdge  := monInfoBottom
            targetOuterHeight := targetBottomEdge - targetTopEdge
        }

        if (targetOuterHeight > 0) {
            targetMoveY      := targetTopEdge
            targetMoveHeight := targetOuterHeight + 2*Abs(movedOffsetY) + 1
            didVerticalFit   := true
            didFitWindow     := true
            WinMove, ahk_id %movedHwndID%, , , %targetMoveY%, , %targetMoveHeight%
            WaitForStableWindow(movedHwndID)
        }
    }

    ; Hierarchy step 4: side alignment is resolved independently so a corner-docked release can fit
    ; against one window vertically and another horizontally in the same pass.
    if (sideHwndID && sideHwndID != movedHwndID && WinGetPosEx(sideHwndID, sideWinX, sideWinY, sideWinW, sideWinH, null, null)) {
        c_sidePartnerBottomEdge := sideWinY + sideWinH
        c_sidePartnerH          := sideWinH
        c_sidePartnerY          := sideWinY
        c_sideRightEdge         := sideWinX + sideWinW

        if (sideFitAnchorsDroppedLeftOrRightSide && !topBottomOnlySideMoveMode) {
            if (horizontalPartnerEdgeToMatch = "left") {
                ; Top/bottom plus side-docked moved window: keep its released
                ; left edge fixed and resize its right edge until it reaches
                ; the partner.
                targetLeftEdge   := movedX
                targetOuterWidth := sideWinX - targetLeftEdge
            }
            else {
                ; Top/bottom plus side-docked moved window: keep its released
                ; right edge fixed and move/resize its left edge until it
                ; reaches the partner on the left side.
                targetLeftEdge   := c_sideRightEdge
                targetRightEdge  := c_movedRightEdge
                targetOuterWidth := targetRightEdge - targetLeftEdge
            }
        }
        else if (horizontalPartnerEdgeToMatch = "left") {
            ; CASE 3A / CASE 1 / CASE 2 right-side partner path:
            ; full-height windows keep the normal left-edge resize only when
            ; the released window was already intentionally left-docked.
            ; Otherwise, and for CASE 1 / CASE 2 top-only or bottom-only
            ; releases, preserve width and shift the whole window first.
            if (fullHeightSideFitMode || topBottomOnlySideMoveMode) {
                targetLeftEdge   := monInfoLeft
                targetOuterWidth := sideWinX - targetLeftEdge
                if (topBottomOnlySideMoveMode || !movedDocksToLeft)
                    sideMoveOnlyTargetX := sideWinX - movedW + movedOffsetX
            }
            else {
                ; Left-docked moved window: widen it from the monitor's left edge
                ; until it meets the candidate's left edge on the right side.
                targetLeftEdge   := monInfoLeft
                targetOuterWidth := sideWinX - targetLeftEdge
            }
        }
        else {
            if (fullHeightSideFitMode || topBottomOnlySideMoveMode) {
                ; CASE 4A / CASE 1 / CASE 2 left-side partner path:
                ; mirror the left-edge move-first rule for left-side partners.
                targetLeftEdge   := c_sideRightEdge
                targetRightEdge  := monInfoRight
                targetOuterWidth := targetRightEdge - targetLeftEdge
                if (topBottomOnlySideMoveMode || !movedDocksToRight)
                    sideMoveOnlyTargetX := c_sideRightEdge + movedOffsetX
            }
            else {
                ; Right-docked moved window: widen it from the candidate's right
                ; edge until it fully reaches the monitor's right edge.
                targetLeftEdge   := c_sideRightEdge
                targetRightEdge  := monInfoRight
                targetOuterWidth := targetRightEdge - targetLeftEdge
            }
        }

        ; CASE 3A / CASE 4A / CASE 1 / CASE 2 move-first verification:
        ; accept the shift only if the post-move window still stays on-monitor.
        if (sideMoveOnlyTargetX != "") {
            WinMove, ahk_id %movedHwndID%, , %sideMoveOnlyTargetX%
            WaitForStableWindow(movedHwndID)
            if (WinGetPosEx(movedHwndID, movedPostMoveX, movedPostMoveY, movedPostMoveW, movedPostMoveH, null, null)) {
                movedPostMoveRightEdge  := movedPostMoveX + movedPostMoveW
                if (   movedPostMoveX >= (monInfoLeft - strictDockEdgeTolerance)
                    && movedPostMoveRightEdge <= (monInfoRight + strictDockEdgeTolerance))
                {
                    usedSideMoveOnlyFit := true
                    didSideFit          := true
                    didFitWindow        := true
                }
            }
        }
        if (!usedSideMoveOnlyFit && targetOuterWidth > 0) {
            ; CASE 3A / CASE 4A / CASE 1 / CASE 2 resize fallback:
            ; Preserve the original non-client offset while expanding the moved
            ; window outward to its final fitted width.
            targetMoveX     := targetLeftEdge + movedOffsetX
            targetMoveWidth := targetOuterWidth + 2*Abs(movedOffsetX)
            didSideFit      := true
            WinMove, ahk_id %movedHwndID%, , %targetMoveX%, , %targetMoveWidth%
            didFitWindow := true
        }
    }

    ; Hierarchy step 6: if neither adjacent axis qualified, let the docked
    ; lower-z-order fallback candidate donate whichever dimensions are already
    ; nearly aligned with the released window. This treats the candidate as a size
    ; template rather than
    ; as an opposite boundary against the monitor edge.
    if (   !didFindAdjacentPartner
        && fallbackTemplateHwndID
        && fallbackTemplateHwndID != movedHwndID
        && WinGetPosEx(fallbackTemplateHwndID, fallbackWinX, fallbackWinY, fallbackWinW, fallbackWinH, null, null))
    {
        c_fallbackBottomEdge := fallbackWinY + fallbackWinH
        c_fallbackRightEdge  := fallbackWinX + fallbackWinW
        fallbackMatchHeight := (   !fullHeightSideFitMode
                                && Abs(movedY          - fallbackWinY)      <= edgeTouchTolerance
                                && Abs(c_movedBottomEdge - c_fallbackBottomEdge) <= edgeTouchTolerance)
        fallbackMatchWidth  := (   Abs(movedX           - fallbackWinX)       <= edgeTouchTolerance
                                && Abs(c_movedRightEdge - c_fallbackRightEdge) <= edgeTouchTolerance)

        if (fallbackMatchWidth || fallbackMatchHeight) {
            if (fallbackMatchWidth) {
                targetMoveX     := fallbackWinX + movedOffsetX
                targetMoveWidth := fallbackWinW + 2*Abs(movedOffsetX)
            }
            else {
                targetMoveX     := ""
                targetMoveWidth := ""
            }

            if (fallbackMatchHeight) {
                targetMoveY      := fallbackWinY
                targetMoveHeight := fallbackWinH + 2*Abs(movedOffsetY) + 1
            }
            else {
                targetMoveY      := ""
                targetMoveHeight := ""
            }

            WinMove, ahk_id %movedHwndID%, , %targetMoveX%, %targetMoveY%, %targetMoveWidth%, %targetMoveHeight%
            didFitWindow := true
        }
    }

    ; If a top/bottom fit succeeded but no left/right partner qualified, allow
    ; the moved window to inherit the vertical partner's width when both of its
    ; vertical edges were already nearly aligned with that partner at release.
    if (   didVerticalFit && !didSideFit
        && Abs(movedX             - c_verticalPartnerX)         <= edgeTouchTolerance
        && Abs(c_movedRightEdge   - c_verticalPartnerRightEdge) <= edgeTouchTolerance)
    {
        targetMoveX     := c_verticalPartnerX + movedOffsetX
        targetMoveWidth := c_verticalPartnerW + 2*Abs(movedOffsetX)
        if (targetMoveWidth > 0) {
            WinMove, ahk_id %movedHwndID%, , %targetMoveX%, , %targetMoveWidth%
            didFitWindow := true
        }
    }

    ; Mirror the top/bottom width-inheritance fallback for left/right fits. If a
    ; side fit succeeded but no separate vertical partner qualified, allow the
    ; moved window to inherit the side partner's height when both of its
    ; horizontal edges were already nearly aligned with that partner at release.
    if (   didSideFit && !didVerticalFit && !usedSideMoveOnlyFit && !fullHeightSideFitMode
        && Abs(movedY              - c_sidePartnerY)          <= edgeTouchTolerance
        && Abs(c_movedBottomEdge   - c_sidePartnerBottomEdge) <= edgeTouchTolerance)
    {
        targetMoveY      := c_sidePartnerY
        targetMoveHeight := c_sidePartnerH + 2*Abs(movedOffsetY) + 1
        if (targetMoveHeight > 0) {
            WinMove, ahk_id %movedHwndID%, , , %targetMoveY%, , %targetMoveHeight%
            didFitWindow := true
        }
    }

    if (fitDebugText != "") {
        lastDockPartnerSearchDebug := fitDebugText
        ToolTip, % lastDockPartnerSearchDebug
        SetTimer, RemoveToolTip, -5000
    }

    return didFitWindow
}

IsEditFieldActive() {
    ControlGetFocus, FocusedControl, A
    If (RegExMatch(FocusedControl, "^Edit\d+$"))
        Return True
    Else
        Return False
}
;-------------------------------------------------------------------------------
;-------------------------------------------------------------------------------

;------------------------------
;
; Function: WinGetPosEx
;
; Description:
;
;   Gets the position, size, and offset of a window. See the *Remarks* section
;   for more information.
;
; Parameters:
;
;   hWindow - Handle to the window.
;
;   X, Y, Width, Height - Output variables. [Optional] If defined, these
;       variables contain the coordinates of the window relative to the
;       upper-left corner of the screen (X and Y), and the Width and Height of
;       the window.
;
;   Offset_X, Offset_Y - Output variables. [Optional] Offset, in pixels, of the
;       actual position of the window versus the position of the window as
;       reported by GetWindowRect.  If mouseMoving the window to specific
;       coordinates, add these offset values to the appropriate coordinate
;       (X and/or Y) to reflect the true size of the window.
;
; Returns:
;
;   If successful, the address of a RECTPlus structure is returned.  The first
;   16 bytes contains a RECT structure that contains the dimensions of the
;   bounding rectangle of the specified window.  The dimensions are given in
;   screen coordinates that are relative to the upper-left corner of the screen.
;   The next 8 bytes contain the X and Y offsets (4-byte integer for X and
;   4-byte integer for Y).
;
;   Also if successful (and if defined), the output variables (X, Y, Width,
;   Height, Offset_X, and Offset_Y) are updated.  See the *Parameters* section
;   for more more information.
;
;   If not successful, FALSE is returned.
;
; Requirement:
;
;   Windows 2000+
;
; Remarks, Observations, and Changes:
;
; * Starting with Windows Vista, Microsoft includes the Desktop Window Manager
;   (DWM) along with Aero-based themes that use DWM.  Aero themes provide new
;   features like a translucent glass design with subtle window animations.
;   Unfortunately, the DWM doesn't always conform to the OS rules for size and
;   positioning of windows.  If using an Aero theme, many of the windows are
;   actually larger than reported by Windows when using standard commands (Ex:
;   WinGetPos, GetWindowRect, etc.) and because of that, are not positioned
;   correctly when using standard commands (Ex: gui Show, WinMove, etc.).  This
;   function was created to 1) identify the true position and size of all
;   windows regardless of the window attributes, desktop theme, or version of
;   Windows and to 2) identify the appropriate offset that is needed to position
;   the window if the window is a different size than reported.
;
; * The true size, position, and offset of a window cannot be determined until
;   the window has been rendered.  See the example script for an example of how
;   to use this function to position a new window.
;
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
         Else
            outputdebug,
               (ltrim join`s
                Function: %A_ThisFunc% -
                Unknown error calling "dwmapi\DwmGetWindowAttribute".
                RC=%DWMRC%,
                ErrorLevel=%ErrorLevel%,
                A_LastError=%A_LastError%.
                "GetWindowRect" used instead.
               )

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
    NumPut(Offset_X:=(Width-GWR_Width)//2,RECTPlus,16,"Int")
    NumPut(Offset_Y:=(Height-GWR_Height)//2,RECTPlus,20,"Int")
    Return &RECTPlus
}
;------------------------------------------------------------------------------
DynaRun(TempScript, pipename="")
{
   static ptrType:="Ptr", uintType:="uint", uintPointerType:="uint *"
   If pipename =
      name := "AHK" A_TickCount
   Else
      name := pipename

   __PIPE_GA_ := DllCall("CreateNamedPipe","str","\\.\pipe\" name,uintType,2,uintType,0,uintType,255,uintType,0,uintType,0,ptrType,0,ptrType,0)
   __PIPE_    := DllCall("CreateNamedPipe","str","\\.\pipe\" name,uintType,2,uintType,0,uintType,255,uintType,0,uintType,0,ptrType,0,ptrType,0)

   If (__PIPE_=-1 or __PIPE_GA_=-1)
      Return 0

   If A_IsCompiled
      Run, "%A_AhkPath%" /script "\\.\pipe\%name%",,UseErrorLevel HIDE, PID
   Else
      Run, %A_AhkPath% "\\.\pipe\%name%",,UseErrorLevel HIDE, PID

   If ErrorLevel
      MsgBox, 262144, ERROR,% "Could not open file:`n" __AHK_EXE_ """\\.\pipe\" name """"

   DllCall("ConnectNamedPipe",ptrType,__PIPE_GA_,ptrType,0)
   DllCall("CloseHandle",ptrType,__PIPE_GA_)
   DllCall("ConnectNamedPipe",ptrType,__PIPE_,ptrType,0)
   script := (A_IsUnicode ? chr(0xfeff) : (chr(239) . chr(187) . chr(191))) TempScript

   If !DllCall("WriteFile",ptrType,__PIPE_,"str",script,uintType,(StrLen(script)+1)*(A_IsUnicode ? 2 : 1),uintPointerType,0,ptrType,0)
        Return A_LastError,DllCall("CloseHandle",ptrType,__PIPE_)

   DllCall("CloseHandle",ptrType,__PIPE_)

   Return PID
}

MoveMouseToDefaultDialogButton(hwndDlg := "", moveSpeed := 0) {
    static BS_PUSHBUTTON     := 0x00000000
    static BS_DEFPUSHBUTTON  := 0x00000001
    static BS_SPLITBUTTON    := 0x0000000C
    static BS_DEFSPLITBUTTON := 0x0000000D
    static BS_COMMANDLINK    := 0x0000000E
    static BS_DEFCOMMANDLINK := 0x0000000F
    static BS_TYPEMASK       := 0x0000000F

    static DC_HASDEFID       := 0x534B
    static DM_GETDEFID       := 0x0400
    static GWL_STYLE         := -16
    static SMTO_ABORTIFHUNG  := 0x0002
    static WS_MAXIMIZEBOX    := 0x00010000
    static WS_MINIMIZEBOX    := 0x00020000

    ; If no dialog was supplied, target the current active window.
    if (!hwndDlg)
        WinGet, hwndDlg, ID, A

    if (!hwndDlg || !DllCall("user32\IsWindow", "Ptr", hwndDlg, "Int"))
        return 0

    ; This function is intentionally limited to classic Win32 dialog windows.
    if (GetClassName(hwndDlg) != "#32770")
        return 0

    dialogStyle := DllCall(A_PtrSize = 8 ? "user32\GetWindowLongPtrW" : "user32\GetWindowLongW"
        , "Ptr", hwndDlg
        , "Int", GWL_STYLE
        , "Ptr")

    ; Reject dialogs containing either a Minimize or Maximize caption button.
    if (dialogStyle & (WS_MINIMIZEBOX | WS_MAXIMIZEBOX))
        return 0

    btnHwnd       := 0
    firstButton   := 0
    msgResult     := 0
    defaultCtrlId := 0

    ; Ask the dialog manager which control currently owns the default-button role.
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

    ; First try the control ID returned by DM_GETDEFID.
    ; This is the most authoritative method for standard #32770 dialogs.
    if (defaultCtrlId) {
        h := DllCall("user32\GetDlgItem", "Ptr", hwndDlg, "Int", defaultCtrlId, "Ptr")

        if (IsUsableDialogPushButton(h)) {
            btnHwnd := h
        }
    }

    ; If DM_GETDEFID did not produce a usable hwnd, scan the child controls.
    ; This catches dialogs where the default style is visible but DM_GETDEFID fails.
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

            ; Remember the first real push-like button only as an internal reference.
            ; We do NOT automatically use it unless it is actually a default style.
            if (!firstButton)
                firstButton := h

            if (buttonType = BS_DEFPUSHBUTTON
             || buttonType = BS_DEFSPLITBUTTON
             || buttonType = BS_DEFCOMMANDLINK) {
                btnHwnd := h
                break
            }
        }
    }

    ; Safer behavior:
    ; If no actual default button was found, do not guess.
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

GetClassName(hwnd) {
    VarSetCapacity(className, 256 * 2, 0)

    len := DllCall("user32\GetClassNameW"
        , "Ptr", hwnd
        , "Ptr", &className
        , "Int", 256
        , "Int")

    if (!len)
        return ""

    return StrGet(&className, len, "UTF-16")
}

GetDialogBreadcrumbText(hwndDlg) {
    static cache := {}   ; hwndDlg -> toolbar hwnd
    tbHwnd := 0

    if (cache.HasKey(hwndDlg))
        tbHwnd := cache[hwndDlg]

    ; Read and validate the cached toolbar below. Rescan only when that handle is
    ; gone or its current direct/accessibility text no longer identifies a path.
    if (!tbHwnd || !DllCall("user32\IsWindow", "Ptr", tbHwnd, "Int"))
    {
        tbHwnd := ResolveDialogBreadcrumbToolbar(hwndDlg)
        cache[hwndDlg] := tbHwnd
    }

    if (!tbHwnd)
        return ""

    ; First try: cheap window text (works on some Win10 dialogs; sometimes Win11 returns "Address Band")
    dir := GetWindowTextTimeout(tbHwnd, 25)
    if Acc_LooksLikePath(dir)
        return dir

    ; Second try: MSAA scan within the Address Band subtree (Win11-friendly)
    dir2 := Acc_GetToolbarAddressPath(tbHwnd)
    if Acc_LooksLikePath(dir2)
        return dir2

    ; If still nothing, rescan toolbar once (layout can change per dialog instance)
    tbHwnd2 := ResolveDialogBreadcrumbToolbar(hwndDlg, tbHwnd)
    if (tbHwnd2 && tbHwnd2 != tbHwnd)
    {
        cache[hwndDlg] := tbHwnd2

        dir := GetWindowTextTimeout(tbHwnd2, 25)
        if Acc_LooksLikePath(dir)
            return dir

        dir2 := Acc_GetToolbarAddressPath(tbHwnd2)
        if Acc_LooksLikePath(dir2)
            return dir2
    }

    return ""
}

; Read a #32770 breadcrumb using only bounded native window-text messages.
; This timer-safe resolver avoids MSAA providers that can block far beyond the
; navigation poll interval; broader accessibility lookup remains available to
; callers of GetDialogBreadcrumbText().
GetDialogBreadcrumbWindowText(hwndDlg, timeoutMs := 50) {
    static cache := {} ; hwndDlg -> last native ToolbarWindow32 hwnd

    if (!hwndDlg || !DllCall("user32\IsWindow", "Ptr", hwndDlg, "Int"))
        return ""

    WinGetClass, dialogClass, ahk_id %hwndDlg%
    if (dialogClass != "#32770")
        return ""

    candidateHwnds := []
    seenHwnds      := {}
    if (cache.HasKey(hwndDlg)) {
        cachedToolbar := cache[hwndDlg]
        if (cachedToolbar
         && DllCall("user32\IsWindow", "Ptr", cachedToolbar, "Int")
         && DllCall("user32\IsChild", "Ptr", hwndDlg, "Ptr", cachedToolbar, "Int")) {
            candidateHwnds.Push(cachedToolbar)
            seenHwnds[cachedToolbar] := True
        }
        else
            cache[hwndDlg] := 0
    }

    ; Try the common address-toolbar ClassNNs before enumerating other toolbars.
    ControlGet, toolbarHwnd, Hwnd,, ToolbarWindow323, ahk_id %hwndDlg%
    if (toolbarHwnd && !seenHwnds.HasKey(toolbarHwnd)) {
        candidateHwnds.Push(toolbarHwnd)
        seenHwnds[toolbarHwnd] := True
    }
    ControlGet, toolbarHwnd, Hwnd,, ToolbarWindow324, ahk_id %hwndDlg%
    if (toolbarHwnd && !seenHwnds.HasKey(toolbarHwnd)) {
        candidateHwnds.Push(toolbarHwnd)
        seenHwnds[toolbarHwnd] := True
    }

    ; Include uncommon ToolbarWindow32 instances while keeping every text read
    ; inside the one shared deadline below.
    WinGet, controlHwndList, ControlListHwnd, ahk_id %hwndDlg%
    Loop, Parse, controlHwndList, `n, `r
    {
        toolbarHwnd := A_LoopField + 0
        if (!toolbarHwnd || seenHwnds.HasKey(toolbarHwnd))
            continue
        if (GetClassName(toolbarHwnd) != "ToolbarWindow32")
            continue
        candidateHwnds.Push(toolbarHwnd)
        seenHwnds[toolbarHwnd] := True
    }

    deadlineTick := A_TickCount + Max(1, timeoutMs)
    for _, toolbarHwnd in candidateHwnds {
        remainingMs := deadlineTick - A_TickCount
        if (remainingMs <= 0)
            break

        ; GetWindowTextTimeout() sends two messages, so divide the remaining
        ; budget between them to keep this resolver within the shared deadline.
        perMessageTimeoutMs := Max(1, Floor(remainingMs / 2))
        toolbarText := GetWindowTextTimeout(toolbarHwnd, perMessageTimeoutMs)
        if !Acc_LooksLikePath(toolbarText)
            continue

        cache[hwndDlg] := toolbarHwnd
        return _NormalizeDialogFolderPath(toolbarText)
    }

    return ""
}

; Accept only a toolbar whose direct or accessibility text identifies a path.
; This excludes unrelated #32770 controls such as an "Up band" toolbar.
_DialogBreadcrumbToolbarLooksValid(toolbarHwnd) {
    if (!toolbarHwnd || !DllCall("user32\IsWindow", "Ptr", toolbarHwnd, "Int"))
        return False

    if Acc_LooksLikePath(GetWindowTextTimeout(toolbarHwnd, 25))
        return True

    return Acc_LooksLikePath(Acc_GetToolbarAddressPath(toolbarHwnd))
}

GetWindowTextTimeout(hwndCtl, timeoutMs := 25) {
    static WM_GETTEXT := 0x0D
    static WM_GETTEXTLENGTH := 0x0E
    static SMTO_ABORTIFHUNG := 0x0002

    len := 0
    ok := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", hwndCtl
        , "UInt", WM_GETTEXTLENGTH
        , "Ptr", 0
        , "Ptr", 0
        , "UInt", SMTO_ABORTIFHUNG
        , "UInt", timeoutMs
        , "UPtr*", len)

    if (!ok || len <= 0)
        return ""

    VarSetCapacity(buf, (len + 1) * 2, 0)

    ok := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", hwndCtl
        , "UInt", WM_GETTEXT
        , "UPtr", len + 1
        , "Ptr", &buf
        , "UInt", SMTO_ABORTIFHUNG
        , "UInt", timeoutMs
        , "UPtr*", 0)

    if (!ok)
        return ""

    return StrGet(&buf, "UTF-16")
}

ResolveDialogBreadcrumbToolbar(hwndDlg, excludeHwnd := 0) {
    ; Fast path: common ctrlNNs (may vary, but cheap to try)
    ControlGet, h1, Hwnd,, ToolbarWindow323, ahk_id %hwndDlg%
    if (h1 && h1 != excludeHwnd && _DialogBreadcrumbToolbarLooksValid(h1))
        return h1

    ControlGet, h2, Hwnd,, ToolbarWindow324, ahk_id %hwndDlg%
    if (h2 && h2 != excludeHwnd && _DialogBreadcrumbToolbarLooksValid(h2))
        return h2

    ; Fallback: find any ToolbarWindow32 child hwnd
    WinGet, listH, ControlListHwnd, ahk_id %hwndDlg%
    Loop, Parse, listH, `n, `r
    {
        h := A_LoopField + 0
        if (!h || h = excludeHwnd)
            continue

        cls := GetClassName(h)
        if (cls = "ToolbarWindow32" && _DialogBreadcrumbToolbarLooksValid(h))
            return h
    }

    return 0
}

; Read the active Explorer tab's current folder through native shell interfaces.
; The returned desktop-absolute parsing name identifies filesystem and virtual
; folders without invoking the potentially slow Document.Folder.Self.Path getter.
_GetExplorerFolderIdentityFromShellBrowser(shellBrowser, ByRef failureReason := "") {
    ; Cache parsed interface IDs because this function can run repeatedly while navigation is being polled.
    static IID_IFolderView
    static IID_IPersistFolder2
    static iidReady                     := False
    ; Request one desktop-absolute parsing name format for both filesystem and virtual shell folders.
    static SIGDN_DESKTOPABSOLUTEPARSING := 0x80028000

    ; Reset the diagnostic output so success cannot retain a reason from an earlier call.
    failureReason := ""
    ; QueryActiveShellView requires an acquired IShellBrowser pointer for the active Explorer tab.
    if (!shellBrowser) {
        failureReason := "shell_browser_unavailable"
        return ""
    }

    ; Convert the textual interface GUIDs once because their binary forms are reused by every COM query.
    if (!iidReady) {
        ; Allocate the exact 16-byte storage required for each binary IID.
        VarSetCapacity(IID_IFolderView, 16, 0)
        VarSetCapacity(IID_IPersistFolder2, 16, 0)
        ; Parse IFolderView so the active IShellView can expose its represented folder.
        folderViewIidHr := DllCall("ole32\CLSIDFromString"
            , "WStr", "{CDE725B0-CCC9-4519-917E-325D72FAB4CE}"
            , "Ptr", &IID_IFolderView
            , "Int")
        ; Parse IPersistFolder2 so the folder object can return its current absolute PIDL.
        persistFolderIidHr := DllCall("ole32\CLSIDFromString"
            , "WStr", "{1AC3D9F0-175C-11D1-95BE-00609797EA4F}"
            , "Ptr", &IID_IPersistFolder2
            , "Int")
        ; Cache readiness only when both HRESULT values report success because both IIDs are required below.
        iidReady := (folderViewIidHr >= 0 && persistFolderIidHr >= 0)
        if (!iidReady) {
            failureReason := "iid_initialization_failed"
            return ""
        }
    }

    ; Initialize every owned pointer so the shared cleanup can release only resources actually acquired.
    folderIdentity := ""
    folderNamePtr  := 0
    folderPidl     := 0
    folderView     := 0
    persistFolder  := 0
    shellView      := 0

    try {
        ; Query the visible tab's IShellView so an inactive Explorer tab cannot supply the path.
        queryViewHr := DllCall(NumGet(NumGet(shellBrowser + 0) + 15*A_PtrSize)
            , "Ptr", shellBrowser
            , "Ptr*", shellView
            , "Int")
        if (queryViewHr < 0 || !shellView)
            failureReason := "active_shell_view_unavailable"
        else {
            ; IFolderView exposes the folder object represented by the active shell view.
            queryFolderViewHr := DllCall(NumGet(NumGet(shellView + 0) + 0*A_PtrSize)
                , "Ptr", shellView
                , "Ptr", &IID_IFolderView
                , "Ptr*", folderView
                , "Int")
            if (queryFolderViewHr < 0 || !folderView)
                failureReason := "folder_view_unavailable"
            else {
                ; Request IPersistFolder2 from that folder so its current absolute PIDL can be read.
                getFolderHr := DllCall(NumGet(NumGet(folderView + 0) + 5*A_PtrSize)
                    , "Ptr", folderView
                    , "Ptr", &IID_IPersistFolder2
                    , "Ptr*", persistFolder
                    , "Int")
                if (getFolderHr < 0 || !persistFolder)
                    failureReason := "persist_folder_unavailable"
                else {
                    ; GetCurFolder clones the PIDL; this function releases it with CoTaskMemFree below.
                    getCurFolderHr := DllCall(NumGet(NumGet(persistFolder + 0) + 5*A_PtrSize)
                        , "Ptr", persistFolder
                        , "Ptr*", folderPidl
                        , "Int")
                    if (getCurFolderHr < 0 || !folderPidl)
                        failureReason := "current_folder_pidl_unavailable"
                    else {
                        ; Convert filesystem and virtual-folder PIDLs into one comparable parsing-name format.
                        getNameHr := DllCall("shell32\SHGetNameFromIDList"
                            , "Ptr", folderPidl
                            , "UInt", SIGDN_DESKTOPABSOLUTEPARSING
                            , "Ptr*", folderNamePtr
                            , "Int")
                        if (getNameHr < 0 || !folderNamePtr)
                            failureReason := "folder_parsing_name_unavailable"
                        else {
                            folderIdentity := StrGet(folderNamePtr, "UTF-16")
                            ; Treat an allocated but empty parsing name as failure because it cannot prove a path.
                            if (folderIdentity = "")
                                failureReason := "folder_parsing_name_empty"
                        }
                    }
                }
            }
        }
    }
    catch {
        ; Convert any COM or pointer-call exception into a normal failed lookup for the caller's fallback path.
        failureReason := "native_shell_exception"
        folderIdentity := ""
    }

    ; SHGetNameFromIDList allocates its string with the COM task allocator, so release it with CoTaskMemFree.
    if (folderNamePtr)
        DllCall("ole32\CoTaskMemFree", "Ptr", folderNamePtr)
    ; GetCurFolder returns a cloned PIDL owned by this function, so release that allocation independently.
    if (folderPidl)
        DllCall("ole32\CoTaskMemFree", "Ptr", folderPidl)
    ; Release each reference-counted COM interface in reverse acquisition order for predictable cleanup.
    if (persistFolder)
        ObjRelease(persistFolder)
    if (folderView)
        ObjRelease(folderView)
    if (shellView)
        ObjRelease(shellView)

    ; Canonicalize separators and trailing slashes before navigation code compares this identity with fallbacks.
    return _NormalizeExplorerFolderIdentity(folderIdentity)
}

; Normalize folder identities returned by Explorer's native, automation, dialog,
; breadcrumb, and toolbar resolvers before navigation code compares them.
_NormalizeExplorerFolderIdentity(folderIdentity) {
    ; Remove surrounding whitespace that UI text and automation providers may include around the same path.
    folderIdentity := Trim(folderIdentity, " `t`r`n")
    ; Convert forward slashes to Windows separators so equivalent provider results compare literally equal.
    folderIdentity := StrReplace(folderIdentity, "/", "\")
    ; Preserve a drive root such as C:\, but remove trailing separators elsewhere to avoid false path changes.
    if (StrLen(folderIdentity) > 3)
        folderIdentity := RTrim(folderIdentity, "\")
    ; Return one comparable identity without changing its case or shell parsing-name content.
    return folderIdentity
}

; Normalize a dialog-reported folder path so the native common-dialog message
; and breadcrumb fallbacks produce directly comparable folder identities.
_NormalizeDialogFolderPath(folderPath) {
    folderPath := Trim(folderPath, " `t`r`n")
    folderPath := RegExReplace(folderPath, "i)^Address:\s*")
    if (StrLen(folderPath) >= 2
     && SubStr(folderPath, 1, 1) = Chr(34)
     && SubStr(folderPath, 0) = Chr(34))
        folderPath := SubStr(folderPath, 2, -1)

    return _NormalizeExplorerFolderIdentity(folderPath)
}

; Read a #32770 file dialog's current filesystem folder through the bounded
; CDM_GETFOLDERPATH common-dialog message. An empty result lets the caller try
; another native source without blocking the navigation timer.
GetDialogFolderPath(hwndDlg, timeoutMs := 25) {
    static CDM_GETFOLDERPATH := 0x0466
    static maxPathChars      := 32768
    static SMTO_ABORTIFHUNG  := 0x0002

    if (!hwndDlg || !DllCall("user32\IsWindow", "Ptr", hwndDlg, "Int"))
        return ""

    WinGetClass, dialogClass, ahk_id %hwndDlg%
    if (dialogClass != "#32770")
        return ""

    VarSetCapacity(folderPathBuffer, maxPathChars * 2, 0)
    copiedChars := 0
    messageSent := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", hwndDlg
        , "UInt", CDM_GETFOLDERPATH
        , "UPtr", maxPathChars
        , "Ptr", &folderPathBuffer
        , "UInt", SMTO_ABORTIFHUNG
        , "UInt", Max(1, timeoutMs)
        , "UPtr*", copiedChars)

    if (!messageSent || copiedChars <= 0)
        return ""

    return _NormalizeDialogFolderPath(StrGet(&folderPathBuffer, "UTF-16"))
}

; Read a #32770 file dialog's current folder PIDL through the bounded
; CDM_GETFOLDERIDLIST message, then convert it to the same parsing-name identity
; used by Explorer. This also supports shell folders that have no filesystem path.
GetDialogFolderIdentityFromIdList(hwndDlg, timeoutMs := 25) {
    static CDM_GETFOLDERIDLIST          := 0x0467
    static maxPidlBytes                 := 65536
    static SIGDN_DESKTOPABSOLUTEPARSING := 0x80028000
    static SMTO_ABORTIFHUNG             := 0x0002

    if (!hwndDlg || !DllCall("user32\IsWindow", "Ptr", hwndDlg, "Int"))
        return ""

    WinGetClass, dialogClass, ahk_id %hwndDlg%
    if (dialogClass != "#32770")
        return ""

    VarSetCapacity(folderPidlBuffer, maxPidlBytes, 0)
    copiedBytes := 0
    messageSent := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", hwndDlg
        , "UInt", CDM_GETFOLDERIDLIST
        , "UPtr", maxPidlBytes
        , "Ptr", &folderPidlBuffer
        , "UInt", SMTO_ABORTIFHUNG
        , "UInt", Max(1, timeoutMs)
        , "UPtr*", copiedBytes)
    if (!messageSent || copiedBytes <= 0)
        return ""

    folderNamePtr := 0
    getNameHr := DllCall("shell32\SHGetNameFromIDList"
        , "Ptr", &folderPidlBuffer
        , "UInt", SIGDN_DESKTOPABSOLUTEPARSING
        , "Ptr*", folderNamePtr
        , "Int")
    if (getNameHr < 0 || !folderNamePtr)
        return ""

    folderIdentity := StrGet(folderNamePtr, "UTF-16")
    DllCall("ole32\CoTaskMemFree", "Ptr", folderNamePtr)
    return _NormalizeExplorerFolderIdentity(folderIdentity)
}

; Resolve a #32770 file dialog's folder identity through native, time-bounded
; sources only. Reusing the last successful source first reduces repeated work;
; excluding MSAA prevents an accessibility provider from blocking this timer.
_ResolveDialogFolderLocation(hwndDlg, preferredResolver := "", traceRequestId := "") {
    resolverOrder := []
    if (preferredResolver = "dialog_path"
     || preferredResolver = "dialog_idlist"
     || preferredResolver = "dialog_toolbar_text")
        resolverOrder.Push(preferredResolver)

    for _, resolverName in ["dialog_path", "dialog_idlist", "dialog_toolbar_text"] {
        if (resolverName != preferredResolver)
            resolverOrder.Push(resolverName)
    }

    for _, resolverName in resolverOrder {
        resolverStartTick := A_TickCount
        if (resolverName = "dialog_path")
            dialogPath := GetDialogFolderPath(hwndDlg, 25)
        else if (resolverName = "dialog_idlist")
            dialogPath := GetDialogFolderIdentityFromIdList(hwndDlg, 25)
        else
            dialogPath := GetDialogBreadcrumbWindowText(hwndDlg, 50)

        if (traceRequestId != "")
            _TraceExplorerCtrlAdd("dialog_location_probe"
                , "resolver=" . resolverName
                . " elapsedMs=" . (A_TickCount - resolverStartTick)
                . " found=" . (dialogPath != "")
                . " preferred=" . (resolverName = preferredResolver)
                . " path=[" . dialogPath . "]"
                , False, traceRequestId)
        if (dialogPath != "")
            return { path: dialogPath, resolver: resolverName }
    }

    return { path: "", resolver: "" }
}

GetExplorerPath(hwnd := "", traceRequestId := "") {
    ; Read the OS-generation flag because Windows 10 and Windows 11 expose Explorer locations differently.
    global k_isWin11

    ; Reuse one Shell.Application COM object because creating it on every navigation poll is comparatively expensive.
    static shellApp := ""
    ; Cache each Explorer host's active tab, shell COM window, path, and sample time to avoid repeated collection scans.
    static cacheMap := {} ; hwnd -> { activeTabHwnd, shellWin, lastPath, lastTick }
    ; Store IShellBrowser's interface ID because it exposes both the tab HWND and active shell view.
    static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"

    ; Default to the foreground window so callers can omit an HWND when querying the active Explorer location.
    if (!hwnd)
        hwnd := WinExist("A")

    ; Stop when no target window exists because neither class lookup nor location resolution can succeed.
    if (!hwnd)
        return ""

    ; Confirm the HWND still identifies a live window because deferred navigation timers can outlive their target.
    if (!DllCall("user32\IsWindow", "Ptr", hwnd, "Int"))
        return ""

    ; Read the target's native window class so the function can select the correct location-resolution method.
    WinGetClass, winClass, ahk_id %hwnd%

    ; Delegate common file dialogs because #32770 locations require bounded native common-dialog resolution.
    if (winClass = "#32770")
        return _ResolveDialogFolderLocation(hwnd, "", traceRequestId).path

    ; Reject unrelated windows because the remaining COM and toolbar logic is specific to Explorer hosts.
    if (winClass != "CabinetWClass")
        return ""

    ; Preserve the Windows 10 title-based behavior because that Explorer version exposes useful location text there.
    if (!k_isWin11) {
        ; Read the Explorer title because this legacy branch returns it as the current location label.
        WinGetTitle, expTitle, ahk_id %hwnd%

        ; Recognize common virtual and user folders explicitly because their titles may not be filesystem paths.
        if (   InStr(expTitle, "This PC"    , True)
            || InStr(expTitle, "Home"       , True)
            || InStr(expTitle, "Downloads"  , True)
            || InStr(expTitle, "Recycle Bin", True)
            || InStr(expTitle, "Pictures"   , True)
            || InStr(expTitle, "Videos"     , True)
            || InStr(expTitle, "Documents"  , True)
            || InStr(expTitle, "Music"      , True)
            || InStr(expTitle, "Desktop"    , True) )
        {
            ; Return the recognized folder title because it is the best available legacy location identifier.
            return expTitle
        }

        ; Return any other Explorer title because the Windows 10 compatibility path historically uses it as well.
        return expTitle
    }

    ; Lazily create Shell.Application so the matching Explorer tab object can supply its IShellBrowser interface.
    if !IsObject(shellApp) {
        shellAppStartTick := A_TickCount
        try
            shellApp := ComObjCreate("Shell.Application")
        catch
        {
            ; Clear a failed COM object so a later call can retry after Explorer or COM recovers.
            shellApp := ""
            if (traceRequestId != "")
                _TraceExplorerCtrlAdd("explorer_path_shell_app_create"
                    , "elapsedMs=" . (A_TickCount - shellAppStartTick)
                    . " success=0", False, traceRequestId)
            ; Return no path because continuing without Shell.Application would make the primary lookup invalid.
            return ""
        }
        if (traceRequestId != "")
            _TraceExplorerCtrlAdd("explorer_path_shell_app_create"
                , "elapsedMs=" . (A_TickCount - shellAppStartTick)
                . " success=1", False, traceRequestId)
    }

    ; Initialize the active-tab HWND to zero so a missing tab control safely disables tab-specific filtering.
    activeTabHwnd := 0
    ; Resolve the active ShellTabWindowClass child because one CabinetWClass can host multiple Explorer tabs.
    activeTabStartTick := A_TickCount
    ControlGet, activeTabHwnd, Hwnd,, ShellTabWindowClass1, % "ahk_id " hwnd
    if (traceRequestId != "")
        _TraceExplorerCtrlAdd("explorer_path_active_tab_lookup"
            , "elapsedMs=" . (A_TickCount - activeTabStartTick)
            . " found=" . !!activeTabHwnd
            . " activeTabHwnd=" . activeTabHwnd, False, traceRequestId)

    ; Start without cached state so the following checks run only for a previously observed Explorer HWND.
    cacheItem := ""
    ; Retrieve this host's cache entry because it may avoid a full Shell.Application.Windows enumeration.
    if (cacheMap.HasKey(hwnd))
        cacheItem := cacheMap[hwnd]

    ; Reuse cached state only when it is a valid object because failed or empty entries cannot safely be dereferenced.
    if (IsObject(cacheItem)) {
        ; Apply a 10 ms throttle because tight polling loops do not need to repeat COM work within the same instant.
        if (A_TickCount - cacheItem.lastTick < 10)
        {
            ; Require the same active tab because a cached path from another tab would report the wrong directory.
            if (cacheItem.activeTabHwnd = activeTabHwnd) {
                if (traceRequestId != "")
                    _TraceExplorerCtrlAdd("explorer_path_cache_throttle_hit"
                        , "cacheAgeMs=" . (A_TickCount - cacheItem.lastTick)
                        . " path=[" . cacheItem.lastPath . "]", False, traceRequestId)
                return cacheItem.lastPath
            }
        }

        ; Reuse the cached shell COM window only for the same tab so navigation can be sampled without rescanning all windows.
        if (cacheItem.activeTabHwnd = activeTabHwnd && IsObject(cacheItem.shellWin))
        {
            ; Initialize the refreshed path as empty so a native or automation failure cannot preserve an obsolete value.
            cachedPath := ""
            cachedNativeFailureReason := ""
            cachedShellBrowser := 0
            cachedNativeStartTick := A_TickCount
            try {
                ; Query the cached tab's IShellBrowser so its active shell view supplies the current folder PIDL.
                cachedShellBrowser := ComObjQuery(cacheItem.shellWin, IID_IShellBrowser, IID_IShellBrowser)
                cachedPath := _GetExplorerFolderIdentityFromShellBrowser(cachedShellBrowser, cachedNativeFailureReason)
            }
            catch {
                ; Treat an invalidated shell COM window as a cache miss after the compatibility fallback below.
                cachedPath := ""
                cachedNativeFailureReason := "shell_browser_query_exception"
            }
            if (cachedShellBrowser)
                ObjRelease(cachedShellBrowser)
            if (traceRequestId != "")
                _TraceExplorerCtrlAdd("explorer_path_cached_native_read"
                    , "elapsedMs=" . (A_TickCount - cachedNativeStartTick)
                    . " found=" . (cachedPath != "")
                    . " failure=" . cachedNativeFailureReason
                    . " path=[" . cachedPath . "]", False, traceRequestId)

            ; Preserve Folder.Self.Path only as a compatibility fallback when the native folder-PIDL chain is unavailable.
            if (cachedPath = "") {
                cachedAutomationStartTick := A_TickCount
                try
                    cachedPath := _NormalizeExplorerFolderIdentity(cacheItem.shellWin.Document.Folder.Self.Path)
                catch
                    cachedPath := ""
                if (traceRequestId != "")
                    _TraceExplorerCtrlAdd("explorer_path_cached_automation_fallback"
                        , "elapsedMs=" . (A_TickCount - cachedAutomationStartTick)
                        . " found=" . (cachedPath != "")
                        . " path=[" . cachedPath . "]", False, traceRequestId)
            }

            ; Accept only nonempty path text because an empty resolver result cannot prove the current Explorer location.
            if (cachedPath != "")
            {
                ; Store the newly observed path so immediate subsequent polls can use the 10 ms throttle.
                cacheItem.lastPath := cachedPath
                ; Record the sample time because cache freshness is measured from this successful folder read.
                cacheItem.lastTick := A_TickCount
                ; Write the updated object back by HWND so later calls observe the refreshed values.
                cacheMap[hwnd] := cacheItem
                ; Return immediately because the cached tab object supplied a current nonempty location.
                return cachedPath
            }
        }
    }

    ; Initialize the collection-scan results so exceptions or misses produce a clean fallback state.
    automationFallbackElapsedMs := 0
    collectionElapsedMs := 0
    enumeratedWindowCount := 0
    foundPath := ""
    foundWin := ""
    hostMatchCount := 0
    hwndReadElapsedMs := 0
    nativePathFailureReason := ""
    nativePathReadElapsedMs := 0
    pathReadElapsedMs := 0
    scanException := False
    shellBrowserQueryElapsedMs := 0
    tabMatchElapsedMs := 0

    ; Guard the COM collection scan because Explorer can replace tab objects while navigation is in progress.
    collectionScanStartTick := A_TickCount
    try
    {
        ; Acquire the collection separately so the trace distinguishes that COM call from enumeration and tab matching.
        shellWindowsStartTick := A_TickCount
        shellWindows := shellApp.Windows
        collectionElapsedMs := A_TickCount - shellWindowsStartTick

        ; Enumerate Shell.Application windows to locate the COM object associated with the requested Explorer host.
        for shellWin in shellWindows
        {
            enumeratedWindowCount++
            shellWinHwndStartTick := A_TickCount
            shellWinHwnd := shellWin.hwnd
            hwndReadElapsedMs += A_TickCount - shellWinHwndStartTick

            ; Skip COM windows hosted by another top-level HWND because they cannot describe this Explorer instance.
            if (shellWinHwnd != hwnd)
                continue
            hostMatchCount++

            ; Query IShellBrowser once for both active-tab verification and native current-folder resolution.
            shellBrowser := 0
            shellBrowserQueryStartTick := A_TickCount
            try
                shellBrowser := ComObjQuery(shellWin, IID_IShellBrowser, IID_IShellBrowser)
            catch {
                shellBrowser := 0
                nativePathFailureReason := "shell_browser_query_exception"
            }
            shellBrowserQueryElapsedMs += A_TickCount - shellBrowserQueryStartTick

            ; When Explorer exposes tabs, require this COM entry's IOleWindow HWND to match the visible tab.
            if (activeTabHwnd) {
                thisTabHwnd := 0
                getTabHwndHr := -1
                tabMatchStartTick := A_TickCount
                try {
                    if (shellBrowser)
                        getTabHwndHr := DllCall(NumGet(NumGet(shellBrowser + 0) + 3*A_PtrSize)
                            , "Ptr", shellBrowser
                            , "Ptr*", thisTabHwnd
                            , "Int")
                }
                catch
                    thisTabHwnd := 0
                if (getTabHwndHr < 0)
                    thisTabHwnd := 0
                tabMatchElapsedMs += A_TickCount - tabMatchStartTick

                ; Ignore inactive or unverifiable tabs because their folder identities may differ from the visible tab.
                if (thisTabHwnd != activeTabHwnd) {
                    if (shellBrowser)
                        ObjRelease(shellBrowser)
                    continue
                }
            }

            ; Prefer the active shell view's current folder PIDL because it avoids Folder.Self.Path's variable delay.
            nativePathStartTick := A_TickCount
            if (shellBrowser)
                foundPath := _GetExplorerFolderIdentityFromShellBrowser(shellBrowser, nativePathFailureReason)
            else {
                foundPath := ""
                if (nativePathFailureReason = "")
                    nativePathFailureReason := "shell_browser_unavailable"
            }
            nativePathElapsedMs := A_TickCount - nativePathStartTick
            nativePathReadElapsedMs += nativePathElapsedMs
            pathReadElapsedMs += nativePathElapsedMs

            ; Release the queried interface after both tab matching and folder resolution have finished using it.
            if (shellBrowser)
                ObjRelease(shellBrowser)

            ; Preserve Folder.Self.Path only as the compatibility fallback for native shell-interface failures.
            if (foundPath = "") {
                automationFallbackStartTick := A_TickCount
                try
                    foundPath := _NormalizeExplorerFolderIdentity(shellWin.Document.Folder.Self.Path)
                catch
                    foundPath := ""
                automationFallbackMs := A_TickCount - automationFallbackStartTick
                automationFallbackElapsedMs += automationFallbackMs
                pathReadElapsedMs += automationFallbackMs
            }

            ; Retain the matched COM window even when its path is empty so the final cache reflects what was examined.
            foundWin := shellWin
            ; Stop after the host-and-tab match because later entries cannot be a better match for the active view.
            break
        }
    }
    catch {
        scanException := True
        ; Discard the matched window after a collection exception because its COM state may be incomplete or stale.
        foundWin := ""
        ; Discard the path after the same exception because returning a partial COM result could misreport navigation.
        foundPath := ""
    }
    if (traceRequestId != "")
        _TraceExplorerCtrlAdd("explorer_path_collection_scan"
            , "elapsedMs=" . (A_TickCount - collectionScanStartTick)
            . " collectionMs=" . collectionElapsedMs
            . " enumerated=" . enumeratedWindowCount
            . " hwndReadMs=" . hwndReadElapsedMs
            . " hostMatches=" . hostMatchCount
            . " shellBrowserQueryMs=" . shellBrowserQueryElapsedMs
            . " tabMatchMs=" . tabMatchElapsedMs
            . " nativePathReadMs=" . nativePathReadElapsedMs
            . " nativeFailure=" . nativePathFailureReason
            . " automationFallbackMs=" . automationFallbackElapsedMs
            . " pathReadMs=" . pathReadElapsedMs
            . " found=" . (foundPath != "")
            . " exception=" . scanException
            . " path=[" . foundPath . "]", False, traceRequestId)

    ; Use a nonempty folder identity immediately because no toolbar fallback is needed when either shell resolver succeeded.
    if (foundPath != "") {
        ; Cache the active tab, shell COM object, path, and timestamp so subsequent navigation polls avoid enumeration.
        cacheMap[hwnd] := { "activeTabHwnd": activeTabHwnd, "shellWin": foundWin, "lastPath": foundPath, "lastTick": A_TickCount }
        ; Return the matched tab's normalized folder identity because it identifies the current Explorer location.
        return foundPath
    }

    ; Fall back to address-bar text when neither native shell interfaces nor Folder.Self.Path identify the location.
    dirText := ""
    ; Initialize both toolbar handles to zero so missing address controls are handled without stale HWND values.
    toolbarHwnd1 := 0
    toolbarHwnd2 := 0

    ; Resolve the primary address toolbar because its window text can identify locations that COM did not return.
    primaryToolbarLookupStartTick := A_TickCount
    ControlGet, toolbarHwnd1, Hwnd,, ToolbarWindow323, ahk_id %hwnd%
    primaryToolbarLookupElapsedMs := A_TickCount - primaryToolbarLookupStartTick
    primaryToolbarTextElapsedMs := 0
    if (toolbarHwnd1) {
        ; Read toolbar text with a 25 ms timeout so a hung Explorer UI thread cannot block navigation polling for long.
        primaryToolbarTextStartTick := A_TickCount
        dirText := GetWindowTextTimeout(toolbarHwnd1, 25)
        primaryToolbarTextElapsedMs := A_TickCount - primaryToolbarTextStartTick
    }

    ; Try the alternate toolbar when the primary is empty or only reports its generic Address Band label.
    alternateToolbarLookupElapsedMs := 0
    alternateToolbarTextElapsedMs := 0
    if (dirText = "" || dirText = "Address Band") {
        ; Resolve the alternate address toolbar because Explorer layouts can expose the useful text under this ClassNN.
        alternateToolbarLookupStartTick := A_TickCount
        ControlGet, toolbarHwnd2, Hwnd,, ToolbarWindow324, ahk_id %hwnd%
        alternateToolbarLookupElapsedMs := A_TickCount - alternateToolbarLookupStartTick
        ; Read the alternate only when it exists because GetWindowTextTimeout requires a valid target HWND.
        if (toolbarHwnd2) {
            alternateToolbarTextStartTick := A_TickCount
            dirText := GetWindowTextTimeout(toolbarHwnd2, 25)
            alternateToolbarTextElapsedMs := A_TickCount - alternateToolbarTextStartTick
        }
    }
    ; Normalize the toolbar fallback so it can be compared with native, automation, and dialog folder identities.
    dirText := _NormalizeExplorerFolderIdentity(dirText)
    if (traceRequestId != "")
        _TraceExplorerCtrlAdd("explorer_path_toolbar_fallback"
            , "primaryLookupMs=" . primaryToolbarLookupElapsedMs
            . " primaryTextMs=" . primaryToolbarTextElapsedMs
            . " primaryFound=" . !!toolbarHwnd1
            . " alternateLookupMs=" . alternateToolbarLookupElapsedMs
            . " alternateTextMs=" . alternateToolbarTextElapsedMs
            . " alternateFound=" . !!toolbarHwnd2
            . " path=[" . dirText . "]", False, traceRequestId)

    ; Cache the fallback result, including an empty value, so immediate repeated calls can still use the short throttle.
    cacheMap[hwnd] := { "activeTabHwnd": activeTabHwnd, "shellWin": foundWin, "lastPath": dirText, "lastTick": A_TickCount }
    ; Return the best address-toolbar text found, or empty when neither COM nor the toolbars identified a location.
    return dirText
}

; https://www.autohotkey.com/boards/viewtopic.php?t=60403
Explorer_GetSelection() {
   WinGetClass, winClass, % "ahk_id" . hWnd := WinExist("A")
   If !(winClass ~= "^(Progman|WorkerW|(Cabinet|Explore)WClass)$")
      Return

   shellWindows := ComObjCreate("Shell.Application").Windows
   If (winClass ~= "Progman|WorkerW")  ; IShellWindows::Item:    https://goo.gl/ihW9Gm
                                       ; IShellFolderViewDual:   https://goo.gl/gnntq3
      shellFolderView := shellWindows.Item( ComObject(VT_UI4 := 0x13, SWC_DESKTOP := 0x8) ).Document
   Else {
      for window in shellWindows       ; ShellFolderView object: https://tinyurl.com/yh92uvpa
         If (hWnd = window.HWND) && (shellFolderView := window.Document)
            break
   }
   for item in shellFolderView.SelectedItems
      result .= (result = "" ? "" : "`n") . item.Path
   ;~ If !result
      ;~ result := shellFolderView.Folder.Self.Path
   Return result
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

    if !_TypingAutoFixTryGetFocusedControlIdentity(prewarmHwnd, prewarmCtrlNN
        , prewarmCtrlHwnd, prewarmCtrlClass)
        Return

    GetTypingAutoFixEligibilityFastOrQ(prewarmHwnd, prewarmCtrlNN
        , prewarmCtrlHwnd, prewarmCtrlClass, A_TickCount
        , prewarmStartTypingSeq, prewarmStartHotstringBoundarySeq)
Return

; Runs after the requested separator key event completes, then discards the
; hotstring recognition buffer so the following word starts with a clean buffer.
ResetHotstringBufferAfterBoundary:
    hotstringResetTimerPending := False
    if (hotstringResetAtBoundarySeq
        && hotstringBoundarySeq >= hotstringResetAtBoundarySeq)
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
    if !_TypingAutoFixTargetStillFocused(tbcRefreshHwnd, tbcRefreshCtrlNN
        , tbcRefreshCtrlHwnd, tbcRefreshCtrlClass)
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
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd
            , c_typingAutoFixAllowed, c_typingAutoFixReason, nowTick)

    ; A new context or expired slow-path TTL means it is time to refresh accessibility state.
    typingAutoFixSlowProbeTick := nowTick

    ; UIA is the preferred slow-path signal for custom editors that expose editability.
    uiaEditable := UIA_IsFocusedEditable()
    if !_TypingAutoFixTargetStillFocused(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass)
        return false

    if (uiaEditable) {
        _SetHotstringResetTimingAfterAsyncProbe(protectPartialWord
            , startTypingSeq, startHotstringBoundarySeq)
        return _TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, true, "uia_editable", nowTick)
    }

    ; MSAA stays as a weaker fallback when UIA is missing or incomplete.
    msaaEditable := MSAA_IsFocusedEditable()
    if !_TypingAutoFixTargetStillFocused(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass)
        return false

    if (msaaEditable) {
        _SetHotstringResetTimingAfterAsyncProbe(protectPartialWord
            , startTypingSeq, startHotstringBoundarySeq)
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

    cacheExpired := (!confirmedContext
        || (nowTick - c_typingAutoFixTick) > k_typingAutoFixFastTtlMs)
    sameRefreshPending := (activeHwnd = typingAutoFixRefreshHwnd
        && ctrlNN = typingAutoFixRefreshCtrlNN
        && ctrlHwnd = typingAutoFixRefreshCtrlHwnd)

    ; Do not keep resetting the one-shot timer while the user is typing. The
    ; existing matching request will run as soon as physical input is quiet.
    if (cacheExpired && !sameRefreshPending)
        QueueTypingAutoFixRefresh(activeHwnd, ctrlNN, ctrlHwnd, ctrlClass
            , nowTick, false)

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
    if (_HotstringAutoCorrectIsExcludedProcess(processName)
        || _TypingAutoFixIsExcludedProcess(processName))
        return false

    ; Capture one guarded identity snapshot. A transient focus lookup failure is
    ; treated as unknown and therefore must not disable every hotstring.
    if !_TypingAutoFixTryGetFocusedControlIdentity(activeHwnd, ctrlNN
        , ctrlHwnd, ctrlClass)
        return true

    ; Preserve the long-standing exclusion for plain Edit controls while still
    ; allowing RichEdit controls and accessibility-backed custom editors.
    if (InStr(ctrlNN, "Edit", True) && !InStr(ctrlNN, "Rich", True))
        return false

    if (IsClassicEditControlClass(ctrlClass))
        return true

    return GetHotstringEligibilityFastOrQueue(activeHwnd, ctrlNN, ctrlHwnd
        , ctrlClass, A_TickCount)
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
_TypingAutoFixSetCache(activeHwnd, ctrlNN, ctrlHwnd, allowed, reason
    , nowTick := "") {
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
_SetHotstringResetTimingAfterAsyncProbe(protectPartialWord, startTypingSeq
    , startHotstringBoundarySeq) {
    global hotstringBoundarySeq, hotstringResetAtBoundarySeq
    global hotstringResetTimerPending
    global physicalTypingSeq

    if (!protectPartialWord)
        return

    SetTimer, ResetHotstringBufferAfterBoundary, Off
    hotstringResetTimerPending := False

    ; No physical text arrived, or the user already completed a separator. The
    ; positive result can be used immediately without carrying a word fragment.
    if (physicalTypingSeq <= startTypingSeq
        || hotstringBoundarySeq > startHotstringBoundarySeq)
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

MouseIsOverAnyTaskbarSurface() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , windowUnderMouseId
    if (!windowUnderMouseId)
        return False

    WinGetClass, windowClass, ahk_id %windowUnderMouseId%
    isTaskbar := (windowClass == "Shell_TrayWnd"
         || windowClass == "Shell_SecondaryTrayWnd"
         || windowClass == "TaskListThumbnailWnd"
         || windowClass == "Windows.UI.Core.CoreWindow"
         || windowClass == "XamlExplorerHostIslandWindow")

     return isTaskbar
}

MouseIsOverDesktopShellSurface() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , windowUnderMouseId
    if (!windowUnderMouseId)
        return False

    WinGetClass, windowClass, ahk_id %windowUnderMouseId%
    return (windowClass == "Progman" || windowClass == "ProgMan" || windowClass == "WorkerW")
}

MouseIsOverTaskbarTray() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    Return (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId == "TrayNotifyWnd1")
}

MouseIsOverTaskbar() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    Return (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId != "ToolbarWindow323")
}

MouseIsOverTaskbarButtonGroup() {
    CoordMode, Mouse, Screen
    MouseGetPos, x, y, WindowUnderMouseID, CtrlUnderMouseId

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%
    If (InStr(mClass,"TrayWnd",False) && InStr(mClass,"Shell",False) && CtrlUnderMouseId != "TrayNotifyWnd1") {
        pt := SafeUIA_ElementFromPoint(x,y, "", 2000)
        ctype := SafeUIA_GetControlType(pt)
        ; tooltip, % "val is " pt.CurrentControlType
        Return (ctype == 50000)
    }
    Else
        Return False
}

MouseIsOverTaskbarWidgets() {
    CoordMode, Mouse, Screen
    MouseGetPos, , , WindowUnderMouseID

    WinGetClass, mClass, ahk_id %WindowUnderMouseID%

    Return (mClass == "TaskListThumbnailWnd" || mClass == "Windows.UI.Core.CoreWindow" || mClass == "XamlExplorerHostIslandWindow")
}

MouseIsOverTaskbarBlank() {
    local mousePosX
    local mousePosY
    local windowUnderMouseId
    local controlUnderMouseHwnd
    local windowClass
    local controlClass

    if !(GetKeyState("WheelDown", "P")
      || GetKeyState("WheelUp",   "P")
      || GetKeyState("LButton",   "P")
      || GetKeyState("RButton",   "P")
      || GetKeyState("MButton",   "P"))
        return False

    MouseGetPos, mousePosX, mousePosY, windowUnderMouseId, controlUnderMouseHwnd, 2
    if (!windowUnderMouseId)
        return False

    WinGetClass, windowClass, ahk_id %windowUnderMouseId%
    if !(InStr(windowClass, "Shell", False) && InStr(windowClass, "TrayWnd", False))
        return False

    if WinExist("ahk_class TaskListThumbnailWnd")
        return False

    controlClass := ""
    if (controlUnderMouseHwnd)
        WinGetClass, controlClass, ahk_id %controlUnderMouseHwnd%

    if (controlClass = "TrayNotifyWnd")
        return False

    return AreaLooksUniformFast(mousePosX, mousePosY, , 6, 10)
}
; Use AreaLooksUniformFast() when false positives are costly and every pixel in
; a small region must be checked to confirm that the region is visually flat.
;
; RADIUS GUIDELINES -----------------------------------------------------------
; sampleRadius selects a (2 * sampleRadius + 1)-pixel square. The function
; checks every pixel, so scan cost grows with the square of the region width.
; A larger radius examines farther from the click point, reducing false reports
; of uniformity over text, icons, or edges, but increasing failures near real
; borders, gradients, shadows, and mica blur.
;
; 1       3x3,   9 pixels: very local and cheap; easiest to falsely call flat
; 2       5x5,  25 pixels: conservative default for small UI targets
; 3       7x7,  49 pixels: stronger surrounding-area check at about 2x radius 2
; 4       9x9,  81 pixels: broad check; more sensitive to nearby visual detail
; 5      11x11, 121 pixels: use only when the expected flat area is comfortably large
;
; Increasing sampleRadius does not change the allowed color difference. It adds
; more pixels, and every added pixel must pass the same tolerance test. A larger
; radius may therefore need a slightly higher tolerance on blurred or textured
; surfaces; otherwise one distant pixel can make the entire check return False.
;
; TOLERANCE GUIDELINES --------------------------------------------------------
; tolerance is the maximum allowed difference in each RGB channel between every
; sampled pixel and targetColor, or the requested centerPosX/centerPosY pixel
; when targetColor is blank. Near a monitor edge, the capture square shifts
; inward while that requested pixel remains the color reference.
; 6-8    very strict, may fail on mica blur
; 10     lowest practical starting point
; 12     safer low value for mica
; 14-16  robust but still conservative
; 18     already moderately forgiving
AreaLooksUniformFast(centerPosX, centerPosY, targetColor := "", sampleRadius := 2, tolerance := 18) {

    ; Compute the width/height of the square sample region.
    sampleSize := (sampleRadius * 2) + 1

    ; Top-left corner of the sampled square in screen coordinates.
    startPosX := centerPosX - sampleRadius
    startPosY := centerPosY - sampleRadius

    ; Keep the complete capture inside the monitor containing the requested
    ; point. This avoids reading invalid pixels or an adjacent monitor when the
    ; mouse is near an edge, while preserving the requested sample size.
    GetMonitorRectForMouse(centerPosX, centerPosY, False
        , monitorLeft, monitorTop, monitorRight, monitorBottom)
    monitorWidth  := monitorRight - monitorLeft
    monitorHeight := monitorBottom - monitorTop
    if (sampleSize > monitorWidth || sampleSize > monitorHeight)
        return False

    if (startPosX < monitorLeft)
        startPosX := monitorLeft
    else if ((startPosX + sampleSize) > monitorRight)
        startPosX := monitorRight - sampleSize

    if (startPosY < monitorTop)
        startPosY := monitorTop
    else if ((startPosY + sampleSize) > monitorBottom)
        startPosY := monitorBottom - sampleSize

    ; Get a DC for the full screen.
    screenDc := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    if (!screenDc)
        return False

    ; Create a compatible memory DC.
    memoryDc := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDc, "Ptr")
    if (!memoryDc) {
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDc)
        return False
    }

    ; Create a top-down 32-bit DIB section so copied pixels can be read directly.
    VarSetCapacity(bitmapInfo, 40, 0)
    NumPut(40, bitmapInfo, 0, "UInt")         ; biSize
    NumPut(sampleSize, bitmapInfo, 4, "Int")  ; biWidth
    NumPut(-sampleSize, bitmapInfo, 8, "Int") ; biHeight (negative = top-down)
    NumPut(1, bitmapInfo, 12, "UShort")       ; biPlanes
    NumPut(32, bitmapInfo, 14, "UShort")      ; biBitCount
    NumPut(0, bitmapInfo, 16, "UInt")         ; BI_RGB

    dibBitmap := DllCall("gdi32\CreateDIBSection"
        , "Ptr", memoryDc
        , "Ptr", &bitmapInfo
        , "UInt", 0
        , "Ptr*", pixelBuffer
        , "Ptr", 0
        , "UInt", 0
        , "Ptr")

    if (!dibBitmap || !pixelBuffer) {
        if (dibBitmap)
            DllCall("gdi32\DeleteObject", "Ptr", dibBitmap)
        DllCall("gdi32\DeleteDC", "Ptr", memoryDc)
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDc)
        return False
    }

    oldBitmap := DllCall("gdi32\SelectObject", "Ptr", memoryDc, "Ptr", dibBitmap, "Ptr")

    ; Copy the sample square from the screen into the memory bitmap.
    copySucceeded := DllCall("gdi32\BitBlt"
        , "Ptr", memoryDc
        , "Int", 0
        , "Int", 0
        , "Int", sampleSize
        , "Int", sampleSize
        , "Ptr", screenDc
        , "Int", startPosX
        , "Int", startPosY
        , "UInt", 0x00CC0020) ; SRCCOPY

    if (!copySucceeded) {
        DllCall("gdi32\SelectObject", "Ptr", memoryDc, "Ptr", oldBitmap)
        DllCall("gdi32\DeleteObject", "Ptr", dibBitmap)
        DllCall("gdi32\DeleteDC", "Ptr", memoryDc)
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDc)
        return False
    }

    ; Each pixel is 4 bytes (BGRA).
    rowStride := sampleSize * 4

    ; If no target color was provided, use the requested point as the reference.
    ; Its offset changes when the capture square is shifted away from an edge.
    if (targetColor = "") {
        referenceCol := centerPosX - startPosX
        referenceRow := centerPosY - startPosY
        centerOffset := (referenceRow * rowStride) + (referenceCol * 4)
        targetBlue   := NumGet(pixelBuffer + 0, centerOffset + 0, "UChar")
        targetGreen  := NumGet(pixelBuffer + 0, centerOffset + 1, "UChar")
        targetRed    := NumGet(pixelBuffer + 0, centerOffset + 2, "UChar")
    } else {
        ; Otherwise use the caller-provided RGB target color.
        targetRed    := (targetColor >> 16) & 0xFF
        targetGreen  := (targetColor >> 8) & 0xFF
        targetBlue   := targetColor & 0xFF
    }

    ; Compare every sampled pixel against the chosen reference color.
    Loop, %sampleSize%
    {
        rowIndex := A_Index - 1

        Loop, %sampleSize%
        {
            colIndex    := A_Index - 1
            pixelOffset := (rowIndex * rowStride) + (colIndex * 4)

            blueValue   := NumGet(pixelBuffer + 0, pixelOffset + 0, "UChar")
            greenValue  := NumGet(pixelBuffer + 0, pixelOffset + 1, "UChar")
            redValue    := NumGet(pixelBuffer + 0, pixelOffset + 2, "UChar")

            if (Abs(redValue - targetRed) > tolerance
             || Abs(greenValue - targetGreen) > tolerance
             || Abs(blueValue - targetBlue) > tolerance) {
                DllCall("gdi32\SelectObject", "Ptr", memoryDc, "Ptr", oldBitmap)
                DllCall("gdi32\DeleteObject", "Ptr", dibBitmap)
                DllCall("gdi32\DeleteDC", "Ptr", memoryDc)
                DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDc)
                return False
            }
        }
    }

    DllCall("gdi32\SelectObject", "Ptr", memoryDc, "Ptr", oldBitmap)
    DllCall("gdi32\DeleteObject", "Ptr", dibBitmap)
    DllCall("gdi32\DeleteDC", "Ptr", memoryDc)
    DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDc)

    return True
}
; Use AreaLooksUniformFast9() when:
; faster, but more approximate
; this runs in a hot path,
; you only need a quick heuristic,
; you want to cheaply reject obviously non-uniform regions without paying for a full scan.
AreaLooksUniformFast9(centerPosX, centerPosY, targetColor := "", sampleRadius := 3, tolerance := 18) {

    ; Compute the width/height of the sampled square.
    ; sampleRadius := 3 means a 7x7 captured area.
    sampleSize := (sampleRadius * 2) + 1

    ; Top-left corner of the captured square in screen coordinates.
    startPosX := centerPosX - sampleRadius
    startPosY := centerPosY - sampleRadius

    ; Get a DC for the screen.
    screenDc := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    if (!screenDc)
        return False

    ; Create a memory DC for the off-screen bitmap.
    memoryDc := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDc, "Ptr")
    if (!memoryDc) {
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDc)
        return False
    }

    ; Create a top-down 32-bit DIB section so the copied pixels can be read
    ; directly from memory in normal top-to-bottom order.
    VarSetCapacity(bitmapInfo, 40, 0)
    NumPut(40, bitmapInfo, 0, "UInt")         ; biSize
    NumPut(sampleSize, bitmapInfo, 4, "Int")  ; biWidth
    NumPut(-sampleSize, bitmapInfo, 8, "Int") ; biHeight (negative = top-down)
    NumPut(1, bitmapInfo, 12, "UShort")       ; biPlanes
    NumPut(32, bitmapInfo, 14, "UShort")      ; biBitCount
    NumPut(0, bitmapInfo, 16, "UInt")         ; biCompression = BI_RGB

    ; Create the bitmap and get a pointer to its pixel memory.
    dibBitmap := DllCall("gdi32\CreateDIBSection"
        , "Ptr", memoryDc
        , "Ptr", &bitmapInfo
        , "UInt", 0
        , "Ptr*", pixelBuffer
        , "Ptr", 0
        , "UInt", 0
        , "Ptr")

    if (!dibBitmap || !pixelBuffer) {
        if (dibBitmap)
            DllCall("gdi32\DeleteObject", "Ptr", dibBitmap)

        DllCall("gdi32\DeleteDC", "Ptr", memoryDc)
        DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDc)
        return False
    }

    ; Select the bitmap into the memory DC so BitBlt writes into it.
    oldBitmap := DllCall("gdi32\SelectObject", "Ptr", memoryDc, "Ptr", dibBitmap, "Ptr")

    ; Copy the square around the target point from the screen into memory.
    DllCall("gdi32\BitBlt"
        , "Ptr", memoryDc
        , "Int", 0
        , "Int", 0
        , "Int", sampleSize
        , "Int", sampleSize
        , "Ptr", screenDc
        , "Int", startPosX
        , "Int", startPosY
        , "UInt", 0x00CC0020) ; SRCCOPY

    ; Each 32-bit pixel takes 4 bytes (BGRA).
    rowStride := sampleSize * 4

    ; If no target color was provided, use the center pixel as the reference.
    if (targetColor = "") {
        centerOffset := (sampleRadius * rowStride) + (sampleRadius * 4)
        targetBlue   := NumGet(pixelBuffer + 0, centerOffset + 0, "UChar")
        targetGreen  := NumGet(pixelBuffer + 0, centerOffset + 1, "UChar")
        targetRed    := NumGet(pixelBuffer + 0, centerOffset + 2, "UChar")
    } else {
        ; Otherwise use the caller-provided RGB target color.
        targetRed    := (targetColor >> 16) & 0xFF
        targetGreen  := (targetColor >> 8) & 0xFF
        targetBlue   := targetColor & 0xFF
    }

    ; Sample only 9 points:
    ; center, left, right, top, bottom, and the 4 corners.
    ; This is faster than scanning every pixel in the square while still giving
    ; a useful measure of whether the area is visually uniform.
    pointList := [[0,0], [-sampleRadius,0], [sampleRadius,0], [0,-sampleRadius], [0,sampleRadius]
                , [-sampleRadius,-sampleRadius], [sampleRadius,-sampleRadius], [-sampleRadius,sampleRadius], [sampleRadius,sampleRadius]]

    for pointIndex, pointPair in pointList
    {
        pointPosX   := sampleRadius + pointPair[1]
        pointPosY   := sampleRadius + pointPair[2]
        pixelOffset := (pointPosY * rowStride) + (pointPosX * 4)

        blueValue   := NumGet(pixelBuffer + 0, pixelOffset + 0, "UChar")
        greenValue  := NumGet(pixelBuffer + 0, pixelOffset + 1, "UChar")
        redValue    := NumGet(pixelBuffer + 0, pixelOffset + 2, "UChar")

        ; If any sampled point differs from the reference pixel/color by more
        ; than the allowed tolerance on any RGB channel, the area is not
        ; uniform enough.
        if (Abs(redValue - targetRed) > tolerance
         || Abs(greenValue - targetGreen) > tolerance
         || Abs(blueValue - targetBlue) > tolerance) {
            DllCall("gdi32\SelectObject", "Ptr", memoryDc, "Ptr", oldBitmap)
            DllCall("gdi32\DeleteObject", "Ptr", dibBitmap)
            DllCall("gdi32\DeleteDC", "Ptr", memoryDc)
            DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDc)
            return False
        }
    }

    ; Clean up GDI objects.
    DllCall("gdi32\SelectObject", "Ptr", memoryDc, "Ptr", oldBitmap)
    DllCall("gdi32\DeleteObject", "Ptr", dibBitmap)
    DllCall("gdi32\DeleteDC", "Ptr", memoryDc)
    DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDc)

    ; All 9 sampled points were close enough to the reference color.
    return True
}

ClearWindowTitlePopup() {
    global WindowTitleID, WindowTitle

    if !(WindowTitleID && WinExist("ahk_id " . WindowTitleID))
        return

    delayTime  := 20
    alphaStart := 200
    alphaStep  := 25
    alphaStop  := 25
    alphaNow   := alphaStart

    while (alphaNow >= alphaStop)
    {
        WinSet, Transparent, %alphaNow%, ahk_id %WindowTitleID%
        Sleep, %delayTime%
        alphaNow -= alphaStep
    }

    Gui, WindowTitle:Hide
    return
}

; Create the Alt+Tab title popup once so rapid cycle steps can reuse the same
; GUI and only mutate its icon/text instead of rebuilding the window each time.
EnsureWindowTitlePopupGui() {
    global WindowTitleGuiReady, WindowTitleID, WindowTitleIcon, WindowTitleText

    if (WindowTitleGuiReady && WindowTitleID && WinExist("ahk_id " . WindowTitleID))
        return WindowTitleID

    Gui, WindowTitle:Destroy
    Gui, WindowTitle: +LastFound +AlwaysOnTop -Caption +ToolWindow +HwndWindowTitleID
    Gui, WindowTitle: Color, 000000
    Gui, WindowTitle: Margin, 20, 16
    Gui, WindowTitle: Font, s24
    Gui, WindowTitle: Add, Picture, vWindowTitleIcon x0 y0 w48 h48 Hidden
    Gui, WindowTitle: Add, Text, vWindowTitleText x0 y8 cWhite,

    WindowTitleGuiReady := True
    return WindowTitleID
}

; Measure the retained title control's current string with its actual GUI font
; so DrawWindowTitlePopup() can size and vertically align the text precisely.
_MeasureWindowTitlePopupTextSize(textHwnd, text, ByRef textWidth, ByRef textHeight) {
    textWidth  := 0
    textHeight := 0

    if (!textHwnd || text = "")
        return false

    textDC := DllCall("user32\GetDC", "ptr", textHwnd, "ptr")
    if !textDC
        return false

    textFont := DllCall("user32\SendMessage", "ptr", textHwnd, "uint", 0x31, "ptr", 0, "ptr", 0, "ptr")
    if (textFont)
        oldFont := DllCall("gdi32\SelectObject", "ptr", textDC, "ptr", textFont, "ptr")

    VarSetCapacity(textSize, 8, 0)
    if !DllCall("gdi32\GetTextExtentPoint32", "ptr", textDC, "str", text, "int", StrLen(text), "ptr", &textSize) {
        if (oldFont)
            DllCall("gdi32\SelectObject", "ptr", textDC, "ptr", oldFont, "ptr")
        DllCall("user32\ReleaseDC", "ptr", textHwnd, "ptr", textDC)
        return false
    }

    if (oldFont)
        DllCall("gdi32\SelectObject", "ptr", textDC, "ptr", oldFont, "ptr")
    DllCall("user32\ReleaseDC", "ptr", textHwnd, "ptr", textDC)

    textWidth  := NumGet(textSize, 0, "int")
    textHeight := NumGet(textSize, 4, "int")
    return true
}

; Hides the retained Alt+Tab title popup without tearing down the underlying
; GUI so the next cycle can show it again without paying reconstruction cost.
HideWindowTitlePopup() {
    global WindowTitleID

    if (WindowTitleID && WinExist("ahk_id " . WindowTitleID))
        Gui, WindowTitle:Hide
}

DrawWindowTitlePopup(hwnd, vtext := "", pathToExe := "", centerOnWin := False) {
    global bufferedCycleAdvance, hitTAB, hitTilde, k_Opacity, WindowTitleID, WindowTitle, WindowTitleIcon, WindowTitleText

    static HWND_TOPMOST   := -1
    static SWP_NOMOVE     := 0x0002
    static SWP_NOACTIVATE := 0x0010
    static SWP_NOSIZE     := 0x0001
    static SWP_SHOWWINDOW := 0x0040

    cardPadX      := 20
    cardPadY      := 16
    iconGap       := 16
    iconSize      := 48
    textWidthPad  := 12

    If (!GetKeyState("LAlt", "P") && !GetKeyState("Esc","P"))
        Return
    ; Popup creation can take long enough for the next Tab/` press to arrive before the
    ; Cycle()/CycleAppWindows() loop reaches its next KeyWait. Latch that press here.
    bufferedCycleAdvance := (bufferedCycleAdvance || (hitTAB && GetKeyState("Tab","P")) || (hitTilde && GetKeyState("`","P")))

    EnsureWindowTitlePopupGui()

    If (StrLen(vtext) > 60) {
        vtext := SubStr(vtext, 1, 60) . "..."
    }

    If (!GetKeyState("LAlt", "P") && !GetKeyState("Esc","P"))
        Return
    ; Popup creation can take long enough for the next Tab/` press to arrive before the
    ; Cycle()/CycleAppWindows() loop reaches its next KeyWait. Latch that press here.
    bufferedCycleAdvance := (bufferedCycleAdvance || (hitTAB && GetKeyState("Tab","P")) || (hitTilde && GetKeyState("`","P")))

    If (pathToExe) {
        If InStr(pathToExe, "ApplicationFrameHost", False) {
            ; *Icon3 *w48 *h48 C:\Windows\System32\SHELL32.dll tells the Picture control to load icon resource 3 from SHELL32.dll and display it at 48x4
            iconSpec := "*Icon3 *w48 *h48 " . A_WinDir . "\System32\SHELL32.dll"
        }
        Else {
            iconSpec := "*w48 *h48 " . pathToExe
        }
    }
    Else {
        iconSpec := ""
    }

    ; In `GuiControl, WindowTitle:, WindowTitleText, %vtext%`:
    ; `WindowTitle` names the GUI, the blank slot means "change this control's
    ; value/text", and `WindowTitleText` is the specific Text control to update.
    ; Set that retained Text control first so later measurement uses this cycle's
    ; current window/app label instead of the previous cycle's stale text.
    GuiControl, WindowTitle:, WindowTitleText, %vtext%
    ; Read back the text control HWND so the measurement helper can query the
    ; exact font metrics of this live control instead of estimating width.
    GuiControlGet, textHwnd, WindowTitle:Hwnd, WindowTitleText
    _MeasureWindowTitlePopupTextSize(textHwnd, vtext, textWidth, textHeight)
    if (textWidth < 24)
        textWidth  := 24
    if (textHeight < 24)
        textHeight := 24
    textWidth += textWidthPad

    if (iconSpec != "") {
        ; Outer GUI: WindowTitle
        ; popupWidth = leftPad + icon + gap + textWidth + rightPad
        ; popupHeight = topPad + max(iconHeight, textHeight) + bottomPad
        ; +------------------------------------------------------+
        ; |                                                      |
        ; |  x=iconX,y=iconY                                     |
        ; |  +--------+   x=textX,y=textY                        |
        ; |  |  icon  |   +-------------------------------+      |
        ; |  |Picture |   | window title text             |      |
        ; |  +--------+   | Text control                  |      |
        ; |               +-------------------------------+      |
        ; |                                                      |
        ; +------------------------------------------------------+
        contentHeight := Max(iconSize, textHeight)
        iconX         := cardPadX
        iconY         := cardPadY + Floor((contentHeight - iconSize) / 2)
        textX         := cardPadX + iconSize + iconGap
        textY         := cardPadY + Floor((contentHeight - textHeight) / 2)
        popupWidth    := cardPadX + iconSize + iconGap + textWidth + cardPadX
        popupHeight   := cardPadY + contentHeight + cardPadY

        ; Here the target control is `WindowTitleIcon`, the retained Picture
        ; control inside the `WindowTitle` GUI. This swaps that control's image
        ; to the current app icon source without rebuilding the GUI.
        GuiControl, WindowTitle:, WindowTitleIcon, %iconSpec%
        ; `MoveDraw` is the GuiControl subcommand. It tells AutoHotkey to move
        ; and resize the `WindowTitleIcon` Picture control to this rectangle,
        ; then redraw that control immediately in its new slot.
        GuiControl, WindowTitle:MoveDraw, WindowTitleIcon, % "x" iconX " y" iconY " w" iconSize " h" iconSize
        ; `Show` is another GuiControl subcommand. It makes the
        ; `WindowTitleIcon` Picture control visible when this entry has an icon.
        GuiControl, WindowTitle:Show, WindowTitleIcon
    }
    else {
        textX       := cardPadX
        textY       := cardPadY
        popupWidth  := cardPadX + textWidth + cardPadX
        popupHeight := cardPadY + textHeight + cardPadY
        ; `Hide` is the matching GuiControl subcommand. It hides the
        ; `WindowTitleIcon` Picture control for text-only entries so the text
        ; can use the simpler no-icon card layout.
        GuiControl, WindowTitle:Hide, WindowTitleIcon
    }

    ; `MoveDraw` here targets the `WindowTitleText` Text control. Resize and
    ; reposition that specific control to the measured rectangle, then redraw it
    ; immediately before the popup window itself is shown.
    GuiControl, WindowTitle:MoveDraw, WindowTitleText, % "x" textX " y" textY " w" textWidth " h" textHeight

    If (!GetKeyState("LAlt", "P") && !GetKeyState("Esc","P"))
        Return
    ; Popup creation can take long enough for the next Tab/` press to arrive before the
    ; Cycle()/CycleAppWindows() loop reaches its next KeyWait. Latch that press here.
    bufferedCycleAdvance := (bufferedCycleAdvance || (hitTAB && GetKeyState("Tab","P")) || (hitTilde && GetKeyState("`","P")))

    If (centerOnWin) {
        WinGetPos, targetX, targetY, targetWidth, targetHeight, ahk_id %hwnd%
        drawX := Round(targetX + (targetWidth / 2) - (popupWidth / 2))
        drawY := Round(targetY + (targetHeight / 2) - (popupHeight / 2))
    }
    Else {
        drawX := Round(CoordXCenterScreen() - (popupWidth / 2))
        drawY := Round(CoordYCenterScreen() - (popupHeight / 2))
    }

    Gui, WindowTitle: Show, % "x" drawX " y" drawY " w" popupWidth " h" popupHeight " NoActivate"
    ; The retained WindowTitle GUI is no longer recreated on every Alt+Tab step,
    ; so explicitly raise this popup HWND to the top of the topmost band after
    ; Show. Without this, the already-visible dim Overlay GUI can stay above it
    ; in z-order and make the title card appear to have vanished.
    DllCall("user32\SetWindowPos"
        , "ptr", WindowTitleID
        , "ptr", HWND_TOPMOST
        , "int", 0
        , "int", 0
        , "int", 0
        , "int", 0
        , "uint", SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW)
    WinSet, Transparent, 1, ahk_id %WindowTitleID%

    If (!GetKeyState("LAlt", "P") && !GetKeyState("Esc","P"))
        Return
    ; Popup creation can take long enough for the next Tab/` press to arrive before the
    ; Cycle()/CycleAppWindows() loop reaches its next KeyWait. Latch that press here.
    bufferedCycleAdvance := (bufferedCycleAdvance || (hitTAB && GetKeyState("Tab","P")) || (hitTilde && GetKeyState("`","P")))

    ; WinMove, ahk_id %WindowTitleID%,, drawX-floor(w/2), drawY-floor(h/2)
    WinSet, AlwaysOnTop, On, ahk_id %WindowTitleID%
    WinSet, Transparent, %k_Opacity%, ahk_id %WindowTitleID%

    Return WindowTitleID
}

GetAppDisplayNameFromHwnd(windowHwnd) {
    local processPath
    local appName

    WinGet, processPath, ProcessPath, ahk_id %windowHwnd%
    if (!processPath)
        return ""

    ; Prefer FileDescription
    appName := GetFileVersionString(processPath, "FileDescription")
    if (appName != "")
        return appName

    ; Fallback to ProductName
    appName := GetFileVersionString(processPath, "ProductName")
    if (appName != "")
        return appName

    ; Final fallback: executable file name without extension
    SplitPath, processPath, fileName, dirName, extName, fileNameNoExt
    return fileNameNoExt
}

GetFileVersionString(filePath, stringName) {
    local dummyHandle
    local infoSize
    local infoBuffer
    local translatePtr
    local translateLen
    local langCode
    local codePage
    local queryBlock
    local valuePtr
    local valueLen
    local resultText

    dummyHandle := 0
    infoSize := DllCall("Version\GetFileVersionInfoSize", "Str", filePath, "UInt*", dummyHandle, "UInt")
    if (!infoSize)
        return ""

    VarSetCapacity(infoBuffer, infoSize, 0)
    if !DllCall("Version\GetFileVersionInfo", "Str", filePath, "UInt", 0, "UInt", infoSize, "Ptr", &infoBuffer)
        return ""

    ; Read translation table
    if !DllCall("Version\VerQueryValue", "Ptr", &infoBuffer, "Str", "\VarFileInfo\Translation", "Ptr*", translatePtr, "UInt*", translateLen)
        return ""

    ; First language/codepage pair
    langCode := NumGet(translatePtr + 0, 0, "UShort")
    codePage := NumGet(translatePtr + 0, 2, "UShort")

    queryBlock := Format("\StringFileInfo\{1:04X}{2:04X}\{3}", langCode, codePage, stringName)

    if !DllCall("Version\VerQueryValue", "Ptr", &infoBuffer, "Str", queryBlock, "Ptr*", valuePtr, "UInt*", valueLen)
        return ""

    resultText := StrGet(valuePtr, valueLen, "UTF-16")
    return RTrim(resultText, "`0")
}

InitCOM_STA() {
    global comInitd

    if (comInitd != "") {
        return comInitd
    }

    ; COINIT_APARTMENTTHREADED = 0x2
    hr := DllCall("ole32\CoInitializeEx", "Ptr", 0, "UInt", 0x2, "Int")

    if (hr = 0) {
        comInitd := 2
    } else if (hr = 1) {
        comInitd := 1
    } else {
        comInitd := 0
    }

    return comInitd
}

;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
; https://github.com/Drugoy/Autohotkey-scripts-.ahk/blob/master/Libraries/Acc.ahk
;------------------------------------------------------------------------------
Acc_Init() {
    static hMod := 0

    if (hMod)
        return true

    hMod := DllCall("kernel32\LoadLibrary", "Str", "oleacc.dll", "Ptr")
    return (hMod != 0)
}
; ChatGPT
Acc_CreateChildRef(parentIA, childId) {
    local childRef := {}
    childRef.__accChildRef := true
    childRef.acc := parentIA
    childRef.child := childId
    return childRef
}

Acc_IsChildRef(accObj) {
    return IsObject(accObj)
        && ObjHasKey(accObj, "__accChildRef")
        && (accObj.__accChildRef = true)
}
; ChatGPT
Acc_GetRoleText(nRole) {
    static c_role := {}
    local textSize, roleText

    if (c_role.HasKey(nRole))
        return c_role[nRole]

    textSize := DllCall("oleacc\GetRoleText", "UInt", nRole, "Ptr", 0, "UInt", 0)
    VarSetCapacity(roleText, (A_IsUnicode ? 2 : 1) * (textSize + 1), 0)
    DllCall("oleacc\GetRoleText", "UInt", nRole, "Str", roleText, "UInt", textSize + 1)

    c_role[nRole] := roleText
    return roleText
}
; ChatGPT
Acc_FindLikelyAddressMarker(rootAcc, maxNodes := 60) {
    local queueList := []
    local queueIndex := 1
    local seenCount := 0
    local currentAcc, currentName, currentValue
    local childrenList, childIndex, childAcc

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
; ChatGPT
Acc_LocationSafe(accObj, ByRef xPos, ByRef yPos, ByRef wid, ByRef hei, childId := "") {
    local iaObj, childVal, childNum

    xPos := ""
    yPos := ""
    wid := ""
    hei := ""

    if !IsObject(accObj)
        return false

    if (Acc_IsChildRef(accObj)) {
        iaObj := accObj.acc
        childVal := accObj.child
    }
    else {
        iaObj := accObj
        childVal := (childId = "") ? 0 : childId
    }

    childNum := childVal + 0
    if (childNum = 0 && childVal != 0 && childVal != "0")
        return false

    try {
        iaObj.accLocation(xPos, yPos, wid, hei, ComObjParameter(3, childNum))
        return true
    } catch {
        xPos := ""
        yPos := ""
        wid := ""
        hei := ""
        return false
    }
}
; ChatGPT
Acc_PointInAccRect(accObj, sx, sy) {
    ; Returns True only if (sx,sy) lies within accObj's screen rectangle.
    ; If we can't get a rectangle, fail closed.
    local ax, ay, aw, ah

    if (!Acc_LocationSafe(accObj, ax, ay, aw, ah))
        return false

    if (aw <= 0 || ah <= 0)
        return false

    return (sx >= ax && sx < ax + aw && sy >= ay && sy < ay + ah)
}
; ChatGPT
Acc_GetObjectAtScreenPoint(xPos, yPos) {
    local accObj, pointStruct, hwndUnder, accRoot, hitVal, childId, childObj

    accObj := Acc_ObjectFromPoint(, xPos, yPos)
    if IsObject(accObj)
        return accObj

    ; Fallback path: WindowFromPoint -> Acc_ObjectFromWindow -> accHitTest

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

    ; accHitTest expects SCREEN coordinates
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
; ChatGPT
Acc_ObjectFromPoint(ByRef childIdOut := "", xPos := "", yPos := "") {
    local pointStruct, xVal, yVal, pt64, hr, pacc := 0, vt
    local varChild

    Acc_Init()

    VarSetCapacity(varChild, (A_PtrSize = 8) ? 24 : 16, 0)

    if (xPos = "" || yPos = "") {
        VarSetCapacity(pointStruct, 8, 0)
        if !DllCall("user32\GetCursorPos", "Ptr", &pointStruct)
        {
            childIdOut := 0
            return
        }
        xVal := NumGet(pointStruct, 0, "Int")
        yVal := NumGet(pointStruct, 4, "Int")
    }
    else {
        xVal := xPos + 0
        yVal := yPos + 0
    }

    ; Pack POINT into 64-bit: low DWORD = x, high DWORD = y
    pt64 := (xVal & 0xFFFFFFFF) | ((yVal & 0xFFFFFFFF) << 32)

    hr := DllCall("oleacc\AccessibleObjectFromPoint"
        , "Int64", pt64
        , "Ptr*", pacc
        , "Ptr", &varChild
        , "Int")

    if (hr != 0 || !pacc) {
        childIdOut := 0
        return
    }

    vt := NumGet(varChild, 0, "UShort")
    childIdOut := (vt = 3) ? NumGet(varChild, 8, "Int") : 0

    try
        return ComObjEnwrap(9, pacc, 1)
    catch {
        childIdOut := 0
        return
    }
}
; ChatGPT
Acc_ObjectFromWindow(hWnd, idObject := 0xFFFFFFFC) {
    local accObj := ""

    Acc_Init()

    if (Acc_FromWindow(hWnd, idObject, accObj))
        return accObj

    return ""
}
; ChatGPT
Acc_TryGetIAccessibleSafe(accObj) {
    local iAccessiblePtr := 0

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
; ChatGPT
Acc_RoleNameSafe(accObj) {
    local iaObj, childId, roleValue := "", roleNumber

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
; ChatGPT
Acc_GetToolbarAddressPath(tbHwnd) {
    acc := Acc_ObjectFromWindow(tbHwnd)
    if !IsObject(acc)
        return ""

    ; Bounded search so it stays quick
    return Acc_FindLikelyPathText(acc, 140)
}
; ChatGPT
Acc_FindLikelyPathText(rootAcc, maxNodes := 140) {
    local queueList := []
    local queueIndex := 1
    local seenCount := 0
    local currentAcc, currentName, currentValue
    local childrenList, childIndex, childAcc

    if !IsObject(rootAcc)
        return ""

    queueList.Push(rootAcc)

    while (queueIndex <= queueList.Length() && seenCount < maxNodes)
    {
        currentAcc := queueList[queueIndex]
        queueIndex += 1
        seenCount += 1

        currentValue := Acc_ValueSafe(currentAcc)
        if (currentValue != "" && currentValue != "Address Band" && Acc_LooksLikePath(currentValue))
            return currentValue

        currentName := Acc_NameSafe(currentAcc)
        if (currentName != "" && currentName != "Address Band" && Acc_LooksLikePath(currentName))
            return currentName

        childrenList := Acc_GetChildrenListSafe(currentAcc)
        for childIndex, childAcc in childrenList
        {
            if IsObject(childAcc)
                queueList.Push(childAcc)
        }
    }

    return ""
}
; ChatGPT
Acc_LooksLikePath(s) {
    ; Heuristic: accept full paths, UNC, or shell-like breadcrumb with backslashes.
    ; You can tighten/expand this based on what you see on your system.
    if (s = "" || s = "Address Band")
        return false

    ; Strong matches first
    if InStr(s, ":\")
        return true

    if InStr(s, "\\")
        return true

    ; Explorer breadcrumb-ish path fragments:
    ; require at least one backslash and avoid obvious non-path labels
    if (InStr(s, "\")
     && !InStr(s, "Address Band")
     && !InStr(s, "Toolbar")
     && !InStr(s, "Ribbon"))
        return true

    return false
}
; ChatGPT
Acc_GetChildrenListSafe(accObj, maxChildren := 60) {
    local iaObj, childrenCount := 0, fetchedCount := 0
    local fetchCount, cbVariant, bufferBytes
    local childIndex, offsetBytes, variantType
    local childId, dispatchPointer, outputList := []
    local resultCode := 0
    local buf

    if !IsObject(accObj)
        return outputList

    iaObj := Acc_IsChildRef(accObj) ? accObj.acc : accObj
    if !IsObject(iaObj)
        return outputList

    try
        childrenCount := iaObj.accChildCount
    catch
        return outputList

    if (childrenCount <= 0)
        return outputList

    fetchCount := childrenCount
    if (maxChildren > 0 && fetchCount > maxChildren)
        fetchCount := maxChildren

    cbVariant := (A_PtrSize = 8) ? 24 : 16
    bufferBytes := fetchCount * cbVariant
    VarSetCapacity(buf, bufferBytes, 0)

    try
    {
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
        return outputList

    outputList.Capacity := fetchedCount

    Loop, %fetchedCount%
    {
        childIndex := A_Index - 1
        offsetBytes := childIndex * cbVariant
        variantType := NumGet(buf, offsetBytes + 0, "UShort")

        if (variantType = 9) ; VT_DISPATCH
        {
            dispatchPointer := NumGet(buf, offsetBytes + 8, "Ptr")
            if (dispatchPointer)
                outputList.Push(ComObjEnwrap(9, dispatchPointer, 1))
        }
        else if (variantType = 3) ; VT_I4
        {
            childId := NumGet(buf, offsetBytes + 8, "Int")
            outputList.Push(Acc_CreateChildRef(iaObj, childId))
        }
    }

    return outputList
}
; ChatGPT
Acc_GetFocusedObject() {
    static OBJID_CARET  := 0xFFFFFFF8
    static OBJID_CLIENT := 0xFFFFFFFC

    WinGet, hWnd, ID, A
    if !hWnd
        return ""

    ; Try CARET object first
    if (Acc_FromWindow(hWnd, OBJID_CARET, acc))
        return acc

    ; Fallback: CLIENT object
    if (Acc_FromWindow(hWnd, OBJID_CLIENT, acc))
        return acc

    return ""
}
; ChatGPT
Acc_FromWindow(hWnd, objID, ByRef acc) {
    static iid
    static iidReady := false
    local pacc := 0

    if (!iidReady) {
        VarSetCapacity(iid, 16, 0)
        DllCall("ole32\CLSIDFromString"
            , "WStr", "{618736E0-3C3D-11CF-810C-00AA00389B71}"
            , "Ptr", &iid)
        iidReady := true
    }

    if (DllCall("oleacc\AccessibleObjectFromWindow"
        , "Ptr", hWnd
        , "UInt", objID
        , "Ptr", &iid
        , "Ptr*", pacc
        , "Int") = 0)
    {
        acc := ComObjEnwrap(9, pacc, 1)
        return true
    }

    return false
}
; ChatGPT
Acc_FindHeaderObject(accObj, cls, outlineRole, colHeaderRole, menuPopupRole, directUIHwnd := 0) {
    local cur, role, needQuirkCheck, hostHwnd, checked

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

        ; Only pay for this check once or twice (it's a DllCall)
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
; ChatGPT
Acc_WindowFromObjectSafe(accObj) {
    local iaObj, hwnd, hr

    if !IsObject(accObj)
        return 0

    iaObj := accObj

    if (Acc_IsChildRef(accObj))
        iaObj := accObj.acc

    hwnd := 0
    hr := 0

    try
    {
        hr := DllCall("oleacc\WindowFromAccessibleObject"
            , "Ptr", ComObjValue(iaObj)
            , "Ptr*", hwnd
            , "Int")
    }
    catch
        return 0

    if (hr != 0)
        return 0

    return hwnd
}
; ChatGPT
Acc_NameIsKnownColumnSafe(accObj) {
    static knownNames := { "Name": true
        , "Date modified": true
        , "Type": true
        , "Size": true
        , "Date created": true
        , "Authors": true
        , "Title": true }

    local nameStr

    if !IsObject(accObj)
        return 0

    nameStr := Acc_NameSafe(accObj)
    if (nameStr = "")
        return 0

    return knownNames.HasKey(nameStr)
}
; ChatGPT
Acc_ResolveTarget(accObj, ByRef iaObj, ByRef childId) {
    if !IsObject(accObj)
        return false

    if (Acc_IsChildRef(accObj)) {
        iaObj := accObj.acc
        childId := accObj.child
        return true
    }

    iaObj := accObj
    childId := 0
    return true
}
; ChatGPT
Acc_NameSafe(accObj) {
    local iaObj, childId, nameStr := ""

    if !Acc_ResolveTarget(accObj, iaObj, childId)
        return ""

    try
        nameStr := iaObj.accName(childId)
    catch
        return ""

    return nameStr
}
; ChatGPT
Acc_ValueSafe(accObj) {
    local iaObj, childId, valueStr := ""

    if !Acc_ResolveTarget(accObj, iaObj, childId)
        return ""

    try
        valueStr := iaObj.accValue(childId)
    catch
        return ""

    return valueStr
}
; ChatGPT
Acc_RoleIdSafe(accObj) {
    local iaObj, childId, roleVal := "", roleNum

    if !Acc_ResolveTarget(accObj, iaObj, childId)
        return 0

    try
        roleVal := iaObj.accRole(childId)
    catch
        return 0

    roleNum := roleVal + 0
    if (roleNum = 0 && roleVal != 0 && roleVal != "0")
        return 0

    return roleNum
}
; ChatGPT
Acc_ParentSafe(accObj) {
    local parentObj := ""

    if !IsObject(accObj)
        return ""

    if (Acc_IsChildRef(accObj))
        return accObj.acc

    try
        parentObj := accObj.accParent
    catch
        return ""

    return parentObj
}
/*
    SafeUIA_* wrappers provide a small defensive layer over UIA_Interface so
    callers do not have to handle COM exceptions, missing elements, or shared
    timeout state directly.

    Shared parameter conventions in this wrapper block:
    x, y:
    Screen coordinates in pixels.

    timeout values:
    Milliseconds.

    TreeScope values passed to UIA_Interface searches:
    0x2 = UIA_TreeScope_Children (direct children only)
    0x4 = UIA_TreeScope_Descendants (search the full descendant subtree)

    matchMode values:
    1 = starts with
    2 = contains
    3 = exact match
    RegEx = regular-expression match supported by UIA_Interface

    cacheRequest:
    Optional UIA cache-request object. Blank means "do not use build-cache for
    this lookup; read properties normally."

    SafeUIA_ElementFromPoint():
    Return the UIA element under a screen point.
    This is the UIA equivalent of "what control is under the mouse right now?"
    The wrapper applies per-call UIA timeouts and restores the shared UIA
    object's prior timeout state before returning.

    Parameters:
    x, y = screen point to query.
    default = value returned if UIA lookup fails.
    transactionTimeout := 250 = per-call UIA transaction timeout in ms.
    connectionTimeout := 20000 = per-call UIA connection timeout in ms.
    retryAfterFailure := True = rebuild UIA and make one additional lookup attempt.
*/
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
    Return the root UIA element for a window/control HWND.
    This is the UIA equivalent of starting from a known window handle and then
    searching inside that window's automation tree.

    Parameters:
    hwnd                                   = target window/control handle to convert into a UIA root element.
    default                                = value returned if hwnd is blank or UIA lookup fails.
    activateChromiumAccessibility := False = pass-through flag for UIA_Interface's ElementFromHandle(); when True, let the library try to
                                     activate Chromium accessibility for that handle if needed.
    transactionTimeout            := 2000  = per-call UIA transaction timeout in ms.
    connectionTimeout             := 20000 = per-call UIA connection timeout in ms.
    retryAfterFailure             := True  = rebuild UIA and retry once after failure.
*/
SafeUIA_ElementFromHandle(hwnd, default := "", activateChromiumAccessibility := False, transactionTimeout := 2000, connectionTimeout := 20000, retryAfterFailure := True) {
    global UIA
    priorConnectionTimeout := ""
    priorTransactionTimeout := ""
    result := default

    if (!hwnd)
        return default

    if (transactionTimeout <= 0)
        transactionTimeout := 2000
    if (connectionTimeout <= 0)
        connectionTimeout := 20000

    if (!IsObject(UIA))
        UIA := UIA_Interface()

    ; Force an explicit timeout on every handle lookup so earlier fast probes
    ; cannot leave this shared UIA path in a too-short timeout mode.
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
        result := UIA.ElementFromHandle(hwnd, activateChromiumAccessibility)
    } catch {
        UIA := ""
        if (retryAfterFailure) {
            UIA := UIA_Interface()
            try
                UIA.TransactionTimeout := transactionTimeout
            catch e {
            }
            try
                UIA.ConnectionTimeout  := connectionTimeout
            catch e {
            }

            try
                result := UIA.ElementFromHandle(hwnd, activateChromiumAccessibility)
            catch
                result := default
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
    Search for the first descendant element with the requested UIA Name.
    It tries a cheaper near-root search first, then falls back to a broader
    subtree search if needed.

    Parameters:
    rootEl                = starting UIA element whose subtree will be searched.
    name                  = UIA Name property to match.
    default               = value returned if the search fails.
    childScope    := 0x2  = first-pass scope, UIA_TreeScope_Children, meaning search only direct children of rootEl.
    fallbackScope := 0x4  = second-pass scope, UIA_TreeScope_Descendants, meaning search all descendants under rootEl.
    matchMode     := 3    = exact-name match by default.
    caseSensitive := True = keep case-sensitive string matching by default.
    cacheRequest  := ""   = no UIA cache request unless the caller supplies one.
*/
SafeUIA_FindFirstByNameFast(rootEl, name, default := "", childScope := 0x2, fallbackScope := 0x4, matchMode := 3, caseSensitive := True, cacheRequest := "") {
    if !IsObject(rootEl)
        return default

    el := ""
    try
        el := rootEl.FindFirstByName(name, childScope, matchMode, caseSensitive, cacheRequest)
    catch e
        el := ""

    if IsObject(el)
        return el

    try
        return rootEl.FindFirstByName(name, fallbackScope, matchMode, caseSensitive, cacheRequest)
    catch e
        return default
}

/*
    Wait for a UIA element matching expr to appear.
    It spends a short time on a fast narrow search first, then uses the
    remaining budget on a broader search so common cases resolve sooner.

    Parameters:
    rootEl                  = starting UIA element whose subtree will be polled.
    expr                    = UIA_Interface FindFirstBy()/WaitElementExist() expression, such as "Name=Open" or "ControlType=Button".
    default                 = value returned if nothing is found before timeout.
    fastTimeout     := 200  = initial narrow-search budget in ms.
    fallbackTimeout := 5000 = total fallback budget in ms; the time already spent in the fast pass is subtracted before the broader retry.
    fastScope       := 0x2  = UIA_TreeScope_Children for the quick first pass.
    fallbackScope   := 0x4  = UIA_TreeScope_Descendants for the broader retry.
    matchMode       := 3    = exact-match mode by default.
    caseSensitive   := True = keep case-sensitive string matching by default.
    cacheRequest    := ""   = no UIA cache request unless the caller supplies one.
*/
SafeUIA_WaitElementExistFast(rootEl, expr, default := "", fastTimeout := 200, fallbackTimeout := 5000, fastScope := 0x2, fallbackScope := 0x4, matchMode := 3, caseSensitive := True, cacheRequest := "") {
    if !IsObject(rootEl)
        return default

    el := ""
    startTick := A_TickCount
    if (fastTimeout > 0) {
        try
            el := rootEl.WaitElementExist(expr, fastScope, matchMode, caseSensitive, fastTimeout, cacheRequest)
        catch e
            el := ""

        if IsObject(el)
            return el
    }

    remainingTimeout := fallbackTimeout
    if (fallbackTimeout >= 0) {
        remainingTimeout -= (A_TickCount - startTick)
        if (remainingTimeout < 0)
            remainingTimeout := 0
    }

    try
        return rootEl.WaitElementExist(expr, fallbackScope, matchMode, caseSensitive, remainingTimeout, cacheRequest)
    catch e
        return default
}
/*
    Read the small set of UIA properties a caller needs in one local snapshot
    so clustered hot paths avoid repeated COM property calls on the same element.

    Parameters:
    el = UIA element to read from.
    fields := "" = pipe-delimited property list to fetch. Blank means fetch the
                    wrapper's standard set:
                    autoId|className|controlType|localizedType|name|nativeHwnd

    Returned object keys:
    autoId        = UIA AutomationId
    className     = UIA ClassName
    controlType   = numeric UIA control-type ID
    isEnabled     = UIA enabled/disabled flag, when requested
    localizedType = human-readable localized control-type label
    name          = UIA Name
    nativeHwnd    = provider-reported native window handle, if any
*/
SafeUIA_GetElementSnapshot(el, fields := "") {
    fieldList := (fields = "") ? "|autoId|className|controlType|localizedType|name|nativeHwnd|" : "|" . fields . "|"
    info := { autoId: ""
        , className: ""
        , controlType: ""
        , isEnabled: ""
        , localizedType: ""
        , name: ""
        , nativeHwnd: 0 }

    if !IsObject(el)
        return info

    if InStr(fieldList, "|autoId|") {
        try
            info.autoId := el.AutomationId
        catch e
            info.autoId := ""
    }
    if InStr(fieldList, "|className|") {
        try
            info.className := el.CurrentClassName
        catch e
            info.className := ""
    }
    if InStr(fieldList, "|controlType|") {
        try
            info.controlType := el.CurrentControlType
        catch e
            info.controlType := ""
    }
    if InStr(fieldList, "|isEnabled|") {
        try
            info.isEnabled := el.CurrentIsEnabled
        catch e
            info.isEnabled := ""
    }
    if InStr(fieldList, "|localizedType|") {
        try
            info.localizedType := el.CurrentLocalizedControlType
        catch e
            info.localizedType := ""
    }
    if InStr(fieldList, "|name|") {
        try
            info.name := el.CurrentName
        catch e
            info.name := ""
    }
    if InStr(fieldList, "|nativeHwnd|") {
        try
            info.nativeHwnd := el.CurrentNativeWindowHandle
        catch e
            info.nativeHwnd := 0
    }

    return info
}
/*
    Read an element's numeric UIA control type, such as List, Pane, or Header.
    Returns default if the element is missing or the UIA property read fails.

    Parameters:
    el            = UIA element to read from.
    default := "" = fallback value if the property cannot be read.
*/
SafeUIA_GetControlType(el, default := "") {
    if !IsObject(el)
        return default
    try
        return el.CurrentControlType
    catch e
        return default

}
/*
    Read an element's human-readable control type label, such as "list" or
    "pane", instead of the numeric UIA control type ID.

    Parameters:
    el            = UIA element to read from.
    default := "" = fallback value if the property cannot be read.
*/
SafeUIA_GetLocalizedControlType(el, default := "") {
    if !IsObject(el)
        return default
    try
        return el.CurrentLocalizedControlType
    catch e
        return default
}
/*
    Read the UIA Name property, which is the accessibility/display label that
    automation clients use to identify the element.

    Parameters:
    el            = UIA element to read from.
    default := "" = fallback value if the property cannot be read.
*/
SafeUIA_GetName(el, default := "") {
    if !IsObject(el)
        return default
    try
        return el.CurrentName
    catch e
        return default
}
/*
    Read the UIA ClassName property, which is the provider-reported class label
    such as UIItem, UIItemsView, DirectUI, or other framework-specific names.

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
    Read the UIA Orientation property when a control reports horizontal or
    vertical layout information.

    Parameters:
    el                  = UIA element to read from.
    default := 0        = fallback orientation value if the property cannot be read.
                          Common values are 0 = NotApplicable, 1 = horizontal, 2 = vertical.
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
    Return the direct UIA parent element.
    Use this when walking upward through the automation tree.

    Parameters:
    el = UIA element whose direct parent should be returned.
*/
SafeUIA_GetParent(el) {
    if !IsObject(el)
        return ""
    try
        return el.Parent
    catch e
        return ""
}
/*
    Read the UIA AutomationId property, which is the provider's stable
    identifier when one is exposed for the element.

    Parameters:
    el = UIA element to read from.
*/
SafeUIA_GetAutoId(el) {
    if !IsObject(el)
        return ""
    try
        return el.AutomationId
    catch e
        return ""
}
/*
    Read the UIA IsContentElement flag.
    This reports whether the provider considers the element meaningful content
    for content-view traversal, not just structural UI chrome.

    Parameters:
    el           = UIA element to read from.
    default := 0 = fallback value if the property cannot be read.
                   Common values are 0 = False and 1 = True.
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
    Read the UIA IsControlElement flag.
    This reports whether the provider considers the element a real control in
    the control view of the automation tree.

    Parameters:
    el           = UIA element to read from.
    default := 0 = fallback value if the property cannot be read.
                   Common values are 0 = False and 1 = True.
*/
SafeUIA_GetIsControlElement(el, default := 0) {
    if !IsObject(el)
        return default
    try
        return el.CurrentIsControlElement
    catch e
        return default
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
::dunk::
::eloign::
::ensign::
::exiting::
::feign::
::foreign::
::indign::
::ing::
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
::sign::
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
::fuck::
::ether::
::rot::
::SXe::
::IPs::
::VMware::
::VMs::
::ah::
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
::app::
::apps::
::cue::
::jest::
::boil::
::logger::
::activate::
::checkin::
::sine::
::cosine::
::cos::
::rms::
::axis::
::axes::
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

#Hotstring B T C k-1
::vms::VMs
::sxe::SXe
::ips::IPs
::vmware::VMware
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
:?:eses::esses
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
:*:disparat::disparit
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
