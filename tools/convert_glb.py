# 转换 meshy GLB（KHR_mesh_quantization，Godot 不支持）→ Blender 重导出普通 GLB
# 用法: D:/isme/blender.exe -b -P convert_glb.py
import bpy, os

SRC_DST = [
    (r"C:\Users\shy\桌面\Godot\assets\models\entities\shibing_a.glb",
     r"C:\Users\shy\桌面\Godot\assets\models\entities\shibing_a_c.glb"),
    (r"C:\Users\shy\桌面\Godot\assets\models\entities\shibing_b.glb",
     r"C:\Users\shy\桌面\Godot\assets\models\entities\shibing_b_c.glb"),
    (r"C:\Users\shy\桌面\Godot\assets\models\entities\shibing_c.glb",
     r"C:\Users\shy\桌面\Godot\assets\models\entities\shibing_c_c.glb"),
    (r"C:\Users\shy\桌面\Godot\assets\models\entities\daobingying.glb",
     r"C:\Users\shy\桌面\Godot\assets\models\entities\daobingying_c.glb"),
]

for src, dst in SRC_DST:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    # 清场景里多余对象（灯光/相机由 glTF 导入器不产生，但保险起见只留网格）
    for o in list(bpy.data.objects):
        if o.type not in {'MESH', 'EMPTY', 'ARMATURE'}:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_yup=True)
    print("[CONVERT] %s -> %s (%.1f MB)" % (os.path.basename(src), os.path.basename(dst),
          os.path.getsize(dst) / 1048576.0))
