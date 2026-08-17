/*
 * ide.HC  —  Whitespace IDE (TUI) in HolyC
 *
 * Een kleine IDE met een menu in de stijl van `archinstall` (pijltjestoetsen
 * + Enter) en een teksteditor. Je typt custom stack-assembly, assembleert die
 * naar Whitespace, en draait de Whitespace in dezelfde IDE.
 *
 * Gebruik:
 *   hcc ide.HC -o wside && ./wside
 *
 * Toetsen:
 *   menu    : pijltjes ↑/↓, Enter bevestigen, q of Ctrl+C afsluiten
 *   editor  : typen, pijltjes, Backspace, Ctrl+A begin, Ctrl+E eind,
 *             Ctrl+D klaar (opslaan en terug naar menu)
 *
 * Deze file include ws.HC (de engine: assembler + interpreter).
 */

#include "ws.HC"

/* ------------------------- libc-bindingen (termios) -------------------- */

extern "c" I64  write(I32 fd, U0 *buf, U64 nbyte);
extern "c" I32  fflush(U0 *stream);
extern "c" I32  tcgetattr(I32 fd, U0 *termios_p);
extern "c" I32  tcsetattr(I32 fd, I32 optional_actions, U0 *termios_p);
extern "c" U0   cfmakeraw(U0 *termios_p);
extern "c" I32  isatty(I32 fd);
extern "c" I32  open(U8 *path, I32 flags, I32 mode);
extern "c" I32  close(I32 fd);

/* ------------------------------ constanten ----------------------------- */

#define MAX_LINES   512
#define MAX_COLS    256
#define SRC_MAX     1048576

#define KEY_UP      256
#define KEY_DOWN    257
#define KEY_RIGHT   258
#define KEY_LEFT    259
#define KEY_ESC     260
#define KEY_ENTER   13
#define KEY_CTRL_D  4
#define KEY_CTRL_C  3

/* ---------------------------- globale staat ---------------------------- */

U8   g_lines[MAX_LINES][MAX_COLS];
I64  g_num_lines;
I64  g_cur_line;
I64  g_cur_col;

U8   g_source[SRC_MAX];
I64  g_source_len;

WsProg g_prog;
Bool  g_have_prog;

U8  *g_menu[] = {
  "Bewerk code",
  "Assembleer naar Whitespace",
  "Toon Whitespace (zichtbaar)",
  "Run Whitespace",
  "Voorbeeld laden",
  "Opslaan naar bestand",
  "Afsluiten"
};
#define MENU_COUNT 7
I64 g_sel;

/* --------------------------- raw terminal mode ------------------------- */

U8 g_orig_termios[64];
U8 g_raw_termios[64];

U0 EnterRaw()
{
  tcgetattr(0, g_orig_termios);
  for (I64 i = 0; i < 64; i++)
    g_raw_termios[i] = g_orig_termios[i];
  cfmakeraw(g_raw_termios);
  /* cfmakeraw() zet OPOST uit, waardoor de kernel '\n' niet meer naar
   * '\r\n' vertaalt -> het bekende 'trapjes'-effect. Zet output-processing
   * weer aan (OPOST|ONLCR = 0x1 | 0x4 = 5) zodat de cursor na elke newline
   * terug naar kolom 0 gaat. c_oflag zit op byte-offset 4 (na c_iflag). */
  g_raw_termios[4] = g_raw_termios[4] | 5;
  /* VMIN=1, VTIME=1 (100ms) zodat een losse ESC niet blijft hangen.
   * c_cc begint op offset 17; VMIN is index 6, VTIME is index 5. */
  g_raw_termios[17 + 6] = 1;
  g_raw_termios[17 + 5] = 1;
  tcsetattr(0, 0, g_raw_termios);
}

U0 ExitRaw()
{
  tcsetattr(0, 0, g_orig_termios);
}

/* ------------------------------ invoer -------------------------------- */

I64 GetByte()
{
  U8 b;
  I64 r = read(0, &b, 1);
  if (r <= 0) return -1;
  return b;
}

I64 GetKey()
{
  I64 b = GetByte();
  if (b != 27) return b;
  I64 b2 = GetByte();
  if (b2 < 0) return KEY_ESC;              /* losse ESC (timeout) */
  if (b2 == '[' || b2 == 'O') {
    I64 b3 = GetByte();
    if (b3 == 'A') return KEY_UP;
    if (b3 == 'B') return KEY_DOWN;
    if (b3 == 'C') return KEY_RIGHT;
    if (b3 == 'D') return KEY_LEFT;
    return KEY_ESC;
  }
  return b2;
}

