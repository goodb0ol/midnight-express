"""Shared Blender toolkit for The Midnight Express art.

All positions and sizes here are in GODOT coordinates (X right, Y up, -Z forward),
so build scripts can copy numbers straight from docs/ART_BRIEF.md. The kit converts
to Blender's Z-up space, and the glTF exporter converts back.

Run a build script with:
  blender.exe --background --python blender/build_<group>.py
"""
import math
import os
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Dark, restrained colours: soot, old wood, dull brass. Warmth comes from the lamps, so
# surfaces stay plain and low in saturation. Skin and eye whites are the brightest things
# on purpose, because faces have to read in a dim car.
PALETTE = {
    "mustard": (0.46, 0.33, 0.1),
    "tomato": (0.34, 0.09, 0.07),
    "oxblood": (0.14, 0.035, 0.04),
    "teal": (0.05, 0.15, 0.15),
    "swamp": (0.15, 0.19, 0.08),
    "bubblegum": (0.42, 0.22, 0.25),
    "lilac": (0.24, 0.2, 0.3),
    "navy": (0.03, 0.045, 0.09),
    "cream": (0.56, 0.5, 0.39),
    "bone": (0.5, 0.46, 0.37),
    "rust": (0.2, 0.09, 0.05),
    "wood": (0.2, 0.12, 0.065),
    "wood_dark": (0.075, 0.045, 0.028),
    "iron": (0.045, 0.048, 0.052),
    "steel": (0.2, 0.21, 0.23),
    "brass": (0.42, 0.29, 0.1),
    "coal": (0.018, 0.018, 0.02),
    "snow": (0.8, 0.85, 0.94),
    "ice": (0.45, 0.58, 0.68),
    "pine": (0.022, 0.05, 0.045),
    "skin_a": (0.7, 0.5, 0.38),
    "skin_b": (0.47, 0.3, 0.2),
    "skin_c": (0.26, 0.16, 0.11),
    "skin_sick": (0.42, 0.47, 0.3),
    "black": (0.01, 0.01, 0.012),
    "white": (0.8, 0.78, 0.72),
}

# Colour limit for one character: unlit palette names swapped before lookup. Set by a build
# script right after reset_scene(), so each passenger keeps to a few colours.
REMAP = {}

_materials = {}


def gv(x, y, z):
    """Godot point or size direction to Blender space."""
    return Vector((x, -z, y))


def gs(size):
    """Godot size (x, y, z) to Blender size."""
    return Vector((size[0], size[2], size[1]))


def reset_scene():
    global REMAP
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()
    REMAP = {}


def mat(color, emission=0.0, rough=0.85, alpha=1.0, metal=0.0):
    """Flat-colour material. [color] is a PALETTE name or an RGB tuple."""
    if isinstance(color, str) and emission == 0.0:
        color = REMAP.get(color, color)
    rgb = PALETTE[color] if isinstance(color, str) else color
    key = (tuple(rgb), emission, rough, alpha, metal)
    if key in _materials:
        return _materials[key]
    name = color if isinstance(color, str) else "c_%02x%02x%02x" % tuple(int(c * 255) for c in rgb)
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    node = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    node.inputs["Base Color"].default_value = (*rgb, 1.0)
    node.inputs["Roughness"].default_value = rough
    node.inputs["Metallic"].default_value = metal
    if emission > 0.0:
        node.inputs["Emission Color"].default_value = (*rgb, 1.0)
        node.inputs["Emission Strength"].default_value = emission
    if alpha < 1.0:
        node.inputs["Alpha"].default_value = alpha
        material.surface_render_method = "BLENDED"
    material.diffuse_color = (*rgb, alpha)
    _materials[key] = material
    return material


def _new_object(name, mesh):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _finish(name, bm, center, material, rotation=None):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = _new_object(name, mesh)
    if material is not None:
        mesh.materials.append(material)
    if rotation is not None:
        obj.rotation_euler = rotation
    obj.location = gv(*center)
    return obj


