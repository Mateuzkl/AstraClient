#!/bin/bash
set -e

# Configurações de cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== AstraClient Linux Valgrind Build (C++23 + Debug Symbols) ===${NC}"

# Detectar número de cores/threads do processador
CORES=$(nproc 2>/dev/null || echo 4)
echo -e "${GREEN}Usando ${CORES} threads para compilação.${NC}"

# Criar diretório de build para Valgrind
BUILD_DIR="build_valgrind"
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

# Configurar o CMake em modo RelWithDebInfo (otimizado + símbolos para rodar rápido no Valgrind)
echo -e "${BLUE}Configurando CMake...${NC}"
cmake -B $BUILD_DIR -S . \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_STANDARD=23 \
    -DCMAKE_CXX_STANDARD_REQUIRED=ON \
    -DCMAKE_UNITY_BUILD=ON \
    -DCMAKE_UNITY_BUILD_BATCH_SIZE=0 \
    -DUSE_LTO=OFF \
    $VCPKG_PARAMS

# Compilar o client
echo -e "${BLUE}Compilando o projeto para Valgrind...${NC}"
if cmake --build $BUILD_DIR -- -j$CORES; then
    echo -e "${GREEN}=== Compilação para Valgrind Concluída com Sucesso! ===${NC}"
    echo -e "Para executar o client com Valgrind, use: ${YELLOW}./run_valgrind.sh${NC}"
else
    echo -e "${RED}Erro na compilação!${NC}"
    exit 1
fi
