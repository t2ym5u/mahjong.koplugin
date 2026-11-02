local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TextViewer      = require("ui/widget/textviewer")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase   = require("screen_base")
local DailySeed    = require("daily_seed")
local MenuHelper   = require("menu_helper")
local Board        = lrequire("board")
local BoardWidget  = lrequire("board_widget")
local Layouts      = lrequire("layouts")

local DeviceScreen = Device.screen

local GAME_RULES_EN = [[
Mahjong Solitaire — Rules

Clear the table: take the tiles off two by two, in matching pairs.

• Only free tiles can be taken: a tile is free when no tile lies on it, even partly, and it can slide out to the left or to the right (no tile touching it on at least one of those two sides).
• Two tiles match when they are identical. Any flower matches any flower, and any season any season.
• The game is won when the table is empty.

The tiles: dots, bamboo and characters, numbered 1 to 9; four winds (East, South, West, North); three dragons (red, green, white); four flowers and four seasons. With the "Readable" tile style each suited tile shows its number above its suit sign: a ring for dots, two canes for bamboo, 萬 for characters; winds show their letter, the red dragon is a black box, the green one a box with a letter, the white one an empty frame. The "Traditional" style draws the classic faces.

Stacks: each layer sits a little up and to the right of the one below it, and the higher a tile, the darker its side.

Every deal can be won: it is built backwards from an empty table. Tiles hidden under others can make you choose wrongly, though, and then the table can no longer be cleared.

Controls:
• Tap a free tile to select it (it turns black), then tap a matching free tile: both go. Tap the selected tile again to let it go.
• Undo takes back the last pair (or shuffle).
• Hint: the first tap marks a pair (dashed outline), the second removes it. The hint is checked to keep the table clearable from where you are; if the check runs out of time on a big layout, the hint says so.
• Shuffle deals the faces of the tiles left again, in an order that can be cleared. Use it when no pair is left, or when the hint says the table can no longer be cleared (Undo is the other way out).
• Mark free tiles (menu) greys the tiles you cannot take yet.

Layouts go from Pyramid (56 tiles, big tiles on a 6" screen) to the traditional Turtle (144 tiles). The Daily Challenge is the same deal for everyone today, on the current layout.
]]

local GAME_RULES_FR = [[
Mahjong solitaire — Règles

Videz la table : retirez les tuiles deux par deux, par paires identiques.

• Seules les tuiles libres peuvent être retirées : une tuile est libre si aucune tuile n'est posée dessus, même en partie, et si elle peut glisser vers la gauche ou vers la droite (aucune tuile ne la touche d'au moins un de ces deux côtés).
• Deux tuiles vont ensemble si elles sont identiques. N'importe quelle fleur va avec n'importe quelle fleur, et n'importe quelle saison avec n'importe quelle saison.
• La partie est gagnée quand la table est vide.

Les tuiles : ronds, bambous et caractères, numérotés de 1 à 9 ; quatre vents (Est, Sud, Ouest, Nord) ; trois dragons (rouge, vert, blanc) ; quatre fleurs et quatre saisons. Avec le style de tuiles « Lisible », chaque tuile de couleur montre son chiffre au-dessus de son signe : un rond pour les ronds, deux cannes pour les bambous, 萬 pour les caractères ; les vents montrent leur lettre, le dragon rouge est une case noire, le vert une case avec une lettre, le blanc un cadre vide. Le style « Traditionnel » dessine les faces classiques.

Les piles : chaque étage est un peu décalé vers le haut et la droite par rapport à celui du dessous, et plus une tuile est haute, plus son côté est sombre.

Chaque donne peut être gagnée : elle est construite à l'envers, depuis une table vide. Les tuiles cachées sous d'autres peuvent toutefois vous faire mal choisir, et la table ne peut alors plus être vidée.

Commandes :
• Touchez une tuile libre pour la sélectionner (elle devient noire), puis une tuile libre identique : les deux partent. Touchez à nouveau la tuile sélectionnée pour la relâcher.
• Annuler reprend la dernière paire (ou le dernier mélange).
• Astuce : le premier appui marque une paire (contour pointillé), le second la retire. L'astuce est vérifiée : la table reste vidable depuis la position actuelle ; si la vérification manque de temps sur une grande disposition, l'astuce le dit.
• Mélanger redistribue les faces des tuiles restantes, dans un ordre qui peut être vidé. À utiliser quand il ne reste aucune paire, ou quand l'astuce dit que la table ne peut plus être vidée (Annuler est l'autre solution).
• Marquer les tuiles libres (menu) grise les tuiles qu'on ne peut pas encore prendre.

Les dispositions vont de la Pyramide (56 tuiles, de grandes tuiles sur un écran 6") à la Tortue traditionnelle (144 tuiles). Le Défi du jour est la même donne pour tout le monde aujourd'hui, sur la disposition choisie.
]]

