-- NoLandSale5Years.lua
-- FS25 - Strict Sale Blocking, Economy Fix, Save System, Multiplayer Sync & Config

NoLandSale5Years = {}
local NoLandSale5Years_mt = { __index = NoLandSale5Years }

NoLandSale5Years.modName = "NoLandSale5Years"
NoLandSale5Years.defaultBlockedYears = 5

-- =============================================================================
-- NETWORK SYNC EVENT (Примусова синхронізація клієнта з сервером)
-- =============================================================================

NoLandSaleSyncEvent = {}
local NoLandSaleSyncEvent_mt = Class(NoLandSaleSyncEvent, Event)
InitEventClass(NoLandSaleSyncEvent, "NoLandSaleSyncEvent")

function NoLandSaleSyncEvent.emptyNew()
    return Event.new(NoLandSaleSyncEvent_mt)
end

function NoLandSaleSyncEvent.new(blockedYears, purchaseData)
    local self = NoLandSaleSyncEvent.emptyNew()
    self.blockedYears = blockedYears
    self.purchaseData = purchaseData
    return self
end

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

function NoLandSaleSyncEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.blockedYears)
    local count = 0
    for _ in pairs(self.purchaseData) do count = count + 1 end
    streamWriteInt32(streamId, count)
    for id, year in pairs(self.purchaseData) do
        streamWriteInt32(streamId, id)
        streamWriteInt32(streamId, year)
    end
end

function NoLandSaleSyncEvent:run(connection)
    if g_noLandSaleInstance ~= nil then
        g_noLandSaleInstance.blockedYears = self.blockedYears
        g_noLandSaleInstance.purchaseData = self.purchaseData
        g_noLandSaleInstance:print("INFO", "Sync successful! Client updated blockedYears to %d", self.blockedYears)
    end
end

-- =============================================================================
-- MAIN CLASS
-- =============================================================================

function NoLandSale5Years.new()
    local self = setmetatable({}, NoLandSale5Years_mt)
    self.blockedYears = NoLandSale5Years.defaultBlockedYears
    self.purchaseData = {}
    self.isInitialized = false
    print(string.format("[%s] Instance created.", NoLandSale5Years.modName))
    return self
end

function NoLandSale5Years:print(level, message, ...)
    print(string.format("[%s][%s] %s", self.modName, level, string.format(message, ...)))
end

function NoLandSale5Years:loadConfiguration()
    local modSettingsDir = getUserProfileAppPath() .. "modSettings/"
    local myModDir = modSettingsDir .. self.modName .. "/"
    local xmlFilePath = myModDir .. "config.xml"

    self:print("INFO", "--- CONFIGURATION CHECK ---")
    self:print("INFO", "Looking for config file at: %s", xmlFilePath)

    if not fileExists(modSettingsDir) then createFolder(modSettingsDir) end
    if not fileExists(myModDir) then createFolder(myModDir) end

    if not fileExists(xmlFilePath) then
        self:print("WARNING", "Config file NOT FOUND! Creating a new default config.xml...")
        local xmlFile = createXMLFile("NoLandSaleConfig", xmlFilePath, "noLandSale")
        if xmlFile ~= 0 then
            setXMLInt(xmlFile, "noLandSale.blockedYears", self.defaultBlockedYears)
            saveXMLFile(xmlFile)
            delete(xmlFile)
            self:print("INFO", "Created default config.xml with %d years.", self.defaultBlockedYears)
        end
    else
        self:print("INFO", "Config file FOUND. Trying to read...")
        local xmlFile = loadXMLFile("NoLandSaleConfig", xmlFilePath)
        if xmlFile ~= 0 then
            local customYears = getXMLInt(xmlFile, "noLandSale.blockedYears")
            if customYears ~= nil then
                self.blockedYears = math.max(0, customYears)
                self:print("INFO", "SUCCESS: Applied custom years from config: %d", self.blockedYears)
            else
                self:print("ERROR", "Failed to find 'noLandSale.blockedYears' tag! Using default: %d", self.blockedYears)
            end
            delete(xmlFile)
        end
    end
    self:print("INFO", "--- CONFIGURATION END ---")
end

function NoLandSale5Years:canSellFarmland(farmlandId)
    local purchaseYear = self.purchaseData[farmlandId]
    if purchaseYear == nil then return true, 0 end
    if g_currentMission == nil or g_currentMission.environment == nil then return true, 0 end

    local currentYear = g_currentMission.environment.currentYear
    local yearsOwned = currentYear - purchaseYear

    if yearsOwned < self.blockedYears then
        return false, self.blockedYears - yearsOwned
    end
    return true, 0
end

function NoLandSale5Years:onSavegameSave()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return end
    local savegameDir = g_currentMission.missionInfo.savegameDirectory
    if savegameDir == nil then return end
    
    local xmlPath = savegameDir .. "/NoLandSale5Years.xml"
    local xmlFile = createXMLFile("NoLandSaleXML", xmlPath, "noLandSale")
    if xmlFile == nil or xmlFile == 0 then return end
    
    local i = 0
    for id, year in pairs(self.purchaseData) do
        local key = string.format("noLandSale.purchase(%d)", i)
        setXMLInt(xmlFile, key .. "#farmlandId", id)
        setXMLInt(xmlFile, key .. "#year", year)
        i = i + 1
    end
    
    saveXMLFile(xmlFile)
    delete(xmlFile)
    self:print("INFO", "Data saved successfully.")
