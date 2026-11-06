"""Passengers, first half: gran, baron, smuggler.

Run with:
  blender.exe --background --python blender/build_passengers_a.py

All numbers are Godot coordinates. Character faces -Z, so the face is built on the
negative Z side, and `_l` parts sit on -X.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

import bmesh
import bpy
from mathutils import Matrix, Vector

import wacky
from wacky import ball, box, cyl, mat, wobble

# wacky.VIEWS is written in Blender axes, where a character's front is +Y. Its "front"
# tile would show the back, so the sheet is pointed at the faces here. The lib is untouched.
wacky.VIEWS.update({
    "front": (0.0, 1.0, 0.14),
    "side": (1.0, 0.0, 0.14),
    "three_quarter": (-0.75, 0.75, 0.35),
    "back": (0.6, -0.8, 0.3),
})

OUT = "assets/models/passengers"
PREVIEWS = "assets/previews/passengers"

POS = {
    "pelvis": (0, 0.98, 0),
    "chest": (0, 1.31, 0),
    "head": (0, 1.67, 0),
    "head_ko": (0, 1.67, 0),
    "upper_arm_l": (-0.29, 1.35, 0),
    "forearm_l": (-0.29, 1.03, 0),
    "upper_arm_r": (0.29, 1.35, 0),
    "forearm_r": (0.29, 1.03, 0),
    "thigh_l": (-0.11, 0.66, 0),
    "shin_l": (-0.11, 0.22, 0),
    "thigh_r": (0.11, 0.66, 0),
    "shin_r": (0.11, 0.22, 0),
}


# --- Small kit on top of wacky -------------------------------------------------------

def rot(obj, x=0.0, y=0.0, z=0.0):
    """Tilts [obj] about its own centre, in degrees around Godot axes."""
    obj.rotation_euler = (math.radians(x), math.radians(-z), math.radians(y))
    return obj


def tube(points, radius, material, sides=6):
    """Bent pipe through Godot [points]. [radius] is one number or one per point."""
    bm = bmesh.new()
    pts = [wacky.gv(*p) for p in points]
    radii = radius if isinstance(radius, (list, tuple)) else [radius] * len(pts)
    rings = []
    normal = None
    for i, p in enumerate(pts):
        tangent = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if normal is None:
            ref = Vector((0, 0, 1)) if abs(tangent.z) < 0.9 else Vector((1, 0, 0))
            normal = tangent.cross(ref).normalized()
        normal = (normal - tangent * normal.dot(tangent)).normalized()
        side = tangent.cross(normal)
        ring = []
        for j in range(sides):
            a = 2.0 * math.pi * j / sides
            ring.append(bm.verts.new(p + (normal * math.cos(a) + side * math.sin(a)) * radii[i]))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    return wacky._finish("_tube", bm, (0, 0, 0), material)


def loft(sections, material):
    """Skin through cross-sections, each a list of Godot points. For wedges and crooked slabs."""
    bm = bmesh.new()
    rings = [[bm.verts.new(wacky.gv(*p)) for p in section] for section in sections]
    count = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for j in range(count):
            k = (j + 1) % count
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    return wacky._finish("_loft", bm, (0, 0, 0), material)


def text(string, center, size, material, spin=0.0):
    """Flat mesh letters facing -Z, like a label on a chest. [spin] turns them around Y."""
    curve = bpy.data.curves.new("_text", "FONT")
    curve.body = string
    curve.size = size
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.resolution_u = 1
    source = bpy.data.objects.new("_text", curve)
    bpy.context.scene.collection.objects.link(source)
    graph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(source.evaluated_get(graph))
    bpy.data.objects.remove(source, do_unlink=True)
    bpy.data.curves.remove(curve)
    # Font is in the XY plane facing +Z. Godot -Z is Blender +Y, read from that side.
    mesh.transform(Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    mesh.materials.clear()
    mesh.materials.append(material)
    obj = bpy.data.objects.new("_text", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = wacky.gv(*center)
    return rot(obj, y=spin)


def _flat(points, center, material):
    """One-sided n-gon. [points] are (right, up) as seen by someone looking at the face."""
    verts = [(-right, 0.0, up) for right, up in points]
    mesh = bpy.data.meshes.new("_flat")
    mesh.from_pydata(verts, [], [list(range(len(verts)))])
    mesh.update()
    mesh.materials.append(material)
    obj = bpy.data.objects.new("_flat", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = wacky.gv(*center)
    return obj


def plate(center, size, material):
    """Flat quad facing -Z. Costs 2 tris, for labels, patches and teeth."""
    w, h = size[0] / 2.0, size[1] / 2.0
    return _flat(((-w, -h), (w, -h), (w, h), (-w, h)), center, material)


def disc(center, radius, material, verts=7):
    """Flat round decal facing -Z."""
    points = [(math.cos(2.0 * math.pi * i / verts) * radius, math.sin(2.0 * math.pi * i / verts) * radius)
              for i in range(verts)]
    return _flat(points, center, material)


def eye(center, radius, look=(0.0, 0.0), pupil=0.3, white="white", verts=9):
    """Googly eye: a domed button. [look] slides the pupil, in units of the eye's radius."""
    x, y, z = center
    depth = radius * 0.8
    return [
        cyl("_eye", radius * 0.74, depth, (x, y, z), mat(white), axis="z", verts=verts, top_radius=radius),
        disc((x + look[0] * radius, y + look[1] * radius, z - depth * 0.5 - 0.004), radius * pupil, mat("black"), 6),
    ]


