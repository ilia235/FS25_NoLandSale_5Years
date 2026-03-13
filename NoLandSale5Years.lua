-- NoLandSale5Years.lua
-- Mod for Farming Simulator 25
-- Prevents selling land parcels for a configurable number of game years

NoLandSale5Years = {}
NoLandSale5Years.modName = "NoLandSale5Years"
NoLandSale5Years.blockedYears = 5
NoLandSale5Years.startYear = nil
NoLandSale5Years.currentYear = 1
NoLandSale5Years.isInitialized = false
NoLandSale5Years.originalSellFarmland = nil
NoLandSale5Years.originalBuyFarmland = nil
NoLandSale5Years.lastBlockedTime = 0
NoLandSale5Years.setBlockedTime = function(self)
    local timeValue = 0
    if getTime ~= nil then
        timeValue = getTime()
        self.BLOCK_TIMEOUT = 2000  -- getTime returns seconds
    elseif g_time ~= nil and g_time.current ~= nil then
        timeValue = g_time.current
        self.BLOCK_TIMEOUT = 2000  -- milliseconds
    else
        timeValue = 1
        self.BLOCK_TIMEOUT = 2000
    end
    self.lastBlockedTime = timeValue
    self:logDebug(string.format("setBlockedTime: set to %s (timeout=%s)", tostring(timeValue), tostring(self.BLOCK_TIMEOUT)))
end
NoLandSale5Years.logLevel = "DEBUG" -- DEBUG, INFO, WARN, ERROR
NoLandSale5Years._lastBlockedLogKey = nil
NoLandSale5Years._didRun = false
NoLandSale5Years.lastOwnerByFarmlandId = {}
NoLandSale5Years._farmlandHooksInstalled = false
NoLandSale5Years._dayChangeListenerRegistered = false
NoLandSale5Years._uiHooksInstalled = false
NoLandSale5Years._pendingUIHooks = false
NoLandSale5Years.originalShowScreen = nil

-- Check if farmland sale is currently blocked (with timeout)
NoLandSale5Years.isFarmlandSaleBlocked = function(self)
    if self.lastBlockedTime > 0 then
        -- Use getTime() if available, otherwise use g_time
        local currentTime = 0
        if getTime ~= nil then
            currentTime = getTime()
        elseif g_time ~= nil and g_time.current ~= nil then
            currentTime = g_time.current
        end
        
        if currentTime ~= nil and currentTime > 0 then
            local diff = 0
            if getTime ~= nil then
                diff = (currentTime - self.lastBlockedTime) * 1000  -- convert to ms
            else
                diff = currentTime - self.lastBlockedTime
            end
            self:logDebug(string.format("isFarmlandSaleBlocked: lastBlockedTime=%s currentTime=%s diff=%s timeout=%s", 
                tostring(self.lastBlockedTime), tostring(currentTime), tostring(diff), tostring(self.BLOCK_TIMEOUT)))
            
            if diff < self.BLOCK_TIMEOUT then
                return true
            else
                self.lastBlockedTime = 0
            end
        end
    end
    return false
end

NoLandSale5Years.BLOCK_TIMEOUT = 2000  -- 2 seconds timeout to unblock

NoLandSale5Years._logLevelValue = function(self, level)
    if level == "DEBUG" then
        return 10
    elseif level == "INFO" then
        return 20
    elseif level == "WARN" then
        return 30
    elseif level == "ERROR" then
        return 40
    end

    return 20
end

NoLandSale5Years._getEnvContext = function(self)
    local yearStr = "n/a"
    local dayStr = "n/a"

    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        if g_currentMission.environment.currentYear ~= nil then
            yearStr = tostring(g_currentMission.environment.currentYear)
        end
        if g_currentMission.environment.currentDay ~= nil then
            dayStr = tostring(g_currentMission.environment.currentDay)
        end
    end

    return string.format("year=%s day=%s", yearStr, dayStr)
end

NoLandSale5Years.log = function(self, level, message)
    if message == nil then
        return
    end

    local configuredLevel = self.logLevel or "INFO"
    if self:_logLevelValue(level) < self:_logLevelValue(configuredLevel) then
        return
    end

    local prefix = string.format("[%s][%s][%s]", self.modName, tostring(level), self:_getEnvContext())
    print(string.format("%s %s", prefix, tostring(message)))
end

NoLandSale5Years.logDebug = function(self, message) self:log("DEBUG", message) end
NoLandSale5Years.logInfo = function(self, message) self:log("INFO", message) end
NoLandSale5Years.logWarn = function(self, message) self:log("WARN", message) end
NoLandSale5Years.logError = function(self, message) self:log("ERROR", message) end

-- Register mod
NoLandSale5Years.registerInit = function()
    -- Register this mod
end

NoLandSale5Years.load = function(self)
    self:logInfo("Loading mod...")
    -- Configuration will be loaded in run() when mission is ready
    self.isInitialized = true
    self:logInfo(string.format("Mod loaded. Land sale blocked for %d years.", self.blockedYears))
end

NoLandSale5Years.getConfigPaths = function(self)
    local basePath = ""
    if getUserProfileAppPath ~= nil then
        basePath = getUserProfileAppPath()
    end

    local modSettingsRoot = basePath .. "modSettings/"
    local modFolderPath = modSettingsRoot .. self.modName .. "/"
    local filePath = modFolderPath .. "config.xml"

    return modSettingsRoot, modFolderPath, filePath
