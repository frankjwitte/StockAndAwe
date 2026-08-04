# Stock And Awe

> Because arriving without your buff reagents is a bold way to meet new people.

Stock And Awe is a small World of Warcraft Classic Era / Anniversary addon that restocks your class reagents whenever you open a vendor that sells them. It buys enough to hit your target and leaves you free to concentrate on the important things, such as pretending this was the plan all along.

## Behavior

- Restocks only the current character's class reagents. We respect your alts' right to make their own mistakes.
- Uses stack targets, not raw item counts.
- Buys full vendor-safe chunks, then uses one exact final purchase to reach the target.
- Counts items in your bags, not your bank or mail.
- Buys only from the currently open merchant. No mysterious mail-order service, sadly.
- Skips merchant items with extended costs, because that is a conversation for your wallet.
- Prints what it bought unless chat messages are disabled.

## Default Targets

- Druid: one stack each of Wild Thornroot and Rebirth seeds through Ironwood Seed.
- Mage: one stack each of Rune of Teleportation and Rune of Portals.
- Paladin: one stack each of Symbol of Divinity and Symbol of Kings.
- Priest: three stacks of Sacred Candle. Holy Candle can stay in the past where it belongs.
- Rogue: one stack of Flash Powder.
- Shaman: one stack of Ankh. Fish scales and oil come from creatures, not vendors, and therefore are not our problem.
- Warlock: one stack each of Demonic Figurine and Infernal Stone.

## Commands

```text
/saa
/saa on
/saa off
/saa buy
/saa dryrun
/saa quiet
/saa chat
/saa item <itemID> <stacks>
/saa reagent <itemID>
/saa options
/saa remove <itemID>
/saa reset
```

Use `/saa dryrun` to see what it would buy before spending a single copper. For the cautious, the broke, and anyone who has been both.

Use `/saa reagent <itemID>` to toggle a configured reagent without deleting its target. Use `/saa item <itemID> <stacks>` to add or update one of the supported vendor reagents, such as Holy Candle for a lower-level priest. It is capable, not psychic, and it does not visit the Auction House.

Use `/saa options` for the small stack-target panel. It lists the configured reagents for your current class and lets you set their desired number of stacks without typing item IDs like it is 2006.

## Titan Panel

When Titan Panel is installed, Stock And Awe adds an optional panel button. The button shows whether automatic buying is on; hover it for live bag and target counts. Left-click toggles automatic buying, and right-click opens controls for dry-run mode, restocking now, options, resetting rules, and enabling or disabling individual reagents. No Titan Panel, no problem. The addon carries on quietly.

## Installation

Extract the release so that the addon files are in one of these folders:

```text
World of Warcraft\_classic_era_\Interface\AddOns\StockAndAwe
World of Warcraft\_anniversary_\Interface\AddOns\StockAndAwe
```

Enable it from the character select addon list, then reload WoW or type `/reload`.

The `.toc` supports interface versions `120005`, `50504`, `38000`, `20506`, and `11508`. If your client marks the addon out of date after a patch, update the `## Interface` value in `StockAndAwe.toc` or enable out-of-date addons.

## Contributing

Bug reports, suggestions, and praise are welcome. Open an issue or submit a pull request, but remember: this addon is held together by Lua, vendor menus, and a profound distrust of running out of candles.

## License

MIT - Do whatever, just do not claim you wrote it unless you are one of my alts. The full license text is in `LICENSE`.
