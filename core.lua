-- Bulwark: a combat and aggro toolkit on Blizzard's own nameplates. Built on NorgannonDB_Core.
-- core.lua colours each enemy's health bar by who the mob is on and flashes it when you're about to lose it;
-- threat.lua puts a threat % on each plate; marks.lua draws bigger raid marks. Everything else about the plates is Blizzard's.
--
-- What the client allows (PlateProbe, 2026-11-07): Blizzard's enemy plate health bars can be repainted and the paint
-- holds; threat and "who is the mob targeting" can be read on nameplateN units. If any of those turns secret in some
-- fight, the code below falls back rather than erroring: a secret threat drops to "is it targeting me", and a secret
-- "is it targeting me" goes straight to the bar through a colour-from-boolean, with no flash.
--
-- Colours, in tank mode:          not-tank mode swaps the first two:
--   on you            green          on you            red
--   on someone else   red            on someone else   green
--   on another tank   cyan           on a tank         cyan
--   on nobody         grey           on nobody         grey
-- Mobs that aren't in combat keep Blizzard's colour.

local ADDON = ...
local Core = NorgannonCore

if not (Core and Core.NewAddon) then
  Bulwark = { disabled = true }
  print("Bulwark needs NorgannonDB Core 1.20 or newer; it is turned off.")
  return
end

Bulwark = Bulwark or {}
local B = Bulwark
local IsSecret = Core.IsSecret

B.DEFAULTS = {
  enabled = true,
  mode = "auto",          -- "auto": tank mode when you're a tank (role, stance or form) or alone; "tank"; "dps"
  flash = true,
  flashAt = 90,           -- flash when someone else's threat reaches this % of what it takes to pull the mob off you
  threatText = {
    enabled = true,       -- a small threat % on each enemy plate in combat (threat.lua)
    size = 10,
    where = "inside",     -- "inside" the bar at its right end, or "below" it
  },
  marks = {
    enabled = true,       -- our own bigger raid marks, in place of Blizzard's small ones
    size = 34,
    where = "above",      -- "above" the name, or "left" of the bar where Blizzard puts its own
    backdrop = true,      -- a soft dark disc behind the mark, so it stands out on a busy screen
  },
  list = {
    enabled = true,       -- the mob list (mobs.lua): every enemy in the fight, its health, and your DoTs on it
    combatOnly = true,    -- only mobs in combat (and any carrying one of your debuffs)
    dots = true,          -- your DoTs and debuffs with the seconds left
    rows = 8,
    width = 150,
    height = 18,
    markSize = 20,        -- the raid mark at the left of each row, px
    locked = false,
    background = 0,       -- the panel behind the rows, 0-100 %; 0 leaves just the handle and the bars
    click = true,         -- rows are secure buttons: click one to target that mob, in combat too (clicks.lua)
    learned = {},         -- spell name -> seconds, read off a mob out of combat (talents and ranks included)
  },
  scheme = "default",      -- a key of B.SCHEMES, or "custom" once you change a colour yourself
  colors = {
    me = { 0.2, 0.85, 0.25 },
    other = { 0.92, 0.15, 0.12 },
    tank = { 0.2, 0.8, 0.95 },
    none = { 0.55, 0.55, 0.55 },
    warn = { 1, 0.82, 0.2 },      -- threat % getting close
    danger = { 1, 0.35, 0.25 },   -- threat % at the flash line
  },
}

-- Ready-made colour schemes. The colour-blind ones use the Okabe-Ito palette, chosen so the pairs that matter
-- (on you / on someone else, getting close / at the line) differ in brightness as well as hue.
B.SCHEMES = {
  { key = "default", label = "Default", colors = B.DEFAULTS.colors },
  { key = "redgreen", label = "Red-green colour blind (protanopia, deuteranopia)", colors = {
    me = { 0.34, 0.71, 0.91 },      -- sky blue
    other = { 0.84, 0.37, 0 },      -- vermillion
    tank = { 0.94, 0.89, 0.26 },    -- yellow
    none = { 0.55, 0.55, 0.55 },
    warn = { 0.94, 0.89, 0.26 },
    danger = { 0.84, 0.37, 0 },
  } },
  { key = "blueyellow", label = "Blue-yellow colour blind (tritanopia)", colors = {
    me = { 0, 0.62, 0.45 },         -- bluish green
    other = { 0.9, 0.12, 0.2 },     -- red
    tank = { 0.8, 0.47, 0.65 },     -- reddish purple
    none = { 0.55, 0.55, 0.55 },
    warn = { 0.8, 0.47, 0.65 },
    danger = { 0.9, 0.12, 0.2 },
  } },
  { key = "contrast", label = "High contrast", colors = {
    me = { 0.1, 1, 0.1 },
    other = { 1, 0, 0 },
    tank = { 0, 0.55, 1 },
    none = { 0.3, 0.3, 0.3 },
    warn = { 1, 1, 0 },
    danger = { 1, 0, 0 },
  } },
}

