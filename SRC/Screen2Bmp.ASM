;	Screen2bmp 0.1 [20.07.06 - 27.02.07]
; Сохранение изображения с экрана в файл BMP (только в 24-битном цвете).
; Существующий файл не перезаписывается (если не задать).

; Командная строка:
; =файл.bmp	- "мгновенный" захват экрана в файл.
; ==файл.bmp	- захват экрана по нажатию клавиши CTRL,
;	если же она не будет нажата более 2 минут, то выход из программы.

; Сделано и проверено в WinXP.
; Ассемблер: MASM32. Редактор: Блокнот. Шрифт: Lucida Console,10
;___________________________________________________________________________
.386P
.MODEL FLAT,STDCALL

;Клавиша начала захвата экрана (если будет команда "==").
C_SCREEN_CAP_KEY equ	11h ;VK_CONTROL

;Открытие картинки в программе по умолчанию (ShellExecute), если она будет успешно записана в файл.
C_OPEN_BMP equ	1

;Режим копирования бит. 0CC0020h - SRCCOPY. +40000000h - захват прозрачных окон в Win2000/XP.
C_BIT_MODE equ	[0CC0020h+40000000h]

;Количество мсек до окончания ожидания нажатия клавиши.
C_WAIT_MSEC equ		2*60*1000

;Число мсек "сна" между проверками нажатия клавиши. Влияет и на уменьшение времени ожидания (заданного выше).
C_SLEEP_MSEC equ	10

;Выбор пары функций работы с экраном: GetDC + ReleaseDC или CreateDC + DeleteDC.
;	C_USE_GETDC equ		1

;Как создавать файл: 1 - без перезаписи (CREATE_NEW), 2 - перезапись (CREATE_ALWAYS).
C_CREATE_FILE equ	1

;Уменьшение размера программы. Не будет описания программы и "обработки" ошибок.
;	C_MIN_PROG_SIZE equ	1


IFDEF C_OPEN_BMP
	EXTERN	ShellExecuteA@24:NEAR
ENDIF

IFDEF C_USE_GETDC
	EXTERN	GetDC@4:NEAR,ReleaseDC@8:NEAR
ELSE
	EXTERN	CreateDCA@16:NEAR
ENDIF

IFNDEF C_MIN_PROG_SIZE
	EXTERN	GetLastError@0:NEAR,MessageBoxA@16:NEAR
ENDIF

EXTERN	BitBlt@36:NEAR,\
	CloseHandle@4:NEAR,\
	CreateCompatibleDC@4:NEAR,\
	CreateCompatibleBitmap@12:NEAR,\
	CreateFileA@28:NEAR,\
	DeleteDC@4:NEAR,\
	DeleteObject@4:NEAR,\
	ExitProcess@4:NEAR,\
	GetAsyncKeyState@4:NEAR,\
	GetCommandLineA@0:NEAR,\
	GetDeviceCaps@8:NEAR,\
	GetDIBits@28:NEAR,\
	GetFileAttributesA@4:NEAR,\
	GlobalAlloc@8:NEAR,\
	GlobalFree@4:NEAR,\
	SelectObject@8:NEAR,\
	Sleep@4:NEAR,\
	WriteFile@20:NEAR



.DATA?
	WAIT_FLAG       	DD ?				; Флаг ожидания CTRL, если будет ключ "==".
	HDC_SCREEN		DD ?				; Дескриптор контекста экрана
	HDC_COMP		DD ?				;  и совместимых с ним устройства и
	HBMP			DD ?				;  картыбит. Можно хранить их в регистрах, но для упрощения кода ставим сюда.
	BMPSIZE			DD ?				; Размер картыбит.
	SCREENW			DD ?				; Ширина
	SCREENH			DD ?				;  и высота экрана на момент захвата.
	EXIT_CODE		DD ?				; Код выхода из программы. Любой или код последней ошибки.

C_BUF_LEN equ	512 ; кратно 8
	S_FILENAME		DQ C_BUF_LEN/8 DUP(?)		; 512 байт под копию имени файла из командной строки.