U0 Flush()
{
  fflush(NULL);
}

/* ------------------------------ hulpjes -------------------------------- */

U0 Cls()
{
  /* 2J = wis scherm, H = cursor naar home, 3J = wis scrollback-buffer
   * (xterm-extensie; wordt genegeerd door terminals die het niet kennen).
   * De 3J zorgt ervoor dat oude output (bv. fastfetch) ook uit de
   * scrollback verdwijnt i.p.v. 'bovenaan te blijven hangen'. */
  "\033[2J\033[H\033[3J";
  Flush();
}

U0 WaitKey()
{
  "\n\033[2m[Druk op een toets om verder te gaan]\033[0m\n";
  Flush();
  GetKey();
}

Bool SaveFile(U8 *path, U8 *buf, I64 len)
{
  I32 fd = open(path, 1 | 0x40 | 0x200, 420);   /* O_WRONLY|O_CREAT|O_TRUNC */
  if (fd < 0) return FALSE;
  write(fd, buf, len);
  close(fd);
  return TRUE;
}

U0 PrintWsError(I64 rc)
{
  if (rc == WS_ERR_STACK)     "\033[1;31mStack-onderflow.\033[0m\n";
  else if (rc == WS_ERR_DIV0) "\033[1;31mDeling door nul.\033[0m\n";
  else if (rc == WS_ERR_LABEL)"\033[1;31mOnbekend label.\033[0m\n";
  else if (rc == WS_ERR_RETURN)"\033[1;31mReturn zonder call.\033[0m\n";
  else if (rc == WS_ERR_OVERFLOW)"\033[1;31mOverflow (stack/heap vol).\033[0m\n";
  else if (rc == WS_ERR_SYNTAX)"\033[1;31mSyntaxfout.\033[0m\n";
  else if (rc == WS_ERR_EOF)  "\033[1;31mOnverwacht einde (invoer).\033[0m\n";
}

/* ------------------------------- editor ------------------------------- */

U0 EdInit()
{
  g_num_lines = 1;
  g_cur_line  = 0;
  g_cur_col   = 0;
  g_lines[0][0] = 0;
}

/* Laad een platte bron-string (met '\n') in de editor-buffer. */
U0 EdLoadSource(U8 *src)
{
  I64 li = 0, ci = 0, i = 0;
  g_lines[0][0] = 0;
  while (src[i]) {
    if (src[i] == '\n') {
      g_lines[li][ci] = 0;
      li++;
      if (li >= MAX_LINES) break;
      ci = 0;
    } else if (ci < MAX_COLS - 1) {
      g_lines[li][ci++] = src[i];
    }
    i++;
  }
  g_lines[li][ci] = 0;
  g_num_lines = li + 1;
  g_cur_line = 0;
  g_cur_col  = 0;
}

/* Maak een platte bron-string van de editor-buffer. */
I64 EdToSource(U8 *out, I64 cap)
{
  I64 k = 0;
  for (I64 l = 0; l < g_num_lines; l++) {
    I64 len = StrLen(g_lines[l]);
    for (I64 i = 0; i < len && k < cap - 2; i++)
      out[k++] = g_lines[l][i];
    if (k < cap - 2) out[k++] = '\n';
  }
  out[k] = 0;
  return k;
}

U0 EdInsert(U8 ch)
{
  U8 *line = g_lines[g_cur_line];
  I64 len = StrLen(line);
  if (len >= MAX_COLS - 1) return;
  if (g_cur_col > len) g_cur_col = len;
  for (I64 i = len; i >= g_cur_col; i--)
    line[i + 1] = line[i];
  line[g_cur_col] = ch;
  g_cur_col++;
}

U0 EdNewline()
{
  if (g_num_lines >= MAX_LINES) return;
  for (I64 l = g_num_lines; l > g_cur_line; l--)
    StrCpy(g_lines[l], g_lines[l - 1]);
  StrCpy(g_lines[g_cur_line + 1], g_lines[g_cur_line] + g_cur_col);
  g_lines[g_cur_line][g_cur_col] = 0;
  g_num_lines++;
  g_cur_line++;
  g_cur_col = 0;
}

