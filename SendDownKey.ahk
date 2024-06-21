#NoTrayIcon
#NoEnv
#SingleInstance
#KeyHistory 0

Send, {DOWN}
sleep, 10000
ExitApp
Return

~Alt Up::
Winclose, ahk_class #32768
ExitApp

