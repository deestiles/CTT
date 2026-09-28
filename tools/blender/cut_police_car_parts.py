import bpy, bmesh, math, os
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
fbx = r"C:\Projects\Catch the Thief\Purchased Assets\Synty POLYGON City\FBX\Veh\SM_Veh_Car_Police_01.fbx"
bpy.ops.import_scene.fbx(filepath=fbx)

def lerp_y(z, z0,y0, z1,y1):
    t=max(0.0,min(1.0,(z-z0)/(z1-z0))); return y0+(y1-y0)*t
def front_y(z): return lerp_y(z, 0.50,-0.98, 1.45,-1.18)   # A-pillar
def rear_y(z):  return lerp_y(z, 0.50, 1.18, 1.45, 0.98)   # C-pillar

def separate(objname, pred, newname):
    obj=bpy.data.objects[objname]
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active=obj
    bpy.ops.object.mode_set(mode='EDIT'); bm=bmesh.from_edit_mesh(obj.data); mw=obj.matrix_world
    for f in bm.faces: f.select=False
    n=0
    for f in bm.faces:
        c=mw @ f.calc_center_median()
        nz=(mw.to_3x3() @ f.normal).normalized()
        if pred(c,nz): f.select=True; n+=1
    bmesh.update_edit_mesh(obj.data)
    if n==0:
        bpy.ops.object.mode_set(mode='OBJECT'); print('SEP',newname,'0 skip'); return None
    before=set(bpy.data.objects.keys()); bpy.ops.mesh.separate(type='SELECTED'); bpy.ops.object.mode_set(mode='OBJECT')
    d=set(bpy.data.objects.keys())-before
    if not d: print("SEP",newname,"0"); return None
    o=bpy.data.objects[d.pop()]; o.name=newname; print(f"SEP {newname} n={n} v={len(o.data.vertices)}"); return o

B="SM_Veh_Car_Police_01"; G="SM_Veh_Car_Police_Glass"
# Doors (body)
FL=separate(B, lambda c,nz: c.x>0.72 and front_y(c.z)<c.y<0.24 and 0.44<c.z<1.50, "Door_FL")
FR=separate(B, lambda c,nz: c.x<-0.72 and front_y(c.z)<c.y<0.24 and 0.44<c.z<1.50, "Door_FR")
RL=separate(B, lambda c,nz: c.x>0.72 and 0.24<c.y<rear_y(c.z) and 0.44<c.z<1.44, "Door_RL")
RR=separate(B, lambda c,nz: c.x<-0.72 and 0.24<c.y<rear_y(c.z) and 0.44<c.z<1.44, "Door_RR")
# Trunk & hood: upward-facing lid faces
TR=separate(B, lambda c,nz: abs(c.x)<0.98 and c.y>1.66 and c.z>0.85 and nz.z>0.5, "Trunk")
HD=separate(B, lambda c,nz: abs(c.x)<0.98 and c.y<-1.66 and c.z>0.72 and nz.z>0.5, "Hood")
# Window panes (glass)
gFL=separate(G, lambda c,nz: c.x>0.40 and -1.05<c.y<0.20, "gFL")
gFR=separate(G, lambda c,nz: c.x<-0.40 and -1.05<c.y<0.20, "gFR")
gRL=separate(G, lambda c,nz: c.x>0.40 and 0.20<c.y<1.05, "gRL")
gRR=separate(G, lambda c,nz: c.x<-0.40 and 0.20<c.y<1.05, "gRR")

def join(door, glass):
    if door is None or glass is None: return
    bpy.ops.object.select_all(action='DESELECT'); glass.select_set(True); door.select_set(True)
    bpy.context.view_layer.objects.active=door; bpy.ops.object.join()
join(FL,gFL); join(FR,gFR); join(RL,gRL); join(RR,gRR)

def bounds(o):
    bb=[o.matrix_world @ Vector(c) for c in o.bound_box]
    return (Vector((min(v.x for v in bb),min(v.y for v in bb),min(v.z for v in bb))),
            Vector((max(v.x for v in bb),max(v.y for v in bb),max(v.z for v in bb))))
def set_origin(o, p):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
    bpy.context.scene.cursor.location=p; bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
# Door hinges: front edge (min Y), at the skin X (outer), mid Z
for o,left in ((FL,True),(FR,False),(RL,True),(RR,False)):
    if o is None: continue
    mn,mx=bounds(o); xs=mx.x-0.02 if left else mn.x+0.02
    set_origin(o, Vector((xs, mn.y, (mn.z+mx.z)/2)))
# Trunk hinge: front edge (min Y), mid X, top Z
if TR: mn,mx=bounds(TR); set_origin(TR, Vector(((mn.x+mx.x)/2, mn.y, mx.z)))
# Hood hinge: rear edge (max Y), mid X, top Z
if HD: mn,mx=bounds(HD); set_origin(HD, Vector(((mn.x+mx.x)/2, mx.y, mx.z)))

# Export with real materials preserved, all parts closed.
glb=r"C:\Projects\Catch the Thief\catch-the-thief-mapbuilder\Assets\Vehicles\SM_Veh_Car_Police_Rigged.glb"
import os
os.makedirs(os.path.dirname(glb),exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_yup=True)
print("EXPORTED", glb)
for o in bpy.data.objects:
    if o.type=='MESH': print("  PART", o.name)
