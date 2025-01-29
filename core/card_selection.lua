
if not AMA then AMA = {} end

-- ---------- Imports ----------
--- @module 'inspect'
local inspect, err = SMODS.load_file("lib/inspect.lua")()
if err then
	print("Error loading library `inspect`: " .. err)
	error(err)
end

-- ---------- Local Variables ----------

G.kb_select_offset = 0

-- ----- Voxlatro Class Object -----

-- TODO: We should not name this class Amilatro. Come up with a better name.
--       I don't remember if our objection was that `Amilatro` was just a name we didn't like in general.
--       Or if we wanted a name that more aligned with card selection? I think it was the latter.

--- @class Voxlatro
--- @field selected_id? string The Area ID of the currently selected card area. Such as 'hand', 'jokers', 'consumeables', 'shop_jokers', 'shop_vouchers', 'shop_booster', 'pack_cards'
--- @field last_state string? Used in Card:update() to track the last state G.STATE was in. When G.STATE changes, we reset Vars and potentially set it as unsafe to cash out.
--- @field last_highlighted Card? The last card that was highlighted
AMA.Voxlatro = Object:extend()

-- --- Voxlatro Class Methods ---
function AMA.Voxlatro:init()
	self.selected_id = nil
	self.last_state = nil
	self.last_highlighted = nil

    -- --- Debug Variables ---
    self.last_card_dumped = 0 -- nil
    self.info_dump_mode = "off"  -- Valid Values: "off", "trigger", "once"
    self.last_card_info_dump_time = love.timer.getTime()  -- Units: Seconds
    self.dump_card_info_interval = 0.5  -- Units: Seconds

end

-- ---------- Initialization ----------
local dprint = AMA.dprint

---@type Voxlatro
local amy = AMA.Voxlatro()
amy:init()


-- ---------- Validation ----------

-- ---------- Local Functions ----------

function AMA.Voxlatro:reset_vars()
	if G.kb_selected_area then G.kb_selected_area:unhighlight_all() end
	G.kb_selected_area = nil
	self.selected_id = nil
	if self.last_highlighted then
		self.last_highlighted:stop_hover()
		self.last_highlighted = nil
	end
end

function AMA.Voxlatro:can(action)
	local fakebutton = {config = {}}
	G.FUNCS["can_" .. action](fakebutton)
	return fakebutton.config.button ~= nil
end

--- Returns the number of cards in the current card area
--- @return number The number of cards in the current card area
--- @private
function AMA.Voxlatro:get_size()
	if not G.kb_selected_area then return 0 end
	if not G.kb_selected_area.cards then return 0 end
	if not G[self.selected_id] then 
		self:reset_vars()
	return 0 end
	return #G.kb_selected_area.cards
end

--- Helper function to update the offset of the current card selection offset
--- @param value number The value to set the offset to
--- @private
function AMA.Voxlatro:update_offset(value)
	G.kb_select_offset = value
	if G.kb_selected_area and G.kb_selected_area.cards then
		for i = G.kb_select_offset, G.kb_select_offset + 9 do
			local card = G.kb_selected_area.cards[i + 1]
			if not card then break end
			card:juice_up(.1, .2)
		end
	end
end

--- Adds/Subtracts [amount] from the current card selection offset
--- @param amount number The amount to add/subtract from the current card selection offset
function AMA.Voxlatro:add_offset(amount)
	if not G.kb_selected_area then return end
	if not G[self.selected_id] then 
		self:reset_vars()
	return end
	local size = self:get_size()
	if G.kb_select_offset + amount < 0 then 
		local o = math.floor(size / 10) * 10
		if o == size then
			o = o - 10
		end
		self:update_offset(o)
		return
	elseif G.kb_select_offset + amount > size then
		self:update_offset(0)
		return
	end
	self:update_offset(G.kb_select_offset + amount)
end

