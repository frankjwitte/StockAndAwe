local addonName = ...

-- Newer clients moved the item API into C_Item; older ones only have the globals.
local C_Item = C_Item or {}
local GetItemInfo = C_Item.GetItemInfo or GetItemInfo
local GetItemCount = C_Item.GetItemCount or GetItemCount
local GetItemInfoInstant = C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetItemFamily = C_Item.GetItemFamily or GetItemFamily

local frame = CreateFrame("Frame")
local playerClass
local DEFAULT_RULES_VERSION = 3
local restockQueue = {}
local restockInProgress = false
local restockItemIDs = {}
local merchantOpen = false
local merchantSession = 0
local merchantReady = false
local restockPending = false
local chatFilterRegistered = false

local DEFAULTS = {
    enabled = true,
    announce = true,
    dryRun = false,
    ammo = true,
    rules = {
        DRUID = {
            { itemID = 17026, stacks = 1, fallbackStack = 20 }, -- Wild Thornroot
            { itemID = 17034, stacks = 1, fallbackStack = 20 }, -- Maple Seed
            { itemID = 17035, stacks = 1, fallbackStack = 20 }, -- Stranglethorn Seed
            { itemID = 17036, stacks = 1, fallbackStack = 20 }, -- Ashwood Seed
            { itemID = 17037, stacks = 1, fallbackStack = 20 }, -- Hornbeam Seed
            { itemID = 17038, stacks = 1, fallbackStack = 20 }, -- Ironwood Seed
        },
        MAGE = {
            { itemID = 17031, stacks = 1, fallbackStack = 20 }, -- Rune of Teleportation
            { itemID = 17032, stacks = 1, fallbackStack = 20 }, -- Rune of Portals
        },
        PALADIN = {
            { itemID = 17033, stacks = 1, fallbackStack = 20 }, -- Symbol of Divinity
            { itemID = 21177, stacks = 1, fallbackStack = 20 }, -- Symbol of Kings
        },
        PRIEST = {
            { itemID = 17029, stacks = 3, fallbackStack = 20 }, -- Sacred Candle
        },
        ROGUE = {
            { itemID = 5140, stacks = 1, fallbackStack = 20 }, -- Flash Powder
        },
        SHAMAN = {
            { itemID = 17030, stacks = 1, fallbackStack = 20 }, -- Ankh
        },
        WARLOCK = {
            { itemID = 16583, stacks = 1, fallbackStack = 20 }, -- Demonic Figurine
            { itemID = 5565, stacks = 1, fallbackStack = 20 }, -- Infernal Stone
        },
    },
}

local VENDOR_REAGENT_ITEM_IDS = {
    [5140] = true, -- Flash Powder
    [5565] = true, -- Infernal Stone
    [16583] = true, -- Demonic Figurine
    [17026] = true, -- Wild Thornroot
    [17028] = true, -- Holy Candle
    [17029] = true, -- Sacred Candle
    [17030] = true, -- Ankh
    [17031] = true, -- Rune of Teleportation
    [17032] = true, -- Rune of Portals
    [17033] = true, -- Symbol of Divinity
    [17034] = true, -- Maple Seed
    [17035] = true, -- Stranglethorn Seed
    [17036] = true, -- Ashwood Seed
    [17037] = true, -- Hornbeam Seed
    [17038] = true, -- Ironwood Seed
    [21177] = true, -- Symbol of Kings
}

local function CopyTable(source)
    local target = {}

    for key, value in pairs(source) do
        if type(value) == "table" then
            target[key] = CopyTable(value)
        else
            target[key] = value
        end
    end

    return target
end