def x_eye(center, radius, verts=9):
    """Knocked-out eye: same button, big black cross."""
    x, y, z = center
    depth = radius * 0.8
    pieces = [cyl("_eye", radius * 0.74, depth, center, mat("white"), axis="z", verts=verts, top_radius=radius)]
    for angle in (45, -45):
        pieces.append(rot(plate((x, y, z - depth * 0.5 - 0.004 - (angle > 0) * 0.002), (radius * 1.5, radius * 0.36),
                                mat("black")), z=angle))
    return pieces


def teeth(center, width, count, height, depth=0.0, sag=0.0, seed=1, color="cream"):
    """Row of wonky teeth. [depth] curves the row back round a head, [sag] bends it up or down."""
    rng = random.Random(seed)
    cx, cy, cz = center
    pieces = []
    for i in range(count):
        t = (i + 0.5) / count * 2.0 - 1.0
        tall = height * rng.uniform(0.75, 1.2)
        pieces.append(rot(plate((cx + t * width * 0.5, cy + sag * t * t + rng.uniform(-0.004, 0.004), cz + depth * t * t),
                                (width / count * 0.88, tall), mat(color)),
                          y=-t * 30.0, z=rng.uniform(-6, 6)))
    return pieces


def tongue(points, material="bubblegum"):
    """Lolling tongue with a tip that flops."""
    last = points[-1]
    radii = [0.04] + [0.05] * (len(points) - 2) + [0.03]
    return [tube(points, radii, mat(material), 5),
            plate((last[0], last[1] + 0.04, last[2] - 0.052), (0.012, 0.07), mat("oxblood"))]


def part(name, *pieces):
    """Merges nested piece lists into one body part with its origin on the joint."""
    flat = []

    def walk(items):
        for item in items:
            if isinstance(item, (list, tuple)):
                walk(item)
            else:
                flat.append(item)

    walk(pieces)
    obj = wacky.join(name, flat)
    wacky.set_origin(obj, POS[name])
    return obj


def finish(file_name):
    print("==", file_name)
    wacky.report()
    wacky.export_glb("%s/%s.glb" % (OUT, file_name))
    head = bpy.data.objects["head"]
    head_ko = bpy.data.objects["head_ko"]
    head_ko.hide_render = True
    wacky.preview("%s/%s.png" % (PREVIEWS, file_name))
    head_ko.hide_render = False
    head.hide_render = True
    wacky.preview("%s/%s_ko.png" % (PREVIEWS, file_name))


# --- Gran: tiny, furious, holding a rolling pin and a bag that clearly contains a brick ---

def gran_head(name, ko):
    skin = mat("skin_a")
    frame = mat("tomato")
    hair = mat("ice")
    pieces = [
        wobble(ball("_skull", 0.21, (0, 1.65, 0), skin, squash=(1.14, 1.0, 1.0)), 0.009, 11),
        wobble(ball("_jaw", 0.14, (0, 1.53, -0.04), skin, squash=(1.05, 0.7, 1.0), detail=1), 0.006, 12),
        # Hooked nose, wart included.
        tube([(0, 1.69, -0.2), (0, 1.665, -0.29), (0, 1.61, -0.32), (0, 1.57, -0.28)],
             [0.04, 0.056, 0.042, 0.014], skin, 4),
        # Glasses with wildly unequal lenses.
        cyl("_rim", 0.125, 0.03, (-0.11, 1.71, -0.185), frame, axis="z", verts=8),
        cyl("_rim", 0.09, 0.03, (0.11, 1.71, -0.2), frame, axis="z", verts=8),
        box("_bridge", (0.07, 0.024, 0.025), (0, 1.73, -0.215), frame),
        rot(box("_wing", (0.08, 0.035, 0.03), (-0.2, 1.81, -0.16), frame), z=-40),
        rot(box("_wing", (0.08, 0.035, 0.03), (0.185, 1.78, -0.175), frame), z=40),
        # Brows slammed into the glasses.
        rot(box("_brow", (0.16, 0.04, 0.04), (-0.1, 1.85, -0.18), hair), z=-16),
        rot(box("_brow", (0.14, 0.04, 0.04), (0.1, 1.82, -0.19), hair), z=16),
        # Enormous false teeth, a size too big for the mouth.
        ball("_mouth", 0.11, (0, 1.51, -0.145), mat("oxblood"), squash=(1.25, 0.42, 0.55), detail=1),
        teeth((0, 1.51, -0.215), 0.24, 9, 0.06, depth=0.05, sag=-0.03, seed=3),
        # Blue-rinse tower. Narrower than it was: it has a width limit, unlike her.
        wobble(tube([(0, 1.76, 0.03), (0.0, 1.85, 0.03), (0.0, 1.97, 0.04), (0.01, 2.1, 0.05), (-0.01, 2.2, 0.05),
                     (0.01, 2.28, 0.04), (0.02, 2.34, 0.02)],
                    [0.2, 0.245, 0.22, 0.245, 0.2, 0.18, 0.11], hair, 7), 0.012, 21),
        # Things filed in the hair for later: a fork and a knitting needle, both pointing up.
        # Live pigeon, no ticket. It has seen your papers and it is not convinced.
        wobble(ball("_bird", 0.155, (0.0, 2.44, 0.02), mat("steel"), squash=(1.0, 0.9, 1.3), detail=1), 0.005, 24),
        wobble(ball("_birdhead", 0.095, (0.0, 2.565, -0.085), mat("lilac"), detail=1), 0.003, 25),
        cyl("_beak", 0.008, 0.09, (0.0, 2.535, -0.2), mat("mustard"), axis="z", verts=4, top_radius=0.042),
        eye((-0.05, 2.59, -0.165), 0.052, (0, 0), 0.3, verts=6),
        eye((0.05, 2.58, -0.165), 0.04, (0, 0), 0.32, verts=6),
        cyl("_tail", 0.02, 0.17, (0.0, 2.47, 0.22), mat("iron"), axis="z", verts=4, top_radius=0.09),
        # Brass ear trumpet, jammed in the left ear. The long S of tube drops down past her
        # cheek, and the bell swings 30 degrees outward so it reads as a horn from the front.
        ball("_ear", 0.05, (0.235, 1.65, 0.0), skin, detail=1, squash=(0.5, 1.2, 1)),
    ]
    if ko:
        pieces += [x_eye((-0.11, 1.71, -0.2), 0.1), x_eye((0.11, 1.71, -0.215), 0.07),
                   tongue([(0.03, 1.5, -0.21), (0.06, 1.45, -0.25), (0.1, 1.41, -0.26), (0.12, 1.36, -0.24)])]
    else:
        pieces += [eye((-0.11, 1.71, -0.2), 0.11, (0.25, -0.15), 0.2), eye((0.11, 1.71, -0.215), 0.075, (-0.3, 0.2), 0.28)]
    return part(name, pieces)


