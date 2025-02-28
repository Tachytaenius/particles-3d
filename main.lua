local util = require("util")
util.load()

local consts = require("consts")
consts.load() -- Avoiding circular dependencies

local mathsies = require("lib.mathsies")
local vec3 = mathsies.vec3
local quat = mathsies.quat
local mat4 = mathsies.mat4

local particlePositionsShader
local sortParticleBoxIdsShader
local clearBoxArrayDataShader
local setBoxArrayDataShader
local setBoxParticleDataShader
local generateMipmapsShader
local particleAccelerationShader

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

local boxParticleDataViews

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

	boxParticleDataViews = {}
	local function newBoxParticleDataTexture(name, format, mipmaps, volumetrics, debugName)
		local canvas = love.graphics.newCanvas(consts.worldWidthBoxes, consts.worldHeightBoxes, consts.worldDepthBoxes, {
			type = "volume",
			format = format,
			computewrite = true,
			mipmaps = mipmaps and "manual" or nil,
			debugname = debugName
		})
		canvas:setFilter(volumetrics and consts.volumetricsCanvasFilter or "nearest")
		canvas:setWrap("clampzero", "clampzero", "clampzero")
		if mipmaps then
			local viewSet = {}

			local _, frexpResult = math.frexp(consts.worldSizeBoxes.x) -- Sizes should be the same. Also should be 1 more than the base 2 logarithm of box count along each axis (math.log(consts.worldSizeBoxes.x, 2)), but I don't trust float imprecision
			assert(canvas:getMipmapCount() == frexpResult, "Wrong number of mipmaps...?")

			for i = 1, canvas:getMipmapCount() do
				viewSet[i] = love.graphics.newTextureView(canvas, {
					mipmapstart = i,
					mipmapcount = 1,
					debugname = debugName .. " View " .. i
				})
			end
			boxParticleDataViews[name] = viewSet
		end
		return canvas
	end
	massTexture = newBoxParticleDataTexture("mass", "r32f", true, false, "Mass Texture")
	centreOfMassTexture = newBoxParticleDataTexture("centreOfMass", "rgba32f", true, false, "Centre of Mass Texture") -- Alpha is unused
	scatteranceTexture = newBoxParticleDataTexture("scatterance", "r32f", false, true, "Scatterance Texture")
	absorptionTexture = newBoxParticleDataTexture("absorption", "r32f", false, true, "Absorption Texture")
	averageColourTexture = newBoxParticleDataTexture("averageColour", "rgba32f", false, true, "Average Colour Texture") -- Alpha is unused
	emissionTexture = newBoxParticleDataTexture("emission", "rgba32f", false, true, "Emission Texture") -- Alpha is unused

	local structsCode = love.filesystem.read("shaders/include/structs.glsl")

	local function stage(name)
		return love.graphics.newComputeShader(
			structsCode ..
			love.filesystem.read("shaders/simulation/" .. name .. ".glsl")
		)
	end
	particlePositionsShader = stage("particlePositions")
	sortParticleBoxIdsShader = stage("sortParticleBoxIds")
	clearBoxArrayDataShader = stage("clearBoxArrayData")
	setBoxArrayDataShader = stage("setBoxArrayData")
	setBoxParticleDataShader = stage("setBoxParticleData")
	generateMipmapsShader = stage("generateMipmaps")
	particleAccelerationShader = stage("particleAcceleration")

	particleStarShader = love.graphics.newComputeShader(
		"#pragma language glsl4\n" ..
		structsCode ..
		love.filesystem.read("shaders/drawing/particleStar.glsl")
	)

	cloudShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		structsCode ..
		love.filesystem.read("shaders/drawing/cloud.glsl")
	)

	pointShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		structsCode ..
		love.filesystem.read("shaders/drawing/point.glsl")
	)
	pointMesh = love.graphics.newMesh(consts.particleMeshFormat, consts.particleCount, "points")

	diskShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		structsCode ..
		love.filesystem.read("shaders/drawing/disk.glsl"),
		{defines = {INSTANCED = true}}
	)
	diskMesh = util.generateDiskMesh(consts.starDiskVertices)

	dummyTexture = love.graphics.newImage(love.image.newImageData(1, 1))

	outputCanvas = love.graphics.newCanvas(love.graphics.getDimensions())

	local particleData = {}
	for i = 1, consts.particleCount do
		local position = consts.worldSize / 2 + util.randomInSphereVolume(0.4) * consts.worldSize
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

		local cloudEmissionCrossSection = {4, 1, 3} -- Linear space
		-- local function emissionChannel()
		-- 	return love.math.random() * 4
		-- end
		-- local cloudEmissionCrossSection = {emissionChannel(), emissionChannel(), emissionChannel()} -- Linear space

		local luminousFlux = {6, 5, 1} -- Linear space
		-- local function fluxChannel()
		-- 	return love.math.random() * 6
		-- end
		-- local luminousFlux = {fluxChannel(), fluxChannel(), fluxChannel()} -- Linear space

		local scatteranceCrossSection = love.math.random() * 15
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

	particlePositionsShader:send("particleCount", consts.particleCount) -- In
	particlePositionsShader:send("dt", dt) -- In
	particlePositionsShader:send("boxSize", {consts.boxWidth, consts.boxHeight, consts.boxDepth})
	particlePositionsShader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)})
	particlePositionsShader:send("Particles", particleBufferA) -- In/out
	particlePositionsShader:send("ParticleBoxIds", particleBoxIds) -- Out
	particlePositionsShader:send("ParticleBoxIdsToSort", sortedParticleBoxIds) -- Out
	love.graphics.dispatchThreadgroups(particlePositionsShader,
		math.ceil(consts.particleCount / particlePositionsShader:getLocalThreadgroupSize())
	)

	sortParticleBoxIdsShader:send("ParticleBoxIdsToSort", sortedParticleBoxIds) -- In/out
	local level = 2
	while level <= consts.sortedParticleBoxIdBufferSize do
		sortParticleBoxIdsShader:send("level", level) -- In
		local stage = math.floor(level / 2) -- Within stage 2
		while stage > 0 do
			sortParticleBoxIdsShader:send("stage", stage) -- In
			love.graphics.dispatchThreadgroups(sortParticleBoxIdsShader,
				math.ceil(
					math.floor(consts.sortedParticleBoxIdBufferSize / 2) /
					sortParticleBoxIdsShader:getLocalThreadgroupSize()
				)
			)
			stage = math.floor(stage / 2)
		end
		level = level * 2
	end

	clearBoxArrayDataShader:send("boxCount", consts.boxCount) -- In
	clearBoxArrayDataShader:send("BoxArrayData", boxArrayData) -- Out
	love.graphics.dispatchThreadgroups(clearBoxArrayDataShader,
		math.ceil(consts.boxCount / clearBoxArrayDataShader:getLocalThreadgroupSize())
	)

	setBoxArrayDataShader:send("SortedParticleBoxIds", sortedParticleBoxIds) -- In
	setBoxArrayDataShader:send("particleCount", consts.particleCount) -- In
	setBoxArrayDataShader:send("BoxArrayData", boxArrayData) -- Out
	love.graphics.dispatchThreadgroups(setBoxArrayDataShader,
		math.ceil(consts.particleCount / setBoxArrayDataShader:getLocalThreadgroupSize())
	)

	setBoxParticleDataShader:send("SortedParticleBoxIds", sortedParticleBoxIds) -- In
	setBoxParticleDataShader:send("Particles", particleBufferA) -- In
	setBoxParticleDataShader:send("particleCount", consts.particleCount) -- In
	setBoxParticleDataShader:send("BoxArrayData", boxArrayData) -- In
	setBoxParticleDataShader:send("boxCount", consts.boxCount) -- In
	setBoxParticleDataShader:send("boxVolume", consts.boxSize.x * consts.boxSize.y * consts.boxSize.z) -- In
	setBoxParticleDataShader:send("boxSize", {vec3.components(consts.boxSize)}) -- In
	setBoxParticleDataShader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)}) -- In
	setBoxParticleDataShader:send("mass", massTexture) -- Out
	setBoxParticleDataShader:send("centreOfMass", centreOfMassTexture) -- Out
	setBoxParticleDataShader:send("scatterance", scatteranceTexture) -- Out
	setBoxParticleDataShader:send("absorption", absorptionTexture) -- Out
	setBoxParticleDataShader:send("averageColour", averageColourTexture) -- Out
	setBoxParticleDataShader:send("emission", emissionTexture) -- Out
	love.graphics.dispatchThreadgroups(setBoxParticleDataShader,
		math.ceil(consts.boxCount / setBoxParticleDataShader:getLocalThreadgroupSize())
	)

	for i = 2, massTexture:getMipmapCount() do -- All the textures have the same dimensions, so same number of mipmaps
		local destinationWidth, destinationHeight = boxParticleDataViews.mass[i]:getDimensions()
		local destinationDepth = boxParticleDataViews.mass[i]:getDepth()

		generateMipmapsShader:send("massSource", boxParticleDataViews.mass[i - 1])
		generateMipmapsShader:send("massDestination", boxParticleDataViews.mass[i])

		generateMipmapsShader:send("centreOfMassSource", boxParticleDataViews.centreOfMass[i - 1])
		generateMipmapsShader:send("centreOfMassDestination", boxParticleDataViews.centreOfMass[i])

		local x, y, z = generateMipmapsShader:getLocalThreadgroupSize()
		love.graphics.dispatchThreadgroups(generateMipmapsShader,
			math.ceil(destinationWidth / x),
			math.ceil(destinationHeight / y),
			math.ceil(destinationDepth / z)
		)
	end
	-- These work fine without manual treatment
	-- averageColourTexture:generateMipmaps()
	-- scatteranceTexture:generateMipmaps()
	-- absorptionTexture:generateMipmaps()
	-- emissionTexture:generateMipmaps()

	particleAccelerationShader:send("lods", massTexture:getMipmapCount())
	particleAccelerationShader:send("boxRange", consts.simulationBoxRange)
	particleAccelerationShader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)})
	particleAccelerationShader:send("particleCount", consts.particleCount) -- In
	particleAccelerationShader:send("ParticlesIn", particleBufferA) -- In
	particleAccelerationShader:send("gravityStrength", consts.gravityStrength) -- In
	particleAccelerationShader:send("dt", dt) -- In
	particleAccelerationShader:send("ParticleBoxIds", particleBoxIds) -- In
	particleAccelerationShader:send("SortedParticleBoxIds", sortedParticleBoxIds) -- In
	particleAccelerationShader:send("BoxArrayData", boxArrayData) -- In
	particleAccelerationShader:send("massTexture", massTexture) -- In
	particleAccelerationShader:send("centreOfMassTexture", centreOfMassTexture) -- In
	particleAccelerationShader:send("ParticlesOut", particleBufferB) -- Out
	love.graphics.dispatchThreadgroups(particleAccelerationShader,
		math.ceil(consts.particleCount / particleAccelerationShader:getLocalThreadgroupSize())
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
	-- cloudShader:send("averageColour", averageColourTexture)
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
