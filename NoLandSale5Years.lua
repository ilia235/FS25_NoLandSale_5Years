---@diagnostic disable: undefined-global
---@diagnostic disable: lowercase-global

-- NoLandSale5Years.lua
-- FS25 - Strict Sale Blocking, Economy Fix, Save System, Multiplayer Sync & Config

NoLandSale5Years = {}
local NoLandSale5Years_mt = { __index = NoLandSale5Years }

NoLandSale5Years.modName = "NoLandSale5Years"
NoLandSale5Years.DEFAULT_BLOCKED_YEARS = 5
NoLandSale5Years.MSG_DURATION = 15000

-- =============================================================================
-- NETWORK SYNC EVENT
-- =============================================================================

NoLandSaleSyncEvent = {}
local NoLandSaleSyncEvent_mt = Class(NoLandSaleSyncEvent, Event)
InitEventClass(NoLandSaleSyncEvent, "NoLandSaleSyncEvent")

-- Creates an empty event object
function NoLandSaleSyncEvent.emptyNew()
    return Event.new(NoLandSaleSyncEvent_mt)
end

-- Creates a new sync event for the network
function NoLandSaleSyncEvent.new(blockedYears, purchaseData)
    local self = NoLandSaleSyncEvent.emptyNew()
    self.blockedYears = blockedYears
    self.purchaseData = purchaseData
    return self
end

-- Reads data from the network stream (Client side)
function NoLandSaleSyncEvent:readStream(streamId, connection)
    self.blockedYears = streamReadInt32(streamId)
    self.purchaseData = {}

    local count = streamReadInt32(streamId)

    for i = 1, count do
        local id = streamReadInt32(streamId)
        local year = streamReadInt32(streamId)
        self.purchaseData[id] = year
    end

    self:run(connection)
end

-- Writes data to the network stream (Server side)
function NoLandSaleSyncEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.blockedYears)

    local count = 0
    for _ in pairs(self.purchaseData) do
        count = count + 1
    end

    streamWriteInt32(streamId, count)

    for id, year in pairs(self.purchaseData) do
        streamWriteInt32(streamId, id)
        streamWriteInt32(streamId, year)
    end
end

-- Executes the event logic after receiving
function NoLandSaleSyncEvent:run(connection)
    if g_noLandSaleInstance ~= nil then
        g_noLandSaleInstance.blockedYears = self.blockedYears
        g_noLandSaleInstance.purchaseData = self.purchaseData
        g_noLandSaleInstance:print("INFO", "Sync successful! Server setting: %d years.", self.blockedYears)
    end
end

-- =============================================================================
-- MAIN CLASS
-- =============================================================================

-- Initializes the main mod class
function NoLandSale5Years.new()
    local self = setmetatable({}, NoLandSale5Years_mt)
    self.blockedYears = NoLandSale5Years.DEFAULT_BLOCKED_YEARS
    self.purchaseData = {}
    self.isInitialized = false
    return self
end

-- Custom print function for the game log
function NoLandSale5Years:print(level, message, ...)
    print(string.format("[%s][%s] %s", self.modName, level, string.format(message, ...)))
end

-- Loads configuration from modSettings folder
function NoLandSale5Years:loadConfiguration()
    local modSettingsDir = getUserProfileAppPath() .. "modSettings/"
    local myModDir = modSettingsDir .. self.modName .. "/"
    local xmlFilePath = myModDir .. "config.xml"

    if not fileExists(modSettingsDir) then
        createFolder(modSettingsDir)
    end
    if not fileExists(myModDir) then
        createFolder(myModDir)
    end

    if not fileExists(xmlFilePath) then
        local xmlFile = createXMLFile("NoLandSaleConfig", xmlFilePath, "noLandSale")
        if xmlFile ~= 0 then
            setXMLInt(xmlFile, "noLandSale.blockedYears", self.blockedYears)
            saveXMLFile(xmlFile)
            delete(xmlFile)
        end
    else
        local xmlFile = loadXMLFile("NoLandSaleConfig", xmlFilePath)
        if xmlFile ~= 0 then
            local customYears = getXMLInt(xmlFile, "noLandSale.blockedYears")
            if customYears ~= nil then
                self.blockedYears = math.max(0, customYears)
            end
            delete(xmlFile)
        end
    end
end

