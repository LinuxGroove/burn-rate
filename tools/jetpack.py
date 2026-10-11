"""Builds Burn Rate's prototype jetpack in Blender from the Modular Sci-Fi MegaKit's trim sheets.

Run: blender-venv/bin/python jetpack.py <kit textures dir> <out dir>
Writes jetpack.blend, jetpack.glb and gltf/jetpack.gltf (textures referenced by the kit's file names).
Axes: Blender +Z is up and the pack sits behind the wearer along -Y, which is +Z in Godot and glTF.
The origin is where the back plate touches the wearer's back, level with the shoulder blades.
"""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

TEX, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# ---------- materials ----------
def image(name, data=False):
    im = bpy.data.images.load(os.path.join(TEX, name), check_existing=True)
    if data:
        im.colorspace_settings.name = 'Non-Color'
    return im


def trim(name, base, normal, orm):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes['Principled BSDF']
    tb = nt.nodes.new('ShaderNodeTexImage'); tb.image = image(base)
    nt.links.new(tb.outputs['Color'], bsdf.inputs['Base Color'])
    to = nt.nodes.new('ShaderNodeTexImage'); to.image = image(orm, True)
    sep = nt.nodes.new('ShaderNodeSeparateColor')
    nt.links.new(to.outputs['Color'], sep.inputs['Color'])
    nt.links.new(sep.outputs['Green'], bsdf.inputs['Roughness'])
    nt.links.new(sep.outputs['Blue'], bsdf.inputs['Metallic'])
    tn = nt.nodes.new('ShaderNodeTexImage'); tn.image = image(normal, True)
    nm = nt.nodes.new('ShaderNodeNormalMap')
    nt.links.new(tn.outputs['Color'], nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    return m


def flat(name, color, rough=0.5, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if emit:
        b.inputs['Emission Color'].default_value = (*emit, 1)
        b.inputs['Emission Strength'].default_value = strength
    return m


M_TANK = trim('MI_Trim_02_Red', 'T_Trim_02_BaseColor_Red.png', 'T_Trim_02_Normal.png', 'T_Trim_02_ORM.png')
M_PLATE = trim('MI_Trim_01', 'T_Trim_01_BaseColor.png', 'T_Trim_01_Normal.png', 'T_Trim_01_ORM.png')
M_DARK = trim('MI_Trim_03_Dark', 'T_Trim_03_Cables.png', 'T_Trim_03_Normal.png', 'T_Trim_03_ORM.png')
M_GLOW = flat('M_Jet_Glow', (1.0, 0.45, 0.1), emit=(1.0, 0.42, 0.08), strength=4.0)
M_STRAP = flat('M_Jet_Strap', (0.03, 0.032, 0.035), rough=0.8)


# ---------- UVs on the trim sheets ----------
# Regions are (u0, v0, u1, v1) in image space (v down), as read off the textures.
def to_uv(u0, v0, u1, v1, a, b):
    return Vector((u0 + a * (u1 - u0), 1.0 - (v0 + b * (v1 - v0))))


def box_uv(bm, regions):
    """Fit each face group (by dominant axis) into its trim region."""
    uv = bm.loops.layers.uv.verify()
    lo = Vector([min(v.co[i] for v in bm.verts) for i in range(3)])
    hi = Vector([max(v.co[i] for v in bm.verts) for i in range(3)])
    span = hi - lo
    span = Vector([s if s > 1e-6 else 1 for s in span])
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        r = regions['xyz'[ax]]
        for l in f.loops:
            c = (l.vert.co - lo)
            if ax == 0:
                a, b = c.y / span.y, 1 - c.z / span.z
            elif ax == 1:
                a, b = c.x / span.x, 1 - c.z / span.z
            else:
                a, b = c.y / span.y, c.x / span.x
            l[uv].uv = to_uv(*r, a, b)


def tube_uv(bm, side, cap=None):
    """Cylinder along Y: wrap `side` round it, map `cap` onto the ends."""
    uv = bm.loops.layers.uv.verify()
    ys = [v.co.y for v in bm.verts]
    y0, y1 = min(ys), max(ys)
    rmax = max(math.hypot(v.co.x, v.co.z) for v in bm.verts) or 1
    for f in bm.faces:
        if abs(f.normal.y) > 0.9:
            r = cap or side
            for l in f.loops:
                l[uv].uv = to_uv(*r, 0.5 + 0.5 * l.vert.co.x / rmax, 0.5 - 0.5 * l.vert.co.z / rmax)
            continue
        angs = [math.atan2(l.vert.co.z, l.vert.co.x) for l in f.loops]
        ref = angs[0]
        for l, a in zip(f.loops, angs):
            if a - ref > math.pi: a -= 2 * math.pi
            if ref - a > math.pi: a += 2 * math.pi
            l[uv].uv = to_uv(*side, (a + math.pi) / (2 * math.pi), (l.vert.co.y - y0) / max(y1 - y0, 1e-6))


# ---------- parts ----------
parts = []


def finish(name, bm, mat, loc=(0, 0, 0), rot=(0, 0, 0), smooth=0.6):
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if e.is_manifold and e.calc_face_angle(0) > smooth:
            e.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = [math.radians(a) for a in rot]
    scene.collection.objects.link(ob)
    parts.append(ob)
    return ob


def box(name, size, loc, mat, regions, bevel=0.008, segs=3, rot=(0, 0, 0), taper=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if taper:  # shrink the front (+Y) face: (x scale, z scale, z shift)
        front = [v for v in bm.verts if v.co.y > 0]
        for v in front:
            v.co.x *= taper[0]
            v.co.z = v.co.z * taper[1] + taper[2]
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=segs, affect='EDGES', profile=0.5, clamp_overlap=True)
    bm.normal_update()
    box_uv(bm, regions)
    return finish(name, bm, mat, loc, rot)


def tube(name, r1, r2, length, loc, mat, side, cap=None, segs=40, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=length)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, 'X'))
    if bevel:
        rims = [e for e in bm.edges if len(e.link_faces) == 2 and abs(e.link_faces[0].normal.y - e.link_faces[1].normal.y) > 0.5]
        bmesh.ops.bevel(bm, geom=rims, offset=bevel, segments=2, affect='EDGES', profile=0.5, clamp_overlap=True)
    bm.normal_update()
    tube_uv(bm, side, cap)
    return finish(name, bm, mat, loc)


