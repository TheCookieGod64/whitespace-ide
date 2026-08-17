/*
 * ws.HC  —  Whitespace-engine voor de HolyC "Whitespace IDE"
 *
 * Twee onderdelen:
 *   1. Assemble  : vertaal custom stack-assembly naar Whitespace.
 *   2. Run       : voer een Whitespace-programma uit (interpreter).
 *
 * Deze file bevat GEEN user-interface en geen Main(). Die zitten in ide.HC.
 * Zo kun je de engine ook los gebruiken/testen (zie tests.HC).
 *
 * Custom assembly (de "taal" die je in de IDE typt):
 *
 *   push N   duw het getal N op de stack
 *   pop      gooi de bovenste waarde weg
 *   dup      dupliceer de bovenste waarde
 *   swap     wissel de bovenste twee waarden om
 *   add      pop b, pop a, duw a + b
 *   sub      pop b, pop a, duw a - b
 *   mul      pop b, pop a, duw a * b
 *   div      pop b, pop a, duw a / b   (integer)
 *   mod      pop b, pop a, duw a % b
 *   out      pop een getal en print het als getal
 *   outc     pop een getal en print het als karakter (ASCII)
 *   read     lees een geheel getal van stdin en duw het op de stack
 *   readc    lees één karakter van stdin en duw het op de stack
 *   pick N   kopieer het N-de item van de stack naar de top (N=0 is dup)
 *
 * Regels die beginnen met ';' of '#' zijn commentaar.
 */

/* ----------------------------- constanten ------------------------------ */

#define WS_MAX        1048576   /* max. grootte van het Whitespace-programma */
#define WS_STACK_MAX  4096      /* interpreter-stack */
#define WS_HEAP_MAX   4096      /* interpreter-heap */
#define WS_CALL_MAX   1024      /* call-stack (subroutines) */

/* Foutcodes (returnwaarde van Assemble() en RunWhitespace()) */
#define WS_OK           0
#define WS_ERR_SYNTAX   1
#define WS_ERR_STACK    2
#define WS_ERR_DIV0     3
#define WS_ERR_LABEL    4
#define WS_ERR_RETURN   5
#define WS_ERR_OVERFLOW 6
#define WS_ERR_EOF      7

/* -------------------------- datastructuur ------------------------------ */

class WsProg
{
  U8  code[WS_MAX];   /* de ruwe Whitespace (spaties, tabs, newlines) */
  I64 len;            /* gebruikte lengte */
};

/* ------------------------------ emitter -------------------------------- */

U0 WsEmit(WsProg *p, U8 c)
{
  if (p->len < WS_MAX - 1)
    p->code[p->len++] = c;
}

/* Encodeer een getal volgens de Whitespace-specificatie:
 * [sign] [binaire cijfers] [LF],  spatie=+/0, tab=-/1 */
U0 WsEmitNum(WsProg *p, I64 n)
{
  U8 digits[66];
  I64 k = 0;

  if (n < 0) { WsEmit(p, '\t'); n = -n; }
  else       WsEmit(p, ' ');

  if (n == 0) {
    WsEmit(p, ' ');
  } else {
    while (n > 0) {
      if (n & 1) digits[k++] = '\t';
      else       digits[k++] = ' ';
      n >>= 1;
    }
    for (I64 i = k - 1; i >= 0; i--)
      WsEmit(p, digits[i]);
  }
  WsEmit(p, '\n');
}

/* ------------------------- instructie-emitters ------------------------- */

U0 WsPush   (WsProg *p, I64 n) { WsEmit(p,' '); WsEmit(p,' '); WsEmitNum(p,n); }
U0 WsDup    (WsProg *p)        { WsEmit(p,' '); WsEmit(p,'\n'); WsEmit(p,' '); }
U0 WsSwap   (WsProg *p)        { WsEmit(p,' '); WsEmit(p,'\n'); WsEmit(p,'\t'); }
U0 WsPop    (WsProg *p)        { WsEmit(p,' '); WsEmit(p,'\n'); WsEmit(p,'\n'); }
U0 WsAdd    (WsProg *p)        { WsEmit(p,'\t'); WsEmit(p,' '); WsEmit(p,' '); WsEmit(p,' '); }
U0 WsSub    (WsProg *p)        { WsEmit(p,'\t'); WsEmit(p,' '); WsEmit(p,' '); WsEmit(p,'\t'); }
U0 WsMul    (WsProg *p)        { WsEmit(p,'\t'); WsEmit(p,' '); WsEmit(p,' '); WsEmit(p,'\n'); }
U0 WsDiv    (WsProg *p)        { WsEmit(p,'\t'); WsEmit(p,' '); WsEmit(p,'\t'); WsEmit(p,' '); }
U0 WsMod    (WsProg *p)        { WsEmit(p,'\t'); WsEmit(p,' '); WsEmit(p,'\t'); WsEmit(p,'\t'); }
U0 WsOutChr (WsProg *p)        { WsEmit(p,'\t'); WsEmit(p,'\n'); WsEmit(p,' '); WsEmit(p,' '); }
U0 WsOutNum (WsProg *p)        { WsEmit(p,'\t'); WsEmit(p,'\n'); WsEmit(p,' '); WsEmit(p,'\t'); }
U0 WsInChr  (WsProg *p)        { WsEmit(p,'\t'); WsEmit(p,'\n'); WsEmit(p,'\t'); WsEmit(p,' '); }
U0 WsInNum  (WsProg *p)        { WsEmit(p,'\t'); WsEmit(p,'\n'); WsEmit(p,'\t'); WsEmit(p,'\t'); }
U0 WsPick   (WsProg *p, I64 n) { WsEmit(p,' '); WsEmit(p,'\t'); WsEmitNum(p,n); }
U0 WsEnd    (WsProg *p)        { WsEmit(p,'\n'); WsEmit(p,'\n'); WsEmit(p,'\n'); }

