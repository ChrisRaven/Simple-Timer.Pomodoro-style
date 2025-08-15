; Simple 25-minute countdown timer in Win32 Assembly using FASM
; - Window size approximately 200x100 client area, always on top
; - Large countdown display
; - START/RESET button
; - Flashes the time text in red when reaches 00:00

format PE GUI 4.0
entry start

include 'INCLUDE\win32a.inc'

; Constants
ID_BUTTON = 1001
ID_STATIC = 1002
ID_TIMER_COUNTDOWN = 1
ID_TIMER_FLASH = 2
TIMER_LENGTH = 1500  ; 25 minutes in seconds

; Data section
section '.data' data readable writeable
  szClass db 'TimerClass',0
  szTitle db 'Timer',0
  szStatic db 'STATIC',0
  szButton db 'BUTTON',0
  szStart db 'START',0
  szReset db 'RESET',0
  szFormat db '%02d:%02d',0
  szFont db 'Arial',0
  szRegError db 'Failed to register class',0
  szCreateError db 'Failed to create window',0

  hinstance dd ?
  hwnd dd ?
  hstatic dd ?
  hbutton dd ?
  hfont dd ?

  time_left dd TIMER_LENGTH
  is_running db 0
  is_initial_state db 1  ; 1 if button says "START" (initial or reset state), 0 if "RESET"
  flash_count db 0
  flash_on db 0

  buffer rb 10

  wcex WNDCLASSEX
  msg MSG
  rect RECT

; Code section
section '.code' code readable executable

start:
  invoke GetModuleHandle, 0
  mov [hinstance], eax

  mov [wcex.cbSize], sizeof.WNDCLASSEX
  mov [wcex.style], CS_HREDRAW + CS_VREDRAW
  mov [wcex.lpfnWndProc], WndProc
  mov [wcex.cbClsExtra], 0
  mov [wcex.cbWndExtra], 0
  mov [wcex.hInstance], eax
  invoke LoadIcon, 0, IDI_APPLICATION
  mov [wcex.hIcon], eax
  mov [wcex.hIconSm], eax
  invoke LoadCursor, 0, IDC_ARROW
  mov [wcex.hCursor], eax
  mov [wcex.hbrBackground], COLOR_WINDOW + 1
  mov [wcex.lpszMenuName], 0
  mov [wcex.lpszClassName], szClass

  invoke RegisterClassEx, wcex
  test eax, eax
  jz reg_error

  ; Adjust window size for exact client area 200x100
  mov [rect.left], 0
  mov [rect.top], 0
  mov [rect.right], 200
  mov [rect.bottom], 100
  invoke AdjustWindowRect, rect, WS_CAPTION + WS_SYSMENU, 0

  mov eax, [rect.right]
  sub eax, [rect.left]
  mov ebx, [rect.bottom]
  sub ebx, [rect.top]

  invoke CreateWindowEx, WS_EX_TOPMOST, szClass, szTitle, WS_VISIBLE + WS_CAPTION + WS_SYSMENU, \
                         CW_USEDEFAULT, CW_USEDEFAULT, eax, ebx, 0, 0, [hinstance], 0
  test eax, eax
  jz cr_error
  mov [hwnd], eax

msg_loop:
  invoke GetMessage, msg, 0, 0, 0
  cmp eax, 1
  jb exit_loop
  jne msg_loop
  invoke TranslateMessage, msg
  invoke DispatchMessage, msg
  jmp msg_loop

reg_error:
  invoke MessageBox, 0, szRegError, szTitle, MB_ICONERROR + MB_OK
  jmp exit_loop

cr_error:
  invoke MessageBox, 0, szCreateError, szTitle, MB_ICONERROR + MB_OK

exit_loop:
  invoke ExitProcess, [msg.wParam]

proc WndProc hwnd:DWORD, wmsg:DWORD, wparam:DWORD, lparam:DWORD
  cmp [wmsg], WM_CREATE
  je .wmcreate
  cmp [wmsg], WM_DESTROY
  je .wmdestroy
  cmp [wmsg], WM_COMMAND
  je .wmcommand
  cmp [wmsg], WM_TIMER
  je .wmtimer
  cmp [wmsg], WM_CTLCOLORSTATIC
  je .wmctlcolorstatic

  invoke DefWindowProc, [hwnd], [wmsg], [wparam], [lparam]
  jmp .done

.wmcreate:
  ; Create large font
  invoke CreateFont, 48, 0, 0, 0, FW_BOLD, 0, 0, 0, ANSI_CHARSET, OUT_DEFAULT_PRECIS, \
                     CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH, szFont
  mov [hfont], eax

  ; Create static control for time display
  invoke CreateWindowEx, 0, szStatic, 0, WS_CHILD + WS_VISIBLE + SS_CENTER, \
                         0, 0, 200, 60, [hwnd], ID_STATIC, [hinstance], 0
  mov [hstatic], eax
  invoke SendMessage, [hstatic], WM_SETFONT, [hfont], 1

  ; Create button
  invoke CreateWindowEx, 0, szButton, szStart, WS_CHILD + WS_VISIBLE + BS_PUSHBUTTON, \
                         50, 60, 100, 30, [hwnd], ID_BUTTON, [hinstance], 0
  mov [hbutton], eax

  ; Initial update
  stdcall UpdateTime
  xor eax, eax
  jmp .done

