#!/bin/bash

# Script para compilar AstraClient com AddressSanitizer (ASAN)

echo "==================================="
echo "Compilando com AddressSanitizer..."
echo "==================================="

# Criar diretório de build para ASAN
BUILD_DIR="build_asan"
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# Configurar CMake com flags do ASAN
cmake .. \
    -DCMAKE_BUILD_TYPE=Debug \
    -DUSE_LTO=OFF \
    -DCMAKE_CXX_FLAGS="-fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer -g -O1" \
    -DCMAKE_C_FLAGS="-fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer -g -O1" \
    -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address -fsanitize=undefined"

# Compilar
if cmake --build . -j2; then
    echo ""
    echo "==================================="
    echo "Compilação concluída com sucesso!"
    echo "Iniciando AstraClient com ASAN..."
    echo "==================================="
    echo ""
    
    # Executa o cliente com as flags do ASAN
    ASAN_OPTIONS=detect_leaks=1:symbolize=1:abort_on_error=1 ./AstraClient
else
    echo ""
    echo "==================================="
    echo "Erro na compilação!"
    echo "==================================="
    exit 1
fi
