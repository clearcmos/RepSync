-- RepSync: Auto-switch watched reputation in dungeons, raids, and cities
-- For WoW Classic Anniversary Edition (2.5.5)

local addonName, _ = ...;

--------------------------------------------------------------------------------
-- Configuration Defaults
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    enabled = true,
    restorePrevious = true,
    enableCities = true,
    previousFactionID = nil,
    skipExalted = false,
    verbose = true,
    showAlert = true,
    alertOffsetX = 0,
    alertOffsetY = -220,
};

--------------------------------------------------------------------------------
-- Local References
--------------------------------------------------------------------------------

local pairs = pairs;
local ipairs = ipairs;
local strlower = string.lower;
local strtrim = strtrim;
local floor = math.floor;
local GetNumFactions = GetNumFactions;
local GetFactionInfo = GetFactionInfo;
local ExpandFactionHeader = ExpandFactionHeader;
local CollapseFactionHeader = CollapseFactionHeader;
local SetWatchedFactionIndex = SetWatchedFactionIndex;
local GetInstanceInfo = GetInstanceInfo;
local IsInInstance = IsInInstance;
local UnitFactionGroup = UnitFactionGroup;
local GetSubZoneText = GetSubZoneText;
local GetTime = GetTime;

local ADDON_COLOR = "|cff8080ff";
local ADDON_PREFIX = ADDON_COLOR .. "RepSync|r: ";

--------------------------------------------------------------------------------
-- Instance → Faction Mapping
-- Keys are instanceID (8th return of GetInstanceInfo(), i.e. the map ID)
-- Values: { faction = ID } for universal, { alliance = ID, horde = ID } for split
--------------------------------------------------------------------------------

local INSTANCE_FACTION_MAP = {
    -- TBC Dungeons: Hellfire Citadel
    [543]  = { alliance = 946, horde = 947 },  -- Hellfire Ramparts → Honor Hold / Thrallmar
    [542]  = { alliance = 946, horde = 947 },  -- The Blood Furnace
    [540]  = { alliance = 946, horde = 947 },  -- The Shattered Halls

    -- TBC Dungeons: Coilfang Reservoir
    [547]  = { faction = 942 },   -- The Slave Pens → Cenarion Expedition
    [546]  = { faction = 942 },   -- The Underbog
    [545]  = { faction = 942 },   -- The Steamvault

    -- TBC Dungeons: Auchindoun
    [557]  = { faction = 933 },   -- Mana-Tombs → The Consortium
    [558]  = { faction = 1011 },  -- Auchenai Crypts → Lower City
    [556]  = { faction = 1011 },  -- Sethekk Halls
    [555]  = { faction = 1011 },  -- Shadow Labyrinth

    -- TBC Dungeons: Tempest Keep
    [554]  = { faction = 935 },   -- The Mechanar → The Sha'tar
    [553]  = { faction = 935 },   -- The Botanica
    [552]  = { faction = 935 },   -- The Arcatraz

    -- TBC Dungeons: Caverns of Time
    [560]  = { faction = 989 },   -- Old Hillsbrad Foothills → Keepers of Time
    [269]  = { faction = 989 },   -- The Black Morass

    -- TBC Dungeons: Sunwell Isle
    [585]  = { faction = 1077 },  -- Magister's Terrace → Shattered Sun Offensive

    -- TBC Raids
    [532]  = { faction = 967 },   -- Karazhan → The Violet Eye
    [534]  = { faction = 990 },   -- Hyjal Summit → Scale of the Sands
    [564]  = { faction = 1012 },  -- Black Temple → Ashtongue Deathsworn

    -- Vanilla Dungeons
    [329]  = { faction = 529 },   -- Stratholme → Argent Dawn
    [289]  = { faction = 529 },   -- Scholomance → Argent Dawn
    [230]  = { faction = 59 },    -- Blackrock Depths → Thorium Brotherhood
    [429]  = { faction = 809 },   -- Dire Maul → Shen'dralar

    -- Vanilla Raids
    [409]  = { faction = 749 },   -- Molten Core → Hydraxian Waterlords
    [509]  = { faction = 609 },   -- Ruins of Ahn'Qiraj → Cenarion Circle
    [531]  = { faction = 910 },   -- Temple of Ahn'Qiraj → Brood of Nozdormu
    [309]  = { faction = 270 },   -- Zul'Gurub → Zandalar Tribe
    [533]  = { faction = 529 },   -- Naxxramas → Argent Dawn

    -- Battlegrounds
    [30]   = { alliance = 730, horde = 729 },  -- Alterac Valley → Stormpike Guard / Frostwolf Clan
    [489]  = { alliance = 890, horde = 889 },  -- Warsong Gulch → Silverwing Sentinels / Warsong Outriders
    [529]  = { alliance = 509, horde = 510 },  -- Arathi Basin → League of Arathor / The Defilers
};

--------------------------------------------------------------------------------
-- City → Faction Mapping
-- Keys are uiMapID from C_Map.GetBestMapForUnit("player")
-- Values: { alliance = ID } or { horde = ID } (only triggers for matching faction)
--------------------------------------------------------------------------------

