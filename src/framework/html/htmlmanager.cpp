/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "htmlmanager.h"
#include "htmlparser.h"
#include "htmlnode.h"
#include <cstdio>
#include <framework/ui/uiwidget.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/logger.h>
#include <framework/stdext/format.h>
#include <framework/luaengine/luainterface.h>
#include <framework/otml/otmlnode.h>
#include <framework/ui/uimanager.h>
#include <framework/ui/uiwidget.h>
#include <algorithm>
#include <cctype>

HtmlManager g_html;

namespace {
    static std::vector<css::StyleSheet> GLOBAL_STYLES;

    std::string trimCopy(std::string value) {
        stdext::trim(value);
        return value;
    }

    std::string lowerCopy(std::string value) {
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });
        return value;
    }

    bool isCssColorProperty(const std::string& prop) {
        return prop == "background" ||
               prop == "background-color" ||
               prop == "color" ||
               prop == "border-color" ||
               prop == "border-top-color" ||
               prop == "border-right-color" ||
               prop == "border-bottom-color" ||
               prop == "border-left-color" ||
               prop == "image-color";
    }

    std::string cssNamedColor(const std::string& value) {
        static const std::unordered_map<std::string, std::string> colors = {
            {"transparent", "#00000000"},
            {"black", "#000000"},
            {"white", "#ffffff"},
            {"red", "#ff0000"},
            {"green", "#008000"},
            {"blue", "#0000ff"},
            {"yellow", "#ffff00"},
            {"gray", "#808080"},
            {"grey", "#808080"},
            {"silver", "#c0c0c0"},
            {"orange", "#ffa500"},
            {"darkorange", "#ff8c00"},
            {"purple", "#800080"},
            {"navy", "#000080"},
            {"teal", "#008080"},
            {"olive", "#808000"},
            {"maroon", "#800000"},
            {"brown", "#a52a2a"},
            {"sienna", "#a0522d"},
            {"indigo", "#4b0082"},
            {"darkviolet", "#9400d3"},
            {"darkslateblue", "#483d8b"},
            {"darkslategray", "#2f4f4f"},
            {"darkslategrey", "#2f4f4f"},
            {"midnightblue", "#191970"},
            {"darkred", "#8b0000"},
            {"darkgreen", "#006400"},
            {"darkolivegreen", "#556b2f"},
            {"crimson", "#dc143c"},
            {"firebrick", "#b22222"},
            {"coral", "#ff7f50"},
            {"tomato", "#ff6347"},
            {"royalblue", "#4169e1"},
            {"steelblue", "#4682b4"},
            {"slateblue", "#6a5acd"},
            {"darkblue", "#00008b"},
            {"darkcyan", "#008b8b"},
            {"lightgray", "#d3d3d3"},
            {"lightgrey", "#d3d3d3"},
            {"darkgray", "#a9a9a9"},
            {"darkgrey", "#a9a9a9"},
            {"lightblue", "#add8e6"},
            {"rebeccapurple", "#663399"},
            {"lime", "#00ff00"},
            {"cyan", "#00ffff"},
            {"aqua", "#00ffff"},
            {"magenta", "#ff00ff"},
            {"fuchsia", "#ff00ff"},
            {"gold", "#ffd700"},
            {"pink", "#ffc0cb"},
            {"violet", "#ee82ee"}
        };

        auto it = colors.find(lowerCopy(trimCopy(value)));
        return it == colors.end() ? std::string{} : it->second;
    }

    std::string normalizeCssHexColor(const std::string& value) {
        auto color = lowerCopy(trimCopy(value));
        if (color.size() < 2 || color[0] != '#')
            return {};

        const auto hex = color.substr(1);
        for (char c : hex) {
            if (!std::isxdigit(static_cast<unsigned char>(c)))
                return {};
        }

        if (hex.size() == 3 || hex.size() == 4) {
            std::string expanded = "#";
            expanded.reserve(hex.size() * 2 + 1);
            for (char c : hex) {
                expanded.push_back(c);
                expanded.push_back(c);
            }
            return expanded;
        }

        if (hex.size() == 6 || hex.size() == 8)
            return color;

        return {};
    }

    std::string normalizeCssLengthToken(std::string token) {
        token = trimCopy(token);
        if (token.empty())
            return token;

        auto lower = lowerCopy(token);
        if (lower == "auto" || lower == "fit-content" || lower == "max-content" ||
            lower == "min-content" || lower.find("calc(") != std::string::npos) {
            return token;
        }

        auto stripUnit = [&](const std::string& suffix) -> bool {
            if (lower.size() <= suffix.size())
                return false;
            if (lower.compare(lower.size() - suffix.size(), suffix.size(), suffix) != 0)
                return false;

            const auto numeric = token.substr(0, token.size() - suffix.size());
            bool valid = !numeric.empty();
            for (char c : numeric) {
                if (!std::isdigit(static_cast<unsigned char>(c)) && c != '-' && c != '+') {
                    valid = false;
                    break;
                }
            }
            if (valid)
                token = numeric;
            return valid;
        };

        stripUnit("px") || stripUnit("em") || stripUnit("rem");
        return token;
    }

    std::string normalizeCssBoxValue(const std::string& value) {
        std::vector<std::string> out;
        for (auto token : stdext::split(value, " ")) {
            token = normalizeCssLengthToken(token);
            if (!token.empty())
                out.emplace_back(token);
        }
        return stdext::join(out, " ");
    }

    std::string normalizeCssBorderValue(const std::string& value) {
        std::string width;
        std::string color;

        for (auto token : stdext::split(value, " ")) {
            token = trimCopy(token);
            if (token.empty())
                continue;

            const auto lower = lowerCopy(token);
            if (lower == "solid" || lower == "dashed" || lower == "dotted" ||
                lower == "double" || lower == "groove" || lower == "ridge" ||
                lower == "inset" || lower == "outset")
                continue;

            if (lower == "none" || lower == "hidden")
                return "0 #00000000";

            if (color.empty()) {
                if (!cssNamedColor(token).empty()) {
                    color = cssNamedColor(token);
                    continue;
                }
                if (const auto hex = normalizeCssHexColor(token); !hex.empty()) {
                    color = hex;
                    continue;
                }
                if (html_compat::starts_with(lower, "rgb")) {
                    color = token;
                    continue;
                }
            }

            if (width.empty())
                width = normalizeCssLengthToken(token);
        }

        if (!width.empty() && !color.empty())
            return width + " " + color;
        return normalizeCssBoxValue(value);
    }

    static const std::unordered_map<std::string, std::string> IMG_ATTR_TRANSLATED = {
        {"offset-x", "image-offset-x"},
        {"offset-y", "image-offset-y"},
        {"offset", "image-offset"},
        {"width", "image-width"},
        {"height", "image-height"},
        {"size", "image-size"},
        {"rect", "image-rect"},
        {"clip", "image-clip"},
        {"fixed-ratio", "image-fixed-ratio"},
        {"repeated", "image-repeated"},
        {"smooth", "image-smooth"},
        {"color", "image-color"},
        {"border-top", "image-border-top"},
        {"border-right", "image-border-right"},
        {"border-bottom", "image-border-bottom"},
        {"border-left", "image-border-left"},
        {"border", "image-border"},
        {"auto-resize", "image-auto-resize"},
        {"individual-animation", "image-individual-animation"},
        {"src", "image-source"}
    };

    static const std::unordered_map<std::string, std::string> cssMap = {
        {"active", "active"},
        {"focus", "focus"},
        {"hover", "hover"},
        {"pressed", "pressed"},
        {"checked", "checked"},
        {"disabled", "disabled"},
        {"first-child", "first"},
        {"middle", "middle"},
        {"last-child", "last"},
        {"nth-child(even)", "alternate"},
        {"nth-child(odd)", "alternate"},
        {"on", "on"},
        {"[aria-pressed='true']", "on"},
        {"[data-on]", "on"},
        {"dragging", "dragging"},
        {"hidden", "hidden"},
        {"[hidden]", "hidden"},
        {"mobile", "mobile"},
        {"@media", "mobile"}
    };

    static const std::unordered_set<std::string_view> kProps = {
        "color",
        "cursor",
        "direction",
        "font",
        "font-family",
        "font-scale",
        "font-size",
        "font-style",
        "font-variant",
        "font-weight",
        "letter-spacing",
        "line-height",
        "text-align",
        "text-indent",
        "text-transform",
        "unicode-bidi",
        /*"visibility",*/
        "white-space",
        "word-spacing",
        "writing-mode",
        "hyphens",
        "text-lang"
    };

    static inline bool isInheritable(std::string_view prop) noexcept {
        if (html_compat::starts_with(prop, "*"))
            prop = prop.substr(1);
        return kProps.find(prop) != kProps.end();
    }

    void setChildrenStyles(std::string_view htmlId, const HtmlNodePtr& node, const std::string& style, const std::string& prop, const std::string& value) {
        if (!node)
            return;

        if (node->getType() == NodeType::Element)
            node->getInheritableStyles()[style][prop] = value;

        for (const auto& child : node->getChildren()) {
            auto& styleMap = child->getStyles()[style];
            auto it = styleMap.find(prop);
            if (it == styleMap.end() || !it->second.important) {
                child->getStyles()[style][prop] = { value , std::string{htmlId} };
                setChildrenStyles(htmlId, child, style, prop, value);
            }
        }
    }

    std::string cssToState(const std::string& css) {
        if (auto it = cssMap.find(css); it != cssMap.end())
            return it->second;
        return "";
    }

    void parseAttrPropList(std::string_view attrsStr, std::map<std::string, std::string>& attrsMap) {
        for (auto& data : stdext::split(std::string(attrsStr), ";")) {
            stdext::trim(data);
            auto attr = stdext::split(data, ":");
            if (attr.size() > 1) {
                stdext::trim(attr[0]);
                stdext::trim(attr[1]);
                attrsMap[attr[0]] = attr[1];
            }
        }
    }

    void translateAttribute(std::string_view styleName, std::string_view tagName, std::string& attr, std::string& value) {
        if (attr == "*style") {
            attr = "*mergeStyle";
        } else if (attr == "*if") {
            attr = "*condition-if";
        }

        if (styleName != "CheckBox" && styleName != "ComboBox") {
            if (attr == "*value") {
                attr = "*text";
            } else if (attr == "value") {
                attr = "text";
            }
        }

        if (tagName == "img") {
            auto it = IMG_ATTR_TRANSLATED.find(attr);
            if (it != IMG_ATTR_TRANSLATED.end()) {
                attr = it->second;
            }
        }
    }

    std::string_view translateStyleName(std::string_view styleName, const HtmlNodePtr& el) {
        if (styleName == "select") {
            return "QtComboBox";
        }

        if (styleName == "hr") {
            return "HorizontalSeparator";
        }

        if (styleName == "input") {
            const auto& type = el->getAttr("type");
            if (type == "checkbox" || type == "radio") {
                return "QtCheckBox";
            }
            return "TextEdit";
        }

        if (styleName == "textarea") {
            return "MultilineTextEdit";
        }

        return styleName;
    }

    void createRadioGroup(const HtmlNodePtr& node, std::unordered_map<std::string, UIWidgetPtr>& groups) {
        if (!node)
            return;

        const auto& name = node->getAttr("name");
        if (name.empty())
            return;

        UIWidgetPtr group;
        auto it = groups.find(name);
        if (it == groups.end()) {
            group = groups
                .emplace(name, g_lua.callGlobalField<UIWidgetPtr>("UIRadioGroup", "create"))
                .first->second;
        } else group = it->second;

        group->callLuaField("addWidget", node->getWidget());
    }

    void applyStyleSheet(const HtmlNodePtr& mainNode, std::string_view htmlPath, const css::StyleSheet& sheet, bool checkRuleExist) {
        if (!mainNode)
            return;

        for (const auto& rule : sheet.rules) {
            const auto& selectors = stdext::join(rule.selectors);
            const auto& nodes = mainNode->querySelectorAll(selectors);
            const auto is_all = selectors == "*";

            if (checkRuleExist && nodes.empty()) {
                g_logger.warning(stdext::format("[%s][style] selector(%s) no element was found.", std::string(htmlPath), selectors));
                continue;
            }

            for (const auto& node : nodes) {
                const auto widget = node->getWidget();
                if (widget && !node->isStyleResolved()) {
                    bool hasMeta = false;
                    for (const auto& metas : rule.selectorMeta) {
                        for (const auto& state : metas.pseudos) {
                            for (const auto& decl : rule.decls) {
                                std::string style = "$";
                                if (state.negated)
                                    style += "!";
                                style += state.name;

                                auto& styleMap = node->getStyles()[style];
                                auto it = styleMap.find(decl.property);
                                if (it == styleMap.end() || !it->second.important) {
                                    styleMap[decl.property] = { decl.value , "", decl.important };
                                    if (!is_all && isInheritable(decl.property)) {
                                        setChildrenStyles(widget->getHtmlId(), node, style, decl.property, decl.value);
                                    }
                                }
                            }
                            hasMeta = true;
                        }
                    }

                    if (hasMeta)
                        continue;

                    for (const auto& decl : rule.decls) {
                        auto& styleMap = node->getStyles()["styles"];
                        auto it = styleMap.find(decl.property);
                        if (it == styleMap.end() || !it->second.important) {
                            styleMap[decl.property] = { decl.value , "", decl.important };
                            if (!is_all && isInheritable(decl.property)) {
                                setChildrenStyles(widget->getHtmlId(), node, "styles", decl.property, decl.value);
                            }
                        }
                    }
                }
            }
        }
    };

    std::string convertCssValueToOtml(const std::string& prop, const std::string& value) {
        const auto lowerValue = lowerCopy(trimCopy(value));

        if (isCssColorProperty(prop)) {
            if (const auto named = cssNamedColor(value); !named.empty())
                return named;

            if (const auto hex = normalizeCssHexColor(value); !hex.empty())
                return hex;

            if (html_compat::starts_with(lowerValue, "rgb")) {
                std::string nums = value;
                auto start = nums.find('(');
                auto end   = nums.rfind(')');
                if (start != std::string::npos && end != std::string::npos) {
                    nums = nums.substr(start + 1, end - start - 1);
                }
                auto parts = stdext::split(nums, ",");
                if (parts.size() >= 3) {
                    stdext::trim(parts[0]);
                    stdext::trim(parts[1]);
                    stdext::trim(parts[2]);
                    int r = std::stoi(parts[0]);
                    int g = std::stoi(parts[1]);
                    int b = std::stoi(parts[2]);
                    int a = 255;
                    if (parts.size() >= 4) {
                        stdext::trim(parts[3]);
                        a = static_cast<int>(std::stof(parts[3]) * 255);
                    }
                    char buf[12];
                    std::snprintf(buf, sizeof(buf), "#%02x%02x%02x%02x", r, g, b, a);
                    return std::string(buf);
                }
            }
            return value;
        }

        if (prop == "width" || prop == "height" ||
            prop == "min-width" || prop == "min-height" ||
            prop == "max-width" || prop == "max-height") {
            if (lowerValue.find("calc(") != std::string::npos) {
                return "";
            }
            return normalizeCssLengthToken(value);
        }

        if (html_compat::starts_with(prop, "margin") ||
            html_compat::starts_with(prop, "padding") ||
            html_compat::starts_with(prop, "gap")) {
            if (lowerValue.find("calc(") != std::string::npos)
                return "";
            return normalizeCssBoxValue(value);
        }

        if (prop == "border")
            return normalizeCssBorderValue(value);

        if (html_compat::starts_with(prop, "border-width") ||
            html_compat::starts_with(prop, "border-top-width") ||
            html_compat::starts_with(prop, "border-right-width") ||
            html_compat::starts_with(prop, "border-bottom-width") ||
            html_compat::starts_with(prop, "border-left-width") ||
            prop == "top" || prop == "right" || prop == "bottom" || prop == "left") {
            return normalizeCssLengthToken(value);
        }

        return value;
    }
}