local function ApplyDefaults()
    if StockAndAweDB.enabled == nil then
        StockAndAweDB.enabled = DEFAULTS.enabled
    end

    if StockAndAweDB.announce == nil then
        StockAndAweDB.announce = DEFAULTS.announce
    end

    if StockAndAweDB.dryRun == nil then
        StockAndAweDB.dryRun = DEFAULTS.dryRun
    end

    if StockAndAweDB.ammo == nil then
        StockAndAweDB.ammo = DEFAULTS.ammo
    end

    if type(StockAndAweDB.rules) ~= "table" then
        StockAndAweDB.rules = {}
    end

    for classFileName, rules in pairs(DEFAULTS.rules) do
        if StockAndAweDB.rules[classFileName] == nil then
            StockAndAweDB.rules[classFileName] = CopyTable(rules)
        end
    end

    if (StockAndAweDB.rulesVersion or 0) < DEFAULT_RULES_VERSION then
        local retiredItems = {
            [17028] = true, -- Holy Candle
        }

        for _, classRules in pairs(StockAndAweDB.rules) do
            for index = #classRules, 1, -1 do
                local itemID = classRules[index].itemID
                if retiredItems[itemID] or not VENDOR_REAGENT_ITEM_IDS[itemID] then
                    table.remove(classRules, index)
                end
            end
        end

        StockAndAweDB.rulesVersion = DEFAULT_RULES_VERSION
    end
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd6b45dStock And Awe|r: " .. message)
end

local function FilterRestockLoot(_, _, message)
    if not restockInProgress then
        return false
    end

    local itemID = tonumber(string.match(message or "", "|Hitem:(%d+):"))
    return itemID and restockItemIDs[itemID] == true
end

local function Announce(message)
    if StockAndAweDB and StockAndAweDB.announce then
        Print(message)
    end
end

local function UpdateTitanPanel()
    if TitanPanelButton_UpdateButton and TitanPanelStockAndAweButton then
        TitanPanelButton_UpdateButton("StockAndAwe")
    end
end

local function GetItemName(itemID)
    local name = GetItemInfo(itemID)
    return name or ("item:" .. tostring(itemID))
end

local function GetStackSize(rule)
    local _, _, _, _, _, _, _, itemStackCount = GetItemInfo(rule.itemID)
    return itemStackCount or rule.fallbackStack or 20
end

local function GetRuleTarget(rule)
    if rule.target then
        return rule.target
    end

    return (rule.stacks or 1) * GetStackSize(rule)
end

-- Ammo pouches and quivers. Bag family bits: 1 = Quiver, 2 = Ammo Pouch.
local AMMO_BAG_FAMILY_MASK = 3
local AMMO_FALLBACK_STACK = 200

local function GetBagNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end

    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function GetBagFamily(bag)
    local _, family
    if C_Container and C_Container.GetContainerNumFreeSlots then
        _, family = C_Container.GetContainerNumFreeSlots(bag)
    elseif GetContainerNumFreeSlots then
        _, family = GetContainerNumFreeSlots(bag)
    end

    return family or 0
end

local function GetBagItemID(bag)
    local inventoryID
    if C_Container and C_Container.ContainerIDToInventoryID then
        inventoryID = C_Container.ContainerIDToInventoryID(bag)
    elseif ContainerIDToInventoryID then
        inventoryID = ContainerIDToInventoryID(bag)
    end

    return inventoryID and GetInventoryItemID("player", inventoryID)
end

local QUIVER_ITEM_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Quiver) or 11

local function IsAmmoBag(bag)
    if bit.band(GetBagFamily(bag), AMMO_BAG_FAMILY_MASK) ~= 0 then
        return true
    end

    local bagItemID = GetBagItemID(bag)
    if not bagItemID then
        return false
    end

    if GetItemFamily and bit.band(GetItemFamily(bagItemID) or 0, AMMO_BAG_FAMILY_MASK) ~= 0 then
        return true
    end

    local classID = GetItemInfoInstant and select(6, GetItemInfoInstant(bagItemID))
    return classID == QUIVER_ITEM_CLASS
end

local function GetBagSlotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.itemID, info.stackCount or 0
        end
        return nil, 0
    end

    if GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        itemID = itemID or (link and tonumber(string.match(link, "item:(%d+)")))
        return itemID, count or 0
    end

    return nil, 0
end

local function IsAmmo(itemID)
    if not itemID or not GetItemInfoInstant then
        return false
    end

    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    return equipLoc == "INVTYPE_AMMO"
