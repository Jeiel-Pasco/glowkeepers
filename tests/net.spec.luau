-- Net: remote definitions, argument validation, token buckets (TECH_SPEC §7).
local H = require("./harness")
local Net = require("../src/shared/Net")
local Validate = require("../src/shared/Net/Validate")
local TokenBucket = require("../src/shared/Net/TokenBucket")

H.test("every remote is well formed", function()
	for name, def in Net.remotes do
		H.ok(def.dir == "c2s" or def.dir == "s2c", `{name} direction`)
		if def.dir == "c2s" then
			H.ok(def.rate ~= nil and def.rate.perSecond > 0 and def.rate.burst >= 1, `{name} needs a rate`)
			H.ok(def.args ~= nil, `{name} needs an args list (may be empty)`)
		else
			H.eq(def.args, nil, `{name}: server → client remotes take no schema`)
		end
	end
end)

H.test("SetSetting's key enum matches Net.settings", function()
	local keys = Net.remotes.SetSetting.args[1].values
	local count = 0
	for key in Net.settings do
		count += 1
		H.ok(table.find(keys, key) ~= nil, `{key} missing from the enum`)
	end
	H.eq(#keys, count, "same number of keys")
end)

H.test("value checks", function()
	H.ok(Validate.value({ type = "boolean" }, true), "boolean")
	H.ok(not Validate.value({ type = "boolean" }, 1), "1 is not a boolean")
	H.ok(Validate.value({ type = "number", min = 0, max = 1 }, 0.5), "in range")
	H.ok(not Validate.value({ type = "number", min = 0, max = 1 }, 1.5), "above max")
	H.ok(not Validate.value({ type = "number" }, 0 / 0), "NaN")
	H.ok(not Validate.value({ type = "number" }, math.huge), "infinity")
	H.ok(Validate.value({ type = "integer" }, 3), "integer")
	H.ok(not Validate.value({ type = "integer" }, 3.5), "not an integer")
	H.ok(Validate.value({ type = "string", maxLen = 3 }, "abc"), "short string")
	H.ok(not Validate.value({ type = "string", maxLen = 3 }, "abcd"), "too long")
	H.ok(not Validate.value({ type = "string" }, "\255\254"), "invalid UTF-8")
	H.ok(Validate.value({ type = "enum", values = { "a", "b" } }, "b"), "enum")
	H.ok(not Validate.value({ type = "enum", values = { "a", "b" } }, "c"), "not in enum")
	H.ok(Validate.value({ type = "any" }, {}), "any")
	H.ok(not Validate.value({ type = "any" }, nil), "any still needs a value")
	H.ok(Validate.value({ type = "integer", optional = true }, nil), "optional")
	H.ok(not Validate.value({ type = "mystery" }, 1), "unknown schema type")
end)

H.test("argument lists", function()
	local schemas = Net.remotes.FtueStep.args
	H.ok(Validate.args(schemas, table.pack(3)), "valid")
	H.ok(not Validate.args(schemas, table.pack(3, "extra")), "too many")
	H.ok(not Validate.args(schemas, table.pack()), "missing")
	H.ok(not Validate.args(schemas, table.pack(11)), "out of range")
	H.ok(Validate.args(Net.remotes.ClientReady.args, table.pack()), "no arguments")
	H.ok(not Validate.args(Net.remotes.ClientReady.args, table.pack(nil, 1)), "trailing junk")
end)

H.test("token bucket: burst, refill, and a clock that goes backwards", function()
	local bucket = TokenBucket.new(2, 3, 100)
	H.ok(TokenBucket.take(bucket, 100), "1")
	H.ok(TokenBucket.take(bucket, 100), "2")
	H.ok(TokenBucket.take(bucket, 100), "3")
	H.ok(not TokenBucket.take(bucket, 100), "burst spent")
	H.ok(TokenBucket.take(bucket, 101), "refilled 2 after 1 s")
	H.ok(TokenBucket.take(bucket, 101), "second token")
	H.ok(not TokenBucket.take(bucket, 101), "empty again")
	H.ok(not TokenBucket.take(bucket, 50), "going back in time refills nothing")
	H.ok(TokenBucket.take(bucket, 101.5), "refill resumes from the latest time")
	H.ok(not TokenBucket.take(TokenBucket.new(1, 1, 0), 0, 2), "a cost above the burst")
	H.throws(function()
		TokenBucket.new(0, 1, 0)
	end, "zero rate")
end)

H.finish("net")