/* ------------------------------- assembler ----------------------------- */

U0 SetErrOp(U8 *dst, I64 cap, U8 *src)
{
  I64 k = 0;
  while (src[k] && k < cap - 1) { dst[k] = src[k]; k++; }
  dst[k] = 0;
}

/* Verwerk één regel assembly. Geeft foutcode terug. */
I64 AsmLine(WsProg *prog, U8 *line, I64 line_no,
            I64 *err_line, U8 *err_op, I64 err_op_cap)
{
  I64 i = 0;
  while (line[i] == ' ' || line[i] == '\t') i++;

  if (line[i] == 0) return WS_OK;                        /* lege regel */
  if (line[i] == ';' || line[i] == '#') return WS_OK;    /* commentaar */

  /* lees opcode */
  U8 op[32];
  I64 k = 0;
  while (line[i] && line[i] != ' ' && line[i] != '\t' && k < 31)
    op[k++] = line[i++];
  op[k] = 0;
  while (line[i] == ' ' || line[i] == '\t') i++;

  /* lees (optioneel) operand-getal */
  Bool has_operand = FALSE;
  I64 operand = 0;
  if (line[i] && line[i] != ';' && line[i] != '#') {
    Bool neg = FALSE;
    if (line[i] == '-') { neg = TRUE; i++; }
    else if (line[i] == '+') i++;
    I64 val = 0;
    while (line[i] >= '0' && line[i] <= '9') { val = val * 10 + (line[i] - '0'); i++; }
    if (neg) operand = -val;
    else     operand =  val;
    has_operand = TRUE;
  }

  if      (StrCmp(op, "push") == 0) {
    if (!has_operand) { *err_line = line_no; SetErrOp(err_op, err_op_cap, op); return WS_ERR_SYNTAX; }
    WsPush(prog, operand);
  }
  else if (StrCmp(op, "pop")  == 0) WsPop(prog);
  else if (StrCmp(op, "dup")  == 0) WsDup(prog);
  else if (StrCmp(op, "swap") == 0) WsSwap(prog);
  else if (StrCmp(op, "add")  == 0) WsAdd(prog);
  else if (StrCmp(op, "sub")  == 0) WsSub(prog);
  else if (StrCmp(op, "mul")  == 0) WsMul(prog);
  else if (StrCmp(op, "div")  == 0) WsDiv(prog);
  else if (StrCmp(op, "mod")  == 0) WsMod(prog);
  else if (StrCmp(op, "out")  == 0) WsOutNum(prog);
  else if (StrCmp(op, "outc") == 0) WsOutChr(prog);
  else if (StrCmp(op, "read")  == 0) WsInNum(prog);
  else if (StrCmp(op, "readc") == 0) WsInChr(prog);
  else if (StrCmp(op, "pick")  == 0) {
    if (!has_operand) { *err_line = line_no; SetErrOp(err_op, err_op_cap, op); return WS_ERR_SYNTAX; }
    WsPick(prog, operand);
  }
  else {
    *err_line = line_no;
    SetErrOp(err_op, err_op_cap, op);
    return WS_ERR_SYNTAX;
  }
  return WS_OK;
}

/* Vertaal de volledige assembly-bron (flat string met '\n') naar Whitespace.
 * Bij succes: prog gevuld + WS_OK. Bij fout: foutcode, *err_line en *err_op. */
