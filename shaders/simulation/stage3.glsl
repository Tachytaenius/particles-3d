#line 1

buffer SortedParticleBoxIds {
	SortedParticleBoxId[] sortedParticleBoxIds;
};
uniform uint particleCount;

buffer BoxArrayData {
	BoxArrayEntry[] boxArrayData;
};
uniform uint boxCount;

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	// One invocation (for now)

	uint lastSeenBoxId = invalidBoxArrayDatum;
	uint currentBoxStart;
	uint currentBoxLength;

	for (uint i = 0; i < particleCount; i++) {
		uint arrayBoxId = sortedParticleBoxIds[i].boxId;
		if (lastSeenBoxId == arrayBoxId) {
			currentBoxLength++;
		} else {
			uint zeroingStart;
			if (lastSeenBoxId != invalidBoxArrayDatum) {
				// Record the box we were counting
				boxArrayData[lastSeenBoxId] = BoxArrayEntry (currentBoxStart, currentBoxLength);
				zeroingStart = lastSeenBoxId + 1;
			} else {
				// Start zeroing on box id 0 if no boxes have been seen yet
				zeroingStart = 0;
			}
			for (uint boxIdToZero = zeroingStart; boxIdToZero < arrayBoxId; boxIdToZero++) {
				boxArrayData[boxIdToZero] = BoxArrayEntry (invalidBoxArrayDatum, 0);
			}
			lastSeenBoxId = arrayBoxId;
			currentBoxStart = i;
			currentBoxLength = 1;
		}
	}

	// Zero all remaining boxes and record current box if any seen
	uint zeroingStart;
	if (lastSeenBoxId != invalidBoxArrayDatum) {
		// Record the box we were counting
		boxArrayData[lastSeenBoxId] = BoxArrayEntry (currentBoxStart, currentBoxLength);
		zeroingStart = lastSeenBoxId + 1;
	} else {
		// Start zeroing on box id 0 if no boxes have been seen yet
		zeroingStart = 0;
	}
	for (uint boxIdToZero = zeroingStart; boxIdToZero < boxCount; boxIdToZero++) {
		boxArrayData[boxIdToZero] = BoxArrayEntry (invalidBoxArrayDatum, 0);
	}
}