--- Sets the currently selected card area
--- @param id string The ID of the card area to select (e.g. 'hand', 'jokers', etc.)
function AMA.Voxlatro:set_selected(id)
	--- If the target area doesn't exist or is empty:
	---   - Reset variables if we're already focused on that area
	---   - Return without doing anything
	--- Otherwise:
	---   - Focus the game controller on the area
	---   - Update the selected area ID and reference
	---   - Update the offset to match current scroll position
	print("Switching to " .. id)
	if not G[id] or not G[id].cards or #G[id].cards == 0 then 
		if self.selected_id == id then
			self:reset_vars()
		end
	return end
	G.CONTROLLER:recall_cardarea_focus(id)
	self.selected_id = id
	G.kb_selected_area = G[id]
	self:update_offset(G.kb_select_offset)
end

--- Handles toggling card selection at a given offset index. This is the function called by the `0` - `9` KeyBindings
--- @param index number The 0-based index from the current scroll offset to select/deselect
function AMA.Voxlatro:toggle_selected(index)
	--- If no area is currently selected:
	---   - Sets appropriate default area based on game state
	---   - Returns without selecting if no valid area available
	--- If the target card exists and is selectable:
	---   - Toggles highlight state of card at offset + index + 1 
	---   - Updates hover state and last highlighted card tracking
	---   - Unhighlights previous card if one exists
    -- print("Toggling Selection with Index " .. index .. " (KB Select Offset: " .. G.kb_select_offset .. ")")
	if G.kb_selected_area and G.kb_selected_area.cards and #G.kb_selected_area.cards == 0 then
		self:reset_vars()
	end
	if not G.kb_selected_area then 
		-- Some sensible defaults
		if G.STATE == G.STATES.SELECTING_HAND then
			self:set_selected('hand')
		elseif G.STATE == G.STATES.BLIND_SELECT
			or G.STATE == G.STATES.HAND_PLAYED
			or G.STATE == G.STATES.ROUND_EVAL
			then self:set_selected('jokers')
		elseif G.STATE == G.STATES.TAROT_PACK
			or G.STATE == G.STATES.PLANET_PACK
			or G.STATE == G.STATES.SPECTRAL_PACK
			or G.STATE == G.STATES.BUFFOON_PACK
			or G.STATE == G.STATES.STANDARD_PACK
		then self:set_selected("pack_cards")
		elseif G.STATE == G.STATES.SHOP then
			self:set_selected("shop_jokers")
		else return end
	end
	if not G[self.selected_id] then 
		self:reset_vars()
	return end
	if not G.kb_selected_area.cards then return end
	local total_index = G.kb_select_offset + index + 1
	if 1 > total_index or total_index > #G.kb_selected_area.cards then return end
	local card = G.kb_selected_area.cards[total_index]
	-- print("Selecting Card #" .. total_index .. " (KB Select Offset: " .. G.kb_select_offset .. ")")
	if card.highlighted then
		if self.last_highlighted then
			self.last_highlighted:stop_hover()
		end
		self.last_highlighted = nil
		G.kb_selected_area:remove_from_highlighted(card)
	elseif G.kb_selected_area:can_highlight(card) then
		if self.last_highlighted then
			self.last_highlighted:stop_hover()
		end
		G.kb_selected_area:add_to_highlighted(card)
		self.last_highlighted = card
		self.last_highlighted:hover()
	end
end

function AMA.Voxlatro:reroll()
	if G.STATE == G.STATES.SHOP then
		if self:can("reroll") then
			G.FUNCS.reroll_shop({})
			return
		end
	elseif G.STATE == G.STATES.BLIND_SELECT then
		local fakebutton = {config = {}, children = {{children = {{config = {}}}}}}
		G.FUNCS.reroll_boss_button(fakebutton)
		if fakebutton.config.button then
			G.FUNCS.reroll_boss()
			return
		end
	end
end


