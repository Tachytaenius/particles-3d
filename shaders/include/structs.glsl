#line 1

struct Particle {
	vec3 position;
	vec3 velocity;
	vec3 colour;
	vec3 cloudEmissionCrossSection;
	float scatteranceCrossSection;
	float absorptionCrossSection;
	float mass;
	vec3 luminousFlux;
};

struct SortedParticleBoxId {
	uint boxId;
	uint particleId;
};
const uint invalidSortedParticleBoxId = 0xFFFFFFFF; // UINT32_MAX

const uint invalidBoxArrayDatum = 0xFFFFFFFF; // UINT32_MAX

struct ParticleDrawDataEntry {
	vec3 direction;
	vec3 incomingLight;
};