local CITY_FACTION_MAP = {
    -- Alliance Capitals (Classic Anniversary uiMapIDs)
    [1453] = { alliance = 72 },   -- Stormwind City → Stormwind
    [1455] = { alliance = 47 },   -- Ironforge → Ironforge
    [1457] = { alliance = 69 },   -- Darnassus → Darnassus
    [1947] = { alliance = 930 },  -- The Exodar → Exodar

    -- Horde Capitals (Classic Anniversary uiMapIDs)
    [1454] = { horde = 76 },      -- Orgrimmar → Orgrimmar
    [1456] = { horde = 81 },      -- Thunder Bluff → Thunder Bluff
    [1458] = { horde = 68 },      -- Undercity → Undercity
    [1954] = { horde = 911 },     -- Silvermoon City → Silvermoon City
};

--------------------------------------------------------------------------------
-- Sub-zone → Faction Mapping (Aldor Rise / Scryer's Tier)
-- Built from all locale names so GetSubZoneText() matches any client language
--------------------------------------------------------------------------------

local SUBZONE_FACTION_MAP = {};

local SUBZONE_LOCALE_DATA = {
    { factionID = 932, names = {  -- The Aldor
        "Aldor Rise",                    -- enUS
        "Aldorhöhe",                     -- deDE
        "Alto Aldor",                    -- esES / esMX
        "Éminence de l'Aldor",           -- frFR
        "Poggio degli Aldor",            -- itIT
        "Terraço dos Aldor",             -- ptBR
        "Возвышенность Алдоров",         -- ruRU
        "알도르 마루",                      -- koKR
        "奥尔多高地",                       -- zhCN
        "奧多爾高地",                       -- zhTW
    }},
    { factionID = 934, names = {  -- The Scryers
        "Scryer's Tier",                 -- enUS
        "Sehertreppe",                   -- deDE
        "Grada del Arúspice",            -- esES / esMX
        "Degré des Clairvoyants",        -- frFR
        "Loggia dei Veggenti",           -- itIT
        "Terraço dos Áugures",           -- ptBR
        "Ярус Провидцев",                -- ruRU
        "점술가 언덕",                      -- koKR
        "占星者之台",                       -- zhCN
        "占卜者階梯",                       -- zhTW
    }},
    { factionID = 54, names = {   -- Gnomeregan Exiles (Tinker Town in Ironforge)
        "Tinker Town",                   -- enUS
        "Tüftlerstadt",                  -- deDE
        "Ciudad Manitas",                -- esES / esMX
        "Brikabrok",                     -- frFR
        "Rabberciopoli",                 -- itIT
        "Beco da Gambiarra",             -- ptBR
        "Город Механиков",               -- ruRU
        "땜장이 마을",                      -- koKR
        "侏儒区",                          -- zhCN
        "地精區",                          -- zhTW
    }},
    { factionID = 530, names = {  -- Darkspear Trolls (Valley of Spirits in Orgrimmar)
        "Valley of Spirits",             -- enUS
        "Tal der Geister",               -- deDE
        "Valle de los Espíritus",        -- esES / esMX
        "Vallée des Esprits",            -- frFR
        "Valle degli Spiriti",           -- itIT
        "Vale dos Espíritos",            -- ptBR
        "Аллея Духов",                   -- ruRU
        "정기의 골짜기",                    -- koKR
        "精神谷",                          -- zhCN / zhTW
    }},

    -- Steamwheedle Cartel goblin towns
    { factionID = 21, names = {   -- Booty Bay
        "Booty Bay",                     -- enUS
        "Beutebucht",                    -- deDE
        "Bahía del Botín",               -- esES / esMX
        "Baie-du-Butin",                 -- frFR
        "Baia del Bottino",              -- itIT
        "Angra do Butim",                -- ptBR
        "Пиратская Бухта",               -- ruRU
        "무법항",                           -- koKR
        "藏宝海湾",                         -- zhCN
        "藏寶海灣",                         -- zhTW
    }},
    { factionID = 577, names = {  -- Everlook
        "Everlook",                      -- enUS
        "Ewige Warte",                   -- deDE
        "Vista Eterna",                  -- esES / esMX
        "Long-Guet",                     -- frFR
        "Lungavista",                    -- itIT
        "Visteterna",                    -- ptBR
        "Круговзор",                     -- ruRU
        "눈망루 마을",                      -- koKR
        "永望镇",                          -- zhCN
        "永望鎮",                          -- zhTW
    }},
    { factionID = 369, names = {  -- Gadgetzan
        "Gadgetzan",                     -- enUS / deDE / esES / esMX / frFR
        "Meccania",                      -- itIT
        "Geringontzan",                  -- ptBR
        "Прибамбасск",                   -- ruRU
        "가젯잔",                          -- koKR
        "加基森",                          -- zhCN / zhTW
    }},
    { factionID = 470, names = {  -- Ratchet
        "Ratchet",                       -- enUS
        "Ratschet",                      -- deDE
        "Trinquete",                     -- esES / esMX
        "Cabestan",                      -- frFR
        "Porto Paranco",                 -- itIT
        "Vila Catraca",                  -- ptBR
        "Кабестан",                      -- ruRU
        "톱니항",                           -- koKR
        "棘齿城",                          -- zhCN
        "棘齒城",                          -- zhTW
    }},

    -- TBC sub-zones
    { factionID = 970, names = {  -- Sporeggar
        "Sporeggar",                     -- enUS / deDE / frFR / itIT / ptBR
        "Esporaggar",                    -- esES / esMX
        "Спореггар",                     -- ruRU
        "스포어가르",                       -- koKR
        "孢子村",                          -- zhCN
        "斯博格爾",                         -- zhTW
    }},
    { factionID = 978, names = {  -- Kurenai (Telaar - Alliance town in Nagrand)
        "Telaar",                        -- enUS / deDE / esES / esMX / frFR / itIT / ptBR
        "Телаар",                        -- ruRU
        "텔라아르",                         -- koKR
        "塔拉",                            -- zhCN
        "泰拉",                            -- zhTW
    }},
    { factionID = 941, names = {  -- The Mag'har (Garadar - Horde town in Nagrand)
        "Garadar",                       -- enUS / deDE / esES / esMX / frFR / itIT / ptBR
        "Гарадар",                       -- ruRU
        "가라다르",                         -- koKR
        "加拉达尔",                         -- zhCN
        "卡拉達爾",                         -- zhTW
    }},

    -- Vanilla sub-zones
    { factionID = 609, names = {  -- Cenarion Circle (Cenarion Hold in Silithus)
        "Cenarion Hold",                 -- enUS
        "Burg Cenarius",                 -- deDE
        "Fuerte Cenarion",               -- esES / esMX
        "Fort Cénarien",                 -- frFR
        "Fortezza Cenariana",            -- itIT
        "Forte Cenariano",               -- ptBR
        "Крепость Кенария",              -- ruRU
        "세나리온 요새",                    -- koKR
        "塞纳里奥要塞",                     -- zhCN
        "塞納里奧城堡",                     -- zhTW
    }},
    { factionID = 529, names = {  -- Argent Dawn (Light's Hope Chapel in EPL)
        "Light's Hope Chapel",           -- enUS
        "Kapelle des Hoffnungsvollen Lichts", -- deDE
        "Capilla de la Esperanza de la Luz",  -- esES / esMX
        "Chapelle de l'Espoir de Lumière",    -- frFR
        "Cappella della Luce",           -- itIT
        "Capela Esperança da Luz",       -- ptBR
        "Часовня Последней Надежды",     -- ruRU
        "희망의 빛 예배당",                  -- koKR
        "圣光之愿礼拜堂",                   -- zhCN
        "聖光之願禮拜堂",                   -- zhTW
    }},
};

for _, entry in ipairs(SUBZONE_LOCALE_DATA) do
    for _, name in ipairs(entry.names) do
        SUBZONE_FACTION_MAP[name] = entry.factionID;
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local db;
local playerFaction;       -- "Alliance" or "Horde"
local lastProcessedTime = 0;
local lastProcessedTarget = nil;
local DEBOUNCE_INTERVAL = 2;
local repSyncCategoryID;
local settingsDemoActive = false;
local RegisterSettings;

local eventFrame = CreateFrame("Frame");

--------------------------------------------------------------------------------
-- Alert Display (zone-text style fade notification)
--------------------------------------------------------------------------------

local alertFrame = CreateFrame("Frame", "RepSyncAlertFrame", UIParent);
alertFrame:SetSize(512, 40);
alertFrame:SetPoint("TOP", UIParent, "TOP", 0, -220);
alertFrame:SetFrameStrata("LOW");
alertFrame:Hide();

local alertText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge");
alertText:SetPoint("CENTER");
alertText:SetFont(alertText:GetFont(), 26, "THICKOUTLINE");
alertText:SetTextColor(0.5, 0.5, 1.0);

local function UpdateAlertPosition()
    if not db then return; end
    alertFrame:ClearAllPoints();
    alertFrame:SetPoint("TOP", UIParent, "TOP", db.alertOffsetX, db.alertOffsetY);
end

local alertStartTime = 0;
local alertDemoMode = false;
local ALERT_FADE_IN  = 0.5;
local ALERT_HOLD     = 1.5;
local ALERT_FADE_OUT = 2.0;
local ALERT_TOTAL    = ALERT_FADE_IN + ALERT_HOLD + ALERT_FADE_OUT;

alertFrame:SetScript("OnUpdate", function(self)
    local elapsed = GetTime() - alertStartTime;
    if alertDemoMode then
        elapsed = elapsed % ALERT_TOTAL;
    end
    if elapsed < ALERT_FADE_IN then
        self:SetAlpha(elapsed / ALERT_FADE_IN);
    elseif elapsed < ALERT_FADE_IN + ALERT_HOLD then
        self:SetAlpha(1.0);
    elseif elapsed < ALERT_FADE_IN + ALERT_HOLD + ALERT_FADE_OUT then
        local fadeElapsed = elapsed - ALERT_FADE_IN - ALERT_HOLD;
        self:SetAlpha(1.0 - fadeElapsed / ALERT_FADE_OUT);
    else
        self:Hide();
    end
end);

local function ShowAlert(text)
    alertText:SetText(text);
    alertStartTime = GetTime();
    alertDemoMode = false;
    alertFrame:SetAlpha(0);
    alertFrame:Show();
end

-- Draggable preview area (blue highlight, ScrollingLoot style)
local alertPreview = CreateFrame("Frame", "RepSyncAlertPreview", UIParent);
alertPreview:SetSize(512, 40);
alertPreview:SetPoint("TOP", UIParent, "TOP", 0, -220);
alertPreview:SetFrameStrata("DIALOG");
alertPreview:SetFrameLevel(50);
alertPreview:EnableMouse(true);
alertPreview:SetMovable(true);
alertPreview:SetClampedToScreen(true);
alertPreview:Hide();

alertPreview.highlight = alertPreview:CreateTexture(nil, "BACKGROUND");
alertPreview.highlight:SetAllPoints();
alertPreview.highlight:SetColorTexture(0.2, 0.5, 0.8, 0.25);
alertPreview.highlight:Hide();

alertPreview.border = alertPreview:CreateTexture(nil, "BORDER");
alertPreview.border:SetPoint("TOPLEFT", -2, 2);
alertPreview.border:SetPoint("BOTTOMRIGHT", 2, -2);
alertPreview.border:SetColorTexture(0.3, 0.6, 1.0, 0.6);
alertPreview.border:Hide();

alertPreview.inner = alertPreview:CreateTexture(nil, "BORDER", nil, 1);
alertPreview.inner:SetAllPoints();
alertPreview.inner:SetColorTexture(0, 0, 0, 0);
alertPreview.inner:Hide();

alertPreview:SetScript("OnEnter", function(self)
    self.highlight:Show();
    self.border:Show();
    self.inner:Show();
    SetCursor("Interface\\CURSOR\\UI-Cursor-Move");
end);

alertPreview:SetScript("OnLeave", function(self)
    if not self.isDragging then
        self.highlight:Hide();
        self.border:Hide();
        self.inner:Hide();
    end
    SetCursor(nil);
end);

local UpdateAlertPreviewPosition;

alertPreview:RegisterForDrag("LeftButton");

alertPreview:SetScript("OnDragStart", function(self)
    self.isDragging = true;
    self.highlight:Show();
    self.border:Show();
    self.inner:Show();
    self.dragStartLeft = self:GetLeft();
    self.dragStartTop = self:GetTop();
    self.dragStartOffsetX = db.alertOffsetX;
    self.dragStartOffsetY = db.alertOffsetY;
    self:StartMoving();
end);

alertPreview:SetScript("OnUpdate", function(self)
    if self.isDragging then
        local deltaX = self:GetLeft() - self.dragStartLeft;
        local deltaY = self:GetTop() - self.dragStartTop;
        db.alertOffsetX = self.dragStartOffsetX + deltaX;
        db.alertOffsetY = self.dragStartOffsetY + deltaY;
        UpdateAlertPosition();
    end
end);

alertPreview:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing();
    self.isDragging = false;

    if not self:IsMouseOver() then
        self.highlight:Hide();
        self.border:Hide();
        self.inner:Hide();
    end

    local deltaX = self:GetLeft() - self.dragStartLeft;
    local deltaY = self:GetTop() - self.dragStartTop;
    db.alertOffsetX = self.dragStartOffsetX + deltaX;
    db.alertOffsetY = self.dragStartOffsetY + deltaY;

    db.alertOffsetX = floor(db.alertOffsetX / 5 + 0.5) * 5;
    db.alertOffsetY = floor(db.alertOffsetY / 5 + 0.5) * 5;

    UpdateAlertPosition();
    UpdateAlertPreviewPosition();
end);

UpdateAlertPreviewPosition = function()
    if not db then return; end
    alertPreview:ClearAllPoints();
    alertPreview:SetPoint("TOP", UIParent, "TOP", db.alertOffsetX, db.alertOffsetY);
end

local function StartAlertDemo()
    UpdateAlertPosition();
    UpdateAlertPreviewPosition();
    alertText:SetText("RepSync: Honor Hold");
    alertStartTime = GetTime();
    alertDemoMode = true;
    alertFrame:SetAlpha(0);
    alertFrame:Show();
    alertPreview:Show();
end

local function StopAlertDemo()
    alertDemoMode = false;
    alertFrame:Hide();
    alertPreview:Hide();
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local function Print(msg)
    if db and db.verbose then
        print(ADDON_PREFIX .. msg);
    end
end

local function PrintAlways(msg)
    print(ADDON_PREFIX .. msg);
end

--- Get the target faction ID from an entry table based on player faction
local function GetFactionIDFromEntry(entry)
    if not entry then return nil; end

    if entry.faction then
        return entry.faction;
    end

    if playerFaction == "Alliance" then
        return entry.alliance;
    elseif playerFaction == "Horde" then
        return entry.horde;
    end

    return nil;
end

--- Get the faction ID currently being watched, or nil
local function GetCurrentWatchedFactionID()
    local data = C_Reputation.GetWatchedFactionData();
    if data and data.factionID and data.factionID ~= 0 then
        return data.factionID;
    end
    return nil;
end

local FACTION_NAMES = {
    [946]  = "Honor Hold",              [947]  = "Thrallmar",
    [942]  = "Cenarion Expedition",     [933]  = "The Consortium",
    [1011] = "Lower City",              [935]  = "The Sha'tar",
    [989]  = "Keepers of Time",         [1077] = "Shattered Sun Offensive",
    [967]  = "The Violet Eye",          [990]  = "Scale of the Sands",
    [1012] = "Ashtongue Deathsworn",    [529]  = "Argent Dawn",
    [59]   = "Thorium Brotherhood",     [809]  = "Shen'dralar",
    [749]  = "Hydraxian Waterlords",    [609]  = "Cenarion Circle",
    [910]  = "Brood of Nozdormu",       [270]  = "Zandalar Tribe",
    [932]  = "The Aldor",              [934]  = "The Scryers",
    [54]   = "Gnomeregan Exiles",      [530]  = "Darkspear Trolls",
    [21]   = "Booty Bay",              [577]  = "Everlook",
    [369]  = "Gadgetzan",              [470]  = "Ratchet",
    [970]  = "Sporeggar",              [978]  = "Kurenai",
    [941]  = "The Mag'har",
    [730]  = "Stormpike Guard",        [729]  = "Frostwolf Clan",
    [890]  = "Silverwing Sentinels",   [889]  = "Warsong Outriders",
    [509]  = "League of Arathor",      [510]  = "The Defilers",
    [72]   = "Stormwind",              [47]   = "Ironforge",
    [69]   = "Darnassus",              [930]  = "Exodar",
    [76]   = "Orgrimmar",              [81]   = "Thunder Bluff",
    [68]   = "Undercity",              [911]  = "Silvermoon City",
};

--- Get faction name by ID (tries rep panel first, falls back to static table)
local function GetFactionNameByID(targetFactionID)
    if not targetFactionID then return nil; end
    local numFactions = GetNumFactions();
    for i = 1, numFactions do
        local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i);
        if factionID == targetFactionID then
            return name;
        end
    end
    return FACTION_NAMES[targetFactionID];
