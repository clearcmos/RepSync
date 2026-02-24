# Changelog

## [1.0.3] - 2026-02-24

### Added
- Battleground reputation switching: Alterac Valley, Warsong Gulch, Arathi Basin (faction-aware)
- Ignored Factions section in options panel with per-faction checkboxes

### Changed
- Skip checks (Hostile, Exalted, Ignored) now run inside the expanded faction scan for reliability

### Removed
- Unused localized variables (`tinsert`, `GetFactionInfoByID`)

## [1.0.2] - 2026-02-21

### Changed
- Options panel now uses native Blizzard Settings API (Options > AddOns > RepSync)
- `/rs` opens the native settings panel instead of a custom floating window
- Alert demo preview renders above the settings panel for easy repositioning

### Removed
- Custom floating options dialog (replaced by native integration)

## [1.0.1] - 2026-02-18

### Added
- Capital city reputation switching (Stormwind, Ironforge, Darnassus, Exodar, Orgrimmar, Thunder Bluff, Undercity, Silvermoon City)
- Sub-zone reputation switching with full localization support (all 10 WoW client languages)
- Aldor Rise → The Aldor, Scryer's Tier → The Scryers
- Tinker Town → Gnomeregan Exiles, Valley of Spirits → Darkspear Trolls
- Steamwheedle Cartel towns: Booty Bay, Everlook, Gadgetzan, Ratchet
- TBC sub-zones: Sporeggar, Telaar → Kurenai (Alliance), Garadar → The Mag'har (Horde)
- Cenarion Hold → Cenarion Circle, Light's Hope Chapel → Argent Dawn
- New "Switch in cities & sub-zones" toggle in the options panel
- ZONE_CHANGED event handling for sub-zone transitions

### Changed
- Reputation restore now preserves original rep across multiple mapped location transitions

## [1.0.0] - 2026-02-11

### Added
- Auto-switch watched reputation when entering mapped dungeons and raids
- Faction-specific reputation handling (Alliance/Horde)
- Automatic restoration of previous reputation on instance exit
- TBC dungeon and raid mappings (Hellfire Citadel, Coilfang Reservoir, Auchindoun, Tempest Keep, Caverns of Time, Magister's Terrace, Karazhan, Hyjal Summit, Black Temple)
- Vanilla dungeon and raid mappings (Stratholme, Scholomance, BRD, Dire Maul, Molten Core, AQ20, AQ40, ZG, Naxxramas)
- GUI options panel with settings, live status, and scrollable instance list
- Slash commands: `/rs`, `/repsync`
- Per-character saved variables
