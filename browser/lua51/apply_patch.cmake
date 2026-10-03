if(NOT DEFINED LUA51_SOURCE_DIR)
    message(FATAL_ERROR "LUA51_SOURCE_DIR is required")
endif()

function(astra_replace_exact variable old_text new_text description)
    string(FIND "${${variable}}" "${old_text}" match_position)
    if(match_position EQUAL -1)
        message(FATAL_ERROR "Unable to apply Astra Lua 5.1 patch: ${description}")
    endif()
    string(REPLACE "${old_text}" "${new_text}" replaced "${${variable}}")
    set(${variable} "${replaced}" PARENT_SCOPE)
endfunction()

set(llex_h_path "${LUA51_SOURCE_DIR}/llex.h")
set(llex_c_path "${LUA51_SOURCE_DIR}/llex.c")
set(lparser_c_path "${LUA51_SOURCE_DIR}/lparser.c")

file(READ "${llex_h_path}" llex_h)
if(NOT llex_h MATCHES "TK_DBCOLON")
    astra_replace_exact(llex_h
        "TK_CONCAT, TK_DOTS, TK_EQ, TK_GE, TK_LE, TK_NE, TK_NUMBER,"
        "TK_CONCAT, TK_DOTS, TK_EQ, TK_GE, TK_LE, TK_NE, TK_DBCOLON, TK_NUMBER,"
        "add the double-colon token")
    file(WRITE "${llex_h_path}" "${llex_h}")
endif()

file(READ "${llex_c_path}" llex_c)
if(NOT llex_c MATCHES "return TK_DBCOLON")
    astra_replace_exact(llex_c
        [=[    "..", "...", "==", ">=", "<=", "~=",
]=]
        [=[    "..", "...", "==", ">=", "<=", "~=", "::",
]=]
        "add the double-colon token name")
    astra_replace_exact(llex_c
        [=[      case '~': {
        next(ls);
        if (ls->current != '=') return '~';
        else { next(ls); return TK_NE; }
      }
]=]
        [=[      case '~': {
        next(ls);
        if (ls->current != '=') return '~';
        else { next(ls); return TK_NE; }
      }
      case ':': {
        next(ls);
        if (ls->current != ':') return ':';
        else { next(ls); return TK_DBCOLON; }
      }
]=]
        "lex the double-colon token")
    file(WRITE "${llex_c_path}" "${llex_c}")
endif()

