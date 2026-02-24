# RepSync - Development Guide

## Project Overview

**RepSync** is a WoW Classic Anniversary addon that automatically switches the player's watched reputation bar when entering dungeons, raids, capital cities, and faction sub-zones.

### Key Files
- `RepSync.lua` - Main addon code (all logic in single file, ~1100 lines)
- `RepSync.toc` - Addon manifest
- `README.md` - Documentation (also used for CurseForge description)
- Deployed to: `/mnt/data/games/World of Warcraft/_anniversary_/Interface/AddOns/RepSync/`

### Features
- Auto-detects instance entry via `GetInstanceInfo()` (dungeons, raids, and battlegrounds)
- Auto-detects capital cities via `C_Map.GetBestMapForUnit("player")` (numeric uiMapIDs, locale-independent)
- Auto-detects faction sub-zones via `GetSubZoneText()` with full localization (10 WoW client languages)
- Maps instances, cities, sub-zones, and battlegrounds to their associated reputation faction
- Handles faction-specific reps (Honor Hold vs Thrallmar, Kurenai vs Mag'har, Stormpike Guard vs Frostwolf Clan) via `UnitFactionGroup()`
- Saves and restores previously watched reputation on exit (preserves original across multi-zone transitions)
- Expand/collapse-safe faction index lookup (expands headers, finds faction, re-collapses)
- Skip checks (Hostile, Exalted, Ignored) run inside expanded scan for reliability
- Debounce logic to avoid redundant switches
- Native Blizzard Settings API options panel (Options > AddOns > RepSync)
- Skip exalted factions toggle
- Faction ignore list with GUI checkboxes in options panel (also manageable via slash commands)
- Zone-text style screen alerts with draggable positioning
- Chat message toggle
- SavedVariables: `RepSyncDB` (per-character)

### Architecture
- Single Lua file with no XML dependencies
- Event-driven: PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA, ZONE_CHANGED
- Priority system: instances > sub-zones > cities
- `FindAndWatchFactionByID()` handles the expand-all → find → set → re-collapse dance
- `GetFactionIDFromEntry()` resolves faction-split entries based on player faction
- `INSTANCE_FACTION_MAP` flat table keyed by instanceID (8th return of `GetInstanceInfo()`) — includes dungeons, raids, and battlegrounds
- `CITY_FACTION_MAP` flat table keyed by uiMapID (Classic Anniversary IDs: 1453-1458, 1947, 1954)
- `SUBZONE_FACTION_MAP` built at load time from `SUBZONE_LOCALE_DATA` (all locale names → factionID)
- `C_Reputation.GetWatchedFactionData()` to check current watched faction

### Slash Commands
- `/rs` - Open native options panel (Options > AddOns > RepSync)
- `/rs clear` - Clear saved previous faction
- `/rs list` - List all mapped locations in chat
- `/rs ignore <name>` - Add faction to ignore list
- `/rs unignore <name>` - Remove faction from ignore list
- `/rs ignorelist` - Show ignored factions
- `/rs help` - Show commands

### Development Workflow

See the `/wow-addon` skill for the standard development workflow (test, version, commit, deploy).

### Important Notes
- Classic Anniversary uiMapIDs differ from retail (e.g., Stormwind = 1453, not 84)
- Sub-zone translations sourced from LibBabble-SubZone-3.0
- Faction-specific sub-zones (Telaar/Garadar) silently fail for the wrong faction

## WoW API Reference

For WoW Classic Anniversary API documentation, patterns, and development workflow, use the `/wow-addon` skill:
```
/wow-addon
```
This loads the shared TBC API reference, common patterns, and gotchas.
