# The engine features Robo Rush is built without, as SCons options.
#
# The stock Web template is 39.5 MB of WebAssembly, and most of it is engine the game never
# runs: 3D, two physics engines it does not use, XR, video, networking, and a text server whose
# Unicode data alone outweighs the game. tools/engine/build_template.sh compiles the engine with
# this file as its SCons profile, which takes index.wasm to 22.9 MB (3.7 MB with brotli, from
# 6.9). Platform and target are not set here; they come from the build script's command line.
#
# The same profile builds the native engine the suite runs against, so what the game can use in
# a browser is what the suite proves it can use. tests/test_engine_profile.gd is the check that a
# switch here has not taken away something the game needs: on the stripped engine, every shipped
# script has to compile and every shipped scene has to instantiate.
#
# Turning a feature back on is a one-line change here. Turning one off needs the reason the game
# does not need it, next to the line.

production = "yes"
# Compatibility code for APIs Godot has deprecated. Nothing here was written against them.
deprecated = "no"

# A 2D game. disable_3d also removes 3D physics, 3D navigation and XR. There is no navigation
# at all (enemies steer straight at the player), and none of the GUI nodes disable_advanced_gui
# removes: no dialogs, menus, trees, rich text, spin boxes or option buttons.
disable_3d = "yes"
disable_navigation_2d = "yes"
disable_advanced_gui = "yes"
# Loading .zip packs. The game ships one .pck.
minizip = "no"

# English, in one bitmap font: the fallback text server instead of ICU and HarfBuzz. It draws
# the font identically (the main menu is pixel-identical on both).
module_text_server_adv_enabled = "no"
module_text_server_fb_enabled = "yes"
module_msdfgen_enabled = "no"

# Imported textures are WebP lossless, so webp stays. Nothing loads any other image format at
# runtime: jpg only serves the Wavedash SDK's get_user_avatar, which the game never calls.
module_jpg_enabled = "no"
module_bmp_enabled = "no"
module_tga_enabled = "no"
module_hdr_enabled = "no"
module_dds_enabled = "no"
module_ktx_enabled = "no"
module_tinyexr_enabled = "no"
module_svg_enabled = "no"
module_basis_universal_enabled = "no"
module_astcenc_enabled = "no"
module_bcdec_enabled = "no"
module_betsy_enabled = "no"
module_cvtt_enabled = "no"
module_etcpak_enabled = "no"

# Every sound is a WAV, imported as QOA, which the engine core decodes. No video.
module_ogg_enabled = "no"
module_vorbis_enabled = "no"
module_mp3_enabled = "no"
module_theora_enabled = "no"
module_interactive_music_enabled = "no"

# 3D modules that disable_3d does not reach on its own.
module_csg_enabled = "no"
module_gridmap_enabled = "no"
module_gltf_enabled = "no"
module_fbx_enabled = "no"
module_jolt_physics_enabled = "no"
module_godot_physics_3d_enabled = "no"
module_navigation_2d_enabled = "no"
module_navigation_3d_enabled = "no"
module_openxr_enabled = "no"
module_webxr_enabled = "no"
module_mobile_vr_enabled = "no"
module_meshoptimizer_enabled = "no"
module_vhacd_enabled = "no"
module_xatlas_unwrap_enabled = "no"
module_lightmapper_rd_enabled = "no"
module_raycast_enabled = "no"
module_glslang_enabled = "no"

# No networking beyond HTTPRequest, which the Web platform serves with the browser's fetch.
# Core keeps the hashing it needs from mbedtls without the module.
module_mbedtls_enabled = "no"
module_enet_enabled = "no"
module_webrtc_enabled = "no"
module_websocket_enabled = "no"
module_multiplayer_enabled = "no"
module_upnp_enabled = "no"
module_jsonrpc_enabled = "no"

module_regex_enabled = "no"
module_noise_enabled = "no"
module_camera_enabled = "no"
module_zip_enabled = "no"
module_visual_shader_enabled = "no"
module_objectdb_profiler_enabled = "no"