def box(name, size, center=(0, 0, 0), material=None, bevel=0.0, taper=1.0, segments=1):
    """Box. [taper] scales the top face for that chunky hand-made slant."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=gs(size), verts=bm.verts)
    if taper != 1.0:
        for vert in bm.verts:
            if vert.co.z > 0.0:
                vert.co.x *= taper
                vert.co.y *= taper
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect="EDGES", profile=0.5)
    return _finish(name, bm, center, material)


def cyl(name, radius, height, center=(0, 0, 0), material=None, axis="y", verts=8, top_radius=None):
    """Cylinder or cone along a Godot axis ('x', 'y', 'z')."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius,
                          radius2=radius if top_radius is None else top_radius, depth=height)
    if axis == "x":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif axis == "z":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    return _finish(name, bm, center, material)


def ball(name, radius, center=(0, 0, 0), material=None, squash=(1, 1, 1), detail=2):
    """Faceted ball. [squash] is a Godot-axis scale; detail 1-3 sets the facet count."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=radius)
    bmesh.ops.scale(bm, vec=gs(squash), verts=bm.verts)
    return _finish(name, bm, center, material)


def wobble(obj, amount=0.02, seed=1):
    """Nudges every vertex, so nothing looks machine-straight. Keeps welded edges welded."""
    rng = random.Random(seed)
    offsets = {}
    for vert in obj.data.vertices:
        key = tuple(round(c, 4) for c in vert.co)
        if key not in offsets:
            offsets[key] = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * amount
        vert.co += offsets[key]
    obj.data.update()
    return obj


def join(name, objects):
    """Merges [objects] into one mesh, keeping materials. Origin stays at Godot (0,0,0)."""
    bpy.ops.object.select_all(action="DESELECT")
    keep = objects[0]
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = keep
    if len(objects) > 1:
        bpy.ops.object.join()
    keep.name = name
    keep.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    keep.select_set(False)
    return keep


def set_origin(obj, point):
    """Moves the object's origin to Godot [point] without moving its geometry."""
    offset = gv(*point) - obj.location
    obj.data.transform(Matrix.Translation(-offset))
    obj.data.update()
    obj.location = gv(*point)
    return obj


def clear_except(keep):
    """Deletes every object not in [keep]."""
    names = {obj.name for obj in keep}
    for obj in list(bpy.data.objects):
        if obj.name not in names:
            bpy.data.objects.remove(obj, do_unlink=True)


def shade_flat():
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.data.polygons.foreach_set("use_smooth", [False] * len(obj.data.polygons))
            obj.data.update()


