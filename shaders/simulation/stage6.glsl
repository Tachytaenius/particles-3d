#line 1

buffer ParticlesIn {
	Particle[] particlesIn;
};
buffer ParticlesOut {
	Particle[] particlesOut;
};
uniform uint particleCount;

buffer ParticleBoxIds {
	uint[] particleBoxIds;
};

buffer SortedParticleBoxIds {
	SortedParticleBoxId[] sortedParticleBoxIds;
};

buffer BoxArrayData {
	uint[] boxArrayData;
};

uniform layout(r32f) image3D mass;
uniform layout(rgba32f) image3D centreOfMass;

uniform uvec3 worldSizeBoxes;
uniform float dt;
uniform float gravityStrength;

vec3 getAccelerationWithoutStrength(float mass, vec3 relativePosition) {
	float dist = length(relativePosition);
	if (dist == 0.0) { // >= epsilon...?
		return vec3(0.0);
	}
	vec3 direction = normalize(relativePosition);
	return direction * mass * pow(max(dist, 0.01), -2.0);
}

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint particleId = gl_GlobalInvocationID.x;
	if (particleId >= particleCount) {
		return;
	}

	Particle particle = particlesIn[particleId];
	uint particleBoxId = particleBoxIds[particleId];
	ivec3 particleBoxGridPosition = ivec3( // Signed this time
		particleBoxId % worldSizeBoxes.x,
		(particleBoxId / worldSizeBoxes.x) % worldSizeBoxes.y,
		(particleBoxId / worldSizeBoxes.x) / worldSizeBoxes.y
	);
	vec3 accelerationWithoutStrength = vec3(0.0);

	// Gravitate towards all boxes considering their particles together if far and all particles within it individually if near

	for (uint x = 0; x < worldSizeBoxes.x; x++) {
		for (uint y = 0; y < worldSizeBoxes.y; y++) {
			for (uint z = 0; z < worldSizeBoxes.z; z++) {
				ivec3 boxGridPosition = ivec3(x, y, z); // Signed this time
				ivec3 absDifference = abs(boxGridPosition - particleBoxGridPosition);
				// 3x3x3 around particle's own box
				if (absDifference.x > 1 || absDifference.y > 1 || absDifference.z > 1) {
					// Too far, just consider its overall influence
					float mass = imageLoad(mass, boxGridPosition).r;
					vec3 centreOfMass = imageLoad(centreOfMass, boxGridPosition).rgb;
					accelerationWithoutStrength += getAccelerationWithoutStrength(mass, centreOfMass - particle.position);
				} else {
					// Consider all particles within the box
					uint boxId = (boxGridPosition.z * worldSizeBoxes.y + boxGridPosition.y) * worldSizeBoxes.x + boxGridPosition.x;
					uint arrayStart = boxArrayData[boxId];
					if (arrayStart == invalidBoxArrayDatum) {
						continue;
					}
					for (uint i = arrayStart; i < particleCount; i++) { // Just to stop from going over particleCount, this is more likely to hit break
						if (sortedParticleBoxIds[i].boxId != boxId) {
							break;
						}
						uint otherParticleId = sortedParticleBoxIds[i].particleId;
						if (particleId == otherParticleId) {
							continue;
						}
						Particle otherParticle = particlesIn[otherParticleId];
						accelerationWithoutStrength += getAccelerationWithoutStrength(otherParticle.mass, otherParticle.position - particle.position);
					}
				}
			}
		}
	}

	vec3 acceleration = accelerationWithoutStrength * gravityStrength;
	particle.velocity += acceleration * dt;
	// Position is already handled

	particlesOut[particleId] = particle;
}
