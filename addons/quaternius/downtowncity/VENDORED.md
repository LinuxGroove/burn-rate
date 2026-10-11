# Downtown City MegaKit (vendored)

Quaternius' Downtown City MegaKit, Source tier, CC0 (see `Downtown_City_MegaKit_License.txt`). It comes from the kit's Godot project, `Downtown City MegaKit[Source]/Engine Projects/Godot.zip` in [LinuxGroove/quaternius-assets](https://github.com/LinuxGroove/quaternius-assets) (a Git LFS file). `tools/vendor_downtowncity.py` copies it here:

    python3 tools/vendor_downtowncity.py /path/to/unzipped/Godot .

Only the pieces Burn Rate uses are here (`MODELS` in the script): the seven buildings of the skyline, roofs, AC units, fire escapes, planters, cornices, walls with windows and the shop signs. `Kit` finds them by name with the `city:` prefix (`city:Building_Large_1`).

## What's changed from the kit

- **Meshes/**: each glTF loses the kit's collision nodes (the `-colonly` and `-convcolonly` ones, thousands in each building) and their meshes, and its texture references; the buffer is written again with only what's left. The imports make no shadow meshes and no lightmap UVs, and do make LODs. `city_import_script.gd` is the kit's import script, looking in this folder for the materials.
- **materials/**: only the materials those models use, with their paths moved to this folder and the kit's UIDs taken out. Textures are at most 1024 pixels (the kit's are up to 2048): the city is seen at night and from a distance.
- **M_FakeInterior.gdshader** replaces the kit's fake interior visual shader with one written by hand from it. Each window picks a lit or dark room, a tint and curtains from its own place in the world, so one model (or one MultiMesh of many) shows both lit and dark windows. Lit rooms glow (`EMISSION`); the game turns them down for the Calm background setting through the `city_lights` uniform.
- **M_Glass.gdshader** is the kit's glass, more see-through.
- `M_BaseMaterial.gdshader` is the kit's own, unchanged.
