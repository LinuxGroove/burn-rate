#!/usr/bin/env python3
"""Copies the pieces of Quaternius' Downtown City MegaKit that Burn Rate uses
into addons/quaternius/downtowncity/, from the kit's Source tier Godot
project (`Downtown City MegaKit[Source]/Engine Projects/Godot.zip` in
https://github.com/LinuxGroove/quaternius-assets, a Git LFS file):

    python3 tools/vendor_downtowncity.py /path/to/unzipped/Godot

- Meshes/: the models in MODELS, with the kit's collision nodes (the
  `-colonly` and `-convcolonly` ones, thousands per building) and their
  meshes taken out of the glTF and its buffer, and the texture references
  dropped (the import script gives every surface the kit's own material).
- materials/: the kit's materials those models use, the base shader, and
  the textures they need, scaled to 1024 pixels (the city is seen at night
  and from a distance). The fake window interiors use the game's own
  version of the kit's interior shader (M_FakeInterior.gdshader, written
  by hand from the kit's visual shader), which picks lit and dark rooms per
  window instead of per model, so one model or MultiMesh has both.
- city_import_script.gd: the kit's import script, looking in this folder.

The kit is CC0 (Downtown_City_MegaKit_License.txt).
"""
import json
import os
import re
import shutil
import struct
import sys

from PIL import Image

