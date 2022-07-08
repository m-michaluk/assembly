;Monika Michaluk, mm395135
extern debug
global notec

; Indeksy poszczególnych instrukcji w tablicy lookup_table:
AND_ equ 0
ASTERISK equ 1
PLUS equ 2
MINUS equ 3
DIGIT equ 4
EQUAL equ 5
N_ equ 6
W equ 7
X equ 8
Y equ 9
Z equ 10
XOR_ equ 11
G equ 12
n_ID equ 13
OR_ equ 14
NOT_ equ 15
MIN_REPRESENTED_VALUE equ '&'
;Stałe, które należy odjąć od wartości ASCII znaku, aby uzyskać jego wartość liczbową,
;jeśli interpretujemy dany znak jako cyfrę w zapisue szesnastkowym
TO_HEX_DIGIT equ '0'
TO_HEX_BIG_LETTER equ 'A'-10
TO_HEX_SMALL_LETTER equ 'a'-10


section .rodata
lookup_table:
    align 8
    dq _and, _asterisk, _plus, _minus, _number, _equal, _N, _W, _X, _Y, _Z,
    dq _xor, _g, _n, _or, _not 


; Pod indeksem x w tej tablicy, znajduje się indeks w tablicy lookup_table, pod którym jest
; adres funkcji, do której należy wykonać jmp, aby obsłużyć znak o wartości ASCII x + 38
; (numeruję od 38, aby zaoszczedzić miejsce - pierwsze 38 nie są poprawnymi znakami
; w obliczeniu)
mapped_ASCII:
       ;  38, 39
    db   AND_,  0,

       ;40, 41,       42,   43, 44,    45, 46, 47,    48,    49
    db   0,  0, ASTERISK, PLUS,  0, MINUS,  0,  0, DIGIT, DIGIT,  

       ;   50,    51,    52,    53,    54,    55,    56,    57, 58, 59,
    db  DIGIT, DIGIT, DIGIT, DIGIT, DIGIT, DIGIT, DIGIT, DIGIT,  0,  0,

       ;60,   61,  62, 63, 64,    65,    66,    67,    68,    69,
    db   0, EQUAL,  0,  0,  0, DIGIT, DIGIT, DIGIT, DIGIT, DIGIT,

       ;  70, 71, 72, 73, 74, 75, 76, 77,  78, 79
    db DIGIT,  0,  0,  0,  0,  0,  0,  0,  N_,  0,

       ;80, 81, 82, 83, 84, 85, 86, 87, 88, 89
    db   0,  0,  0,  0,  0,  0,  0,  W,  X,  Y,

       ;90, 91, 92, 93,    94, 95, 96,    97,    98,    99
    db   Z,  0,  0,  0,  XOR_,  0,  0, DIGIT, DIGIT, DIGIT,

       ; 100,   101,   102, 103, 104, 105, 106, 107, 108, 109
    db DIGIT, DIGIT, DIGIT,   G,   0,   0,   0,   0,   0,   0,

       ; 110, 111, 112, 113, 114, 115, 116, 117, 118, 119
    db  n_ID,   0,   0,   0,   0,   0,   0,   0,   0,   0,

       ;120, 121, 122, 123,  124, 125,  126
    db    0,   0,   0,   0,  OR_,   0, NOT_


section .bss
    alignb 8
    exchange_values resq N+1 ;numeruję notecie zamiast od 0..N-1 , to od 1 do N
    alignb 4
    exchange_id resd N+1 ;(wystarczą 4 bajty bo numery noteci są z  0.. 2^32-1)
section .text

