; SO Zadanie 1 Diakrytynizator
; Monika Michaluk
; nr. indeksu 395135
global _start

SYS_WRITE equ 1
SYS_READ equ 0
SYS_EXIT equ 60
STDIN equ 0
STDOUT equ 1
BUF_SIZE equ 2024 ; Rozmiar buforów.
ZERO_IN_UNICODE equ 48 ; Wartość znaku 0 w Unicode.
MOD equ 0x10FF80 ; Wartość wielomianu liczona jest modulo 0x10FF80.

; Wartości z jakiego zakresu mogą być kodowane na dane liczby bajtów.
; Np. wartości z zakresu (0x7FF, 0xFFFF] kodowane są na 3 bajtach.
ONE_BYTE_BOUND equ 0x7F
TWO_BYTE_BOUND equ 0x7FF
THREE_BYTE_BOUND equ 0xFFFF
FOUR_BYTE_BOUND equ 0x10FFFF

; Maski bitowe służące do dekodowania UTF8 -> Unicode i kodowania Unicode -> UTF8
; (Pozycje, na których znajdują się jedynki to pozycje, gdzie powinny znaleźć się bity wartości
; Unicode analizowanego znaku.)
UTF8_2_BYTES_MASK equ 0001111100111111b
UTF8_3_BYTES_MASK equ 000011110011111100111111b
UTF8_4_BYTES_MASK equ 00000111001111110011111100111111b

; Te wartości są wykorzystywane do kodowania Unicode -> UTF8.
; Po umieszczeniu bitów wartości Unicode na odpowiednich miejscach za pomocą maski UTF8_x_BYTES_MASK
; należy dodać te wartości, aby uzyskać poprawne kodowanie.
ENCODE_2_BYTES_MASK equ 1100000010000000b
ENCODE_3_BYTES_MASK equ 111000001000000010000000b 
ENCODE_4_BYTES_MASK equ 11110000100000001000000010000000b

section .bss
    alignb 8
    buffer_in resb BUF_SIZE ; rezerwuje BUF_SIZE *bajtów*
    buffer_out resb BUF_SIZE
section .text

; Rejestry wykorzystywane globalnie:
; - rbp - wskaźnik za ostatnie miejsce z danymi w buffer_in
; - r8b - zmienna równa 1, jeśli standardowe wejście jest puste (sys_read zwróciło 0), równa 0 wpp.
; - r13 - wskaźnik na aktualną pozycję w buffer_in, z której czytamy dane
; - r14 - wskaźnik na pierwsze wolne miejsce do pisania w buffer_out 

; Wykorzystywane rejestry w _start:
; r15 - wskaźnik za ostatni wspołczynnik wielomianu na stosie
; rax - zmienna pomocnicza
; rdi - w tym rejestrze przekazywany jest argument do funkcji value_at i unicode_to_utf8
; r10 - w tym rejestrze przekazywany jest argument do funkcji value_at (adres pierwszego współczynnika
;        wielomianu)
_start:
    ;sprawdzam czy został podany przynajmniej jeden argument
    mov rax, [rsp]
    cmp rax, 2
    jl exit_error
    lea r15, [rsp + 16]
    call process_coefficients
    mov r8b, 0
    mov r14, buffer_out
    mov rbp, buffer_in
    mov r13, buffer_in
loop_start:
    cmp r8b, 1 ; sprawdzam czy są jeszcze dane do wczytania z STDIN
    jne check_buffer_in
    cmp r13, rbp ; jeśli nie, to sprawdzam czy buffer_in został opróżniony
    je exit
    jmp check_buffer_out    
check_buffer_in:
    ; Ponieważ znaki są co najwyżej 4 bajtowe, to w buffer_in muszą być dostępne co najmniej 4 znaki.
    lea rax, [rbp - 4]
    cmp r13, rax
    jb check_buffer_out ; skok jeśli jest wystarczająco dużo znaków w buforze
    call load_buffer
check_buffer_out:
    ; Jeśli nie ma miejsca w buffer_out na potencjalnie 4 bajty, to trzeba go najpierw opróżnić.
    cmp r14, buffer_out + BUF_SIZE - 4
    jb process_data
    call print_buffer
    mov r14, buffer_out
