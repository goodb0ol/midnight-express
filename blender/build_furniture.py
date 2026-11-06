"""Builds assets/models/furniture/*.glb and their preview sheets.

  blender.exe --background --python blender/build_furniture.py [-- boiler table ...]

All coordinates are Godot coordinates. See docs/ART_BRIEF.md, group "furniture".
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
from wacky import ball, box, cyl, gv, join, mat, wobble



def _r(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


# Chunky painted letters on a 3 x 5 grid. Boxes and slabs, so each letter costs a few tris.
_O = [_r(0, 0.6, 1, 4.4), _r(2, 0.6, 3, 4.4), _r(0.5, 4, 2.5, 5), _r(0.5, 0, 2.5, 1)]
_P = [_r(0, 0, 1, 5), _r(1, 4, 2.5, 5), _r(1, 2, 2.5, 3), _r(2, 2.7, 3, 4.3)]
GLYPHS = {
    "A": [_r(0, 0, 1, 4.3), _r(2, 0, 3, 4.3), _r(0.4, 4, 2.6, 5), _r(1, 1.6, 2, 2.6)],
    "B": [_r(0, 0, 1, 5), _r(1, 4, 2.5, 5), _r(1, 2, 2.4, 3), _r(1, 0, 2.5, 1), _r(2, 2.9, 2.8, 4.1), _r(2, 0.9, 3, 2.1)],
    "C": [_r(0, 0.6, 1, 4.4), _r(0.5, 4, 3, 5), _r(0.5, 0, 3, 1)],
    "D": [_r(0, 0, 1, 5), _r(1, 4, 2.4, 5), _r(1, 0, 2.4, 1), _r(2, 0.7, 3, 4.3)],
    "E": [_r(0, 0, 1, 5), _r(1, 4, 3, 5), _r(1, 2, 2.6, 3), _r(1, 0, 3, 1)],
    "F": [_r(0, 0, 1, 5), _r(1, 4, 3, 5), _r(1, 2, 2.6, 3)],
    "H": [_r(0, 0, 1, 5), _r(2, 0, 3, 5), _r(1, 2, 2, 3)],
    "I": [_r(0, 0, 1.2, 5)],
    "K": [_r(0, 0, 1, 5), [(1, 2), (2, 5), (3.1, 5), (1.7, 2.5), (3.1, 0), (2, 0), (1, 2.9)]],
    "L": [_r(0, 0, 1, 5), _r(1, 0, 3, 1)],
    "M": [_r(0, 0, 1, 5), _r(2.6, 0, 3.6, 5), [(1, 5), (1.8, 2.4), (2.6, 5), (2.6, 3.2), (1.8, 0.9), (1, 3.2)]],
    "N": [_r(0, 0, 1, 5), _r(2.2, 0, 3.2, 5), [(1, 5), (2.2, 1.8), (2.2, 0), (1, 3.2)]],
    "O": _O,
    "P": _P,
    "R": _P + [[(1.3, 2.2), (2.4, 2.2), (3.1, 0), (2, 0)]],
    "S": [_r(0.4, 4, 3, 5), _r(0, 2.6, 1, 4.4), _r(0.4, 2, 2.6, 3), _r(2, 0.6, 3, 2.4), _r(0, 0, 2.6, 1)],
    "T": [_r(0, 4, 3, 5), _r(1, 0, 2, 4)],
    "U": [_r(0, 0.6, 1, 5), _r(2, 0.6, 3, 5), _r(0.5, 0, 2.5, 1)],
    "Y": [[(0, 5), (1.1, 5), (2, 2.2), (1, 2.2)], [(1.9, 5), (3, 5), (2, 2.2), (1, 2.2)], _r(1, 0, 2, 2.4)],
    "0": _O,
    "1": [_r(1, 0, 2, 5), _r(0.2, 3.6, 1, 4.6), _r(0.3, 0, 2.8, 1)],
    "3": [_r(0, 4, 2.6, 5), _r(2, 2.9, 3, 4.2), _r(0.9, 2, 2.4, 3), _r(2, 0.8, 3, 2.1), _r(0, 0, 2.6, 1)],
    "9": [_r(0.4, 4, 2.6, 5), _r(0, 2.6, 1, 4.4), _r(2, 0.6, 3, 4.4), _r(0.4, 2, 2.6, 3), _r(0, 0, 2.6, 1)],
    "?": [_r(0.2, 4, 2.6, 5), _r(2, 2.7, 3, 4.4), _r(1, 1.7, 2.4, 3), _r(1, 0, 2, 1.1)],
}
FACING = {
    # facing: (right, up) as the viewer sees the text.
    "+z": ((1, 0, 0), (0, 1, 0)),
    "-z": ((-1, 0, 0), (0, 1, 0)),
    "+x": ((0, 0, -1), (0, 1, 0)),
    "-x": ((0, 0, 1), (0, 1, 0)),
    "-y": ((1, 0, 0), (0, 0, 1)),
    "+y": ((1, 0, 0), (0, 0, -1)),
}


# ---------------------------------------------------------------- local helpers


def tilt(obj, x=0.0, y=0.0, z=0.0):
    """Rotates [obj] about its own origin, in degrees around Godot axes."""
    rotation = (Matrix.Rotation(math.radians(z), 3, gv(0, 0, 1))
                @ Matrix.Rotation(math.radians(y), 3, gv(0, 1, 0))
                @ Matrix.Rotation(math.radians(x), 3, gv(1, 0, 0)))
    obj.rotation_euler = rotation.to_euler()
    return obj


def stretch(obj, x=1.0, y=1.0, z=1.0):
    """Scales the mesh about its own origin along Godot axes."""
    size = wacky.gs((x, y, z))
    obj.data.transform(Matrix.Diagonal((size.x, size.y, size.z, 1.0)))
    obj.data.update()
    return obj


def prism(name, outline, depth, center=(0, 0, 0), material=None, plane="xy"):
    """Extrudes a 2D [outline]. plane 'xy' extrudes along Z, 'zy' along X, 'xz' along Y."""
    bm = bmesh.new()
    if plane == "xy":
        points, axis = [gv(a, b, 0) for a, b in outline], gv(0, 0, 1)
    elif plane == "zy":
        points, axis = [gv(0, b, a) for a, b in outline], gv(1, 0, 0)
    else:
        points, axis = [gv(a, 0, b) for a, b in outline], gv(0, 1, 0)
    face = bm.faces.new([bm.verts.new(p) for p in points])
    made = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [g for g in made["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=axis * depth)
    bmesh.ops.translate(bm, verts=bm.verts, vec=axis * (-depth * 0.5))
    return wacky._finish(name, bm, center, material)


def hoop(name, radius, height, center=(0, 0, 0), material=None, axis="y", verts=12, top_radius=None):
    """Open-ended tube. For surfaces whose end caps are never seen."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=verts, radius1=radius,
                          radius2=radius if top_radius is None else top_radius, depth=height)
    if axis == "x":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif axis == "z":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    return wacky._finish(name, bm, center, material)


