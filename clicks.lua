-- Click a row of the mob list to target that mob, in combat too.
--
-- Only secure buttons can target, and in combat add-on code can't move, show, hide or re-point them. So the rows here
-- are the game's own secure unit buttons, one per nameplate token (nameplate1 to nameplate40), and the game lays them
-- out itself:
--   * RegisterUnitWatch shows a button while its nameplate exists.
--   * A secure snippet on the list (the "layout" attribute below; it runs in the game's restricted environment, the way
--     group frames sort themselves) stacks the shown buttons whose mob you can attack, in the order they appeared.
--   * Out of combat Bulwark hands that snippet a preferred order (raid marks first, skull at the top) for the next fight.
-- Add-on code only paints the rows (name, health, colour, DoTs), which sit on the buttons as plain child frames.
-- Trade-offs against the plain list, which "Click a row to target it" off brings back: in combat a mob that isn't in
-- the fight yet still has a row (dimmed), marks put on mid-fight don't reorder, and the target doesn't jump the queue.
-- The list itself always shows while it's on (the handle, to move it); "Only mobs in combat" empties it out of combat
-- through a second state driver ("fight") that re-runs the layout as combat starts and ends.
-- Restricted code can't be run by the harness's stub client the way the game runs it; bulwark_test.py runs the snippet
-- in a stand-in environment with the same functions, which proves its logic, not the game's acceptance of it.

local Core = NorgannonCore
local B = Bulwark
if B.disabled then return end
local L = B.MobList
local UI = Core.UI
local IsSecret, plain = Core.IsSecret, Core.Plain

local S = { buttons = {} }
L.Secure = S

local MAX_UNITS = 40

-- self is the list (a secure header). ... = the button id that showed or hid, and whether it's shown now.
-- Globals in this snippet (order, orderN) live in the list's own secure environment between calls.
S.LAYOUT = [=[
  local id, shown = ...
  local kept, n = newtable(), 0
  for i = 1, (orderN or 0) do
    if order[i] ~= id then n = n + 1 kept[n] = order[i] end
  end
  if shown and id and id > 0 then n = n + 1 kept[n] = id end
  order, orderN = kept, n

  -- a row for each mob you can attack that's alive
  local ok, okN = newtable(), 0
  for i = 1, n do
    local u = "nameplate" .. order[i]
    if UnitExists(u) and PlayerCanAttack(u) and not UnitIsDead(u) then okN = okN + 1 ok[okN] = order[i] end
  end

  -- the preferred order first (marks, set out of combat), then the order they appeared
  local ranked, rN, used = newtable(), 0, newtable()
  for p in gmatch(self:GetAttribute("pref") or "", "%d+") do
    p = tonumber(p)
    for i = 1, okN do
      if ok[i] == p and not used[p] then rN = rN + 1 ranked[rN] = p used[p] = true end
    end
  end
  for i = 1, okN do
    if not used[ok[i]] then rN = rN + 1 ranked[rN] = ok[i] used[ok[i]] = true end
  end

  -- only mobs in combat: no rows until you're in the fight (the "fight" driver re-runs this as it starts and ends)
  local fight = self:GetAttribute("state-fight")
  if self:GetAttribute("combatonly") and fight ~= "1" and fight ~= 1 then rN = 0 end

  local h = self:GetAttribute("rowh") or 18
  local top = self:GetAttribute("top") or 30
  local max = self:GetAttribute("maxrows") or 8
  local placed = newtable()
  for i = 1, rN do
    if i <= max then
      local b = self:GetFrameRef("b" .. ranked[i])
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -(top + (i - 1) * (h + 3)))
      b:SetAlpha(1)
      b:EnableMouse(true)
      placed[ranked[i]] = true
    end
  end
  for i = 1, 40 do
    if not placed[i] then
      local b = self:GetFrameRef("b" .. i)
      if b then b:SetAlpha(0) b:EnableMouse(false) end
    end
  end
  local shownN = rN
  if shownN > max then shownN = max end
  if shownN > 0 then self:SetHeight(top + shownN * (h + 3) + 3) else self:SetHeight(top - 4) end
  self:SetAttribute("count", shownN)
]=]

