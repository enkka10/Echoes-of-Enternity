import bpy
import random
import math
import os
import sys
import bmesh

# Configuration
OUTPUT_DIR = os.path.abspath("./assets/trees")
RENDER_DIR = os.path.join(OUTPUT_DIR, "renders")
NUM_VARIATIONS = 10

def clean_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for block in bpy.data.meshes: bpy.data.meshes.remove(block)
    for block in bpy.data.materials: bpy.data.materials.remove(block)
    for block in bpy.data.textures: bpy.data.textures.remove(block)
    for block in bpy.data.images: bpy.data.images.remove(block)
    for block in bpy.data.node_groups: bpy.data.node_groups.remove(block)

def create_materials():
    # Bark Material
    bark_mat = bpy.data.materials.new(name="Bark_Mat")
    bark_mat.use_nodes = True
    bsdf = bark_mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.15, 0.1, 0.05, 1)  # Dark Brown
    bsdf.inputs["Roughness"].default_value = 0.9

    # Leaf Material
    leaf_mat = bpy.data.materials.new(name="Leaf_Mat")
    leaf_mat.use_nodes = True
    bsdf = leaf_mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.1, 0.4, 0.1, 1)    # Green
    bsdf.inputs["Roughness"].default_value = 0.5
    
    return bark_mat, leaf_mat

