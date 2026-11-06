"""Independent check of exported models. Reads the GLB, not the build script's scene.

  blender.exe --background --python blender/check_glb.py -- assets/models/props/crate.glb ...

Prints each object's size and origin in Godot coordinates, triangle counts, and flags
empty meshes or objects with leftover rotation or scale.
"""
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
paths = sys.argv[sys.argv.index("--") + 1:]

for relative in paths:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, relative))
    print("==", relative)
    total = 0
    for obj in sorted(bpy.data.objects, key=lambda o: o.name):
        if obj.type != "MESH":
            continue
        corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        low = [min(c[i] for c in corners) for i in range(3)]
        high = [max(c[i] for c in corners) for i in range(3)]
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        total += tris
        loc = obj.matrix_world.translation
        flags = []
        if tris == 0:
            flags.append("EMPTY")
        if (obj.scale - Vector((1, 1, 1))).length > 0.001:
            flags.append("SCALED")
        if max(abs(a) for a in obj.rotation_euler) > 0.001 and obj.rotation_mode == "XYZ":
            flags.append("ROTATED")
        print("  %-18s size=(%.2f %.2f %.2f) origin=(%.2f %.2f %.2f) tris=%d mats=%d %s" % (
            obj.name, high[0] - low[0], high[2] - low[2], high[1] - low[1],
            loc.x, loc.z, -loc.y, tris, len(obj.data.materials), " ".join(flags)))
    print("  total tris:", total)
