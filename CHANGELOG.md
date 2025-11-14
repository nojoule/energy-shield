# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2025-11-14

### Fixed
- **Critical: Object scale and wave size bugs** - Fixed incorrect application of `_object_scale` and `_object_size` causing waves to not scale properly with object transformations
  - `_object_scale` was hardcoded to `1.0` instead of using actual transform scale
  - `_object_size` was incorrectly set to the transform scale instead of mesh size (1.0)
  - Wave frequencies and radii were being incorrectly multiplied/divided by scale
  - Generation origin was incorrectly multiplied by scale in relative mode
  - Generation progress calculation incorrectly used both `_object_scale` and `_object_size`

### Changed
- **shield.gd**: Refactored scale handling
  - Added `class_name NJEnergyShield` declaration
  - `_ready()`: Now uses maximum of all axis scales instead of just X-axis
  - `_physics_process()`: Now correctly updates `_object_scale` with the actual transform scale

- **shield_base.gdshaderinc**: Major refactoring of wave calculations
  - Changed function signatures to use offset vectors instead of separate world positions
    - `computeImpactOffset()`, `computeStaticOffset()`, `adjustImpactNormal()`, `adjustStaticNormal()`, `getAffectionStrengthStatic()`, `getAffectionStrengthImpact()`
  - Wave direction calculations now use `normalize(-origin_offset)` instead of `normalize(position - origin)`
  - Vertex shader: Calculate offset vectors and divide by `_object_scale` for relative origins
  - Removed incorrect scale multiplication from wave parameters (frequency, radius, amplitude)
  - Fragment shader: Calculate offset vectors per fragment for accurate normal calculations
  - Fixed generation progress to use only `_object_scale` instead of `_object_scale * _object_size`

- **camera_movement.gd**: Changed to use built-in `ui_*` input actions
  - Replaced custom input actions (`move_forward`, `move_backward`, `move_left`, `move_right`, `move_up`, `move_down`) with Godot's built-in actions (`ui_up`, `ui_down`, `ui_left`, `ui_right`)
  - Removed vertical movement (up/down) for simpler camera controls
  - No longer requires custom input definitions in `project.godot`

### Added
- **shield_plane.tscn**: Missing shader parameters
  - `shader_parameter/_relative_origin_static = true`
  - `shader_parameter/_relative_origin_impact = false`

- **test-scenes/resize.tscn**: New test scene demonstrating proper scaling behavior
  - 3 shield spheres at different scales (0.5x, 1.0x, 2.0x)
  - 3 shield planes at different scales (0.5x, 1.0x, 2.0x)

### Technical Details
**Scale Handling Philosophy:**
- `_object_scale`: The transform scale applied to the object (from `global_transform.basis.get_scale()`)
- `_object_size`: The base mesh size (default 1.0 for standard meshes)
- Wave parameters are defined in mesh-local units and scale automatically with object transform
- Offset vectors are calculated in world space, then divided by `_object_scale` for relative origins
- This approach keeps shader parameters simple and allows consistent visual effects across different scales
