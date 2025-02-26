#line 1

readonly buffer Particles {
	Particle particles[];
};

readonly buffer ParticleDrawData {
	ParticleDrawDataEntry[] particleDrawData;
};

varying vec3 vertexColour;
varying vec3 transformedPosition;

#ifdef VERTEX

vec3 perspectiveDivide(vec4 v) {
	return v.xyz / v.w;
}

uniform float pointSize;
uniform mat4 worldToClip;

vec4 position(mat4 loveTransform, vec4 VertexPosition) {
	uint i = love_VertexID;
	Particle particle = particles[i];
	gl_PointSize = pointSize;
	vertexColour = particleDrawData[i].incomingLight;
	transformedPosition = perspectiveDivide(worldToClip * vec4(particle.position, 1.0));
	return vec4(transformedPosition, 1.0);
}

#endif

#ifdef PIXEL

vec4 effect(vec4 loveColour, sampler2D image, vec2 textureCoords, vec2 windowCoords) {
	return vec4(vertexColour, 1.0);
}

#endif