; Argumenty:
; rdi - numer instancji Notecia 0 .. N
; rsi - wskaźnik na napis ASCIIZ opisujący obliczenie jakie
;       ma wykonać Noteć
; w rax zwraca wynik funkcji czyli wartość wierzchołka stosu
; po wykonaniu obliczeń
;
; Wykorzystywane rejestry:
; - r11 = 1, jeśli noteć jest aktualnie w trybie wczytywania liczby, 0 wpp
; - r12 - wskazuje na znak obliczenia do przetworzenia
; - r13 - identyfikator Notecia
; - rbp - wartość rejestru rsp na początku funkcji
; Pomocnicze:
; - dl - wartość ASCII aktualnego znaku
; - rdx - indeks w tablicy lookup_table, w której znajduje się adres funkcji którą trzeba
;         wykonać dla danego znaku
; - rsi, r10 - adresy tablic mapped_ASCII i lookup_table
; - rax - adres funkcji, którą należy wykonać dla danego znaku
align 8
notec:
    push r12
    push r13
    push rbp
    mov rbp, rsp
    mov r12, rsi
    mov r13, rdi
loop_start: ; przygotowuje wartości rejestrów edi, edx, r10, rsi
    mov edi, 0    
    mov edx, 0
    lea r10, [rel mapped_ASCII]
    lea rsi, [rel lookup_table]
quit_number_mode:
    mov r11d, 0
notec_loop:
    mov dl, byte [r12]
    test dl, dl
    jz notec_end
    mov dil, byte [r10 + rdx - MIN_REPRESENTED_VALUE]  ; w rdx jest indeks do tablicy lookuptable
    mov rax, [rsi + 8*rdi] ; adres do ktorego trzeba skoczyc

    add r12, 1
    jmp rax
notec_end:
    pop rax ; na wierzchu stosu jest wynik funkcji
    leave ; mov rsp, rbp / pop rbp
    pop r13
    pop r12 
    ret


; Przetwarza znak napisu, interpretując go jako cyfrę w zapisie przy podstawie 16.
; Jeśli Noteć jest w trybie wczytywania liczby (r11b = 1), to mnoży wartość na wierzchu stosu
; przez 16 i dodaje wartość liczbową danego znaku. Wpp. na stos wrzucane jest najpierw 0.
; Argumenty:
; - dl - wartość ASCII znaku; jest to poprawna wartość, tzn. dl jest z zakresu ['0','9'] lub
;      ['A', 'F'] lub ['a', 'f']
; - r11b - równa 1, jeśli Noteć jest w trybie wczytywania liczby, 0 wpp.
; Zmienia wartość w rejestrach:
; - rax - zmienna przechowująca stałą, którą należy odjąć od wartości znaku ASCII, aby
;         uzyskać wartość liczbową tego znaku interpretując go jako liczbę w systemie 
;         szesnastkowym
_number:
    test r11d, r11d
    jnz .convert_digit
    mov r11d, 1
    push 0
.convert_digit:
    ; w zależności od tego, czy znak jest cyfrą, dużą literą czy małą literą, należy odjąć
    ; od dl inną stałą - ustawiam odpowiednią wartość al
    mov eax, 0
    mov al, TO_HEX_DIGIT
    cmp dl, '9'
    jbe .add_number
    mov al, TO_HEX_BIG_LETTER
    cmp dl, 'F'
    jbe .add_number
    mov al, TO_HEX_SMALL_LETTER
.add_number:
    sub dl, al
    shl qword [rsp], 4
    add qword [rsp], rdx
    jmp notec_loop

_equal:
    xor r11d, r11d
    jmp quit_number_mode

_plus:
    pop rax
    add [rsp], rax;
    jmp quit_number_mode

_asterisk:
    pop rax
    mul qword [rsp] ; rdx:rax <- rax * [rsp]
    mov [rsp], rax
    mov edx, 0 ; mul zmieniło wartość rdx, które jest wykorzystywane w głównej pętli notecia
    jmp quit_number_mode

_minus:
    neg qword [rsp]
    jmp quit_number_mode

_and:
    pop rax
    and [rsp], rax;
    jmp quit_number_mode

_or:
    pop rax
    or [rsp], rax;
    jmp quit_number_mode

_xor:
    pop rax
    xor [rsp], rax;
    jmp quit_number_mode

_not:
    not qword [rsp]
    jmp quit_number_mode


_Z:
    add rsp, 8
    jmp quit_number_mode


_Y:
    push qword [rsp]
    jmp quit_number_mode