def ring(name, major, minor, y, mat):
    bm = bmesh.new()
    segs, sides = 48, 12
    verts = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        row = []
        for j in range(sides):
            b = 2 * math.pi * j / sides
            rr = major + minor * math.cos(b)
            row.append(bm.verts.new((rr * math.cos(a), minor * math.sin(b), rr * math.sin(a))))
        verts.append(row)
    for i in range(segs):
        for j in range(sides):
            bm.faces.new((verts[i][j], verts[(i + 1) % segs][j], verts[(i + 1) % segs][(j + 1) % sides], verts[i][(j + 1) % sides]))
    bm.normal_update()
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for l in f.loops:
            l[uv].uv = (0.5, 0.5)
    return finish(name, bm, mat, (0, y, 0), smooth=3.0)



# Trim regions (image space).
SIDE_GREEBLE = (0.0, 0.605, 0.62, 0.80)     # buttons, grille, round hatch, amber light
PLAIN = (0.04, 0.28, 0.40, 0.58)             # plain panel with a seam
BRACKETS = (0.18, 0.035, 0.92, 0.245)        # panel strip with brackets
HAZARD = (0.012, 0.792, 0.27, 0.822)         # red and grey hazard stripes
RIVETS = (0.0, 0.43, 1.0, 0.47)              # Trim_01 riveted band
TRIANGLES = (0.0, 0.335, 1.0, 0.37)          # Trim_01 triangle band
HATCH = (0.525, 0.715, 0.635, 0.825)         # round hatch, for end caps
X_PANEL = (0.79, 0.62, 0.995, 0.85)          # Trim_02 X-braced panel
DARK = (0.1, 0.1, 0.6, 0.6)


