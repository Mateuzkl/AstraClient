#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <memory>
#include <vector>
#include <algorithm>
#include <framework/core/browsercredentialpolicy.h>
struct Node
{
    std::string name;
    std::vector<std::shared_ptr<Node>> nodes;
    const std::string& tag() const { return name; }
    auto children() const { return nodes; }
    void removeChild(const std::shared_ptr<Node>& child) { nodes.erase(std::find(nodes.begin(), nodes.end(), child)); }
};
int main()
{
    for (const auto* key : {"password", "GTOKEN", "session_key", "authenticatorToken", "Auto-Login", "access_token"})
        assert(isBrowserCredentialKey(key));
    for (const auto* key : {"account", "hotkeys", "quickloot", "minimap", "tokensEarned"})
        assert(!isBrowserCredentialKey(key));
    auto root = std::make_shared<Node>();
    auto preferences = std::make_shared<Node>();
    preferences->name = "preferences";
    for (const auto* key : {"password", "gtoken", "autologin", "hotkeys"})
    {
        auto child = std::make_shared<Node>();
        child->name = key;
        preferences->nodes.push_back(child);
    }
    root->nodes.push_back(preferences);
    assert(removeBrowserCredentials(root));
    assert(preferences->nodes.size() == 1 && preferences->nodes.front()->name == "hotkeys");
    assert(!removeBrowserCredentials(root));
}