def sausage(name, stations, y, x_scale, material, floor=0.03, verts=12):
    """Open hull along Z. [stations] are (z, sag, radius). Verts stop at y=[floor], so it sits there."""
    bm = bmesh.new()
    rings = []
    for z, sag, radius in stations:
        ring = []
        for k in range(verts):
            a = k * math.tau / verts
            ring.append(bm.verts.new(gv(radius * x_scale * math.cos(a), max(floor, y + sag + radius * math.sin(a)), z)))
        rings.append(ring)
    for first, second in zip(rings, rings[1:]):
        for k in range(verts):
            bm.faces.new((first[k], first[(k + 1) % verts], second[(k + 1) % verts], second[k]))
    return wacky._finish(name, bm, (0, 0, 0), material)


def shave(obj, normal, keep_from=0.0):
    """Deletes faces wholly behind [keep_from] along Godot [normal]. For halves nobody can see."""
    direction = gv(*normal).normalized()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    hidden = [f for f in bm.faces if all(v.co.dot(direction) < keep_from for v in f.verts)]
    bmesh.ops.delete(bm, geom=hidden, context="FACES_ONLY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def stuck_ball(name, radius, center, normal, material, flatten=0.6, detail=2):
    """Half ball flattened along [normal]: an eye glued to a curved surface, no hidden back."""
    turn = gv(0, 0, -1).rotation_difference(gv(*normal).normalized()).to_matrix().to_4x4()
    obj = ball(name, radius, center, material, squash=(1, 1, flatten), detail=detail)
    obj.data.transform(turn)
    obj.data.update()
    return shave(obj, normal, -radius * flatten * 0.3)


def spring(name, base, height, r0, r1, turns, wire, material, seg=6):
    """Coil rising along +Y from [base], flaring from r0 to r1. Triangular wire, closed ends."""
    bm = bmesh.new()
    rings = []
    count = int(turns * seg) + 1
    for i in range(count):
        t = i / (count - 1)
        angle = t * turns * math.tau
        radial = Vector((math.cos(angle), math.sin(angle), 0.0))
        middle = radial * (r0 + (r1 - r0) * t) + Vector((0.0, 0.0, height * t))
        ring = []
        for k in range(3):
            a = k * math.tau / 3.0
            ring.append(bm.verts.new(middle + (radial * math.cos(a) + Vector((0, 0, 1)) * math.sin(a)) * wire))
        rings.append(ring)
    for first, second in zip(rings, rings[1:]):
        for k in range(3):
            bm.faces.new((first[k], first[(k + 1) % 3], second[(k + 1) % 3], second[k]))
    bm.faces.new(rings[0])
    bm.faces.new(rings[-1])
    return wacky._finish(name, bm, base, material)


def ngon(radius, count, squash=1.0, start=0.0):
    """Regular outline for flat(), wider by [squash] along the second axis."""
    return [(radius * math.cos(start + i * math.tau / count), radius * squash * math.sin(start + i * math.tau / count))
            for i in range(count)]


def flat(name, outline, center, facing, material, spin=0.0):
    """One-sided decal: a single polygon facing out along [facing]. Cheap, for stuck-on detail."""
    right, up = (gv(*axis) for axis in FACING[facing])
    a = math.radians(spin)
    points = [(u * math.cos(a) - v * math.sin(a), u * math.sin(a) + v * math.cos(a)) for u, v in outline]
    area = sum(p[0] * q[1] - q[0] * p[1] for p, q in zip(points, points[1:] + points[:1]))
    if area < 0.0:
        points.reverse()
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bm.faces.new([bm.verts.new(right * u + up * v) for u, v in points])
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = wacky._new_object(name, mesh)
    obj.location = gv(*center)
    return obj


def skirt(name, half_x, half_z, y_top, hem, material, per_x=5, per_z=6, flare=0.02, thick=0.012, seed=1):
    """Cloth drop round a rectangle: a closed shell with a ragged, zig-zag hem."""
    rng = random.Random(seed)
    outline = []
    for i in range(per_x):
        outline.append((-half_x + 2 * half_x * i / per_x, half_z))
    for i in range(per_z):
        outline.append((half_x, half_z - 2 * half_z * i / per_z))
    for i in range(per_x):
        outline.append((half_x - 2 * half_x * i / per_x, -half_z))
    for i in range(per_z):
        outline.append((-half_x, -half_z + 2 * half_z * i / per_z))
    bm = bmesh.new()
    top = [bm.verts.new(gv(x, y_top, z)) for x, z in outline]
    bottom = []
    for i, (x, z) in enumerate(outline):
        y = hem[i % len(hem)] + rng.uniform(-0.02, 0.02)
        bottom.append(bm.verts.new(gv(x + math.copysign(flare, x), y, z + math.copysign(flare, z))))
    faces = []
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        faces.append(bm.faces.new((top[i], top[j], bottom[j], bottom[i])))
    bmesh.ops.solidify(bm, geom=faces, thickness=thick)
    return wacky._finish(name, bm, (0, 0, 0), material)


def text(name, string, center, facing, material, width=1.0, spin=0.0, seed=7):
    """Flat block lettering, one-sided, centred on [center] and fitted to [width] across."""
    rng = random.Random(seed)
    lines = []
    for row, line in enumerate(string.split("\n")):
        polys = []
        cursor = 0.0
        for letter in line:
            if letter == " ":
                cursor += 1.9
                continue
            shapes = GLYPHS[letter]
            wide = max(p[0] for shape in shapes for p in shape)
            a = math.radians(rng.uniform(-5.0, 5.0))
            lift = rng.uniform(-0.22, 0.22)
            for shape in shapes:
                turned = []
                for x, y in shape:
                    x, y = x - wide / 2, y - 2.5
                    turned.append((cursor + wide / 2 + x * math.cos(a) - y * math.sin(a),
                                   lift + x * math.sin(a) + y * math.cos(a) - row * 6.3))
                polys.append(turned)
            cursor += wide + 0.75
        lines.append((polys, cursor - 0.75))
    longest = max(length for _, length in lines)
    polys = [[(x - length / 2, y) for x, y in poly] for line, length in lines for poly in line]
    middle = (min(y for poly in polys for _, y in poly) + max(y for poly in polys for _, y in poly)) / 2
    scale = width / longest
    turn = math.radians(spin)
    right, up = (gv(*axis) for axis in FACING[facing])
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for poly in polys:
        points = []
        for x, y in poly:
            x, y = x * scale, (y - middle) * scale
            points.append(right * (x * math.cos(turn) - y * math.sin(turn)) + up * (x * math.sin(turn) + y * math.cos(turn)))
        if sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1])) < 0.0:
            points.reverse()
        bm.faces.new([bm.verts.new(p) for p in points])
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = wacky._new_object(name, mesh)
    obj.location = gv(*center)
    print("  text %r tris=%d" % (string, sum(len(p.vertices) - 2 for p in mesh.polygons)))
    return obj


