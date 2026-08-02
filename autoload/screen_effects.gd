extends CanvasLayer
## Full-screen effects that belong to the screen rather than to any scene.
##
## An autoload CanvasLayer above everything else, because both effects here have to survive a
## scene change and cover whatever is loaded. The CRT filter is a *display* setting — a player
## who turned it on at the title screen expects it on in the game, and a copy of it in each
## scene is two copies to keep in step. The damage vignette has to sit over the HUD, and the
## HUD is the thing it would otherwise be underneath.
##
## Deliberately the only autoload that draws anything. Everything else the player sees is
## owned by the scene it belongs to (spec section 26.4 on narrowly scoped services), and the
## test for being here is the same one GameManager uses: no sensible owner in the tree, and
## more than one unrelated thing needs it.

const CRT_SHADER := preload("res://shaders/crt.gdshader")
const DAMAGE_SHADER := preload("res://shaders/damage_vignette.gdshader")

## Above the menu layer (10), which is above the HUD. Nothing draws over the screen itself.
const LAYER := 100

## Peak opacity of the damage vignette, before the player's flash intensity scales it.
const DAMAGE_PEAK := 0.45

## Seconds for the vignette to fade back to nothing. Long enough to register in peripheral
## vision, short enough to be gone before the next hit lands.
const DAMAGE_FADE_SECONDS := 0.45

var _crt: ColorRect
var _damage: ColorRect
var _damage_left := 0.0


func _ready() -> void:
	# Must keep fading while the tree is paused, or a hit that kills the player freezes the
	# vignette on screen underneath the summary.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER

	_crt = _build_overlay(CRT_SHADER)
	_damage = _build_overlay(DAMAGE_SHADER)

	EventBus.player_damaged.connect(_on_player_damaged)
	SaveManager.settings_changed.connect(_on_settings_changed)
	_on_settings_changed(SaveManager.settings)


## Both overlays are the same thing with a different shader: a full-rect ColorRect that
## ignores the mouse, so nothing behind it becomes unclickable.
func _build_overlay(shader: Shader) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	add_child(rect)
	return rect


func _process(delta: float) -> void:
	if _damage_left <= 0.0:
		return
	_damage_left = maxf(_damage_left - delta, 0.0)
	_set_damage_strength(_damage_left / DAMAGE_FADE_SECONDS)


func _on_player_damaged(_info: DamageInfo, _remaining: float) -> void:
	# Restarted rather than accumulated. Two hits in quick succession should read as two
	# flashes, not as one that gets progressively brighter until it hides the screen.
	_damage_left = DAMAGE_FADE_SECONDS


## The vignette obeys the same flash intensity slider as the hurt flash on the sprite, which
## is the setting a player turns down because full-screen colour changes bother them. At zero
## it is off entirely, not merely dim.
func _set_damage_strength(fraction: float) -> void:
	var intensity := clampf(SaveManager.settings.flash_intensity, 0.0, GameSettings.INTENSITY_MAX)
	var material := _damage.material as ShaderMaterial
	material.set_shader_parameter("strength", fraction * DAMAGE_PEAK * intensity)


func _on_settings_changed(settings: GameSettings) -> void:
	_crt.visible = settings.crt_enabled
	# Applied immediately as well as on the next hit, so turning the slider to zero from the
	# pause menu clears a vignette that is fading right now.
	_set_damage_strength(_damage_left / DAMAGE_FADE_SECONDS)
