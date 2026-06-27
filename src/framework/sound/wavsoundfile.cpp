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

#include "wavsoundfile.h"
#include <cstring>

WavSoundFile::WavSoundFile(const FileStreamPtr& fileStream) : SoundFile(fileStream)
{
    m_channels = 0;
    m_rate = 0;
    m_bps = 0;
    m_size = 0;
    m_dataOffset = 0;
    m_dataPos = 0;
}

bool WavSoundFile::prepareWav()
{
    m_file->seek(0);

    // NOTE: FileStream::read returns bytes when streaming from disk but returns
    // the element COUNT (nmemb) when the file is cached in memory (the path
    // openFile() takes for sounds). Always call read(buf, 1, N) so the return
    // value is N (== bytes) in both modes.
    char magic[4];
    if(m_file->read(magic, 1, 4) != 4 || strncmp(magic, "RIFF", 4) != 0)
        return false;

    m_file->getU32(); // overall RIFF chunk size (unused)

    if(m_file->read(magic, 1, 4) != 4 || strncmp(magic, "WAVE", 4) != 0)
        return false;

    bool haveFmt = false;
    bool haveData = false;
    uint16 audioFormat = 0;
    uint fileSize = m_file->size();

    // walk the RIFF sub-chunks; "fmt " always precedes "data" in valid files
    while(m_file->tell() + 8 <= fileSize) {
        char chunkId[4];
        if(m_file->read(chunkId, 1, 4) != 4)
            break;
        uint32 chunkSize = m_file->getU32();

        if(strncmp(chunkId, "fmt ", 4) == 0) {
            audioFormat = m_file->getU16();
            m_channels = m_file->getU16();
            m_rate = m_file->getU32();
            m_file->getU32();         // byte rate
            m_file->getU16();         // block align
            m_bps = m_file->getU16(); // bits per sample
            haveFmt = true;
            if(chunkSize > 16)
                m_file->skip(chunkSize - 16); // skip non-PCM extension bytes
        } else if(strncmp(chunkId, "data", 4) == 0) {
            m_dataOffset = m_file->tell();
            uint avail = (fileSize > m_dataOffset) ? (fileSize - m_dataOffset) : 0;
            m_size = ((uint)chunkSize <= avail) ? (int)chunkSize : (int)avail;
            haveData = true;
            break;
        } else {
            m_file->skip(chunkSize);
            if(chunkSize & 1) // chunks are word-aligned
                m_file->skip(1);
        }
    }

    if(!haveFmt || !haveData || audioFormat != 1 || m_size <= 0)
        return false;

    m_file->seek(m_dataOffset);
    m_dataPos = 0;
    return true;
}

int WavSoundFile::read(void* buffer, int bufferSize)
{
    if(bufferSize <= 0 || m_dataPos >= (uint)m_size)
        return 0;

    uint remaining = (uint)m_size - m_dataPos;
    uint toRead = ((uint)bufferSize < remaining) ? (uint)bufferSize : remaining;

    // read(buf, 1, N) -> returns N (== bytes) regardless of caching mode
    int got = m_file->read(buffer, 1, toRead);
    if(got > 0)
        m_dataPos += got;
    return got;
}

void WavSoundFile::reset()
{
    m_file->seek(m_dataOffset);
    m_dataPos = 0;
}

#endif
