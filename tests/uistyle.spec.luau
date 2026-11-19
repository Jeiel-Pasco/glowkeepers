-- HUD skin colours (Shared.UIStyle).
local H = require("./harness")
local UIStyle = require("../src/shared/UIStyle")

H.test("dark panels take the plum panel and a gold rim", function()
	local s = UIStyle.skin({ 16, 18, 32 })
	H.eq(s.fill, UIStyle.PANEL)
	H.eq(s.rim, UIStyle.RIM)
	H.eq(UIStyle.isDark(UIStyle.PANEL), true, "the panel itself stays dark")
end)

H.test("coloured buttons keep their colour with a darker rim", function()
	local blue = { 70, 140, 220 }
	local s = UIStyle.skin(blue)
	H.eq(s.fill, blue)
	H.eq(s.rim[1] < blue[1] and s.rim[2] < blue[2] and s.rim[3] < blue[3], true)
end)

H.test("shade stays in 0..255", function()
	H.eq(UIStyle.shade({ 255, 0, 128 }, 1)[2], 255)
	H.eq(UIStyle.shade({ 255, 0, 128 }, -1)[1], 0)
	H.eq(UIStyle.shade({ 100, 100, 100 }, 0)[1], 100)
end)

H.finish("uistyle")
