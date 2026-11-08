-- The mob list: a small window with every enemy in the fight, its health, who it's on (the plate colours), and your
-- own DoTs and debuffs on it with the seconds left. Bulwark's take on Cursive.
--
-- What this client allows, and how the list works with it:
--   * Add-ons can't read auras in combat (ApiProbe, 2026-11-07: every aura call errors). So, like Cursive, the list
--     tracks your own casts: UNIT_SPELLCAST_SENT and _SUCCEEDED give your spell id in plain, and the mob is the one
--     you had targeted when you cast. How long each lasts comes from DOTS below, corrected by what we read out of
--     combat (learned durations, so talents and ranks come right after you've seen them once).
--     A resist or immune still shows a timer: in combat nothing tells us it missed.
--   * Health is always secret: the bar and the % get it straight from the client; nothing here reads it.
--   * Cursive sees every mob by GUID through nampower. Here a mob is on the list while it has a nameplate.
--   * Clicking a row targets the mob: clicks.lua, with secure buttons the game lays out itself in combat.
--   * The handle (mark and name) always shows while the list is on, so you can move it; with no mobs it's dimmed and
--     the rows are gone. The list hangs from its top-left corner, so rows come and go below a title that stays put.

local Core = NorgannonCore
local B = Bulwark
if B.disabled then return end
local UI = Core.UI
local IsSecret, plain = Core.IsSecret, Core.Plain

local L = { rows = {}, dots = {}, seen = {}, sent = {}, preview = false, gen = 1 }
B.MobList = L

-------------------------------------------------------------------------------------------
-- Your DoTs and debuffs: name -> seconds (the top rank); RANKS has the ranks that last less
-------------------------------------------------------------------------------------------

L.DOTS = {
  -- Warlock
  ["Corruption"] = 18, ["Curse of Agony"] = 24, ["Siphon Life"] = 30, ["Immolate"] = 15, ["Curse of Doom"] = 60,
  ["Curse of Recklessness"] = 120, ["Curse of Shadow"] = 300, ["Curse of the Elements"] = 300,
  ["Curse of Tongues"] = 30, ["Curse of Weakness"] = 120, ["Curse of Exhaustion"] = 12, ["Banish"] = 30,
  ["Fear"] = 20, ["Death Coil"] = 3,
  -- Priest
  ["Shadow Word: Pain"] = 18, ["Devouring Plague"] = 24, ["Vampiric Embrace"] = 60, ["Holy Fire"] = 10,
  ["Shackle Undead"] = 50, ["Hex of Weakness"] = 120, ["Mind Control"] = 60,
  -- Druid
  ["Moonfire"] = 12, ["Insect Swarm"] = 12, ["Faerie Fire"] = 40, ["Faerie Fire (Feral)"] = 40, ["Rake"] = 9,
  ["Rip"] = 12, ["Hibernate"] = 40, ["Entangling Roots"] = 27, ["Lacerate"] = 15,
  -- Hunter
  ["Serpent Sting"] = 15, ["Hunter's Mark"] = 120, ["Viper Sting"] = 8, ["Scorpid Sting"] = 20,
  ["Wyvern Sting"] = 12, ["Concussive Shot"] = 4, ["Wing Clip"] = 10,
  -- Rogue
  ["Garrote"] = 18, ["Rupture"] = 16, ["Expose Armor"] = 30, ["Hemorrhage"] = 15, ["Sap"] = 45, ["Blind"] = 10,
  ["Gouge"] = 4,
  -- Mage
  ["Polymorph"] = 50, ["Pyroblast"] = 12,
  -- Warrior
  ["Rend"] = 21, ["Sunder Armor"] = 30, ["Hamstring"] = 15, ["Mortal Strike"] = 10, ["Disarm"] = 10,
  -- Shaman
  ["Flame Shock"] = 12, ["Frost Shock"] = 8, ["Stormstrike"] = 12,
  -- Paladin
  ["Hammer of Justice"] = 6,
}

L.RANKS = {
  [172] = 12, [6222] = 15,                                   -- Corruption 1-2
  [5782] = 10, [6213] = 15,                                  -- Fear 1-2
  [710] = 20,                                                -- Banish 1
  [9484] = 30, [9485] = 40,                                  -- Shackle Undead 1-2
  [8921] = 9,                                                -- Moonfire 1
  [2637] = 20, [18657] = 30,                                 -- Hibernate 1-2
  [339] = 12, [1062] = 15, [5195] = 18, [5196] = 21, [9852] = 24,   -- Entangling Roots 1-5
  [118] = 20, [12824] = 30, [12825] = 40,                    -- Polymorph 1-3
  [772] = 9, [6546] = 12, [6547] = 15, [6548] = 18,          -- Rend 1-4
  [6770] = 25, [2070] = 35,                                  -- Sap 1-2
  [853] = 3, [5588] = 4, [5589] = 5,                         -- Hammer of Justice 1-3
}

-- debuffs that stack: each cast adds one, up to this many, and refreshes the timer
L.STACKS = { ["Lacerate"] = 5, ["Sunder Armor"] = 5 }

local function now() return GetTime() end

local function spellName(id)
  local CS = rawget(_G, "C_Spell")
  local name = CS and CS.GetSpellName and plain(CS.GetSpellName, id)
  if not name and rawget(_G, "GetSpellInfo") then name = plain(GetSpellInfo, id) end
  return name
end

local function spellIcon(id)
  local CS = rawget(_G, "C_Spell")
  local icon = CS and CS.GetSpellTexture and plain(CS.GetSpellTexture, id)
  if not icon and rawget(_G, "GetSpellInfo") then icon = select(3, plain(GetSpellInfo, id)) end
  return icon or 134400   -- the question mark
end

---How long your cast of spell id lasts, or nil when it isn't one the list tracks.
function L:Duration(id, name)
  if not (name and self.DOTS[name]) then return nil end
  local learned = B.db.list.learned[name]
  if learned then return learned end
  return self.RANKS[id] or self.DOTS[name]
end

-------------------------------------------------------------------------------------------
-- Which mob is which: its GUID when the client shows it, else its nameplate token while it has one
-------------------------------------------------------------------------------------------

local function keyOf(unit)
  return plain(UnitGUID, unit) or unit
end

---The nameplate token ("nameplate3") of a unit such as "target", or nil when it has no plate.
function L:PlateUnit(unit)
  local NP = rawget(_G, "C_NamePlate")
  local ok, p = Core.Call(NP and NP.GetNamePlateForUnit, unit)
  if ok and p and not IsSecret(p) then
    local t = p.namePlateUnitToken
    if IsSecret(t) or type(t) ~= "string" then t = p.UnitFrame and p.UnitFrame.unit end
    if not IsSecret(t) and type(t) == "string" then return t end
  end
  for i = 1, 40 do
    local u = "nameplate" .. i
    if plain(UnitExists, u) and plain(UnitIsUnit, unit, u) then return u end
  end
end

-------------------------------------------------------------------------------------------
-- Your casts
-------------------------------------------------------------------------------------------

function L:OnSent(unit, castGUID)
  if unit ~= "player" or IsSecret(castGUID) or type(castGUID) ~= "string" then return end
  local plate = self:PlateUnit("target")
  self.sent[castGUID] = plate and { unit = plate, key = keyOf(plate), at = now() } or false
end

function L:OnSucceeded(unit, castGUID, id)
  if unit ~= "player" or IsSecret(id) or type(id) ~= "number" then return end
  local where
  if not IsSecret(castGUID) and type(castGUID) == "string" then
    where = self.sent[castGUID]
    self.sent[castGUID] = nil
  end
  if where == nil then   -- no SENT seen for it: the target now
    local plate = self:PlateUnit("target")
    where = plate and { unit = plate, key = keyOf(plate) }
  end
  if not where then return end
  local name = spellName(id)
  local seconds = self:Duration(id, name)
  if not seconds then return end
  local stacks
  local max = self.STACKS[name]
  if max then   -- one more on a stack still running, else a fresh one
    local t = self.dots[where.key]
    local old = t and t[name]
    stacks = math.min(max, (old and old.expires > now() and old.stacks or 0) + 1)
  end
  self:Apply(where.key, name, spellIcon(id), seconds, nil, stacks)
end

---Put (or refresh) one of your debuffs on a mob. stacks: how many, for those that stack.
function L:Apply(key, name, icon, seconds, expires, stacks)
  local t = self.dots[key]
  if not t then t = {} self.dots[key] = t end
  t[name] = { icon = icon, duration = seconds, expires = expires or (now() + seconds), stacks = stacks }
  self.dirty = true
end

---Out of combat the client lets us read your debuffs on a mob: take the real timers, and learn how long each lasts.
function L:Read(unit)
  if InCombatLockdown() then return end
  local U = rawget(_G, "C_UnitAuras")
  if not (U and U.GetAuraDataByIndex) then return end
  local found = {}
  for i = 1, 40 do
    local ok, a = Core.Call(U.GetAuraDataByIndex, unit, i, "HARMFUL|PLAYER")
    if not ok or IsSecret(a) then return end
    if a == nil then break end
    local name, dur, exp = a.name, a.duration, a.expirationTime
    if IsSecret(name) or IsSecret(dur) or IsSecret(exp) then return end
    if type(name) == "string" and self.DOTS[name] and type(dur) == "number" and dur > 0 then
      found[name] = true
      B.db.list.learned[name] = dur
      local n = a.applications
      if IsSecret(n) or type(n) ~= "number" or n < 2 then n = self.STACKS[name] and 1 or nil end
      self:Apply(keyOf(unit), name, a.icon or 134400, dur, exp, n)
    end
  end
  local t = self.dots[keyOf(unit)]
  if t then
    for name in pairs(t) do if not found[name] then t[name] = nil end end
  end
end

---Drop expired debuffs, and mobs with none left.
function L:Expire()
  local t0 = now()
  for key, t in pairs(self.dots) do
    for name, d in pairs(t) do if d.expires <= t0 then t[name] = nil end end
    if next(t) == nil then self.dots[key] = nil end
  end
  for guid, sent in pairs(self.sent) do
    if not sent or t0 - (sent.at or 0) > 30 then self.sent[guid] = nil end
  end
end

-------------------------------------------------------------------------------------------
-- Which mobs: in combat (or carrying one of your debuffs), hostile, alive; marked ones first
-------------------------------------------------------------------------------------------

local MARK_ORDER = { [8] = 1, [7] = 2, [2] = 3, [6] = 4, [5] = 5, [4] = 6, [3] = 7, [1] = 8 }   -- skull, cross, circle, square, moon, triangle, diamond, star

function L:Include(unit, isTarget)
  if plain(UnitCanAttack, "player", unit) == false then return false end
  if plain(UnitIsDead, unit) then return false end
  if isTarget then return true end
  if self.dots[keyOf(unit)] then return true end
  if not B.db.list.combatOnly then return true end
  local ok, fighting = Core.Call(UnitAffectingCombat, unit)
  if not ok then return false end
  return IsSecret(fighting) or fighting == true
end

function L:Mobs()
  local out = {}
  local target = self:PlateUnit("target")
  local t0 = now()
  for i = 1, 40 do
    local u = "nameplate" .. i
    if plain(UnitExists, u) and self:Include(u, u == target) then
      local key = keyOf(u)
      if not self.seen[key] then self.seen[key] = t0 + i / 1000 end
      local mark = plain(GetRaidTargetIndex, u)
      out[#out + 1] = { unit = u, key = key, target = u == target, order = mark and MARK_ORDER[mark] or 99, seen = self.seen[key] }
    end
  end
  table.sort(out, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.seen < b.seen
  end)
  -- too many: the target always keeps a row, in place of the last one
  local max = B.db.list.rows
  if #out > max then
    local keep
    for i = max + 1, #out do if out[i].target then keep = out[i] end end
    for i = #out, max + 1, -1 do out[i] = nil end
    if keep then out[max] = keep end
  end
  return out
end

-------------------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------------------

local MAX_DOTS = 6
local HOSTILE, NEUTRAL, TAPPED = { 0.6, 0.22, 0.18 }, { 0.85, 0.7, 0.2 }, { 0.42, 0.42, 0.42 }
local SAVE_KEY = "BulwarkMobList"

local percentCurve
local function curve()
  if percentCurve ~= nil then return percentCurve or nil end
  local CU = rawget(_G, "C_CurveUtil")
  local ok, c = false, nil
  if CU and CU.CreateCurve then
    ok, c = pcall(function()
      local k = CU.CreateCurve()
      k:AddPoint(0, 0)
      k:AddPoint(1, 100)
      return k
    end)
  end
  percentCurve = ok and c or false
  return percentCurve or nil
end

-- where the list goes until you move it: its top-left corner left of the screen's middle
local function defaultPoint(f)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "LEFT", 40, 150)
end

---Anchor f by its top-left corner, where it sits now. StopMovingOrSizing anchors by whichever point is nearest, so
---without this a list near the bottom of the screen would grow upward and push its title around.
local function pinTop(f)
  local left, top = f:GetLeft(), f:GetTop()
  if not (left and top) then return end
  local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * s, top * s)
