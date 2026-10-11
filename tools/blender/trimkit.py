"""Helpers for Burn Rate's Blender models: the Modular Sci-Fi MegaKit's trim-sheet materials, fitting
UVs onto the trim sheets, parts (boxes, tubes, bars, rings, fins, empties) and glTF export that points
at the kit's own textures. Used by tools/jetpack.py and the scripts beside this one.

Every builder calls `start(tex_dir)` first, adds parts, then `export(name, out_dir)`.
"""
import bpy, bmesh, json, math, os, shutil, tempfile
from mathutils import Vector, Matrix

TEX = ''
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


M = {}


def materials():
    M['tank'] = trim('MI_Trim_02_Red', 'T_Trim_02_BaseColor_Red.png', 'T_Trim_02_Normal.png', 'T_Trim_02_ORM.png')
    M['plate'] = trim('MI_Trim_01', 'T_Trim_01_BaseColor.png', 'T_Trim_01_Normal.png', 'T_Trim_01_ORM.png')
    M['dark'] = trim('MI_Trim_03_Dark', 'T_Trim_03_Cables.png', 'T_Trim_03_Normal.png', 'T_Trim_03_ORM.png')
    M['glow'] = flat('M_Jet_Glow', (1.0, 0.45, 0.1), emit=(1.0, 0.42, 0.08), strength=4.0)
    M['strap'] = flat('M_Jet_Strap', (0.03, 0.032, 0.035), rough=0.8)


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


# Trim regions (image space).
SIDE_GREEBLE = (0.0, 0.605, 0.62, 0.80)     # buttons, grille, round hatch, amber light
GRILLE = (0.42, 0.645, 0.62, 0.72)           # the mesh grille
PLAIN = (0.04, 0.28, 0.40, 0.58)             # plain panel with a seam
BRACKETS = (0.18, 0.035, 0.92, 0.245)        # panel strip with brackets
HAZARD = (0.012, 0.792, 0.27, 0.822)         # red and grey hazard stripes
STRIPE = (0.0, 0.515, 1.0, 0.555)            # Trim_02's painted band
RIVETS = (0.0, 0.43, 1.0, 0.47)              # Trim_01 riveted band
TRIANGLES = (0.0, 0.335, 1.0, 0.37)          # Trim_01 triangle band
HATCH = (0.525, 0.715, 0.635, 0.825)         # round hatch, for end caps
X_PANEL = (0.79, 0.62, 0.995, 0.85)          # Trim_02 X-braced panel
DARK = (0.1, 0.1, 0.6, 0.6)
D3 = {'x': DARK, 'y': DARK, 'z': DARK}


# ---------- parts ----------
class Pack:
    def __init__(self):
        self.parts = []
        self.groups = {}

    def add(self, ob, group=None):
        (self.groups.setdefault(group, []) if group else self.parts).append(ob)
        return ob


P = None


def finish(name, bm, mat, loc=(0, 0, 0), rot=(0, 0, 0), smooth=0.6, group=None):
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
    bpy.context.scene.collection.objects.link(ob)
    return P.add(ob, group)


def box(name, size, loc, mat, regions, bevel=0.008, segs=3, rot=(0, 0, 0), taper=None, group=None):
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
    return finish(name, bm, mat, loc, rot, group=group)


def tube_bm(r1, r2, length, side, cap, segs, bevel):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=length)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, 'X'))
    if bevel:
        rims = [e for e in bm.edges if len(e.link_faces) == 2 and abs(e.link_faces[0].normal.y - e.link_faces[1].normal.y) > 0.5]
        bmesh.ops.bevel(bm, geom=rims, offset=bevel, segments=2, affect='EDGES', profile=0.5, clamp_overlap=True)
    bm.normal_update()
    tube_uv(bm, side, cap)
    return bm


def vtube(name, r_bottom, r_top, length, loc, mat, side, cap=None, segs=28, bevel=0.0, group=None):
    """A tube standing upright (along Z) centred on loc, r_bottom at its lower end."""
    # Built along Y with radius1 at -Y; turned 90 about X so +Y goes up.
    bm = tube_bm(r_bottom, r_top, length, side, cap, segs, bevel)
    ob = finish(name, bm, mat, loc, group=group)
    ob.rotation_euler = (math.radians(90), 0, 0)
    return ob


def dtube(name, r, a, b, mat, side=DARK, segs=16, group=None):
    """A bar from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bm = tube_bm(r, r, d.length, side, None, segs, 0.0)
    ob = finish(name, bm, mat, (a + b) * 0.5, group=group)
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = Vector((0, 1, 0)).rotation_difference(d.normalized())
    return ob


def ring(name, major, minor, loc, mat, group=None):
    bm = bmesh.new()
    segs, sides = 28, 8
    verts = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        row = []
        for j in range(sides):
            b = 2 * math.pi * j / sides
            rr = major + minor * math.cos(b)
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), minor * math.sin(b))))
        verts.append(row)
    for i in range(segs):
        for j in range(sides):
            bm.faces.new((verts[i][j], verts[(i + 1) % segs][j], verts[(i + 1) % segs][(j + 1) % sides], verts[i][(j + 1) % sides]))
    bm.normal_update()
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for l in f.loops:
            l[uv].uv = (0.5, 0.5)
    return finish(name, bm, mat, loc, smooth=3.0, group=group)


def wing(name, side, root_chord, tip_chord, span, sweep, thick, mat, group):
    """A tapered fin from the origin out along side*X, its chord along Z, swept down by `sweep` at the tip."""
    bm = bmesh.new()
    pts = [(0, 0, root_chord * 0.5), (0, 0, -root_chord * 0.5), (span, 0, -sweep - tip_chord * 0.5), (span, 0, -sweep + tip_chord * 0.5)]
    top = [bm.verts.new((side * x, y - thick * 0.5, z)) for x, y, z in pts]
    bot = [bm.verts.new((side * x, y + thick * 0.5, z)) for x, y, z in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((top[j], top[i], bot[i], bot[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.004, segments=2, affect='EDGES', profile=0.5, clamp_overlap=True)
    bm.normal_update()
    box_uv(bm, {'x': PLAIN, 'y': X_PANEL, 'z': PLAIN})
    return finish(name, bm, mat, group=group)


def empty(name, loc, size=1.0, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    e.scale = (size, size, size)
    e.empty_display_size = 0.05
    bpy.context.scene.collection.objects.link(e)
    if parent:
        e.parent = parent
    return e



def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = objs[0]
    ob.name = name
    ob.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob



def start(tex):
    """Clears Blender, makes the materials and a fresh part list."""
    global TEX, P
    TEX = tex
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials()
    P = Pack()
    return P


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def export(name, out):
    """Writes out/name.gltf and .bin with every object, textures named by a path to the kit's files."""
    os.makedirs(out, exist_ok=True)
    tmp = tempfile.mkdtemp()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=os.path.join(tmp, name + '.gltf'), export_format='GLTF_SEPARATE', use_selection=True)
    data = json.load(open(os.path.join(tmp, name + '.gltf')))
    rel = os.path.relpath(os.path.abspath(TEX), os.path.abspath(out))
    for im in data.get('images', []):
        im['uri'] = rel + '/' + os.path.basename(im['uri'])
    json.dump(data, open(os.path.join(out, name + '.gltf'), 'w'), indent=1)
    shutil.copy(os.path.join(tmp, name + '.bin'), os.path.join(out, name + '.bin'))
    shutil.rmtree(tmp)