end

--------------------------------------------------------------------------------
-- Core: Find and Watch Faction by ID
-- Expands all collapsed headers, finds the faction index, sets watched, then
-- re-collapses previously collapsed headers.
--------------------------------------------------------------------------------

local function FindAndWatchFactionByID(targetFactionID, skipExalted, blacklist)
    if not targetFactionID then return false; end

    -- Phase 1: Record and expand all collapsed headers
    local collapsedHeaders = {};

    local expanded = true;
    while expanded do
        expanded = false;
        local numFactions = GetNumFactions();
        for i = numFactions, 1, -1 do
            local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i);
            if isHeader and isCollapsed then
                collapsedHeaders[name] = true;
                ExpandFactionHeader(i);
                expanded = true;
                break;
            end
        end
    end

    -- Phase 2: Find the target faction index
    local targetIndex = nil;
    local factionName = nil;
    local numFactions = GetNumFactions();
    for i = 1, numFactions do
        local name, _, _, _, _, _, _, _, _, _, _, _, _, factionID = GetFactionInfo(i);
        if factionID == targetFactionID then
            targetIndex = i;
            factionName = name;
            break;
        end
    end

    -- Phase 2.5: Check skip criteria (reliable after expand, unlike GetFactionInfoByID
    -- which can return nil for factions in the Inactive reputation list)
    local skipReason = nil;
    if targetIndex and (skipExalted or blacklist) then
        local _, _, standingID = GetFactionInfo(targetIndex);
        if standingID and standingID <= 2 then
            skipReason = "Hostile";
        elseif skipExalted and standingID and standingID == 8 then
            skipReason = "Exalted";
        elseif blacklist and blacklist[targetFactionID] then
            skipReason = "Ignored";
        end
    end

    -- Phase 3: Set watched faction (only if not skipped)
    local success = false;
    if targetIndex and not skipReason then
        SetWatchedFactionIndex(targetIndex);
        success = true;
    end

    -- Phase 4: Re-collapse headers we expanded
    local recollapsed = true;
    while recollapsed do
        recollapsed = false;
        numFactions = GetNumFactions();
        for i = numFactions, 1, -1 do
            local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i);
            if isHeader and not isCollapsed and collapsedHeaders[name] then
                CollapseFactionHeader(i);
                collapsedHeaders[name] = nil;
                recollapsed = true;
                break;
            end
        end
    end

    return success, skipReason, factionName;
