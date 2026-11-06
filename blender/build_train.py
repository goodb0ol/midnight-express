"""Builds the train group of The Midnight Express (see docs/ART_BRIEF.md).

  blender.exe --background --python blender/build_train.py [-- name name ...]

With no names it builds everything. Names are the file stems, e.g. car_coach nose.
Every position is a Godot coordinate. wacky.py converts them.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import wacky  # noqa: E402
from wacky import gv  # noqa: E402

OUT = "assets/models/train/"
PREVIEW = "assets/previews/train/"
EXTRA = os.environ.get("TRAIN_SHOTS", "")

WINDOWS = (-6.5, -4.0, 2.0, 4.5, 7.0)
DOOR = (-1.7, -0.3, 0.0, 2.2)
HOLES = [DOOR] + [(c - 0.75, c + 0.75, 0.85, 1.95) for c in WINDOWS]
# Solid wall stretches, handy for hanging signs on.
PILLARS = {"front": -8.12, "mid_a": -2.48, "mid_b": 0.47, "pair_a": 3.25, "pair_b": 5.75, "rear": 8.38}

INK = (0.012, 0.012, 0.015)
BISTRO_HULL = (0.2, 0.05, 0.055)
COACH_HULL = (0.05, 0.075, 0.14)
LOCO_HULL = (0.035, 0.06, 0.042)
LOCO_DARK = (0.016, 0.024, 0.02)
LOCO_LINER = (0.035, 0.044, 0.036)
LOCO_FLOOR = (0.05, 0.05, 0.045)
PLANK_A = (0.2, 0.13, 0.07)
PLANK_B = (0.13, 0.08, 0.045)
WALLPAPER = (0.045, 0.017, 0.019)
CEILING_WARM = (0.1, 0.066, 0.038)
CARPET_WARM = (0.1, 0.035, 0.03)
RUNNER_WARM = (0.17, 0.05, 0.045)
ROOF_WARM = (0.06, 0.02, 0.022)
COACH_LINER = (0.025, 0.036, 0.062)
CEILING_COLD = (0.1, 0.11, 0.14)
CARPET_COLD = (0.05, 0.06, 0.09)
ROOF_COLD = (0.02, 0.027, 0.05)
GLOW_EYE = (1.0, 0.8, 0.4)
LAMP_GLOW = (1.0, 0.68, 0.32)

# Baked light: (x, y, z, radius, strength). The two real ceiling lamps sit at z=+-4.5.
LAMPS = [(0.0, 2.3, -4.5, 5.2, 1.0), (0.0, 2.3, 4.5, 5.2, 1.0)]
FURNACE = (0.0, 0.5, -4.1, 4.4, 1.3, (1.0, 0.42, 0.14))
BISTRO_SCONCES = (-5.25, -2.48, 0.47, 3.25, 5.75)

_glyphs = {}


def rot(rx=0.0, ry=0.0, rz=0.0):
    """Rotation in Godot axes, degrees."""
    return (Matrix.Rotation(math.radians(rz), 4, gv(0, 0, 1))
            @ Matrix.Rotation(math.radians(ry), 4, gv(0, 1, 0))
            @ Matrix.Rotation(math.radians(rx), 4, gv(1, 0, 0)))


def facing(center, normal, roll=0.0):
    """Matrix taking a local plane (X right, Y up, +Z out) to a Godot wall.

    [normal] is one of +x -x +y -y +z -z and is the side the viewer stands on.
    """
    axes = {"+x": (1, 0, 0), "-x": (-1, 0, 0), "+y": (0, 1, 0), "-y": (0, -1, 0), "+z": (0, 0, 1), "-z": (0, 0, -1)}
    n = Vector(axes[normal])
    up = Vector((0, 0, -1)) if normal == "+y" else Vector((0, 0, 1)) if normal == "-y" else Vector((0, 1, 0))
    right = up.cross(n)
    basis = Matrix.Identity(4)
    basis.col[0] = (*gv(*right), 0.0)
    basis.col[1] = (*gv(*up), 0.0)
    basis.col[2] = (*gv(*n), 0.0)
    basis.col[3] = (*gv(*center), 1.0)
    return basis @ Matrix.Rotation(math.radians(roll), 4, "Z")


def _glyph(char, fat=0.03):
    key = (char, fat)
    if key in _glyphs:
        return _glyphs[key]
    curve = bpy.data.curves.new("glyph", "FONT")
    curve.body = char
    curve.size = 1.0
    curve.resolution_u = 1
    curve.offset = fat
    obj = bpy.data.objects.new("glyph", curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    verts = [tuple(v.co) for v in mesh.vertices]
    faces = [tuple(p.vertices) for p in mesh.polygons]
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(curve)
    bpy.data.meshes.remove(mesh)
    _glyphs[key] = (verts, faces)
    return _glyphs[key]


def clear_rects(y0, y1, z0=-9.0, z1=9.0):
    """Wall rectangles (z0, z1, y0, y1) inside the band that dodge every hole."""
    edges = {z0, z1}
    for hole in HOLES:
        for edge in hole[:2]:
            if z0 < edge < z1:
                edges.add(edge)
    edges = sorted(edges)
    out = []
    for a, b in zip(edges, edges[1:]):
        mid = (a + b) * 0.5
        spans = [(y0, y1)]
        for hole in HOLES:
            if hole[0] < mid < hole[1]:
                next_spans = []
                for low, high in spans:
                    if hole[2] > low:
                        next_spans.append((low, min(high, hole[2])))
                    if hole[3] < high:
                        next_spans.append((max(low, hole[3]), high))
                spans = [s for s in next_spans if s[1] - s[0] > 0.001]
        out.extend((a, b, low, high) for low, high in spans)
    # Merge neighbours with the same height, so a plain stretch stays one box.
    merged = []
    for rect in out:
        for i, other in enumerate(merged):
            if abs(other[1] - rect[0]) < 1e-6 and other[2:] == rect[2:]:
                merged[i] = (other[0], rect[1], rect[2], rect[3])
                break
        else:
            merged.append(rect)
    return merged


class Kit:
    """Collects the pieces of one object, then joins them."""

    def __init__(self, seed=1):
        self.parts = []
        self.rng = random.Random(seed)

    def add(self, obj):
        self.parts.append(obj)
        return obj

    def done(self, name):
        return wacky.join(name, self.parts)

    def jitter(self, amount):
        return self.rng.uniform(-amount, amount)

    def box(self, size, center, material, turn=None, taper=1.0, wob=0.0, bevel=0.0):
        obj = wacky.box("p", size, center, wacky_mat(material), taper=taper, bevel=bevel)
        if wob:
            wacky.wobble(obj, wob, self.rng.randint(1, 9999))
        if turn:
            obj.data.transform(rot(*turn))
            obj.data.update()
        return self.add(obj)

    def cyl(self, radius, height, center, material, axis="y", verts=8, top=None, turn=None, wob=0.0):
        obj = wacky.cyl("p", radius, height, center, wacky_mat(material), axis=axis, verts=verts, top_radius=top)
        if wob:
            wacky.wobble(obj, wob, self.rng.randint(1, 9999))
        if turn:
            obj.data.transform(rot(*turn))
            obj.data.update()
        return self.add(obj)

    def ball(self, radius, center, material, squash=(1, 1, 1), detail=1, wob=0.0, turn=None):
        obj = wacky.ball("p", radius, center, wacky_mat(material), squash=squash, detail=detail)
        if wob:
            wacky.wobble(obj, wob, self.rng.randint(1, 9999))
        if turn:
            obj.data.transform(rot(*turn))
            obj.data.update()
        return self.add(obj)

    def pipe(self, a, b, radius, material, verts=6, end=None):
        """Cylinder between two Godot points. [end] tapers it at b."""
        a_v, b_v = gv(*a), gv(*b)
        delta = b_v - a_v
        obj = wacky.cyl("p", radius, delta.length, (0, 0, 0), wacky_mat(material), verts=verts, top_radius=end)
        obj.data.transform(delta.to_track_quat("Z", "Y").to_matrix().to_4x4())
        obj.data.update()
        obj.location = (a_v + b_v) * 0.5
        return self.add(obj)

    def path(self, points, radius, material, verts=6):
        for a, b in zip(points, points[1:]):
            self.pipe(a, b, radius, material, verts)

    def deck(self, center, width, height, normal, material, roll=0.0):
        """One flat quad, two triangles, facing [normal]."""
        return self.blob(center, width, height, normal, material, sides=4, roll=roll, wob=0.0, square=True)

    def blob(self, center, width, height, normal, material, sides=7, roll=0.0, wob=0.25, square=False):
        """Flat wobbly stain or patch."""
        mat = facing(center, normal, roll)
        bm = bmesh.new()
        ring = []
        for i in range(sides):
            angle = math.tau * (i + (0.5 if square else 0.0)) / sides
            scale = (1.0 + self.jitter(wob)) * (math.sqrt(2.0) if square else 1.0)
            co = Vector((math.cos(angle) * width * 0.5 * scale, math.sin(angle) * height * 0.5 * scale, 0.0))
            ring.append(bm.verts.new(mat @ co))
        bm.faces.new(ring)
        return self._flat(bm, material)

    def poly(self, center, points, normal, material, roll=0.0):
        """Flat polygon from local (x, y) points, counter-clockwise."""
        mat = facing(center, normal, roll)
        bm = bmesh.new()
        ring = [bm.verts.new(mat @ Vector((x, y, 0.0))) for x, y in points]
        bm.faces.new(ring)
        return self._flat(bm, material)

    def _flat(self, bm, material):
        mesh = bpy.data.meshes.new("p")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(wacky_mat(material))
        obj = bpy.data.objects.new("p", mesh)
        bpy.context.scene.collection.objects.link(obj)
        return self.add(obj)

    def panel(self, center, width, height, thick, normal, material, roll=0.0):
        """Box lying on a wall: width and height along the wall, thick along [normal]."""
        mat = facing(center, normal, roll)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(width, height, thick), verts=bm.verts)
        bmesh.ops.transform(bm, matrix=mat, verts=bm.verts)
        return self.add(wacky._finish("p", bm, (0, 0, 0), wacky_mat(material)))

    def text(self, string, center, size, normal, material, roll=0.0, crook=3.0, track=0.08, fat=0.03):
        """Letters as one flat mesh. [size] is the cap height. Each letter sits a bit wrong.

        [fat] thickens the strokes, for words that have to read from the next field.
        """
        scale = size / 0.73
        laid = []
        cursor = 0.0
        for char in string:
            if char == " ":
                cursor += size * 0.55
                continue
            verts, faces = _glyph(char, fat)
            xs = [v[0] for v in verts] or [0.0]
            low, high = min(xs) * scale, max(xs) * scale
            laid.append((verts, faces, cursor - low, high - low))
            cursor += high - low + track * size
        total = cursor - track * size
        mat = facing(center, normal, roll)
        out_verts = []
        out_faces = []
        for verts, faces, offset, width in laid:
            tilt = math.radians(self.jitter(crook))
            bump = self.jitter(crook) * 0.006 * size
            cos_t, sin_t = math.cos(tilt), math.sin(tilt)
            base = len(out_verts)
            for x, y, _z in verts:
                lx = x * scale - width * 0.5
                ly = y * scale - size * 0.5
                px = lx * cos_t - ly * sin_t + offset + width * 0.5 - total * 0.5
                py = lx * sin_t + ly * cos_t + bump
                out_verts.append(tuple(mat @ Vector((px, py, 0.0))))
            out_faces.extend(tuple(i + base for i in face) for face in faces)
        mesh = bpy.data.meshes.new("p")
        mesh.from_pydata(out_verts, [], out_faces)
        mesh.materials.append(wacky_mat(material))
        mesh.update()
        obj = bpy.data.objects.new("p", mesh)
        bpy.context.scene.collection.objects.link(obj)
        return self.add(obj)

    def sign(self, center, width, height, normal, lines, board, ink, size, roll=0.0, thick=0.04, nails=True, fat=0.03):
        """Board with text, hanging a bit wrong. [lines] is a list of strings."""
        self.panel(center, width, height, thick, normal, board, roll)
        axis = {"+x": (1, 0, 0), "-x": (-1, 0, 0), "+y": (0, 1, 0), "-y": (0, -1, 0), "+z": (0, 0, 1), "-z": (0, 0, -1)}[normal]
        lift = thick * 0.5 + 0.006
        top = facing(center, normal, roll)
        step = size * 1.35
        start = (len(lines) - 1) * step * 0.5
        for i, line in enumerate(lines):
            co = top @ Vector((0.0, start - i * step, lift))
            g = (co.x, co.z, -co.y)
            self.text(line, g, size, normal, ink, roll, fat=fat)
        if nails:
            co = top @ Vector((-width * 0.42, height * 0.36, lift))
            self.cyl(0.03, 0.03, (co.x, co.z, -co.y), "steel", axis=normal[1], verts=5)
            co = top @ Vector((width * 0.42, height * 0.36, lift))
            self.cyl(0.03, 0.03, (co.x, co.z, -co.y), "steel", axis=normal[1], verts=5)

    def frame(self, side, z0, z1, y0, y1, wide, x0, x1, material, skew=0.05):
        """Ring round a hole. The inner edge is exact, the outer edge is drunk."""
        inner = [(z0, y0), (z1, y0), (z1, y1), (z0, y1)]
        signs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        outer = [(z + sz * wide + self.jitter(skew), y + sy * wide + self.jitter(skew))
                 for (z, y), (sz, sy) in zip(inner, signs)]
        bm = bmesh.new()

        def vert(x, z, y):
            return bm.verts.new(gv(side * x, y, z))

        front_in = [vert(x1, z, y) for z, y in inner]
        front_out = [vert(x1, z, y) for z, y in outer]
        back_in = [vert(x0, z, y) for z, y in inner]
        back_out = [vert(x0, z, y) for z, y in outer]
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((front_in[i], front_in[j], front_out[j], front_out[i]))
            bm.faces.new((back_in[i], back_in[j], back_out[j], back_out[i]))
            bm.faces.new((front_in[i], front_in[j], back_in[j], back_in[i]))
            bm.faces.new((front_out[i], front_out[j], back_out[j], back_out[i]))
        return self.add(wacky._finish("p", bm, (0, 0, 0), wacky_mat(material)))

    def ring(self, center, outer, inner, normal, material, roll=0.0, sides=14, stretch=1.15):
        """Flat round ring, a touch taller than wide, like a proper letter O."""
        mat = facing(center, normal, roll)
        bm = bmesh.new()
        outside = []
        within = []
        for i in range(sides):
            angle = math.tau * i / sides
            cos_a, sin_a = math.cos(angle), math.sin(angle) * stretch
            outside.append(bm.verts.new(mat @ Vector((cos_a * outer, sin_a * outer, 0.0))))
            within.append(bm.verts.new(mat @ Vector((cos_a * inner, sin_a * inner, 0.0))))
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((outside[i], outside[j], within[j], within[i]))
        return self._flat(bm, material)

    def tri(self, a, b, c, out, material):
        """One flat triangle from Godot points, turned so it faces [out]."""
        bm = bmesh.new()
        face = bm.faces.new([bm.verts.new(gv(*p)) for p in (a, b, c)])
        face.normal_update()
        if face.normal.dot(gv(*out)) < 0.0:
            face.normal_flip()
        return self._flat(bm, material)

    def rail_run(self, points, y, material, thick=0.08):
        """Square rail through (x, z) points, kinked in plan so the top stays dead level."""
        for (x0, z0), (x1, z1) in zip(points, points[1:]):
            dx, dz = x1 - x0, z1 - z0
            length = math.hypot(dx, dz) + thick * 0.6
            yaw = math.degrees(math.atan2(dx, dz))
            self.box((thick, thick, length), ((x0 + x1) * 0.5, y, (z0 + z1) * 0.5), material, turn=(0, yaw, 0))

    def tilt_since(self, start, pivot, turn):
        """Rotates every part added since index [start] about Godot [pivot]."""
        where = gv(*pivot)
        move = Matrix.Translation(where) @ rot(*turn) @ Matrix.Translation(-where)
        for obj in self.parts[start:]:
            obj.matrix_basis = move @ obj.matrix_basis

    def splinters(self, center, reach_x, reach_z, tip_y, colours, count=10, thick=0.1):
        """Torn ceiling: fat shards bent down into the room round a hole."""
        for i in range(count):
            angle = math.tau * (i + self.jitter(0.3)) / count
            cos_a, sin_a = math.cos(angle), math.sin(angle)
            rim = (center[0] + cos_a * reach_x, 2.69, center[1] + sin_a * reach_z)
            reach = 0.72 + self.jitter(0.1)
            tip = (center[0] + cos_a * reach_x * reach, tip_y + self.jitter(0.05), center[1] + sin_a * reach_z * reach)
            self.pipe(rim, tip, thick, colours[i % len(colours)], verts=4, end=0.015)

    def hanger(self, x, z, normal, lines, board, ink, size, wide, tall=0.34, y=2.46, roll=2.5):
        """Board on two chains under the ceiling, readable down the corridor."""
        for off in (-0.42, 0.42):
            self.pipe((x + off * wide, 2.7, z), (x + off * wide, y + tall * 0.4, z), 0.018, "steel", verts=4)
        self.sign((x, y, z), wide, tall, normal, lines, board, ink, size, roll=roll, thick=0.03, nails=False, fat=0.05)

    def prism(self, profile, z0, z1, material):
        """Extrudes an (x, y) outline along Z."""
        bm = bmesh.new()
        a = [bm.verts.new(gv(x, y, z0)) for x, y in profile]
        b = [bm.verts.new(gv(x, y, z1)) for x, y in profile]
        for i in range(len(profile)):
            j = (i + 1) % len(profile)
            bm.faces.new((a[i], a[j], b[j], b[i]))
        bm.faces.new(a)
        bm.faces.new(list(reversed(b)))
        return self.add(wacky._finish("p", bm, (0, 0, 0), wacky_mat(material)))


def bake_interior(k, pools, step=0.75):
    """Joins the cabin, then paints the lamp light into its vertices."""
    wacky.bake_pools(k.done("Interior"), pools, step=step)


def wacky_mat(material):
    if isinstance(material, (str, tuple)):
        return wacky.mat(material)
    return material


# ---------------------------------------------------------------- shared car parts


def swayed_roof(k, material, stations):
    """Roof crown that sags and rolls along the car. [stations] is (z, sag, roll, drift).

    The slab under it stays flat for collision, only the crown and the eaves go wrong.
    """
    base = [(-1.96, 2.86), (-1.96, 2.94), (-1.5, 3.08), (-0.75, 3.18), (0.75, 3.15), (1.5, 3.07), (1.96, 2.93), (1.96, 2.86)]
    last = len(base) - 1
    bm = bmesh.new()
    rings = []
    for z, sag, roll, drift in stations:
        ring = []
        for i, (x, y) in enumerate(base):
            lift = roll * x / 1.96
            if i in (0, last):
                # Eave lip: droops with the sag, which is what you see from ten metres.
                ny = y + sag * 0.9 + lift
                nx = x
            elif i in (1, last - 1):
                ny = max(y + sag * 0.5 + lift, 2.91)
                nx = x
            else:
                ny = y + sag + lift
                nx = x + drift
            ring.append(bm.verts.new(gv(nx, ny, z)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(len(base)):
            j = (i + 1) % len(base)
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    return k.add(wacky._finish("p", bm, (0, 0, 0), wacky_mat(material)))


def shell(k, hull, floor, roof, stations, solid_front=False):
    """Hull with holes that are exactly the sizes in the brief."""
    k.box((3.8, 0.25, 18.0), (0, -0.125, 0), floor)
    k.box((3.8, 0.2, 18.0), (0, 2.8, 0), roof)
    for side in (-1, 1):
        for z0, z1, y0, y1 in clear_rects(0.0, 2.7):
            k.box((0.2, y1 - y0, z1 - z0), (side * 1.8, (y0 + y1) * 0.5, (z0 + z1) * 0.5), hull)
    if solid_front:
        k.box((3.4, 2.7, 0.2), (0, 1.35, -8.9), hull)
    else:
        end_wall(k, -8.9, hull)
    end_wall(k, 8.9, hull)
    swayed_roof(k, roof, stations)


def end_wall(k, z, hull):
    for side in (-1, 1):
        k.box((1.05, 2.7, 0.2), (side * 1.175, 1.35, z), hull)
    k.box((1.3, 0.5, 0.2), (0, 2.45, z), hull)


def wheel(k, x, y, z, radius, style):
    if style == "square":
        k.cyl(radius, 0.18, (x, y, z), "iron", axis="x", verts=4)
        k.cyl(0.12, 0.26, (x, y, z), "tomato", axis="x", verts=6)
    elif style == "wagon":
        k.cyl(radius, 0.1, (x, y, z), "wood", axis="x", verts=10)
        k.cyl(radius * 0.8, 0.13, (x, y, z), "wood_dark", axis="x", verts=10)
        k.cyl(0.13, 0.22, (x, y, z), "brass", axis="x", verts=6)
        for angle in (0, 60, 120):
            k.box((0.16, radius * 1.7, 0.08), (x, y, z), "wood", turn=(angle, 0, 0))
    elif style == "tiny":
        lift = radius - 0.2
        # A pram wheel, propped up on a stack of hymn books.
        k.cyl(0.2, 0.1, (x, y - lift + 0.14 - 0.14 + 0.16, z), "white", axis="x", verts=8)
        k.cyl(0.08, 0.14, (x, y - lift + 0.16, z), "tomato", axis="x", verts=6)
        for i, colour in enumerate(("tomato", "teal", "mustard")):
            k.box((0.24, 0.09, 0.36), (x, y - radius + 0.05 + i * 0.09, z), colour, turn=(0, 6 * i - 5, 0))
    else:
        k.cyl(radius, 0.16, (x, y, z), "iron", axis="x", verts=10)
        k.cyl(radius * 0.72, 0.2, (x, y, z), "rust", axis="x", verts=10)
        k.cyl(0.12, 0.26, (x, y, z), "steel", axis="x", verts=6)


def bogie(k, z, styles):
    """Two axles under the car. [styles] picks a wheel per corner."""
    k.box((2.2, 0.32, 2.8), (0, -0.58, z), "iron", turn=(1.2, 0, 0.6), taper=0.96)
    k.box((1.5, 0.3, 0.5), (0, -0.33, z), "coal")
    corner = 0
    for offset in (-0.8, 0.8):
        k.cyl(0.07, 1.8, (0, -0.88, z + offset), "steel", axis="x", verts=6)
        for side in (-1, 1):
            wheel(k, side * 0.78, -0.88, z + offset, 0.42, styles[corner])
            corner += 1
    for side in (-1, 1):
        k.box((0.14, 0.14, 2.2), (side * 1.05, -0.5, z), "rust", turn=(2 * side, 0, 0))
        for i in range(3):
            k.box((0.16, 0.06, 1.3 - i * 0.35), (side * 1.05, -0.6 - i * 0.06, z), "steel")


def belly(k, tank="iron"):
    k.box((1.3, 0.28, 11.0), (0, -0.4, 0), "coal")
    k.cyl(0.32, 3.6, (0.2, -0.62, 0), tank, axis="z", verts=8, turn=(0, 0, 3))
    for z in (-1.2, 1.2):
        k.cyl(0.34, 0.08, (0.2, -0.62, z), "rust", axis="z", verts=8)


def racks(k, side, z0, z1, rail, bracket):
    """Luggage rack, all of it above y=2.25."""
    x = side * 1.5
    for off in (-0.14, 0.14):
        k.box((0.1, 0.1, z1 - z0), (x + off, 2.3, (z0 + z1) * 0.5), rail)
    z = z0 + 0.4
    while z < z1:
        k.box((0.42, 0.06, 0.08), (side * 1.47, 2.3, z), bracket)
        k.box((0.06, 0.3, 0.08), (side * 1.665, 2.43, z), bracket)
        z += 1.9


def liner_layers(k, wain_top, wain, liner, trim):
    """Faces the cabin sees: flat quads on the walls, so the car stays under budget."""
    for side in (-1, 1):
        normal = "-x" if side > 0 else "+x"
        x = side * 1.69
        for z0, z1, y0, y1 in clear_rects(0.0, wain_top):
            k.deck((x, (y0 + y1) * 0.5, (z0 + z1) * 0.5), z1 - z0, y1 - y0, normal, wain)
        for z0, z1, y0, y1 in clear_rects(wain_top, 2.7):
            k.deck((x, (y0 + y1) * 0.5, (z0 + z1) * 0.5), z1 - z0, y1 - y0, normal, liner)
        for z0, z1, y0, y1 in clear_rects(wain_top - 0.05, wain_top + 0.03):
            k.deck((side * 1.685, (y0 + y1) * 0.5, (z0 + z1) * 0.5), z1 - z0, y1 - y0, normal, trim)
        k.frame(side, DOOR[0], DOOR[1], DOOR[2], DOOR[3], 0.09, 1.68, 1.7, trim, skew=0.03)
        for c in WINDOWS:
            k.frame(side, c - 0.75, c + 0.75, 0.85, 1.95, 0.08, 1.68, 1.7, trim, skew=0.03)
            k.frame(side, c - 0.744, c + 0.744, 0.856, 1.944, 0.03, 1.7, 1.9, trim, skew=0.0)
        k.frame(side, DOOR[0] + 0.006, DOOR[1] - 0.006, DOOR[2] + 0.006, DOOR[3] - 0.006, 0.03, 1.7, 1.9, trim, skew=0.0)


def end_lining(k, z, normal, liner, trim, solid=False):
    face = z
    if solid:
        k.deck((0, 1.35, face), 3.4, 2.7, normal, liner)
        return
    for side in (-1, 1):
        k.deck((side * 1.175, 1.35, face), 1.05, 2.7, normal, liner)
    k.deck((0, 2.45, face), 1.3, 0.5, normal, liner)
    towards = -1 if z > 0 else 1
    wide = 0.1
    k.box((wide, 2.3, 0.08), (-0.72, 1.15, z + towards * 0.04), trim, turn=(0, 0, 0.8))
    k.box((wide, 2.3, 0.08), (0.72, 1.15, z + towards * 0.04), trim, turn=(0, 0, -0.6))
    k.box((1.64, wide, 0.08), (0, 2.25, z + towards * 0.04), trim)


def cabin(k, carpet, ceiling, liner, trim, solid_front=False):
    k.deck((0, 0.01, 0), 3.4, 17.6, "+y", carpet)
    k.deck((0, 2.69, 0), 3.4, 17.6, "-y", ceiling)
    end_lining(k, -8.79, "+z", liner, trim, solid=solid_front)
    end_lining(k, 8.79, "-z", liner, trim)


# ---------------------------------------------------------------- locomotive


def stuck_stoker(k, x, z):
    """Corridor gag: the last man to check the safety valve, from the knees down."""
    k.blob((x, 2.684, z), 1.7, 1.9, "-y", INK, sides=9, wob=0.2)
    k.splinters((x, z), 0.82, 0.92, 2.44, ("iron", LOCO_DARK, "rust"), count=8, thick=0.14)
    # Left leg: dangling, boot still laced.
    k.pipe((x - 0.22, 2.7, z), (x - 0.26, 2.46, z + 0.04), 0.14, "tomato", verts=7)
    k.box((0.34, 0.2, 0.66), (x - 0.27, 2.36, z - 0.14), "black", taper=0.86, turn=(-6, 8, 0), wob=0.012)
    # Right leg: mid-kick, boot gone, sock not up to the job.
    k.pipe((x + 0.22, 2.7, z), (x + 0.44, 2.46, z + 0.16), 0.14, "tomato", verts=7)
    k.box((0.3, 0.24, 0.58), (x + 0.46, 2.39, z - 0.06), "bone", taper=0.9, turn=(-10, -16, 0), wob=0.012)


def car_locomotive():
    k = Kit(13)
    shell(k, LOCO_HULL, "iron", LOCO_DARK, [
        (-9.05, 0.0, 0.0, 0.0), (-6.5, -0.05, 0.03, 0.03), (-3.5, -0.1, 0.05, 0.06), (-0.5, -0.13, 0.03, 0.02),
        (2.5, -0.1, -0.03, -0.05), (5.0, -0.04, -0.05, -0.04), (7.0, -0.08, -0.03, 0.0), (9.05, -0.01, 0.02, 0.02)],
        solid_front=True)
    for side in (-1, 1):
        outside = "+x" if side > 0 else "-x"
        k.frame(side, DOOR[0], DOOR[1], DOOR[2], DOOR[3], 0.12, 1.88, 1.96, LOCO_DARK)
        for c in WINDOWS:
            k.frame(side, c - 0.75, c + 0.75, 0.85, 1.95, 0.1, 1.88, 1.95, LOCO_DARK)
        for z0, z1, y0, y1 in clear_rects(0.0, 0.34):
            k.box((0.05, y1 - y0, z1 - z0), (side * 1.92, (y0 + y1) * 0.5, (z0 + z1) * 0.5), LOCO_DARK)
        # One fat pipe, with a nervous breakdown halfway along.
        k.path([(side * 2.0, 2.34, -9.0), (side * 2.0, 2.3, -0.9), (side * 2.14, 2.56, -0.2),
                (side * 2.0, 2.32, 0.4), (side * 2.0, 2.36, 9.0)], 0.09, "iron")
        # Number plate that could not commit to a number.
        k.panel((side * 1.93, 1.25, PILLARS["mid_a"]), 1.3, 0.9, 0.05, outside, "brass", roll=3 * side)
        k.panel((side * 1.955, 1.25, PILLARS["mid_a"]), 1.14, 0.74, 0.02, outside, LOCO_DARK, roll=3 * side)
        k.text("No.13", (side * 1.97, 1.38, PILLARS["mid_a"]), 0.3, outside, "brass", roll=3 * side, track=0.2)
        k.text("AND A HALF", (side * 1.97, 1.05, PILLARS["mid_a"]), 0.12, outside, "brass", roll=3 * side)
    # Roof: big plain shapes, and one line of washing.
    k.cyl(0.6, 0.46, (0.75, 3.2, -4.2), "iron", verts=8, top=0.7, turn=(7, 0, 6))
    k.cyl(0.9, 0.09, (0.8, 3.41, -4.17), "iron", verts=8, turn=(-5, 0, 6))
    k.pipe((-0.95, 2.98, -2.6), (-0.95, 3.22, -2.0), 0.3, "iron", verts=8)
    k.box((0.1, 0.62, 0.1), (-1.0, 3.26, 0.7), "wood_dark", turn=(0, 0, -6))
    k.box((0.1, 0.62, 0.1), (-1.0, 3.26, 4.6), "wood_dark", turn=(4, 0, 4))
    k.path([(-1.0, 3.55, 0.7), (-1.0, 3.45, 2.6), (-1.0, 3.55, 4.6)], 0.03, "iron", verts=4)
    k.box((0.06, 0.2, 0.74), (-1.0, 3.34, 1.7), "tomato", turn=(4, 0, 0))
    k.box((0.06, 0.36, 0.3), (-1.0, 3.16, 1.5), "tomato", turn=(5, 0, 0))
    k.box((0.06, 0.36, 0.3), (-1.0, 3.16, 1.9), "tomato", turn=(5, 0, 0))
    for i in range(10):
        k.ball(0.3 - i * 0.012, (0.5 + k.jitter(0.7), 3.25 - i * 0.004, 7.6 + k.jitter(0.75)), "coal", wob=0.03)
    door_lamps(k)
    belly(k)
    bogie(k, -5.94, ["normal", "square", "normal", "normal"])
    bogie(k, 5.94, ["normal", "normal", "normal", "normal"])
    k.done("Exterior")

    k = Kit(14)
    liner_layers(k, 0.9, LOCO_DARK, LOCO_LINER, "iron")
    cabin(k, LOCO_FLOOR, LOCO_DARK, LOCO_LINER, "iron", solid_front=True)
    for side in (-1, 1):
        # Fat overhead pipes, with a sagging middle. The only thing up here.
        k.path([(side * 1.4, 2.5, -8.8), (side * 1.42, 2.46, -3.0), (side * 1.3, 2.34, 0.0), (side * 1.42, 2.46, 3.0),
                (side * 1.4, 2.5, 8.8)], 0.11, "iron")
        for z in (-6.0, -2.0, 2.0, 6.0):
            k.box((0.3, 0.14, 0.14), (side * 1.52, 2.54, z), "black")
    # One sign in the whole engine room, on the wall you face when you shovel.
    k.sign((-1.689, 1.5, PILLARS["mid_b"]), 1.2, 0.84, "+x", ["DAYS SINCE", "LAST FIRE", "0"], "bone", "black", 0.15,
           roll=-3, thick=0.004, nails=False)
    stuck_stoker(k, 0.0, 0.5)
    bake_interior(k, LAMPS + [FURNACE], step=1.0)
    finish("car_locomotive", ((0, 1.55, 8.2), (0, 1.3, -2)), ((9, 1.8, 3), (0, 1.2, 3)),
           gag=((0.5, 1.5, 4.0), (0, 2.45, 0.5)))


# ---------------------------------------------------------------- bistro


def letter_sign(k, side):
    """Grand board over the windows. The O gave up and hangs by one bolt."""
    outside = "+x" if side > 0 else "-x"
    fx = side * 1.905
    mid = 3.15 if side < 0 else 2.6
    k.panel((fx + side * 0.075, 2.41, mid), 3.9, 0.6, 0.04, outside, "black", roll=1.2 * side)
    letters = [("B", 1.58), ("I", 2.1), ("S", 2.6), ("T", 3.2), ("R", 3.84)]
    for char, z in letters:
        k.text(char, (fx + side * 0.1, 2.42 + k.jitter(0.02), z if side < 0 else 5.75 - z), 0.46, outside,
               wacky.mat("brass", emission=0.6), roll=k.jitter(4), crook=0, fat=0.09)
    z = 4.5 if side < 0 else 1.25
    z_o = z + (0.26 if side < 0 else -0.26)
    k.cyl(0.05, 0.16, (side * 2.02, 2.62, z_o), "steel", axis="x", verts=5)
    # Bottom stays above the window hole.
    k.ring((side * 2.04, 2.27, z_o + 0.02), 0.25, 0.13, outside, "brass", roll=24, sides=14)


def door_lamps(k):
    """A lit lamp over each side door: the only warmth you see from out in the snow."""
    for side in (-1, 1):
        k.box((0.3, 0.06, 0.08), (side * 2.0, 2.42, -1.0), "iron")
        k.cyl(0.15, 0.22, (side * 2.1, 2.3, -1.0), wacky.mat(LAMP_GLOW, emission=1.5), verts=7, top=0.1)


def beams(k, zs, material, thick=0.2, drop=0.16):
    """Cross beams under the ceiling: plain, heavy, above head height."""
    for z in zs:
        k.box((3.4, drop, thick), (0, 2.7 - drop * 0.5, z), material)


def sconce(k, side, z):
    """Wall lamp over the windows: a brass arm and one fat warm shade."""
    x = side * 1.68
    k.box((0.26, 0.05, 0.08), (x - side * 0.13, 2.28, z), "brass")
    k.cyl(0.13, 0.17, (side * 1.5, 2.33, z), wacky.mat((0.5, 0.2, 0.05), emission=0.55), verts=7, top=0.09)


def car_bistro():
    k = Kit(21)
    shell(k, BISTRO_HULL, "wood_dark", ROOF_WARM, [
        (-9.05, 0.0, 0.0, 0.0), (-6.5, -0.09, -0.03, 0.03), (-4.5, -0.05, -0.05, 0.05), (-2.0, -0.03, -0.02, 0.02),
        (1.0, -0.13, 0.03, -0.03), (3.5, -0.1, 0.05, -0.05), (6.0, -0.04, 0.04, 0.0), (9.05, -0.02, -0.02, 0.02)])
    for side in (-1, 1):
        fx = side * 1.9
        k.frame(side, DOOR[0], DOOR[1], DOOR[2], DOOR[3], 0.14, 1.88, 1.97, "wood_dark")
        for c in WINDOWS:
            k.frame(side, c - 0.75, c + 0.75, 0.85, 1.95, 0.11, 1.88, 1.96, "wood_dark", skew=0.07)
        for z0, z1, y0, y1 in clear_rects(0.0, 0.72):
            k.box((0.04, y1 - y0, z1 - z0), (fx + side * 0.02, (y0 + y1) * 0.5, (z0 + z1) * 0.5), "wood_dark")
        k.box((0.05, 0.1, 18.0), (fx + side * 0.03, 2.66, 0), "brass")
        letter_sign(k, side)
    # Roof: the stock pot that feeds the whole train, and one stove pipe.
    k.box((2.0, 0.2, 2.0), (0.2, 3.1, -2.9), "wood_dark", turn=(0, 8, 2))
    k.cyl(0.84, 0.36, (0.2, 3.32, -2.9), "steel", verts=10, top=0.9, turn=(2, 0, 2))
    k.cyl(0.98, 0.07, (0.26, 3.45, -2.78), "iron", verts=10, turn=(-4, 0, 5))
    k.path([(-1.05, 2.98, 3.0), (-1.05, 3.18, 3.1), (-1.0, 3.33, 3.45)], 0.2, "iron", verts=8)
    k.cyl(0.36, 0.05, (-0.98, 3.39, 3.5), "black", verts=8, turn=(8, 0, -6))
    k.cyl(0.22, 0.13, (-0.98, 3.46, 3.5), "black", verts=8, turn=(8, 0, -6))
    door_lamps(k)
    belly(k)
    bogie(k, -5.94, ["normal", "normal", "normal", "normal"])
    bogie(k, 5.94, ["normal", "normal", "normal", "normal"])
    k.done("Exterior")

    k = Kit(22)
    liner_layers(k, 0.95, "wood_dark", WALLPAPER, "wood_dark")
    cabin(k, CARPET_WARM, CEILING_WARM, WALLPAPER, "wood_dark")
    beams(k, (-7.5, -2.5, 0.5, 2.5, 7.5), "wood_dark")
    for side in (-1, 1):
        for z in BISTRO_SCONCES:
            sconce(k, side, z)
    # Portrait of the founder, a bowl of soup with a moustache. Only one. He would not share.
    pz = PILLARS["mid_a"]
    k.frame(-1, pz - 0.46, pz + 0.46, 0.95, 2.02, 0.09, 1.68, 1.69, "brass", skew=0.02)
    k.deck((-1.688, 1.48, pz), 0.92, 1.07, "+x", (0.05, 0.1, 0.09))
    k.blob((-1.685, 1.32, pz), 0.62, 0.4, "+x", "bone", sides=8, wob=0.05)
    k.blob((-1.683, 1.72, pz - 0.14), 0.15, 0.2, "+x", "white", sides=7, wob=0.05)
    k.blob((-1.683, 1.72, pz + 0.16), 0.2, 0.15, "+x", "white", sides=7, wob=0.05)
    k.blob((-1.682, 1.72, pz - 0.14), 0.05, 0.05, "+x", "black", sides=5, wob=0.05)
    k.blob((-1.682, 1.72, pz + 0.16), 0.05, 0.05, "+x", "black", sides=5, wob=0.05)
    k.blob((-1.684, 1.55, pz - 0.16), 0.32, 0.1, "+x", "black", sides=6, roll=-14, wob=0.1)
    k.blob((-1.684, 1.55, pz + 0.16), 0.32, 0.1, "+x", "black", sides=6, roll=14, wob=0.1)
    # A plain runner down the aisle. No pattern, no stains.
    k.deck((0, 0.012, 0), 1.7, 17.4, "+y", RUNNER_WARM)
    bake_interior(k, LAMPS + [(s * 1.5, 2.3, z, 2.0, 1.1) for s in (-1, 1) for z in BISTRO_SCONCES])
    finish("car_bistro", ((0, 1.55, 8.2), (0, 1.3, -2)), ((9, 1.8, -2), (0, 1.3, -2)))


# ---------------------------------------------------------------- coach


def plank_patch(k, side, z, y, count, length, slant=0.0):
    outside = "+x" if side > 0 else "-x"
    for i in range(count):
        off = (i - (count - 1) * 0.5) * 0.25
        k.panel((side * 1.93, y + off, z + k.jitter(0.06)), length + k.jitter(0.1), 0.23, 0.05, outside,
                (PLANK_A, PLANK_B)[i % 2], roll=slant + k.jitter(4))


def bath_through_ceiling(k, x, z):
    """Corridor gag: the bath lashed to the roof has come through, feet first. Still in use."""
    k.blob((x, 2.684, z), 2.0, 3.1, "-y", INK, sides=10, wob=0.16)
    k.splinters((x, z), 1.0, 1.5, 2.4, (PLANK_B, "iron"), count=6, thick=0.16)
    k.box((1.02, 0.34, 1.86), (x, 2.53, z), "bone", taper=1.18, turn=(0, 7, 0), wob=0.01)
    turn = rot(0, 7, 0)
    for dx, dz in ((-0.4, -0.72), (0.4, -0.72), (-0.4, 0.72), (0.4, 0.72)):
        co = turn @ Vector((dx, -dz, 0.0))
        px, pz = x + co.x, z - co.y
        k.cyl(0.05, 0.14, (px, 2.32, pz), "brass", verts=5, top=0.1)
        k.ball(0.1, (px, 2.3, pz + 0.04), "brass", squash=(1.2, 0.55, 1.5))
    k.hanger(x, z - 1.75, "-z", ["OCCUPIED"], "bone", "black", 0.2, 1.9)


def car_coach():
    k = Kit(31)
    navy = COACH_HULL
    shell(k, navy, "iron", ROOF_COLD, [
        (-9.05, 0.0, 0.0, 0.0), (-7.0, -0.04, 0.05, 0.05), (-4.0, -0.12, 0.03, 0.03), (-1.0, -0.07, -0.02, 0.0),
        (1.5, -0.14, -0.05, -0.05), (4.0, -0.08, -0.03, -0.02), (6.5, -0.12, 0.03, 0.03), (9.05, -0.02, 0.02, 0.0)])
    for side in (-1, 1):
        outside = "+x" if side > 0 else "-x"
        fx = side * 1.9
        k.frame(side, DOOR[0], DOOR[1], DOOR[2], DOOR[3], 0.12, 1.88, 1.96, "wood_dark")
        for c in WINDOWS:
            k.frame(side, c - 0.75, c + 0.75, 0.85, 1.95, 0.09, 1.88, 1.95, "wood_dark", skew=0.08)
        for z0, z1, y0, y1 in clear_rects(0.0, 0.5):
            k.box((0.04, y1 - y0, z1 - z0), (fx + side * 0.02, (y0 + y1) * 0.5, (z0 + z1) * 0.5), "wood_dark")
        plank_patch(k, side, -8.1, 1.2, 4, 1.15, slant=8)
        plank_patch(k, side, 8.38, 1.55, 4, 0.95, slant=-12)
        k.sign((side * 1.93, 1.32, PILLARS["mid_a"]), 1.26, 0.86, outside, ["CLASS", "4 1/2"], "bone", "black", 0.27,
               roll=-3 * side, nails=False)
    # Roof: everything anyone ever lost, under one heroic rope. Two storeys of it, all one dark.
    k.box((1.5, 0.34, 1.0), (0.3, 3.18, -6.3), "wood", turn=(0, 9, 2))
    k.box((1.1, 0.3, 0.7), (-0.95, 3.2, -5.8), "wood_dark", turn=(0, -11, -3))
    k.box((1.0, 0.28, 0.8), (-0.9, 3.2, -7.0), "wood", turn=(0, 7, 2))
    k.box((0.92, 0.2, 0.66), (0.38, 3.45, -6.42), "wood_dark", turn=(0, -14, 2))
    k.path([(-1.7, 3.0, -6.5), (-1.2, 3.42, -6.45), (-0.6, 3.565, -6.5), (0.4, 3.565, -6.45), (1.1, 3.4, -6.4), (1.6, 3.0, -6.4)],
           0.03, "bone", verts=4)
    # The other half of the bath is still up here.
    k.box((0.86, 0.32, 1.7), (-0.2, 3.23, -1.0), "bone", taper=1.14, turn=(0, 7, 1.5))
    k.box((1.08, 0.08, 1.98), (-0.2, 3.4, -1.0), "bone", turn=(0, 7, 1.5))
    # Snow on the luggage, because the coach has no heating, ever.
    k.ball(0.5, (-0.9, 3.12, 7.6), "snow", squash=(1.4, 0.3, 2.1), wob=0.04)
    k.ball(0.45, (0.8, 3.14, 0.9), "snow", squash=(1.5, 0.3, 1.5), wob=0.04)
    door_lamps(k)
    belly(k)
    bogie(k, -5.94, ["normal", "normal", "normal", "normal"])
    bogie(k, 5.94, ["normal", "normal", "normal", "normal"])
    k.done("Exterior")

    k = Kit(32)
    liner_layers(k, 0.9, "wood_dark", COACH_LINER, "wood_dark")
    cabin(k, CARPET_COLD, CEILING_COLD, COACH_LINER, "wood_dark")
    beams(k, (-7.5, 7.5), "iron", thick=0.14, drop=0.12)
    for side in (-1, 1):
        racks(k, side, -8.6, 8.6, "wood_dark", "iron")
        for z, sx, sz in ((-7.0, 0.46, 0.8), (3.8, 0.4, 0.7), (6.6, 0.5, 0.9)):
            k.box((sx, 0.3, sz), (side * 1.49, 2.48, z + side * 0.3), "wood", turn=(0, k.jitter(9), k.jitter(5)), wob=0.015)
    # The whole of this car's paperwork.
    k.sign((-1.689, 1.68, PILLARS["mid_b"]), 1.34, 0.72, "+x", ["PASSENGERS", "LOST SO FAR"], "bone", "black", 0.12,
           roll=-2, thick=0.004, nails=False)
    bath_through_ceiling(k, -0.2, -1.0)
    bake_interior(k, LAMPS, step=1.25)
    finish("car_coach", ((0, 1.55, 8.2), (0, 1.3, -2)), ((9, 1.8, 0), (0, 1.3, 0)),
           gag=((0.5, 1.5, 2.6), (-0.2, 2.45, -1.0)))


# ---------------------------------------------------------------- nose


def driver(k, x, z, radius, style, width=0.5):
    """Wheel with a tyre fat enough to cover the rail at x=0.78."""
    y = -1.3 + radius
    if style == "square":
        k.cyl(radius, width, (x, y, z), "iron", axis="x", verts=4, turn=(45, 0, 0))
        k.cyl(radius * 0.74, width + 0.06, (x, y, z), "rust", axis="x", verts=4, turn=(45, 0, 0))
        k.cyl(0.2, width + 0.16, (x, y, z), "tomato", axis="x", verts=6)
    elif style == "wagon":
        k.cyl(radius, width, (x, y, z), "wood", axis="x", verts=12)
        k.cyl(radius * 0.84, width + 0.04, (x, y, z), "wood_dark", axis="x", verts=12)
        k.cyl(0.2, width + 0.16, (x, y, z), "brass", axis="x", verts=6)
        for angle in (0, 45, 90, 135):
            k.box((width + 0.1, radius * 1.74, 0.11), (x, y, z), "wood", turn=(angle, 0, 0))
    else:
        k.cyl(radius, width, (x, y, z), "iron", axis="x", verts=12)
        k.cyl(radius * 0.78, width + 0.06, (x, y, z), "rust", axis="x", verts=12)
        k.cyl(radius * 0.62, width + 0.1, (x, y, z), "iron", axis="x", verts=12)
        k.cyl(0.2, width + 0.16, (x, y, z), "steel", axis="x", verts=6)
    return y


def tiny_cow(k, x, y, z):
    """Rides the cow-catcher. Has never been caught. Knows it."""
    k.box((0.56, 0.42, 0.8), (x, y + 0.4, z + 0.2), "white", taper=0.9, wob=0.015)
    for dx, dz in ((-0.18, -0.08), (0.18, -0.08), (-0.18, 0.46), (0.18, 0.46)):
        k.box((0.13, 0.24, 0.13), (x + dx, y + 0.12, z + dz), "black")
    k.deck((x + 0.27, y + 0.46, z + 0.26), 0.32, 0.24, "+x", "black", roll=20)
    k.deck((x - 0.27, y + 0.36, z + 0.1), 0.34, 0.22, "-x", "black", roll=-14)
    k.box((0.42, 0.38, 0.38), (x, y + 0.72, z - 0.26), "white", wob=0.012)
    k.box((0.42, 0.18, 0.16), (x, y + 0.6, z - 0.5), "bubblegum")
    for side in (-1, 1):
        k.pipe((x + side * 0.2, y + 0.88, z - 0.26), (x + side * 0.38, y + 1.04, z - 0.26), 0.04, "bone", verts=4, end=0.012)
    k.ball(0.11, (x - 0.13, y + 0.78, z - 0.45), "white")
    k.ball(0.07, (x + 0.13, y + 0.8, z - 0.45), "white")
    k.ball(0.04, (x - 0.12, y + 0.77, z - 0.54), "black")
    k.ball(0.035, (x + 0.14, y + 0.81, z - 0.505), "black")


def nose():
    k = Kit(41)
    # Boiler, three drums that never quite agreed where the middle is.
    k.cyl(1.5, 2.6, (0, 1.42, -1.3), LOCO_HULL, axis="z", verts=12, turn=(1.0, 0, 0))
    k.cyl(1.56, 2.2, (0.03, 1.46, -3.5), (0.09, 0.14, 0.1), axis="z", verts=12, turn=(-1.2, 0.8, 0))
    k.cyl(1.62, 2.2, (-0.02, 1.5, -5.4), LOCO_HULL, axis="z", verts=12, turn=(1.5, -0.6, 0))
    for z, r, c in ((-0.4, 1.56, "brass"), (-2.6, 1.61, "brass"), (-4.45, 1.68, "rust")):
        k.cyl(r, 0.2, (0, 1.45, z), c, axis="z", verts=12, turn=(k.jitter(1), k.jitter(1), 0))
    # Smokebox: the head.
    k.cyl(1.82, 1.2, (0, 1.6, -6.7), (0.05, 0.07, 0.06), axis="z", verts=14, top=1.82)
    k.cyl(1.9, 0.14, (0, 1.6, -7.3), "iron", axis="z", verts=14, turn=(0, 0, 4))
    f = -7.38
    # Eyes that have seen the timetable.
    k.ball(0.72, (-0.84, 2.3, f), wacky.mat(GLOW_EYE, emission=2.2), squash=(1, 1, 0.34), detail=2)
    k.cyl(0.8, 0.12, (-0.84, 2.3, f + 0.06), "brass", axis="z", verts=12)
    k.ball(0.17, (-0.66, 2.12, f - 0.21), "black", squash=(1, 1, 0.6))
    k.ball(0.46, (0.86, 2.62, f), wacky.mat(GLOW_EYE, emission=1.2), squash=(1, 1, 0.34), detail=2)
    k.cyl(0.54, 0.12, (0.86, 2.62, f + 0.06), "steel", axis="z", verts=10)
    k.ball(0.09, (1.0, 2.76, f - 0.135), "black", squash=(1, 1, 0.6))
    k.box((1.22, 0.18, 0.14), (0.86, 3.08, f - 0.03), "iron", turn=(0, 0, 12))
    # Rivet nose, and one big brass nut for a mole.
    k.ball(0.26, (0.06, 1.7, f - 0.04), "rust", squash=(0.85, 1.2, 0.8))
    k.cyl(0.12, 0.08, (1.3, 1.6, f - 0.01), "brass", axis="z", verts=6)
    # The grin: far too many teeth for one engine.
    mouth = []
    count = 13
    half = 1.5
    for i in range(count):
        u = -1.0 + 2.0 * i / (count - 1)
        mouth.append((u * half, 1.02 - 1.6 + 0.62 * u * u + 0.34))
    for i in range(count - 1, -1, -1):
        u = -1.0 + 2.0 * i / (count - 1)
        mouth.append((u * half, 1.02 - 1.6 - 0.34 + 1.3 * u * u + 0.02))
    # Local origin at y=1.6.
    k.poly((0, 1.6, f - 0.01), list(reversed(mouth)), "-z", "black")
    missing = {3, 9}
    for i in range(14):
        u = -1.0 + 2.0 * (i + 0.5) / 14
        x = u * half * 0.97
        top = 1.6 + 1.02 - 1.6 + 0.62 * u * u + 0.34
        low = 1.6 + 1.02 - 1.6 - 0.34 + 1.3 * u * u + 0.02
        if i not in missing:
            colour = "brass" if i == 6 else "bone" if i % 4 == 1 else "white"
            k.box((0.19, 0.3, 0.09), (x, top - 0.13, f - 0.02), colour, taper=0.72, turn=(0, 0, k.jitter(6)), wob=0.008)
        if i not in {0, 13, 11}:
            k.box((0.19, 0.28, 0.09), (x, low + 0.12, f - 0.02), "bone" if i % 3 else "white", taper=0.72, turn=(0, 0, k.jitter(7)), wob=0.008)
    # Funnel: bent by regret.
    k.cyl(0.62, 0.5, (0.05, 3.42, -5.6), "iron", verts=10, top=0.52, turn=(0, 0, 3))
    k.cyl(0.5, 0.75, (0.14, 3.95, -5.68), "rust", verts=10, top=0.56, turn=(-6, 0, -9))
    k.cyl(0.56, 0.7, (0.34, 4.5, -5.82), "iron", verts=10, top=0.78, turn=(-13, 0, -22))
    k.cyl(0.86, 0.14, (0.5, 4.9, -5.93), "rust", verts=10, turn=(-14, 0, -24))
    # Smallest possible top hat, for formal occasions.
    k.box((0.2, 0.5, 0.2), (0.86, 5.05, -5.96), "steel", turn=(0, 0, -30))
    k.cyl(0.4, 0.04, (0.78, 5.36, -5.96), "black", verts=10, turn=(0, 0, -6))
    k.cyl(0.26, 0.46, (0.74, 5.58, -5.96), "black", verts=10, top=0.3, turn=(0, 0, -6))
    # Steam dome: a tea kettle the size of a shed.
    k.ball(1.0, (-0.1, 3.1, -3.2), "brass", squash=(1, 0.86, 1.1), detail=2)
    k.cyl(0.46, 0.22, (-0.1, 3.95, -3.2), "steel", verts=8, top=0.34)
    k.ball(0.16, (-0.1, 4.14, -3.2), "tomato")
    k.pipe((-0.8, 3.1, -3.2), (-1.62, 3.72, -3.2), 0.26, "brass", verts=7, end=0.12)
    k.path([(0.72, 3.46, -3.2), (0.9, 4.2, -3.2), (0.4, 4.7, -3.2), (-0.5, 4.72, -3.2), (-0.86, 4.1, -3.2)], 0.1, "iron")
    # Cracked bell.
    k.box((0.34, 0.6, 0.34), (0, 3.04, -1.1), "iron", taper=0.72, wob=0.012)
    k.box((0.7, 0.14, 0.5), (0, 2.86, -1.1), "rust", turn=(0, 0, 2))
    k.box((0.9, 0.12, 0.14), (0, 3.34, -1.1), "iron")
    k.cyl(0.36, 0.5, (0.0, 3.6, -1.1), "brass", verts=8, top=0.16)
    k.path([(0.08, 3.37, -1.46), (0.0, 3.5, -1.39), (0.09, 3.62, -1.34), (0.03, 3.8, -1.26)], 0.028, "black", verts=4)
    # Running boards and frame.
    k.box((1.3, 0.34, 7.2), (0, -0.2, -3.6), "iron", taper=0.97)
    for side in (-1, 1):
        k.box((0.98, 0.08, 6.6), (side * 1.67, 0.76, -3.4), "rust", turn=(side * 1.6, 0, 0))
    for side in (-1, 1):
        # Handrail: from the smokebox to the cab wall, on posts that reach the boiler.
        rail = [(side * 1.6, 2.24, -6.3), (side * 1.72, 2.16, -4.6), (side * 1.66, 2.13, -3.1),
                (side * 1.6, 2.1, -1.6), (side * 1.62, 2.08, 0.03)]
        k.path(rail, 0.06, "brass")
        k.cyl(0.13, 0.05, (side * 1.62, 2.08, -0.02), "steel", axis="z", verts=6)
        for point, radius, axis_y in ((rail[1], 1.62, 1.5), (rail[2], 1.56, 1.46), (rail[3], 1.5, 1.42)):
            px, py, pz = point
            scale = (radius - 0.14) / math.hypot(px, py - axis_y)
            k.pipe((px * scale, axis_y + (py - axis_y) * scale, pz), point, 0.09, "steel", verts=5, end=0.06)
            k.ball(0.09, point, "steel")
        outside = "+x" if side > 0 else "-x"
        # Drivers. No two of them were ever introduced. Fat tyres, because the rails
        # are at x=0.78 and the boiler is a lot wider than the track.
        heights = []
        for z, radius, style in ((-1.1, 1.0, "normal"), (-3.3, 1.0, "normal"), (-5.45, 0.86, "normal")):
            heights.append(driver(k, side * 0.97, z, radius, style))
        k.pipe((side * 1.36, heights[0] + 0.3, -1.1), (side * 1.36, heights[1] - 0.2, -3.3), 0.1, "steel", verts=6)
        k.pipe((side * 1.36, heights[1] - 0.2, -3.3), (side * 1.38, heights[2] + 0.22, -5.45), 0.1, "steel", verts=6)
        k.pipe((side * 1.38, heights[2] + 0.22, -5.45), (side * 1.4, -0.62, -6.4), 0.08, "steel", verts=6)
        k.cyl(0.42, 1.0, (side * 1.4, -0.62, -6.87), "iron", axis="z", verts=8)
        k.cyl(0.47, 0.12, (side * 1.4, -0.62, -6.42), "brass", axis="z", verts=8)
    for z in (-1.1, -3.3, -5.45):
        k.cyl(0.14, 1.5, (0, -0.3 if z > -5 else -0.44, z), "steel", axis="x", verts=6)
    # Cow-catcher.
    k.box((3.3, 0.4, 0.3), (0, 0.08, -7.32), "tomato", turn=(0, 0, 1.2))
    k.text("SORRY", (0.0, 0.08, -7.48), 0.26, "-z", "cream", crook=4)
    tip = (0.05, -1.26, -7.96)
    for x in (-1.6, -1.15, -0.7, -0.25, 0.25, 0.7, 1.15, 1.6):
        k.pipe((x, -0.1, -7.36), (tip[0] + x * 0.1, tip[1], tip[2]), 0.075, "rust" if abs(x) % 0.9 > 0.3 else "iron", verts=5)
    k.pipe((-1.65, -0.6, -7.5), (0.0, -0.74, -7.84), 0.08, "iron", verts=5)
    k.pipe((1.65, -0.6, -7.5), (0.0, -0.74, -7.84), 0.08, "iron", verts=5)
    tiny_cow(k, -1.12, 0.27, -7.3)
    k.done("Nose")
    finish("nose", None, ((7, 3.5, -15), (0, 1.5, -7)))


# ---------------------------------------------------------------- gangway


def bellows(k, half, top, y0, colours, facing_in=False, chamfer=0.0, folds=6):
    """Fat V folds swept round a U. [half] and [top] are (valley, peak) pairs.

    Flanks alternate between two colours so the folds still read from a distance.
    """
    stations = folds * 2 + 1
    meshes = (bmesh.new(), bmesh.new())
    flip = -1.0 if facing_in else 1.0
    outs = [(-1, 0, 0), (0, 1, 0), (1, 0, 0)]
    if chamfer:
        outs = [(-1, 0, 0), (-1, 1, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]
    rings = []
    for i in range(stations):
        z = -0.65 + 1.3 * i / (stations - 1)
        w = half[i % 2]
        h = top[i % 2]
        if chamfer:
            rings.append([(-w, y0, z), (-w, h - chamfer, z), (-w + chamfer, h, z), (w - chamfer, h, z), (w, h - chamfer, z), (w, y0, z)])
        else:
            rings.append([(-w, y0, z), (-w, h, z), (w, h, z), (w, y0, z)])
    for i in range(stations - 1):
        bm = meshes[i % 2]
        for seg, out in enumerate(outs):
            quad = (rings[i][seg], rings[i][seg + 1], rings[i + 1][seg + 1], rings[i + 1][seg])
            face = bm.faces.new([bm.verts.new(gv(*p)) for p in quad])
            face.normal_update()
            if face.normal.dot(gv(*out)) * flip < 0.0:
                face.normal_flip()
    for bm, colour in zip(meshes, colours):
        k._flat(bm, colour)


def tooth_row(k, points, out, reach, tooth, skip=()):
    """Flat teeth along a line. [points] are base centres, [tooth] the half-width vector."""
    for i, p in enumerate(points):
        if i in skip:
            continue
        colour = "brass" if i == 3 else "bone" if i % 3 == 1 else "white"
        grow = 1.0 + k.jitter(0.22)
        a = tuple(p[n] - tooth[n] for n in range(3))
        b = tuple(p[n] + tooth[n] for n in range(3))
        c = tuple(p[n] + reach[n] * grow for n in range(3))
        k.tri(a, b, c, out, colour)


def gangway():
    k = Kit(51)
    rubber = (0.05, 0.05, 0.055)
    rubber_b = (0.02, 0.02, 0.025)
    gum = (0.2, 0.06, 0.07)
    gum_b = (0.1, 0.025, 0.035)
    k.box((1.54, 0.25, 1.3), (0, -0.125, 0), "iron")
    # Foot plate that clearly does not meet in the middle.
    k.box((1.42, 0.02, 0.62), (0, 0.01, -0.32), "iron", turn=(0.6, 0, 0))
    k.box((1.42, 0.02, 0.62), (0.02, 0.01, 0.32), "iron", turn=(-0.6, 0, 0.2))
    # Rubber outside, fat V folds. Stops at x=0.86, the collision wall ends at 0.82.
    bellows(k, (0.79, 0.86), (2.25, 2.32), -0.2, (rubber, rubber_b), chamfer=0.09)
    # Same rubber inside, except it turns out the corridor is a throat. Stops at x=0.72.
    bellows(k, (0.765, 0.725), (2.245, 2.205), -0.02, (gum, gum_b), facing_in=True)
    # Steel hoops where it bolts to each car.
    for z in (-0.57, 0.57):
        for side in (-1, 1):
            k.box((0.14, 2.5, 0.06), (side * 0.79, 1.05, z), "iron")
        k.box((1.72, 0.1, 0.06), (0, 2.26, z), "iron")
    # Teeth round both ends. The one joke here: you walk in through a mouth, every time.
    for end in (-1, 1):
        base = end * 0.58
        xs = [-0.6 + 0.2 * i for i in range(7)]
        tooth_row(k, [(x, 2.2015, base) for x in xs], (0, -1, 0), (0, 0, -end * 0.3), (0.095, 0, 0), skip=(5,))
        tooth_row(k, [(x, 0.037, base) for x in xs], (0, 1, 0), (0, 0, -end * 0.24), (0.095, 0, 0), skip=(1,))
    k.blob((0.0, 0.03, 0.0), 1.04, 1.0, "+y", gum, sides=10, wob=0.05)
    k.done("Gangway")
    audit_gangway()
    finish("gangway", ((0.0, 1.55, 1.9), (0.0, 0.9, -1.0)), ((3.2, 1.9, 2.4), (0, 1.0, 0)))


# ---------------------------------------------------------------- rear platform


def rear_platform():
    k = Kit(61)
    k.box((3.8, 0.1, 2.4), (0, -0.15, 1.2), "iron")
    for i in range(7):
        k.box((3.8, 0.08, 0.34), (0, -0.04, 0.17 + i * 0.343), PLANK_B if i % 2 else "wood_dark", turn=(0, 0, k.jitter(0.25)))
    k.box((0.3, 0.3, 2.3), (-1.55, -0.32, 1.2), "iron")
    k.box((0.3, 0.3, 2.3), (1.55, -0.32, 1.2), "iron")
    k.box((3.9, 0.4, 0.26), (0, -0.4, 2.27), "iron", turn=(0, 0, 1.0))
    for x in (-1.4, 1.4):
        k.cyl(0.3, 0.2, (x, -0.42, 2.45 - 0.04), "steel", axis="z", verts=8)
    # Rails: tops dead level at y=1.04 to match the collision. All the wrongness is in plan.
    rail = "iron"
    for side in (-1, 1):
        x = side * 1.86
        k.rail_run([(x, 0.03), (x, 1.05), (x - side * 0.05, 1.7), (x, 2.36)], 1.0, rail)
        k.box((0.12, 1.08, 0.12), (x, 0.5, 2.34), rail, turn=(0, 0, 0))
        k.box((0.1, 1.0, 0.1), (x, 0.5, 0.05), rail)
        k.box((0.08, 1.0, 0.08), (x, 0.47, 1.25), rail, turn=(3, 0, 0))
    # Rear rail punched outwards in the exact outline of somebody leaving in a hurry.
    k.rail_run([(-1.86, 2.36), (-0.68, 2.36), (-0.52, 2.56), (-0.27, 2.61), (-0.17, 2.72), (0.13, 2.72),
                (0.24, 2.6), (0.5, 2.54), (0.68, 2.36), (1.86, 2.36)], 1.0, rail)
    # Red tail lamp, wired on with hope.
    k.box((0.07, 0.2, 0.07), (1.86, 1.08, 2.34), "iron", turn=(0, 0, 3))
    k.box((0.2, 0.26, 0.2), (1.86, 1.28, 2.34), "iron")
    k.box((0.14, 0.18, 0.04), (1.86, 1.28, 2.45), wacky.mat((0.9, 0.12, 0.06), emission=2.5))
    # The sign that made a conductor resign.
    k.path([(-1.1, 1.0, 2.42), (-1.1, 0.68, 2.46)], 0.02, "iron", verts=4)
    k.path([(1.1, 1.0, 2.42), (1.1, 0.7, 2.46)], 0.02, "iron", verts=4)
    k.sign((0.0, 0.5, 2.48), 2.5, 0.42, "+z", ["JUST DERAILED"], "bone", "black", 0.21, roll=-3, thick=0.03, nails=False)
    k.panel((0.0, 0.5, 2.46), 2.5, 0.42, 0.01, "-z", "wood_dark", roll=3)
    # Tin cans dragged behind the train on strings, like a wedding that went wrong.
    for x0, x1, y1, z1 in ((-1.05, -1.3, -1.12, 3.45), (1.08, 1.34, -1.1, 3.55)):
        k.path([(x0, -0.5, 2.38), ((x0 + x1) * 0.5, (y1 - 0.5) * 0.5 - 0.1, (2.38 + z1) * 0.5), (x1, y1, z1)], 0.05, "iron", verts=4)
        a = Vector((x1, y1, z1))
        b = a + Vector((0.1, 0.14, 0.46))
        k.pipe(tuple(a), tuple(b), 0.17, "steel", verts=8)
    # Giant brake wheel, clear of the car wall and inside the rail.
    k.cyl(0.08, 1.3, (1.46, 0.65, 0.42), "iron", verts=6)
    k.cyl(0.36, 0.08, (1.46, 1.3, 0.42), "iron", verts=10, turn=(5, 0, 3))
    k.done("Platform")
    audit_platform()
    finish("rear_platform", ((0, 1.6, -0.6), (0, 0.5, 2.4)), ((5, 2.2, 6), (0, 0.4, 1.2)))


# ---------------------------------------------------------------- panels


def door_panel():
    k = Kit(71)
    body = (0.09, 0.055, 0.03)
    rail = (0.04, 0.025, 0.016)
    k.box((0.05, 2.2, 1.4), (0, 0, 0), body)
    for side in (-1, 1):
        n = "+x" if side > 0 else "-x"
        x = side * 0.034
        fx = side * 0.0405
        # Raised frame stays inside the 0.08 collision thickness.
        k.panel((x, 0.98, 0), 1.4, 0.24, 0.012, n, rail)
        k.panel((x, -0.98, 0), 1.4, 0.24, 0.012, n, rail)
        k.panel((x, 0, -0.59), 0.2, 1.72, 0.012, n, rail, roll=0.5)
        k.panel((x, 0, 0.59), 0.2, 1.72, 0.012, n, rail, roll=-0.5)
        k.panel((x, -0.2, 0), 1.0, 0.12, 0.012, n, rail)
        # Handle plate, flush so it can slide into the wall. Brass, so the door reads as a door.
        k.deck((fx - side * 0.0015, -0.02, -0.6), 0.12, 0.5, n, "brass")
    k.done("Panel")
    finish("door_panel")


def rear_door_panel():
    k = Kit(72)
    body = (0.13, 0.08, 0.05)
    k.box((1.3, 2.2, 0.05), (0, 0, 0), body)
    for side in (-1, 1):
        n = "+z" if side > 0 else "-z"
        z = side * 0.034
        k.panel((0, 0.98, z), 1.3, 0.24, 0.012, n, "iron")
        k.panel((0, -0.98, z), 1.3, 0.24, 0.012, n, "iron")
        k.panel((-0.55, 0, z), 0.18, 1.72, 0.012, n, "iron", roll=0.4)
        k.panel((0.55, 0, z), 0.18, 1.72, 0.012, n, "iron", roll=-0.4)
    # Facing the platform and the night. Nothing facing the cabin.
    k.deck((0, 0.38, 0.039), 0.9, 0.6, "+z", "bone", roll=3)
    k.text("THANK", (0, 0.5, 0.0405), 0.16, "+z", "black", roll=3)
    k.text("YOU", (0, 0.27, 0.0405), 0.16, "+z", "black", roll=3)
    k.done("Panel")
    finish("rear_door_panel")


def window_panel():
    k = Kit(73)
    rail = (0.04, 0.025, 0.016)
    # Frame: chunky, and the crooked bits stay in the outline.
    k.box((0.08, 0.14, 1.5), (0, 0.48, 0), rail)
    k.box((0.08, 0.26, 1.5), (0, -0.42, 0), rail)
    k.box((0.08, 0.84, 0.13), (0, 0.03, -0.685), rail)
    k.box((0.08, 0.84, 0.13), (0, 0.03, 0.685), rail)
    k.box((0.05, 0.82, 0.09), (0, 0.04, 0.2), rail, turn=(5, 0, 0))
    k.done("Frame")
    k = Kit(74)
    glass = wacky.mat((0.1, 0.14, 0.18), alpha=0.3, rough=0.2)
    k.box((0.02, 0.84, 1.3), (0, 0.02, 0), glass)
    k.done("Glass")
    finish("window_panel")


# ---------------------------------------------------------------- checks and output


def bvh_of(objects):
    verts = []
    tris = []
    for obj in objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        base = len(verts)
        verts.extend(tuple(obj.matrix_world @ v.co) for v in mesh.vertices)
        tris.extend(tuple(i + base for i in t.vertices) for t in mesh.loop_triangles)
    return BVHTree.FromPolygons(verts, tris)


def audit_car(name):
    """Fires rays through every hole. Anything hit is a build error, not a judgement call."""
    objects = [o for o in bpy.data.objects if o.type == "MESH"]
    tree = bvh_of(objects)
    problems = []
    margin = 0.012
    for z0, z1, y0, y1 in HOLES:
        for i in range(9):
            z = z0 + margin + (z1 - z0 - margin * 2) * i / 8
            for j in range(9):
                y = max(y0, 0.03) + margin + (y1 - max(y0, 0.03) - margin * 2) * j / 8
                for side in (-1, 1):
                    # Whole wall depth, from just inside to well outside.
                    start = gv(side * 1.67, y, z)
                    direction = gv(side, 0, 0)
                    hit = tree.ray_cast(start, direction, 3.0)
                    if hit[0] is not None:
                        problems.append(("hole", side, round(z, 2), round(y, 2), round(hit[3], 2)))
    passages = [(9.2, -1)]
    if name != "car_locomotive":
        passages.append((-9.2, 1))
    for z_start, sign in passages:
        for i in range(9):
            x = -0.645 + 1.29 * i / 8
            for j in range(9):
                y = 0.03 + 2.165 * j / 8
                hit = tree.ray_cast(gv(x, y, z_start), gv(0, 0, sign), 0.7)
                if hit[0] is not None:
                    problems.append(("passage", z_start, round(x, 2), round(y, 2)))
    interior = bpy.data.objects["Interior"]
    for vert in interior.data.vertices:
        co = interior.matrix_world @ vert.co
        x, y, z = co.x, co.z, -co.y
        if 0.03 < y < 2.2 and abs(x) < 1.6795 and abs(z) < 8.7:
            problems.append(("intrude", round(x, 3), round(y, 3), round(z, 3)))
    # Through the end walls: nothing may stand in the passage, on either object.
    for obj in objects:
        for vert in obj.data.vertices:
            co = obj.matrix_world @ vert.co
            x, y, z = co.x, co.z, -co.y
            front_blocked = name == "car_locomotive" and z < 0.0
            if abs(z) > 8.6 and abs(x) < 0.649 and 0.03 < y < 2.199 and not front_blocked:
                problems.append(("passage_vert", obj.name, round(x, 3), round(y, 3), round(z, 3)))
    for obj in objects:
        ys = [(obj.matrix_world @ v.co).z for v in obj.data.vertices]
        print("RANGE", obj.name, "y %.3f to %.3f" % (min(ys), max(ys)))
        if max(ys) > 3.6005:
            problems.append(("roof_clutter", obj.name, round(max(ys), 3)))
        if min(ys) < -1.3005:
            problems.append(("below_track", obj.name, round(min(ys), 3)))
    print("AUDIT", name, "%d problems" % len(problems), problems[:8])


def audit_gangway():
    """Walkway must stay clear of the collision box: x=+-0.72, y=2.2, floor top allowed 4 cm."""
    obj = bpy.data.objects["Gangway"]
    problems = []
    for vert in obj.data.vertices:
        co = obj.matrix_world @ vert.co
        x, y, z = co.x, co.z, -co.y
        if abs(x) < 0.712 and 0.04 < y < 2.2:
            problems.append(("walkway", round(x, 3), round(y, 3), round(z, 3)))
        if abs(z) > 0.651:
            problems.append(("long", round(z, 3)))
    tree = bvh_of([obj])
    for i in range(9):
        x = -0.645 + 1.29 * i / 8
        for j in range(9):
            hit = tree.ray_cast(gv(x, 0.045 + 2.15 * j / 8, -1.0), gv(0, 0, 1), 2.0)
            if hit[0] is not None:
                problems.append(("ray", round(x, 2), j))
    wall = max(abs(v.co.x) for v in obj.data.vertices if v.co.z < 1.2 and abs(v.co.y) < 0.2)
    print("AUDIT gangway %d problems" % len(problems), problems[:8], "half width %.3f" % wall)


def audit_platform():
    """Rail tops at 1.04 where the collision is, nothing past the car wall at z=0."""
    obj = bpy.data.objects["Platform"]
    problems = []
    for vert in obj.data.vertices:
        co = obj.matrix_world @ vert.co
        if -co.y < -0.001:
            problems.append(("past_car_wall", round(co.x, 3), round(co.z, 3), round(-co.y, 3)))
    tree = bvh_of([obj])
    probes = [(s * x, z) for s in (-1, 1) for x, z in ((1.86, 0.2), (1.86, 0.7), (1.84, 1.2), (1.83, 1.7), (1.85, 2.1))]
    probes += [(-1.5, 2.36), (-1.0, 2.36), (-0.6, 2.46), (-0.4, 2.585), (0.0, 2.72), (0.37, 2.57), (0.6, 2.45), (1.0, 2.36), (1.5, 2.36)]
    tops = []
    for x, z in probes:
        hit = tree.ray_cast(gv(x, 1.2, z), gv(0, -1, 0), 1.0)
        top = hit[0].z if hit[0] is not None else -9.0
        tops.append(round(top, 3))
        if abs(top - 1.04) > 0.006:
            problems.append(("rail_top", x, z, round(top, 3)))
    print("AUDIT rear_platform %d problems" % len(problems), problems[:8], "rail tops", min(tops), max(tops))


def shot(path, eye, target, lens=24):
    """Extra look from inside or close up. Goes wherever TRAIN_SHOTS says."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 800
    scene.render.resolution_y = 500
    scene.render.image_settings.file_format = "PNG"
    data = bpy.data.cameras.new("look")
    data.lens = lens
    data.clip_start = 0.02
    data.clip_end = 300.0
    camera = bpy.data.objects.new("look", data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.location = gv(*eye)
    heading = gv(*target) - gv(*eye)
    camera.rotation_euler = heading.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)


def finish(name, inside=None, outside=None, gag=None):
    print("==", name)
    total = wacky.report()
    if name.startswith("car_"):
        print("BUDGET", name, total, "of 9000", "OVER" if total > 9000 else "ok")
        audit_car(name)
    wacky.export_glb(OUT + name + ".glb")
    wacky.preview(PREVIEW + name + ".png")
    if EXTRA:
        os.makedirs(EXTRA, exist_ok=True)
        if inside:
            shot(os.path.join(EXTRA, name + "_inside.png"), *inside)
        if outside:
            shot(os.path.join(EXTRA, name + "_side.png"), *outside)
        if gag:
            shot(os.path.join(EXTRA, name + "_gag.png"), *gag)


BUILDS = {
    "car_locomotive": car_locomotive,
    "car_bistro": car_bistro,
    "car_coach": car_coach,
    "gangway": gangway,
    "rear_platform": rear_platform,
    "nose": nose,
    "door_panel": door_panel,
    "rear_door_panel": rear_door_panel,
    "window_panel": window_panel,
}

wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(BUILDS)
for key in wanted:
    wacky.reset_scene()
    BUILDS[key]()
print("DONE")
