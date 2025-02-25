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

local viewShader
local dummyTexture
local outputCanvas
local camera

local particleBufferA, particleBufferB
local particleBoxIds, sortedParticleBoxIds
local boxArrayData, boxParticleData

function love.load()
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

	local structsCode = love.filesystem.read("shaders/include/structs.glsl")

	local function stage(number)
		return love.graphics.newComputeShader(
			structsCode ..
			love.filesystem.read("shaders/simulation/stage" .. number .. ".glsl")
		)
	end
	stage1Shader = stage(1)
	stage2Shader = stage(2)
	stage3Shader = stage(3)
	stage4Shader = stage(4)
	stage5Shader = stage(5)
	stage6Shader = stage(6)

	local trilinearCode = love.filesystem.read("shaders/include/trilinearMix.glsl")
	local function trilinearCodeType(typeName)
		return
			"#define TYPE " .. typeName .. "\n" ..
			trilinearCode ..
			"#undef TYPE\n"
	end

	viewShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		structsCode ..
		trilinearCodeType("float") ..
		trilinearCodeType("vec3") ..
		love.filesystem.read("shaders/view.glsl")
	)

	dummyTexture = love.graphics.newImage(love.image.newImageData(1, 1))

	outputCanvas = love.graphics.newCanvas(love.graphics.getDimensions())

	local particleData = {}
	for i = 1, consts.particleCount do
		local position = vec3(love.math.random(), love.math.random(), love.math.random()) * consts.worldSize
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

		local function colourChannel()
			return love.math.random()
		end
		local colour = {colourChannel(), colourChannel(), colourChannel()}

		local mass = love.math.random() ^ 5 * 8

		local function emissionChannel()
			return love.math.random() * 32
		end
		local emissionCrossSection = {emissionChannel(), emissionChannel(), emissionChannel()} -- Linear space

		local scatteranceCrossSection = love.math.random() * 5
		local absorptionCrossSection = love.math.random() * 2

		particleData[i] = {
			position.x, position.y, position.z,
			velocity.x, velocity.y, velocity.z,
			colour[1], colour[2], colour[3],
			emissionCrossSection[1], emissionCrossSection[2], emissionCrossSection[3],
			scatteranceCrossSection,
			absorptionCrossSection,
			mass
		}
	end
	particleBufferB:setArrayData(particleData) -- Gets swapped immediately

	local sortedParticleBoxIdsData = {}
	local invalid = 0xFFFFFFFF -- UINT32_MAX
	for i = 1, consts.sortedParticleBoxIdBufferSize do
		sortedParticleBoxIdsData[i] = {
			invalid,
			invalid
		}
	end
	sortedParticleBoxIds:setArrayData(sortedParticleBoxIdsData)

	camera = {
		position = vec3(consts.worldSize.x * 0.5, consts.worldSize.y * 0.5, -consts.worldSize.z),
		orientation = quat(),
		verticalFOV = math.rad(70),
		speed = 200,
		angularSpeed = 1,
		farPlaneDistance = 2048,
		nearPlaneDistance = 0.125
	}
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
	local level = 2
	while level <= consts.sortedParticleBoxIdBufferSize do
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
	stage5Shader:send("boxSize", {vec3.components(consts.boxSize)})
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

	local translation = vec3()
	if love.keyboard.isDown(consts.controls.moveRight) then
		translation = translation + consts.rightVector
	end
	if love.keyboard.isDown(consts.controls.moveLeft) then
		translation = translation - consts.rightVector
	end
	if love.keyboard.isDown(consts.controls.moveUp) then
		translation = translation + consts.upVector
	end
	if love.keyboard.isDown(consts.controls.moveDown) then
		translation = translation - consts.upVector
	end
	if love.keyboard.isDown(consts.controls.moveForwards) then
		translation = translation + consts.forwardVector
	end
	if love.keyboard.isDown(consts.controls.moveBackwards) then
		translation = translation - consts.forwardVector
	end
	camera.position = camera.position + vec3.rotate(util.normaliseOrZero(translation), camera.orientation) * camera.speed * dt

	local rotation = vec3()
	if love.keyboard.isDown(consts.controls.pitchDown) then
		rotation = rotation + consts.rightVector
	end
	if love.keyboard.isDown(consts.controls.pitchUp) then
		rotation = rotation - consts.rightVector
	end
	if love.keyboard.isDown(consts.controls.yawRight) then
		rotation = rotation + consts.upVector
	end
	if love.keyboard.isDown(consts.controls.yawLeft) then
		rotation = rotation - consts.upVector
	end
	if love.keyboard.isDown(consts.controls.rollAnticlockwise) then
		rotation = rotation + consts.forwardVector
	end
	if love.keyboard.isDown(consts.controls.rollClockwise) then
		rotation = rotation - consts.forwardVector
	end
	local rotationQuat = quat.fromAxisAngle(util.limitVectorLength(rotation, camera.angularSpeed * dt))
	camera.orientation = quat.normalise(camera.orientation * rotationQuat) -- Normalise to prevent numeric drift
end

function love.draw()
	love.graphics.setCanvas(outputCanvas)
	love.graphics.clear(0, 0, 0, 1)

	local worldToCamera = mat4.camera(camera.position, camera.orientation)
	local worldToCameraStationary = mat4.camera(vec3(), camera.orientation)
	local cameraToClip = mat4.perspectiveLeftHanded(
		outputCanvas:getWidth() / outputCanvas:getHeight(),
		camera.verticalFOV,
		camera.farPlaneDistance,
		camera.nearPlaneDistance
	)
	local worldToClip = cameraToClip * worldToCamera
	local clipToSky = mat4.inverse(cameraToClip * worldToCameraStationary)

	love.graphics.setShader(viewShader)
	viewShader:send("clipToSky", {mat4.components(clipToSky)})
	viewShader:send("cameraPosition", {vec3.components(camera.position)})
	viewShader:send("BoxParticleData", boxParticleData)
	viewShader:send("boxSize", {vec3.components(consts.boxSize)})
	viewShader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)})
	viewShader:send("rayStepSize", 1)
	viewShader:send("rayStepCount", 1024)
	viewShader:send("nearestNeighbour", false)
	love.graphics.draw(dummyTexture, 0, 0, 0, outputCanvas:getDimensions())
	love.graphics.setShader()

	love.graphics.setCanvas()
	love.graphics.draw(outputCanvas)

	love.graphics.print(love.timer.getFPS())
end