end

NoLandSale5Years.loadConfiguration = function(self)
    -- Check if file system functions are available
    if getUserProfileAppPath == nil then
        self:logWarn("getUserProfileAppPath not available, using default config")
        return
    end
    
    local basePath = getUserProfileAppPath()
    if basePath == nil or basePath == "" then
        self:logWarn("Could not get user profile path, using default config")
        return
    end

    local modSettingsRoot = basePath .. "modSettings/"
    local modFolderPath = modSettingsRoot .. self.modName .. "/"
    local filePath = modFolderPath .. "config.xml"

    -- 1. Create folder in modSettings if it doesn't exist
    if createFolder ~= nil and not fileExists(modFolderPath) then
        createFolder(modFolderPath)
    end

    -- 2. If file doesn't exist, create default XML
    if not fileExists(filePath) then
        self:logInfo("Configuration not found. Creating default: " .. filePath)
        if createXMLFile ~= nil and setXMLInt ~= nil and saveXMLFile ~= nil and delete ~= nil then
            local xmlFile = createXMLFile("config", filePath, "NoLandSale5Years")
            if xmlFile ~= nil and xmlFile ~= 0 then
                setXMLInt(xmlFile, "NoLandSale5Years.blockedYears", self.blockedYears)
                saveXMLFile(xmlFile)
                delete(xmlFile)
            end
        end
    else
        -- 3. Read existing config
        if loadXMLFile ~= nil and getXMLInt ~= nil and delete ~= nil then
            local xmlFile = loadXMLFile("config", filePath)
            if xmlFile ~= nil and xmlFile ~= 0 then
                local loadedYears = getXMLInt(xmlFile, "NoLandSale5Years.blockedYears")
                if loadedYears ~= nil then
                    self.blockedYears = loadedYears
                end
                self:logInfo(string.format("Configuration loaded. Blocked years: %d", self.blockedYears))
                delete(xmlFile)
            end
        end
    end
end

-- Таблиця для збереження дат купівлі землі
NoLandSale5Years.purchaseYears = {}

-- Слідкуємо за купівлею землі, щоб зафіксувати рік
NoLandSale5Years.onSetLandOwnership = function(self, manager, superFunc, farmlandId, farmId)
    local oldOwner = manager:getFarmlandOwner(farmlandId)
    local result = superFunc(manager, farmlandId, farmId)
    
    -- Якщо землю КУПИЛИ (власник змінився з 0 на когось іншого)
    if oldOwner == 0 and farmId ~= 0 then
        local currentYear = g_currentMission.environment.currentYear
        self.purchaseYears[farmlandId] = currentYear
        self:logInfo(string.format("Ділянку %d куплено у році %d. Продаж заборонено на %d років.", 
            farmlandId, currentYear, self.blockedYears))
    end
    
    -- Якщо землю ПРАВИЛЬНО продали (через 5 років), видаляємо запис
    if farmId == 0 and oldOwner ~= 0 then
        self.purchaseYears[farmlandId] = nil
    end
    
    return result
end

-- Головна логіка: ПЕРЕВІРКА МОЖЛИВОСТІ ПРОДАЖУ
NoLandSale5Years.canSellFarmlandById = function(self, farmlandId)
    local purchaseYear = self.purchaseYears[farmlandId]
    
    -- Якщо ми не знаємо, коли купили - вважаємо що можна продати
    if purchaseYear == nil then return true, 0 end
    
    local currentYear = g_currentMission.environment.currentYear
    local yearsOwned = currentYear - purchaseYear
    
    if yearsOwned < self.blockedYears then
        local yearsLeft = self.blockedYears - yearsOwned
        return false, yearsLeft
    end
    
    return true, 0
end

-- ХУК ДЛЯ МЕНЮ (Блокування кнопки в інтерфейсі)
NoLandSale5Years.overwrittenCanSellFarmland = function(self, manager, superFunc, farmlandId, farmId)
    local canSell, yearsLeft = self:canSellFarmlandById(farmlandId)
    
    if not canSell then
        -- Виводимо повідомлення гравцеві
        if g_gui ~= nil and g_gui.getIsGuiVisible ~= nil and g_gui:getIsGuiVisible() then
            if g_currentMission ~= nil and g_currentMission.showBlinkingWarning ~= nil then
                g_currentMission:showBlinkingWarning(string.format("Цю землю не можна продати ще %d р.!", yearsLeft), 2000)
            end
        end
        return false
    end
    
    return superFunc(manager, farmlandId, farmId)
end