def finish(name, parts, filename, size, offset=(0, 0, 0), views=None, shaded=True, bonus=0.0):
    """Joins [parts], checks the footprint, exports and previews. [size] is x y z."""
    heavy = sorted(((sum(len(f.vertices) - 2 for f in o.data.polygons), o.name) for o in parts), reverse=True)
    print("  heaviest:", " ".join("%s=%d" % (n, t) for t, n in heavy[:16]))
    obj = join(name, parts)
    wacky.clear_except([obj])
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    low = (min(c.x for c in corners), min(c.z for c in corners), min(-c.y for c in corners))
    high = (max(c.x for c in corners), max(c.z for c in corners), max(-c.y for c in corners))
    want_low = (-size[0] / 2 + offset[0], offset[1], -size[2] / 2 + offset[2])
    want_high = (size[0] / 2 + offset[0], size[1] + offset[1], size[2] / 2 + offset[2])
    wacky.report([obj])
    for i, axis in enumerate("xyz"):
        print("  %s %.3f..%.3f  wanted %.3f..%.3f%s" % (
            axis, low[i], high[i], want_low[i], want_high[i],
            "  OVERHANG" if low[i] < want_low[i] - 0.05 or high[i] > want_high[i] + 0.05 + bonus else ""))
    if shaded:
        wacky.bake_height(obj)
    wacky.export_glb("assets/models/furniture/%s.glb" % filename)
    saved = dict(wacky.VIEWS)
    if views:
        wacky.VIEWS.update(views)
    wacky.preview("assets/previews/furniture/%s.png" % filename)
    wacky.VIEWS.clear()
    wacky.VIEWS.update(saved)
    wacky.reset_scene()


