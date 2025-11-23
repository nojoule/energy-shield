# Energy Shield
This addon for Godot provides an energy shield that can be easily integrated into your scenes. You can use either the `shield_plane.tscn` or `shield_sphere.tscn` directly, or apply the shader to other materials. Note that some adjustments may be needed to ensure proper functionality on meshes other than planes and spheres.

## Changes
- 1.3.1: Velocity Incorperated into Impact Effect
	NOTE: For impacts with non RigidBody3D nodes to incorperate the node's velocity it would need to: 1) keep track of their approximate velocity, and 2) have a function called "get_approx_velocity" that would return that approximated velocity.
- 1.3.0: Touch Based Ripple Effects
	This also changes the size of the ripples depending on the size of the object that is touching the shield.
	NOTE: To have this feature look the best, don't scale the shield mesh or any of its parents.
- 1.2.0: Adding Dynamic number of Impacts
- 1.1.0: Origin for static waves and impacts can now be set to relative, so the movement of the object won't influence the impact/static waves
- 1.0.1: Web build compatibility

## Roadmap
- [x] Release 1.0
- [x] create Youtube explaining the Shader https://youtu.be/0YiZSrtxtcg
- [x] Dynamic number of Impacts
~- [ ] Asset for Unity~
- [ ] Support more types of meshes (e.g. Cube)
- [ ] Add refraction effect
- [ ] Add chromatic aberration effect

<img src="./docs/showcase_inenvironment.webp" alt="sphere and plane energy shield, with the sphere showing an impact reaction" height="200"> <img src="./docs/showcase_standalone.webp" alt="sphere and plane energy shield, each showing a wave" height="200">

## Interactable
You can use the `shield.gd` script to add mouse click interactions or modify it to suit your specific needs. The following interactions are available:

**Impact**:
Impacts can be dynamically added, up to Image.MAX_HEIGHT, by adjusting the shader’s uniform variables. Each impact generates a wave that propagates across the shield from a specified position. The wave’s intensity and speed can be customized to your preference.

**Generate/Collapse**:
The energy shield can be animated to collapse or regenerate from specified positions. Both the animation and the highlight effects are fully adjustable.

**Intersection Highlight**:
Leveraging the depth texture, the material detects and highlights nearby objects or intersections with other objects.

## Customizations

You can customize parameters such as color, wave height, frequency, and color quantization to match your game’s style. All shader parameters are thoroughly documented — refer to the example scene for demonstrations.

## Support me
[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Y8Y01BSU6N)

Follow me on [Twitch](https://www.twitch.tv/nojoule) for some live-coding or check out my [Youtube](https://www.youtube.com/@nojoule) for content around game dev.
