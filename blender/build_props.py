"""Builds the hand-held props for The Midnight Express.

  blender.exe --background --python blender/build_props.py [-- coal crate ...]

Each file holds one object named Prop, centred on its collision box and scaled to the
exact size in docs/ART_BRIEF.md. Tools point their head at -Z.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import wacky as w

STRAW = (0.42, 0.33, 0.14)
LIGHT_WOOD = (0.3, 0.19, 0.1)
GREY_SOUP = (0.3, 0.3, 0.26)
EMBER = (1.0, 0.2, 0.02)
LEATHER = (0.17, 0.095, 0.055)
SCRAPED = (0.34, 0.35, 0.37)
FACE_STEEL = (0.45, 0.46, 0.48)
PASTA = (0.5, 0.26, 0.08)
BALD = (0.7, 0.55, 0.46)
SKIN_RED = (0.55, 0.3, 0.24)
PLASTER = (0.4, 0.2, 0.22)
SCOURED = (0.5, 0.47, 0.4)

GLYPHS = {
    "A": ["111", "101", "111", "101", "101"],
    "B": ["110", "101", "110", "101", "110"],
    "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"],
    "F": ["111", "100", "110", "100", "100"],
    "G": ["111", "100", "101", "101", "111"],
    "H": ["101", "101", "111", "101", "101"],
    "I": ["111", "010", "010", "010", "111"],
    "K": ["101", "101", "110", "101", "101"],
    "L": ["100", "100", "100", "100", "111"],
    "M": ["10001", "11011", "10101", "10001", "10001"],
    "N": ["1001", "1101", "1011", "1001", "1001"],
    "O": ["111", "101", "101", "101", "111"],
    "P": ["111", "101", "111", "100", "100"],
    "R": ["110", "101", "110", "101", "101"],
    "S": ["111", "100", "111", "001", "111"],
    "T": ["111", "010", "010", "010", "010"],
    "U": ["101", "101", "101", "101", "111"],
    "Y": ["101", "101", "111", "010", "010"],
    "C": ["111", "100", "100", "100", "111"],
}


def glyph_rects(rows):
    """Covers a bitmap glyph with as few rectangles as possible, so letters stay cheap."""
    height = len(rows)
    width = len(rows[0])
    solid = {(c, r) for r in range(height) for c in range(width) if rows[r][c] == "1"}
    left = set(solid)
    rects = []
    while left:
        best = None
        best_gain = 0
        for r0 in range(height):
            for c0 in range(width):
                for r1 in range(r0, height):
                    for c1 in range(c0, width):
                        cells = {(c, r) for c in range(c0, c1 + 1) for r in range(r0, r1 + 1)}
                        if cells <= solid and len(cells & left) > best_gain:
                            best_gain = len(cells & left)
                            best = (c0, r0, c1 + 1, r1 + 1, cells)
        left -= best[4]
        rects.append(best[:4])
    return rects


def flat(name, quads, material):
    """Mesh of flat polygons given as lists of Godot points. Normal follows the winding."""
    verts = []
    faces = []
    for quad in quads:
        start = len(verts)
        verts.extend(tuple(w.gv(*point)) for point in quad)
        faces.append(tuple(range(start, start + len(quad))))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def plane_point(center, u, v, a, b):
    return tuple(center[i] + u[i] * a + v[i] * b for i in range(3))


def text(name, string, center, u, v, px, material, tilt=0.0, seed=3):
    """Blocky letters on the plane through [center]. Reads along u, up along v; u x v faces out."""
    rng = random.Random(seed)
    lines = string.split("\n")
    line_height = 6.5
    total_height = line_height * len(lines) - 1.5
    cos_t, sin_t = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
    quads = []

    def corner(a, b):
        return plane_point(center, u, v, a * cos_t - b * sin_t, a * sin_t + b * cos_t)

    for index, line in enumerate(lines):
        width = sum(len(GLYPHS[c][0]) + 1 if c != " " else 2.5 for c in line) - 1
        pen = -width * 0.5
        top = total_height * 0.5 - index * line_height
        for char in line:
            if char == " ":
                pen += 2.5
                continue
            jitter = rng.uniform(-0.35, 0.35)
            rows = GLYPHS[char]
            for c0, r0, c1, r1 in glyph_rects(rows):
                a0, a1 = (pen + c0) * px, (pen + c1) * px
                b1, b0 = (top - r0 + jitter) * px, (top - r1 + jitter) * px
                quads.append([corner(a0, b0), corner(a1, b0), corner(a1, b1), corner(a0, b1)])
            pen += len(rows[0]) + 1
    return flat(name, quads, material)


def disc(name, center, u, v, radius, material, sides=7, squash=1.0):
    points = []
    for i in range(sides):
        angle = math.tau * i / sides
        points.append(plane_point(center, u, v, math.cos(angle) * radius, math.sin(angle) * radius * squash))
    return flat(name, [points], material)


def rect(name, center, u, v, half_u, half_v, material, tilt=0.0):
    cos_t, sin_t = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
    points = []
    for a, b in ((-half_u, -half_v), (half_u, -half_v), (half_u, half_v), (-half_u, half_v)):
        points.append(plane_point(center, u, v, a * cos_t - b * sin_t, a * sin_t + b * cos_t))
    return flat(name, [points], material)


def spin(obj, axis, degrees):
    """Rotates about the object's own centre, around a Godot axis."""
    vector = {"x": Vector((1, 0, 0)), "y": Vector((0, 0, 1)), "z": Vector((0, -1, 0))}[axis]
    rotation = Matrix.Rotation(math.radians(degrees), 3, vector)
    obj.rotation_euler = (rotation @ obj.rotation_euler.to_matrix()).to_euler()
    return obj


def deform(obj, fn):
    """Applies fn(x, y, z) -> (x, y, z) to a joined object, in Godot coordinates."""
    for vert in obj.data.vertices:
        x, y, z = fn(vert.co.x, vert.co.z, -vert.co.y)
        vert.co = w.gv(x, y, z)
    obj.data.update()
    return obj