local MODES = { auto = "Auto", tank = "Tank", dps = "Not tanking" }

local function setEnabled(on)
  B.db.enabled = on
  B:Changed()
  B:Print(on and "Colouring nameplates." or "Off: Blizzard's colours are back.")
end

local function setMode(mode)
  return function()
    B.db.mode = mode
    B:Changed()
    B:Print("Mode: " .. MODES[mode] .. ".")
  end
end

-- The suite's plumbing: version check, BulwarkDB with its defaults, the slash command, the minimap row and the add-on
-- menu. Bulwark has no window: a click opens its settings, and Shift-click turns it on or off.
Core:NewAddon("bulwark", {
  folder = ADDON, api = { 1, 20 },
  db = "BulwarkDB", defaults = B.DEFAULTS,
  slash = { "/bulwark" },
  commands = {
    on = { function() setEnabled(true) end, "colour enemy nameplates" },
    off = { function() setEnabled(false) end, "give Blizzard's colours back" },
    tank = { setMode("tank"), "always tank mode" },
    dps = { setMode("dps"), "never tank mode" },
    auto = { setMode("auto"), "tank mode when your role, form or stance says so" },
    list = { function() if B.MobList then B.MobList:Preview() end end, "show the mob list with sample mobs, to move it" },
    clicks = { function() if B.MobList and B.MobList.Secure then B.MobList.Secure:Debug() end end,
      "report what happens when you click a mob-list row (again to stop)" },
    status = { function()
      B:Print(("%s. Mode: %s (%s now). Flash: %s at %d%%.")
        :format(B.db.enabled and "On" or "Off", MODES[B.db.mode] or B.db.mode, B:TankMode() and "tanking" or "not tanking",
          B.db.flash and "on" or "off", B.db.flashAt))
    end, "what Bulwark is doing" },
  },
  minimap = {
    onShiftClick = function() setEnabled(not B.db.enabled) end,
    shiftHint = "on or off",
    status = function() return B.db and not B.db.enabled and "Off" or nil end,   -- otherwise the role shows
  },
})
if B.disabled then return end

function B:Scheme(key)
  for _, s in ipairs(self.SCHEMES) do if s.key == key then return s end end
end

---Put a scheme's colours in place.
function B:ApplyScheme(key)
  local s = self:Scheme(key)
  if not s then return end
  for k, c in pairs(s.colors) do self.db.colors[k] = { c[1], c[2], c[3] } end
  self.db.scheme = key
  self:Changed()
end

-------------------------------------------------------------------------------------------
-- Calling the client: any call may be missing, refuse, or answer with a secret
-------------------------------------------------------------------------------------------

---The first answer of fn(...), or nil if it errored. May be secret.
local function ask(fn, ...)
  local ok, v = Core.Call(fn, ...)
  if ok then return v end
end

---The answers only when they're plain; nil when secret, missing or errored.
local plain = Core.Plain

-------------------------------------------------------------------------------------------
-- Who's a tank
-------------------------------------------------------------------------------------------

-- Forms, stances and auras that mean "I'm tanking": Bear Form, Dire Bear Form, Defensive Stance, Righteous Fury.
local TANK_AURAS = { [5487] = true, [9634] = true, [71] = true, [25780] = true }
local TANK_FORMS = { [5] = true, [8] = true, [18] = true }   -- GetShapeshiftFormID: bear, dire bear, defensive stance

B.knownTanks = {}   -- guid -> true, learned out of combat (auras are secret in combat), kept until it's seen gone

