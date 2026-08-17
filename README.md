# Whitespace IDE (HolyC)

Een kleine **IDE geschreven in HolyC** waarin je een eigen, minimalistische
**stack-assembly** typt (denk aan `push`, `pop`, `add`, …), die automatisch
wordt **vertaald naar de esoterische taal [Whitespace](https://en.wikipedia.org/wiki/Whitespace_(programming_language))**,
en die je in diezelfde IDE meteen kunt **draaien**.

De interface is een TUI in de stijl van `archinstall`: een menu met
pijltjestoetsen, plus een teksteditor.

```
  Whitespace IDE
  custom stack-asm  →  Whitespace  →  run
  ====================================

    Bewerk code
    Assembleer naar Whitespace
    Toon Whitespace (zichtbaar)
    Run Whitespace
    Voorbeeld laden
    Opslaan naar bestand
    Afsluiten

  ↑/↓ selecteren · Enter bevestigen · q of Ctrl+C afsluiten
```

## Hoe het werkt

1. Je typt custom assembly, bijvoorbeeld:

   ```
   push 72
   outc          ; print 'H'
   push 10
   outc          ; print newline
   ```

2. **Assembleer** vertaalt dit naar echte Whitespace (alleen spaties, tabs
   en newlines):

   ```
   SSSTSSTSSSL
   TL
   SSSTSTSL
   TL
   LLL
   ```

   (`S` = spatie, `T` = tab, `L` = newline — dit is de *zichtbare* weergave;
   het echte bestand bevat enkel spaties/tabs/newlines.)

3. **Run Whitespace** voert die Whitespace uit met de ingebouwde interpreter.
   Het voorbeeld hierboven print `H` gevolgd door een newline.

De interpreter ondersteunt de **volledige Whitespace-specificatie**:
stack-manipulatie, rekenkunde, heap, flow control (labels, jumps,
subroutines) en I/O. De custom assembly is bewust klein gehouden.

## Vereisten

- Linux of macOS op **x86_64** (of ARM64)
- `gcc`, `make`, `cmake`
- De HolyC-compiler **[holyc-lang](https://github.com/Jamesbarford/holyc-lang)**

### holyc-lang installeren

```bash
git clone https://github.com/Jamesbarford/holyc-lang
cd holyc-lang
make -j4            # bouwt ./hcc  (gebruikt cmake)
sudo make install   # installeert hcc + de tos-bibliotheek naar /usr/local
```

## Bouwen en draaien

```bash
git clone https://github.com/TheCookieGod64/whitespace-ide
cd whitespace-ide
make            # of: hcc src/ide.HC -o wside
./wside
```

## Bediening

**Menu**

| Toets        | Actie                          |
|--------------|--------------------------------|
| `↑` / `↓`    | selecteren                     |
| `Enter`/`spatie` | bevestigen                |
| `q` / `Ctrl+C` | afsluiten                   |

**Editor**

| Toets        | Actie                          |
|--------------|--------------------------------|
| typen        | tekst invoegen                 |
| pijltjes     | cursor verplaatsen             |
| `Backspace`  | teken/regel verwijderen        |
| `Ctrl+A`     | naar begin van de regel         |
| `Ctrl+E`     | naar eind van de regel          |
| `Ctrl+D`     | klaar (opslaan, terug naar menu)|

## De custom assembly

Eén instructie per regel. Regels die met `;` of `#` beginnen zijn commentaar.
Zie [docs/WHITESPACE.md](docs/WHITESPACE.md) voor de exacte vertaling naar
Whitespace.

| Instructie  | Betekenis                                        |
|-------------|--------------------------------------------------|
| `push N`    | duw getal `N` op de stack                        |
| `pop`       | gooi de bovenste waarde weg                      |
| `dup`       | dupliceer de bovenste waarde                     |
| `swap`      | wissel de bovenste twee waarden                  |
| `add`       | pop b, pop a, duw `a + b`                        |
| `sub`       | pop b, pop a, duw `a - b`                        |
| `mul`       | pop b, pop a, duw `a * b`                        |
| `div`       | pop b, pop a, duw `a / b` (integer)              |
| `mod`       | pop b, pop a, duw `a % b`                        |
| `out`       | pop een getal en print het **als getal**         |
| `outc`      | pop een getal en print het **als karakter**      |
| `read`      | lees een geheel getal van stdin en duw het op de stack |
| `readc`     | lees één karakter van stdin en duw het op de stack |
| `pick N`    | kopieer het N-de item van de stack naar de top (N=0 is `dup`) |

## Projectstructuur

```
src/ws.HC      engine: assembler (asm → Whitespace) + interpreter
src/ide.HC     de TUI-IDE (editor + menu), include ws.HC
src/tests.HC   niet-interactieve tests voor de engine
examples/      een paar .asm-voorbeelden
docs/          de Whitespace-encodingreferentie
```

## Tests

```bash
make test       # compileert en draait src/tests.HC
```

De engine is ook gevalideerd tegen een **onafhankelijke** Whitespace-
interpreter (rechtstreeks van de officiële specificatie): de gegenereerde
`.ws`-bestanden draaien daarop met identiek resultaat.

## Licentie

MIT — zie [LICENSE](LICENSE).