def slipper(x, sign, seed):
    """Monster slipper. It bites too."""
    return [
        wobble(ball("_slipper", 0.115, (x + 0.01 * sign, 0.08, -0.08), mat("teal"), squash=(1.0, 0.7, 1.75), detail=1), 0.008, seed),
    ]


def build_gran():
    wacky.reset_scene()
    wacky.REMAP = {"tomato": "oxblood", "teal": "bubblegum", "mustard": "brass", "cream": "bone"}
    cardigan = mat("lilac")
    skin = mat("skin_a")

    part("pelvis",
         wobble(cyl("_skirt", 0.3, 0.56, (0, 0.82, 0), mat("bubblegum"), verts=9, top_radius=0.17), 0.012, 1),
         cyl("_hem", 0.305, 0.05, (0, 0.57, 0), mat("tomato"), verts=9),
         cyl("_waist", 0.18, 0.08, (0, 1.09, 0), cardigan, verts=9, top_radius=0.17))

    # Dowager's hump, and beads the size of golf balls.
    pearls = []
    for i in range(5):
        t = (i - 2) / 2.0
        pearls.append(ball("_pearl", 0.045, (t * 0.14, 1.45 - 0.1 * (1 - t * t), -0.145 - 0.03 * (1 - t * t)),
                           mat("white"), detail=1))
    part("chest",
         wobble(ball("_torso", 0.21, (0, 1.3, 0), cardigan, squash=(1.05, 1.1, 0.82)), 0.012, 2),
         wobble(ball("_hump", 0.15, (0, 1.4, 0.13), cardigan, detail=1), 0.01, 3),
         box("_yoke", (0.44, 0.12, 0.16), (0, 1.47, 0), cardigan, taper=0.75),
         box("_placket", (0.06, 0.34, 0.03), (0, 1.25, -0.175), mat("cream"), taper=0.8),
         # Rosette: bingo champion, and she wants you to know.
         pearls)

    for side, sign in (("l", -1), ("r", 1)):
        x = 0.29 * sign
        part("upper_arm_" + side,
             wobble(ball("_shoulder", 0.095, (x - 0.02 * sign, 1.46, 0), cardigan, detail=1), 0.006, 4),
             cyl("_arm", 0.052, 0.34, (x, 1.34, 0), cardigan, verts=6, top_radius=0.066))

    # Left hand: rolling pin, dented from prior disputes.
    part("forearm_l",
         cyl("_arm", 0.05, 0.3, (-0.29, 1.03, 0), cardigan, verts=6),
         cyl("_cuff", 0.065, 0.05, (-0.29, 0.91, 0), mat("cream"), verts=6),
         # Fist 1.3x bigger than a tiny old lady should own, knuckles clamped over the pin.
         wobble(ball("_hand", 0.13, (-0.31, 0.79, 0), skin, detail=1), 0.008, 5),
         [box("_finger", (0.039, 0.065, 0.078), (-0.382 + i * 0.048, 0.865, -0.12), skin) for i in range(4)],
         wobble(cyl("_pin", 0.08, 0.56, (-0.34, 0.79, -0.02), mat("wood"), axis="z", verts=6), 0.005, 6),
         cyl("_pin_end", 0.032, 0.12, (-0.34, 0.79, -0.35), mat("wood_dark"), axis="z", verts=5),
         cyl("_pin_end", 0.032, 0.12, (-0.34, 0.79, 0.31), mat("wood_dark"), axis="z", verts=5))

    # Right hand: bag labelled MINE, containing an unmistakable house brick.
    part("forearm_r",
         cyl("_arm", 0.05, 0.3, (0.29, 1.03, 0), cardigan, verts=6),
         cyl("_cuff", 0.065, 0.05, (0.29, 0.91, 0), mat("cream"), verts=6),
         wobble(ball("_hand", 0.13, (0.29, 0.8, 0), skin, detail=1), 0.008, 7),
         [box("_finger", (0.039, 0.065, 0.078), (0.218 + i * 0.048, 0.77, -0.115), skin) for i in range(4)],
         tube([(0.27, 0.62, 0.0), (0.27, 0.78, 0.0), (0.33, 0.87, 0.0), (0.49, 0.78, 0.0), (0.53, 0.62, 0.0)],
              0.02, mat("black"), 3),
         wobble(box("_bag", (0.38, 0.28, 0.18), (0.4, 0.48, 0), mat("tomato"), taper=0.88), 0.006, 8),
         rot(box("_brick", (0.2, 0.09, 0.11), (0.42, 0.65, 0.0), mat("rust")), z=-14))

    for side, sign in (("l", -1), ("r", 1)):
        x = 0.11 * sign
        part("thigh_" + side,
             cyl("_thigh", 0.05, 0.42, (x, 0.66, 0), mat("cream"), verts=5, top_radius=0.06))
        part("shin_" + side,
             ball("_knee", 0.062, (x, 0.42, -0.01), mat("cream"), detail=1),
             cyl("_shin", 0.042, 0.36, (x, 0.25, 0), mat("cream"), verts=5),
             cyl("_sock", 0.066, 0.08, (x, 0.235, 0), mat("tomato"), verts=6, top_radius=0.056),
             slipper(x, sign, 9 + int(sign)))

    gran_head("head", False)
    gran_head("head_ko", True)
    finish("gran")