process_data:
    mov al, byte [r13]
    cmp al, ONE_BYTE_BOUND
    ja encode
    mov byte [r14], al
    inc r14
    inc r13
    jmp loop_start
encode:
    call utf8_to_unicode ; w eax jest wartość unicode, r13 jest odpowiednio przesunięty
    sub eax, 0x80
    mov edi, eax
    lea r10, [rsp + 16] ; przekazuję argument do value_at, rsp + 16 to adres pierwszego wsp. wielomianu
    call value_at
    lea rdi, [rax + 0x80]
    call unicode_to_utf8
    jmp loop_start


; Funkcja wypisująca zawartość buffer_out na standardowe wyjście.
; Argumenty:
; - r14 - wskaźnik za ostatnie miejsce z danymi do wypisania
; Zmienia wartości w rejestrach: rax, rdi, rsi, rdx, rcx, r11 (wywołanie funkcji systemowej sys_write)
print_buffer: 
    mov rax, buffer_out
    mov rdx, r14 
    sub rdx, rax ; ile bajtow wypisać = r14 - buffer_out
    mov eax, SYS_WRITE
    mov edi, STDOUT
    mov rsi, buffer_out
    syscall
    ret


; Funkcja zapisująca do buffer_in dane ze standardowego wejścia.
; W razie gdyby ostatni element w buforze był znakiem wielobajtowym i nie został w całości wczytany
; do bufora, przepisuję końcowe bajty na początek bufora i jego resztę wypełniam znakami z STDIN.
; Wykorzystywane rejestry:
; - rdx - ile bajtów zostanie przepisanych z końca na początek bufora
; - rdi - iterator od początku bufora przy przenoszenu tych bajtów
; - rax - zmienna pomocnicza
; Dodatkowo zmienia wartości rax, rdi, rsi, rdx, rcx, r11 (wywołanie funkcji systemowej sys_read)
; Aktualizuje "globalne" wartości rejestrów r13, rbp i r8b
load_buffer:
    cmp r8b, 1
    je check_if_exit
    mov rdi, buffer_in
    lea rdx, [r13 + BUF_SIZE] ; ile przenieść = BUF_SIZE - (rbp - r13)
    sub rdx, rbp
rewrite:
    cmp r13, rbp ; czy doszliśmy do końca bufora
    je get_input
    mov al, byte [r13]
    mov byte [rdi], al
    inc r13
    inc rdi
    jmp rewrite
get_input:
    mov rbp, rdi ; ustawiam rbp na wskaźnik, gdzie skończono przepisywać dane z końca
    mov eax, SYS_READ
    mov rsi, rdi
    mov edi, STDIN
    syscall
    mov r13, buffer_in
    add rbp, rax ; uaktualniam rbp, dodając liczbę wczytanych elementów
    cmp eax, 0
    je check_if_exit
    ret
check_if_exit: ; jeśli standardowe wejście jest puste, sprawdzam czy buffer_in też jest pusty
    mov r8b, 1
    cmp r13, rbp
    je exit
    ret


; Wypisuje pozostałe dane z buffer_out i kończy program z kodem 0.
exit:
    call print_buffer
    mov eax, SYS_EXIT
    xor edi, edi
    syscall


; Wypisuje pozostałe dane z buffer_out i kończy program z kodem 1. (**)
exit_error:
    call print_buffer
    mov eax, SYS_EXIT
    mov edi, 1
    syscall    
; ** Zdecydowałam się oddzielić exit i exit_error, a nie przekazywać jako argument kod błędu ze 
; względu na przejrzystość kodu i optymalizację programu (mniej skoków warunkowych).