.CODE
;--------> Ставим данные в начало секции кода (в них не будет записи, только чтение) -------->
IFNDEF C_MIN_PROG_SIZE
;____________________________
	S_PROG_NAME		DB 'Save Screen to BMP file 0.1 [ProgWin 27.02.07]',0

	S_HELP			DB 'Сохранение изображения с экрана в файл BMP.',13,10
				DB '    Командная строка:',13,10
				DB 'exe =имя_файла.bmp',13,10
				DB 'exe ==имя_файла.bmp  - захват по нажатию CTRL, или выход через 2 минуты.',13,10
				DB 13,10
				DB 'Save picture from screen to BMP file.',13,10
				DB '    Command line:',13,10
				DB 'exe =file_name.bmp',13,10
				DB 'exe ==file_name.bmp  - capture by CTRL key, or exit after 2 minutes.',13,10
				DB 0

ENDIF ;______________________

IFNDEF C_USE_GETDC ; Не требуется для GetDC.
	S_DISPLAY		DB 'DISPLAY',0
ENDIF

;-----------------------------------------------------------------------------------------<
_GO:
	MOV [WAIT_FLAG],0

;Получаем командную строку.
	CALL GetCommandLineA@0
;	TEST EAX,EAX
;	JE _ER_EXIT

;Ищем ключ "=" или "=="
_FIND_EQUAL_CMD:
	MOV DX,[EAX]						; Берем 2 символа из строки.
	TEST DL,DL						; Проверка на 0 - конец строки.
	JE _BadCommandLine ;_EXIT
	TEST DH,DH						; Предотвращаем редкую вероятность выхода за конец памяти доступной для чтения.
	JE _BadCommandLine ;_EXIT
	INC EAX							; На следующий символ строки.
	CMP DL,'='						; Если не ключ, то проверяем очередной символ.
	JNE _FIND_EQUAL_CMD

	CMP DH,DL ;'='						; Вот почему ключ "==" - сразу можно его "поймать".
	JNE @F
	INC EAX							; Пропуск второго "=".
	INC [WAIT_FLAG]						; Установка флага ожидания нажатия клавиши.
@@:

;Копирование имени файла в буфер и пропуск всех двойных кавычек.
	MOV EBX,C_BUF_LEN					; EBX = длина буфера в символах, включая 0.
	LEA EDX,S_FILENAME					; EDX = адрес буфера.
_CopyFileName_SkipAllDoubleQuotes:
	MOV CL,[EAX]
	MOV [EDX],CL
	TEST CL,CL
	JE @F
	DEC EBX							; Проверка длины буфера.
	JE _FileNameTooLong ;_EXIT
	INC EAX
	CMP CL,'"'
	JE _CopyFileName_SkipAllDoubleQuotes
	INC EDX
	JMP _CopyFileName_SkipAllDoubleQuotes
@@:

;Получение дескриптора для работы с экраном.
	XOR EAX,EAX

IFDEF C_USE_GETDC
	PUSH EAX
	CALL GetDC@4

ELSE	; not C_USE_GETDC
	PUSH EAX
	PUSH EAX
	PUSH EAX
	PUSH OFFSET S_DISPLAY
	CALL CreateDCA@16
ENDIF

	TEST EAX,EAX
	JE _GetDC_err ;_EXIT

	MOV [HDC_SCREEN],EAX

;Если есть флаг, то ждем нажатия CTRL, иначе сразу "хватаем" экран.
	DEC [WAIT_FLAG]
	JNE _START_SCREEN_CAPTURE

	MOV EBX,C_WAIT_MSEC
_WAIT_KEY_LOOP:
	PUSH C_SCREEN_CAP_KEY					; Код клавиши - задан в начале файла.
	CALL GetAsyncKeyState@4					; бит0=1 - была нажата, бит15=1 - сейчас нажата.
	TEST AX,AX
	JNE _START_SCREEN_CAPTURE

;Уменьшаем счетчик времени ожидания и если время вышло, то выходим из программы.
	SUB EBX,C_SLEEP_MSEC
	JBE _TimeoutExit ;_DELETE_DC

	PUSH C_SLEEP_MSEC
	CALL Sleep@4
	JMP _WAIT_KEY_LOOP


_START_SCREEN_CAPTURE:
;Получаем информацию об устройстве - высота экрана в пикселях. Игнорируем 2-й и тд. экраны.
	PUSH 10 ;HORZRES
	PUSH [HDC_SCREEN]
	CALL GetDeviceCaps@8
	TEST EAX,EAX						; Нулевую и отрицательную не принимаем.
	JLE _GetScreenHeight_err ;_DELETE_DC
	MOV [SCREENH],EAX
	MOV EBX,EAX						; EBX = высота экрана.