def gauge(parts, cx, cy, z, r, red_from, red_to, needle, prefix, verts=10):
    """Pressure gauge facing +Z. Angles run clockwise from 12 o'clock."""
    parts.append(hoop(prefix + "bezel", r, 0.07, (cx, cy, z), mat("brass", metal=0.3, rough=0.5), axis="z",
                      verts=verts, top_radius=r * 0.84))
    parts.append(flat(prefix + "face", ngon(r * 0.86, verts), (cx, cy, z + 0.036), "+z", mat("cream")))
    outline = [(0.0, 0.0)]
    steps = 5
    for i in range(steps + 1):
        a = math.radians(red_from + (red_to - red_from) * i / steps)
        outline.append((math.sin(a) * r * 0.76, math.cos(a) * r * 0.76))
    parts.append(flat(prefix + "red", outline, (cx, cy, z + 0.04), "+z", mat("tomato")))
    length = r * 0.72
    wide = max(0.018, r * 0.05)
    parts.append(flat(prefix + "needle", [(-wide, 0.0), (wide, 0.0), (0.0, length)], (cx, cy, z + 0.044), "+z",
                      mat("black"), spin=-needle))


# ---------------------------------------------------------------- boiler


def build_boiler():
    hull = mat((0.03, 0.05, 0.04), rough=0.6)
    brass = mat("brass", metal=0.3, rough=0.5)
    iron = mat("iron", rough=0.7)
    glow = mat((1.0, 0.42, 0.05), emission=3.0)
    tooth = mat("bone")
    rng = random.Random(4)
    parts = []
    # Fat oval boiler: a round one would not fill the 2.4 m footprint.
    # The bands cinch it into fat sausage links, and the middle has sagged onto the floor.
    belly = ((-1.95, 0.0, 0.94), (-0.6, -0.05, 1.0), (0.2, -0.11, 0.89), (0.85, -0.08, 0.99),
             (1.5, -0.03, 0.9), (2.13, 0.0, 0.94))
    parts.append(wobble(sausage("hull", belly, 0.99, 1.19, hull, verts=10), 0.012, 2))
    parts.append(stretch(hoop("rear", 0.7, 0.28, (0, 0.99, -2.09), iron, axis="z", top_radius=0.94, verts=8), x=1.19))
    parts.append(flat("rearcap", ngon(0.83, 12, 0.84), (0, 0.99, -2.23), "-z", iron))
    # The middle band has slipped badly. Nobody has mentioned it.
    for i, (z, sag, radius) in enumerate(((-1.25, -0.026, 1.015), (0.2, -0.09, 0.96), (1.5, -0.03, 0.945))):
        band = sausage("band%d" % i, ((-0.085, 0, radius), (0.085, 0, radius)), 0.0, 1.19, brass, floor=-9.0, verts=10)
        band.location = gv(0, 0.99 + sag, z)
        parts.append(tilt(band, x=[-2.0, 11.0, 2.5][i], y=[1.5, -1.0, 0.8][i]))
    parts.append(flat("plate", ngon(1.14, 12, 0.84), (0, 0.99, 2.13), "+z", iron))
    # Saddles and skids.
    for i, z in enumerate((-1.25, 1.2)):
        parts.append(box("saddle%d" % i, (2.4, 0.5, 0.5), (0, 0.25, z), mat("rust"), taper=0.92))
    for side in (-1, 1):
        parts.append(box("skid%d" % side, (0.26, 0.14, 4.5), (side * 1.07, 0.07, 0), iron))

    # The furnace door is a grinning jaw: a brass frame, a glowing slot, bars for teeth.
    jaw = [(-0.72, 1.04), (0.72, 1.08), (0.8, 0.84), (0.62, 0.56), (0.28, 0.42), (-0.3, 0.44), (-0.64, 0.54), (-0.8, 0.82)]
    parts.append(prism("door", jaw, 0.06, (0, 0, 2.16), brass, plane="xy"))
    fire = [(x * 0.86, 0.75 + (y - 0.75) * 0.8) for x, y in jaw]
    parts.append(flat("fire", fire, (0, 0, 2.196), "+z", glow))
    for i in range(6):
        x = -0.56 + i * 0.224
        drop = rng.uniform(0.2, 0.34)
        fang = hoop("top%d" % i, 0.1, drop, (x, 1.0 - drop / 2, 2.2), tooth, verts=4, top_radius=0.0)
        parts.append(tilt(fang, x=180))
    for i in range(5):
        x = -0.46 + i * 0.23
        rise = rng.uniform(0.14, 0.26)
        floor = 0.56 - abs(x) * 0.08
        parts.append(hoop("low%d" % i, 0.095, rise, (x, floor + rise / 2, 2.2), tooth, verts=4, top_radius=0.0))
    parts.append(tilt(box("latch", (0.14, 0.42, 0.07), (0.86, 0.78, 2.22), mat("iron")), z=-18))
    plaque = box("plaque", (1.16, 0.28, 0.04), (0.02, 0.27, 2.15), mat("cream"))
    parts.append(tilt(plaque, z=2.5))
    parts.append(text("feed", "FEED ME", (0.02, 0.27, 2.18), "+z", mat("black"), width=1.0, spin=2.5))

    # Mismatched gauge eyes, every one of them in the red.
    gauge(parts, -0.44, 1.5, 2.14, 0.38, 40, 170, 158, "eyeL", verts=10)
    gauge(parts, 0.5, 1.6, 2.14, 0.23, 20, 200, 100, "eyeR", verts=8)
    gauge(parts, 0.08, 1.8, 2.14, 0.13, 0, 300, 250, "eyeT", verts=6)
    parts.append(tilt(box("brow", (0.62, 0.09, 0.05), (-0.46, 1.92, 2.17), iron), z=-12))

    # Top: steam dome. The top of the box is 2.1, so it stays squat.
    parts.append(cyl("dome", 0.34, 0.27, (0.28, 1.97, -0.6), brass, verts=6, top_radius=0.26))

    # Crooked steam pipe down the +X flank, in three bad sections.
    pipe = mat("rust")
    for i, (z, kink) in enumerate(((-1.4, 3.0), (-0.1, -4.0), (1.15, 3.5))):
        parts.append(tilt(hoop("pipe%d" % i, 0.075, 1.3, (1.05, 1.53, z), pipe, axis="z", verts=6), y=kink))
    for i, z in enumerate((-0.75, 0.55)):
        parts.append(hoop("elbow%d" % i, 0.115, 0.14, (1.06, 1.53, z), brass, axis="z", verts=6))
    # Rear end bends back into the boiler. Front end has a wine cork in it.
    parts.append(cyl("elbowRear", 0.13, 0.2, (1.05, 1.53, -2.04), brass, axis="x", verts=5))
    parts.append(hoop("stubRear", 0.085, 0.38, (0.87, 1.53, -2.02), pipe, axis="x", verts=6))
    parts.append(cyl("elbowFront", 0.13, 0.2, (1.05, 1.53, 1.8), brass, verts=5))
    parts.append(tilt(hoop("stubFront", 0.085, 0.3, (1.05, 1.68, 1.8), pipe, verts=6), x=-8, z=-6))
    parts.append(tilt(cyl("cork", 0.075, 0.12, (1.04, 1.86, 1.78), mat("wood"), verts=5, top_radius=0.1), x=-8, z=-6))

    return finish("Boiler", parts, "boiler", (2.4, 2.1, 4.5))


