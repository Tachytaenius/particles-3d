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
#ifdef COLOUR_ENABLED
uniform sampler3D redTexture;
uniform sampler3D greenTexture;
uniform sampler3D blueTexture;
uniform sampler3D antiredTexture;
uniform sampler3D antigreenTexture;
uniform sampler3D antiblueTexture;
uniform sampler3D spacingTexture;
#endif

uniform uint lods;
uniform int boxRange;
uniform uvec3 worldSizeBoxes;
uniform float dt;

uniform float gravityStrength;
uniform float gravitySoftening;

uniform float electromagnetismStrength;
uniform float electromagnetismSoftening;

#ifdef COLOUR_ENABLED
uniform float colourForceStrength;
uniform float colourForcePower;
uniform float colourForceSoftening;
uniform float colourForceDistanceDivide;
uniform float spacingForceStrength;
uniform float spacingForceSoftening;
uniform float spacingForcePower;
uniform float spacingForceDistanceDivide;
#endif

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
	float forceMagnitude = -1.0 * chargeA * chargeB / (dist * dist + electromagnetismSoftening * electromagnetismSoftening);
	return direction * forceMagnitude;
}

#ifdef COLOUR_ENABLED
const int colourChargeCount = 6;
vec3 getColourForceWithoutStrength(float[colourChargeCount] chargesA, float[colourChargeCount] chargesB, vec3[colourChargeCount] relativePositions) {
	vec3 force = vec3(0.0);
	for (int i = 0; i < colourChargeCount; i++) {
		float aChargeI = chargesA[i];
		if (aChargeI == 0.0) {
			continue;
		}

		int oppositeId = (i + colourChargeCount / 2) % colourChargeCount;
		int adjacentNegId = (i - 1) % colourChargeCount;
		int adjacentPosId = (i + 1) % colourChargeCount;

		for (int j = 0; j < colourChargeCount; j++) {
			float bChargeJ = chargesB[j];
			if (bChargeJ == 0.0) {
				continue;
			}

			vec3 relativePosition = relativePositions[j];
			float dist = length(relativePosition);
			if (dist == 0.0) { // >= epsilon...?
				continue;
			}
			vec3 direction = normalize(relativePosition);

			float multiplier;
			if (j == i) {
				multiplier = -2.0;
			// } else if (j == oppositeId) {
			// 	multiplier = 1.0;
			} else if (j == adjacentNegId || j == adjacentPosId) {
				multiplier = -0.5;
			} else {
				multiplier = 1.0;
			}
			force += direction * aChargeI * bChargeJ * multiplier / (pow(dist / colourForceDistanceDivide, colourForcePower) + pow(colourForceSoftening, colourForcePower));
		}
	}
	return force;
}

vec3 getSpacingForceWithoutStrength(float chargeA, float chargeB, float massA, float massB, vec3 relativeVelocity, vec3 relativePosition) {
	float dist = length(relativePosition);
	if (dist == 0.0) { // >= epsilon...?
		return vec3(0.0);
	}
	vec3 direction = normalize(relativePosition);
	float forceMagnitude = -1.0 * chargeA * chargeB / (pow(dist / spacingForceDistanceDivide, spacingForcePower) + pow(spacingForceSoftening, spacingForcePower))
		* massA * massB
		* clamp(-dot(relativePosition, relativeVelocity), 0.0, 1.0);
	return direction * forceMagnitude;
}
#endif

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
	vec3 colourForceWithoutStrength = vec3(0.0);
	vec3 spacingForceWithoutStrength = vec3(0.0);

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
						vec4 electricChargeInfo = texelFetch(electricTexture, lodBoxPosition, int(lod));
						float electricCharge = electricChargeInfo[3];
						vec3 centreOfElectricCharge = electricChargeInfo.xyz;
						electromagnetismForceWithoutStrength += getElectromagnetismForceWithoutStrength(electricCharges[particleId], electricCharge, centreOfElectricCharge - particle.position);

#ifdef COLOUR_ENABLED
						// Colour force
						vec4 redChargeInfo = texelFetch(redTexture, lodBoxPosition, int(lod));
						vec4 greenChargeInfo = texelFetch(greenTexture, lodBoxPosition, int(lod));
						vec4 blueChargeInfo = texelFetch(blueTexture, lodBoxPosition, int(lod));
						vec4 antiredChargeInfo = texelFetch(antiredTexture, lodBoxPosition, int(lod));
						vec4 antigreenChargeInfo = texelFetch(antigreenTexture, lodBoxPosition, int(lod));
						vec4 antiblueChargeInfo = texelFetch(antiblueTexture, lodBoxPosition, int(lod));
						colourForceWithoutStrength += getColourForceWithoutStrength(
							float[](
								redCharges[particleId],
								antiblueCharges[particleId],
								greenCharges[particleId],
								antiredCharges[particleId],
								blueCharges[particleId],
								antigreenCharges[particleId]
							),
							float[](
								redChargeInfo[3],
								antiblueChargeInfo[3],
								greenChargeInfo[3],
								antiredChargeInfo[3],
								blueChargeInfo[3],
								antigreenChargeInfo[3]
							),
							vec3[](
								redChargeInfo.xyz - particle.position,
								antiblueChargeInfo.xyz - particle.position,
								greenChargeInfo.xyz - particle.position,
								antiredChargeInfo.xyz - particle.position,
								blueChargeInfo.xyz - particle.position,
								antigreenChargeInfo.xyz - particle.position
							)
						);

						// Spacing force is too short range to need calculation here,
						// and I'm not sure how I'd get its use of velocity to work either!
						// If it's possible, it'd be very cool to understand.
#endif
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
						vec3 relativePosition = otherParticle.position - particle.position;

						// Gravity
						gravityAccelerationWithoutStrength += getGravityAccelerationWithoutStrength(massCharges[otherParticleId], relativePosition);

						// Electromagnetism
						electromagnetismForceWithoutStrength += getElectromagnetismForceWithoutStrength(electricCharges[particleId], electricCharges[otherParticleId], relativePosition);

#ifdef COLOUR_ENABLED
						// Colour force
						colourForceWithoutStrength += getColourForceWithoutStrength(
							float[](
								redCharges[particleId],
								antiblueCharges[particleId],
								greenCharges[particleId],
								antiredCharges[particleId],
								blueCharges[particleId],
								antigreenCharges[particleId]
							),
							float[](
								redCharges[otherParticleId],
								antiblueCharges[otherParticleId],
								greenCharges[otherParticleId],
								antiredCharges[otherParticleId],
								blueCharges[otherParticleId],
								antigreenCharges[otherParticleId]
							),
							vec3[](
								relativePosition,
								relativePosition,
								relativePosition,
								relativePosition,
								relativePosition,
								relativePosition
							)
						);

						// Spacing force
						spacingForceWithoutStrength += getSpacingForceWithoutStrength(
							spacingCharges[particleId], spacingCharges[otherParticleId],
							massCharges[particleId], massCharges[otherParticleId],
							otherParticle.velocity - particle.velocity,
							relativePosition
						);
#endif
					}
				}
			}
		}
	}

	vec3 acceleration = vec3(0.0);
	float mass = massCharges[particleId];
	acceleration += gravityAccelerationWithoutStrength * gravityStrength;
	acceleration += electromagnetismForceWithoutStrength * electromagnetismStrength / mass;
#ifdef COLOUR_ENABLED
	acceleration += colourForceWithoutStrength * colourForceStrength / mass;
	acceleration += spacingForceWithoutStrength * spacingForceStrength / mass;
#endif
	particle.velocity += acceleration * dt;
	// Position is already handled

	particlesOut[particleId] = particle;
}