end

local function GetEquippedAmmo()
    local ammoSlot = INVSLOT_AMMO or 0
    local itemID = GetInventoryItemID and GetInventoryItemID("player", ammoSlot)
    if IsAmmo(itemID) then
        return itemID
    end

    return nil
end

-- Returns a synthetic rule that fills the hunter's quiver or ammo pouch with
-- the ammo that is already in it, or nil when there is nothing to fill.
local function GetAmmoRule()
    if playerClass ~= "HUNTER" or not StockAndAweDB.ammo then
        return nil
    end

    local pouchSlots = {}
    local ammoCounts = {}

    for bag = 1, NUM_BAG_SLOTS or 4 do
        if IsAmmoBag(bag) then
            for slot = 1, GetBagNumSlots(bag) do
                local itemID, count = GetBagSlotItem(bag, slot)
                table.insert(pouchSlots, { itemID = itemID, count = count })
                if IsAmmo(itemID) then
                    ammoCounts[itemID] = (ammoCounts[itemID] or 0) + count
                end
            end
        end
    end

    if #pouchSlots == 0 then
        return nil
    end

    local ammoID, bestCount = nil, 0
    for itemID, count in pairs(ammoCounts) do
        if count > bestCount then
            ammoID, bestCount = itemID, count
        end
    end

    ammoID = ammoID or GetEquippedAmmo()
    if not ammoID then
        return nil
    end

    local rule = { itemID = ammoID, fallbackStack = AMMO_FALLBACK_STACK, isAmmo = true }
    local stackSize = GetStackSize(rule)
    local free = 0

    for _, pouchSlot in ipairs(pouchSlots) do
        if not pouchSlot.itemID then
            free = free + stackSize
        elseif pouchSlot.itemID == ammoID then
            free = free + math.max(0, stackSize - pouchSlot.count)
        end
    end

    rule.target = (GetItemCount(ammoID, false, false) or 0) + free
    return rule
end

local function GetClassRules()
    if not playerClass or not StockAndAweDB or not StockAndAweDB.rules then
        return nil
    end

    return StockAndAweDB.rules[playerClass]
end

-- Returns a normalized table: { name, stackCount, numAvailable, hasExtendedCost }
-- Uses C_MerchantFrame.GetItemInfo (11.0+) when available, else the legacy global.
local function GetMerchantSlotInfo(slot)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(slot)
        if not info then
            return nil
        end
        return {
            name = info.name,
            stackCount = info.stackCount,
            numAvailable = info.numAvailable,
            hasExtendedCost = info.hasExtendedCost,
        }
    end

    if GetMerchantItemInfo then
        local returnCount = select("#", GetMerchantItemInfo(slot))
        local name, _, _, stackCount, numAvailable, _, classicExtendedCost, modernExtendedCost = GetMerchantItemInfo(slot)
        local extendedCost = classicExtendedCost
        if returnCount >= 8 then
            extendedCost = modernExtendedCost
        end
        return {
            name = name,
            stackCount = stackCount,
            numAvailable = numAvailable,
            hasExtendedCost = extendedCost,
        }
    end

    return nil
end

local function GetMerchantItemId(slot)
    if GetMerchantItemID then
        local itemID = GetMerchantItemID(slot)
        if itemID then
            return itemID
        end
    end

    if GetMerchantItemLink then
        local itemLink = GetMerchantItemLink(slot)
        return itemLink and tonumber(string.match(itemLink, "item:(%d+)"))
    end

    return nil
end

local function BuildMerchantIndex()
    local items = {}

    for slot = 1, GetMerchantNumItems() do
        local info = GetMerchantSlotInfo(slot)
        local itemID = GetMerchantItemId(slot)

        if itemID and info and info.name then
            items[itemID] = {
                slot = slot,
                quantity = info.stackCount or 1,
                available = info.numAvailable,
                extendedCost = info.hasExtendedCost,
            }
        end
    end

    return items
end