# --- Baron: all chest and moustache, on spindly legs, with a matching tiny dog ---------

def moustache(sign, y, z, reach, material):
    """One side of a curled moustache, spiralling up at the tip. [sign] picks the side."""
    points = [(0.0, y + 0.005, z), (sign * 0.09, y - 0.01, z - 0.012)]
    cx, cy = sign * (reach - 0.07), y + 0.055
    for i in range(6):
        a = -1.57 + i * 1.15
        r = 0.075 * (1.0 - i * 0.11)
        points.append((cx + sign * math.cos(a) * r, cy + math.sin(a) * r, z + 0.05))
    radii = [0.05, 0.058, 0.05, 0.044, 0.036, 0.03, 0.022, 0.012]
    return tube(points, radii, material, 4)


def baron_head(name, ko):
    skin = mat("skin_a")
    tash = mat("black")
    pieces = [
        wobble(ball("_skull", 0.2, (0, 1.69, 0), skin, squash=(1.08, 1.15, 1.0)), 0.007, 31),
        # Chins, in descending order of importance.
        wobble(ball("_chin", 0.145, (0, 1.5, -0.03), skin, squash=(1.25, 0.6, 1.05), detail=1), 0.005, 32),
        wobble(ball("_chin", 0.125, (0, 1.43, -0.02), skin, squash=(1.2, 0.5, 1.05), detail=1), 0.005, 33),
        # Wine-cellar nose.
        wobble(ball("_nose", 0.082, (0, 1.65, -0.235), mat((0.46, 0.15, 0.12)), squash=(1.05, 0.9, 1.05), detail=1), 0.004, 34),
        # Smug row of teeth under the moustache.
        ball("_mouth", 0.09, (0, 1.53, -0.145), mat("oxblood"), squash=(1.3, 0.42, 0.55), detail=1),
        teeth((0, 1.525, -0.205), 0.2, 8, 0.05, depth=0.05, sag=0.018, seed=7, color="white"),
        moustache(-1, 1.585, -0.215, 0.235, tash),
        moustache(1, 1.585, -0.215, 0.235, tash),
        ball("_chop", 0.07, (-0.2, 1.68, 0.02), mat("rust"), squash=(0.5, 1.3, 1.1), detail=1),
        ball("_chop", 0.07, (0.2, 1.68, 0.02), mat("rust"), squash=(0.5, 1.3, 1.1), detail=1),
        # Eyebrows raised at everyone.
        rot(box("_brow", (0.14, 0.045, 0.05), (-0.1, 1.82, -0.17), tash), z=14),
        rot(box("_brow", (0.15, 0.055, 0.05), (0.1, 1.86, -0.15), tash), z=-22),
        cyl("_monocle", 0.105, 0.024, (0.105, 1.74, -0.2), mat("brass"), axis="z", verts=8),
        tube([(0.2, 1.71, -0.18), (0.23, 1.6, -0.14), (0.235, 1.5, -0.07), (0.2, 1.44, 0.0)], 0.012, mat("brass"), 3),
        # Stovepipe hat, slightly too small, bought at a closing-down sale with the tag left on.
        rot(cyl("_brim", 0.205, 0.03, (-0.03, 1.93, 0.03), mat("oxblood"), verts=7), z=9),
        rot(wobble(cyl("_hat", 0.125, 0.38, (-0.06, 2.12, 0.03), mat("oxblood"), verts=7, top_radius=0.16), 0.006, 37), z=9),
        # Plume off a much better hat.
        tube([(0.05, 2.0, 0.13), (0.12, 2.2, 0.15), (0.185, 2.38, 0.13), (0.24, 2.47, 0.06)],
             [0.03, 0.06, 0.05, 0.012], mat("bubblegum"), 4),
    ]
    if ko:
        pieces += [x_eye((0.105, 1.74, -0.22), 0.09), x_eye((-0.1, 1.74, -0.18), 0.065),
                   tongue([(-0.03, 1.5, -0.2), (-0.06, 1.45, -0.25), (-0.09, 1.4, -0.27), (-0.12, 1.36, -0.25)], "tomato")]
    else:
        pieces += [eye((0.105, 1.74, -0.22), 0.095, (-0.15, -0.2), 0.16),
                   eye((-0.1, 1.74, -0.18), 0.06, (0.2, 0.0), 0.42)]
    return part(name, pieces)


