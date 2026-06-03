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
#include <array>
#include <cstring>
#include <deque>
#include <queue>
#include <regex>

#include <locale>
#include <zlib.h>

#define PHYSFS_DEPRECATED
#include <physfs.h>
#ifndef __EMSCRIPTEN__
#include <zip.h>
#include <zlib.h>
#endif

ResourceManager g_resources;
static const std::string INIT_FILENAME = "init.lua";

namespace {
using PhysFSFilePtr = std::unique_ptr<PHYSFS_File, PhysFSFileDeleter>;

#ifndef __EMSCRIPTEN__
struct ZipSourceDeleter
{
    void operator()(zip_source_t* source) const
    {
        if (source)
            zip_source_free(source);
    }
};

struct ZipArchiveDeleter
{
    void operator()(zip_t* archive) const
    {
        if (archive)
            zip_discard(archive);
    }
};

struct ZipFileDeleter
{
    void operator()(zip_file_t* file) const
    {
        if (file)
            zip_fclose(file);
    }
};

using ZipSourcePtr = std::unique_ptr<zip_source_t, ZipSourceDeleter>;
using ZipArchivePtr = std::unique_ptr<zip_t, ZipArchiveDeleter>;
using ZipFilePtr = std::unique_ptr<zip_file_t, ZipFileDeleter>;
#endif
}

void ResourceManager::init(const char *argv0)
{
#if defined(WIN32)
    char fileName[255];
    GetModuleFileNameA(NULL, fileName, sizeof(fileName));
    m_binaryPath = std::filesystem::absolute(fileName);
#elif defined(ANDROID)
    // nothing
#else
    m_binaryPath = std::filesystem::absolute(argv0);    
#endif
    PHYSFS_init(argv0);
    PHYSFS_permitSymbolicLinks(1);
}

void ResourceManager::terminate()
{
    unmountMemoryData();
    PHYSFS_deinit();
}

bool ResourceManager::launchCorrect(const std::string& product, const std::string& app) { // curently works only on windows
#if !defined(ANDROID)
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

    return g_platform.spawnProcess(binary.string(), {});
#else
    return false;
#endif
}

bool ResourceManager::setupWriteDir(const std::string& product, const std::string& app) {
#ifdef ANDROID
    const char* localDir = g_androidState->activity->internalDataPath;
#else
    const char* localDir = PHYSFS_getPrefDir(product.c_str(), app.c_str());
#endif

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

#ifndef ANDROID
    m_writeDir = std::filesystem::path(std::filesystem::u8path(localDir));
#endif
    return true;
}

bool ResourceManager::setup()
{
#ifdef ANDROID
    PhysFSFilePtr file(PHYSFS_openRead("data.zip"));
    if (file) {
        auto data = std::make_shared<std::vector<uint8_t>>(PHYSFS_fileLength(file.get()));
        PHYSFS_readBytes(file.get(), data->data(), data->size());
        if (mountMemoryData(data))
            return true;
    }
#else
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
        std::filesystem::path archivePath = std::filesystem::path(std::filesystem::u8path(dir)) / "data.zip";
        if (!std::filesystem::exists(archivePath))
            continue;

        g_logger.info(stdext::format("Found data archive at '%s'", archivePath.string()));
        if (mountArchiveFile(archivePath.string()))
            return true;
    }
#endif
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

#ifndef ANDROID
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
#endif

    std::smatch regex_match;
    if (std::regex_search(fileData, regex_match, std::regex("APP_NAME[^\"]+\"([^\"]+)"))) {
        if (regex_match.size() == 2 && regex_match[1].str().length() > 0 && regex_match[1].str().length() < 30) {
            return regex_match[1].str();
        }
    }
    return "astraclient";
}

