--[[
    BossHit - Boss Swing Timer
    
    Shows swing timer for boss monsters, trying to show a correct timing with parry haste calculation.
    Tracks boss swings using combat messages and displays a configurable timer bar.
    
    Commands:
    /bosshit - Show current settings
    /bosshit help - Show all commands
--]]

-- Saved Variables (persisted between logins)
BossHitDB = BossHitDB or {}

-- Addon state
local BossHit = {}
local addonLoaded = false

-- Default settings with comprehensive options
local defaultSettings = {
    enabled = true,
    x = 0,
    y = -200,
    width = 250,
    height = 5,
    scale = 1.0,
    alpha = 1.0,
    moveable = false,
    
    -- Simple display options
    showBossName = true,       -- Show boss name above bar
    showSwingText = true,      -- Show "SWING!" when ready
    
    -- Behavior options
    debugMode = false,
    soundAlerts = false,
    warningTime = 1.0,
    combatLogDelay = 0.25,
    
    -- Colors
    barColor = {r = 0.8, g = 0.2, b = 0.2, a = 0.8},
    warningColor = {r = 1.0, g = 0.4, b = 0.0, a = 0.9},
    readyColor = {r = 0.2, g = 1.0, b = 0.2, a = 0.9},
    textColor = {r = 1.0, g = 1.0, b = 1.0, a = 1.0}
}

-- Boss list - monsters we want to track
local bossNames = {
    -- Molten Core
    ["Incindis"] = true,
    ["Lucifron"] = true,
    ["Magmadar"] = true,
    ["Gehennas"] = true,
    ["Garr"] = true,
    ["Shazzrah"] = true,
    ["Baron Geddon"] = true,
    ["Golemagg the Incinerator"] = true,
    ["Sulfuron Harbinger"] = true,
    ["Sorcerer-Thane Thaurissan"] = true,
    ["Majordomo Executus"] = true,
    ["Ragnaros"] = true,
    
    -- Blackwing Lair
    ["Razorgore the Untamed"] = true,
    ["Vaelastrasz the Corrupt"] = true,
    ["Broodlord Lashlayer"] = true,
    ["Firemaw"] = true,
    ["Ebonroc"] = true,
    ["Flamegor"] = true,
    ["Chromaggus"] = true,
    ["Nefarian"] = true,
    
    -- Onyxia's Lair
    ["Onyxia"] = true,
    
    -- Zul'Gurub
    ["High Priest Jeklik"] = true,
    ["High Priestess Venoxis"] = true,
    ["High Priestess Mar'li"] = true,
    ["Bloodlord Mandokir"] = true,
    ["Edge of Madness"] = true,
    ["High Priest Thekal"] = true,
    ["Gahz'ranka"] = true,
    ["High Priestess Arlokk"] = true,
    ["Jin'do the Hexxer"] = true,
    ["Hakkar the Soulflayer"] = true,
    
    -- AQ20
    ["Kurinnaxx"] = true,
    ["General Rajaxx"] = true,
    ["Moam"] = true,
    ["Buru the Gorger"] = true,
    ["Ayamiss the Hunter"] = true,
    ["Ossirian the Unscarred"] = true,
    
    -- AQ40
    ["The Prophet Skeram"] = true,
    ["Battleguard Sartura"] = true,
    ["Fankriss the Unyielding"] = true,
    ["Viscidus"] = true,
    ["Princess Huhuran"] = true,
    ["Emperor Vek'lor"] = true,
    ["Emperor Vek'nilash"] = true,
    ["Ouro"] = true,
    ["C'Thun"] = true,
    
    -- Naxxramas
    ["Anub'Rekhan"] = true,
    ["Grand Widow Faerlina"] = true,
    ["Maexxna"] = true,
    ["Noth the Plaguebringer"] = true,
    ["Heigan the Unclean"] = true,
    ["Loatheb"] = true,
    ["Instructor Razuvious"] = true,
    ["Gothik the Harvester"] = true,
    ["Patchwerk"] = true,
    ["Grobbulus"] = true,
    ["Gluth"] = true,
    ["Thaddius"] = true,
    ["Sapphiron"] = true,
    ["Kel'Thuzad"] = true,
    
    -- Kara40
    ["Keeper Gnarlmoon"] = true,
    ["Ley-Watcher Incantagos"] = true,
    ["Echo of Medivh"] = true,
    ["Sanv Tas'dal"] = true,
    ["Kruul"] = true,
    ["Rupturan the Broken"] = true,
    ["Mephistroth"] = true,

    -- World Bosses
    ["Lord Kazzak"] = true,
    ["Azuregos"] = true,
    ["Taerar"] = true,
    ["Emeriss"] = true,
    ["Lethon"] = true,
    ["Ysondre"] = true,
    
    -- Testing
    ["Elder Mottled Boar"] = true

}

