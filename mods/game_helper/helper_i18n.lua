-- ============================================================================
-- HELPER I18N - Local translation system for game_helper module
-- Does NOT affect global client language. Only translates helper UI texts.
-- ============================================================================

local helperLanguage = "en" -- default language

-- PT-BR dictionary: English key -> Portuguese translation
-- IMPORTANTE: Nao usar acentos, cedilha ou caracteres especiais ABNT2
local dictPtbr = {
  -- Universal Buttons
  ["Ok"] = "OK",
  ["Cancel"] = "Cancelar",
  ["Close"] = "Fechar",
  ["Save"] = "Salvar",
  ["Delete"] = "Deletar",
  ["Load"] = "Carregar",
  ["Clear"] = "Limpar",
  ["Rename"] = "Renomear",
  ["Edit"] = "Editar",
  ["Duplicate"] = "Duplicar",
  ["Remove"] = "Remover",
  ["Remove Item"] = "Remover Item",
  ["Select Item"] = "Selecionar Item",
  ["Assign ID"] = "Atribuir ID",
  ["Assign List"] = "Atribuir Lista",
  ["Unequip"] = "Desequipar",
  ["Equip"] = "Equipar",
  ["Browse..."] = "Procurar...",
  ["Open Folder"] = "Abrir Pasta",
  ["Reload"] = "Recarregar",
  ["Import"] = "Importar",
  ["Add"] = "Adicionar",
  ["Pause"] = "Pausar",
  ["Play"] = "Play",
  ["Stop"] = "Parar",
  ["Record"] = "Gravar",
  ["Move Up"] = "Mover para Cima",
  ["Move Down"] = "Mover para Baixo",
  ["New"] = "Novo",
  ["Select Rune"] = "Selecionar Runa",
  ["Set Key"] = "Definir Tecla",
  ["Accept"] = "Aceitar",

  -- Waypoint Creator
  ["Waypoint Creator"] = "Criador de Waypoints",
  ["Waypoint Type:"] = "Tipo de Waypoint:",
  ["Direction:"] = "Direcao:",
  ["Waypoint Mode:"] = "Modo do Waypoint:",
  ["Replace"] = "Substituir",
  ["Insert"] = "Inserir",
  ["Node"] = "Node",
  ["Stand"] = "Stand",
  ["Rope"] = "Rope",
  ["Hole"] = "Hole",
  ["Use"] = "Usar",
  ["Lever"] = "Alavanca",
  ["Label"] = "Label",
  ["Goto"] = "Ir Para",
  ["Check Supply"] = "Verificar Supplies",
  ["Wait Stamina"] = "Esperar Stamina",
  ["Buy Supply"] = "Comprar Supply",
  ["Sell Loot"] = "Vender Loot",
  ["Wait Delay"] = "Esperar Delay",
  ["STOP TO KILL"] = "PARAR PRA MATAR",
  ["Special Area"] = "Area Especial",
  ["Special List"] = "Lista Especial",

  -- Check Supply Popup
  ["Check Supply - Verify Supplies"] = "Check Supply - Verificar Supplies",
  ["Checks all configured supplies and jumps to\na label based on the verification result."] = "Verifica todos os supplies configurados e salta para\num label baseado no resultado da verificacao.",
  ["Label when HAS supply (all OK):"] = "Label quando TEM supply (todos OK):",
  ["Label when NO supply (missing some):"] = "Label quando NAO TEM supply (falta algum):",
  ["The Check Supply checks if all configured supplies are above the minimum. If yes, goes to the 'has supply' label. If not, goes to the 'no supply' label."] = "O Check Supply verifica se todos os supplies configurados estao acima do minimo. Se sim, vai para o label 'tem supply'. Se nao, vai para o label 'sem supply'.",
  ["Type the label name to jump to when all supplies are OK (quantity >= minimum)."] = "Digite o nome do label para onde saltar quando todos os supplies estiverem OK (quantidade >= minimo).",
  ["Type the label name to jump to when some supply is below the minimum."] = "Digite o nome do label para onde saltar quando algum supply estiver abaixo do minimo.",
  ["Check Supply labels updated"] = "Labels do Check Supply atualizados",

  -- Tab Names & Module Headers
  ["Healing"] = "Cura",
  ["Equipment"] = "Equipamento",
  ["Tank Mode"] = "Modo Tanque",
  ["Equipments"] = "Equipamentos",
  ["Targeting"] = "Targeting",
  ["Shooter"] = "Shooter",
  ["Cavebot"] = "Cavebot",
  ["Timer"] = "Temporizador",
  ["Alarms"] = "Alarmes",
  ["Tools"] = "Ferramentas",
  ["Ammo"] = "Municao",
  ["Party"] = "Party",
  ["Extras"] = "Extras",
  ["Settings"] = "Configuracoes",
  ["General"] = "Geral",
  ["Profiles"] = "Perfis",
  ["Icon Stats"] = "Icon Stats",
  ["Helper"] = "Assistente",

  -- Module Titles
  ["Auto Healing Helper"] = "Assistente de Cura Automatica",
  ["Magic Shield Helper"] = "Assistente de Escudo Magico",
  ["Energy Ring Helper"] = "Assistente de Anel de Energia",
  ["Equipment Swap"] = "Troca de Equipamento",
  ["Equip Helper"] = "Assistente de Equipamento",
  ["Auto SSA"] = "SSA Automatico",
  ["Auto Might Ring"] = "Anel de Poder Automatico",
  ["Magic Shooter Helper"] = "Assistente de Atirador Magico",
  ["Rune Shooter Helper"] = "Assistente de Atirador de Runa",
  ["Auto Target"] = "Alvo Automatico",
  ["Level Spy"] = "Espiao de Nivel",
  ["Auto Follow"] = "Seguir Automatico",
  ["Shooter Helper"] = "Assistente de Atirador",
  ["Ammo & Rune Helper"] = "Assistente de Municao e Runa",
  ["Tools Helper"] = "Assistente de Ferramentas",
  ["Utility Helper"] = "Assistente de Utilidade",

  -- Healing
  ["Enable"] = "Ativar",
  ["Heal Party"] = "Curar Grupo",
  ["Heal Guild"] = "Curar Guilda",
  ["Heal Screen"] = "Curar na Tela",
  ["Sio Spell"] = "Feitico Sio",
  ["Gran Sio Spell"] = "Feitico Gran Sio",
  ["Spell Healing"] = "Cura por Feitico",
  ["Potion Healing"] = "Cura por Pocao",
  ["Heal Settings"] = "Configuracoes de Cura",
  ["Healing Rules"] = "Regras de Cura",
  ["Add Healing"] = "Adicionar Cura",
  ["Priority"] = "Prioridade",
  ["Type"] = "Tipo",
  ["Name"] = "Nome",
  ["Rule"] = "Regra",
  ["Enable All Friend Healing"] = "Ativar Cura de Amigo Para Todos",
  ["Enable Tio Sio"] = "Ativar Tio Sio",
  ["Friend List"] = "Lista de Amigos",
  ["Friends (one per line):"] = "Amigos (um por linha):",
  ["Heal Friend"] = "Curar Amigo",

  -- Equipment
  ["Tank Amulet"] = "Amuleto de Tanque",
  ["Tank Ring"] = "Anel de Tanque",
  ["Enable Tank Mode"] = "Ativar Modo Tanque",
  ["Keep Energy Ring"] = "Manter Anel de Energia",
  ["Swap Rules"] = "Regras de Troca",
  ["Add Equipment"] = "Adicionar Equipamento",

  -- Targeting & Shooter
  ["Enable Shooter Helper"] = "Ativar Assistente de Atirador",
  ["Shooter Rules"] = "Regras de Atirador",
  ["Add Shooter Rule"] = "Adicionar Regra de Atirador",
  ["Add Magic Shooter"] = "Adicionar Atirador Magico",
  ["Select Attack Mode"] = "Selecionar Modo de Ataque",
  ["Spell"] = "Feitico",
  ["Creatures"] = "Criaturas",
  ["Need Target"] = "Necessita Alvo",
  ["Prioritize Rune over Potion"] = "Priorizar runa em vez de pocao",
  ["Min Harmony"] = "Harmonia Minima",
  ["Rune"] = "Runa",
  ["Prioritize Boss"] = "Priorizar Chefe",
  ["Select Spell"] = "Selecionar Feitico",

  -- Tools
  ["Mana Training"] = "Treinamento de Mana",
  ["Exercise Training"] = "Exercise Training",
  ["Dummies"] = "Dummies",
  ["Auto Haste"] = "Pressa Automatica",
  ["Cure Paralyze"] = "Curar Paralisia",
  ["Others Tools"] = "Outras Ferramentas",
  ["Portable Trader"] = "Comerciante Portatil",
  ["Auto Eat Food"] = "Comer Comida Automaticamente",
  ["Auto Increase Forge Limit"] = "Aumentar Limite de Forja Automaticamente",
  ["Hold Attack"] = "Manter Ataque",
  ["Magic Shield"] = "Escudo Magico",
  ["Energy Ring"] = "Anel de Energia",

  -- Ammo & Rune
  ["Rune Portable"] = "Runa Portatil",
  ["Ammo Portable"] = "Municao Portatil",
  ["Ammo Refiller"] = "Enchedor de Municao",

  -- Timer
  ["Add Timer"] = "Adicionar Temporizador",

  -- Party
  ["Party Management"] = "Gerenciamento de Grupo",
  ["Invite"] = "Convidar",
  ["All"] = "Todos",
  ["VIP"] = "VIP",
  ["Guild"] = "Guilda",
  ["Friend"] = "Amigo",
  ["Names"] = "Nomes",

  -- Level Spy
  ["Players"] = "Jogadores",
  ["Guilds"] = "Guildas",
  ["Mobs"] = "Mobs",

  -- Alarms
  ["Damage Taken"] = "Dano Recebido",
  ["Low Health"] = "Saude Baixa",
  ["Monster On Screen"] = "Monstro na Tela",
  ["Player On Screen"] = "Jogador na Tela",
  ["Player Skull On Screen"] = "Caveira de Jogador na Tela",
  ["Player Attack"] = "Ataque de Jogador",
  ["Enemy On Screen"] = "Inimigo na Tela",
  ["Notify Configuration"] = "Configuracao de Notificacao",
  ["Sound Alert"] = "Alerta de Som",
  ["Bring Window to Front"] = "Trazer Janela para Frente",

  -- Settings
  ["Helper Window"] = "Janela do Assistente",
  ["Open Helper Window"] = "Abrir Janela do Assistente",
  ["Open Helper"] = "Abrir Assistente",
  ["Client Display"] = "Exibicao do Cliente",
  ["Show infos on client"] = "Mostrar informacoes no cliente",
  ["Window Opacity"] = "Opacidade da Janela",
  ["Helper Windows Opacity"] = "Opacidade das Janelas do Assistente",
  ["Lock Position"] = "Bloquear Posicao",
  ["Horizontal"] = "Horizontal",
  ["Icon Stats Window"] = "Janela de Estatisticas de Icone",
  ["Helper Language"] = "Idioma do Assistente",

  -- Profiles
  ["Character Profiles"] = "Perfis de Personagem",
  ["Vocation Profiles"] = "Perfis de Vocacao",
  ["Auto Load Profile on Login"] = "Carregar Perfil Automaticamente ao Fazer Login",
  ["Enable Auto Load"] = "Ativar Carregamento Automatico",
  ["By Character Name"] = "Por Nome do Personagem",
  ["By Vocation"] = "Por Vocacao",

  -- Hotkey Labels
  ["Hotkey"] = "Tecla de Atalho",
  ["Assign Hotkey"] = "Atribuir Tecla de Atalho",
  ["Press any key to assign..."] = "Pressione qualquer tecla para atribuir...",
  ["Edit Primary Key"] = "Editar Tecla Primaria",

  -- Target Modes
  ["Mode A - Prioritize closest target"] = "Modo A - Priorizar alvo mais proximo",
  ["Mode B - Prioritize farthest target"] = "Modo B - Priorizar alvo mais distante",
  ["Mode C - Prioritize target with lowest health"] = "Modo C - Priorizar alvo com menor saude",
  ["Mode D - Prioritize target with highest health"] = "Modo D - Priorizar alvo com maior saude",
  ["Mode E - Prioritize best target for runes (diamond arrows for paladins)"] = "Modo E - Priorizar melhor alvo para runas (flechas de diamante para paladinos)",
  ["Mode F - Attack closest target, prioritizing lowest health"] = "Modo F - Atacar alvo mais proximo, priorizando menor saude",
  ["Mode G - Prioritize closest target with highest health"] = "Modo G - Priorizar alvo mais proximo com maior saude",
  ["Mode H - Prioritize farthest target with lowest health"] = "Modo H - Priorizar alvo mais distante com menor saude",
  ["Mode I - Prioritize farthest target with highest health"] = "Modo I - Priorizar alvo mais distante com maior saude",
  ["Mode J - Chain Mode for Mages"] = "Modo J - Modo de Corrente para Magos",
  ["Mode K - Chain Mode for Monks"] = "Modo K - Modo de Corrente para Monges",

  -- Status & Error Messages
  ["Invalid item!"] = "Item invalido!",
  ["Invalid rune!"] = "Runa invalida!",
  ["Invalid spell."] = "Feitico invalido.",
  ["Invalid item ID!"] = "ID do item invalido!",
  ["Invalid item ID."] = "ID do item invalido.",
  ["No item found!"] = "Nenhum item encontrado!",
  ["Select a spell."] = "Selecione um feitico.",
  ["Select a rune."] = "Selecione uma runa.",
  ["Player not found."] = "Jogador nao encontrado.",
  ["Player not available."] = "Jogador nao disponivel.",
  ["File is empty."] = "Arquivo vazio.",
  ["Profiles list reloaded."] = "Lista de perfis recarregada.",
  ["Helper reset. Start a new profile from scratch."] = "Assistente redefinido. Inicie um novo perfil do zero.",
  ["Exeta Res settings saved!"] = "Configuracoes de Exeta Res salvas!",
  ["Utility settings saved!"] = "Configuracoes de Utilidade salvas!",
  ["Vocation HP settings saved!"] = "Configuracoes de HP da Vocacao salvas!",
  ["Utevo Grav San settings saved!"] = "Configuracoes de Utevo Grav San salvas!",
  ["Auto Follow target cleared"] = "Alvo de Seguimento Automatico limpo",
  ["Auto Follow enabled - use Ctrl+RightClick to set target"] = "Seguimento Automatico ativado - use Ctrl+Clique Direito para definir alvo",
  ["Auto Follow disabled"] = "Seguimento Automatico desativado",
  ["Auto Target disabled (Protection Zone)"] = "Alvo Automatico desativado (Zona de Protecao)",
  ["Auto Target restored"] = "Alvo Automatico restaurado",
  ["Magic Shooter disabled (Protection Zone)"] = "Atirador Magico desativado (Zona de Protecao)",
  ["Magic Shooter restored"] = "Atirador Magico restaurado",
  ["Ammo portable configured successfully!"] = "Municao portatil configurada com sucesso!",
  ["Rune portable configured successfully!"] = "Runa portatil configurada com sucesso!",
  ["Cavebot waypoints cleared"] = "Pontos de Referencia do Cavebot limpos",
  ["No waypoints to save"] = "Nenhum ponto de referencia para salvar",
  ["No session selected"] = "Nenhuma sessao selecionada",
  ["Paste the ZeroBot JSON first."] = "Cole o JSON do ZeroBot primeiro.",
  ["Failed to get root widget."] = "Falha ao obter widget raiz.",
  ["Failed to open shooter settings."] = "Falha ao abrir configuracoes do atirador.",
  ["Failed to load healing settings popup."] = "Falha ao carregar popup de configuracoes de cura.",
  ["Failed to load timer settings popup."] = "Falha ao carregar popup de configuracoes de temporizador.",
  ["Failed to load equipment settings popup."] = "Falha ao carregar popup de configuracoes de equipamento.",
  ["Failed to load ZeroBot import dialog."] = "Falha ao carregar dialogo de importacao ZeroBot.",
  ["Failed to load settings window."] = "Falha ao carregar janela de configuracoes.",
  ["Failed to load supplies popup."] = "Falha ao carregar popup de suprimentos.",
  ["Failed to load lure settings."] = "Falha ao carregar configuracoes de atracao.",
  ["Failed to load cavebots manager window."] = "Falha ao carregar janela de gerenciamento de cavebots.",

  -- Tooltips (Settings)
  ["Configure hotkey to open/close Helper window and access configuration panel"] = "Configure a tecla de atalho para abrir/fechar a janela do Assistente e acessar o painel de configuracao",
  ["Show helper stats, shooter profile and cavebot name on client screen."] = "Mostrar estatisticas do assistente, perfil do atirador e nome do cavebot na tela do cliente.",
  ["Change the opacity/transparency of all helper windows.\nLower values make windows more transparent."] = "Altere a opacidade/transparencia de todas as janelas do assistente.\nValores mais baixos tornam as janelas mais transparentes.",

  -- Cavebot
  ["Waypoints"] = "Pontos de Referencia",
  ["Sessions"] = "Sessoes",
  ["Confirm New Cavebot"] = "Confirmar Novo Cavebot",
  ["Lure Timeout (500-5000ms):"] = "Timeout Lure (500-5000ms):",
  ["WAIT only counts mobs coming towards you.\nInterval (ms) between distance samples\nused to detect approach.\nLower = reacts faster,\nhigher = fewer false positives."] = "WAIT so conta mobs vindo na sua direcao.\nIntervalo (ms) entre amostras de distancia\nusadas para detectar aproximacao.\nMenor = reage mais rapido,\nmaior = menos falsos positivos.",

  -- Cavebot Settings Window
  ["Cavebot Settings"] = "Configuracoes do Cavebot",
  ["Movement"] = "Movimento",
  ["Walker Settings (applies to this cavebot)"] = "Configuracoes de Caminhada (aplica-se a este cavebot)",
  ["Node Dist (1-3):"] = "Dist. de Node (1-3):",
  ["SQM distance to reach\na waypoint node. (default: 2)"] = "Distancia em SQM para alcancar\num node de waypoint. (padrao: 2)",
  ["Stop Kill Dist (1-3):"] = "Dist. p/ Matar (1-3):",
  ["SQM distance to reach\na stop_to_kill node. (default: 2)"] = "Distancia em SQM para alcancar\num node de parar e matar. (padrao: 2)",
  ["Creatures to stop (1-99):"] = "Parar com (1-99):",
  ["Stop walking when this\nmany creatures are nearby."] = "Para de andar quando houver\nesta quantidade de criaturas por perto.",
  ["Creatures to walk (0-99):"] = "Andar com (0-99):",
  ["Resume walking when creatures\nare at or below this."] = "Volta a andar quando as criaturas\nestiverem neste valor ou abaixo.",
  ["Do not walk if"] = "Nao andar se",
  ["mobs HP below"] = "HP abaixo de",
  ["Do not resume walking (Stop to Kill or Creatures to walk) while there are at least X mobs with HP below Y percent. Finish them off first. 0 = disabled."] = "Nao volta a andar (Stop to Kill ou Criaturas para andar) enquanto houver pelo menos X mobs com HP abaixo de Y por cento. Finalize-os primeiro. 0 = desativado.",
  ["Walk Delay (10-5000ms):"] = "Delay Andar (10-5000ms):",
  ["Delay in ms between\neach waypoint step."] = "Delay em ms entre\ncada passo de waypoint.",
  ["Walk"] = "Andar",
  ["Click"] = "Clicar",
  ["DEBUG PATH"] = "DEBUG ROTA",
  ["Reset Debug Pos"] = "Resetar Debug Pos",
  ["Walk uses A* steps.\nClick uses map auto-walk."] = "Andar usa passos A*.\nClicar usa auto-walk do mapa.",
  ["Lure Mode"] = "Modo Lure",
  ["Lure Debug"] = "Debug do Lure",
  ["Walk slower to attract\nmonsters and lure them."] = "Anda mais devagar para atrair\nmonstros e isca-los.",
  ["Check X Area (1-6):"] = "Area X (1-6):",
  ["X area to check\nfor creatures in lure."] = "Area X para verificar\ncriaturas no lure.",
  ["Check Y Area (1-4):"] = "Area Y (1-4):",
  ["Y area to check\nfor creatures in lure."] = "Area Y para verificar\ncriaturas no lure.",
  ["Avoid Trap"] = "Evitar Box",
  ["Keep walking to avoid\nbeing trapped by monsters."] = "Continua andando para evitar\nser encurralado por monstros (box).",
  ["Z-Recovery"] = "Recuperar Andar",
  ["Auto recover when on wrong floor.\nSearches nearby stairs or reachable\nwaypoint on same Z level."] = "Recuperacao automatica quando no andar errado.\nProcura escadas proximas ou waypoint\nalcancavel no mesmo nivel Z.",
  ["Trap Distance (1-3):"] = "Distancia de Box (1-3):",
  ["Tile distance to detect\ntrap-threatening monsters."] = "Distancia em tiles para detectar\nmonstros que ameacam fazer box.",
  ["Creatures to Avoid (1-7):"] = "Evitar Criat. (1-7):",
  ["Min monsters nearby to\ntrigger trap avoidance."] = "Minimo de monstros por perto para\nativar evitar box.",
  ["Ignored Creatures (separated by comma):"] = "Criaturas Ignoradas (separadas por virgula):",
  ["Configure Supplies"] = "Configurar Supplies",
  ["Cavebot Conditions"] = "Condicoes do Cavebot",
  ["Stamina to leave (0-42h):"] = "Stamina para sair (0-42h):",
  ["Leave hunt when stamina\ndrops below this (hours)."] = "Sai da hunt quando a stamina\ncair abaixo deste valor (horas).",
  ["Stamina to return (1-42h):"] = "Stamina p/ voltar (1-42h):",
  ["Return to hunt when\nstamina reaches this (hours)."] = "Volta para a hunt quando a\nstamina atingir este valor (horas).",
  ["Cap to leave (0-4000):"] = "Cap para sair (0-4000):",
  ["Leave hunt when cap\ndrops below this value."] = "Sai da hunt quando o cap\ncair abaixo deste valor.",
  ["Deaths to disable (0-100):"] = "Mortes p/ desativar (0-100):",
  ["Deaths before disabling cavebot.\n0 = never disable by death."] = "Mortes antes de desativar o cavebot.\n0 = nunca desativar por morte.",
  ["Apply"] = "Aplicar",

  -- Vocation/Utility Settings
  ["Vocation HP Settings"] = "Configuracoes de HP da Vocacao",
  ["Exeta Res - Settings"] = "Exeta Res - Configuracoes",
  ["Utevo Grav San - Settings"] = "Utevo Grav San - Configuracoes",
  ["Magic Potion Settings"] = "Configuracoes de Pocao Magica",
  ["Utility Spell Settings"] = "Configuracoes de Feitico de Utilidade",

  -- None/Default
  ["None"] = "Nenhum",
  ["Status"] = "Status",
  ["Backpack"] = "Mochila",
  ["Item"] = "Item",

  -- Additional game messages
  ["Auto-load disabled: starting with blank profile"] = "Carregamento automatico desativado: iniciando com perfil em branco",
  ["ZeroBot profile imported (healing, equipment, shooter, timers, heal friend)."] = "Perfil ZeroBot importado (cura, equipamento, atirador, temporizadores, curar amigo).",
  ["Cavebot disabled: you are inside expedition, dungeon or vortex."] = "Cavebot desativado: voce esta dentro de uma expedicao, masmorra ou vortice.",
  ["Cavebot not allowed in expedition, dungeon or vortex."] = "Cavebot nao permitido em expedicao, masmorra ou vortice.",
  ["Left Protection Zone - Utility Helper active"] = "Saiu da Zona de Protecao - Assistente de Utilidade ativo",
  ["No other preset available to copy."] = "Nenhuma outra pre-definicao disponivel para copiar.",
  ["No profile selected. Select a profile in the list first."] = "Nenhum perfil selecionado. Selecione um perfil na lista primeiro.",
  ["No current profile selected. Load or save a profile first."] = "Nenhum perfil atual selecionado. Carregue ou salve um perfil primeiro.",
  ["Source profile is already the current profile."] = "O perfil de origem ja e o perfil atual.",
  ["Profile name cannot be empty."] = "O nome do perfil nao pode estar vazio.",
  -- Clone profile
  ["Clone"] = "Clonar",
  ["Clone Profile"] = "Clonar Perfil",
  ["Clone the selected profile under a new name (does not change the source)."] = "Clona o perfil selecionado com um novo nome (nao altera o original).",
  ["Load the selected profile into the helper for viewing/cloning. Does NOT auto-save over it."] = "Carrega o perfil selecionado para visualizar/clonar. NAO salva automaticamente por cima dele.",
  ["New profile name:"] = "Novo nome do perfil:",
  ["The clone must use a different name than the source."] = "O clone precisa usar um nome diferente do original.",
  ["Profile cloned: %s -> %s"] = "Perfil clonado: %s -> %s",
  ["Overwrite Profile?"] = "Sobrescrever Perfil?",
  ["Overwrite"] = "Sobrescrever",
  ["A profile named '%s' already exists. Overwrite it?"] = "Ja existe um perfil chamado '%s'. Sobrescrever?",
  ["Profile name is too long (max 64 characters)."] = "Nome do perfil muito longo (max 64 caracteres).",
  ["'Default' is a reserved profile name."] = "'Default' e um nome de perfil reservado.",
  ["Profile name has invalid characters."] = "O nome do perfil tem caracteres invalidos.",
  ["Invalid profile name."] = "Nome de perfil invalido.",
  ["Browse not available on this platform."] = "Navegacao nao disponivel nesta plataforma.",
  ["Helper Tracker not available. Please restart the module."] = "Rastreador do Assistente nao disponivel. Por favor, reinicie o modulo.",
  ["Icon Stats not available. Please restart the module."] = "Estatisticas de Icone nao disponiveis. Por favor, reinicie o modulo.",
  ["No shooter profiles available"] = "Nenhum perfil de atirador disponivel",
  ["Unable to determine the write directory."] = "Nao foi possivel determinar o diretorio de escrita.",
  ["Unable to determine the vocation for a vocation profile."] = "Nao foi possivel determinar a vocacao para um perfil de vocacao.",
  ["Language"] = "Idioma",
  ["Change the helper language between English and Portuguese.\nOnly affects helper texts, not the entire client."] = "Altere o idioma do assistente entre Ingles e Portugues.\nAfeta apenas os textos do assistente, nao o cliente inteiro.",
  ["Failed to load waypoint creator window."] = "Falha ao carregar janela do criador de pontos de referencia.",
}

