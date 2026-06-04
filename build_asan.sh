#!/bin/bash
set -e

# Configurações de cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== AstraClient Linux ASAN Build (C++23 + AddressSanitizer) ===${NC}"

# Detectar número de cores/threads do processador
CORES=$(nproc 2>/dev/null || echo 4)
echo -e "${GREEN}Usando ${CORES} threads para compilação.${NC}"

# Criar diretório de build para ASAN e limpar cache antigo se necessário
BUILD_DIR="build_asan"
mkdir -p $BUILD_DIR

# Verificar se existe vcpkg local ou no sistema
VCPKG_PARAMS=""
if [ -d "vcpkg" ]; then
    echo -e "${YELLOW}Vcpkg local detectado.${NC}"
    VCPKG_PARAMS="-DCMAKE_TOOLCHAIN_FILE=vcpkg/scripts/buildsystems/vcpkg.cmake"
elif [ -n "$VCPKG_ROOT" ]; then
    echo -e "${YELLOW}VCPKG_ROOT detectado em: $VCPKG_ROOT${NC}"
    VCPKG_PARAMS="-DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
else
    echo -e "${YELLOW}Aviso: vcpkg não encontrado. Compilando com as dependências do sistema.${NC}"
fi

# Corrigir índice do physfs automaticamente (evita erro de linker)
PHYSFS_LIB="/usr/lib/x86_64-linux-gnu/libphysfs.a"
if [ -f "$PHYSFS_LIB" ]; then
    echo -e "${YELLOW}Corrigindo índice do libphysfs.a...${NC}"
    sudo ranlib "$PHYSFS_LIB" 2>/dev/null || true
fi

# Configurar o CMake habilitando Unity Build, C++23 e AddressSanitizer
echo -e "${BLUE}Configurando CMake...${NC}"
cmake -B $BUILD_DIR -S . \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_STANDARD=23 \
    -DCMAKE_CXX_STANDARD_REQUIRED=ON \
    -DCMAKE_UNITY_BUILD=ON \
    -DCMAKE_UNITY_BUILD_BATCH_SIZE=0 \
    -DUSE_LTO=OFF \
    -DCMAKE_CXX_FLAGS="-fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer -g -O1" \
    -DCMAKE_C_FLAGS="-fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer -g -O1" \
    -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address -fsanitize=undefined" \
    $VCPKG_PARAMS

# Compilar o client
echo -e "${BLUE}Compilando o projeto com ASAN...${NC}"
if cmake --build $BUILD_DIR -- -j$CORES; then
    echo -e "${GREEN}=== Compilação com ASAN Concluída com Sucesso! ===${NC}"
    echo -e "Para executar o client com ASAN via WSL, use: ${YELLOW}./run_asan.sh${NC}"
else
    echo -e "${RED}Erro na compilação com ASAN!${NC}"
    exit 1
fi

