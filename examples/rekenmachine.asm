; ═══════════════════════════════════════════════════
;  WhiteASM Rekenmachine
;
;  Leest twee getallen (a en b) van stdin en print:
;    som (a+b), verschil (a-b), product (a*b),
;    quotiënt (a/b), rest (a%b)
;
;  Voorbeeld-invoer:  10  ENTER  3  ENTER
;  Voorbeeld-uitvoer: 13, 7, 30, 3, 1 (elk op eigen regel)
; ═══════════════════════════════════════════════════

read          ; lees a
read          ; lees b
; stack is nu: [ a, b ]  (b bovenaan)

; --- a + b ---
pick 1        ; kopieer a
pick 1        ; kopieer b
add
out
push 10
outc          ; newline

; --- a - b ---
pick 1
pick 1
sub
out
push 10
outc

; --- a * b ---
pick 1
pick 1
mul
out
push 10
outc

; --- a / b ---
pick 1
pick 1
div
out
push 10
outc

; --- a % b ---
pick 1
pick 1
mod
out
push 10
outc
