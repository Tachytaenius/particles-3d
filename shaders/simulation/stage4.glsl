#line 1

buffer Particles {
	Particle[] particles;
};

buffer SortedParticleBoxIds {
	SortedParticleBoxId[] sortedParticleBoxIds;
};

buffer BoxArrayData {
	BoxArrayEntry[] boxArrayData;
};

buffer BoxParticleData {
	BoxParticleDataEntry[] boxParticleData;
};
uniform uint boxCount;

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint boxId = gl_GlobalInvocationID.x;
	if (boxId >= boxCount) {
		return;
	}

	BoxArrayEntry thisBoxArrayData = boxArrayData[boxId];
	if (thisBoxArrayData.start == invalidBoxArrayDatum) {
		return;
	}
	// Assume thisBoxArrayData.count > 0
	float massTotal = 0.0;
	vec3 weightedPositionTotal = vec3(0.0);
	for (uint i = thisBoxArrayData.start; i < thisBoxArrayData.start + thisBoxArrayData.count; i++) {
		uint particleId = sortedParticleBoxIds[i].particleId;
		// Assume sortedParticleBoxIds[i].boxId == boxId
		Particle particle = particles[particleId];
		massTotal += particle.mass;
		weightedPositionTotal += particle.position * particle.mass;
	}
	boxParticleData[boxId] = BoxParticleDataEntry (
		massTotal,
		weightedPositionTotal / massTotal
	);
}