local function BuildPurchase(rule, merchantItems)
    if rule.enabled == false then
        return nil
    end

    local merchantItem = merchantItems[rule.itemID]
    if not merchantItem or merchantItem.extendedCost then
        return nil
    end

    local target = GetRuleTarget(rule)
    local owned = GetItemCount(rule.itemID, false, false) or 0
    local missing = target - owned

    if missing <= 0 then
        return nil
    end

    local merchantQuantity = merchantItem.quantity
    if merchantQuantity < 1 then
        merchantQuantity = 1
    end

    local amount = missing
    if merchantItem.available and merchantItem.available > -1 then
        amount = math.min(amount, merchantItem.available * merchantQuantity)
    end

    -- Vendors sell ammo in fixed batches (e.g. 200 arrows); a quiver has a hard
    -- capacity, so only buy whole batches that fit.
    if rule.isAmmo and merchantQuantity > 1 then
        amount = math.floor(amount / merchantQuantity) * merchantQuantity
    end

    if amount <= 0 then
        return nil
    end

    return {
        itemID = rule.itemID,
        amount = amount,
        owned = owned,
        target = target,
        dryRun = StockAndAweDB.dryRun,
        merchantItem = merchantItem,
    }
end

local function FinishPurchase(entry)
    local owned = GetItemCount(entry.itemID, false, false) or 0
    local bought = math.max(0, owned - entry.owned)

    if bought > 0 then
        Announce(string.format("Bought %d %s (%d/%d).", bought, GetItemName(entry.itemID), owned, entry.target))
    else
        Announce("Could not buy " .. GetItemName(entry.itemID) .. ".")
    end

    table.remove(restockQueue, 1)
end

local function ProcessRestockQueue()
    local entry = restockQueue[1]
    if not entry then
        restockInProgress = false
        restockItemIDs = {}
        return
    end

    if not merchantOpen then
        restockQueue = {}
        restockInProgress = false
        restockItemIDs = {}
        return
    end

    local owned = GetItemCount(entry.itemID, false, false) or 0

    if entry.waitingForPurchase then
        if not entry.forceCheck and (not entry.merchantUpdated or not entry.bagUpdated) then
            return
        end

        if owned <= entry.ownedBeforePurchase then
            FinishPurchase(entry)
            ProcessRestockQueue()
            return
        end

        entry.waitingForPurchase = false
        entry.forceCheck = false
    end

    local missing = entry.target - owned
    if missing <= 0 then
        FinishPurchase(entry)
        ProcessRestockQueue()
        return
    end

    local remainingPlanned = entry.amount - math.max(0, owned - entry.owned)
    if remainingPlanned <= 0 then
        FinishPurchase(entry)
        ProcessRestockQueue()
        return
    end

    local maxPurchase = GetMerchantItemMaxStack and GetMerchantItemMaxStack(entry.merchantItem.slot)
    if not maxPurchase or maxPurchase < 1 then
        maxPurchase = GetStackSize(entry.rule)
    end

    local purchaseAmount = math.min(maxPurchase, remainingPlanned)

    entry.ownedBeforePurchase = owned
    entry.waitingForPurchase = true
    entry.merchantUpdated = false
    entry.bagUpdated = false
    entry.forceCheck = false
    entry.purchaseSequence = entry.purchaseSequence + 1
    local scheduledSession = merchantSession
    local scheduledPurchase = entry.purchaseSequence
    BuyMerchantItem(entry.merchantItem.slot, purchaseAmount)
    C_Timer.After(2, function()
        if scheduledSession == merchantSession and restockQueue[1] == entry and entry.purchaseSequence == scheduledPurchase then
            entry.forceCheck = true
            ProcessRestockQueue()
        end
    end)
end

local function QueuePurchase(result, rule)
    table.insert(restockQueue, {
        itemID = result.itemID,
        amount = result.amount,
        owned = result.owned,
        target = result.target,
        merchantItem = result.merchantItem,
        rule = rule,
        ownedBeforePurchase = nil,
        waitingForPurchase = false,
        merchantUpdated = false,
        bagUpdated = false,
        forceCheck = false,
        purchaseSequence = 0,
    })
    restockItemIDs[result.itemID] = true
