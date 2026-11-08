-- Bigger raid marks on enemy nameplates. Blizzard draws a 22px mark left of the health bar (Blizzard_NamePlates.xml,
-- RaidTargetFrame), which is lost in a crowd. We draw our own, larger, above the name, with a soft dark disc behind it,
-- and hide Blizzard's small one while ours shows. Blizzard's frame is only ever faded, never moved or resized.

local Core = NorgannonCore
local B = Bulwark
if B.disabled then return end
local IsSecret = Core.IsSecret

local Marks = { icons = {} }   -- plate frame -> our mark frame
B.Marks = Marks

local function plateFrame(unit)
  local NP = rawget(_G, "C_NamePlate")
  local ok, p = pcall(NP.GetNamePlateForUnit, unit)
  if not ok or p == nil or IsSecret(p) then return nil end
  if p.IsForbidden and p:IsForbidden() then return nil end
  return p
end

local function iconFor(plate)
  local f = Marks.icons[plate]
  if f then return f end
  f = CreateFrame("Frame", nil, plate)
  f:SetFrameLevel((plate:GetFrameLevel() or 1) + 10)
  f.disc = f:CreateTexture(nil, "BACKGROUND")
  f.disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  f.disc:SetVertexColor(0, 0, 0, 0.55)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
  f.icon:SetAllPoints()
  f:Hide()
  Marks.icons[plate] = f
  return f
end

function Marks:Place(f, plate)
  local db, uf = B.db.marks, plate.UnitFrame
  local size = db.size
  f:SetSize(size, size)
  f.disc:ClearAllPoints()
  f.disc:SetPoint("CENTER")
  f.disc:SetSize(size * 1.25, size * 1.25)
  f.disc:SetShown(db.backdrop)
  f:ClearAllPoints()
  local bar = uf and (uf.HealthBarsContainer or uf.healthBar)
  if db.where == "left" and bar then
    f:SetPoint("RIGHT", bar, "LEFT", -4, 0)
  elseif uf and uf.name then
    f:SetPoint("BOTTOM", uf.name, "TOP", 0, 4)
  else
    f:SetPoint("BOTTOM", plate, "TOP", 0, 0)
  end
end

-- Blizzard's own small mark: faded out while ours shows, back when we stop.
local function blizzardMark(plate, shown)
  local rf = plate.UnitFrame and plate.UnitFrame.RaidTargetFrame
  if rf and rf.SetAlpha then pcall(rf.SetAlpha, rf, shown and 1 or 0) end
end

function Marks:Update(unit)
  if not B.db or IsSecret(unit) or type(unit) ~= "string" then return end
  local plate = plateFrame(unit)
  if not plate then return end
  local f = Marks.icons[plate]
  if not B.db.marks.enabled then
    if f then f:Hide() end
    blizzardMark(plate, true)
    return
  end
  local ok, index = pcall(GetRaidTargetIndex, unit)
  if not ok or index == nil then
    if f then f:Hide() end
    blizzardMark(plate, true)
    return
  end
  f = iconFor(plate)
  self:Place(f, plate)
  -- the index may be secret: SetRaidTargetIconTexture takes it as it is
  local set = pcall(SetRaidTargetIconTexture, f.icon, index)
  if not set then
    f:Hide()
    blizzardMark(plate, true)
    return
  end
  f:Show()
  blizzardMark(plate, false)
end

function Marks:Forget(unit)
  local plate = plateFrame(unit)
  local f = plate and Marks.icons[plate]
  if f then f:Hide() end
end

function Marks:UpdateAll()
  for i = 1, 40 do
    local u = "nameplate" .. i
    local ok, exists = pcall(UnitExists, u)
    if ok and not IsSecret(exists) and exists then self:Update(u) end
  end
end

Core:OnLogin(function()
  if not B.db then return end
  Core:On("RAID_TARGET_UPDATE", Marks, function() Marks:UpdateAll() end)
  Core:On("NAME_PLATE_UNIT_ADDED", Marks, function(_, unit) Marks:Update(unit) end)
  Core:On("NAME_PLATE_UNIT_REMOVED", Marks, function(_, unit) if not IsSecret(unit) then Marks:Forget(unit) end end)
  Marks:UpdateAll()
end)