local WRAP_SHOW = [=[ control:RunAttribute("layout", self:GetID(), true) ]=]
local WRAP_HIDE = [=[ control:RunAttribute("layout", self:GetID(), false) ]=]
local RELAYOUT = [=[ self:RunAttribute("layout", 0, false) ]=]

function S:Active()
  local db = B.db.list
  return db.enabled and db.click and self.header ~= nil
end

---Build the secure list. Out of combat only; false if it can't be built (the plain list carries on).
function S:Build()
  if self.header then return true end
  if self.failed or InCombatLockdown() then return false end
  local ok, err = pcall(function()
    local h = CreateFrame("Frame", "BulwarkMobHeader", UIParent, "SecureHandlerStateTemplate")
    L:Dress(h)
    h:SetAttribute("layout", S.LAYOUT)
    h:SetAttribute("_onstate-fight", RELAYOUT)
    for i = 1, MAX_UNITS do
      local unit = "nameplate" .. i
      local b = CreateFrame("Button", "BulwarkMobButton" .. i, h, "SecureUnitButtonTemplate")
      b:SetID(i)
      b:SetAttribute("unit", unit)
      b:SetAttribute("*type1", "target")
      b:SetAttribute("*type2", "target")
      b:RegisterForClicks("AnyUp", "AnyDown")
      b:RegisterForDrag("LeftButton")
      b:SetScript("OnDragStart", L.StartDrag)
      b:SetScript("OnDragStop", L.StopDrag)
      b.row = L:MakeRow(b, true)
      b.row:SetAllPoints(b)
      b:HookScript("OnMouseDown", function(_, button) S:Note(i, "the mouse reached the row (" .. tostring(button) .. ")") end)
      b:HookScript("PostClick", function(_, button, down) S:Clicked(i, button, down) end)
      b:HookScript("OnEnter", function(self)
        self.row.hover = true
        self.row:SetTarget(self.row.isTarget)
        L.Tooltip(self, unit)
      end)
      b:HookScript("OnLeave", function(self)
        self.row.hover = nil
        self.row:SetTarget(self.row.isTarget)
        GameTooltip:Hide()
      end)
      b:SetAlpha(0)
      h:SetFrameRef("b" .. i, b)
      h:WrapScript(b, "OnShow", WRAP_SHOW)
      h:WrapScript(b, "OnHide", WRAP_HIDE)
      RegisterUnitWatch(b)
      S.buttons[i] = b
    end
    RegisterStateDriver(h, "fight", "[combat] 1; 0")
    S.header = h
  end)
  if not ok then
    self.failed = tostring(err)
    B:Print("Click to target couldn't start, so the mob list can't be clicked: " .. self.failed)
    return false
  end
  return true
end

---Sizes, settings and when the list shows. Out of combat; in combat it waits for the end of the fight.
function S:Apply()
  if not (B.db and B.db.list.click) and not self.header then return end
  if InCombatLockdown() then
    Core:AfterCombat(function() S:Apply() end, "bulwark-mob-buttons")
    return
  end
  if not self:Build() then return end
  local h, db = self.header, B.db.list
  h:SetWidth(L:Width())
  h:SetAttribute("rowh", db.height)
  h:SetAttribute("top", L.HANDLE_H + 4)
  h:SetAttribute("maxrows", db.rows)
  h:SetAttribute("combatonly", db.combatOnly and true or false)
  for _, b in ipairs(self.buttons) do
    b:SetSize(L:Width() - 8, db.height)
    L:LayoutParts(b.row)
  end
  local show = "hide"
  if self:Active() and not L.preview then show = "show" end
  if self.driver ~= show then
    UnregisterStateDriver(h, "visibility")
    RegisterStateDriver(h, "visibility", show)
    self.driver = show
  end
  self:SetPref(true)
  L:Fade(h, h:GetAttribute("count") or 0)
end

