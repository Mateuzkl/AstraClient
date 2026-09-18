/*
** LuaJIT keeps Lua 5.1 semantics but accepts the Lua 5.2-style goto/label
** syntax. AstraClient scripts use that extension primarily to express
** continue. Keep the PUC Lua 5.1 VM and C API, and add only the parser/code
** generation required for forward and backward labels.
*/
#define MAX_GOTO_DESCRIPTORS 512
#define MAX_GOTO_SCOPES 2048

typedef struct GotoDesc {
  TString *name;
  int closepc;
  int jumppc;
  int line;
  int nactvar;
  int depth;
  int scope;
  lu_byte resolved;
} GotoDesc;

typedef struct LabelDesc {
  TString *name;
  int pc;
  int nactvar;
  int depth;
  int scope;
  lu_byte active;
} LabelDesc;

typedef struct GotoParserState {
  struct GotoParserState *previous;
  FuncState *fs;
  GotoDesc gotos[MAX_GOTO_DESCRIPTORS];
  LabelDesc labels[MAX_GOTO_DESCRIPTORS];
  int ngotos;
  int nlabels;
  int depth;
  int currentScope;
  int nextScope;
  int scopeParents[MAX_GOTO_SCOPES];
} GotoParserState;

static GotoParserState *gotoState = NULL;


static int samename (TString *left, TString *right) {
  return left == right ||
         (left->tsv.len == right->tsv.len &&
          memcmp(getstr(left), getstr(right), left->tsv.len) == 0);
}


static GotoParserState *currentgotostate (FuncState *fs) {
  lua_assert(gotoState != NULL && gotoState->fs == fs);
  return gotoState;
}


static int isscopeancestor (GotoParserState *state, int ancestor, int scope) {
  while (scope != ancestor && scope != 0)
    scope = state->scopeParents[scope];
  return scope == ancestor;
}


static void patchgoto (FuncState *fs, GotoDesc *gt, int pc,
                       int nactvar, int depth) {
  if (gt->depth < depth || gt->nactvar < nactvar)
    luaX_syntaxerror(fs->ls, luaO_pushfstring(fs->L,
      "goto '%s' at line %d jumps into a local scope",
      getstr(gt->name), gt->line));
  SETARG_A(fs->f->code[gt->closepc], nactvar);
  luaK_patchlist(fs, gt->jumppc, pc);
  gt->resolved = 1;
}


static void deactivateblocklabels (FuncState *fs, int depth) {
  GotoParserState *state = currentgotostate(fs);
  int i;
  for (i = 0; i < state->nlabels; ++i) {
    if (state->labels[i].depth == depth)
      state->labels[i].active = 0;
  }
}