end

---Put f where it was saved (positions saved before 0.7.1 by another corner are turned into the top-left one).
local function place(f)
  defaultPoint(f)
  UI.RestorePosition(f, SAVE_KEY)
  pinTop(f)
end

-- the frame being shown: the secure one while it's in use, else the plain one
local function mover()
  local S = L.Secure
  if S and S.header and S.driver ~= "hide" and S.header:IsShown() then return S.header end
  return L.frame
end
local function startDrag()
  local f = mover()
  if f and not B.db.list.locked and not InCombatLockdown() then f:StartMoving() f.moving = true end
end
local function stopDrag()
  local f = mover()
  if not (f and f.moving) then return end
  f.moving = nil
  f:StopMovingOrSizing()
  pinTop(f)
  UI.SavePosition(f, SAVE_KEY)
  for _, other in ipairs({ L.frame, L.Secure and L.Secure.header }) do
    if other and other ~= f and not InCombatLockdown() then place(other) end
  end
end

L.StartDrag, L.StopDrag = startDrag, stopDrag

---One row's pieces, in the suite's look: a dark well with a 1px edge (gold on your target), the bar inside it, the
---name in the suite's bold face, and your debuffs as framed icons. passive: it sits on a secure button that takes the
---mouse (clicks.lua).
function L:MakeRow(f, passive)
  local r = CreateFrame("Frame", nil, f)
  if passive then
    r:EnableMouse(false)
  else
    r:EnableMouse(true)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", startDrag)
    r:SetScript("OnDragStop", stopDrag)
  end
  r.mark = r:CreateTexture(nil, "ARTWORK")
  r.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  r.well = CreateFrame("Frame", nil, r)
  r.box = UI.Box(r.well, "BACKGROUND", 0)
  r.bar = CreateFrame("StatusBar", nil, r.well)
  r.bar:SetPoint("TOPLEFT", 1, -1)
  r.bar:SetPoint("BOTTOMRIGHT", -1, 1)
  r.bar:SetStatusBarTexture(UI.TEX.white)
  r.bar:SetMinMaxValues(0, 1)
  r.bar:SetValue(1)
  -- a soft sheen on the top half, so the flat colour reads as a bar
  r.sheen = r.bar:CreateTexture(nil, "OVERLAY", nil, 1)
  r.sheen:SetPoint("TOPLEFT")
  r.sheen:SetPoint("RIGHT")
  UI.Gradient(r.sheen, { 1, 1, 1 }, { 1, 1, 1 }, 0.16, 0)
  r.warn = r.bar:CreateTexture(nil, "OVERLAY", nil, 2)
  r.warn:SetColorTexture(1, 1, 1, 0.3)
  r.warn:SetBlendMode("ADD")
  r.warn:SetAllPoints()
  r.name = r.bar:CreateFontString(nil, "OVERLAY", nil, 3)
  r.hp = r.bar:CreateFontString(nil, "OVERLAY", nil, 3)
  r.hp:SetJustifyH("RIGHT")
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.dots = {}
  for i = 1, MAX_DOTS do
    local d = CreateFrame("Frame", nil, r)
    d.box = UI.Box(d, "BACKGROUND", 0)
    d.box:Set(UI.C.black, UI.C.black)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetPoint("TOPLEFT", 1, -1)
    d.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.shade = d:CreateTexture(nil, "ARTWORK", nil, 1)
    d.shade:SetAllPoints(d.icon)
    d.shade:SetColorTexture(0, 0, 0, 0.35)
    d.time = d:CreateFontString(nil, "OVERLAY")
    d.time:SetPoint("CENTER", 0, 0)
    d.stack = d:CreateFontString(nil, "OVERLAY")
    d.stack:SetPoint("BOTTOMRIGHT", 1, -1)
    d:Hide()
    r.dots[i] = d
  end
  function r:SetTarget(on)
    self.isTarget = on
    self.box:Set(on and UI.C.gold or (self.hover and UI.C.goldSoft or UI.C.black), { UI.C.inset[1], UI.C.inset[2], UI.C.inset[3], 0.85 })
  end
  r:SetTarget(false)
  if not passive then
    r:SetScript("OnEnter", function(self) L.Tooltip(self, self.unit) end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return r
end

function L.Tooltip(owner, unit)
  if not unit then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if not Core.SetSecret(GameTooltip, "SetUnit", unit) then GameTooltip:Hide() return end
  GameTooltip:Show()
end

local HANDLE_H = 26   -- the mark and name on top; rows start below it
L.HANDLE_H = HANDLE_H

---Size and place every piece of a row from the settings.
function L:Layout(r, i)
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -(HANDLE_H + 4 + (i - 1) * (B.db.list.height + 3)))
  r:SetSize(self:Width() - 8, B.db.list.height)
  self:LayoutParts(r)