def baron_dog():
    """Tiny lap dog with the same moustache, hat and contempt as its owner."""
    x, y, z = -0.34, 0.74, -0.3
    k = 1.5
    fur = mat("bubblegum")

    def at(dx, dy, dz):
        return (x + dx * k, y + dy * k, z + dz * k)

    return [
        # The glove reaches out and presents him, like a prize nobody asked for.
        tube([(-0.29, 0.8, -0.04), (-0.31, 0.72, -0.18), (x, y - 0.11, z + 0.02)], [0.075, 0.07, 0.06], mat("white"), 4),
        wobble(ball("_dog", 0.115 * k, at(0, 0, 0.02), fur, squash=(0.95, 0.85, 1.2), detail=1), 0.01, 41),
        wobble(ball("_doghead", 0.09 * k, at(0, 0.11, -0.09), fur, detail=1), 0.006, 42),
        ball("_dogear", 0.045 * k, at(-0.09, 0.09, -0.08), mat("oxblood"), detail=1, squash=(0.6, 1.5, 0.9)),
        ball("_dogear", 0.045 * k, at(0.09, 0.09, -0.08), mat("oxblood"), detail=1, squash=(0.6, 1.5, 0.9)),
        tube([at(-0.13, 0.13, -0.15), at(-0.07, 0.075, -0.185), at(0, 0.085, -0.19), at(0.07, 0.075, -0.185), at(0.13, 0.13, -0.15)],
             [0.012, 0.032, 0.038, 0.032, 0.012], mat("black"), 4),
        eye(at(-0.035, 0.15, -0.165), 0.03, (0, 0), 0.5, verts=5),
        eye(at(0.04, 0.15, -0.165), 0.048, (0, 0), 0.25, verts=6),
        cyl("_doghat", 0.058 * k, 0.02, at(0, 0.19, -0.09), mat("oxblood"), verts=5),
        cyl("_doghat", 0.034 * k, 0.14, at(0, 0.245, -0.09), mat("oxblood"), verts=5),
    ]