I64 Assemble(U8 *src, WsProg *prog, I64 *err_line, U8 *err_op, I64 err_op_cap)
{
  prog->len = 0;
  I64 i = 0;
  I64 slen = StrLen(src);
  I64 line_no = 0;
  U8 line[512];

  while (i < slen) {
    line_no++;
    I64 k = 0;
    while (i < slen && src[i] != '\n' && k < 511)
      line[k++] = src[i++];
    if (i < slen && src[i] == '\n') i++;
    line[k] = 0;

    I64 rc = AsmLine(prog, line, line_no, err_line, err_op, err_op_cap);
    if (rc != WS_OK) return rc;
  }
  WsEnd(prog);
  return WS_OK;
}

/* ------------------------------ interpreter ---------------------------- */

extern "c" I64 read(I32 fd, U0 *buf, U64 nbyte);

/* Lees een Whitespace-getal vanaf *pc. */
I64 WsReadNum(WsProg *p, I64 *pc)
{
  I64 neg = 0;
  if (*pc < p->len && p->code[(*pc)++] == '\t') neg = 1;
  I64 val = 0;
  while (*pc < p->len) {
    U8 c = p->code[(*pc)++];
    if (c == '\n') break;
    val = val << 1;
    if (c == '\t') val = val | 1;
  }
  if (neg) return -val;
  return val;
}

/* Zoek de programmapositie van een label (lineair, prima voor kleine
 * programma's). Geeft -1 als het label niet bestaat. */
I64 FindLabel(WsProg *p, I64 target)
{
  I64 pc = 0;
  while (pc < p->len) {
    U8 c = p->code[pc++];
    if (c == '\n') {
      U8 n = p->code[pc++];
      if (n == ' ') {
        U8 n2 = p->code[pc++];
        if (n2 == ' ') {
          I64 lbl = WsReadNum(p, &pc);
          if (lbl == target) return pc;
        } else {
          WsReadNum(p, &pc);
        }
      } else if (n == '\t') {
        U8 n2 = p->code[pc++];
        if (n2 == ' ' || n2 == '\t') WsReadNum(p, &pc);
      } else {
        /* end program = [LF][LF][LF]: IMP + 2 commando-chars.
         * n verbruikte commando[0]; sla commando[1] over. */
        pc++;
      }
    } else if (c == ' ') {
      U8 n = p->code[pc++];
      if (n == ' ') WsReadNum(p, &pc);
      else if (n == '\t') WsReadNum(p, &pc);
    } else if (c == '\t') {
      U8 n = p->code[pc++];
      if (n == ' ') pc += 2;
      else if (n == '\t') pc += 1;
      else pc += 2;
    }
  }
  return -1;
}

/* Lees een geheel getal van stdin (tot en met de newline). */
I64 WsReadInputNum()
{
  U8 tmp[64];
  I64 k = 0;
  while (k < 63) {
    U8 b;
    I64 r = read(0, &b, 1);
    if (r <= 0) break;
    if (b == '\n') break;
    tmp[k++] = b;
  }
  tmp[k] = 0;
  return Atoi(tmp);
}