local function hasTankAura(unit)
  local U = rawget(_G, "C_UnitAuras")
  if not (U and U.GetAuraDataByIndex) then return nil end
  for i = 1, 40 do
    local a = ask(U.GetAuraDataByIndex, unit, i, "HELPFUL")
    if a == nil then return false end
    if IsSecret(a) then return nil end
    local id = a.spellId
    if IsSecret(id) then return nil end
    if TANK_AURAS[id] then return true end
  end
  return false
end

---Learn whether a group member is in a tanking form. Only out of combat: in combat the last answer stands.
function B:LearnTank(unit)
  local guid = plain(UnitGUID, unit)
  if not guid then return end
  local tank = hasTankAura(unit)
  if tank ~= nil then self.knownTanks[guid] = tank or nil end
end

function B:IsTank(unit)
  if plain(UnitGroupRolesAssigned, unit) == "TANK" then return true end
  if plain(GetPartyAssignment, "MAINTANK", unit) then return true end
  if plain(UnitIsUnit, unit, "pet") then return true end   -- your own pet holding a mob is what you want
  if plain(UnitIsUnit, unit, "player") then
    local form = plain(rawget(_G, "GetShapeshiftFormID"))
    if form and TANK_FORMS[form] then return true end
  end
  local guid = plain(UnitGUID, unit)
  return guid ~= nil and self.knownTanks[guid] == true
end

function B:InGroup()
  return (plain(IsInGroup) or plain(IsInRaid)) and true or false
end

---Tank mode or not, from the setting.
function B:TankMode()
  local m = self.db.mode
  if m == "tank" then return true end
  if m == "dps" then return false end
  if not self:InGroup() then return true end
  return self:IsTank("player")
end

-------------------------------------------------------------------------------------------
-- The group, for "who has it"
-------------------------------------------------------------------------------------------