U0 EdBackspace()
{
  if (g_cur_col > 0) {
    U8 *line = g_lines[g_cur_line];
    I64 len = StrLen(line);
    for (I64 i = g_cur_col - 1; i < len; i++)
      line[i] = line[i + 1];
    g_cur_col--;
  } else if (g_cur_line > 0) {
    I64 prevlen = StrLen(g_lines[g_cur_line - 1]);
    StrCpy(g_lines[g_cur_line - 1] + prevlen, g_lines[g_cur_line]);
    for (I64 l = g_cur_line; l < g_num_lines - 1; l++)
      StrCpy(g_lines[l], g_lines[l + 1]);
    g_num_lines--;
    g_cur_line--;
    g_cur_col = prevlen;
  }
}

U0 EdLeft()
{
  if (g_cur_col > 0) g_cur_col--;
  else if (g_cur_line > 0) {
    g_cur_line--;
    g_cur_col = StrLen(g_lines[g_cur_line]);
  }
}

U0 EdRight()
{
  I64 len = StrLen(g_lines[g_cur_line]);
  if (g_cur_col < len) g_cur_col++;
  else if (g_cur_line < g_num_lines - 1) {
    g_cur_line++;
    g_cur_col = 0;
  }
}

U0 EdUp()
{
  if (g_cur_line > 0) {
    g_cur_line--;
    I64 len = StrLen(g_lines[g_cur_line]);
    if (g_cur_col > len) g_cur_col = len;
  }
}

U0 EdDown()
{
  if (g_cur_line < g_num_lines - 1) {
    g_cur_line++;
    I64 len = StrLen(g_lines[g_cur_line]);
    if (g_cur_col > len) g_cur_col = len;
  }
}

U0 EdRender()
{
  Cls();
  "\033[1;36m  Whitespace IDE  —  Editor\033[0m\n";
  "\033[2m  typ  ·  pijltjes  ·  Backspace  ·  Ctrl+A/E begin/eind  ·  Ctrl+D klaar\033[0m\n";
  "  ------------------------------------------------------------------\n";
  for (I64 l = 0; l < g_num_lines; l++) {
    U8 *line = g_lines[l];
    I64 len = StrLen(line);
    "%3d| ", l + 1;
    if (l == g_cur_line) {
      for (I64 i = 0; i < len; i++) {
        if (i == g_cur_col) "\033[7m%c\033[0m", line[i];
        else                "%c", line[i];
      }
      if (g_cur_col >= len) "\033[7m \033[0m";
    } else {
      "%s", line;
    }
    "\n";
  }
  "\n\033[2m  Ctrl+D = opslaan en terug naar menu\033[0m\n";
  Flush();
}

U0 EditorLoop()
{
  for (;;) {
    EdRender();
    I64 k = GetKey();
    if (k == KEY_CTRL_D) break;
    if (k == KEY_UP)         EdUp();
    else if (k == KEY_DOWN)  EdDown();
    else if (k == KEY_LEFT)  EdLeft();
    else if (k == KEY_RIGHT) EdRight();
    else if (k == KEY_ENTER) EdNewline();
    else if (k == 8 || k == 127) EdBackspace();
    else if (k == 1)  { g_cur_col = 0; }                                  /* Ctrl+A */
    else if (k == 5)  { g_cur_col = StrLen(g_lines[g_cur_line]); }        /* Ctrl+E */
    else if (k >= 32 && k < 127) EdInsert(k(U8));
  }
}

/* -------------------------------- menu --------------------------------- */

U0 MenuRender()
{
  Cls();
  "\033[1;36m  Whitespace IDE\033[0m\n";
  "\033[2m  custom stack-asm  →  Whitespace  →  run\033[0m\n";
  "  ====================================\n\n";
  for (I64 i = 0; i < MENU_COUNT; i++) {
    if (i == g_sel) "\033[7m    %s \033[0m\n", g_menu[i];
    else            "    %s\n", g_menu[i];
  }
  "\n  \033[2m↑/↓ selecteren · Enter bevestigen · q of Ctrl+C afsluiten\033[0m\n";
  Flush();
}

/* ------------------------------- voorbeeld ----------------------------- */

U0 LoadExample()
{
  U8 *ex =
    "; Whitespace IDE - voorbeeld\n"
    "; druk \"Hi\" af en doe een sommetje\n"
    "\n"
    "push 72\n"
    "outc\n"
    "push 105\n"
    "outc\n"
    "push 10\n"
    "outc\n"
    "\n"
    "push 10\n"
    "push 32\n"
    "add\n"
    "push 3\n"
    "mul\n"
    "out\n"
    "push 10\n"
    "outc\n";
  I64 len = StrLen(ex);
  for (I64 i = 0; i <= len; i++)
    g_source[i] = ex[i];
  g_source_len = len;
  g_have_prog = FALSE;
}

