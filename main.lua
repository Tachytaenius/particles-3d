local util = require("util")
util.load()

local mathsies = require("lib.mathsies")
local vec3 = mathsies.vec3
local quat = mathsies.quat
local mat4 = mathsies.mat4

local consts = require("consts")

local stage1Shader
local stage2Shader
local stage3Shader
local stage4Shader
local stage5Shader
local stage6Shader

local view2DShader
local view2DMesh

local particleBufferA, particleBufferB
local particleBoxIds, sortedParticleBoxIds
local boxArrayData, boxParticleData

function love.load()
	-- TODO: Remove readback

	particleBufferA = love.graphics.newBuffer(consts.particleFormat, consts.particleCount, {
		shaderstorage = true,
		debugname = "Particles A"
	})
	particleBufferB = love.graphics.newBuffer(consts.particleFormat, consts.particleCount, {
		shaderstorage = true,
		debugname = "Particles B"
	})

	particleBoxIds = love.graphics.newBuffer(consts.particleBoxIdFormat, consts.particleCount, {
		shaderstorage = true,
		debugname = "Particle Box IDs"
	})
	sortedParticleBoxIds = love.graphics.newBuffer(consts.sortedParticleBoxIdFormat, consts.sortedParticleBoxIdBufferSize, {
		shaderstorage = true,
		debugname = "Sorted Particle Box IDs"
	})

	boxArrayData = love.graphics.newBuffer(consts.boxArrayEntryFormat, consts.boxCount, {
		shaderstorage = true,
		debugname = "Box Array Data"
	})
	boxParticleData = love.graphics.newBuffer(consts.boxParticleDataFormat, consts.boxCount, {
		shaderstorage = true,
		debugname = "Box Particle Data"
	})

	local function stage(number)
		return love.graphics.newComputeShader(
			love.filesystem.read("shaders/include/structs.glsl") ..
			love.filesystem.read("shaders/simulation/stage" .. number .. ".glsl")
		)
	end
	stage1Shader = stage(1)
	stage2Shader = stage(2)
	stage3Shader = stage(3)
	stage4Shader = stage(4)
	stage5Shader = stage(5)
	stage6Shader = stage(6)

	view2DShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		love.filesystem.read("shaders/include/structs.glsl") ..
		love.filesystem.read("shaders/view2D.glsl")
	)

	view2DMesh = love.graphics.newMesh(consts.view2DMeshFormat, consts.particleCount, "points")

	local particleData = {}
	for i = 1, consts.particleCount do
		local position = (love.math.random() < 0.4 and vec3(consts.startPositionRadius) or (consts.worldSize - consts.startPositionRadius)) + util.randomInSphereVolume(consts.startPositionRadius)
		local function axis(w)
			return (love.math.simplexNoise(
				position.x * consts.startNoiseFrequency,
				position.y * consts.startNoiseFrequency,
				position.z * consts.startNoiseFrequency,
				w
			) * 2 - 1) * consts.startNoiseAmplitude
		end
		local noise = vec3(axis(0), axis(2), axis(4))
		position = position + noise

		local velocity = util.randomInSphereVolume(consts.startVelocityRadius)

		local colour = {1, 1, 1, 0.5}

		local mass = 2

		particleData[i] = {
			position.x, position.y, position.z,
			velocity.x, velocity.y, velocity.z,
			colour[1], colour[2], colour[3], colour[4],
			mass
		}
	end
	particleBufferB:setArrayData(particleData) -- Gets swapped immediately
end

