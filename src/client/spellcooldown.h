#ifndef SPELLCOOLDOWN_H
#define SPELLCOOLDOWN_H

namespace SpellCooldownProtocol
{
struct Cooldown
{
    int spellId;
    int delay;
};

template <typename Message>
Cooldown read(Message& message, const bool extendedSpellIds)
{
    // Only 0xA4 negotiates U16 spell ids. The 0xA5 group id remains U8.
    const int spellId = extendedSpellIds ? message.getU16() : message.getU8();
    const int delay = message.getU32();
    return {spellId, delay};
}
} // namespace SpellCooldownProtocol

#endif