def build_baron():
    wacky.reset_scene()
    wacky.REMAP = {"tomato": "oxblood", "teal": "oxblood", "bubblegum": "bone", "rust": "black"}
    coat = mat("navy")

    part("pelvis",
         wobble(ball("_waist", 0.2, (0, 1.0, 0), coat, squash=(1.1, 0.75, 0.95), detail=1), 0.006, 1),
         ball("_breech", 0.17, (0, 0.92, 0), mat("mustard"), squash=(1.1, 0.75, 0.95), detail=1),
         # Long coat tails, frayed on one side.
         rot(box("_tail", (0.15, 0.5, 0.04), (-0.09, 0.74, 0.19), coat, taper=1.4), x=-5, z=-4),
         rot(box("_tail", (0.15, 0.44, 0.04), (0.09, 0.77, 0.19), coat, taper=1.4), x=-5, z=6))

    def medal(x, y, color):
        return [
            rot(plate((x, y + 0.055, -0.3), (0.055, 0.08), mat("tomato" if color == "brass" else "teal")), y=-x * 90),
            rot(cyl("_medal", 0.042, 0.02, (x, y, -0.3), mat(color), axis="z", verts=6), y=-x * 90),
        ]

    part("chest",
         # Barrel chest, mostly air and opinions.
         wobble(ball("_torso", 0.29, (0, 1.33, -0.05), coat, squash=(1.0, 0.98, 0.9)), 0.008, 2),
         box("_shirt", (0.1, 0.46, 0.06), (0, 1.3, -0.29), mat("cream"), taper=1.6),
         rot(box("_sash", (0.1, 0.7, 0.05), (0.03, 1.27, -0.325), mat("tomato")), z=33, x=4),
         medal(-0.2, 1.45, "brass"))

    for side, sign in (("l", -1), ("r", 1)):
        x = 0.29 * sign
        part("upper_arm_" + side,
             cyl("_arm", 0.068, 0.32, (x, 1.33, 0), coat, verts=6, top_radius=0.08),
             wobble(box("_epaulette", (0.24, 0.05, 0.19), (x + 0.03 * sign, 1.53, 0), mat("mustard")), 0.005, 3))

    part("forearm_l",
         cyl("_arm", 0.06, 0.3, (-0.29, 1.03, 0), coat, verts=6),
         cyl("_cuff", 0.08, 0.08, (-0.29, 0.92, 0), mat("mustard"), verts=6),
         wobble(ball("_glove", 0.105, (-0.29, 0.82, -0.02), mat("white"), detail=1), 0.008, 4),
         baron_dog())

    part("forearm_r",
         cyl("_arm", 0.06, 0.3, (0.29, 1.03, 0), coat, verts=6),
         cyl("_cuff", 0.08, 0.08, (0.29, 0.92, 0), mat("mustard"), verts=6),
         wobble(ball("_glove", 0.12, (0.29, 0.8, -0.02), mat("white"), detail=1), 0.008, 5),
         [tube([(0.235 + i * 0.038, 0.74, -0.06), (0.235 + i * 0.038, 0.66, -0.08)], 0.024, mat("white"), 4) for i in range(4)],
         # Silver-topped stick he has never once used for anything.
         tube([(0.33, 0.78, -0.03), (0.34, 0.5, -0.06), (0.36, 0.08, -0.1)], 0.02, mat("wood_dark"), 4),
         ball("_knob", 0.045, (0.33, 0.87, -0.02), mat("steel"), detail=1))

    for side, sign in (("l", -1), ("r", 1)):
        x = 0.11 * sign
        part("thigh_" + side,
             # Riding breeches inflated well past any need.
             wobble(ball("_breech", 0.195, (x + 0.095 * sign, 0.66, 0), mat("mustard"), squash=(1.05, 1.2, 1.0)), 0.009, 6),
             cyl("_top", 0.06, 0.1, (x, 0.82, 0), mat("mustard"), verts=6))
        part("shin_" + side,
             # Stick legs in tall boots with gigantic toes.
             cyl("_boot", 0.055, 0.34, (x, 0.28, 0), mat("black"), verts=6, top_radius=0.08),
             wobble(ball("_toe", 0.105, (x, 0.085, -0.12), mat("black"), squash=(1.1, 0.78, 2.0), detail=1), 0.006, 7),
             box("_heel", (0.12, 0.07, 0.1), (x, 0.035, 0.05), mat("wood_dark")))

    baron_head("head", False)
    baron_head("head_ko", True)
    finish("baron")


# --- Smuggler: sweaty, sideways, and certainly not hiding a chicken --------------------

def sweat_run(sign, z):
    """Three fat linked drops running off the hat brim and down the temple."""
    points = [(sign * 0.15, 1.85, z), (sign * 0.17, 1.8, z), (sign * 0.178, 1.76, z), (sign * 0.183, 1.715, z - 0.005),
              (sign * 0.185, 1.68, z - 0.005), (sign * 0.188, 1.63, z), (sign * 0.188, 1.585, z)]
    return tube(points, [0.012, 0.036, 0.012, 0.04, 0.012, 0.043, 0.008], mat("ice"), 5)


def smuggler_head(name, ko):
    skin = mat("skin_sick")
    pieces = [
        wobble(ball("_skull", 0.19, (0, 1.67, -0.02), skin, squash=(0.92, 1.1, 1.0)), 0.009, 51),
        wobble(ball("_jaw", 0.115, (0.03, 1.53, -0.06), skin, squash=(1.0, 0.8, 1.0), detail=1), 0.006, 52),
        # A long, nervous nose, pointing where he wishes he was.
        tube([(0, 1.68, -0.19), (0.05, 1.65, -0.28), (0.12, 1.6, -0.33), (0.2, 1.585, -0.34)],
             [0.04, 0.05, 0.04, 0.018], skin, 4),
        # Eye bags and a mouth of crooked teeth, one gold.
        rot(plate((-0.085, 1.645, -0.188), (0.12, 0.05), mat("lilac")), z=-6),
        rot(plate((0.085, 1.645, -0.188), (0.12, 0.05), mat("lilac")), z=6),
        rot(ball("_mouth", 0.09, (0.04, 1.54, -0.145), mat("black"), squash=(1.2, 0.33, 0.5), detail=1), z=9),
        rot(plate((0.095, 1.56, -0.2), (0.04, 0.055), mat("brass", emission=0.6, rough=0.3, metal=0.6)), z=9),
        teeth((0.015, 1.535, -0.198), 0.12, 5, 0.045, depth=0.02, sag=-0.012, seed=9, color="bone"),
        # Three-day stubble.
        # Fedora, brim yanked down as far as physics allows.
        rot(wobble(cyl("_brim", 0.262, 0.03, (0, 1.855, -0.03), mat("wood_dark"), verts=8), 0.008, 53), x=-8, z=5),
        rot(cyl("_crown", 0.18, 0.2, (0.0, 1.965, 0.0), mat("wood_dark"), verts=7, top_radius=0.14), x=-5, z=5),
        # Marked playing card in the hat band.
        # Flying sweat, about a pint a minute.
    ]
    if ko:
        pieces += [x_eye((-0.085, 1.72, -0.17), 0.08), x_eye((0.085, 1.72, -0.175), 0.068),
                   tongue([(0.05, 1.53, -0.19), (0.09, 1.49, -0.23), (0.13, 1.45, -0.245), (0.16, 1.41, -0.22)], "bubblegum")]
    else:
        # Both pupils slammed to one side, checking who is behind him.
        pieces += [eye((-0.085, 1.72, -0.17), 0.085, (0.42, 0.0), 0.3), eye((0.085, 1.72, -0.175), 0.072, (0.42, 0.12), 0.34)]
    return part(name, pieces)