/* Voer het Whitespace-programma uit. Geeft een foutcode terug. */
I64 RunWhitespace(WsProg *prog)
{
  I64 stack[WS_STACK_MAX];
  I64 sp = 0;
  I64 heap[WS_HEAP_MAX];
  I64 callstk[WS_CALL_MAX];
  I64 csp = 0;
  I64 pc = 0;

  while (pc < prog->len) {
    U8 c = prog->code[pc++];

    if (c == ' ') {                       /* IMP: stack-manipulatie */
      U8 n = prog->code[pc++];
      if (n == ' ') {                     /* push */
        if (sp >= WS_STACK_MAX) return WS_ERR_OVERFLOW;
        stack[sp++] = WsReadNum(prog, &pc);
      } else if (n == '\n') {
        U8 n2 = prog->code[pc++];
        if (n2 == ' ') {                  /* dup */
          if (sp < 1 || sp >= WS_STACK_MAX) return WS_ERR_STACK;
          stack[sp] = stack[sp - 1]; sp++;
        } else if (n2 == '\t') {          /* swap */
          if (sp < 2) return WS_ERR_STACK;
          I64 t = stack[sp - 1];
          stack[sp - 1] = stack[sp - 2];
          stack[sp - 2] = t;
        } else {                          /* discard */
          if (sp < 1) return WS_ERR_STACK;
          sp--;
        }
      } else {                            /* copy n-th */
        I64 idx = WsReadNum(prog, &pc);
        if (idx < 0 || idx >= sp || sp >= WS_STACK_MAX) return WS_ERR_STACK;
        I64 v = stack[sp - 1 - idx];
        stack[sp++] = v;
      }
    }
    else if (c == '\t') {
      U8 n = prog->code[pc++];
      if (n == ' ') {                     /* IMP: rekenkunde */
        U8 o1 = prog->code[pc++];
        U8 o2 = prog->code[pc++];
        if (sp < 2) return WS_ERR_STACK;
        I64 b = stack[--sp];
        I64 a = stack[--sp];
        if      (o1 == ' ' && o2 == ' ')  stack[sp++] = a + b;
        else if (o1 == ' ' && o2 == '\t') stack[sp++] = a - b;
        else if (o1 == ' ' && o2 == '\n') stack[sp++] = a * b;
        else if (o1 == '\t' && o2 == ' ') { if (b == 0) return WS_ERR_DIV0; stack[sp++] = a / b; }
        else if (o1 == '\t' && o2 == '\t') { if (b == 0) return WS_ERR_DIV0; stack[sp++] = a % b; }
        else return WS_ERR_SYNTAX;
      }
      else if (n == '\t') {               /* IMP: heap */
        U8 o = prog->code[pc++];
        if (o == ' ') {                   /* store */
          if (sp < 2) return WS_ERR_STACK;
          I64 val  = stack[--sp];
          I64 addr = stack[--sp];
          if (addr < 0 || addr >= WS_HEAP_MAX) return WS_ERR_OVERFLOW;
          heap[addr] = val;
        } else {                          /* retrieve */
          if (sp < 1) return WS_ERR_STACK;
          I64 addr = stack[--sp];
          if (addr < 0 || addr >= WS_HEAP_MAX) return WS_ERR_OVERFLOW;
          stack[sp++] = heap[addr];
        }
      }
      else {                              /* IMP: I/O */
        U8 o1 = prog->code[pc++];
        U8 o2 = prog->code[pc++];
        if (o1 == ' ') {                  /* output */
          if (sp < 1) return WS_ERR_STACK;
          I64 v = stack[--sp];
          if (o2 == ' ') { "%c", v; }     /* char */
          else           { "%d", v; }     /* num  */
        } else {                          /* input */
          if (sp >= WS_STACK_MAX) return WS_ERR_OVERFLOW;
          if (o2 == ' ') {                /* char */
            U8 b;
            I64 r = read(0, &b, 1);
            if (r <= 0) return WS_ERR_EOF;
            stack[sp++] = b;
          } else {                        /* num */
            stack[sp++] = WsReadInputNum();
          }
        }
      }
    }
    else {                                /* IMP: flow control */
      U8 n = prog->code[pc++];
      if (n == ' ') {
        U8 n2 = prog->code[pc++];
        if (n2 == ' ') {                  /* label: niks doen */
          WsReadNum(prog, &pc);
        } else if (n2 == '\t') {          /* call */
          I64 lbl = WsReadNum(prog, &pc);
          I64 target = FindLabel(prog, lbl);
          if (target < 0) return WS_ERR_LABEL;
          if (csp >= WS_CALL_MAX) return WS_ERR_OVERFLOW;
          callstk[csp++] = pc;
          pc = target;
        } else {                          /* jump */
          I64 lbl = WsReadNum(prog, &pc);
          I64 target = FindLabel(prog, lbl);
          if (target < 0) return WS_ERR_LABEL;
          pc = target;
        }
      } else if (n == '\t') {
        U8 n2 = prog->code[pc++];
        if (n2 == ' ') {                  /* jump if zero */
          I64 lbl = WsReadNum(prog, &pc);
          if (sp < 1) return WS_ERR_STACK;
          I64 v = stack[--sp];
          if (v == 0) {
            I64 target = FindLabel(prog, lbl);
            if (target < 0) return WS_ERR_LABEL;
            pc = target;
          }
        } else if (n2 == '\t') {          /* jump if negative */
          I64 lbl = WsReadNum(prog, &pc);
          if (sp < 1) return WS_ERR_STACK;
          I64 v = stack[--sp];
          if (v < 0) {
            I64 target = FindLabel(prog, lbl);
            if (target < 0) return WS_ERR_LABEL;
            pc = target;
          }
        } else {                          /* end subroutine */
          if (csp < 1) return WS_ERR_RETURN;
          pc = callstk[--csp];
        }
      } else {                            /* end programma */
        return WS_OK;
      }
    }
  }
  return WS_OK;
}

/* ----------------------- hulp: zichtbare whitespace -------------------- */

/* Zet Whitespace om naar een leesbare vorm: S=spatie, T=tab, L=newline. */
I64 WsToVisible(WsProg *prog, U8 *out, I64 out_cap)
{
  I64 k = 0;
  for (I64 i = 0; i < prog->len && k < out_cap - 2; i++) {
    U8 c = prog->code[i];
    if      (c == ' ')  out[k++] = 'S';
    else if (c == '\t') out[k++] = 'T';
    else if (c == '\n') { out[k++] = 'L'; out[k++] = '\n'; }
  }
  out[k] = 0;
  return k;
}