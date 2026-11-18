# Vendor

Put loleris's **ProfileStore** module here as `ProfileStore.luau`
(https://github.com/MadStudioRoblox/ProfileStore). DataService looks for
`ServerScriptService.Server.Vendor.ProfileStore`.

Without it, DataService runs on an in-memory store and prints a warning. Nothing is
saved in that mode, and a PROD server refuses to start sessions at all.