def bake_pools(obj, pools, shade=0.2, shade_tint=(0.72, 0.8, 1.0), warm=(1.0, 0.76, 0.5), step=0.75):
    """Paints lamp light into vertex colours, so a dark room holds warm pools under its lamps.

    [pools] are (x, y, z, radius, strength[, rgb]) in Godot space. Vertices far from every
    pool end up at [shade], tinted cold. The mesh is sliced first so big flat walls have
    vertices for the gradient. The glTF importer multiplies these colours onto the material.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    planes = [(gv(0, 0, -9.0 + i * step), gv(0, 0, 1)) for i in range(1, int(18.0 / step))]
    planes += [(gv(0, y, 0), gv(0, 1, 0)) for y in (0.5, 1.0, 1.5, 2.0, 2.45)]
    planes += [(gv(x, 0, 0), gv(1, 0, 0)) for x in (-1.2, -0.6, 0.0, 0.6, 1.2)]
    for co, no in planes:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=co, plane_no=no)
    bm.to_mesh(obj.data)
    bm.free()
    attribute = obj.data.color_attributes.new("Light", "FLOAT_COLOR", "CORNER")
    for loop in obj.data.loops:
        co = obj.matrix_world @ obj.data.vertices[loop.vertex_index].co
        point = Vector((co.x, co.z, -co.y))
        light = [shade * c for c in shade_tint]
        for pool in pools:
            distance = (point - Vector(pool[:3])).length
            fall = max(0.0, 1.0 - distance / pool[3])
            tint = pool[5] if len(pool) > 5 else warm
            for i in range(3):
                light[i] += fall * fall * pool[4] * tint[i] * 1.5
        attribute.data[loop.index].color = (*[min(c, 1.0) for c in light], 1.0)
    obj.data.color_attributes.active_color = attribute
    obj.data.update()
    return obj


def bake_height(obj, floor=0.35, top=1.0, height=1.1):
    """Darkens the lower part of a floor-standing object: lamps are overhead, feet sit in shade."""
    attribute = obj.data.color_attributes.new("Light", "FLOAT_COLOR", "CORNER")
    for loop in obj.data.loops:
        co = obj.matrix_world @ obj.data.vertices[loop.vertex_index].co
        t = min(max(co.z / height, 0.0), 1.0)
        value = floor + (top - floor) * t
        attribute.data[loop.index].color = (value, value * 0.97, value * 0.94, 1.0)
    obj.data.color_attributes.active_color = attribute
    obj.data.update()
    return obj


def report(objects=None):
    """Prints per-object Godot-space size, origin and triangle count."""
    objects = objects or [o for o in bpy.data.objects if o.type == "MESH"]
    total = 0
    for obj in objects:
        corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        low = [min(c[i] for c in corners) for i in range(3)]
        high = [max(c[i] for c in corners) for i in range(3)]
        size = (high[0] - low[0], high[2] - low[2], high[1] - low[1])
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        total += tris
        loc = obj.location
        print("  %-18s size=(%.2f %.2f %.2f) origin=(%.2f %.2f %.2f) tris=%d mats=%d" % (
            obj.name, *size, loc.x, loc.z, -loc.y, tris, len(obj.data.materials)))
    print("  total tris: %d" % total)
    return total


def export_glb(relative_path):
    """Exports all mesh objects to [relative_path] under the project root."""
    path = os.path.join(ROOT, relative_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    shade_flat()
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_vertex_color="ACTIVE",
    )
    print("exported", relative_path, "%d bytes" % os.path.getsize(path))


VIEWS = {
    "front": (0.0, -1.0, 0.18),     # Godot -Z side: the side a character faces.
    "side": (1.0, 0.0, 0.18),
    "three_quarter": (0.75, -0.75, 0.5),
    "back": (-0.7, 0.75, 0.35),
}


def preview(relative_path, tile=420):
    """Renders front, side, three-quarter and back views into one 2x2 sheet PNG."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = tile
    scene.render.resolution_y = tile
    scene.render.image_settings.file_format = "PNG"
    meshes = [o for o in scene.objects if o.type == "MESH"]
    corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    low = Vector((min(c[i] for c in corners) for i in range(3)))
    high = Vector((max(c[i] for c in corners) for i in range(3)))
    center = (low + high) * 0.5
    radius = max((high - low).length * 0.5, 0.05)

    camera_data = bpy.data.cameras.new("preview")
    camera_data.lens = 60.0
    camera_data.clip_end = radius * 40.0
    camera_data.clip_start = radius * 0.01
    camera = bpy.data.objects.new("preview", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera

    out_path = os.path.join(ROOT, relative_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    sheet = np.zeros((tile * 2, tile * 2, 4), dtype=np.float32)
    temp = out_path + ".tile.png"
    for i, direction in enumerate(VIEWS.values()):
        heading = Vector(direction).normalized()
        camera.location = center + heading * radius * 3.4
        camera.rotation_euler = (-heading).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = temp
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(temp)
        pixels = np.empty(tile * tile * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        row, col = 1 - i // 2, i % 2
        sheet[row * tile:(row + 1) * tile, col * tile:(col + 1) * tile] = pixels.reshape(tile, tile, 4)
        bpy.data.images.remove(image)
    os.remove(temp)
    result = bpy.data.images.new("sheet", tile * 2, tile * 2, alpha=True)
    result.pixels.foreach_set(sheet.ravel())
    result.filepath_raw = out_path
    result.file_format = "PNG"
    result.save()
    bpy.data.objects.remove(camera, do_unlink=True)
    print("preview", relative_path)