; Funkcja obliczająca wartość w punkcie x wielomianu modulo 0x10FF80
; Argumenty:
; - rdi - punkt x w którym liczona jest wartość
; - r10 - adres pierwszego współczynnika wielomianu (a0). a_i jest pod adresem [r10 + 8*a_0]
; - r15 - adres za ostatnim współczynnikiem wielomianu
; Zwraca:
; - rax - wartość wielomianu w punkcie x modulo 0x10FF80
; Zmieniane wartości: rdx, r10, r11:
; - rdx, rsi - zmienna pomocnicza
; - r11 - kolejne potęgi x
; - r10 - adres kolejnych współczynników wielomianu
value_at:
    xor rax, rax ; rax = 0
    mov r11, 1
    mov rbx, MOD
loop:
    ; rax += r11 * a_{r10}
    mov rdx, [r10]
    imul rdx, r11
    add rax, rdx
    call modulo ; rax = rax % MOD
    imul r11, rdi ; aktualizacja potęgi
    mov rsi, rax
    mov rax, r11
    call modulo
    mov r11, rax
    mov rax, rsi
    add r10, 8
    cmp r10, r15
    jne loop
    ret


; Funkcja zamieniająca znak w UTF8 na jego wartość Unicode.
; Jeśli podany znak nie jest zakodowany w UTF8 to kończy program z kodem 1.
; Argumenty:
; - r13 - adres, z którego należy zacząć odczytywanie znaku.
; Zwraca:
; - eax - wartość Unicode znaku podanego jako argument.
; Zmienia wartości:
; - edi - trzymana jest w nim maska bitowa.
; - r13 - aktualizuje globalny wskaźnik zależnie od tego, na ilu bajtach zakodowany jest znak
utf8_to_unicode:
    mov al, byte [r13] ; analizuję pierwszy bajt znak, żeby sprawdzić na ilu bajtach jest zakodowany
four_bytes_decode:
    shr al, 3
    cmp al, 0011110b
    jne three_bytes_decode
    mov eax, 4
    call check_if_correct
    mov eax, dword [r13]
    bswap eax ; bajty zostały załadowane z pamięci w odwrotnej kolejności
    mov edi, UTF8_4_BYTES_MASK
    pext eax, eax, edi
    ;Sprawdzam czy policzona wartość Unicode jest odpowiednia do liczby bajtów, na ilu jest zakodowany.
    cmp eax, THREE_BYTE_BOUND
    jbe exit_error
    cmp eax, FOUR_BYTE_BOUND
    ja exit_error
    add r13, 4
    ret
three_bytes_decode:
    shr al, 1
    cmp al, 0001110b
    jne two_bytes_decode
    mov eax, 3
    call check_if_correct
    mov eax, dword [r13]
    bswap eax
    shr eax, 8
    mov edi, UTF8_3_BYTES_MASK
    pext eax, eax, edi
    cmp eax, TWO_BYTE_BOUND ; powinno być eax > TWO_BYTE_BOUND, jeśli eax <= TWO_BYTE_BOUND to jest źle
    jbe exit_error
    add r13, 3
    ret
two_bytes_decode:
    shr al, 1
    cmp al, 00000110b
    jne exit_error
    mov eax, 2
    call check_if_correct
    movzx eax, word [r13]
    xchg al, ah
    mov edi, UTF8_2_BYTES_MASK
    pext eax, eax, edi
    cmp eax, ONE_BYTE_BOUND
    jbe exit_error    
    add r13, 2
    ret


; Funkcja sprawdzająca, czy znak zapisany w pamięci pod adresem r13 jest zakodowany poprawnie.
; Argumenty:
; - rax - na ilu bajtach zakodowany jest znak
; - r13 - globalny rejestr, adres początku przetwarzanego znaku
; Zmienia wartości:
; - rdi - zmienna pomocnicza do iterowania po kolejnych bajtach znaku
check_if_correct:
    mov rdi, r13
    inc rdi
    dec rax
check_if_correct_loop:
    ; sprawdzam czy dany bajt nie wychodzi poza zakres bufora
    cmp rdi, rbp
    jnb exit_error
    ; Sprawdzam czy bajt pod adresem rdi jest postaci 10xxxxxx
    mov dl, byte [rdi]
    and dl, 11000000b
    cmp dl, 10000000b
    jne exit_error
    inc rdi
    dec al
    jnz check_if_correct_loop    
    ret


