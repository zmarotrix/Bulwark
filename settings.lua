-- Bulwark's settings: a page under NorgannonDB in the game's Settings. /bulwark opens it.

local Core = NorgannonCore
local B = Bulwark
if B.disabled then return end
local UI = Core.UI

local COLORS = {
  { "me", "On you", "Tank mode. Not tanking, this is the colour for someone else." },
  { "other", "On someone else", "Someone who isn't a tank. Not tanking, this is the colour for you." },
  { "tank", "On another tank", "Their role is Tank, they're the main tank, they're in a bear form, Defensive Stance or Righteous Fury, or it's your pet." },
  { "none", "On nobody", "In combat, but not on anyone." },
  { "warn", "Threat % getting close", "The number, from 20 points below the flash line." },
  { "danger", "Threat % at the flash line", "The number, once it reaches the flash line." },
}

local function pick(key, after)
  local picker = rawget(_G, "ColorPickerFrame")
  if not picker then return end
  local before = { unpack(B.db.colors[key]) }
  local function set(c) B.db.colors[key] = c B.db.scheme = "custom" B:Changed() after() end
  local function apply() local r, g, b = picker:GetColorRGB() set({ r, g, b }) end
  local function cancel() set(before) end
  if picker.SetupColorPickerAndShow then
    picker:SetupColorPickerAndShow({ r = before[1], g = before[2], b = before[3], hasOpacity = false,
      swatchFunc = apply, cancelFunc = cancel })
  else
    picker.hasOpacity = false
    picker.func, picker.cancelFunc = apply, cancel
    picker.previousValues = { r = before[1], g = before[2], b = before[3] }
    picker:SetColorRGB(before[1], before[2], before[3])
    picker:Hide()
    picker:Show()
  end
end

