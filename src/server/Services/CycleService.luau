--!strict
-- Owner of the day/night cycle (GAME_SYSTEMS §2, TECH_SPEC §6).
--
-- Picks the epoch at server start (servers are deliberately not in sync) and publishes it as
-- workspace attributes CycleEpoch, DayLen and NightLen. Everyone derives the phase from those
-- with Shared.Cycle. This service fires a signal at each phase change and picks tonight's
-- modifier at the dusk warning (workspace attribute NightModifier, cleared at dawn).
--
-- DEV/BETA: set the server-side workspace attribute DebugSkipPhase = true (Studio command bar
-- or Properties) to jump everyone to the next phase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cycle = require(Shared:WaitForChild("Cycle"))
local Env = require(Shared:WaitForChild("Env"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local economy = require(Shared:WaitForChild("Config"):WaitForChild("economy")) :: any

local CycleService = {}
CycleService.PhaseChanged = Signal.new() -- (phase: Cycle.Phase, state: Cycle.State); "Day" = dawn
CycleService.StalkerAwake = Signal.new() -- (state): the night's grace period is over

local epoch = 0
local random = Random.new()
local lastPhase: Cycle.Phase? = nil
local lastIndex = -1
local stalkerWasActive = false
local lastModifierId: string? = nil
local modifierPickedFor = -1 -- cycle index whose night modifier has been picked
local tonight: any? = nil

local function publishEpoch()
	workspace:SetAttribute("CycleEpoch", epoch)
	workspace:SetAttribute("DayLen", economy.cycle.daySeconds)
	workspace:SetAttribute("NightLen", economy.cycle.nightSeconds)
end

function CycleService.get(): Cycle.State
	return Cycle.at(economy, epoch, workspace:GetServerTimeNow())
end

-- Tonight's modifier from config (e.g. { id = "Gusty", fireDrainMult = 1.25 }), or nil.
function CycleService.modifier(): any?
	return tonight
end

function CycleService.skipPhase()
	assert(Env.get().name ~= "PROD", "skipPhase is disabled in PROD")
	epoch = Cycle.skipEpoch(economy, epoch, workspace:GetServerTimeNow())
	publishEpoch()
end

local function pickModifier(index: number)
	modifierPickedFor = index
	tonight = Cycle.pickModifier(economy, lastModifierId, random:NextNumber(), random:NextNumber())
	if tonight ~= nil then
		lastModifierId = tonight.id
	end
	workspace:SetAttribute("NightModifier", if tonight ~= nil then tonight.id else nil)
end

local function tick()
	local state = CycleService.get()
	if state.phase ~= lastPhase or state.index ~= lastIndex then
		-- A slow frame can jump straight from Day to Night; the modifier still gets picked.
		if (state.phase == "Dusk" or state.phase == "Night") and modifierPickedFor ~= state.index then
			pickModifier(state.index)
		elseif state.phase == "Day" then
			tonight = nil
			workspace:SetAttribute("NightModifier", nil)
		end
		lastPhase = state.phase
		lastIndex = state.index
		CycleService.PhaseChanged:Fire(state.phase, state)
	end
	if state.stalkerActive and not stalkerWasActive then
		CycleService.StalkerAwake:Fire(state)
	end
	stalkerWasActive = state.stalkerActive
end

function CycleService.Init()
	epoch = workspace:GetServerTimeNow()
	publishEpoch()

	if Env.get().name ~= "PROD" then
		workspace:GetAttributeChangedSignal("DebugSkipPhase"):Connect(function()
			if workspace:GetAttribute("DebugSkipPhase") == true then
				workspace:SetAttribute("DebugSkipPhase", false)
				CycleService.skipPhase()
			end
		end)
	end
end

function CycleService.Start()
	RunService.Heartbeat:Connect(tick)
end

return CycleService
