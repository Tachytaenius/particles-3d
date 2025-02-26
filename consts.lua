local vec3 = require("lib.mathsies").vec3

local consts = {}

consts.tau = math.pi * 2

consts.particleFormat = {
	{name = "position", format = "floatvec3"},
	{name = "velocity", format = "floatvec3"},
	{name = "colour", format = "floatvec3"},
	{name = "cloudEmissionCrossSection", format = "floatvec3"},
	{name = "scatteranceCrossSection", format = "float"},
	{name = "absorptionCrossSection", format = "float"},
	{name = "mass", format = "float"},
	{name = "luminousFlux", format = "floatvec3"}
}

consts.particleBoxIdFormat = {
	{name = "boxId", format = "uint32"}
}

consts.sortedParticleBoxIdFormat = {
	{name = "boxId", format = "uint32"},
	{name = "particleId", format = "uint32"}
}

consts.boxArrayEntryFormat = {
	{name = "start", format = "uint32"}
}

consts.particleDrawDataFormat = {
	{name = "direction", format = "floatvec3"},
	{name = "incomingLight", format = "floatvec3"}
}

consts.particleMeshFormat = {
	{name = "VertexPosition", location = 0, format = "float"} -- Dummy
}

consts.diskMeshFormat = {
	{name = "VertexPosition", location = 0, format = "floatvec2"},
	{name = "VertexFade", location = 1, format = "float"}
}

consts.boxWidth = 8
consts.boxHeight = 8
consts.boxDepth = 8

consts.worldWidthBoxes = 32
consts.worldHeightBoxes = 32
consts.worldDepthBoxes = 32

-- Derived
consts.boxCount = consts.worldWidthBoxes * consts.worldHeightBoxes * consts.worldDepthBoxes
consts.boxSize = vec3(consts.boxWidth, consts.boxHeight, consts.boxDepth)
consts.worldSizeBoxes = vec3(consts.worldWidthBoxes, consts.worldHeightBoxes, consts.worldDepthBoxes)
consts.worldSize = consts.boxSize * consts.worldSizeBoxes

consts.particleCount = 5000
consts.startNoiseFrequency = 1/50
consts.startNoiseAmplitude = 50
consts.startVelocityRadius = 0.01

consts.boxParticleDataCanvasFilter = "linear"
consts.rayStepSize = 6
consts.rayStepCount = 160
consts.extinctionRayStepCount = 100

consts.starDrawType = "disks" -- "points" or "disks"
consts.starDiskVertices = 8
consts.starDiskFadePower = 4
consts.starDiskAngularRadius = 0.005
consts.pointShaderPointSize = 2 -- TODO: Make this be a good fit derived from starDiskAngularRadius

-- Derived
consts.starDiskSolidAngle = consts.tau * (1 - math.cos(consts.starDiskAngularRadius))

consts.gravityStrength = 1 -- Gravitational constant

local function nextPowerOfTwo(x)
	local ret = 1
	while ret < x do
		ret = ret * 2
	end
	return ret
end
-- Derived
consts.sortedParticleBoxIdBufferSize = nextPowerOfTwo(consts.particleCount)

consts.rightVector = vec3(1, 0, 0)
consts.upVector = vec3(0, 1, 0)
consts.forwardVector = vec3(0, 0, 1)

consts.controls = {
	moveRight = "d",
	moveLeft = "a",
	moveUp = "e",
	moveDown = "q",
	moveForwards = "w",
	moveBackwards = "s",

	pitchDown = "k",
	pitchUp = "i",
	yawRight = "l",
	yawLeft = "j",
	rollAnticlockwise = "u",
	rollClockwise = "o"
}

return consts
