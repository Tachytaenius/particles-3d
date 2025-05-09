#line 1

uniform layout(rgba32f) image3D chargeSource;
uniform layout(rgba32f) image3D chargeDestination;

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

	float nnnCharge = imageLoad(chargeSource, nnn).r;
	float nnpCharge = imageLoad(chargeSource, nnp).r;
	float npnCharge = imageLoad(chargeSource, npn).r;
	float nppCharge = imageLoad(chargeSource, npp).r;
	float pnnCharge = imageLoad(chargeSource, pnn).r;
	float pnpCharge = imageLoad(chargeSource, pnp).r;
	float ppnCharge = imageLoad(chargeSource, ppn).r;
	float pppCharge = imageLoad(chargeSource, ppp).r;

	float chargeSum = nnnCharge + nnpCharge + npnCharge + nppCharge + pnnCharge + pnpCharge + ppnCharge + pppCharge;

	imageStore(chargeDestination, destinationCoord, vec4(
		chargeSum != 0.0 ? ( // Avoid dividing by zero
			( // Weighted average
				imageLoad(chargeSource, nnn).xyz * nnnCharge + imageLoad(chargeSource, nnp).xyz * nnpCharge +
				imageLoad(chargeSource, npn).xyz * npnCharge + imageLoad(chargeSource, npp).xyz * nppCharge +
				imageLoad(chargeSource, pnn).xyz * pnnCharge + imageLoad(chargeSource, pnp).xyz * pnpCharge +
				imageLoad(chargeSource, ppn).xyz * ppnCharge + imageLoad(chargeSource, ppp).xyz * pppCharge
			) / chargeSum
		) : vec3(0.0),
		chargeSum
	));
}