end

---The pieces inside a row.
function L:LayoutParts(r)
  local db = B.db.list
  local h, w = db.height, db.width
  local size = math.max(9, math.floor(h * 0.62))
  r.mark:ClearAllPoints()
  r.mark:SetPoint("LEFT", 0, 0)
  local m = db.markSize or h
  r.mark:SetSize(m, m)
  r.well:ClearAllPoints()
  r.well:SetPoint("LEFT", r.mark, "RIGHT", 4, 0)
  r.well:SetSize(w, h)
  r.sheen:SetHeight(math.max(1, math.floor((h - 2) / 2)))
  r.name:SetFontObject(UI.Font("bold", size))
  r.name:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
  r.hp:SetFontObject(UI.Font("body", size))
  r.hp:SetTextColor(UI.C.text[1], UI.C.text[2], UI.C.text[3])
  r.hp:ClearAllPoints()
  r.hp:SetPoint("RIGHT", r.bar, "RIGHT", -4, 0)
  r.name:ClearAllPoints()
  r.name:SetPoint("LEFT", r.bar, "LEFT", 4, 0)
  r.name:SetPoint("RIGHT", r.hp, "LEFT", -4, 0)
  for j, d in ipairs(r.dots) do
    d:ClearAllPoints()
    d:SetPoint("LEFT", r.well, "RIGHT", 4 + (j - 1) * (h + 3), 0)
    d:SetSize(h, h)
    d.time:SetFontObject(UI.Font("bold", math.max(9, math.floor(h * 0.6)), "OUTLINE"))
    d.stack:SetFontObject(UI.Font("bold", math.max(8, math.floor(h * 0.45)), "OUTLINE"))
    d.stack:SetTextColor(UI.C.gold[1], UI.C.gold[2], UI.C.gold[3])
  end
