"""Builds Burn Rate's six prototype jetpacks in Blender from the Modular Sci-Fi MegaKit's trim sheets.

Run (pip bpy 5.2.2, see the mockup README for installing it):
    python tools/jetpack.py addons/quaternius/materials assets/models/jetpack [k1 k2 ...]
Writes jetpack_<id>.gltf and .bin for each pack, naming the kit's textures by a path into
addons/quaternius/materials, so they share the kit's files.

Every pack is built from the K-1's parts (back plate, tanks, collars, nozzles, burners, fins, spine,
straps), rearranged: K-2 twin big burners, K-3 fold-out glide fins, K-4 a pulse drum, K-5 side
thrusters, K-6 a heavy cargo frame.

Axes: Blender +Z is up and the pack sits behind the wearer along -Y, which is +Z in Godot and glTF.
The origin is where the back plate touches the wearer's back, level with the shoulder blades.

Named nodes the game reads (see PackView):
    Flame_<n>          a nozzle's exit, exhaust going down; its scale is the flame's size
    Side_L, Side_R     K-5's side thrusters, exhaust going out sideways (-X, +X)
    Wing_L, Wing_R     K-3's glide fins, hinged at their node (folded is a turn about Z in Godot)
    Drum               K-4's pulse drum, turned about Y a notch each kick
    Armour             K-6's side plates, dropped when its armour takes a hit
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'blender'))
import trimkit
from trimkit import *

TEX, OUT = sys.argv[1], sys.argv[2]
ONLY = sys.argv[3:]


# ---------- shared assemblies ----------
def back(w=0.34, h=0.5, spine=True, z=-0.02):
    """The back plate against the wearer, its rim, the spine housing, straps and belt."""
    box('Plate', (w, 0.05, h), (0, -0.03, z), M['plate'], {'x': BRACKETS, 'y': PLAIN, 'z': BRACKETS}, bevel=0.012)
    box('PlateRim', (w - 0.04, 0.02, h - 0.06), (0, -0.065, z), M['dark'], D3, bevel=0.006)
    if spine:
        box('Spine', (0.09, 0.1, 0.4), (0, -0.13, 0.0), M['plate'], {'x': BRACKETS, 'y': SIDE_GREEBLE, 'z': PLAIN}, bevel=0.01)
        box('Hazard', (0.03, 0.012, 0.3), (0, -0.183, 0.0), M['tank'], {'x': HAZARD, 'y': HAZARD, 'z': HAZARD}, bevel=0.003, segs=2)
        box('Status', (0.05, 0.012, 0.02), (0, -0.183, 0.18), M['glow'], D3, bevel=0.003, segs=1)
    for side in (-1, 1):
        x = side * 0.1
        box(f'StrapTop{side}', (0.055, 0.2, 0.025), (x, 0.08, 0.26), M['strap'], D3, bevel=0.006, rot=(-12, 0, 0))
        box(f'StrapFront{side}', (0.05, 0.022, 0.3), (x, 0.2, 0.09), M['strap'], D3, bevel=0.006, rot=(8, 0, 0))
        box(f'Buckle{side}', (0.06, 0.03, 0.04), (x, 0.215, 0.13), M['dark'], D3, bevel=0.004)
    box('Belt', (w + 0.02, 0.03, 0.05), (0, -0.01, -0.26), M['strap'], D3, bevel=0.006)


def thruster(x, y, r=0.078, length=0.42, z=0.0, nozzle=(0.09, 0.062, 0.11), collars=(0.15, -0.13), fin=True, name='T'):
    """A tank with riveted collars, a dome on top, a flared nozzle and a glowing burner. Returns the exhaust point and size."""
    vtube(f'{name}Tank', r, r, length, (x, y, z), M['tank'], SIDE_GREEBLE, cap=HATCH, bevel=0.01)
    for i, cz in enumerate(collars):
        vtube(f'{name}Collar{i}', r + 0.006, r + 0.006, 0.035, (x, y, z + cz * length / 0.42), M['plate'], RIVETS, bevel=0.004)
    top = z + length * 0.5
    vtube(f'{name}Dome', r * 0.9, r * 0.38, 0.05, (x, y, top + 0.025), M['dark'], DARK, bevel=0.006)
    nb, nt, nl = nozzle
    bottom = z - length * 0.5
    vtube(f'{name}Nozzle', nb, nt, nl, (x, y, bottom - nl * 0.5 + 0.01), M['dark'], DARK, bevel=0.004)
    exit_z = bottom - nl + 0.01
    ring(f'{name}Burner', nb * 0.56, nb * 0.13, (x, y, exit_z - 0.005), M['glow'])
    vtube(f'{name}Core', nb * 0.5, nb * 0.5, 0.01, (x, y, exit_z + 0.004), M['glow'], DARK, segs=24)
    if fin:
        side = 1 if x > 0 else -1
        box(f'{name}Fin', (0.012, 0.13, 0.2), (x + side * (r + 0.007), y - 0.01, z - length * 0.31), M['tank'], {'x': X_PANEL, 'y': PLAIN, 'z': PLAIN}, bevel=0.004, segs=2)
    return (x, y, exit_z - 0.01), nb / 0.09


# ---------- the six prototypes ----------
def build_k1():
    back()
    flames = []
    for side in (-1, 1):
        flames.append(thruster(side * 0.105, -0.15, name=f'T{side}'))
    return flames, {}


def build_k2():
    """Twin big burners: fat short tanks, big bell nozzles, cooling rings and intakes."""
    back(w=0.42, spine=False)
    box('Spine', (0.1, 0.09, 0.36), (0, -0.12, 0.02), M['plate'], {'x': BRACKETS, 'y': SIDE_GREEBLE, 'z': PLAIN}, bevel=0.01)
    box('Status', (0.05, 0.012, 0.02), (0, -0.168, 0.16), M['glow'], D3, bevel=0.003, segs=1)
    flames = []
    for side in (-1, 1):
        x = side * 0.14
        f = thruster(x, -0.18, r=0.1, length=0.34, z=0.05, nozzle=(0.135, 0.085, 0.17), collars=(0.12,), fin=False, name=f'T{side}')
        flames.append(f)
        # Cooling rings above the nozzle.
        for i in range(3):
            vtube(f'Cool{side}{i}', 0.118, 0.118, 0.012, (x, -0.18, -0.06 - i * 0.032), M['dark'], DARK, segs=32)
        # An air intake on the top of each tank.
        box(f'Intake{side}', (0.1, 0.07, 0.05), (x, -0.18, 0.26), M['plate'], {'x': GRILLE, 'y': GRILLE, 'z': GRILLE}, bevel=0.008)
        # A brace between tank and plate.
        box(f'Brace{side}', (0.05, 0.12, 0.05), (x * 0.8, -0.1, 0.12), M['dark'], D3, bevel=0.006)
        box(f'Stripe{side}', (0.02, 0.012, 0.2), (x + side * 0.1, -0.18, 0.06), M['tank'], {'x': HAZARD, 'y': HAZARD, 'z': HAZARD}, bevel=0.003, segs=1)
    return flames, {}


def build_k3():
    """Fold-out glide fins on slim tanks."""
    back(spine=False)
    box('Spine', (0.08, 0.1, 0.46), (0, -0.13, 0.03), M['plate'], {'x': BRACKETS, 'y': SIDE_GREEBLE, 'z': PLAIN}, bevel=0.01)
    box('Status', (0.04, 0.012, 0.02), (0, -0.183, 0.2), M['glow'], D3, bevel=0.003, segs=1)
    flames = []
    for side in (-1, 1):
        flames.append(thruster(side * 0.09, -0.15, r=0.062, length=0.44, z=-0.01, nozzle=(0.075, 0.052, 0.1), collars=(0.16, -0.1, -0.16), fin=False, name=f'T{side}'))
    moving = {}
    for side, label in ((-1, 'Wing_L'), (1, 'Wing_R')):
        hinge = Vector((side * 0.075, -0.2, 0.17))
        g = label
        vtube(f'{label}Hinge', 0.022, 0.022, 0.07, hinge, M['dark'], DARK, segs=16, group=g)
        w = wing(f'{label}Fin', side, 0.26, 0.09, 0.5, 0.2, 0.02, M['tank'], g)
        w.location = hinge
        # A stiffener along the leading edge and a light at the tip.
        dtube(f'{label}Spar', 0.009, hinge + Vector((0, 0, 0.11)), hinge + Vector((side * 0.5, 0, -0.16)), M['dark'], group=g)
        box(f'{label}Tip', (0.03, 0.03, 0.05), hinge + Vector((side * 0.5, 0, -0.2)), M['glow'], D3, bevel=0.006, group=g)
        moving[label] = hinge
    return flames, moving


def build_k4():
    """A pulse drum: a turning cylinder of chambers over one big nozzle."""
    back(spine=False)
    flames = []
    # The drum and its chambers.
    vtube('DrumBody', 0.11, 0.11, 0.26, (0, -0.17, 0.04), M['tank'], STRIPE, cap=HATCH, bevel=0.012, group='Drum')
    for i in range(6):
        a = i * math.tau / 6
        p = Vector((math.cos(a) * 0.1, -0.17 + math.sin(a) * 0.1, 0.04))
        vtube(f'Chamber{i}', 0.026, 0.026, 0.22, p, M['dark'], DARK, segs=12, group='Drum')
        vtube(f'ChamberCap{i}', 0.03, 0.03, 0.02, p + Vector((0, 0, 0.115)), M['plate'], RIVETS, segs=12, group='Drum')
    vtube('DrumCap', 0.12, 0.12, 0.03, (0, -0.17, 0.18), M['plate'], RIVETS, bevel=0.004)
    vtube('DrumBase', 0.12, 0.12, 0.03, (0, -0.17, -0.1), M['plate'], RIVETS, bevel=0.004)
    vtube('Axle', 0.03, 0.02, 0.05, (0, -0.17, 0.22), M['dark'], DARK, segs=16)
    # One big nozzle under it.
    vtube('Nozzle', 0.13, 0.08, 0.15, (0, -0.17, -0.19), M['dark'], DARK, bevel=0.004)
    ring('Burner', 0.075, 0.017, (0, -0.17, -0.27), M['glow'])
    vtube('Core', 0.065, 0.065, 0.01, (0, -0.17, -0.262), M['glow'], DARK, segs=24)
    flames.append(((0, -0.17, -0.28), 1.45))
    # Stub tanks either side feed it, with small pilot burners.
    for side in (-1, 1):
        x = side * 0.17
        flames.append(thruster(x, -0.12, r=0.045, length=0.3, z=0.0, nozzle=(0.05, 0.035, 0.06), collars=(0.14, -0.14), fin=False, name=f'S{side}'))
        dtube(f'Feed{side}', 0.012, (x * 0.75, -0.12, 0.1), (side * 0.11, -0.17, 0.12), M['dark'])
        box(f'Bracket{side}', (0.08, 0.06, 0.04), (side * 0.12, -0.09, -0.12), M['plate'], {'x': BRACKETS, 'y': BRACKETS, 'z': BRACKETS}, bevel=0.006)
    box('Status', (0.05, 0.012, 0.02), (0, -0.07, 0.2), M['glow'], D3, bevel=0.003, segs=1)
    return flames, {'Drum': Vector((0, -0.17, 0.04))}


def build_k5():
    """Side thrusters on struts, for quick lane changes."""
    back()
    flames = []
    for side in (-1, 1):
        flames.append(thruster(side * 0.105, -0.15, length=0.4, z=0.01, name=f'T{side}', fin=False))
    side_flames = {}
    for side, label in ((-1, 'Side_L'), (1, 'Side_R')):
        x0 = side * 0.18
        pod = Vector((side * 0.27, -0.15, 0.1))
        dtube(f'Strut{side}a', 0.014, (x0, -0.15, 0.16), pod + Vector((-side * 0.03, 0, 0.02)), M['dark'])
        dtube(f'Strut{side}b', 0.014, (x0, -0.15, 0.0), pod + Vector((-side * 0.03, 0, -0.02)), M['dark'])
        # The pod lies along X with its nozzle pointing out.
        bm = tube_bm(0.05, 0.05, 0.13, SIDE_GREEBLE, HATCH, 24, 0.006)
        ob = finish(f'Pod{side}', bm, M['tank'], pod)
        ob.rotation_euler = (0, 0, math.radians(90))
        bm = tube_bm(0.04, 0.058, 0.07, DARK, None, 24, 0.003)
        ob = finish(f'PodNozzle{side}', bm, M['dark'], pod + Vector((side * 0.095, 0, 0)))
        ob.rotation_euler = (0, 0, math.radians(-90 * side))
        ring(f'PodBurner{side}', 0.033, 0.008, pod + Vector((side * 0.13, 0, 0)), M['glow']).rotation_euler = (0, math.radians(90), 0)
        box(f'PodLight{side}', (0.03, 0.012, 0.02), pod + Vector((0, -0.05, 0.03)), M['glow'], D3, bevel=0.003, segs=1)
        side_flames[label] = pod + Vector((side * 0.135, 0, 0))
    return flames, {'sides': side_flames}


def build_k6():
    """A heavy cargo frame: a cage of bars, big tanks, a booster and armour plates."""
    back(w=0.46, h=0.6, spine=False, z=-0.03)
    flames = []
    box('Body', (0.3, 0.16, 0.5), (0, -0.14, 0.0), M['tank'], {'x': X_PANEL, 'y': X_PANEL, 'z': PLAIN}, bevel=0.014)
    box('BodyGrille', (0.16, 0.012, 0.12), (0, -0.225, 0.12), M['plate'], {'x': GRILLE, 'y': GRILLE, 'z': GRILLE}, bevel=0.003, segs=1)
    box('Status', (0.06, 0.012, 0.02), (0, -0.225, 0.22), M['glow'], D3, bevel=0.003, segs=1)
    for side in (-1, 1):
        flames.append(thruster(side * 0.19, -0.2, r=0.085, length=0.46, z=0.0, nozzle=(0.1, 0.07, 0.11), collars=(0.17, 0.0, -0.17), fin=False, name=f'T{side}'))
    # A booster under the body.
    vtube('Booster', 0.11, 0.07, 0.12, (0, -0.15, -0.3), M['dark'], DARK, bevel=0.004)
    ring('BoosterBurner', 0.062, 0.014, (0, -0.15, -0.365), M['glow'])
    flames.append(((0, -0.15, -0.37), 1.2))
    # The cage.
    xs, ys, z0, z1 = 0.31, (-0.04, -0.32), -0.33, 0.36
    for x in (-xs, xs):
        for y in ys:
            dtube(f'Post{x}{y}', 0.016, (x, y, z0), (x, y, z1), M['dark'])
        dtube(f'SideTop{x}', 0.016, (x, ys[0], z1), (x, ys[1], z1), M['dark'])
        dtube(f'SideLow{x}', 0.016, (x, ys[0], z0), (x, ys[1], z0), M['dark'])
    for y in ys:
        dtube(f'Top{y}', 0.016, (-xs, y, z1), (xs, y, z1), M['dark'])
    dtube('Low', 0.016, (-xs, ys[1], z0), (xs, ys[1], z0), M['dark'])
    for x in (-0.12, 0.0, 0.12):
        dtube(f'Rack{x}', 0.01, (x, ys[0], z1 + 0.005), (x, ys[1], z1 + 0.005), M['dark'], segs=10)
    # Cargo strapped on top.
    box('Cargo', (0.36, 0.22, 0.12), (0, -0.18, z1 + 0.075), M['plate'], {'x': SIDE_GREEBLE, 'y': BRACKETS, 'z': PLAIN}, bevel=0.01)
    for x in (-0.1, 0.1):
        box(f'CargoStrap{x}', (0.03, 0.235, 0.135), (x, -0.18, z1 + 0.075), M['strap'], D3, bevel=0.004)
    # Corner caps.
    for x in (-xs, xs):
        for y in ys:
            for z in (z0, z1):
                box(f'Cap{x}{y}{z}', (0.045, 0.045, 0.045), (x, y, z), M['plate'], {'x': RIVETS, 'y': RIVETS, 'z': RIVETS}, bevel=0.008, segs=2)
    # Armour plates on the outside of the cage: they come off with its one hit.
    for side in (-1, 1):
        box(f'ArmourPlate{side}', (0.024, 0.26, 0.42), (side * 0.335, -0.18, 0.02), M['tank'], {'x': X_PANEL, 'y': PLAIN, 'z': PLAIN}, bevel=0.008, group='Armour')
        box(f'ArmourStripe{side}', (0.028, 0.18, 0.04), (side * 0.335, -0.18, -0.14), M['tank'], {'x': HAZARD, 'y': HAZARD, 'z': HAZARD}, bevel=0.003, segs=1, group='Armour')
    return flames, {'Armour': Vector((0, -0.18, 0.02))}


BUILDERS = {'k1': build_k1, 'k2': build_k2, 'k3': build_k3, 'k4': build_k4, 'k5': build_k5, 'k6': build_k6}
def build(pid):
    pack = trimkit.start(TEX)
    flames, moving = BUILDERS[pid]()
    main = join(pack.parts, 'Jetpack')
    n = tris(main)
    for label, objs in pack.groups.items():
        g = join(objs, label)
        pivot = moving[label]
        g.data.transform(Matrix.Translation(-pivot))
        g.location = pivot
        g.parent = main
        n += tris(g)
    for i, (pos, size) in enumerate(flames):
        empty(f'Flame_{i}', pos, size, main)
    for label, pos in moving.get('sides', {}).items():
        empty(label, pos, 0.6, main)
    print(pid, 'triangles', n, 'flames', len(flames))
    export(f'jetpack_{pid}', OUT)


for pid in (ONLY or BUILDERS.keys()):
    build(pid)
print('done')
