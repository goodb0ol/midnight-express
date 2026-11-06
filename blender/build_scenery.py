"""Builds the snowy wasteland scenery: assets/models/scenery/*.glb and preview sheets.

Run with:
  blender.exe --background --python blender/build_scenery.py

Scenery is drawn hundreds of times through MultiMesh, so nothing here uses the kit's
box()/cyl() helpers. Mesh() below writes faces by hand: hidden faces are never made,
decals are single quads, and snow is a recolour of upward faces, which costs no tris.
All coordinates are Godot coordinates (X right, Y up, -Z forward).
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.geometry import intersect_ray_tri

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import wacky  # noqa: E402

CARROT = (0.5, 0.2, 0.06)
EXTRA_COLOURS = {"carrot": CARROT}
GLOW = {"eyeglow": ("mustard", 1.5)}

Y_AXIS = Vector((0, 1, 0))


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def rot(x=0.0, y=0.0, z=0.0):
    """Rotation in degrees about Godot axes, applied X then Y then Z."""
    return (Matrix.Rotation(math.radians(z), 4, "Z")
            @ Matrix.Rotation(math.radians(y), 4, "Y")
            @ Matrix.Rotation(math.radians(x), 4, "X"))


def scale(x=1.0, y=1.0, z=1.0):
    return Matrix.Diagonal((x, y, z, 1.0))


def facing(position, normal):
    """Local +Z becomes [normal], local +Y stays as upright as it can."""
    n = Vector(normal).normalized()
    up = Y_AXIS if abs(n.y) < 0.95 else Vector((0, 0, -1))
    right = up.cross(n).normalized()
    true_up = n.cross(right)
    result = Matrix.Identity(4)
    result.col[0][:3] = right
    result.col[1][:3] = true_up
    result.col[2][:3] = n
    result.col[3][:3] = Vector(position)
    return result


class Mesh:
    """One mesh built face by face, with [m] applied to everything added."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.m = Matrix.Identity(4)
        self.stick_dir = None
        self.stick_lift = 0.0
        self.stick_tris = []
        self.stick_polys = []

    def at(self, matrix):
        self.m = matrix
        return self

    def home(self):
        self.m = Matrix.Identity(4)
        return self

    def _v(self, point):
        self.verts.append(self.m @ Vector((*point, 0.0) if len(point) == 2 else point))
        return len(self.verts) - 1

    def poly(self, points, mat):
        """Polygon, counter-clockwise seen from outside."""
        indices = [self._v(p) for p in points]
        if self.stick_dir is not None:
            self.stick_polys.append(indices)
        self.faces.append((indices, mat))

    def stick_to(self, direction, lift=0.03):
        """Polygons added before unstick() form one flat decal, dropped along [direction].

        Hand-placed decals hover or sink on faceted, lumpy surfaces. This slides the
        whole group rigidly until its closest point sits [lift] off what is built so far.
        """
        self.stick_dir = Vector(direction).normalized()
        self.stick_lift = lift
        self.stick_polys = []
        self.stick_tris = []
        for indices, _mat in self.faces:
            corners = [self.verts[i] for i in indices]
            for i in range(1, len(corners) - 1):
                self.stick_tris.append((corners[0], corners[i], corners[i + 1]))

    def _gap(self, point):
        """Distance along the stick direction to the first surface, or None on a miss."""
        start = point - self.stick_dir * 6.0
        nearest = None
        for a, b, c in self.stick_tris:
            hit = intersect_ray_tri(a, b, c, self.stick_dir, start)
            if hit is not None:
                gap = (hit - point).dot(self.stick_dir)
                nearest = gap if nearest is None else min(nearest, gap)
        return nearest

    def _conform(self):
        """Lays each decal vertex on the surface, so nothing stands off as a flat card.

        Layers stay apart: a pupil keeps its offset above the white it sits on.
        """
        direction = self.stick_dir
        indices = {i for group in self.stick_polys for i in group}
        a, b, c = (self.verts[i] for i in self.stick_polys[0][:3])
        outward = (b - a).cross(c - a).normalized()
        if outward.dot(direction) > 0.0:
            outward = -outward
        moves = {}
        for i in indices:
            gap = self._gap(self.verts[i])
            if gap is not None:
                layer = max((self.verts[i] - a).dot(outward), 0.0)
                moves[i] = direction * (gap - self.stick_lift - layer)
        fallback = sum(moves.values(), Vector((0, 0, 0))) / max(len(moves), 1)
        for i in indices:
            self.verts[i] = self.verts[i] + moves.get(i, fallback)
        self.stick_dir = None

    def turn(self):
        """Half turn about Y. _place_gag aims local +Z at the track, so gags built
        facing -Z finish with this to show their face to the train."""
        self.verts = [Vector((-v.x, v.y, -v.z)) for v in self.verts]

    def unstick(self, conform=False):
        if conform:
            self._conform()
            return
        direction = self.stick_dir
        samples = []
        for indices in self.stick_polys:
            corners = [self.verts[i] for i in indices]
            middle = sum(corners, Vector((0, 0, 0))) / len(corners)
            samples.append(middle)
            samples.extend(corners)
            samples.extend(c.lerp(middle, 0.5) for c in corners)
        gaps = [gap for gap in (self._gap(sample) for sample in samples) if gap is not None]
        if gaps:
            shift = direction * (min(gaps) - self.stick_lift)
            for index in {i for indices in self.stick_polys for i in indices}:
                self.verts[index] = self.verts[index] + shift
        self.stick_dir = None

    def _face(self, indices, mat):
        unique = []
        for index in indices:
            if index not in unique:
                unique.append(index)
        if len(unique) >= 3:
            self.faces.append((unique, mat))

    def tri_facing(self, a, b, c, normal, mat):
        """Triangle in world space, wound to face [normal]."""
        a, b, c = Vector(a), Vector(b), Vector(c)
        if (b - a).cross(c - a).dot(Vector(normal)) < 0.0:
            b, c = c, b
        keep, self.m = self.m, Matrix.Identity(4)
        self.poly([a, b, c], mat)
        self.m = keep

    def box(self, size, center=(0, 0, 0), mat="wood", taper=1.0, skip=""):
        """Box. [skip] drops faces: any of 'xXyYzZ' (lower case is the negative face)."""
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        cx, cy, cz = center

        def p(sx, sy, sz):
            t = taper if sy > 0 else 1.0
            return (cx + sx * hx * t, cy + sy * hy, cz + sz * hz * t)

        sides = {
            "X": [(1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)],
            "x": [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)],
            "Y": [(-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)],
            "y": [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
            "Z": [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
            "z": [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)],
        }
        for key, corners in sides.items():
            if key not in skip:
                self.poly([p(*c) for c in corners], mat)

    def lathe(self, rings, sides, mat, cap=False, phase=0.0, lump=0.0, seed=1, nudge=None):
        """Stack of rings up Y. Each ring is (y, radius) or (y, radius, cx, cz).

        Angle 0 is -Z, turning toward +X. A radius of 0 is a single apex vertex.
        [mat] is a name or fn(ring, side). [nudge] is fn(ring, side, point) -> point.
        Returns the world-space corner of every (ring, side) for placing things on it.
        """
        rng = random.Random(seed)
        grid = []
        corners = []
        for i, ring in enumerate(rings):
            y, radius = ring[0], ring[1]
            cx = ring[2] if len(ring) > 2 else 0.0
            cz = ring[3] if len(ring) > 3 else 0.0
            if radius <= 0.0:
                point = Vector((cx, y, cz))
                if nudge:
                    point = Vector(nudge(i, 0, point))
                index = self._v(point)
                grid.append([index] * sides)
                corners.append([self.verts[index]] * sides)
                continue
            row = []
            for j in range(sides):
                angle = phase + math.tau * j / sides
                push = 1.0 + rng.uniform(-lump, lump)
                point = Vector((cx + radius * push * math.sin(angle), y,
                                cz - radius * push * math.cos(angle)))
                if lump:
                    point.y += rng.uniform(-lump, lump) * radius * 0.6
                if nudge:
                    point = Vector(nudge(i, j, point))
                row.append(self._v(point))
            grid.append(row)
            corners.append([self.verts[index] for index in row])
        pick = mat if callable(mat) else (lambda _i, _j: mat)
        for i in range(len(rings) - 1):
            for j in range(sides):
                k = (j + 1) % sides
                self._face([grid[i][k], grid[i][j], grid[i + 1][j], grid[i + 1][k]], pick(i, j))
        if cap:
            self._face(list(grid[0]), pick(0, 0))
        return corners

    def tube(self, path, radii, sides, mat, top_cap=False, twist=0.0, phase=0.0):
        """Bent tube along [path]. A last radius of 0 ends in a point. Open at the start."""
        path = [Vector(p) for p in path]
        grid = []
        first = (path[1] - path[0]).normalized()
        seed_axis = Vector((1, 0, 0)) if abs(first.x) < 0.8 else Vector((0, 0, 1))
        u = first.cross(seed_axis).normalized()
        for i, centre in enumerate(path):
            before = path[max(i - 1, 0)]
            after = path[min(i + 1, len(path) - 1)]
            t = (after - before).normalized()
            u = (u - t * u.dot(t)).normalized()
            v = t.cross(u)
            if radii[i] <= 0.0:
                grid.append([self._v(centre)] * sides)
                continue
            row = []
            for j in range(sides):
                angle = phase + twist * i + math.tau * j / sides
                row.append(self._v(centre + (u * math.cos(angle) + v * math.sin(angle)) * radii[i]))
            grid.append(row)
        pick = mat if callable(mat) else (lambda _i, _j: mat)
        for i in range(len(path) - 1):
            for j in range(sides):
                k = (j + 1) % sides
                self._face([grid[i][j], grid[i][k], grid[i + 1][k], grid[i + 1][j]], pick(i, j))
        if top_cap and radii[-1] > 0.0:
            self._face(list(grid[-1]), pick(len(path) - 2, 0))

    def disc(self, center, radius, sides, mat, squash=1.0, spin=0.0):
        """Flat polygon in the local XY plane, facing local +Z."""
        cx, cy, cz = center
        self.poly([(cx + radius * math.cos(spin + math.tau * j / sides),
                    cy + radius * squash * math.sin(spin + math.tau * j / sides), cz)
                   for j in range(sides)], mat)

    def blob(self, radius, center, mat, squash=(1, 1, 1), lump=0.0, seed=1):
        """Twenty-face lump."""
        phi = (1 + 5 ** 0.5) / 2
        raw = [(-1, phi, 0), (1, phi, 0), (-1, -phi, 0), (1, -phi, 0),
               (0, -1, phi), (0, 1, phi), (0, -1, -phi), (0, 1, -phi),
               (phi, 0, -1), (phi, 0, 1), (-phi, 0, -1), (-phi, 0, 1)]
        tris = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
                (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
                (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
                (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
        rng = random.Random(seed)
        indices = []
        for v in raw:
            n = Vector(v).normalized() * radius * (1.0 + rng.uniform(-lump, lump))
            indices.append(self._v((center[0] + n.x * squash[0], center[1] + n.y * squash[1],
                                    center[2] + n.z * squash[2])))
        for a, b, c in tris:
            self._face([indices[a], indices[b], indices[c]], mat)

    def slab(self, points, depth, mat, rim=None):
        """Extrudes a counter-clockwise 2D outline along local Z, centred on z=0."""
        front = [(x, y, depth / 2) for x, y in points]
        back = [(x, y, -depth / 2) for x, y in reversed(points)]
        self.poly(front, mat)
        self.poly(back, mat)
        for i, (x, y) in enumerate(points):
            nx, ny = points[(i + 1) % len(points)]
            self.poly([(x, y, -depth / 2), (nx, ny, -depth / 2), (nx, ny, depth / 2), (x, y, depth / 2)],
                      rim or mat)

    def snowfall(self, on, threshold=0.55):
        """Recolours every upward face of materials in [on] as snow. Costs nothing."""
        names = set(on)
        for n, (indices, mat) in enumerate(self.faces):
            if mat not in names:
                continue
            normal = Vector((0, 0, 0))
            for i, index in enumerate(indices):
                a = self.verts[index]
                b = self.verts[indices[(i + 1) % len(indices)]]
                normal += a.cross(b)
            if normal.length > 0 and normal.normalized().y > threshold:
                self.faces[n] = (indices, "snow")

    def build(self, name="Scenery"):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([wacky.gv(*v) for v in self.verts], [], [f[0] for f in self.faces])
        slots = {}
        for _indices, mat in self.faces:
            if mat not in slots:
                slots[mat] = len(slots)
                if mat in GLOW:
                    colour, emission = GLOW[mat]
                    material = wacky.mat(colour, emission=emission)
                else:
                    material = wacky.mat(EXTRA_COLOURS.get(mat, mat))
                mesh.materials.append(material)
        for polygon, (_indices, mat) in zip(mesh.polygons, self.faces):
            polygon.material_index = slots[mat]
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# Letters as strokes in a unit cell. Every stroke is one quad, so text stays cheap.
STROKES = {
    "A": [(0, 0, .5, 1), (1, 0, .5, 1), (.2, .35, .8, .35)],
    "B": [(0, 0, 0, 1), (0, 1, .9, 1), (0, .5, 1, .5), (0, 0, 1, 0), (.9, 1, .9, .5), (1, .5, 1, 0)],
    "C": [(0, 0, 0, 1), (0, 1, 1, 1), (0, 0, 1, 0)],
    "D": [(0, 0, 0, 1), (1, .15, 1, .85), (0, 1, 1, .85), (0, 0, 1, .15)],
    "E": [(0, 0, 0, 1), (0, 1, 1, 1), (0, .5, .8, .5), (0, 0, 1, 0)],
    "F": [(0, 0, 0, 1), (0, 1, 1, 1), (0, .5, .8, .5)],
    "I": [(.5, 0, .5, 1)],
    "K": [(0, 0, 0, 1), (0, .4, 1, 1), (.3, .6, 1, 0)],
    "L": [(0, 0, 0, 1), (0, 0, 1, 0)],
    "M": [(0, 0, 0, 1), (1, 0, 1, 1), (0, 1, .5, .4), (1, 1, .5, .4)],
    "N": [(0, 0, 0, 1), (1, 0, 1, 1), (0, 1, 1, 0)],
    "O": [(0, 0, 0, 1), (1, 0, 1, 1), (0, 1, 1, 1), (0, 0, 1, 0)],
    "P": [(0, 0, 0, 1), (0, 1, 1, 1), (1, 1, 1, .45), (0, .45, 1, .45)],
    "R": [(0, 0, 0, 1), (0, 1, 1, 1), (1, 1, 1, .5), (0, .5, 1, .5), (.4, .5, 1, 0)],
    "S": [(0, 1, 1, 1), (0, 1, 0, .5), (0, .5, 1, .5), (1, .5, 1, 0), (0, 0, 1, 0)],
    "T": [(0, 1, 1, 1), (.5, 0, .5, 1)],
    "U": [(0, 0, 0, 1), (1, 0, 1, 1), (0, 0, 1, 0)],
    "Y": [(0, 1, .5, .5), (1, 1, .5, .5), (.5, 0, .5, .5)],
    "0": [(0, 0, 0, 1), (1, 0, 1, 1), (0, 1, 1, 1), (0, 0, 1, 0)],
    "9": [(0, 1, 1, 1), (1, 0, 1, 1), (0, .5, 1, .5), (0, 1, 0, .5), (0, 0, 1, 0)],
}


def text(mesh, string, cx, y, height, width, gap, stroke, mat, z=0.0, seed=1, wonk=5.0):
    """Lettering in the local XY plane facing +Z, [cx] centred, [y] the baseline."""
    rng = random.Random(seed)
    span = len(string) * (width + gap) - gap
    x = cx - span / 2
    for char in string:
        if char != " ":
            tilt = math.radians(rng.uniform(-wonk, wonk))
            hop = rng.uniform(-0.06, 0.06) * height
            mid = Vector((x + width / 2, y + height / 2 + hop))

            def place(px, py):
                offset = Vector((x + px * width, y + py * height + hop)) - mid
                return mid + Vector((offset.x * math.cos(tilt) - offset.y * math.sin(tilt),
                                     offset.x * math.sin(tilt) + offset.y * math.cos(tilt)))

            for x0, y0, x1, y1 in STROKES[char]:
                a, b = place(x0, y0), place(x1, y1)
                d = (b - a).normalized()
                n = Vector((-d.y, d.x)) * stroke / 2
                a, b = a - d * stroke / 2, b + d * stroke / 2
                mesh.poly([(*(a - n), z), (*(b - n), z), (*(b + n), z), (*(a + n), z)], mat)
        x += width + gap


def googly(mesh, x, y, radius, pupil_scale, look=(0.0, 0.0), z=0.0, white="snow", pupil="black"):
    """Mismatched staring eye in the local XY plane, facing +Z."""
    mesh.disc((x, y, z), radius, 6, white, spin=0.3)
    mesh.disc((x + look[0] * radius, y + look[1] * radius, z + 0.012),
              radius * pupil_scale, 4, pupil, spin=0.5)


def on_surface(m, point, direction):
    """Where a ray from [point] along [direction] first meets what is built so far."""
    m.stick_to(direction)
    seat = Vector(point) + m.stick_dir * m._gap(Vector(point))
    m.stick_dir = None
    return seat


def bug_eye(m, point, direction, aim, radius, sides=5, pupil=0.5):
    """Solid eyeball pushed into the surface along [direction], looking along [aim].

    Its base is buried, so it can never stand off as a card or be cut by a facet ridge.
    """
    m.at(facing(on_surface(m, point, direction), aim) @ rot(x=90))
    m.lathe([(-0.6 * radius, radius), (0.55 * radius, pupil * radius), (0.8 * radius, 0.0)], sides,
            lambda i, _j: "white" if i == 0 else "black", phase=0.3)
    m.home()


def tree_a():
    """A crooked pine: a big dark shape under snow, drawn hundreds of times, so no gags."""
    m = Mesh()
    m.tube([(0, 0, 0), (0.06, 0.8, 0.03), (-0.14, 1.8, 0.0), (0.1, 3.3, -0.06)],
           [0.46, 0.36, 0.3, 0.16], 5, "wood_dark")

    def jag(height, spike):
        def nudge(i, j, point):
            if i == 0 and j % 2:
                point = Vector(point)
                point.y += height
                point.x *= spike
                point.z *= spike
            if i == 1 and j % 2:
                point = Vector(point)
                point.y -= 0.32
            return point
        return nudge

    def tier(i, _j):
        return "pine" if i == 0 else "snow"

    # Lopsided skirts: the middle ring of each is the wandering snow line.
    m.lathe([(1.55, 1.9, 0.0, 0.0), (3.0, 1.05, 0.05, 0.0), (4.35, 0.0, -0.2, 0.05)],
            7, tier, cap=True, phase=0.2, nudge=jag(0.34, 0.76), lump=0.03, seed=3)
    m.lathe([(3.05, 1.5, -0.12, 0.05), (4.25, 0.8, -0.05, 0.0), (5.3, 0.0, 0.2, 0.0)],
            7, tier, cap=True, phase=0.7, nudge=jag(0.28, 0.76), lump=0.03, seed=5)

    m.lathe([(4.45, 1.1, 0.1, 0.0), (5.15, 0.68, 0.16, 0.0), (5.7, 0.46, 0.22, 0.0)],
            7, tier, cap=True, phase=1.2, nudge=jag(0.22, 0.76), lump=0.02, seed=7)
    m.lathe([(5.5, 0.6, 0.2, 0.0), (6.95, 0.0, 0.3, 0.0)], 7, "snow", phase=0.4, lump=0.02, seed=9)
    m.home()
    return m.build()


def boot(m, base):
    """One lost boot, sole on local y=0, toe at -Z, shaft up."""
    m.at(base)
    m.box((0.44, 0.1, 1.0), (0, 0.05, -0.16), "black")
    m.box((0.4, 0.28, 0.9), (0, 0.24, -0.14), "iron", taper=0.74, skip="y")
    m.box((0.34, 0.56, 0.4), (0, 0.64, 0.14), "iron", taper=1.08, skip="yY")
    m.box((0.44, 0.13, 0.5), (0, 0.97, 0.14), "snow")
    for y in (0.46, 0.62):
        m.box((0.22, 0.06, 0.01), (0, y, -0.065), "black", skip="xXyYZ")
    m.home()


def tree_b():
    """Dead, twisted, screaming, and in possession of somebody's boot."""
    m = Mesh()
    m.tube([(0, 0, 0), (0.26, 1.05, 0.08), (-0.22, 2.15, -0.1), (0.14, 3.2, 0.1)],
           [0.5, 0.47, 0.42, 0.25], 5, "wood_dark", twist=0.5)
    m.tube([(0.14, 3.1, 0.1), (-0.32, 3.75, 0.1), (-1.0, 4.1, -0.12), (-1.48, 5.1, 0.1)],
           [0.22, 0.17, 0.11, 0.0], 4, "wood_dark")
    m.tube([(0.14, 3.1, 0.1), (0.55, 4.05, 0.2), (0.24, 5.05, -0.05), (0.62, 6.02, 0.12)],
           [0.22, 0.17, 0.11, 0.0], 4, "wood_dark")
    m.tube([(0.5, 3.75, 0.15), (1.0, 3.95, -0.1), (1.42, 4.75, 0.04)],
           [0.12, 0.09, 0.0], 4, "wood_dark")
    m.tube([(-0.2, 2.1, -0.1), (-0.85, 2.4, 0.1), (-1.28, 3.2, -0.05)],
           [0.14, 0.09, 0.0], 4, "wood_dark")
    m.snowfall(["wood_dark"], threshold=0.5)

    # A screaming knot-hole, because it has watched this train pass every night.
    m.stick_to((0, 0, 1), lift=0.03)
    m.at(T(0.2, 0.92, -1.2) @ rot(y=180))
    m.disc((0.0, 0.0, 0.0), 0.28, 6, "black", squash=1.4)
    m.unstick(conform=True)
    bug_eye(m, (0.16, 1.62, -1.2), (0, 0, 1), (0.12, 0.12, -1), 0.3, sides=6)
    bug_eye(m, (-0.26, 1.8, -1.2), (0, 0, 1), (-0.35, -0.2, -1), 0.21, sides=6, pupil=0.6)

    # The boot sits in the top fork, toe up, as though it was flung from a passing train.
    boot(m, T(-0.08, 3.88, 0.1) @ rot(x=16, y=-96) @ scale(0.92, 0.92, 0.92))
    m.home()
    return m.build()


def rock():
    """A pompous boulder: moustache, tiny top hat, and no idea that it is a rock."""
    m = Mesh()
    m.lathe([(-0.05, 1.0), (0.3, 1.04), (0.6, 0.82), (0.82, 0.44), (0.88, 0.0, 0.1, 0.05)],
            7, "steel", phase=0.2, lump=0.13, seed=8)
    m.snowfall(["steel"], threshold=0.55)

    # Eyes lean back with the slope: the train looks down on rocks from its windows.
    bug_eye(m, (-0.28, 0.6, -1.6), (0, 0, 1), (-0.2, 0.3, -1), 0.3, pupil=0.36)
    bug_eye(m, (0.24, 0.58, -1.6), (0, 0, 1), (0.25, 0.3, -1), 0.2, sides=4, pupil=0.5)

    # A solid handlebar moustache: it pokes out of the rock, so no facet can cut through it.
    for side in (-1, 1):
        wing = [on_surface(m, (side * x, y, -1.6), (0, 0, 1)) + Vector((0, 0, -0.03))
                for x, y in ((0.0, 0.34), (0.28, 0.3), (0.5, 0.46))]
        m.tube(wing, [0.1, 0.07, 0.0], 3, "black")

    m.at(T(0.22, 0.86, 0.06) @ rot(z=-14, x=6) @ scale(1.3, 1.3, 1.3))
    m.lathe([(0.0, 0.32), (0.03, 0.17), (0.3, 0.19), (0.3, 0.0)], 5, "black")
    m.home()
    return m.build()


def pole(span=24.0):
    """Leaning telegraph pole. Somebody's long johns went missing a long way from home."""
    m = Mesh()
    m.tube([(0, 0, 0), (0.06, 2.0, 0.0), (0.1, 4.2, 0.03), (0.2, 6.2, 0.0)],
           [0.16, 0.14, 0.12, 0.11], 5, "wood_dark", top_cap=True)

    # The arm droops, so each insulator is its own height to keep the wires dead on spec.
    m.at(T(0, 5.7, 0) @ rot(z=-2.5))
    m.box((1.8, 0.13, 0.15), (0, 0, 0), "wood_dark")
    m.home()
    m.box((0.14, 0.16, 0.14), (-0.8, 5.76, 0), "black", taper=0.7, skip="y")
    m.box((0.14, 0.2, 0.14), (0.8, 5.74, 0), "black", taper=0.7, skip="y")
    m.box((0.42, 0.13, 0.2), (0.44, 5.79, 0), "snow", taper=0.7, skip="y")

    # Wires: end points are exact, so neighbouring poles join up. Only the middle sags.
    sag = 0.32

    def wire_y(z):
        t = -z / span
        return 5.78 - sag * 4.0 * t * (1.0 - t)

    steps = 4
    for x in (-0.8, 0.8):
        m.tube([(x, wire_y(-span * i / steps), -span * i / steps) for i in range(steps + 1)],
               [0.022] * (steps + 1), 3, "black")

    # Long johns, one peg, all the way out here. Faces +X and -X, where the windows look.
    if span >= 20.0:
        top = wire_y(-span * 0.5)
        outline = [(-0.46, 0.0), (0.46, 0.0), (0.56, -1.22), (0.2, -1.26), (0.03, -0.42),
                   (-0.2, -1.22), (-0.58, -1.16)]
        patch = [(-0.2, -0.42, 0.012), (0.16, -0.46, 0.012), (0.2, -0.16, 0.012), (-0.16, -0.14, 0.012)]
        pants = T(0.8, top + 0.02, -span * 0.5) @ rot(y=90) @ rot(z=-5) @ scale(1.35, 1.35, 1.0)
        m.at(pants)
        m.poly(outline, "tomato")
        m.poly(patch, "snow")
        m.at(pants @ rot(y=180))
        m.poly(outline, "tomato")
        m.poly(patch, "snow")
        m.home()

    # A crow, supervising.
    m.at(T(-0.42, 5.78, 0))
    m.lathe([(0.0, 0.0), (0.12, 0.13), (0.3, 0.0, 0.0, -0.03)], 4, "black", phase=0.78)
    m.at(T(-0.42, 5.97, -0.08) @ rot(y=180))
    m.disc((0, 0, 0), 0.05, 4, "snow")
    m.poly([(-0.04, -0.06, 0), (0.04, -0.06, 0), (0, -0.12, 0)][::-1], "tomato")
    m.home()
    m.snowfall(["wood_dark"], threshold=0.7)
    return m.build()


def drift():
    """Snow mound. The engine scales it about 8 x 1 x 10, so the watcher inside is built
    tall and thin here and comes out round. Only X and Z are wide: Y stays near 1."""
    m = Mesh()
    # The lower half is always underground, so it is one cheap cone.
    # Its bottom band is tall and straight: the burrow fits on it without crossing a ridge.
    m.lathe([(-1.0, 0.0), (0.02, 0.98, 0.0, 0.0), (0.72, 0.72, 0.04, -0.03), (0.92, 0.4, 0.2, -0.14),
             (1.0, 0.0, 0.26, -0.2)], 9, "snow", phase=0.3, lump=0.08, seed=4)
    # Burrows both ways, because a drift never turns and could be on either side of the track.
    for side in (-1, 1):
        m.stick_to((-side, 0, 0), lift=0.02)
        m.at(T(side * 1.6, 0.37, 0.0) @ rot(y=side * 90))
        m.disc((0, 0, 0), 0.036, 8, "black", squash=8.3)
        m.poly([(-0.024, -0.04, 0.012), (-0.005, 0.07, 0.012), (-0.026, 0.18, 0.012)], "eyeglow")
        m.poly([(0.026, -0.04, 0.012), (0.026, 0.18, 0.012), (0.007, 0.07, 0.012)], "eyeglow")
        m.unstick(conform=True)
    m.home()
    return m.build()


def snow_foot(m, radius=0.8, height=0.3, center=(0.0, 0.0), seed=2, sides=6):
    m.lathe([(-0.02, radius, *center), (height * 0.55, radius * 0.62, *center), (height, 0.0, *center)],
            sides, "snow", lump=0.08, seed=seed)


def bite_outline(half):
    """Diamond with a bite taken out of the lower right edge, counter-clockwise."""
    a = half
    return [(0.0, -a), (0.52 * a, -0.48 * a), (0.42 * a, -0.34 * a), (0.6 * a, -0.28 * a),
            (0.52 * a, -0.13 * a), (0.76 * a, -0.24 * a), (a, 0.0), (0.0, a), (-a, 0.0)]


def gag_sign_a():
    """Warning diamond: NO REFUNDS. One screw left, and something has had a bite of it."""
    m = Mesh()
    # The post stops below the lettering and stands behind the board, on -Z. The train
    # sees +Z, so nothing crosses the warning mark or the one remaining screw.
    m.box((0.22, 1.62, 0.2), (0.03, 0.8, -0.1), "wood_dark", taper=0.82, skip="y")
    board = T(0.03, 1.55, 0.0) @ rot(z=9) @ T(0.0, 0.45, 0.0)
    m.at(board)
    m.slab(bite_outline(1.5), 0.08, "black")
    for flip in (0, 180):
        m.at(board @ rot(y=flip))
        z = 0.052
        plate = bite_outline(1.3)
        if flip:
            plate = [(-x, y) for x, y in reversed(plate)]
        m.poly([(x, y, z) for x, y in plate], "mustard")
        z = 0.066
        text(m, "NO", 0.0, 0.32, 0.46, 0.3, 0.12, 0.085, "black", z=z, seed=2, wonk=4)
        text(m, "REFUNDS", -0.02, -0.22, 0.42, 0.235, 0.07, 0.078, "black", z=z, seed=3, wonk=4)
        m.poly([(-0.3, -0.84, z), (-0.14, -0.84, z), (-0.13, -0.52, z), (-0.31, -0.52, z)], "tomato")
        m.poly([(-0.3, -1.03, z), (-0.14, -1.03, z), (-0.14, -0.89, z), (-0.3, -0.89, z)], "tomato")
        m.disc((0.0, -0.45, z), 0.09, 6, "steel")
        m.disc((0.3, -0.62, z), 0.08, 5, "black")
        m.disc((0.16, -0.88, z), 0.06, 5, "black")
    m.at(board)
    m.blob(0.5, (0.0, 1.35, 0.0), "snow", squash=(1.1, 0.42, 0.3), lump=0.14, seed=4)
    # The same screw, come out through the far side of the post.
    m.at(T(0.03, 1.5, -0.19) @ rot(y=180))
    m.disc((0.0, 0.0, 0.0), 0.07, 5, "steel")
    m.at(T(0.03, 0, -0.1))
    snow_foot(m, 0.9, 0.34)
    m.home()
    return m.build()


def gag_sign_b():
    """Two planks of bad news, and the last soup itself on top, looking at you."""
    m = Mesh()
    # One post, standing in the gap between the words, so both faces read cleanly.
    m.at(T(0.02, 0, 0.13) @ rot(z=2.5))
    m.box((0.24, 3.0, 0.2), (0, 1.5, 0), "wood_dark", taper=0.8, skip="y")
    top = T(0.0, 2.42, 0.0) @ rot(z=-3)
    low = T(0.03, 1.55, 0.0) @ rot(z=2.5)
    m.at(top)
    m.box((2.96, 0.72, 0.1), (0, 0, 0), "cream")
    m.box((2.7, 0.16, 0.16), (-0.06, 0.42, 0), "snow", taper=0.8, skip="y")
    arrow = [(-1.4, -0.36), (1.0, -0.36), (1.47, 0.0), (1.0, 0.36), (-1.4, 0.36), (-1.2, 0.0)]
    m.at(low)
    m.slab(arrow, 0.1, "mustard")
    for flip in (0, 180):
        m.at(top @ rot(y=flip))
        text(m, "LAST SOUP", 0.0, -0.25, 0.5, 0.21, 0.12, 0.068, "black", z=0.056, seed=5, wonk=3)
        m.at(low @ rot(y=flip))
        # Mirrored so both faces keep clear of the arrow tip.
        text(m, "900 KM", -0.17 if flip == 0 else 0.17, -0.24, 0.48, 0.22, 0.13, 0.07, "black",
             z=0.056, seed=6, wonk=3)
    # The last soup: a wooden bowl, tipped at the train, with something's eye bobbing in it.
    bowl = T(0.1, 2.98, 0.1) @ rot(x=-24, z=-6)
    m.at(bowl)
    m.lathe([(-0.1, 0.22), (0.28, 0.66), (0.24, 0.54), (0.24, 0.0)], 5,
            lambda i, _j: "steel" if i == 2 else "wood_dark", cap=True)
    # A real eyeball rising out of the soup, so it reads from level, not just from above.
    m.at(bowl @ T(0.02, 0.32, -0.12) @ rot(x=-62, z=8))
    m.lathe([(-0.04, 0.33), (0.19, 0.27), (0.27, 0.13), (0.29, 0.0)], 5,
            lambda i, _j: ("white", "tomato", "black")[i], phase=0.3)
    m.home()
    m.snowfall(["cream", "mustard"], threshold=0.6)
    m.turn()
    return m.build()


def gag_snowman():
    """Everything a snowman should not be. Ear-to-ear teeth, and it has found the ladle."""
    m = Mesh()
    m.lathe([(-0.02, 0.88), (0.46, 1.0), (0.98, 0.84), (1.48, 0.46)], 8, "snow", lump=0.03, seed=2)

    # Head. The band between rings 0 and 1 is the mouth: those facets are simply black,
    # and the corners of the grin bend upward so it can never stop smiling.
    def grin(i, j, point):
        point = Vector(point)
        if i in (0, 1) and min(j, 8 - j) == 2:
            point.y += 0.2 if i == 0 else 0.14
        return point

    def head_mat(i, j):
        return "black" if i == 0 and j in (0, 1, 6, 7) else "snow"

    head_centre = Vector((0, 2.05, 0))
    rings = [(1.62, 0.7), (2.06, 0.84), (2.5, 0.64), (2.76, 0.0)]
    corners = m.lathe(rings, 8, head_mat, nudge=grin, cap=True)

    # Teeth: a triangle each, pointing into the mouth from both lips.
    def row(a, b, c, d, count):
        for k in range(count):
            t0, t1 = k / count, (k + 1) / count
            tm = (t0 + t1) / 2
            base0, base1 = a.lerp(b, t0), a.lerp(b, t1)
            tip = a.lerp(b, tm).lerp(c.lerp(d, tm), 0.58)
            normal = (a + tip - 2 * head_centre).normalized()
            shift = normal * 0.016
            m.tri_facing(base0 + shift, base1 + shift, tip + shift, normal, "bone")

    for j in (0, 1, 6, 7):
        k = (j + 1) % 8
        row(corners[1][j], corners[1][k], corners[0][j], corners[0][k], 4)
        row(corners[0][j], corners[0][k], corners[1][j], corners[1][k], 4)

    # Eyes: one enormous, one tiny, both furious.
    tilt = rot(x=-20)
    m.stick_to((0, 0, 1), lift=0.02)
    m.at(T(-0.34, 2.3, -1.6) @ rot(y=203) @ tilt)
    googly(m, 0, 0, 0.27, 0.2, look=(-0.2, -0.2), white="black", pupil="tomato")
    m.unstick()
    m.stick_to((0, 0, 1), lift=0.02)
    m.at(T(0.34, 2.28, -1.6) @ rot(y=157) @ tilt)
    googly(m, 0, 0, 0.15, 0.42, look=(0.2, 0.25), white="black", pupil="tomato")
    m.unstick()
    m.at(T(-0.3, 2.53, -0.47) @ rot(z=16))
    m.box((0.6, 0.1, 0.12), (0, 0, 0), "black", skip="yZ")
    m.home()
    # Bent carrot, drooping toward the teeth.
    m.tube([(0.02, 2.12, -0.74), (0.1, 2.14, -1.04), (0.24, 2.02, -1.3)], [0.14, 0.1, 0.0], 3, "carrot")

    # Scarf and tail.
    m.lathe([(1.38, 0.7), (1.68, 0.74)], 8, "tomato", lump=0.02, seed=3)
    m.box((0.26, 0.74, 0.08), (0.42, 1.2, -0.6), "tomato", taper=1.1, skip="yY")

    # Hat, crooked.
    m.at(T(0.08, 2.6, 0.02) @ rot(z=-11, x=-5))
    m.lathe([(0.0, 0.6), (0.02, 0.33), (0.4, 0.38), (0.4, 0.0)], 6, "black", cap=True, phase=0.4)
    m.home()

    # Arm one: raised claw. Arm two: holding a ladle it should not have.
    m.tube([(-0.76, 1.1, 0), (-1.04, 1.7, -0.12), (-0.96, 2.3, -0.2)], [0.08, 0.06, 0.04], 3, "wood_dark")
    for dx, dz in ((-0.14, 0.0), (0.2, 0.06)):
        m.tube([(-0.96, 2.28, -0.2), (-0.96 + dx, 2.7, -0.2 + dz)], [0.05, 0.0], 3, "wood_dark")
    m.tube([(0.76, 1.1, 0), (1.02, 1.66, -0.24), (0.92, 2.08, -0.34)], [0.08, 0.06, 0.05], 3, "wood_dark")
    m.tube([(0.9, 1.5, -0.46), (1.0, 2.82, -0.2)], [0.05, 0.05], 3, "wood_dark")
    m.at(T(1.0, 2.84, -0.2) @ rot(z=8))
    m.lathe([(-0.12, 0.0), (0.04, 0.25), (0.05, 0.0)], 5, "wood_dark")
    m.home()

    # Stuck to its back, unknown to it, and not advised.
    m.at(T(0.04, 0.74, 0.97) @ rot(x=-2, z=-5))
    m.poly([(-0.46, -0.2, 0), (0.46, -0.2, 0), (0.46, 0.2, 0), (-0.46, 0.2, 0)], "bone")
    text(m, "KICK ME", 0.0, -0.11, 0.22, 0.09, 0.03, 0.04, "black", z=0.01, seed=4, wonk=3)
    m.home()
    # The teeth face the train. KICK ME is now only for whoever gets thrown off and lands behind.
    m.turn()
    return m.build()


def gag_outhouse():
    """Door swung wide, occupied anyway. Whoever it is, they have not finished reading."""
    m = Mesh()
    hx, hz = 0.74, 0.74
    front_y, back_y = 2.2, 2.42

    # Everything leans: shear the whole hut so no wall is true.
    lean = Matrix.Identity(4)
    lean[0][1] = 0.045
    lean[2][1] = 0.02
    m.at(lean)

    def wall_top(z):
        return front_y + (back_y - front_y) * (z + hz) / (2 * hz)

    gap = 0.55
    door_top = 2.04
    # Outer skin, single quads only.
    m.poly([(-hx, 0, hz), (hx, 0, hz), (hx, back_y, hz), (-hx, back_y, hz)], "wood")
    m.poly([(hx, 0, hz), (hx, 0, -hz), (hx, front_y, -hz), (hx, back_y, hz)], "wood")
    m.poly([(-hx, 0, -hz), (-hx, 0, hz), (-hx, back_y, hz), (-hx, front_y, -hz)], "wood")
    m.poly([(hx, 0, -hz), (gap, 0, -hz), (gap, door_top, -hz), (hx, door_top, -hz)], "wood")
    m.poly([(-gap, 0, -hz), (-hx, 0, -hz), (-hx, door_top, -hz), (-gap, door_top, -hz)], "wood")
    m.poly([(hx, door_top, -hz), (-hx, door_top, -hz), (-hx, front_y, -hz), (hx, front_y, -hz)], "wood")

    # Plank gaps, the cheapest possible carpentry.
    for z in (-0.25, 0.28):
        m.poly([(hx + 0.01, 0, z + 0.02), (hx + 0.01, 0, z - 0.02),
                (hx + 0.01, wall_top(z), z - 0.02), (hx + 0.01, wall_top(z), z + 0.02)], "wood_dark")
        m.poly([(-hx - 0.01, 0, z - 0.02), (-hx - 0.01, 0, z + 0.02),
                (-hx - 0.01, wall_top(z), z + 0.02), (-hx - 0.01, wall_top(z), z - 0.02)], "wood_dark")

    # Inside faces are a single black cave, wound to show from within.
    inset = 0.06
    ix, iz = hx - inset, hz - inset
    m.poly([(ix, 0.02, iz), (-ix, 0.02, iz), (-ix, 2.15, iz), (ix, 2.15, iz)], "black")
    m.poly([(-ix, 0.02, iz), (-ix, 0.02, -hz), (-ix, 2.15, -hz), (-ix, 2.15, iz)], "black")
    m.poly([(ix, 0.02, -hz), (ix, 0.02, iz), (ix, 2.15, iz), (ix, 2.15, -hz)], "black")
    m.poly([(-ix, 2.15, iz), (ix, 2.15, iz), (ix, 2.15, -hz), (-ix, 2.15, -hz)], "black")
    m.poly([(-ix, 0.02, iz), (ix, 0.02, iz), (ix, 0.02, -hz), (-ix, 0.02, -hz)], "wood_dark")

    # Seat.
    m.box((1.34, 0.5, 0.42), (0, 0.25, 0.44), "wood", skip="yZxX")

    # The occupant: pasty shins, trousers round the boots, a raised newspaper, two eyes.
    m.box((0.44, 0.12, 0.5), (0, 0.54, -0.02), "cream", skip="yZ")
    for x in (-0.2, 0.2):
        m.box((0.13, 0.44, 0.13), (x, 0.3, -0.24), "cream", skip="yY")
        m.box((0.2, 0.15, 0.38), (x, 0.08, -0.32), "black", taper=0.85, skip="y")
    m.box((0.62, 0.14, 0.26), (0, 0.24, -0.24), "teal", taper=0.9, skip="y")
    paper = lean @ T(0, 1.2, -0.42) @ rot(z=-4, x=-5)
    m.at(paper)
    m.poly([(0.0, -0.46, 0.0), (0.0, 0.46, 0.0), (-0.44, 0.48, 0.09), (-0.44, -0.44, 0.09)], "cream")
    m.poly([(0.44, -0.44, 0.09), (0.44, 0.48, 0.09), (0.0, 0.46, 0.0), (0.0, -0.46, 0.0)], "cream")
    # The headline, one frame per page of the fold. The soup news reaches everyone.
    reader = paper @ T(0, 0, -0.012) @ rot(y=180)
    fold = math.degrees(math.atan2(0.09, 0.44))
    m.at(reader @ rot(y=-fold))
    text(m, "N", -0.22, 0.14, 0.26, 0.2, 0.0, 0.05, "black", seed=8, wonk=2)
    text(m, "SO", -0.22, -0.2, 0.26, 0.14, 0.07, 0.045, "black", seed=9, wonk=2)
    m.at(reader @ rot(y=fold))
    text(m, "O", 0.22, 0.14, 0.26, 0.2, 0.0, 0.05, "black", seed=10, wonk=2)
    text(m, "UP", 0.22, -0.2, 0.26, 0.14, 0.07, 0.045, "black", seed=11, wonk=2)
    m.at(lean @ T(0.02, 1.82, -0.38) @ rot(y=180))
    googly(m, -0.15, 0.0, 0.14, 0.3, look=(-0.3, -0.3), white="eyeglow")
    googly(m, 0.15, 0.03, 0.1, 0.42, look=(0.3, -0.4), white="eyeglow")

    # The door, on its last hinge, sagging, wide open to the blizzard.
    door_w = 2 * gap
    hinge = lean @ T(gap, 0.02, -hz) @ rot(y=-122) @ rot(z=-3)
    m.at(hinge)
    m.slab([(-door_w, 0.0), (0.0, 0.0), (0.0, 1.94), (-door_w, 1.94)], 0.06, "teal", rim="wood_dark")
    moon = [(0.0, -0.17), (0.13, -0.08), (0.17, 0.05), (0.1, 0.17), (0.12, 0.05), (0.05, -0.06), (-0.08, -0.1)]
    m.at(hinge @ T(-gap, 1.58, 0.032))
    m.poly(moon, "black")
    m.at(hinge @ T(-gap, 1.58, -0.032) @ rot(y=180))
    m.poly(moon, "black")
    # On both faces, so it shows beside the occupant too. The wall hides the hinge end.
    m.at(hinge @ T(-gap, 0.0, -0.034) @ rot(y=180))
    text(m, "BUSY", 0.04, 0.84, 0.36, 0.17, 0.06, 0.06, "cream", seed=7)
    m.at(hinge @ T(-gap, 0.0, 0.034))
    text(m, "BUSY", 0.0, 0.84, 0.36, 0.19, 0.06, 0.065, "cream", seed=7)

    # Roof, slumped, wearing most of the winter.
    m.at(lean @ T(0.02, 2.36, 0.0) @ rot(x=-8, z=3))
    m.box((1.96, 0.14, 1.95), (0, 0, 0), "wood_dark")
    m.box((1.84, 0.26, 1.8), (-0.03, 0.2, -0.02), "snow", taper=0.84, skip="y")
    m.home()

    # Loo roll, escaping out of the door and away across the snow.
    path = [Vector((0.0, 0.03, -0.5)), Vector((-0.22, 0.03, -0.95)),
            Vector((0.05, 0.03, -1.3)), Vector((-0.16, 0.03, -1.62))]
    for a, b in zip(path, path[1:]):
        side = (b - a).cross(Y_AXIS).normalized() * 0.1
        m.tri_facing(a - side, a + side, b + side, Y_AXIS, "cream")
        m.tri_facing(a - side, b + side, b - side, Y_AXIS, "cream")
    m.tube([(-0.3, 0.15, -1.62), (-0.03, 0.15, -1.62)], [0.15, 0.15], 5, "cream", top_cap=True)

    snow_foot(m, 0.62, 0.42, center=(-0.86, 0.35), seed=6, sides=5)
    m.turn()
    return m.build()


ASSETS = [
    (tree_a, "tree_a", 220),
    (tree_b, "tree_b", 220),
    (rock, "rock", 120),
    (pole, "pole", 150),
    (drift, "drift", 80),
    (gag_sign_a, "gag_sign_a", 300),
    (gag_sign_b, "gag_sign_b", 300),
    (gag_snowman, "gag_snowman", 300),
    (gag_outhouse, "gag_outhouse", 300),
]


def main():
    over = []
    for build, name, limit in ASSETS:
        wacky.reset_scene()
        obj = build()
        print("==", name, "limit", limit)
        total = wacky.report([obj])
        if total > limit:
            over.append("%s %d/%d" % (name, total, limit))
        wacky.export_glb("assets/models/scenery/%s.glb" % name)
        wacky.preview("assets/previews/scenery/%s.png" % name)

    # The wires make the pole sheet mostly sky, so also shoot the top of it up close.
    wacky.reset_scene()
    pole(span=2.0)
    wacky.preview("assets/previews/scenery/pole_closeup.png")
    print("OVER BUDGET: " + ", ".join(over) if over else "all within budget")


main()