-- ============================================================================
-- Reverse dictionary: Portuguese -> English (built from dictPtbr)
-- ============================================================================
local dictEnFromPtbr = {}
for en, ptbr in pairs(dictPtbr) do
  dictEnFromPtbr[ptbr] = en
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Translate a text key for the helper module.
--- Returns the translated string if language is ptbr and key exists in dict,
--- otherwise returns the original key (English fallback).
--- Supports format arguments: htr("Hello %s", name)
function htr(key, ...)
  if not key then return "" end
  local result = key
  if helperLanguage == "ptbr" and dictPtbr[key] then
    result = dictPtbr[key]
  end
  local args = {...}
  if #args > 0 then
    local ok, formatted = pcall(string.format, result, unpack(args))
    if ok then return formatted end
  end
  return result
end

--- Translate a single text string to the target language.
--- Looks up in both directions (en->ptbr and ptbr->en) to find the translation.
local function translateText(text, targetLang)
  if not text or text == "" then return nil end
  if targetLang == "ptbr" then
    -- English -> Portuguese
    if dictPtbr[text] then return dictPtbr[text] end
  else
    -- Portuguese -> English
    if dictEnFromPtbr[text] then return dictEnFromPtbr[text] end
  end
  return nil
end

-- Callback registered by helper.lua to refresh UI after language change
local onLanguageChangedCallback = nil

