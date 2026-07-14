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

#include "resourcemanager.h"
#include "filestream.h"
#include "resource.h"

#include <framework/core/application.h>
#include <framework/luaengine/luainterface.h>
#include <framework/platform/platform.h>
#include <framework/util/crypt.h>
#include <framework/http/http.h>
#include <queue>
#include <regex>

#include <locale>
#include <cstring>
#include <zlib.h>

#define PHYSFS_DEPRECATED
#include <physfs.h>
#ifndef __EMSCRIPTEN__
#include <zip.h>
#include <zlib.h>
#endif

ResourceManager g_resources;
static const std::string INIT_FILENAME = "init.lua";

// --- Asset container format (Fase 1: AES-256-GCM, key derived, never stored) --
//
//   off  0  [4]  magic      - NOT "ENC*" so the format does not advertise its
//                             OTClient heritage; rotated per-release with the key
//   off  4  [16] salt       - random; per-file key = HKDF(masterKey, salt)
//   off 20  [12] nonce      - random GCM IV
//   off 32  [16] tag        - GCM authentication tag (detects tampering)
//   off 48  [4]  origSize   - uncompressed plaintext size, authenticated as AAD
//   off 52  [..] ciphertext = AES-256-GCM( zlib_compress(plaintext) )
//
// Unlike the legacy ENC3 scheme, the decryption key is NEVER written next to the
// ciphertext. It is derived at runtime from the embedded master key + the salt.
namespace {
    constexpr size_t ASSET_MAGIC_LEN = 4;
    constexpr size_t ASSET_SALT_LEN = 16;
    constexpr size_t ASSET_NONCE_LEN = 12;
    constexpr size_t ASSET_TAG_LEN = 16;
    constexpr size_t ASSET_ORIGSIZE_LEN = 4;
    constexpr size_t ASSET_OFF_SALT = ASSET_MAGIC_LEN;                       // 4
    constexpr size_t ASSET_OFF_NONCE = ASSET_OFF_SALT + ASSET_SALT_LEN;      // 20
    constexpr size_t ASSET_OFF_TAG = ASSET_OFF_NONCE + ASSET_NONCE_LEN;      // 32
    constexpr size_t ASSET_OFF_ORIGSIZE = ASSET_OFF_TAG + ASSET_TAG_LEN;     // 48
    constexpr size_t ASSET_HEADER_LEN = ASSET_OFF_ORIGSIZE + ASSET_ORIGSIZE_LEN; // 52
    constexpr uint32_t ASSET_MAX_SIZE = 512u * 1024u * 1024u;                // sanity bound

    const uint8_t ASSET_MAGIC[ASSET_MAGIC_LEN] = { 0x4B, 0x39, 0x1D, 0xE2 };

    // Footer written after an encrypted container blob that is appended to the
    // binary, so loadDataFromSelf can locate the blob without a ZIP/PK signature.
    // Layout: [uint32 LE blobLen][4-byte footer magic]. Total 8 bytes at EOF.
    constexpr size_t ASSET_FOOTER_LEN = 8;
    const uint8_t ASSET_FOOTER_MAGIC[4] = { 0xC7, 0x1A, 0x6B, 0x4F };

    // Master-key material. The real per-release values live in a gitignored
    // generated header (tools/gen_asset_key.py) so the key is never committed.
    // A committed fallback is used in dev. NOTE: this is free obfuscation only --
    // the material is, by necessity, present in the binary, so it slows a manual
    // reverse-engineer but does not stop one. The actual master key bytes never
    // appear contiguously: they are DERIVED from the scattered material via HKDF.
#if __has_include("keymaterial.gen.h")
#  include "keymaterial.gen.h"
#else
    static const unsigned char KOLISEU_KM_A[12] = {
        0x3f, 0xa1, 0x07, 0xcc, 0x91, 0x6e, 0x28, 0xb4, 0x5d, 0xe0, 0x12, 0x8a
    };
    static const unsigned char KOLISEU_KM_B[12] = {
        0xd7, 0x49, 0xbf, 0x03, 0x66, 0xfa, 0x15, 0x9c, 0x2b, 0x80, 0xe5, 0x47
    };
    static const unsigned char KOLISEU_KM_C[12] = {
        0x71, 0x0a, 0xcd, 0x38, 0x96, 0x52, 0xab, 0x1f, 0xe4, 0x63, 0x8d, 0xf0
    };
    static const unsigned int KOLISEU_KM_SALT = 0x5A3C9E11u;
#endif

    void assembleMasterKey(uint8_t out[32]) {
        uint8_t ikm[36];
        std::memcpy(ikm + 0,  KOLISEU_KM_A, 12);
        std::memcpy(ikm + 12, KOLISEU_KM_B, 12);
        std::memcpy(ikm + 24, KOLISEU_KM_C, 12);
        uint32_t salt = KOLISEU_KM_SALT;
        g_crypt.hkdfSha256(ikm, sizeof(ikm),
                           reinterpret_cast<const uint8_t*>(&salt), sizeof(salt),
                           reinterpret_cast<const uint8_t*>("koliseu-master-v1"), 17,
                           out, 32);
        std::memset(ikm, 0, sizeof(ikm));
    }

    // Derive the per-file key from the master key and the file's random salt.
    void deriveAssetKey(const uint8_t* salt, size_t saltLen, uint8_t out[32]) {
        uint8_t master[32];
        assembleMasterKey(master);
        static const char info[] = "koliseu-asset-v1";
        g_crypt.hkdfSha256(master, sizeof(master), salt, saltLen,
                           (const uint8_t*)info, sizeof(info) - 1, out, 32);
        std::memset(master, 0, sizeof(master));
    }

    bool isAssetEncrypted(const std::string& b) {
        return b.size() >= ASSET_MAGIC_LEN &&
               std::memcmp(b.data(), ASSET_MAGIC, ASSET_MAGIC_LEN) == 0;
    }
}

void ResourceManager::init(const char *argv0)
{
#if defined(WIN32)
    char fileName[255];
    GetModuleFileNameA(NULL, fileName, sizeof(fileName));
    m_binaryPath = std::filesystem::absolute(fileName);
#else
    m_binaryPath = std::filesystem::absolute(argv0);    
#endif
    PHYSFS_init(argv0);
    PHYSFS_permitSymbolicLinks(1);
}

void ResourceManager::terminate()
{
    PHYSFS_deinit();
}

