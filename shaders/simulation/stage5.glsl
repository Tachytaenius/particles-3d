#line 1

buffer Particles {
	Particle[] particles;
};
uniform uint particleCount;

buffer SortedParticleBoxIds {
	SortedParticleBoxId[] sortedParticleBoxIds;
};

buffer BoxArrayData {
	uint[] boxArrayData;
};

buffer BoxParticleData {
	BoxParticleDataEntry[] boxParticleData;
};
uniform uint boxCount;

uniform vec3 boxSize;

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint boxId = gl_GlobalInvocationID.x;
	if (boxId >= boxCount) {
		return;
	}

	uint thisBoxArrayStart = boxArrayData[boxId];
	if (thisBoxArrayStart == invalidBoxArrayDatum) {
		return;
	}

	float massTotal = 0.0;
	vec3 weightedPositionTotal = vec3(0.0);
	float scatteranceCrossSectionTotal = 0.0;
	float absorptionCrossSectionTotal = 0.0;
	vec3 emissionCrossSectionTotal = vec3(0.0);
	vec3 weightedColourTotal = vec3(0.0);

	for (uint i = thisBoxArrayStart; i < particleCount; i++) { // Just to stop from going over particleCount, this is more likely to hit break
		if (sortedParticleBoxIds[i].boxId != boxId) {
			break;
		}
		uint particleId = sortedParticleBoxIds[i].particleId;
		Particle particle = particles[particleId];

		massTotal += particle.mass;
		weightedPositionTotal += particle.position * particle.mass;
		emissionCrossSectionTotal += particle.emissionCrossSection;
		scatteranceCrossSectionTotal += particle.scatteranceCrossSection;
		absorptionCrossSectionTotal += particle.absorptionCrossSection;

		weightedColourTotal += particle.colour * particle.mass;
	}

	float boxVolume = boxSize.x * boxSize.y * boxSize.z;

	boxParticleData[boxId] = BoxParticleDataEntry (
		massTotal,
		weightedPositionTotal / massTotal,
		scatteranceCrossSectionTotal / boxVolume,
		absorptionCrossSectionTotal / boxVolume,
		weightedColourTotal / massTotal,
		emissionCrossSectionTotal / boxVolume
	);
}