# ---------------------------------------------------------------- coal bin


def build_coal_bin():
    plank = mat("wood")
    dark = mat("wood_dark")
    odd = dark
    paint = mat("cream")
    parts = []
    parts.append(box("floor", (1.3, 0.01, 4.12), (0, 0.005, 0), mat("iron")))
    # Long wall on -X: its outer face is what the crew sees from the aisle.
    # Boards overlap where they lean, so each sits a few mm off the next: no shared planes.
    # The middle ones are tall enough to stop the leans opening see-through slits.
    parts.append(tilt(box("low", (0.12, 0.2, 4.12), (-0.59, 0.108, 0), odd), x=0.2))
    parts.append(tilt(box("mid", (0.12, 0.24, 2.5), (-0.585, 0.3, -0.8), dark), x=-1.3))
    parts.append(tilt(box("mid2", (0.12, 0.24, 1.62), (-0.582, 0.3, 1.25), plank), x=-0.9))
    # Top plank has a row of colossal bite marks.
    edge = [(-2.06, 0.4), (2.06, 0.4), (2.06, 0.6), (1.05, 0.61), (1.0, 0.54), (0.93, 0.47), (0.84, 0.52),
            (0.76, 0.46), (0.67, 0.52), (0.58, 0.46), (0.49, 0.53), (0.43, 0.6), (-1.1, 0.585), (-2.06, 0.6)]
    parts.append(tilt(prism("top", edge, 0.12, (-0.593, 0, 0), plank, plane="zy"), x=-0.8))
    # End walls: (y, lean, length, x shift, distance from centre). Sawn by eye, nailed on in a hurry.
    # The bottom board stays level on the floor. Faces step 5 mm apart, all behind the post.
    boards = {-1: ((0.104, -0.3, 1.3, 0.0, 2.0), (0.3, -1.0, 1.31, 0.015, 1.99), (0.5, -2.8, 1.27, 0.02, 1.995)),
              1: ((0.104, 0.3, 1.3, 0.0, 2.0), (0.3, 0.9, 1.28, 0.015, 1.99), (0.5, 2.6, 1.34, 0.02, 1.995))}
    for sign in (-1, 1):
        for i, (y, lean, length, shift, reach) in enumerate(boards[sign]):
            parts.append(tilt(box("end%d%d" % (sign, i), (length, 0.24 if i == 1 else 0.2, 0.12), (shift, y, sign * reach),
                                  dark if i == 1 else plank), z=lean))
        # Proud of every board by 1 cm, so the corners never share a plane.
        parts.append(box("post%d" % sign, (0.18, 0.62, 0.18), (-0.57, 0.31, sign * 1.98), mat("iron")))
    # Iron straps.
    for i, z in enumerate((-1.78, 0.32)):
        parts.append(tilt(box("strap%d" % i, (0.03, 0.62, 0.12), (-0.645, 0.315, z), mat("rust")), x=[2, -3][i]))
    # Aisle-side lettering.
    parts.append(text("snacks", "NOT SNACKS", (-0.665, 0.31, -0.72), "-x", paint, width=1.85, spin=1.5))
    return finish("CoalBin", parts, "coal_bin", (1.3, 0.6, 4.12))


