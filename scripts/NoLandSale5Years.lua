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
NoLandSale5Years.logLevel = "DEBUG" -- DEBUG, INFO, WARN, ERROR
NoLandSale5Years._lastBlockedLogKey = nil
NoLandSale5Years._didRun = false
NoLandSale5Years.lastOwnerByFarmlandId = {}
NoLandSale5Years._farmlandHooksInstalled = false
NoLandSale5Years._dayChangeListenerRegistered = false

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
    
    -- Load configuration from modSettings.xml
    self:loadConfiguration()
    
    self.isInitialized = true
    self:logInfo(string.format("Mod loaded. Land sale blocked for %d years.", self.blockedYears))
end

NoLandSale5Years.loadConfiguration = function(self)
    -- Load from user-profile modSettings
    local modSettingsRoot, modFolderPath, modSettingsPath = self:getConfigPaths()
    self:logDebug(string.format("Loading configuration from '%s'...", modSettingsPath))

    if fileExists(modSettingsPath) then
        local xmlFile = loadXMLFile("ModSettings", modSettingsPath)
        if xmlFile ~= nil and xmlFile ~= 0 then
            local configuredLogLevel = getXMLString(xmlFile, "modSettings.logLevel")
            if configuredLogLevel ~= nil then
                configuredLogLevel = string.upper(tostring(configuredLogLevel))
                if configuredLogLevel == "DEBUG" or configuredLogLevel == "INFO" or configuredLogLevel == "WARN" or configuredLogLevel == "ERROR" then
                    self.logLevel = configuredLogLevel
                else
                    self:logWarn(string.format("Invalid logLevel '%s' in config.xml; using '%s'", tostring(configuredLogLevel), tostring(self.logLevel)))
                end
            end

            local blockedYears = getXMLInt(xmlFile, "modSettings.blockedYears")
            if blockedYears ~= nil then
                self.blockedYears = math.max(1, math.min(5, math.floor(blockedYears)))
                self:logInfo(string.format("Configuration loaded: blockedYears=%d logLevel=%s", self.blockedYears, tostring(self.logLevel)))
            else
                self:logInfo(string.format("Configuration loaded: blockedYears=<default:%d> logLevel=%s", self.blockedYears, tostring(self.logLevel)))
            end
            delete(xmlFile)
        else
            self:logWarn("Failed to load XML (xmlFile is nil/0); using defaults")
        end
    else
        -- Ensure folders exist and create default config.xml
        self:logInfo(string.format("Config not found at '%s'; creating default config.xml", modSettingsPath))

        if createFolder ~= nil then
            createFolder(modSettingsRoot)
            createFolder(modFolderPath)
        else
            self:logWarn("createFolder not available; cannot ensure modSettings folders exist")
        end

        if createXMLFile ~= nil and saveXMLFile ~= nil then
            local xmlFile = createXMLFile("ModSettings", modSettingsPath, "modSettings")
            if xmlFile ~= nil and xmlFile ~= 0 then
                setXMLInt(xmlFile, "modSettings.blockedYears", self.blockedYears)
                setXMLString(xmlFile, "modSettings.logLevel", self.logLevel)
                saveXMLFile(xmlFile)
                delete(xmlFile)
                self:logInfo(string.format("Default config.xml created with blockedYears=%d logLevel=%s", self.blockedYears, tostring(self.logLevel)))
            else
                self:logWarn("Failed to create default config.xml (createXMLFile returned nil/0)")
            end
        else
            self:logWarn("XML create/save functions not available; cannot create default config.xml")
        end

        self:logInfo(string.format("Using in-memory defaults: blockedYears=%d logLevel=%s", self.blockedYears, tostring(self.logLevel)))
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
    
    -- Initialize farmland ownership tracking
    self:initializeFarmlandOwners()
    
    -- Override farmland sale function
    self:overrideFarmlandSale()
    
    -- Register day change callback using multiple methods for FS25 compatibility
    self:registerDayChangeCallback()
    
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
            
            -- Try to hook sellFarmland
            for _, methodName in ipairs(methodNames) do
                if targetTable[methodName] ~= nil and self.originalSellFarmland == nil then
                    self.originalSellFarmland = targetTable[methodName]
                    
                    -- Store the original table and method for later
                    local origTable = targetTable
                    local origMethodName = methodName
                    
                    targetTable[methodName] = function(...)
                        local args = {...}
                        local manager = args[1]
                        local farmlandId = args[2]
                        local farmId = args[3]
                        
                        self:logInfo(string.format("%s called (farmlandId=%s farmId=%s)", methodName, tostring(farmlandId), tostring(farmId)))
                        
                        -- Check if this is a sale (farmId = 0 or nil means selling to no one)
                        local isSale = false
                        if methodName == "setLandOwnership" then
                            -- setLandOwnership(farmlandId, farmId, ...)
                            -- farmId = 0 or nil means land is being sold/released
                            if farmId == nil or farmId == 0 then
                                isSale = true
                                self:logInfo("Detected land SALE via setLandOwnership")
                            end
                        end
                        
                        -- Check if sale is allowed - MUST block BEFORE calling original
                        if isSale then
                            local allowed, reason = self:canSellFarmland()
                            if not allowed then
                                self:logInfo(string.format("BLOCKING land %s (farmlandId=%s farmId=%s). %s", methodName, tostring(farmlandId), tostring(farmId), tostring(reason)))
                                self:showBlockedMessage(farmlandId, farmId, reason)
                                -- Return early to prevent original function from being called
                                return false
                            end
                        end
                        
                        local result = self.originalSellFarmland(...)
                        
                        if result then
                            self:logInfo(string.format("%s success (farmlandId=%s)", methodName, tostring(farmlandId)))
                        end
                        
                        return result
                    end
                    
                    hooked = true
                    self:logInfo(string.format("Hooked %s.%s", label, methodName))
                    break
                end
            end
            
            -- Also try hook buyFarmland style methods
            if not hooked then
                local buyMethodNames = {"buyFarmland", "purchaseFarmland", "rentFarmland"}
                for _, methodName in ipairs(buyMethodNames) do
                    if targetTable[methodName] ~= nil and self.originalBuyFarmland == nil then
                        self.originalBuyFarmland = targetTable[methodName]
                        
                        targetTable[methodName] = function(...)
                            local args = {...}
                            local farmlandId = args[2]
                            local farmId = args[3]
                            
                            self:logInfo(string.format("%s called (farmlandId=%s farmId=%s)", methodName, tostring(farmlandId), tostring(farmId)))
                            
                            local result = self.originalBuyFarmland(...)
                            
                            if result then
                                self.lastOwnerByFarmlandId[farmlandId] = farmId
                                self:logInfo(string.format("%s success (farmlandId=%s newOwner=%s)", methodName, tostring(farmlandId), tostring(farmId)))
                            end
                            
                            return result
                        end
                        
                        self:logInfo(string.format("Hooked %s.%s for buy tracking", label, methodName))
                        break
                    end
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
                
                FarmlandManager[methodName] = function(...)
                    local args = {...}
                    local farmlandId = args[1]
                    local farmId = args[2]
                    
                    self:logInfo(string.format("FarmlandManager.%s called (farmlandId=%s farmId=%s)", methodName, tostring(farmlandId), tostring(farmId)))
                    
                    -- Check if this is a sale
                    local isSale = false
                    if methodName == "setLandOwnership" and (farmId == nil or farmId == 0) then
                        isSale = true
                        self:logInfo("Detected land SALE via FarmlandManager.setLandOwnership")
                    end
                    
                    -- Check BEFORE calling original - must block first!
                    if isSale then
                        local allowed, reason = self:canSellFarmland()
                        if not allowed then
                            self:logInfo(string.format("BLOCKING FarmlandManager.%s (farmlandId=%s). %s", methodName, tostring(farmlandId), tostring(reason)))
                            self:showBlockedMessage(farmlandId, farmId, reason)
                            return false
                        end
                    end
                    
                    return self.originalSellFarmland(...)
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
                self:logInfo(string.format("Blocking FarmlandInfo.delete. %s", tostring(reason)))
                self:showBlockedMessage(nil, nil, reason)
                return false
            end
            return self.originalSellFarmland(...)
        end
        
        hooked = true
        self:logInfo("Hooked FarmlandInfo.delete")
    end
    
    self._farmlandHooksInstalled = hooked
    
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

function NoLandSale5Years:loadMap(mapName)
    self:logInfo(string.format("loadMap('%s')", tostring(mapName)))
    self:loadConfiguration()
end

function NoLandSale5Years:update(dt)
    -- Try to initialize if mission is ready
    if not self.isInitialized and g_currentMission ~= nil and g_currentMission.environment ~= nil then
        self.isInitialized = true
        self:logInfo("Mission detected in update(); initializing")
        self:run()
    end
    
    -- Retry hooking if not hooked yet (in case farmland manager wasn't ready)
    if self._didRun and not self._farmlandHooksInstalled then
        self:logDebug("Retrying farmland hook installation...")
        self:overrideFarmlandSale()
    end
    
    -- Also retry callback registration
    if self._didRun and not self._dayChangeListenerRegistered then
        self:logDebug("Retrying day change callback registration...")
        self:registerDayChangeCallback()
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
