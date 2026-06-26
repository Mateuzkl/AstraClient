-- Cavebot Walker Module
-- Entry point - carrega o novo sistema de cavebot baseado na referencia game_bot
--
-- ESTRUTURA NOVA:
--   cavebots/init.lua       - Entry point que carrega todos os modulos
--   cavebots/config.lua     - Sistema de configuracao extensivel
--   cavebots/walking.lua    - Movimento baseado na referencia (expectedDirs)
--   cavebots/actions.lua    - Sistema de acoes registraveis
--   cavebots/core.lua       - Loop principal macro(20ms) + API publica
--   cavebots/recorder.lua   - Gravador automatico de waypoints
--   cavebots/extensions/    - Extensoes (supplies, lure)
--   cavebots/utils.lua      - Funcoes utilitarias (mantido)
--   cavebots/libs.lua       - IDs de tiles bloqueados (mantido)
--
-- ARQUIVOS ANTIGOS (podem ser removidos):
--   cavebots/main.lua       - Substituido por core.lua + walking.lua
--   cavebots/move.lua       - Substituido por walking.lua

-- Carrega o modulo principal que inicializa tudo
dofile("/game_helper/cavebots/init.lua")

-- CaveBot e cavebotWalker ja estao disponiveis globalmente apos o dofile
