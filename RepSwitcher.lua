-- RepSwitcher: Auto-switch watched reputation when entering dungeons/raids
-- For WoW Classic Anniversary Edition (2.5.5)

local addonName, addon = ...;

--------------------------------------------------------------------------------
-- Configuration Defaults
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    enabled = true,
    restorePrevious = true,
    previousFactionID = nil,
    verbose = true,
};

--------------------------------------------------------------------------------
-- Local References
--------------------------------------------------------------------------------

local pairs = pairs;
local ipairs = ipairs;
local format = string.format;
local strlower = string.lower;
local strtrim = strtrim;
local tinsert = table.insert;
local floor = math.floor;
local GetNumFactions = GetNumFactions;
local GetFactionInfo = GetFactionInfo;
local ExpandFactionHeader = ExpandFactionHeader;
local CollapseFactionHeader = CollapseFactionHeader;
local SetWatchedFactionIndex = SetWatchedFactionIndex;
local GetInstanceInfo = GetInstanceInfo;
local IsInInstance = IsInInstance;
local UnitFactionGroup = UnitFactionGroup;
local GetTime = GetTime;

local ADDON_COLOR = "|cff8080ff";
local ADDON_PREFIX = ADDON_COLOR .. "RepSwitcher|r: ";

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
};

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local db;
local playerFaction;       -- "Alliance" or "Horde"
local lastProcessedTime = 0;
local lastProcessedInstance = nil;
local DEBOUNCE_INTERVAL = 2;
local OptionsFrame;

local eventFrame = CreateFrame("Frame");

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

--- Get the target faction ID for the current instance based on player faction
local function GetFactionIDForInstance(instanceID)
    local entry = INSTANCE_FACTION_MAP[instanceID];
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

local function FindAndWatchFactionByID(targetFactionID)
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
    local numFactions = GetNumFactions();
    for i = 1, numFactions do
        local _, _, _, _, _, _, _, _, _, _, _, _, _, factionID = GetFactionInfo(i);
        if factionID == targetFactionID then
            targetIndex = i;
            break;
        end
    end

    -- Phase 3: Set watched faction
    local success = false;
    if targetIndex then
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

    return success;
end

--------------------------------------------------------------------------------
-- Zone Change Processing
--------------------------------------------------------------------------------

local function ProcessZoneChange()
    if not db or not db.enabled then return; end

    local inInstance, instanceType = IsInInstance();

    if inInstance and (instanceType == "party" or instanceType == "raid") then
        local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo();
        if not instanceID then return; end

        -- Debounce
        local now = GetTime();
        if instanceID == lastProcessedInstance and (now - lastProcessedTime) < DEBOUNCE_INTERVAL then
            return;
        end

        local targetFactionID = GetFactionIDForInstance(instanceID);
        if not targetFactionID then return; end

        local currentFactionID = GetCurrentWatchedFactionID();
        if currentFactionID == targetFactionID then
            lastProcessedInstance = instanceID;
            lastProcessedTime = now;
            return;
        end

        if db.restorePrevious and currentFactionID then
            db.previousFactionID = currentFactionID;
        end

        if FindAndWatchFactionByID(targetFactionID) then
            local factionName = GetFactionNameByID(targetFactionID) or tostring(targetFactionID);
            Print("Switched to |cffffd200" .. factionName .. "|r for " .. (instanceName or ""));
        end

        lastProcessedInstance = instanceID;
        lastProcessedTime = now;

    else
        if db.restorePrevious and db.previousFactionID then
            local previousID = db.previousFactionID;
            db.previousFactionID = nil;

            if FindAndWatchFactionByID(previousID) then
                local factionName = GetFactionNameByID(previousID) or tostring(previousID);
                Print("Restored |cffffd200" .. factionName .. "|r");
            end
        end

        lastProcessedInstance = nil;
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

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...;
        if loaded ~= addonName then return; end

        if not RepSwitcherDB then
            RepSwitcherDB = {};
        end
        for k, v in pairs(DEFAULT_SETTINGS) do
            if RepSwitcherDB[k] == nil then
                RepSwitcherDB[k] = v;
            end
        end
        db = RepSwitcherDB;

        self:UnregisterEvent("ADDON_LOADED");

    elseif event == "PLAYER_LOGIN" then
        playerFaction = UnitFactionGroup("player");
        C_Timer.After(1, ProcessZoneChange);

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, ProcessZoneChange);

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        ProcessZoneChange();
    end
end);

--------------------------------------------------------------------------------
-- GUI: Widget Factories (matching MyDruid/HealerMana style)
--------------------------------------------------------------------------------

local FrameBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
};

local function CreateCheckbox(parent, label, width)
    local container = CreateFrame("Frame", nil, parent);
    container:SetSize(width or 200, 24);

    local checkbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate");
    checkbox:SetPoint("LEFT");
    checkbox:SetSize(24, 24);

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    labelText:SetPoint("LEFT", checkbox, "RIGHT", 2, 0);
    labelText:SetText(label);

    checkbox:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and 856 or 857);
        if container.OnValueChanged then
            container:OnValueChanged(self:GetChecked());
        end
    end);

    container.checkbox = checkbox;
    container.labelText = labelText;

    function container:SetValue(value)
        checkbox:SetChecked(value);
    end

    function container:GetValue()
        return checkbox:GetChecked();
    end

    return container;
end

--------------------------------------------------------------------------------
-- GUI: Options Frame
--------------------------------------------------------------------------------