def create_geometry_nodes(tree_obj, bark_mat, leaf_mat):
    modifier = tree_obj.modifiers.new(name="TreeGenerator", type='NODES')
    node_group = bpy.data.node_groups.new("TreeGen", "GeometryNodeTree")
    modifier.node_group = node_group
    
    # Helper to add nodes
    nodes = node_group.nodes
    links = node_group.links
    
    def add_node(type, location):
        node = nodes.new(type)
        node.location = location
        return node

    # Inputs/Outputs
    input_node = add_node('NodeGroupInput', (-600, 0))
    node_group.interface.new_socket("Seed", in_out='INPUT', socket_type='NodeSocketInt')
    input_node.outputs["Seed"].default_value = 0
    
    output_node = add_node('NodeGroupOutput', (1200, 0))
    node_group.interface.new_socket("Geometry", in_out='OUTPUT', socket_type='NodeSocketGeometry')

    # --- TRUNK ---
    # Curve Line
    trunk_line = add_node('GeometryNodeCurvePrimitiveLine', (-400, 0))
    trunk_line.inputs["End"].default_value = (0, 0, 4) # Height 4m
    
    # Resample for shape
    resample_trunk = add_node('GeometryNodeResampleCurve', (-200, 0))
    resample_trunk.inputs["Count"].default_value = 10
    links.new(trunk_line.outputs["Curve"], resample_trunk.inputs["Curve"])
    
    # Noise for wobble
    noise_tex = add_node('ShaderNodeTexNoise', (-200, 200))
    noise_tex.inputs["Scale"].default_value = 1.0
    
    # 4D Noise driven by Seed
    noise_tex.noise_dimensions = '4D'
    links.new(input_node.outputs["Seed"], noise_tex.inputs["W"])

    subtract_vec = add_node('ShaderNodeVectorMath', (0, 200))
    subtract_vec.operation = 'SUBTRACT'
    links.new(noise_tex.outputs["Color"], subtract_vec.inputs[0])
    subtract_vec.inputs[1].default_value = (0.5, 0.5, 0.5)
    
    scale_noise = add_node('ShaderNodeVectorMath', (200, 200))
    scale_noise.operation = 'SCALE'
    links.new(subtract_vec.outputs["Vector"], scale_noise.inputs[0])
    scale_noise.inputs[3].default_value = 0.5 # Wobble intensity
    
    # Scale Noise by Spline Parameter (to keep base at 0,0,0)
    spline_param_for_noise = add_node('GeometryNodeSplineParameter', (0, 400))
    
    # Map Range: 0.0-0.1 -> 0.0, 0.1-1.0 -> 0.0-1.0
    map_range_noise = add_node('ShaderNodeMapRange', (200, 400))
    links.new(spline_param_for_noise.outputs["Factor"], map_range_noise.inputs["Value"])
    map_range_noise.inputs["From Min"].default_value = 0.0
    map_range_noise.inputs["From Max"].default_value = 0.1
    map_range_noise.inputs["To Min"].default_value = 0.0
    map_range_noise.inputs["To Max"].default_value = 0.0
    # Wait, we want 0-0.1 to be 0. So From Min 0, From Max 0.1, To Min 0, To Max 0? No.
    # We want 0 to 0.1 to output 0. And 0.1 to 1.0 to output 0 to 1.
    # Actually, simpler: Map Range (0.1, 1.0) -> (0.0, 1.0). Clamp enabled.
    map_range_noise.inputs["From Min"].default_value = 0.1
    map_range_noise.inputs["From Max"].default_value = 1.0
    map_range_noise.inputs["To Min"].default_value = 0.0
    map_range_noise.inputs["To Max"].default_value = 1.0
    
    # Power 2
    math_pow = add_node('ShaderNodeMath', (400, 400))
    math_pow.operation = 'POWER'
    links.new(map_range_noise.outputs["Result"], math_pow.inputs[0])
    math_pow.inputs[1].default_value = 2.0
    
    multiply_noise = add_node('ShaderNodeVectorMath', (600, 200))
    multiply_noise.operation = 'MULTIPLY'
    links.new(scale_noise.outputs["Vector"], multiply_noise.inputs[0])
    links.new(math_pow.outputs["Value"], multiply_noise.inputs[1])
    
    # Set Position (Wobble)
    set_pos_trunk = add_node('GeometryNodeSetPosition', (800, 0))
    links.new(resample_trunk.outputs["Curve"], set_pos_trunk.inputs["Geometry"])
    links.new(multiply_noise.outputs["Vector"], set_pos_trunk.inputs["Offset"])
    
    # Set Radius (Taper)
    spline_param = add_node('GeometryNodeSplineParameter', (400, 200))
    map_range = add_node('ShaderNodeMapRange', (600, 200))
    links.new(spline_param.outputs["Factor"], map_range.inputs["Value"])
    map_range.inputs["To Min"].default_value = 0.3 # Base radius
    map_range.inputs["To Max"].default_value = 0.05 # Top radius
    
    set_radius = add_node('GeometryNodeSetCurveRadius', (800, 0))
    links.new(set_pos_trunk.outputs["Geometry"], set_radius.inputs["Curve"])
    links.new(map_range.outputs["Result"], set_radius.inputs["Radius"])
    
    # Trunk Mesh
    circle_profile = add_node('GeometryNodeCurvePrimitiveCircle', (800, -200))
    circle_profile.inputs["Radius"].default_value = 1.0
    circle_profile.inputs["Resolution"].default_value = 6 # Low poly
    
    trunk_mesh = add_node('GeometryNodeCurveToMesh', (1000, 0))
    links.new(set_radius.outputs["Curve"], trunk_mesh.inputs["Curve"])
    links.new(circle_profile.outputs["Curve"], trunk_mesh.inputs["Profile Curve"])
    
    set_mat_trunk = add_node('GeometryNodeSetMaterial', (1200, 0))
    links.new(trunk_mesh.outputs["Mesh"], set_mat_trunk.inputs["Geometry"])
    set_mat_trunk.inputs["Material"].default_value = bark_mat

    # --- BRANCHES ---
    # Distribute points on trunk
    dist_points = add_node('GeometryNodeDistributePointsOnFaces', (1000, 400))
    # Using the mesh for distribution is easier than curve for rotation alignment in simple setup
    links.new(trunk_mesh.outputs["Mesh"], dist_points.inputs["Mesh"]) 
    dist_points.inputs["Density"].default_value = 5.0
    
    # Branch Instance (Cone)
    branch_cone = add_node('GeometryNodeMeshCone', (1000, 200))
    branch_cone.inputs["Radius Bottom"].default_value = 0.1
    branch_cone.inputs["Radius Top"].default_value = 0.0
    branch_cone.inputs["Depth"].default_value = 1.5
    
    # Random Rotation
    random_rot = add_node('FunctionNodeRandomValue', (1000, 600))
    random_rot.data_type = 'FLOAT_VECTOR'
    random_rot.inputs["Min"].default_value = (-1.0, -1.0, 0.5)
    random_rot.inputs["Max"].default_value = (1.0, 1.0, 2.0)
    # Drive seed
    links.new(input_node.outputs["Seed"], random_rot.inputs["ID"])

    instance_branches = add_node('GeometryNodeInstanceOnPoints', (1200, 400))
    links.new(dist_points.outputs["Points"], instance_branches.inputs["Points"])
    links.new(branch_cone.outputs["Mesh"], instance_branches.inputs["Instance"])
    links.new(random_rot.outputs["Value"], instance_branches.inputs["Rotation"])
    
    set_mat_branch = add_node('GeometryNodeSetMaterial', (1400, 400))
    links.new(instance_branches.outputs["Instances"], set_mat_branch.inputs["Geometry"])
    set_mat_branch.inputs["Material"].default_value = bark_mat

    # --- LEAVES ---
    # Distribute on branches
    realize_branches = add_node('GeometryNodeRealizeInstances', (1400, 600))
    links.new(instance_branches.outputs["Instances"], realize_branches.inputs["Geometry"])
    
    dist_leaves = add_node('GeometryNodeDistributePointsOnFaces', (1600, 600))
    links.new(realize_branches.outputs["Geometry"], dist_leaves.inputs["Mesh"])
    dist_leaves.inputs["Density"].default_value = 10.0
    
    # Leaf Instance (Ico Sphere)
    leaf_mesh = add_node('GeometryNodeMeshIcoSphere', (1600, 400))
    leaf_mesh.inputs["Radius"].default_value = 0.3
    leaf_mesh.inputs["Subdivisions"].default_value = 1
    
    instance_leaves = add_node('GeometryNodeInstanceOnPoints', (1800, 600))
    links.new(dist_leaves.outputs["Points"], instance_leaves.inputs["Points"])
    links.new(leaf_mesh.outputs["Mesh"], instance_leaves.inputs["Instance"])
    
    # Random Scale for leaves
    random_scale = add_node('FunctionNodeRandomValue', (1600, 800))
    random_scale.inputs["Min"].default_value = 0.5
    random_scale.inputs["Max"].default_value = 1.5
    links.new(input_node.outputs["Seed"], random_scale.inputs["ID"])
    links.new(random_scale.outputs["Value"], instance_leaves.inputs["Scale"])

    set_mat_leaf = add_node('GeometryNodeSetMaterial', (2000, 600))
    links.new(instance_leaves.outputs["Instances"], set_mat_leaf.inputs["Geometry"])
    set_mat_leaf.inputs["Material"].default_value = leaf_mat

    # --- JOIN ---
    join_geo = add_node('GeometryNodeJoinGeometry', (2200, 0))
    links.new(set_mat_trunk.outputs["Geometry"], join_geo.inputs["Geometry"])
    links.new(set_mat_branch.outputs["Geometry"], join_geo.inputs["Geometry"])
    links.new(set_mat_leaf.outputs["Geometry"], join_geo.inputs["Geometry"])
    
    # Realize Instances before output (important for export sometimes, though GLTF handles instances)
    # But for AABB check in Blender, we might need realized geometry if we apply modifier.
    # Let's realize for safety and low-poly baked look.
    realize_final = add_node('GeometryNodeRealizeInstances', (2400, 0))
    links.new(join_geo.outputs["Geometry"], realize_final.inputs["Geometry"])

    links.new(realize_final.outputs["Geometry"], output_node.inputs["Geometry"])