# ---------- parts ----------
# The back plate, against the wearer's back.
plate = box('Plate', (0.34, 0.05, 0.5), (0, -0.03, -0.02), M_PLATE, {'x': BRACKETS, 'y': PLAIN, 'z': BRACKETS}, bevel=0.012)
box('PlateRim', (0.3, 0.02, 0.44), (0, -0.065, -0.02), M_DARK, {'x': DARK, 'y': DARK, 'z': DARK}, bevel=0.006)
# Twin thrusters: red tanks with riveted collars, flared nozzles and a glowing ring inside each.
for side in (-1, 1):
    x = side * 0.105
    t = tube(f'Tank{side}', 0.078, 0.078, 0.42, (x, -0.15, 0.0), M_TANK, SIDE_GREEBLE, cap=HATCH, bevel=0.01)
    t.rotation_euler = (math.radians(90), 0, 0)
    for z in (0.15, -0.13):
        c = tube(f'Collar{side}{z}', 0.084, 0.084, 0.035, (x, -0.15, z), M_PLATE, RIVETS, bevel=0.004)
        c.rotation_euler = (math.radians(90), 0, 0)
    d = tube(f'Dome{side}', 0.07, 0.03, 0.05, (x, -0.15, 0.235), M_DARK, DARK, bevel=0.006)
    d.rotation_euler = (math.radians(90), 0, 0)
    n = tube(f'Nozzle{side}', 0.09, 0.062, 0.11, (x, -0.15, -0.265), M_DARK, DARK, bevel=0.004)
    n.rotation_euler = (math.radians(90), 0, 0)
    g = ring(f'Burner{side}', 0.05, 0.012, 0.0, M_GLOW)
    g.location = (x, -0.15, -0.3)
    g.rotation_euler = (math.radians(90), 0, 0)
    tube(f'Core{side}', 0.045, 0.045, 0.01, (x, -0.15, -0.31), M_GLOW, DARK, segs=24).rotation_euler = (math.radians(90), 0, 0)
    # A fin on the outside of each tank.
    box(f'Fin{side}', (0.012, 0.13, 0.2), (side * 0.19, -0.16, -0.13), M_TANK, {'x': X_PANEL, 'y': PLAIN, 'z': PLAIN}, bevel=0.004, segs=2)
# The spine between the tanks: a power housing with a hazard strip and a status light.
box('Spine', (0.09, 0.1, 0.4), (0, -0.13, 0.0), M_PLATE, {'x': BRACKETS, 'y': SIDE_GREEBLE, 'z': PLAIN}, bevel=0.01)
box('Hazard', (0.03, 0.012, 0.3), (0, -0.183, 0.0), M_TANK, {'x': HAZARD, 'y': HAZARD, 'z': HAZARD}, bevel=0.003, segs=2)
box('Status', (0.05, 0.012, 0.02), (0, -0.183, 0.18), M_GLOW, {'x': DARK, 'y': DARK, 'z': DARK}, bevel=0.003, segs=1)
# Shoulder straps, over the shoulders and down the chest, and a belt.
for side in (-1, 1):
    x = side * 0.1
    box(f'StrapTop{side}', (0.055, 0.2, 0.025), (x, 0.08, 0.26), M_STRAP, {'x': DARK, 'y': DARK, 'z': DARK}, bevel=0.006, rot=(-12, 0, 0))
    box(f'StrapFront{side}', (0.05, 0.022, 0.3), (x, 0.2, 0.09), M_STRAP, {'x': DARK, 'y': DARK, 'z': DARK}, bevel=0.006, rot=(8, 0, 0))
    box(f'Buckle{side}', (0.06, 0.03, 0.04), (x, 0.215, 0.13), M_DARK, {'x': DARK, 'y': DARK, 'z': DARK}, bevel=0.004)
box('Belt', (0.36, 0.03, 0.05), (0, -0.01, -0.26), M_STRAP, {'x': DARK, 'y': DARK, 'z': DARK}, bevel=0.006)

# One object, ready for a game.
bpy.ops.object.select_all(action='DESELECT')
for ob in parts:
    ob.select_set(True)
bpy.context.view_layer.objects.active = plate
bpy.ops.object.join()
plate.name = 'Jetpack'
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
tris = sum(len(p.vertices) - 2 for p in plate.data.polygons)
print('triangles', tris, 'materials', [m.name for m in plate.data.materials])

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'jetpack.blend'))
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, 'jetpack.glb'), export_format='GLB', use_selection=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, 'gltf', 'jetpack.gltf'), export_format='GLTF_SEPARATE', use_selection=True)
print('done')
