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

struct BoxParticleDataEntry {
	float totalMass;
	vec3 centreOfMass;
	float scatterance;
	float absorption;
	vec3 averageColour;
	vec3 emission;
};

const BoxParticleDataEntry emptyBoxParticleData = BoxParticleDataEntry (
	0.0,
	vec3(0.0), // Don't care value
	0.0,
	0.0,
	vec3(0.0), // Don't care value
	vec3(0.0)
);

struct VolumetricSample {
	float scatterance;
	float absorption;
	vec3 colour;
	vec3 emission;
};