# ---------------------------------------------------------------- counter


def build_counter():
    wood = mat("wood_dark")
    trim = mat("brass")
    parts = []
    parts.append(box("kick", (1.1, 0.08, 0.6), (0, 0.04, 0), mat("iron")))
    parts.append(box("body", (1.08, 0.58, 0.58), (0, 0.37, 0), wood, taper=1.015))
    parts.append(box("rail", (1.1, 0.05, 0.6), (0, 0.6, 0), trim))
    parts.append(tilt(box("slab", (1.1, 0.06, 0.6), (0, 0.69, 0), mat("wood")), z=-0.8))
    # Front and back boards.
    parts.append(tilt(box("board", (0.92, 0.3, 0.02), (0, 0.37, -0.298), mat("bone")), z=-2.5))
    parts.append(text("fresh", "FRESH SINCE\n1931", (0, 0.37, -0.312), "-z", mat("black"), width=0.8, spin=2.5))

    # The pie. It is looking at you. It sits back in the dome so the eyes clear the glass at -Z.
    px, pz = -0.17, 0.04
    top = 0.72
    slab_y = lambda x: top - 0.014 * x  # Top of the tilted slab.
    parts.append(cyl("tin", 0.22, 0.05, (px, top + 0.025, pz), mat("steel"), verts=8))
    parts.append(hoop("crust", 0.2, 0.08, (px, top + 0.08, pz), mat("mustard"), verts=10, top_radius=0.205))
    lid = ball("lid", 0.215, (px, top + 0.105, pz), mat("mustard"), squash=(1, 0.42, 1), detail=2)
    parts.append(wobble(shave(lid, (0, 1, 0), -0.03), 0.008, 5))
    # Crust grin on the -Z side, cut into the rim below the eyes.
    parts.append(tilt(box("slit", (0.28, 0.06, 0.02), (px, top + 0.072, pz - 0.208), mat("black")), x=-5))
    fangs = [(-0.126, 0.03), (0.126, 0.03)]
    for i in range(6):
        fangs[1:1] = [(0.126 - i * 0.042, 0.03), (0.105 - i * 0.042, -0.02 - (i % 2) * 0.012)]
    parts.append(flat("pt", [(-u, v) for u, v in fangs[:-1]], (px, top + 0.072, pz - 0.2195), "-z", mat("white")))
    # Wildly mismatched eyes, glued to the lid and aimed at whoever is about to order.
    white = mat("white", rough=0.4)
    black = mat("black")
    left, right = (-0.32, 0.72, -0.62), (0.3, 0.75, -0.6)
    parts.append(stuck_ball("pieEyeL", 0.078, (px - 0.085, top + 0.158, pz - 0.15), left, white))
    parts.append(stuck_ball("pieEyeR", 0.05, (px + 0.095, top + 0.152, pz - 0.155), right, white, detail=1))
    parts.append(stuck_ball("piePupL", 0.024, (px - 0.07, top + 0.185, pz - 0.195), left, black, detail=1))
    parts.append(stuck_ball("piePupR", 0.016, (px + 0.1, top + 0.178, pz - 0.178), right, black, detail=1))
    # Dome. Wide enough to fit that stare, and short enough to leave room for the knob.
    dome_r, dome_h = 0.295, 0.28
    glass = ball("dome", dome_r, (px, top, 0), mat("ice", alpha=0.3, rough=0.1), squash=(1, dome_h / dome_r, 1), detail=2)
    # Everything inside must stay behind every facet of the glass. Positive means it pokes through.
    facets = [(p.center + glass.location, p.normal.copy()) for p in glass.data.polygons]
    for obj in parts:
        if obj.name.startswith(("pieEye", "piePup", "pfork", "pt", "slit", "lid", "ooze", "tin", "crust")):
            points = [obj.matrix_basis @ v.co for v in obj.data.vertices]
            gap = max((q - c).dot(n) for q in points for c, n in facets)
            print("  dome clearance %-8s %+.3f" % (obj.name, gap))
    parts.append(shave(glass, (0, 1, 0), -0.02))
    parts.append(hoop("domering", 0.285, 0.035, (px, top + 0.02, 0), mat("brass"), verts=8))
    parts.append(shave(ball("knob", 0.04, (px, top + 0.285, 0), mat("brass"), detail=1), (0, 1, 0), -0.015))

    # Brass pie case. The whole 1 m tall block is solid in the game, so it has to look solid.
    brass = mat("brass", metal=0.3, rough=0.5)
    pane = mat("ice", alpha=0.14, rough=0.1)
    for sx in (-1, 1):
        for sz in (-1, 1):
            post = box("post%d%d" % (sx, sz), (0.06, 0.3, 0.06), (sx * 0.52, 0.84, sz * 0.27), brass, taper=0.85)
            parts.append(tilt(post, z=sx * sz * 0.9))
    # No rail on the -Z side: it would sit right on the sight line to the pie's eyes.
    parts.append(tilt(box("railz", (1.1, 0.05, 0.05), (0, 0.973, 0.272), brass), z=0.5))
    for sx in (-1, 1):
        parts.append(tilt(box("railx%d" % sx, (0.05, 0.05, 0.6), (sx * 0.52, 0.975, 0), brass), x=sx * 0.5))
    # Panes are single quads: every material exports double-sided.
    parts.append(flat("glasslid", _r(-0.5, -0.25, 0.5, 0.25), (0, 0.992, 0), "+y", pane))
    parts.append(hoop("collar", 0.125, 0.04, (px, 0.985, 0), brass, verts=8, top_radius=0.115))
    for sz in (-1, 1):
        parts.append(flat("glassz%d" % sz, _r(-0.49, -0.125, 0.49, 0.125), (0, 0.85, sz * 0.297), "+z", pane))
    for sx in (-1, 1):
        parts.append(flat("glassx%d" % sx, _r(-0.24, -0.125, 0.24, 0.125), (sx * 0.53, 0.85, 0), "+x", pane))
    return finish("Counter", parts, "counter", (1.1, 1.0, 0.6), views={"side": (-0.55, 0.85, 0.45)})