-- Stable swing tracking variables (SP_SwingTimer approach)
local currentTarget = nil
local currentTargetGUID = nil
local swingTimer = 0            -- Time remaining until next swing
local baseSwingTime = 2.0       -- Base swing speed from UnitAttackSpeed
local isTracking = false
local lastSwingTime = 0         -- For detecting speed changes
-- Configuration variables
local combatLogDelay = 0.25     -- Will be loaded from settings

-- UI Frame
local swingFrame = nil

-- Debug function (defined early so other functions can use it)
local function DebugPrint(message)
    if BossHitDB and BossHitDB.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[BossHit Debug]:|r " .. message)
    end
end

-- Correct parry haste calculation (based on research)
local function ApplyParryHaste()
    if not isTracking or swingTimer <= 0 then return end
    
    local percentRemaining = swingTimer / baseSwingTime
    local reduction = 0
    
    -- Correct parry haste formula from research:
    if percentRemaining > 0.6 then
        -- If time remaining > 60%, reduce by 40% of speed
        reduction = baseSwingTime * 0.4
    elseif percentRemaining < 0.2 then
        -- If time remaining < 20%, no reduction
        reduction = 0
    else
        -- Otherwise, reduce by (time remaining - 20%) * weapon speed
        reduction = (percentRemaining - 0.2) * baseSwingTime
    end
    
    if reduction > 0 then
        local oldTimer = swingTimer
        swingTimer = swingTimer - reduction
        
        -- Ensure we don't go below 20% minimum
        local minimum = baseSwingTime * 0.2
        if swingTimer < minimum then
            swingTimer = minimum
        end
        
        DebugPrint(string.format("Parry haste: %.2fs -> %.2fs (%.1f%% remaining, -%.2fs)", 
                   oldTimer, swingTimer, percentRemaining * 100, reduction))
        
        -- Debug-only parry notification
        if BossHitDB.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFF4444BossHit:|r %s PARRIED! Swing in %.1fs", 
                                         currentTarget or "Boss", swingTimer))
        end
    else
        DebugPrint(string.format("Parry too late: %.1f%% remaining - no haste", percentRemaining * 100))
    end
end

-- Reset swing timer when boss swings
local function ResetSwingTimer()
    swingTimer = baseSwingTime + combatLogDelay  -- Add delay compensation
    lastSwingTime = GetTime()
    
    DebugPrint(string.format("Swing timer reset: %.2fs (base: %.2fs + delay: %.2fs)", 
               swingTimer, baseSwingTime, combatLogDelay))
end

