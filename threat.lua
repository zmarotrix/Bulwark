-- Threat % on enemy nameplates: one small number per mob in combat, the one that matters for your role.
--   Tanking, and you hold the mob: the highest threat anyone else has, as a % of what it takes to pull it off you.
--     "72%" means the next person is 72% of the way to taking it. Hidden when you're alone (nobody else to watch).
--   Otherwise: your own threat, as a % of what it takes to pull it. For a tank that's how close you are to taking it
--   back; for everyone else, how close you are to pulling it off the tank.
-- If the client keeps the number secret it still shows, through SetFormattedText, but in plain white.

local Core = NorgannonCore
local B = Bulwark
if B.disabled then return end
local IsSecret = Core.IsSecret

local Threat = { texts = {} }   -- plate frame -> our font string's holder
B.Threat = Threat

local WHITE = { 0.95, 0.95, 0.95 }

---number (may be secret), kind ("lead" | "mine"), or nil when there's nothing to show.
function Threat:Number(plate)
  local okA, attackable = pcall(UnitCanAttack, "player", plate)
  if okA and not IsSecret(attackable) and not attackable then return nil end
  if B:TappedByOthers(plate) then return nil end
  local okC, fighting = pcall(UnitAffectingCombat, plate)
  if not okC or (not IsSecret(fighting) and not fighting) then return nil end
  local ok, isTanking, _, pct = pcall(UnitDetailedThreatSituation, "player", plate)
  if not ok then return nil end
  if not IsSecret(isTanking) and isTanking and B:TankMode() then
    local top = B:OthersTopPercent(plate)
    if top then return top, "lead" end
    return nil
  end
  if pct == nil then return nil end
  if not IsSecret(pct) and type(pct) ~= "number" then return nil end
  return pct, "mine"
end

---The colour for a plain number: white while it's safe, the warn colour getting close, the danger colour at the flash line (both in settings).
function Threat:ColorFor(n, kind)
  if kind == "mine" and B:TankMode() then return WHITE end   -- a tank wants this one high
  local at = B.db.flashAt
  if n >= at then return B.db.colors.danger end
  if n >= at - 20 then return B.db.colors.warn end
  return WHITE
end

local function textFor(plate, bar)
  local t = Threat.texts[plate]
  if t then return t end
  local f = CreateFrame("Frame", nil, plate)
  f:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)
  f:SetAllPoints(bar)
  f.text = f:CreateFontString(nil, "OVERLAY")
  f:Hide()
  Threat.texts[plate] = f
  return f
end

function Threat:Place(f, bar)
  local db = B.db.threatText
  local font = rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF"
  pcall(f.text.SetFont, f.text, font, db.size, "OUTLINE")
  f.text:ClearAllPoints()
  if db.where == "below" then
    f.text:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -1)
  else
    f.text:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
  end
end

function Threat:Hide(plate)
  local f = plate and self.texts[plate]
  if f then f:Hide() end
end

function Threat:Update(unit, plate, bar)
  if not (B.db.threatText.enabled and B.db.enabled) then self:Hide(plate) return end
  local n, kind = self:Number(unit)
  if n == nil then self:Hide(plate) return end
  local f = textFor(plate, bar)
  self:Place(f, bar)
  if IsSecret(n) then
    if not pcall(f.text.SetFormattedText, f.text, "%.0f%%", n) then self:Hide(plate) return end
    f.text:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
  else
    f.text:SetFormattedText("%.0f%%", n)
    local c = self:ColorFor(n, kind)
    f.text:SetTextColor(c[1], c[2], c[3])
  end
  f:Show()
end
