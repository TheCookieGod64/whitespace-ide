# Whitespace-encoding & vertaling

Whitespace is een taal die enkel bestaat uit **spaties**, **tabs** en
**newlines**. In dit document wordt de gebruikte notatie:

- `S` = spatie (`0x20`)
- `T` = tab (`0x09`)
- `L` = newline (`0x0A`)

## Getallen

Een getal wordt gecodeerd als: `[teken] [binaire cijfers] L`

| Symbool | Betekenis        |
|---------|------------------|
| `S`     | positief / bit 0 |
| `T`     | negatief / bit 1 |

Voorbeeld: `42` = `S` (positief) + `TSTSTS` (101010₂, MSB eerst) + `L`.

## Instructieset (de vertaling)

Dit is hoe de custom assembly naar Whitespace wordt vertaald.

### Stack-manipulatie (IMP = `S`)

| Assembly | Whitespace            |
|----------|-----------------------|
| `push N` | `SS` + getal          |
| `dup`    | `S L S`               |
| `swap`   | `S L T`               |
| `pop`    | `S L L`               |
| `pick N` | `S T` + getal         |

### Rekenkunde (IMP = `T S`)

| Assembly | Whitespace |
|----------|------------|
| `add`    | `T S S S`  |
| `sub`    | `T S S T`  |
| `mul`    | `T S S L`  |
| `div`    | `T S T S`  |
| `mod`    | `T S T T`  |

### I/O (IMP = `T L`)

| Assembly | Whitespace       |
|----------|------------------|
| `outc`   | `T L S S` (char) |
| `out`    | `T L S T` (getal)|
| `readc`  | `T L T S` (char) |
| `read`   | `T L T T` (getal)|

### Einde

|              | Whitespace |
|--------------|------------|
| end programma| `L L L`    |

## Volledige Whitespace-specificatie

De interpreter in `src/ws.HC` ondersteunt daarnaast de **volledige**
Whitespace-specificatie, mocht je ooit handmatig Whitespace willen draaien:

### Flow control (IMP = `L`)

| Instructie        | Whitespace |
|-------------------|------------|
| label             | `L S S` + getal |
| call subroutine   | `L S T` + getal |
| jump              | `L S L` + getal |
| jump if zero      | `L T S` + getal |
| jump if negative  | `L T T` + getal |
| end subroutine    | `L T L`   |
| end programma     | `L L L`   |

### Heap (IMP = `T T`)

| Instructie | Whitespace |
|------------|------------|
| store      | `T T S`    |
| retrieve   | `T T T`    |

### I/O (IMP = `T L`)

| Instructie  | Whitespace |
|-------------|------------|
| output char | `T L S S`  |
| output num  | `T L S T`  |
| read char   | `T L T S`  |
| read num    | `T L T T`  |

## Voorbeeld

```
push 42
out
```

wordt:

```
S S  S TSTSTS L      ; push 42
T L  S T             ; output number
L L L                ; end program
```

wat zichtbaar neerkomt op:

```
SSSTSTSTSL
TLST
LLL
```