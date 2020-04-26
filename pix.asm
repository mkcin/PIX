%define ppi_ptr r13
%define pidx_ptr r14
%define max r15
%define n rbx
%define result rcx
%define result_32 ecx

SECTION .data

SECTION .TEXT
	GLOBAL pix
        extern pixtime

pix:
        push    ppi_ptr         ; Przed podaniem czasu procesora wykonuję 
        push    pidx_ptr        ; niezbędne przepisania argumentów na rejestry
        push    max
        mov     ppi_ptr, rdi
        mov     pidx_ptr, rsi
        mov     max, rdx

        rdtsc                   ; Zapisuję liczbę ticków procesora
        mov     rdi, rdx        ; i przekazuję ją jako argument do funkcji pixtime
        shl     rdi, 32         ; rdtsc zapisuje ticki na 2 rejestrach 32 bitowych, więc przepisuję 
        add     rdi, rax        ; je na 1 rejestr - rdi
        call    pixtime 

        push    rbp             ; Wrzucam na stos rejestry, których wartość
        push    n               ; zgodnie z ABI nie powinna się zmienić
        push    r12             ; po zakończeniu funkcji
        push    result


main_loop:
        mov     rbp, 1          
        lock\
        xadd    [pidx_ptr], rbp 
        cmp     rbp, max        ; i sprawdzam, czy nie jest już większa bądź równa wartości argumentu max
        jge     program_end

        mov     rax, 8          ; Zgodnie ze wskazówką 1. przyjmuję n = 8m
        mul     rbp
        mov     n, rax

        push    rbp             ; Zapisuję indeks komórki, który obliczam 

; Obliczam  [ I ] { 16^n π } = { 4 * { 16^n * S1 } − 2 * { 16^n * S4 } − { 16^n * S5 } − { 16^n * S6 } } 
        xor     result, result
; Obliczam { 16^n * Sj } = { { ∑[ (16^(n−k) mod 8k + j) / (8k + j) ] } + ∑[ 16^(n−k) / (8k + j) ] } dla:
; j = 1
        mov     rbp, 1
        call    calculate_Sj
        shl     r9, 2           ; Zgodnie z [ I ], { 16^n * S1 } mnożę przez 4
        add     result, r9      ; i dodaję do wyniku
; j = 4
        mov     rbp, 4
        call    calculate_Sj
        shl     r9, 1           ; Zgodnie z [ I ], { 16^n * S4 } mnożę przez 2
        sub     result, r9      ; i dodaję do wyniku wartość przeciwną
; j = 5
        mov     rbp, 5
        call    calculate_Sj
        sub     result, r9      ; Dodaję do wyniku wartość przeciwną
; j = 6
        mov     rbp, 6
        call    calculate_Sj
        sub     result, r9      ; Dodaję do wyniku wartość przeciwną

        pop     rbp             ; Odzyskuję indeks komórki, który obliczam 
        shr     result, 32      ; i zapisuję w tej komórce starsze 32 bity obliczonego wyniku
        mov     [ppi_ptr + 4 * rbp], result_32 

        jmp     main_loop

program_end:

        rdtsc                   ; Zapisuję liczbę ticków procesora
        mov     rdi, rdx        ; i przekazuję ją jako argument do funkcji pixtime
        shl     rdi, 32         ; rdtsc zapisuje ticki na 2 rejestrach 32 bitowych, więc przepisuję 
        add     rdi, rax        ; je na 1 rejestr - rdi
        call    pixtime 

        pop     result
        pop     r12             ; odzyskuję wrzucone na stos rejestry
        pop     n
        pop     rbp
        pop     max
        pop     pidx_ptr
        pop     ppi_ptr

        ret


; calculate_Sj dla zadanego n i j oblicza 16^n * Sj ze wzoru z
; https://math.stackexchange.com/questions/880904/how-do-you-use-the-bbp-formula-to-calculate-the-nth-digit-of-%CF%80
; Korzysta z argumentów w rejestrach:
; rbx ( zapisywane jako n ) - pełni rolę n
; rbp - pełni rolę j
; Modyfikuje rejestry: 
; r8 - kolejne potęgi 16 ( licznik )
; r9 - wynik
; r10 - zmienna pomocnicza
; r11 - k w obu sumach
; r12 - zmienna pomocnicza
; rdi - zmienna pomocnicza
; rsi - zmienna pomocnicza
; rax - zmienna pomocnicza ( obliczenia div i mul )
; rdx - zmienna pomocnicza ( obliczenia div i mul )
calculate_Sj:
        xor     r9, r9
; left_Sj_component dla n (rbx), j (rbp) oblicza część ułamkową [ sum 16^(n-k)/(8k + j), k=0 to n ]
        xor     r11, r11