bool ResourceManager::loadDataFromSelf(bool unmountIfMounted) {
    std::shared_ptr<std::vector<uint8_t>> data = nullptr;
#ifdef ANDROID
    AAsset* file = AAssetManager_open(g_androidState->activity->assetManager, "data.zip", AASSET_MODE_BUFFER);
    if (!file)
        g_logger.fatal("Can't open data.zip from assets");
    data = std::make_shared<std::vector<uint8_t>>(AAsset_getLength(file));
    AAsset_read(file, data->data(), data->size());
    AAsset_close(file);
#else
    std::ifstream file(m_binaryPath.string(), std::ios::binary);
    if (!file.is_open())
        return false;
    file.seekg(0, std::ios_base::end);
    std::streamoff size = file.tellg();
    file.seekg(0, std::ios_base::beg);
    if (size < 1024 || size > 1024 * 1024 * 128) {
        return false;
    }

    constexpr std::size_t chunkSize = 1024 * 1024;
    constexpr std::size_t overlap = 32;
    std::vector<uint8_t> scanBuffer(chunkSize + overlap);
    std::size_t carry = 0;
    std::size_t bufferStart = 0;
    std::size_t zipOffset = 0;
    bool foundZip = false;

    while (file && !foundZip) {
        file.read(reinterpret_cast<char*>(scanBuffer.data() + carry), chunkSize);
        const std::size_t bytesRead = static_cast<std::size_t>(file.gcount());
        const std::size_t total = carry + bytesRead;

        for (std::size_t i = 0; i + 26 < total; ++i) {
            if (scanBuffer[i] == 0x50 && scanBuffer[i + 1] == 0x4b &&
                scanBuffer[i + 2] == 0x03 && scanBuffer[i + 3] == 0x04 &&
                scanBuffer[i + 4] == 0x14) {
                uint32_t compSize = 0;
                uint32_t decompSize = 0;
                std::memcpy(&compSize, scanBuffer.data() + i + 18, sizeof(compSize));
                std::memcpy(&decompSize, scanBuffer.data() + i + 22, sizeof(decompSize));
                if (compSize < 1024 * 1024 * 512 && decompSize < 1024 * 1024 * 512) {
                    zipOffset = bufferStart + i;
                    foundZip = true;
                    break;
                }
            }
        }

        if (foundZip || bytesRead == 0)
            break;

        carry = std::min<std::size_t>(total, overlap);
        std::memmove(scanBuffer.data(), scanBuffer.data() + total - carry, carry);
        bufferStart += total - carry;
    }

    if (foundZip) {
        const std::size_t zipSize = static_cast<std::size_t>(size) - zipOffset;
        data = std::make_shared<std::vector<uint8_t>>(zipSize);
        file.clear();
        file.seekg(zipOffset, std::ios_base::beg);
        file.read(reinterpret_cast<char*>(data->data()), data->size());
        if (static_cast<std::size_t>(file.gcount()) != data->size())
            data = nullptr;
    }

#endif

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

    PhysFSFilePtr file(PHYSFS_openRead(fullPath.c_str()));
    if(!file)
        stdext::throw_exception(stdext::format("unable to open file '%s': %s", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

    PHYSFS_sint64 fileSize = PHYSFS_fileLength(file.get());
    if (fileSize < 0)
        stdext::throw_exception(stdext::format("unable to get file size '%s': %s", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    std::string buffer(static_cast<std::size_t>(fileSize), 0);
    if (fileSize > 0 && PHYSFS_readBytes(file.get(), buffer.data(), fileSize) != fileSize)
        stdext::throw_exception(stdext::format("unable to read file '%s': %s", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

    if (safe) {
        return buffer;
    }

    // skip decryption for bot configs
    if (fullPath.find("/bot/") != std::string::npos) {
        return buffer;
    }

    static std::string unencryptedExtensions[] = { ".otml", ".otmm", ".dmp", ".log", ".txt", ".dll", ".exe", ".zip" };

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

    if (fileContent.empty()) {
        PhysFSFilePtr file(PHYSFS_openRead(fullPath.c_str()));
        if (!file)
            stdext::throw_exception(stdext::format("unable to open file '%s': %s", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

        PHYSFS_sint64 rawFileSize = PHYSFS_fileLength(file.get());
        if (rawFileSize <= 0)
            return false;
        int fileSize = std::min<int>(10, static_cast<int>(rawFileSize));
        fileContent.resize(fileSize);
        PHYSFS_readBytes(file.get(), fileContent.data(), fileSize);
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
    PhysFSFilePtr file(PHYSFS_openWrite(fileName.c_str()));
    if(!file) {
        g_logger.error(stdext::format("unable to open file for writing '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
        return false;
    }

    if (PHYSFS_writeBytes(file.get(), (void*)data, size) != size) {
        g_logger.error(stdext::format("unable to write file '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
        return false;
    }
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
    PhysFSFilePtr file(PHYSFS_openRead(fullPath.c_str()));
    if (!file)
        stdext::throw_exception(stdext::format("unable to open file '%s': %s", fullPath, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    return std::make_shared<FileStream>(fullPath, file.release(), false);
}

FileStreamPtr ResourceManager::appendFile(const std::string& fileName)
{
    PhysFSFilePtr file(PHYSFS_openAppend(fileName.c_str()));
    if(!file)
        stdext::throw_exception(stdext::format("failed to append file '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    return std::make_shared<FileStream>(fileName, file.release(), true);
}

FileStreamPtr ResourceManager::createFile(const std::string& fileName)
{
    PhysFSFilePtr file(PHYSFS_openWrite(fileName.c_str()));
    if(!file)
        stdext::throw_exception(stdext::format("failed to create file '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    return std::make_shared<FileStream>(fileName, file.release(), true);
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
    PhysFSFilePtr file(PHYSFS_openRead(path.c_str()));
    if(!file)
        return "";

    PHYSFS_sint64 fileSize = PHYSFS_fileLength(file.get());
    if (fileSize < 0)
        return "";
    std::string buffer(static_cast<std::size_t>(fileSize), 0);
    if (fileSize > 0 && PHYSFS_readBytes(file.get(), buffer.data(), fileSize) != fileSize)
        return "";

    return g_crypt.crc32(buffer, false);
}

std::map<std::string, std::string> ResourceManager::filesChecksums()
{
    std::map<std::string, std::string> ret;
#ifndef __EMSCRIPTEN__
    if (!m_memoryData && m_mountedArchivePath.empty())
        return ret;

    zip_stat_t file_stat;
    zip_error_t error;
    zip_error_init(&error);
    zip_stat_init(&file_stat);

    ZipSourcePtr src;
    ZipArchivePtr za;
    if (m_memoryData) {
        src.reset(zip_source_buffer_create(m_memoryData->data(), m_memoryData->size(), 0, &error));
        if (!src)
            g_logger.fatal(stdext::format("can't create source: %s", zip_error_strerror(&error)));

        za.reset(zip_open_from_source(src.get(), ZIP_RDONLY, &error));
        if (!za)
            g_logger.fatal(stdext::format("can't open zip from source: %s", zip_error_strerror(&error)));
        src.release();
    } else {
        za.reset(zip_open(m_mountedArchivePath.c_str(), ZIP_RDONLY, nullptr));
        if (!za)
            g_logger.fatal(stdext::format("can't open zip archive: %s", m_mountedArchivePath));
    }

    zip_int64_t entries = zip_get_num_entries(za.get(), 0);
    for (zip_int64_t entry_idx = 0; entry_idx < entries; entry_idx++) {
        if (zip_stat_index(za.get(), entry_idx, 0, &file_stat)) {
            g_logger.fatal(stdext::format("error stat-ing file at index %i: %s",
                    (int)(entry_idx), zip_strerror(za.get())));
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

    if (zip_close(za.get()) < 0)
        g_logger.fatal(stdext::format("can't close zip archive: %s", zip_strerror(za.get())));
    za.release();
    zip_error_fini(&error);
#endif
    return ret;
}

std::string ResourceManager::selfChecksum() {
#ifdef ANDROID
    return "";
#else
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
#endif
}

void ResourceManager::updateData(const std::set<std::string>& files, bool reMount) {
#if !defined(__EMSCRIPTEN__)
    if (!m_loadedFromArchive)
        g_logger.fatal("Client can be updated only when running from zip archive");

    g_logger.info(stdext::format("Updating client, %i files", files.size()));

    zip_error_t error;
    zip_error_init(&error);

    ZipSourcePtr src(zip_source_buffer_create(0, 0, 0, &error));
    if (!src)
        return g_logger.fatal(stdext::format("can't create source: %s", zip_error_strerror(&error)));
    zip_source_keep(src.get());

    ZipArchivePtr za(zip_open_from_source(src.get(), ZIP_TRUNCATE, &error));
    if (!za)
        return g_logger.fatal(stdext::format("can't open zip from source: %s", zip_error_strerror(&error)));

    zip_error_fini(&error);

    std::vector<std::unique_ptr<uint8_t[]>> ownedSourceBuffers;
    std::vector<std::string> downloadedFilesToClear;
    for (auto fileName : files) {
        if (fileName.empty())
            continue;
        if (fileName.size() > 1 && fileName[0] == '/')
            fileName = fileName.substr(1);
        zip_source_t* s;
        auto dFile = g_http.getFile(fileName);
        if (dFile) {
            if ((s = zip_source_buffer(za.get(), dFile->body.data(), dFile->body.size(), 0)) == NULL)
                return g_logger.fatal(stdext::format("can't create source buffer: %s", zip_strerror(za.get())));
            downloadedFilesToClear.push_back(fileName);
        } else {
            PhysFSFilePtr file(PHYSFS_openRead((std::string("/") + fileName).c_str()));
            if (!file)
                g_logger.fatal(stdext::format("unable to open file '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

            PHYSFS_sint64 fileSize = PHYSFS_fileLength(file.get());
            if (fileSize < 0)
                return g_logger.fatal(stdext::format("unable to get file size '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

            auto buffer = std::make_unique<uint8_t[]>(static_cast<std::size_t>(fileSize));
            if (fileSize > 0 && PHYSFS_readBytes(file.get(), buffer.get(), fileSize) != fileSize)
                return g_logger.fatal(stdext::format("unable to read file '%s': %s", fileName, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

            if ((s = zip_source_buffer(za.get(), buffer.get(), static_cast<zip_uint64_t>(fileSize), 0)) == NULL)
                return g_logger.fatal(stdext::format("can't create source buffer: %s", zip_strerror(za.get())));
            ownedSourceBuffers.push_back(std::move(buffer));
        }

        int fileIndex = zip_file_add(za.get(), fileName.c_str(), s, ZIP_FL_OVERWRITE);
        if(fileIndex < 0)
            return g_logger.fatal(stdext::format("can't add file %s to zip archive: %s", fileName, zip_strerror(za.get())));
        if (zip_set_file_compression(za.get(), fileIndex, ZIP_CM_DEFLATE, 1) != 0)
            return g_logger.fatal("Can't set file compression level");
    }

    if (zip_close(za.get()) < 0)
        return g_logger.fatal(stdext::format("can't close zip archive: %s", zip_strerror(za.get())));
    za.release();

    zip_stat_t zst;
    if (zip_source_stat(src.get(), &zst) < 0)
        return g_logger.fatal(stdext::format("can't stat source: %s", zip_error_strerror(zip_source_error(src.get()))));
    
    size_t zipSize = zst.size;    

    if (zip_source_open(src.get()) < 0)
        return g_logger.fatal(stdext::format("can't open source: %s", zip_error_strerror(zip_source_error(src.get()))));

    PhysFSFilePtr file(PHYSFS_openWrite("data.zip"));
    if (!file)
        return g_logger.fatal(stdext::format("can't open data.zip for writing: %s", PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

    static const size_t CHUNK_SIZE = 1024 * 1024;
    std::vector<char> chunk(CHUNK_SIZE);
    while (zipSize > 0) {
        size_t currentChunk = std::min<size_t>(zipSize, CHUNK_SIZE);
        if ((zip_uint64_t)zip_source_read(src.get(), chunk.data(), currentChunk) < currentChunk)
            return g_logger.fatal(stdext::format("can't read data from source: %s", zip_error_strerror(zip_source_error(src.get()))));
        if (PHYSFS_writeBytes(file.get(), chunk.data(), currentChunk) != currentChunk)
            return g_logger.fatal(stdext::format("can't write data.zip: %s", PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
        zipSize -= currentChunk;
    }

    zip_source_close(src.get());

    for (const std::string& fileName : downloadedFilesToClear)
        g_http.clearDownloadedFile(fileName);

    if (reMount) {
        unmountMemoryData();
#ifdef ANDROID
        PhysFSFilePtr remountFile(PHYSFS_openRead("data.zip"));
        if (!remountFile)
            g_logger.fatal(stdext::format("Can't open new data.zip"));

        PHYSFS_sint64 size = PHYSFS_fileLength(remountFile.get());
        if (size < 1024)
            g_logger.fatal(stdext::format("New data.zip is invalid"));

        auto data = std::make_shared<std::vector<uint8_t>>(static_cast<std::size_t>(size));
        if (PHYSFS_readBytes(remountFile.get(), data->data(), data->size()) != size)
            g_logger.fatal(stdext::format("Can't read new data.zip"));
        if (!mountMemoryData(data)) {
            g_logger.fatal("Error while mounting new data.zip");
        }
#else
        std::filesystem::path archivePath = m_writeDir / "data.zip";
        if (!mountArchiveFile(archivePath.string())) {
            g_logger.fatal("Error while mounting new data.zip");
        }
#endif
    }
#else
    g_logger.fatal("updateData is unsupported");
#endif
}

void ResourceManager::updateExecutable(std::string fileName)
{
#if defined(ANDROID)
    g_logger.fatal("Executable cannot be updated on android or in free version");
#else
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
    PhysFSFilePtr file(PHYSFS_openWrite(newBinary.c_str()));
    if (!file)
        return g_logger.fatal(stdext::format("can't open %s for writing: %s", newBinary, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    if (PHYSFS_writeBytes(file.get(), dFile->body.data(), dFile->body.size()) != dFile->body.size())
        return g_logger.fatal(stdext::format("can't write %s: %s", newBinary, PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));

    std::filesystem::path newBinaryPath(std::filesystem::u8path(PHYSFS_getWriteDir()));
#if defined(WIN32)
    installDlls(newBinaryPath);
#endif
#endif
}

std::string ResourceManager::createArchive(const std::map<std::string, std::string>& files)
{
#ifdef __EMSCRIPTEN__
    return "";
#else
    if (files.empty()) return "";

    zip_error_t error;
    zip_error_init(&error);

    ZipSourcePtr src(zip_source_buffer_create(0, 0, 0, &error));
    if (!src)
        stdext::throw_exception(stdext::format("can't create source: %s", zip_error_strerror(&error)));
    zip_source_keep(src.get());

    ZipArchivePtr za(zip_open_from_source(src.get(), ZIP_TRUNCATE, &error));
    if (!za)
        stdext::throw_exception(stdext::format("can't open zip from source: %s", zip_error_strerror(&error)));

    zip_error_fini(&error);

    for (auto& file : files) {
        if (file.first.empty() || file.second.empty())
            continue;

        zip_source_t* s;
        if ((s = zip_source_buffer(za.get(), file.second.data(), file.second.size(), 0)) == NULL)
            stdext::throw_exception(stdext::format("can't create source buffer: %s", zip_strerror(za.get())));

        std::string fileName = file.first;
        if (fileName.size() > 1 && fileName[0] == '/')
            fileName = fileName.substr(1);

        int fileIndex = zip_file_add(za.get(), fileName.c_str(), s, ZIP_FL_OVERWRITE);
        if (fileIndex < 0)
            stdext::throw_exception(stdext::format("can't add file %s to zip archive: %s", fileName, zip_strerror(za.get())));
//        if (zip_set_file_compression(za, fileIndex, ZIP_CM_DEFLATE, 1) != 0)
//            stdext::throw_exception("Can't set file compression level");
    }

    if (zip_close(za.get()) < 0)
        stdext::throw_exception(stdext::format("can't close zip archive: %s", zip_strerror(za.get())));
    za.release();

    zip_stat_t zst;
    if (zip_source_stat(src.get(), &zst) < 0)
        stdext::throw_exception(stdext::format("can't stat source: %s", zip_error_strerror(zip_source_error(src.get()))));

    size_t zipSize = zst.size;

    if (zip_source_open(src.get()) < 0)
        stdext::throw_exception(stdext::format("can't open source: %s", zip_error_strerror(zip_source_error(src.get()))));

    std::string data(zipSize, '\0');
    if ((zip_uint64_t)zip_source_read(src.get(), data.data(), data.size()) != data.size())
        stdext::throw_exception(stdext::format("can't read data from source: %s", zip_error_strerror(zip_source_error(src.get()))));

    zip_source_close(src.get());

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

    zip_stat_t file_stat;
    zip_error_t error;
    zip_error_init(&error);
    zip_stat_init(&file_stat);

    ZipSourcePtr src(zip_source_buffer_create(dataOrPath.c_str(), dataOrPath.size(), 0, &error));
    if (!src)
        stdext::throw_exception(stdext::format("unpackArchive: can't create source: %s", zip_error_strerror(&error)));

    ZipArchivePtr za(zip_open_from_source(src.get(), ZIP_RDONLY, &error));
    if (!za)
        stdext::throw_exception(stdext::format("unpackArchive: can't open zip from source: %s", zip_error_strerror(&error)));
    src.release();

    zip_int64_t entries = zip_get_num_entries(za.get(), 0);
    for (zip_int64_t entry_idx = 0; entry_idx < entries; entry_idx++) {
        if (zip_stat_index(za.get(), entry_idx, 0, &file_stat)) {
            stdext::throw_exception(stdext::format("unpackArchive: error stat-ing file at index %i: %s",
                                          (int)(entry_idx), zip_strerror(za.get())));
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

        ZipFilePtr file(zip_fopen_index(za.get(), entry_idx, 0));
        if(!file)
            stdext::throw_exception(stdext::format("can't open file from zip archive: %s - %s", name, zip_strerror(za.get())));
        std::string buffer(file_stat.size, '\0');
        const zip_int64_t bytesRead = zip_fread(file.get(), buffer.data(), buffer.size());
        const zip_int64_t expectedSize = static_cast<zip_int64_t>(buffer.size());
        if (bytesRead != expectedSize) {
            stdext::throw_exception(stdext::format("can't read file from zip archive: %s - expected %lld bytes, read %lld: %s",
                                                   name, static_cast<long long>(expectedSize),
                                                   static_cast<long long>(bytesRead), zip_strerror(za.get())));
        }
        ret[name] = std::move(buffer);
    }

    if (zip_close(za.get()) < 0)
        stdext::throw_exception(stdext::format("can't close zip archive: %s", zip_strerror(za.get())));
    za.release();
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

#if defined(WITH_ENCRYPTION) && !defined(ANDROID)
void ResourceManager::encrypt(const std::string& seed) {
    const std::string dirsToCheck[] = { "data", "modules", "mods", "layouts" };
    const std::string luaExtension = ".lua";

    g_logger.setLogFile("encryption.log");
    g_logger.info("----------------------");

    std::queue<std::filesystem::path> toEncrypt;
    // you can add custom files here
    toEncrypt.push(std::filesystem::path(INIT_FILENAME));

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
            toEncrypt.push(entry.path());
        }
    }

    bool encryptForAndroid = seed.find("android") != std::string::npos;
    uint32_t uintseed = seed.empty() ? 0 : stdext::adler32((const uint8_t*)seed.c_str(), seed.size());

    while (!toEncrypt.empty()) {
        auto it = toEncrypt.front();
        toEncrypt.pop();
        std::ifstream in_file(it, std::ios::binary);
        if (!in_file.is_open())
            continue;
        std::string buffer(std::istreambuf_iterator<char>(in_file), {});
        in_file.close();
        if (buffer.size() >= 4 && buffer.substr(0, 4).compare("ENC3") == 0)
            continue; // already encrypted

        if (!encryptForAndroid && it.extension().string() == luaExtension && it.filename().string() != INIT_FILENAME) {
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
    if (buffer.size() < 5)
        return true;

    if (buffer.substr(0, 4).compare("ENC3") != 0) {
        return false;
    }

    uint64_t key = *(uint64_t*)&buffer[4];
    uint32_t compressed_size = *(uint32_t*)&buffer[12];
    uint32_t size = *(uint32_t*)&buffer[16];
    uint32_t adler = *(uint32_t*)&buffer[20];

    if (compressed_size < buffer.size() - 24)
        return false;

    g_crypt.bdecrypt((uint8_t*)&buffer[24], compressed_size, key);
    std::string new_buffer;
    new_buffer.resize(size);
    unsigned long new_buffer_size = new_buffer.size();
    if (uncompress((uint8_t*)new_buffer.data(), &new_buffer_size, (uint8_t*)&buffer[24], compressed_size) != Z_OK)
        return false;

    uint32_t addlerCheck = stdext::adler32((const uint8_t*)&new_buffer[0], size);
    if (adler != addlerCheck) {
        uint32_t cseed = adler ^ addlerCheck;
        if (m_customEncryption == 0) {
            m_customEncryption = cseed;
        }
        if ((addlerCheck ^ m_customEncryption) != adler) {
            return false;
        }
    }

    buffer = new_buffer;
    return true;
}

#ifdef WITH_ENCRYPTION
bool ResourceManager::encryptBuffer(std::string& buffer, uint32_t seed) {
    if (buffer.size() >= 4 && buffer.substr(0, 4).compare("ENC3") == 0)
        return false; // already encrypted

    // not random beacause it would require to update to new files each time
    int64_t key = stdext::adler32((const uint8_t*)&buffer[0], buffer.size());
    key <<= 32;
    key += stdext::adler32((const uint8_t*)&buffer[0], buffer.size() / 2);

    std::string new_buffer(24 + buffer.size() * 2, '0');
    new_buffer[0] = 'E';
    new_buffer[1] = 'N';
    new_buffer[2] = 'C';
    new_buffer[3] = '3';

    unsigned long dstLen = new_buffer.size() - 24;
    if (compress((uint8_t*)&new_buffer[24], &dstLen, (const uint8_t*)buffer.data(), buffer.size()) != Z_OK) {
        g_logger.error("Error while compressing");
        return false;
    }
    new_buffer.resize(24 + dstLen);

    *(int64_t*)&new_buffer[4] = key;
    *(uint32_t*)&new_buffer[12] = (uint32_t)dstLen;
    *(uint32_t*)&new_buffer[16] = (uint32_t)buffer.size();
    *(uint32_t*)&new_buffer[20] = ((uint32_t)stdext::adler32((const uint8_t*)&buffer[0], buffer.size())) ^ seed;

    g_crypt.bencrypt((uint8_t*)&new_buffer[0] + 24, new_buffer.size() - 24, key);
    buffer = new_buffer;
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

bool ResourceManager::mountArchiveFile(const std::string& archivePath)
{
    if (archivePath.empty())
        return false;

    if (PHYSFS_mount(archivePath.c_str(), "/", 0)) {
        if (PHYSFS_exists(INIT_FILENAME.c_str())) {
            m_loadedFromArchive = true;
            m_loadedFromMemory = false;
            m_mountedArchivePath = archivePath;
            m_memoryData = nullptr;
            return true;
        }
        PHYSFS_unmount(archivePath.c_str());
    }
    return false;
}

bool ResourceManager::mountMemoryData(const std::shared_ptr<std::vector<uint8_t>>& data)
{
    if (!data || data->size() < 1024)
        return false;

    if (PHYSFS_mountMemory(data->data(), data->size(), nullptr,
                           "memory_data.zip", "/", 0)) {
        if (PHYSFS_exists(INIT_FILENAME.c_str())) {
            m_loadedFromArchive = true;
            m_mountedArchivePath.clear();
            m_memoryData = data;
            return true;
        }
        PHYSFS_unmount("memory_data.zip");
    }
    return false;
}

void ResourceManager::unmountMemoryData()
{
    if (!m_memoryData && m_mountedArchivePath.empty())
        return;

    if (m_memoryData) {
        if (!PHYSFS_unmount("memory_data.zip")) {
            g_logger.fatal(stdext::format("Unable to unmount memory data: %s", PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
        }
    } else if (!PHYSFS_unmount(m_mountedArchivePath.c_str())) {
        g_logger.fatal(stdext::format("Unable to unmount archive data: %s", PHYSFS_getErrorByCode(PHYSFS_getLastErrorCode())));
    }
    m_memoryData = nullptr;
    m_mountedArchivePath.clear();
    m_loadedFromMemory = false;
    m_loadedFromArchive = false;
}
