class_name Person
extends Node3D
## A person in the tower: the pilot or one of Kestrel Lift's staff, a
## Universal Base Character dressed by [code]person.gdshader[/code] and
## animated with the Universal Animation Libraries. Clothes are drawn on the
## rest pose, so one shader dresses everyone.

const MALE := "res://assets/people/Superhero_Male_FullBody.gltf"
const FEMALE := "res://assets/people/Superhero_Female_FullBody.gltf"
const UAL1 := "res://assets/people/UAL1_Standard.glb"
const UAL2 := "res://assets/people/UAL2_Standard.glb"
const HAIR := "res://assets/people/hair/%s.gltf"
const SHADER := preload("res://game/people/person.gdshader")

## What each job wears: outfit (see the shader), colours. Staff vary these
## from [constant PALETTES] by their seed.
const JOBS := {
	"pilot": {"outfit": 0, "main": Color(0.13, 0.14, 0.18), "accent": Color(1.0, 0.45, 0.1)},
	"scientist": {"outfit": 1, "main": Color(0.9, 0.91, 0.93), "accent": Color(0.2, 0.4, 0.8), "shirt": Color(0.35, 0.5, 0.75)},
	"exec": {"outfit": 2, "main": Color(0.16, 0.17, 0.22), "accent": Color(0.75, 0.15, 0.2)},
	"guard": {"outfit": 3, "main": Color(0.1, 0.1, 0.12), "accent": Color(1.0, 0.55, 0.0)},
	"engineer": {"outfit": 4, "main": Color(0.2, 0.32, 0.5), "accent": Color(0.95, 0.75, 0.1)},
}
## Staff colour choices per job: each entry overrides some of the job's.
const PALETTES := {
	"scientist": [
		{"shirt": Color(0.35, 0.5, 0.75)}, {"shirt": Color(0.6, 0.25, 0.3), "accent": Color(0.8, 0.3, 0.2)},
		{"shirt": Color(0.3, 0.55, 0.4), "accent": Color(0.2, 0.7, 0.4)}, {"shirt": Color(0.8, 0.75, 0.6)},
		{"shirt": Color(0.2, 0.2, 0.25), "legs": Color(0.3, 0.25, 0.2)},
	],
	"exec": [
		{"main": Color(0.16, 0.17, 0.22), "accent": Color(0.75, 0.15, 0.2)}, {"main": Color(0.08, 0.1, 0.2), "accent": Color(0.85, 0.65, 0.2)},
		{"main": Color(0.35, 0.36, 0.38), "accent": Color(0.2, 0.3, 0.6)}, {"main": Color(0.3, 0.22, 0.16), "accent": Color(0.4, 0.55, 0.3)},
		{"main": Color(0.55, 0.12, 0.15), "accent": Color(0.1, 0.1, 0.1), "shirt": Color(0.1, 0.1, 0.12)},
	],
	"engineer": [
		{"main": Color(0.2, 0.32, 0.5)}, {"main": Color(0.85, 0.42, 0.1), "accent": Color(0.15, 0.15, 0.15)},
		{"main": Color(0.35, 0.37, 0.4), "accent": Color(0.2, 0.75, 0.3)}, {"main": Color(0.15, 0.35, 0.3)},
	],
	"guard": [{}],
}
const SKINS := [Color(0.88, 0.69, 0.56), Color(0.78, 0.56, 0.44), Color(0.6, 0.42, 0.3), Color(0.42, 0.28, 0.2), Color(0.3, 0.2, 0.15)]
const HAIR_COLORS := [Color(0.08, 0.06, 0.05), Color(0.25, 0.15, 0.08), Color(0.5, 0.35, 0.18), Color(0.62, 0.58, 0.52), Color(0.55, 0.22, 0.1), Color(0.75, 0.6, 0.35)]
const HAIR_STYLES := {
	"female": ["Hair_Buns", "Hair_Long", "Hair_BuzzedFemale", "Hair_SimpleParted"],
	"male": ["Hair_SimpleParted", "Hair_Buzzed", "Hair_Long", "Hair_SimpleParted"],
}
## Clips that loop.
const LOOPS := ["Idle", "Jump", "Sprint", "Jog_Fwd", "Walk", "Crouch_Idle", "Crouch_Fwd",
	"Driving", "Slide", "Idle_TalkingPhone", "NinjaJump_Idle", "Sitting_Idle", "Idle_Talking",
	"Dance", "Swim_Idle", "Swim_Fwd", "Idle_FoldArms", "Idle_No", "Push", "Spell_Simple_Idle", "Zombie_Idle"]