;Ширина экрана в пикселях.
	PUSH 8
	PUSH [HDC_SCREEN]
	CALL GetDeviceCaps@8
	TEST EAX,EAX
	JLE _GetScreenWidth_err ;_DELETE_DC
	MOV [SCREENW],EAX

;Вычисление размера под картубит в байтах.
	CDQ							; XOR EDX,EDX
	XOR ECX,ECX
	MOV CL,3						; 3 байта на пиксель.
	MUL ECX							; EAX = байт на строку пикселей.
	ADD EAX,ECX						; + 3
	NOT ECX							; ECX = -4
	AND EAX,ECX						; EAX = байт на строку пикселей кратно 4 - строки картыбит "набиваются" до числа байт кратного 4.
	MUL EBX							; EAX = размер картыбит.
	MOV [BMPSIZE],EAX

;Создание устройства совместимого с экраном.
	PUSH [HDC_SCREEN]
	CALL CreateCompatibleDC@4
	TEST EAX,EAX
	JE _CreateCompatibleDC_err ;_DELETE_DC
	MOV [HDC_COMP],EAX

;Создание картыбит совместимой с экраном.
	PUSH EBX ; [SCREENH]
	PUSH [SCREENW]
	PUSH [HDC_SCREEN]
	CALL CreateCompatibleBitmap@12
	TEST EAX,EAX
	JE _CreateCompatibleBitmap_err ;_DELETE_COMPATIBLE_DC
	MOV [HBMP],EAX

;Выбор картыбит в совместимое устройство.
	PUSH EAX
	PUSH [HDC_COMP]
	CALL SelectObject@8					; Вернет дескриптор картыбит бывшей в этом устройстве.
	TEST EAX,EAX
	JE _SelectBitmap_err ;_DELETE_BITMAP

;Помещаем дескриптор бывшей картыбит в стек для выбора обратно.
		PUSH EAX

;Копируем картубит с экрана в нашу картубит в совместимом устройстве.
	PUSH C_BIT_MODE
	PUSH 0							; y
	PUSH 0							; x
	PUSH [HDC_SCREEN]					; hDC откуда
	PUSH [SCREENH]
	PUSH [SCREENW]
	PUSH 0							; y
	PUSH 0							; x
	PUSH [HDC_COMP]						; hDC куда
	CALL BitBlt@36
;Если будет ошибка, то вместо картинки с экрана у нас будет набор случайных байт. Игнорируем эту ошибку.

;Выбор прежней картыбит обратно в устройство.
		PUSH [HDC_COMP]
		CALL SelectObject@8
	TEST EAX,EAX						; в EAX должно быть число = [HBMP]
	JE _SelectBitmap_err ;_DELETE_BITMAP

;Выделяем память под картубит и ее заголовок.
	MOV EAX,[BMPSIZE]
	LEA ESI,[EAX+54]					; ESI = размер картыбит + заголовок файла = размер файла.

	LEA ECX,[ESI+2]						; +2 байта для выравнивания адреса под картубит, см. ниже.
	PUSH ECX
	PUSH 0
	CALL GlobalAlloc@8
	TEST EAX,EAX
	JE _GlobalAlloc_err ;_DELETE_BITMAP

