# Guildhall Exporter

WoW: Forever addon for **The Desperado Club**. Reads profession/recipe data
that [Guildhall](https://github.com/vBaustad/Guildhall) has already scanned
and synced across the guild, and formats it into a JSON blob you can paste
into the guild website's crafting-database importer.

This addon does **no scanning or syncing of its own** — it requires
[Guildhall](https://www.curseforge.com/wow/addons/guildhall) to be installed
and logged in at least once. All the "who knows what recipe" heavy lifting is
Guildhall's job; this addon just reads its tables and prints them.

## Usage

1. Install and use [Guildhall](https://www.curseforge.com/wow/addons/guildhall)
   normally (it syncs profession data with the guild automatically).
2. Type `/ghe` (mirrors Guildhall's own `/gh` command style).
3. Click **Generate**. The export is selected automatically — press Ctrl+C.
4. Paste into the Desperado Club website's crafting import tool.

If you're not in a guild yet, or Guildhall hasn't synced with anyone, the
export still includes your own characters' known recipes.

## Export format

```json
{
  "schema": "GUILDHALL_EXPORTER_V1",
  "guild": "The Desperado Club-Emberstorm",
  "generatedBy": "Bob-Emberstorm",
  "generatedAt": 1758000000,
  "characters": {
    "Bob-Emberstorm": {
      "class": "WARRIOR",
      "level": 60,
      "rev": 4821,
      "professions": {
        "164": { "rank": 300, "max": 300, "recipes": [3275, 3276] }
      }
    }
  }
}
```

Profession keys are Guildhall's skill line IDs, recipe values are recipe spell
IDs. Names/icons/reagents/crafted items are intentionally not duplicated here
— the website resolves those from its own recipe catalog (built from
Guildhall's bundled `Data/Recipes.lua`, or an independent source such as
[forever-ref](https://github.com/alcaras/forever-ref)).

## Testing the export logic without the game

`test/test_export.lua` mocks a fake `Guildhall` table and exercises
`GuildhallExporter.BuildExportJSON()` directly:

```bash
cd test
lua test_export.lua
```

This only checks the JSON-building logic. The UI (`/ghe` window) can only be
verified in-game.