const GEAR := "res://assets/models/gear/%s_%s.gltf"
const GHOST := preload("res://game/view/fx/ghost.gdshader")
## Bones that make up each region, for the shader.
const HEAD_BONES := ["Head", "neck_01"]
const FOOT_BONES := ["foot_l", "foot_r", "ball_l", "ball_r", "ball_leaf_l", "ball_leaf_r"]

static var _libs := {}
static var _baked := {}
static var _mats := {}
static var _hair_mats := {}
static var _lens_mats := {}
static var _ghost_mat: ShaderMaterial

var job := "scientist"
var female := false
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var _current := ""
var _extras: Array[MeshInstance3D] = []
var _dizzy: Node3D


## Other names the run uses for jobs.
const JOB_NAMES := {"tech": "engineer"}


## A person. `look` can set "skin", "hair" and "style" (indexes) and, for
## pilots, "main", "accent" and "trim" colours and "gear" and "lens"; anything
## missing comes from `seed`. `p_job` is a key of [constant JOBS] (or of
## [constant JOB_NAMES]).
static func make(p_job := "scientist", p_female := false, seed := 0, look := {}) -> Person:
	var c := Person.new()
	c.name = "Person"
	var j: String = JOB_NAMES.get(p_job, p_job)
	c.job = j if JOBS.has(j) else "scientist"
	c.female = p_female
	c._build(seed, look)
	return c


func _build(seed: int, look: Dictionary) -> void:
	var ps: PackedScene = load(FEMALE if female else MALE)
	model = ps.instantiate()
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var skin_i := int(look.get("skin", r.randi() % SKINS.size())) % SKINS.size()
	var hair_i := int(look.get("hair", r.randi() % HAIR_COLORS.size())) % HAIR_COLORS.size()
	var styles: Array = HAIR_STYLES["female" if female else "male"]
	var style_i := int(look.get("style", r.randi() % styles.size())) % styles.size()
	var j: Dictionary = JOBS[job].duplicate()
	if job != "pilot":
		var pal: Array = PALETTES.get(job, [{}])
		j.merge(pal[r.randi() % pal.size()], true)
	for k in ["main", "accent", "trim"]:
		if look.has(k):
			j[k] = look[k]
	j["wrist"] = 0.6 if female else 0.66
	var mat := _material(j, skin_i)
	for mi in model.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		meshes.append(m)
		if m.name.begins_with("Eye"):
			m.material_override = Kit.flat(Color(0.9, 0.88, 0.85) if m.name == "Eyes" else HAIR_COLORS[hair_i] * 0.7, 0.4)
			continue
		m.mesh = bake(m.mesh, m.skin, skeleton)
		m.material_override = mat
	_add_hair(str(styles[style_i]), HAIR_COLORS[hair_i])
	if not female and r.randf() < 0.3 and job != "pilot":
		_add_hair("Hair_Beard", HAIR_COLORS[hair_i])
	if look.has("gear"):
		_add_gear(str(look.gear), look.get("lens", Color(1.0, 0.6, 0.2)))
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.add_animation_library("ual1", _lib(UAL1))
	anim.add_animation_library("ual2", _lib(UAL2))
	anim.playback_default_blend_time = 0.15


## Hair models are made in the rest pose's space, so they ride the head bone
## offset by its rest.
func _add_hair(style: String, color: Color) -> void:
	var path := HAIR % style
	if skeleton == null or not ResourceLoader.exists(path):
		return
	var head := skeleton.find_bone("Head")
	if head < 0:
		return
	var at := BoneAttachment3D.new()
	at.bone_name = "Head"
	skeleton.add_child(at)
	var hair: Node3D = (load(path) as PackedScene).instantiate()
	hair.transform = skeleton.get_bone_global_rest(head).affine_inverse()
	at.add_child(hair)
	var key := color.to_html()
	for mi in hair.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		_extras.append(m)
		var base: Material = m.mesh.surface_get_material(0) if m.mesh else null
		if base is StandardMaterial3D:
			var k := "%s/%s" % [key, base.resource_name]
			if not _hair_mats.has(k):
				var hm: StandardMaterial3D = base.duplicate()
				hm.albedo_color = color * 2.2
				_hair_mats[k] = hm
			m.material_override = _hair_mats[k]