-- Checks if the player is allowed to sell the farmland
function NoLandSale5Years:canSellFarmland(farmlandId)
    local purchaseYear = self.purchaseData[farmlandId]
    if purchaseYear == nil then
        return true, 0
    end

    if g_currentMission == nil or g_currentMission.environment == nil then
        return true, 0
    end

    local currentYear = g_currentMission.environment.currentYear
    local yearsOwned = currentYear - purchaseYear

    if yearsOwned < self.blockedYears then
        return false, self.blockedYears - yearsOwned
    end

    return true, 0
end

-- Saves purchase data to the savegame
function NoLandSale5Years:onSavegameSave()
    if g_currentMission == nil or g_currentMission.missionInfo == nil or g_server == nil then
        return
    end

    local savegameDir = g_currentMission.missionInfo.savegameDirectory
    if savegameDir == nil then
        return
    end

    local xmlPath = savegameDir .. "/NoLandSale5Years.xml"
    local xmlFile = createXMLFile("NoLandSaleXML", xmlPath, "noLandSale")

    if xmlFile ~= nil and xmlFile ~= 0 then
        local i = 0
        for id, year in pairs(self.purchaseData) do
            local key = string.format("noLandSale.purchase(%d)", i)
            setXMLInt(xmlFile, key .. "#farmlandId", id)
            setXMLInt(xmlFile, key .. "#year", year)
            i = i + 1
        end
        saveXMLFile(xmlFile)
        delete(xmlFile)
    end
end

-- Loads purchase data from the savegame
function NoLandSale5Years:loadFromSavegame()
    local savegameDir = g_currentMission.missionInfo.savegameDirectory
    if savegameDir == nil then
        return
    end

    local xmlPath = savegameDir .. "/NoLandSale5Years.xml"
    if fileExists(xmlPath) then
        local xmlFile = loadXMLFile("NoLandSaleXML", xmlPath)
        if xmlFile == 0 then
            return
        end

        local i = 0
        while true do
            local key = string.format("noLandSale.purchase(%d)", i)
            if not hasXMLEntry(xmlFile, key) then
                break
            end

            local id = getXMLInt(xmlFile, key .. "#farmlandId")
            local year = getXMLInt(xmlFile, key .. "#year")

            if id ~= nil and year ~= nil then
                self.purchaseData[id] = year
            end
            i = i + 1
        end
        delete(xmlFile)
    end
end

-- Initializes the mod and injects the farmland hook
function NoLandSale5Years:init()
    if self.isInitialized or FarmlandManager == nil then
        return
    end

    if g_server ~= nil then
        self:loadConfiguration()
        self:loadFromSavegame()
    end

    FSBaseMission.registerActionEvents = Utils.appendedFunction(FSBaseMission.registerActionEvents,
        function(mission, connection)
            if g_server ~= nil and connection ~= nil then
                connection:sendEvent(NoLandSaleSyncEvent.new(self.blockedYears, self.purchaseData))
            end
        end)

    local oldSetLandOwnership = FarmlandManager.setLandOwnership
    FarmlandManager.setLandOwnership = function(manager, farmlandId, farmId, ...)
        local oldOwnerId = manager:getFarmlandOwner(farmlandId)

        if farmId == 0 and oldOwnerId ~= 0 then
            local canSell, _ = self:canSellFarmland(farmlandId)

            if not canSell then
                local text = string.format(g_i18n:getText("warning_noLandSaleYet"), self.blockedYears)
                g_currentMission:showBlinkingWarning(text, self.MSG_DURATION)

                if g_server ~= nil then
                    local farmland = manager:getFarmlandById(farmlandId)
                    if farmland ~= nil and farmland.price > 0 then
                        g_currentMission:addMoney(-farmland.price, oldOwnerId, MoneyType.SHOP_PROPERTY_BUY, true, true)
                    end
                end
                return false
            end
        end

        local result = oldSetLandOwnership(manager, farmlandId, farmId, ...)

        if result and farmId ~= 0 and oldOwnerId == 0 then
            if g_currentMission.environment then
                self.purchaseData[farmlandId] = g_currentMission.environment.currentYear
            end
        elseif result and farmId == 0 then
            self.purchaseData[farmlandId] = nil
        end

        return result
    end

    self.isInitialized = true
end

-- =============================================================================
-- MOD INITIALIZATION
-- =============================================================================

g_noLandSaleInstance = NoLandSale5Years.new()

function NoLandSale5Years:loadMap(name)
    self:init()
end

function NoLandSale5Years:saveSavegame()
    self:onSavegameSave()
end

addModEventListener(g_noLandSaleInstance)