--- Moves the specified card to the specified position. (Card number references the current area)
--- @param card_number number The card number to move. 1-based index
--- @param position number The position to move the card to. 1-based index
--- @return table table The return value of the function.
---  - `state`: boolean If the function was successful or not.
---  - `msg`: string message explaining the result of the function.
function AMA.Voxlatro:move_card_to_position(card_number, position)
	
	local number_of_cards = self:get_size()

	if number_of_cards == 0 then
		return {state=false, msg="No Cards In Selected Area"}
	end
	if card_number < 1 or card_number > number_of_cards then
		return {state=false, msg="Invalid Card Number: " .. card_number}
	end

	if position < 1 or position > number_of_cards then
		return {state=false, msg="Invalid Destination: " .. position}
	end

	-- If the destination is the same as the current card, then there's nothing to do. Return.
	if position == card_number then
		return {state=false, msg="Destination Is Same As Current Card"}
	end

	local vector = position - card_number
	return self:move_card_relative(card_number, vector)
end

--- Moves the specified card all the way to the left or right edge of the current card area
--- @param card_number number The card number to move. 1-based index
--- @param direction number The direction to move the card in. negative values will move the card to the left, positive values will move the card to the right.
--- @return table table The return value of the function.
---  - `state`: boolean If the function was successful or not.
---  - `msg`: string message explaining the result of the function.
function AMA.Voxlatro:move_card_to_limit(card_number, direction)

	if direction == nil then
		return {state=false, msg="Must Provide Direction (-1/+1)"}
	end

	local number_of_cards = self:get_size()

	if number_of_cards == 0 then
		return {state=false, msg="No Cards In Selected Area"}
	end

	if card_number < 1 or card_number > number_of_cards then
		return {state=false, msg="Invalid Card Number: " .. card_number}
	end

	if direction < 0 then
		return self:move_card_to_position(card_number, 1)
	elseif direction > 0 then
		return self:move_card_to_position(card_number, number_of_cards)
	end

	return {state=false, msg="Invalid Direction: " .. direction}
end

--- Moves the specified card to the specified position. (Card number references the current area)
--- @param card_number number The card number to move. 1-based index
--- @param vector number The vector to move the card by. Positive values will move the card to the right, negative values will move the card to the left.
--- @return table table The return value of the function.
---  - `state`: boolean If the function was successful or not.
---  - `msg`: string message explaining the result of the function.
function AMA.Voxlatro:move_card_relative(card_number, vector)
	-- If there is no selected area set (not G.kb_selected_area) there's nothing to do. Return.
	if not G.kb_selected_area then return {state=false, msg="No Selected Area"} end

	-- If the selected area doesn't exist. then it's likly the game has changed to a state where the selected area is no longer present.
	-- Reset state variables and return.
	if not G[self.selected_id] then 
		self:reset_vars()
		return {state=false, msg="Selected Area Does Not Exist"}
	end

	local number_of_cards = self:get_size()
	-- Since this command will only ever be called via the RPC, ignore the offset

	if number_of_cards == 0 then
		return {state=false, msg="No Cards In Selected Area"}
	end

	if card_number < 1 or card_number > number_of_cards then
		return {state=false, msg="Invalid Card Number: " .. card_number}
	end

	-- if vector > number_of_cards or vector < -number_of_cards then
	-- 	return {state=false, msg="Invalid Vector: " .. vector}
	-- end

	-- Perform the move
	-- local card = G.kb_selected_area.cards[card_number]
	-- local original_card_rank = card.rank
	-- local original_other_card_rank = card.area.cards[card.rank].rank

	-- card.rank = card.rank + vector
	-- card.area.cards[card.rank].rank = card.rank + vector
	-- table.sort(card.area.cards, function (a, b) return a.rank < b.rank end)
	-- card.area:align_cards()

	-- print("Card Moved! Card #" .. card_number .. " Moved To #" .. card.rank .. " (Original Rank: " .. original_card_rank .. ")")
	-- print("                    Other Moved To #" .. card.area.cards[card.rank].rank .. " (Original Rank: " .. original_other_card_rank .. ")")

	local direction = vector > 0 and "right" or "left"
	local ret = nil
	for i = 0, math.abs(vector) - 1 do
		-- Only align cards at the end of the move
		local sign = vector > 0 and 1 or (vector == 0 and 0 or -1)
		local card_number = card_number + (i * sign)
		ret = self:_move_card(card_number, direction, i == (math.abs(vector)-1))
		if not ret.state then
			print("Error Moving Card Partway! " .. ret.msg)
			return ret
		end
	end
	return ret or {state=false, msg="Unexpected Error"}