## Goggles or a visor ([code]tools/blender/gear.py[/code]), on the head like
## the hair, with its glass in `lens`.
func _add_gear(kind: String, lens: Color) -> void:
	var path := GEAR % [kind, "female" if female else "male"]
	if skeleton == null or not ResourceLoader.exists(path):
		return
	var head := skeleton.find_bone("Head")
	if head < 0:
		return
	var at := BoneAttachment3D.new()
	at.bone_name = "Head"
	skeleton.add_child(at)
	var gear: Node3D = (load(path) as PackedScene).instantiate()
	gear.name = "Gear"
	gear.transform = skeleton.get_bone_global_rest(head).affine_inverse()
	at.add_child(gear)
	var key := lens.to_html()
	if not _lens_mats.has(key):
		_lens_mats[key] = Kit.flat(lens * 0.35, 0.08, lens, 1.4)
		(_lens_mats[key] as StandardMaterial3D).metallic = 0.8
	for mi in gear.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		_extras.append(m)
		for s in m.mesh.get_surface_count():
			if PackView.surface_name(m.mesh, s) == "M_Lens":
				m.set_surface_override_material(s, _lens_mats[key])


static func _material(j: Dictionary, skin_i: int) -> ShaderMaterial:
	var key := "%s/%s/%s/%s/%s/%s/%s/%d" % [j.outfit, j.main.to_html(), j.accent.to_html(), j.get("shirt", Color.WHITE).to_html(), j.get("legs", Color.BLACK).to_html(), j.get("trim", Color.BLACK).to_html(), j.get("wrist", 0.66), skin_i]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("outfit", int(j.outfit))
		m.set_shader_parameter("main_color", j.main)
		m.set_shader_parameter("accent", j.accent)
		for k in ["shirt", "legs", "trim"]:
			if j.has(k):
				m.set_shader_parameter(k, j[k])
		m.set_shader_parameter("wrist", float(j.get("wrist", 0.66)))
		m.set_shader_parameter("skin", SKINS[skin_i])
		_mats[key] = m
	return _mats[key]


static func _lib(path: String) -> AnimationLibrary:
	if not _libs.has(path):
		var lib: AnimationLibrary = load(path)
		for n in lib.get_animation_list():
			var a := lib.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR if String(n) in LOOPS else Animation.LOOP_NONE
		_libs[path] = lib
	return _libs[path]


## A copy of a skinned body mesh with its rest pose in CUSTOM0 and how much
## of each vertex is head, hand and foot in CUSTOM1 (cached per mesh).
static func bake(mesh: Mesh, skin: Skin, skel: Skeleton3D) -> Mesh:
	if mesh == null or _baked.has(mesh):
		return _baked.get(mesh, mesh)
	var region_of := {}
	if skin:
		for i in skin.get_bind_count():
			var bname := String(skin.get_bind_name(i))
			if bname == "" and skel:
				bname = skel.get_bone_name(skin.get_bind_bone(i))
			var reg := Vector3.ZERO
			if bname in HEAD_BONES:
				reg = Vector3(1, 0, 0)
			elif bname.begins_with("hand_") or bname.begins_with("index_") or bname.begins_with("middle_") or bname.begins_with("ring_") or bname.begins_with("pinky_") or bname.begins_with("thumb_"):
				reg = Vector3(0, 1, 0)
			elif bname in FOOT_BONES:
				reg = Vector3(0, 0, 1)
			region_of[i] = reg
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var fmt: int = (mesh as ArrayMesh).surface_get_format(s) if mesh is ArrayMesh else 0
		var per := 8 if fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
		var c0 := PackedFloat32Array()
		var c1 := PackedFloat32Array()
		c0.resize(verts.size() * 3)
		c1.resize(verts.size() * 4)
		for i in verts.size():
			c0[i * 3] = verts[i].x
			c0[i * 3 + 1] = verts[i].y
			c0[i * 3 + 2] = verts[i].z
			var reg := Vector3.ZERO
			if bones != null and weights != null and bones.size() >= (i + 1) * per:
				for k in per:
					reg += region_of.get(int(bones[i * per + k]), Vector3.ZERO) * float(weights[i * per + k])
			c1[i * 4] = reg.x
			c1[i * 4 + 1] = reg.y
			c1[i * 4 + 2] = reg.z
			c1[i * 4 + 3] = 0.0
		arrays[Mesh.ARRAY_CUSTOM0] = c0
		arrays[Mesh.ARRAY_CUSTOM1] = c1
		var flags: int = (fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, flags)
	_baked[mesh] = out
	return out