def lathe(name, profile, center, material, segments=14, tweak=None):
    """Spins (radius, y) points around Godot Y. tweak(ring, angle, r, y) -> (r, y) bends a vertex."""
    bm = bmesh.new()
    rings = []
    for index, (radius, height) in enumerate(profile):
        ring = []
        if radius <= 1e-6:
            ring = [bm.verts.new((0, 0, height))]
        else:
            for j in range(segments):
                angle = math.tau * j / segments
                r, y = (radius, height) if tweak is None else tweak(index, angle, radius, height)
                # Godot +X is angle 0, Godot +Z is angle 90.
                ring.append(bm.verts.new((math.cos(angle) * r, -math.sin(angle) * r, y)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1:
            for j in range(segments):
                bm.faces.new((a[0], b[j], b[(j + 1) % segments]))
        elif len(b) == 1:
            for j in range(segments):
                bm.faces.new((a[j], b[0], a[(j + 1) % segments]))
        else:
            for j in range(segments):
                k = (j + 1) % segments
                bm.faces.new((a[j], a[k], b[k], b[j]))
    return w._finish(name, bm, center, material)


def plate(name, outline, y0, y1, material):
    """Extrudes a possibly concave (x, z) outline between two heights."""
    bm = bmesh.new()
    low = [bm.verts.new((x, -z, y0)) for x, z in outline]
    high = [bm.verts.new((x, -z, y1)) for x, z in outline]
    caps = [bm.faces.new(low), bm.faces.new(high)]
    for i in range(len(outline)):
        k = (i + 1) % len(outline)
        bm.faces.new((low[i], low[k], high[k], high[i]))
    bm.normal_update()
    bmesh.ops.triangulate(bm, faces=caps, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    return w._finish(name, bm, (0, 0, 0), material)


def pillow(name, xs, half_y, half_z, material):
    """Box built as eight-point sections along X, so it can swell without wasting tris."""
    section = [(1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1), (1, 0)]
    bm = bmesh.new()
    rings = []
    for x in xs:
        rings.append([bm.verts.new((x, -sz * half_z, sy * half_y)) for sy, sz in section])
    for a, b in zip(rings, rings[1:]):
        for j in range(8):
            k = (j + 1) % 8
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(rings[0])
    bm.faces.new(rings[-1])
    return w._finish(name, bm, (0, 0, 0), material)


def fit(obj, size):
    """Centres the bounding box on the origin and scales it to exactly [size]."""
    points = [(v.co.x, v.co.z, -v.co.y) for v in obj.data.vertices]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    print("  raw size (%.3f %.3f %.3f) target (%.3f %.3f %.3f)" % (
        high[0] - low[0], high[1] - low[1], high[2] - low[2], *size))
    scale = [size[i] / (high[i] - low[i]) for i in range(3)]
    mid = [(low[i] + high[i]) * 0.5 for i in range(3)]
    deform(obj, lambda x, y, z: ((x - mid[0]) * scale[0], (y - mid[1]) * scale[1], (z - mid[2]) * scale[2]))
    bpy.context.view_layer.update()


def finish(name, parts, size, closes=None):
    """Exports the prop. [closes] maps a view name to (direction, target, span) close renders."""
    obj = w.join("Prop", parts)
    w.clear_except([obj])
    fit(obj, size)
    print("==", name)
    tris = w.report([obj])
    if tris > 500:
        print("  OVER BUDGET:", tris)
    w.export_glb("assets/models/props/%s.glb" % name)
    w.preview("assets/previews/props/%s.png" % name)
    for view, (direction, target, span) in (closes or {}).items():
        snapshot("assets/previews/props/close/%s_%s.png" % (name, view), direction, target or (0, 0, 0), span)


HEX = [(0.62, 1), (-0.62, 1), (-1, 0), (-0.62, -1), (0.62, -1), (1, 0)]
DIAMOND = [(1, 0), (0, 1), (-1, 0), (0, -1)]
SOFT_SQUARE = [(0.72, 1), (-0.72, 1), (-1, 0.72), (-1, -0.72), (-0.72, -1), (0.72, -1), (1, -0.72), (1, 0.72)]


def ring_points(path, radii, section, side):
    """Sections along a Godot path. Section (a, b) runs along [side], then along side x tangent."""
    points = [Vector(p) for p in path]
    rings = []
    for i, centre in enumerate(points):
        tangent = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        across = Vector(side)
        across = (across - tangent * across.dot(tangent)).normalized()
        up = across.cross(tangent)
        radius = radii[i]
        rx, ry = radius if isinstance(radius, tuple) else (radius, radius)
        if rx <= 1e-6:
            rings.append([centre.copy()])
        else:
            rings.append([centre + across * a * rx + up * b * ry for a, b in section])
    return rings


def tube(name, path, radii, material, section=HEX, side=(1, 0, 0), caps=True):
    """Bent chunky limb along a Godot path. A radius of 0 closes that end to a point."""
    rings = ring_points(path, radii, section, side)
    bm = bmesh.new()
    made = [[bm.verts.new(tuple(w.gv(*p))) for p in ring] for ring in rings]
    count = len(section)
    for a, b in zip(made, made[1:]):
        if len(a) == 1:
            for j in range(count):
                bm.faces.new((a[0], b[j], b[(j + 1) % count]))
        elif len(b) == 1:
            for j in range(count):
                bm.faces.new((a[j], b[0], a[(j + 1) % count]))
        else:
            for j in range(count):
                k = (j + 1) % count
                bm.faces.new((a[j], a[k], b[k], b[j]))
    if caps:
        for ring in (made[0], made[-1]):
            if len(ring) > 1:
                bm.faces.new(ring)
    return w._finish(name, bm, (0, 0, 0), material)


def lerp3(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def sheet(name, center, u, v, half_u, half_v, material, tilt=0.0, nu=4, nv=3):
    """Rectangle split into a grid, so drape() can bend it over a curved surface."""
    cos_t, sin_t = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))

    def corner(i, j):
        a = (i / nu * 2 - 1) * half_u
        b = (j / nv * 2 - 1) * half_v
        return plane_point(center, u, v, a * cos_t - b * sin_t, a * sin_t + b * cos_t)

    quads = []
    for i in range(nu):
        for j in range(nv):
            quads.append([corner(i, j), corner(i + 1, j), corner(i + 1, j + 1), corner(i, j + 1)])
    return flat(name, quads, material)


def round_sheet(name, center, u, v, radius, material, sides=8):
    """Disc with an inner ring, so drape() can bend it."""
    def ring(r, i):
        angle = math.tau * i / sides
        return plane_point(center, u, v, math.cos(angle) * r, math.sin(angle) * r)

    faces = [[center, ring(radius * 0.5, i), ring(radius * 0.5, i + 1)] for i in range(sides)]
    faces += [[ring(radius * 0.5, i), ring(radius, i), ring(radius, i + 1), ring(radius * 0.5, i + 1)]
              for i in range(sides)]
    return flat(name, faces, material)


def strip(name, points, widths, material, steps=3):
    """Ribbon along (x, y) points in the XY plane. Densified so drape() can follow a surface."""
    dense = []
    dense_width = []
    for i in range(len(points) - 1):
        for s in range(steps):
            t = s / steps
            dense.append((points[i][0] + (points[i + 1][0] - points[i][0]) * t,
                          points[i][1] + (points[i + 1][1] - points[i][1]) * t))
            dense_width.append(widths[i] + (widths[i + 1] - widths[i]) * t)
    dense.append(points[-1])
    dense_width.append(widths[-1])
    quads = []
    for i in range(len(dense) - 1):
        ax, ay = dense[i]
        bx, by = dense[i + 1]
        length = math.hypot(bx - ax, by - ay)
        nx, ny = -(by - ay) / length, (bx - ax) / length
        wa, wb = dense_width[i] * 0.5, dense_width[i + 1] * 0.5
        quads.append([(ax + nx * wa, ay + ny * wa, 0), (ax - nx * wa, ay - ny * wa, 0),
                      (bx - nx * wb, by - ny * wb, 0), (bx + nx * wb, by + ny * wb, 0)])
    return flat(name, quads, material)


def triangulate(obj):
    """Locks the triangulation, so a swollen quad exports the same surface drape() measured."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def body_tree(body):
    verts = [v.co.copy() for v in body.data.vertices]
    polys = [tuple(p.vertices) for p in body.data.polygons]
    return BVHTree.FromPolygons(verts, polys)


def drape(obj, tree, direction, offset):
    """Drops every vertex of [obj] along Godot [direction] onto the surface, [offset] proud of it."""
    ray = w.gv(*direction).normalized()
    misses = 0
    for vert in obj.data.vertices:
        hit = tree.ray_cast(vert.co - ray * 2.0, ray)
        if hit[0] is None:
            misses += 1
            continue
        vert.co = hit[0] - ray * offset
    obj.data.update()
    if misses:
        print("  drape miss %d verts on %s" % (misses, obj.name))
    return obj


def audit(label, objects, tree, direction):
    """Prints how far decals stand off (+) or sink into (-) the body, sampled across each face."""
    ray = w.gv(*direction).normalized()
    low, high = 1e9, -1e9
    worst = ""
    for obj in objects:
        mesh = obj.data
        for poly in mesh.polygons:
            corners = [mesh.vertices[i].co.copy() for i in poly.vertices]
            centre = sum(corners, Vector((0, 0, 0))) / len(corners)
            samples = corners + [centre] + [(c + centre) * 0.5 for c in corners]
            samples += [(c + d) * 0.5 for c, d in zip(corners, corners[1:] + corners[:1])]
            for point in samples:
                hit = tree.ray_cast(point - ray * 2.0, ray)
                if hit[0] is None:
                    print("  AUDIT %s: sample past the edge of the body" % label)
                    continue
                gap = (hit[0] - point).dot(ray)
                if gap > high:
                    worst = obj.name
                low, high = min(low, gap), max(high, gap)
    print("  AUDIT %s: gap %.1f to %.1f mm (highest: %s)" % (label, low * 1000, high * 1000, worst))


def chop(obj, z):
    """Slices off everything in front of the plane at Godot z, leaving one true flat face."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=tuple(w.gv(0, 0, z)), plane_no=(0, 1, 0), clear_outer=True)
    open_edges = [e for e in bm.edges if e.is_boundary]
    bmesh.ops.holes_fill(bm, edges=open_edges, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rim = [(v.co.x, v.co.z) for v in bm.verts if abs(-v.co.y - z) < 1e-5]
    print("  flat x %.3f to %.3f, y %.3f to %.3f" % (
        min(p[0] for p in rim), max(p[0] for p in rim), min(p[1] for p in rim), max(p[1] for p in rim)))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def snapshot(relative_path, direction, target=(0, 0, 0), span=None, tile=560):
    """One close render. [direction] is the Godot direction from the target to the camera."""
    scene = bpy.context.scene
    scene.render.resolution_x = tile
    scene.render.resolution_y = tile
    data = bpy.data.cameras.new("snap")
    data.lens = 60.0
    camera = bpy.data.objects.new("snap", data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    mesh = next(o for o in scene.objects if o.type == "MESH")
    radius = span or Vector(mesh.dimensions).length * 0.5
    data.clip_start = radius * 0.01
    data.clip_end = radius * 40.0
    heading = w.gv(*direction).normalized()
    camera.location = w.gv(*target) + heading * radius * 2.9
    camera.rotation_euler = (-heading).to_track_quat("-Z", "Y").to_euler()
    path = os.path.join(w.ROOT, relative_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)


def build_coal():
    coal = w.mat("coal", rough=0.35)
    white = w.mat("white")
    black = w.mat("black")
    gold = w.mat("brass", metal=0.8, rough=0.3)
    ember = w.mat(EMBER, emission=2.0)
    body = w.wobble(w.ball("body", 0.128, (0, 0, 0), coal, squash=(1.08, 0.82, 0.92), detail=2), 0.012, 7)
    # A chipped-flat front gives him somewhere to keep his face. Everything on it stays inside the flat.
    plane = -0.066
    chop(body, plane)
    tree = body_tree(body)
    parts = [body]
    decals = []
    u, v = (-1, 0, 0), (0, 1, 0)

    def at(a, b, layer):
        # The flat sits low on the lump, so the whole face does too.
        return (-a, b - 0.012, plane - 0.002 - layer * 0.0012)

    # Viewer's left and right eyes, mismatched, sliding sideways at you.
    for a, b, radius, tilt in ((-0.043, 0.012, 0.028, -9), (0.04, 0.014, 0.023, 10)):
        decals.append(disc("eye", at(a, b, 0), u, v, radius, white, sides=8))
        decals.append(disc("pupil", at(a + radius * 0.42, b - radius * 0.2, 1), u, v, radius * 0.34, black, sides=6))
        # Heavy half-closed lid: the whole of the smugness lives here.
        decals.append(rect("lid", at(a, b + radius * 0.56, 2), u, v, radius * 1.05, radius * 0.5, w.mat("iron"), tilt=tilt))
    decals.append(rect("brow", at(-0.045, 0.043, 3), u, v, 0.031, 0.0085, w.mat("bone"), tilt=-6))
    decals.append(rect("brow", at(0.043, 0.047, 3), u, v, 0.028, 0.0085, w.mat("bone"), tilt=20))
    # Smirk: one long lopsided grin with a gold tooth.
    decals.append(rect("grin", at(-0.014, -0.036, 0), u, v, 0.04, 0.0095, white, tilt=3))
    decals.append(rect("grin", at(0.042, -0.027, 0), u, v, 0.024, 0.0095, white, tilt=24))
    decals.append(rect("tooth", at(0.018, -0.032, 1), u, v, 0.011, 0.0115, gold, tilt=14))
    audit("coal face", decals, tree, (0, 0, 1))
    parts.extend(decals)
    # He has somehow got hold of a cigar. Coal, smoking. Cigar and ember share one axis.
    root = Vector((-0.05, -0.039, plane + 0.006))
    aim = Vector((-0.5, 0.2, -0.84)).normalized()
    butt = root + aim * 0.062
    tip_end = butt + aim * 0.014
    parts.append(tube("cigar", [tuple(root), tuple(butt)], [0.0145, 0.0155], w.mat("wood_dark"), side=(0, 1, 0)))
    parts.append(tube("tip", [tuple(butt), tuple(tip_end)], [0.0165, 0.0135], ember, side=(0, 1, 0)))
    # A glowing crack across the back: he is hot, and he knows it.
    crack = strip("crack", [(-0.092, 0.03), (-0.04, -0.018), (-0.012, 0.042), (0.038, -0.006), (0.092, -0.042)],
                  [0.006, 0.022, 0.024, 0.02, 0.005], ember, steps=4)
    drape(crack, tree, (0, 0, -1), 0.003)
    audit("coal crack", [crack], tree, (0, 0, -1))
    parts.append(crack)
    finish("coal", parts, (0.26, 0.2, 0.24), {
        "face": ((0, 0.1, -1), None, None), "back": ((0, 0.1, 1), None, None), "side": ((1, 0.1, -0.1), None, None)})


def build_crate():
    planks = w.mat("wood")
    bars = w.mat(LIGHT_WOOD)
    ink = w.mat("black")
    red = w.mat("tomato")
    half = 0.28
    high = 0.23
    lift = half + 0.004
    parts = [w.box("core", (half * 2, high * 2, half * 2), (0, 0, 0), planks)]
    # Rough frame, every bar a little out of true.
    rng = random.Random(4)
    for sx in (-1, 1):
        for sz in (-1, 1):
            post = w.box("post", (0.07, 0.5, 0.07), (sx * 0.28, 0, sz * 0.28), bars)
            parts.append(spin(post, "x", rng.uniform(-1.5, 1.5)))
    for y in (-0.225, 0.225):
        for s in (-1, 1):
            parts.append(spin(w.box("rail", (0.62, 0.06, 0.055), (0, y, s * 0.295), bars), "z", rng.uniform(-1.5, 1.5)))
            parts.append(spin(w.box("rail", (0.055, 0.06, 0.62), (s * 0.295, y, 0), bars), "x", rng.uniform(-1.5, 1.5)))
    # +Z: reassuring.
    parts.append(text("label", "NOT A\nBOMB", (0, 0, lift), (1, 0, 0), (0, 1, 0), 0.024, ink, tilt=-5, seed=1))
    # +X: something inside has noticed you.
    parts.append(flat("hole", [[
        (lift, -0.15, 0.2), (lift, -0.165, -0.04), (lift, -0.14, -0.2), (lift, 0.03, -0.17),
        (lift, 0.17, -0.205), (lift, 0.13, -0.03), (lift, 0.17, 0.14), (lift, 0.07, 0.205)]], ink))
    parts.append(w.ball("eye", 0.082, (half - 0.012, 0.0, 0.08), w.mat("white"), squash=(1, 1.2, 1), detail=2))
    parts.append(w.ball("eye", 0.056, (half - 0.012, 0.04, -0.1), w.mat("mustard"), detail=1))
    parts.append(disc("pupil", (half + 0.0705, -0.028, 0.092), (0, 0, -1), (0, 1, 0), 0.014, ink, sides=6))
    parts.append(disc("pupil", (half + 0.046, 0.022, -0.09), (0, 0, -1), (0, 1, 0), 0.01, ink, sides=6))
    parts.append(flat("splinter", [[(lift + 0.03, 0.17, 0.12), (lift + 0.03, 0.165, 0.2), (lift, 0.12, 0.16)]], bars))
    crate = w.join("crate", parts)
    # The whole crate leans, so the stencils lean with it.
    deform(crate, lambda x, y, z: (x + 0.05 * y, y + 0.03 * x, z - 0.03 * y))
    finish("crate", [crate], (0.62, 0.5, 0.62), {"top": ((0, 1, 0.08), None, None)})


def build_suitcase():
    shell = w.mat("teal")
    strap = w.mat("wood_dark")
    brass = w.mat("brass", metal=0.7, rough=0.4)
    hx, hy, hz = 0.27, 0.17, 0.07
    case = [pillow("shell", (-hx, -hx * 0.5, 0.0, hx * 0.5, hx), hy, hz, shell)]
    # The belt bites into the middle, so the case bulges out either side of it.
    t = 0.008
    case.append(w.box("belt", (0.05, 0.012, hz * 2 + 2 * t), (0, hy + t * 0.5, 0), strap))
    case.append(w.box("belt", (0.05, 0.012, hz * 2 + 2 * t), (0, -hy - t * 0.5, 0), strap))
    case.append(w.box("belt", (0.05, hy * 2 + 2 * t, 0.012), (0, 0, hz + t * 0.5), strap))
    case.append(w.box("belt", (0.05, hy * 2 + 2 * t, 0.012), (0, 0, -hz - t * 0.5), strap))
    for sx in (-1, 1):
        for sy in (-1, 1):
            case.append(w.box("corner", (0.05, 0.05, hz * 2 + 0.026), (sx * (hx - 0.012), sy * (hy - 0.012), 0), brass))
    body = w.join("case", case)

    def swell(x, y, z):
        pinch = min(abs(x) / 0.1, 1.0)
        across = 1.0 - min(abs(x) / hx, 1.0) ** 2
        tall = 1.0 - min(abs(y) / hy, 1.0) ** 2
        return (x * (1.0 + 0.03 * pinch),
                y * (1.0 + 0.22 * across * pinch),
                z * (1.0 + 0.85 * across * pinch * max(tall, 0.2)))

    deform(body, swell)
    tree = body_tree(triangulate(body))
    parts = [body]
    # Handle, held on by faith.
    parts.append(w.box("handle", (0.17, 0.028, 0.04), (0.14, 0.225, 0), strap))
    parts.append(spin(w.box("strut", (0.024, 0.05, 0.03), (0.075, 0.2, 0), brass), "z", -6))
    parts.append(spin(w.box("strut", (0.024, 0.05, 0.03), (0.205, 0.198, 0), brass), "z", 10))
    parts.append(w.box("buckle", (0.075, 0.075, 0.018), (0, 0.02, hz + 0.018), brass))
    # A sock has made a run for it through the seam.
    sock = w.mat("bubblegum")
    # The lid has sprung here, so there is a dark gap in the end wall for it to come out of.
    wall = hx * 1.03 + 0.0012
    gap = [(0.004, -0.125), (-0.004, -0.125), (-0.032, 0.03), (-0.012, 0.128), (0.012, 0.128), (0.032, 0.03)]
    parts.append(flat("seam", [[(wall, y, z) for z, y in gap]], w.mat("black")))
    parts.append(spin(w.box("sock", (0.05, 0.11, 0.035), (0.3, 0.09, 0.0), sock), "z", -22))
    parts.append(spin(w.box("toe", (0.085, 0.045, 0.04), (0.343, 0.02, 0.0), w.mat("white")), "z", -22))

    def stick(obj, direction, offset):
        return drape(obj, tree, direction, offset)

    case_all = w.join("case", parts)
    deform(case_all, lambda x, y, z: (x, y + 0.03 * x, z))
    finish("suitcase", [case_all], (0.62, 0.42, 0.22), {
        "front": ((0, 0.1, 1), None, None), "back": ((0, 0.1, -1), None, None), "side": ((1, 0.05, 0.25), None, None)})


def build_soup_bowl():
    cream = w.mat("cream", rough=0.5)
    rim = w.mat("navy", rough=0.5)
    soup = w.mat(GREY_SOUP, rough=0.3)
    pasta = w.mat(PASTA)

    def bite(index, angle, radius, height):
        # A neat row of tooth marks out of the rim, on the +X side.
        degrees = math.degrees(angle)
        if height > 0.03 and (degrees <= 45.0 or degrees >= 315.0):
            step = int(round(degrees / 22.5)) % 16
            return (radius, height - (0.018 if step % 2 == 0 else 0.006))
        return (radius, height)

    parts = [w.wobble(lathe("bowl", [(0.0, -0.05), (0.092, -0.05), (0.098, -0.04), (0.124, 0.015), (0.0, 0.015)],
                            (0, 0, 0), cream, segments=16), 0.002, 3)]
    parts.append(lathe("rim", [(0.0, 0.0), (0.124, 0.015), (0.13, 0.05), (0.116, 0.05), (0.108, 0.0), (0.0, 0.0)],
                       (0, 0, 0), rim, segments=16, tweak=bite))
    level = 0.032
    parts.append(disc("soup", (0, level, 0), (1, 0, 0), (0, 0, -1), 0.116, soup, sides=14))
    # The eye bobs half sunk, stares straight up at whoever ordered this, and is not happy.
    eye_center = (-0.012, level - 0.02, -0.04)
    radius = 0.05
    parts.append(w.ball("eye", radius, eye_center, w.mat("white", rough=0.2), detail=2))
    n = Vector((0.06, 0.9, 0.42)).normalized()
    u = Vector((0, 0, 1)).cross(n).normalized()
    v = n.cross(u).normalized()
    iris = tuple(eye_center[i] + n[i] * (radius + 0.0002) for i in range(3))
    parts.append(disc("iris", iris, tuple(u), tuple(v), 0.022, w.mat("tomato"), sides=9))
    dot = tuple(iris[i] + n[i] * 0.0012 for i in range(3))
    parts.append(disc("pupil", dot, tuple(u), tuple(v), 0.0065, w.mat("black"), sides=6))
    # Alphabet soup, and the letters have an opinion.
    # Big, nearly straight and on the near side of the bowl, so the rim hides less of them.
    for char, x, z, tilt in (("R", -0.056, 0.054, -9), ("U", -0.002, 0.066, 2), ("N", 0.054, 0.054, 9)):
        parts.append(text("pasta", char, (x, level + 0.002, z), (1, 0, 0), (0, 0, -1), 0.0128, pasta, tilt=tilt, seed=4))
    finish("soup_bowl", parts, (0.26, 0.1, 0.26), {"top": ((0, 1, 0.02), None, 0.17), "over": ((0, 0.75, 0.75), None, None), "low": ((0.1, 0.4, 1), None, None)})


def build_wrench():
    steel = w.mat("steel", metal=0.6, rough=0.45)
    rust = w.mat("rust")
    y0, y1 = -0.018, 0.018
    outline = [(-0.024, 0.28), (0.024, 0.28), (0.031, 0.25), (0.024, 0.02), (0.03, -0.055), (0.072, -0.1),
               (0.074, -0.205), (0.05, -0.285), (0.03, -0.27), (0.026, -0.15), (-0.026, -0.15), (-0.03, -0.235),
               (-0.052, -0.245), (-0.074, -0.19), (-0.07, -0.1), (-0.03, -0.055), (-0.024, 0.02), (-0.031, 0.25)]
    parts = [plate("wrench", outline, y0, y1, steel)]
    # The jaw has teeth. Actual teeth.
    teeth = w.mat("bone")
    for z, x0, tip in ((-0.255, 0.031, 0.008), (-0.215, 0.028, 0.004), (-0.175, 0.027, 0.006)):
        parts.append(plate("tooth", [(x0 + 0.003, z - 0.019), (x0 + 0.003, z + 0.019), (tip, z)], y0 + 0.003, y1 - 0.003, teeth))
    for z, x0, tip in ((-0.215, -0.029, -0.006), (-0.175, -0.027, -0.002)):
        parts.append(plate("tooth", [(x0 - 0.003, z + 0.019), (x0 - 0.003, z - 0.019), (tip, z)], y0 + 0.003, y1 - 0.003, teeth))
    # Wide-set googly eyes, one on each prong, looking in different directions.
    eye_top = 0.0305
    parts.append(w.ball("eye", 0.032, (0.046, 0.018, -0.17), w.mat("white"), squash=(1, 0.38, 1), detail=2))
    parts.append(w.ball("eye", 0.025, (-0.05, 0.018, -0.165), w.mat("white"), squash=(1, 0.48, 1), detail=2))
    parts.append(disc("pupil", (0.053, eye_top, -0.178), (1, 0, 0), (0, 0, -1), 0.0105, w.mat("black"), sides=6))
    parts.append(disc("pupil", (-0.055, eye_top, -0.157), (1, 0, 0), (0, 0, -1), 0.0075, w.mat("black"), sides=6))
    top = y1 + 0.002
    bottom = y0 - 0.002
    parts.append(disc("rust", (0.05, top, -0.115), (1, 0, 0), (0, 0, -1), 0.021, rust, sides=6, squash=0.7))
    parts.append(disc("rust", (-0.02, bottom, 0.07), (1, 0, 0), (0, 0, 1), 0.02, rust, sides=6, squash=1.6))
    # The stamp, for the avoidance of doubt.
    # Repaired grip, in the proper engineering way.
    tape = w.mat("tomato")
    parts.append(spin(w.box("tape", (0.07, 0.045, 0.05), (0, 0, 0.245), tape), "y", 5))
    parts.append(spin(w.box("tape", (0.068, 0.043, 0.024), (0, 0, 0.205), tape), "y", -7))
    wrench = w.join("wrench", parts)
    deform(wrench, lambda x, y, z: (x + 0.018 * math.sin((z + 0.05) * 5.0) if z > -0.05 else x + 0.0, y, z))
    finish("wrench", [wrench], (0.14, 0.05, 0.56), {"top": ((0.2, 1, 0.1), (0, 0, -0.14), 0.2)})


def build_frying_pan():
    iron = w.mat("iron", metal=0.5, rough=0.5)
    print_mat = w.mat(SCRAPED, metal=0.3, rough=0.35)
    pale = w.mat(FACE_STEEL, metal=0.2, rough=0.4)
    dark = w.mat("black")
    white = w.mat("white")
    pan_z = -0.16

    def flattened(index, angle, radius, height):
        # The rim took the worst of it: squashed flat on one side.
        degrees = math.degrees(angle)
        if 20.0 <= degrees <= 75.0 and height > 0.0:
            return (radius * 0.9, height - 0.012)
        return (radius, height)

    # The base is properly stove in: a real recess underneath, a real bulge inside.
    roof = -0.006
    profile = [(0.0, roof), (0.098, roof), (0.106, -0.03), (0.122, -0.03), (0.15, 0.03), (0.136, 0.03),
               (0.116, -0.014), (0.104, -0.014)]
    parts = [w.wobble(lathe("pan", profile, (0, 0, pan_z), iron, segments=12, tweak=flattened), 0.0012, 5)]
    parts.append(lathe("dome", [(0.104, -0.0145), (0.08, 0.011), (0.045, 0.022), (0.0, 0.025)], (0, 0, pan_z), w.mat(SCOURED, rough=0.6), segments=10))

    def under(x, z, layer=1):
        return (x, roof - 0.001 - layer * 0.0009, pan_z + z)

    # Underside: the print, sunk into the recess. A very surprised somebody, forehead towards -Z.
    u, v = (-1, 0, 0), (0, 0, -1)
    parts.append(disc("print", under(0, 0, 0), u, v, 0.086, print_mat, sides=9, squash=1.1))
    parts.append(disc("eye", under(-0.04, -0.03), u, v, 0.024, dark, sides=6))
    parts.append(disc("eye", under(0.042, -0.036), u, v, 0.018, dark, sides=6))
    parts.append(disc("glint", under(-0.04, -0.03, 2), u, v, 0.007, white, sides=4))
    parts.append(disc("glint", under(0.042, -0.036, 2), u, v, 0.005, white, sides=4))
    parts.append(rect("brow", under(-0.04, -0.068), u, v, 0.03, 0.0075, dark, tilt=14))
    parts.append(rect("brow", under(0.043, -0.07), u, v, 0.025, 0.0075, dark, tilt=-22))
    # A nose that has been sat on, wide and flat.
    parts.append(w.ball("nose", 0.034, (0.002, roof - 0.003, pan_z + 0.008), pale, squash=(1.3, 0.5, 0.7), detail=1))
    parts.append(disc("mouth", under(0.002, 0.056), u, v, 0.032, dark, sides=7, squash=0.72))
    parts.append(disc("gap", under(-0.01, 0.046, 2), u, v, 0.008, white, sides=4))
    # Inside, the same face has punched up through the floor of the pan.
    parts.append(w.ball("nose", 0.04, (0, 0.0185, pan_z + 0.004), w.mat("tomato"), squash=(0.72, 0.34, 1.2), detail=1))
    parts.append(w.ball("eye", 0.034, (-0.046, 0.0185, pan_z - 0.038), dark, squash=(1, 0.2, 1.05), detail=1))
    parts.append(w.ball("eye", 0.027, (0.05, 0.0185, pan_z - 0.042), dark, squash=(1, 0.22, 1.05), detail=1))
    parts.append(disc("pupil", (-0.046, 0.0258, pan_z - 0.038), (1, 0, 0), (0, 0, -1), 0.0125, white, sides=5))
    parts.append(disc("pupil", (0.05, 0.0253, pan_z - 0.042), (1, 0, 0), (0, 0, -1), 0.0095, white, sides=5))
    parts.append(spin(w.box("brow", (0.066, 0.016, 0.017), (-0.05, 0.0135, pan_z - 0.086), dark), "y", 16))
    parts.append(spin(w.box("brow", (0.058, 0.016, 0.017), (0.054, 0.0125, pan_z - 0.088), dark), "y", -24))
    parts.append(w.ball("mouth", 0.044, (0.002, 0.0145, pan_z + 0.066), dark, squash=(1, 0.22, 0.62), detail=1))
    parts.append(spin(w.box("tooth", (0.024, 0.014, 0.02), (-0.015, 0.0215, pan_z + 0.058), white, taper=0.75), "y", 10))
    parts.append(spin(w.box("tooth", (0.018, 0.014, 0.016), (0.02, 0.0205, pan_z + 0.082), w.mat("mustard"), taper=0.75), "y", -12))
    # Handle: iron neck, wooden grip, an apology and a running score.
    parts.append(plate("neck", [(-0.03, -0.03), (0.03, -0.03), (0.025, 0.105), (-0.025, 0.105)], -0.002, 0.024, iron))
    grip = w.mat("wood_dark")
    parts.append(plate("grip", [(-0.03, 0.085), (0.03, 0.085), (0.036, 0.27), (0.02, 0.31), (-0.02, 0.31), (-0.036, 0.27)],
                       -0.01, 0.026, grip))
    parts.append(w.ball("rivet", 0.012, (0, 0.0265, 0.097), w.mat("brass", metal=0.7), squash=(1, 0.42, 1), detail=1))
    top = 0.0268
    for i in range(4):
        parts.append(rect("tally", (-0.0165 + i * 0.011, top, 0.142), (1, 0, 0), (0, 0, -1), 0.003, 0.019, w.mat("bone"), tilt=4))
    parts.append(rect("tally", (0.0, top + 0.0007, 0.142), (1, 0, 0), (0, 0, -1), 0.03, 0.003, w.mat("tomato"), tilt=24))
    pan = w.join("pan", parts)
    deform(pan, lambda x, y, z: (x + (0.03 * ((z - 0.02) / 0.3) ** 2 if z > 0.02 else 0.0), y, z))
    finish("frying_pan", [pan], (0.3, 0.06, 0.62), {
        "under": ((0.0, -1, -0.25), (0, 0, -0.16), 0.2), "inside": ((0.35, 0.8, 0.8), (0, 0, -0.16), 0.2),
        "low": ((0, 0.45, 1), (0, 0, -0.16), 0.2)})


def build_broom():
    pole = w.mat("wood")
    twine = w.mat("tomato")
    skin = w.mat("skin_a")
    ink = w.mat("black")
    white = w.mat("white")
    # Handle in three bad decisions, spliced together with tape.
    length = 1.35
    tip = length * 0.5
    parts = []
    parts.append(spin(w.cyl("stick", 0.028, 0.43, (0.0, 0.0, 0.04), pole, axis="z", verts=5), "y", 1.5))
    parts.append(spin(w.cyl("stick", 0.026, 0.46, (0.03, 0.006, 0.44), w.mat(LIGHT_WOOD), axis="z", verts=5), "y", 9))
    parts.append(spin(w.box("splint", (0.068, 0.05, 0.05), (0.012, 0.004, 0.19), w.mat("mustard")), "y", 8))
    parts.append(spin(w.box("splint", (0.068, 0.05, 0.05), (0.022, 0.006, 0.31), w.mat("mustard")), "y", 3))
    parts.append(w.cyl("cap", 0.034, 0.05, (0.068, 0.012, tip - 0.03), twine, axis="z", verts=5))
    # The head IS an elderly gentleman: the full width of the broom, ears out, bristles for a wild beard.
    head_z = -0.27
    outline = [(-0.1, 0.11), (0.1, 0.11), (0.125, 0.06), (0.122, 0.02), (0.14, 0.04), (0.14, -0.02), (0.116, -0.035),
               (0.108, -0.125), (-0.108, -0.125), (-0.116, -0.035), (-0.14, -0.02), (-0.14, 0.04), (-0.122, 0.02), (-0.125, 0.06)]
    slab = 0.018
    parts.append(plate("head", [(x, z + head_z) for x, z in outline], -slab, slab, skin))
    parts.append(w.box("collar", (0.11, 0.05, 0.03), (0, 0, head_z + 0.122), twine))
    parts.append(spin(w.box("band", (0.24, 0.048, 0.03), (0, 0, head_z - 0.13), twine), "y", 2))
    face = slab + 0.0006
    u, v = (-1, 0, 0), (0, 0, 1)

    def eye(x, z, radius, colour, look):
        lift = 0.013
        parts.append(lathe("eye", [(radius, 0.0), (radius * 0.62, lift), (0.0, lift)], (x, slab - 0.001, z), w.mat(colour), segments=8))
        parts.append(disc("pupil", (x + look[0], slab + lift + 0.0006, z + look[1]), u, v, radius * 0.24, ink, sides=5))

    # One huge wandering eye, one small suspicious one.
    eye(0.058, head_z + 0.03, 0.054, "white", (-0.012, -0.012))
    eye(-0.058, head_z + 0.036, 0.038, "mustard", (0.009, 0.008))
    parts.append(w.ball("nose", 0.05, (0.002, slab, head_z - 0.012), w.mat("tomato"), squash=(0.95, 0.44, 1.2), detail=1))
    parts.append(spin(w.box("brow", (0.1, 0.022, 0.024), (0.06, slab + 0.004, head_z + 0.092), white), "y", 12))
    parts.append(spin(w.box("brow", (0.082, 0.022, 0.024), (-0.06, slab + 0.004, head_z + 0.082), white), "y", -18))
    # Wide open, one last complaint, four surviving teeth.
    parts.append(flat("mouth", [[(0.086, face, head_z - 0.066), (0.078, face, head_z - 0.112), (-0.07, face, head_z - 0.114),
                                 (-0.088, face, head_z - 0.06)]], ink))
    for x, half, drop, colour, tilt in ((0.055, 0.015, 0.027, "bone", -6), (0.014, 0.011, 0.021, "mustard", 8),
                                        (-0.014, 0.012, 0.03, "white", -4), (-0.058, 0.014, 0.022, "bone", 10)):
        top_z = head_z - 0.064 + x * 0.04
        parts.append(rect("tooth", (x, face + 0.0008, top_z - drop * 0.5), u, v, half, drop * 0.5, w.mat(colour), tilt=tilt))
    # Back of the head: a bald patch, a brave comb-over, and his employment status.
    back = -slab - 0.0006
    u_back, v_back = (1, 0, 0), (0, 0, 1)
    parts.append(disc("bald", (0, back, head_z + 0.05), u_back, v_back, 0.058, w.mat(BALD), sides=8, squash=0.9))
    for offset, tilt in ((0.03, 5), (0.012, -2), (-0.008, 4)):
        parts.append(rect("combover", (0, back - 0.0008, head_z + 0.05 + offset), u_back, v_back, 0.082, 0.0042, white, tilt=tilt))
    # Beard: fat clumps at different lengths and angles, each pinched into a point.
    straw = w.mat(STRAW)
    gold = w.mat("mustard")
    rust = w.mat("rust")
    root_z = head_z - 0.125
    clumps = (
        (-0.094, -0.112, -0.535, -0.006, 0.018, straw),
        (-0.064, -0.098, -0.672, 0.012, -0.02, gold),
        (-0.038, -0.03, -0.61, -0.02, -0.024, rust),
        (-0.008, -0.04, -0.675, 0.02, -0.02, straw),
        (0.024, 0.016, -0.565, -0.012, 0.022, gold),
        (0.05, 0.06, -0.655, -0.02, -0.022, straw),
        (0.078, 0.1, -0.6, -0.006, 0.016, rust),
    )
    for root_x, tip_x, tip_z, kink, tip_y, colour in clumps:
        middle = (root_x * 0.45 + tip_x * 0.55 + kink, tip_y * 0.4, root_z + (tip_z - root_z) * 0.55)
        parts.append(tube("clump", [(root_x, 0, root_z + 0.012), middle, (tip_x, tip_y, tip_z)],
                          [(0.034, 0.017), (0.042, 0.019), 0.0], colour, section=DIAMOND, side=(1, 0, 0), caps=False))
    # One clump has snapped clean over and is pointing at the horizon.
    parts.append(tube("snapped", [(0.106, 0, root_z + 0.012), (0.104, 0.008, root_z - 0.1), (0.13, -0.006, root_z - 0.122)],
                      [(0.03, 0.016), (0.03, 0.016), (0.009, 0.006)], straw, section=DIAMOND, side=(1, 0, 0), caps=False))
    parts.append(tube("stray", [(-0.112, -0.012, root_z + 0.01), (-0.122, -0.03, root_z - 0.09), (-0.095, -0.036, root_z - 0.15)],
                      [(0.016, 0.01), (0.012, 0.008), 0.0], gold, section=DIAMOND, side=(1, 0, 0), caps=False))
    # Somebody's sock got swept up. It is snagged on the outside, in full view, and it will not be coming back.
    sock = w.mat("bubblegum")
    parts.append(plate("sock", [(-0.098, -0.455), (-0.044, -0.462), (-0.04, -0.552), (-0.004, -0.588), (-0.022, -0.624),
                                (-0.086, -0.57)], 0.024, 0.04, sock))
    parts.append(plate("toe", [(-0.0035, -0.587), (-0.022, -0.625), (-0.052, -0.598), (-0.026, -0.572)], 0.0245, 0.0405, white))
    parts.append(rect("stripe", (-0.071, 0.0406, -0.49), (1, 0, 0), (0, 0, -1), 0.03, 0.007, white, tilt=4))
    finish("broom", parts, (0.28, 0.08, 1.35), {
        "face": ((0, 1, -0.1), (0, 0, -0.42), 0.34), "back": ((0, -1, -0.1), (0, 0, -0.42), 0.34),
        "angle": ((0.6, 0.7, -0.5), (0, 0, -0.42), 0.34), "far": ((0.25, 1, 0.1), (0, 0, 0), 0.75)})


def build_hand():
    glove = w.mat(LEATHER)
    skin = w.mat("skin_a")
    knuckle = w.mat(SKIN_RED)
    ink = w.mat("navy")
    # A fist that has only ever been used for carrying soup and hitting people.
    palm_top = 0.056
    parts = [w.box("palm", (0.132, 0.112, 0.112), (0.0, 0.0, 0.03), glove, bevel=0.013)]
    # Fingers, index at -X: one fat folded sausage each, wide across the top so the ink has room.
    letters = "SOUP"
    long = (0.0, 0.006, 0.003, -0.007)
    rise = (0.0, 0.002, 0.001, -0.004)
    for i in range(4):
        x = -0.0525 + i * 0.035
        reach, h = long[i], rise[i]
        path = [(x, 0.044 + h, -0.016), (x, 0.047 + h, -0.069 - reach), (x, 0.012 + h, -0.1 - reach), (x, -0.034, -0.078 - reach * 0.5)]
        radii = [(0.0178, 0.021), (0.0178, 0.021), (0.0178, 0.027), (0.0176, 0.021)]
        parts.append(tube("finger", path, radii, skin))
        # Great raw knuckle bursting through the leather.
        parts.append(lathe("knuckle", [(0.0215, 0.0), (0.0165, 0.0135), (0.0, 0.0195)], (x, 0.052 + h, -0.016), knuckle, segments=6))
        # The ink sits on the finger's own top face, so it tilts with the finger.
        rings = ring_points(path, radii, HEX, (1, 0, 0))
        a0, a1, b0, b1 = rings[0][0], rings[0][1], rings[1][0], rings[1][1]
        along = (b0 - a0).normalized()
        across = Vector((1, 0, 0))
        normal = across.cross(along).normalized()
        mid = (a0 + a1 + b0 + b1) * 0.25 + along * 0.003 + normal * 0.0012
        parts.append(text("tattoo", letters[i], tuple(mid), tuple(across), tuple(along), 0.0062, ink, seed=i + 1))
    # Thumb the size of a bread roll, crossing the front, with a heroic sticking plaster doing nothing.
    root = (-0.043, -0.012, 0.0)
    bend = (-0.041, -0.02, -0.062)
    knob = (-0.008, -0.031, -0.09)
    end = (0.048, -0.031, -0.092)
    parts.append(tube("thumb", [root, bend], [0.03, 0.03], glove, side=(0, 1, 0), caps=False))
    parts.append(tube("thumb", [bend, knob, end, lerp3(knob, end, 1.14)], [0.03, 0.031, 0.026, 0.012], skin, side=(0, 1, 0)))
    plaster = w.mat(PLASTER)
    a, b = lerp3(knob, end, 0.05), lerp3(knob, end, 0.74)
    parts.append(tube("plaster", [a, b], [0.0335, 0.0305], plaster, side=(0, 1, 0), caps=False))
    parts.append(tube("pad", [lerp3(a, b, 0.32), lerp3(a, b, 0.68)], [0.0355, 0.0345], w.mat("white"), side=(0, 1, 0), caps=False))
    # Wrist cuff, chunky, flared and properly torn.
    fray = w.mat("oxblood")
    sides = 10
    tear = (0.122, 0.098, 0.125, 0.104, 0.082, 0.126, 0.1, 0.121, 0.094, 0.128)
    bm = bmesh.new()

    def cuff_ring(z, grow, jag):
        ring = []
        for j in range(sides):
            angle = math.tau * (j + 0.5) / sides
            cx, cy = math.cos(angle), math.sin(angle)
            sx = max(abs(cx), abs(cy))
            r = grow + (0.004 if j % 2 else -0.004) * jag
            zz = z if jag == 0 else tear[j]
            ring.append(bm.verts.new(tuple(w.gv(cx / sx * r, cy / sx * r, zz))))
        return ring

    rings = [cuff_ring(0.058, 0.061, 0), cuff_ring(0.082, 0.07, 0), cuff_ring(0.0, 0.064, 1)]
    for p, q in zip(rings, rings[1:]):
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((p[j], p[k], q[k], q[j]))
    parts.append(w._finish("cuff", bm, (0, 0, 0), fray))
    # The arm stops here, which the player sees end-on when punching, so it gets some hair.
    parts.append(disc("wrist", (0, 0, 0.09), (1, 0, 0), (0, 1, 0), 0.056, skin, sides=6))
    # All combed one way, so it reads as a pelt and not as a row of dashes.
    hairs = ((-0.024, 0.024, 62), (-0.008, 0.03, 78), (0.016, 0.03, 55), (-0.036, 0.0, 70), (-0.014, 0.006, 50),
             (0.01, 0.008, 74), (0.033, 0.004, 60), (-0.024, -0.024, 76), (0.0, -0.022, 58), (0.024, -0.026, 82))
    for hx_, hy_, tilt in hairs:
        parts.append(rect("hair", (hx_, hy_, 0.0908), (1, 0, 0), (0, 1, 0), 0.017, 0.0026, w.mat("black"), tilt=tilt))
    # Patch on the back of the hand, stitched by a man who has given up.
    back_y = palm_top + 0.0008
    parts.append(rect("patch", (0.012, back_y, 0.03), (1, 0, 0), (0, 0, -1), 0.03, 0.026, w.mat("teal"), tilt=11))
    for ax, az, spin_deg in ((-0.018, 0.012, 45), (0.042, 0.016, -40), (0.04, 0.05, 50), (-0.018, 0.05, -35)):
        parts.append(rect("stitch", (ax, back_y + 0.0008, az), (1, 0, 0), (0, 0, -1), 0.012, 0.0028, w.mat("white"), tilt=spin_deg))
    parts.append(disc("hole", (-0.044, back_y, 0.046), (1, 0, 0), (0, 0, -1), 0.012, skin, sides=6, squash=1.5))
    finish("hand", parts, (0.14, 0.14, 0.24), {
        "fp": ((0.0, 0.8, 0.75), None, None), "ingame": ((-0.24, 0.22, 0.42), None, None), "front": ((0.15, 0.1, -1), None, None),
        "under": ((-0.4, -0.9, -0.4), None, None), "side": ((1, 0.1, 0), None, None)})


BUILDS = {
    "coal": build_coal,
    "crate": build_crate,
    "suitcase": build_suitcase,
    "soup_bowl": build_soup_bowl,
    "wrench": build_wrench,
    "frying_pan": build_frying_pan,
    "broom": build_broom,
    "hand": build_hand,
}

wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(BUILDS)
for key in wanted:
    w.reset_scene()
    BUILDS[key]()
