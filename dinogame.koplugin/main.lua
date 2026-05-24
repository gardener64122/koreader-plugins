--[[
    Steve the Dino - Real-Time E-Ink Edition
]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local GestureRange = require("ui/gesturerange")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")

local TICK = 0.06
local FULL_REFRESH_SCORE = 100
local TRACK_LEN = 20
local JUMP_TICKS = 8
local FRAMES_PER_MOVE = 2

local DinoCanvas = InputContainer:extend{
    width = nil,
    height = nil,
    score = 0,
    jumping = false,
    jump_ticks_left = 0,
    alive = true,
    cacti = {},
    tick_count = 0,
    last_full_refresh_score = 0,
    running = false,
    _frame = nil,
}

function DinoCanvas:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Screen:getHeight()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.running = true
    self.cacti = {}

    self.ges_events = {
        TapJump = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = self.width,
                    h = self.height,
                },
            },
        },
        HoldJump = {
            GestureRange:new{
                ges = "hold_release",
                range = Geom:new{
                    x = 0, y = 0,
                    w = self.width,
                    h = self.height,
                },
            },
        },
    }

    self:spawnCactus()
end

function DinoCanvas:onTapJump()
    if not self.alive then return true end
    if not self.jumping then
        self.jumping = true
        self.jump_ticks_left = JUMP_TICKS
    end
    return true
end

function DinoCanvas:onHoldRelease()
    return self:onTapJump()
end

function DinoCanvas:onCloseWidget()
    self.running = false
end

function DinoCanvas:spawnCactus()
    table.insert(self.cacti, { x = TRACK_LEN + math.random(4, 10) })
end

function DinoCanvas:tick()
    if not self.running then return end
    if not self.alive then return end

    self.tick_count = self.tick_count + 1

    if self.tick_count % FRAMES_PER_MOVE == 0 then
        for i = #self.cacti, 1, -1 do
            self.cacti[i].x = self.cacti[i].x - 1
            if self.cacti[i].x <= 0 then
                table.remove(self.cacti, i)
                self.score = self.score + 1
                self:spawnCactus()
            end
        end
    end

    if self.jumping then
        self.jump_ticks_left = self.jump_ticks_left - 1
        if self.jump_ticks_left <= 0 then
            self.jumping = false
        end
    end

    for _, cactus in ipairs(self.cacti) do
        if cactus.x <= 3 and cactus.x >= 1 and not self.jumping then
            self.alive = false
            self:onDeath()
            return
        end
    end

    if self.score > 0 and self.score >= self.last_full_refresh_score + FULL_REFRESH_SCORE then
        self.last_full_refresh_score = self.score
        Screen:refreshFull()
    end

    UIManager:setDirty(self._frame, function()
        return "fast", Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    end)
    UIManager:scheduleIn(TICK, function() self:tick() end)
end

function DinoCanvas:onDeath()
    self.running = false
    UIManager:setDirty(self._frame, function()
        return "fast", Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    end)
    UIManager:scheduleIn(1.0, function()
        UIManager:close(self._frame)
        UIManager:show(InfoMessage:new{
            text = string.format("Game Over!\n\nFinal Score: %d", self.score),
        })
    end)
end

function DinoCanvas:paintTo(bb, x, y)
    bb:fill(Blitbuffer.COLOR_WHITE)

    local w = self.width
    local h = self.height
    local ground_y = math.floor(h * 0.72)
    local dino_x = math.floor(w * 0.15)

    bb:paintRect(0, ground_y, w, 2, Blitbuffer.COLOR_BLACK)

    local score_w = math.min(self.score * 3, w - 20)
    if score_w > 0 then
        bb:paintRect(10, 10, score_w, 8, Blitbuffer.COLOR_BLACK)
    end

    local dino_y
    if self.jumping then
        local ratio = 1 - math.abs((self.jump_ticks_left / JUMP_TICKS) - 0.5) * 2
        local jump_height = math.floor(h * 0.18 * ratio)
        dino_y = ground_y - 48 - jump_height
    else
        dino_y = ground_y - 48
    end

    bb:paintRect(dino_x,      dino_y + 8, 28, 28, Blitbuffer.COLOR_BLACK)
    bb:paintRect(dino_x + 10, dino_y,     22, 18, Blitbuffer.COLOR_BLACK)
    bb:paintRect(dino_x + 26, dino_y + 3,  4,  4, Blitbuffer.COLOR_WHITE)

    if not self.jumping then
        if self.tick_count % 4 < 2 then
            bb:paintRect(dino_x + 4,  ground_y - 16, 8, 16, Blitbuffer.COLOR_BLACK)
            bb:paintRect(dino_x + 16, ground_y - 10, 8, 10, Blitbuffer.COLOR_BLACK)
        else
            bb:paintRect(dino_x + 4,  ground_y - 10, 8, 10, Blitbuffer.COLOR_BLACK)
            bb:paintRect(dino_x + 16, ground_y - 16, 8, 16, Blitbuffer.COLOR_BLACK)
        end
    else
        bb:paintRect(dino_x + 4,  dino_y + 28, 8, 10, Blitbuffer.COLOR_BLACK)
        bb:paintRect(dino_x + 16, dino_y + 28, 8, 10, Blitbuffer.COLOR_BLACK)
    end

    for _, cactus in ipairs(self.cacti) do
        local cx = math.floor(dino_x + (cactus.x / TRACK_LEN) * (w - dino_x - 40))
        if cx > 0 and cx < w then
            bb:paintRect(cx + 6,  ground_y - 40,  8, 40, Blitbuffer.COLOR_BLACK)
            bb:paintRect(cx,      ground_y - 30,  6,  4, Blitbuffer.COLOR_BLACK)
            bb:paintRect(cx,      ground_y - 38,  4, 12, Blitbuffer.COLOR_BLACK)
            bb:paintRect(cx + 14, ground_y - 28,  6,  4, Blitbuffer.COLOR_BLACK)
            bb:paintRect(cx + 16, ground_y - 38,  4, 14, Blitbuffer.COLOR_BLACK)
        end
    end
end

local DinoGame = WidgetContainer:extend{
    name = "dinogame",
    is_doc_only = false,
}

function DinoGame:init()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function DinoGame:addToMainMenu(menu_items)
    menu_items.dinogame_trigger = {
        text = "Play Steve the Dino",
        sorting_hint = "more_tools",
        callback = function()
            self:startGame()
        end,
    }
end

function DinoGame:startGame()
    math.randomseed(os.time())

    local canvas = DinoCanvas:new{
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }

    local frame = FrameContainer:new{
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        canvas,
    }

    canvas._frame = frame
    UIManager:show(frame)
    UIManager:scheduleIn(TICK, function() canvas:tick() end)
end

return DinoGame
