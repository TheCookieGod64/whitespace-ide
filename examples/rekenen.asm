; Rekenkunde-demo: (10 + 32) * 3 = 126
push 10
push 32
add
push 3
mul
out          ; 126
push 10
outc         ; newline

; Deling en modulo: 7 / 2 = 3, 7 % 2 = 1
push 7
push 2
div
out
push 10
outc

push 7
push 2
mod
out
push 10
outc

; Negatieve getallen
push 100
push 105
sub
out          ; -5
push 10
outc
