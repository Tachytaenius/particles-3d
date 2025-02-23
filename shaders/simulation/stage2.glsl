#line 1

uniform uint level;
uniform uint stage;

buffer ParticleBoxIdsToSort {
	SortedParticleBoxId[] particleBoxIdsToSort;
};

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint a = (gl_GlobalInvocationID.x / stage) * (stage * 2) + gl_GlobalInvocationID.x % stage;
	uint b = a ^ stage;
	SortedParticleBoxId arrayA = particleBoxIdsToSort[a];
	SortedParticleBoxId arrayB = particleBoxIdsToSort[b];

	if ((a & level) == 0) {
		if (arrayA.boxId > arrayB.boxId) {
			particleBoxIdsToSort[a] = arrayB;
			particleBoxIdsToSort[b] = arrayA;
		}
	} else {
		if (arrayA.boxId < arrayB.boxId) {
			particleBoxIdsToSort[a] = arrayB;
			particleBoxIdsToSort[b] = arrayA;
		}
	}
}