-- Реєстрація хуків
NoLandSale5Years.installHooks = function(self)
    if not self._farmlandHooksInstalled then
        -- Перехоплюємо setLandOwnership для відстеження купівлі
        if FarmlandManager ~= nil and FarmlandManager.setLandOwnership ~= nil and Utils ~= nil and Utils.overwrittenFunction ~= nil then
            FarmlandManager.setLandOwnership = Utils.overwrittenFunction(FarmlandManager.setLandOwnership, 
                function(...) return self:onSetLandOwnership(...) end)
            self:logInfo("Hooked FarmlandManager.setLandOwnership")
        end
        
        -- Перехоплюємо getCanSellFarmland для блокування кнопки
        if FarmlandManager ~= nil and FarmlandManager.getCanSellFarmland ~= nil and Utils ~= nil and Utils.overwrittenFunction ~= nil then
            FarmlandManager.getCanSellFarmland = Utils.overwrittenFunction(FarmlandManager.getCanSellFarmland,
                function(...) return self:overwrittenCanSellFarmland(...) end)
            self:logInfo("Hooked FarmlandManager.getCanSellFarmland")
        end
        
        self._farmlandHooksInstalled = true
    end
end

NoLandSale5Years.run = function(self)
    if self._didRun then
        self:logDebug("run() called again; ignoring (already initialized)")
        return
    end
    self._didRun = true

    -- Load config here too (in case load() isn't called in this game version)
    self:loadConfiguration()

    self:logInfo("Starting mod...")
    
    -- Get start year from mission
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        self.startYear = g_currentMission.environment.currentYear
        self.currentYear = self.startYear
        self:logInfo(string.format("Captured startYear=%s currentYear=%s blockedYears=%d", tostring(self.startYear), tostring(self.currentYear), self.blockedYears))
    else
        self:logWarn("Mission/environment not available yet; startYear not captured")
    end
    
    -- Install hooks for farmland sale blocking
    self:installHooks()
    
    self:logInfo(string.format("Mod started. Land sale blocked for %d years.", self.blockedYears))
end

NoLandSale5Years.initializeFarmlandOwners = function(self)
    -- Initialize farmland owners from the farmland manager
    if g_farmlandManager ~= nil then
        local farmlands = g_farmlandManager:getFarmlands()
        if farmlands ~= nil then
            for farmlandId, farmland in pairs(farmlands) do
                if farmland ~= nil and farmland.owner ~= nil then
                    self.lastOwnerByFarmlandId[farmlandId] = farmland.owner
                    self:logDebug(string.format("Initialized farmland %d owner to %d", farmlandId, farmland.owner))
                end
            end
            self:logInfo(string.format("Initialized %d farmland owners", #farmlands))
        end
    end
end

NoLandSale5Years.registerDayChangeCallback = function(self)
    -- Try different callback registration methods for FS25 compatibility
    
    -- Method 1: Try g_callbackManager (older FS versions)
    if g_callbackManager ~= nil and g_callbackManager.registerCallback ~= nil then
        g_callbackManager:registerCallback("onDayChanged", self.onDayChanged, self)
        self._dayChangeListenerRegistered = true
        self:logDebug("Registered onDayChanged callback via g_callbackManager")
        return
    end
    
    -- Method 2: Try g mission:addDayChangeListener (FS25)
    if g_currentMission ~= nil and g_currentMission.addDayChangeListener ~= nil then
        g_currentMission:addDayChangeListener(self)
        self._dayChangeListenerRegistered = true
        self:logDebug("Registered day change listener via g_currentMission:addDayChangeListener")
        return
    end
    
    -- Method 3: Try DayChanged listener (alternative FS25)
    if g_currentMission ~= nil and g_currentMission.registerEvent ~= nil then
        local dayChangedEvent = g_currentMission.registerEvent(g_currentMission, "onDayChanged")
        if dayChangedEvent ~= nil then
            dayChangedEvent:register(self.onDayChanged, self)
            self._dayChangeListenerRegistered = true
            self:logDebug("Registered onDayChanged event")
            return
        end
    end
    
    -- Method 4: Try g_currentMission.onDayChanged (direct assignment)
    if g_currentMission ~= nil then
        local originalDayChanged = g_currentMission.onDayChanged
        g_currentMission.onDayChanged = function(...)
            if originalDayChanged then
                originalDayChanged(...)
            end
            self:onDayChanged()
        end
        self._dayChangeListenerRegistered = true
        self:logDebug("Registered onDayChanged via direct hook")
        return
    end
    
    self:logWarn("No callback registration method available; year tracking may not work")
end

NoLandSale5Years.onDayChanged = function(self)
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        local newYear = g_currentMission.environment.currentYear
        if newYear ~= self.currentYear then
            self.currentYear = newYear
            self:logInfo(string.format("Year changed. currentYear=%s startYear=%s", tostring(self.currentYear), tostring(self.startYear)))
        else
            self:logDebug(string.format("Day changed, year unchanged (currentYear=%s)", tostring(self.currentYear)))
        end
    else
        self:logDebug("onDayChanged fired but mission/environment is nil")
    end
end

NoLandSale5Years.overrideFarmlandSale = function(self)
    if self._farmlandHooksInstalled then
        self:logDebug("Farmland hooks already installed")
        return
    end
    
    local hooked = false
    
    -- Debug: Search for money-related functions that might be involved in farmland sale
    self:logInfo("=== Searching for farmland and money functions ===")
    
    -- Check FarmManager for money-related functions
    if FarmManager ~= nil then
        self:logInfo("FarmManager class found - checking functions...")
        local moneyFuncs = {}
        for k, v in pairs(FarmManager) do
            if type(v) == "function" and (string.find(string.lower(tostring(k)), "money") or string.find(string.lower(tostring(k)), "cash") or string.find(string.lower(tostring(k)), "fund") or string.find(string.lower(tostring(k)), "balance")) then
                table.insert(moneyFuncs, tostring(k))
                self:logDebug(string.format("FarmManager.%s = function (MONEY RELATED)", tostring(k)))
            end
        end
        if #moneyFuncs > 0 then
            self:logInfo(string.format("Found money-related: %s", table.concat(moneyFuncs, ", ")))
        end
    end
    
    -- Check Farm for money functions
    if Farm ~= nil then
        self:logInfo("Farm class found - checking...")
        local farmMoneyFuncs = {}
        for k, v in pairs(Farm) do
            if type(v) == "function" and (string.find(string.lower(tostring(k)), "money") or string.find(string.lower(tostring(k)), "cash") or string.find(string.lower(tostring(k)), "addMoney") or string.find(string.lower(tostring(k)), "setMoney")) then
                table.insert(farmMoneyFuncs, tostring(k))
                self:logDebug(string.format("Farm.%s = function (MONEY)", tostring(k)))
            end
        end
        if #farmMoneyFuncs > 0 then
            self:logInfo(string.format("Found Farm money-related: %s", table.concat(farmMoneyFuncs, ", ")))
        end
    end
    
    -- Check g_farmManager if exists
    if g_farmManager ~= nil then
        self:logInfo("g_farmManager found - checking functions...")
        for k, v in pairs(g_farmManager) do
            if type(v) == "function" and string.find(string.lower(tostring(k)), "money") then
                self:logDebug(string.format("g_farmManager.%s = function (MONEY)", tostring(k)))
            end
        end
    end
    
    -- Also check g_currentMission for money
    if g_currentMission ~= nil and g_currentMission.farm ~= nil then
        self:logInfo("g_currentMission.farm found")
        local farm = g_currentMission.farm
        for k, v in pairs(farm) do
            if type(v) == "function" and string.find(string.lower(tostring(k)), "money") then
                self:logDebug(string.format("farm.%s = function (MONEY)", tostring(k)))
            end
        end
    end
    
    -- Check g_farmlandManager and list its functions
    if g_farmlandManager ~= nil then
        self:logInfo("g_farmlandManager found - checking functions...")
        local count = 0
        local funcList = {}
        for k, v in pairs(g_farmlandManager) do
            if type(v) == "function" then
                count = count + 1
                table.insert(funcList, tostring(k))
                self:logDebug(string.format("g_farmlandManager.%s = function", tostring(k)))
            end
        end
        self:logInfo(string.format("g_farmlandManager has %d functions: %s", count, table.concat(funcList, ", ")))
    else
        self:logWarn("g_farmlandManager is nil")
    end
    
    -- Check FarmlandManager class
    if FarmlandManager ~= nil then
        self:logInfo("FarmlandManager class found - checking functions...")
        local count = 0
        local funcList = {}
        for k, v in pairs(FarmlandManager) do
            if type(v) == "function" then
                count = count + 1
                table.insert(funcList, tostring(k))
                self:logDebug(string.format("FarmlandManager.%s = function", tostring(k)))
            end
        end
        self:logInfo(string.format("FarmlandManager class has %d functions: %s", count, table.concat(funcList, ", ")))
    else
        self:logWarn("FarmlandManager class is nil")
    end
    
    -- Check FarmlandInfo
    if FarmlandInfo ~= nil then
        self:logInfo("FarmlandInfo class found - checking functions...")
        local count = 0
        local funcList = {}
        for k, v in pairs(FarmlandInfo) do
            if type(v) == "function" then
                count = count + 1
                table.insert(funcList, tostring(k))
                self:logDebug(string.format("FarmlandInfo.%s = function", tostring(k)))
            end
        end
        self:logInfo(string.format("FarmlandInfo class has %d functions: %s", count, table.concat(funcList, ", ")))
    else
        self:logDebug("FarmlandInfo class not found")
    end
    
    -- Try multiple tables and method names for FS25 compatibility
    local tablesToCheck = {
        { table = g_farmlandManager, name = "g_farmlandManager" },
        { table = FarmlandManager, name = "FarmlandManager" },
        { table = FarmlandInfo, name = "FarmlandInfo" },
        { table = g_currentMission, name = "g_currentMission" },
    }
    
    -- FS25 might use different method names - try all common variations
    -- KEY: setLandOwnership is the main function for changing ownership in FS25!
    local methodNames = {
        "setLandOwnership",
        "sellFarmland",
        "buyFarmland",
        "rentFarmland",
        "unrentFarmland",
        "sell",
        "buy",
        "purchaseFarmland",
        "releaseFarmland",
        "setFarmlandOwner",
        "changeOwner",
        "setOwner",
    }
    
    for _, tableInfo in ipairs(tablesToCheck) do
        local targetTable = tableInfo.table
        local label = tableInfo.name
        
        if targetTable == nil then
            self:logDebug(string.format("Table %s is nil, skipping", label))
        else
            self:logDebug(string.format("Checking %s for farmland methods", label))
            
            -- Try to hook sellFarmland FIRST (most likely in FS25)
            if targetTable.sellFarmland ~= nil and self.originalSellFarmland == nil then
                self.originalSellFarmland = targetTable.sellFarmland
                
                targetTable.sellFarmland = function(...)
                    local args = {...}
                    local farmlandId = args[1] or args[2]
                    local farmId = args[2] or args[3]
                    
                    self:logInfo(string.format("%s.sellFarmland called (farmlandId=%s farmId=%s)", label, tostring(farmlandId), tostring(farmId)))
                    
                    -- Check if sale is allowed
                    local allowed, reason = self:canSellFarmland()
                    if not allowed then
                        self:setBlockedTime()
                        self:logInfo(string.format("BLOCKING sellFarmland (farmlandId=%s). %s", tostring(farmlandId), tostring(reason)))
                        self:showBlockedMessage(farmlandId, farmId, reason)
                        return false
                    end
                    
                    local result = self.originalSellFarmland(...)
                    self.lastBlockedTime = 0
                    return result
                end
                
                hooked = true
                self:logInfo(string.format("Hooked %s.sellFarmland", label))
            end
            
            -- Try to hook setLandOwnership
            for _, methodName in ipairs(methodNames) do
                if targetTable[methodName] ~= nil and self.originalSellFarmland == nil then
                    self.originalSellFarmland = targetTable[methodName]
                    
                    -- Store the original table and method for later
                    local origTable = targetTable
                    local origMethodName = methodName
                    local mod = self
                    
                    targetTable[methodName] = function(...)
                        local args = {...}
                        local manager = args[1]
                        local farmlandId = args[2]
                        local farmId = args[3]
                        
                        mod:logInfo(string.format("%s called (farmlandId=%s farmId=%s)", methodName, tostring(farmlandId), tostring(farmId)))
                        
                        -- Check if this is a sale (farmId = 0 or nil means selling to no one)
                        local isSale = false
                        if methodName == "setLandOwnership" then
                            -- setLandOwnership(farmlandId, farmId, ...)
                            -- farmId = 0 or nil means land is being sold/released
                            if farmId == nil or farmId == 0 then
                                isSale = true
                                mod:logInfo("Detected land SALE via setLandOwnership")
                            else
                                -- Reset blocked flag when land is bought/transferred (not sold)
                                mod.lastBlockedTime = 0
                                mod:logDebug("Land transaction (not sale) - resetting blocked flag")
                            end
                        end
                        
                        -- FIRST: Call original function to allow the transaction
                        local result = mod.originalSellFarmland(...)
                        
                        -- THEN: Check if sale happened and if it's blocked
                        if isSale and result then
                            local allowed, reason = mod:canSellFarmland()
                            if not allowed then
                                mod:logInfo(string.format("BLOCKING land %s (farmlandId=%s farmId=%s). %s", methodName, tostring(farmlandId), tostring(farmId), tostring(reason)))
                                mod:showBlockedMessage(farmlandId, farmId, reason)
                                
                                -- Get the farm that bought the land (or current farm)
                                local farmId = g_currentMission ~= nil and g_currentMission.farmId or 1
                                local farm = g_farmManager:getFarmById(farmId)
                                
                                if farm ~= nil then
                                    -- Get the sale price and subtract it (return money)
                                    local price = mod:getFarmlandPrice(farmlandId)
                                    if price > 0 then
                                        -- Try different methods to add/subtract money
                                        if farm.addMoney ~= nil then
                                            farm:addMoney(-price, farmId, "landSale", -1)
                                            mod:logInfo(string.format("Returned money via addMoney: price=%d", price))
                                        elseif farm.money ~= nil then
                                            farm.money = farm.money - price
                                            mod:logInfo(string.format("Returned money via money property: price=%d", price))
                                        else
                                            mod:logWarn("Could not find method to return money")
                                        end
                                    end
                                end
                                
                                -- Reset ownership back to original owner
                                local farmland = g_farmlandManager:getFarmlandById(farmlandId)
                                if farmland ~= nil and farmland.owner ~= nil then
                                    g_farmlandManager:setLandOwnership(farmlandId, farmland.owner)
                                    mod:logInfo(string.format("Reset farmland %d ownership back to farm %d", farmlandId, farmland.owner))
                                end
                                
                                return false
                            end
                        end
                        
                        if result then
                            mod:logInfo(string.format("%s success (farmlandId=%s)", methodName, tostring(farmlandId)))
                            -- Reset blocked flag after successful sale
                            mod.lastBlockedTime = 0
                        end
                        
                        return result
                    end
                    
                    hooked = true
                    mod:logInfo(string.format("Hooked %s.%s", label, methodName))
                    break
                end
            end
        end
    end
    
    -- Try hooking FarmlandManager class methods (static)
    if FarmlandManager ~= nil then
        self:logDebug("Checking FarmlandManager class methods")
        
        -- KEY: Try setLandOwnership as static method too
        local staticMethods = {"setLandOwnership", "sellFarmland", "buyFarmland", "rentFarmland"}
        for _, methodName in ipairs(staticMethods) do
            if FarmlandManager[methodName] ~= nil and self.originalSellFarmland == nil then
                self.originalSellFarmland = FarmlandManager[methodName]
                local mod = self
                
                FarmlandManager[methodName] = function(...)
                    local args = {...}
                    local farmlandId = args[1]
                    local farmId = args[2]
                    
                    mod:logInfo(string.format("FarmlandManager.%s called (farmlandId=%s farmId=%s)", methodName, tostring(farmlandId), tostring(farmId)))
                    
                    -- Check if this is a sale
                    local isSale = false
                    if methodName == "setLandOwnership" and (farmId == nil or farmId == 0) then
                        isSale = true
                        mod:logInfo("Detected land SALE via FarmlandManager.setLandOwnership")
                    elseif methodName == "setLandOwnership" and farmId ~= nil and farmId ~= 0 then
                        -- Reset flag when land is bought/transferred
                        mod.lastBlockedTime = 0
                    elseif methodName == "sellFarmland" then
                        isSale = true
                        mod:logInfo("Detected land SALE via FarmlandManager.sellFarmland")
                    end
                    
                    -- FIRST: Call original function
                    local result = mod.originalSellFarmland(...)
                    
                    -- THEN: Check if sale happened and if it's blocked
                    if isSale and result then
                        local allowed, reason = mod:canSellFarmland()
                        if not allowed then
                            mod:logInfo(string.format("BLOCKING FarmlandManager.%s (farmlandId=%s). %s", methodName, tostring(farmlandId), tostring(reason)))
                            mod:showBlockedMessage(farmlandId, farmId, reason)
                            
                            -- Get the farm that bought the land
                            local targetFarmId = farmId or (g_currentMission ~= nil and g_currentMission.farmId) or 1
                            local farm = g_farmManager:getFarmById(targetFarmId)
                            
                            if farm ~= nil then
                                -- Get the sale price and subtract it (return money)
                                local price = mod:getFarmlandPrice(farmlandId)
                                if price > 0 then
                                    -- Try different methods to add/subtract money
                                    if farm.addMoney ~= nil then
                                        farm:addMoney(-price, targetFarmId, "landSale", -1)
                                        mod:logInfo(string.format("Returned money via addMoney: price=%d", price))
                                    elseif farm.money ~= nil then
                                        farm.money = farm.money - price
                                        mod:logInfo(string.format("Returned money via money property: price=%d", price))
                                    else
                                        mod:logWarn("Could not find method to return money")
                                    end
                                end
                            end
                            
                            -- Reset ownership back to original owner
                            local farmland = g_farmlandManager:getFarmlandById(farmlandId)
                            if farmland ~= nil and farmland.owner ~= nil then
                                g_farmlandManager:setLandOwnership(farmlandId, farmland.owner)
                                mod:logInfo(string.format("Reset farmland %d ownership back to farm %d", farmlandId, farmland.owner))
                            end
                            
                            return false
                        end
                    end
                    
                    if result then
                        mod.lastBlockedTime = 0
                    end
                    
                    return result
                end
                
                hooked = true
                self:logInfo(string.format("Hooked FarmlandManager.%s (static)", methodName))
                break
            end
        end
    end
    
    -- Try hooking FarmlandInfo:delete() - might be called when selling
    if FarmlandInfo ~= nil and FarmlandInfo.delete ~= nil and self.originalSellFarmland == nil then
        self.originalSellFarmland = FarmlandInfo.delete
        
        FarmlandInfo.delete = function(...)
            self:logInfo("FarmlandInfo.delete called - potential sale?")
            local allowed, reason = self:canSellFarmland()
            if not allowed then
                self:setBlockedTime()
                self:logInfo(string.format("Blocking FarmlandInfo.delete. %s", tostring(reason)))
                self:showBlockedMessage(nil, nil, reason)
                return false
            end
            local result = self.originalSellFarmland(...)
            self.lastBlockedTime = 0
            return result
        end
        
        hooked = true
        self:logInfo("Hooked FarmlandInfo.delete")
    end
    
    self._farmlandHooksInstalled = hooked
    
    -- Money blocking is now done by returning money after blocked sale
    -- self:overrideMoneyFunctions()
    
    if hooked then
        self:logInfo("Farmland hooks installed successfully")
    else
        self:logWarn("No known function found to override for land sale/ownership; land sale may not be blocked")
    end
end

NoLandSale5Years.canSellFarmland = function(self)
    -- If start year is not set, allow sale
    if self.startYear == nil then
        return true, "startYear is nil (mission not initialized yet)"
    end
    
    -- Calculate how many years have passed
    local yearsPassed = self.currentYear - self.startYear
    
    -- If more years have passed than blocked years, allow sale
    if yearsPassed >= self.blockedYears then
        return true, string.format("yearsPassed=%d >= blockedYears=%d", yearsPassed, self.blockedYears)
    end
    
    -- Sale is blocked
    local yearsRemaining = self.blockedYears - yearsPassed
    return false, string.format("yearsPassed=%d < blockedYears=%d (remaining=%d)", yearsPassed, self.blockedYears, yearsRemaining)
end

-- Get farmland price
NoLandSale5Years.getFarmlandPrice = function(self, farmlandId)
    if g_farmlandManager == nil then
        return 0
    end
    
    local farmland = g_farmlandManager:getFarmlandById(farmlandId)
    if farmland == nil then
        return 0
    end
    
    -- Try different ways to get price
    if farmland.price ~= nil then
        return farmland.price
    end
    
    if farmland.getPrice ~= nil then
        return farmland:getPrice()
    end
    
    if farmland.basePrice ~= nil then
        return farmland.basePrice
    end
    
    return 0
end

-- Money functions override disabled - we now return money after sale instead
-- NoLandSale5Years.overrideMoneyFunctions = function(self)
-- This approach was causing issues with timeout
-- Instead we now: allow sale -> check if blocked -> return money if blocked

NoLandSale5Years.showBlockedMessage = function(self, farmlandId, farmId, reason)
    local yearsRemaining = self.blockedYears - (self.currentYear - self.startYear)
    local logKey = string.format("%s|%s|%s|%s", tostring(self.currentYear), tostring(farmlandId), tostring(farmId), tostring(yearsRemaining))
    if self._lastBlockedLogKey ~= logKey then
        self._lastBlockedLogKey = logKey
        self:logDebug(string.format("showBlockedMessage (farmlandId=%s farmId=%s remaining=%d) reason=%s", tostring(farmlandId), tostring(farmId), yearsRemaining, tostring(reason)))
    end
    
    local message = string.format("Продаж землі заблоковано! Залишилось %d років(рік).", yearsRemaining)
    
    -- Try multiple methods to show message
    
    -- Method 1: g_currentMission:showBlinkingWarning
    if g_currentMission ~= nil then
        -- Check for different warning functions
        if g_currentMission.showBlinkingWarning ~= nil then
            -- Call on next frame to ensure UI is ready
            g_currentMission:showBlinkingWarning(message, 5000)
            self:logInfo("Showing message via showBlinkingWarning")
            return
        elseif g_currentMission.showWarning ~= nil then
            g_currentMission:showWarning(message)
            self:logInfo("Showing message via showWarning")
            return
        elseif g_currentMission.addInfoMessage ~= nil then
            g_currentMission:addInfoMessage(message)
            self:logInfo("Showing message via addInfoMessage")
            return
        elseif g_currentMission.showMessage ~= nil then
            g_currentMission:showMessage(0, 0, message)
            self:logInfo("Showing message via showMessage")
            return
        end
    end
    
    -- Method 2: g_gui:showMessageDialog
    if g_gui ~= nil and g_gui.showMessageDialog ~= nil then
        g_gui:showMessageDialog(
            g_i18n:getText("ui_error"),
            message,
            nil
        )
        self:logInfo("Showing message via showMessageDialog")
        return
    end
    
    -- Method 3: g_gui:showInfoDialog
    if g_gui ~= nil and g_gui.showInfoDialog ~= nil then
        g_gui:showInfoDialog(
            message,
            nil
        )
        self:logInfo("Showing message via showInfoDialog")
        return
    end
    
    -- Method 4: Try to show via screen
    if g_gui ~= nil and g_gui.currentScreen ~= nil then
        -- Try to get screen and show message
        local screen = g_gui.currentScreen
        if screen.showMessage ~= nil then
            screen:showMessage(message)
            self:logInfo("Showing message via screen:showMessage")
            return
        end
    end
    
    -- Fallback: log only
    self:logInfo(message)
end

NoLandSale5Years.overrideUIScreens = function(self)
    if self._uiHooksInstalled then
        self:logDebug("UI hooks already installed")
        return
    end
    
    self:logInfo("=== Installing UI hooks for farmland buttons ===")
    
    -- Wait for GUI to be ready
    local function tryInstallHooks()
        if g_gui == nil then
            self:logDebug("g_gui not ready, will retry...")
            return false
        end
        
        -- FS25 uses g_gui.screenDebug to get current screen, not findScreenByName
        -- Try different methods to get current screen
        
        -- Method 1: Try g_gui.currentScreen
        local currentScreen = nil
        if g_gui.currentScreen ~= nil then
            currentScreen = g_gui.currentScreen
            self:logDebug("Found currentScreen via g_gui.currentScreen")
        end
        
        -- Hook g_gui.showScreen if available
        if g_gui ~= nil and g_gui.showScreen ~= nil and self.originalShowScreen == nil then
            self.originalShowScreen = g_gui.showScreen
            
            g_gui.showScreen = function(...)
                local result = self.originalShowScreen(...)
                
                -- After showScreen, try to get the screen
                if g_gui.currentScreen ~= nil then
                    local screen = g_gui.currentScreen
                    if screen ~= nil then
                        -- Check if it's a farmland screen
                        local screenClass = screen.class or screen.className
                        if screenClass ~= nil then
                            local screenName = tostring(screenClass)
                            if string.find(screenName, "Farmland") or string.find(screenName, "Buy") or string.find(screenName, "Sell") then
                                self:logInfo(string.format("Detected farmland-related screen: %s", screenName))
                                self:hookFarmlandScreen(screen, screenName)
                            end
                        end
                    end
                end
                
                return result
            end
            
            self._uiHooksInstalled = true
            self:logInfo("Hooked g_gui.showScreen to catch farmland screens")
        end
        
        -- Also try to directly check current screen in update
        if g_gui.currentScreen ~= nil then
            local screen = g_gui.currentScreen
            if screen ~= nil then
                local screenClass = screen.class or screen.className
                if screenClass ~= nil then
                    local screenName = tostring(screenClass)
                    self:logInfo(string.format("Current screen class: %s", screenName))
                    if string.find(screenName, "Farmland") or string.find(screenName, "Buy") or string.find(screenName, "Sell") then
                        self:hookFarmlandScreen(screen, screenName)
                    end
                end
            end
        end
        
        return true
    end
    
    -- Try to install hooks now, or schedule for later
    if not tryInstallHooks() then
        -- Schedule retry in update
        self._pendingUIHooks = true
    end
end

NoLandSale5Years.hookFarmlandScreen = function(self, screen, screenName)
    if screen == nil then
        return
    end
    
    -- Check if already hooked
    if screen._noLandSale5YearsHooked then
        return
    end
    screen._noLandSale5YearsHooked = true
    
    self:logInfo(string.format("Hooking farmland screen: %s", screenName))
    
    -- Try to find sell button in the screen
    -- Common button names in FS25 farmland screens
    local buttonNames = {
        "sellButton",
        "btnSell", 
        "sellFarmlandButton",
        "buttonSell",
        "btnSellFarmland",
        "rentSellButton"
    }
    
    -- Store original update method if exists
    local originalUpdate = nil
    if screen.update ~= nil and type(screen.update) == "function" then
        originalUpdate = screen.update
        
        screen.update = function(selfScreen, dt)
            -- Call original update
            local result = originalUpdate(selfScreen, dt)
            
            -- Update button state based on sale blocking
            NoLandSale5Years:updateFarmlandButtons(selfScreen)
            
            return result
        end
    end
    
    -- Also try onGuiUpdate which is commonly used in FS25
    local originalOnGuiUpdate = nil
    if screen.onGuiUpdate ~= nil and type(screen.onGuiUpdate) == "function" then
        originalOnGuiUpdate = screen.onGuiUpdate
        
        screen.onGuiUpdate = function(selfScreen, dt)
            -- Call original
            local result = originalOnGuiUpdate(selfScreen, dt)
            
            -- Update button state
            NoLandSale5Years:updateFarmlandButtons(selfScreen)
            
            return result
        end
    end
    
    -- Also try onOpen which is called when screen opens
    local originalOnOpen = nil
    if screen.onOpen ~= nil and type(screen.onOpen) == "function" then
        originalOnOpen = screen.onOpen
        
        screen.onOpen = function(selfScreen)
            -- Call original
            local result = originalOnOpen(selfScreen)
            
            -- Update button state when screen opens
            NoLandSale5Years:updateFarmlandButtons(selfScreen)
            
            return result
        end
    end
    
    self:logInfo(string.format("Hooked %s update methods", screenName))
end

NoLandSale5Years.updateFarmlandButtons = function(self, screen)
    if screen == nil then
        return
    end
    
    -- Check if sale is blocked
    local allowed, _ = self:canSellFarmland()
    local isBlocked = not allowed
    
    -- Try to find and disable sell buttons
    local buttonNames = {
        "sellButton",
        "btnSell",
        "sellFarmlandButton",
        "buttonSell",
        "btnSellFarmland",
        "rentSellButton",
        "sellAreaButton"
    }
    
    for _, buttonName in ipairs(buttonNames) do
        local button = screen[buttonName]
        if button ~= nil then
            if isBlocked then
                -- Disable the button
                if button.setDisabled ~= nil then
                    button:setDisabled(true)
                    self:logDebug(string.format("Disabled button: %s", buttonName))
                end
                if button.setEnabled ~= nil then
                    button:setEnabled(false)
                end
                if button.setInputEnabled ~= nil then
                    button:setInputEnabled(false)
                end
            else
                -- Enable the button (if sale is allowed)
                if button.setDisabled ~= nil then
                    button:setDisabled(false)
                end
                if button.setEnabled ~= nil then
                    button:setEnabled(true)
                end
                if button.setInputEnabled ~= nil then
                    button:setInputEnabled(true)
                end
            end
        end
    end
    
    -- Also try to find buttons in element lists (e.g., list items)
    if screen.elements ~= nil then
        for _, element in ipairs(screen.elements) do
            if element ~= nil and type(element) == "table" then
                for _, buttonName in ipairs(buttonNames) do
                    local button = element[buttonName]
                    if button ~= nil then
                        if isBlocked and button.setDisabled ~= nil then
                            button:setDisabled(true)
                        elseif not isBlocked and button.setDisabled ~= nil then
                            button:setDisabled(false)
                        end
                    end
                end
            end
        end
    end
end

-- Prefer the official event listener hook; keep script self-contained
if addModEventListener ~= nil then
    addModEventListener(NoLandSale5Years)
else
    -- Fallback: old behavior (may not work in all versions)
    NoLandSale5Years:logWarn("addModEventListener not available; falling back to MissionLoaded hook")
    local oldMissionLoaded = MissionLoaded
    MissionLoaded = function(mission)
        if oldMissionLoaded then
            oldMissionLoaded(mission)
        end
        NoLandSale5Years:run()
    end
end

-- Global functions required for extraSourceFiles in FS25
function loadMap(name)
    NoLandSale5Years:loadMap(name)
end

function update(dt)
    NoLandSale5Years:update(dt)
end

function delete()
    -- Cleanup if needed
end