end

--------------------------------------------------------------------------------
-- Zone Change Processing
--------------------------------------------------------------------------------

local function ProcessZoneChange()
    if not db or not db.enabled then return; end

    local targetFactionID = nil;
    local contextLabel = nil;

    -- Priority 1: Instance detection
    local inInstance, instanceType = IsInInstance();
    if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp") then
        local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo();
        if instanceID then
            targetFactionID = GetFactionIDFromEntry(INSTANCE_FACTION_MAP[instanceID]);
            contextLabel = instanceName;
        end
    end

    -- Priority 2: Sub-zone detection (Aldor Rise / Scryer's Tier)
    if not targetFactionID and db.enableCities then
        local subZone = GetSubZoneText();
        if subZone and subZone ~= "" then
            targetFactionID = SUBZONE_FACTION_MAP[subZone];
            if targetFactionID then
                contextLabel = subZone;
            end
        end
    end

    -- Priority 3: Capital city detection
    if not targetFactionID and db.enableCities then
        local mapID = C_Map.GetBestMapForUnit("player");
        if mapID then
            local entry = CITY_FACTION_MAP[mapID];
            if entry then
                targetFactionID = GetFactionIDFromEntry(entry);
                if targetFactionID then
                    local mapInfo = C_Map.GetMapInfo(mapID);
                    contextLabel = mapInfo and mapInfo.name or tostring(mapID);
                end
            end
        end
    end

    -- Debounce
    local now = GetTime();

    if targetFactionID then
        if targetFactionID == lastProcessedTarget and (now - lastProcessedTime) < DEBOUNCE_INTERVAL then
            return;
        end

        local currentFactionID = GetCurrentWatchedFactionID();
        if currentFactionID == targetFactionID then
            lastProcessedTarget = targetFactionID;
            lastProcessedTime = now;
            return;
        end

        local success, skipReason, foundName = FindAndWatchFactionByID(targetFactionID, db.skipExalted, db.blacklist);
        if skipReason then
            local factionName = foundName or FACTION_NAMES[targetFactionID] or tostring(targetFactionID);
            Print("Skipping |cffffd200" .. factionName .. "|r (" .. skipReason .. ")");
        elseif success then
            -- Save previous only on successful switch (preserves original across transitions)
            if db.restorePrevious and currentFactionID and not db.previousFactionID then
                db.previousFactionID = currentFactionID;
            end
            local factionName = foundName or FACTION_NAMES[targetFactionID] or tostring(targetFactionID);
            if db.showAlert then
                ShowAlert("RepSync: " .. factionName);
            else
                Print("Switched to |cffffd200" .. factionName .. "|r for " .. (contextLabel or ""));
            end
        end

        lastProcessedTarget = targetFactionID;
        lastProcessedTime = now;

    else
        if db.restorePrevious and db.previousFactionID then
            local previousID = db.previousFactionID;
            db.previousFactionID = nil;

            if FindAndWatchFactionByID(previousID) then
                local factionName = GetFactionNameByID(previousID) or tostring(previousID);
                if db.showAlert then
                    ShowAlert("RepSync: " .. factionName);
                else
                    Print("Restored |cffffd200" .. factionName .. "|r");
                end
            end
        end

        lastProcessedTarget = nil;
        lastProcessedTime = 0;
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

eventFrame:RegisterEvent("ADDON_LOADED");
eventFrame:RegisterEvent("PLAYER_LOGIN");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
eventFrame:RegisterEvent("ZONE_CHANGED");

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...;
        if loaded ~= addonName then return; end

        if not RepSyncDB then
            RepSyncDB = {};
        end
        for k, v in pairs(DEFAULT_SETTINGS) do
            if RepSyncDB[k] == nil then
                RepSyncDB[k] = v;
            end
        end
        db = RepSyncDB;
        if not db.blacklist then
            db.blacklist = {};
        end
        UpdateAlertPosition();

        self:UnregisterEvent("ADDON_LOADED");

    elseif event == "PLAYER_LOGIN" then
        playerFaction = UnitFactionGroup("player");
        RegisterSettings();
        C_Timer.After(1, ProcessZoneChange);

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, ProcessZoneChange);

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        ProcessZoneChange();
    end