-- Check for weapon speed changes (debuffs like Thunderfury)
local function CheckSpeedChanges()
    if not isTracking or not currentTarget then return end
    
    -- Only check if we have the boss targeted
    if UnitExists("target") and UnitName("target") == currentTarget then
        local mainSpeed, offSpeed = UnitAttackSpeed("target")
        if mainSpeed and math.abs(mainSpeed - baseSwingTime) > 0.1 then
            -- Significant speed change detected (debuff/buff)
            local oldSpeed = baseSwingTime
            local speedRatio = mainSpeed / baseSwingTime
            
            -- Adjust current timer proportionally
            if swingTimer > 0 then
                swingTimer = swingTimer * speedRatio
            end
            
            baseSwingTime = mainSpeed
            
            DebugPrint(string.format("Speed change: %.2fs -> %.2fs (ratio: %.2f)", 
                       oldSpeed, mainSpeed, speedRatio))
            
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FFFF[BossHit]:|r %s speed changed to %.1fs", 
                                         currentTarget, mainSpeed))
        end
    end
end

-- Initialize settings after addon loads
local function LoadSettings()
    if not addonLoaded then return end
    
    -- Initialize with defaults if missing
    for key, value in pairs(defaultSettings) do
        if BossHitDB[key] == nil then
            if type(value) == "table" then
                BossHitDB[key] = {}
                for subkey, subvalue in pairs(value) do
                    BossHitDB[key][subkey] = subvalue
                end
            else
                BossHitDB[key] = value
            end
        end
    end
    
    -- Load combat log delay from settings
    combatLogDelay = BossHitDB.combatLogDelay or 0.25
end

-- Simple display text
local function GetDisplayText(timeLeft)
    if timeLeft <= 0 and BossHitDB.showSwingText then
        return "SWING!"
    elseif BossHitDB.showBossName and currentTarget then
        return currentTarget
    else
        return ""
    end
end

-- Create the swing timer UI
local function CreateSwingFrame()
    if swingFrame then return end
    
    DebugPrint("Creating swing frame...")
    
    -- Main frame
    swingFrame = CreateFrame("Frame", "BossHitFrame", UIParent)
    swingFrame:SetWidth(BossHitDB.width or 250)
    swingFrame:SetHeight(BossHitDB.height or 20)
    swingFrame:SetPoint("CENTER", UIParent, "CENTER", BossHitDB.x or 0, BossHitDB.y or -200)
    swingFrame:SetScale(BossHitDB.scale or 1.0)
    swingFrame:SetAlpha(BossHitDB.alpha or 1.0)
    
    -- Make it moveable
    swingFrame:EnableMouse(true)
    swingFrame:SetMovable(true)
    swingFrame:RegisterForDrag("LeftButton")
    swingFrame:SetScript("OnDragStart", function()
        if BossHitDB.moveable then
            swingFrame:StartMoving()
        end
    end)
    swingFrame:SetScript("OnDragStop", function()
        swingFrame:StopMovingOrSizing()
        -- Save new position
        local point, _, _, x, y = swingFrame:GetPoint()
        BossHitDB.x = x
        BossHitDB.y = y
    end)
    
    -- Background
    swingFrame.bg = swingFrame:CreateTexture(nil, "BACKGROUND")
    swingFrame.bg:SetAllPoints(swingFrame)
    swingFrame.bg:SetTexture(0, 0, 0, 0.6)
    
    -- Border
    swingFrame.border = CreateFrame("Frame", nil, swingFrame)
    swingFrame.border:SetPoint("TOPLEFT", swingFrame, "TOPLEFT", -1, 1)
    swingFrame.border:SetPoint("BOTTOMRIGHT", swingFrame, "BOTTOMRIGHT", 1, -1)
    swingFrame.border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    swingFrame.border:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    -- Progress bar
    swingFrame.bar = CreateFrame("StatusBar", nil, swingFrame)
    swingFrame.bar:SetPoint("TOPLEFT", swingFrame, "TOPLEFT", 2, -2)
    swingFrame.bar:SetPoint("BOTTOMRIGHT", swingFrame, "BOTTOMRIGHT", -2, 2)
    swingFrame.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    swingFrame.bar:SetStatusBarColor(
        BossHitDB.barColor.r, 
        BossHitDB.barColor.g, 
        BossHitDB.barColor.b, 
        BossHitDB.barColor.a
    )
    swingFrame.bar:SetMinMaxValues(0, 1)
    swingFrame.bar:SetValue(0)
    
    -- Text display
    swingFrame.text = swingFrame.bar:CreateFontString(nil, "OVERLAY")
    swingFrame.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    swingFrame.text:SetPoint("CENTER", swingFrame.bar, "CENTER", 0, 0)
    swingFrame.text:SetTextColor(
        BossHitDB.textColor.r,
        BossHitDB.textColor.g,
        BossHitDB.textColor.b,
        BossHitDB.textColor.a
    )
    swingFrame.text:SetText("BossHit Ready")
    
    -- Hide initially
    swingFrame:Hide()