file(READ "${lparser_c_path}" lparser_c)
if(NOT lparser_c MATCHES "astra_lua51_goto_state.inc|MAX_GOTO_DESCRIPTORS")
    astra_replace_exact(lparser_c
        [=[} BlockCnt;



/*
** prototypes for recursive non-terminal functions
*/
]=]
        [=[} BlockCnt;

#include "astra_lua51_goto_state.inc"


/*
** prototypes for recursive non-terminal functions
*/
]=]
        "include the goto parser state")

    astra_replace_exact(lparser_c
        [=[static void enterblock (FuncState *fs, BlockCnt *bl, lu_byte isbreakable) {
  bl->breaklist = NO_JUMP;
  bl->isbreakable = isbreakable;
  bl->nactvar = fs->nactvar;
  bl->upval = 0;
  bl->previous = fs->bl;
  fs->bl = bl;
  lua_assert(fs->freereg == fs->nactvar);
}
]=]
        [=[static void enterblock (FuncState *fs, BlockCnt *bl, lu_byte isbreakable) {
  GotoParserState *state = currentgotostate(fs);
  check_condition(fs->ls, state->nextScope + 1 < MAX_GOTO_SCOPES,
                  "function has too many nested blocks for goto labels");
  state->nextScope++;
  state->scopeParents[state->nextScope] = state->currentScope;
  state->currentScope = state->nextScope;
  bl->breaklist = NO_JUMP;
  bl->isbreakable = isbreakable;
  bl->nactvar = fs->nactvar;
  bl->upval = 0;
  bl->previous = fs->bl;
  fs->bl = bl;
  state->depth++;
  lua_assert(fs->freereg == fs->nactvar);
}
]=]
        "track goto block entry")

    astra_replace_exact(lparser_c
        [=[static void leaveblock (FuncState *fs) {
  BlockCnt *bl = fs->bl;
  fs->bl = bl->previous;
]=]
        [=[static void leaveblock (FuncState *fs) {
  BlockCnt *bl = fs->bl;
  GotoParserState *state = currentgotostate(fs);
  deactivateblocklabels(fs, state->depth);
  state->currentScope = state->scopeParents[state->currentScope];
  state->depth--;
  fs->bl = bl->previous;
]=]
        "track goto block exit")

    astra_replace_exact(lparser_c
        [=[static void open_func (LexState *ls, FuncState *fs) {
  lua_State *L = ls->L;
  Proto *f = luaF_newproto(L);
]=]
        [=[static void open_func (LexState *ls, FuncState *fs) {
  lua_State *L = ls->L;
  GotoParserState *state = luaM_new(L, GotoParserState);
  Proto *f = luaF_newproto(L);
  memset(state, 0, sizeof(*state));
  state->previous = gotoState;
  state->fs = fs;
  gotoState = state;
]=]
        "create per-function goto state")

    astra_replace_exact(lparser_c
        [=[  FuncState *fs = ls->fs;
  Proto *f = fs->f;
  removevars(ls, 0);
]=]
        [=[  FuncState *fs = ls->fs;
  GotoParserState *state = currentgotostate(fs);
  Proto *f = fs->f;
  int i;
  for (i = 0; i < state->ngotos; ++i) {
    if (!state->gotos[i].resolved)
      luaX_syntaxerror(ls, luaO_pushfstring(L,
        "no visible label '%s' for goto at line %d",
        getstr(state->gotos[i].name), state->gotos[i].line));
  }
  removevars(ls, 0);
]=]
        "validate unresolved gotos")

    astra_replace_exact(lparser_c
        [=[  ls->fs = fs->prev;
  /* last token read was anchored in defunct function; must reanchor it */
]=]
        [=[  ls->fs = fs->prev;
  gotoState = state->previous;
  luaM_free(L, state);
  /* last token read was anchored in defunct function; must reanchor it */
]=]
        "release per-function goto state")

    astra_replace_exact(lparser_c
        [=[  struct LexState lexstate;
  struct FuncState funcstate;
  lexstate.buff = buff;
]=]
        [=[  struct LexState lexstate;
  struct FuncState funcstate;
  gotoState = NULL;
  lexstate.buff = buff;
]=]
        "reset goto state for a parser invocation")

    astra_replace_exact(lparser_c
        [=[  luaK_concat(fs, &bl->breaklist, luaK_jump(fs));
}


static void whilestat (LexState *ls, int line) {
]=]
        [=[  luaK_concat(fs, &bl->breaklist, luaK_jump(fs));
}

#include "astra_lua51_goto_statements.inc"


static void whilestat (LexState *ls, int line) {
]=]
        "include goto and label statements")

    astra_replace_exact(lparser_c
        [=[    case TK_BREAK: {  /* stat -> breakstat */
      luaX_next(ls);  /* skip BREAK */
      breakstat(ls);
      return 1;  /* must be last statement */
    }
    default: {
]=]
        [=[    case TK_BREAK: {  /* stat -> breakstat */
      luaX_next(ls);  /* skip BREAK */
      breakstat(ls);
      return 1;  /* must be last statement */
    }
    case TK_DBCOLON: {  /* stat -> :: NAME :: */
      labelstat(ls);
      return 0;
    }
    case TK_NAME: {
      if (strcmp(getstr(ls->t.seminfo.ts), "goto") == 0) {
        gotostat(ls);
        return 0;
      }
      exprstat(ls);
      return 0;
    }
    default: {
]=]
        "parse goto and label statements")

    file(WRITE "${lparser_c_path}" "${lparser_c}")
endif()

# Upgrade previously patched build trees as well as fresh Lua sources. Anchor
# parser state in Lua-owned userdata: syntax errors longjmp past close_func,
# so a raw luaM_new allocation would leak on every unsuccessful compilation.
set(lparser_h_path "${LUA51_SOURCE_DIR}/lparser.h")
file(READ "${lparser_h_path}" lparser_h)
if(NOT lparser_h MATCHES "struct GotoParserState \\*gotoState")
    astra_replace_exact(lparser_h
        "  struct BlockCnt *bl;  /* chain of current blocks */"
        "  struct BlockCnt *bl;  /* chain of current blocks */\n  struct GotoParserState *gotoState;  /* Lua-owned parser userdata */"
        "attach goto state to its function instead of a process global")
    file(WRITE "${lparser_h_path}" "${lparser_h}")
endif()

file(READ "${lparser_c_path}" lparser_c)
if(lparser_c MATCHES "luaM_new\\(L, GotoParserState\\)")
    astra_replace_exact(lparser_c
        [=[  GotoParserState *state = luaM_new(L, GotoParserState);
  Proto *f = luaF_newproto(L);
  memset(state, 0, sizeof(*state));
  state->previous = gotoState;
  state->fs = fs;
  gotoState = state;
]=]
        [=[  GotoParserState *state;
  Proto *f;
  luaD_checkstack(L, 3);
  f = luaF_newproto(L);
]=]
        "make goto state collectible on syntax errors")
    astra_replace_exact(lparser_c
        [=[  gotoState = state->previous;
  luaM_free(L, state);
]=]
        ""
        "remove manual goto state lifetime")
    astra_replace_exact(lparser_c
        "  L->top -= 2;  /* remove table and prototype from the stack */"
        "  L->top -= 3;  /* remove parser userdata, table and prototype */"
        "unanchor goto state after successful compilation")
    astra_replace_exact(lparser_c "  gotoState = NULL;\n" ""
        "remove process-global parser reset")
    file(WRITE "${lparser_c_path}" "${lparser_c}")
endif()

# A public userdata allocation can step the GC. The chunk source is not rooted
# until the prototype is on the stack, so allocate only after anchoring it.
# Also migrate build trees produced by the earlier userdata patch.
if(NOT lparser_c MATCHES "prototype/source are rooted before userdata allocation")
    string(REPLACE [=[  state = (GotoParserState *)lua_newuserdata(L, sizeof(*state));
  memset(state, 0, sizeof(*state));
  fs->gotoState = state;
  f = luaF_newproto(L);
]=] [=[  f = luaF_newproto(L);
]=] lparser_c "${lparser_c}")
    astra_replace_exact(lparser_c
        [=[  setptvalue2s(L, L->top, f);
  incr_top(L);
}
]=]
        [=[  setptvalue2s(L, L->top, f);
  incr_top(L);
  /* prototype/source are rooted before userdata allocation steps the GC */
  state = (GotoParserState *)lua_newuserdata(L, sizeof(*state));
  memset(state, 0, sizeof(*state));
  fs->gotoState = state;
}
]=]
        "protect the source name during parser userdata allocation")
    file(WRITE "${lparser_c_path}" "${lparser_c}")
endif()
