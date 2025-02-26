#line 1

buffer Particles {
	Particle[] particles;
};
uniform uint particleCount;

buffer ParticleBoxIds {
	uint[] particleBoxIds;
};

buffer ParticleBoxIdsToSort {
	SortedParticleBoxId[] particleBoxIdsToSort;
};

uniform vec3 boxSize;
uniform uvec3 worldSizeBoxes;

uniform float dt;

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint particleId = gl_GlobalInvocationID.x;
	if (particleId >= particleCount) {
		return;
	}

	Particle particle = particles[particleId];
	vec3 position = particle.position + particle.velocity * dt;
	vec3 bounceBoxReduction = boxSize / 2.0; // So that particles don't influence nonexistent boxes in coords outside of the space
	vec3 positionClamped = clamp(position, bounceBoxReduction, worldSizeBoxes * boxSize - bounceBoxReduction);
	particle.position = positionClamped;
	if (positionClamped != position) {
		vec3 normal = normalize(position - positionClamped);
		particle.velocity = reflect(particle.velocity, normal);
	}
	particles[particleId] = particle;

	uvec3 boxPosition = min(worldSizeBoxes - 1, uvec3(max(vec3(0.0), particle.position / boxSize)));
	uint boxId = (boxPosition.z * worldSizeBoxes.y + boxPosition.y) * worldSizeBoxes.x + boxPosition.x;
	particleBoxIds[particleId] = boxId;
	particleBoxIdsToSort[particleId] = SortedParticleBoxId (
		boxId,
		particleId
	);
}