end

-- Update the swing timer display
local function UpdateSwingDisplay()
    if not swingFrame or not isTracking then return end
    
    if swingTimer > 0 then
        local progress = 1 - (swingTimer / maxSwingTime)
        swingFrame.bar:SetValue(progress)
        
        -- Change color based on time remaining (warning system)
        if swingTimer <= BossHitDB.warningTime then
            -- Warning color when swing is imminent
            swingFrame.bar:SetStatusBarColor(
                BossHitDB.warningColor.r,
                BossHitDB.warningColor.g,
                BossHitDB.warningColor.b,
                BossHitDB.warningColor.a
            )
        else
            -- Normal color
            swingFrame.bar:SetStatusBarColor(
                BossHitDB.barColor.r,
                BossHitDB.barColor.g,
                BossHitDB.barColor.b,
                BossHitDB.barColor.a
            )
        end
        
        local displayText = GetDisplayText(math.max(0, swingTimer))
        swingFrame.text:SetText(displayText)
        
        swingFrame:Show()
    else
        -- Timer expired - show ready state briefly
        swingFrame.bar:SetValue(1)
        swingFrame.bar:SetStatusBarColor(
            BossHitDB.readyColor.r,
            BossHitDB.readyColor.g,
            BossHitDB.readyColor.b,
            BossHitDB.readyColor.a
        )
        local displayText = GetDisplayText(0)
        swingFrame.text:SetText(displayText or "SWING!")
        swingFrame:Show()
    end
end

-- Check if target is in range for combat
local function IsTargetInRange()
    if not UnitExists("target") then return false end
    
    -- Check if target is attackable and in range
    if UnitCanAttack("player", "target") then
        -- Use spell range checking as a proxy for combat range
        -- IsSpellInRange doesn't exist in vanilla, so we use other methods
        
        -- Check if target is too far (more than 100 yards)
        if CheckInteractDistance("target", 4) then
            return true  -- Within 28 yards (follow distance)
        elseif CheckInteractDistance("target", 3) then
            return true  -- Within 10 yards (inspect distance)
        elseif CheckInteractDistance("target", 2) then
            return true  -- Within 11.11 yards (trade distance)
        elseif CheckInteractDistance("target", 1) then
            return true  -- Within 28 yards (inspect distance for players)
        end
        
        -- If none of the interact distances work, assume it's in reasonable range
        -- if we can see its health and it's hostile
        return UnitHealth("target") and UnitHealth("target") > 0
    end
    
    return false
end

-- Check if current target is a boss we should track
local function ShouldTrackTarget()
    if not UnitExists("target") then return false end
    
    local targetName = UnitName("target")
    if not targetName then return false end
    
    -- Check if target is in reasonable range
    if not IsTargetInRange() then
        DebugPrint("Target " .. targetName .. " is out of range")
        return false
    end
    
    -- Check if it's in our boss list
    if bossNames[targetName] then
        DebugPrint("Target " .. targetName .. " found in boss list")
        return true
    end
    
    -- Additional checks for boss-like units
    local classification = UnitClassification("target")
    if classification == "worldboss" or classification == "rareelite" or classification == "elite" then
        DebugPrint("Target " .. targetName .. " is " .. classification .. " - tracking")
        return true
    end
    
    DebugPrint("Target " .. targetName .. " (" .. (classification or "normal") .. ") - not tracking")
    return false
