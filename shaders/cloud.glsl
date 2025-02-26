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

uniform vec3 cameraPosition;
uniform float rayStepSize;
uniform uint rayStepCount;

uniform vec3 worldSize;

uniform sampler3D scatterance;
uniform sampler3D absorption;
uniform sampler3D averageColour;
uniform sampler3D emission;

struct VolumetricSample {
	float scatterance;
	float absorption;
	vec3 colour;
	vec3 emission;
};

VolumetricSample sampleVolumetrics(vec3 position) {
	vec3 textureCoords = position / worldSize;
	return VolumetricSample (
		Texel(scatterance, textureCoords).r,
		Texel(absorption, textureCoords).r,
		Texel(averageColour, textureCoords).rgb,
		Texel(emission, textureCoords).rgb
	);
}

vec3 getRayColour(vec3 rayPosition, vec3 rayDirection) {
	vec3 totalRayLight = vec3(0.0);
	float totalTransmittance = 1.0;
	for (uint rayStep = 0; rayStep < rayStepCount; rayStep++) {
		float t = rayStepSize * float(rayStep);
		vec3 currentPosition = rayPosition + rayDirection * t;

		VolumetricSample volumetricSample = sampleVolumetrics(currentPosition);

		float extinction = volumetricSample.absorption + volumetricSample.scatterance;

		float transmittanceThisStep = exp(-extinction * rayStepSize);
		vec3 incomingLight = vec3(0.0); // TODO
		vec3 rayLightThisStep = rayStepSize * (volumetricSample.emission + volumetricSample.colour * volumetricSample.scatterance * incomingLight);

		totalRayLight *= transmittanceThisStep;
		totalRayLight += rayLightThisStep;
		totalTransmittance *= transmittanceThisStep;
	}
	return totalRayLight;
}

vec4 effect(vec4 loveColour, sampler2D image, vec2 textureCoords, vec2 windowCoords) {
	vec3 direction = normalize(directionPreNormalise);
	vec3 outColour = getRayColour(cameraPosition, direction);
	return vec4(outColour, 1.0);
}

#endif