end

local function Restock()
    if not StockAndAweDB.enabled then
        return
    end

    if restockInProgress then
        Print("Restocking is already in progress.")
        return
    end

    local rules = GetClassRules() or {}
    local ammoRule = GetAmmoRule()

    local merchantItems = BuildMerchantIndex()
    local purchases = {}

    for _, rule in ipairs(rules) do
        local result = BuildPurchase(rule, merchantItems)
        if result then
            table.insert(purchases, { result = result, rule = rule })
        end
    end

    if ammoRule then
        local result = BuildPurchase(ammoRule, merchantItems)
        if result then
            table.insert(purchases, { result = result, rule = ammoRule })
        end
    end

    for _, purchase in ipairs(purchases) do
        local result = purchase.result
        if result.dryRun then
            Print(string.format("Would buy %d %s (%d/%d).", result.amount, GetItemName(result.itemID), result.owned, result.target))
        else
            QueuePurchase(result, purchase.rule)
        end
    end

    if not StockAndAweDB.dryRun and #restockQueue > 0 and not restockInProgress then
        restockInProgress = true
        ProcessRestockQueue()
    end
end

local function SchedulePendingRestock()
    local scheduledSession = merchantSession
    C_Timer.After(0.1, function()
        if scheduledSession == merchantSession and merchantOpen and restockPending then
            merchantReady = true
            restockPending = false
            Restock()
        end
    end)
end

local function FindRule(rules, itemID)
    for index, rule in ipairs(rules) do
        if rule.itemID == itemID then
            return rule, index
        end
    end

    return nil, nil
end

local function ShowStatus()
    Print("enabled=" .. tostring(StockAndAweDB.enabled) .. ", dryRun=" .. tostring(StockAndAweDB.dryRun) .. ", announce=" .. tostring(StockAndAweDB.announce))

    if playerClass == "HUNTER" then
        local ammoRule = GetAmmoRule()
        if not StockAndAweDB.ammo then
            Print("Ammo refill: disabled.")
        elseif ammoRule then
            Print(string.format("Ammo refill: %s, target %d, bags %d", GetItemName(ammoRule.itemID), ammoRule.target, GetItemCount(ammoRule.itemID, false, false) or 0))
        else
            Print("Ammo refill: enabled, but no ammo found in a quiver or ammo pouch.")
        end
    end

    local rules = GetClassRules()
    if not rules or #rules == 0 then
        if playerClass == "HUNTER" then
            return
        end
        Print("No stock rules for your class yet. Use /saa item <itemID> <stacks>.")
        return
    end

    for _, rule in ipairs(rules) do
        Print(string.format("%s: %d stack(s), target %d, bags %d", GetItemName(rule.itemID), rule.stacks or 1, GetRuleTarget(rule), GetItemCount(rule.itemID, false, false) or 0))
    end
end

local function ResetClassRules()
    if not playerClass then
        return
    end

    StockAndAweDB.rules[playerClass] = CopyTable(DEFAULTS.rules[playerClass] or {})
    Print("Reset stock rules for your class.")
    UpdateTitanPanel()
end

local function SetRule(itemID, stacks, silent)
    if not VENDOR_REAGENT_ITEM_IDS[itemID] then
        Print(GetItemName(itemID) .. " is not a supported vendor reagent.")
        return
    end

    local rules = GetClassRules()
    if not rules then
        StockAndAweDB.rules[playerClass] = {}
        rules = StockAndAweDB.rules[playerClass]
    end

    local rule = FindRule(rules, itemID)
    if rule then
        rule.stacks = stacks
        rule.enabled = true
    else
        table.insert(rules, { itemID = itemID, stacks = stacks, fallbackStack = 20 })
    end

    if not silent then
        Print(string.format("%s set to %d stack(s).", GetItemName(itemID), stacks))
    end
    UpdateTitanPanel()
end