def chicken():
    """Smuggled hen peering out of the coat, wearing a label that fools nobody."""
    x, y, z = 0.0, 1.355, -0.24
    feather = mat("white")
    return [
        tube([(0, 1.2, -0.1), (0, 1.24, -0.17), (x, y - 0.02, z + 0.03)], [0.08, 0.065, 0.05], feather, 5),
        wobble(ball("_head", 0.09, (x, y + 0.03, z), feather), 0.006, 61),
        ball("_comb", 0.036, (x, y + 0.135, z - 0.03), mat("tomato"), detail=1),
        ball("_comb", 0.044, (x, y + 0.145, z + 0.025), mat("tomato"), detail=1),
        cyl("_beak", 0.006, 0.08, (x, y + 0.01, z - 0.12), mat("mustard"), axis="z", verts=5, top_radius=0.042),
        ball("_wattle", 0.03, (x, y - 0.055, z - 0.08), mat("tomato"), detail=1, squash=(0.8, 1.4, 0.8)),
        eye((x - 0.05, y + 0.06, z - 0.075), 0.042, (0.2, -0.2), 0.3, verts=6),
        eye((x + 0.052, y + 0.055, z - 0.075), 0.033, (-0.3, 0.3), 0.4, verts=6),
    ]


def popped_collar(material):
    """Open crooked ring round the neck, flaring out as it rises, with an uneven top edge."""
    sections = []
    for angle, top in ((-130, 1.76), (-85, 1.7), (-40, 1.75), (10, 1.68), (55, 1.72), (95, 1.66), (130, 1.62)):
        s, c = math.sin(math.radians(angle)), math.cos(math.radians(angle))
        ring = ((0.19, 1.5), (0.24, 1.5), (0.315, top), (0.27, top))
        sections.append([(s * r, y, c * r - 0.02) for r, y in ring])
    return wobble(loft(sections, material), 0.006, 4)