end



--- Moves the specified card in the specified direction by one
--- @param card_number number The card number to move. 1-based index
--- @param direction string The direction to move the card in. Valid values are "left" and "right"
--- @private
function AMA.Voxlatro:_move_card(card_number, direction, align_cards)

	if not G.kb_selected_area then return {state=false, msg="No Selected Area"} end

	-- If the selected area doesn't exist. then it's likly the game has changed to a state where the selected area is no longer present.
	-- Reset state variables and return.
	if not G[self.selected_id] then 
		self:reset_vars()
		return {state=false, msg="Selected Area Does Not Exist"}
	end

	local new_card_rank = (direction == 'left' and {card_number - 1} or {card_number + 1})[1]
	if new_card_rank < 1 or new_card_rank > #G.kb_selected_area.cards then
		return {state=false, msg="Can not move card outside of bounds"}
	end

	local focused = G.kb_selected_area.cards[card_number]
	-- print("Moving Card #" .. card_number .. " " .. direction .. " (KB Select Offset: " .. G.kb_select_offset .. ")")
	if focused == nil then
		return {state=false, msg="Card @ " .. card_number .. " does not exist"}
	end

	-- TODO: Optimize This Section
	if direction == 'left' and focused.rank > 1 then
		focused.rank = focused.rank - 1 
		focused.area.cards[focused.rank].rank = focused.rank + 1
		table.sort(focused.area.cards, function (a, b) return a.rank < b.rank end)
		focused.area:align_cards()
		-- self:update_cursor()
	elseif direction == 'right' and focused.rank < #focused.area.cards then
		focused.rank = focused.rank + 1 
		focused.area.cards[focused.rank].rank = focused.rank - 1
		table.sort(focused.area.cards, function (a, b) return a.rank < b.rank end)
		focused.area:align_cards()
		-- self:update_cursor()
	end
	return {state=true, msg="Card Moved"}
end

-- backspace to skip pack -- done
-- backspace for next round -- done
-- backspace to skip blind -- DONE OMFFGGGGG


function AMA.Voxlatro:discard()
	if G.STATE == G.STATES.BLIND_SELECT then
		-- Can't fake it fully, we need the tag
		
		local current_blind = G.GAME.blind_on_deck or 'Small'
		if current_blind == "Boss" then return end
		
		-- TODO: Make `_tag` local
		local _tag = Tag(G.GAME.round_resets.blind_tags[current_blind], nil, current_blind)
		
		if not _tag then
			error("tag is null for blind " .. current_blind)
		end
		
		local fakebutton = {
			UIBox = {
				get_UIE_by_ID = function()
					return {config = {ref_table = _tag}}
				end
			}
		}
		
		G.FUNCS.skip_blind(fakebutton)
		return
	end
	if G.STATE == G.STATES.TAROT_PACK
		or G.STATE == G.STATES.PLANET_PACK
		or G.STATE == G.STATES.SPECTRAL_PACK
		or G.STATE == G.STATES.BUFFOON_PACK
		or G.STATE == G.STATES.STANDARD_PACK
	then
		if self:can("skip_booster") then
			G.FUNCS.skip_booster()
			self:reset_vars()
			return
		end
	end
	if G.STATE == G.STATES.SHOP then
		G.FUNCS.toggle_shop()
		self:reset_vars()
		return
	end
		
	if G.STATE ~= G.STATES.SELECTING_HAND then return end
	if not G.GAME.current_round then return end
	if not G.kb_selected_area then return end
	if G.hand and G.kb_selected_area ~= G.hand then return end
	if not self:can("discard") then return end
	G.FUNCS.discard_cards_from_highlighted(nil, false) 
	self:reset_vars()
