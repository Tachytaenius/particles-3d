#line 1

uniform layout(r32f) image3D massSource;
uniform layout(r32f) image3D massDestination;

uniform layout(rgba32f) image3D centreOfMassSource;
uniform layout(rgba32f) image3D centreOfMassDestination;

layout(local_size_x = 2, local_size_y = 2, local_size_z = 2) in;
void computemain() {
	ivec3 destinationCoord = ivec3(gl_GlobalInvocationID);

	// Source coords, negative/positive on each axis
	ivec4 s = ivec4(1, 1, 1, 0); // Swizzlable offset, zero an axis by replacing its letter with w
	ivec3 nnn = 2 * destinationCoord;
	ivec3 nnp = nnn + s.wwz;
	ivec3 npn = nnn + s.wyw;
	ivec3 npp = nnn + s.wyz;
	ivec3 pnn = nnn + s.xww;
	ivec3 pnp = nnn + s.xwz;
	ivec3 ppn = nnn + s.xyw;
	ivec3 ppp = nnn + s.xyz;

	float nnnMass = imageLoad(massSource, nnn).r;
	float nnpMass = imageLoad(massSource, nnp).r;
	float npnMass = imageLoad(massSource, npn).r;
	float nppMass = imageLoad(massSource, npp).r;
	float pnnMass = imageLoad(massSource, pnn).r;
	float pnpMass = imageLoad(massSource, pnp).r;
	float ppnMass = imageLoad(massSource, ppn).r;
	float pppMass = imageLoad(massSource, ppp).r;

	float massSum = nnnMass + nnpMass + npnMass + nppMass + pnnMass + pnpMass + ppnMass + pppMass;

	imageStore(massDestination, destinationCoord, vec4(
		massSum,
		0.0, 0.0, 1.0
	));

	imageStore(centreOfMassDestination, destinationCoord, vec4(
		massSum != 0.0 ? ( // Avoid dividing by zero
			( // Weighted average
				imageLoad(centreOfMassSource, nnn).rgb * nnnMass + imageLoad(centreOfMassSource, nnp).rgb * nnpMass +
				imageLoad(centreOfMassSource, npn).rgb * npnMass + imageLoad(centreOfMassSource, npp).rgb * nppMass +
				imageLoad(centreOfMassSource, pnn).rgb * pnnMass + imageLoad(centreOfMassSource, pnp).rgb * pnpMass +
				imageLoad(centreOfMassSource, ppn).rgb * ppnMass + imageLoad(centreOfMassSource, ppp).rgb * pppMass
			) / massSum
		) : vec3(0.0),
		1.0
	));
}