--- Register a callback to be invoked after language changes.
--- The callback receives (newLang) and should re-translate the UI.
function registerLanguageChangeCallback(cb)
  onLanguageChangedCallback = cb
end

--- Set the helper language and trigger UI refresh.
--- Valid values: "en", "ptbr"
function setHelperLanguage(lang)
  if lang ~= "ptbr" and lang ~= "en" then return end
  if lang == helperLanguage then return end
  helperLanguage = lang

  -- Notify helper.lua to refresh UI
  if onLanguageChangedCallback then
    onLanguageChangedCallback(lang)
  end
end

--- Get the current helper language.
function getHelperLanguage()
  return helperLanguage
end

--- Walk a widget tree and translate ALL text/tooltip values by matching
--- against the dictionaries. Handles:
---   - exact text match
---   - "- " prefix (active side menu buttons via markActiveButton)
---   - _baseText cache used by markActiveButton
function applyTranslationsToWidgetTree(rootWidget, targetLang)
  if not rootWidget then return end
  targetLang = targetLang or helperLanguage

  local function walkAndTranslate(widget)
    if not widget or widget:isDestroyed() then return end

    -- 1) Translate _baseText first (used by markActiveButton for side menu buttons)
    --    This must happen regardless of whether the display text matches
    if widget._baseText then
      local baseTr = translateText(widget._baseText, targetLang)
      if baseTr then
        widget._baseText = baseTr
        -- Reconstruct display text: if it had "- " prefix, keep it
        local ok, text = pcall(function() return widget:getText() end)
        if ok and text then
          local prefix = text:sub(1, 2)
          if prefix == "- " then
            widget:setText("- " .. baseTr)
          else
            widget:setText(baseTr)
          end
        end
      end
    else
      -- 2) Normal widget without _baseText: try exact match on display text
      local ok1, text = pcall(function() return widget:getText() end)
      if ok1 and text and text ~= "" then
        -- Try direct match first
        local translated = translateText(text, targetLang)
        if translated then
          widget:setText(translated)
        else
          -- Try stripping "- " prefix (active button that hasn't cached _baseText yet)
          if text:sub(1, 2) == "- " then
            local inner = text:sub(3)
            local innerTr = translateText(inner, targetLang)
            if innerTr then
              widget:setText("- " .. innerTr)
            end
          end
        end
      end
    end

    -- 3) Translate tooltip
    local ok2, tip = pcall(function() return widget:getTooltip() end)
    if ok2 and tip and tip ~= "" then
      local translated = translateText(tip, targetLang)
      if translated then
        widget:setTooltip(translated)
      end
    end

    -- 4) Recurse into children
    local ok3, children = pcall(function() return widget:getChildren() end)
    if ok3 and children then
      for _, child in ipairs(children) do
        walkAndTranslate(child)
      end
    end
  end

  walkAndTranslate(rootWidget)
end

-- Expose globally for other scripts in the module
_G.htr = htr
_G.setHelperLanguage = setHelperLanguage
_G.getHelperLanguage = getHelperLanguage
_G.applyTranslationsToWidgetTree = applyTranslationsToWidgetTree
_G.registerLanguageChangeCallback = registerLanguageChangeCallback
