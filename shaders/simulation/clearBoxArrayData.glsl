#line 1

buffer BoxArrayData {
	uint[] boxArrayData;
};
uniform uint boxCount;

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint boxId = gl_GlobalInvocationID.x;
	if (boxId >= boxCount) {
		return;
	}

	boxArrayData[boxId] = invalidBoxArrayDatum;
}
