; Stack-demo: push, swap, dup en pop
push 65
push 66
swap        ; 66 komt bovenaan
outc        ; B
outc        ; A
push 67
dup         ; 67, 67
outc        ; C
pop         ; gooi de bovenste 67 weg
push 10
outc        ; newline