bool ResourceManager::launchCorrect(const std::string& product, const std::string& app) { // curently works only on windows
    auto init_path = m_binaryPath.parent_path();
    init_path /= INIT_FILENAME;
    if (std::filesystem::exists(init_path)) // debug version
        return false;

    const char* localDir = PHYSFS_getPrefDir(product.c_str(), app.c_str());
    if (!localDir)
        return false;

    auto fileName2 = m_binaryPath.stem().string();
    fileName2 = stdext::split(fileName2, "-")[0];
    stdext::tolower(fileName2);

    std::filesystem::path path(std::filesystem::u8path(localDir));
    std::error_code ec;
    auto lastWrite = std::filesystem::last_write_time(m_binaryPath, ec);
    std::filesystem::path binary = m_binaryPath;
    for (auto& entry : std::filesystem::directory_iterator(path)) {
        if (std::filesystem::is_directory(entry.path()))
            continue;

        auto fileName1 = entry.path().stem().string();
        fileName1 = stdext::split(fileName1, "-")[0];
        stdext::tolower(fileName1);
        if (fileName1 != fileName2)
            continue;

        if (entry.path().extension() == m_binaryPath.extension()) {
            std::error_code ec;
            auto writeTime = std::filesystem::last_write_time(entry.path(), ec);
            if (!ec && writeTime > lastWrite) {
                lastWrite = writeTime;
                binary = entry.path();
            }
        }
    }

    for (auto& entry : std::filesystem::directory_iterator(path)) { // remove old
        if (std::filesystem::is_directory(entry.path()))
            continue;

        auto fileName1 = entry.path().stem().string();
        fileName1 = stdext::split(fileName1, "-")[0];
        stdext::tolower(fileName1);
        if (fileName1 != fileName2)
            continue;

        if (entry.path().extension() == m_binaryPath.extension()) {
            if (binary == entry.path())
                continue;
            std::error_code ec;
            std::filesystem::remove(entry.path(), ec);
        }
    }

    if (binary == m_binaryPath)
        return false;

    // Boost.Process v2 dropped boost::process::child + wait_for/exit_code/detach
    // in favor of a co_await-flavoured API. Rather than chase that upstream
    // (this is the bootstrap-rename helper, never the hot path), shell out via
    // CreateProcessA directly — same semantics, no dep.
    STARTUPINFOA si{}; si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    std::string cmdLine = binary.string();
    std::vector<char> cmdMutable(cmdLine.begin(), cmdLine.end());
    cmdMutable.push_back('\0');
    if (!CreateProcessA(nullptr, cmdMutable.data(), nullptr, nullptr, FALSE,
                        0, nullptr, nullptr, &si, &pi)) {
        return false;
    }
    DWORD waitResult = WaitForSingleObject(pi.hProcess, 5000);
    bool ok = true;
    if (waitResult == WAIT_OBJECT_0) {
        DWORD code = 1;
        GetExitCodeProcess(pi.hProcess, &code);
        ok = (code == 0);
    }
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return ok;
}

