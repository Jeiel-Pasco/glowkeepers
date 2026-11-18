--!strict
-- Input for touch, keyboard/mouse and gamepad (TECH_SPEC §4).
--
-- One context button does whatever is relevant right now: Catch, Grab, Feed, Revive or Place.
-- Gameplay controllers offer a label with a priority on every check, or nil to withdraw it
-- (InputController.offer); the highest offer shows. Keyboard: E. Gamepad: X. Touch: an
-- on-screen button. Hold actions (Grab, Revive) use the began/ended pair; the server times
-- the hold.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local CONTEXT_ACTION = "GlowkeepersContext"
local CONTEXT_KEYS = { Enum.KeyCode.E, Enum.KeyCode.ButtonX }

local InputController = {}
InputController.Action = Signal.new() -- (label: string, began: boolean)

type Offer = { label: string, priority: number }

local contextLabel: string? = nil
local bound = false
local offers: { [string]: Offer } = {}

local function onContext(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	local label = contextLabel
	if label == nil then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		InputController.Action:Fire(label, true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		InputController.Action:Fire(label, false)
	end
	return Enum.ContextActionResult.Sink
end

-- Show the context button with this label, or hide it with nil.
function InputController.setContext(label: string?)
	if label == contextLabel then
		return
	end
	contextLabel = label
	if label == nil then
		if bound then
			ContextActionService:UnbindAction(CONTEXT_ACTION)
			bound = false
		end
		return
	end
	if not bound then
		ContextActionService:BindAction(CONTEXT_ACTION, onContext, true, table.unpack(CONTEXT_KEYS))
		bound = true
	end
	ContextActionService:SetTitle(CONTEXT_ACTION, label)
end

function InputController.context(): string?
	return contextLabel
end

-- `source` (a controller's name) wants the button to say `label`, or nothing with nil. The
-- highest priority wins; give each source its own priority so two never tie.
function InputController.offer(source: string, label: string?, priority: number)
	offers[source] = if label ~= nil then { label = label, priority = priority } else nil
	local best: Offer? = nil
	for _, offer in offers do
		if best == nil or offer.priority > best.priority then
			best = offer
		end
	end
	InputController.setContext(if best ~= nil then best.label else nil)
end

return InputController