---Out of combat: tell the layout snippet which mobs go first next fight (marked ones, skull first).
function S:SetPref(force)
  local h = self.header
  if not h or InCombatLockdown() then return end
  local marked = {}
  for i = 1, MAX_UNITS do
    local u = "nameplate" .. i
    local mark = plain(UnitExists, u) and plain(GetRaidTargetIndex, u)
    if mark and L.MARK_ORDER[mark] then marked[#marked + 1] = { id = i, order = L.MARK_ORDER[mark] } end
  end
  table.sort(marked, function(a, b) return a.order < b.order end)
  local ids = {}
  for k, m in ipairs(marked) do ids[k] = m.id end
  local pref = table.concat(ids, ",")
  if force or pref ~= h:GetAttribute("pref") then
    h:SetAttribute("pref", pref)
    if h.Execute then h:Execute(RELAYOUT) end
  end
end

---/bulwark clicks: say where a click on a row gets to, to find out why one doesn't target.
function S:Debug()
  self.debug = not self.debug
  if not self.debug then B:Print("Click report off.") return end
  local h, db = self.header, B.db.list
  local lines = {
    ("Click report on: click a row (in combat too); /bulwark clicks again to stop. Click to target: %s. Secure list: %s.")
      :format(db.click and "on" or "off", self.failed and ("failed (" .. self.failed .. ")") or (h and "built" or "not built")),
  }
  if h then
    lines[#lines + 1] = ("Shown: %s. Driver: %s. Rows laid out: %s. In combat now: %s.")
      :format(tostring(h:IsShown()), tostring(self.driver), tostring(h:GetAttribute("count")), tostring(InCombatLockdown()))
  end
  local CB = rawget(_G, "C_ClickBindings")
  if CB and CB.GetBindingType then
    local ok, kind = pcall(CB.GetBindingType, "LeftButton", "")
    local E = rawget(_G, "Enum") and Enum.ClickBindingType
    local name = tostring(kind)
    if ok and E then for k, v in pairs(E) do if v == kind then name = k end end end
    lines[#lines + 1] = "Left click on unit frames is bound to: " .. (ok and name or "?") .. " (Target needs Interaction)."
  end
  for _, l in ipairs(lines) do B:Print(l) end
end

function S:Note(i, what)
  if self.debug then B:Print(("Row %d (nameplate%d): %s."):format(i, i, what)) end
end

function S:Clicked(i, button, down)
  if not self.debug then return end
  local u = "nameplate" .. i
  self:Note(i, ("the game ran the click (%s, %s); the mob %s, you %s attack it"):format(tostring(button),
    down and "down" or "up", plain(UnitExists, u) and "exists" or "doesn't exist",
    plain(UnitCanAttack, "player", u) and "can" or "can't"))
  C_Timer.After(0.1, function()
    local same = plain(UnitIsUnit, "target", u)
    self:Note(i, same == nil and "can't tell whether it's your target now" or (same and "it's your target now" or "your target didn't change to it"))
  end)
end

function S:Hide()
  -- the plain list is showing (preview, or click to target off): Apply's driver already hides ours
end

---Paint the rows the game placed. Any time, combat included: only plain child frames are touched.
function S:Refresh()
  local h = self.header
  if not h then return end
  self:SetPref()
  if not h:IsVisible() then return end
  local target = L:PlateUnit("target")
  for i, b in ipairs(self.buttons) do
    if b:IsVisible() and (b:GetAlpha() or 0) > 0 then
      local u = "nameplate" .. i
      L:Paint(b.row, u)
      b.row:SetTarget(u == target)
      local ok, fighting = Core.Call(UnitAffectingCombat, u)
      b.row:SetAlpha((ok and not IsSecret(fighting) and not fighting) and 0.45 or 1)
    end
  end
  local n = h:GetAttribute("count")
  if type(n) ~= "number" then n = 0 end
  h.count:SetText(n > 0 and tostring(n) or "")
  h.hint:Hide()
  L:Fade(h, n)
end

Core:OnLogin(function()
  if not B.db then return end
  S:Apply()
end)
