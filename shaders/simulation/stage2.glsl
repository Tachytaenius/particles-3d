#line 1

buffer ParticleBoxIdsToSort {
	SortedParticleBoxId[] particleBoxIdsToSort;
};
uniform uint particleCount;

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	// One invocation (for now)
	// I'm tired.
	uint n = particleCount;
	bool firstRun = true;
	while (firstRun || n > 1) {
		uint newN = 0;
		for (uint i = 1; i < n; i++) {
			if (
				particleBoxIdsToSort[i - 1].boxId >
				particleBoxIdsToSort[i].boxId
			) {
				SortedParticleBoxId temp = particleBoxIdsToSort[i - 1];
				particleBoxIdsToSort[i - 1] = particleBoxIdsToSort[i];
				particleBoxIdsToSort[i] = temp;
				newN = i;
			}
		}
		n = newN;
		firstRun = false;
	}
}