; Zapisuje w pamięci pod zadanym adresem znak o danej wartości Unicode zakodowany jako UTF8.
; Jeśli nie da się zakodować jako UTF8 to kończy program z kodem 1.
; Argumenty:
; rdi - Wartość unicode znaku jako liczba ze znakiem, rdi >= 128.
; r14 - Wskaźnik na pierwsze wolne miejsce w buforze do wypisywania.
; Zmienia wartości:
; - eax - zmienna pomocnicza.
; - r14 - globalny rejestr zwiększany w zależności od tego ile bajtów zajmuje zakodowany znak.
unicode_to_utf8:
two_bytes_encode:
    cmp rdi, TWO_BYTE_BOUND
    jg three_bytes_encode
    mov eax, UTF8_2_BYTES_MASK
    pdep eax, edi, eax
    add eax, ENCODE_2_BYTES_MASK
    bswap eax ; bez zamiany bajty zapiszą się w odwrotnej kolejności
    shr eax, 16 ; przesunięcie, aby interesujące nas bajty znalazły się na młodszych 1 i 2 bajcie
    mov word [r14], ax
    add r14, 2
    ret
three_bytes_encode:
    cmp rdi, THREE_BYTE_BOUND
    jg four_bytes_encode
    mov eax, UTF8_3_BYTES_MASK
    pdep eax, edi, eax
    add eax, ENCODE_3_BYTES_MASK
    bswap eax
    mov dword [r14], eax
    shr dword [r14], 8 ; przesunięcie, aby zerowe bajty znalazły się na końcu w pamięci
    add r14, 3
    ret
four_bytes_encode:
    cmp rdi, FOUR_BYTE_BOUND
    jg exit_error
    mov eax, UTF8_4_BYTES_MASK
    pdep eax, edi, eax
    add eax, ENCODE_4_BYTES_MASK
    bswap eax
    mov dword [r14], eax
    add r14, 4
    ret


; Zamienia argumenty programu na wartości liczbowe współczynników wielomianu.
; Argumenty:
;  - r15 - wskaźnik do pierwszego argumentu programu. i-ty argument jest pod adresem [r15 + 8*i]
; Funkcja zamienia wartość wskaźnika do i-tego argumentu na wartość i-tego współczynnika
; wielomianu lub kończy program z kodem 1, jeśli podane argumenty są błędne.
; Zmienia wartości:
; - r15 - po wywołaniu programu r15 wskazuje za ostatni współczynnik wielomianu
; - rsi - jest iteratorem po aktualnym argumencie
; - rax - jest aktualną wartością obliczanego współczynnika
; - r9 - wartość liczbowa aktualnie przetwarzanego znaku
; - rcx (cl) - zmienna pomocnicza
; - ebx - argument do funkcji modulo (dzielnik)
process_coefficients:
    mov rsi, [r15]
    xor rax, rax
    mov r9, 0
    mov ebx, MOD
number_loop:    
    mov r9b, byte [rsi]
    lea r9, [r9 - ZERO_IN_UNICODE]
    cmp r9, 9
    ja exit_error ; wczytano znak który nie jest cyfrą
    lea rax, [rax + rax*4] ; mnożę przez 5
    add rax, rax ; mnożę przez 2
    add rax, r9
    call modulo
    inc rsi ; przechodzę do kolejnego znaku
    mov cl, byte [rsi] ; sprawdzam czy to koniec danego argumentu
    test cl, cl
    jnz number_loop

    mov [r15], rax
    add r15, 8 ; przechodzę do kolejnego argumentu
    xor rax, rax
    mov rsi, [r15] ; aktualizuję rsi i sprawdzam czy ten argument nie jest nullem
    test rsi, rsi
    jnz number_loop
    ret


; Funkcja obliczająca rax % rbx.
; Argumenty:
; rax, rbx
; Wyznaczona reszta z dzielenia zwracana jest w rax.
modulo:
    cmp rax, rbx
    jb modulo_end
    mov rdx, 0
    div rbx   
    mov rax, rdx  
modulo_end:    
    ret