end

function L:Width()
  local db = B.db.list
  local dots = db.dots and MAX_DOTS * (db.height + 3) or 0
  return 4 + (db.markSize or db.height) + 4 + db.width + 4 + dots + 4
end

---The list's height for n rows.
function L:Height(n, extra)
  return HANDLE_H + 4 + n * (B.db.list.height + 3) + 3 + (extra or 0)
end

function L:Build()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", SAVE_KEY, UIParent)
  self:Dress(f)
  f:Hide()
  self.frame = f
  return f
end

---The list's look, on the plain frame or the secure one. On top, a handle with the Bulwark mark and name, always
---readable and the thing you drag. Below it the rows, on a stone panel framed in gold like every suite window, faded
---by the Background setting (none at all by default, as Cursive players are used to).
function L:Dress(f)
  local C = UI.C
  f:SetSize(240, 60)
  defaultPoint(f)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f.panel = CreateFrame("Frame", nil, f)
  f.panel:SetPoint("TOPLEFT", 0, -HANDLE_H)
  f.panel:SetPoint("BOTTOMRIGHT")
  f.panel:SetFrameLevel(math.max(0, f:GetFrameLevel()))
  f.panel.box = UI.Box(f.panel, "BACKGROUND", -6)
  f.panel.box:Set(C.frameGold, C.stone2, C.stone)
  f.handle = CreateFrame("Frame", nil, f)
  f.handle:SetPoint("TOPLEFT")
  f.handle:SetHeight(HANDLE_H)
  f.handle:EnableMouse(true)
  f.handle:RegisterForDrag("LeftButton")
  f.handle:SetScript("OnDragStart", startDrag)
  f.handle:SetScript("OnDragStop", stopDrag)
  f.handle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Bulwark", 1, 1, 1)
    GameTooltip:AddLine(B.db.list.locked and "Locked in place (settings)." or "Drag to move.", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  f.handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.mark = UI.Mark(f.handle, "bulwark", 24)
  f.mark:SetPoint("LEFT", 0, 0)
  f.title = UI.Text(f.handle, "title", 15, UI.AccentText("bulwark"))
  f.title:SetPoint("LEFT", f.mark, "RIGHT", 5, 0)
  f.title:SetText("Bulwark")
  UI.Glow(f.title)
  f.count = UI.Text(f.handle, "body", 12, C.muted)
  f.count:SetPoint("LEFT", f.title, "RIGHT", 7, -1)
  UI.Glow(f.count)
  f.hint = UI.Text(f, "body", 10, C.muted)
  f.hint:SetPoint("BOTTOMLEFT", 6, 5)
  UI.Glow(f.hint)
  self:Fade(f)
  place(f)
end

---The handle sized to its words, dimmed while there are no mobs (n == 0), and the panel faded to the Background
---setting (none behind an empty list).
function L:Fade(f, n)
  local a = (B.db.list.background or 0) / 100
  f.panel:SetAlpha(a)
  f.panel:SetShown(a > 0 and n ~= 0)
  f.handle:SetAlpha(n == 0 and 0.6 or 1)
  f.handle:SetWidth(24 + 5 + (f.title:GetStringWidth() or 60) + 7 + (f.count:GetStringWidth() or 20) + 4)
end

function L:Row(i)
  local r = self.rows[i]
  if not r then
    r = self:MakeRow(self.frame)
    self.rows[i] = r
  end
  return r
end

---The plate colour, toned down for a long bar in a list: the plates stay vivid, a column of full-strength green or red
---bars would shout over everything else on screen.
local function tone(c)
  return { c[1] * 0.6 + 0.04, c[2] * 0.6 + 0.04, c[3] * 0.6 + 0.04 }
end
L.Tone = tone

local function paintBar(r, unit)
  local v = B:Verdict(unit)
  r.warn:SetShown(v and v.flash and true or false)
  if v and v.secretIsMe ~= nil then
    local CU = rawget(_G, "C_CurveUtil")
    local mine, theirs = tone(B:ColorFor({ who = "me", tankMode = v.tankMode })), tone(B:ColorFor({ who = "other", tankMode = v.tankMode }))
    local ok, c = Core.Call(CU and CU.EvaluateColorFromBoolean, v.secretIsMe,
      CreateColor(mine[1], mine[2], mine[3], 1), CreateColor(theirs[1], theirs[2], theirs[3], 1))
    if ok and c and pcall(function() r.bar:SetStatusBarColor(c:GetRGB()) end) then return end
    v = nil
  end
  local c
  if v then c = tone(B:ColorFor(v))
  elseif B:TappedByOthers(unit) then c = TAPPED
  else c = plain(UnitReaction, unit, "player") == 4 and NEUTRAL or HOSTILE end
  r.bar:SetStatusBarColor(c[1], c[2], c[3])
end

local function paintHealth(r, unit)
  local okH, hp = Core.Call(UnitHealth, unit)
  local okM, mx = Core.Call(UnitHealthMax, unit)
  if okH and okM then
    Core.SetSecret(r.bar, "SetMinMaxValues", 0, mx)
    Core.SetSecret(r.bar, "SetValue", hp)
  end
  local k = curve()
  local okP, pct = false, nil
  if k then okP, pct = Core.Call(UnitHealthPercent, unit, true, k) end
  if okP and pct ~= nil and Core.SetSecret(r.hp, "SetFormattedText", "%.0f%%", pct) then return end
  if okH and okM and not IsSecret(hp) and not IsSecret(mx) and type(hp) == "number" and type(mx) == "number" and mx > 0 then
    r.hp:SetFormattedText("%.0f%%", hp / mx * 100)
  else
    r.hp:SetText("")
  end
end

---Your debuffs on a row, soonest to run out first.
local function paintDots(r, list)
  local show = B.db.list.dots
  local t0 = now()
  for i, d in ipairs(r.dots) do
    local e = show and list[i]
    if e then
      d.icon:SetTexture(e.icon)
      local left = e.expires - t0
      d.time:SetText(left >= 10 and ("%d"):format(left) or ("%.0f"):format(math.max(0, left)))
      local c = left < 3 and UI.C.bad or UI.C.text
      d.time:SetTextColor(c[1], c[2], c[3])
      d.box:Set(left < 3 and UI.C.bad or UI.C.black, UI.C.black)
      d.stack:SetText(e.stacks and e.stacks > 1 and tostring(e.stacks) or "")
      d:Show()
    else
      d:Hide()
    end
  end
end

local function sortedDots(key)
  local t = L.dots[key]
  local out = {}
  if not t then return out end
  for name, d in pairs(t) do out[#out + 1] = { name = name, icon = d.icon, expires = d.expires, stacks = d.stacks } end
  table.sort(out, function(a, b) return a.expires < b.expires end)
  return out
end

---Fill a row from a live mob.
function L:Paint(r, u, key)
  r.unit = u
  local okN, name = Core.Call(UnitName, u)
  if not (okN and Core.SetSecret(r.name, "SetText", name)) then r.name:SetText("") end
  paintHealth(r, u)
  paintBar(r, u)
  local okI, index = Core.Call(GetRaidTargetIndex, u)
  if okI and index ~= nil and pcall(SetRaidTargetIconTexture, r.mark, index) then r.mark:Show() else r.mark:Hide() end
  paintDots(r, sortedDots(key or keyOf(u)))
end

-- sample mobs for the preview, so the window can be placed and sized out of combat
local SAMPLE = {
  { name = "Defias Pillager", pct = 82, mark = 8, who = "me", target = true, dots = { { 135817, 14 }, { 136139, 6 } } },
  { name = "Defias Conjurer", pct = 47, mark = 7, who = "tank", dots = { { 136118, 2 } } },
  { name = "Defias Overseer", pct = 100, who = "other", flash = true, dots = {} },
  { name = "Defias Watchman", pct = 23, who = "none", dots = { { 136207, 21 }, { 132131, 9, 3 }, { 136139, 4 } } },
}

function L:Refresh()
  local db = B.db.list
  if not (db.enabled or self.preview) then
    if self.frame then self.frame:Hide() end
    return
  end
  self:Expire()
  local S = self.Secure
  if S and S:Active() and not self.preview then
    if self.frame then self.frame:Hide() end
    S:Refresh()
    return
  end
  if S then S:Hide() end
  local f = self:Build()
  local mobs
  if self.preview then
    mobs = {}
    for i, s in ipairs(SAMPLE) do mobs[i] = { sample = s, target = s.target } end
  else
    mobs = self:Mobs()
  end
  if #mobs == 0 then   -- just the handle, so the list can be moved and you know it's there
    for _, r in ipairs(self.rows) do r.unit = nil r:Hide() end
    f:SetSize(self:Width(), HANDLE_H)
    f.count:SetText("")
    f.hint:Hide()
    self:Fade(f, 0)
    f:Show()
    return
  end
  local width = self:Width()
  f:SetSize(width, self:Height(#mobs, self.preview and 16 or 0))
  f.count:SetText(self.preview and "preview" or tostring(#mobs))
  f.hint:SetText(self.preview and "Drag to move. /bulwark list to close." or "")
  f.hint:SetShown(self.preview)
  self:Fade(f, #mobs)
  for i, m in ipairs(mobs) do
    local r = self:Row(i)
    if r.laidOut ~= self.gen then self:Layout(r, i) r.laidOut = self.gen end
    r:SetTarget(m.target and true or false)
    if m.sample then
      local s = m.sample
      r.unit = nil
      r.name:SetText(s.name)
      r.hp:SetFormattedText("%d%%", s.pct)
      r.bar:SetMinMaxValues(0, 100)
      r.bar:SetValue(s.pct)
      local c = tone(B:ColorFor({ who = s.who, tankMode = B:TankMode() }))
      r.bar:SetStatusBarColor(c[1], c[2], c[3])
      r.warn:SetShown(s.flash and true or false)
      if s.mark then SetRaidTargetIconTexture(r.mark, s.mark) r.mark:Show() else r.mark:Hide() end
      local list = {}
      for j, d in ipairs(s.dots) do list[j] = { icon = d[1], expires = now() + d[2], stacks = d[3] } end
      paintDots(r, list)
    else
      self:Paint(r, m.unit, m.key)
    end
    r:Show()
  end
  for i = #mobs + 1, #self.rows do
    self.rows[i].unit = nil
    self.rows[i]:Hide()
  end
  f:Show()
end

---Show sample mobs (to move and size the window), or stop showing them.
function L:Preview(on)
  if on == nil then on = not self.preview end
  self.preview = on
  if self.Secure then self.Secure:Apply() end
  if on and not B.db.list.enabled then B:Print("The mob list is turned off in settings; this is how it would look.") end
  self:Refresh()
end

---Settings changed: lay the rows out again.
function L:Changed()
  self.gen = self.gen + 1
  if self.Secure then self.Secure:Apply() end
  if self.frame then self:Refresh() end
end

function L:ResetPosition()
  if InCombatLockdown() then return end
  local f = self:Build()
  defaultPoint(f)
  pinTop(f)
  UI.SavePosition(f, SAVE_KEY)
  if self.Secure and self.Secure.header then place(self.Secure.header) end
end

L.keyOf, L.MARK_ORDER, L.SAVE_KEY = keyOf, MARK_ORDER, SAVE_KEY

-------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------

local function isPlate(unit)
  return not IsSecret(unit) and type(unit) == "string" and unit:find("^nameplate%d") ~= nil
end

Core:OnLogin(function()
  if not B.db then return end
  Core:On("UNIT_SPELLCAST_SENT", L, function(_, unit, _, castGUID) L:OnSent(unit, castGUID) end)
  Core:On("UNIT_SPELLCAST_SUCCEEDED", L, function(_, unit, castGUID, id) L:OnSucceeded(unit, castGUID, id) end)
  Core:On("UNIT_AURA", L, function(_, unit) if isPlate(unit) then L:Read(unit) end end)
  Core:On("NAME_PLATE_UNIT_ADDED", L, function(_, unit) if isPlate(unit) then L:Read(unit) end end)
  Core:On("NAME_PLATE_UNIT_REMOVED", L, function(_, unit)
    -- a mob known only by its plate is gone with it; one known by GUID keeps its timers in case it comes back
    if isPlate(unit) and L.dots[unit] then L.dots[unit] = nil end
  end)
  Core:On("PLAYER_REGEN_ENABLED", L, function()
    for key in pairs(L.seen) do if not L.dots[key] then L.seen[key] = nil end end
    for i = 1, 40 do
      local u = "nameplate" .. i
      if plain(UnitExists, u) then L:Read(u) end
    end
  end)
  C_Timer.NewTicker(0.1, function()
    if B.db.list.enabled or L.preview or (L.frame and L.frame:IsShown()) then L:Refresh() end
  end)
end)