local LAYOUT_LABELS = {
    pyramid    = _("Pyramid"),
    fortress   = _("Fortress"),
    temple     = _("Temple"),
    bridge     = _("Bridge"),
    bigpyramid = _("Big pyramid"),
    turtle     = _("Turtle"),
}

local STYLES = { "readable", "classic" }
local STYLE_LABELS = {
    readable = _("Readable"),
    classic  = _("Traditional"),
}

local MahjongScreen = ScreenBase:extend{}

function MahjongScreen:init()
    self.board = Board:new()
    if not self.board:load(self.plugin:loadState()) then
        self:_newDeal(self:_getLayout())
    end
    ScreenBase.init(self)
end

function MahjongScreen:serializeState()
    return self.board:serialize()
end

function MahjongScreen:_save()
    self.plugin:saveState(self.board:serialize())
end

-- ---------------------------------------------------------------------------
-- Settings and statistics
-- ---------------------------------------------------------------------------

function MahjongScreen:_getLayout()
    local id = self.plugin:getSetting("layout", Layouts.DEFAULT)
    return Layouts.isLayout(id) and id or Layouts.DEFAULT
end

function MahjongScreen:_getStyle()
    local s = self.plugin:getSetting("tile_style", "readable")
    return STYLE_LABELS[s] and s or "readable"
end

function MahjongScreen:_markFree()
    return self.plugin:getSetting("mark_free", false) == true
end

-- Per layout: { played, won, best (seconds) }.
function MahjongScreen:getStats(id)
    local all = self.plugin:getSetting("stats", {})
    local s = type(all) == "table" and all[id] or nil
    if type(s) ~= "table" then s = {} end
    return { played = tonumber(s.played) or 0, won = tonumber(s.won) or 0, best = tonumber(s.best) }
end

function MahjongScreen:_saveStats(id, s)
    local all = self.plugin:getSetting("stats", {})
    if type(all) ~= "table" then all = {} end
    all[id] = s
    self.plugin:saveSetting("stats", all)
end

local function formatTime(secs)
    secs = math.floor(secs or 0)
    if secs >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60)
    end
    return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
end

function MahjongScreen:_newDeal(id, daily)
    if not self.board:newDeal(id, daily) then return false end
    local s = self:getStats(id)
    s.played = s.played + 1
    self:_saveStats(id, s)
    self:_save()
    return true
end

-- Records a win once (the save remembers it, so a restored won game does not
-- count twice).
function MahjongScreen:_recordWin()
    local b = self.board
    if b.recorded then return end
    b.recorded = true
    local s = self:getStats(b.layout)
    s.won = s.won + 1
    local t = math.floor(b.timer:getElapsed())
    self.new_best = not s.best or t < s.best
    if self.new_best then s.best = t end
    self:_saveStats(b.layout, s)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function MahjongScreen:_buildControls(width, two_rows)
    local undo    = { id = "undo_btn",    text = _("Undo"),    callback = function() self:onUndo() end }
    local hint    = { id = "hint_btn",    text = _("Hint"),    callback = function() self:onHint() end }
    local shuffle = { id = "shuffle_btn", text = _("Shuffle"), callback = function() self:onShuffle() end }
    self.status_text:setMaxWidth(width)
    local action_bar = self:buildActionBar(two_rows and { { undo, hint }, { shuffle } } or { undo, hint, shuffle }, width)
    self.undo_btn    = action_bar:getButtonById("undo_btn")
    self.shuffle_btn = action_bar:getButtonById("shuffle_btn")
    return VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }
