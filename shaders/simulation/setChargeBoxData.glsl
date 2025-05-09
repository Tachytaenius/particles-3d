#line 1

buffer Particles {
	Particle[] particles;
};

buffer ParticleCharges {
	float[] particleCharges;
};
uniform uint particleCount;

buffer SortedParticleBoxIds {
	SortedParticleBoxId[] sortedParticleBoxIds;
};

buffer BoxArrayData {
	uint[] boxArrayData;
};
uniform uint boxCount;

uniform uvec3 worldSizeBoxes;
uniform vec3 boxSize;
uniform float boxVolume;

uniform float spaceDensity;
uniform layout(rgba32f) image3D charge;

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint mainBoxId = gl_GlobalInvocationID.x;
	if (mainBoxId >= boxCount) {
		return;
	}

	uint mainBoxArrayStart = boxArrayData[mainBoxId];
	uvec3 mainBoxGridPosition = uvec3(
		mainBoxId % worldSizeBoxes.x,
		(mainBoxId / worldSizeBoxes.x) % worldSizeBoxes.y,
		(mainBoxId / worldSizeBoxes.x) / worldSizeBoxes.y
	);
	vec3 mainBoxCentre = (vec3(mainBoxGridPosition) + 0.5) * boxSize;

	// Get particles in main box and consider them for box charge and centre of charge
	float chargeTotal = 0.0;
	float chargeTotalAbs = 0.0;
	vec3 weightedPositionTotal = vec3(0.0);
	for (uint i = mainBoxArrayStart; i < particleCount; i++) { // Just to stop from going over particleCount, this is more likely to hit break
		if (sortedParticleBoxIds[i].boxId != mainBoxId) {
			break;
		}
		uint particleId = sortedParticleBoxIds[i].particleId;
		float charge = particleCharges[particleId];
		float chargeAbs = abs(charge);
		chargeTotal += charge;
		chargeTotalAbs += chargeAbs;
		weightedPositionTotal += particles[particleId].position * chargeAbs;
	}
	// Add dark energy
	float spaceDensityCharge = spaceDensity * boxVolume;
	float spaceDensityChargeAbs = abs(spaceDensityCharge);
	chargeTotal += spaceDensityCharge;
	chargeTotalAbs += spaceDensityChargeAbs;
	weightedPositionTotal += mainBoxCentre * spaceDensityChargeAbs;

	ivec3 imageCoord = ivec3(mainBoxGridPosition);
	imageStore(charge, imageCoord,
		vec4(
			chargeTotalAbs > 0.0 ? weightedPositionTotal / chargeTotalAbs : vec3(0.0), // Don't care value if charge (excluding neighbouring boxes) is zero
			chargeTotal
		)
	);
}