left_Sj_component_sum_loop:
        
        mov     rax, 8          ; Obliczam 8k + j
        mul     r11
        add     rax, rbp     
        mov     r12, rax        ; Przenoszę mianownik do zmiennej pomocniczej 

        mov     rdi, n          ; Wykładnik potęgi 16,
        sub     rdi, r11        ; czyli n-k

left_Sj_component_fast_modulo_power:
        mov     r10, 0x10       ; w r10 trzymam pomocnicze potęgi 16 mod 8k + j

        mov     rax, 0x1        ; Obliczam 1 mod 8k + j
        xor     rdx, rdx        
        div     r12
        mov     rsi, rdx        ; W rsi trzymam wynik 
        test    rdi, rdi        ; Sprawdzam, czy wykładnik potęgi to 0, jeśli nie, zaczynam potęgować
        je      left_Sj_component_fast_modulo_power_end
        mov     r8, 0x1         ; Zmienna do sprawdzania które bity wykładnika potęgi są zapalone
left_Sj_component_fast_modulo_power_loop:
        mov     rax, r10        ; Moduluję obecną potęgę 16 przez 8k + j
        xor     rdx, rdx
        div     r12
        mov     r10, rdx        

        test    rdi, r8         ; sprawdzam czy r8-ty ( licząc od najmniej znaczącego )
                                ; bit wykładnika potęgi jest zapalony
        je      left_Sj_component_fast_modulo_power_loop_condition
        mov     rax, rsi        ; jeśli jest, mnożę wynik przez obecną potęgę 16
        mul     r10
        xor     rdx, rdx        ; i obliczam jej modulo 8k + j
        div     r12             
        mov     rsi, rdx        ; Wynik zapisuję z powrotem w odpowiedniej zmiennej 
left_Sj_component_fast_modulo_power_loop_condition:        
        imul    r10, r10        ; Obecną potęgę 16 mod 8k + j podnoszę do kwadratu 
        add     r8, r8          ; Wskaźnik na kolejne zapalone bity przesuwam o 1 w stronę bardziej znaczących
        cmp     rdi, r8         ; i sprawdzam, czy nie sięga on już poza zapis bitowy wykładnika potęgi 
        jge     left_Sj_component_fast_modulo_power_loop
left_Sj_component_fast_modulo_power_end:
        xor     rax, rax        ; Obliczam iloraz policzonej potęgi oraz 8k + j
        mov     rdx, rsi        
        div     r12

        add     r9, rax         ; Dodaję składnik do sumy
        inc     r11             ; Zwiększam k
        cmp     r11, n          ; i sprawdzam czy jest większe od n
                                ; jeśli nie, obliczam następny składnik sumy 
        jle     left_Sj_component_sum_loop

; right_Sj_component dla n (rbx) i j (rbp) oblicza [ sum 16^(n-k)/(8k + j), k=n+1 to infinity ]
; z dokładnością przynajmniej do 2^(-32) dla n <= 2^32
        mov     r8, 0x1
right_Sj_component_sum_loop:
        mov     rax, r8         ; Poprzednia potęga 16 w mianowniku
        shl     rax, 4          ; Teraz mianownik to 16^(k - n),
                                ; docelowo ma wynosić 16^(k - n) * (8k + j)
                                ; jest to tyle samo co 16^(k - n) * 8k + 16^(k - n) * j
        test    rax, rax        ; sprawdzam czy mianownik sumy nie jest większy niż 2^64
                                ; ( czyli nie zmieścił się w 64 bitowym rejestrze ) 
                                ; jeśli tak jest, kończę liczenie sumy
        jz      right_Sj_component_end
        mov     r8, rax         ; Zapisuję do następnego obrotu pętli obecną potęgę 16
        imul    rax, 0x8        ; Mianownik w rax mnożę przez 8,
        mul     r11             ; a teraz przez k
                                ; czyli teraz wynosi 16^(k - n) * 8k
        mov     r10, rax        ; zapisuję częściowy mianownik

        mov     rax, r8         ; do rax ponownie wrzucam 16^(k - n)
        imul    rax, rbp        ; i mnożę go przez j uzyskując drugi składnik mianownika
        add     r10, rax        ; Sumuję z pierwszym składnikiem uzyskując 16^(k - n) * (8k + j)

        xor     rax, rax        ; przed dzieleniem zeruję rax, a do rdx wkładam licznik
        mov     rdx, 1          ; w ten sposób będę dzielił 2^64 * licznik 
        div     r10             ; więc w rax dostanę pierwsze 64 bity części ułamkowej ilorazu

        add     r9, rax         ; dodaję składnik do sumy
        inc     r11             ; zwiększam k

        jmp     right_Sj_component_sum_loop
right_Sj_component_end: 

        ret
