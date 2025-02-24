#line 1

varying vec3 directionPreNormalise;

#ifdef VERTEX

uniform mat4 clipToSky;

vec4 position(mat4 loveTransform, vec4 vertexPosition) {
	directionPreNormalise = (
		clipToSky * vec4(
			(VertexTexCoord.xy * 2.0 - 1.0) * vec2(1.0, -1.0),
			-1.0,
			1.0
		)
	).xyz;
	return loveTransform * vertexPosition;
}

#endif

#ifdef PIXEL

readonly buffer BoxParticleData {
	BoxParticleDataEntry[] boxParticleData;
};

readonly buffer BoxArrayData {
	uint[] boxArrayData;
};

uniform vec3 cameraPosition;
uniform vec3 boxSize;
uniform uvec3 worldSizeBoxes;

uniform float rayStepSize;
uniform uint rayStepCount;

const float colourMultiplier = 5.0;

vec3 getRayColour(vec3 rayPosition, vec3 rayDirection) {
	vec3 outColour = vec3(0.0);
	for (uint rayStep = 0; rayStep < rayStepCount; rayStep++) {
		float t = rayStepSize * float(rayStep);
		vec3 currentPosition = rayPosition + rayDirection * t;
		if (currentPosition.x < 0.0 || currentPosition.y < 0.0 || currentPosition.z < 0.0) {
			continue;
		}
		uvec3 boxCoords = uvec3(currentPosition / boxSize);
		if (boxCoords.x >= worldSizeBoxes.x || boxCoords.y >= worldSizeBoxes.y || boxCoords.z >= worldSizeBoxes.z) {
			continue;
		}
		uint boxId =
			boxCoords.x * worldSizeBoxes.x * worldSizeBoxes.y +
			boxCoords.y * worldSizeBoxes.y +
			boxCoords.z;
		if (boxArrayData[boxId] == invalidBoxArrayDatum) {
			continue; // Empty box, its data may be wrong
		}
		float density = boxParticleData[boxId].totalMass / (boxSize.x * boxSize.y * boxSize.z);
		outColour += rayStepSize * density * colourMultiplier;
	}
	return outColour;
}

vec4 effect(vec4 loveColour, sampler2D image, vec2 textureCoords, vec2 windowCoords) {
	vec3 direction = normalize(directionPreNormalise);
	vec3 outColour = getRayColour(cameraPosition, direction);
	return vec4(outColour, 1.0);
}

#endif