local function CreateOptionsFrame()
    if OptionsFrame then return OptionsFrame; end

    local frame = CreateFrame("Frame", "RepSwitcherOptionsFrame", UIParent, "BackdropTemplate");
    frame:SetSize(280, 160);
    frame:SetPoint("CENTER");
    frame:SetBackdrop(FrameBackdrop);
    frame:SetBackdropColor(0, 0, 0, 1);
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:SetToplevel(true);
    frame:SetFrameStrata("DIALOG");
    frame:SetFrameLevel(100);
    frame:Hide();

    -- Title bar
    local titleBg = frame:CreateTexture(nil, "OVERLAY");
    titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBg:SetTexCoord(0.31, 0.67, 0, 0.63);
    titleBg:SetPoint("TOP", 0, 12);
    titleBg:SetSize(180, 40);

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    titleText:SetPoint("TOP", titleBg, "TOP", 0, -14);
    titleText:SetText("RepSwitcher");

    local titleBgL = frame:CreateTexture(nil, "OVERLAY");
    titleBgL:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBgL:SetTexCoord(0.21, 0.31, 0, 0.63);
    titleBgL:SetPoint("RIGHT", titleBg, "LEFT");
    titleBgL:SetSize(30, 40);

    local titleBgR = frame:CreateTexture(nil, "OVERLAY");
    titleBgR:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBgR:SetTexCoord(0.67, 0.77, 0, 0.63);
    titleBgR:SetPoint("LEFT", titleBg, "RIGHT");
    titleBgR:SetSize(30, 40);

    -- Title drag area
    local titleArea = CreateFrame("Frame", nil, frame);
    titleArea:SetAllPoints(titleBg);
    titleArea:EnableMouse(true);
    titleArea:SetScript("OnMouseDown", function() frame:StartMoving(); end);
    titleArea:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); end);

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    closeBtn:SetPoint("TOPRIGHT", -5, -5);

    -- Content area
    local content = CreateFrame("Frame", nil, frame);
    content:SetPoint("TOPLEFT", 20, -40);
    content:SetPoint("BOTTOMRIGHT", -20, 15);

    local y = 0;

    -- Enabled checkbox
    local enabledCb = CreateCheckbox(content, "Enable auto-switching", 240);
    enabledCb:SetPoint("TOPLEFT", 0, y);
    enabledCb:SetValue(db.enabled);
    enabledCb:EnableMouse(true);
    enabledCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText("Enable Auto-Switching", 1, 1, 1);
        GameTooltip:AddLine("Automatically switch your reputation bar when entering a mapped dungeon or raid.", 1, 0.82, 0, true);
        GameTooltip:Show();
    end);
    enabledCb:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    enabledCb.OnValueChanged = function(self, value)
        db.enabled = value;
    end;
    y = y - 32;

    -- Restore previous checkbox
    local restoreCb = CreateCheckbox(content, "Restore previous rep on exit", 240);
    restoreCb:SetPoint("TOPLEFT", 0, y);
    restoreCb:SetValue(db.restorePrevious);
    restoreCb:EnableMouse(true);
    restoreCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText("Restore Previous", 1, 1, 1);
        GameTooltip:AddLine("When leaving a mapped instance, automatically switch back to the reputation you were tracking before.", 1, 0.82, 0, true);
        GameTooltip:Show();
    end);
    restoreCb:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    restoreCb.OnValueChanged = function(self, value)
        db.restorePrevious = value;
    end;

    -- ESC to close
    tinsert(UISpecialFrames, "RepSwitcherOptionsFrame");

    OptionsFrame = frame;
    return frame;
end

local function ToggleOptionsFrame()
    local frame = CreateOptionsFrame();
    if frame:IsShown() then
        frame:Hide();
    else
        frame:Show();
    end
end

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

local function ShowHelp()
    PrintAlways("Commands:");
    PrintAlways("  |cffffd200/rs|r - Toggle options window");
    PrintAlways("  |cffffd200/rs clear|r - Clear saved previous faction");
    PrintAlways("  |cffffd200/rs list|r - List all mapped instances in chat");
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
};

local function ShowList()
    PrintAlways("Mapped instances:");
    local entries = {};
    for instanceID, entry in pairs(INSTANCE_FACTION_MAP) do
        local factionID;
        if entry.faction then
            factionID = entry.faction;
        elseif playerFaction == "Alliance" then
            factionID = entry.alliance;
        else
            factionID = entry.horde;
        end
        local factionName = GetFactionNameByID(factionID) or tostring(factionID);
        local instanceName = INSTANCE_NAMES[instanceID] or tostring(instanceID);
        entries[#entries + 1] = { instance = instanceName, faction = factionName };
    end
    table.sort(entries, function(a, b) return a.instance < b.instance; end);

    for _, e in ipairs(entries) do
        PrintAlways("  |cffffd200" .. e.instance .. "|r -> " .. e.faction);
    end
end

local function SlashHandler(msg)
    if not db then return; end

    msg = strtrim(msg or "");
    local cmd = msg:match("^(%S+)") or "";
    cmd = strlower(cmd);

    if cmd == "" then
        ToggleOptionsFrame();
    elseif cmd == "clear" then
        db.previousFactionID = nil;
        PrintAlways("Cleared saved previous faction");
    elseif cmd == "list" then
        ShowList();
    elseif cmd == "help" then
        ShowHelp();
    else
        ShowHelp();
    end
end

SLASH_REPSWITCHER1 = "/repswitcher";
SLASH_REPSWITCHER2 = "/rs";
SlashCmdList["REPSWITCHER"] = SlashHandler;
