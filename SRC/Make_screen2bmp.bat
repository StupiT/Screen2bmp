@\masm32\bin\ml.exe /c /coff /nologo /Cp Screen2bmp.asm
@if errorlevel 1 goto ERR

@\masm32\bin\link.exe /VERSION:0.1 /nologo /SUBSYSTEM:WINDOWS /OPT:NOWIN98 /LIBPATH:o:\masm32\lib Screen2bmp.obj kernel32.lib user32.lib gdi32.lib shell32.lib
@if errorlevel 1 goto ERR
@del Screen2bmp.obj
@goto END
:ERR
@pause
:END