local function ToggleRule(itemID)
    local rules = GetClassRules()
    local rule = rules and FindRule(rules, itemID)

    if not rule then
        Print("No rule found for item:" .. tostring(itemID) .. ". Try /saa item <itemID> <stacks> first.")
        return
    end

    rule.enabled = rule.enabled == false
    Print(GetItemName(itemID) .. " auto-stock " .. (rule.enabled and "enabled." or "disabled.") .. "")
    UpdateTitanPanel()
end

local function RemoveRule(itemID)
    local rules = GetClassRules()
    if not rules then
        return
    end

    local _, index = FindRule(rules, itemID)
    if index then
        table.remove(rules, index)
        Print("Removed " .. GetItemName(itemID) .. ".")
        UpdateTitanPanel()
    else
        Print("No rule found for item:" .. tostring(itemID) .. ".")
    end
end

local function ShowHelp()
    Print("/saa - show current stock rules")
    Print("/saa on|off - enable or disable automatic buying")
    Print("/saa buy - restock from the open vendor now")
    Print("/saa dryrun - toggle preview mode without buying")
    Print("/saa quiet|chat - toggle purchase messages")
    Print("/saa ammo - toggle hunter quiver/ammo pouch refills")
    Print("/saa item <itemID> <stacks> - add or update a vendor reagent rule for your class")
    Print("/saa reagent <itemID> - toggle a reagent rule for your class")
    Print("/saa options - change stack targets for your class")
    Print("/saa remove <itemID> - remove a stock rule for your class")
    Print("/saa reset - reset your class to addon defaults")
end

local function HandleSlashCommand(input)
    local command, rest = string.match(input or "", "^(%S*)%s*(.-)$")
    command = string.lower(command or "")

    if command == "" or command == "status" then
        ShowStatus()
    elseif command == "on" then
        StockAndAweDB.enabled = true
        Print("Automatic buying enabled.")
        UpdateTitanPanel()
    elseif command == "off" then
        StockAndAweDB.enabled = false
        Print("Automatic buying disabled.")
        UpdateTitanPanel()
    elseif command == "buy" then
        if merchantOpen or (MerchantFrame and MerchantFrame:IsShown()) then
            merchantOpen = true
            if merchantReady then
                Restock()
            else
                restockPending = true
                SchedulePendingRestock()
            end
        else
            Print("Open a vendor first.")
        end
    elseif command == "dryrun" then
        StockAndAweDB.dryRun = not StockAndAweDB.dryRun
        Print("Dry run is now " .. tostring(StockAndAweDB.dryRun) .. ".")
        UpdateTitanPanel()
    elseif command == "quiet" then
        StockAndAweDB.announce = false
        Print("Purchase messages hidden.")
    elseif command == "chat" then
        StockAndAweDB.announce = true
        Print("Purchase messages shown.")
    elseif command == "ammo" then
        StockAndAweDB.ammo = not StockAndAweDB.ammo
        Print("Ammo refill " .. (StockAndAweDB.ammo and "enabled." or "disabled."))
    elseif command == "ammodebug" then
        for bag = 0, NUM_BAG_SLOTS or 4 do
            local bagItemID = bag > 0 and GetBagItemID(bag) or nil
            local itemFamily = bagItemID and GetItemFamily and GetItemFamily(bagItemID)
            local classID = bagItemID and GetItemInfoInstant and select(6, GetItemInfoInstant(bagItemID))
            local ammoSlots = 0
            for slot = 1, GetBagNumSlots(bag) do
                if IsAmmo((GetBagSlotItem(bag, slot))) then
                    ammoSlots = ammoSlots + 1
                end
            end
            Print(string.format("bag %d: item=%s slots=%d freeFamily=%s itemFamily=%s classID=%s ammoBag=%s ammoStacks=%d",
                bag, tostring(bagItemID), GetBagNumSlots(bag), tostring(GetBagFamily(bag)), tostring(itemFamily),
                tostring(classID), tostring(bag > 0 and IsAmmoBag(bag)), ammoSlots))
        end
        Print("equipped ammo: " .. tostring(GetEquippedAmmo()))
    elseif command == "item" then
        local itemID, stacks = string.match(rest, "^(%d+)%s+(%d+)$")
        itemID = tonumber(itemID)
        stacks = tonumber(stacks)

        if itemID and stacks and stacks > 0 then
            SetRule(itemID, stacks)
        else
            Print("Usage: /saa item <itemID> <stacks>")
        end
    elseif command == "remove" then
        local itemID = tonumber(rest)
        if itemID then
            RemoveRule(itemID)
        else
            Print("Usage: /saa remove <itemID>")
        end
    elseif command == "reagent" then
        local itemID = tonumber(rest)
        if itemID then
            ToggleRule(itemID)
        else
            Print("Usage: /saa reagent <itemID>")
        end
    elseif command == "options" then
        if StockAndAweOptions_Show then
            StockAndAweOptions_Show()
        end
    elseif command == "reset" then
        ResetClassRules()
    else
        ShowHelp()
    end
