-- NoLandSale5Years.lua
-- FS25 - Strict Sale Blocking, Economy Fix, Save System & Multiplayer Sync

NoLandSale5Years = {}
local NoLandSale5Years_mt = { __index = NoLandSale5Years }

NoLandSale5Years.modName = "NoLandSale5Years"
NoLandSale5Years.defaultBlockedYears = 5

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

-- =============================================================================
-- Core Logic
-- =============================================================================

function NoLandSale5Years:canSellFarmland(farmlandId)
    local purchaseYear = self.purchaseData[farmlandId]
    if purchaseYear == nil then return true, 0 end

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

-- =============================================================================
-- Save/Load System
-- =============================================================================

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
    self:print("INFO", "Дані збережено на сервері.")
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
        self:print("INFO", "Завантажено %d записів з файлу збереження.", i)
    end
end

-- =============================================================================
-- Multiplayer Synchronization (Network Streams)
-- =============================================================================

-- Ця функція викликається сервером, коли підключається новий гравець (відправляємо дані)
function NoLandSale5Years:onWriteStream(streamId, connection)
    if not connection:GetIsServer() then 
        local count = 0
        for _ in pairs(self.purchaseData) do count = count + 1 end
        
        streamWriteInt32(streamId, count)
        for id, year in pairs(self.purchaseData) do
            streamWriteInt32(streamId, id)
            streamWriteInt32(streamId, year)
        end
        self:print("INFO", "Синхронізація: Відправлено %d записів клієнту.", count)
    end
end

-- Ця функція викликається у клієнта, коли він підключається (отримуємо дані від сервера)
function NoLandSale5Years:onReadStream(streamId, connection)
    if connection:GetIsServer() then
        self.purchaseData = {}
        local count = streamReadInt32(streamId)
        
        for i = 1, count do
            local id = streamReadInt32(streamId)
            local year = streamReadInt32(streamId)
            self.purchaseData[id] = year
        end
        self:print("INFO", "Синхронізація: Отримано %d записів від сервера.", count)
    end
end

-- =============================================================================
-- Initialization & Safe Hooks
-- =============================================================================

function NoLandSale5Years:init()
    if self.isInitialized or FarmlandManager == nil then return end
    
    -- ХУК 1: Блокування мережевої події (зупиняє клієнтів від надсилання запиту на продаж)
    if FarmlandStateEvent ~= nil and FarmlandStateEvent.run ~= nil then
        local oldEventRun = FarmlandStateEvent.run
        FarmlandStateEvent.run = function(eventSelf, connection)
            if eventSelf.farmId == 0 then 
                local canSell, _ = self:canSellFarmland(eventSelf.farmlandId)
                if not canSell then
                    return 
                end
            end
            return oldEventRun(eventSelf, connection)
        end
    end

    -- ХУК 2: Відстеження транзакцій + відкат грошей
    local oldSetLandOwnership = FarmlandManager.setLandOwnership
    FarmlandManager.setLandOwnership = function(manager, farmlandId, farmId, ...)
        local oldOwnerId = manager:getFarmlandOwner(farmlandId)
        
        -- Якщо це спроба продажу
        if farmId == 0 and oldOwnerId ~= 0 then
            local canSell, yearsLeft = self:canSellFarmland(farmlandId)
            
            if not canSell then
                local message = string.format("Ви не можете продати цю ділянку ще %d р.", yearsLeft)
                g_currentMission:showBlinkingWarning(message, 5000)
                
                -- Сервер повертає гроші, якщо вони були зараховані
                if g_server ~= nil then
                    local price = 0
                    if manager.farmlands ~= nil and manager.farmlands[farmlandId] ~= nil then
                        price = manager.farmlands[farmlandId].price
                    end
                    
                    if price ~= nil and price > 0 then
                        local moneyType = MoneyType and MoneyType.OTHER or 1
                        g_currentMission:addMoney(-price, oldOwnerId, moneyType, true, true)
                        self:print("INFO", "Відкат транзакції: %d списано з балансу ферми.", price)
                    end
                end
                
                return false
            end
        end
        
        local result = false
        if oldSetLandOwnership ~= nil then
            result = oldSetLandOwnership(manager, farmlandId, farmId, ...)
        end

        -- Фіксація покупок та продажів (Спрацьовує і на сервері, і у клієнтів)
        local newOwnerId = manager:getFarmlandOwner(farmlandId)
        if newOwnerId == farmId and oldOwnerId ~= farmId then
            if oldOwnerId == 0 and farmId ~= 0 then
                if g_currentMission and g_currentMission.environment then
                    local currentYear = g_currentMission.environment.currentYear
                    self.purchaseData[farmlandId] = currentYear
                    self:print("INFO", "Земля %d куплена. Заблоковано на %d років.", farmlandId, self.blockedYears)
                end
            elseif farmId == 0 then
                self.purchaseData[farmlandId] = nil
                self:print("INFO", "Земля %d успішно продана.", farmlandId)
            end
        end
        
        return result
    end

    -- Сервер завантажує дані зі збереження
    if g_server ~= nil then
        self:loadFromSavegame()
    end
    
    self.isInitialized = true
    self:print("INFO", "Мод ініціалізовано. Мультиплеєр та економічний захист увімкнено.")
end

g_noLandSaleInstance = NoLandSale5Years.new()

function NoLandSale5Years:loadMap(name)
    g_noLandSaleInstance:init()
end

function NoLandSale5Years:saveSavegame()
    g_noLandSaleInstance:onSavegameSave()
end

-- Реєструємо слухача для виклику stream-методів
addModEventListener(g_noLandSaleInstance)