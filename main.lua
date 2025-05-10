local util = require("util")
util.load()

local consts = require("consts")

local mathsies = require("lib.mathsies")
local vec3 = mathsies.vec3
local quat = mathsies.quat
local mat4 = mathsies.mat4

local particlePositionsShader
local sortParticleBoxIdsShader
local clearBoxArrayDataShader
local setBoxArrayDataShader
local setChargeBoxDataShader
local setVolumetricBoxDataShader
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

local particleBufferA, particleChargeBuffersA
local particleBufferB, particleChargeBuffersB
local particleBoxIds, sortedParticleBoxIds
local boxArrayData
local particleDrawData

local chargeTextures
local scatteranceTexture
local absorptionTexture
local averageColourTexture
local emissionTexture

local boxParticleDataViews

local paused
local time

function love.load(args)
	consts.load(args)

	local function generateChargeBuffers(letter)
		local buffers = {}
		for i, charge in ipairs(consts.charges) do
			local buffer = love.graphics.newBuffer(consts.particleChargeFormat, consts.particleCount, {
				shaderstorage = true,
				debugname = "Particle " .. charge.displayName .. " Charges " .. letter
			})
			buffers[charge.name] = buffer
			buffers[i] = buffer
		end
		return buffers
	end

	particleBufferA = love.graphics.newBuffer(consts.particleFormat, consts.particleCount, {
		shaderstorage = true,
		debugname = "Particles A"
	})
	particleChargeBuffersA = generateChargeBuffers("A")

	particleBufferB = love.graphics.newBuffer(consts.particleFormat, consts.particleCount, {
		shaderstorage = true,
		debugname = "Particles B"
	})
	particleChargeBuffersB = generateChargeBuffers("B")

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

	chargeTextures = {}
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

			assert(canvas:getMipmapCount() == consts.boxTextureMipmapCount, "Wrong number of mipmaps...?")

			for i = 1, consts.boxTextureMipmapCount do
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
	for i, charge in ipairs(consts.charges) do
		local texture = newBoxParticleDataTexture(charge.name, "rgba32f", true, false, charge.displayName .. " Texture") -- Centre x, y, z, then fourth component is charge amount
		chargeTextures[charge.name] = texture
		chargeTextures[i] = texture
	end
	scatteranceTexture = newBoxParticleDataTexture("scatterance", "r16f", false, true, "Scatterance Texture")
	absorptionTexture = newBoxParticleDataTexture("absorption", "r16f", false, true, "Absorption Texture")
	averageColourTexture = newBoxParticleDataTexture("averageColour", "rg11b10f", false, true, "Average Colour Texture") -- Alpha is unused
	emissionTexture = newBoxParticleDataTexture("emission", "rg11b10f", false, true, "Emission Texture") -- Alpha is unused

	local structsCode = love.filesystem.read("shaders/include/structs.glsl")

	local function stage(name, prepend, settings)
		return love.graphics.newComputeShader(
			structsCode ..
			(prepend or "") ..
			love.filesystem.read("shaders/simulation/" .. name .. ".glsl"),
			settings
		)
	end
	particlePositionsShader = stage("particlePositions")
	sortParticleBoxIdsShader = stage("sortParticleBoxIds")
	clearBoxArrayDataShader = stage("clearBoxArrayData")
	setBoxArrayDataShader = stage("setBoxArrayData")
	setChargeBoxDataShader = stage("setChargeBoxData")
	setVolumetricBoxDataShader = stage("setVolumetricBoxData")
	generateMipmapsShader = stage("generateMipmaps")
	local accelerationPrepend = "#line 1\n"
	for _, charge in ipairs(consts.charges) do
		accelerationPrepend = accelerationPrepend ..
			"readonly buffer " .. charge.pascalName .. "Charges {\n" ..
			"\tfloat[] " .. charge.name .. "Charges;\n" ..
			"};\n\n"
	end
	particleAccelerationShader = stage("particleAcceleration", accelerationPrepend, {defines = {COLOUR_ENABLED = consts.colourEnabled or nil}})

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

	-- Coinciding seeds is... unlikely
	local seed1 = love.math.random(0, 2^16 - 1)
	local seed2 = love.math.random(0, 2^16 - 1)
	local function sampleParticleDensityNoise(position) -- Not the actual number density, that would be this multiplied by the number of particles (I think)
		local noise1 = love.math.simplexNoise(
			position.x * consts.startDensityNoiseFrequency,
			position.y * consts.startDensityNoiseFrequency,
			position.z * consts.startDensityNoiseFrequency,
			seed1
		)
		local noise2 = love.math.simplexNoise(
			position.x * consts.startDensityNoiseFrequency,
			position.y * consts.startDensityNoiseFrequency,
			position.z * consts.startDensityNoiseFrequency,
			seed2
		)
		return ((1 - math.abs(noise1 * 2 - 1)) * (1 - math.abs(noise2 * 2 - 1))) ^ 20
	end

	local seed1 = love.math.random(0, 2^16 - 1)
	local seed2 = love.math.random(0, 2^16 - 1)
	local seed3 = love.math.random(0, 2^16 - 1)
	local function sampleColourNoise(position)
		local r = love.math.simplexNoise(
			position.x * consts.startColourNoiseFrequency,
			position.y * consts.startColourNoiseFrequency,
			position.z * consts.startColourNoiseFrequency,
			seed1
		)
		local g = love.math.simplexNoise(
			position.x * consts.startColourNoiseFrequency,
			position.y * consts.startColourNoiseFrequency,
			position.z * consts.startColourNoiseFrequency,
			seed2
		)
		local b = love.math.simplexNoise(
			position.x * consts.startColourNoiseFrequency,
			position.y * consts.startColourNoiseFrequency,
			position.z * consts.startColourNoiseFrequency,
			seed3
		)
		local max = math.max(r, g, b)
		if max == 0 then
			return 0, 0, 0
		end
		return r / max, g / max, b / max
	end

	local particleData = {}
	local particleChargeData = {}
	for i = 1, #consts.charges do
		particleChargeData[i] = {}
	end
	local function newParticle(position)
		local i = #particleData + 1

		local function setCharge(name, value)
			particleChargeData[consts.charges[name].index][i] = value
			return value
		end

		local mass
		if consts.colourEnabled then
			mass = setCharge("mass", 1)
		else
			mass = setCharge("mass", love.math.random() ^ 5 * 8)
		end
		local electricCharge = setCharge("electric",
			-- (love.math.random() < 0.2 and mass * (love.math.random() * 0.01) or 0)
			-- * (love.math.random() < 0.5 and 1 or -1)
			0
		)
		if consts.colourEnabled then
			setCharge("spacing", 1)
		end
		local colourCharges = {
			"red",
			"antiblue",
			"green",
			"antired",
			"blue",
			"antigreen"
		}
		local colourColours = {
			{1, 0, 0},
			{1, 1, 0},
			{0, 1, 0},
			{0, 1, 1},
			{0, 0, 1},
			{1, 0, 1}
		}
		local chosenColourIndex, chosenColour
		if consts.colourEnabled then
			chosenColourIndex = love.math.random(#colourCharges)
			chosenColour = colourCharges[chosenColourIndex]
			for _, chargeName in ipairs(colourCharges) do
				setCharge(chargeName, chargeName == chosenColour and 1 or 0)
			end
		end

		local velocity = util.randomInSphereVolume(consts.startVelocityRadius)

		local function colourChannel()
			return love.math.random()
		end
		local colour = {colourChannel(), colourChannel(), colourChannel()}

		-- local cloudEmissionCrossSection = {4, 1, 3} -- Linear space
		-- local function emissionChannel()
		-- 	return love.math.random() * 2
		-- end
		-- local cloudEmissionCrossSection = {emissionChannel(), emissionChannel(), emissionChannel()} -- Linear space
		local r, g, b = sampleColourNoise(position)
		local mul = 0.75
		local cloudEmissionCrossSection = {r * mul, g * mul, b * mul}

		-- local luminousFlux = {6, 5, 1} -- Linear space
		local function fluxChannel()
			return love.math.random() * 2
		end
		local luminousFlux = {fluxChannel(), fluxChannel(), fluxChannel()} -- Linear space

		local scatteranceCrossSection = love.math.random() * 2
		local absorptionCrossSection = love.math.random() * 1

		if consts.colourEnabled then
			local m = 5
			cloudEmissionCrossSection = {colourColours[chosenColourIndex][1] * m, colourColours[chosenColourIndex][2] * m, colourColours[chosenColourIndex][3] * m}
			local m = 10
			luminousFlux = {colourColours[chosenColourIndex][1] * m, colourColours[chosenColourIndex][2] * m, colourColours[chosenColourIndex][3] * m}
		end

		local particle = {
			position.x, position.y, position.z,
			velocity.x, velocity.y, velocity.z,
			colour[1], colour[2], colour[3],
			cloudEmissionCrossSection[1], cloudEmissionCrossSection[2], cloudEmissionCrossSection[3],
			scatteranceCrossSection,
			absorptionCrossSection,
			luminousFlux[1], luminousFlux[2], luminousFlux[3],
		}

		particleData[i] = particle
	end
	for i = 1, consts.particleCount do
		local position
		repeat -- Rejection sampling
			position = vec3(
				love.math.random(),
				love.math.random(),
				love.math.random()
			) * consts.worldSize
			local noise = sampleParticleDensityNoise(position)
		until love.math.random() < noise
		newParticle(position)
	end
	assert(consts.particleCount == #particleData, "Wrong number of particles in particle data")
	particleBufferB:setArrayData(particleData) -- Gets swapped immediately
	for i, data in ipairs(particleChargeData) do
		particleChargeBuffersB[i]:setArrayData(data)
		particleChargeBuffersA[i]:setArrayData(data) -- TEMP: Allow charges to change over time
	end

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

	paused = false
	time = 0
end

function love.keypressed(key)
	if key == "space" then
		paused = not paused
	end
end

local function safeSend(shader, uniform, ...)
	if not shader:hasUniform(uniform) then
		return
	end
	shader:send(uniform, ...)
end

function love.update(dt)
	if not paused then
		particleBufferA, particleBufferB = particleBufferB, particleBufferA
		particleChargeBuffersA, particleChargeBuffersB = particleChargeBuffersB, particleChargeBuffersA

		particlePositionsShader:send("particleCount", consts.particleCount) -- In
		particlePositionsShader:send("dt", dt) -- In
		particlePositionsShader:send("boxSize", {consts.boxWidth, consts.boxHeight, consts.boxDepth}) -- In
		particlePositionsShader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)}) -- In
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

		local function sendToBoxDataStage(shader)
			shader:send("Particles", particleBufferA) -- In
			shader:send("SortedParticleBoxIds", sortedParticleBoxIds) -- In
			shader:send("particleCount", consts.particleCount) -- In
			shader:send("BoxArrayData", boxArrayData) -- In
			shader:send("boxCount", consts.boxCount) -- In
			shader:send("boxVolume", consts.boxVolume) -- In
			shader:send("boxSize", {vec3.components(consts.boxSize)}) -- In
			shader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)}) -- In
		end

		sendToBoxDataStage(setChargeBoxDataShader)
		for i, charge in ipairs(consts.charges) do
			setChargeBoxDataShader:send("ParticleCharges", particleChargeBuffersA[i]) -- In
			setChargeBoxDataShader:send("spaceDensity", charge.spaceDensity) -- In
			setChargeBoxDataShader:send("charge", chargeTextures[charge.name]) -- Out
			love.graphics.dispatchThreadgroups(setChargeBoxDataShader,
				math.ceil(consts.boxCount / setChargeBoxDataShader:getLocalThreadgroupSize())
			)
		end

		sendToBoxDataStage(setVolumetricBoxDataShader)
		setVolumetricBoxDataShader:send("scatterance", scatteranceTexture) -- Out
		setVolumetricBoxDataShader:send("absorption", absorptionTexture) -- Out
		setVolumetricBoxDataShader:send("averageColour", averageColourTexture) -- Out
		setVolumetricBoxDataShader:send("emission", emissionTexture) -- Out
		setVolumetricBoxDataShader:send("MassCharges", particleChargeBuffersA.mass)
		love.graphics.dispatchThreadgroups(setVolumetricBoxDataShader,
			math.ceil(consts.boxCount / setVolumetricBoxDataShader:getLocalThreadgroupSize())
		)

		for _, chargeInfo in ipairs(consts.charges) do
			local name = chargeInfo.name
			for i = 2, consts.boxTextureMipmapCount do -- All the textures have the same dimensions, so same number of mipmaps
				local destinationWidth, destinationHeight = boxParticleDataViews[name][i]:getDimensions()
				local destinationDepth = boxParticleDataViews[name][i]:getDepth()

				generateMipmapsShader:send("chargeSource", boxParticleDataViews[name][i - 1])
				generateMipmapsShader:send("chargeDestination", boxParticleDataViews[name][i])

				local x, y, z = generateMipmapsShader:getLocalThreadgroupSize()
				love.graphics.dispatchThreadgroups(generateMipmapsShader,
					math.ceil(destinationWidth / x),
					math.ceil(destinationHeight / y),
					math.ceil(destinationDepth / z)
				)
			end
		end
		-- These work fine without manual treatment
		-- averageColourTexture:generateMipmaps()
		-- scatteranceTexture:generateMipmaps()
		-- absorptionTexture:generateMipmaps()
		-- emissionTexture:generateMipmaps()

		particleAccelerationShader:send("gravityStrength", consts.gravityStrength) -- In
		particleAccelerationShader:send("gravitySoftening", consts.gravitySoftening)  -- In
		particleAccelerationShader:send("electromagnetismStrength", consts.electromagnetismStrength) -- In
		particleAccelerationShader:send("electromagnetismSoftening", consts.electromagnetismSoftening)  -- In
		if consts.colourEnabled then
			particleAccelerationShader:send("colourForceStrength", consts.colourForceStrength) -- In
			particleAccelerationShader:send("colourForcePower", consts.colourForcePower) -- In
			particleAccelerationShader:send("colourForceSoftening", consts.colourForceSoftening)  -- In
			particleAccelerationShader:send("colourForceDistanceDivide", consts.colourForceDistanceDivide) -- In
			particleAccelerationShader:send("spacingForceStrength", consts.spacingForceStrength) -- In
			particleAccelerationShader:send("spacingForceSoftening", consts.spacingForceSoftening)  -- In
			particleAccelerationShader:send("spacingForcePower", consts.spacingForcePower)  -- In
			particleAccelerationShader:send("spacingForceDistanceDivide", consts.spacingForceDistanceDivide)  -- In
		end
		particleAccelerationShader:send("lods", consts.boxTextureMipmapCount)  -- In
		particleAccelerationShader:send("boxRange", consts.simulationBoxRange)  -- In
		particleAccelerationShader:send("worldSizeBoxes", {vec3.components(consts.worldSizeBoxes)})  -- In
		particleAccelerationShader:send("particleCount", consts.particleCount) -- In
		particleAccelerationShader:send("ParticlesIn", particleBufferA) -- In
		particleAccelerationShader:send("dt", dt) -- In
		particleAccelerationShader:send("ParticleBoxIds", particleBoxIds) -- In
		particleAccelerationShader:send("SortedParticleBoxIds", sortedParticleBoxIds) -- In
		particleAccelerationShader:send("BoxArrayData", boxArrayData) -- In
		particleAccelerationShader:send("ParticlesOut", particleBufferB) -- Out
		for _, charge in ipairs(consts.charges) do
			safeSend(particleAccelerationShader, charge.pascalName .. "Charges", particleChargeBuffersA[charge.name])
			safeSend(particleAccelerationShader, charge.name .. "Texture", chargeTextures[charge.name])
		end
		love.graphics.dispatchThreadgroups(particleAccelerationShader,
			math.ceil(consts.particleCount / particleAccelerationShader:getLocalThreadgroupSize())
		)

		time = time + dt
	end

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
