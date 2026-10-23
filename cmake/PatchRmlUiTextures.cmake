# Pinned RmlUi 6.3 caches can outlive an individual render manager. Do not let
# shared RCSS/spritesheets reuse its non-owning textures after a host is closed.
function(astra_patch_rmlui_textures source_dir)
    set(core "${source_dir}/Source/Core")
    set(headers "${source_dir}/Include/RmlUi/Core")
    file(READ "${core}/Texture.cpp" texture)
    if(texture MATCHES "ASTRA_RENDERER_SCOPED_TEXTURES")
        return()
    endif()
    function(astra_texture_replace variable before after)
        string(FIND "${${variable}}" "${before}" found)
        if(found EQUAL -1)
            message(FATAL_ERROR "Pinned RmlUi texture source changed; lifecycle patch needs review")
        endif()
        string(REPLACE "${before}" "${after}" result "${${variable}}")
        set(${variable} "${result}" PARENT_SCOPE)
    endfunction()

    # RenderManager already caches sources in its own FileTextureDatabase. The
    # second cache on a shared TextureSource was redundant and keyed by an address
    # that the allocator can reuse for a different, empty texture database.
    astra_texture_replace(texture [=[	Texture& texture = textures[&render_manager];
	if (!texture)
		texture = render_manager.LoadTexture(source, document_path);
	return texture;]=] [=[	// ASTRA_RENDERER_SCOPED_TEXTURES: resolve through the current manager's cache.
	return render_manager.LoadTexture(source, document_path);]=])
    file(READ "${headers}/Texture.h" texture_header)
    astra_texture_replace(texture_header "\tmutable SmallUnorderedMap<RenderManager*, Texture> textures;\n" "")

    # ObserverPtr is the library's weak lifetime token. It distinguishes a live
    # manager from a new manager allocated at the same address, without owning it.
    file(READ "${headers}/RenderManager.h" manager_header)
    astra_texture_replace(manager_header "#include \"Mesh.h\"" "#include \"Mesh.h\"\n#include \"ObserverPtr.h\"")
    astra_texture_replace(manager_header "class RMLUICORE_API RenderManager : NonCopyMoveable {"
        "class RMLUICORE_API RenderManager : NonCopyMoveable, public EnableObserverPtr<RenderManager> {")
    file(READ "${headers}/StyleSheet.h" sheet_header)
    astra_texture_replace(sheet_header "#include \"PropertyDictionary.h\"" "#include \"PropertyDictionary.h\"\n#include \"ObserverPtr.h\"")
    astra_texture_replace(sheet_header "\tmutable DecoratorCache decorator_cache;" [=[	struct RendererDecoratorCache {
		ObserverPtr<RenderManager> owner;
		DecoratorCache decorators;
	};
	mutable Vector<RendererDecoratorCache> renderer_decorator_caches;]=])

    file(READ "${core}/StyleSheet.cpp" sheet)
    astra_texture_replace(sheet "#include \"../../Include/RmlUi/Core/Decorator.h\""
        "#include \"../../Include/RmlUi/Core/Decorator.h\"\n#include \"../../Include/RmlUi/Core/RenderManager.h\"")
    astra_texture_replace(sheet [=[	String key;

	if (enable_cache)
	{
		key.reserve]=] [=[	String key;
	DecoratorCache* renderer_cache = nullptr;

	if (enable_cache)
	{
		// Purge expired owners before using a cache entry. A raw address is not
		// a lifetime identity, and a decorator embeds non-owning Texture views.
		renderer_decorator_caches.erase(std::remove_if(renderer_decorator_caches.begin(), renderer_decorator_caches.end(),
			[](const RendererDecoratorCache& entry) { return !entry.owner; }), renderer_decorator_caches.end());
		auto owner = std::find_if(renderer_decorator_caches.begin(), renderer_decorator_caches.end(),
			[&](const RendererDecoratorCache& entry) { return entry.owner == &render_manager; });
		if (owner == renderer_decorator_caches.end())
		{
			renderer_decorator_caches.push_back({render_manager.GetObserverPtr(), {}});
			owner = renderer_decorator_caches.end() - 1;
		}
		renderer_cache = &owner->decorators;
		key.reserve]=])
    astra_texture_replace(sheet "auto it_cache = decorator_cache.find(key);" "auto it_cache = renderer_cache->find(key);")
    astra_texture_replace(sheet "it_cache != decorator_cache.end()" "it_cache != renderer_cache->end()")
    astra_texture_replace(sheet "enable_cache ? decorator_cache[key] : non_cached_decorator_list"
        "enable_cache ? (*renderer_cache)[key] : non_cached_decorator_list")

    file(WRITE "${headers}/Texture.h" "${texture_header}")
    file(WRITE "${headers}/RenderManager.h" "${manager_header}")
    file(WRITE "${headers}/StyleSheet.h" "${sheet_header}")
    file(WRITE "${core}/StyleSheet.cpp" "${sheet}")
    file(WRITE "${core}/Texture.cpp" "${texture}")
endfunction()