bool checkSpecialCase(const HtmlNodePtr& node, const UIWidgetPtr& parent, const std::string& moduleName) {
    if (!parent || !parent->getHtmlNode())
        return true;

    if (!node->getAttr("*for").empty()) {
        const auto condition = node->getAttr("*for");
        node->removeAttr("*for");
        parent->callLuaField("__childFor", moduleName, condition, node->outerHTML(), parent->getChildren().size());
        return false;
    }

    if (parent->getHtmlNode()->getTag() == "select") {
        parent->callLuaField("addOptionFromHtml", node->textContent(), node->getAttr("value"));
        return false;
    }

    return true;
}

UIWidgetPtr createWidgetFromNode(const HtmlNodePtr& node, const UIWidgetPtr& parent, std::vector<HtmlNodePtr>& textNodes, uint32_t htmlId, const std::string& moduleName, std::vector<UIWidgetPtr>& widgets) {
    if (!checkSpecialCase(node, parent, moduleName))
        return nullptr;

    if (node->getType() == NodeType::Comment || node->getType() == NodeType::Doctype)
        return nullptr;

    const auto& styleName = g_ui.getStyleName(std::string(translateStyleName(node->getTag(), node)));

    auto widget = g_ui.createWidget(styleName.empty() ? "UIHTML" : styleName, parent);
    widgets.emplace_back(widget);

    node->setWidget(widget);

    widget->setHtmlNode(node);
    widget->setHtmlRootId(htmlId);
    widget->ensureUniqueId();

    if (node->getType() == NodeType::Text) {
        textNodes.emplace_back(node);
        widget->setTextAlign(Fw::AlignTopLeft);
        widget->setFocusable(false);
        widget->setPhantom(true);
    }

    if (node->isExpression()) {
        node->setAttr("*text", node->getText());
    }

    if (!node->getChildren().empty()) {
        for (const auto& child : node->getChildren()) {
            createWidgetFromNode(child, widget, textNodes, htmlId, moduleName, widgets);
        }
    }

    return widget;
}

