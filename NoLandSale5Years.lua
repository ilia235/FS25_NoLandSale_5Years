-- NoLandSale5Years.lua
-- FS25 - Strict Sale Blocking, Economy Fix, Save System, Multiplayer Sync & UI Blocking

NoLandSale5Years = {}
local NoLandSale5Years_mt = { __index = NoLandSale5Years }

NoLandSale5Years.modName = "NoLandSale5Years"
NoLandSale5Years.defaultBlockedYears = 5

function NoLandSale5Years.new()
    local self = setmetatable({}, NoLandSale5Years_mt)
    self.blockedYears = NoLandSale5Years.defaultBlockedYears
    self.purchaseData = {}
    self.isInitialized = false
    self.isAdminAction = false 
    print(string.format("[%s] Instance created.", NoLandSale5Years.modName))
    return self
end

function NoLandSale5Years:print(level, message, ...)
    print(string.format("[%s][%s] %s", self.modName, level, string.format(message, ...)))
end

-- =============================================================================
-- Admin Access Checker (ОНОВЛЕНО: Жорсткий фільтр для Соло та Звичайного МП)
-- =============================================================================

function NoLandSale5Years:isAdmin(connection)
    -- ГЛОБАЛЬНЕ ПРАВИЛО: Якщо це одиночна гра (соло) — адмінів немає, продаж заборонено всім.
    if g_currentMission ~= nil and g_currentMission.missionDynamicInfo ~= nil then
        if not g_currentMission.missionDynamicInfo.isMultiplayer then
            return false
        end
    end

    -- 1. Перевірка транзакції на сервері (коли гравець тисне "Продати")
    if g_server ~= nil and connection ~= nil then
        -- ЖОРСТКИЙ ФІЛЬТР: Дозволяємо тільки на ВИДІЛЕНОМУ сервері.
        -- Якщо це звичайний хост-гравець у мультиплеєрі, йому також буде заборонено.
        if g_dedicatedServerInfo == nil then
            return false 
        end

        -- Якщо ми точно на виділеному сервері, перевіряємо, чи ввів гравець пароль адміна
        if type(connection.getIsMasterUser) == "function" then
            return connection:getIsMasterUser()
        elseif g_currentMission.userManager ~= nil and type(g_currentMission.userManager.getIsConnectionMasterUser) == "function" then
            return g_currentMission.userManager:getIsConnectionMasterUser(connection)
        end
        return false
    end
    
    -- 2. Локальна клієнтська перевірка (викликається для відображення UI кнопок на карті)
    if g_currentMission ~= nil then
        -- Кнопка розблокується лише якщо гравець залогінився як адмін у мультиплеєрі
        return g_currentMission.isMasterUser == true
    end
    
    return false
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
    self:print("INFO", "Дані збережено. Записів: %d", i)
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
-- Multiplayer Synchronization
-- =============================================================================

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
    
    self.isAdminAction = false 

    -- ХУК 1: Мережева подія (Перевірка перед продажем)
    if FarmlandStateEvent ~= nil and FarmlandStateEvent.run ~= nil then
        local oldEventRun = FarmlandStateEvent.run
        FarmlandStateEvent.run = function(eventSelf, connection)
            if eventSelf.farmId == 0 then 
                
                local hasAdminRights = false
                if g_server ~= nil then
                    hasAdminRights = self:isAdmin(connection)
                else
                    hasAdminRights = self:isAdmin()
                end

                if hasAdminRights then
                    self.isAdminAction = true 
                    self:print("INFO", "Дозвіл на продаж: Користувач є адміністратором виділеного сервера.")
                else
                    local canSell, _ = self:canSellFarmland(eventSelf.farmlandId)
                    if not canSell then
                        self:print("WARNING", "Спроба продажу відхилена: Земля заблокована, немає прав.")
                        return 
                    end
                end
            end
            
            local result = oldEventRun(eventSelf, connection)
            self.isAdminAction = false 
            return result
        end
    end

    -- ХУК 2: Відкат транзакцій (Логіка менеджера)
    local oldSetLandOwnership = FarmlandManager.setLandOwnership
    FarmlandManager.setLandOwnership = function(manager, farmlandId, farmId, ...)
        local oldOwnerId = manager:getFarmlandOwner(farmlandId)
        
        if farmId == 0 and oldOwnerId ~= 0 then
            self:print("DEBUG", "Спроба зміни власності. ID землі: %d. Статус адмін-дії: %s", farmlandId, tostring(self.isAdminAction))
            
            if not self.isAdminAction then
                local canSell, yearsLeft = self:canSellFarmland(farmlandId)
                
                if not canSell then
                    local message = string.format("Ви не можете продати цю ділянку ще %d р.", yearsLeft)
                    g_currentMission:showBlinkingWarning(message, 5000)
                    
                    if g_server ~= nil then
                        local price = 0
                        if manager.farmlands ~= nil and manager.farmlands[farmlandId] ~= nil then
                            price = manager.farmlands[farmlandId].price
                        end
                        
                        if price > 0 then
                            local moneyType = MoneyType and MoneyType.OTHER or 1
                            g_currentMission:addMoney(-price, oldOwnerId, moneyType, true, true)
                            self:print("INFO", "Відкат транзакції: Гроші (-%d) списано з балансу ферми.", price)
                        end
                    end
                    return false
                end
            else
                self:print("INFO", "Транзакція дозволена: Адміністратор продає заблоковану землю.")
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
                    self:print("INFO", "Землю %d куплено фермою %d. Блокування на %d років.", farmlandId, farmId, self.blockedYears)
                end
            elseif farmId == 0 then
                self.purchaseData[farmlandId] = nil
                self:print("INFO", "Землю %d успішно продано.", farmlandId)
            end
        end
        
        return result
    end

    -- ХУК 3: ВІЗУАЛЬНИЙ UI-БЛОКУВАЛЬНИК
    if InGameMenuMapFrame ~= nil and InGameMenuMapFrame.updateFarmlandSelection ~= nil then
        local oldUpdateFarmlandSelection = InGameMenuMapFrame.updateFarmlandSelection
        
        InGameMenuMapFrame.updateFarmlandSelection = function(mapFrameSelf, ...)
            oldUpdateFarmlandSelection(mapFrameSelf, ...)
            
            local farmlandId = mapFrameSelf.selectedFarmlandId or mapFrameSelf.hoveredFarmlandId
            if farmlandId ~= nil and farmlandId ~= 0 then
                
                local ownerId = g_farmlandManager:getFarmlandOwner(farmlandId)
                local myFarmId = g_currentMission:getFarmId()
                
                if ownerId == myFarmId and ownerId ~= 0 then
                    local canSell, _ = self:canSellFarmland(farmlandId)
                    
                    local isClientAdmin = self:isAdmin()
                    
                    if not canSell and not isClientAdmin then
                        if mapFrameSelf.actionBuySellFarmland ~= nil then
                            mapFrameSelf:setButtonState(mapFrameSelf.actionBuySellFarmland, true, false)
                        end
                    end
                end
            end
        end
    end

    if g_server ~= nil then
        self:loadFromSavegame()
    end
    
    self.isInitialized = true
    self:print("INFO", "Мод ініціалізовано. UI-блокування та захист адміна працюють.")
end

g_noLandSaleInstance = NoLandSale5Years.new()

function NoLandSale5Years:loadMap(name)
    g_noLandSaleInstance:init()
end

function NoLandSale5Years:saveSavegame()
    g_noLandSaleInstance:onSavegameSave()
end

addModEventListener(g_noLandSaleInstance)
