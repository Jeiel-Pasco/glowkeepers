--!strict
-- Boots the client (TECH_SPEC §4): require each controller, Init() all in ORDER, Start() all,
-- then tell the server this client is ready for its PlayerState snapshot.

local Client = script.Parent
local Controllers = Client:WaitForChild("Controllers")
local NetClient = require(Client:WaitForChild("Net"):WaitForChild("NetClient"))

-- Explicit order: a controller may use the controllers listed before it.
local ORDER = {
	"StateController",
	"InputController",
	"MovementController",
	"CycleFXController",
	"PlotController",
	"CampfireController",
	"ForestController",
	"StalkerFXController",
	"DownedController",
	"StealController",
	"LockController",
	"ShieldController",
	"OfflineController",
	"UpgradeController",
	"ShopController",
	"StorageController",
	"RebirthController",
	"GlowdexController",
	"GiftController",
	"QuestController",
	"GoalController",
	"DecorController",
	"LeaderboardController",
	"EventController",
	"StoreController",
	"HUDController",
}

local loaded: { [string]: any } = {}
for _, name in ORDER do
	local module = Controllers:WaitForChild(name)
	assert(module:IsA("ModuleScript"), `Main: controller {name} is not a ModuleScript`)
	loaded[name] = require(module) :: any
end

for _, name in ORDER do
	local controller = loaded[name]
	if controller.Init then
		controller.Init()
	end
end

for _, name in ORDER do
	local controller = loaded[name]
	if controller.Start then
		task.spawn(controller.Start)
	end
end

NetClient.send("ClientReady")