# ---------------------------------------------------------------- table


def build_table():
    cloth = mat((0.13, 0.105, 0.075))
    parts = []
    # Collision is a slim central post, so the leg is one fat iron post.
    parts.append(box("footx", (0.72, 0.04, 0.14), (0, 0.02, 0), mat("iron")))
    parts.append(box("footz", (0.14, 0.04, 0.9), (0, 0.02, 0), mat("iron")))
    parts.append(cyl("post", 0.09, 0.72, (0, 0.38, 0), mat("iron"), verts=8))
    parts.append(box("top", (0.76, 0.05, 0.96), (0, 0.745, 0), mat("wood_dark")))
    parts.append(box("cloth", (0.8, 0.012, 1.0), (0, 0.774, 0), cloth))
    parts.append(wobble(skirt("skirt", 0.4, 0.5, 0.778, (0.58, 0.54, 0.6, 0.53, 0.56), cloth, seed=3), 0.006, 4))
    # One stain, and it is an honest one.
    parts.append(flat("stain", ngon(0.17, 9, 1.25), (0.17, 0.782, 0.27), "+y", mat((0.06, 0.04, 0.028))))
    # Fork on a chain, nailed to the table, tines toward the middle.
    y = 0.782
    fork = mat("steel", rough=0.4)
    outline = [(-0.02, -0.26), (0.02, -0.26), (0.024, 0.0), (0.05, 0.03), (0.05, 0.15), (0.03, 0.15), (0.03, 0.06), (0.01, 0.06),
               (0.01, 0.16), (-0.01, 0.16), (-0.01, 0.06), (-0.03, 0.06), (-0.03, 0.15), (-0.05, 0.15), (-0.05, 0.03), (-0.024, 0.0)]
    fx, fz = -0.31, 0.02
    parts.append(flat("fork", outline, (fx, y + 0.003, fz), "+y", fork, spin=8))
    for i in range(4):
        link = box("chain%d" % i, (0.036, 0.018, 0.07), (fx + 0.045 + i * 0.008, y + 0.008, fz + 0.28 + i * 0.044), mat("iron"))
        parts.append(tilt(link, y=30 if i % 2 else -24))
    return finish("Table", parts, "table", (0.8, 0.78, 1.0))


