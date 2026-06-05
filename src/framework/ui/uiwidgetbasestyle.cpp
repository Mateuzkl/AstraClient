/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
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

#include "uiwidget.h"
#include "uihorizontallayout.h"
#include "uiverticallayout.h"
#include "uigridlayout.h"
#include "uianchorlayout.h"
#include "uiflexbox.h"
#include "uitranslator.h"

#include <framework/graphics/painter.h>
#include <framework/graphics/texture.h>
#include <framework/graphics/texturemanager.h>
#include <framework/ui/uimanager.h>
#include <algorithm>
#include <cctype>
#include <cmath>

namespace {
    std::string cssLower(std::string value)
    {
        stdext::trim(value);
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });
        return value;
    }

    std::string cssNumberPart(std::string value)
    {
        value = cssLower(value);
        if (value == "auto" || value == "fit-content" || value == "max-content" || value == "min-content")
            return "0";

        const std::vector<std::string> suffixes = { "px", "em", "rem", "%" };
        for (const auto& suffix : suffixes) {
            if (value.size() > suffix.size() &&
                value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0) {
                value = value.substr(0, value.size() - suffix.size());
                break;
            }
        }
        return value;
    }

    int cssToInt(const std::string& value)
    {
        const auto numeric = cssNumberPart(value);
        try {
            return static_cast<int>(std::lround(std::stof(numeric)));
        } catch (const std::exception&) {
            return 0;
        }
    }

    float cssToFloat(const std::string& value, float fallback = 0.f)
    {
        try {
            return std::stof(cssNumberPart(value));
        } catch (const std::exception&) {
            return fallback;
        }
    }

    FlexDirection parseCssFlexDirection(const std::string& value)
    {
        const auto v = cssLower(value);
        if (v == "row-reverse") return FlexDirection::RowReverse;
        if (v == "column") return FlexDirection::Column;
        if (v == "column-reverse") return FlexDirection::ColumnReverse;
        return FlexDirection::Row;
    }

    FlexWrap parseCssFlexWrap(const std::string& value)
    {
        const auto v = cssLower(value);
        if (v == "wrap") return FlexWrap::Wrap;
        if (v == "wrap-reverse") return FlexWrap::WrapReverse;
        return FlexWrap::NoWrap;
    }

    JustifyContent parseCssJustifyContent(const std::string& value)
    {
        const auto v = cssLower(value);
        if (v == "flex-end" || v == "end" || v == "right") return JustifyContent::FlexEnd;
        if (v == "center") return JustifyContent::Center;
        if (v == "space-between") return JustifyContent::SpaceBetween;
        if (v == "space-around") return JustifyContent::SpaceAround;
        if (v == "space-evenly") return JustifyContent::SpaceEvenly;
        return JustifyContent::FlexStart;
    }

    AlignItems parseCssAlignItems(const std::string& value)
    {
        const auto v = cssLower(value);
        if (v == "flex-start" || v == "start") return AlignItems::FlexStart;
        if (v == "flex-end" || v == "end") return AlignItems::FlexEnd;
        if (v == "center") return AlignItems::Center;
        if (v == "baseline") return AlignItems::Baseline;
        return AlignItems::Stretch;
    }

    AlignContent parseCssAlignContent(const std::string& value)
    {
        const auto v = cssLower(value);
        if (v == "flex-start" || v == "start") return AlignContent::FlexStart;
        if (v == "flex-end" || v == "end") return AlignContent::FlexEnd;
        if (v == "center") return AlignContent::Center;
        if (v == "space-between") return AlignContent::SpaceBetween;
        if (v == "space-around") return AlignContent::SpaceAround;
        if (v == "space-evenly") return AlignContent::SpaceEvenly;
        return AlignContent::Stretch;
    }

    AlignSelf parseCssAlignSelf(const std::string& value)
    {
        const auto v = cssLower(value);
        if (v == "stretch") return AlignSelf::Stretch;
        if (v == "flex-start" || v == "start") return AlignSelf::FlexStart;
        if (v == "flex-end" || v == "end") return AlignSelf::FlexEnd;
        if (v == "center") return AlignSelf::Center;
        if (v == "baseline") return AlignSelf::Baseline;
        return AlignSelf::Auto;
    }

    FlexBasis parseCssFlexBasis(const std::string& value)
    {
        const auto v = cssLower(value);
        FlexBasis basis;
        if (v == "auto") return basis;
        if (v == "content") {
            basis.type = FlexBasis::Type::Content;
            return basis;
        }
        if (!v.empty() && v.back() == '%') {
            basis.type = FlexBasis::Type::Percent;
            basis.value = cssToFloat(v);
            return basis;
        }
        basis.type = FlexBasis::Type::Px;
        basis.value = cssToFloat(v);
        return basis;
    }
}