end

-- Start tracking a new target
local function StartTracking()
    if not UnitExists("target") then 
        DebugPrint("StartTracking: No target exists")
        return 
    end
    
    currentTarget = UnitName("target")
    -- UnitGUID doesn't exist in vanilla WoW, so we'll use name + level as identifier
    local targetLevel = UnitLevel("target")
    currentTargetGUID = currentTarget .. "_" .. (targetLevel or "??")
    
    DebugPrint("StartTracking: " .. (currentTarget or "Unknown"))
    
    -- Get the target's attack speed
    local mainSpeed, offSpeed = UnitAttackSpeed("target")
    DebugPrint("Target attack speed: " .. (mainSpeed or "nil"))
    
    if mainSpeed then
        maxSwingTime = mainSpeed
        swingTimer = 0.1  -- Small initial value to show the bar
        isTracking = true
        
        DebugPrint("Now tracking " .. currentTarget .. " with swing time " .. maxSwingTime)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Now tracking " .. currentTarget .. " (swing: " .. string.format("%.1f", maxSwingTime) .. "s)")
    else
        DebugPrint("Could not get attack speed for " .. currentTarget)
    end
end

-- Stop tracking current target
local function StopTracking()
    if isTracking and currentTarget then
        if BossHitDB.enabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Stopped tracking " .. currentTarget)
        end
    end
    
    currentTarget = nil
    currentTargetGUID = nil
    swingTimer = 0
    baseSwingTime = 2.0
    isTracking = false
    lastSwingTime = 0
    
    if swingFrame then
        swingFrame:Hide()
    end
end

-- Handle target changes
local function OnTargetChanged()
    DebugPrint("OnTargetChanged called")
    
    if not BossHitDB.enabled then 
        DebugPrint("Addon not enabled")
        return 
    end
    
    -- NEW LOGIC: Only prepare for tracking, don't start tracking yet
    -- Tracking will start when the target actually swings at us
    
    if UnitExists("target") then
        local targetName = UnitName("target")
        DebugPrint("New target: " .. (targetName or "Unknown"))
        
        if ShouldTrackTarget() then
            DebugPrint("Target " .. targetName .. " is trackable - waiting for swing")
        else
            DebugPrint("Target " .. targetName .. " is not trackable")
            -- Stop tracking if we target something we shouldn't track
            if isTracking then
                StopTracking()
            end
        end
    else
        DebugPrint("No target - stopping tracking")
        if isTracking then
            StopTracking()
        end
    end
end

-- Handle combat log events for swing detection (not used in vanilla)
local function OnCombatLogEvent()
    -- Not used in vanilla WoW - we use combat message events instead
end

