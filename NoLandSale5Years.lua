-- NoLandSale5Years.lua
-- Mod for Farming Simulator 25
-- Prevents selling land parcels for a configurable number of game years after purchase.
--
-- Copyright (c) 2026, ilia235_1. All rights reserved.
-- Refactored by Gemini AI assistant.

print("[NoLandSale5Years][TRACE] Script file is being executed by the game engine.")

NoLandSale5Years = {}
local NoLandSale5Years_mt = {
    __index = NoLandSale5Years
}

-- =============================================================================
-- Constants and Configuration
-- =============================================================================

NoLandSale5Years.modName = "NoLandSale5Years"
NoLandSale5Years.savegameFileName = "NoLandSale5Years.xml"
NoLandSale5Years.defaultBlockedYears = 5

-- =============================================================================
-- Constructor
-- =============================================================================

function NoLandSale5Years.new()
    local self = {}
    setmetatable(self, NoLandSale5Years_mt)
    
    -- Initialize state
    self.blockedYears = NoLandSale5Years.defaultBlockedYears
    self.purchaseData = {}
    self.hooksInstalled = false
    
    self:print("TRACE", "Mod instance created.")
    return self
end

-- =============================================================================
-- Logging
-- =============================================================================

function NoLandSale5Years:print(level, message, ...)
    local text = string.format(tostring(message), ...)
    print(string.format("[%s][%s] %s", self.modName, level, text))
end

-- =============================================================================
-- Core Logic
-- =============================================================================

function NoLandSale5Years:canSellFarmland(farmlandId)
    local purchaseYear = self.purchaseData[farmlandId]
    if purchaseYear == nil then
        return true, 0
    end

    local currentYear = g_currentMission.environment.currentYear
    local yearsOwned = currentYear - purchaseYear

    if yearsOwned < self.blockedYears then
        local yearsLeft = self.blockedYears - yearsOwned
        if yearsLeft <= 0 then yearsLeft = 1 end
        return false, yearsLeft
    end

    return true, 0
end

function NoLandSale5Years:showBlockedNotification(yearsLeft)
    local message = string.format(g_i18n:getText("nls5y_block_message"), yearsLeft)
    g_currentMission:showBlinkingWarning(message, 5000)
    self:print("INFO", "Blocked sale. Years left: %d", yearsLeft)
end

-- =============================================================================
-- Hooks
-- =============================================================================

function NoLandSale5Years:onGetCanSellFarmland(superFunc, manager, farmlandId, farmId)
    self:print("TRACE", "Hook onGetCanSellFarmland called for farmland %d", farmlandId)
    local canSell, yearsLeft = self:canSellFarmland(farmlandId)

    if not canSell then
        self:showBlockedNotification(yearsLeft)
        return false
    end

    return superFunc(manager, farmlandId, farmId)
end

function NoLandSale5Years:onSetLandOwnership(superFunc, manager, farmlandId, farmId, price, ...)
    local oldOwnerId = manager:getFarmlandOwner(farmlandId)
    self:print("TRACE", "Hook onSetLandOwnership called for farmland %d. Old owner: %d, New farm: %d", farmlandId, oldOwnerId, farmId)
    
    local result = superFunc(manager, farmlandId, farmId, price, ...)

    if result then
        if oldOwnerId == 0 and farmId ~= 0 then
            local currentYear = g_currentMission.environment.currentYear
            self.purchaseData[farmlandId] = currentYear
            self:print("INFO", "Farmland %d purchased in year %d. Sale is blocked for %d years.", farmlandId, currentYear, self.blockedYears)
        elseif farmId == 0 and oldOwnerId ~= 0 then
            self.purchaseData[farmlandId] = nil
            self:print("INFO", "Farmland %d sold. Purchase record cleared.", farmlandId)
        end
    else
        self:print("WARN", "onSetLandOwnership call failed, transaction was not successful.")
    end

    return result
end

function NoLandSale5Years:installHooks()
    self:print("TRACE", "installHooks() called.")
    if self.hooksInstalled then
        self:print("WARN", "Hooks already installed, skipping.")
        return
    end

    FarmlandManager.getCanSellFarmland = Utils.overwrittenFunction(FarmlandManager.getCanSellFarmland, self.onGetCanSellFarmland, self)
    FarmlandManager.setLandOwnership = Utils.overwrittenFunction(FarmlandManager.setLandOwnership, self.onSetLandOwnership, self)

    self.hooksInstalled = true
    self:print("INFO", "Successfully installed farmland hooks.")
