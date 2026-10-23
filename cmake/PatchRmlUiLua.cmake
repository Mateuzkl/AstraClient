# Local lifecycle fixes for the pinned RmlUi 6.3 Lua plugin. Applied to fetched
# sources in both CMake and vc23 builds, not to the installed dependency headers.
function(astra_patch_rmlui_lua source_dir)
    set(lua_dir "${source_dir}/Source/Lua")
    file(READ "${lua_dir}/LuaDataModel.cpp" model)
    if(model MATCHES "ASTRA_CONTEXT_OWNED_LUA_MODELS")
        return()
    endif()
    function(replace_checked variable before after)
        string(FIND "${${variable}}" "${before}" found)
        if(found EQUAL -1)
            message(FATAL_ERROR "Pinned RmlUi Lua source changed; lifecycle patch needs review")
        endif()
        string(REPLACE "${before}" "${after}" result "${${variable}}")
        set(${variable} "${result}" PARENT_SCOPE)
    endfunction()

    set(old_table [=[void PushDataModelsTable(lua_State* L)
{
	static constexpr auto datamodels_key = "datamodels";

	lua_pushstring(L, datamodels_key);
	lua_rawget(L, LUA_REGISTRYINDEX);

	if (lua_type(L, -1) == LUA_TTABLE)
		return;

	lua_pop(L, 1);
	lua_newtable(L);
	lua_pushstring(L, datamodels_key);
	lua_pushvalue(L, -2);
	lua_rawset(L, LUA_REGISTRYINDEX);
}]=])
    set(new_table [=[// ASTRA_CONTEXT_OWNED_LUA_MODELS: model names are local to their context.
bool PushDataModelsTable(lua_State* L, Context* context, bool create)
{
	lua_getfield(L, LUA_REGISTRYINDEX, "datamodels");
	if (!lua_istable(L, -1))
	{
		lua_pop(L, 1);
		if (!create) return false;
		lua_newtable(L);
		lua_pushvalue(L, -1);
		lua_setfield(L, LUA_REGISTRYINDEX, "datamodels");
	}
	lua_pushlightuserdata(L, context);
	lua_rawget(L, -2);
	if (!lua_istable(L, -1))
	{
		lua_pop(L, 1);
		if (!create) { lua_pop(L, 1); return false; }
		lua_newtable(L);
		lua_pushlightuserdata(L, context);
		lua_pushvalue(L, -2);
		lua_rawset(L, -4);
	}
	lua_remove(L, -2);
	return true;
}]=])
    replace_checked(model "${old_table}" "${new_table}")
    replace_checked(model "\tPushDataModelsTable(L);" "\tPushDataModelsTable(L, context, true);")
    replace_checked(model [=[	luaL_checktype(L, table_index, LUA_TTABLE);

	DataModelConstructor constructor]=] [=[	luaL_checktype(L, table_index, LUA_TTABLE);

	PushDataModelsTable(L, context, true);
	lua_getfield(L, -1, name.c_str());
	if (luaL_testudata(L, -1, RMLDATAMODEL))
		return true; // Reuse, rather than orphan, an already open Lua model.
	lua_pop(L, 2);

	DataModelConstructor constructor]=])

    # A retained nested proxy must also retain its LuaDataModel userdata. Once
    # closed, indexing either proxy is an ordinary Lua error, never a stale pointer.
    replace_checked(model [=[	proxy->key_ref = key_ref;
]=] [=[	proxy->key_ref = key_ref;
	lua_newtable(L);
	PushValue(model, model->model_ref);
	lua_setfield(L, -2, "model");
	lua_setfenv(L, -2);
]=])
    # Only indexing/mutation should error; __gc must remain valid after close.
    foreach(method IN ITEMS TableProxyGet TableProxySet)
        string(FIND "${model}" "static int ${method}(lua_State* L)" start)
        string(SUBSTRING "${model}" ${start} -1 tail)
        string(FIND "${tail}" "\tstruct TableProxy* proxy = (struct TableProxy*)lua_touserdata(L, 1);" offset)
        string(LENGTH "\tstruct TableProxy* proxy = (struct TableProxy*)lua_touserdata(L, 1);" length)
        math(EXPR insertion "${start} + ${offset} + ${length}")
        string(SUBSTRING "${model}" 0 ${insertion} prefix)
        string(SUBSTRING "${model}" ${insertion} -1 suffix)
        set(model "${prefix}\n\tif (!proxy->model->L) return luaL_error(L, \"DataModel closed\");${suffix}")
    endforeach()

    string(FIND "${model}" "void CloseLuaDataModel(lua_State* L, Context* context, int name_index)" close_start)
    if(close_start EQUAL -1)
        message(FATAL_ERROR "Pinned RmlUi CloseLuaDataModel not found")
    endif()
    string(SUBSTRING "${model}" 0 ${close_start} model)
    string(APPEND model [=[void ReleaseLuaDataModel(lua_State* L, Context* context, const String& name)
{
	if (!PushDataModelsTable(L, context, false)) return;
	lua_getfield(L, -1, name.c_str());
	auto* model = (LuaDataModel*)luaL_testudata(L, -1, RMLDATAMODEL);
	if (model)
	{
		// The native model is already detached. Release every registry reference
		// while the userdata is still rooted on the stack, including captured UI.
		model->L = nullptr;
		model->model_ref = LUA_NOREF;
		for (int* ref : {&model->valuestore_ref, &model->tablestore_ref, &model->keystore_ref})
		{
			luaL_unref(L, LUA_REGISTRYINDEX, *ref);
			*ref = LUA_NOREF;
		}
		delete model->objectDef;
		model->objectDef = nullptr;
	}
	lua_pop(L, 1);
	lua_pushnil(L);
	lua_setfield(L, -2, name.c_str());
	lua_pushnil(L);
	const bool empty = lua_next(L, -2) == 0;
	if (!empty) lua_pop(L, 2);
	lua_pop(L, 1);
	if (empty)
	{
		lua_getfield(L, LUA_REGISTRYINDEX, "datamodels");
		lua_pushlightuserdata(L, context);
		lua_pushnil(L);
		lua_rawset(L, -3);
		lua_pop(L, 1);
	}
}

void CloseLuaDataModel(lua_State* L, Context* context, int name_index)
{
	// The plugin's destroy hook handles both explicit close and context teardown.
	context->RemoveDataModel(luaL_checkstring(L, name_index));
}

} // namespace Lua
} // namespace Rml
]=])

    file(READ "${lua_dir}/LuaDataModel.h" header)
    replace_checked(header "// Close a DataModel" "void ReleaseLuaDataModel(lua_State* L, Rml::Context* context, const String& name);\n// Close a DataModel")
    file(READ "${lua_dir}/LuaPlugin.h" plugin_header)
    replace_checked(plugin_header "\tvoid OnShutdown() override;" "\tvoid OnShutdown() override;\n\tvoid OnDataModelDestroy(Context* context, const String& name) override;")
    file(READ "${lua_dir}/LuaPlugin.cpp" plugin)
    replace_checked(plugin "#include \"LuaPlugin.h\"" "#include \"LuaPlugin.h\"\n#include \"LuaDataModel.h\"")
    replace_checked(plugin "return EVT_BASIC;" "return EVT_BASIC | EVT_DATA_MODEL;")
    replace_checked(plugin "void LuaPlugin::OnShutdown()" "void LuaPlugin::OnDataModelDestroy(Context* context, const String& name)\n{\n\tReleaseLuaDataModel(g_L, context, name);\n}\n\nvoid LuaPlugin::OnShutdown()")
    file(WRITE "${lua_dir}/LuaDataModel.h" "${header}")
    file(WRITE "${lua_dir}/LuaPlugin.h" "${plugin_header}")
    file(WRITE "${lua_dir}/LuaPlugin.cpp" "${plugin}")
    file(WRITE "${lua_dir}/LuaDataModel.cpp" "${model}")
endfunction()
