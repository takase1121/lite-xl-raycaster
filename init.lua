-- mod-version:2
-- lite-xl-raycaster?

local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"

local bresenham = require "plugins.raycaster.bresenham"

local conf = common.merge(config.plugins.raycaster, {
	map = USERDIR .. "/plugins/raycaster/map.txt"
})

local map_size = 64

local Raycaster = View:extend()

local entities = {
	wall = string.byte "x",
	empty = string.byte " ",
	player = string.byte "p"
}

function Raycaster:new(map)
	Raycaster.super.new(self)
	self.screen = { w = 640, h = 480 }
	self.player = { x = 0, y = 0, dx = 0, dy = 0, a = 0 }
	self.direction = { x = 1, y = 0 }
	self.time = { old = 0, now = 0 }

	self.close = style.caret
	self.far = {}
	for i, v in ipairs(style.caret) do
		self.far[i] = v * 1/0.5
	end

	self.map = { w = 0, h = 0 }
	local first = true
	for line in io.lines(map) do
		if first then
			self.map.w = #line
		elseif #line ~= self.map.w then
			error "invalid map"
		end

		for c in line:gmatch(".") do
			local i = #self.map + 1
			self.map[i] = c:byte()
			if self.map[i] == entities.player then
				self.player.x = math.floor((i - 1) % self.map.w)
				self.player.y = math.floor((i - 1) / self.map.w)
			end
		end
		self.map.h = self.map.h + 1
	end
end

function Raycaster:draw_player(ox, oy)
	local px, py = math.floor(ox + self.player.x * 8), math.floor(oy + self.player.y * 8)
	renderer.draw_rect(
		px, py,
		8,
		8,
		style.accent
	)
	local ex = ox + math.floor(self.player.x + (math.cos(self.player.a) * 5)) * 8
	local ey = oy + math.floor(self.player.y + (math.sin(self.player.a) * 5)) * 8
	bresenham.los(px, py, ex, ey, function(x, y)
		renderer.draw_rect(x, y, 2, 2, style.caret)
		return true
	end)
end

local function fix_rad(a)
	if a < 0 then a = a + 2 * math.pi end
	if a > 2 * math.pi then a = a - 2 * math.pi end
	return a
end

local function drad(d)
	return d * math.pi / 180
end

function Raycaster:cast(ox, oy)
	local ra = self.player.a - drad(30) -- TODO: make this variable
	local px, py = self.player.x, self.player.y
	local rx, ry, rc, rs, dof
	local mp, lh, lo
	for i = 1, 60 do
		rx, ry = px, py

		rc, rs = math.cos(ra) / 64, math.sin(ra / 64)

		dof = 0
		while dof < 8 do
			rx, ry = rx + rc, ry + rs
			mp = math.floor(ry) * self.map.w + math.floor(rx) + 1
			if self.map[mp] ~= entities.empty then
				-- hit wall
				dof = 8
			else
				dof = dof + 1
			end
		end

		local d = (((px - rx) ^ 2) + ((py - ry) ^ 2)) ^ 0.5
		d = d * math.cos(ra - self.player.a) -- fisheye fix

		lh = (self.screen.h / 2) / d
		lo = (self.screen.h / 2) - (lh / 2)

		renderer.draw_rect(ox + (i - 1) * 8, math.floor(oy + lo), 8, math.floor(lh), style.caret)
		
		ra = ra + (60/self.screen.w) -- TODO: precalc inc angle
	end
end

function Raycaster:draw_map(ox, oy)
	for my = 0, self.map.h - 1 do
		for mx = 0, self.map.w - 1 do
			if self.map[my * self.map.w + mx + 1] == entities.wall then
				-- draw the thing
				local x, y = ox + mx * 8, oy + my * 8
				renderer.draw_rect(x, y, 8, 8, style.caret)
			end
		end
	end
end

function Raycaster:update()
	Raycaster.super.update(self)
	self.screen.w = math.floor(self.size.x / 2)
	self.screen.h = math.floor(self.size.y / 2)
end

function Raycaster:draw()
	self:draw_background(style.background)

	local ox, oy = self:get_content_offset()
	ox, oy = ox + style.padding.x, oy + style.padding.y
	self:draw_map(ox + self.screen.w + style.padding.x, oy)
	self:draw_player(ox + self.screen.w + style.padding.x, oy)
	self:cast(ox, oy)
end

command.add(nil, {
	["raycaster:open"] = function()
		local node = core.root_view:get_active_node()
		node:add_view(Raycaster(conf.map))
	end
})

local function predicate()
	return core.active_view:is(Raycaster)
end

command.add(predicate, {
	["raycaster:up"] = function()
		local r = core.active_view
		r.player.x = r.player.x + r.player.dx
		r.player.y = r.player.y + r.player.dy
	end,
	["raycaster:down"] = function()
		local r = core.active_view
		r.player.x = r.player.x - r.player.dx
		r.player.y = r.player.y - r.player.dy
	end,
	["raycaster:left"] = function()
		local r = core.active_view
		r.player.a = r.player.a - 0.1
		r.player.a = fix_rad(r.player.a)
		r.player.dx = math.cos(r.player.a)
		r.player.dy = math.sin(r.player.a)
	end,
	["raycaster:right"] = function()
		local r = core.active_view
		r.player.a = r.player.a + 0.1
		r.player.a = fix_rad(r.player.a)
		r.player.dx = math.cos(r.player.a)
		r.player.dy = math.sin(r.player.a)
	end
})

keymap.add {
	["up"] = "raycaster:up",
	["down"] = "raycaster:down",
	["left"] = "raycaster:left",
	["right"] = "raycaster:right",
}
