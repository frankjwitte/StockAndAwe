local panel
local rows = {}

local function GetItemName(itemID)
    return GetItemInfo(itemID) or ("item:" .. tostring(itemID))
end

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(320, 26)
    row:SetPoint("TOPLEFT", 18, -54 - ((index - 1) * 28))

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(210)
    row.name:SetJustifyH("LEFT")

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.label:SetPoint("RIGHT", -64, 0)
    row.label:SetText("Stacks")

    row.input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.input:SetSize(38, 20)
    row.input:SetPoint("RIGHT", 0, 0)
    row.input:SetAutoFocus(false)
    row.input:SetNumeric(true)
    row.input:SetMaxLetters(2)
    row.input:SetJustifyH("CENTER")

    return row
end

local function Refresh()
    local rules = StockAndAweAPI.GetRules()
    local requiredRows = #rules

    for index = 1, requiredRows do
        local row = rows[index]
        if not row then
            row = CreateRow(index)
            rows[index] = row
        end

        local rule = rules[index]
        row.itemID = rule.itemID
        row.name:SetText(GetItemName(rule.itemID))
        row.input:SetText(tostring(rule.stacks or 1))
        row:Show()
    end

    for index = requiredRows + 1, #rows do
        rows[index]:Hide()
    end

    panel:SetHeight(math.max(140, 118 + (requiredRows * 28)))
end

local function Save()
    local changed = 0

    for _, row in ipairs(rows) do
        if row:IsShown() then
            local stacks = tonumber(row.input:GetText())
            if stacks and stacks >= 1 then
                StockAndAweAPI.SetRuleStacks(row.itemID, math.floor(stacks))
                changed = changed + 1
            end
        end
    end

    if changed > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffd6b45dStock And Awe|r: Stack targets saved.")
    end

    panel:Hide()
end

function StockAndAweOptions_Show()
    if not panel then
        return
    end

    Refresh()
    panel:Show()
end

function StockAndAweOptions_Initialize()
    if panel then
        return
    end

    panel = CreateFrame("Frame", "StockAndAweOptionsFrame", UIParent, "BackdropTemplate")
    panel:SetSize(356, 140)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Stock And Awe")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetText("Stack targets for this class")

    local save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    save:SetSize(86, 22)
    save:SetPoint("BOTTOMRIGHT", -18, 16)
    save:SetText("Save")
    save:SetScript("OnClick", Save)

    local cancel = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    cancel:SetSize(86, 22)
    cancel:SetPoint("RIGHT", save, "LEFT", -6, 0)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function()
        panel:Hide()
    end)
end
