local vec3 = require("lib.mathsies").vec3

local consts = {}

consts.tau = math.pi * 2

consts.particleFormat = {
	{name = "position", format = "floatvec3"},
	{name = "velocity", format = "floatvec3"},
	{name = "colour", format = "floatvec3"},
	{name = "emissionCrossSection", format = "floatvec3"},
	{name = "scatteranceCrossSection", format = "float"},
	{name = "absorptionCrossSection", format = "float"},
	{name = "mass", format = "float"}
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

consts.boxParticleDataFormat = {
	{name = "totalMass", format = "float"},
	{name = "centreOfMass", format = "floatvec3"},
	{name = "scatterance", format = "float"},
	{name = "absorption", format = "float"},
	{name = "averageColour", format = "floatvec3"},
	{name = "emission", format = "floatvec3"}
}

consts.boxWidth = 16
consts.boxHeight = 16
consts.boxDepth = 16

consts.worldWidthBoxes = 32
consts.worldHeightBoxes = 32
consts.worldDepthBoxes = 32

-- Derived
consts.boxCount = consts.worldWidthBoxes * consts.worldHeightBoxes * consts.worldDepthBoxes
consts.boxSize = vec3(consts.boxWidth, consts.boxHeight, consts.boxDepth)
consts.worldSizeBoxes = vec3(consts.worldWidthBoxes, consts.worldHeightBoxes, consts.worldDepthBoxes)
consts.worldSize = consts.boxSize * consts.worldSizeBoxes

consts.particleCount = 10000
consts.startNoiseFrequency = 10
consts.startNoiseAmplitude = 8
consts.startVelocityRadius = 0.01

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
