--!strict
-- Live config (TECH_SPEC §10): reads the DataStore key `LiveConfig/current` (a JSON string or a
-- table) at boot and every live.pollSeconds, and merges it over live.defaults with
-- Shared.LiveConfig. A failed read keeps the last good value.
--
-- Used by: StealService (kill switch "stealing"), EventService (the event and its multipliers).
-- Kill switches for trading, serverLuck and products are read when those features land.
--
-- Replicates: workspace attributes `LiveEventId` and `LiveEventEnds` (server time) while an
-- event runs, for the client HUD.
-- DEV/BETA: workspace attribute DebugLiveConfig = a JSON string replaces the DataStore value
-- ("" goes back to it).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Env = require(Shared:WaitForChild("Env"))
local LiveConfig = require(Shared:WaitForChild("LiveConfig"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any

local LiveConfigService = {}
LiveConfigService.Changed = Signal.new() -- (live): after every read that changed something

local live: LiveConfig.Live = LiveConfig.merge(economy, nil)
local lastJson = ""
local debugRaw: any = nil -- the DebugLiveConfig override

function LiveConfigService.get(): LiveConfig.Live
	return live
end

function LiveConfigService.killed(name: string): boolean
	return LiveConfig.killed(live, name)
end

function LiveConfigService.event(): { [string]: any }?
	return LiveConfig.event(live, os.time())
end

function LiveConfigService.mult(key: string): number
	return LiveConfig.mult(live, key, os.time())
end

local function decode(value: any): any
	if type(value) == "string" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(value)
		end)
		return if ok then decoded else nil
	end
	return value
end

local function publishEvent()
	local event = LiveConfigService.event()
	workspace:SetAttribute("LiveEventId", if event then event.id else nil)
	-- Unix end → server time (both count seconds; the offset is ~0 but kept exact).
	local offset = workspace:GetServerTimeNow() - os.time()
	workspace:SetAttribute("LiveEventEnds", if event then event["end"] + offset else nil)
end

local function apply(raw: any)
	local merged = LiveConfig.merge(economy, raw)
	local json = HttpService:JSONEncode(merged)
	if json ~= lastJson then
		lastJson = json
		live = merged
		LiveConfigService.Changed:Fire(live)
	end
	publishEvent()
end

local function read()
	if debugRaw ~= nil then
		apply(debugRaw)
		return
	end
	local ok, value = pcall(function()
		return DataStoreService:GetDataStore("LiveConfig"):GetAsync("current")
	end)
	if ok then
		apply(decode(value))
	else
		warn(`[LiveConfigService] read failed, keeping the last value: {value}`)
		publishEvent()
	end
end

function LiveConfigService.Init()
	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugLiveConfig"):Connect(function()
			local value = workspace:GetAttribute("DebugLiveConfig")
			debugRaw = if type(value) == "string" and value ~= "" then decode(value) else nil
			task.spawn(read)
		end)
	end
end

-- Re-reads the DataStore value now (after an admin edit) instead of at the next poll.
function LiveConfigService.refresh()
	task.spawn(read)
end

function LiveConfigService.Start()
	task.spawn(function()
		while true do
			read()
			-- Poll on schedule, but also catch an event's start or end within a minute.
			local waited = 0
			while waited < economy.live.pollSeconds do
				task.wait(60)
				waited += 60
				publishEvent()
			end
		end
	end)
end

return LiveConfigService
