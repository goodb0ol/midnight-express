"""Builds three wacky passengers: intern, stoker and opera.

  blender.exe --background --python blender/build_passengers_b.py

Optional names after "--" build a subset, for example:
  blender.exe --background --python blender/build_passengers_b.py -- stoker

All numbers are Godot coordinates. Every part is built in full-body world space, joined,
then has its origin moved to its joint, so numbers line up with docs/ART_BRIEF.md.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import wacky
from wacky import box, cyl, gv, mat

JOINTS = {
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
HEAD_Y = JOINTS["head"][1]
MAX_TRIS = 2800
SOOT = (0.11, 0.1, 0.1)
SMOKE = (0.25, 0.25, 0.27)


def h(x, y, z):
    """Point relative to the head joint."""
    return (x, HEAD_Y + y, z)


def ball(name, radius, center=(0, 0, 0), material=None, squash=(1, 1, 1), detail=0):
    """Faceted ball. detail 1 is 20 tris, 2 is 80, and the default 0 is a 48-tri in-between."""
    if detail:
        return wacky.ball(name, radius, center, material, squash, detail)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=radius)
    bmesh.ops.scale(bm, vec=wacky.gs(squash), verts=bm.verts)
    return wacky._finish(name, bm, center, material)


def plate(width, height, center, material, facing="-z"):
    """One-sided two-tri card, for teeth, stitches and stickers on a surface."""
    a, b = width * 0.5, height * 0.5
    corners = [(-a, 0, -b), (-a, 0, b), (a, 0, b), (a, 0, -b)]
    if facing != "-z":
        corners.reverse()
    mesh = bpy.data.meshes.new("t")
    mesh.from_pydata(corners, [], [(0, 1, 2, 3)])
    mesh.materials.append(material)
    obj = bpy.data.objects.new("t", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = gv(*center)
    return obj


def tilt(obj, x=0.0, y=0.0, z=0.0):
    """Rotates around the object's own centre, in degrees about Godot axes."""
    obj.rotation_euler = (math.radians(x), -math.radians(z), math.radians(y))
    return obj


def limb(a, b, r1, r2, material, verts=6):
    """Tapered bar from Godot point [a] to [b]."""
    a, b = Vector(a), Vector(b)
    offset = b - a
    obj = cyl("t", r1, offset.length, tuple((a + b) * 0.5), material, "y", verts, r2)
    direction = gv(*offset).normalized()
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction)
    return obj


def squash_mesh(obj, x=1.0, y=1.0, z=1.0):
    """Scales mesh data on Godot axes, around the object's origin."""
    obj.data.transform(Matrix.Diagonal((x, z, y, 1.0)))
    obj.data.update()
    return obj


def frill(obj, amount=0.8):
    """Pulls every other rim vertex inward, turning a many-sided disc into a star-edged ruff."""
    for vert in obj.data.vertices:
        angle = math.atan2(vert.co.y, vert.co.x)
        if round(angle / (math.pi * 2 / 12)) % 2:
            vert.co.x *= amount
            vert.co.y *= amount
    obj.data.update()
    return obj


