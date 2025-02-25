#line 1

varying vec3 directionPreNormalise;

#ifdef VERTEX

uniform mat4 clipToSky;

vec4 position(mat4 loveTransform, vec4 vertexPosition) {
	directionPreNormalise = (
		clipToSky * vec4(
			(VertexTexCoord.xy * 2.0 - 1.0) * vec2(1.0, -1.0),
			-1.0,
			1.0
		)
	).xyz;
	return loveTransform * vertexPosition;
}

#endif

#ifdef PIXEL

readonly buffer BoxParticleData {
	BoxParticleDataEntry[] boxParticleData;
};

readonly buffer BoxArrayData {
	uint[] boxArrayData;
};

uniform vec3 cameraPosition;
uniform vec3 boxSize;
uniform uvec3 worldSizeBoxes;
uniform vec3 worldSize;
uniform bool nearestNeighbour;
uniform float rayStepSize;
uniform uint rayStepCount;

const float colourMultiplier = 5.0;

BoxParticleDataEntry getBoxParticleData(vec3 position) {
	if (position.x < 0.0 || position.y < 0.0 || position.z < 0.0) {
		return emptyBoxParticleData;
	}
	uvec3 boxCoords = uvec3(position / boxSize);
	if (boxCoords.x >= worldSizeBoxes.x || boxCoords.y >= worldSizeBoxes.y || boxCoords.z >= worldSizeBoxes.z) {
		return emptyBoxParticleData;
	}
	uint boxId =
		boxCoords.x * worldSizeBoxes.x * worldSizeBoxes.y +
		boxCoords.y * worldSizeBoxes.y +
		boxCoords.z;
	// Box data is set to usable empty data when empty so that we don't need to check here
	// if (boxArrayData[boxId] == invalidBoxArrayDatum) {
	// 	return emptyBoxParticleData; // Empty box
	// }
	return boxParticleData[boxId];
}

VolumetricSample sampleVolumetricsNearestNeighbour(vec3 position) {
	BoxParticleDataEntry entry = getBoxParticleData(position);

	return VolumetricSample (
		entry.scatterance,
		entry.absorption,
		entry.averageColour,
		entry.emission
	);
}

VolumetricSample sampleVolumetricsTrilinear(vec3 position) {
	// Trilinear interpolation
	vec3 positionUsable = position - boxSize * 0.5;
	vec3 fractional = mod(positionUsable, boxSize) / boxSize;
	vec4 swizzlableOffset = vec4(boxSize, 0.0); // Swizzle with xyz but replace components with w when not offset on that axis
	// n is negative, p is positive
	BoxParticleDataEntry nnn = getBoxParticleData(positionUsable + swizzlableOffset.www);
	BoxParticleDataEntry nnp = getBoxParticleData(positionUsable + swizzlableOffset.wwz);
	BoxParticleDataEntry npn = getBoxParticleData(positionUsable + swizzlableOffset.wyw);
	BoxParticleDataEntry npp = getBoxParticleData(positionUsable + swizzlableOffset.wyz);
	BoxParticleDataEntry pnn = getBoxParticleData(positionUsable + swizzlableOffset.xww);
	BoxParticleDataEntry pnp = getBoxParticleData(positionUsable + swizzlableOffset.xwz);
	BoxParticleDataEntry ppn = getBoxParticleData(positionUsable + swizzlableOffset.xyw);
	BoxParticleDataEntry ppp = getBoxParticleData(positionUsable + swizzlableOffset.xyz);

	return VolumetricSample (
		trilinearMix(
			nnn.scatterance, nnp.scatterance, npn.scatterance, npp.scatterance,
			pnn.scatterance, pnp.scatterance, ppn.scatterance, ppp.scatterance,
			fractional
		),
		trilinearMix(
			nnn.absorption, nnp.absorption, npn.absorption, npp.absorption,
			pnn.absorption, pnp.absorption, ppn.absorption, ppp.absorption,
			fractional
		),
		trilinearMix(
			nnn.averageColour, nnp.averageColour, npn.averageColour, npp.averageColour,
			pnn.averageColour, pnp.averageColour, ppn.averageColour, ppp.averageColour,
			fractional
		),
		trilinearMix(
			nnn.emission, nnp.emission, npn.emission, npp.emission,
			pnn.emission, pnp.emission, ppn.emission, ppp.emission,
			fractional
		)
	);
}

vec3 getRayColour(vec3 rayPosition, vec3 rayDirection) {
	vec3 totalRayLight = vec3(0.0);
	float totalTransmittance = 1.0;
	for (uint rayStep = 0; rayStep < rayStepCount; rayStep++) {
		float t = rayStepSize * float(rayStep);
		vec3 currentPosition = rayPosition + rayDirection * t;

		VolumetricSample volumetricSample = nearestNeighbour ?
			sampleVolumetricsNearestNeighbour(currentPosition) :
			sampleVolumetricsTrilinear(currentPosition);

		float extinction = volumetricSample.absorption + volumetricSample.scatterance;

		float transmittanceThisStep = exp(-extinction * rayStepSize);
		vec3 incomingLight = vec3(0.0); // TODO
		vec3 rayLightThisStep = rayStepSize * (volumetricSample.emission + volumetricSample.colour * volumetricSample.scatterance * incomingLight);

		totalRayLight *= transmittanceThisStep;
		totalRayLight += rayLightThisStep;
		totalTransmittance *= transmittanceThisStep;
	}
	return totalRayLight;
}

vec4 effect(vec4 loveColour, sampler2D image, vec2 textureCoords, vec2 windowCoords) {
	vec3 direction = normalize(directionPreNormalise);
	vec3 outColour = getRayColour(cameraPosition, direction);
	return vec4(outColour, 1.0);
}

#endif
