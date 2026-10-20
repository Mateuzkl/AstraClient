// Counted TFS item metadata payloads, without speculative frame-tail fields.
#ifndef ASTRA_CUSTOMITEMPROTOCOL_H
#define ASTRA_CUSTOMITEMPROTOCOL_H

#include <cstdint>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

namespace CustomItemProtocol {
struct Details {
    uint16_t itemId;
    uint32_t defaultValue;
    uint32_t defaultBuyPrice;
    uint32_t averageMarketValue;
    std::vector<std::pair<std::string, std::string>> descriptions;
    std::vector<std::tuple<std::string, std::string, uint32_t, uint32_t, std::string>> npcSaleData;
};

template <typename Message>
Details readDetails(Message& msg)
{
    Details data;
    data.itemId = msg.getU16();
    data.defaultValue = msg.getU32();
    data.defaultBuyPrice = msg.getU32();
    data.averageMarketValue = msg.getU32();
    const auto descriptionCount = msg.getU8();
    data.descriptions.reserve(descriptionCount);
    for (unsigned i = 0; i < descriptionCount; ++i) {
        // Function argument evaluation order must not reverse the two strings.
        auto detail = msg.getString();
        auto description = msg.getString();
        data.descriptions.emplace_back(std::move(detail), std::move(description));
    }
    const auto npcCount = msg.getU16();
    data.npcSaleData.reserve(npcCount);
    for (unsigned i = 0; i < npcCount; ++i) {
        auto name = msg.getString();
        auto location = msg.getString();
        const auto buy = msg.getU32();
        const auto sale = msg.getU32();
        auto currency = msg.getString();
        data.npcSaleData.emplace_back(std::move(name), std::move(location), buy, sale, std::move(currency));
    }
    return data;
}
} // namespace CustomItemProtocol
#endif