function love.update(dt)
	particleBufferA, particleBufferB = particleBufferB, particleBufferA

	stage1Shader:send("particleCount", consts.particleCount) -- In
	stage1Shader:send("dt", dt) -- In
	stage1Shader:send("boxSize", {consts.boxWidth, consts.boxHeight, consts.boxDepth})
	stage1Shader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)})
	stage1Shader:send("Particles", particleBufferA) -- In/out
	stage1Shader:send("ParticleBoxIds", particleBoxIds) -- Out
	stage1Shader:send("ParticleBoxIdsToSort", sortedParticleBoxIds) -- Out
	love.graphics.dispatchThreadgroups(stage1Shader,
		math.ceil(consts.particleCount / stage1Shader:getLocalThreadgroupSize())
	)

	stage2Shader:send("ParticleBoxIdsToSort", sortedParticleBoxIds) -- In/out
	-- love.graphics.dispatchThreadgroups(stage2Shader, )
	local level = 2
	while level < consts.sortedParticleBoxIdBufferSize do
		stage2Shader:send("level", level) -- In
		local stage = math.floor(level / 2) -- Within stage 2
		while stage > 0 do
			stage2Shader:send("stage", stage) -- In
			love.graphics.dispatchThreadgroups(stage2Shader,
				math.ceil(
					math.floor(consts.sortedParticleBoxIdBufferSize / 2) /
					stage2Shader:getLocalThreadgroupSize()
				)
			)
			stage = math.floor(stage / 2)
		end
		level = level * 2
	end

	stage3Shader:send("boxCount", consts.boxCount) -- In
	stage3Shader:send("BoxArrayData", boxArrayData) -- Out
	love.graphics.dispatchThreadgroups(stage3Shader,
		math.ceil(consts.boxCount / stage3Shader:getLocalThreadgroupSize())
	)

	stage4Shader:send("SortedParticleBoxIds", sortedParticleBoxIds) -- In
	stage4Shader:send("particleCount", consts.particleCount) -- In
	stage4Shader:send("BoxArrayData", boxArrayData) -- Out
	love.graphics.dispatchThreadgroups(stage4Shader,
		math.ceil(consts.particleCount / stage4Shader:getLocalThreadgroupSize())
	)

	stage5Shader:send("SortedParticleBoxIds", sortedParticleBoxIds) -- In
	stage5Shader:send("BoxArrayData", boxArrayData) -- In
	stage5Shader:send("Particles", particleBufferA) -- In
	stage5Shader:send("particleCount", consts.particleCount) -- In
	stage5Shader:send("boxCount", consts.boxCount) -- In
	stage5Shader:send("BoxParticleData", boxParticleData) -- Out
	love.graphics.dispatchThreadgroups(stage5Shader,
		math.ceil(consts.boxCount / stage5Shader:getLocalThreadgroupSize())
	)

	stage6Shader:send("particleCount", consts.particleCount) -- In
	stage6Shader:send("ParticlesIn", particleBufferA) -- In
	stage6Shader:send("gravityStrength", consts.gravityStrength) -- In
	stage6Shader:send("dt", dt) -- In
	stage6Shader:send("ParticleBoxIds", particleBoxIds) -- In
	stage6Shader:send("SortedParticleBoxIds", sortedParticleBoxIds) -- In
	stage6Shader:send("BoxArrayData", boxArrayData) -- In
	stage6Shader:send("BoxParticleData", boxParticleData) -- In
	-- stage6Shader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)})
	stage6Shader:send("boxCount", consts.boxCount)
	stage6Shader:send("ParticlesOut", particleBufferB) -- Out
	love.graphics.dispatchThreadgroups(stage6Shader,
		math.ceil(consts.particleCount / stage6Shader:getLocalThreadgroupSize())
	)
end

function love.draw()
	love.graphics.setShader(view2DShader)
	view2DShader:send("Particles", particleBufferB)
	love.graphics.translate(love.graphics.getWidth() / 2 - consts.worldSize.x / 2, love.graphics.getHeight() / 2 - consts.worldSize.y / 2)
	love.graphics.draw(view2DMesh)
	love.graphics.setShader()
	love.graphics.rectangle("line", 0, 0, consts.worldSize.x, consts.worldSize.y)

	love.graphics.origin()
	love.graphics.print(love.timer.getFPS())
end