## Sets an instance uniform on the body: "hurt" or "dim", 0 to 1.
func set_instance(key: String, value: float) -> void:
	for m in meshes:
		if m.material_override is ShaderMaterial:
			m.set_instance_shader_parameter(key, value)


## Plays a clip from either library by name ("Sprint", "Hit_Knockback").
func play(clip: String, blend := -1.0, speed := 1.0, restart := false) -> void:
	var full := clip_path(clip)
	if full == "":
		return
	anim.speed_scale = speed
	if full == _current and not restart and anim.is_playing():
		return
	_current = full
	anim.play(full, blend)
	if restart:
		anim.seek(0.0, true)


## Holds a clip at a moment (0 to 1 of its length).
func pose(clip: String, at := 1.0) -> void:
	var full := clip_path(clip)
	if full == "":
		return
	anim.play(full, 0.0)
	var a := anim.get_animation(full)
	anim.seek(a.length * clampf(at, 0.0, 0.999), true)
	anim.pause()
	_current = full


func current() -> String:
	return _current.get_slice("/", 1)


func clip_path(clip: String) -> String:
	for lib in ["ual1", "ual2"]:
		var p := "%s/%s" % [lib, clip]
		if anim.has_animation(p):
			return p
	push_warning("Person: no clip %s" % clip)
	return ""


func clip_length(clip: String) -> float:
	var p := clip_path(clip)
	return anim.get_animation(p).length if p != "" else 0.0


func bone_position(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	if i < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin


## Draws this person as a see-through ghost (Daily Flight and Course ghosts).
func set_ghost() -> void:
	if _ghost_mat == null:
		_ghost_mat = ShaderMaterial.new()
		_ghost_mat.shader = GHOST
	for m in meshes:
		m.material_override = _ghost_mat
	for m in _extras:
		m.material_override = _ghost_mat
		for s in m.mesh.get_surface_count():
			m.set_surface_override_material(s, null)


## Little stars circling the head (knocked over, or stunned in a party race).
func set_dizzy(on: bool) -> void:
	if not on:
		if _dizzy:
			_dizzy.visible = false
		return
	if _dizzy == null:
		_dizzy = Node3D.new()
		_dizzy.name = "Dizzy"
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://game/view/fx/glow.gdshader")
		mat.set_shader_parameter("shape", 3)
		mat.set_shader_parameter("billboard", true)
		mat.set_shader_parameter("strength", 2.2)
		var q := QuadMesh.new()
		q.size = Vector2(0.24, 0.24)
		q.material = mat
		for i in 3:
			var star := MeshInstance3D.new()
			star.mesh = q
			star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			star.set_instance_shader_parameter("tint", Color(1.0, 0.85, 0.3))
			_dizzy.add_child(star)
		add_child(_dizzy)
	_dizzy.visible = true


func is_dizzy() -> bool:
	return _dizzy != null and _dizzy.visible


## Turns the dizzy stars; call each frame while they show.
func spin_dizzy(time: float) -> void:
	if not is_dizzy():
		return
	_dizzy.global_position = bone_position("Head") + Vector3(0, 0.3, 0)
	var n := _dizzy.get_child_count()
	for i in n:
		var a := time * 4.0 + TAU * i / n
		(_dizzy.get_child(i) as Node3D).position = Vector3(cos(a) * 0.22, sin(a * 2.0) * 0.03, sin(a) * 0.22)
