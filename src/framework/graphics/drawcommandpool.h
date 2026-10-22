// Astra's compatibility layer for the DrawPool migration. Submission order and
// custom draw actions stay unchanged; ordinary commands use frame-owned pages.
#pragma once

#include <concepts>
#include <memory>
#include <memory_resource>
#include <type_traits>
#include <utility>
#include <vector>

template<class Base>
class DrawCommandPool
{
    static_assert(std::has_virtual_destructor_v<Base>);
    using Owner = std::unique_ptr<Base, void (*)(Base*)>;

public:
    explicit DrawCommandPool(bool pooled = true,
        std::pmr::memory_resource* upstream = std::pmr::get_default_resource()) :
        m_memory(upstream), m_pooled(pooled) {}
    DrawCommandPool(const DrawCommandPool&) = delete;
    DrawCommandPool& operator=(const DrawCommandPool&) = delete;

    template<std::derived_from<Base> T, class... Args>
    T* emplace(Args&&... args)
    {
        if (!m_pooled) {
            auto command = std::make_unique<T>(std::forward<Args>(args)...);
            auto* result = command.get();
            push_back(std::move(command));
            return result;
        }
        auto* storage = static_cast<T*>(m_memory.allocate(sizeof(T), alignof(T)));
        auto* result = std::construct_at(storage, std::forward<Args>(args)...);
        Owner owner(result, [](Base* p) { std::destroy_at(static_cast<T*>(p)); });
        m_commands.push_back(std::move(owner));
        return result;
    }

    // Custom actions (RmlUi, lighting, shader-specific commands) keep their owners.
    void push_back(std::unique_ptr<Base> command)
    {
        if (!command) return;
        Owner owner(command.release(), [](Base* p) { delete p; });
        m_commands.push_back(std::move(owner));
    }

    auto& operator[](size_t index) { return m_commands[index]; }
    const auto& operator[](size_t index) const { return m_commands[index]; }
    auto begin() { return m_commands.begin(); }
    auto end() { return m_commands.end(); }
    size_t size() const noexcept { return m_commands.size(); }
    bool empty() const noexcept { return m_commands.empty(); }

private:
    // Declared first: destruct commands/resources before releasing their pages.
    std::pmr::monotonic_buffer_resource m_memory;
    std::vector<Owner> m_commands;
    bool m_pooled;
};
