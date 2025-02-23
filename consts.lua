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

consts.boxWidth = 8
consts.boxHeight = 8
consts.boxDepth = 8

consts.worldWidthBoxes = 64
consts.worldHeightBoxes = 64
consts.worldDepthBoxes = 64

-- Derived
consts.boxCount = consts.worldWidthBoxes * consts.worldHeightBoxes * consts.worldDepthBoxes
consts.boxSize = vec3(consts.boxWidth, consts.boxHeight, consts.boxDepth)
consts.worldSizeBoxes = vec3(consts.worldWidthBoxes, consts.worldHeightBoxes, consts.worldDepthBoxes)
consts.worldSize = consts.boxSize * consts.worldSizeBoxes

consts.particleCount = 1000
consts.startPositionRadius = 32
consts.startNoiseFrequency = 0.0001
consts.startNoiseAmplitude = 0
consts.startVelocityRadius = 0

consts.gravityStrength = 1 -- Gravitational constant

return consts
