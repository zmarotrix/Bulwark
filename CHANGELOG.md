# Changelog

## 0.7.6, 2026-11-08

- Click to target, still being worked out: the 0.7.5 log showed every click reaching the row and the game running its
  "target" action, but the target not changing. Right click now targets through a `/target nameplateN` macro instead,
  and the click log notes whether the mob was already your target before each click, so the next fight shows which
  route the game honours.

## 0.7.5, 2026-11-08

- Clicking a mob-list row should now target the mob. The rows were the game's unit-frame buttons, whose click first
  checks your click bindings and silently drops a "target" click when left click isn't bound there. They're now
  action buttons, which target directly.
- Every row click is kept in Bulwark's saved settings (the last 30), so a click that still doesn't target can be looked
  at after a /reload.

## 0.7.4, 2026-11-08

- A mob tagged by someone outside your group isn't your fight: its plate keeps Blizzard's tapped grey, with no flash
  and no threat %. In the mob list its bar is grey too.

## 0.7.4, 2026-11-08

- The minimap list shows Bulwark's role, "Aggro management", and says "Off" only when it's turned off.

## 0.7.3, 2026-11-07

- The mob list's bars use the plate colours toned down to 60%, so a column of them doesn't shout over the screen; the
  nameplates themselves stay vivid.
- **Raid mark size** slider for the mark at the left of each row (default 20 px).
- `/bulwark clicks` reports what happens to a click on a row: whether the mouse reached it, whether the game ran the
  click, and whether your target changed. Clicking a row didn't target in the first test in game; this finds out why.

## 0.7.2, 2026-11-07

- The mob list tracks **Lacerate** (15 seconds). Debuffs that stack (Lacerate, Sunder Armor) count up with each cast, to
  5, shown in gold in the corner of the icon; a stack that ran out starts again at 1. Out of combat the real count is
  read from the mob.

## 0.7.1, 2026-11-07

- The list's handle (the Bulwark mark and name) now shows all the time while the list is on, dimmed when there are no
  mobs, so you can move it whenever you like. "Only mobs in combat" now empties the rows instead of hiding the list.
- The list hangs from its top-left corner wherever you drop it, so rows come and go below a title that stays put. A
  position saved by 0.7.0 is turned into the top-left one.

## 0.7.0, 2026-11-07

- **Click a row to target that mob, in combat too.** The rows are the game's own secure unit buttons, and the game lays
  them out itself during a fight: mobs you can attack, in the order they appeared, with mobs marked before the pull
  first (skull at the top). A mob not in the fight yet shows dimmed. Hovering a row shows the mob's tooltip. Turning
  "Click a row to target it" off brings back the freely sorted list that can't be clicked.
- **The suite's look**: on top, a handle with the Bulwark mark and name that you drag to move the list; below it the rows,
  each a dark well with a 1px edge (gold on your target, soft gold under the mouse), the suite's fonts, and your DoTs as
  framed icons that edge in red in their last 3 seconds.
- **Background** slider: the stone-and-gold panel behind the rows, from 0 (the default: just the handle and the bars) to
  100%.

## 0.6.0, 2026-11-07

- **The mob list**, Bulwark's take on Cursive: a small window with every enemy in the fight. Each row has the raid mark,
  the mob's name and health %, a health bar in the plate colour for who it's on (and the flash's glow when you're about to
  lose it), and your own DoTs and debuffs on it with the seconds left, soonest to run out first.
- Marked mobs first (skull, cross, circle, ...), then in the order they joined the fight. Your target has a white edge and
  always keeps a row.
- The timers come from your casts on your target, since the game hides auras from add-ons in combat. Out of combat
  Bulwark reads the real timers and learns how long each of your spells lasts, so talents and ranks come right.
- Settings: on or off, only mobs in combat, DoTs on or off, how many rows, bar width, row height, lock, and a Preview
  with sample mobs to place it. `/bulwark list` shows the preview too.

## 0.5.0, 2026-11-07

- Built on NorgannonDB Core 1.20's `Core:NewAddon`: the same commands, settings and minimap row, with a quarter of the
  setup code.
- The minimap row and the add-on menu now work like every suite add-on's: a click opens settings, and right-click does
  too. Turning Bulwark on or off moved to **Shift-click**, so a habit from another add-on can't switch it off.
- The "Show the minimap button" setting is gone: NorgannonDB > Minimap pins any add-on.
- `/bulwark help` lists every command.

## 0.4.0, 2026-11-07

- **Colour schemes:** Default, red-green colour blind (protanopia, deuteranopia), blue-yellow colour blind (tritanopia)
  and high contrast. The colour-blind ones use the Okabe-Ito palette. Changing any colour yourself makes the scheme
  "Your own".
- Cleaner colour rows: the colour is a framed swatch you click to change it, with room around it. Reset sits beside it
  and only shows once that colour differs from the scheme.
- The threat % colours (getting close, at the flash line) can be changed too, and follow the scheme.

## 0.3.0, 2026-11-07

- **Threat % on each plate**, in combat: tanking a mob, how close the next person is to pulling it off you ("72%");
  otherwise, how close you are to pulling it. White while safe, yellow 20 points before the flash line, red at it.
  Hidden when you're alone and holding the mob. Text size and place (inside the bar or below it) are in settings.

## 0.2.0, 2026-11-07

- Bulwark is now a combat and aggro toolkit, and has its own mark (a shield with two chevrons) and colour, dark blue. It's
  in the suite's list, the game's add-on menu, and on a minimap button (click: settings, right-click: on or off).
- **Bigger raid marks:** our own mark, 34px by default, above the name, with a soft dark disc behind it, in place of
  Blizzard's small one. Size, place (above the name or left of the bar) and the disc are in settings.

## 0.1.0, 2026-11-07

- First version. Blizzard's health bar on each enemy nameplate is coloured by who the mob is on: green on you, red on
  someone who isn't a tank, cyan on another tank, grey on nobody. Mobs out of combat keep Blizzard's colour.
- The bar flashes when you're about to lose the mob: someone is above you on threat, or within 90% of pulling it.
- Not-tanking mode swaps green and red, and flashes when you're about to pull the mob off the tank. Auto picks the mode
  from your role, your stance or form, and whether you're in a group.
- A tank is someone with the Tank role or main tank, a druid in bear form, a warrior in Defensive Stance, a paladin with
  Righteous Fury, or your own pet.
- Settings under NorgannonDB in the game's Settings, or /bulwark.