# ---------------------------------------------------------------- booth seat


def build_booth_seat():
    parts = []
    parts.append(box("base", (0.78, 0.27, 0.43), (0, 0.135, 0), mat("wood_dark"), taper=1.012))
    parts.append(box("kick", (0.8, 0.05, 0.45), (0, 0.025, 0), mat("iron")))
    parts.append(wobble(box("pad", (0.8, 0.14, 0.45), (0, 0.338, 0), mat("oxblood"), bevel=0.03), 0.008, 6))
    # The burst cushion: one rip, one spring. Everything else is plain leather.
    top = 0.41
    rip = [(-0.14, 0.05), (0.0, 0.08), (0.15, 0.05), (0.11, -0.07), (-0.1, -0.07)]
    parts.append(flat("rip", rip, (0.12, top, 0.02), "+y", mat("black")))
    tongue = spring("spring", (0.13, 0.41, 0.02), 0.085, 0.05, 0.03, 2.5, 0.0145, mat("steel", rough=0.4), seg=8)
    parts.append(tilt(tongue, x=12, z=8))
    return finish("BoothSeat", parts, "booth_seat", (0.8, 0.45, 0.45), bonus=0.02)


# ---------------------------------------------------------------- coach seat


def build_coach_seat():
    fabric = mat((0.05, 0.07, 0.12))
    iron = mat("iron")
    plank = mat("wood_dark")
    parts = []
    for side in (-1, 1):
        parts.append(tilt(box("leg%d" % side, (0.09, 0.3, 0.32), (side * 0.36, 0.15, -0.02), iron, taper=0.75), z=side * 3))
        parts.append(box("foot%d" % side, (0.13, 0.03, 0.5), (side * 0.36, 0.015, -0.03), iron))
        parts.append(box("arm_post%d" % side, (0.07, 0.17, 0.08), (side * 0.44, 0.53, 0.14), iron))
    parts.append(wobble(box("seat", (0.95, 0.16, 0.5), (0, 0.37, -0.05), fabric, bevel=0.03), 0.007, 7))
    parts.append(box("rail", (0.8, 0.07, 0.14), (0, 0.33, 0.24), iron))
    back = box("back", (0.93, 0.72, 0.09), (0, 0.64, 0.298), fabric, bevel=0.02, taper=0.97)
    parts.append(wobble(tilt(back, z=1.0), 0.006, 8))
    # Armrests. The left one has been eaten by a passenger on a long journey.
    bite = [(-0.24, 0.6), (0.27, 0.6), (0.27, 0.665), (0.02, 0.67), (-0.02, 0.64), (-0.07, 0.61), (-0.12, 0.64),
            (-0.15, 0.61), (-0.2, 0.645), (-0.24, 0.665)]
    parts.append(prism("armL", bite, 0.1, (-0.43, 0, 0), plank, plane="zy"))
    parts.append(box("armR", (0.1, 0.07, 0.51), (0.43, 0.635, 0.015), plank))
    return finish("CoachSeat", parts, "coach_seat", (0.95, 1.0, 0.6))


# ---------------------------------------------------------------- ceiling lamp


def build_lamp():
    light = mat((1.0, 0.68, 0.3), emission=2.0)
    brass = mat("brass", metal=0.3, rough=0.5)
    mount = [box("plate", (0.3, 0.03, 0.3), (0.02, -0.015, 0.0), mat("iron"))]
    hang = [cyl("neck", 0.1, 0.05, (0, -0.05, 0), brass, verts=8, top_radius=0.07)]
    hang.append(cyl("bowl", 0.19, 0.13, (0, -0.135, 0), light, verts=10, top_radius=0.235))
    hang.append(cyl("rim", 0.255, 0.03, (0, -0.075, 0), brass, verts=10))
    # One moth. It has made its choice.
    wing = mat("wood_dark")
    for sign in (-1, 1):
        outline = [(0.0, 0.03), (sign * 0.14, 0.07), (sign * 0.17, 0.0), (0.0, -0.05)]
        if sign < 0:
            outline.reverse()
        hang.append(prism("w%d" % sign, outline, 0.012, (0.02, -0.135, -0.215), wing, plane="xy"))
    body = join("hang", hang)
    tilt(body, z=4.0, x=3.0)
    return finish("Lamp", [body] + mount, "ceiling_lamp", (0.5, 0.2, 0.5), offset=(0, -0.2, 0),
                  views={"back": (0.45, -0.3, -1.0)}, shaded=False)


BUILDERS = {
    "boiler": build_boiler,
    "coal_bin": build_coal_bin,
    "counter": build_counter,
    "table": build_table,
    "booth_seat": build_booth_seat,
    "coach_seat": build_coach_seat,
    "ceiling_lamp": build_lamp,
}

wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(BUILDERS)
wacky.reset_scene()
for key in wanted:
    print("== build", key)
    BUILDERS[key]()