def build_smuggler():
    wacky.reset_scene()
    wacky.REMAP = {"tomato": "oxblood", "teal": "steel", "lilac": "wood_dark", "navy": "wood_dark"}
    coat = mat("wood")
    lining = mat("tomato")
    skin = mat("skin_sick")

    part("pelvis",
         # Coat skirt reaching the knees, split at the front.
         wobble(cyl("_skirt", 0.27, 0.55, (0, 0.84, 0), coat, verts=8, top_radius=0.2), 0.012, 1),
         cyl("_belt", 0.215, 0.06, (0, 1.08, 0), mat("wood_dark"), verts=8))

    watches = ((-0.13, 1.46, "brass"), (-0.13, 1.36, "steel"), (-0.13, 1.26, "brass"),
               (0.13, 1.46, "steel"), (0.13, 1.36, "brass"), (0.13, 1.26, "steel"))
    part("chest",
         wobble(box("_torso", (0.46, 0.5, 0.3), (0, 1.32, 0), coat, taper=1.1, bevel=0.03), 0.01, 3),
         # Coat held open, showing the red lining and the stock.
         plate((0, 1.31, -0.16), (0.32, 0.47), lining),
         # Lapels: slept in, pulled about, and not on speaking terms.
         loft([[(-0.1, 1.58, -0.2), (-0.25, 1.57, -0.17), (-0.25, 1.55, -0.12), (-0.1, 1.57, -0.14)],
               [(-0.185, 1.34, -0.22), (-0.275, 1.31, -0.17), (-0.26, 1.3, -0.12), (-0.185, 1.33, -0.15)],
               [(-0.175, 1.08, -0.2), (-0.25, 1.07, -0.17), (-0.24, 1.07, -0.12), (-0.175, 1.08, -0.15)]], coat),
         loft([[(0.12, 1.52, -0.19), (0.27, 1.6, -0.19), (0.25, 1.57, -0.12), (0.12, 1.52, -0.13)],
               [(0.195, 1.3, -0.215), (0.285, 1.33, -0.16), (0.27, 1.31, -0.11), (0.195, 1.3, -0.15)],
               [(0.18, 1.08, -0.19), (0.26, 1.1, -0.16), (0.25, 1.09, -0.11), (0.18, 1.08, -0.14)]], coat),
         # Popped collar, doing the work of a false identity. One side has given up.
         popped_collar(coat),
         # Back flap, so he is not just a box.
         rot(box("_stormflap", (0.5, 0.2, 0.04), (0, 1.46, 0.16), mat("wood_dark")), x=8),
         chicken(),
         rot(box("_label", (0.28, 0.16, 0.012), (0, 1.16, -0.245), mat("cream")), z=-4),
         rot(text("NOT A", (0, 1.195, -0.255), 0.055, mat("black")), z=-4),
         rot(text("CHICKEN", (0, 1.132, -0.255), 0.055, mat("black")), z=-4))

    for side, sign in (("l", -1), ("r", 1)):
        x = 0.29 * sign
        part("upper_arm_" + side,
             wobble(ball("_pad", 0.105, (x, 1.47, 0), coat, squash=(1.25, 0.8, 1.1), detail=1), 0.008, 6),
             cyl("_arm", 0.07, 0.32, (x, 1.33, 0), coat, verts=6, top_radius=0.082))

    # Left sleeve shoved up: forearm stacked with watches for sale.
    part("forearm_l",
         cyl("_cuff", 0.085, 0.1, (-0.29, 1.15, 0), coat, verts=6),
         cyl("_arm", 0.05, 0.28, (-0.29, 1.0, 0), skin, verts=5, top_radius=0.056),
         wobble(ball("_hand", 0.105, (-0.29, 0.81, -0.01), skin, detail=1), 0.008, 7),
         [box("_finger", (0.036, 0.1, 0.04), (-0.345 + i * 0.038, 0.73, -0.07), skin, taper=0.8) for i in range(4)])

    # Right sleeve: stolen sausages making a run for it, swinging clear of the hand and tied
    # off with twine, so each link reads as a sausage from across the carriage.
    meat = mat((0.42, 0.17, 0.13))
    joints = []
    for i in range(5):
        t = i / 4.0
        joints.append((0.345 + 0.1 * math.sin(t * 2.6), 0.79 - t * 0.66, -0.06 - 0.05 * math.sin(t * 3.1)))
    sausages = []
    for a, b in zip(joints, joints[1:]):
        rings = [tuple(a[j] + (b[j] - a[j]) * k for j in range(3)) for k in (0.0, 0.16, 0.5, 0.84, 1.0)]
        sausages.append(tube(rings, [0.016, 0.05, 0.056, 0.05, 0.016], meat, 5))
    sausages += [box("_twine", (0.05, 0.05, 0.05), point, mat("cream")) for point in joints]
    part("forearm_r",
         cyl("_arm", 0.08, 0.3, (0.29, 1.03, 0), coat, verts=6, top_radius=0.07),
         cyl("_cuff", 0.092, 0.06, (0.29, 0.88, 0), mat("wood_dark"), verts=6),
         wobble(ball("_hand", 0.095, (0.27, 0.8, -0.02), skin, detail=1), 0.007, 8),
         [box("_finger", (0.036, 0.09, 0.04), (0.215 + i * 0.038, 0.76, -0.1), skin, taper=0.8) for i in range(4)],
         sausages)

    for side, sign in (("l", -1), ("r", 1)):
        x = 0.11 * sign
        part("thigh_" + side,
             cyl("_leg", 0.06, 0.42, (x, 0.66, 0), mat("navy"), verts=6, top_radius=0.075))

    part("shin_l",
         # Shin runs 3 cm up inside the thigh, with a knee bead, so no light shows at the joint.
         cyl("_leg", 0.055, 0.42, (-0.11, 0.27, 0), mat("navy"), verts=6, top_radius=0.06),
         ball("_knee", 0.072, (-0.11, 0.45, -0.005), mat("navy"), detail=1),
         # Polished shoe, stolen.
         wobble(ball("_shoe", 0.105, (-0.11, 0.085, -0.11), mat("oxblood"), squash=(1.1, 0.75, 1.9), detail=1), 0.006, 9))
    part("shin_r",
         cyl("_leg", 0.055, 0.42, (0.11, 0.27, 0), mat("navy"), verts=6, top_radius=0.06),
         ball("_knee", 0.072, (0.11, 0.45, -0.005), mat("navy"), detail=1),
         # Other shoe, also stolen, from a much poorer man. Toes out, sole flapping.
         rot(wobble(ball("_shoe", 0.11, (0.11, 0.095, -0.08), mat("wood_dark"), squash=(1.1, 0.78, 1.5), detail=1), 0.012, 10), x=16),
         # Sole hinged at the heel, gaping like a mouth, with the nails for teeth.
         loft([[(0.04, 0.07, 0.03), (0.18, 0.07, 0.03), (0.18, 0.0, 0.03), (0.04, 0.0, 0.03)],
               [(0.005, 0.04, -0.12), (0.215, 0.04, -0.12), (0.215, 0.0, -0.12), (0.005, 0.0, -0.12)],
               [(0.03, 0.022, -0.29), (0.19, 0.022, -0.29), (0.19, 0.0, -0.29), (0.03, 0.0, -0.29)]], mat("black")),
         [ball("_toe", 0.036, (0.065 + i * 0.05, 0.07, -0.235), mat("skin_a"), detail=1) for i in range(3)],
         ball("_toe", 0.046, (0.035, 0.08, -0.24), mat("skin_a"), detail=1))

    smuggler_head("head", False)
    smuggler_head("head_ko", True)
    finish("smuggler")


build_gran()
build_baron()
build_smuggler()
print("done")
