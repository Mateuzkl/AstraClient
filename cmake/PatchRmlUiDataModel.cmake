# Local data-model reference fixes for the pinned RmlUi 6.3 Lua plugin.
# Applied to the fetched sources during configure in both the CMake and the vc23
# builds: the vc23 RmlUi dependency target configures cmake/rmlui, which pulls in
# cmake/FetchRmlUi.cmake and therefore runs this function too. Installed
# dependency headers are never modified. The Lua data model roots every child
# reference in its value store and only ever frees the three top-level stores, so
# every update that replaced a table used to leak one registry slot and one proxy
# per child. Chat republishes its message list on every new line, which made that
# leak visible as unbounded memory growth.
function(astra_patch_rmlui_data_model source_dir)
    set(lua_dir "${source_dir}/Source/Lua")
    set(path "${lua_dir}/LuaDataModel.cpp")
    file(READ "${path}" model)
    if(model MATCHES "ASTRA_LUA_DATAMODEL_REFS")
        return()
    endif()

    function(rdm_replace_checked variable before after)
        string(FIND "${${variable}}" "${before}" found)
        if(found EQUAL -1)
            message(FATAL_ERROR "Pinned RmlUi Lua data model changed; reference patch needs review")
        endif()
        string(REPLACE "${before}" "${after}" result "${${variable}}")
        set(${variable} "${result}" PARENT_SCOPE)
    endfunction()

    set(before_child [==[	if (lua_type(L, -1) == LUA_TTABLE)
		NewTableProxy(model, proxy->key_ref);
	else if (lua_isnil(L, -1))
	{
		lua_pop(L, 2);
		return DataVariable{};
	}

	lua_rawgeti(L, LUA_REGISTRYINDEX, model->valuestore_ref);
	// -1 = valuestore, -2 = value, -3 = key
	lua_pushvalue(L, -2);
	// -1 = value, -2 = valuestore, -3 = value, -4 = key
	child_ref = luaL_ref(L, -2);
	// -1 = valuestore, -2 = value, -3 = key
	lua_pop(L, 2);
	// -1 = key

	lua_rawgeti(L, LUA_REGISTRYINDEX, model->tablestore_ref);
	// -1 = tablestore, -2 = key
	lua_rawgeti(L, -1, proxy->table_ref);
	// -1 = tablestore entry / nil, -2 = tablestore, -3 = key

	if (lua_type(L, -1) != LUA_TTABLE)
	{
		lua_pop(L, 1);
		// -1 = tablestore, -2 = key
		lua_newtable(L);
		// -1 = tablestore entry, -2 = tablestore, -3 = key
		lua_pushvalue(L, -1);
		// -1 = tablestore entry, -2 = tablestore entry, -3 = tablestore, -4 = key
		lua_rawseti(L, -3, proxy->table_ref);
		// -1 = tablestore entry, -2 = tablestore, -3 = key
	}

	lua_replace(L, -2);
	// -1 = tablestore entry, -2 = key

	lua_pushvalue(L, -2);
	// -1 = key, -2 = tablestore entry, -3 = key
	lua_pushnumber(L, child_ref);
	// -1 = child ref, -2 = key, -3 = tablestore entry, -4 = key
	lua_rawset(L, -3);
	// -1 = tablestore entry, -2 = key
	lua_pop(L, 2);

	return DataVariable(model->objectDef, (void*)(intptr_t)child_ref);
}]==])
    set(after_child [==[	if (lua_isnil(L, -1))
	{
		lua_pop(L, 2);
		return DataVariable{};
	}

	// ASTRA_LUA_DATAMODEL_REFS: lua_gettable above already ran TableProxyGet, which
	// caches the child and (for tables) stores a proxy in the value store. Reusing
	// that reference keeps exactly one owner per child. Allocating a second one
	// here left the first rooted in the value store forever, so every update that
	// replaced a table leaked one extra registry slot per child.
	lua_pop(L, 1);
	// -1 = key
	child_ref = ChildRef(model, proxy->table_ref);
	lua_pop(L, 1);
	if (child_ref == LUA_REFNIL)
		return DataVariable{};

	return DataVariable(model->objectDef, (void*)(intptr_t)child_ref);
}]==])
    rdm_replace_checked(model "${before_child}" "${after_child}")

    set(before_gc [==[static int TableProxyGc(lua_State* L)
{
	struct TableProxy* proxy = (struct TableProxy*)lua_touserdata(L, 1);

	if (proxy->model->valuestore_ref != LUA_NOREF)
	{
		lua_rawgeti(L, LUA_REGISTRYINDEX, proxy->model->valuestore_ref);
		lua_pushnil(L);
		lua_rawseti(L, -2, proxy->table_ref);
		lua_pop(L, 1);
	}

	if (proxy->model->tablestore_ref != LUA_NOREF)
	{
		lua_rawgeti(L, LUA_REGISTRYINDEX, proxy->model->tablestore_ref);
		lua_pushnil(L);
		lua_rawseti(L, -2, proxy->table_ref);
		lua_pop(L, 1);
	}

	proxy->table_ref = LUA_NOREF;

	return 0;
}
]==])
    set(after_gc [==[// ASTRA_LUA_DATAMODEL_REFS: every child reference is owned by exactly one table
// store entry. Dropping that entry has to release its children, otherwise the
// value store keeps them rooted in the registry forever: neither the values nor
// the proxies created for nested tables could ever be collected, so repeatedly
// publishing table data grew memory without bound.
static void UnrefTableChildren(lua_State* L, struct LuaDataModel* model, int table_ref)
{
	if (!model->L || table_ref == LUA_NOREF)
		return;
	if (model->tablestore_ref == LUA_NOREF || model->valuestore_ref == LUA_NOREF)
		return;

	lua_rawgeti(L, LUA_REGISTRYINDEX, model->tablestore_ref);
	lua_rawgeti(L, -1, table_ref);
	lua_remove(L, -2);
	// -1 = table store entry
	if (lua_type(L, -1) != LUA_TTABLE)
	{
		lua_pop(L, 1);
		return;
	}

	lua_pushnil(L);
	while (lua_next(L, -2) != 0)
	{
		// -1 = child ref, -2 = key
		if (lua_isnumber(L, -1))
		{
			int child_ref = (int)lua_tonumber(L, -1);
			lua_pop(L, 1);
			// -1 = key
			lua_rawgeti(L, LUA_REGISTRYINDEX, model->valuestore_ref);
			luaL_unref(L, -1, child_ref);
			lua_pop(L, 1);
		}
		else
			lua_pop(L, 1);
	}

	lua_pop(L, 1);
}

static int TableProxyGc(lua_State* L)
{
	struct TableProxy* proxy = (struct TableProxy*)lua_touserdata(L, 1);

	// ASTRA_LUA_DATAMODEL_REFS: release the children first, then the entry that
	// owns them. The table reference goes through the free list so the value store
	// does not accumulate dead slots on each publish either.
	UnrefTableChildren(L, proxy->model, proxy->table_ref);

	if (proxy->model->valuestore_ref != LUA_NOREF)
	{
		lua_rawgeti(L, LUA_REGISTRYINDEX, proxy->model->valuestore_ref);
		luaL_unref(L, -1, proxy->table_ref);
		lua_pop(L, 1);
	}

	if (proxy->model->tablestore_ref != LUA_NOREF)
	{
		lua_rawgeti(L, LUA_REGISTRYINDEX, proxy->model->tablestore_ref);
		lua_pushnil(L);
		lua_rawseti(L, -2, proxy->table_ref);
		lua_pop(L, 1);
	}

	proxy->table_ref = LUA_NOREF;

	return 0;
}
]==])
    rdm_replace_checked(model "${before_gc}" "${after_gc}")

    file(WRITE "${path}" "${model}")
endfunction()
