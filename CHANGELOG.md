# Changelog

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