-- Handle combat messages for swing detection (stable SP_SwingTimer approach)
local function OnCombatMessage()
    if not BossHitDB.enabled then return end
    
    local message = arg1
    if not message then return end
    
    DebugPrint("Combat message: " .. message)
    
    -- Check for parry events first (for parry haste)
    for bossName, _ in pairs(bossNames) do
        if string.find(message, bossName .. " parries") then
            if currentTarget == bossName and isTracking then
                ApplyParryHaste()
                DebugPrint("Parry haste applied for " .. bossName)
            end
            return  -- Don't process as swing if it's a parry
        end
    end
    
    -- Check if any boss from our list is swinging
    local swingingBoss = nil
    local swingDetected = false
    
    -- Look through all boss names to see if any are swinging
    for bossName, _ in pairs(bossNames) do
        local patterns = {
            bossName .. " hits",           -- Direct hit
            bossName .. " misses",         -- Miss
            bossName .. " crits",          -- Critical hit
            bossName .. "'s attack",       -- Attack blocked/parried/dodged
            bossName .. " crushes",        -- Crushing blow
            bossName .. " glances",        -- Glancing blow
            bossName .. " performs"        -- Special attacks
        }
        
        for _, pattern in pairs(patterns) do
            if string.find(message, pattern) then
                swingingBoss = bossName
                swingDetected = true
                DebugPrint("Swing detected from " .. bossName .. " with pattern: " .. pattern)
                break
            end
        end
        
        if swingDetected then break end
    end
    
    if swingDetected and swingingBoss then
        -- Check if we should switch to tracking this boss
        if not isTracking or currentTarget ~= swingingBoss then
            -- Start or switch tracking
            currentTarget = swingingBoss
            local targetLevel = UnitExists("target") and UnitLevel("target") or "??"
            currentTargetGUID = currentTarget .. "_" .. targetLevel
            
            -- Get attack speed if we have the boss targeted
            if UnitExists("target") and UnitName("target") == swingingBoss then
                local mainSpeed, offSpeed = UnitAttackSpeed("target")
                if mainSpeed then
                    baseSwingTime = mainSpeed
                    DebugPrint("Got attack speed for " .. swingingBoss .. ": " .. mainSpeed)
                else
                    baseSwingTime = 2.0
                    DebugPrint("Using default attack speed for " .. swingingBoss)
                end
            else
                baseSwingTime = 2.0
                DebugPrint("Boss not targeted, using default attack speed")
            end
            
            isTracking = true
            DebugPrint("Now tracking " .. swingingBoss)
        end
        
        -- Reset swing timer for new swing cycle
        ResetSwingTimer()
        maxSwingTime = baseSwingTime  -- Update display max time
        
        -- Debug-only swing notification
        if BossHitDB.debugMode then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r " .. swingingBoss .. " swung! Next swing in " .. string.format("%.1f", baseSwingTime) .. "s")
        end
        
        -- Play sound alert if enabled
        if BossHitDB.soundAlerts then
            PlaySound("igQuestLogAbandonQuest")
        end
    end
end

-- Simple, stable update function (SP_SwingTimer approach)
local function OnUpdate()
    if not addonLoaded or not BossHitDB or not BossHitDB.enabled then return end
    
    local elapsed = arg1  -- arg1 is elapsed time in vanilla
    
    -- Update swing timer
    if isTracking and swingTimer > 0 then
        swingTimer = swingTimer - elapsed
        if swingTimer < 0 then
            swingTimer = 0
        end
    end
    
    -- Check for speed changes periodically
    CheckSpeedChanges()
    
    -- Update display
    if isTracking then
        UpdateSwingDisplay()
    end
    
    -- Check if we should continue tracking
    if isTracking and currentTarget then
        -- Simple validity check - keep tracking unless manually stopped
        local stillValid = true
        
        -- Hide timer if not in combat and timer expired
        if swingTimer <= 0 and not UnitAffectingCombat("player") then
            -- Timer expired and not in combat - hide but keep tracking
            if swingFrame then
                swingFrame:Hide()
            end
        end
        
        if not stillValid then
            DebugPrint("Tracked boss " .. currentTarget .. " no longer valid")
            StopTracking()
        end
    end
end