end

function MahjongScreen:buildLayout()
    local is_landscape = self:isLandscape()
    local title_bar = self:buildTitleBar(_("Mahjong Solitaire"), function()
        local items = {
            { text = _("New game"), callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = T(_("Layout: %1"), LAYOUT_LABELS[self:_getLayout()]),
              callback = function() self:openLayoutMenu() end },
            { text = T(_("Tile style: %1"), STYLE_LABELS[self:_getStyle()]),
              callback = function() self:openStyleMenu() end },
            { text = T(_("Mark free tiles: %1"), self:_markFree() and _("On") or _("Off")),
              callback = function() self:onToggleMarkFree() end },
            { text = _("Statistics"), callback = function() self:showStatistics() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
        return items
    end)

    -- The board is much wider than tall, so in landscape the controls may
    -- give it more room under it than beside it: take whichever gives the
    -- bigger tiles.
    local g = self:getGutter()
    local sw, sh = self.dimen.w, self.dimen.h
    local tb_h = title_bar:getSize().h
    local frame_pad = Size.padding.default
    local L = self.board.L
    local full_w = sw - 2 * g
    local controls = self:_buildControls(full_w, false)
    local below_w = full_w - 2 * frame_pad
    local below_h = sh - tb_h - controls:getSize().h - 3 * g - 2 * frame_pad
    local side = false
    if is_landscape then
        local side_w = self:getControlsWidth()
        local bw = sw - side_w - 3 * g - 2 * frame_pad
        local bh = sh - tb_h - 2 * g - 2 * frame_pad
        if BoardWidget.fitTileWidth(L, bw, bh) > BoardWidget.fitTileWidth(L, below_w, below_h) then
            side = true
            controls = self:_buildControls(side_w, true)
            below_w, below_h = bw, bh
        end
    end

    self.board_widget = BoardWidget:new{
        board           = self.board,
        max_width       = math.max(below_w, 60),
        max_height      = math.max(below_h, 60),
        style           = self:_getStyle(),
        mark_free       = self:_markFree(),
        tileTapCallback = function(i) self:onTileTap(i) end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }
    self:_updateButtons()

    if side then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = g },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = g } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Interaction
-- ---------------------------------------------------------------------------

-- After anything that changed the table: the save, the win, one repaint.
function MahjongScreen:_afterMove(msg)
    local b = self.board
    if b:isWon() then self:_recordWin() end
    self:_save()
    self:_updateButtons()
    self:updateStatus(msg)
end

function MahjongScreen:onTileTap(i)
    local b = self.board
    if b:isWon() then return end
    if not i then
        if b.selected then
            b.selected = nil
            self:updateStatus()
        end
        return
    end
    local what = b:tap(i)
    if what == "remove" then
        self:_afterMove()
    elseif what == "blocked" then
        self:updateStatus(_("This tile is not free."))
    elseif what then
        self:updateStatus()
    end
end

function MahjongScreen:onUndo()
    if self.board:undo() then self:_afterMove() end
end

function MahjongScreen:onShuffle()
    local b = self.board
    if b:isWon() then return end
    if b:shuffle() then
        self:_afterMove(_("Tiles shuffled: the game can be won again."))
    else
        self:updateStatus(_("Shuffling cannot help here: use Undo."))
    end
end

-- Two taps, as everywhere in the fleet: the first marks a pair, the second
-- takes it off.
function MahjongScreen:onHint()
    local b = self.board
    if b:isWon() then return end
    local shown = b.hint
    if shown and b.present[shown.a] and b.present[shown.b] then
        if b:applyHint(shown) then
            b:noteHintUsed()
            self:_afterMove(not b:isWon() and T(_("Pair taken off. Hints used: %1."), b:getHintsUsed()) or nil)
        end
        return
    end
    local step, why = b:findHint()
    if not step then
        b.hint = nil
        if why == "lost" then
            self:updateStatus(_("The game can no longer be won: Undo or Shuffle."))
        elseif why == "stuck" then
            self:updateStatus(_("No pair left: Undo or Shuffle."))
        end
        return
    end
    b.hint = step
    b.selected = nil
    local msg
    if step.kind == "plan" then
        msg = _("The marked pair keeps the game winnable.")
    elseif step.kind == "safe" then
        msg = _("The marked pair can never do harm.")
    else
        msg = _("A free pair (no time to check it is safe).")
    end
    self:updateStatus(msg)