void applyAttributesAndStyles(const UIWidgetPtr& widget, const HtmlNodePtr& node, std::unordered_map<std::string, UIWidgetPtr>& groups, const std::string& moduleName) {
    if (!widget || !node)
        return;

    const auto& styleValue = node->getAttr("style");
    if (!styleValue.empty()) {
        parseAttrPropList(styleValue, node->getAttrStyles());
        for (const auto& [prop, value] : node->getAttrStyles()) {
            if (isInheritable(prop)) {
                setChildrenStyles(widget->getHtmlId(), node, "styles", prop, value);
            }
        }
    }

    // text node depends on style
    if (!node->getText().empty()) {
        widget->setText(node->getText());
    }

    auto styles = OTMLNode::create();

    std::map<std::string, StyleValue> stylesMerge;

    for (const auto [key, stylesMap] : node->getStyles()) {
        if (key != "styles") {
            auto meta = OTMLNode::create();
            meta->setTag(key);
            styles->addChild(meta);

            for (const auto [prop, value] : stylesMap) {
                const auto converted = convertCssValueToOtml(prop, value.value);
                if (converted.empty())
                    continue;
                auto nodeAttr = OTMLNode::create();
                nodeAttr->setTag(prop);
                nodeAttr->setValue(converted);
                meta->addChild(nodeAttr);
            }
        } else for (const auto [prop, value] : stylesMap) {
            stylesMerge[prop] = value;
        }
    }

    for (const auto& [prop, value] : node->getAttrStyles()) {
        stylesMerge[prop] = { value , "", false };
    }

    for (const auto [prop, value] : stylesMerge) {
        const auto converted = convertCssValueToOtml(prop, value.value);
        if (converted.empty())
            continue; // valor CSS não traduzível para OTML — tratado pelo sistema HTML
        auto nodeAttr = OTMLNode::create();
        nodeAttr->setTag(prop);
        nodeAttr->setValue(converted);
        styles->addChild(nodeAttr);
    }

    widget->mergeStyle(styles);

    if (node->getTag() == "input" && node->getAttr("type") == "radio")
        createRadioGroup(node, groups);

    for (const auto [key, v] : node->getAttributesMap()) {
        auto attr = key;
        auto value = v;
        translateAttribute(widget->getStyleName(), node->getTag(), attr, value);

        if (html_compat::starts_with(attr, "on") || html_compat::starts_with(attr, "*for")) {
            // lua call
        } else if (attr == "image-source" && trimCopy(value).empty()) {
            // Ignore empty <img src="">. OTUI texture loading treats it as a broken path.
        } else if (attr == "anchor") {
            // ignore
        } else if (attr == "style" || attr == "id") {
            // executed before
        } else if (attr == "layout") {
            auto otml = OTMLNode::create();
            auto layout = OTMLNode::create();

            std::map<std::string, std::string> styles;
            parseAttrPropList(value, styles);
            for (const auto& [tag, value] : styles) {
                auto nodeAttr = OTMLNode::create();
                nodeAttr->setTag(tag);
                nodeAttr->setValue(value);
                layout->addChild(nodeAttr);
            }

            layout->setTag("layout");
            otml->addChild(layout);
            widget->mergeStyle(otml);
        } else if (attr == "class") {
            for (const auto& className : stdext::split(value, " ")) {
                if (const auto& style = g_ui.getStyle(className))
                    widget->mergeStyle(style);
            }
        } else {
            widget->callLuaField("__applyOrBindHtmlAttribute", attr, value, isInheritable(attr), moduleName, node->toString());
        }
    }

    std::map<std::string, std::string> inheritedStyles;
    for (const auto& [prop, value] : stylesMerge)
        if (isInheritable(prop) && !value.inheritedFromId.empty())
            inheritedStyles[prop] = value.inheritedFromId;

    widget->callLuaField("__onHtmlProcessFinished", inheritedStyles);

    node->setStyleResolved(true);
}