-- Show current settings (default command)
local function ShowSettings()
    -- Debug check
    if not BossHitDB then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r |cFFFF0000Error:|r Settings not loaded!")
        return
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit Settings:|r")
    DEFAULT_CHAT_FRAME:AddMessage("Enabled: " .. (BossHitDB.enabled and "|cFF00FF00Yes|r" or "|cFFFF0000No|r"))
    DEFAULT_CHAT_FRAME:AddMessage("Size: |cFFFFFFFF" .. BossHitDB.width .. "x" .. BossHitDB.height .. "|r")
    DEFAULT_CHAT_FRAME:AddMessage("Show Boss Name: " .. (BossHitDB.showBossName and "|cFF00FF00Yes|r" or "|cFFFF0000No|r"))
    DEFAULT_CHAT_FRAME:AddMessage("Show SWING Text: " .. (BossHitDB.showSwingText and "|cFF00FF00Yes|r" or "|cFFFF0000No|r"))
    DEFAULT_CHAT_FRAME:AddMessage("Moveable: " .. (BossHitDB.moveable and "|cFF00FF00Yes|r" or "|cFFFF0000No|r"))
    DEFAULT_CHAT_FRAME:AddMessage("Currently tracking: " .. (isTracking and ("|cFF00FF00" .. currentTarget .. "|r") or "|cFFFF0000None|r"))
    DEFAULT_CHAT_FRAME:AddMessage("")
    DEFAULT_CHAT_FRAME:AddMessage("Type |cFFFFFF00/bosshit help|r for configuration commands")
end

-- Slash command handler with comprehensive options
local function SlashCommandHandler(msg)
    if not addonLoaded then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r |cFFFF0000Error:|r Addon not fully loaded yet!")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Try reloading UI with /reload")
        return
    end
    
    local command = string.lower(msg or "")
    
    -- Default command shows settings
    if command == "" then
        ShowSettings()
        return
    end
    
    -- Parse command and arguments
    local spacePos = string.find(command, " ")
    local cmd, arg
    if spacePos then
        cmd = string.sub(command, 1, spacePos - 1)
        arg = string.sub(command, spacePos + 1)
    else
        cmd = command
        arg = ""
    end
    
    if cmd == "toggle" or cmd == "on" or cmd == "off" then
        if cmd == "on" then
            BossHitDB.enabled = true
        elseif cmd == "off" then
            BossHitDB.enabled = false
        else
            BossHitDB.enabled = not BossHitDB.enabled
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r " .. (BossHitDB.enabled and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        
        if not BossHitDB.enabled then
            StopTracking()
        else
            OnTargetChanged()
        end
        
    elseif cmd == "name" then
        BossHitDB.showBossName = not BossHitDB.showBossName
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Boss name display " .. (BossHitDB.showBossName and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        
    elseif cmd == "swing" then
        BossHitDB.showSwingText = not BossHitDB.showSwingText
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r SWING text " .. (BossHitDB.showSwingText and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        
    elseif cmd == "size" then
        if arg == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Current size: " .. BossHitDB.width .. "x" .. BossHitDB.height)
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /bosshit size 300 25 (width height)")
        else
            -- Simple parsing for "width height"
            local spacePos = string.find(arg, " ")
            if spacePos then
                local widthStr = string.sub(arg, 1, spacePos - 1)
                local heightStr = string.sub(arg, spacePos + 1)
                local width = tonumber(widthStr)
                local height = tonumber(heightStr)
                
                if width and height and width > 0 and height > 0 then
                    BossHitDB.width = width
                    BossHitDB.height = height
                    if swingFrame then
                        swingFrame:SetWidth(BossHitDB.width)
                        swingFrame:SetHeight(BossHitDB.height)
                    end
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Size set to " .. BossHitDB.width .. "x" .. BossHitDB.height)
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Invalid numbers. Use: /bosshit size 300 25")
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Invalid format. Use: /bosshit size 300 25")
            end
        end
        
    elseif cmd == "delay" then
        if arg == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Current combat log delay: |cFFFFFFFF" .. string.format("%.2fs", BossHitDB.combatLogDelay or 0.25) .. "|r")
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /bosshit delay 0.25")
        else
            local newDelay = tonumber(arg)
            if newDelay and newDelay >= 0 and newDelay <= 1.0 then
                BossHitDB.combatLogDelay = newDelay
                combatLogDelay = newDelay
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Combat log delay set to |cFFFFFFFF" .. string.format("%.2fs", newDelay) .. "|r")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Invalid delay. Use 0.0 to 1.0 seconds")
            end
        end
        
    elseif cmd == "move" then
        BossHitDB.moveable = not BossHitDB.moveable
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Movement " .. (BossHitDB.moveable and "|cFF00FF00Enabled|r (drag to move)" or "|cFFFF0000Disabled|r"))
        
    elseif cmd == "reset" then
        BossHitDB.x = 0
        BossHitDB.y = -200
        if swingFrame then
            swingFrame:ClearAllPoints()
            swingFrame:SetPoint("CENTER", UIParent, "CENTER", BossHitDB.x, BossHitDB.y)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Position reset to center")
        
    elseif cmd == "sound" then
        BossHitDB.soundAlerts = not BossHitDB.soundAlerts
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Sound alerts " .. (BossHitDB.soundAlerts and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        
    elseif cmd == "debug" then
        BossHitDB.debugMode = not BossHitDB.debugMode
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Debug mode " .. (BossHitDB.debugMode and "|cFF00FF00Enabled|r" or "|cFFFF0000Disabled|r"))
        
    elseif cmd == "test" then
        if not swingFrame then
            CreateSwingFrame()
        end
        swingTimer = 5.0
        maxSwingTime = 5.0
        isTracking = true
        currentTarget = "Test Target"
        swingFrame:Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Test mode - 5 second countdown")
        
    elseif cmd == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit Commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/bosshit|r - Show current settings")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/bosshit toggle|r - Enable/disable addon")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/bosshit name|r - Toggle boss name display")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/bosshit swing|r - Toggle SWING text")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/bosshit size [width height]|r - Set bar size (e.g. 300 25)")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/bosshit move|r - Toggle movement mode")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/bosshit reset|r - Reset position")
        DEFAULT_CHAT_FRAME:AddMessage("")
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[Simple casting bar with parry haste support]|r")
        
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Unknown command '|cFFFF0000" .. cmd .. "|r'. Use |cFFFFFF00/bosshit help|r")
    end
