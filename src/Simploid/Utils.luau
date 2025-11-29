--!optimize 2
local Utils = {}

--
Utils.ReplicateExhaustion = 0

-- Serialize a RaycastParams into a table that can be sent over remotes
function Utils.RayParamsSerialize(params: RaycastParams)
	return {
		FilterType = params.FilterType,
		FilterDescendants = params.FilterDescendantsInstances,
		IgnoreWater = params.IgnoreWater,
	}
end

Utils.ctr = 0
-- Deserialize a table back into a RaycastParams
function Utils.RayParamsDeserialize(data): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = data.FilterType
	params.FilterDescendantsInstances = data.FilterDescendants or {}
	params.IgnoreWater = data.IgnoreWater or false
	Utils.ctr += 1
	return params
end

return Utils