void UIWidget::initBaseStyle()
{
    m_backgroundColor = Color::alpha;
    m_borderColor.set(Color::black);
    m_iconColor = Color::white;
    m_color = Color::white;
    m_opacity = 1.0f;
    m_rotation = 0.0f;
    m_iconAlign = Fw::AlignNone;
    m_sizeOffset = Size(0, 0);

    // generate an unique id, this is need because anchored layouts find widgets by id
    static unsigned long id = 1;
    m_id = std::string("widget") + std::to_string(id++);
}

void UIWidget::parseBaseStyle(const OTMLNodePtr& styleNode)
{
    // parse lua variables and callbacks first
    for(const OTMLNodePtr& node : styleNode->children()) {
        // lua functions
        if(stdext::starts_with(node->tag(), "@")) {
            // load once
            if(m_firstOnStyle) {
                std::string funcName = node->tag().substr(1);
                std::string funcOrigin = std::string("@") + node->source() + ": [" + node->tag() + "]";
                g_lua.loadFunction(node->value(), funcOrigin);
                luaSetField(funcName);
            }
        // lua fields value
        } else if(stdext::starts_with(node->tag(), "&")) {
            std::string fieldName = node->tag().substr(1);
            std::string fieldOrigin = std::string("@") + node->source() + ": [" + node->tag() + "]";

            g_lua.evaluateExpression(node->value(), fieldOrigin);
            luaSetField(fieldName);
        }
    }
    // load styles used by all widgets
    for(const OTMLNodePtr& node : styleNode->children()) {
        if(node->tag() == "color")
            setColor(node->value<Color>());
        else if(node->tag() == "x")
            setX(node->value<int>());
        else if(node->tag() == "y")
            setY(node->value<int>());
        else if(node->tag() == "pos")
            setPosition(node->value<Point>());
        else if (node->tag() == "width") {
            if (isOnHtml())
                applyDimension(true, node->value());
            else
                setWidth(node->value<int>(), node->value().find('%') != std::string::npos);
        } else if (node->tag() == "height") {
            if (isOnHtml())
                applyDimension(false, node->value());
            else
                setHeight(node->value<int>(), node->value().find('%') != std::string::npos);
        } else if (node->tag() == "min-width") {
            m_minSize.setWidth(cssToInt(node->value()));
            scheduleHtmlTask(PropUpdateSize);
        } else if (node->tag() == "max-width") {
            m_maxSize.setWidth(cssToInt(node->value()));
            scheduleHtmlTask(PropUpdateSize);
        } else if (node->tag() == "min-height") {
            m_minSize.setHeight(cssToInt(node->value()));
            scheduleHtmlTask(PropUpdateSize);
        } else if (node->tag() == "max-height") {
            m_maxSize.setHeight(cssToInt(node->value()));
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "rect")
            setRect(node->value<Rect>());
        else if(node->tag() == "background")
            setBackgroundColor(node->value<Color>());
        else if(node->tag() == "background-color")
            setBackgroundColor(node->value<Color>());
        else if(node->tag() == "background-offset-x")
            setBackgroundOffsetX(node->value<int>());
        else if(node->tag() == "background-offset-y")
            setBackgroundOffsetY(node->value<int>());
        else if(node->tag() == "background-offset")
            setBackgroundOffset(node->value<Point>());
        else if(node->tag() == "background-width")
            setBackgroundWidth(node->value<int>());
        else if(node->tag() == "background-height")
            setBackgroundHeight(node->value<int>());
        else if(node->tag() == "background-size")
            setBackgroundSize(node->value<Size>());
        else if(node->tag() == "background-rect")
            setBackgroundRect(node->value<Rect>());
        else if(node->tag() == "icon")
            setIcon(stdext::resolve_path(node->value(), node->source()));
        else if(node->tag() == "icon-source")
            setIcon(stdext::resolve_path(node->value(), node->source()));
        else if(node->tag() == "icon-color")
            setIconColor(node->value<Color>());
        else if(node->tag() == "icon-offset-x")
            setIconOffsetX(node->value<int>());
        else if(node->tag() == "icon-offset-y")
            setIconOffsetY(node->value<int>());
        else if(node->tag() == "icon-offset")
            setIconOffset(node->value<Point>());
        else if(node->tag() == "icon-width")
            setIconWidth(node->value<int>());
        else if(node->tag() == "icon-height")
            setIconHeight(node->value<int>());
        else if(node->tag() == "icon-size")
            setIconSize(node->value<Size>());
        else if(node->tag() == "icon-rect")
            setIconRect(node->value<Rect>());
        else if(node->tag() == "icon-clip")
            setIconClip(node->value<Rect>());
        else if(node->tag() == "icon-align")
            setIconAlign(Fw::translateAlignment(node->value()));
        else if (node->tag() == "icon-smooth")
            setIconSmooth(node->value<bool>());
        else if(node->tag() == "opacity")
            setOpacity(node->value<float>());
        else if (node->tag() == "rotation")
            setRotation(node->value<float>());
        else if(node->tag() == "enabled")
            setEnabled(node->value<bool>());
        else if(node->tag() == "visible")
            setVisible(node->value<bool>());
        else if(node->tag() == "checked")
            setChecked(node->value<bool>());
        else if(node->tag() == "draggable")
            setDraggable(node->value<bool>());
        else if(node->tag() == "on")
            setOn(node->value<bool>());
        else if(node->tag() == "focusable")
            setFocusable(node->value<bool>());
        else if (node->tag() == "auto-draw")
            setAutoDraw(node->value<bool>());
        else if(node->tag() == "auto-focus")
            setAutoFocusPolicy(Fw::translateAutoFocusPolicy(node->value()));
        else if(node->tag() == "phantom")
            setPhantom(node->value<bool>());
        else if (node->tag() == "size") {
            // I know, setSize(node->value<Size>()) is better but this is a negligible and necessary change
            auto split = stdext::split(node->value(true), " ");
            if (split.size() == 2) {
                int width, height;
                if (stdext::cast(split[0], width)) {
                    setWidth(width, split[0].find('%') != std::string::npos);
                }

                if (stdext::cast(split[1], height)) {
                    setHeight(height, split[1].find('%') != std::string::npos);
                }
            }
        }
        else if(node->tag() == "width-offset")
            setWidthOffset(node->value<int>());
        else if(node->tag() == "height-offset")
            setHeightOffset(node->value<int>());
        else if(node->tag() == "size-offset")
            setSizeOffset(node->value<Size>());
        else if(node->tag() == "fixed-size")
            setFixedSize(node->value<bool>());
        else if(node->tag() == "clipping")
            setClipping(node->value<bool>());
        else if(node->tag() == "border") {
            auto split = stdext::split(node->value(true), " ");
            if(split.size() == 2) {
                setBorderWidth(stdext::safe_cast<int>(g_ui.getOTUIVarSafe(split[0])));
                setBorderColor(stdext::safe_cast<Color>(g_ui.getOTUIVarSafe(split[1])));
            } else
                throw OTMLException(node, "border param must have its width followed by its color");
        }
        else if(node->tag() == "border-width")
            setBorderWidth(cssToInt(node->value()));
        else if(node->tag() == "border-width-top")
            setBorderWidthTop(cssToInt(node->value()));
        else if(node->tag() == "border-width-right")
            setBorderWidthRight(cssToInt(node->value()));
        else if(node->tag() == "border-width-bottom")
            setBorderWidthBottom(cssToInt(node->value()));
        else if(node->tag() == "border-width-left")
            setBorderWidthLeft(cssToInt(node->value()));
        else if(node->tag() == "border-color")
            setBorderColor(node->value<Color>());
        else if(node->tag() == "border-color-top")
            setBorderColorTop(node->value<Color>());
        else if(node->tag() == "border-color-right")
            setBorderColorRight(node->value<Color>());
        else if(node->tag() == "border-color-bottom")
            setBorderColorBottom(node->value<Color>());
        else if(node->tag() == "border-color-left")
            setBorderColorLeft(node->value<Color>());
        else if(node->tag() == "display") {
            auto v = cssLower(node->value());
            DisplayType display = DisplayType::Initial;
            if(v == "none") display = DisplayType::None;
            else if(v == "block") display = DisplayType::Block;
            else if(v == "inline") display = DisplayType::Inline;
            else if(v == "inline-block") display = DisplayType::InlineBlock;
            else if(v == "flex") display = DisplayType::Flex;
            else if(v == "inline-flex") display = DisplayType::InlineFlex;
            else if(v == "grid") display = DisplayType::Grid;
            else if(v == "inline-grid") display = DisplayType::InlineGrid;
            else if(v == "table") display = DisplayType::Table;
            else if(v == "table-row-group") display = DisplayType::TableRowGroup;
            else if(v == "table-header-group") display = DisplayType::TableHeaderGroup;
            else if(v == "table-footer-group") display = DisplayType::TableFooterGroup;
            else if(v == "table-row") display = DisplayType::TableRow;
            else if(v == "table-cell") display = DisplayType::TableCell;
            else if(v == "table-column-group") display = DisplayType::TableColumnGroup;
            else if(v == "table-column") display = DisplayType::TableColumn;
            else if(v == "table-caption") display = DisplayType::TableCaption;
            else if(v == "list-item") display = DisplayType::ListItem;
            else if(v == "run-in") display = DisplayType::RunIn;
            else if(v == "contents") display = DisplayType::Contents;
            else if(v == "inherit") display = DisplayType::Inherit;
            setDisplay(display);
        }
        else if(node->tag() == "flex-direction") {
            m_flexContainer.direction = parseCssFlexDirection(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "flex-wrap") {
            m_flexContainer.wrap = parseCssFlexWrap(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "flex-flow") {
            for(auto part : stdext::split(node->value(), " ")) {
                part = cssLower(part);
                if(part == "row" || part == "row-reverse" || part == "column" || part == "column-reverse")
                    m_flexContainer.direction = parseCssFlexDirection(part);
                else if(part == "nowrap" || part == "wrap" || part == "wrap-reverse")
                    m_flexContainer.wrap = parseCssFlexWrap(part);
            }
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "justify-content") {
            m_flexContainer.justify = parseCssJustifyContent(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "align-items") {
            m_flexContainer.alignItems = parseCssAlignItems(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "align-content") {
            m_flexContainer.alignContent = parseCssAlignContent(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "gap") {
            const int gap = cssToInt(node->value());
            m_flexContainer.rowGap = gap;
            m_flexContainer.columnGap = gap;
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "row-gap") {
            m_flexContainer.rowGap = cssToInt(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "column-gap") {
            m_flexContainer.columnGap = cssToInt(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "order") {
            m_flexItem.order = cssToInt(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "flex-grow") {
            m_flexItem.flexGrow = cssToFloat(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "flex-shrink") {
            m_flexItem.flexShrink = cssToFloat(node->value(), 1.f);
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "flex-basis") {
            m_flexItem.basis = parseCssFlexBasis(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "align-self") {
            m_flexItem.alignSelf = parseCssAlignSelf(node->value());
            scheduleHtmlTask(PropUpdateSize);
        }
        else if(node->tag() == "overflow") {
            auto v = cssLower(node->value());
            OverflowType type = OverflowType::Visible;
            if(v == "hidden") type = OverflowType::Hidden;
            else if(v == "scroll") type = OverflowType::Scroll;
            else if(v == "auto") type = OverflowType::Auto;
            else if(v == "clip") type = OverflowType::Clip;
            setOverflow(type);
            setClipping(type == OverflowType::Hidden || type == OverflowType::Scroll || type == OverflowType::Clip);
        }
        else if(node->tag() == "position") {
            auto v = cssLower(node->value());
            PositionType type = PositionType::Static;
            if(v == "absolute") type = PositionType::Absolute;
            else if(v == "relative") type = PositionType::Relative;
            setPositionType(type);
        }
        else if(node->tag() == "top" || node->tag() == "right" || node->tag() == "bottom" || node->tag() == "left")
            setPositions(node->tag(), node->value());
        else if(node->tag() == "float") {
            auto v = cssLower(node->value());
            FloatType type = FloatType::None;
            if(v == "left") type = FloatType::Left;
            else if(v == "right") type = FloatType::Right;
            else if(v == "inline-start") type = FloatType::InlineStart;
            else if(v == "inline-end") type = FloatType::InlineEnd;
            setFloat(type);
        }
        else if(node->tag() == "clear") {
            auto v = cssLower(node->value());
            ClearType type = ClearType::None;
            if(v == "left") type = ClearType::Left;
            else if(v == "right") type = ClearType::Right;
            else if(v == "both") type = ClearType::Both;
            else if(v == "inline-start") type = ClearType::InlineStart;
            else if(v == "inline-end") type = ClearType::InlineEnd;
            setClear(type);
        }
        else if(node->tag() == "justify-items") {
            auto v = cssLower(node->value());
            JustifyItemsType type = JustifyItemsType::Normal;
            if(v == "center") type = JustifyItemsType::Center;
            else if(v == "left" || v == "flex-start" || v == "start" || v == "inline-start") type = JustifyItemsType::Left;
            else if(v == "right" || v == "flex-end" || v == "end" || v == "inline-end") type = JustifyItemsType::Right;
            setJustifyItems(type);
        }
        else if(node->tag() == "line-height")
            setLineHeight(node->value());
        else if(node->tag() == "margin-top")
            setMarginTop(cssToInt(node->value()));
        else if(node->tag() == "margin-right")
            setMarginRight(cssToInt(node->value()));
        else if(node->tag() == "margin-bottom")
            setMarginBottom(cssToInt(node->value()));
        else if(node->tag() == "margin-left")
            setMarginLeft(cssToInt(node->value()));
        else if(node->tag() == "margin") {
            std::string marginDesc = node->value(true);
            std::vector<std::string> split = stdext::split(marginDesc, " ");
            if(split.size() == 4) {
                setMarginTop(cssToInt(g_ui.getOTUIVarSafe(split[0])));
                setMarginRight(cssToInt(g_ui.getOTUIVarSafe(split[1])));
                setMarginBottom(cssToInt(g_ui.getOTUIVarSafe(split[2])));
                setMarginLeft(cssToInt(g_ui.getOTUIVarSafe(split[3])));
            } else if(split.size() == 3) {
                int marginTop = cssToInt(g_ui.getOTUIVarSafe(split[0]));
                int marginHorizontal = cssToInt(g_ui.getOTUIVarSafe(split[1]));
                int marginBottom = cssToInt(g_ui.getOTUIVarSafe(split[2]));
                setMarginTop(marginTop);
                setMarginRight(marginHorizontal);
                setMarginBottom(marginBottom);
                setMarginLeft(marginHorizontal);
            } else if(split.size() == 2) {
                int marginVertical = cssToInt(g_ui.getOTUIVarSafe(split[0]));
                int marginHorizontal = cssToInt(g_ui.getOTUIVarSafe(split[1]));
                setMarginTop(marginVertical);
                setMarginRight(marginHorizontal);
                setMarginBottom(marginVertical);
                setMarginLeft(marginHorizontal);
            } else if(split.size() == 1) {
                int margin = cssToInt(g_ui.getOTUIVarSafe(split[0]));
                setMarginTop(margin);
                setMarginRight(margin);
                setMarginBottom(margin);
                setMarginLeft(margin);
            }
        }
        else if(node->tag() == "padding-top")
            setPaddingTop(cssToInt(node->value()));
        else if(node->tag() == "padding-right")
            setPaddingRight(cssToInt(node->value()));
        else if(node->tag() == "padding-bottom")
            setPaddingBottom(cssToInt(node->value()));
        else if(node->tag() == "padding-left")
            setPaddingLeft(cssToInt(node->value()));
        else if(node->tag() == "padding") {
            std::string paddingDesc = node->value(true);
            std::vector<std::string> split = stdext::split(paddingDesc, " ");
            if(split.size() == 4) {
                setPaddingTop(cssToInt(g_ui.getOTUIVarSafe(split[0])));
                setPaddingRight(cssToInt(g_ui.getOTUIVarSafe(split[1])));
                setPaddingBottom(cssToInt(g_ui.getOTUIVarSafe(split[2])));
                setPaddingLeft(cssToInt(g_ui.getOTUIVarSafe(split[3])));
            } else if(split.size() == 3) {
                int paddingTop = cssToInt(g_ui.getOTUIVarSafe(split[0]));
                int paddingHorizontal = cssToInt(g_ui.getOTUIVarSafe(split[1]));
                int paddingBottom = cssToInt(g_ui.getOTUIVarSafe(split[2]));
                setPaddingTop(paddingTop);
                setPaddingRight(paddingHorizontal);
                setPaddingBottom(paddingBottom);
                setPaddingLeft(paddingHorizontal);
            } else if(split.size() == 2) {
                int paddingVertical = cssToInt(g_ui.getOTUIVarSafe(split[0]));
                int paddingHorizontal = cssToInt(g_ui.getOTUIVarSafe(split[1]));
                setPaddingTop(paddingVertical);
                setPaddingRight(paddingHorizontal);
                setPaddingBottom(paddingVertical);
                setPaddingLeft(paddingHorizontal);
            } else if(split.size() == 1) {
                int padding = cssToInt(g_ui.getOTUIVarSafe(split[0]));
                setPaddingTop(padding);
                setPaddingRight(padding);
                setPaddingBottom(padding);
                setPaddingLeft(padding);
            }
        }
        // layouts
        else if(node->tag() == "layout") {
            std::string layoutType;
            if(node->hasValue())
                layoutType = node->value();
            else
                layoutType = node->valueAt<std::string>("type", "");

            if(!layoutType.empty()) {
                UILayoutPtr layout;
                if(layoutType == "horizontalBox")
                    layout = std::make_shared<UIHorizontalLayout>(static_self_cast<UIWidget>());
                else if(layoutType == "verticalBox")
                    layout = std::make_shared<UIVerticalLayout>(static_self_cast<UIWidget>());
                else if(layoutType == "grid")
                    layout = std::make_shared<UIGridLayout>(static_self_cast<UIWidget>());
                else if(layoutType == "anchor")
                    layout = std::make_shared<UIAnchorLayout>(static_self_cast<UIWidget>());
                else if(layoutType == "flex")
                    layout = std::make_shared<UIFlexBox>(static_self_cast<UIWidget>());
                else
                    throw OTMLException(node, "cannot determine layout type");
                setLayout(layout);
            }

            if(node->hasChildren())
                m_layout->applyStyle(node);
        }
        // anchors
        else if(stdext::starts_with(node->tag(), "anchors.")) {
            UIWidgetPtr parent = getParent();
            if(!parent) {
                if(m_firstOnStyle)
                    throw OTMLException(node, "cannot create anchor, there is no parent widget!");
                else
                    continue;
            }

            UILayoutPtr layout = parent->getLayout();
            UIAnchorLayoutPtr anchorLayout;
            if(layout->isUIAnchorLayout())
                anchorLayout = layout->static_self_cast<UIAnchorLayout>();

            if(!anchorLayout)
                throw OTMLException(node, "cannot create anchor, the parent widget doesn't use anchor layout!");

            std::string what = node->tag().substr(8);
            if(what == "fill") {
                fill(node->value());
            } else if(what == "centerIn") {
                centerIn(node->value());
            } else {
                Fw::AnchorEdge anchoredEdge = Fw::translateAnchorEdge(what);

                if(node->value() == "none") {
                    removeAnchor(anchoredEdge);
                } else {
                    std::vector<std::string> split = stdext::split(node->value(true), ".");
                    if(split.size() != 2)
                        throw OTMLException(node, "invalid anchor description");

                    std::string hookedWidgetId = g_ui.getOTUIVarSafe(split[0]);
                    Fw::AnchorEdge hookedEdge = Fw::translateAnchorEdge(g_ui.getOTUIVarSafe(split[1]));

                    if(anchoredEdge == Fw::AnchorNone)
                        throw OTMLException(node, "invalid anchor edge");

                    if(hookedEdge == Fw::AnchorNone)
                        throw OTMLException(node, "invalid anchor target edge");

                    addAnchor(anchoredEdge, hookedWidgetId, hookedEdge);
                }
            }
        }
        else if (node->tag() == "cursor")
            setCursor(node->value());
        else if (node->tag() == "change-cursor-image")
            setChangeCursorImage(node->value<bool>());
        else if (node->tag() == "events") {
            auto split = stdext::split(node->value(true), " ");
            for (const auto& event : split) {
                auto it = eventMap.find(event);
                if (it != eventMap.end()) {
                    setEventListener(it->second);
                }
            }
        }
        else if (node->tag() == "load-otui") {
            g_ui.loadUI(stdext::resolve_path(node->value(), node->source()), static_self_cast<UIWidget>());
        }
    }
}

void UIWidget::drawBackground(const Rect& screenCoords)
{
    if(m_backgroundColor.aF() > 0.0f) {
        Rect drawRect = screenCoords;
        drawRect.translate(m_backgroundRect.topLeft());
        if(m_backgroundRect.isValid())
            drawRect.resize(m_backgroundRect.size());
        g_drawQueue->addFilledRect(drawRect, m_backgroundColor);
    }
}

void UIWidget::drawBorder(const Rect& screenCoords)
{
    // top
    if(m_borderWidth.top > 0) {
        Rect borderRect(screenCoords.topLeft(), screenCoords.width(), m_borderWidth.top);
        g_drawQueue->addFilledRect(borderRect, m_borderColor.top);
    }

    // right
    if(m_borderWidth.right > 0) {
        Rect borderRect(screenCoords.topRight() - Point(m_borderWidth.right - 1, 0), m_borderWidth.right, screenCoords.height());
        g_drawQueue->addFilledRect(borderRect, m_borderColor.right);
    }

    // bottom
    if(m_borderWidth.bottom > 0) {
        Rect borderRect(screenCoords.bottomLeft() - Point(0, m_borderWidth.bottom - 1), screenCoords.width(), m_borderWidth.bottom);
        g_drawQueue->addFilledRect(borderRect, m_borderColor.bottom);
    }

    // left
    if(m_borderWidth.left > 0) {
        Rect borderRect(screenCoords.topLeft(), m_borderWidth.left, screenCoords.height());
        g_drawQueue->addFilledRect(borderRect, m_borderColor.left);
    }
}

void UIWidget::drawIcon(const Rect& screenCoords)
{
    if(m_icon) {
        m_icon->setSmooth(m_iconSmooth);
        Rect drawRect;
        if(m_iconRect.isValid()) {
            drawRect = screenCoords;
            drawRect.translate(m_iconRect.topLeft());
            drawRect.resize(m_iconRect.size());
        } else {
            drawRect.resize(m_iconClipRect.size());

            if(m_iconAlign == Fw::AlignNone)
                drawRect.moveCenter(screenCoords.center());
            else
                drawRect.alignIn(screenCoords, m_iconAlign);
        }
        drawRect.translate(m_iconOffset);
        g_drawQueue->addTexturedRect(drawRect, m_icon, m_iconClipRect, m_iconColor);
    }
}

void UIWidget::setIcon(const std::string& iconFile)
{
    if (iconFile.empty()) {
        m_icon = nullptr;
        m_iconPath = "";
    }
    else {
        m_icon = g_textures.getTexture(iconFile);
        m_iconPath = iconFile;
    }
    if(m_icon && !m_iconClipRect.isValid())
        m_iconClipRect = Rect(0, 0, m_icon->getSize());
}