end

-- enter to select from pack
-- enter to select blind -- done

function AMA.Voxlatro:context_use()
	if G.STATE == G.STATES.ROUND_EVAL then
		local fakebutton = {config = {}}
		if G.__vi_safe_to_cash_out then
			G.FUNCS.cash_out(fakebutton)
			G.__vi_safe_to_cash_out = false
		end
		return
	end
	if G.STATE == G.STATES.BLIND_SELECT then
		-- Can't fake it, we need the real button
		local current_blind = G.GAME.blind_on_deck or 'Small'
		local blind_index = (current_blind == 'Small' and 1) or (current_blind == 'Big' and 2) or 3
		local button = G.blind_select.UIRoot.children[1].children[blind_index].config.object:get_UIE_by_ID('select_blind_button')
		G.FUNCS.select_blind(button)
		return
	end
	if not G.kb_selected_area then return end
	if G.kb_selected_area.highlighted and #G.kb_selected_area.highlighted == 0 then
		self:toggle_selected(0)
		return
	end
	if G.STATE == G.STATES.SELECTING_HAND and G.hand and G.kb_selected_area == G.hand then
		if self:can("play") then
			G.FUNCS.play_cards_from_highlighted()
			self:reset_vars()
		end
		return
	end
	if G.jokers and G.kb_selected_area == G.jokers then return end
	if G.consumeables and G.kb_selected_area == G.consumeables then
		if G.kb_selected_area.highlighted and
			G.kb_selected_area.highlighted[1] and
			G.kb_selected_area.highlighted[1]:can_use_consumeable()
		then
			G.FUNCS.use_card {
				config = {ref_table = G.kb_selected_area.highlighted[1]}
			}
			self:reset_vars()
			return
		end
	end
	if G.STATE == G.STATES.SHOP and G.kb_selected_area == G.shop_jokers or G.kb_selected_area == G.shop_vouchers or G.kb_selected_area == G.shop_booster then
		local card = G.kb_selected_area.highlighted and G.kb_selected_area.highlighted[1]
		if not card then return end
		
		local button = {config = {ref_table = card}}
		
		if card.area == G.shop_booster then
			G.FUNCS.can_open(button)
			if button.config.button then
				G.FUNCS.use_card(button)
				self:reset_vars()
				return
			end
		end
		
		if card.area == G.shop_vouchers then
			G.FUNCS.can_redeem(button)
			if button.config.button then
				G.FUNCS.use_card(button)
				self:reset_vars()
				return
			end
		end
		
		if card.area == G.shop_jokers then
			G.FUNCS.can_buy(button)
			if button.config.button then
				G.FUNCS.buy_from_shop(button)
				return
			end
		end
	end
	
	if G.kb_selected_area == G.pack_cards then
		local card = G.kb_selected_area.highlighted and G.kb_selected_area.highlighted[1]
		if not card then return end
		if card.ability.consumeable and not card:can_use_consumeable() then return end
		
		local button = {config = {ref_table = card}}
		G.FUNCS.can_select_card(button)
		if button.config.button then
			G.FUNCS.use_card(button)
			self:reset_vars()
			return
		end
	end
end

function AMA.Voxlatro:buy_and_use()
	if not G.kb_selected_area then return end
	if G.kb_selected_area.highlighted and #G.kb_selected_area.highlighted == 0 then
		self:toggle_selected(0)
		return
	end
	if not (G.STATE == G.STATES.SHOP and G.kb_selected_area == G.shop_jokers) then return end
	local card = G.kb_selected_area.highlighted and G.kb_selected_area.highlighted[1]
	if not card then return end
		
	local button = {config = {ref_table = card, id = "buy_and_use"}, UIBox = {states = {}}}
		
	G.FUNCS.can_buy_and_use(button)
	if button.config.button then
		G.FUNCS.buy_from_shop(button)
		self:reset_vars()
		return
	end
