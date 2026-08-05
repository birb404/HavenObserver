local ADDON_NAME = ...

local Observer = CreateFrame("Frame")
local MAX_DURATION = 300
local SAMPLE_INTERVAL = 0.20

local recording
local sampleElapsed = 0
local visibleUnits = {}
local RecorderPanel

local function Plain(value)
    if value == nil then
        return nil
    end

    if issecretvalue and issecretvalue(value) then
        return "<secret>"
    end

    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return value
    end

    return tostring(value)
end

local function NpcID(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then
        return nil
    end

    local unitType, _, _, _, _, id = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" or unitType == "Pet" then
        return tonumber(id)
    end
end

local function Now()
    return recording and (GetTime() - recording.startedAt) or 0
end

local function Add(kind, data)
    if not recording then
        return
    end

    data = data or {}
    data.t = math.floor(Now() * 1000 + 0.5) / 1000
    data.kind = kind
    recording.events[#recording.events + 1] = data
end

local function UnitSnapshot(unit)
    local guid = Plain(UnitGUID(unit))
    if not guid then
        return nil
    end

    local health = Plain(UnitHealth(unit))
    local healthMax = Plain(UnitHealthMax(unit))
    local healthPct
    if type(health) == "number" and type(healthMax) == "number" and healthMax > 0 then
        healthPct = math.floor((health / healthMax) * 1000 + 0.5) / 10
    end

    return {
        unit = unit,
        guid = guid,
        npcId = NpcID(guid),
        name = Plain(UnitName(unit)),
        level = Plain(UnitLevel(unit)),
        reaction = Plain(UnitReaction("player", unit)),
        healthPct = healthPct,
        dead = Plain(UnitIsDeadOrGhost(unit)),
        targetGuid = Plain(UnitGUID(unit .. "target")),
        targetName = Plain(UnitName(unit .. "target")),
    }
end

local function TrackNameplateUnit(unit)
    if type(unit) ~= "string" or not UnitExists(unit) then
        return
    end

    local snapshot = UnitSnapshot(unit)
    if snapshot and visibleUnits[unit] ~= snapshot.guid then
        visibleUnits[unit] = snapshot.guid
        Add("NPC_VISIBLE", snapshot)
    end
end

local function DiscoverNameplates()
    for index = 1, 40 do
        TrackNameplateUnit("nameplate" .. index)
    end
end

local function PlayerPosition()
    local worldY, worldX, worldZ, instanceID = UnitPosition("player")
    local mapID = C_Map.GetBestMapForUnit("player")
    local mapX, mapY
    if mapID then
        local point = C_Map.GetPlayerMapPosition(mapID, "player")
        if point then
            mapX, mapY = point:GetXY()
        end
    end

    return {
        worldX = Plain(worldX),
        worldY = Plain(worldY),
        worldZ = Plain(worldZ),
        instanceID = Plain(instanceID),
        mapID = Plain(mapID),
        mapX = Plain(mapX),
        mapY = Plain(mapY),
        facing = Plain(GetPlayerFacing()),
    }
end

local function Sample()
    if not recording then
        return
    end

    DiscoverNameplates()
    Add("PLAYER_POSITION", PlayerPosition())

    recording.samples = recording.samples + 1
    if Now() >= MAX_DURATION then
        Observer:Stop("five-minute limit")
    end
end

function Observer:Start()
    if recording then
        print("|cff58c6ffHavenObserver:|r already recording.")
        return
    end

    HavenObserverDB = HavenObserverDB or { sessions = {} }
    recording = {
        version = "0.1.3",
        started = date("%Y-%m-%d %H:%M:%S"),
        startedAt = GetTime(),
        realm = GetRealmName(),
        character = UnitName("player"),
        durationLimit = MAX_DURATION,
        samples = 0,
        events = {},
    }
    visibleUnits = {}
    sampleElapsed = 0

    Add("RECORD_START", PlayerPosition())
    DiscoverNameplates()
    print("|cff58c6ffHavenObserver:|r RECORDING for up to five minutes. Video provides movement; the addon records safe NPC unit events.")
end

function Observer:Stop(reason)
    if not recording then
        print("|cff58c6ffHavenObserver:|r not recording.")
        return
    end

    Add("RECORD_STOP", { reason = reason or "manual" })
    recording.duration = math.floor(Now() * 1000 + 0.5) / 1000
    recording.startedAt = nil
    HavenObserverDB.sessions[#HavenObserverDB.sessions + 1] = recording

    print(string.format("|cff58c6ffHavenObserver:|r saved session %d: %.1fs, %d events. Use /reload or logout before copying SavedVariables.",
        #HavenObserverDB.sessions, recording.duration, #recording.events))
    recording = nil
    visibleUnits = {}
end

BINDING_HEADER_HAVENOBSERVER = "Haven Observer"
BINDING_NAME_HAVENOBSERVER_TOGGLE = "Start / stop synchronized recording"

function HavenObserver_ToggleRecording()
    if recording then
        Observer:Stop("shared hotkey")
    else
        Observer:Start()
    end
end

local chatEvents = {
    CHAT_MSG_MONSTER_SAY = true,
    CHAT_MSG_MONSTER_YELL = true,
    CHAT_MSG_MONSTER_EMOTE = true,
    CHAT_MSG_MONSTER_WHISPER = true,
    CHAT_MSG_RAID_BOSS_EMOTE = true,
    CHAT_MSG_RAID_BOSS_WHISPER = true,
}

Observer:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        HavenObserverDB = HavenObserverDB or { sessions = {} }
        HavenObserverDB.sessions = HavenObserverDB.sessions or {}
        print("|cff58c6ffHavenObserver loaded.|r /ho record, /ho stop, /ho mark <text>, /ho status")
        return
    end

    if not recording then
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        TrackNameplateUnit(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        local guid = visibleUnits[unit] or Plain(UnitGUID(unit))
        Add("NPC_HIDDEN", { unit = unit, guid = guid, npcId = NpcID(guid) })
        visibleUnits[unit] = nil
    elseif event == "PLAYER_TARGET_CHANGED" then
        Add("PLAYER_TARGET", UnitSnapshot("target") or { guid = nil })
    elseif chatEvents[event] then
        local message, sender, language, channel, target, flags, _, _, _, _, lineID, guid = ...
        Add("NPC_CHAT", {
            event = event, message = Plain(message), sender = Plain(sender), language = Plain(language),
            channel = Plain(channel), target = Plain(target), flags = Plain(flags), lineID = Plain(lineID),
            guid = Plain(guid), npcId = NpcID(guid),
        })
    elseif event:match("^UNIT_SPELLCAST_") then
        local unit, castGUID, spellID = ...
        if type(unit) == "string" and unit:match("^nameplate") then
            Add("NPC_CAST", {
                event = event, unit = unit, guid = Plain(UnitGUID(unit)), npcId = NpcID(UnitGUID(unit)),
                name = Plain(UnitName(unit)), castGUID = Plain(castGUID), spellID = Plain(spellID),
            })
        end
    end
end)

Observer:SetScript("OnUpdate", function(_, elapsed)
    if not recording then
        return
    end

    sampleElapsed = sampleElapsed + elapsed
    if sampleElapsed >= SAMPLE_INTERVAL then
        sampleElapsed = sampleElapsed - SAMPLE_INTERVAL
        Sample()
    end
end)

Observer:RegisterEvent("PLAYER_LOGIN")
Observer:RegisterEvent("NAME_PLATE_UNIT_ADDED")
Observer:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
Observer:RegisterEvent("PLAYER_TARGET_CHANGED")
Observer:RegisterEvent("CHAT_MSG_MONSTER_SAY")
Observer:RegisterEvent("CHAT_MSG_MONSTER_YELL")
Observer:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
Observer:RegisterEvent("CHAT_MSG_MONSTER_WHISPER")
Observer:RegisterEvent("CHAT_MSG_RAID_BOSS_EMOTE")
Observer:RegisterEvent("CHAT_MSG_RAID_BOSS_WHISPER")
Observer:RegisterEvent("UNIT_SPELLCAST_START")
Observer:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
Observer:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
Observer:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

SLASH_HAVENOBSERVER1 = "/havenobserver"
SLASH_HAVENOBSERVER2 = "/ho"
SlashCmdList.HAVENOBSERVER = function(input)
    local command, rest = input:match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "record" or command == "start" then
        Observer:Start()
    elseif command == "stop" then
        Observer:Stop("manual")
    elseif command == "mark" then
        Add("USER_MARK", { text = rest ~= "" and rest or "mark", player = PlayerPosition() })
        print("|cff58c6ffHavenObserver:|r mark added: " .. (rest ~= "" and rest or "mark"))
    elseif command == "status" then
        if recording then
            local visibleCount = 0
            for _ in pairs(visibleUnits) do
                visibleCount = visibleCount + 1
            end
            print(string.format("|cff58c6ffHavenObserver:|r recording %.1fs, %d events, %d visible nameplates.", Now(), #recording.events, visibleCount))
        else
            print(string.format("|cff58c6ffHavenObserver:|r idle; %d saved sessions.", HavenObserverDB and #HavenObserverDB.sessions or 0))
        end
    elseif command == "clear" then
        if recording then
            print("|cff58c6ffHavenObserver:|r stop recording before clearing sessions.")
        else
            HavenObserverDB.sessions = {}
            print("|cff58c6ffHavenObserver:|r saved sessions cleared.")
        end
    elseif command == "show" then
        RecorderPanel:Show()
    elseif command == "hide" then
        RecorderPanel:Hide()
    else
        print("|cff58c6ffHavenObserver:|r /ho record | stop | mark <text> | status | clear | show | hide")
    end
end

local function CreateButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

RecorderPanel = CreateFrame("Frame", "HavenObserverRecorderPanel", UIParent, "BackdropTemplate")
RecorderPanel:SetSize(430, 118)
RecorderPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
RecorderPanel:SetMovable(true)
RecorderPanel:EnableMouse(true)
RecorderPanel:RegisterForDrag("LeftButton")
RecorderPanel:SetScript("OnDragStart", RecorderPanel.StartMoving)
RecorderPanel:SetScript("OnDragStop", RecorderPanel.StopMovingOrSizing)
RecorderPanel:SetClampedToScreen(true)
RecorderPanel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
RecorderPanel:SetBackdropColor(0.02, 0.04, 0.06, 0.94)

local title = RecorderPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("HAVEN OBSERVER")

local status = RecorderPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("TOPRIGHT", -12, -14)
status:SetText("IDLE")

local coordinates = RecorderPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
coordinates:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
coordinates:SetJustifyH("LEFT")
coordinates:SetText("Map --  --.--, --.--\nWorld --, --, --")

local recordButton = CreateButton(RecorderPanel, "RECORD 5 MIN", 105, function() Observer:Start() end)
recordButton:SetPoint("BOTTOMLEFT", 10, 10)

local stopButton = CreateButton(RecorderPanel, "STOP", 80, function() Observer:Stop("panel") end)
stopButton:SetPoint("LEFT", recordButton, "RIGHT", 5, 0)

local markButton = CreateButton(RecorderPanel, "MARK", 80, function()
    Add("USER_MARK", { text = "panel mark", player = PlayerPosition() })
    print("|cff58c6ffHavenObserver:|r panel mark added.")
end)
markButton:SetPoint("LEFT", stopButton, "RIGHT", 5, 0)

local panelElapsed = 0
RecorderPanel:SetScript("OnUpdate", function(_, elapsed)
    panelElapsed = panelElapsed + elapsed
    if panelElapsed < 0.20 then
        return
    end
    panelElapsed = 0

    local position = PlayerPosition()
    local mapX = type(position.mapX) == "number" and position.mapX * 100 or nil
    local mapY = type(position.mapY) == "number" and position.mapY * 100 or nil
    if mapX and mapY then
        coordinates:SetFormattedText(
            "|cffffd100Map %s|r  %.2f, %.2f\n|cff58c6ffWorld|r %.2f, %.2f, %.2f",
            tostring(position.mapID or "--"), mapX, mapY,
            tonumber(position.worldX) or 0, tonumber(position.worldY) or 0, tonumber(position.worldZ) or 0)
    else
        coordinates:SetFormattedText(
            "|cffffd100Map %s|r  --.--, --.--\n|cff58c6ffWorld|r %.2f, %.2f, %.2f",
            tostring(position.mapID or "--"),
            tonumber(position.worldX) or 0, tonumber(position.worldY) or 0, tonumber(position.worldZ) or 0)
    end

    if recording then
        status:SetFormattedText("|cffff4040REC|r %05.1fs  %d events", Now(), #recording.events)
        recordButton:Disable()
        stopButton:Enable()
        markButton:Enable()
    else
        status:SetText("|cff80ff80IDLE|r")
        recordButton:Enable()
        stopButton:Disable()
        markButton:Disable()
    end
end)