MAX_TEX = 1024
MODELS = [
    # The skyline.
    "Building_Large_1", "Building_Large_2", "Building_Large_3", "Building_Medium_1", "Building_Medium_2",
    "Building_Small_1", "Building_Small_2",
    # Rooftops.
    "Prop_ACUnit", "Roof_4x4", "Prop_FireEscape_Top", "Prop_FireEscape_Center", "Prop_Planter_Single",
    "Cornice_Brick_Center", "Cornice_Metal_Center", "Cornice_WornBrick_Center", "Cornice_Marble_Center",
    "Cornice_WhiteBrick_Center", "Cornice_Trim_Center",
    # Walls with windows, for the buildings beside the roofs.
    "Metal_Window", "Brick_Inset_Window", "WornBrick_WindowTriple", "Marble_Window", "WhiteBrick_Window",
    # Signs.
    "Prop_Sign_JadeGarden", "Prop_Sign_JadeGarden_Vertical", "Prop_Sign_Carmines", "Prop_Sign_Deli", "Prop_Sign_Mays",
    "Prop_Sign_Bakery", "Prop_Sign_Hannigan",
]
COLLISION = re.compile(r"-(conv)?colonly$|-col$")
COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def strip_gltf(src: str, dst_dir: str) -> set:
    """Writes the model without collision or textures; returns its material names."""
    g = json.load(open(src))
    data = open(os.path.join(os.path.dirname(src), g["buffers"][0]["uri"]), "rb").read()
    keep_nodes = [i for i, n in enumerate(g["nodes"]) if not COLLISION.search(n.get("name", ""))]
    remap_node = {old: new for new, old in enumerate(keep_nodes)}
    nodes = []
    for i in keep_nodes:
        n = dict(g["nodes"][i])
        if "children" in n:
            n["children"] = [remap_node[c] for c in n["children"] if c in remap_node]
            if not n["children"]:
                del n["children"]
        nodes.append(n)
    # Meshes still used.
    used_meshes = sorted({n["mesh"] for n in nodes if "mesh" in n})
    remap_mesh = {old: new for new, old in enumerate(used_meshes)}
    for n in nodes:
        if "mesh" in n:
            n["mesh"] = remap_mesh[n["mesh"]]
    meshes = [g["meshes"][i] for i in used_meshes]
    # Materials still used, without textures.
    used_mats = sorted({p["material"] for m in meshes for p in m["primitives"] if "material" in p})
    remap_mat = {old: new for new, old in enumerate(used_mats)}
    materials = [{"name": g["materials"][i]["name"], "doubleSided": g["materials"][i].get("doubleSided", False)} for i in used_mats]
    # Accessors still used, copied into a new buffer.
    out = bytearray()
    views, accessors, remap_acc = [], [], {}

    def take(a: int) -> int:
        if a in remap_acc:
            return remap_acc[a]
        acc = dict(g["accessors"][a])
        view = g["bufferViews"][acc["bufferView"]]
        size = COMPONENT_SIZE[acc["componentType"]] * TYPE_COUNT[acc["type"]]
        stride = view.get("byteStride", size)
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        chunk = b"".join(data[start + k * stride:start + k * stride + size] for k in range(acc["count"])) if stride != size else data[start:start + size * acc["count"]]
        while len(out) % 4:
            out.append(0)
        nv = {"buffer": 0, "byteOffset": len(out), "byteLength": len(chunk)}
        if "target" in view:
            nv["target"] = view["target"]
        out.extend(chunk)
        views.append(nv)
        acc["bufferView"] = len(views) - 1
        acc.pop("byteOffset", None)
        accessors.append(acc)
        remap_acc[a] = len(accessors) - 1
        return remap_acc[a]

    for m in meshes:
        for p in m["primitives"]:
            p["attributes"] = {k: take(v) for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = take(p["indices"])
            if "material" in p:
                p["material"] = remap_mat[p["material"]]
    name = os.path.splitext(os.path.basename(src))[0]
    roots = [remap_node[i] for i in g["scenes"][g.get("scene", 0)]["nodes"] if i in remap_node]
    out_g = {
        "asset": g["asset"], "scene": 0, "scenes": [{"name": g["scenes"][0].get("name", "Scene"), "nodes": roots}],
        "nodes": nodes, "meshes": meshes, "materials": materials, "accessors": accessors, "bufferViews": views,
        "buffers": [{"byteLength": len(out), "uri": name + ".bin"}],
    }
    json.dump(out_g, open(os.path.join(dst_dir, name + ".gltf"), "w"), separators=(",", ":"))
    open(os.path.join(dst_dir, name + ".bin"), "wb").write(bytes(out))
    open(os.path.join(dst_dir, name + ".gltf.import"), "w").write(IMPORT)
    return {m["name"] for m in materials}


IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=false
meshes/light_baking=0
import_script/path="res://addons/quaternius/downtowncity/city_import_script.gd"
"""


def main(src: str, dst: str) -> None:
    kit = os.path.join(src, "addons/quaternius")
    out = os.path.join(dst, "addons/quaternius/downtowncity")
    keep = {}
    if os.path.isdir(os.path.join(out, "Meshes")):
        shutil.rmtree(os.path.join(out, "Meshes"))
    os.makedirs(os.path.join(out, "Meshes"))
    os.makedirs(os.path.join(out, "materials"), exist_ok=True)
    # The game's own shaders (M_FakeInterior, M_Glass) stay; the kit's files go.
    for f in os.listdir(os.path.join(out, "materials")):
        if f.endswith((".tres", ".png", ".import")) or f == "M_BaseMaterial.gdshader":
            os.remove(os.path.join(out, "materials", f))
    mats = set()
    for m in MODELS:
        mats |= strip_gltf(os.path.join(kit, "downtowncitymegakit/Meshes", m + ".gltf"), os.path.join(out, "Meshes"))
    mats.discard("Collision")
    # The materials, pointed at this folder, and the textures they use.
    textures = set()
    mdir = os.path.join(kit, "materials")
    for name in sorted(mats):
        p = os.path.join(mdir, name + ".tres")
        if not os.path.exists(p):
            print("no material", name)
            continue
        text = open(p).read()
        if name.startswith("MI_FakeInterior"):
            # The game's own interior shader in place of the kit's visual shader.
            text = re.sub(r'\[ext_resource type="Shader"[^\]]*\]',
                          '[ext_resource type="Shader" path="res://addons/quaternius/downtowncity/materials/M_FakeInterior.gdshader" id="1_shader"]', text)
            text = re.sub(r'shader = ExtResource\("[^"]+"\)', 'shader = ExtResource("1_shader")', text)
        if name == "MI_Glass":
            text = re.sub(r'\[ext_resource type="Shader"[^\]]*\]',
                          '[ext_resource type="Shader" path="res://addons/quaternius/downtowncity/materials/M_Glass.gdshader" id="1_shader"]', text)
            text = re.sub(r'shader = ExtResource\("[^"]+"\)', 'shader = ExtResource("1_shader")', text)
        text = text.replace("res://addons/quaternius/materials/", "res://addons/quaternius/downtowncity/materials/")
        # Paths only: the kit's UIDs belong to its own project.
        text = re.sub(r'(\[ext_resource[^\]]*?) uid="uid://[^"]*"', r"\1", text)
        textures |= set(re.findall(r'downtowncity/materials/(T_[^"]+\.png)', text))
        open(os.path.join(out, "materials", name + ".tres"), "w").write(text)
    shutil.copy2(os.path.join(mdir, "M_BaseMaterial.gdshader"), os.path.join(out, "materials"))
    for t in sorted(textures):
        s = os.path.join(mdir, t)
        d = os.path.join(out, "materials", t)
        im = Image.open(s)
        if max(im.size) > MAX_TEX:
            im = im.resize((MAX_TEX, MAX_TEX), Image.LANCZOS)
            im.save(d, optimize=True)
        else:
            shutil.copy2(s, d)
        imp = open(s + ".import").read()
        imp = imp.replace("res://addons/quaternius/materials/", "res://addons/quaternius/downtowncity/materials/")
        # Godot fills in the imported paths again.
        imp = re.sub(r'^(path[^=]*|dest_files)=.*\n', "", imp, flags=re.M)
        open(d + ".import", "w").write(imp)
    script = open(os.path.join(kit, "quaternius_import_script.gd")).read()
    script = script.replace('"res://addons/quaternius/materials/"', '"res://addons/quaternius/downtowncity/materials/"')
    open(os.path.join(out, "city_import_script.gd"), "w").write(script)
    print(len(MODELS), "models,", len(mats), "materials,", len(textures), "textures")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
