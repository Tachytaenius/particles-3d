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

uniform sampler3D massTexture;
uniform sampler3D electricTexture;

uniform uint lods;
uniform int boxRange;
uniform uvec3 worldSizeBoxes;
uniform float dt;

uniform float gravityStrength;
uniform float gravitySoftening;

uniform float electromagnetismStrength;
uniform float electromagnetismSoftening;

vec3 getGravityAccelerationWithoutStrength(float mass, vec3 relativePosition) {
	float dist = length(relativePosition);
	if (dist == 0.0) { // >= epsilon...?
		return vec3(0.0);
	}
	vec3 direction = normalize(relativePosition);
	float forceMagnitude = mass / (dist * dist + gravitySoftening * gravitySoftening);
	return direction * forceMagnitude;
}

vec3 getElectromagnetismForceWithoutStrength(float chargeA, float chargeB, vec3 relativePosition) {
	float dist = length(relativePosition);
	if (dist == 0.0) { // >= epsilon...?
		return vec3(0.0);
	}
	vec3 direction = normalize(relativePosition);
	float forceMagnitude = chargeA * chargeB * (dist * dist + electromagnetismSoftening * electromagnetismSoftening);
	return direction * forceMagnitude;
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

	vec3 gravityAccelerationWithoutStrength = vec3(0.0);
	vec3 electromagnetismForceWithoutStrength = vec3(0.0);

	// Iterate with increasing detail (lod 0 is highest detail)
	// Expects a cube world with the side length being a power of two

	uint leastDetailedLod = lods - 1; // Starting lod
	// Ends are exclusive
	uvec3 nextLodStart = uvec3(0);
	uvec3 nextLodEnd = uvec3(1); // Should be worldSizeBoxes >> leastDetailedLod;
	for (uint lod = lods; lod-- > 0;) { // lods - 1 inclusive to 0 inclusive, because unsigned
		ivec3 particleBoxGridPositionThisLod = particleBoxGridPosition >> lod;
		uvec3 thisLodStart = nextLodStart;
		uvec3 thisLodEnd = nextLodEnd;

		// Initialise to values that will allow anything
		// I'm not sure I'm supposed to use inf and -inf in a shader
		nextLodStart = worldSizeBoxes; // Just use lod 0's size
		nextLodEnd = uvec3(0);

		for (uint x = thisLodStart.x; x < thisLodEnd.x; x++) {
			for (uint y = thisLodStart.y; y < thisLodEnd.y; y++) {
				for (uint z = thisLodStart.z; z < thisLodEnd.z; z++) {
					ivec3 lodBoxPosition = ivec3(x, y, z);

					ivec3 absDelta = abs(lodBoxPosition - particleBoxGridPositionThisLod);
					if (
						absDelta.x <= boxRange &&
						absDelta.y <= boxRange &&
						absDelta.z <= boxRange
					) {
						// Leave this box to other lods
						nextLodStart = min(nextLodStart, lodBoxPosition * 2);
						nextLodEnd = max(nextLodEnd, (lodBoxPosition + 1) * 2);
					} else {
						// Accelerate to this box at current lod

						// Gravity
						vec4 massInfo = texelFetch(massTexture, lodBoxPosition, int(lod));
						float mass = massInfo[3];
						vec3 centreOfMass = massInfo.xyz;
						gravityAccelerationWithoutStrength += getGravityAccelerationWithoutStrength(mass, centreOfMass - particle.position);

						// Electromagnetism
						vec4 chargeInfo = texelFetch(electricTexture, lodBoxPosition, int(lod));
						float electricCharge = chargeInfo[3];
						vec3 centreOfCharge = chargeInfo.xyz;
						electromagnetismForceWithoutStrength += getElectromagnetismForceWithoutStrength(electricCharges[particleId], electricCharge, centreOfCharge - particle.position);
					}
				}
			}
		}
	}

	// Lod 0 should have not iterated over the boxes within range of the particle's box. We will iterate over all the (other) particles in those boxes now
	for (int x = -boxRange; x <= boxRange; x++) {
		for (int y = -boxRange; y <= boxRange; y++) {
			for (int z = -boxRange; z <= boxRange; z++) {
				ivec3 boxGridPosition = particleBoxGridPosition + ivec3(x, y, z);
				if (
					0 <= boxGridPosition.x && boxGridPosition.x < worldSizeBoxes.x &&
					0 <= boxGridPosition.y && boxGridPosition.y < worldSizeBoxes.y &&
					0 <= boxGridPosition.z && boxGridPosition.z < worldSizeBoxes.z
				) {
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

						// Gravity
						gravityAccelerationWithoutStrength += getGravityAccelerationWithoutStrength(massCharges[otherParticleId], otherParticle.position - particle.position);

						// Electromagnetism
						electromagnetismForceWithoutStrength += getElectromagnetismForceWithoutStrength(electricCharges[particleId], electricCharges[otherParticleId], otherParticle.position - particle.position);
					}
				}
			}
		}
	}

	vec3 acceleration = vec3(0.0);
	acceleration += gravityAccelerationWithoutStrength * gravityStrength;
	acceleration += electromagnetismForceWithoutStrength * electromagnetismStrength / massCharges[particleId];
	particle.velocity += acceleration * dt;
	// Position is already handled

	particlesOut[particleId] = particle;
}