function B:GroupUnits()
  local out = {}
  if plain(IsInRaid) then
    for i = 1, (plain(GetNumGroupMembers) or 0) do
      local u = "raid" .. i
      if plain(UnitExists, u) and not plain(UnitIsUnit, u, "player") then out[#out + 1] = u end
    end
  else
    for i = 1, 4 do
      local u = "party" .. i
      if plain(UnitExists, u) then out[#out + 1] = u end
    end
  end
  if plain(UnitExists, "pet") then out[#out + 1] = "pet" end
  return out
end

-------------------------------------------------------------------------------------------
-- The verdict for one mob
-------------------------------------------------------------------------------------------

-- A verdict is { who = "me" | "other" | "tank" | "none", flash = bool } or nil for "leave Blizzard's colour",
-- or { secretIsMe = <secret boolean> } when all we have is a secret "is it targeting me".

---Who among the group the mob is on, by threat first and its target second. "other", "tank" or "none".
function B:Holder(plate)
  local holder
  for _, u in ipairs(self:GroupUnits()) do
    if plain(UnitThreatSituation, u, plate) == 3 then holder = u break end
  end
  if not holder then
    local target = plate .. "target"
    if not plain(UnitExists, target) then return "none" end
    holder = target
  end
  return self:IsTank(holder) and "tank" or "other"
end

---The highest threat anyone else in the group has on the mob, as a % of what it takes to pull it; nil if unreadable.
function B:OthersTopPercent(plate)
  local top
  for _, u in ipairs(self:GroupUnits()) do
    local ok, isTanking, status, pct = pcall(UnitDetailedThreatSituation, u, plate)
    if ok and not IsSecret(pct) and type(pct) == "number" and not IsSecret(isTanking) and not isTanking then
      if not top or pct > top then top = pct end
    end
  end
  return top
end

function B:Verdict(plate)
  if plain(UnitCanAttack, "player", plate) == false then return nil end
  local fighting = ask(UnitAffectingCombat, plate)
  if not IsSecret(fighting) and not fighting then return nil end

  local tankMode = self:TankMode()
  local status = ask(UnitThreatSituation, "player", plate)
  if IsSecret(status) then status = "secret" end

  if status == "secret" or status == nil then
    -- no threat to read (secret, or you're not on its threat list): who is it targeting?
    local target = plate .. "target"
    local isMe = ask(UnitIsUnit, target, "player")
    if IsSecret(isMe) then return { secretIsMe = isMe, tankMode = tankMode } end
    if isMe then return { who = "me", tankMode = tankMode } end
    return { who = self:Holder(plate), tankMode = tankMode }
  end

  local v = { tankMode = tankMode }
  if status >= 2 then
    v.who = "me"
    if tankMode and self.db.flash then
      if status == 2 then
        v.flash = true   -- you have it, but someone's above you and about to take it
      else
        local top = self:OthersTopPercent(plate)
        v.flash = top ~= nil and top >= self.db.flashAt
      end
    end
  else
    v.who = self:Holder(plate)
    if v.who == "none" and plain(UnitIsUnit, plate .. "target", "player") then v.who = "me" end
    if not tankMode and self.db.flash then
      if status == 1 then
        v.flash = true   -- you're above the tank and about to pull it
      else
        local _, _, pct = select(2, pcall(UnitDetailedThreatSituation, "player", plate))
        if not IsSecret(pct) and type(pct) == "number" and pct >= self.db.flashAt then v.flash = true end
      end
    end
  end
  return v
end

---The colour for a verdict.
function B:ColorFor(v)
  local c = self.db.colors
  local who = v.who
  if not v.tankMode then
    if who == "me" then who = "other" elseif who == "other" then who = "me" end
  end
  return c[who] or c.none
end

-------------------------------------------------------------------------------------------
-- Painting Blizzard's bar
-------------------------------------------------------------------------------------------

B.painted = {}   -- plate unit -> { bar, color = {r,g,b} | nil (secret), secret = {r,g,b secret}, flash = bool }
local overlays = {}   -- plate frame -> our flash overlay

local function plateFrame(unit)
  local NP = rawget(_G, "C_NamePlate")
  local p = NP and ask(NP.GetNamePlateForUnit, unit)
  if p == nil or IsSecret(p) then return nil end
  if p.IsForbidden and p:IsForbidden() then return nil end
  return p
end

local function healthBarOf(plate)
  local uf = plate and plate.UnitFrame
  if not uf then return nil end
  local bar = uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
  if bar and bar.IsForbidden and bar:IsForbidden() then return nil end
  return bar
end

local function overlayFor(plate, bar)
  local o = overlays[plate]
  if o then return o end
  local ok, made = pcall(function()
    local f = CreateFrame("Frame", nil, plate)
    f:SetAllPoints(bar)
    f:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(1, 1, 1, 0.55)
    t:SetBlendMode("ADD")
    local anim = f:CreateAnimationGroup()
    anim:SetLooping("BOUNCE")
    local a = anim:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.35)
    f.anim = anim
    f:Hide()
    return f
  end)
  if ok then overlays[plate] = made return made end
end

local function setFlash(plate, bar, on)
  local o = on and overlayFor(plate, bar) or overlays[plate]
  if not o then return end
  if on then
    if not o:IsShown() then o:Show() o.anim:Play() end
  elseif o:IsShown() then
    o.anim:Stop()
    o:Hide()
  end
end

-- Blizzard's own colour for the bar: it caches what it last set in bar.r/g/b.
local function blizzardColor(bar)
  local r, g, b = bar.r, bar.g, bar.b
  if IsSecret(r) or IsSecret(g) or IsSecret(b) or type(r) ~= "number" then return nil end
  return r, g, b
end

---Put Blizzard's colour back on a plate we painted.
function B:Restore(unit)
  local p = self.painted[unit]
  if not p then return end
  self.painted[unit] = nil
  local r, g, b = blizzardColor(p.bar)
  if r then pcall(p.bar.SetStatusBarColor, p.bar, r, g, b) end
  if p.plate then setFlash(p.plate, p.bar, false) end
end

local function apply(p)
  if p.color then
    pcall(p.bar.SetStatusBarColor, p.bar, p.color[1], p.color[2], p.color[3])
  elseif p.secretColor then
    pcall(function() p.bar:SetStatusBarColor(p.secretColor:GetRGB()) end)
  end
end

function B:Update(unit)
  if not self.db or IsSecret(unit) or type(unit) ~= "string" then return end
  local plate = plateFrame(unit)
  local bar = plate and healthBarOf(plate)
  if not bar then self.painted[unit] = nil return end
  if self.Threat then self.Threat:Update(unit, plate, bar) end
  if not self.db.enabled then self:Restore(unit) return end
  local v = self:Verdict(unit)
  if not v then self:Restore(unit) return end

  local p = self.painted[unit]
  if not p or p.bar ~= bar then p = { bar = bar, plate = plate } self.painted[unit] = p end
  if v.secretIsMe ~= nil then
    local CU = rawget(_G, "C_CurveUtil")
    local mine, theirs = self:ColorFor({ who = "me", tankMode = v.tankMode }), self:ColorFor({ who = "other", tankMode = v.tankMode })
    local color = CU and CU.EvaluateColorFromBoolean and CreateColor
      and ask(CU.EvaluateColorFromBoolean, v.secretIsMe, CreateColor(mine[1], mine[2], mine[3], 1), CreateColor(theirs[1], theirs[2], theirs[3], 1))
    p.color, p.secretColor = nil, color
    if not color then self:Restore(unit) return end
  else
    p.color, p.secretColor = self:ColorFor(v), nil
  end
  apply(p)
  setFlash(plate, bar, v.flash and true or false)
end

function B:UpdateAll()
  for i = 1, 40 do
    local u = "nameplate" .. i
    if plain(UnitExists, u) then self:Update(u) elseif self.painted[u] then self.painted[u] = nil end
  end
end

-- Blizzard recolours its bar on its own updates (reaction, tapped, threat); put ours straight back.
local function hookBlizzard()
  if type(CompactUnitFrame_UpdateHealthColor) ~= "function" then return end
  hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
    local unit = frame and frame.unit
    if IsSecret(unit) or type(unit) ~= "string" then return end
    local p = B.painted[unit]
    if p and p.bar == frame.healthBar then apply(p) end
  end)
end

-------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------

local function isPlate(unit)
  return not IsSecret(unit) and type(unit) == "string" and unit:find("^nameplate%d") ~= nil
end

function B:LearnGroup()
  if InCombatLockdown() then return end
  self:LearnTank("player")
  for _, u in ipairs(self:GroupUnits()) do self:LearnTank(u) end
end

Core:OnLogin(function()
  if not B.db then return end
  hookBlizzard()
  B:LearnGroup()
  local function onPlate(_, unit) if isPlate(unit) then B:Update(unit) end end
  Core:On("NAME_PLATE_UNIT_ADDED", B, onPlate)
  Core:On("NAME_PLATE_UNIT_REMOVED", B, function(_, unit)
    if not isPlate(unit) then return end
    local p = B.painted[unit]
    if p and p.plate then setFlash(p.plate, p.bar, false) end
    B.painted[unit] = nil
    local plate = plateFrame(unit)
    if plate and B.Threat then B.Threat:Hide(plate) end
  end)
  Core:On("UNIT_THREAT_LIST_UPDATE", B, onPlate)
  Core:On("UNIT_THREAT_SITUATION_UPDATE", B, function() B:UpdateAll() end)
  Core:On("UNIT_TARGET", B, onPlate)
  Core:On("UNIT_FLAGS", B, onPlate)   -- a mob entering or leaving combat
  Core:On("PLAYER_REGEN_ENABLED", B, function() B:LearnGroup() B:UpdateAll() end)
  Core:On("PLAYER_REGEN_DISABLED", B, function() B:UpdateAll() end)
  Core:On("GROUP_ROSTER_UPDATE", B, function() B:LearnGroup() B:UpdateAll() end)
  Core:On("PLAYER_ROLES_ASSIGNED", B, function() B:UpdateAll() end)
  Core:On("UPDATE_SHAPESHIFT_FORM", B, function() B:UpdateAll() end)
  Core:On("UNIT_AURA", B, function(_, unit)
    if not InCombatLockdown() and not isPlate(unit) then B:LearnTank(unit) end
  end)
  -- threat percentages move without an event for every step; a light sweep keeps the flash honest
  C_Timer.NewTicker(0.5, function() if B.db.enabled and next(B.painted) then B:UpdateAll() end end)
  B:UpdateAll()
end)

-------------------------------------------------------------------------------------------
-- Settings changed
-------------------------------------------------------------------------------------------

function B:Changed()
  self:UpdateAll()
  if self.Marks then self.Marks:UpdateAll() end
  if self.MobList then self.MobList:Changed() end
end
