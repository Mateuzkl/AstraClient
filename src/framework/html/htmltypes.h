/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 * HTML/CSS layout types — adapted for OrigenOTClient V8
 */

#pragma once

#include <cstdint>

// DisplayType — mapeia a propriedade CSS "display"
enum class DisplayType : uint8_t {
    None,
    Block,
    Inline,
    InlineBlock,
    Flex,
    InlineFlex,
    Grid,
    InlineGrid,
    Table,
    TableRowGroup,
    TableHeaderGroup,
    TableFooterGroup,
    TableRow,
    TableCell,
    TableColumnGroup,
    TableColumn,
    TableCaption,
    ListItem,
    RunIn,
    Contents,
    Initial,
    Inherit
};

// Unit — unidade das dimensões CSS
enum class Unit : uint8_t { Auto, FitContent, Px, Em, Percent, Invalid };

// FloatType — propriedade CSS "float"
enum class FloatType : uint8_t {
    None,
    Left,
    Right,
    InlineStart,
    InlineEnd
};

// ClearType — propriedade CSS "clear"
enum class ClearType : uint8_t {
    None,
    Left,
    Right,
    Both,
    InlineStart,
    InlineEnd
};

// JustifyItemsType
enum class JustifyItemsType : uint8_t {
    Normal,
    Center,
    Left,
    Right
};

// FlexDirection
enum class FlexDirection : uint8_t {
    Row,
    RowReverse,
    Column,
    ColumnReverse
};

// FlexWrap
enum class FlexWrap : uint8_t {
    NoWrap,
    Wrap,
    WrapReverse
};

// JustifyContent
enum class JustifyContent : uint8_t {
    FlexStart,
    FlexEnd,
    Center,
    SpaceBetween,
    SpaceAround,
    SpaceEvenly
};

// AlignItems
enum class AlignItems : uint8_t {
    Stretch,
    FlexStart,
    FlexEnd,
    Center,
    Baseline
};

// AlignContent
enum class AlignContent : uint8_t {
    Stretch,
    FlexStart,
    FlexEnd,
    Center,
    SpaceBetween,
    SpaceAround,
    SpaceEvenly
};

// AlignSelf
enum class AlignSelf : uint8_t {
    Auto,
    Stretch,
    FlexStart,
    FlexEnd,
    Center,
    Baseline
};

// OverflowType
enum class OverflowType : uint8_t {
    Visible,
    Hidden,
    Scroll,
    Auto,
    Clip
};

// PositionType — propriedade CSS "position"
enum class PositionType : uint8_t {
    Static,
    Relative,
    Absolute
};

// SizeUnit — struct para width/height com unit e value (compatível com Mehah)
struct SizeUnit {
    bool needsUpdate(Unit _unit) const {
        return pendingUpdate && unit == _unit;
    }

    bool needsUpdate(Unit _unit, uint32_t _version) const {
        return pendingUpdate && unit == _unit && version != _version;
    }

    void applyUpdate(int16_t v, uint32_t newVersion) {
        valueCalculed = v;
        version = newVersion;
        pendingUpdate = false;
    }

    SizeUnit() = default;
    SizeUnit(Unit u) : unit(u) {}
    SizeUnit(int16_t v) : unit(Unit::Px), value(v) {}
    SizeUnit(Unit u, int16_t v, int16_t valueCalculed, uint32_t needUpdate)
        : unit(u), value(v), valueCalculed(valueCalculed), pendingUpdate(needUpdate) {}

    Unit unit = Unit::Px;
    int16_t value = 0;
    int16_t valueCalculed = -1;
    uint32_t version = 0;
    bool pendingUpdate = false;
};

// FlexBasis
struct FlexBasis {
    enum class Type : uint8_t { Auto, Px, Percent, Content };

    Type type{ Type::Auto };
    float value{ 0.f };
};

// FlexContainerStyle
struct FlexContainerStyle {
    FlexDirection direction{ FlexDirection::Row };
    FlexWrap wrap{ FlexWrap::NoWrap };
    JustifyContent justify{ JustifyContent::FlexStart };
    AlignItems alignItems{ AlignItems::Stretch };
    AlignContent alignContent{ AlignContent::Stretch };
    int rowGap{ 0 };
    int columnGap{ 0 };
};

// FlexItemStyle
struct FlexItemStyle {
    int order{ 0 };
    float flexGrow{ 0.f };
    float flexShrink{ 1.f };
    FlexBasis basis{};
    AlignSelf alignSelf{ AlignSelf::Auto };
};
