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
uniform uint boxCount;

uniform uvec3 worldSizeBoxes;
uniform float boxVolume;

uniform layout(r32f) image3D mass;
uniform layout(rgba32f) image3D centreOfMass;
uniform layout(r32f) image3D scatterance;
uniform layout(r32f) image3D absorption;
uniform layout(rgba32f) image3D averageColour;
uniform layout(rgba32f) image3D emission;

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint boxId = gl_GlobalInvocationID.x;
	if (boxId >= boxCount) {
		return;
	}

	uint thisBoxArrayStart = boxArrayData[boxId];

	float massTotal = 0.0;
	vec3 weightedPositionTotal = vec3(0.0);
	float scatteranceCrossSectionTotal = 0.0;
	float absorptionCrossSectionTotal = 0.0;
	vec3 cloudEmissionCrossSectionTotal = vec3(0.0);
	vec3 weightedColourTotal = vec3(0.0);

	for (uint i = thisBoxArrayStart; i < particleCount; i++) { // Just to stop from going over particleCount, this is more likely to hit break
		if (sortedParticleBoxIds[i].boxId != boxId) {
			break;
		}
		uint particleId = sortedParticleBoxIds[i].particleId;
		Particle particle = particles[particleId];

		massTotal += particle.mass;
		weightedPositionTotal += particle.position * particle.mass;
		cloudEmissionCrossSectionTotal += particle.cloudEmissionCrossSection;
		scatteranceCrossSectionTotal += particle.scatteranceCrossSection;
		absorptionCrossSectionTotal += particle.absorptionCrossSection;
		weightedColourTotal += particle.colour * particle.mass;
	}

	uvec3 boxPosition = uvec3(
		boxId % worldSizeBoxes.x,
		(boxId / worldSizeBoxes.x) % worldSizeBoxes.y,
		(boxId / worldSizeBoxes.x) / worldSizeBoxes.y
	);
	ivec3 imageCoord = ivec3(boxPosition);

	imageStore(mass, imageCoord,
		vec4(massTotal, 0.0, 0.0, 1.0)
	);
	imageStore(centreOfMass, imageCoord,
		vec4(
			massTotal > 0.0 ? weightedPositionTotal / massTotal : vec3(0.0), // Don't care value if mass is zero
			1.0
		)
	);
	imageStore(scatterance, imageCoord,
		vec4(scatteranceCrossSectionTotal / boxVolume, 0.0, 0.0, 1.0)
	);
	imageStore(absorption, imageCoord,
		vec4(absorptionCrossSectionTotal / boxVolume, 0.0, 0.0, 1.0)
	);
	imageStore(averageColour, imageCoord,
		vec4(
			massTotal > 0.0 ? weightedColourTotal / massTotal : vec3(0.0), // Don't care value if mass is zero
			1.0
		)
	);
	imageStore(emission, imageCoord,
		vec4(cloudEmissionCrossSectionTotal / boxVolume, 1.0)
	);
}
