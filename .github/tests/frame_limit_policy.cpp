#include <framework/core/framelimitpolicy.h>

#include <cassert>
#include <iostream>

int main()
{
    FrameLimitPolicy policy;

    assert(policy.getLimit(WindowFrameState::Foreground, false, false) == 0);
    assert(policy.getLimit(WindowFrameState::Background, false, false) == 30);
    assert(policy.getLimit(WindowFrameState::Minimized, false, false) == 5);

    policy.setUnlimitedForeground(false);
    policy.setForegroundLimit(200);
    policy.setBackgroundLimit(24);
    policy.setMinimizedLimit(3);
    assert(policy.getLimit(WindowFrameState::Foreground, false, false) == 200);
    assert(policy.getLimit(WindowFrameState::Background, false, false) == 24);
    assert(policy.getLimit(WindowFrameState::Minimized, false, false) == 3);

    // A lower software cap coexists with V-Sync; presentation may reduce it further.
    assert(policy.getLimit(WindowFrameState::Foreground, true, true) == 200);
    policy.setUnlimitedForeground(true);
    assert(policy.getLimit(WindowFrameState::Foreground, true, true) == 0);
    assert(policy.getLimit(WindowFrameState::Foreground, true, false) == FrameLimitPolicy::VSyncFallbackFps);
    assert(policy.getLimit(WindowFrameState::Background, true, true) == 24);
    assert(policy.getLimit(WindowFrameState::Minimized, true, true) == 3);

    policy.setBackgroundLimit(0);
    policy.setMinimizedLimit(5000);
    assert(policy.getBackgroundLimit() == 1);
    assert(policy.getMinimizedLimit() == 1000);

    std::cout << "frame limit policy: OK\n";
}