UIWidgetPtr HtmlManager::readNode(DataRoot& root, const UIWidgetPtr& parent, const std::string& moduleName, const std::string& htmlPath, bool checkRuleExist, uint32_t htmlId) {
    auto path = "/modules/" + moduleName + "/";

    std::string script;
    std::string scriptStr;

    std::vector<HtmlNodePtr> textNodes;
    std::vector<UIWidgetPtr> widgets;
    textNodes.reserve(32);
    widgets.reserve(32);

    const bool isDynamic = root.dynamicNode != nullptr;
    const bool insertWithOrder = parent && parent->getInsertChildIndex() > -1;

    UIWidgetPtr widget;
    for (const auto& el : (isDynamic ? root.dynamicNode : root.node)->getChildren()) {
        if (el->getTag() == "style") {
            root.sheets.emplace_back(css::parse(el->textContent()));
        } else if (el->getTag() == "link") {
            if (el->hasAttr("href")) {
                try {
                    root.sheets.emplace_back(css::parse(g_resources.readFileContents(path + el->getAttr("href"))));
                } catch (const std::exception& e) {
                    g_logger.warning(stdext::format("[%s] CSS not found: %s — %s",
                        std::string(moduleName), el->getAttr("href"), std::string(e.what())));
                }
            }
        } else if (el->getTag() == "script") {
            script = el->getText();
            scriptStr = el->toString();
        } else if (el->getTag() == "html") {
            for (const auto& n : el->getChildren()) {
                if (isDynamic) {
                    n->getInheritableStyles() = parent->getHtmlNode()->getInheritableStyles();
                    for (const auto& [styleName, styleMap] : n->getInheritableStyles()) {
                        for (auto& [style, value] : styleMap)
                            n->getStyles()[styleName][style] = { value , parent->getHtmlId() };
                    }
                }
                widget = createWidgetFromNode(n, parent, textNodes, htmlId, moduleName, widgets);
            }
        }
    }

    if (!widget)
        return nullptr;

    if (widget && !script.empty())
        widget->callLuaField("__scriptHtml", moduleName, script, scriptStr);

    const auto mainNode = root.node;

    if (isDynamic) {
        if (insertWithOrder) {
            parent->getHtmlNode()->insert(widget->getHtmlNode(), parent->getInsertChildIndex() - 1);
        } else {
            parent->getHtmlNode()->append(widget->getHtmlNode());
        }
    }

    for (const auto& sheet : GLOBAL_STYLES)
        applyStyleSheet(mainNode, htmlPath, sheet, false);

    for (const auto& sheet : root.sheets)
        applyStyleSheet(mainNode, htmlPath, sheet, checkRuleExist);

    for (const auto& widget : widgets) {
        if (widget->isDestroyed()) {
            // It is destroyed because the parent is inherit-text
            continue;
        }

        const auto node = widget->getHtmlNode();
        if (!node)
            continue;

        applyAttributesAndStyles(widget, node, root.groups, moduleName);
        widget->scheduleHtmlTask(PropApplyAnchorAlignment);
        widget->callLuaField("onCreateByHTML", node->getTag(), std::map<std::string, std::string>(node->getAttributesMap().begin(), node->getAttributesMap().end()), moduleName, node->toString());
    }

    if (isDynamic) {
        widget->refreshHtml(insertWithOrder);
    }

    return widget;
}