end

function MahjongScreen:onNewGame()
    self:_newDeal(self:_getLayout())
    self.new_best = nil
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- Today's deal: built under the daily seed, so everyone on the same layout
-- gets the same tiles today.
function MahjongScreen:onDailyGame()
    local id = self:_getLayout()
    local plugin = self.plugin
    local key = (plugin.getPluginId and plugin:getPluginId() or plugin.name) .. "_" .. id
    DailySeed.run(key, function()
        self:_newDeal(id, os.date("%Y-%m-%d"))
    end)
    self.new_best = nil
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function MahjongScreen:_statsLine(id)
    local s = self:getStats(id)
    local parts = { T(_("Won: %1/%2"), s.won, s.played) }
    if s.best then parts[#parts + 1] = T(_("Best: %1"), formatTime(s.best)) end
    return table.concat(parts, " · ")
end

function MahjongScreen:openLayoutMenu()
    local items = {}
    for _i, id in ipairs(Layouts.IDS) do
        items[#items + 1] = {
            id   = id,
            -- "✓ won/played": the Statistics entry spells it out.
            text = self:joinStatus(T("%1 (%2)", LAYOUT_LABELS[id], Layouts.count(id)),
                T("✓ %1/%2", self:getStats(id).won, self:getStats(id).played)),
        }
    end
    MenuHelper.openPickerMenu{
        title      = _("Layout"),
        items      = items,
        current_id = self:_getLayout(),
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting("layout", id)
            self:onNewGame()
        end,
    }
end

function MahjongScreen:openStyleMenu()
    local items = {}
    for _i, id in ipairs(STYLES) do
        items[#items + 1] = { id = id, text = STYLE_LABELS[id] }
    end
    MenuHelper.openPickerMenu{
        title      = _("Tile style"),
        items      = items,
        current_id = self:_getStyle(),
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting("tile_style", id)
            self:buildLayout()
            UIManager:setDirty(self, function() return "ui", self.dimen end)
        end,
    }
end

function MahjongScreen:onToggleMarkFree()
    self.plugin:saveSetting("mark_free", not self:_markFree())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function MahjongScreen:showStatistics()
    local lines = {}
    for _i, id in ipairs(Layouts.IDS) do
        lines[#lines + 1] = T("%1 (%2)", LAYOUT_LABELS[id], T(_("%1 tiles"), Layouts.count(id)))
        lines[#lines + 1] = "    " .. self:_statsLine(id)
    end
    local viewer = TextViewer:new{
        title  = _("Statistics"),
        text   = table.concat(lines, "\n"),
        width  = math.floor(DeviceScreen:getWidth() * 0.9),
        height = math.floor(DeviceScreen:getHeight() * 0.7),
    }
    UIManager:show(viewer)
    return viewer
end

-- ---------------------------------------------------------------------------
-- Round over: the table is empty.
-- ---------------------------------------------------------------------------

function MahjongScreen:isRoundOver()
    return self.board:isWon()
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

function MahjongScreen:updateStatus(msg)
    local b = self.board
    local status
    if msg then
        status = msg
    elseif b:isWon() then
        local t = formatTime(b.timer:getElapsed())
        if self.new_best then
            status = T(_("Table cleared in %1, a new best!"), t)
        else
            status = T(_("Table cleared in %1."), t)
        end
    elseif b:isStuck() then
        status = _("No pair left: Undo or Shuffle.")
    else
        status = self:joinStatus(
            b.daily and _("Daily Challenge") or LAYOUT_LABELS[b.layout],
            T(_("Tiles left: %1"), b:tilesLeft()),
            T(_("Free pairs: %1"), b:movesAvailable()))
    end
    ScreenBase.updateStatus(self, status)
    self:refreshActionBar()
end

function MahjongScreen:_updateButtons()
    if self.undo_btn then self.undo_btn:enableDisable(self.board:canUndo()) end
end

return MahjongScreen
