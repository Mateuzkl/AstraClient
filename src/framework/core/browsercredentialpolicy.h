#pragma once
#include <string>
#include <cctype>

// Somente o Config do navegador aplica esta politica. Nativo permanece intacto.
inline bool isBrowserCredentialKey(const std::string& key)
{
    std::string normalized;
    for (const unsigned char c : key)
        if (c != '_' && c != '-')
            normalized += static_cast<char>(std::tolower(c));
    return normalized == "password" || normalized == "accountpassword" || normalized == "gtoken" ||
           normalized == "ptoken" || normalized == "token" || normalized == "authenticatortoken" ||
           normalized == "sessionkey" || normalized == "accesstoken" || normalized == "refreshtoken" ||
           normalized == "googlesession" || normalized == "autologin";
}

template <class Node> bool removeBrowserCredentials(const Node& node)
{
    bool changed = false;
    for (const auto& child : node->children())
    {
        if (isBrowserCredentialKey(child->tag()))
        {
            node->removeChild(child);
            changed = true;
        }
        else
        {
            changed = removeBrowserCredentials(child) || changed;
        }
    }
    return changed;
}