uint32_t HtmlManager::load(const std::string& moduleName, const std::string& htmlPath, UIWidgetPtr parent) {
    auto path = "/modules/" + moduleName + "/";
    std::string htmlContent;
    try {
        htmlContent = g_resources.readFileContents(path + htmlPath);
    } catch (const std::exception& e) {
        g_logger.error(stdext::format("[%s] HTML file not found: %s — %s",
            std::string(moduleName), std::string(htmlPath), std::string(e.what())));
        return 0;
    }

    if (htmlContent.empty()) {
        g_logger.warning(stdext::format("[%s] HTML file is empty: %s",
            std::string(moduleName), std::string(htmlPath)));
        return 0;
    }
    auto root = DataRoot{ parseHtml(htmlContent), nullptr, moduleName };

    if (!root.node || root.node->getChildren().empty())
        return 0;

    if (!parent)
        parent = g_ui.getRootWidget();

    static uint32_t ID = 0;
    auto& rootEmplaced = m_nodes.emplace(++ID, std::move(root)).first->second;
    readNode(rootEmplaced, parent, moduleName, htmlPath, false, ID);
    return ID;
}

UIWidgetPtr HtmlManager::createWidgetFromHTML(std::string html, const UIWidgetPtr& parent, uint32_t htmlId) {
    auto it = m_nodes.find(htmlId);
    if (it == m_nodes.end()) {
        return nullptr;
    }

    stdext::trimSpacesAndNewlines(html);
    if (!html_compat::starts_with(html, "<html>"))
        html = "<html>" + html + "</html>";

    auto rootCopy = it->second;
    rootCopy.dynamicNode = parseHtml(html);
    return readNode(rootCopy, parent, it->second.moduleName, "", false, htmlId);
}

