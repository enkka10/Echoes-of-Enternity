import bpy
import random
import math
import os
import sys
import bmesh

# Configuration
OUTPUT_DIR = os.path.abspath("./assets/rocks")
RENDER_DIR = os.path.join(OUTPUT_DIR, "renders")
NUM_VARIATIONS = 50

def clean_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for block in bpy.data.meshes: bpy.data.meshes.remove(block)
    for block in bpy.data.materials: bpy.data.materials.remove(block)
    for block in bpy.data.textures: bpy.data.textures.remove(block)
    for block in bpy.data.images: bpy.data.images.remove(block)
    for block in bpy.data.node_groups: bpy.data.node_groups.remove(block)

def create_rock_material():
    mat = bpy.data.materials.new(name="Rock_Mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.2, 0.2, 0.2, 1) # Grey
    bsdf.inputs["Roughness"].default_value = 0.8
    return mat

def create_geometry_nodes(obj, material):
    modifier = obj.modifiers.new(name="RockGenerator", type='NODES')
    node_group = bpy.data.node_groups.new("RockGen", "GeometryNodeTree")
    modifier.node_group = node_group
    
    nodes = node_group.nodes
    links = node_group.links
    
    def add_node(type, location):
        node = nodes.new(type)
        node.location = location
        return node

    # Inputs/Outputs
    input_node = add_node('NodeGroupInput', (-600, 0))
    node_group.interface.new_socket("Seed", in_out='INPUT', socket_type='NodeSocketInt')
    
    output_node = add_node('NodeGroupOutput', (1200, 0))
    node_group.interface.new_socket("Geometry", in_out='OUTPUT', socket_type='NodeSocketGeometry')

    # Base Mesh
    ico = add_node('GeometryNodeMeshIcoSphere', (-400, 0))
    ico.inputs["Subdivisions"].default_value = 3
    ico.inputs["Radius"].default_value = 1.0

    # Voronoi Noise for Displacement
    voronoi = add_node('ShaderNodeTexVoronoi', (-200, 200))
    voronoi.voronoi_dimensions = '4D'
    links.new(input_node.outputs["Seed"], voronoi.inputs["W"])
    
    # Math to center noise (0.5)
    subtract = add_node('ShaderNodeVectorMath', (0, 200))
    subtract.operation = 'SUBTRACT'
    links.new(voronoi.outputs["Position"], subtract.inputs[0])
    subtract.inputs[1].default_value = (0.5, 0.5, 0.5)
    
    # Scale Displacement
    scale = add_node('ShaderNodeVectorMath', (200, 200))
    scale.operation = 'SCALE'
    links.new(subtract.outputs["Vector"], scale.inputs[0])
    scale.inputs[3].default_value = 1.5 # Intensity
    
    # Set Position
    set_pos = add_node('GeometryNodeSetPosition', (400, 0))
    links.new(ico.outputs["Mesh"], set_pos.inputs["Geometry"])
    links.new(scale.outputs["Vector"], set_pos.inputs["Offset"])
    
    # Dual Mesh (for cracked look) - Optional, let's stick to simple low poly for now
    # dual_mesh = add_node('GeometryNodeDualMesh', (600, 0))
    # links.new(set_pos.outputs["Geometry"], dual_mesh.inputs["Mesh"])
    
    # Set Material
    set_mat = add_node('GeometryNodeSetMaterial', (800, 0))
    links.new(set_pos.outputs["Geometry"], set_mat.inputs["Geometry"])
    set_mat.inputs["Material"].default_value = material
    
    links.new(set_mat.outputs["Geometry"], output_node.inputs["Geometry"])

def main():
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
    if not os.path.exists(RENDER_DIR):
        os.makedirs(RENDER_DIR)
        
    clean_scene()
    rock_mat = create_rock_material()
    
    # Camera/Light
    cam_data = bpy.data.cameras.new("Camera")
    cam_obj = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (5, -5, 4)
    cam_obj.rotation_euler = (math.radians(60), 0, math.radians(45))
    bpy.context.scene.camera = cam_obj
    
    light_data = bpy.data.lights.new("Sun", type='SUN')
    light_obj = bpy.data.objects.new("Sun", light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.rotation_euler = (math.radians(45), math.radians(45), 0)
    
    # Base Object
    bpy.ops.mesh.primitive_cube_add()
    rock_obj = bpy.context.active_object
    rock_obj.name = "RockBase"
    create_geometry_nodes(rock_obj, rock_mat)
    
    for i in range(NUM_VARIATIONS):
        seed = random.randint(0, 10000)
        
        # Duplicate
        bpy.ops.object.select_all(action='DESELECT')
        rock_obj.select_set(True)
        bpy.ops.object.duplicate()
        new_obj = bpy.context.active_object
        new_obj.name = f"rock_var_{seed}"
        
        # Set Seed
        ng = new_obj.modifiers["RockGenerator"].node_group
        seed_socket = None
        for item in ng.interface.items_tree:
            if item.name == "Seed":
                seed_socket = item
                break
        if seed_socket:
            new_obj.modifiers["RockGenerator"][seed_socket.identifier] = seed
            
        # Apply
        bpy.context.view_layer.update()
        bpy.ops.object.modifier_apply(modifier="RockGenerator")
        
        # Custom Properties
        new_obj["ground_offset"] = 0.0
        new_obj["align_to_slope"] = True
        new_obj["lod_distances"] = [20, 50, 150]
        
        # Export
        filepath = os.path.join(OUTPUT_DIR, f"{new_obj.name}.glb")
        bpy.ops.export_scene.gltf(
            filepath=filepath,
            export_format='GLB',
            use_selection=True,
            export_extras=True,
            export_yup=True
        )
        print(f"Exported: {filepath}")
        
        # Render first 3
        if i < 3:
            bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, f"{new_obj.name}.png")
            bpy.ops.render.render(write_still=True)
            
        bpy.ops.object.delete()
        
        rock_obj.select_set(True)
        bpy.context.view_layer.objects.active = rock_obj

    print("Rock Generation Complete.")

if __name__ == "__main__":
    main()
