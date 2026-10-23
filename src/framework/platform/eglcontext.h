#pragma once

// Choosing a config is not proof that a context can be created (ANGLE DX9,
// old drivers). Commit a version only after the complete attempt succeeds.
namespace AstraEgl {
template<class TryContext>
int negotiateContext(const bool preferEs3, TryContext&& tryContext)
{
    if (preferEs3 && tryContext(3)) return 3;
    if (tryContext(2)) return 2;
    return 0;
}
}
