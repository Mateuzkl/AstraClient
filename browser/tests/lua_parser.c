#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

static void *tracked_alloc(void *opaque, void *pointer, size_t old_size, size_t new_size)
{
    size_t *live = (size_t *)opaque;
    if (new_size == 0) {
        if (pointer)
            *live -= old_size;
        free(pointer);
        return NULL;
    }
    void *replacement = realloc(pointer, new_size);
    if (replacement)
        *live = *live - (pointer ? old_size : 0) + new_size;
    return replacement;
}

static void reject(lua_State *state, const char *source)
{
    assert(luaL_loadstring(state, source) != 0);
    lua_pop(state, 1);
}

int main(int argc, char **argv)
{
    size_t live = 0;
    lua_State *state = lua_newstate(tracked_alloc, &live);
    assert(state);
    luaL_openlibs(state);
    // Parsing must not collect the chunk name before its prototype is anchored.
    // This also protects source-relative module/UI paths in the browser client.
    lua_gc(state, LUA_GCSETPAUSE, 0);
    lua_gc(state, LUA_GCSETSTEPMUL, 10000);
    for (int attempt = 0; attempt < 1000; ++attempt) {
        char source_name[128];
        snprintf(source_name, sizeof(source_name), "@/mods/parser_lifecycle/module_%d.lua", attempt);
        const char *source = "return function() goto done; ::done:: return 42 end";
        assert(luaL_loadbuffer(state, source, strlen(source), source_name) == 0);
        assert(lua_pcall(state, 0, 1, 0) == 0);
        lua_Debug info;
        lua_pushvalue(state, -1);
        assert(lua_getinfo(state, ">S", &info));
        assert(strcmp(info.source, source_name) == 0);
        lua_pop(state, 1);
    }
    lua_gc(state, LUA_GCSETPAUSE, 200);
    lua_gc(state, LUA_GCSETSTEPMUL, 200);
    if (argc > 1) {
        if (luaL_dofile(state, argv[1]) != 0) {
            fprintf(stderr, "%s\n", lua_tostring(state, -1));
            abort();
        }
    }
    assert(luaL_dostring(state,
                         "local sum=0; for i=1,5 do if i==2 then goto continue end "
                         "local value=i; sum=sum+value; ::continue:: end; assert(sum==13); "
                         "local n=0; ::again:: n=n+1; if n<3 then goto again end; assert(n==3); "
                         "local funcs={}; for i=1,3 do do local value=i; "
                         "funcs[i]=function() return value end; goto done end; ::done:: end; "
                         "assert(funcs[1]()==1 and funcs[2]()==2 and funcs[3]()==3); "
                         "local function nested() goto finish; ::finish:: return 42 end; assert(nested()==42)") == 0);
    const char *invalid[] = {"goto missing",
                             "local function nested() goto missing end",
                             "goto label; local value=1; ::label:: return value",
                             "goto label; do ::label:: end",
                             "::label:: ::label::",
                             "local function broken("};
    for (size_t i = 0; i < sizeof(invalid) / sizeof(*invalid); ++i)
        reject(state, invalid[i]);
    lua_gc(state, LUA_GCCOLLECT, 0);
    size_t baseline = live;
    for (int attempt = 0; attempt < 1000; ++attempt) {
        for (size_t i = 0; i < sizeof(invalid) / sizeof(*invalid); ++i)
            reject(state, invalid[i]);
        lua_gc(state, LUA_GCCOLLECT, 0);
    }
    assert(live <= baseline + 1024);
    assert(luaL_dostring(state, "goto ok; ::ok:: assert(1+1==2)") == 0);
    lua_close(state);
    assert(live == 0);
    puts("Lua goto semantics, 6000 syntax failures and complete allocator cleanup: PASS");
    return 0;
}