end

-- Event frame for handling WoW events
local eventFrame = CreateFrame("Frame")

-- Event handlers
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Vanilla WoW combat message events
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES")

eventFrame:SetScript("OnEvent", function()
    -- Debug all addon loaded events
    if event == "ADDON_LOADED" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[Debug]:|r ADDON_LOADED: " .. (arg1 or "nil"))
    end
    
    if event == "ADDON_LOADED" and (arg1 == "BossHit" or arg1 == "hit-timer") then
        addonLoaded = true
        LoadSettings()
        CreateSwingFrame()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Loaded! Use /bosshit for commands.")
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
        
    elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" or
           event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" or
           event == "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS" or
           event == "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES" then
        OnCombatMessage()
    end
end)

-- Update frame for continuous updates
local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", OnUpdate)

-- Register slash commands
SLASH_BOSSHIT1 = "/bosshit"
SLASH_BOSSHIT2 = "/bh"
SlashCmdList["BOSSHIT"] = SlashCommandHandler

-- Export for debugging
_G.BossHit = BossHit

-- Ensure BossHitDB is always initialized
if not BossHitDB then
    BossHitDB = {}
end

-- Fallback initialization (in case ADDON_LOADED doesn't fire)
local function InitializeAddon()
    if not addonLoaded then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[Debug]:|r Fallback initialization")
        addonLoaded = true
        
        -- Ensure BossHitDB exists
        if not BossHitDB then
            BossHitDB = {}
        end
        
        LoadSettings()
        CreateSwingFrame()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BossHit:|r Loaded via fallback! Use /bosshit for commands.")
    end
end

-- Try to initialize immediately
InitializeAddon()

-- Also try after a short delay
local initTimer = CreateFrame("Frame")
initTimer:SetScript("OnUpdate", function()
    if not addonLoaded then
        InitializeAddon()
    else
        -- Stop the timer once loaded
        this:SetScript("OnUpdate", nil)
    end
end)