_X:
    pop rax ; zdejmuję pierwszy element z wierzchu stosu
    push qword [rsp] ; podwajam drugi element
    mov [rsp + 8], rax ; jako drugą wartość ustawiam poprzednio pierwszą
    jmp quit_number_mode


_N:
    push N
    jmp quit_number_mode


_n:
    push r13
    jmp quit_number_mode


_g:
    ; Przekazuję argumenty do funkcji debug w rejestrach rdi (numer instancji notecia)
    ; i w rsi (wskazuje na wierzchołek stosu Notecia)
    mov rsi, rsp
    mov rdi, r13
    ; rsp + 8 musi być wielokrotnością 16 - sprawdzam, czy rsp jest podzielne przez 16 -
    ; jeśli rsp & 0x10 == 0 to rsp jest podzielne przez 16, wpp. jest podzielne przez 8
    test rsp, 0x10
    jnz .align
    call debug
    jmp .clean_up
.align:
    sub rsp, 8
    call debug
    add rsp, 8
.clean_up:
    lea rsp, [rsp + 8*rax] ; przesuwam wierzchołek obliczenia o wskazaną przez debug wartość
    jmp loop_start


; Jeśli Noteć o numerze n chce zamienić się z Noteciem o numerze m, jeśli n < m, to:
; - Noteć o numerze mniejszym dokonuje wymiany. Czeka aż odczyta informację z tablicy 
;   exchange_id, że Noteć m już na niego czeka. Wtedy pobiera z tablicy exchange_values
;   wartość z wierzchołka stosu Notecia m (zapisuje ją na swoim stosie) i umieszcza w jej
;   miejscu wartość z wierzchołka swojego stosu. Po zakończeniu wymiany, informuje Notecia m
;   o zakończeniu wymiany przez ustawienie w tablicy exchange_id wartości 0 pod indeksem m.
; - Noteć o numerze większym umieszcza w tablicy exchange_values pod indeksem m wartość z
;   wierzchołka swojego stosu oraz w tabicy exchange_id, z kim chce się wymienić.
;   Następnie czeka aż Noteć, z którym chce się wymienić i o numerze mniejszym, dokona wymiany.
;   Wtedy odczytuje wartość z exchange_values pod indeksem m i umieszcza ją na swoim stosie. 
; W funkcji notec, Notecie numerowane są liczbami od 0 do N-1 (N <= 2^32). W instrukcji W,
; przemianowuję identyfikatory Noteci na o 1 większe - aby móc wykorzystać wartość 0 jako 
; "na nikogo nie czeka".
_W:
    lea r8, [rel exchange_id]
    lea r9, [rel exchange_values]
    pop rcx ; identyfikator Notecia z którym dokonam wymiany
    add ecx, 1
    lea r11d, [r13 + 1] ; mój identyfikator
    cmp ecx, r11d
    jl .greater
.smaller_wait:
    cmp dword [r8 + 4*rcx], r11d; sprawdzam czy Noteć m, na którego czekam, czeka na mnie 
    jne .smaller_wait
    mov rax, qword [r9 + 8*rcx] ; zapisuje wartość od Notecia m, z którym się wymieniam
    pop qword [r9 + 8*rcx] ; przekazuje mu wartość ze swojego stosu
    push rax ; wrzuca na swój stos wartość od Notecia m
    mov dword [r8 + 4*rcx], 0 ; informuje Notecia m, że wymiana zakończona
    jmp quit_number_mode
.greater:
    pop qword [r9 + 8*r11] ; zdejmuje wartość ze stosu i umieszcza ją w tablicy wymian
    mov dword [r8 + 4*r11], ecx ; zapisuje w tablicy, na jakiego Notecia czeka 
.greater_wait: ; czeka aż Noteć z pary dokona wymiany wartości
    cmp dword [r8 + 4*r11], 0 ; po dokonaniu wymiany, Noteć z pary wyzeruje to na kogo czekam
    jne .greater_wait
    push qword [r9 + 8*r11] ; umieszczam na swoim stosie wartość od drugiego Notecia
    jmp quit_number_mode