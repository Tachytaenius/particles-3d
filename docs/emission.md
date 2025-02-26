Particles carry two sources of luminance:
- Their emission cross section (volume luminance per length).
	This diffuses into the emission coefficient (luminance per length) of the space around the particle.
	The particle's contribution to the emission coefficient of the space is the emission cross section of the particle divided by the volume of the space.
	This represents glowing gas and dust around the particle and is stored in a texture which is marched through during rendering.
- Their luminous flux.
	It is drawn directly as a disk in the scene, representing a star or other body at the particle's position.
	Since the star's radius is so much smaller than the distance to it, its angular radius should be effectively zero. In my model/understanding, that means it blurs out into a disk in the camera, which is the same size as all other such disks. The disk's centre has a luminance equal to the star's luminous flux divided by its distance to the camera squared multiplied by the solid angle the disk occupies.
