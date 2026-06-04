#!/bin/bash

# Configurações de cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}===================================${NC}"
echo -e "${BLUE}Executando AstraClient com Valgrind...${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""

# Verificar se o executável existe
if [ ! -f "build_valgrind/AstraClient" ]; then
    echo -e "${RED}Erro: Executável não encontrado em build_valgrind/AstraClient${NC}"
    echo -e "Execute primeiro: ${YELLOW}./build_valgrind.sh${NC}"
    exit 1
fi

# Copiar arquivos necessários ou rodar a partir da pasta correta se necessário
# Executar o Valgrind
valgrind --tool=memcheck \
         --leak-check=full \
         --show-leak-kinds=definite \
         --track-origins=yes \
         --num-callers=50 \
         --leak-resolution=high \
         --error-limit=no \
         --expensive-definedness-checks=yes \
         --partial-loads-ok=yes \
         --log-file=valgrind-definitive.log \
         ./build_valgrind/AstraClient

echo ""
echo -e "${BLUE}===================================${NC}"
echo -e "${GREEN}Execução finalizada.${NC}"
echo -e "Logs do Valgrind salvos em: ${YELLOW}valgrind-definitive.log${NC}"
echo -e "${BLUE}===================================${NC}"