void HtmlManager::destroy(uint32_t id) {
    auto it = m_nodes.find(id);
    if (it == m_nodes.end())
        return;

    std::vector<UIWidgetPtr> widgets;

    if (const auto& html = it->second.node->querySelector("html")) {
        widgets.reserve(html->getChildren().size());
        for (const auto& node : html->getChildren()) {
            if (const auto widget = node->getWidget())
                widgets.emplace_back(widget);
        }
    }

    for (const auto& widget : widgets) {
        if (widget && !widget->isDestroyed())
            widget->destroy();
    }

    for (const auto& [name, group] : it->second.groups) {
        group->destroy();
    }

    m_nodes.erase(it);
}

void HtmlManager::addGlobalStyle(const std::string& stylePath) {
    if (!g_resources.fileExists(stylePath)) {
        g_logger.warning(stdext::format("HTML/CSS stylesheet not found, skipping: %s", stylePath));
        return;
    }
    try {
        GLOBAL_STYLES.emplace_back(css::parse(g_resources.readFileContents(stylePath)));
    } catch (const std::exception& e) {
        g_logger.error(stdext::format("Failed to parse HTML/CSS stylesheet '%s': %s", stylePath, e.what()));
    }
}

const DataRoot* HtmlManager::getRoot(uint32_t id) {
    auto it = m_nodes.find(id);
    if (it != m_nodes.end()) {
        return &it->second;
    }

    return nullptr;
}

UIWidgetPtr HtmlManager::getRootWidget(uint32_t id) {
    if (const auto root = getRoot(id)) {
        if (const auto& firstNode = root->node->querySelector("html > :first")) {
            return firstNode->getWidget();
        }
    }

    return nullptr;
}
