--!strict
-- Tiny test harness shared by tests/*.spec.luau (Lune 0.11.0).
-- Run a spec from the repo root, e.g. `lune run tests/roll.spec.luau`; it exits 1 on any failure.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local H = {}

local passed, failed = 0, 0

function H.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

function H.eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function H.near(actual: number, expected: number, tolerance: number, label: string?)
	if not (math.abs(actual - expected) <= tolerance) then -- written this way so NaN fails
		error(`{label or "value"}: expected ~{expected}, got {actual}`, 2)
	end
end

-- Relative tolerance, for values of any size.
function H.rel(actual: number, expected: number, tolerance: number, label: string?)
	local scale = math.max(math.abs(expected), 1e-300)
	if not (math.abs(actual - expected) / scale <= tolerance) then
		error(`{label or "value"}: expected ~{expected}, got {actual}`, 2)
	end
end

function H.ok(condition: any, label: string?)
	if not condition then
		error(`{label or "condition"} was false`, 2)
	end
end

function H.throws(fn: () -> (), label: string?)
	local ok = pcall(fn)
	if ok then
		error(`{label or "call"} did not error`, 2)
	end
end

function H.json(path: string): any
	return serde.decode("json", fs.readFile(path))
end

-- config/economy.json, read fresh each call so a test can modify its copy.
function H.config(): any
	return H.json("config/economy.json")
end

-- Deterministic RNG (Park–Miller minimal standard). Values are in (0, 1).
function H.rng(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = state * 48271 % 2147483647
		return state / 2147483647
	end
end

-- An RNG that returns these values in order, then errors if asked for more.
function H.sequence(values: { number }): () -> number
	local i = 0
	return function()
		i += 1
		local value = values[i]
		assert(value ~= nil, "sequence RNG ran out of values")
		return value
	end
end

-- Always returns the same value.
function H.constant(value: number): () -> number
	return function()
		return value
	end
end

function H.finish(suite: string)
	print(`{suite}: {passed} passed, {failed} failed`)
	process.exit(if failed > 0 then 1 else 0)
end

return H