;Адрес под получение бит должен быть кратен 8, иначе GetDIBits выделит память
;и получит картубит в нее, а потом уже скопирует биты в нашу память (так в WinXP).
;Поэтому начинаем составление заголовка файла не с начала памяти, а с +2,
;чтобы заголовок кончался на кратном 8 адресе (+56). Сразу после заголовка будут биты картыбит.
	ADD EAX,2

	MOV WORD PTR[EAX],'MB'					; Первые 2 байта файла = 'BM'
	MOV [EAX+2],ESI						; +2 = размер файла
	XOR ECX,ECX
	AND [EAX+6],ECX						; +6 = резерв
	MOV [EAX+30],ECX					; +30 = сжатие
	MOV [EAX+38],ECX					; +38 = разрешение устройства в пикселях на метр по горизонтали
	MOV [EAX+42],ECX					; +42 = пикс/метр по вертикали
	MOV [EAX+46],ECX					; +46 = число используемых цветов, не требуется для 24-битного цвета
	MOV [EAX+50],ECX					; +50 = число важных цветов, не требуется для 24-битного цвета
	MOV CL,54
	MOV [EAX+10],ECX					; +10 = смещение до картыбит от начала файла = размер заголовка.
	MOV CL,40
	MOV [EAX+14],ECX					; +14 = начало структуры BITMAPINFOHEADER = ее размер.
	PUSH [SCREENW]
	POP DWORD PTR[EAX+18]					; +18 = ширина картыбит
	MOV EDX,[SCREENH]
	MOV [EAX+22],EDX					; +22 = высота картыбит
	MOV DWORD PTR[EAX+26],180001h				; +26 = по 2 байта: число полей и бит на пиксель (1 и 24)
	PUSH [BMPSIZE]
	POP DWORD PTR[EAX+34]					; +34 = размер картыбит в байтах

	MOV ESI,EAX						; ESI = начало заголовка файла в памяти (+2 от начала).

;Получение байт из нашей картыбит - копия экрана (если не было ошибки в BitBlt).
	PUSH 0							; 7. 0 = DIB_RGB_COLORS
		LEA EAX,[ESI+14]
	PUSH EAX						; 6. Желаемый формат (составлен в памяти, см. выше).
		ADD EAX,ECX ;LEA EAX,[ESI+54]			; (ECX = 40)
	PUSH EAX						; 5. Буфер для бит
	PUSH EDX ;[SCREENH]					; 4. Число строк из картыбит
	PUSH 0							; 3. Номер первой строки
	PUSH [HBMP]						; 2. Картабит. Не должна быть выбрана в устройство
	PUSH [HDC_COMP]						; 1. Устройство
	CALL GetDIBits@28    					; Вернет число строк помещенных в буфер
;Ошибки игнорируем. Возможно не поддерживается 24-битный, запрошенный нами формат цвета.
;При ошибке будет случайный набор байт (чаще всего одни нули - черная картинка).

;Создаем файл для записи в него картыбит.
	XOR EBX,EBX						; EBX = 0
	PUSH EBX						; 7. Дескриптор файла для копирования его расширенных атрибутов. в Win95 будет ошибка, если тут не 0.
	PUSH EBX						; 6. Флаги и атрибуты
	PUSH C_CREATE_FILE					; 5. Как создавать
	PUSH EBX ; SECURITY					; 4. Безопасность - права доступа
	PUSH 1 ; FILE_SHARE_READ				; 3. Общий доступ (другие смогут лишь читать)
	PUSH 40000000h ; GENERIC_WRITE				; 2. Доступ
	PUSH OFFSET S_FILENAME					; 1. Имя
	CALL CreateFileA@28					; -1 - ошибка
	INC EAX
	JE _CreateFile_err ;_GLOBAL_FREE
	DEC EAX

;Записываем картубит в файл.
	PUSH EBX ;0						; 5. Адрес структуры OVERLAPPED.
		MOV EBX,EAX					; EBX = hFile.
	PUSH OFFSET WAIT_FLAG					; 4. Адрес для получения числа записанных байт. (Адрес уже ненужного флага.)
	PUSH [ESI+2]						; 3. Число байт для записи = размер файла из его заголовка в памяти.
	PUSH ESI						; 2. Адрес буфера для записи из него.
	PUSH EAX						; 1. Дескриптор файла.
	CALL WriteFile@20					; 0 - ошибка.

;Закрываем файл.
	PUSH EBX
IFNDEF C_MIN_PROG_SIZE
		MOV EBX,EAX					; EBX = Результат записи.
	CALL CloseHandle@4
	TEST EBX,EBX
	JE _WriteFile_err
ELSE
	CALL CloseHandle@4
ENDIF

;Картабит успешно записана в файл. Ура!? (Радоваться рано - могли быть ошибки получения бит!)


IFDEF C_OPEN_BMP
;Открытие картинки в программе по умолчанию.
	XOR EAX,EAX
	PUSH 1 ;SW_SHOWNORMAL					; 6. Тип показа окна запускаемой программы.
	PUSH EAX ;0						; 5. Адрес имени папки.
	PUSH EAX ;0						; 4. Адрес командной строки или 0, если не исполняемый файл.
	PUSH OFFSET S_FILENAME					; 3. Адрес имени файла.
	PUSH EAX ;0						; 2. Команда: "open"=0, "print", "explore".
	PUSH EAX ;0						; 1. Дескриптор окна.
	CALL ShellExecuteA@24					; дескриптор или разные коды ошибок.