end

-- =============================================================================
-- Configuration
-- =============================================================================

function NoLandSale5Years:loadConfiguration()
    self:print("TRACE", "loadConfiguration() called.")
    local configPath = getUserProfileAppPath() .. "modSettings/" .. self.modName .. "/config.xml"

    if fileExists(configPath) then
        local xmlFile = loadXMLFile("config", configPath)
        if xmlFile ~= 0 then
            local loadedYears = getXMLInt(xmlFile, "config.blockedYears")
            if loadedYears ~= nil and loadedYears >= 0 then
                self.blockedYears = loadedYears
            end
            delete(xmlFile)
        end
    else
        local modDir = getUserProfileAppPath() .. "modSettings/" .. self.modName .. "/"
        if not fileExists(modDir) then
            createFolder(modDir)
        end
        local xmlFile = createXMLFile("config", configPath)
        if xmlFile ~= 0 then
            setXMLInt(xmlFile, "config.blockedYears", self.defaultBlockedYears)
            setXMLString(xmlFile, "config#comment", "Number of years to block land sales after purchase.")
            saveXMLFile(xmlFile)
            delete(xmlFile)
        end
    end
    self:print("INFO", "Configuration loaded. Land sale is blocked for %d years after purchase.", self.blockedYears)
end

-- =============================================================================
-- Savegame and Lifecycle
-- =============================================================================

function NoLandSale5Years:load()
    self:print("INFO", "Event 'load' received. Initialization is handled by 'loadMap' for this mod, so this function is intentionally empty.")
end

function NoLandSale5Years:loadFromXMLFile(xmlFile)
    self:print("TRACE", "loadFromXMLFile() called.")
    self.purchaseData = {}
    local i = 0
    while true do
        local key = string.format("purchaseData.farmland(%d)", i)
        if not hasXMLEntry(xmlFile, key) then break end
        local farmlandId = getXMLInt(xmlFile, key .. "#farmlandId")
        local purchaseYear = getXMLInt(xmlFile, key .. "#purchaseYear")
        if farmlandId ~= nil and purchaseYear ~= nil then
            self.purchaseData[farmlandId] = purchaseYear
        end
        i = i + 1
    end
    self:print("INFO", "Loaded %d purchase records from savegame.", i)
end

function NoLandSale5Years:saveToXMLFile(xmlFile)
    self:print("TRACE", "saveToXMLFile() called.")
    local i = 0
    for farmlandId, purchaseYear in pairs(self.purchaseData) do
        local key = string.format("purchaseData.farmland(%d)", i)
        setXMLInt(xmlFile, key .. "#farmlandId", farmlandId)
        setXMLInt(xmlFile, key .. "#purchaseYear", purchaseYear)
        i = i + 1
    end
    self:print("INFO", "Saved %d purchase records to savegame.", i)
end

function NoLandSale5Years:getSavegameFileName()
    self:print("TRACE", "getSavegameFileName() called.")
    return self.savegameFileName
end

function NoLandSale5Years:loadMap(name)
    self:print("INFO", "Event 'loadMap' received. Initializing mod...")
    self:print("TRACE", "Map name: %s", tostring(name))
    
    -- All initialization logic is moved here because the 'load' event is not reliably fired for extraSourceFiles.
    self:loadConfiguration()
    g_currentMission:addMissionSaveFile(self)
    self:installHooks()
    
    self:print("INFO", "Mod initialized and ready via loadMap.")
end

function NoLandSale5Years:update(dt)
    -- This function is called every frame. Avoid logging here unless for specific debugging.
end

function NoLandSale5Years:delete()
    self:print("TRACE", "Event 'delete' received. Cleaning up.")
end

-- =============================================================================
-- Mod Registration
-- =============================================================================

print("[NoLandSale5Years][TRACE] Creating global instance and registering event listener.")
g_noLandSale5YearsInstance = NoLandSale5Years.new()
addModEventListener(g_noLandSale5YearsInstance)

-- Global functions for extraSourceFiles compatibility
function loadMap(name)
    print("[NoLandSale5Years][TRACE] Global 'loadMap' function called.")
    g_noLandSale5YearsInstance:loadMap(name)
end

function update(dt)
    -- Do not log here, it would spam the log file.
    g_noLandSale5YearsInstance:update(dt)
end

function delete()
    print("[NoLandSale5Years][TRACE] Global 'delete' function called.")
    g_noLandSale5YearsInstance:delete()
end

print("[NoLandSale5Years][TRACE] Script file execution finished.")