.wmdestroy:
  invoke PostQuitMessage, 0
  xor eax, eax
  jmp .done

.wmcommand:
  mov eax, [wparam]
  and eax, 0FFFFh
  cmp eax, ID_BUTTON
  jne .done_command

  cmp [is_initial_state], 1
  je .start_timer

  ; Reset (during countdown, flashing, or at 00:00)
  mov [time_left], TIMER_LENGTH
  stdcall UpdateTime
  invoke SetWindowText, [hbutton], szStart
  mov [is_running], 0
  mov [is_initial_state], 1
  invoke KillTimer, [hwnd], ID_TIMER_COUNTDOWN
  invoke KillTimer, [hwnd], ID_TIMER_FLASH
  mov [flash_count], 0
  mov [flash_on], 0
  invoke InvalidateRect, [hwnd], 0, 1
  jmp .done_command

.start_timer:
  ; Start countdown from initial or reset state
  mov [time_left], TIMER_LENGTH
  stdcall UpdateTime
  invoke SetWindowText, [hbutton], szReset
  mov [is_running], 1
  mov [is_initial_state], 0
  invoke KillTimer, [hwnd], ID_TIMER_FLASH
  mov [flash_count], 0
  mov [flash_on], 0
  invoke InvalidateRect, [hwnd], 0, 1
  invoke SetTimer, [hwnd], ID_TIMER_COUNTDOWN, 1000, 0

.done_command:
  xor eax, eax
  jmp .done

.wmtimer:
  mov eax, [wparam]
  cmp eax, ID_TIMER_COUNTDOWN
  je .countdown
  cmp eax, ID_TIMER_FLASH
  je .flash
  jmp .done_timer

.countdown:
  cmp [time_left], 0
  jle .stop_countdown
  dec [time_left]
  stdcall UpdateTime
  jmp .done_timer

.stop_countdown:
  invoke KillTimer, [hwnd], ID_TIMER_COUNTDOWN
  mov [is_running], 0
  invoke SetWindowText, [hbutton], szReset
  mov [is_initial_state], 0
  mov [flash_count], 10  ; Flash 5 times (on/off)
  mov [flash_on], 1
  invoke SetTimer, [hwnd], ID_TIMER_FLASH, 200, 0
  stdcall UpdateTime
  jmp .done_timer

.flash:
  dec [flash_count]
  cmp [flash_count], 0
  jle .stop_flash
  xor [flash_on], 1
  invoke InvalidateRect, [hwnd], 0, 1
  jmp .done_timer

.stop_flash:
  invoke KillTimer, [hwnd], ID_TIMER_FLASH
  mov [flash_on], 0
  invoke InvalidateRect, [hwnd], 0, 1

.done_timer:
  xor eax, eax
  jmp .done

.wmctlcolorstatic:
  cmp [flash_count], 0
  jle .normal_color
  cmp [flash_on], 0
  je .normal_color
  invoke SetTextColor, [wparam], 0x0000FF  ; Red text
  jmp .set_bg

.normal_color:
  invoke SetTextColor, [wparam], 0x000000  ; Black text

.set_bg:
  invoke SetBkColor, [wparam], 0xFFFFFF  ; White background
  invoke GetStockObject, WHITE_BRUSH
  jmp .done

.done:
  ret
endp

proc UpdateTime
  local min:DWORD, sec:DWORD

  mov eax, [time_left]
  mov ebx, 60
  xor edx, edx
  div ebx
  mov [min], eax
  mov [sec], edx

  invoke wsprintf, buffer, szFormat, [min], [sec]
  invoke SetWindowText, [hstatic], buffer
  ret
endp

; Import section
section '.idata' import data readable writeable
  library kernel32, 'KERNEL32.DLL', \
          user32, 'USER32.DLL', \
          gdi32, 'GDI32.DLL'

  import kernel32, \
         GetModuleHandle, 'GetModuleHandleA', \
         ExitProcess, 'ExitProcess'

  import user32, \
         RegisterClassEx, 'RegisterClassExA', \
         CreateWindowEx, 'CreateWindowExA', \
         ShowWindow, 'ShowWindow', \
         UpdateWindow, 'UpdateWindow', \
         GetMessage, 'GetMessageA', \
         TranslateMessage, 'TranslateMessage', \
         DispatchMessage, 'DispatchMessageA', \
         DefWindowProc, 'DefWindowProcA', \
         LoadIcon, 'LoadIconA', \
         LoadCursor, 'LoadCursorA', \
         MessageBox, 'MessageBoxA', \
         PostQuitMessage, 'PostQuitMessage', \
         SetTimer, 'SetTimer', \
         KillTimer, 'KillTimer', \
         wsprintf, 'wsprintfA', \
         SetWindowText, 'SetWindowTextA', \
         SendMessage, 'SendMessageA', \
         InvalidateRect, 'InvalidateRect', \
         AdjustWindowRect, 'AdjustWindowRect'

  import gdi32, \
         CreateFont, 'CreateFontA', \
         SetTextColor, 'SetTextColor', \
         SetBkColor, 'SetBkColor', \
         GetStockObject, 'GetStockObject'
