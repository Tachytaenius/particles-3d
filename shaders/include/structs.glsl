#line 1

struct Particle {
	vec3 position;
	vec3 velocity;
	vec4 colour;
	float mass;
};

struct SortedParticleBoxId {
	uint boxId;
	uint particleId;
};
const uint invalidSortedParticleBoxId = 0xFFFFFFFF; // UINT32_MAX

const uint invalidBoxArrayDatum = 0xFFFFFFFF; // UINT32_MAX

struct BoxParticleDataEntry {
	float totalMass;
	vec3 centreOfMass;
};