Core:OnLogin(function()
  if not B.db then return end
  local page = CreateFrame("Frame")
  page:Hide()
  local list = UI.SettingsList(page)
  local function opt(key) return function() return B.db[key] end, function(v) B.db[key] = v B:Changed() end end

  list:Header("Bulwark")
  list:Toggle("Colour enemy nameplates", "Blizzard's health bar on each enemy plate takes the colour of who the mob is on. Mobs out of combat keep Blizzard's colour.", opt("enabled"))
  list:Dropdown("Mode", "Auto is tank mode when your role is Tank, you're in a tanking form or stance, or you're alone.",
    { { "auto", "Auto" }, { "tank", "Tank" }, { "dps", "Not tanking" } }, opt("mode"))

  list:Header("Flash")
  list:Toggle("Flash when you're about to lose it", "Tanking: someone is above you, or their threat is close to pulling. Not tanking: you're close to pulling it off the tank.", opt("flash"))
  list:Slider("Close means", "Someone's threat as a share of what it takes to pull the mob.", 70, 100, 5,
    function() return B.db.flashAt end, function(v) B.db.flashAt = v B:Changed() end, "%.0f%%", 1)

  list:Header("Threat %")
  local function tt(key) return function() return B.db.threatText[key] end, function(v) B.db.threatText[key] = v B:Changed() end end
  list:Toggle("Threat % on each plate", "Tanking a mob: how close the next person is to pulling it off you. Otherwise: how close you are to pulling it. Yellow 20 points before the flash line, red at it.", tt("enabled"))
  list:Slider("Text size", nil, 8, 16, 1, function() return B.db.threatText.size end, function(v) B.db.threatText.size = v B:Changed() end, "%.0f", 1)
  list:Dropdown("Where", nil, { { "inside", "Inside the bar, at its right end" }, { "below", "Below the bar" } }, tt("where"))

  list:Header("Raid marks")
  local function mark(key) return function() return B.db.marks[key] end, function(v) B.db.marks[key] = v B:Changed() end end
  list:Toggle("Bigger raid marks", "Our own mark in place of Blizzard's small one, so skull and cross stand out in a crowd.", mark("enabled"))
  list:Slider("Size", nil, 20, 64, 2, function() return B.db.marks.size end, function(v) B.db.marks.size = v B:Changed() end, "%.0f px", 1)
  list:Dropdown("Where", nil, { { "above", "Above the name" }, { "left", "Left of the health bar" } }, mark("where"))
  list:Toggle("Dark disc behind it", "Keeps the mark readable against bright spell effects and ground.", mark("backdrop"))

  list:Header("Mob list")
  local function ml(key) return function() return B.db.list[key] end, function(v) B.db.list[key] = v B:Changed() end end
  list:Toggle("Mob list", "A small window with every mob in the fight: its health, who it's on (the plate colours above), and your own DoTs and debuffs on it with the seconds left. Raid marks first, skull at the top; your target has a white edge.", ml("enabled"))
  list:Toggle("Only mobs in combat", "Off, it lists every enemy with a nameplate near you. Either way the Bulwark handle stays up, dimmed while the list is empty, so you can move it.", ml("combatOnly"))
  list:Toggle("Your DoTs and debuffs", "Timed from your casts on your target, since the game hides auras from add-ons in combat. A resisted or immune cast still shows a timer.", ml("dots"))
  list:Slider("Most mobs shown", "Your target always keeps a row.", 3, 20, 1, function() return B.db.list.rows end, function(v) B.db.list.rows = v B:Changed() end, "%.0f", 1)
  list:Slider("Bar width", nil, 90, 260, 10, function() return B.db.list.width end, function(v) B.db.list.width = v B:Changed() end, "%.0f px", 1)
  list:Slider("Row height", nil, 14, 30, 1, function() return B.db.list.height end, function(v) B.db.list.height = v B:Changed() end, "%.0f px", 1)
  list:Toggle("Click a row to target it", "Works in combat. The game only lets secure buttons target, and it lays them out itself during a fight, so in combat the rows go in the order mobs appeared (marked mobs first, as marked before the pull), and a mob not yet in the fight shows dimmed. Off, the list sorts freely but rows can't be clicked.", ml("click"))
  list:Slider("Background", "The panel behind the rows. At 0 only the Bulwark handle and the bars show.", 0, 100, 5,
    function() return B.db.list.background end, function(v) B.db.list.background = v B:Changed() end, "%.0f%%", 1)
  list:Toggle("Lock it in place", "Off, drag the list by the Bulwark mark and name above it.", ml("locked"))
  list:Buttons("Place it", "Shows sample mobs so you can move and size the list out of combat. /bulwark list does the same.", {
    { "Preview", function() B.MobList:Preview() end },
    { "Reset position", function() B.MobList:ResetPosition() end },
  })

  list:Header("Colours")
  local schemes = {}
  for _, sc in ipairs(B.SCHEMES) do schemes[#schemes + 1] = { sc.key, sc.label } end
  schemes[#schemes + 1] = { "custom", "Your own" }
  list:Dropdown("Colour scheme", "Ready-made colours, including colour-blind friendly ones. Changing any colour below makes it your own.",
    schemes, function() return B.db.scheme end,
    function(v) if v ~= "custom" then B:ApplyScheme(v) list:Refresh() end end)
  -- each colour: a framed swatch you click to change it, and Reset beside it only once it differs from the scheme
  local C = UI.C
  local function same(a, b) return math.abs(a[1] - b[1]) < 0.005 and math.abs(a[2] - b[2]) < 0.005 and math.abs(a[3] - b[3]) < 0.005 end
  local function schemeColor(key)
    local sc = B:Scheme(B.db.scheme) or B:Scheme("default")
    return sc.colors[key]
  end
  for _, def in ipairs(COLORS) do
    local key = def[1]
    local r = list:Buttons(def[2], def[3], {
      { "Reset", function()
        local c = schemeColor(key)
        B.db.colors[key] = { c[1], c[2], c[3] }
        B:Changed()
        list:Refresh()
      end },
    })
    local holder = r.control
    local swatch = CreateFrame("Button", nil, holder)
    swatch:SetSize(52, 24)
    swatch:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    swatch.box = UI.Box(swatch, "BACKGROUND", 0)
    swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
    swatch.fill:SetPoint("TOPLEFT", 3, -3)
    swatch.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    local function paint(hover) swatch.box:Set(hover and C.goldSoft or C.frameGold, C.frameDark) end
    paint(false)
    swatch:SetScript("OnEnter", function(self)
      paint(true)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine("Click to change", 1, 1, 1)
      GameTooltip:Show()
    end)
    swatch:SetScript("OnLeave", function() paint(false) GameTooltip:Hide() end)
    swatch:SetScript("OnClick", function() pick(key, function() list:Refresh() end) end)
    local reset = holder.button1
    reset:ClearAllPoints()
    reset:SetPoint("RIGHT", swatch, "LEFT", -12, 0)
    r.refresh = function()
      local c = B.db.colors[key]
      swatch.fill:SetColorTexture(c[1], c[2], c[3], 1)
      reset:SetShown(not same(c, schemeColor(key)))
    end
  end
  list:Buttons("Try it", "A training dummy or any mob shows the colours; /bulwark status says which mode you're in.", {
    { "Status", function() SlashCmdList.BULWARK("status") end } })

  page:SetScript("OnShow", function() list:Refresh() end)
  B.settingsPage = page
  B:AddSettingsPage(page)
end)
