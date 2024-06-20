#NoTrayIcon
#NoEnv
#SingleInstance
#KeyHistory 0

Send, {DOWN}
sleep, 10000
ExitApp
Return

Capslock Up::
Winclose, ahk_class #32768
ExitApp