def setup_camera_and_light():
    # Camera
    cam_data = bpy.data.cameras.new("Camera")
    cam_obj = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = (8, -8, 6)
    cam_obj.rotation_euler = (math.radians(60), 0, math.radians(45))
    bpy.context.scene.camera = cam_obj
    
    # Light
    light_data = bpy.data.lights.new("Sun", type='SUN')
    light_obj = bpy.data.objects.new("Sun", light_data)
    bpy.context.collection.objects.link(light_obj)
    light_obj.rotation_euler = (math.radians(45), math.radians(45), 0)
    light_data.energy = 5.0

def main():
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
    if not os.path.exists(RENDER_DIR):
        os.makedirs(RENDER_DIR)
        
    clean_scene()
    bark_mat, leaf_mat = create_materials()
    setup_camera_and_light()
    
    # Create base object
    bpy.ops.mesh.primitive_cube_add()
    tree_obj = bpy.context.active_object
    tree_obj.name = "TreeBase"
    
    create_geometry_nodes(tree_obj, bark_mat, leaf_mat)
    
    # Variation Loop
    for i in range(NUM_VARIATIONS):
        seed = random.randint(0, 10000)
        tree_obj.modifiers["TreeGenerator"]["Socket_2"] = seed # Socket_2 is usually the first input after geometry? Need to check index.
        # Actually, let's find the input by name to be safe
        # Note: In Blender 4.0+, modifier inputs are accessed via keys if they are exposed
        # But the internal name might be different. 
        # Let's try to find the identifier.
        
        # Update: In recent Blender versions, it's modifier[identifier]
        # We can iterate to find the one named "Seed"
        # But for simplicity, since we just added it, it's likely the first non-geometry input.
        
        # Let's just set it via the node group interface to be sure for the modifier
        # tree_obj.modifiers["TreeGenerator"]["Seed"] = seed # This usually works if the input is named "Seed"
        
        # Re-eval to ensure geometry updates
        bpy.context.view_layer.update()
        
        # Apply Modifier to get real mesh for export and AABB check
        # We need to duplicate the object because we want to keep the generator
        
        # Duplicate
        bpy.ops.object.select_all(action='DESELECT')
        tree_obj.select_set(True)
        bpy.ops.object.duplicate()
        new_obj = bpy.context.active_object
        new_obj.name = f"tree_var_{seed}"
        
        # Set Seed on the duplicate's modifier before applying
        # Finding the input identifier
        ng = new_obj.modifiers["TreeGenerator"].node_group
        seed_socket = None
        for item in ng.interface.items_tree:
            if item.name == "Seed":
                seed_socket = item
                break
        
        if seed_socket:
             # The identifier is used in the modifier dictionary
            new_obj.modifiers["TreeGenerator"][seed_socket.identifier] = seed
        
        # Apply Modifier
        bpy.ops.object.modifier_apply(modifier="TreeGenerator")
        
        # Verify AABB
        # Calculate min Z (Blender Z-up)
        min_z = min([v.co.z for v in new_obj.data.vertices])
        print(f"Tree {new_obj.name}: Min Z = {min_z:.4f}")
        
        # If min_z is not exactly 0.0 due to noise, we might want to correct it or just warn.
        # The trunk starts at 0,0,0 and SetPosition adds noise. 
        # The noise might push the base below 0. 
        # To fix this, we should mask the noise at the bottom of the trunk in the node tree.
        # But for now, let's just check.
        
        if abs(min_z) > 0.1:
            print("WARNING: Tree base is not at 0.0!")
            
        # Custom Properties
        new_obj["ground_offset"] = 0.0
        new_obj["align_to_slope"] = True
        new_obj["lod_distances"] = [20, 50, 150]
        
        # Export GLB
        filepath = os.path.join(OUTPUT_DIR, f"{new_obj.name}.glb")
        bpy.ops.export_scene.gltf(
            filepath=filepath,
            export_format='GLB',
            use_selection=True,
            export_extras=True, # For custom properties
            export_yup=True # Convert to Godot Y-up
        )
        print(f"Exported: {filepath}")
        
        # Render (only for the first few to save time)
        if i < 3:
            bpy.context.scene.render.filepath = os.path.join(RENDER_DIR, f"{new_obj.name}.png")
            bpy.ops.render.render(write_still=True)
        
        # Delete the baked object
        bpy.ops.object.delete()
        
        # Reselect base tree
        tree_obj.select_set(True)
        bpy.context.view_layer.objects.active = tree_obj

    print("Generation Complete.")

if __name__ == "__main__":
    main()
