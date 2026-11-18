--!strict
-- Thin wrapper over AnalyticsService (TECH_SPEC §9).
--
-- Every call is wrapped in pcall: analytics must never break gameplay. Custom fields are a list
-- of at most 3 low-cardinality strings (rarity names, never UUIDs or user ids); they map to
-- CustomField01..03. In Studio every event is also printed.

local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local Telemetry = {}
Telemetry.verbose = RunService:IsStudio()

local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

local function fieldsFrom(list: { string }?): { [string]: string }?
	if list == nil then
		return nil
	end
	assert(#list <= #FIELD_KEYS, "Telemetry: at most 3 custom fields")
	local fields = {}
	for i, value in list do
		fields[FIELD_KEYS[i]] = value
	end
	return fields
end

local function run(label: string, fn: () -> ())
	if Telemetry.verbose then
		print(`[Telemetry] {label}`)
	end
	local ok, err = pcall(fn)
	if not ok then
		warn(`[Telemetry] {label} failed: {err}`)
	end
end

-- FTUE steps 1–10 (GAME_SYSTEMS §22).
function Telemetry.onboarding(player: Player, step: number, stepName: string, fields: { string }?)
	run(`onboarding {step} {stepName}`, function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, fieldsFrom(fields))
	end)
end

-- Recurring funnels: FirstRebirth, Store, Trade.
function Telemetry.funnel(
	player: Player,
	funnelName: string,
	sessionId: string?,
	step: number,
	stepName: string,
	fields: { string }?
)
	run(`funnel {funnelName} {step} {stepName}`, function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName, fieldsFrom(fields))
	end)
end

-- Glow and Embers sources and sinks. `amount` is positive; `flow` says which way it went.
function Telemetry.economy(
	player: Player,
	flow: "Source" | "Sink",
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?,
	fields: { string }?
)
	if amount <= 0 then
		return
	end
	local flowType = if flow == "Source"
		then Enum.AnalyticsEconomyFlowType.Source
		else Enum.AnalyticsEconomyFlowType.Sink
	run(`economy {flow} {currency} {amount} {transactionType}`, function()
		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			currency,
			amount,
			endingBalance,
			transactionType,
			itemSku,
			fieldsFrom(fields)
		)
	end)
end

function Telemetry.custom(player: Player, eventName: string, value: number?, fields: { string }?)
	run(`custom {eventName}`, function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1, fieldsFrom(fields))
	end)
end

return Telemetry
