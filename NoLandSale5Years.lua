-- NoLandSale5Years.lua
-- FS25 - Strict Sale Blocking, Economy Fix, Save System, Multiplayer Sync & Config

NoLandSale5Years = {}
local NoLandSale5Years_mt = { __index = NoLandSale5Years }

NoLandSale5Years.modName = "NoLandSale5Years"
NoLandSale5Years.DEFAULT_BLOCKED_YEARS = 5 -- Використовуємо константу

-- =============================================================================
-- NETWORK SYNC EVENT
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
        g_noLandSaleInstance:print("INFO", "Sync successful! Client updated.")
    end
end

-- =============================================================================
-- MAIN CLASS
-- =============================================================================

function NoLandSale5Years.new()
    local self = setmetatable({}, NoLandSale5Years_mt)
    self.blockedYears = NoLandSale5Years.DEFAULT_BLOCKED_YEARS
    self.purchaseData = {}
    self.isInitialized = false

    return self
end

-- Допоміжна функція для логування
function NoLandSale5Years:print(level, message, ...)
    print(string.format("[%s][%s] %s", self.modName, level, string.format(message, ...)))
end

-- Завантаження налаштувань з XML
function NoLandSale5Years:loadConfiguration()
    local modSettingsDir = getUserProfileAppPath() .. "modSettings/"
    local myModDir = modSettingsDir .. self.modName .. "/"
    local xmlFilePath = myModDir .. "config.xml"

    if not fileExists(modSettingsDir) then createFolder(modSettingsDir) end
    if not fileExists(myModDir) then createFolder(myModDir) end

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

-- Перевірка, чи можна продати ділянку
-- @param farmlandId ID ділянки
-- @return boolean (можна продати), number (скільки років залишилось)
function NoLandSale5Years:canSellFarmland(farmlandId)
    local purchaseYear = self.purchaseData[farmlandId]
    -- Якщо даних немає, вважаємо, що земля була "завжди" або куплена до встановлення моду
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

-- Збереження даних у сейвгейм
function NoLandSale5Years:onSavegameSave()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return end

    local savegameDir = g_currentMission.missionInfo.savegameDirectory
    if savegameDir == nil then return end

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

-- Завантаження даних із сейвгейму
function NoLandSale5Years:loadFromSavegame()
    local savegameDir = g_currentMission.missionInfo.savegameDirectory
    if savegameDir == nil then return end

    local xmlPath = savegameDir .. "/NoLandSale5Years.xml"
    if fileExists(xmlPath) then
        local xmlFile = loadXMLFile("NoLandSaleXML", xmlPath)
        if xmlFile == 0 then return end

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
    end
end

function NoLandSale5Years:init()
    if self.isInitialized or FarmlandManager == nil then return end

    self:loadConfiguration()

    -- ХУК: Синхронізація при підключенні (безпечний метод)
    FSBaseMission.registerActionEvents = Utils.appendedFunction(FSBaseMission.registerActionEvents,
        function(mission, connection)
            if g_server ~= nil and connection ~= nil then
                connection:sendEvent(NoLandSaleSyncEvent.new(self.blockedYears, self.purchaseData))
            end
        end)

    -- ХУК: Основна логіка володіння
    local oldSetLandOwnership = FarmlandManager.setLandOwnership
    FarmlandManager.setLandOwnership = function(manager, farmlandId, farmId, ...)
        local oldOwnerId = manager:getFarmlandOwner(farmlandId)

        -- Спроба продажу (власник стає 0)
        if farmId == 0 and oldOwnerId ~= 0 then
            local canSell, yearsLeft = self:canSellFarmland(farmlandId)

            if not canSell then
                -- Виводимо попередження гравцеві
                local message = string.format("Ви не можете продати цю землю! Потрібно володіти нею ще %d р.", yearsLeft)
                g_currentMission:showBlinkingWarning(message, 5000)

                -- Повернення грошей на сервері, якщо гра вже встигла їх видати
                if g_server ~= nil then
                    local farmland = manager:getFarmlandById(farmlandId)
                    if farmland ~= nil and farmland.price > 0 then
                        -- Вираховуємо ціну назад, оскільки гра додає її при продажу
                        g_currentMission:addMoney(-farmland.price, oldOwnerId, MoneyType.SHOP_PROPERTY_BUY, true, true)
                    end
                end
                return false -- Скасовуємо зміну власника
            end
        end

        -- Виклик оригінальної функції
        local result = oldSetLandOwnership(manager, farmlandId, farmId, ...)

        -- Фіксуємо дату покупки
        if result and farmId ~= 0 and oldOwnerId == 0 then
            if g_currentMission.environment then
                self.purchaseData[farmlandId] = g_currentMission.environment.currentYear
                self:print("INFO", "Земля %d заблокована на %d років", farmlandId, self.blockedYears)
            end
        elseif result and farmId == 0 then
            -- Видаляємо запис після успішного дозволеного продажу
            self.purchaseData[farmlandId] = nil
        end

        return result
    end

    if g_server ~= nil then self:loadFromSavegame() end
    self.isInitialized = true
end

-- Створення екземпляру
g_noLandSaleInstance = NoLandSale5Years.new()

-- Зв'язок з ігровими подіями
function NoLandSale5Years:loadMap(name)
    self:init()
end

function NoLandSale5Years:saveSavegame()
    self:onSavegameSave()
end

addModEventListener(g_noLandSaleInstance)