bool ResourceManager::setupWriteDir(const std::string& product, const std::string& app) {
    const char* localDir = PHYSFS_getPrefDir(product.c_str(), app.c_str());

    if (!localDir) {
        g_logger.fatal(stdext::format("Unable to get local dir, error: %s", PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
        return false;
    }

    if (!PHYSFS_mount(localDir, NULL, 0)) {
        g_logger.fatal(stdext::format("Unable to mount local directory '%s': %s", localDir, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
        return false;
    }

    if (!PHYSFS_setWriteDir(localDir)) {
        g_logger.fatal(stdext::format("Unable to set write dir '%s': %s", localDir, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
        return false;
    }

    m_writeDir = std::filesystem::path(std::filesystem::u8path(localDir));
    return true;
}

bool ResourceManager::setup()
{
    std::string localDir(PHYSFS_getWriteDir());
    std::vector<std::string> possiblePaths = { localDir, g_platform.getCurrentDir() };
    const char* baseDir = PHYSFS_getBaseDir();
    if (baseDir)
        possiblePaths.push_back(baseDir);

    for (const std::string& dir : possiblePaths) {
        if (dir == localDir || !PHYSFS_mount(dir.c_str(), NULL, 0))
            continue;

        if(PHYSFS_exists(INIT_FILENAME.c_str())) {
            g_logger.info(stdext::format("Found work dir at '%s'", dir));
            return true;
        }

        PHYSFS_unmount(dir.c_str());
    }

    for(const std::string& dir : possiblePaths) {
        if (dir != localDir && !PHYSFS_mount(dir.c_str(), NULL, 0)) {
            continue;
        }

        if (!PHYSFS_exists("data.zip")) {
            if(dir != localDir)
                PHYSFS_unmount(dir.c_str());
            continue;
        }

        PHYSFS_File* file = PHYSFS_openRead("data.zip");
        if (!file) {
            if (dir != localDir)
                PHYSFS_unmount(dir.c_str());
            continue;
        }

        auto data = std::make_shared<std::vector<uint8_t>>(PHYSFS_fileLength(file));
        PHYSFS_readBytes(file, data->data(), data->size());
        PHYSFS_close(file);
        if (dir != localDir)
            PHYSFS_unmount(dir.c_str());

        g_logger.info(stdext::format("Found work dir at '%s'", dir));
        decryptContainerIfNeeded(data);
        if (mountMemoryData(data))
            return true;
    }
    if (loadDataFromSelf()) {
        g_logger.info(stdext::format("Found work dir inside binary"));
        return true;
    }

    g_logger.fatal("Unable to find working directory (or data.zip)");
    return false;
}

std::string ResourceManager::getCompactName() {
    std::string fileData;
    if (loadDataFromSelf()) {
        try {
            fileData = readFileContents(INIT_FILENAME);
        } catch (...) {
            fileData = "";
        }
        unmountMemoryData();
    }

    std::vector<std::string> possiblePaths = { g_platform.getCurrentDir() };
    const char* baseDir = PHYSFS_getBaseDir();
    if (baseDir)
        possiblePaths.push_back(baseDir);

    if (fileData.empty()) {
        try {
            for (const std::string& dir : possiblePaths) {
                if (!PHYSFS_mount(dir.c_str(), NULL, 0))
                    continue;

                if (PHYSFS_exists(INIT_FILENAME.c_str())) {
                    fileData = readFileContents(INIT_FILENAME);
                    PHYSFS_unmount(dir.c_str());
                    break;
                }
                PHYSFS_unmount(dir.c_str());
            }
        } catch (...) {
            fileData = "";
        }
    }

    if (fileData.empty()) {
        try {
            for (const std::string& dir : possiblePaths) {
                std::string path = dir + "/data.zip";
                if (!PHYSFS_mount(path.c_str(), NULL, 0))
                    continue;

                if (PHYSFS_exists(INIT_FILENAME.c_str())) {
                    fileData = readFileContents(INIT_FILENAME);
                    PHYSFS_unmount(path.c_str());
                    break;
                }
                PHYSFS_unmount(path.c_str());
            }
        } catch (...) {}
    }

    std::smatch regex_match;
    if (std::regex_search(fileData, regex_match, std::regex("APP_NAME[^\"]+\"([^\"]+)"))) {
        if (regex_match.size() == 2 && regex_match[1].str().length() > 0 && regex_match[1].str().length() < 30) {
            return regex_match[1].str();
        }
    }
    return "koliseuclient";
}

bool ResourceManager::loadDataFromSelf(bool unmountIfMounted) {
    std::shared_ptr<std::vector<uint8_t>> data = nullptr;
    std::ifstream file(m_binaryPath.string(), std::ios::binary);
    if (!file.is_open())
        return false;
    file.seekg(0, std::ios_base::end);
    std::size_t size = file.tellg();
    file.seekg(0, std::ios_base::beg);
    if (size < 1024 || size > 1024 * 1024 * 128) {
        file.close();
        return false;
    }

    std::vector<uint8_t> v(1 + size);
    file.read((char*)&v[0], size);
    file.close();

    // Preferred: encrypted container located via the trailing footer. No ZIP/PK
    // signature is present, so binwalk and friends just see high-entropy noise.
    if (size > ASSET_FOOTER_LEN + ASSET_HEADER_LEN) {
        const uint8_t* foot = &v[size - ASSET_FOOTER_LEN];
        if (std::memcmp(foot + 4, ASSET_FOOTER_MAGIC, 4) == 0) {
            uint32_t blobLen = 0;
            std::memcpy(&blobLen, foot, 4);
            if (blobLen >= ASSET_HEADER_LEN && blobLen <= size - ASSET_FOOTER_LEN) {
                size_t blobStart = size - ASSET_FOOTER_LEN - blobLen;
                std::string blob(reinterpret_cast<const char*>(&v[blobStart]), blobLen);
                if (decryptBuffer(blob))
                    data = std::make_shared<std::vector<uint8_t>>(blob.begin(), blob.end());
            }
        }
    }

    // Fallback: legacy plaintext zip appended to the binary (PK signature scan).
    if (!data) {
        for (size_t i = 0, end = size - 128; i < end; ++i) {
            if (v[i] == 0x50 && v[i + 1] == 0x4b && v[i + 2] == 0x03 && v[i + 3] == 0x04 && v[i + 4] == 0x14) {
                uint32_t compSize = *(uint32_t*)&v[i + 18];
                uint32_t decompSize = *(uint32_t*)&v[i + 22];
                if (compSize < 1024 * 1024 * 512 && decompSize < 1024 * 1024 * 512) {
                    data = std::make_shared<std::vector<uint8_t>>(&v[i], &v[v.size() - 1]);
                    break;
                }
            }
        }
    }
    v.clear();


    if (unmountIfMounted)
        unmountMemoryData();

    if (mountMemoryData(data)) {
        m_loadedFromMemory = true;
        return true;
    }

    return false;
}

bool ResourceManager::fileExists(const std::string& fileName)
{
    if (fileName.find("/downloads") != std::string::npos)
        return g_http.getFile(fileName.substr(10)) != nullptr;
    return (PHYSFS_exists(resolvePath(fileName).c_str()) && !PHYSFS_isDirectory(resolvePath(fileName).c_str()));
}

bool ResourceManager::directoryExists(const std::string& directoryName)
{
    if (directoryName == "/downloads")
        return true;
    return (PHYSFS_isDirectory(resolvePath(directoryName).c_str()));
}

void ResourceManager::readFileStream(const std::string& fileName, std::iostream& out)
{
    std::string buffer(readFileContents(fileName));
    if(buffer.length() == 0) {
        out.clear(std::ios::eofbit);
        return;
    }
    out.clear(std::ios::goodbit);
    out.write(&buffer[0], buffer.length());
    out.seekg(0, std::ios::beg);
}

std::string ResourceManager::readFileContents(const std::string& fileName, bool safe)
{
    std::string fullPath = resolvePath(fileName);
    
    if (fullPath.find("/downloads") != std::string::npos) {
        auto dfile = g_http.getFile(fullPath.substr(10));
        if (dfile)
            return std::string(dfile->body.begin(), dfile->body.end());
    }

    PHYSFS_File* file = PHYSFS_openRead(fullPath.c_str());
    if(!file)
        stdext::throw_exception(stdext::format("unable to open file '%s': %s", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

    int fileSize = PHYSFS_fileLength(file);
    std::string buffer(fileSize, 0);
    PHYSFS_readBytes(file, (void*)&buffer[0], fileSize);
    PHYSFS_close(file);

    if (safe) {
        return buffer;
    }

    // skip decryption for bot configs
    if (fullPath.find("/bot/") != std::string::npos) {
        return buffer;
    }

    // .json is shipped plaintext (see encrypt(): the Lua g_resources.readFileContents
    // binding is the SAFE/non-decrypting variant, so an encrypted .json would reach
    // json.decode as ciphertext). Tolerate plaintext .json on the C++ decrypting path too.
    static std::string unencryptedExtensions[] = { ".otml", ".otmm", ".dmp", ".log", ".txt", ".dll", ".exe", ".zip", ".json" };

    if (!decryptBuffer(buffer)) {
        bool ignore = (m_customEncryption == 0);
        for (auto& it : unencryptedExtensions) {
            if (fileName.find(it) == fileName.size() - it.size()) {
                ignore = true;
            }
        }
        if(!ignore)
            g_logger.fatal(stdext::format("unable to decrypt file: %s", fullPath));
    }

    return buffer;
}

bool ResourceManager::isFileEncryptedOrCompressed(const std::string& fileName)
{
    std::string fullPath = resolvePath(fileName);
    std::string fileContent;

    if (fullPath.find("/downloads") != std::string::npos) {
        auto dfile = g_http.getFile(fullPath.substr(10));
        if (dfile) {
            if (dfile->body.size() < 10)
                return false;
            fileContent = std::string(dfile->body.begin(), dfile->body.begin() + 10);
        }
    }

    if (!fileContent.empty()) {
        PHYSFS_File* file = PHYSFS_openRead(fullPath.c_str());
        if (!file)
            stdext::throw_exception(stdext::format("unable to open file '%s': %s", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

        int fileSize = std::min<int>(10, PHYSFS_fileLength(file));
        fileContent.resize(fileSize);
        PHYSFS_readBytes(file, (void*)&fileContent[0], fileSize);
        PHYSFS_close(file);
    }

    if (fileContent.size() < 10)
        return false;
    
    if (fileContent.substr(0, 4).compare("ENC3") == 0)
        return true;

    if ((uint8_t)fileContent[0] != 0x1f || (uint8_t)fileContent[1] != 0x8b || (uint8_t)fileContent[2] != 0x08) {
        return false;
    }

    return true;
}

bool ResourceManager::writeFileBuffer(const std::string& fileName, const uchar* data, uint size)
{
    PHYSFS_file* file = PHYSFS_openWrite(fileName.c_str());
    if(!file) {
        g_logger.error(stdext::format("unable to open file for writing '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
        return false;
    }

    PHYSFS_writeBytes(file, (void*)data, size);
    PHYSFS_close(file);
    return true;
}

bool ResourceManager::writeFileStream(const std::string& fileName, std::iostream& in)
{
    std::streampos oldPos = in.tellg();
    in.seekg(0, std::ios::end);
    std::streampos size = in.tellg();
    in.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    in.read(&buffer[0], size);
    bool ret = writeFileBuffer(fileName, (const uchar*)&buffer[0], size);
    in.seekg(oldPos, std::ios::beg);
    return ret;
}

bool ResourceManager::writeFileContents(const std::string& fileName, const std::string& data)
{
    return writeFileBuffer(fileName, (const uchar*)data.c_str(), data.size());
}

FileStreamPtr ResourceManager::openFile(const std::string& fileName, bool dontCache)
{
    std::string fullPath = resolvePath(fileName);
    if (isFileEncryptedOrCompressed(fullPath) || !dontCache) {
        return std::make_shared<FileStream>(fullPath, readFileContents(fullPath));
    }
    PHYSFS_File* file = PHYSFS_openRead(fullPath.c_str());
    if (!file)
        stdext::throw_exception(stdext::format("unable to open file '%s': %s", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    return std::make_shared<FileStream>(fullPath, file, false);
}

FileStreamPtr ResourceManager::appendFile(const std::string& fileName)
{
    PHYSFS_File* file = PHYSFS_openAppend(fileName.c_str());
    if(!file)
        stdext::throw_exception(stdext::format("failed to append file '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    return std::make_shared<FileStream>(fileName, file, true);
}

FileStreamPtr ResourceManager::createFile(const std::string& fileName)
{
    PHYSFS_File* file = PHYSFS_openWrite(fileName.c_str());
    if(!file)
        stdext::throw_exception(stdext::format("failed to create file '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    return std::make_shared<FileStream>(fileName, file, true);
}

bool ResourceManager::deleteFile(const std::string& fileName)
{
    return PHYSFS_delete(resolvePath(fileName).c_str()) != 0;
}

bool ResourceManager::makeDir(const std::string directory)
{
    return PHYSFS_mkdir(directory.c_str());
}

std::list<std::string> ResourceManager::listDirectoryFiles(const std::string& directoryPath, bool fullPath /* = false */, bool raw /*= false*/)
{
    std::list<std::string> files;
    auto path = raw ? directoryPath : resolvePath(directoryPath);
    auto rc = PHYSFS_enumerateFiles(path.c_str());

    if (!rc)
        return files;

    for (int i = 0; rc[i] != NULL; i++) {
        if(fullPath)
            files.push_back(path + "/" + rc[i]);
        else
            files.push_back(rc[i]);
    }

    PHYSFS_freeList(rc);
    files.sort();
    return files;
}

std::string ResourceManager::resolvePath(std::string path)
{
    if(!stdext::starts_with(path, "/")) {
        std::string scriptPath = "/" + g_lua.getCurrentSourcePath();
        if(!scriptPath.empty())
            path = scriptPath + "/" + path;
        else
            g_logger.traceWarning(stdext::format("the following file path is not fully resolved: %s", path));
    }
    stdext::replace_all(path, "//", "/");
    if(!PHYSFS_exists(path.c_str())) {
        static const std::string layouts_prefix = "/layouts/";
        if (!m_layout.empty()) {
            if (PHYSFS_exists((layouts_prefix + m_layout + path).c_str())) {
                return layouts_prefix + m_layout + path;
            }
        }
        static const std::string extra_check[] = { "/mods", "/data", "/modules" };
        for (auto extra : extra_check) {
            if (PHYSFS_exists((extra + path).c_str())) {
                return extra + path;
            }
        }
    }
    return path;
}

std::string ResourceManager::getRealPath(const std::string& physfsPath)
{
    // Phase 0 P0.8: Resolve a PHYSFS virtual path to a real filesystem path.
    // The new asset loaders use std::ifstream on raw paths, so we need to
    // translate "/things/1525" -> "<mount root>/things/1525" on the host FS.
    std::string normalized = resolvePath(physfsPath);
    if (normalized.empty())
        return std::string();
    // PHYSFS_getRealDir returns the mount-point root for an existing entry.
    // For a path that doesn't exist (yet to be created file), it returns null.
    const char* realDir = PHYSFS_getRealDir(normalized.c_str());
    if (!realDir) {
        // Fallback: if the entry doesn't exist, try the write dir as the
        // most likely mount point. Callers that need strict semantics should
        // check fileExists/directoryExists first.
        if (m_writeDir.empty())
            return std::string();
        std::filesystem::path candidate = m_writeDir;
        candidate /= std::filesystem::u8path(normalized.substr(normalized.front() == '/' ? 1 : 0));
        return candidate.string();
    }
    std::filesystem::path full = std::filesystem::u8path(realDir);
    full /= std::filesystem::u8path(normalized.front() == '/' ? normalized.substr(1) : normalized);
    return full.string();
}

std::string ResourceManager::guessFilePath(const std::string& filename, const std::string& type)
{
    if(isFileType(filename, type))
        return filename;
    return filename + "." + type;
}

bool ResourceManager::isFileType(const std::string& filename, const std::string& type)
{
    if(stdext::ends_with(filename, std::string(".") + type))
        return true;
    return false;
}

std::string ResourceManager::fileChecksum(const std::string& path) {
    static std::map<std::string, std::string> cache;

    auto it = cache.find(path);
    if (it != cache.end())
        return it->second;

    PHYSFS_File* file = PHYSFS_openRead(path.c_str());
    if(!file)
        return "";

    int fileSize = PHYSFS_fileLength(file);
    std::string buffer(fileSize, 0);
    PHYSFS_readBytes(file, (void*)&buffer[0], fileSize);
    PHYSFS_close(file);

    auto checksum = g_crypt.crc32(buffer, false);
    cache[path] = checksum;

    return checksum;
}

std::map<std::string, std::string> ResourceManager::filesChecksums()
{
    std::map<std::string, std::string> ret;
#ifndef __EMSCRIPTEN__
    if (!m_memoryData)
        return ret;

    zip_source_t* src;
    zip_t* za;
    zip_stat_t file_stat;
    zip_error_t error;
    zip_error_init(&error);
    zip_stat_init(&file_stat);

    if ((src = zip_source_buffer_create(m_memoryData->data(), m_memoryData->size(), 0, &error)) == NULL)
        g_logger.fatal(stdext::format("can't create source: %s", zip_error_strerror(&error)));

    if ((za = zip_open_from_source(src, ZIP_RDONLY, &error)) == NULL)
        g_logger.fatal(stdext::format("can't open zip from source: %s", zip_error_strerror(&error)));

    zip_int64_t entries = zip_get_num_entries(za, 0);
    for (zip_int64_t entry_idx = 0; entry_idx < entries; entry_idx++) {
        if (zip_stat_index(za, entry_idx, 0, &file_stat)) {
            g_logger.fatal(stdext::format("error stat-ing file at index %i: %s",
                    (int)(entry_idx), zip_strerror(za)));
        }
        if (!(file_stat.valid & ZIP_STAT_NAME)) {
            g_logger.warning(stdext::format("warning: skipping entry at index %i with invalid name.",
                    (int)entry_idx));
            continue;
        }
        std::string name(file_stat.name);
        if (name.empty()) continue;
        if (name[0] != '/')
            name = std::string("/") + name;
        if (name.back() == '/' || file_stat.size == 0) // dir
            continue;
        stdext::replace_all(name, "\\", "/");
        ret[name] = stdext::dec_to_hex(file_stat.crc);
    }

    if (zip_close(za) < 0)
        g_logger.fatal(stdext::format("can't close zip archive: %s", zip_strerror(za)));
    zip_error_fini(&error);
#endif
    return ret;
}

std::string ResourceManager::selfChecksum() {
    static std::string checksum;
    if (!checksum.empty())
        return checksum;

    std::ifstream file(m_binaryPath.string(), std::ios::binary);
    if (!file.is_open())
        return "";

    std::string buffer(std::istreambuf_iterator<char>(file), {});
    file.close();

    checksum = g_crypt.crc32(buffer, false);
    return checksum;
}

void ResourceManager::updateData(const std::set<std::string>& files, bool reMount) {
#if !defined(__EMSCRIPTEN__)
    if (!m_loadedFromArchive)
        g_logger.fatal("Client can be updated only when running from zip archive");

    g_logger.info(stdext::format("Updating client, %i files", files.size()));

    zip_source_t *src;
    zip_t *za;
    zip_error_t error;
    zip_error_init(&error);

    if ((src = zip_source_buffer_create(0, 0, 0, &error)) == NULL)
        return g_logger.fatal(stdext::format("can't create source: %s", zip_error_strerror(&error)));
    zip_source_keep(src);

    if ((za = zip_open_from_source(src, ZIP_TRUNCATE, &error)) == NULL)
        return g_logger.fatal(stdext::format("can't open zip from source: %s", zip_error_strerror(&error)));

    zip_error_fini(&error);

    for (auto fileName : files) {
        if (fileName.empty())
            continue;
        if (fileName.size() > 1 && fileName[0] == '/')
            fileName = fileName.substr(1);
        zip_source_t* s;
        auto dFile = g_http.getFile(fileName);
        if (dFile) {
            if ((s = zip_source_buffer(za, dFile->body.data(), dFile->body.size(), 0)) == NULL)
                return g_logger.fatal(stdext::format("can't create source buffer: %s", zip_strerror(za)));
        } else {
            PHYSFS_File* file = PHYSFS_openRead((std::string("/") + fileName).c_str());
            if (!file)
                g_logger.fatal(stdext::format("unable to open file '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

            int fileSize = PHYSFS_fileLength(file);
            void* buffer = malloc(fileSize);
            PHYSFS_readBytes(file, buffer, fileSize);
            PHYSFS_close(file);
            if ((s = zip_source_buffer(za, buffer, fileSize, 1)) == NULL)
                return g_logger.fatal(stdext::format("can't create source buffer: %s", zip_strerror(za)));
        }

        int fileIndex = zip_file_add(za, fileName.c_str(), s, ZIP_FL_OVERWRITE);
        if(fileIndex < 0)
            return g_logger.fatal(stdext::format("can't add file %s to zip archive: %s", fileName, zip_strerror(za)));
        if (zip_set_file_compression(za, fileIndex, ZIP_CM_DEFLATE, 1) != 0)
            return g_logger.fatal("Can't set file compression level");
    }

    if (zip_close(za) < 0)
        return g_logger.fatal(stdext::format("can't close zip archive: %s", zip_strerror(za)));

    zip_stat_t zst;
    if (zip_source_stat(src, &zst) < 0)
        return g_logger.fatal(stdext::format("can't stat source: %s", zip_error_strerror(zip_source_error(src))));
    
    size_t zipSize = zst.size;    

    if (zip_source_open(src) < 0)
        return g_logger.fatal(stdext::format("can't open source: %s", zip_error_strerror(zip_source_error(src))));

    PHYSFS_file* file = PHYSFS_openWrite("data.zip");
    if (!file)
        return g_logger.fatal(stdext::format("can't open data.zip for writing: %s", PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

    static const size_t CHUNK_SIZE = 1024 * 1024;
    std::vector<char> chunk(CHUNK_SIZE);
    while (zipSize > 0) {
        size_t currentChunk = std::min<size_t>(zipSize, CHUNK_SIZE);
        if ((zip_uint64_t)zip_source_read(src, chunk.data(), currentChunk) < currentChunk)
            return g_logger.fatal(stdext::format("can't read data from source: %s", zip_error_strerror(zip_source_error(src))));
        PHYSFS_writeBytes(file, chunk.data(), currentChunk);
        zipSize -= currentChunk;
    }

    PHYSFS_close(file);
    zip_source_close(src);
    zip_source_free(src);

    if (reMount) {
        unmountMemoryData();
        file = PHYSFS_openRead("data.zip");
        if (!file)
            g_logger.fatal(stdext::format("Can't open new data.zip"));

        int size = PHYSFS_fileLength(file);
        if (size < 1024)
            g_logger.fatal(stdext::format("New data.zip is invalid"));

        auto data = std::make_shared<std::vector<uint8_t>>(size);
        PHYSFS_readBytes(file, data->data(), data->size());
        PHYSFS_close(file);
        if (!mountMemoryData(data)) {
            g_logger.fatal("Error while mounting new data.zip");
        }
    }
#else
    g_logger.fatal("updateData is unsupported");
#endif
}

void ResourceManager::updateExecutable(std::string fileName)
{
    if (fileName.size() <= 2) {
        g_logger.fatal("Invalid executable name");
    }

    if (fileName[0] == '/')
        fileName = fileName.substr(1);

    auto dFile = g_http.getFile(fileName);
    if (!dFile)
        g_logger.fatal(stdext::format("Cannot find executable: %s in downloads", fileName));

    std::filesystem::path path(m_binaryPath);
    auto newBinary = path.stem().string() + "-" + std::to_string(time(nullptr)) + path.extension().string();
    g_logger.info(stdext::format("Updating binary file: %s", newBinary));
    PHYSFS_file* file = PHYSFS_openWrite(newBinary.c_str());
    if (!file)
        return g_logger.fatal(stdext::format("can't open %s for writing: %s", newBinary, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    PHYSFS_writeBytes(file, dFile->body.data(), dFile->body.size());
    PHYSFS_close(file);

    std::filesystem::path newBinaryPath(std::filesystem::u8path(PHYSFS_getWriteDir()));
#if defined(WIN32)
    installDlls(newBinaryPath);
#endif
}

std::string ResourceManager::createArchive(const std::map<std::string, std::string>& files)
{
#ifdef __EMSCRIPTEN__
    return "";
#else
    if (files.empty()) return "";

    zip_source_t* src;
    zip_t* za;
    zip_error_t error;
    zip_error_init(&error);

    if ((src = zip_source_buffer_create(0, 0, 0, &error)) == NULL)
        stdext::throw_exception(stdext::format("can't create source: %s", zip_error_strerror(&error)));
    zip_source_keep(src);

    if ((za = zip_open_from_source(src, ZIP_TRUNCATE, &error)) == NULL)
        stdext::throw_exception(stdext::format("can't open zip from source: %s", zip_error_strerror(&error)));

    zip_error_fini(&error);

    for (auto& file : files) {
        if (file.first.empty() || file.second.empty())
            continue;

        zip_source_t* s;
        if ((s = zip_source_buffer(za, file.second.data(), file.second.size(), 0)) == NULL)
            stdext::throw_exception(stdext::format("can't create source buffer: %s", zip_strerror(za)));

        std::string fileName = file.first;
        if (fileName.size() > 1 && fileName[0] == '/')
            fileName = fileName.substr(1);

        int fileIndex = zip_file_add(za, fileName.c_str(), s, ZIP_FL_OVERWRITE);
        if (fileIndex < 0)
            stdext::throw_exception(stdext::format("can't add file %s to zip archive: %s", fileName, zip_strerror(za)));
//        if (zip_set_file_compression(za, fileIndex, ZIP_CM_DEFLATE, 1) != 0)
//            stdext::throw_exception("Can't set file compression level");
    }

    if (zip_close(za) < 0)
        stdext::throw_exception(stdext::format("can't close zip archive: %s", zip_strerror(za)));

    zip_stat_t zst;
    if (zip_source_stat(src, &zst) < 0)
        stdext::throw_exception(stdext::format("can't stat source: %s", zip_error_strerror(zip_source_error(src))));

    size_t zipSize = zst.size;

    if (zip_source_open(src) < 0)
        stdext::throw_exception(stdext::format("can't open source: %s", zip_error_strerror(zip_source_error(src))));

    std::string data(zipSize, '\0');
    if ((zip_uint64_t)zip_source_read(src, data.data(), data.size()) != data.size())
        stdext::throw_exception(stdext::format("can't read data from source: %s", zip_error_strerror(zip_source_error(src))));

    zip_source_close(src);
    zip_source_free(src);

    return data;
#endif
}

std::map<std::string, std::string> ResourceManager::decompressArchive(std::string dataOrPath)
{
    std::map<std::string, std::string> ret;
#ifdef __EMSCRIPTEN__
    return ret;
#else
    if (dataOrPath.size() < 64) {
        dataOrPath = readFileContents(dataOrPath);
    }

    zip_source_t* src;
    zip_t* za;
    zip_stat_t file_stat;
    zip_error_t error;
    zip_error_init(&error);
    zip_stat_init(&file_stat);

    if ((src = zip_source_buffer_create(dataOrPath.c_str(), dataOrPath.size(), 0, &error)) == NULL)
        stdext::throw_exception(stdext::format("unpackArchive: can't create source: %s", zip_error_strerror(&error)));

    if ((za = zip_open_from_source(src, ZIP_RDONLY, &error)) == NULL)
        stdext::throw_exception(stdext::format("unpackArchive: can't open zip from source: %s", zip_error_strerror(&error)));

    zip_int64_t entries = zip_get_num_entries(za, 0);
    for (zip_int64_t entry_idx = 0; entry_idx < entries; entry_idx++) {
        if (zip_stat_index(za, entry_idx, 0, &file_stat)) {
            stdext::throw_exception(stdext::format("unpackArchive: error stat-ing file at index %i: %s",
                                          (int)(entry_idx), zip_strerror(za)));
        }
        if (!(file_stat.valid & ZIP_STAT_NAME)) {
            g_logger.warning(stdext::format("warning: skipping entry at index %i with invalid name.",
                                            (int)entry_idx));
            continue;
        }
        std::string name(file_stat.name);
        if (name.empty()) continue;
        if (name[0] != '/')
            name = std::string("/") + name;
        if (name.back() == '/' || file_stat.size == 0) // dir
            continue;
        stdext::replace_all(name, "\\", "/");

        zip_file_t* file = zip_fopen_index(za, entry_idx, 0);
        if(!file)
            stdext::throw_exception(stdext::format("can't open file from zip archive: %s - %s", name, zip_strerror(za)));
        std::string buffer(file_stat.size, '\0');
        zip_fread(file, buffer.data(), buffer.size());
        zip_fclose(file);
        ret[name] = std::move(buffer);
    }

    if (zip_close(za) < 0)
        stdext::throw_exception(stdext::format("can't close zip archive: %s", zip_strerror(za)));
    zip_error_fini(&error);
    return ret; // success
#endif
}

#if defined(WIN32)
void ResourceManager::installDlls(std::filesystem::path dest)
{
    static std::list<std::string> dlls = {
        {"libEGL.dll"},
        {"libGLESv2.dll"},
        {"d3dcompiler_46.dll"},
        {"d3dcompiler_47.dll"}
    };

    int added_dlls = 0;
    for (auto& dll : dlls) {
        auto dll_path = m_binaryPath.parent_path();
        dll_path /= dll;
        if (!std::filesystem::exists(dll_path)) {
            continue;
        }
        auto out_path = dest;
        out_path /= dll;
        if (std::filesystem::exists(out_path)) {
            continue;
        }
        std::filesystem::copy_file(dll_path, out_path);
    }
}
#endif

#if defined(WITH_ENCRYPTION)
void ResourceManager::encrypt(const std::string& seed) {
    const std::string dirsToCheck[] = { "data", "modules", "mods", "layouts" };
    const std::string luaExtension = ".lua";

    std::queue<std::filesystem::path> toEncrypt;
    // you can add custom files here
    toEncrypt.push(std::filesystem::path(INIT_FILENAME));
    // config.lua is bundled inside data.zip and MUST be encrypted too: once any
    // file decrypts at runtime, m_customEncryption flips on and a plaintext
    // config.lua would then fatal ("unable to decrypt file"). Skipped if absent (dev).
    toEncrypt.push(std::filesystem::path("config.lua"));

    for (auto& dir : dirsToCheck) {
        if (!std::filesystem::exists(dir))
            continue;
        for(auto&& entry : std::filesystem::recursive_directory_iterator(std::filesystem::path(dir))) {
            if (!std::filesystem::is_regular_file(entry.path()))
                continue;
            std::string str(entry.path().string());
            // skip encryption for bot configs
            if (str.find("game_bot") != std::string::npos && str.find("default_config") != std::string::npos) {
                continue;
            }
            // skip .json: Lua reads these via g_resources.readFileContents, which is bound
            // to readFileContentsSafe (does NOT decrypt). An encrypted .json would reach
            // json.decode as ciphertext and fail (e.g. default-options.json -> client_options
            // can't load -> fatal on a fresh profile). They are data/config, not secret logic.
            if (entry.path().extension() == ".json") {
                continue;
            }
            toEncrypt.push(entry.path());
        }
    }

    uint32_t uintseed = seed.empty() ? 0 : stdext::adler32((const uint8_t*)seed.c_str(), seed.size());

    while (!toEncrypt.empty()) {
        auto it = toEncrypt.front();
        toEncrypt.pop();
        std::ifstream in_file(it, std::ios::binary);
        if (!in_file.is_open())
            continue;
        std::string buffer(std::istreambuf_iterator<char>(in_file), {});
        in_file.close();
        if (isAssetEncrypted(buffer))
            continue; // already encrypted

        // Encrypt init.lua and config.lua as SOURCE (not bytecode): both are run
        // via the boot path (dofile) and we want the decrypt->run to be a plain
        // source chunk, exactly like init.lua. Everything else becomes bytecode.
        if (it.extension().string() == luaExtension
            && it.filename().string() != INIT_FILENAME && it.filename().string() != "config.lua") {
            std::string bytecode = g_lua.generateByteCode(buffer, it.string());
            if (bytecode.length() > 10) {
                buffer = bytecode;
                g_logger.info(stdext::format("%s - lua bytecode encrypted", it.string()));
            } else {
                g_logger.info(stdext::format("%s - lua but not bytecode encrypted", it.string()));
            }
        }

        if (!encryptBuffer(buffer, uintseed)) { // already encrypted
            g_logger.info(stdext::format("%s - already encrypted", it.string()));
            continue;
        }

        std::ofstream out_file(it, std::ios::binary);
        if (!out_file.is_open())
            continue;
        out_file.write(buffer.data(), buffer.size());
        out_file.close();
        g_logger.info(stdext::format("%s - encrypted", it.string()));
    }
}
#endif 

bool ResourceManager::decryptBuffer(std::string& buffer) {
    // Too small to carry our header: cannot be one of our files. Leave as-is so
    // unencrypted (dev) assets keep loading verbatim.
    if (buffer.size() < ASSET_HEADER_LEN)
        return true;

    if (!isAssetEncrypted(buffer))
        return false; // not our format -> caller decides (plaintext or fatal)

    const uint8_t* p = reinterpret_cast<const uint8_t*>(buffer.data());
    const uint8_t* salt = p + ASSET_OFF_SALT;
    const uint8_t* nonce = p + ASSET_OFF_NONCE;
    const uint8_t* tag = p + ASSET_OFF_TAG;
    const uint8_t* aad = p + ASSET_OFF_ORIGSIZE; // 4 bytes, authenticated
    uint32_t origSize = 0;
    std::memcpy(&origSize, aad, ASSET_ORIGSIZE_LEN);

    if (origSize > ASSET_MAX_SIZE)
        return false; // crafted file -> refuse huge allocation

    uint8_t key[32];
    deriveAssetKey(salt, ASSET_SALT_LEN, key);

    std::string compressed;
    bool ok = g_crypt.aesGcmDecrypt(p + ASSET_HEADER_LEN, buffer.size() - ASSET_HEADER_LEN,
                                    key, nonce, aad, ASSET_ORIGSIZE_LEN, tag, compressed);
    std::memset(key, 0, sizeof(key));
    if (!ok)
        return false; // wrong key or tampered (GCM tag mismatch)

    std::string plain;
    if (origSize > 0) {
        plain.resize(origSize);
        uLongf destLen = origSize;
        if (uncompress(reinterpret_cast<Bytef*>(&plain[0]), &destLen,
                       reinterpret_cast<const Bytef*>(compressed.data()),
                       static_cast<uLong>(compressed.size())) != Z_OK)
            return false;
        plain.resize(destLen);
    }

    // First successful decrypt -> we are running on an encrypted build, so from
    // now on a file that fails to decrypt is a tamper and must be fatal.
    if (m_customEncryption == 0)
        m_customEncryption = 1;

    buffer = std::move(plain);
    return true;
}

void ResourceManager::decryptContainerIfNeeded(std::shared_ptr<std::vector<uint8_t>>& data)
{
    if (!data || data->size() < ASSET_HEADER_LEN)
        return;
    if (std::memcmp(data->data(), ASSET_MAGIC, ASSET_MAGIC_LEN) != 0)
        return; // plaintext zip -> mount as-is (back-compat)

    std::string s(reinterpret_cast<const char*>(data->data()), data->size());
    if (decryptBuffer(s))
        data = std::make_shared<std::vector<uint8_t>>(s.begin(), s.end());
}

#ifdef WITH_ENCRYPTION
bool ResourceManager::encryptBuffer(std::string& buffer, uint32_t /*seed*/) {
    if (isAssetEncrypted(buffer))
        return false; // already encrypted

    // 1. compress (compress-then-encrypt; the reverse would not compress).
    uLongf compLen = compressBound(static_cast<uLong>(buffer.size()));
    std::string compressed(compLen, '\0');
    if (compress(reinterpret_cast<Bytef*>(&compressed[0]), &compLen,
                 reinterpret_cast<const Bytef*>(buffer.data()),
                 static_cast<uLong>(buffer.size())) != Z_OK) {
        g_logger.error("Error while compressing");
        return false;
    }
    compressed.resize(compLen);

    // 2. random salt + nonce; derive a per-file key (never stored in the file).
    uint8_t salt[ASSET_SALT_LEN];
    uint8_t nonce[ASSET_NONCE_LEN];
    if (!g_crypt.randomBytes(salt, sizeof(salt)) || !g_crypt.randomBytes(nonce, sizeof(nonce))) {
        g_logger.error("Error while generating random bytes");
        return false;
    }
    uint8_t key[32];
    deriveAssetKey(salt, sizeof(salt), key);

    // 3. origSize is authenticated (AAD) so it cannot be tampered.
    uint32_t origSize = static_cast<uint32_t>(buffer.size());
    uint8_t aad[ASSET_ORIGSIZE_LEN];
    std::memcpy(aad, &origSize, ASSET_ORIGSIZE_LEN);

    // 4. encrypt the compressed payload.
    std::string cipher;
    uint8_t tag[ASSET_TAG_LEN];
    bool ok = g_crypt.aesGcmEncrypt(reinterpret_cast<const uint8_t*>(compressed.data()),
                                    compressed.size(), key, nonce, aad, sizeof(aad), cipher, tag);
    std::memset(key, 0, sizeof(key));
    if (!ok) {
        g_logger.error("Error while encrypting");
        return false;
    }

    // 5. assemble: magic | salt | nonce | tag | origSize | ciphertext
    std::string out;
    out.reserve(ASSET_HEADER_LEN + cipher.size());
    out.append(reinterpret_cast<const char*>(ASSET_MAGIC), ASSET_MAGIC_LEN);
    out.append(reinterpret_cast<const char*>(salt), sizeof(salt));
    out.append(reinterpret_cast<const char*>(nonce), sizeof(nonce));
    out.append(reinterpret_cast<const char*>(tag), sizeof(tag));
    out.append(reinterpret_cast<const char*>(aad), sizeof(aad));
    out.append(cipher);

    buffer = std::move(out);
    return true;
}

bool ResourceManager::packContainer(const std::string& inPath, const std::string& outPath,
                                    const std::string& baseExe)
{
    std::ifstream in(inPath, std::ios::binary);
    if (!in.is_open()) {
        g_logger.error(stdext::format("pack: unable to open input '%s'", inPath));
        return false;
    }
    std::string buffer((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    in.close();

    if (!encryptBuffer(buffer, 0)) {
        g_logger.error("pack: encryption failed (already encrypted?)");
        return false;
    }

    std::ofstream out(outPath, std::ios::binary | std::ios::trunc);
    if (!out.is_open()) {
        g_logger.error(stdext::format("pack: unable to open output '%s'", outPath));
        return false;
    }

    if (!baseExe.empty()) {
        std::ifstream be(baseExe, std::ios::binary);
        if (!be.is_open()) {
            g_logger.error(stdext::format("pack: unable to open base exe '%s'", baseExe));
            return false;
        }
        out << be.rdbuf();
        be.close();
    }

    out.write(buffer.data(), buffer.size());

    if (!baseExe.empty()) {
        uint32_t blobLen = static_cast<uint32_t>(buffer.size());
        uint8_t footer[ASSET_FOOTER_LEN];
        std::memcpy(footer, &blobLen, 4);
        std::memcpy(footer + 4, ASSET_FOOTER_MAGIC, 4);
        out.write(reinterpret_cast<const char*>(footer), ASSET_FOOTER_LEN);
    }
    out.close();
    return true;
}
#endif

void ResourceManager::setLayout(std::string layout)
{
    stdext::tolower(layout);
    stdext::replace_all(layout, "/", "");
    if (layout == "default") {
        layout = "";
    }
    if (!layout.empty() && !PHYSFS_exists((std::string("/layouts/") + layout).c_str())) {
        g_logger.error(stdext::format("Layour %s doesn't exist, using default", layout));
        return;
    }
    m_layout = layout;
}

bool ResourceManager::mountMemoryData(const std::shared_ptr<std::vector<uint8_t>>& data)
{
    if (!data || data->size() < 1024)
        return false;

    if (PHYSFS_mountMemory(data->data(), data->size(), nullptr,
                           "memory_data.zip", "/", 0)) {
        if (PHYSFS_exists(INIT_FILENAME.c_str())) {
            m_loadedFromArchive = true;
            m_memoryData = data;
            return true;
        }
        PHYSFS_unmount("memory_data.zip");
    }
    return false;
}

void ResourceManager::unmountMemoryData()
{
    if (!m_memoryData)
        return;

    if (!PHYSFS_unmount("memory_data.zip")) {
        g_logger.fatal(stdext::format("Unable to unmount memory data", PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    }
    m_memoryData = nullptr;
    m_loadedFromMemory = false;
    m_loadedFromArchive = false;
}
