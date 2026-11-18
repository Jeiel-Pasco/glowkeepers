# Vendor

Put loleris's **ProfileStore** module here as `ProfileStore.luau`
(https://github.com/MadStudioRoblox/ProfileStore). DataService looks for
`ServerScriptService.Server.Vendor.ProfileStore`.

Without it, DataService runs on an in-memory store and prints a warning. Nothing is
saved in that mode, and a PROD server refuses to start sessions at all.

Current copy: `ProfileStore.luau` from the `main` branch, downloaded 18 Nov 2026 (2,242 lines),
unmodified. Apache-2.0: keep its header intact. Selene and StyLua skip this folder
(`selene.toml`, `.styluaignore`); to update, replace the file and note the new date here.
