NoLandSale = {
    DEBUG = true -- Увімкнути детальне логування
}

local PURCHASE_LOG = {}

-- Безпечне отримання поточного дня
local function getCurrentDay()
    if g_currentMission == nil or g_currentMission.environment == nil then
        print("NoLandSale: WARNING - g_currentMission або environment не доступні")
        return 0
    end
    
    local env = g_currentMission.environment
    if env.currentDay == nil then
        print("NoLandSale: WARNING - currentDay не знайдено")
        return 0
    end
    
    -- У FS25 currentDay завжди має бути числом
    return tonumber(env.currentDay) or 0
end

-- Збереження PURCHASE_LOG у XML
function NoLandSale:savePurchaseLog()
    local settingsPath = getUserProfileAppPath() .. "/modSettings"
    local filePath = settingsPath .. "/NoLandSale.xml"

    -- Try to create XML file; some environments may not have modSettings folder available.
    local xmlFile = createXMLFile("purchaseLog", filePath, "log")
    if xmlFile == nil then
        print(("NoLandSale: не вдалося створити файл налаштувань: %s"):format(tostring(filePath)))
        return
    end

    local i = 0
    for farmlandId, day in pairs(PURCHASE_LOG) do
        local key = string.format("log.entry(%d)", i)
        setXMLInt(xmlFile, key .. "#id", tonumber(farmlandId))
        setXMLInt(xmlFile, key .. "#day", day)
        i = i + 1
    end

    local ok, err = pcall(saveXMLFile, xmlFile)
    if not ok then
        print(("NoLandSale: помилка при збереженні XML: %s"):format(tostring(err)))
    end

    delete(xmlFile)
end

-- Завантаження PURCHASE_LOG з XML
function NoLandSale:loadPurchaseLog()
    local filePath = getUserProfileAppPath() .. "/modSettings/NoLandSale.xml"
    if not fileExists(filePath) then
        -- Nothing to load
        return
    end

    local xmlFile = loadXMLFile("purchaseLog", filePath)
    if xmlFile == nil then
        print(("NoLandSale: не вдалося відкрити файл налаштувань: %s"):format(tostring(filePath)))
        return
    end

    local i = 0
    while true do
        local key = string.format("log.entry(%d)", i)
        if not hasXMLProperty(xmlFile, key) then break end

        local farmlandId = getXMLInt(xmlFile, key .. "#id")
        local day = getXMLInt(xmlFile, key .. "#day")
        if farmlandId ~= nil and day ~= nil then
            PURCHASE_LOG[tostring(farmlandId)] = day
        end
        i = i + 1
    end

    delete(xmlFile)
end

function NoLandSale:loadMap(name)
    print("NoLandSale: Мод завантажується...")
    self:loadPurchaseLog()
    
    -- Відкладаємо перехоплення функцій до повного завантаження гри
    self.initializeTimer = 0
    self.isInitialized = false
end

function NoLandSale:deleteMap()
    self:savePurchaseLog()
end

function NoLandSale:update(dt)
    if not self.isInitialized then
        -- Чекаємо повного завантаження гри
        if self.initializeTimer == nil then
            self.initializeTimer = 0
        end
        
        self.initializeTimer = self.initializeTimer + dt
        if self.initializeTimer >= 1000 then -- 1 секунда
            if g_currentMission ~= nil and g_currentMission.isLoaded then
                self:overwriteBuyFunction()
                self:overwriteSellFunction()
                self.isInitialized = true
                print("NoLandSale: Ініціалізація завершена")
            end
        end
    end
end

local function recordPurchase(farmlandId)
    PURCHASE_LOG[tostring(farmlandId)] = getCurrentDay()
end

function NoLandSale:canSellFarmland(farmlandId)
    local currentDay = getCurrentDay()
    local purchaseDay = PURCHASE_LOG[tostring(farmlandId)]

    if purchaseDay == nil then
        return true
    end

    local daysPassed = currentDay - purchaseDay
    return daysPassed >= 60 -- 5 років по 12 днів
end

function NoLandSale:overwriteSellFunction()
    if g_farmlandManager == nil then
        print("NoLandSale: ERROR - g_farmlandManager не доступний")
        return
    end

    local originalSell = g_farmlandManager.sellFarmland
    if type(originalSell) ~= "function" then
        print("NoLandSale: ERROR - оригінальна функція sellFarmland не знайдена")
        return
    end

    -- Зберігаємо оригінал, щоб уникнути множинного перехоплення
    if self.originalSell == nil then
        self.originalSell = originalSell
    else
        originalSell = self.originalSell
    end

    g_farmlandManager.sellFarmland = function(manager, farmlandId, farmId, ...)
        if self.DEBUG then
            print(("NoLandSale: Спроба продажу ділянки %s"):format(tostring(farmlandId)))
        end

        if not self:canSellFarmland(farmlandId) then
            g_currentMission:showBlinkingWarning("Цю ділянку не можна продати протягом перших 5 років після покупки!", 5000)
            return false
        end

        return originalSell(manager, farmlandId, farmId, ...)
    end
    
    print("NoLandSale: Перехоплення sellFarmland успішно встановлено")
end

function NoLandSale:overwriteBuyFunction()
    if g_farmlandManager == nil then
        print("NoLandSale: ERROR - g_farmlandManager не доступний")
        return
    end

    local originalBuy = g_farmlandManager.buyFarmland
    if type(originalBuy) ~= "function" then
        print("NoLandSale: ERROR - оригінальна функція buyFarmland не знайдена")
        return
    end

    if self.originalBuy == nil then
        self.originalBuy = originalBuy
    else
        originalBuy = self.originalBuy
    end

    g_farmlandManager.buyFarmland = function(manager, farmlandId, farmId, ...)
        if self.DEBUG then
            print(("NoLandSale: Спроба купівлі ділянки %s"):format(tostring(farmlandId)))
        end

        local results = { originalBuy(manager, farmlandId, farmId, ...) }
        local success = results[1]

        if success then
            recordPurchase(farmlandId)
            if self.DEBUG then
                print(("NoLandSale: Зафіксовано покупку ділянки %s (день %s)"):format(
                    tostring(farmlandId), 
                    tostring(getCurrentDay())
                ))
            end
        end

        return table.unpack(results)
    end
    
    print("NoLandSale: Перехоплення buyFarmland успішно встановлено")
end

addModEventListener(NoLandSale)