/* ------------------------------- acties -------------------------------- */

Bool EnsureAssembled()
{
  if (g_have_prog) return TRUE;
  I64 el = 0;
  U8 eo[32];
  I64 rc = Assemble(g_source, &g_prog, &el, eo, 32);
  if (rc == WS_OK) { g_have_prog = TRUE; return TRUE; }
  "\n\033[1;31m[FOUT] regel %d: onbekende instructie '%s'.\033[0m\n", el, eo;
  WaitKey();
  return FALSE;
}

U0 ActionEdit()
{
  EdLoadSource(g_source);
  EditorLoop();
  g_source_len = EdToSource(g_source, SRC_MAX);
  g_have_prog = FALSE;
}

U0 ActionAssemble()
{
  I64 el = 0;
  U8 eo[32];
  I64 rc = Assemble(g_source, &g_prog, &el, eo, 32);
  if (rc == WS_OK) {
    g_have_prog = TRUE;
    "\n\033[1;32m[OK] Geassembleerd: %d bytes Whitespace.\033[0m\n", g_prog.len;
  } else {
    g_have_prog = FALSE;
    "\n\033[1;31m[FOUT] regel %d: onbekende instructie '%s'.\033[0m\n", el, eo;
  }
  WaitKey();
}

U0 ActionShow()
{
  if (!EnsureAssembled()) return;
  U8 *vis = MAlloc(g_prog.len * 2 + 8);
  WsToVisible(&g_prog, vis, g_prog.len * 2 + 8);
  "\n\033[1mZichtbare Whitespace  (S=spatie, T=tab, L=newline):\033[0m\n";
  "%s", vis;
  "\n";
  Free(vis);
  WaitKey();
}

U0 ActionRun()
{
  if (!EnsureAssembled()) return;
  "\n\033[1m--- Uitvoer ---\033[0m\n";
  I64 rc = RunWhitespace(&g_prog);
  "\n\033[1m--- einde (status %d) ---\033[0m\n", rc;
  if (rc != WS_OK) PrintWsError(rc);
  WaitKey();
}

U0 ActionExample()
{
  LoadExample();
  "\n\033[1;32m[OK] Voorbeeld geladen.\033[0m\n";
  WaitKey();
}

U0 ActionSave()
{
  if (!EnsureAssembled()) return;
  Bool ok1 = SaveFile("program.asm", g_source, g_source_len);
  Bool ok2 = SaveFile("program.ws", g_prog.code, g_prog.len);
  U8 *vis = MAlloc(g_prog.len * 2 + 8);
  I64 vlen = WsToVisible(&g_prog, vis, g_prog.len * 2 + 8);
  Bool ok3 = SaveFile("program_visible.txt", vis, vlen);
  Free(vis);
  "\n";
  if (ok1 && ok2 && ok3)
    "\033[1;32m[OK] Opgeslagen: program.asm, program.ws, program_visible.txt\033[0m\n";
  else
    "\033[1;31m[FOUT] Kon bestanden niet schrijven.\033[0m\n";
  WaitKey();
}

/* ------------------------------- hoofdloop ----------------------------- */

U0 MainLoop()
{
  for (;;) {
    MenuRender();
    I64 k = GetKey();
    if (k == KEY_UP)        { g_sel--; if (g_sel < 0) g_sel = MENU_COUNT - 1; }
    else if (k == KEY_DOWN) { g_sel++; if (g_sel >= MENU_COUNT) g_sel = 0; }
    else if (k == 'q' || k == KEY_CTRL_C) break;
    else if (k == KEY_ENTER || k == ' ') {
      if (g_sel == 6) break;          /* Afsluiten */
      if (g_sel == 0) ActionEdit();
      else if (g_sel == 1) ActionAssemble();
      else if (g_sel == 2) ActionShow();
      else if (g_sel == 3) ActionRun();
      else if (g_sel == 4) ActionExample();
      else if (g_sel == 5) ActionSave();
    }
  }
}

/* --------------------------------- Main -------------------------------- */

U0 Main()
{
  Bool tty = isatty(0) != 0;
  EdInit();
  LoadExample();
  g_sel = 0;
  if (tty) EnterRaw();
  "\033[?25l";
  MainLoop();
  "\033[?25h";
  Cls();
  if (tty) ExitRaw();
}
Main;