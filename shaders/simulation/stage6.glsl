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
uniform uint boxCount;

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
	vec3 accelerationWithoutStrength = vec3(0.0);

	// TODO: Consider individual particles in neighbouring boxes in a range

	// Gravitate towards all other boxes considering each box's particles together

	for (uint boxId = 0; boxId < boxCount; boxId++) {
		if (boxId == particleBoxId) {
			// This is the same box as the particle
			continue;
		}
		if (boxArrayData[boxId] == invalidBoxArrayDatum) {
			// This box is empty
			continue;
		}
		uvec3 boxPosition = uvec3(
			boxId % worldSizeBoxes.x,
			(boxId / worldSizeBoxes.x) % worldSizeBoxes.y,
			(boxId / worldSizeBoxes.x) / worldSizeBoxes.y
		);
		ivec3 imageCoord = ivec3(boxPosition);
		float mass = imageLoad(mass, imageCoord).r;
		vec3 centreOfMass = imageLoad(centreOfMass, imageCoord).rgb;
		accelerationWithoutStrength += getAccelerationWithoutStrength(mass, centreOfMass - particle.position);
	}

	// Gravitate towards all particles in the same box

	uint arrayStart = boxArrayData[particleBoxId];
	// Assume arrayData.start != invalidBoxArrayDatum
	for (uint i = arrayStart; i < particleCount; i++) { // Just to stop from going over particleCount, this is more likely to hit break
		if (sortedParticleBoxIds[i].boxId != particleBoxId) {
			break;
		}
		uint otherParticleId = sortedParticleBoxIds[i].particleId;
		if (particleId == otherParticleId) {
			continue;
		}
		Particle otherParticle = particlesIn[otherParticleId];
		accelerationWithoutStrength += getAccelerationWithoutStrength(otherParticle.mass, otherParticle.position - particle.position);
	}

	vec3 acceleration = accelerationWithoutStrength * gravityStrength;
	particle.velocity += acceleration * dt;
	// Position is already handled

	particlesOut[particleId] = particle;
}