end

StockAndAweAPI = StockAndAweAPI or {}

function StockAndAweAPI.GetRules()
    return GetClassRules() or {}
end

function StockAndAweAPI.GetStatus()
    return StockAndAweDB and StockAndAweDB.enabled, StockAndAweDB and StockAndAweDB.dryRun
end

function StockAndAweAPI.GetRuleStatus(rule)
    return GetItemCount(rule.itemID, false, false) or 0, GetRuleTarget(rule)
end

function StockAndAweAPI.ToggleEnabled()
    StockAndAweDB.enabled = not StockAndAweDB.enabled
    Print("Automatic buying " .. (StockAndAweDB.enabled and "enabled." or "disabled."))
    UpdateTitanPanel()
end

function StockAndAweAPI.ToggleDryRun()
    StockAndAweDB.dryRun = not StockAndAweDB.dryRun
    Print("Dry run is now " .. tostring(StockAndAweDB.dryRun) .. ".")
    UpdateTitanPanel()
end

function StockAndAweAPI.ToggleRule(itemID)
    ToggleRule(itemID)
end

function StockAndAweAPI.SetRuleStacks(itemID, stacks)
    SetRule(itemID, stacks, true)
end

function StockAndAweAPI.ResetRules()
    ResetClassRules()
end

function StockAndAweAPI.Restock()
    Restock()
end

local function Initialize()
    StockAndAweDB = StockAndAweDB or {}
    ApplyDefaults()

    _, playerClass = UnitClass("player")

    SLASH_STOCKANDAWE1 = "/saa"
    SLASH_STOCKANDAWE2 = "/stockandawe"
    SlashCmdList.STOCKANDAWE = HandleSlashCommand

    if not chatFilterRegistered and ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_LOOT", FilterRestockLoot)
        chatFilterRegistered = true
    end

    if StockAndAweTitan_Initialize then
        StockAndAweTitan_Initialize()
    end

    if StockAndAweOptions_Initialize then
        StockAndAweOptions_Initialize()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:RegisterEvent("MERCHANT_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == addonName then
        Initialize()
    elseif event == "PLAYER_LOGIN" then
        _, playerClass = UnitClass("player")
    elseif event == "MERCHANT_SHOW" then
        merchantSession = merchantSession + 1
        merchantOpen = true
        merchantReady = false
        restockPending = true
        SchedulePendingRestock()
    elseif event == "MERCHANT_CLOSED" then
        merchantSession = merchantSession + 1
        merchantOpen = false
        merchantReady = false
        restockPending = false
        restockQueue = {}
        restockInProgress = false
        restockItemIDs = {}
    elseif event == "MERCHANT_UPDATE" then
        merchantReady = true
        if restockPending then
            restockPending = false
            Restock()
        else
            local entry = restockQueue[1]
            if entry and entry.waitingForPurchase then
                entry.merchantUpdated = true
                ProcessRestockQueue()
            end
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        local entry = restockQueue[1]
        if entry and entry.waitingForPurchase and (GetItemCount(entry.itemID, false, false) or 0) > entry.ownedBeforePurchase then
            entry.bagUpdated = true
            ProcessRestockQueue()
        end
    end
end)
