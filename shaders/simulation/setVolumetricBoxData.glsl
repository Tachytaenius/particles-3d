#line 1

buffer Particles {
	Particle[] particles;
};
uniform uint particleCount;

readonly buffer MassCharges {
	float[] massCharges;
};

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

uniform layout(r16f) image3D scatterance;
uniform layout(r16f) image3D absorption;
uniform layout(r11f_g11f_b10f) image3D averageColour;
uniform layout(r11f_g11f_b10f) image3D emission;

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

	float scatteranceCrossSectionTotal = 0.0;
	float absorptionCrossSectionTotal = 0.0;
	vec3 cloudEmissionCrossSectionTotal = vec3(0.0);
	vec3 weightedColourTotal = vec3(0.0);
	float weightedColourWeightTotal = 0.0;

	// Get particles in boxes around main box and add them to the cloud data
	for (int x = -1; x <= 1; x++) {
		if (x == -1 && mainBoxGridPosition.x == 0 || x == 1 && mainBoxGridPosition.x == worldSizeBoxes.x - 1) {
			continue;
		}
		for (int y = -1; y <= 1; y++) {
			if (y == -1 && mainBoxGridPosition.y == 0 || y == 1 && mainBoxGridPosition.y == worldSizeBoxes.y - 1) {
				continue;
			}
			for (int z = -1; z <= 1; z++) {
				if (z == -1 && mainBoxGridPosition.z == 0 || z == 1 && mainBoxGridPosition.z == worldSizeBoxes.z - 1) {
					continue;
				}
				uvec3 boxGridPostion = uvec3(ivec3(mainBoxGridPosition) + ivec3(x, y, z));
				uint boxId = (boxGridPostion.z * worldSizeBoxes.y + boxGridPostion.y) * worldSizeBoxes.x + boxGridPostion.x;
				uint boxArrayStart = boxArrayData[boxId];
				for (uint i = boxArrayStart; i < particleCount; i++) {
					if (sortedParticleBoxIds[i].boxId != boxId) {
						break;
					}
					uint particleId = sortedParticleBoxIds[i].particleId;
					Particle particle = particles[particleId];

					vec3 v = 1.0 - abs(particle.position - mainBoxCentre) / boxSize;
					if (v.x <= 0.0 || v.y <= 0.0 || v.z <= 0.0) {
						continue;
					}
					float influence = v.x * v.y * v.z;

					cloudEmissionCrossSectionTotal += particle.cloudEmissionCrossSection * influence;
					scatteranceCrossSectionTotal += particle.scatteranceCrossSection * influence;
					absorptionCrossSectionTotal += particle.absorptionCrossSection * influence;
					weightedColourTotal += particle.colour * massCharges[particleId] * influence;
					weightedColourWeightTotal += massCharges[particleId] * influence;
				}
			}
		}
	}

	ivec3 imageCoord = ivec3(mainBoxGridPosition);
	imageStore(scatterance, imageCoord,
		vec4(scatteranceCrossSectionTotal / boxVolume, 0.0, 0.0, 1.0)
	);
	imageStore(absorption, imageCoord,
		vec4(absorptionCrossSectionTotal / boxVolume, 0.0, 0.0, 1.0)
	);
	imageStore(averageColour, imageCoord,
		vec4(
			weightedColourWeightTotal > 0.0 ? weightedColourTotal / weightedColourWeightTotal : vec3(0.0), // Don't care value if colour weight (including neighbouring boxes) is zero
			1.0
		)
	);
	imageStore(emission, imageCoord,
		vec4(cloudEmissionCrossSectionTotal / boxVolume, 1.0)
	);
}
