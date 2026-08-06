local TITAN_ID = "StockAndAwe"
local TITAN_BUTTON = "TitanPanelStockAndAweButton"

local function GetItemName(itemID)
    return GetItemInfo(itemID) or ("item:" .. tostring(itemID))
end

local function Update()
    if TitanPanelButton_UpdateButton and _G[TITAN_BUTTON] then
        TitanPanelButton_UpdateButton(TITAN_ID)
    end
end

local function GetRuleText(rule)
    local owned, target = StockAndAweAPI.GetRuleStatus(rule)
    return string.format("%s: %d/%d", GetItemName(rule.itemID), owned, target)
end

function TitanPanelStockAndAwe_GetButtonText()
    local enabled = StockAndAweAPI.GetStatus()
    local state = enabled and "|cff00ff00On|r" or "|cffff0000Off|r"
    return "Stock: " .. state
end

function TitanPanelStockAndAwe_GetTooltipText()
    local enabled, dryRun = StockAndAweAPI.GetStatus()
    local lines = {
        "Auto-stock: " .. (enabled and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"),
        "Dry run: " .. (dryRun and "|cffffff00Enabled|r" or "Disabled"),
        " ",
    }

    for _, rule in ipairs(StockAndAweAPI.GetRules()) do
        local status = rule.enabled == false and "|cffff0000off|r" or "|cff00ff00on|r"
        table.insert(lines, string.format("%s [%s]", GetRuleText(rule), status))
    end

    table.insert(lines, " ")
    table.insert(lines, "Left-click: toggle automatic buying")
    table.insert(lines, "Right-click: options")
    return table.concat(lines, "\n")
end

local function ToggleEnabled()
    StockAndAweAPI.ToggleEnabled()
    Update()
end

local function ToggleDryRun()
    StockAndAweAPI.ToggleDryRun()
    Update()
end

local function Restock()
    StockAndAweAPI.Restock()
end

local function ResetRules()
    StockAndAweAPI.ResetRules()
    Update()
end

local function ShowOptions()
    if StockAndAweOptions_Show then
        StockAndAweOptions_Show()
    end
end

function TitanPanelRightClickMenu_PrepareStockAndAweMenu()
    local level = UIDROPDOWNMENU_MENU_LEVEL

    if level == 1 then
        UIDropDownMenu_AddButton({ text = "Stock And Awe", isTitle = true, notCheckable = true }, level)
        UIDropDownMenu_AddButton({ text = "Automatic buying", func = ToggleEnabled, checked = select(1, StockAndAweAPI.GetStatus()), keepShownOnClick = true }, level)
        UIDropDownMenu_AddButton({ text = "Dry run", func = ToggleDryRun, checked = select(2, StockAndAweAPI.GetStatus()), keepShownOnClick = true }, level)
        UIDropDownMenu_AddButton({ text = "Reagents", hasArrow = true, value = "reagents", notCheckable = true }, level)
        UIDropDownMenu_AddButton({ text = "Restock now", func = Restock, notCheckable = true }, level)
        UIDropDownMenu_AddButton({ text = "Open options", func = ShowOptions, notCheckable = true }, level)
        UIDropDownMenu_AddButton({ text = "Reset this class", func = ResetRules, notCheckable = true }, level)
        TitanPanelRightClickMenu_AddSpacer()
        TitanPanelRightClickMenu_AddToggleIcon(TITAN_ID)
        TitanPanelRightClickMenu_AddToggleLabelText(TITAN_ID)
        TitanPanelRightClickMenu_AddCommand(TITAN_PANEL_MENU_HIDE, TITAN_ID, TITAN_PANEL_MENU_FUNC_HIDE)
    elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "reagents" then
        for _, rule in ipairs(StockAndAweAPI.GetRules()) do
            local itemID = rule.itemID
            UIDropDownMenu_AddButton({
                text = GetRuleText(rule),
                func = function()
                    StockAndAweAPI.ToggleRule(itemID)
                    Update()
                end,
                checked = rule.enabled ~= false,
                keepShownOnClick = true,
            }, level)
        end
    end
end

function StockAndAweTitan_Initialize()
    if _G[TITAN_BUTTON] or not TitanPanelButton_OnLoad then
        return
    end

    local button = CreateFrame("Button", TITAN_BUTTON, UIParent, "TitanPanelComboTemplate")
    button.registry = {
        version = "0.2.3",
        id = TITAN_ID,
        menuText = "Stock And Awe",
        buttonTextFunction = "TitanPanelStockAndAwe_GetButtonText",
        tooltipTitle = "Stock And Awe",
        tooltipTextFunction = "TitanPanelStockAndAwe_GetTooltipText",
        icon = "Interface\\Icons\\INV_Misc_Bag_10",
        iconWidth = 16,
        savedVariables = {
            ShowIcon = 1,
            ShowLabelText = 1,
            ShowColoredText = 1,
        },
    }

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            ToggleEnabled()
        else
            TitanPanelButton_OnClick(self, mouseButton)
        end
    end)
end
