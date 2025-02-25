#line 1

struct Particle {
	vec3 position;
	vec3 velocity;
	vec3 colour;
	vec3 emissionCrossSection;
	float scatteranceCrossSection;
	float absorptionCrossSection;
	float mass;
};

struct SortedParticleBoxId {
	uint boxId;
	uint particleId;
};
const uint invalidSortedParticleBoxId = 0xFFFFFFFF; // UINT32_MAX

const uint invalidBoxArrayDatum = 0xFFFFFFFF; // UINT32_MAX

struct VolumetricSample {
	float scatterance;
	float absorption;
	vec3 colour;
	vec3 emission;
};
