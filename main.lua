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

local particleStarShader
local cloudShader
local pointShader
local pointMesh
local diskShader
local diskMesh
local dummyTexture
local outputCanvas
local camera

local particleBufferA, particleBufferB
local particleBoxIds, sortedParticleBoxIds
local boxArrayData
local particleDrawData

local massTexture
local centreOfMassTexture
local scatteranceTexture
local absorptionTexture
local averageColourTexture
local emissionTexture

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

	particleDrawData = love.graphics.newBuffer(consts.particleDrawDataFormat, consts.particleCount, {
		shaderstorage = true,
		debugname = "Particle Draw Data"
	})

	local function newBoxParticleDataTexture(format, debugName)
		local canvas = love.graphics.newCanvas(consts.worldWidthBoxes, consts.worldHeightBoxes, consts.worldDepthBoxes, {
			type = "volume",
			format = format,
			computewrite = true,
			debugname = debugName
		})
		canvas:setFilter(consts.boxParticleDataCanvasFilter)
		canvas:setWrap("clampzero", "clampzero", "clampzero")
		return canvas
	end
	massTexture = newBoxParticleDataTexture("r32f", "Mass Texture")
	centreOfMassTexture = newBoxParticleDataTexture("rgba32f", "Centre of Mass Texture") -- Alpha is unused
	scatteranceTexture = newBoxParticleDataTexture("r32f", "Scatterance Texture")
	absorptionTexture = newBoxParticleDataTexture("r32f", "Absorption Texture")
	averageColourTexture = newBoxParticleDataTexture("rgba32f", "Average Colour Texture") -- Alpha is unused
	emissionTexture = newBoxParticleDataTexture("rgba32f", "Emission Texture") -- Alpha is unused

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

	particleStarShader = love.graphics.newComputeShader(
		"#pragma language glsl4\n" ..
		structsCode ..
		love.filesystem.read("shaders/particleStar.glsl")
	)

	cloudShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		structsCode ..
		love.filesystem.read("shaders/cloud.glsl")
	)

	pointShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		structsCode ..
		love.filesystem.read("shaders/point.glsl")
	)

	pointMesh = love.graphics.newMesh(consts.particleMeshFormat, consts.particleCount, "points")

	diskShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		structsCode ..
		love.filesystem.read("shaders/disk.glsl"),
		{defines = {INSTANCED = true}}
	)
	diskMesh = util.generateDiskMesh(consts.starDiskVertices)

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
			return love.math.random() * 4
		end
		local cloudEmissionCrossSection = {emissionChannel(), emissionChannel(), emissionChannel()} -- Linear space

		local function fluxChannel()
			return love.math.random() * 6
		end
		local luminousFlux = {fluxChannel(), fluxChannel(), fluxChannel()}

		local scatteranceCrossSection = love.math.random() * 10
		local absorptionCrossSection = love.math.random() * 10

		particleData[i] = {
			position.x, position.y, position.z,
			velocity.x, velocity.y, velocity.z,
			colour[1], colour[2], colour[3],
			cloudEmissionCrossSection[1], cloudEmissionCrossSection[2], cloudEmissionCrossSection[3],
			scatteranceCrossSection,
			absorptionCrossSection,
			mass,
			luminousFlux[1], luminousFlux[2], luminousFlux[3]
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
		position = consts.worldSize / 2,
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
	stage5Shader:send("Particles", particleBufferA) -- In
	stage5Shader:send("particleCount", consts.particleCount) -- In
	stage5Shader:send("BoxArrayData", boxArrayData) -- In
	stage5Shader:send("boxCount", consts.boxCount) -- In
	stage5Shader:send("boxVolume", consts.boxSize.x * consts.boxSize.y * consts.boxSize.z)
	stage5Shader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)})
	stage5Shader:send("mass", massTexture) -- Out
	stage5Shader:send("centreOfMass", centreOfMassTexture) -- Out
	stage5Shader:send("scatterance", scatteranceTexture) -- Out
	stage5Shader:send("absorption", absorptionTexture) -- Out
	stage5Shader:send("averageColour", averageColourTexture) -- Out
	stage5Shader:send("emission", emissionTexture) -- Out
	love.graphics.dispatchThreadgroups(stage5Shader,
		math.ceil(consts.boxCount / stage5Shader:getLocalThreadgroupSize())
	)

	stage6Shader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)})
	stage6Shader:send("particleCount", consts.particleCount) -- In
	stage6Shader:send("ParticlesIn", particleBufferA) -- In
	stage6Shader:send("gravityStrength", consts.gravityStrength) -- In
	stage6Shader:send("dt", dt) -- In
	stage6Shader:send("ParticleBoxIds", particleBoxIds) -- In
	stage6Shader:send("SortedParticleBoxIds", sortedParticleBoxIds) -- In
	stage6Shader:send("BoxArrayData", boxArrayData) -- In
	stage6Shader:send("mass", massTexture) -- In
	stage6Shader:send("centreOfMass", centreOfMassTexture) -- In
	stage6Shader:send("boxCount", consts.boxCount) -- In
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

	particleStarShader:send("Particles", particleBufferB) -- In
	particleStarShader:send("particleCount", consts.particleCount) -- In
	particleStarShader:send("cameraPosition", {vec3.components(camera.position)}) -- In
 	particleStarShader:send("scatterance", scatteranceTexture) -- In
	particleStarShader:send("absorption", absorptionTexture) -- In
	particleStarShader:send("rayStepCount", consts.extinctionRayStepCount) -- In
	particleStarShader:send("worldSize", {vec3.components(consts.worldSize)}) -- In
	particleStarShader:send("diskSolidAngle", consts.starDiskSolidAngle)
	particleStarShader:send("ParticleDrawData", particleDrawData) -- Out
	love.graphics.dispatchThreadgroups(particleStarShader,
		math.ceil(consts.particleCount / particleStarShader:getLocalThreadgroupSize())
	)

	love.graphics.setShader(cloudShader)
	cloudShader:send("clipToSky", {mat4.components(clipToSky)})
	cloudShader:send("cameraPosition", {vec3.components(camera.position)})
	cloudShader:send("scatterance", scatteranceTexture)
	cloudShader:send("absorption", absorptionTexture)
	cloudShader:send("averageColour", averageColourTexture)
	cloudShader:send("worldSize", {vec3.components(consts.worldSize)})
	cloudShader:send("emission", emissionTexture)
	cloudShader:send("rayStepSize", consts.rayStepSize)
	cloudShader:send("rayStepCount", consts.rayStepCount)
	love.graphics.draw(dummyTexture, 0, 0, 0, outputCanvas:getDimensions())

	love.graphics.setBlendMode("add")

	if consts.starDrawType == "points" then
		love.graphics.setShader(pointShader)
		pointShader:send("Particles", particleBufferB)
		pointShader:send("pointSize", consts.pointShaderPointSize)
		pointShader:send("ParticleDrawData", particleDrawData)
		pointShader:send("worldToClip", {mat4.components(worldToClip)})
		love.graphics.draw(pointMesh)
	elseif consts.starDrawType == "disks" then
		local cameraToClipDisk = mat4.perspectiveLeftHanded(
			outputCanvas:getWidth() / outputCanvas:getHeight(),
			camera.verticalFOV,
			1.5,
			0.5
		)
		local worldToClipDisk = cameraToClipDisk * mat4.camera(vec3(), camera.orientation)
		local diskDistanceToSphere = 1 - math.cos(consts.starDiskAngularRadius)
		local scaleToGetAngularRadius = math.tan(consts.starDiskAngularRadius)
		local cameraUp = vec3.rotate(consts.upVector, camera.orientation)
		local cameraRight = vec3.rotate(consts.rightVector, camera.orientation)
		diskShader:send("diskDistanceToSphere", diskDistanceToSphere)
		diskShader:send("scale", scaleToGetAngularRadius)
		diskShader:send("vertexFadePower", consts.starDiskFadePower)
		diskShader:send("cameraUp", {vec3.components(cameraUp)})
		diskShader:send("cameraRight", {vec3.components(cameraRight)})
		diskShader:send("ParticleDrawData", particleDrawData)
		diskShader:send("worldToClip", {mat4.components(worldToClipDisk)})
		love.graphics.setShader(diskShader)
		love.graphics.drawInstanced(diskMesh, consts.particleCount)
	else
		error("Unknown star draw type " .. consts.starDrawType)
	end
	love.graphics.setShader()

	love.graphics.setBlendMode("alpha")

	love.graphics.setCanvas()
	love.graphics.draw(outputCanvas)

	love.graphics.print(love.timer.getFPS())
end
