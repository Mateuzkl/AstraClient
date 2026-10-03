#pragma once

#include <cstddef>

namespace astra_browser
{
template <typename ImagePtr> bool hasVisibleCursorPixels(const ImagePtr &image)
{
    if (!image || image->getBpp() != 4)
        return false;
    const auto &pixels = image->getPixels();
    for (std::size_t i = 3; i < pixels.size(); i += 4) {
        if (pixels[i] != 0)
            return true;
    }
    return false;
}

template <typename ImagePtr> ImagePtr selectCursorImage(const ImagePtr &image)
{
    if (hasVisibleCursorPixels(image))
        return image;
    if (image) {
        // APNG cursors can have a transparent, non-animation base image.
        // CSS cursors are static: use the first visible decoded frame instead.
        for (const auto &frame : image->getAnimation()) {
            if (frame.image && frame.image->getSize() == image->getSize() && hasVisibleCursorPixels(frame.image))
                return frame.image;
        }
    }
    return {};
}
} // namespace astra_browser
