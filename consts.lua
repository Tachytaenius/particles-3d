local vec3 = require("lib.mathsies").vec3

local consts = {}

consts.tau = math.pi * 2

consts.particleFormat = {
	{name = "position", format = "floatvec3"},
	{name = "velocity", format = "floatvec3"},
	{name = "colour", format = "floatvec4"},
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
	{name = "centreOfMass", format = "floatvec3"}
}

consts.view2DMeshFormat = {
	{name = "VertexPosition", location = 0, format = "float"} -- Dummy
}

consts.boxWidth = 32
consts.boxHeight = 32
consts.boxDepth = 32

consts.worldWidthBoxes = 16
consts.worldHeightBoxes = 16
consts.worldDepthBoxes = 16

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

return consts