end);

--------------------------------------------------------------------------------
-- GUI: Options Panel (native Settings API, matching HealerMana style)
--------------------------------------------------------------------------------

RegisterSettings = function()
    local category, layout = Settings.RegisterVerticalLayoutCategory("RepSync");

    -- Helper: register a boolean proxy setting + checkbox
    local function AddCheckbox(key, name, tooltip, onChange)
        local setting = Settings.RegisterProxySetting(category,
            "REPSYNC_" .. key:upper(), Settings.VarType.Boolean, name,
            DEFAULT_SETTINGS[key],
            function() return db[key]; end,
            function(value)
                db[key] = value;
                if onChange then onChange(value); end
            end);
        return Settings.CreateCheckbox(category, setting, tooltip);
    end

    -------------------------
    -- Section: General
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("General"));

    AddCheckbox("enabled", "Enable Auto-Switching",
        "Automatically switch your reputation bar when entering a mapped dungeon, raid, or city.");

    AddCheckbox("restorePrevious", "Restore Previous Rep on Exit",
        "When leaving a mapped instance, automatically switch back to the reputation you were tracking before.");

    AddCheckbox("enableCities", "Switch in Cities & Sub-Zones",
        "Switch reputation when entering capital cities (Stormwind, Orgrimmar, etc.) and faction sub-zones (Aldor Rise, Scryer's Tier).");

    AddCheckbox("skipExalted", "Skip Exalted Factions",
        "Don't switch reputation when you are already Exalted with the target faction.");

    -------------------------
    -- Section: Notifications
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Notifications"));

    AddCheckbox("showAlert", "Show Alert on Screen",
        "Show a zone-text style notification on screen when reputation is switched.",
        function(value)
            if value and settingsDemoActive then
                StartAlertDemo();
            else
                StopAlertDemo();
            end
        end);

    AddCheckbox("verbose", "Chat Messages",
        "Print reputation switch messages to chat.");

    -------------------------
    -- Section: Ignored Factions
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Ignored Factions"));

    local relevantFactions = {};
    local seen = {};

    for _, entry in pairs(INSTANCE_FACTION_MAP) do
        local fid = GetFactionIDFromEntry(entry);
        if fid and not seen[fid] then
            seen[fid] = true;
            relevantFactions[#relevantFactions + 1] = fid;
        end
    end

    for _, entry in pairs(CITY_FACTION_MAP) do
        local fid = GetFactionIDFromEntry(entry);
        if fid and not seen[fid] then
            seen[fid] = true;
            relevantFactions[#relevantFactions + 1] = fid;
        end
    end

    local FACTION_SPECIFIC_SUBZONES = {
        [54]  = "Alliance",  -- Gnomeregan Exiles (Tinker Town)
        [530] = "Horde",     -- Darkspear Trolls (Valley of Spirits)
        [978] = "Alliance",  -- Kurenai (Telaar)
        [941] = "Horde",     -- The Mag'har (Garadar)
    };
    for _, data in ipairs(SUBZONE_LOCALE_DATA) do
        local fid = data.factionID;
        local requiredFaction = FACTION_SPECIFIC_SUBZONES[fid];
        if fid and not seen[fid] and (not requiredFaction or requiredFaction == playerFaction) then
            seen[fid] = true;
            relevantFactions[#relevantFactions + 1] = fid;
        end
    end

    table.sort(relevantFactions, function(a, b)
        return (FACTION_NAMES[a] or "") < (FACTION_NAMES[b] or "");
    end);

    for _, fid in ipairs(relevantFactions) do
        local fname = FACTION_NAMES[fid] or tostring(fid);
        local setting = Settings.RegisterProxySetting(category,
            "REPSYNC_IGNORE_" .. fid, Settings.VarType.Boolean, fname,
            false,
            function() return db.blacklist and db.blacklist[fid] or false; end,
            function(value)
                if not db.blacklist then db.blacklist = {}; end
                if value then
                    db.blacklist[fid] = true;
                else
                    db.blacklist[fid] = nil;
                end
            end);
        Settings.CreateCheckbox(category, setting,
            "Ignore " .. fname .. " -- RepSync will not switch to this faction.");
    end

    Settings.RegisterAddOnCategory(category);
    repSyncCategoryID = category:GetID();

    -- Stop alert demo and restore strata when settings panel closes
    if SettingsPanel then
        SettingsPanel:HookScript("OnHide", function()
            if settingsDemoActive then
                StopAlertDemo();
                settingsDemoActive = false;
                alertFrame:SetFrameStrata("LOW");
                alertPreview:SetFrameStrata("DIALOG");
            end
        end);
    end
end

local function OpenOptions()
    settingsDemoActive = true;
    alertFrame:SetFrameStrata("TOOLTIP");
    alertPreview:SetFrameStrata("TOOLTIP");
    if db.showAlert then
        StartAlertDemo();
    end
    Settings.OpenToCategory(repSyncCategoryID);
end

--------------------------------------------------------------------------------
-- Blacklist (Ignore List)
--------------------------------------------------------------------------------

local function FindFactionByName(input)
    if not input or input == "" then return nil; end
    input = strlower(input);

    -- Exact match first
    for id, name in pairs(FACTION_NAMES) do
        if strlower(name) == input then
            return id, name;
        end
    end

    -- Partial match (must be unambiguous)
    local matchID, matchName;
    local matchCount = 0;
    for id, name in pairs(FACTION_NAMES) do
        if strlower(name):find(input, 1, true) then
            matchID = id;
            matchName = name;
            matchCount = matchCount + 1;
        end
    end

    if matchCount == 1 then
        return matchID, matchName;
    elseif matchCount > 1 then
        return nil, nil, true; -- ambiguous
    end

    return nil;
end

local function AddToBlacklist(input)
    local id, name, ambiguous = FindFactionByName(input);
    if ambiguous then
        PrintAlways("Multiple factions match '" .. input .. "'. Be more specific.");
        return;
    end
    if not id then
        PrintAlways("No faction found matching '" .. input .. "'.");
        return;
    end
    if not db.blacklist then db.blacklist = {}; end
    db.blacklist[id] = true;
    PrintAlways("Added |cffffd200" .. name .. "|r to ignore list.");
end

local function RemoveFromBlacklist(input)
    local id, name, ambiguous = FindFactionByName(input);
    if ambiguous then
        PrintAlways("Multiple factions match '" .. input .. "'. Be more specific.");
        return;
    end
    if not id then
        PrintAlways("No faction found matching '" .. input .. "'.");
        return;
    end
    if db.blacklist then
        db.blacklist[id] = nil;
    end
    PrintAlways("Removed |cffffd200" .. name .. "|r from ignore list.");
end

local function ShowIgnoreList()
    if not db.blacklist or not next(db.blacklist) then
        PrintAlways("Ignore list is empty.");
        return;
    end
    PrintAlways("Ignored factions:");
    for id in pairs(db.blacklist) do
        local name = FACTION_NAMES[id] or tostring(id);
        PrintAlways("  |cffffd200" .. name .. "|r");
    end
end

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

local function ShowHelp()
    PrintAlways("Commands:");
    PrintAlways("  |cffffd200/rs|r - Toggle options window");
    PrintAlways("  |cffffd200/rs clear|r - Clear saved previous faction");
    PrintAlways("  |cffffd200/rs list|r - List all mapped locations in chat");
    PrintAlways("  |cffffd200/rs ignore <name>|r - Add faction to ignore list");
    PrintAlways("  |cffffd200/rs unignore <name>|r - Remove faction from ignore list");
    PrintAlways("  |cffffd200/rs ignorelist|r - Show ignored factions");
    PrintAlways("  |cffffd200/rs help|r - Show this help");
end

local INSTANCE_NAMES = {
    [543] = "Hellfire Ramparts",    [542] = "The Blood Furnace",    [540] = "The Shattered Halls",
    [547] = "The Slave Pens",       [546] = "The Underbog",         [545] = "The Steamvault",
    [557] = "Mana-Tombs",           [558] = "Auchenai Crypts",      [556] = "Sethekk Halls",
    [555] = "Shadow Labyrinth",     [554] = "The Mechanar",         [553] = "The Botanica",
    [552] = "The Arcatraz",         [560] = "Old Hillsbrad",        [269] = "The Black Morass",
    [585] = "Magister's Terrace",   [532] = "Karazhan",             [534] = "Hyjal Summit",
    [564] = "Black Temple",         [329] = "Stratholme",           [289] = "Scholomance",
    [230] = "Blackrock Depths",     [429] = "Dire Maul",            [409] = "Molten Core",
    [509] = "Ruins of Ahn'Qiraj",  [531] = "Temple of Ahn'Qiraj",  [309] = "Zul'Gurub",
    [533] = "Naxxramas",
    [30]  = "Alterac Valley",        [489] = "Warsong Gulch",
    [529] = "Arathi Basin",
};

local CITY_NAMES = {
    [1453] = "Stormwind City",      [1455] = "Ironforge",
    [1457] = "Darnassus",           [1947] = "The Exodar",
    [1454] = "Orgrimmar",           [1456] = "Thunder Bluff",
    [1458] = "Undercity",           [1954] = "Silvermoon City",
};

local function ShowList()
    PrintAlways("Mapped locations:");

    local entries = {};

    -- Instances
    for instanceID, entry in pairs(INSTANCE_FACTION_MAP) do
        local factionID = GetFactionIDFromEntry(entry);
        if factionID then
            local factionName = GetFactionNameByID(factionID) or tostring(factionID);
            local instanceName = INSTANCE_NAMES[instanceID] or tostring(instanceID);
            entries[#entries + 1] = { location = instanceName, faction = factionName };
        end
    end

    -- Cities
    for mapID, entry in pairs(CITY_FACTION_MAP) do
        local factionID = GetFactionIDFromEntry(entry);
        if factionID then
            local factionName = GetFactionNameByID(factionID) or tostring(factionID);
            local cityName = CITY_NAMES[mapID] or tostring(mapID);
            entries[#entries + 1] = { location = cityName, faction = factionName };
        end
    end

    -- Sub-zones (show English names only)
    for _, data in ipairs(SUBZONE_LOCALE_DATA) do
        local factionName = GetFactionNameByID(data.factionID) or tostring(data.factionID);
        entries[#entries + 1] = { location = data.names[1], faction = factionName };
    end

    table.sort(entries, function(a, b) return a.location < b.location; end);

    for _, e in ipairs(entries) do
        PrintAlways("  |cffffd200" .. e.location .. "|r -> " .. e.faction);
    end
end

local function SlashHandler(msg)
    if not db then return; end

    msg = strtrim(msg or "");
    local cmd = msg:match("^(%S+)") or "";
    cmd = strlower(cmd);
    local arg = strtrim(msg:match("^%S+%s+(.+)$") or "");

    if cmd == "" then
        OpenOptions();
    elseif cmd == "clear" then
        db.previousFactionID = nil;
        PrintAlways("Cleared saved previous faction");
    elseif cmd == "list" then
        ShowList();
    elseif cmd == "ignore" then
        if arg == "" then
            ShowIgnoreList();
        else
            AddToBlacklist(arg);
        end
    elseif cmd == "unignore" then
        if arg ~= "" then
            RemoveFromBlacklist(arg);
        else
            PrintAlways("Usage: |cffffd200/rs unignore <faction name>|r");
        end
    elseif cmd == "ignorelist" then
        ShowIgnoreList();
    elseif cmd == "help" then
        ShowHelp();
    else
        ShowHelp();
    end
end

SLASH_REPSYNC1 = "/repsync";
SLASH_REPSYNC2 = "/rs";
SlashCmdList["REPSYNC"] = SlashHandler;
