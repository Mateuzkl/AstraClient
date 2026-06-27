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

#ifdef FW_SOUND

#ifndef WAVSOUNDFILE_H
#define WAVSOUNDFILE_H

#include "soundfile.h"

// Minimal RIFF/WAVE loader for uncompressed PCM samples. Used for short SFX
// (e.g. helper alarms) so we don't need an external OGG encoder to ship them.
class WavSoundFile : public SoundFile
{
public:
    WavSoundFile(const FileStreamPtr& fileStream);

    bool prepareWav();

    int read(void *buffer, int bufferSize) override;
    void reset() override;

private:
    uint m_dataOffset; // byte offset of the PCM data chunk inside the file
    uint m_dataPos;    // bytes already consumed from the data chunk
};

#endif

#endif
