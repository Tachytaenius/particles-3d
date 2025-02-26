#line 1

buffer Particles {
	Particle[] particles;
};

buffer ParticleDrawData {
	ParticleDrawDataEntry[] particleDrawData;
};

uniform uint particleCount;

uniform vec3 cameraPosition;

uniform vec3 worldSize;

uniform sampler3D scatterance;
uniform sampler3D absorption;

uniform uint rayStepCount;

uniform float diskSolidAngle;

struct VolumetricSample {
	float scatterance;
	float absorption;
};

VolumetricSample sampleVolumetrics(vec3 position) {
	vec3 textureCoords = position / worldSize; // Can use any of the textures, they should all have the same size
	return VolumetricSample (
		Texel(scatterance, textureCoords).r,
		Texel(absorption, textureCoords).r
	);
}

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint particleId = gl_GlobalInvocationID.x;
	if (particleId >= particleCount) {
		return;
	}

	Particle particle = particles[particleId];

	vec3 difference = particle.position - cameraPosition;
	float dist = length(difference);

	float totalTransmittance = 1.0;
	float stepSize = dist / float(rayStepCount);
	for (uint i = 0; i < rayStepCount; i++) {
		float t = 1.0 - (i + 0.5) / float(rayStepCount); // Move backwards, sample in the middle of each line segment
		vec3 samplePosition = mix(cameraPosition, particle.position, t); // t goes from 0 to 1
		VolumetricSample dustSample = sampleVolumetrics(samplePosition);
		float extinction = dustSample.absorption + dustSample.scatterance;
		float transmittanceThisStep = exp(-extinction * stepSize);
		totalTransmittance *= transmittanceThisStep;
	}

	particleDrawData[particleId] = ParticleDrawDataEntry(
		normalize(difference),
		// The units work out but this didn't work, but it's kept here anyway:
		// particle.cloudEmissionCrossSection / dot(difference, difference) * totalTransmittance // distance^3 * luminance * distance^-1 * disance^-2 = luminance
		// Now we consider a luminous flux of an object inside a cloud, separate to the emission of the cloud:
		particle.luminousFlux / dot(difference, difference) / diskSolidAngle * totalTransmittance // luminous flux * distance^-2 * solid angle^-1 = luminance
	);
}
