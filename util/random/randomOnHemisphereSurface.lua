local vec3 = require("lib.mathsies").vec3

local util = require("util")

return function(radius, direction)
	local point = util.randomOnSphereSurface(radius)
	return point * util.sign(vec3.dot(point, direction))
end