ENDIF


;________________ Всем спасибо, все свободны ________________
;Освобождаем память.
_GLOBAL_FREE:
IFDEF C_MIN_PROG_SIZE
_CreateFile_err:
ENDIF
	SUB ESI,2
	PUSH ESI
	CALL GlobalFree@4

;Удаляем картубит.
_DELETE_BITMAP:
IFDEF C_MIN_PROG_SIZE
_SelectBitmap_err:
_GlobalAlloc_err:
ENDIF
	PUSH [HBMP]
	CALL DeleteObject@4

;Удаляем совместимое с экраном устройство.
_DELETE_COMPATIBLE_DC:
IFDEF C_MIN_PROG_SIZE
_CreateCompatibleBitmap_err:
ENDIF
	PUSH [HDC_COMP]
	CALL DeleteDC@4

;Удаляем или освобождаем дескриптор экрана.
_DELETE_DC:
IFDEF C_MIN_PROG_SIZE
_TimeoutExit:
_GetScreenHeight_err:
_GetScreenWidth_err:
_CreateCompatibleDC_err:
ENDIF
	PUSH [HDC_SCREEN]
IFDEF C_USE_GETDC
	PUSH 0
	CALL ReleaseDC@8
ELSE
	CALL DeleteDC@4
ENDIF


IFNDEF C_MIN_PROG_SIZE
	MOV EAX,[EXIT_CODE]
ELSE
_GetDC_err:
_BadCommandLine:	; Код выхода (EAX) может оказаться любым -
_FileNameTooLong:	; - "жертва" минимальности программы.
ENDIF

_EXIT:
	PUSH EAX
	CALL ExitProcess@4



IFNDEF C_MIN_PROG_SIZE
;____________________________> Всего этого не будет при задании C_MIN_PROG_SIZE - минимальный размер программы.

_BadCommandLine:
;Командная строка не содержит правильных ключей. Показ краткого описания программы.
	PUSH 40000h ;MB_TOPMOST
	PUSH OFFSET S_PROG_NAME
	PUSH OFFSET S_HELP
	PUSH 0
	CALL MessageBoxA@16
	XOR EAX,EAX
	JMP _EXIT

_FileNameTooLong:
;Имя файла не уместилось в буфер.
	MOV [EXIT_CODE],-1
	JMP _EXIT

_GetDC_err:
;Ошибка получения дескриптора экрана.
	CALL GetLastError@0
	JMP _EXIT

_GetScreenHeight_err:
_GetScreenWidth_err:
;Ошибка получения высоты или ширины экрана.
	CALL GetLastError@0
	MOV [EXIT_CODE],EAX
	JMP _DELETE_DC

_TimeoutExit:
;Вышло время ожидания.
	MOV [EXIT_CODE],-1
	JMP _DELETE_DC

_CreateCompatibleDC_err:
;Ошибка получения дескриптора устройства совместимого с экраном.
	CALL GetLastError@0
	MOV [EXIT_CODE],EAX
	JMP _DELETE_DC

_CreateCompatibleBitmap_err:
;Ошибка создания картыбит совместимой с экраном.
	CALL GetLastError@0
	MOV [EXIT_CODE],EAX
	JMP _DELETE_COMPATIBLE_DC

_SelectBitmap_err:
;Ошибка выбора картыбит в устройство.
	CALL GetLastError@0
	MOV [EXIT_CODE],EAX
	JMP _DELETE_BITMAP

_GlobalAlloc_err:
;Ошибка выделения памяти.
	CALL GetLastError@0
	MOV [EXIT_CODE],EAX
	JMP _DELETE_BITMAP

_CreateFile_err:
;Ошибка создания файла. Неправильное имя в командной строке, нет прав на запись, или файл уже существует.

_WriteFile_err:
;Ошибка записи в файл. Обидно, ведь почти все удалось :(
	CALL GetLastError@0
	MOV [EXIT_CODE],EAX
	JMP _GLOBAL_FREE

ENDIF ;C_MIN_PROG_SIZE
;____________________________<


END _GO