def label(text, size, center, material, facing="-z", angle=0.0):
    """Flat mesh text reading correctly from the [facing] side. Heavy font, low resolution."""
    curve = bpy.data.curves.new("t", "FONT")
    curve.body = text
    curve.size = size
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.resolution_u = 1
    try:
        curve.font = bpy.data.fonts.load("C:/Windows/Fonts/impact.ttf", check_existing=True)
    except (OSError, RuntimeError):
        pass  # Blender's built-in font still gives readable text.
    temp = bpy.data.objects.new("t", curve)
    bpy.context.scene.collection.objects.link(temp)
    graph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(temp.evaluated_get(graph))
    bpy.data.objects.remove(temp, do_unlink=True)
    bpy.data.curves.remove(curve)
    turn = Matrix.Rotation(math.pi / 2, 4, "X")
    if facing == "-z":
        turn = Matrix.Rotation(math.pi, 4, "Z") @ turn
    mesh.transform(turn @ Matrix.Rotation(math.radians(angle), 4, "Z"))
    mesh.materials.clear()
    mesh.materials.append(material)
    obj = bpy.data.objects.new("t", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = gv(*center)
    return obj


def eye(x, y, z, r, look=(0.0, 0.0), pupil=0.26, detail=0):
    """Staring eyeball. [look] shifts the tiny pupil across the ball. Front is -Z."""
    out = Vector((look[0], look[1], -1.0)).normalized() * r * 0.92
    return [
        ball("t", r, (x, y, z), mat("white", rough=0.3), detail=detail),
        ball("t", r * pupil, (x + out.x, y + out.y, z + out.z), mat("black"), detail=1),
    ]


def x_eye(x, y, z, r, detail=0):
    """Eyeball crossed out with two chunky bars."""
    bars = []
    for sign in (1, -1):
        bar = plate(r * 2.0, r * 0.46, (x, y, z - r * 1.03), mat("black"))
        bars.append(tilt(bar, z=45 * sign))
    return [ball("t", r, (x, y, z), mat("white", rough=0.3), detail=detail)] + bars


def teeth(cx, y, z, count, width, height, gold=-1):
    """Row of slightly crooked teeth centred on [cx]. Index [gold] is a gold tooth."""
    parts = []
    for i in range(count):
        tooth_mat = mat("brass", rough=0.3, metal=0.6) if i == gold else mat("white", rough=0.4)
        x = cx + (i - (count - 1) * 0.5) * width
        lift = ((i * 37) % 5 - 2) * height * 0.07
        parts.append(tilt(plate(width * 0.86, height, (x, y + lift, z), tooth_mat), z=(i * 53) % 9 - 4))
    return parts


def hand_fingers(x, y, z, material, r=0.022, spread=0.05, length=0.1):
    """Three chunky sausages hanging off a hand."""
    return [limb((x + i * spread, y, z), (x + i * spread * 1.2, y - length, z - 0.01), r, r * 0.8, material, verts=4)
            for i in (-1, 0, 1)]


def build(parts, wobble=0.004):
    """Joins each part, moves the origin to its joint, nudges the verts, checks the count."""
    objects = []
    for index, name in enumerate(JOINTS):
        obj = wacky.join(name, parts[name])
        wacky.set_origin(obj, JOINTS[name])
        wacky.wobble(obj, wobble, seed=index + 1)
        objects.append(obj)
    return objects


def show_ko_beside(objects):
    """Preview only: slides head_ko clear of the body so both heads can be seen."""
    for obj in objects:
        if obj.name == "head_ko":
            obj.location.x += 0.75


def view_from_front(objects):
    """Preview only: wacky.VIEWS "front" looks from +Z, so turn the figure to face it."""
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for obj in objects:
        obj.parent = pivot
    pivot.rotation_euler = (0, 0, math.pi)
    bpy.context.view_layer.update()
    return pivot


def finish(name, parts):
    objects = build(parts)
    total = wacky.report(objects)
    if total > MAX_TRIS:
        print("OVER BUDGET", name, total)
    wacky.export_glb("assets/models/passengers/%s.glb" % name)
    show_ko_beside(objects)
    pivot = view_from_front(objects)
    wacky.preview("assets/previews/passengers/%s.png" % name)
    heads = [o for o in objects if o.name in ("head", "head_ko")]
    wacky.clear_except(heads + [pivot])
    bpy.context.view_layer.update()
    wacky.preview("assets/previews/passengers/%s_heads.png" % name)


# ---------------------------------------------------------------- intern


def intern_head(ko):
    skin = mat("skin_sick")
    hair = mat("wood_dark")
    black = mat("black")
    out = [
        limb(h(0, -0.27, 0), h(0, -0.04, 0), 0.05, 0.05, skin),
        ball("t", 0.2, h(0, 0.08, 0), skin, squash=(1.08, 1.22, 0.95)),
        ball("t", 0.08, h(-0.235, 0.05, 0), skin, squash=(0.42, 1.0, 0.75), detail=1),
        ball("t", 0.08, h(0.235, 0.09, 0), skin, squash=(0.42, 1.25, 0.75), detail=1),
    ]
    # Nose: a long sad wedge.
    out.append(limb(h(0.01, 0.08, -0.17), h(0.06, 0.0, -0.3), 0.04, 0.05, skin))
    out.append(ball("t", 0.058, h(0.065, -0.01, -0.31), skin, detail=1))
    # Mismatched bug eyes behind enormous taped spectacles.
    left = (-0.1, HEAD_Y + 0.13, -0.17, 0.125)
    right = (0.105, HEAD_Y + 0.09, -0.175, 0.095)
    if ko:
        out += x_eye(*left) + x_eye(*right)
    else:
        out += eye(*left, look=(-0.3, 0.25), pupil=0.2) + eye(*right, look=(0.35, -0.2), pupil=0.24)
    frame_tilt = -9 if ko else 3
    frames = [
        cyl("t", 0.155, 0.03, (left[0], left[1], -0.2), black, "z", 8),
        cyl("t", 0.125, 0.03, (right[0], right[1], -0.2), black, "z", 8),
        box("t", (0.09, 0.04, 0.035), h(0.0, 0.12, -0.25), mat("white")),
        box("t", (0.03, 0.03, 0.25), h(-0.25, 0.12, -0.07), black),
        box("t", (0.03, 0.03, 0.25), h(0.225, 0.12, -0.07), black),
    ]
    for obj in frames[:3]:
        tilt(obj, z=frame_tilt)
    out += frames
    if ko:
        out.append(box("t", (0.2, 0.07, 0.03), h(0, -0.1, -0.15), black))
        out.append(box("t", (0.09, 0.2, 0.03), h(0.04, -0.2, -0.17), mat("bubblegum")))
        out.append(ball("t", 0.05, h(0.045, -0.3, -0.17), mat("bubblegum"), squash=(1.0, 0.8, 0.6), detail=1))
        # Cartoon lump; the three terrified hairs give up and lie down.
        out.append(ball("t", 0.08, h(-0.09, 0.33, -0.05), mat("skin_sick"), squash=(1, 0.9, 1), detail=1))
        for offset in (-0.03, 0.02, 0.07):
            out.append(limb(h(0.02 + offset, 0.31, 0), h(0.17 + offset, 0.25, -0.03), 0.018, 0.006, hair, verts=4))
    else:
        out.append(box("t", (0.27, 0.085, 0.03), h(-0.01, -0.13, -0.145), black))
        out += teeth(-0.01, HEAD_Y - 0.13, -0.165, 6, 0.042, 0.065)
        # Three hairs standing bolt upright in terror.
        out.append(limb(h(-0.04, 0.29, 0), h(-0.1, 0.5, 0.02), 0.02, 0.006, hair, verts=4))
        out.append(limb(h(0.01, 0.31, 0), h(0.02, 0.58, -0.02), 0.022, 0.006, hair, verts=4))
        out.append(limb(h(0.06, 0.29, 0), h(0.15, 0.47, 0.02), 0.02, 0.006, hair, verts=4))
    # Sweat, flying off in sheets.
    return out


def intern():
    wacky.reset_scene()
    wacky.REMAP = {"mustard": "navy", "teal": "navy", "bubblegum": "tomato"}
    skin = mat("skin_sick")
    shirt = mat("cream")
    vest = mat("mustard")
    legs = mat("navy")
    tie = mat("tomato")
    shoe = mat("wood_dark")
    paper = mat("white")

    chest = [
        box("t", (0.3, 0.42, 0.2), (0, 1.31, 0), shirt, taper=1.12),
        box("t", (0.33, 0.31, 0.225), (0, 1.25, 0), vest, taper=1.06),
        tilt(box("t", (0.09, 0.08, 0.02), (-0.06, 1.48, -0.11), paper), z=-20),
        tilt(box("t", (0.09, 0.08, 0.02), (0.06, 1.48, -0.11), paper), z=20),
        # The biggest tie in middle management, swung to one side.
        box("t", (0.075, 0.08, 0.045), (0, 1.46, -0.135), tie, taper=1.4),
        tilt(box("t", (0.2, 0.52, 0.025), (0.035, 1.16, -0.145), tie, taper=0.42), z=-6),
        tilt(box("t", (0.03, 0.09, 0.03), (0.045, 1.26, -0.165), mat("steel")), z=-6),
    ]
    pelvis = [
        box("t", (0.3, 0.22, 0.2), (0, 0.98, 0), legs),
        box("t", (0.33, 0.055, 0.225), (0, 1.08, 0), shoe),
        box("t", (0.09, 0.075, 0.03), (0, 1.08, -0.115), mat("brass", rough=0.3, metal=0.6)),
    ]

    def arm(side):
        s = side
        upper = [
            ball("t", 0.085, (s * 0.235, 1.5, 0), shirt, detail=1),
            limb((s * 0.25, 1.5, 0), (s * 0.3, 1.25, 0), 0.06, 0.085, shirt),
            limb((s * 0.3, 1.27, 0), (s * 0.3, 1.18, 0), 0.036, 0.036, skin),
        ]
        fore = [
            limb((s * 0.3, 1.19, 0), (s * 0.3, 0.92, 0), 0.036, 0.03, skin),
            ball("t", 0.09, (s * 0.3, 0.86, 0), skin, squash=(0.9, 1.1, 1)),
        ]
        return upper, fore

    upper_l, fore_l = arm(-1)
    upper_r, fore_r = arm(1)
    # Left hand: clipboard held up as a shield, with his only honest paperwork.
    fore_l += [
        box("t", (0.32, 0.4, 0.03), (-0.3, 0.87, -0.115), mat("wood")),
        box("t", (0.26, 0.31, 0.012), (-0.3, 0.85, -0.135), paper),
        box("t", (0.11, 0.05, 0.03), (-0.3, 1.05, -0.14), mat("steel")),
        label("HELP", 0.14, (-0.3, 0.87, -0.143), mat("tomato"), angle=-5),
        limb((-0.33, 0.78, -0.145), (-0.22, 0.75, -0.145), 0.02, 0.02, skin, verts=4),
    ]
    # Right hand: coffee, leaving the cup in fear.
    coffee = mat("wood_dark")
    fore_r += [
        limb((0.3, 0.76, -0.1), (0.3, 0.92, -0.1), 0.06, 0.08, paper, verts=8),
        ball("t", 0.09, (0.34, 0.95, -0.1), coffee, squash=(1.1, 0.55, 1.1), detail=1),
        ball("t", 0.04, (0.42, 1.03, -0.1), coffee, detail=1),
        ball("t", 0.03, (0.46, 0.97, -0.08), coffee, detail=1),
    ] + hand_fingers(0.3, 0.88, -0.14, skin, r=0.02, spread=0.04, length=0.09)

    # Knock-kneed: the origins stay on the joints, the shapes lean in.
    def leg(side, sock):
        s = side
        thigh = [limb((s * 0.13, 0.88, 0), (s * 0.07, 0.45, 0), 0.085, 0.06, legs)]
        shin = [
            limb((s * 0.07, 0.46, 0), (s * 0.13, 0.2, 0), 0.06, 0.07, legs),
            limb((s * 0.13, 0.22, 0), (s * 0.13, 0.08, 0), 0.04, 0.042, mat(sock)),
            box("t", (0.17, 0.09, 0.36), (s * 0.14, 0.06, -0.1), shoe),
            ball("t", 0.1, (s * 0.145, 0.07, -0.29), shoe, squash=(1, 0.75, 1.1)),
            box("t", (0.19, 0.03, 0.42), (s * 0.14, 0.015, -0.13), mat("black")),
            box("t", (0.09, 0.03, 0.08), (s * 0.14, 0.115, -0.13), mat("brass", rough=0.3, metal=0.6)),
        ]
        return thigh, shin

    thigh_l, shin_l = leg(-1, "teal")
    thigh_r, shin_r = leg(1, "bubblegum")

    finish("intern", {
        "pelvis": pelvis, "chest": chest,
        "head": intern_head(False), "head_ko": intern_head(True),
        "upper_arm_l": upper_l, "forearm_l": fore_l, "upper_arm_r": upper_r, "forearm_r": fore_r,
        "thigh_l": thigh_l, "shin_l": shin_l, "thigh_r": thigh_r, "shin_r": shin_r,
    })


# ---------------------------------------------------------------- stoker


def stoker_head(ko):
    soot = mat(SOOT)
    beard = mat("coal")
    cap_mat = mat("iron")
    brass = mat("brass", rough=0.3, metal=0.6)
    skull = box("t", (0.46, 0.4, 0.42), h(0, 0.03, 0), soot, taper=0.76, bevel=0.03)
    out = [
        limb(h(0, -0.28, 0), h(0, -0.05, 0), 0.15, 0.15, soot),
        skull,
        ball("t", 0.26, h(0, -0.19, -0.07), beard, squash=(1.03, 0.8, 0.72)),
        limb(h(0, -0.3, -0.12), h(0.05, -0.56, -0.17), 0.13, 0.01, beard, verts=5),
        ball("t", 0.09, h(0, -0.01, -0.27), mat("tomato", rough=0.5), squash=(1.2, 0.9, 1)),
        # The only clean skin on him: where the goggles sit.
        cyl("t", 0.1, 0.03, h(-0.125, 0.09, -0.215), mat("skin_a"), "z", 8),
        cyl("t", 0.12, 0.03, h(0.125, 0.09, -0.215), mat("skin_a"), "z", 8),
        tilt(box("t", (0.19, 0.05, 0.05), h(-0.125, 0.205, -0.225), beard), z=-14),
        tilt(box("t", (0.2, 0.05, 0.05), h(0.13, 0.225, -0.225), beard), z=10),
        ball("t", 0.05, h(-0.222, -0.02, 0), soot, detail=1),
        ball("t", 0.05, h(0.222, -0.02, 0), soot, detail=1),
    ]
    if ko:
        out += x_eye(*h(-0.125, 0.09, -0.235), 0.058) + x_eye(*h(0.125, 0.09, -0.235), 0.072)
        out.append(box("t", (0.2, 0.06, 0.03), h(0, -0.11, -0.26), mat("black")))
        out.append(box("t", (0.11, 0.26, 0.03), h(-0.02, -0.24, -0.285), mat("bubblegum")))
        out.append(ball("t", 0.06, h(-0.02, -0.37, -0.285), mat("bubblegum"), squash=(1, 0.8, 0.6), detail=1))
    else:
        out += eye(*h(-0.125, 0.09, -0.235), 0.058, look=(0.2, 0.3), pupil=0.26)
        out += eye(*h(0.125, 0.09, -0.235), 0.072, look=(-0.25, -0.2), pupil=0.2)
        out.append(box("t", (0.33, 0.085, 0.03), h(0, -0.11, -0.25), mat("black")))
        out += teeth(0, HEAD_Y - 0.11, -0.268, 7, 0.044, 0.065, gold=4)
    # Flat cap, slipped sideways once he has been flattened.
    cap = [
        cyl("t", 0.25, 0.09, h(0, 0.27, 0), cap_mat, "y", 8, 0.265),
        box("t", (0.34, 0.03, 0.18), h(0, 0.235, -0.27), cap_mat, taper=0.9),
        # Goggles parked on the cap.
        box("t", (0.5, 0.05, 0.04), h(0, 0.285, -0.255), mat("wood_dark")),
        cyl("t", 0.075, 0.05, h(-0.09, 0.3, -0.27), brass, "z", 8),
        cyl("t", 0.075, 0.05, h(0.09, 0.3, -0.27), brass, "z", 8),
        cyl("t", 0.052, 0.02, h(-0.09, 0.3, -0.298), mat("ice", emission=0.4, rough=0.2), "z", 8),
        cyl("t", 0.052, 0.02, h(0.09, 0.3, -0.298), mat("ice", emission=0.4, rough=0.2), "z", 8),
    ]
    if ko:
        for obj in cap:
            obj.location += gv(0.012, -0.03, 0)
    out += cap
    if ko:
        # Flame out: three sad puffs of smoke.
        smoke = mat(SMOKE)
        out.append(ball("t", 0.1, h(0.05, 0.42, 0), smoke, detail=1))
        out.append(ball("t", 0.08, h(-0.03, 0.55, 0.02), smoke, detail=1))
        out.append(ball("t", 0.06, h(0.05, 0.66, 0), smoke, detail=1))
    else:
        # His hat is on fire. Nobody has told him. Nobody dares.
        flame_a = mat("tomato", emission=2.0)
        flame_b = mat("mustard", emission=2.5)
        out.append(limb(h(0.02, 0.3, 0.02), h(0.1, 0.82, 0.04), 0.14, 0.0, flame_a, verts=5))
        out.append(limb(h(-0.09, 0.3, 0.0), h(-0.17, 0.62, 0.0), 0.09, 0.0, flame_a, verts=5))
        out.append(limb(h(0.13, 0.3, 0.0), h(0.21, 0.56, 0.0), 0.08, 0.0, flame_a, verts=5))
        out.append(limb(h(0.02, 0.3, -0.07), h(0.05, 0.62, -0.08), 0.09, 0.0, flame_b, verts=5))
        out.append(ball("t", 0.04, h(0.05, -0.56, -0.17), mat("tomato", emission=1.5), detail=1))
    return out


def stoker():
    wacky.reset_scene()
    wacky.REMAP = {"oxblood": "iron", "mustard": "brass", "cream": "bone"}
    soot = mat(SOOT)
    denim = mat("rust")
    iron = mat("iron")
    black = mat("black")
    brass = mat("brass", rough=0.3, metal=0.6)
    white = mat("white")

    chest = [
        box("t", (0.5, 0.46, 0.34), (0, 1.3, 0), soot, taper=1.34, bevel=0.03),
        box("t", (0.36, 0.33, 0.03), (0, 1.24, -0.185), denim, taper=0.9),
        box("t", (0.07, 0.3, 0.035), (-0.15, 1.45, -0.17), denim),
        box("t", (0.07, 0.3, 0.035), (0.15, 1.45, -0.17), denim),
        box("t", (0.07, 0.42, 0.035), (-0.17, 1.33, 0.17), denim),
        box("t", (0.07, 0.42, 0.035), (0.17, 1.33, 0.17), denim),
        ball("t", 0.03, (-0.13, 1.37, -0.205), brass, detail=1),
        ball("t", 0.03, (0.13, 1.37, -0.205), brass, detail=1),
    ]
    pelvis = [
        box("t", (0.42, 0.25, 0.3), (0, 0.98, 0), denim),
        box("t", (0.45, 0.05, 0.32), (0, 1.09, 0), mat("wood_dark")),
    ]

    def shoulder(side):
        s = side
        return [
            ball("t", 0.14, (s * 0.37, 1.46, 0), soot),
            limb((s * 0.37, 1.45, 0), (s * 0.36, 1.18, 0), 0.115, 0.095, soot),
        ]

    upper_l = shoulder(-1)
    upper_r = shoulder(1)

    # Left: enormous filthy fist, one tiny teacup, little finger out.
    fore_l = [
        limb((-0.36, 1.2, 0), (-0.36, 0.93, 0), 0.085, 0.135, soot, verts=8),
        ball("t", 0.18, (-0.36, 0.79, 0), soot, squash=(1, 1.0, 1.1)),
    ]
    for i in (-1, 0, 1):
        fore_l.append(ball("t", 0.055, (-0.36 + i * 0.095, 0.69, -0.1), soot, detail=1))
    fore_l += [
        limb((-0.47, 0.84, -0.13), (-0.52, 1.0, -0.15), 0.04, 0.028, soot),
        limb((-0.28, 0.77, -0.17), (-0.33, 0.77, -0.17), 0.06, 0.06, soot),
        cyl("t", 0.09, 0.016, (-0.36, 0.905, -0.2), white, "y", 8),
        limb((-0.36, 0.91, -0.2), (-0.36, 0.975, -0.2), 0.04, 0.058, white, verts=8),
        cyl("t", 0.05, 0.01, (-0.36, 0.975, -0.2), mat("mustard"), "y", 8),
        ball("t", 0.022, (-0.3, 0.945, -0.2), white, detail=1),
        ball("t", 0.016, (-0.36, 0.945, -0.258), mat("bubblegum"), detail=1),
    ]
    # Right: giant flowery oven mitt. It has clearly seen no ovens.
    mitt = mat("bubblegum")
    fore_r = [
        limb((0.36, 1.2, 0), (0.36, 0.95, 0), 0.085, 0.135, soot, verts=8),
        frill(cyl("t", 0.17, 0.07, (0.36, 0.95, 0), mat("cream"), "y", 12), 0.84),
        ball("t", 0.195, (0.36, 0.77, 0), mitt, squash=(1, 1.08, 1.05)),
        ball("t", 0.08, (0.21, 0.82, -0.08), mitt, squash=(1, 1.3, 1), detail=1),
    ]

    def leg(side, toe):
        s = side
        thigh = [limb((s * 0.13, 0.9, 0), (s * 0.19, 0.46, 0), 0.115, 0.085, denim, verts=8)]
        shin = [
            limb((s * 0.19, 0.47, 0), (s * 0.14, 0.2, 0), 0.085, 0.08, denim, verts=8),
            cyl("t", 0.095, 0.05, (s * 0.145, 0.235, 0), mat("oxblood"), "y", 8),
            box("t", (0.26, 0.17, 0.42), (s * 0.145, 0.1, -0.07), iron),
            ball("t", 0.145, (s * 0.15, 0.1, -0.27), mat("steel", rough=0.4, metal=0.5), squash=(1, 0.8, 1.1)),
            box("t", (0.3, 0.04, 0.58), (s * 0.145, 0.02, -0.12), black),
            box("t", (0.27, 0.03, 0.08), (s * 0.145, 0.17, -0.09), brass),
        ]
        if toe:
            # One big toe through the steel cap. Physics has no comment.
            shin.append(ball("t", 0.055, (s * 0.11, 0.11, -0.42), mat("skin_b"), squash=(1, 0.85, 1.1), detail=1))
        return thigh, shin

    thigh_l, shin_l = leg(-1, True)
    thigh_r, shin_r = leg(1, False)

    finish("stoker", {
        "pelvis": pelvis, "chest": chest,
        "head": stoker_head(False), "head_ko": stoker_head(True),
        "upper_arm_l": upper_l, "forearm_l": fore_l, "upper_arm_r": upper_r, "forearm_r": fore_r,
        "thigh_l": thigh_l, "shin_l": shin_l, "thigh_r": thigh_r, "shin_r": shin_r,
    })


# ---------------------------------------------------------------- opera


def songbird(ko):
    """Stuffed canary understudy, built around Godot (0,0,0) with feet at the bottom."""
    body = mat("mustard")
    beak = mat("tomato")
    leg = mat("wood_dark")
    parts = [
        ball("t", 0.085, (0, 0.09, 0.01), body, squash=(1, 0.95, 1.2), detail=1),
        ball("t", 0.065, (0, 0.2, -0.03), body, detail=1),
        limb((0, 0.09, 0.08), (0, 0.15, 0.18), 0.05, 0.0, body, verts=4),
        limb((0, 0.195, -0.08), (0, 0.235, -0.16), 0.04, 0.0, beak, verts=4),
        limb((0, 0.17, -0.08), (0, 0.13, -0.15), 0.035, 0.0, beak, verts=4),
        limb((-0.035, 0.02, 0), (-0.035, -0.05, 0), 0.012, 0.012, leg, verts=3),
        limb((0.035, 0.02, 0), (0.035, -0.05, 0), 0.012, 0.012, leg, verts=3),
    ]
    if ko:
        parts += x_eye(-0.05, 0.225, -0.05, 0.026, detail=1) + x_eye(0.05, 0.225, -0.05, 0.026, detail=1)
    else:
        parts += eye(-0.05, 0.225, -0.05, 0.03, look=(-0.3, 0.2), detail=1) + eye(0.05, 0.225, -0.05, 0.024, look=(0.3, -0.2), detail=1)
    return wacky.join("bird", parts)


def opera_head(ko):
    powder = mat("cream")
    skin = mat("skin_a")
    hair = mat("tomato")
    lid = mat("lilac")
    rouge = mat("bubblegum")
    black = mat("black")
    lips = mat("oxblood", rough=0.4)
    out = [
        # The powder stops at the jaw, and everyone has agreed not to mention it.
        limb(h(0, -0.29, 0), h(0, -0.05, 0), 0.095, 0.095, skin),
        ball("t", 0.225, h(0, 0.05, 0), powder, squash=(1, 1.05, 0.95)),
        ball("t", 0.165, h(0, -0.15, -0.03), powder, squash=(1.1, 0.62, 0.95), detail=1),
        # Rouge applied with a palette knife, in diamonds, from the back row.
        tilt(plate(0.09, 0.09, h(-0.145, -0.015, -0.178), rouge), y=-22, z=45),
        tilt(plate(0.09, 0.09, h(0.145, -0.015, -0.178), rouge), y=22, z=45),
        # Proud upturned nose, ready for applause.
        limb(h(0, 0.09, -0.2), h(0, 0.02, -0.295), 0.04, 0.052, powder),
        ball("t", 0.056, h(0, 0.02, -0.3), powder, detail=1),
        plate(0.024, 0.024, h(0.1, -0.075, -0.205), black),
        # Brows arched to the upper circle.
        tilt(plate(0.17, 0.03, h(-0.1, 0.225, -0.215), black), z=-18),
        tilt(plate(0.17, 0.03, h(0.1, 0.225, -0.215), black), z=18),
        # Hair and buns.
        ball("t", 0.235, h(0, 0.15, 0.03), hair, squash=(1.03, 0.82, 1.02)),
        ball("t", 0.1, h(-0.185, 0.1, 0.04), hair, squash=(0.9, 1.15, 1), detail=1),
        ball("t", 0.1, h(0.185, 0.1, 0.04), hair, squash=(0.9, 1.15, 1), detail=1),
        # Nest, with a bird that sings harmony and has never been asked to.
        cyl("t", 0.17, 0.1, h(0, 0.36, 0.02), mat("wood_dark"), "y", 8, 0.2),
        tilt(box("t", (0.5, 0.02, 0.03), h(0, 0.4, 0.05), mat("wood")), z=14),
    ]
    bird = songbird(ko)
    if ko:
        bird.location = gv(0.0, 0.62, 0.02)
        tilt(bird, z=172)
    else:
        bird.location = gv(0.0, 0.46, 0.02)
    bird.location += gv(0, HEAD_Y, 0)
    bpy.context.view_layer.update()
    out.append(bird)
    # Mouth: permanently mid high C.
    oval = cyl("t", 0.1, 0.03, h(0, -0.095, -0.19), lips, "z", 8)
    squash_mesh(oval, y=1.3)
    hole = cyl("t", 0.075, 0.03, h(0, -0.095, -0.2), black, "z", 8)
    squash_mesh(hole, y=1.32)
    out += [oval, hole]
    out += teeth(0, HEAD_Y - 0.03, -0.218, 4, 0.03, 0.03)
    if ko:
        out += x_eye(*h(-0.09, 0.1, -0.17), 0.08) + x_eye(*h(0.09, 0.1, -0.17), 0.08)
        out.append(tilt(box("t", (0.1, 0.27, 0.03), h(0.05, -0.22, -0.235), rouge), z=-9))
        out.append(ball("t", 0.058, h(0.075, -0.35, -0.235), rouge, squash=(1, 0.8, 0.6), detail=1))
    else:
        out += eye(*h(-0.09, 0.1, -0.17), 0.08, look=(-0.35, 0.3), pupil=0.24)
        out += eye(*h(0.09, 0.1, -0.17), 0.08, look=(-0.1, 0.45), pupil=0.24)
        for x in (-0.09, 0.09):
            out.append(ball("t", 0.09, h(x, 0.145, -0.165), lid, squash=(1, 0.5, 1), detail=1))
        for x, outward in ((-0.09, -1), (0.09, 1)):
            for i in range(2):
                start = h(x + outward * (0.02 + i * 0.03), 0.17 - i * 0.012, -0.22)
                tip = h(x + outward * (0.045 + i * 0.05), 0.24 - i * 0.03, -0.25)
                out.append(limb(start, tip, 0.012, 0.0, black, verts=3))
        out.append(ball("t", 0.022, h(0, -0.045, -0.215), rouge, squash=(1, 1.6, 1), detail=1))
        out.append(ball("t", 0.045, h(0, -0.15, -0.215), rouge, squash=(1.1, 0.6, 0.5), detail=1))
    return out


def opera():
    wacky.reset_scene()
    wacky.REMAP = {"teal": "brass", "mustard": "brass", "lilac": "wood_dark"}
    gown = mat((0.08, 0.24, 0.22))
    trim = mat("mustard")
    glove = mat("white")
    skin = mat("skin_a")
    black = mat("black")
    gold = mat("brass", rough=0.3, metal=0.6)
    gem = mat("tomato", emission=0.8, rough=0.2)

    chest = [
        box("t", (0.46, 0.44, 0.3), (0, 1.31, 0), gown, taper=1.1),
        # One magnificent uninterrupted shelf of bosom.
        ball("t", 0.33, (0, 1.31, -0.17), gown, squash=(1.08, 0.8, 1.02)),
        ball("t", 0.29, (0, 1.45, -0.13), skin, squash=(0.98, 0.42, 0.9)),
        frill(cyl("t", 0.3, 0.05, (0, 1.54, -0.01), mat("cream"), "y", 12), 0.8),
        box("t", (0.5, 0.05, 0.34), (0, 1.1, 0), trim),
    ]
    for i in range(-2, 3):
        angle = i * 0.42
        pos = (math.sin(angle) * 0.29, 1.43 + abs(i) * 0.02, -0.15 - math.cos(angle) * 0.29)
        chest.append(ball("t", 0.028, pos, gold, detail=1))
    chest += [
        # Square-cut pendant hanging from the necklace, with its price tag still on.
        tilt(box("t", (0.19, 0.21, 0.04), (0, 1.41, -0.475), gold, bevel=0.012), x=-14),
        tilt(box("t", (0.13, 0.15, 0.05), (0, 1.41, -0.49), gem, bevel=0.012), x=-14),
    ]

    pelvis = [
        ball("t", 0.27, (0, 0.98, 0.02), gown, squash=(1.1, 0.62, 1.05)),
        box("t", (0.17, 0.11, 0.05), (-0.12, 1.02, 0.31), gown, taper=1.5),
        box("t", (0.17, 0.11, 0.05), (0.12, 1.02, 0.31), gown, taper=1.5),
        ball("t", 0.06, (0, 1.02, 0.32), mat("tomato"), detail=1),
    ]

    def arm(side):
        s = side
        upper = [
            ball("t", 0.115, (s * 0.335, 1.44, 0), gown, squash=(1, 1.15, 1)),
            cyl("t", 0.085, 0.03, (s * 0.335, 1.33, 0), trim, "y", 8),
            limb((s * 0.335, 1.34, 0), (s * 0.32, 1.18, 0), 0.066, 0.055, skin),
        ]
        fore = [
            limb((s * 0.32, 1.19, 0), (s * 0.31, 0.93, 0), 0.056, 0.042, glove),
            ball("t", 0.085, (s * 0.31, 0.86, 0), glove, squash=(1, 1.1, 1)),
            cyl("t", 0.06, 0.02, (s * 0.32, 1.18, 0), trim, "y", 8),
        ]
        return upper, fore

    upper_l, fore_l = arm(-1)
    upper_r, fore_r = arm(1)
    # Left: turkey leg for the interval, already bitten.
    fore_l += hand_fingers(-0.31, 0.83, -0.075, glove, r=0.022, spread=0.04, length=0.075)
    fore_l += [
        limb((-0.31, 0.92, -0.08), (-0.31, 0.73, -0.1), 0.026, 0.03, mat("bone"), verts=5),
        ball("t", 0.04, (-0.31, 0.95, -0.08), mat("bone"), detail=1),
        ball("t", 0.125, (-0.31, 0.65, -0.12), mat("rust"), squash=(1, 1.25, 1)),
        ball("t", 0.08, (-0.41, 0.62, -0.17), mat("cream"), squash=(0.5, 1, 1), detail=1),
    ]
    # Right: fan, which only ever fans the fan.
    pivot = (0.31, 0.86, -0.1)
    for i, angle in enumerate((-48, -24, 0, 24, 48)):
        radians = math.radians(angle)
        center = (pivot[0] + math.sin(radians) * 0.17, pivot[1] - math.cos(radians) * 0.17, pivot[2])
        blade = box("t", (0.055, 0.34, 0.012), center, mat("teal" if i % 2 else "mustard"), taper=1.9 ** -1)
        fore_r.append(tilt(blade, z=angle))

    def leg(side):
        s = side
        thigh = [
            limb((s * 0.12, 0.92, 0), (s * 0.135, 0.45, 0), 0.17, 0.205, gown, verts=8),
            cyl("t", 0.205, 0.03, (s * 0.135, 0.56, 0), mat("tomato"), "y", 8),
        ]
        shin = [
            limb((s * 0.135, 0.46, 0), (s * 0.15, 0.09, 0), 0.205, 0.26, gown, verts=8),
            frill(cyl("t", 0.3, 0.12, (s * 0.15, 0.075, 0), trim, "y", 12), 0.86),
            # Teeny heels peeping out from under all that gown.
            ball("t", 0.05, (s * 0.14, 0.04, -0.3), mat("tomato"), squash=(1, 0.75, 1.7), detail=1),
        ]
        return thigh, shin

    thigh_l, shin_l = leg(-1)
    thigh_r, shin_r = leg(1)

    finish("opera", {
        "pelvis": pelvis, "chest": chest,
        "head": opera_head(False), "head_ko": opera_head(True),
        "upper_arm_l": upper_l, "forearm_l": fore_l, "upper_arm_r": upper_r, "forearm_r": fore_r,
        "thigh_l": thigh_l, "shin_l": shin_l, "thigh_r": thigh_r, "shin_r": shin_r,
    })


BUILDERS = {"intern": intern, "stoker": stoker, "opera": opera}
names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(BUILDERS)
for passenger in names:
    BUILDERS[passenger]()
print("done", names)