end

function AMA.Voxlatro:sell()
	if G.kb_selected_area and G.kb_selected_area.cards then
		for i, card in ipairs(G.kb_selected_area.cards) do
			if card.area and card.area.config.type == "joker" and card.highlighted then
				local fakebutton = {config = {ref_table = card}}
				G.FUNCS.can_sell_card(fakebutton)
				if fakebutton.config.button then
					G.FUNCS.sell_card(fakebutton)
				end
			end
		end
	end
end

function AMA.Voxlatro:cycle_selected(amount)
	local selections = {
		"hand",
		"jokers",
		"consumeables",
		"shop_jokers",
		"shop_vouchers",
		"shop_booster",
		"pack_cards"
	}
	local index
	local sel_id = self.selected_id or "hand"
	local sel_idx
	for i, sel in ipairs(selections) do
		if sel == sel_id then
			sel_idx = i
			break
		end
	end
	if sel_idx == nil then
		print("Warning: Selection index not found! Current selection id: " .. self.selected_id)
		self.selected_id = "hand"
		sel_idx = 1
	end
	
	for i = 1, #selections do
		i = i * amount -- 1 or -1
		local offset_idx = ((sel_idx + i - 1) % #selections) + 1
		if G[selections[offset_idx]] and G[selections[offset_idx]].cards and #G[selections[offset_idx]].cards > 0 then
			if not (selections[offset_idx]:sub(1, 4) == "shop" and G.STATE ~= G.STATES.SHOP) then
				self:set_selected(selections[offset_idx])
				return
			end
		end
	end
end

-- Monkey-patching

local update_card = Card.update
local update_area = CardArea.update
local draw_card = Card.draw

---@diagnostic disable-next-line: duplicate-set-field
function Card:update(dt)
	update_card(self, dt)
	if not self.area then
		self.__kb_index = nil
	end
	if not self.last_state or G.STATE ~= self.last_state then
		amy:reset_vars()
		self.last_state = G.STATE
		if G.STATE == G.STATES.ROUND_EVAL then
			G.__vi_safe_to_cash_out = false
		end
	end
end

---@diagnostic disable-next-line: duplicate-set-field
function CardArea:update(dt)
	update_area(self, dt)
	if self.cards then
		for i, card in ipairs(self.cards) do
			card.__kb_index = i
		end
	end
end

---@diagnostic disable-next-line: duplicate-set-field
function Card:draw(layer)
	draw_card(self, layer)

	-- This seems to do the following:
	--  - Nothing if the card is NOT in the currently selected area
	--  - Otherwise:
	--    - Add a Triangle Pointer to the card to indicate it's selected

	
	if self.area == G.kb_selected_area 
		and self.__kb_index
		and self.__kb_index > G.kb_select_offset
		and self.__kb_index <= G.kb_select_offset + 10
	then

		local transform = self.VT or self.T
		love.graphics.push()
		love.graphics.scale(G.TILESCALE, G.TILESCALE)
		love.graphics.translate(transform.x*G.TILESIZE+transform.w*G.TILESIZE*0.5, transform.y*G.TILESIZE+transform.h*G.TILESIZE*0.5)
		love.graphics.rotate(transform.r)
		love.graphics.translate(-transform.w*G.TILESIZE*0.5, -transform.h*G.TILESIZE*0.5)
		love.graphics.setColor(G.C.UI.OUTLINE_LIGHT_TRANS)
		love.graphics.arc('fill', transform.w*G.TILESIZE*0.5, transform.h*G.TILESIZE*-0.1, 0.2*G.TILESIZE, -3 * math.pi / 4, -math.pi / 4, 1)

		love.graphics.pop()
	end
end

