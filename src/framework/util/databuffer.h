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

#ifndef DATABUFFER_H
#define DATABUFFER_H

#include <algorithm>
#include <vector>

template<class T>
class DataBuffer
{
public:
    DataBuffer(uint res = 64) :
        m_buffer()
    {
        m_buffer.reserve(res);
    }

    DataBuffer(const DataBuffer<T>& d)
    {
        m_buffer = d.m_buffer;
        m_buffer.reserve(std::max<uint>(64, d.size() * 2));
    }
    DataBuffer& operator=(const DataBuffer<T>& d) = delete;

    inline void reset() { m_buffer.clear(); }
    inline void clear() {
        std::vector<T>().swap(m_buffer);
    }

    inline bool empty() const { return m_buffer.empty(); }
    inline uint size() const { return static_cast<uint>(m_buffer.size()); }
    inline T *data() const { return const_cast<T*>(m_buffer.data()); }

    inline const T& at(uint i) const { return m_buffer[i]; }
    inline const T& last() const { return m_buffer[m_buffer.size()-1]; }
    inline const T& first() const { return m_buffer[0]; }
    inline const T& operator[](uint i) const { return m_buffer[i]; }
    inline T& operator[](uint i) { return m_buffer[i]; }

    inline void reserve(uint n) {
        if(n > m_buffer.capacity())
            m_buffer.reserve(n);
    }

    inline void resize(uint n, T def = T()) {
        if(n == m_buffer.size())
            return;
        m_buffer.resize(n, def);
    }

    inline void grow(uint n, bool precise = false) {
        if(n <= m_buffer.size())
            return;
        if(n > m_buffer.capacity()) {
            uint newcapacity = static_cast<uint>(m_buffer.capacity());
            if (precise) {
                newcapacity = n;
            } else {
                newcapacity = std::max<uint>(64, newcapacity + std::max<uint>(newcapacity / 2, 1));
                while (newcapacity < n)
                    newcapacity += std::max<uint>(newcapacity / 2, 1);
            }
            reserve(newcapacity);
        }
        m_buffer.resize(n);
    }

    inline void add(const T& v) {
        m_buffer.push_back(v);
    }

    inline DataBuffer &operator<<(const T &t) { add(t); return *this; }

private:
    std::vector<T> m_buffer;
};

#endif
