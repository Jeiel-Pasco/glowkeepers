--!strict
-- Argument checks for remotes. Each check returns true, or false and a short reason. Pure.

local Validate = {}

local DEFAULT_MAX_LEN = 64

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Validate.value(schema: any, value: unknown): (boolean, string?)
	if value == nil then
		if schema.optional then
			return true
		end
		return false, "missing"
	end

	local kind = schema.type
	if kind == "any" then
		return true
	elseif kind == "boolean" then
		if type(value) ~= "boolean" then
			return false, "not a boolean"
		end
		return true
	elseif kind == "number" or kind == "integer" then
		if type(value) ~= "number" or not isFinite(value) then
			return false, "not a finite number"
		end
		if kind == "integer" and value % 1 ~= 0 then
			return false, "not an integer"
		end
		if schema.min ~= nil and value < schema.min then
			return false, "below the minimum"
		end
		if schema.max ~= nil and value > schema.max then
			return false, "above the maximum"
		end
		return true
	elseif kind == "string" or kind == "enum" then
		if type(value) ~= "string" then
			return false, "not a string"
		end
		if #value > (schema.maxLen or DEFAULT_MAX_LEN) then
			return false, "too long"
		end
		if utf8.len(value) == nil then
			return false, "invalid UTF-8"
		end
		if kind == "enum" and table.find(schema.values, value) == nil then
			return false, "not an allowed value"
		end
		return true
	elseif kind == "list" then
		-- An array of 1..maxCount items, each checked against `of`. No holes or extra keys.
		if type(value) ~= "table" then
			return false, "not a list"
		end
		local count = 0
		for _ in value :: any do
			count += 1
		end
		local list = value :: { unknown }
		if count == 0 or count ~= #list then
			return false, "not a list"
		end
		if count > (schema.maxCount or 1) then
			return false, "too many items"
		end
		for i, item in list do
			local ok, reason = Validate.value(schema.of, item)
			if not ok then
				return false, `item {i}: {reason}`
			end
		end
		return true
	end
	return false, `unknown schema type {tostring(kind)}`
end

-- `args` is table.pack(...) of the remote's arguments.
function Validate.args(schemas: { any }, args: { [number]: unknown, n: number }): (boolean, string?)
	if args.n > #schemas then
		return false, "too many arguments"
	end
	for i, schema in schemas do
		local ok, reason = Validate.value(schema, args[i])
		if not ok then
			return false, `argument {i}: {reason}`
		end
	end
	return true
end

return Validate
