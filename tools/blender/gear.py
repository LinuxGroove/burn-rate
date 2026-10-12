"""Builds the pilot's flight goggles and visor, fitted to each Universal Base Character's head.

Run (pip bpy, see the mockup README):
    python tools/blender/gear.py addons/quaternius/materials assets/people assets/models/gear
Writes goggles_<body>.gltf and visor_<body>.gltf for the male and female bodies, in the body's rest
space like the kit's hair (so the game hangs them on the Head bone the same way). The strap follows
the head's own outline, sampled from the body mesh at eye height.

Materials: M_Jet_Strap (the strap), MI_Trim_03_Dark (frames) and M_Lens (the glass, which the game
tints per suit).
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trimkit
from trimkit import *

TEX, PEOPLE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
BODIES = {'male': 'Superhero_Male_FullBody.gltf', 'female': 'Superhero_Female_FullBody.gltf'}


def head_points(body):
    """The body's head vertices, in its rest space (Blender Z up, face towards -Y)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PEOPLE, BODIES[body]))
    pts = []
    eyes = []
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        vs = [o.matrix_world @ v.co for v in o.data.vertices]
        if o.name.startswith('Eyes'):
            eyes = vs
        elif o.name.lower().startswith('superhero'):
            pts = [v for v in vs if v.z > 1.5 and abs(v.x) < 0.14]
    eye_z = sum(v.z for v in eyes) / len(eyes)
    eye_y = min(v.y for v in eyes)
    return pts, eye_z, eye_y


def outline(pts, z, tilt, n=40, pad=0.008):
    """The head's outline at height z (rising by `tilt` towards the back), as n points, padded out."""
    cy = sum(p.y for p in pts) / len(pts)
    out = []
    for i in range(n):
        a = i * math.tau / n
        d = Vector((math.sin(a), -math.cos(a), 0))  # i = 0 is the face (-Y)
        zz = z + tilt * (0.5 - 0.5 * math.cos(a))
        best = 0.0
        for p in pts:
            if abs(p.z - zz) > 0.012:
                continue
            q = Vector((p.x, p.y - cy, 0))
            if q.length < 1e-4:
                continue
            if q.normalized().dot(d) > 0.985:
                best = max(best, q.length)
        out.append((Vector((0, cy, zz)) + d * (best + pad), d))
    # Fill gaps (directions with no vertex near) from their neighbours.
    for i, (p, d) in enumerate(out):
        if (p - Vector((0, cy, p.z))).length < pad + 0.02:
            a, b = out[i - 1][0], out[(i + 1) % n][0]
            out[i] = ((a + b) * 0.5, d)
    return out


def band(name, ring_pts, height, mat, a0=0.0, a1=1.0, thick=0.006):
    """A band through the outline points, from fraction a0 to a1 of the way round."""
    bm = bmesh.new()
    n = len(ring_pts)
    if a0 > a1:  # wraps round through the face
        idx = [i for i in range(n) if i / n >= a0] + [i for i in range(n) if i / n <= a1]
    else:
        idx = [i for i in range(n) if a0 <= i / n <= a1] if a1 - a0 < 1 else list(range(n))
    rows = []
    for i in idx:
        p, d = ring_pts[i]
        rows.append([bm.verts.new(p + d * dt + Vector((0, 0, dz))) for dt, dz in ((0, -height / 2), (thick, -height / 2), (thick, height / 2), (0, height / 2))])
    loop = len(idx) == n
    for k in range(len(rows) - (0 if loop else 1)):
        r0, r1 = rows[k], rows[(k + 1) % len(rows)]
        for j in range(4):
            bm.faces.new((r0[j], r1[j], r1[(j + 1) % 4], r0[(j + 1) % 4]))
    if not loop:
        bm.faces.new(rows[0])
        bm.faces.new(list(reversed(rows[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    box_uv(bm, D3)
    return finish(name, bm, mat, smooth=1.0)


def goggles(body):
    pts, eye_z, eye_y = head_points(body)
    trimkit.start(TEX)
    lens = flat('M_Lens', (0.2, 0.5, 0.6), rough=0.1, metal=0.6, emit=(0.3, 0.7, 0.9), strength=0.6)
    ring_pts = outline(pts, eye_z + 0.004, 0.03)
    band('Strap', ring_pts, 0.026, M['strap'])
    face = ring_pts[0][0]
    for side in (-1, 1):
        c = Vector((side * 0.034, face.y - 0.006, eye_z + 0.004))
        bm = tube_bm(0.027, 0.024, 0.022, DARK, None, 20, 0.003)
        ob = finish(f'Cup{side}', bm, M['dark'], c)
        ob.rotation_euler = (0, 0, 0)
        bm = tube_bm(0.021, 0.021, 0.004, DARK, None, 20, 0.0)
        finish(f'Lens{side}', bm, lens, c + Vector((0, -0.012, 0)))
    box('Bridge', (0.02, 0.01, 0.01), (0, face.y - 0.008, eye_z + 0.004), M['dark'], D3, bevel=0.002, segs=1)
    bpy.ops.object.select_all(action='DESELECT')
    ob = join([o for o in bpy.context.scene.objects if o.type == 'MESH'], 'Goggles')
    print(body, 'goggles', tris(ob))
    export(f'goggles_{body}', OUT)


def visor(body):
    pts, eye_z, eye_y = head_points(body)
    trimkit.start(TEX)
    glass = flat('M_Lens', (0.2, 0.5, 0.6), rough=0.1, metal=0.6, emit=(0.3, 0.7, 0.9), strength=0.6)
    ring_pts = outline(pts, eye_z + 0.006, 0.02)
    band('Strap', ring_pts, 0.024, M['strap'])
    shield = outline(pts, eye_z + 0.006, 0.0, pad=0.02)
    band('Visor', shield, 0.045, glass, 0.8, 0.2, thick=0.004)
    top = [(p + Vector((0, 0, 0.026)), d) for p, d in shield]
    band('Rim', top, 0.008, M['dark'], 0.8, 0.2, thick=0.008)
    bpy.ops.object.select_all(action='DESELECT')
    ob = join([o for o in bpy.context.scene.objects if o.type == 'MESH'], 'Visor')
    print(body, 'visor', tris(ob))
    export(f'visor_{body}', OUT)


import bmesh
for b in BODIES:
    goggles(b)
    visor(b)
print('done')