end

function NoLandSale5Years:loadFromSavegame()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return end
    local savegameDir = g_currentMission.missionInfo.savegameDirectory
    if savegameDir == nil then return end
    
    local xmlPath = savegameDir .. "/NoLandSale5Years.xml"
    if fileExists(xmlPath) then
        local xmlFile = loadXMLFile("NoLandSaleXML", xmlPath)
        if xmlFile == nil or xmlFile == 0 then return end
        
        local i = 0
        while true do
            local key = string.format("noLandSale.purchase(%d)", i)
            if not hasXMLEntry(xmlFile, key) then break end
            
            local id = getXMLInt(xmlFile, key .. "#farmlandId")
            local year = getXMLInt(xmlFile, key .. "#year")
            if id ~= nil and year ~= nil then
                self.purchaseData[id] = year
            end
            i = i + 1
        end
        delete(xmlFile)
        self:print("INFO", "Loaded %d records from savegame.", i)
    end
end

function NoLandSale5Years:init()
    if self.isInitialized or FarmlandManager == nil then return end

    self:loadConfiguration()

    -- ХУК 1: Відправка налаштувань сервера гравцям при підключенні
    local oldSendInitialClientState = FSBaseMission.sendInitialClientState
    FSBaseMission.sendInitialClientState = function(mission, connection, user, ...)
        if oldSendInitialClientState ~= nil then
            oldSendInitialClientState(mission, connection, user, ...)
        end
        if g_server ~= nil then
            connection:sendEvent(NoLandSaleSyncEvent.new(self.blockedYears, self.purchaseData))
        end
    end
    
    -- ХУК 2: Блокування мережевої події (зупиняє клієнтів від відправки запиту на продаж)
    if FarmlandStateEvent ~= nil and FarmlandStateEvent.run ~= nil then
        local oldEventRun = FarmlandStateEvent.run
        FarmlandStateEvent.run = function(eventSelf, connection)
            if eventSelf.farmId == 0 then 
                local canSell, _ = self:canSellFarmland(eventSelf.farmlandId)
                if not canSell then return end
            end
            return oldEventRun(eventSelf, connection)
        end
    end

    -- ХУК 3: Відстеження транзакцій + відкат грошей та локальне блокування
    local oldSetLandOwnership = FarmlandManager.setLandOwnership
    FarmlandManager.setLandOwnership = function(manager, farmlandId, farmId, ...)
        local oldOwnerId = manager:getFarmlandOwner(farmlandId)
        
        if farmId == 0 and oldOwnerId ~= 0 then
            local canSell, _ = self:canSellFarmland(farmlandId)
            
            if not canSell then
                local messageTemplate = g_i18n:getText("warning_noLandSaleYet")
                local message = string.format(messageTemplate, self.blockedYears)
                g_currentMission:showBlinkingWarning(message, 15000)
                
                if g_server ~= nil then
                    local price = 0
                    if manager.farmlands ~= nil and manager.farmlands[farmlandId] ~= nil then
                        price = manager.farmlands[farmlandId].price
                    end
                    
                    if price ~= nil and price > 0 then
                        local moneyType = MoneyType and MoneyType.OTHER or 1
                        g_currentMission:addMoney(-price, oldOwnerId, moneyType, true, true)
                        self:print("INFO", "Transaction rollback: %d deducted from farm balance.", price)
                    end
                end
                return false
            end
        end
        
        local result = false
        if oldSetLandOwnership ~= nil then
            result = oldSetLandOwnership(manager, farmlandId, farmId, ...)
        end

        local newOwnerId = manager:getFarmlandOwner(farmlandId)
        if newOwnerId == farmId and oldOwnerId ~= farmId then
            if oldOwnerId == 0 and farmId ~= 0 then
                if g_currentMission and g_currentMission.environment then
                    local currentYear = g_currentMission.environment.currentYear
                    self.purchaseData[farmlandId] = currentYear
                    self:print("INFO", "Land %d purchased. Blocked for %d years.", farmlandId, self.blockedYears)
                end
            elseif farmId == 0 then
                self.purchaseData[farmlandId] = nil
                self:print("INFO", "Land %d successfully sold.", farmlandId)
            end
        end
        return result
    end

    if g_server ~= nil then self:loadFromSavegame() end
    
    self.isInitialized = true
    self:print("INFO", "Mod initialized. Multiplayer and economy protection enabled.")
end

g_noLandSaleInstance = NoLandSale5Years.new()

function NoLandSale5Years:loadMap(name)
    self:init()
end

function NoLandSale5Years:saveSavegame()
    self:onSavegameSave()
end

addModEventListener(g_noLandSaleInstance)