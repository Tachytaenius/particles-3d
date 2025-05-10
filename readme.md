# Particles 3D

This is an optimised n-body cosmic simulation with smooth volumetric raymarched lighting and thousands of particles. It uses Newton's laws of motion for gravity, has dark energy to resist the collapse of the system and allow structure to last for longer, is consistent on units/dimensions for calculations, etc.

Here is a screenshot of it running on an integrated graphics card. Without linearly filtering the volumetric data, it runs at 60 Hz.

![A screenshot of the simulation](screenshot.png)

It runs using the LÖVE framework and requires at least LÖVE 12.

Controls:

- Move right: D
- Move left: A
- Move up: E
- Move down: Q
- Move forwards: W
- Move backwards: S
- Pitch down: K
- Pitch up: I
- Yaw right: L
- Yaw left: J
- Roll anticlockwise: U
- Roll clockwise: O
- Pause: Space

Command line arguments are particle count (defaulting to 5000) followed by a mode (defaulting to `cosmic`).

Run with the mode `colour` to replace the gravity simulation with one based on a concept inspired by colour charge from real-life particle physics.
Don't get the colour charges confused with a particle's cloud emission cross section, luminous flux, or just its colour (which is unused as of yet).

New charges can be defined with relative ease, allowing new behaviours to be developed.
To define a new charge:
1. Call `newCharge` as with the others in consts.lua
2. Call `setCharge` for the charge in `newParticle`, even if the value means chargelessness (presumably 0)
3. Ensure the charges are used in the particle acceleration compute shader.
	Defining constants for the force's strength etc is recommended.
