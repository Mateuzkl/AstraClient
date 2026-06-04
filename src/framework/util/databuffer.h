#ifndef DATABUFFER_H
#define DATABUFFER_H

#include <vector>
#include <algorithm>

template<class T>
class DataBuffer
{
public:
    DataBuffer(uint res = 64) {
        m_buffer.reserve(res);
    }
    ~DataBuffer() = default;

    DataBuffer(const DataBuffer<T>& d) : m_buffer(d.m_buffer) {}
    DataBuffer& operator=(const DataBuffer<T>& d) = delete;

    inline void reset() { m_buffer.clear(); }
    inline void clear() {
        m_buffer.clear();
        m_buffer.shrink_to_fit();
    }

    inline bool empty() const { return m_buffer.empty(); }
    inline uint size() const { return m_buffer.size(); }
    inline T *data() const { return m_buffer.empty() ? nullptr : const_cast<T*>(m_buffer.data()); }

    inline const T& at(uint i) const { return m_buffer[i]; }
    inline const T& last() const { return m_buffer.back(); }
    inline const T& first() const { return m_buffer.front(); }
    inline const T& operator[](uint i) const { return m_buffer[i]; }
    inline T& operator[](uint i) { return m_buffer[i]; }

    inline void reserve(uint n) {
        m_buffer.reserve(n);
    }

    inline void resize(uint n, T def = T()) {
        m_buffer.resize(n, def);
    }

    inline void grow(uint n, bool precise = false) {
        if(n <= m_buffer.size())
            return;
        if(n > m_buffer.capacity()) {
            uint newcapacity = m_buffer.capacity();
            if (newcapacity == 0) newcapacity = 64;
            if (precise) {
                newcapacity = n;
            } else {
                do { newcapacity *= 4; } while (newcapacity < n);
            }
            m_buffer.reserve(newcapacity);
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
