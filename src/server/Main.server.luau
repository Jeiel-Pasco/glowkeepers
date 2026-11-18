--!strict
-- Boots the server (TECH_SPEC §4): require every service, call Init() on each in ORDER, then
-- Start() on each. Init sets up state and connections and must not yield; Start may yield
-- and loop (each runs in its own thread).

local Services = script.Parent:WaitForChild("Services")

-- Explicit order: a service may use the services listed before it during Init.
local ORDER = {
	"Telemetry",
	"DataService",
	"SettingsService",
	"CycleService",
}

local loaded: { [string]: any } = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	assert(module ~= nil and module:IsA("ModuleScript"), `Main: service {name} is missing`)
	loaded[name] = require(module) :: any
end

for _, child in Services:GetChildren() do
	if child:IsA("ModuleScript") and table.find(ORDER, child.Name) == nil then
		warn(`Main: {child.Name} is not in ORDER, so it never starts`)
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service.Init then
		service.Init()
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service.Start then
		task.spawn(service.Start)
	end
end
