"""Builds Halberd's hazards that the kits don't have, on the MegaKit's trim sheets: the seeker rocket,
the zapper's capacitors and the laser's emitter.

Run (pip bpy, see the mockup README):
    python tools/blender/hazards.py addons/quaternius/materials assets/models/hazards
Writes seeker.gltf, zapper_node.gltf and laser_emitter.gltf (and their .bin).

Glow parts use the material M_Jet_Glow, which the game repaints in each hazard's colour.
Axes (Blender, so +Z is +Y in Godot and -Y is +Z):
    seeker         nose at -X, tail at +X; empty "Exhaust" at the nozzle
    zapper_node    the emitter tip at the origin, the body below it along -Z: the arc leaves along +Z
    laser_emitter  the lens at the origin, facing +X
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trimkit
from trimkit import *

TEX, OUT = sys.argv[1], sys.argv[2]


def xtube(name, r_front, r_back, length, x, mat, side, cap=None, segs=24, bevel=0.0, y=0.0, z=0.0):
    """A tube lying along X, r_front at its -X end."""
    bm = tube_bm(r_front, r_back, length, side, cap, segs, bevel)
    ob = finish(name, bm, mat, (x, y, z))
    ob.rotation_euler = (0, 0, math.radians(-90))
    return ob


def done(name):
    bpy.ops.object.select_all(action='DESELECT')
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    ob = join(meshes, name)
    print(name, 'triangles', tris(ob))
    return ob


def seeker():
    trimkit.start(TEX)
    # Nose, seeker band, body, tail and nozzle, front to back.
    xtube('Nose', 0.012, 0.12, 0.24, -0.45, M['tank'], STRIPE, segs=24)
    xtube('Eye', 0.121, 0.121, 0.03, -0.32, M['glow'], DARK, segs=24)
    xtube('Body', 0.12, 0.12, 0.46, -0.07, M['plate'], RIVETS, segs=24, bevel=0.004)
    for x in (-0.27, 0.12):
        xtube(f'Collar{x}', 0.127, 0.127, 0.03, x, M['dark'], DARK, segs=24)
    xtube('Stripe', 0.122, 0.122, 0.08, -0.17, M['tank'], HAZARD, segs=24)
    xtube('Tail', 0.12, 0.085, 0.12, 0.22, M['dark'], DARK, segs=24, bevel=0.004)
    xtube('Nozzle', 0.065, 0.09, 0.1, 0.33, M['dark'], DARK, segs=24, bevel=0.003)
    r = ring('Burner', 0.055, 0.012, (0.38, 0, 0), M['glow'])
    r.rotation_euler = (0, math.radians(90), 0)
    # Four fins at the tail, in an X.
    for i in range(4):
        a = math.radians(45 + 90 * i)
        d = Vector((0, math.cos(a), math.sin(a)))
        fin = box(f'Fin{i}', (0.2, 0.012, 0.13), Vector((0.17, 0, 0)) + d * 0.17, M['tank'], {'x': X_PANEL, 'y': X_PANEL, 'z': PLAIN}, bevel=0.003, segs=2, taper=None)
        fin.rotation_euler = (a - math.radians(90), 0, 0)
        # Small canards near the nose.
        can = box(f'Canard{i}', (0.08, 0.008, 0.06), Vector((-0.22, 0, 0)) + d * 0.145, M['dark'], D3, bevel=0.002, segs=1)
        can.rotation_euler = (a - math.radians(90), 0, 0)
    main = done('Seeker')
    empty('Exhaust', (0.4, 0, 0), 1.0, main)
    export('seeker', OUT)


def zapper_node():
    trimkit.start(TEX)
    # The emitter: a glowing ball in a crown of prongs.
    ring('Emitter', 0.075, 0.03, (0, 0, -0.01), M['glow'])
    vtube('EmitterCore', 0.05, 0.03, 0.06, (0, 0, 0.0), M['glow'], DARK, segs=16)
    for i in range(4):
        a = i * math.tau / 4
        p = Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, -0.02))
        dtube(f'Prong{i}', 0.014, p + Vector((0, 0, -0.08)), p * 0.75 + Vector((0, 0, 0.06)), M['dark'], segs=8)
    vtube('Cap', 0.16, 0.1, 0.07, (0, 0, -0.1), M['dark'], DARK, bevel=0.006)
    # The capacitor: a glowing core wound with coils.
    vtube('Core', 0.1, 0.1, 0.3, (0, 0, -0.28), M['glow'], DARK, segs=20)
    for i in range(6):
        z = -0.15 - i * 0.05
        ring(f'Coil{i}', 0.125, 0.022, (0, 0, z), M['plate'])
    for i in range(3):
        a = i * math.tau / 3
        p = Vector((math.cos(a) * 0.15, math.sin(a) * 0.15, -0.28))
        dtube(f'Rod{i}', 0.012, p + Vector((0, 0, -0.17)), p + Vector((0, 0, 0.17)), M['plate'], segs=8)
    # The housing it stands in, with a hazard band, and its mount.
    vtube('Housing', 0.22, 0.18, 0.2, (0, 0, -0.54), M['plate'], BRACKETS, cap=HATCH, bevel=0.012)
    vtube('Band', 0.222, 0.222, 0.05, (0, 0, -0.5), M['tank'], HAZARD)
    vtube('Lip', 0.2, 0.2, 0.025, (0, 0, -0.43), M['dark'], DARK)
    box('Mount', (0.32, 0.32, 0.06), (0, 0, -0.67), M['dark'], D3, bevel=0.01)
    for i in range(4):
        a = i * math.tau / 4 + math.radians(45)
        box(f'Bolt{i}', (0.035, 0.035, 0.03), (math.cos(a) * 0.19, math.sin(a) * 0.19, -0.635), M['plate'], {'x': RIVETS, 'y': RIVETS, 'z': RIVETS}, bevel=0.006, segs=1)
    done('Zapper')
    export('zapper_node', OUT)


def laser_emitter():
    trimkit.start(TEX)
    box('Housing', (0.46, 0.36, 0.3), (-0.33, 0, 0), M['plate'], {'x': PLAIN, 'y': SIDE_GREEBLE, 'z': BRACKETS}, bevel=0.02)
    box('Stripe', (0.3, 0.37, 0.04), (-0.36, 0, -0.1), M['tank'], {'x': HAZARD, 'y': HAZARD, 'z': HAZARD}, bevel=0.004, segs=1)
    for i in range(4):
        box(f'Sink{i}', (0.025, 0.3, 0.07), (-0.48 + i * 0.07, 0, 0.18), M['dark'], D3, bevel=0.004, segs=1)
    xtube('Barrel', 0.11, 0.11, 0.14, -0.06, M['dark'], DARK, segs=24, bevel=0.006)
    xtube('Shroud', 0.13, 0.1, 0.06, 0.03, M['plate'], RIVETS, segs=24, bevel=0.004)
    xtube('Lens', 0.075, 0.075, 0.02, 0.06, M['glow'], DARK, segs=24)
    r = ring('LensRing', 0.08, 0.012, (0.065, 0, 0), M['glow'])
    r.rotation_euler = (0, math.radians(90), 0)
    box('Status', (0.04, 0.012, 0.02), (-0.2, -0.185, 0.07), M['glow'], D3, bevel=0.003, segs=1)
    # A rail clamp on top, which the arm hangs from.
    box('Clamp', (0.16, 0.16, 0.08), (-0.33, 0, 0.19), M['dark'], D3, bevel=0.01)
    done('Emitter')
    export('laser_emitter', OUT)


seeker()
zapper_node()
laser_emitter()
print('done')
