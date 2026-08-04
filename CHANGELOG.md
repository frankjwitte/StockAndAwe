# Changelog

## 0.2.2

- Triggered the newly configured CurseForge packaging webhook. The machinery has been formally introduced to the button.

## 0.2.1

- Reissued the 0.2.0 compatibility release so the automated packager can do its job. Apparently tags require supervision too.

## 0.2.0

- Added support for interface versions 120005, 50504, 38000, 20506, and 11508. Stocking up is now a cross-era obligation.

## 0.1.0

- Added automatic vendor restocking for class reagents, because running out mid-buff is beneath you.
- Added default stock rules for druids, mages, paladins, priests, rogues, shamans, and warlocks.
- Added `/saa` and `/stockandawe` commands for status, toggles, dry-run mode, and per-class rule edits.
- Priests stock Sacred Candles only. Holy Candles have been honorably retired.
- Shamans stock Ankh only. Shiny Fish Scales and Fish Oil are drops, not vendor stock.
- Added individual reagent toggles through `/saa reagent <itemID>`.
- Added optional Titan Panel integration with live reagent counts, options, and reagent controls.
- Pace merchant purchases using merchant and bag updates to avoid duplicate buys.
- Use an exact final merchant purchase after full merchant-safe chunks to reach the target.
- Added a compact stack-target options panel available through `/saa options` and Titan Panel.
