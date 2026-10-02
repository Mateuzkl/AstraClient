#pragma once

#include <cstddef>
#include <memory>
#include <mutex>
#include <utility>

namespace astra_browser
{
// Own queued-frame reservations independently of the connection. Dispatcher
// cancellation/destruction releases them too, including after reconnect.
class MessageBudget : public std::enable_shared_from_this<MessageBudget>
{
  public:
    MessageBudget(size_t bytes, size_t messages) : m_maxBytes(bytes), m_maxMessages(messages) {}

    class Reservation
    {
      public:
        explicit Reservation(std::shared_ptr<MessageBudget> owner) : m_owner(std::move(owner)) {}
        ~Reservation()
        {
            if (m_reserved) {
                std::lock_guard<std::mutex> lock(m_owner->m_mutex);
                m_owner->m_bytes -= m_bytes;
                --m_owner->m_messages;
            }
        }
        Reservation(const Reservation &) = delete;
        Reservation &operator=(const Reservation &) = delete;

      private:
        friend class MessageBudget;
        std::shared_ptr<MessageBudget> m_owner;
        size_t m_bytes = 0;
        bool m_reserved = false;
    };

    std::shared_ptr<Reservation> reserve(size_t bytes)
    {
        auto reservation = std::make_shared<Reservation>(shared_from_this());
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_failed || bytes > m_maxBytes || m_bytes > m_maxBytes - bytes || m_messages >= m_maxMessages)
            return {};
        m_bytes += bytes;
        ++m_messages;
        reservation->m_bytes = bytes;
        reservation->m_reserved = true;
        return reservation;
    }

    bool failOnce()
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_failed)
            return false;
        m_failed = true;
        return true;
    }

  private:
    const size_t m_maxBytes;
    const size_t m_maxMessages;
    std::mutex m_mutex;
    size_t m_bytes = 0;
    size_t m_messages = 0;
    bool m_failed = false;
};
} // namespace astra_browser
