#line 1

buffer SortedParticleBoxIds {
	SortedParticleBoxId[] sortedParticleBoxIds;
};
uniform uint particleCount;

buffer BoxArrayData {
	uint[] boxArrayData;
};

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	if (gl_GlobalInvocationID.x >= particleCount) {
		return;
	}

	uint boxId = sortedParticleBoxIds[gl_GlobalInvocationID.x].boxId;

	atomicMin(boxArrayData[boxId], gl_GlobalInvocationID.x);
}
