#include "ws.HC"

/* Test de assembler + interpreter. Draait niet-interactief. */

U0 TestAssembleRun(U8 *src)
{
  WsProg prog;
  I64 err_line = 0;
  U8 err_op[32];
  I64 rc = Assemble(src, &prog, &err_line, err_op, 32);
  if (rc != WS_OK) {
    "ASSEMBLE FOUT (rc=%d, regel %d, op='%s')\n", rc, err_line, err_op;
    return;
  }
  "--- assembly: \"%s\"\n", src;
  "--- whitespace (%d bytes, zichtbaar):\n", prog.len;
  U8 vis[4096];
  WsToVisible(&prog, vis, 4096);
  "%s\n", vis;
  "--- output:\n";
  rc = RunWhitespace(&prog);
  "\n--- klaar (rc=%d)\n\n", rc;
}

U0 TestHello()
{
  TestAssembleRun("push 72\noutc\npush 105\noutc\npush 10\noutc\n");
}

U0 TestArith()
{
  TestAssembleRun(
    "push 10\n"
    "push 32\n"
    "add\n"
    "push 3\n"
    "mul\n"
    "out\n"
    "push 10\n"
    "outc\n");
}

/* Handmatig Whitespace met labels + subroutine testen:
 *   push 65, subroutine die het afdrukt, terug, end.
 * Whitespace:
 *   [SS push 65] [SS call label0] [SS push 66] [SS call label0] [LLL end]
 *   [LSS label0] [TS SS outc] ... dit is lastig handmatig; we bouwen via
 *   de emitter-functies in deze test. */
U0 TestFlow()
{
  WsProg p;
  p.len = 0;
  /* label 0 definieert een "print top" subroutine */
  WsEmit(&p, '\n'); WsEmit(&p, ' '); WsEmit(&p, ' ');   /* mark label 0 */
  WsEmitNum(&p, 0);

  WsOutChr(&p);                                          /* print char */
  WsEmit(&p, '\n'); WsEmit(&p, '\t'); WsEmit(&p, '\n');  /* return */

  /* nu het hoofdprogramma vóór het label plaatsen via een tweede buffer is
   * omslachtig; we bouwen gewoon: push 65, call 0, push 66, call 0, end */
  /* (we zetten alles in volgorde: eerst main, dan subroutine) */
  p.len = 0;
  WsPush(&p, 65);
  /* call label 0 */
  WsEmit(&p, '\n'); WsEmit(&p, ' '); WsEmit(&p, '\t'); WsEmitNum(&p, 0);
  WsPush(&p, 66);
  WsEmit(&p, '\n'); WsEmit(&p, ' '); WsEmit(&p, '\t'); WsEmitNum(&p, 0);
  WsEnd(&p);

  /* subroutine na end is onbereikbaar via call? Nee: call zoekt het label
   * overal. Plaats label 0 ná de end. */
  WsEmit(&p, '\n'); WsEmit(&p, ' '); WsEmit(&p, ' '); WsEmitNum(&p, 0);
  WsOutChr(&p);
  WsEmit(&p, '\n'); WsEmit(&p, '\t'); WsEmit(&p, '\n');  /* return */

  "--- flow test (verwacht: AB):\n";
  I64 rc = RunWhitespace(&p);
  "\n--- klaar (rc=%d)\n", rc;
}

U0 Main()
{
  "=== Test 1: Hello ===\n";
  TestHello();
  "=== Test 2: rekenkunde (10+32)*3=126 ===\n";
  TestArith();
  "=== Test 3: labels + subroutine (AB) ===\n";
  TestFlow();
  "=== EINDE ===\n";
}
Main;
