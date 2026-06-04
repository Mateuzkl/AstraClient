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

#include "net.h"
#include <asio/ip/address_v4.hpp>
#include <bit>

namespace stdext {

static uint32_t network_to_host_32(uint32_t val) {
    if constexpr (std::endian::native == std::endian::little) {
        return ((val & 0xFF000000u) >> 24) |
               ((val & 0x00FF0000u) >> 8)  |
               ((val & 0x0000FF00u) << 8)  |
               ((val & 0x000000FFu) << 24);
    }
    return val;
}

static uint32_t host_to_network_32(uint32_t val) {
    return network_to_host_32(val);
}

std::string ip_to_string(uint32 ip)
{
    ip = network_to_host_32(ip);
    asio::ip::address_v4 address_v4 = asio::ip::address_v4(ip);
    return address_v4.to_string();
}

uint32 string_to_ip(const std::string& string)
{
    asio::ip::address_v4 address_v4 = asio::ip::make_address_v4(string);
    return host_to_network_32(address_v4.to_uint());
}

std::vector<uint32> listSubnetAddresses(uint32 address, uint8 mask)
{
    std::vector<uint32> list;
    if(mask < 32) {
        uint32 bitmask = (0xFFFFFFFF >> mask);
        for(uint32 i = 0; i <= bitmask; i++) {
            uint32 ip = host_to_network_32((network_to_host_32(address) & (~bitmask)) | i);
            if((ip >> 24) != 0 && (ip >> 24) != 0xFF)
                list.push_back(ip);
        }
    }
    else
        list.push_back(address);

    return list;
}

}
