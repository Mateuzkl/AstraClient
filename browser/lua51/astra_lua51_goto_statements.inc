static void gotostat (LexState *ls) {
  FuncState *fs = ls->fs;
  GotoParserState *state = currentgotostate(fs);
  GotoDesc *gt;
  TString *name;
  int i;
  int line = ls->linenumber;
  check_condition(ls, state->ngotos < MAX_GOTO_DESCRIPTORS,
                  "function has too many goto statements");
  luaX_next(ls);  /* skip contextual `goto' name */
  name = str_checkname(ls);
  gt = &state->gotos[state->ngotos++];
  gt->name = name;
  gt->closepc = luaK_codeABC(fs, OP_CLOSE, 0, 0, 0);
  gt->jumppc = luaK_jump(fs);
  gt->line = line;
  gt->nactvar = fs->nactvar;
  gt->depth = state->depth;
  gt->scope = state->currentScope;
  gt->resolved = 0;

  /* A previously declared label is visible from this scope when the
     label's block is an ancestor of the goto's block. */
  for (i = state->nlabels - 1; i >= 0; --i) {
    LabelDesc *label = &state->labels[i];
    if (label->active && samename(label->name, name) &&
        isscopeancestor(state, label->scope, gt->scope)) {
      patchgoto(fs, gt, label->pc, label->nactvar, label->depth);
      break;
    }
  }
}


static void labelstat (LexState *ls) {
  FuncState *fs = ls->fs;
  GotoParserState *state = currentgotostate(fs);
  LabelDesc *label;
  TString *name;
  int i;
  int targetlevel;
  check_condition(ls, state->nlabels < MAX_GOTO_DESCRIPTORS,
                  "function has too many labels");
  luaX_next(ls);  /* skip '::' */
  name = str_checkname(ls);
  checknext(ls, TK_DBCOLON);

  for (i = state->nlabels - 1; i >= 0; --i) {
    LabelDesc *existing = &state->labels[i];
    if (existing->active && existing->scope == state->currentScope &&
        samename(existing->name, name))
      luaX_syntaxerror(ls, luaO_pushfstring(ls->L,
        "label '%s' already defined in this block", getstr(name)));
  }

  /* A label immediately before the block terminator is outside the scope
     of locals declared in the block, matching Lua 5.2/LuaJIT semantics. */
  targetlevel = (block_follow(ls->t.token) && fs->bl != NULL)
                  ? fs->bl->nactvar : fs->nactvar;
  label = &state->labels[state->nlabels++];
  label->name = name;
  label->pc = luaK_getlabel(fs);
  label->nactvar = targetlevel;
  label->depth = state->depth;
  label->scope = state->currentScope;
  label->active = 1;

  for (i = 0; i < state->ngotos; ++i) {
    GotoDesc *gt = &state->gotos[i];
    if (!gt->resolved && samename(gt->name, name) &&
        isscopeancestor(state, label->scope, gt->scope))
      patchgoto(fs, gt, label->pc, label->nactvar, label->depth);
  }
}
