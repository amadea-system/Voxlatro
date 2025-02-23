
if not AMA then AMA = {} end

-- ---------- Imports ----------
--- @module 'inspect'
local inspect, err = SMODS.load_file("lib/inspect.lua")()
if err then
	print("Error loading library `inspect`: " .. err)
	error(err)
end

--- @module 'utils'
local utils = {}
utils, err = SMODS.load_file("core/utils.lua")()
if err then
	print("Error loading library `utils`: " .. err)
	error(err)
end

-- ---------- Local Variables ----------

G.kb_select_offset = 0

-- ----- Selection Configuration -----

local UNHIGHLIGHT_JOKER_AND_SHOP_CARDS_WHEN_SELECTING_ANOTHER_CARD = true

-- ----- Voxlatro Class Object -----

-- TODO: We should not name this class Amilatro. Come up with a better name.
--       I don't remember if our objection was that `Amilatro` was just a name we didn't like in general.
--       Or if we wanted a name that more aligned with card selection? I think it was the latter.

--- @class Voxlatro
--- @field selected_id? string The Area ID of the currently selected card area. Such as 'hand', 'jokers', 'consumeables', 'shop_jokers', 'shop_vouchers', 'shop_booster', 'pack_cards'
--- @field last_state string? Used in Card:update() to track the last state G.STATE was in. When G.STATE changes, we reset Vars and potentially set it as unsafe to cash out.
--- @field last_highlighted Card? The last card that was highlighted
--- @field assigned_talon_ids table<string, Card> A table of all assigned Talon IDs and their corresponding cards.
AMA.Voxlatro = Object:extend()

-- --- Voxlatro Class Methods ---
function AMA.Voxlatro:init()
	self.selected_id = nil
	self.last_state = nil
	self.last_highlighted = nil

	-- Original Function References --
	self._update_card = Card.update
	self._update_area = CardArea.update
	self._draw_card = Card.draw

    -- --- Debug Variables ---
    self.last_card_dumped = 0 -- nil
    self.info_dump_mode = "off"  -- Valid Values: "off", "trigger", "once"
    self.last_card_info_dump_time = love.timer.getTime()  -- Units: Seconds
    self.dump_card_info_interval = 0.5  -- Units: Seconds

	-- --- Talon ID Tracking ---
	self.assigned_talon_ids = {}

end

-- ---------- Initialization ----------
local dprint = AMA.dprint

---@type Voxlatro
local amy = AMA.Voxlatro()
amy:init()

---Primary Instance of the Voxlatro Card Selection Class.
---Same ref as `AMA.card_sel`. Use that one instead.
---@type Voxlatro
---@deprecated
AMA.vox = amy

---Primary Instance of the Voxlatro Card Selection Class
---@type Voxlatro
AMA.card_sel = amy


-- ---------- Validation ----------

-- ---------- Talon ID Functions ----------

--- Itterates over all assigned Talon IDs and removes any that are no longer valid
function AMA.Voxlatro:clean_talon_ids()
	for id, card in pairs(self.assigned_talon_ids) do
		-- if not card or not card.__talon_id then
		-- 	self.assigned_talon_ids[id] = nil
		-- end
		if card ~= nil and (card.removed or card.__talon_id == nil) then
			self.assigned_talon_ids[id] = nil
			card.__talon_id = nil
		end
	end
end

--- Returns the next available Talon ID
--- @return string The next available Talon ID. 2-Character String
function AMA.Voxlatro:get_next_talon_id()
	self:clean_talon_ids()
	local next_id = "AA"
	while self.assigned_talon_ids[next_id] do
		local char1 = next_id:sub(1, 1)
		local char2 = next_id:sub(2, 2)
		if char2 == "Z" then
			if char1 == "Z" then
				error("Out of Talon IDs!")
			end
			char1 = string.char(char1:byte() + 1)
			char2 = "A"
		else
			char2 = string.char(char2:byte() + 1)
		end
		next_id = char1 .. char2
	end
	return next_id
end

--- Assigns the next available Talon ID to the specified card
--- @param card Card The card to assign the next available Talon ID to
function AMA.Voxlatro:assign_next_talon_id(card)
	self:clean_talon_ids()

	-- Check if the card already has a Talon ID
	if card.__talon_id ~= nil then
		return
	end
	local next_id = self:get_next_talon_id()
	card.__talon_id = next_id
	self.assigned_talon_ids[next_id] = card
end


---Get a card, and it's area name by it's talon ID.
---@param talon_id string The Talon ID of the card to get.
---@return table {card: Card?, area_name: string?} The card and area name. Values may be nil if they could not be found.
function AMA.Voxlatro:get_card_by_talon_id(talon_id)

	print("Trying to Get Card with Talon-ID " .. inspect(talon_id))

	if type(talon_id) ~= "string" then
		print("Invalid Talon ID Type: " .. type(talon_id) .. "Must be String! (Dump: " .. inspect(talon_id, {depth=3}) .. ")")
		return {card=nil, area_name=nil}
	end
	
	-- Convert to uppercase
	talon_id = string.upper(talon_id)

	local card = nil
	card = self.assigned_talon_ids[talon_id]

	if card == nil then
		print("Card with Talon-ID " .. talon_id .. " not found!")
		return {card=nil, area_name=nil}
	elseif card.area == nil then
		print("Card with Talon-ID " .. talon_id .. " has no area!")
		return {card=card, area_name=nil}
	end

	local area_to_select = card.area:get_cardarea_name()

	if not area_to_select then
		print("Could not find CardArea name for Card with Talon-ID " .. talon_id)
		return {card=card, area_name=nil}
	end
	return {card=card, area_name=area_to_select}
end


---Tries to get a card by it's Talon ID and select it's area.
---Respects the current game state and will not select the hand area if the hand is being played.
---@param talon_id string The Talon ID of the card to get and select.
---@return table? {card: Card?, area_selected: boolean} The card and if the area was successfully selected. Returns nil if the Card or area could not be found.
function AMA.Voxlatro:get_card_and_select_area_by_talon_id(talon_id)

	local ca = self:get_card_by_talon_id(talon_id)
	if not ca or not ca.card or not ca.area_name then
		return nil
	end

	if (ca.card.area == G.hand) and (G.STATE == G.STATES.HAND_PLAYED) then 
		print("Can't select card in hand when hand is being played!!!")
		ca.card:juice_up(0.2, 0.2)
		return {card=ca.card, area_selected=false}
	end

	self:set_selected(ca.area_name)
	return {card=ca.card, area_selected=true}

end

-- ---------- Local Functions ----------

--- Resets the current card selection state variables.
--- If any cards are highlighted, they will be unhighlighted.
--- If any hover UI Boxes are visible, they will be dismissed.
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

--- Toggles the highlight state of the given card.
--- Additionally, handles activating/deactivating hover state and tracking the last highlighted card.
--- @param card Card The card to toggle the highlight state of
--- @private
function AMA.Voxlatro:toggle_card_highlight(card)
	if not card then return false end

	local card_name = card.__talon_id or card.__kb_index or "Unknown"

	local function reset_last_highlighted()
		if self.last_highlighted then
			self.last_highlighted:stop_hover()
		end

		if UNHIGHLIGHT_JOKER_AND_SHOP_CARDS_WHEN_SELECTING_ANOTHER_CARD and self.last_highlighted and self.last_highlighted.area then
			if self.last_highlighted.area == G.jokers or
			   self.last_highlighted.area == G.shop_jokers or
			   self.last_highlighted.area == G.shop_vouchers or
			   self.last_highlighted.area == G.shop_booster
			then
				self.last_highlighted.area:remove_from_highlighted(self.last_highlighted)
			end
		end

		self.last_highlighted = nil
	end

	if card.highlighted then
		reset_last_highlighted()
		G.kb_selected_area:remove_from_highlighted(card)
	elseif G.kb_selected_area:can_highlight(card) then
		reset_last_highlighted()  -- Original implementation did not set last_highlighted to nil here.
		G.kb_selected_area:add_to_highlighted(card)
		self.last_highlighted = card
		self.last_highlighted:hover()
	else
		print("Card " .. card_name .. " can not be highlighted!")
		card:juice_up(0.2, 0.2)
	end

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
--- @deprecated
function AMA.Voxlatro:toggle_selected(index)
	return self:toggle_selected_1idx(index+1, false)
end

--- Handles toggling card selection at a given offset index. This is the function called by the `0` - `9` KeyBindings
--- @param index number The 0-based index from the current scroll offset to select/deselect
function AMA.Voxlatro:toggle_selected_0idx(index)
	return self:toggle_selected_1idx(index+1, false)
end

--- Handles toggling card selection at a given offset index.
--- Negative indexes will not be effected by the kb_select_offset
--- @param index number The 1-based index from the current scroll offset to select/deselect. If negative, selects from the end of the cards.
--- @param allow_negative boolean? If false, disallows negative indexes. Default: true
function AMA.Voxlatro:toggle_selected_1idx(index, allow_negative)
	--- If no area is currently selected:
	---   - Sets appropriate default area based on game state
	---   - Returns without selecting if no valid area available
	--- If the target card exists and is selectable:
	---   - Toggles highlight state of card at offset + index 
	---   - Updates hover state and last highlighted card tracking
	---   - Unhighlights previous card if one exists
    -- print("Toggling Selection with Index " .. index .. " (KB Select Offset: " .. G.kb_select_offset .. ")")
	if G.kb_selected_area and G.kb_selected_area.cards and #G.kb_selected_area.cards == 0 then
		self:reset_vars()
	end
	self:try_select_default_cardarea()

	-- We don't need this check here as we're doing it again on the next line below
	if not G.kb_selected_area then return end

	if not G.kb_selected_area or not G.kb_selected_area.cards then 
		return 
	end

	if allow_negative == nil then allow_negative = true end

	local total_index = index
	if total_index > 0 then
		-- TODO: Should we allow negative indexes to interact with the kb offset?
		total_index = total_index + G.kb_select_offset
	elseif not allow_negative then
		print("Negative Indexing Not Allowed! Index: " .. tostring(index))
		return
	end

	if not utils.is_table_idx_valid(G.kb_selected_area.cards, total_index) then
		print("Invalid Index: " .. total_index)
		return
	end

	local card = utils.get_at(G.kb_selected_area.cards, total_index)  -- use get_at to allow negative indexing.
	print("Selecting Card #" .. total_index .. " (KB Select Offset: " .. G.kb_select_offset .. ")")
	print("card ~= nil" .. (card ~= nil and "true" or "false"))

	self:toggle_card_highlight(card)
end

--- Handles toggling card selection by a Talon ID
--- @param talon_id string The Talon ID of the card to toggle selection of
function AMA.Voxlatro:toggle_with_talon_id(talon_id)
	--- Search through all valid selection car areas for the card with the specified Talon ID
	--- If the target card exists and is selectable:
	---   - Sets the area the card is in as the selected area
	---   - Toggles highlight state of card at offset + index 
	---   - Updates hover state and last highlighted card tracking
	---   - Unhighlights previous card if one exists

	local results = self:get_card_by_talon_id(talon_id)
	if not results or not results.card or not results.area_name then
		return false
	end

	local card = results.card
	local area_to_select = results.area_name

	if (card.area == G.hand) and (G.STATE == G.STATES.HAND_PLAYED) then 
		print("Can't select card in hand when hand is being played!!!")
		card:juice_up(0.2, 0.2)
		return false
	end

	print("Selecting Card with Talon-ID " .. talon_id .. " in Area: " .. area_to_select)

	-- Set the selected area to the area the card is in
	self:set_selected(area_to_select)

	if not G.kb_selected_area or not G.kb_selected_area.cards then 
		print("Error setting selected area to card " .. talon_id .. " area")
		return false
	end

	self:toggle_card_highlight(card)
	return true
end

--- Attempts to select the default card area based on the current game state if no area is currently selected
function AMA.Voxlatro:try_select_default_cardarea()

	if G.kb_selected_area then
		-- An area is already selected, There's nothing to do.
		return
	end

	-- Some sensible defaults
	if G.STATE == G.STATES.SELECTING_HAND then
		self:set_selected('hand')
		
	elseif G.STATE == G.STATES.BLIND_SELECT
		or G.STATE == G.STATES.HAND_PLAYED
		or G.STATE == G.STATES.ROUND_EVAL
	then 
		self:set_selected('jokers')
	elseif G.STATE == G.STATES.TAROT_PACK
		or G.STATE == G.STATES.PLANET_PACK
		or G.STATE == G.STATES.SPECTRAL_PACK
		or G.STATE == G.STATES.BUFFOON_PACK
		or G.STATE == G.STATES.STANDARD_PACK
	then 
		self:set_selected("pack_cards")
	elseif G.STATE == G.STATES.SHOP then
		self:set_selected("shop_jokers")
	else 
		return
	end
	if not G[self.selected_id] then
		-- error("Selected Area Does Not Exist")
		print("[Voxlatro:try_select_default_cardarea()] Selected Area Does Not Exist!?")
		self:reset_vars()
		return
	end
end


---Equivalent to clicking the **Reroll** button in the shop or boss selection screen.
---@return boolean If the reroll was successful or not.
function AMA.Voxlatro:reroll()
	if G.STATE == G.STATES.SHOP then
		if self:can("reroll") then
			G.FUNCS.reroll_shop({})
			return true
		end
	elseif G.STATE == G.STATES.BLIND_SELECT then
		local fakebutton = {config = {}, children = {{children = {{config = {}}}}}}
		G.FUNCS.reroll_boss_button(fakebutton)
		if fakebutton.config.button then
			G.FUNCS.reroll_boss()
			return true
		end
	end
	return false
end

end


---@class CardForMove
---@field state boolean If the function was successful or not.
---@field msg string? message explaining the result of the function.
---@field card Card? The card object that was found.
---@field area_name string? The name of the area the card was found in.
---@field area CardArea? The card area object the card was found in.
---@field kb_index number? The 1-based index of the card in the current area.
---@field card_id number|string? The 2 Letter ID or Number of the card.


--- Moves the specified card to the specified position.
---   If card_id is a number, it references the kb_idx of the cards in the current area, or area provided
---   If card_id is a string, it references the Talon ID of the card to move.
--- @param card_id number|string? The CardID or the card number of the card to move
--- @param position number The position to move the card to. 1-based index
--- @param card_area string? The name of the card area the card to move is in. If not provided, the currently selected area will be used. Only valid for numeric card_id.
--- @param move_card CardForMove? The card object and area name to move. If not provided, the card will be fetched by the card_id & card_area.
--- @return table table The return value of the function.
---  - `state`: boolean If the function was successful or not.
---  - `msg`: string message explaining the result of the function.
function AMA.Voxlatro:move_card_to_position(card_id, position, card_area, move_card)

	if (card_id == nil and move_card == nil) or position == nil then
		return {state=false, msg="Must Provide cardNumber/cardID/CardForMove obj and position"}
	end

	local card_dets = move_card or self:_get_card_for_move(card_id, card_area , true, "move_card_to_position")
	if not card_dets then
		return {state=false, msg="Error Getting Card Details"}
	elseif not card_dets.state then
		return card_dets
	end

	local number_of_cards = card_dets.area:get_card_count()
	if position < 1 or position > number_of_cards then
		return {state=false, msg="Invalid Destination: " .. tostring(position)}
	end

	-- If the destination is the same as the current card, then there's nothing to do. Return.
	if position == card_dets.kb_index then
		return {state=false, msg="Destination Is Same As Current Card"}
	end

	local vector = position - card_dets.kb_index
	-- print("<move_card_to_position> Moving Card `" .. tostring(card_dets.card_id) .. "` (#" .. tostring(card_dets.kb_index).. ") to pos " .. tostring(position) .. "(Transferring move to `move_card_relative`)")
	return self:move_card_relative(card_id, vector, card_area, card_dets)
end

--- Moves the specified card all the way to the left or right edge of the current card area
--- @param card_id number|string? The CardID or the card number of the card to move
--- @param direction number The direction to move the card in. negative values will move the card to the left, positive values will move the card to the right.
--- @param card_area string? The name of the card area the card to move is in. If not provided, the currently selected area will be used. Only valid for numeric card_id.
--- @param move_card CardForMove? The card object and area name to move. If not provided, the card will be fetched by the card_id & card_area.
--- @return table table The return value of the function.
---  - `state`: boolean If the function was successful or not.
---  - `msg`: string message explaining the result of the function.
function AMA.Voxlatro:move_card_to_limit(card_id, direction, card_area, move_card)

	if direction == nil then
		return {state=false, msg="Must Provide Direction (-1/+1)"}
	end

	local card_dets = move_card or self:_get_card_for_move(card_id, card_area , true, "move_card_to_limit")
	if not card_dets then
		return {state=false, msg="Error Getting Card Details"}
	elseif not card_dets.state then
		return card_dets
	end

	if direction < 0 then
		-- print("<move_card_to_limit> Moving Card `" .. tostring(card_dets.card_id) .. "` (#" .. tostring(card_dets.kb_index) .. ") to the left edge. (Transferring move to `move_card_to_position`)")
		return self:move_card_to_position(card_id, 1, card_area, card_dets)
	elseif direction > 0 then
		local number_of_cards = card_dets.area:get_card_count()
		-- print("<move_card_to_limit> Moving Card `" .. tostring(card_dets.card_id) .. "` (#" .. tostring(card_dets.kb_index) .. ") to the right edge (pos: " .. tostring(number_of_cards) .. "). (Transferring move to `move_card_to_position`)")
		return self:move_card_to_position(card_id, number_of_cards, card_area, card_dets)
	end

	return {state=false, msg="Invalid Direction: " .. direction}
end

--- Moves the specified card to the specified position. (Card number references the current area)
--- @param card_id number|string? The CardID or the card number of the card to move
--- @param vector number The vector to move the card by. Positive values will move the card to the right, negative values will move the card to the left.
--- @param card_area string? The name of the card area the card to move is in. If not provided, the currently selected area will be used. Only valid for numeric card_id.
--- @param move_card CardForMove? The card object and area name to move. If not provided, the card will be fetched by the card_id & card_area.
--- @return table table The return value of the function.
---  - `state`: boolean If the function was successful or not.
---  - `msg`: string message explaining the result of the function.
function AMA.Voxlatro:move_card_relative(card_id, vector, card_area, move_card)

	if (card_id == nil and move_card) or vector == nil then
		return {state=false, msg="Must Provide cardNumber/cardID/CardForMove obj and vector"}
	end

	local card_dets = move_card or self:_get_card_for_move(card_id, card_area , true, "move_card_relative")
	if not card_dets then
		return {state=false, msg="Error Getting Card Details"}
	elseif not card_dets.state then
		return card_dets
	end

	local card_number = card_dets.kb_index

	-- print("<move_card_relative> Moving Card `" .. tostring(card_dets.card_id) .. "` (#" .. tostring(card_number) .. ") by " .. tostring(vector))

	-- Perform the move
	local direction = vector > 0 and "right" or "left"
	local ret = nil
	for i = 0, math.abs(vector) - 1 do
		-- Only align cards at the end of the move
		local sign = vector > 0 and 1 or (vector == 0 and 0 or -1)
		local new_card_number = card_number + (i * sign)
		ret = self:_move_card(new_card_number, card_dets.area, direction, i == (math.abs(vector)-1))
		if not ret.state then
			print("Error Moving Card Partway! " .. ret.msg)
			return ret
		end
	end
	return ret or {state=false, msg="Unexpected Error"}
end


--- Tries to get the card with the specified Talon ID and the area it is in.
--- If the card is found, the card is returned.
--- If the card is not found, an error message and state is returned in a table.
--- Helper function for `AMA.Voxlatro:_get_card_for_move`. You should use that function instead of this one.
--- @param card_id string? The Talon ID of the card to move.
--- @return table CardForMove The return value of the function.
---  - `state`: boolean If the function was successful or not.
---  - `msg`: string message explaining the result of the function.
---  - `card`: Card? The card object that was found.
---  - `area_name`: string? The name of the area the card was found in.
---  - `area`: CardArea? The card area object the card was found in.
--- @private
function AMA.Voxlatro:_get_card_for_move__by_id(card_id)

	if type(card_id) ~= "string" then
		return {state=false, msg="Invalid Card ID Type: " .. type(card_id)}
	end

	local results = self:get_card_by_talon_id(card_id)

	local card = (results and results.card) or nil
	local area_name = (results and results.area_name) or nil
	local area = (results and G[area_name]) or nil

	if not card then
		return {state=false, msg="Card " .. tostring(card_id) .. " not found!"}
	elseif not area_name then
		return {state=false, msg="Unable to select find the Area that Card " .. tostring(card_id) .. " is in!"}
	elseif not area then
		return {state=false, msg="The Area `" .. tostring(area_name) .. "` that Card " .. tostring(card_id) .. " is in does not exist!"}
	end

	-- I don't really think that this check is needed, as how could the area have 0 cards if the card was found?
	-- But I'll leave it in for now, as the check is needed when we're trying to get a card by number.
	local number_of_cards = area:get_card_count()
	if number_of_cards == 0 then
		return {state=false, msg="No Cards In Area " .. tostring(area_name)}
	end

	return {state=true, msg="Card Found", card=card, area_name=area_name, area=area}

end

--- Tries to get the card with the specified Card Number and the area it is in.
--- If the card is found, the card is returned.
--- If the card is not found, an error message and state is returned in a table.
---   The card number references the kb_idx of the cards in the current area, or area provided
--- Helper function for `AMA.Voxlatro:_get_card_for_move`. You should use that function instead of this one.
--- @param card_number number The card number to move. 1-based index
--- @param card_area_name string? The name of the card area the card to move is in. If not provided, the currently selected area will be used. Only valid for numeric card_id.
--- @return table CardForMove The return value of the function.
---  - `state`: boolean If the function was successful or not.
---  - `msg`: string message explaining the result of the function.
---  - `card`: Card? The card object that was found.
---  - `area_name`: string? The name of the area the card was found in.
---  - `area`: CardArea? The card area object the card was found in.
--- @private
function AMA.Voxlatro:_get_card_for_move__by_number(card_number, card_area_name)


	local function failure(_area_name, _cleanup_needed, msg)
		if _cleanup_needed and self.selected_id and _area_name == self.selected_id then
			-- If the selected area doesn't exist. then it's likly the game has changed to a state where the selected area is no longer present.
			-- Reset state variables and return.
			self:reset_vars()
		end
		return {state=false, msg=msg}
	end

	if type(card_number) ~= "number" then
		return {state=false, msg="Invalid Card Number Type: " .. type(card_number)}
	end

	local card = nil
	local area = nil

	-- If no card_area_name is provided, try to use the currently selected area
	if not card_area_name then
		card_area_name = self.selected_id
	end
	
	-- Verify that we have a card_area_name
	if not card_area_name then
		return failure(card_area_name, false, "No CardArea Name Provided or No CardArea Selected")
	end

	-- Make sure the card area exists
	if not G[card_area_name] then
		return failure(card_area_name, true, "Area " .. tostring(card_area_name) .. " does not exist!")
	end
	-- Store the area
	area = G[card_area_name]

	-- Sanity check card area
	if self.selected_id == card_area_name and G.kb_selected_area ~= area then

		local kb_sel_name = G.kb_selected_area and G.kb_selected_area:get_cardarea_name() or "nil"
		local stored_area_name = area and area:get_cardarea_name() or "nil"
		return failure(card_area_name, true, "Sanity Check Failed: Error. Selected Area Mismatch. El Psy Kongroo.\n  Selected_id: " .. tostring(self.selected_id) .. "\n  card_area_name: " .. tostring(card_area_name) .. "\n  G.kb_selected_area name: " .. kb_sel_name .. "\n  area name: " .. stored_area_name)
	end

	if area:get_card_count() == 0 then
		-- ? Do we really need to clean up on this failure?
		return failure(card_area_name, true, "Area " .. tostring(card_area_name) .. " does not have any cards!")
	end
	-- if not utils.is_table_idx_valid(G[card_area_name].cards, card_id) then
	-- 	return {state=false, msg="Invalid Card Number: " .. card_id}
	-- end

	card = area.cards[card_number]
	if not card then
		return failure(card_area_name, false, "Card " .. tostring(card_number) .. " not found in Area " .. tostring(card_area_name))
	end

	return {state=true, msg="Card Found", card=card, area_name=card_area_name, area=area}
end


--- Tries to get the card with the specified Talon ID or Card Number and the area it is in.
--- If the card is found, the area is selected and the card is returned.
--- If the card is not found, an error message and state is returned in a table.
---   If card_id is a number, it references the kb_idx of the cards in the current area, or area provided
---   If card_id is a string, it references the Talon ID of the card to move.
--- @param card_id number|string? The card number or Talon ID of the card to move.
--- @param card_area_name string? The name of the card area the card to move is in. If not provided, the currently selected area will be used. Only valid for numeric card_id.
--- @param require_kb_idx boolean If true, the card must have a KB Index.
--- @param _from string? The name of the function that called this function. For debugging purposes.
--- @return table CardForMove The return value of the function.
---  - `state`: boolean If the function was successful or not.
---  - `msg`: string message explaining the result of the function.
---  - `card`: Card? The card object that was found.
---  - `area_name`: string? The name of the area the card was found in.
---  - `area`: CardArea? The card area object the card was found in.
--- @private
function AMA.Voxlatro:_get_card_for_move(card_id, card_area_name, require_kb_idx, _from)
	-- _from = (_from and "" .. _from .. "-> ") or ""
	-- print("<" .. _from .. "_get_card_for_move> Getting Card  `" .. tostring(card_id) .. "` for Move in Area: " .. tostring(card_area_name))
	local card_res = nil
	if type(card_id) == "string" then
		card_res = self:_get_card_for_move__by_id(card_id)
	elseif type(card_id) == "number" then
		-- If no card_area_name is provided, use the currently selected area
		card_res = self:_get_card_for_move__by_number(card_id, card_area_name)
	else
		return {state=false, msg="Invalid Card ID Type: " .. type(card_id)}
	end

	if not card_res then
		return {state=false, msg="UNEXPECTED ERROR: Card Result is nil"}
	end

	if not card_res.state then
		return card_res
	end

	-- Sanity Check that the area and area name are valid
	if not card_res.card or not card_res.area_name or not card_res.area then
		return {state=false, msg="UNEXPECTED ERROR: Sanity Check Failure!! Card, Area, or Area Name is nil"}
	end


	if not card_res.card.__kb_index and require_kb_idx then
		-- todo: Do we really need this check?
		return {state=false, msg="Card " .. tostring(card_id) .. " does not have a KB Index!"}
	end

	card_res.kb_index = card_res.card.__kb_index
	card_res.card_id = card_id

	return card_res
end

--- Moves the specified card in the specified direction by one
--- @param card_number number The card number to move. 1-based index
--- @param card_area CardArea The card area object the card is in.
--- @param direction string The direction to move the card in. Valid values are "left" and "right"
--- @private
function AMA.Voxlatro:_move_card(card_number, card_area, direction, align_cards)

	-- print("<_move_card> Moving Card #" .. tostring(card_number) .. " " .. tostring(direction) .. " (Area: " .. tostring(card_area) .. ")")

	if not card_area then return {state=false, msg="No Area Provided to _move_card"} end

	local new_card_rank = (direction == 'left' and {card_number - 1} or {card_number + 1})[1]
	if new_card_rank < 1 or new_card_rank > #card_area.cards then
		return {state=false, msg="Can not move card outside of bounds! (Card #" .. tostring(card_number) .. " to " .. tostring(new_card_rank) .. ")"}
	end

	local focused = card_area.cards[card_number]
	-- print("Moving Card #" .. card_number .. " " .. direction .. " (KB Select Offset: " .. G.kb_select_offset .. ")")
	if focused == nil then
		return {state=false, msg="Card @ " .. tostring(card_number) .. " does not exist"}
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

--- Does one of the following actions based on the current game state:
--- - Exit out of a Booster Pack (`Skip` Button)
--- - Skip the current blind (`Skip Blind` Button)
--- - Exit Shop (`Next Round` Button)
function AMA.Voxlatro:discard__skip_or_next()
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
		return {activated=true, state=true, msg="Skipped Blind"}
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
			return {activated=true, state=true, msg="Skipped Booster"}
		end
	end
	if G.STATE == G.STATES.SHOP then
		G.FUNCS.toggle_shop()
		self:reset_vars()
		return {activated=true, state=true, msg="Exited Shop"}
	end
	return {activated=false, state=false, msg="No Action Taken"}
end

--- Discards the highlighted cards in the current card area. 
--- Only works when the game is in the correct state.
function AMA.Voxlatro:discard__discard_cards()

	if G.STATE ~= G.STATES.SELECTING_HAND then return {activated=false, state=false, msg="Not in Hand Selection State"} end
	if not G.GAME.current_round then return {activated=false, state=false, msg="No Current Round"} end
	if not G.kb_selected_area then return {activated=false, state=false, msg="No Selected Card Area"} end
	if G.hand and G.kb_selected_area ~= G.hand then return {activated=false, state=false, msg="Selected Area is Not Hand"} end
	if not self:can("discard") then return {activated=false, state=true, msg="Not Allowed to Discard Cards"} end
	G.FUNCS.discard_cards_from_highlighted(nil, false) 
	self:reset_vars()
	return {activated=true, state=true, msg="Discarded Cards"}
end

-- backspace to skip pack -- done
-- backspace for next round -- done
-- backspace to skip blind -- DONE OMFFGGGGG

--- Multifunction Contextual Action for the `Backspace` KeyBinding
--- Potential Actions:
---  - Exit out of a Booster Pack (`Skip` Button)
---  - Skip the current blind (`Skip Blind` Button)
---  - Exit Shop (`Next Round` Button)
---  - Discard Highlighted Cards
function AMA.Voxlatro:context_discard_or_skip()
	-- TODO: Replace the below logic w/ the new `discard__skip_or_next` and `discard__discard_cards` functions 
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

--- Triggers the same action as the `Cash Out` GUI Button
--- Only activates when the game is in the correct state.
--- @return table table The outcome of the action
---  - `activated`: boolean True if the action was successful, false otherwise
---  - `state`: boolean True if the context was valid to try to trigger the action, false otherwise
function AMA.Voxlatro:use__cash_out()
	if G.STATE == G.STATES.ROUND_EVAL then
		local fakebutton = {config = {}}
		if G.__vi_safe_to_cash_out then
			G.FUNCS.cash_out(fakebutton)
			G.__vi_safe_to_cash_out = false
			return {activated=true, state=true, msg="Cash Out Triggered"}
		end
		return {activated=false, state=true, msg="Still Waiting for Round Eval to Finish"}
	end
	return {activated=false, state=false, msg="Not in Round Eval State"}
end

--- Plays the highlighted cards in the current card area
--- @return table table The outcome of the action
---  - `activated`: boolean True if the action was successful, false otherwise
---  - `state`: boolean True if the context was valid to try to trigger the action, false otherwise
function AMA.Voxlatro:use__play_hand()
	if not G.kb_selected_area then return {activated=false, state=false, msg="No Selected Card Area"} end
	if G.STATE == G.STATES.SELECTING_HAND and G.hand and G.kb_selected_area == G.hand then
		if self:can("play") then
			G.FUNCS.play_cards_from_highlighted()
			self:reset_vars()
			return {activated=true, state=true, msg="Playing Cards"}
		end
		return {activated=false, state=true, msg="Can Not Play Cards"}
	end
	return {activated=false, state=false, msg="Not in Hand Selection State or No Hand Selected or Selected Area is Not Hand"}
end

--- Triggers the same action as the `Select Blind` GUI Button
--- Only activates when the game is in the correct state. Automatically selects the correct blind.
--- @return table table The outcome of the action
---  - `activated`: boolean True if the action was successful, false otherwise
---  - `state`: boolean True if the context was valid to try to trigger the action, false otherwise
function AMA.Voxlatro:use__select_blind()
	if G.STATE == G.STATES.BLIND_SELECT then
		-- Can't fake it, we need the real button
		local current_blind = G.GAME.blind_on_deck or 'Small'
		local blind_index = (current_blind == 'Small' and 1) or (current_blind == 'Big' and 2) or 3
		local button = G.blind_select.UIRoot.children[1].children[blind_index].config.object:get_UIE_by_ID('select_blind_button')
		G.FUNCS.select_blind(button)
		return {activated=true, state=true, msg="Selected Blind"}
	end
	return {activated=false, state=false, msg="Not in Blind Selection State"}
end


--- Multi-Function Helper that does the following:
--- Potential Actions:
---  - Use a Highlighted Consumeable Card
---  - Buy a Highlighted Card from the Shop
---  - Open a Highlighted Booster from the Shop
---  - Redeem a Highlighted Voucher from the Shop
---  - Select/Use a Highlighted Card from the Pack
--- @return table table The outcome of the action
---  - `activated`: boolean True if the action was successful, false otherwise. This is mostly for directly calling this function.
---  - `state`: boolean True if the context was valid to try to trigger the action, false otherwise. This is for use in the context_use() function.
function AMA.Voxlatro:use__buy_or_use_or_redeem()
	if not G.kb_selected_area then return {activated=false, state=false, msg="No Selected Card Area"} end
	if G.jokers and G.kb_selected_area == G.jokers then return {activated=false, state=false, msg="Selected Area is Jokers. Can not Buy/Use/Redeem in this Card Area"} end
	if G.consumeables and G.kb_selected_area == G.consumeables then
		if G.kb_selected_area.highlighted and
			G.kb_selected_area.highlighted[1] and
			G.kb_selected_area.highlighted[1]:can_use_consumeable()
		then
			G.FUNCS.use_card {
				config = {ref_table = G.kb_selected_area.highlighted[1]}
			}
			self:reset_vars()
			return {activated=true, state=true, msg="Using Consumeable Card"}
		end
		-- TODO: Do we need to return here? We definitely need to return if the card can't be used.
	end

	if G.STATE == G.STATES.SHOP and G.kb_selected_area == G.shop_jokers or G.kb_selected_area == G.shop_vouchers or G.kb_selected_area == G.shop_booster then
		local card = G.kb_selected_area.highlighted and G.kb_selected_area.highlighted[1]
		if not card then return {activated=false, state=true, msg="No Highlighted Shop Card/Voucher/Booster"} end
		
		local button = {config = {ref_table = card}}
		
		if card.area == G.shop_booster then
			G.FUNCS.can_open(button)
			if button.config.button then
				G.FUNCS.use_card(button)
				self:reset_vars()
				return {activated=true, state=true, msg="Opening Booster"}
			end
			-- TODO: Do we need to return here?
		end
		
		if card.area == G.shop_vouchers then
			G.FUNCS.can_redeem(button)
			if button.config.button then
				G.FUNCS.use_card(button)
				self:reset_vars()
				return	{activated=true, state=true, msg="Redeeming Voucher"}
			end
			-- TODO: Do we need to return here?
		end
		
		if card.area == G.shop_jokers then
			G.FUNCS.can_buy(button)
			if button.config.button then
				G.FUNCS.buy_from_shop(button)
				return	{activated=true, state=true, msg="Buying Joker"}
			end
			-- TODO: Do we need to return here?
		end
		-- TODO: Do we need to return here?
	end
	
	if G.kb_selected_area == G.pack_cards then
		local card = G.kb_selected_area.highlighted and G.kb_selected_area.highlighted[1]
		if not card then return {activated=false, state=true, msg="No Highlighted Card in Pack"} end
		if card.ability.consumeable and not card:can_use_consumeable() then return {activated=false, state=true, msg="Can Not Use Consumeable Card"} end
		
		local button = {config = {ref_table = card}}
		G.FUNCS.can_select_card(button)
		if button.config.button then
			G.FUNCS.use_card(button)
			self:reset_vars()
			return {activated=true, state=true, msg="Selecting Card from Pack"}
		end
	end
	return {activated=false, state=false, msg="Unknown Context..."}
end


-- enter to select from pack
-- enter to select blind -- done


--- Multifunctional Context Use Function. Allows for the `Enter` Key to be used for multiple actions based on the current game state.
--- Potential Actions:
---  - Cash Out
---  - Select Blind
---  - Select the first card in the current card area
---    - Only if an area is selected and no cards are highlighted
---  - Play Highlighted Cards
---  - Use a Highlighted Consumeable Card
---  - Buy a Highlighted Card from the Shop
---  - Open a Highlighted Booster from the Shop
---  - Redeem a Highlighted Voucher from the Shop
---  - Select/Use a Highlighted Card from the Pack
function AMA.Voxlatro:context_use()

	-- if G.STATE == G.STATES.ROUND_EVAL then
		-- local fakebutton = {config = {}}
		-- if G.__vi_safe_to_cash_out then
		-- 	G.FUNCS.cash_out(fakebutton)
		-- 	G.__vi_safe_to_cash_out = false
		-- end
		-- return
	-- end
	local outcome = self:use__cash_out()
	if outcome.state then return end

	-- if G.STATE == G.STATES.BLIND_SELECT then
	-- 	-- Can't fake it, we need the real button
	-- 	local current_blind = G.GAME.blind_on_deck or 'Small'
	-- 	local blind_index = (current_blind == 'Small' and 1) or (current_blind == 'Big' and 2) or 3
	-- 	local button = G.blind_select.UIRoot.children[1].children[blind_index].config.object:get_UIE_by_ID('select_blind_button')
	-- 	G.FUNCS.select_blind(button)
	-- 	return
	-- end

	outcome = self:use__select_blind()
	if outcome.state then return end

	if not G.kb_selected_area then return end
	if G.kb_selected_area.highlighted and #G.kb_selected_area.highlighted == 0 then
		self:toggle_selected_1idx(1)
		return
	end

	-- if G.STATE == G.STATES.SELECTING_HAND and G.hand and G.kb_selected_area == G.hand then
	-- 	if self:can("play") then
	-- 		G.FUNCS.play_cards_from_highlighted()
	-- 		self:reset_vars()
	-- 	end
	-- 	return
	-- end

	outcome = self:use__play_hand()
	if outcome.state then return end

	-- if G.jokers and G.kb_selected_area == G.jokers then return end
	-- if G.consumeables and G.kb_selected_area == G.consumeables then
	-- 	if G.kb_selected_area.highlighted and
	-- 		G.kb_selected_area.highlighted[1] and
	-- 		G.kb_selected_area.highlighted[1]:can_use_consumeable()
	-- 	then
	-- 		G.FUNCS.use_card {
	-- 			config = {ref_table = G.kb_selected_area.highlighted[1]}
	-- 		}
	-- 		self:reset_vars()
	-- 		return
	-- 	end
	-- end
	-- if G.STATE == G.STATES.SHOP and G.kb_selected_area == G.shop_jokers or G.kb_selected_area == G.shop_vouchers or G.kb_selected_area == G.shop_booster then
	-- 	local card = G.kb_selected_area.highlighted and G.kb_selected_area.highlighted[1]
	-- 	if not card then return end
		
	-- 	local button = {config = {ref_table = card}}
		
	-- 	if card.area == G.shop_booster then
	-- 		G.FUNCS.can_open(button)
	-- 		if button.config.button then
	-- 			G.FUNCS.use_card(button)
	-- 			self:reset_vars()
	-- 			return
	-- 		end
	-- 	end
		
	-- 	if card.area == G.shop_vouchers then
	-- 		G.FUNCS.can_redeem(button)
	-- 		if button.config.button then
	-- 			G.FUNCS.use_card(button)
	-- 			self:reset_vars()
	-- 			return
	-- 		end
	-- 	end
		
	-- 	if card.area == G.shop_jokers then
	-- 		G.FUNCS.can_buy(button)
	-- 		if button.config.button then
	-- 			G.FUNCS.buy_from_shop(button)
	-- 			return
	-- 		end
	-- 	end
	-- end
	
	-- if G.kb_selected_area == G.pack_cards then
	-- 	local card = G.kb_selected_area.highlighted and G.kb_selected_area.highlighted[1]
	-- 	if not card then return end
	-- 	if card.ability.consumeable and not card:can_use_consumeable() then return end
		
	-- 	local button = {config = {ref_table = card}}
	-- 	G.FUNCS.can_select_card(button)
	-- 	if button.config.button then
	-- 		G.FUNCS.use_card(button)
	-- 		self:reset_vars()
	-- 		return
	-- 	end
	-- end
	outcome = self:use__buy_or_use_or_redeem()
	if outcome.state then return end

	return
end

function AMA.Voxlatro:buy_and_use()
	if not G.kb_selected_area then return end
	if G.kb_selected_area.highlighted and #G.kb_selected_area.highlighted == 0 then
		self:toggle_selected_1idx(1)
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

function AMA.Voxlatro:isNewUIEnabled()
	return false
	-- return AMA.card_ui.enable_new_ui
end

-- ----- Card Helpers -----

--- Determines if the card is in the currently selected area
--- @return boolean boolean True if the card is in the currently selected area, false otherwise
function Card:is_area_selected()
	return self.area ~= nil and self.area == G.kb_selected_area
end

--- Determines if the card is in a user intractable gameplay area or if it's in a non-gameplay area
--- Examples of non-gameplay areas are View Deck UI Menu, Collection UI Menu, Title Screen, etc.
--- @return boolean boolean True if the card is in a user intractable gameplay area, false otherwise
function Card:in_user_area()
	if self.area == nil then return false end
	return self.area:is_user_area()
end

-- ----- CardArea Helpers -----
--- Determines if the card is a default selection area.
--- This is based both on the area type, and the current game state.
--- @return boolean boolean True if the card area is a default selection area, false otherwise
function Card:in_default_selection_area()
	if self.area == nil then return false end

	if self.area == G.hand and G.STATE == G.STATES.SELECTING_HAND then return true end

	if self.area == G.pack_cards
		and (
			G.STATE == G.STATES.TAROT_PACK
			or G.STATE == G.STATES.PLANET_PACK
			or G.STATE == G.STATES.SPECTRAL_PACK
			or G.STATE == G.STATES.BUFFOON_PACK
			or G.STATE == G.STATES.STANDARD_PACK
		) then
		return true
	end

	if self.area == G.joker
		and (
			G.STATE == G.STATES.BLIND_SELECT
			or G.STATE == G.STATES.HAND_PLAYED
			or G.STATE == G.STATES.ROUND_EVAL
		) then
		return true
	end

	if self.area == G.shop_jokers and G.STATE == G.STATES.SHOP then return true end

	return false
end


---Determines if the cardArea is a user intractable gameplay area or if it's a non-gameplay area
---@return boolean True if the cardArea is a user intractable gameplay area, false otherwise
function CardArea:is_user_area()
	if self.config ~= nil then
		if self.config.type == "deck" then return false end
		if self.config.type == "title" then return false end
	end

	local gameplay_areas = {G.hand, G.jokers, G.consumeables, G.shop_jokers, G.shop_vouchers, G.shop_booster, G.pack_cards}
	-- TODO: There are a few cases where the area will be one of the above, but the card is not actually in a user intractable area.
	--       (For Example, the deck of cards is in the hand (I think) area.
	for _, gp_area in pairs(gameplay_areas) do -- Use `pairs()` instead of `ipairs()`
		if gp_area and self == gp_area then return true end
	end
	return false
end

---Searches for the name of the CardArea. Correlates to the name of the Area in the `G` table.
---@return string? The name of the CardArea if known. nil Otherwise.
function CardArea:get_cardarea_name()

	local known_area_keys = {

		-- --- Primary Card Areas used in `card_selection.lua` --- --

		"hand",           -- Hand of Playing Cards
		"jokers",         -- Currently owned jokers
		"consumeables",   -- Currently owned consumable cards
		"shop_jokers",    -- Jokers in the shop
		"shop_vouchers",  -- Vouchers in the shop
		"shop_booster",   -- Booster packs in the shop
		"pack_cards",     -- The second row of cards in Arcana & Spectral Packs
		
		-- --- Other Areas --- --
		--   More areas may exist, but these are the ones we know about
		--   Found via searching `G`

		"title_top",  -- This seems to be the card in the center of the title screen
		"deck",  -- This is the Deck of Cards in the bottom right corner of the game area
	}

	-- Card Areas we have been unable to find in `G` --
    -- - The Deck in the *New Run* UI Menu
    -- - Any of the cards in the *New Challenge* UI Menu
	-- - Any cards in the *Customize Deck* UI Menu
	-- - Any cards in the *Collections* UI Menu
	-- - Any cards in the *View Deck* UI Menu

	for _, potential_area_name in ipairs(known_area_keys) do
		if G[potential_area_name] and G[potential_area_name] == self then
			return potential_area_name
		end
	end
	return nil
end

--- Returns the number of cards in the CardArea
--- @return number The number of cards in the current card area
function CardArea:get_card_count()
	if not self.cards then return 0 end
	return #self.cards
end

-- ----- Monkey-patching -----


---@diagnostic disable-next-line: duplicate-set-field
function Card:update(dt)
	AMA.card_sel._update_card(self, dt)
	if not self:in_user_area() then
		self.__kb_index = nil
		--TODO: Remove Talon-ID? Although thats done in CardArea:update.
	end
	if not self.last_state or G.STATE ~= self.last_state then
		AMA.card_sel:reset_vars()
		self.last_state = G.STATE
		if G.STATE == G.STATES.ROUND_EVAL then
			G.__vi_safe_to_cash_out = false
		end
	end
end

---@diagnostic disable-next-line: duplicate-set-field
function CardArea:update(dt)
	AMA.card_sel._update_area(self, dt)
	if self.cards then
		for i, card in ipairs(self.cards) do
			card.__kb_index = i
			if card:in_user_area() then
				AMA.card_sel:assign_next_talon_id(card)
			else
				card.__talon_id = nil
			end
		end
	end
end

---@diagnostic disable-next-line: duplicate-set-field
function Card:draw(layer)
	AMA.card_sel._draw_card(self, layer)

	-- This seems to do the following:
	--  - Nothing if the card is NOT in the currently selected area
	--  - Otherwise:
	--    - Add a Triangle Pointer to the card to indicate it's selected

	-- ------ Config Consts ------

	-- --- Behavior of numbers on cards in default areas ---

	--- @type boolean
	--- If true, draw a number on the card even if the card is not in the currently selected area,
	--- As long as it's area is one that would be selected by default via `Voxlatro:toggle_selected(index)`
	local _draw_numbers_on_unselected_default_area_cards = true

	--- @type boolean
	--- If true, the number will be drawn on default area cards even when another area is selected.
	--- Otherwise, the number will only be drawn if no other area is selected or the card is in the currently selected area.
	--- Has no effect if `_draw_numbers_on_unselected_default_area_cards` is false.
	local _always_draw_numbers_on_default_area_cards = false

	--- @type boolean
	--- Specific override of above setting for the Joker area
	--- If false, the Joker area will not draw numbers when unselected even if `_draw_numbers_on_unselected_default_area_cards` is true.
	--- Has no effect if `_draw_numbers_on_unselected_default_area_cards` is false.
	local _draw_numbers_on_joker_area_when_unselected = true

	--- @type boolean
	--- Specific override of above setting for the Shop_Joker area
	--- If false, the Shop_Joker area will not draw numbers when unselected even if `_draw_numbers_on_unselected_default_area_cards` is true.
	--- Has no effect if `_draw_numbers_on_unselected_default_area_cards` is false.
	local _draw_numbers_on_shop_joker_area_when_unselected = false

	--- @type boolean
	--- If true, draw Talon IDs on some unselected areas.
	local _draw_ids_on_select_unselected_areas = true

	local _always_draw_talon_ids = false

	-- local _dont_draw_numbers_when_area_not_selected = true

	if not self.__kb_index then return end
	if not self.area then return end


	--- @type boolean
	--- Indicates if the card is in the currently selected area and 
	---   if the index is within the current selection offset
	local kb_selectable = false
	if self.area == G.kb_selected_area 
		and self.__kb_index
		and self.__kb_index > G.kb_select_offset
		and self.__kb_index <= G.kb_select_offset + 10
	then
		kb_selectable = true
	end

	--- @type boolean
	--- Indicates if we need to draw a number over the card.
	--- This should be true if one of the following is true:
	--- - The card is in the currently selected area
	--- - The card is in the hand area and the game is in the SELECTING_HAND state (Default Selection Area)
	--- - The card is in the pack_cards area and the game is in one of the pack states (Default Selection Area)
	local draw_number = false
	local draw_talon_id = false
	if self.area == G.kb_selected_area then
		draw_number = true

	elseif self.area == G.hand and G.STATE == G.STATES.SELECTING_HAND
		and _draw_numbers_on_unselected_default_area_cards 
	then
		-- This card is in the hand area and the game is in the SELECTING_HAND state
		draw_number = _always_draw_numbers_on_default_area_cards or G.kb_selected_area == nil
		draw_talon_id = not draw_number

	elseif self.area == G.pack_cards
			and (
				G.STATE == G.STATES.TAROT_PACK
				or G.STATE == G.STATES.PLANET_PACK
				or G.STATE == G.STATES.SPECTRAL_PACK
				or G.STATE == G.STATES.BUFFOON_PACK
				or G.STATE == G.STATES.STANDARD_PACK
			) and _draw_numbers_on_unselected_default_area_cards 
	then
		-- This card is in the pack_cards area and the game is in one of the pack states
		-- draw_number = true
		draw_number = _always_draw_numbers_on_default_area_cards or G.kb_selected_area == nil
		draw_talon_id = not draw_number

	elseif self.area == G.joker
			and (
				G.STATE == G.STATES.BLIND_SELECT
				or G.STATE == G.STATES.HAND_PLAYED
				or G.STATE == G.STATES.ROUND_EVAL
			) and _draw_numbers_on_unselected_default_area_cards
			and _draw_numbers_on_joker_area_when_unselected 
	then
		-- This card is in the joker area and the game is in one of the states where selecting a joker is valid
		-- draw_number = true
		draw_number = _always_draw_numbers_on_default_area_cards or G.kb_selected_area == nil
	
	elseif self.area == G.shop_jokers and G.STATE == G.STATES.SHOP and
		_draw_numbers_on_unselected_default_area_cards and
		_draw_numbers_on_shop_joker_area_when_unselected
	then
		-- This card is in the shop_jokers area and the game is in the SHOP state
		-- draw_number = true
		draw_number = _always_draw_numbers_on_default_area_cards or G.kb_selected_area == nil

	-- elseif self.area == G.pack_cards and _draw_numbers_on_unselected_default_area_cards then
	-- 	print("CardArea is pack_cards but not valid state. G.STATE: " .. inspect(G.STATE))
	-- elseif self.area == G.pack_cards and not _draw_numbers_on_unselected_default_area_cards then
	-- 	print("CardArea is pack_cards drawing numbers on unselected areas is disabled.")

	elseif _draw_ids_on_select_unselected_areas 
			and (
				self.area == G.shop_vouchers or
				self.area == G.shop_booster or
				self.area == G.pack_cards or
				self.area == G.consumeables or
				self.area == G.jokers
			)
	then
		-- This card is in the consumeables area and the consumeables area is not currently selected
		draw_talon_id = not draw_number
	end

	-- If there is nothing to draw, return early
	if not kb_selectable and not draw_number and not draw_talon_id then
		return
	end

	if draw_number and _always_draw_talon_ids then
		draw_talon_id = true
		draw_number = false
	end

	local transform = self.VT or self.T
	love.graphics.push()
	love.graphics.scale(G.TILESCALE, G.TILESCALE)
	love.graphics.translate(transform.x*G.TILESIZE+transform.w*G.TILESIZE*0.5, transform.y*G.TILESIZE+transform.h*G.TILESIZE*0.5)
	love.graphics.rotate(transform.r)
	love.graphics.translate(-transform.w*G.TILESIZE*0.5, -transform.h*G.TILESIZE*0.5)

	if kb_selectable then
		love.graphics.setColor(G.C.UI.OUTLINE_LIGHT_TRANS)
	else
		-- love.graphics.setColor(G.C.UI.TEXT_INACTIVE)
		love.graphics.setColor(G.C.UI.TRANSPARENT_DARK)
	end

	local arrow_x = transform.w*G.TILESIZE*0.5
	local arrow_y = transform.h*G.TILESIZE*-0.1
	local arrow_radius = 0.2*G.TILESIZE
	local arrow_angle1 = -3 * math.pi / 4
	local arrow_angle2 = -math.pi / 4

	if self.area == G.kb_selected_area then
		love.graphics.arc('fill', arrow_x, arrow_y, arrow_radius, arrow_angle1, arrow_angle2, 1)
	end

	-- local dot_radius = G.TILESIZE * 0.00625 * 5 -- dot_radius is 1/32 of the arrow_radius (which is 1/160 of the tilesize)
	-- draw_dot(arrow_x, arrow_y, dot_radius)  -- Bottom-Center point of the arrow
	local left_corner = GetArrowCorner(arrow_x, arrow_y, arrow_radius, arrow_angle1)
	local right_corner = GetArrowCorner(arrow_x, arrow_y, arrow_radius, arrow_angle2)
	-- draw_dot(left_corner.x, left_corner.y, dot_radius)
	-- draw_dot(right_corner.x, right_corner.y, dot_radius)

	local arrow_params = {
		x = arrow_x,
		y = arrow_y,
		left_corner = left_corner,
		right_corner = right_corner,
		radius = arrow_radius,
		angle1 = arrow_angle1,
		angle2 = arrow_angle2,
	}
	-- Position the number just slightly above the arrow
	local y_offset = 1
	if self.area ~= G.kb_selected_area then
		-- Move the number down since there is no o->
		-- y_offset = -5
		y_offset = -7
		-- y_offset = -10
	end


	-- self._verbose_log = (verbose ~= nil and {verbose} or {false})[1]
	local numb_or_id_to_draw = (draw_talon_id and {self.__talon_id} or {self.__kb_index})[1]
	if not AMA.card_sel:isNewUIEnabled() and (draw_talon_id or draw_number) then
		draw_number_above_arrow(y_offset, numb_or_id_to_draw, arrow_params)
	end

	love.graphics.pop()

	-- Try to dump card info
	-- dump_card_info(self, arrow_radius, arrow_x, arrow_y, left_corner, right_corner)
end
	end
end


-- Draw Helpers

function GetArrowCorner(x, y, radius, angle)
	local corner_x = x + radius * math.cos(angle)
	local corner_y = y + radius * math.sin(angle)
	return {x = corner_x, y = corner_y}
end

-- local dumped_number_info = false

--- Draws a number above the arrow at the given coordinates  
--- This function is use to indicate which number is associated with each card
---@param y_offset number The y coordinate (rel to top of arrow) to draw the number at
---@param number number The number to draw above the arrow
---@param arrow table The table containing the x and y coordinates of the arrow as well as left_corner, right_corner, radius, angle1, and angle2
function draw_number_above_arrow(y_offset, number, arrow)

	-- local scale = G.TILESCALE * 0.025
	local scale = G.TILESIZE * 0.02

    local x = arrow.x
	local arrow_top_y = arrow.left_corner.y
	-- local number_y = arrow_top_y --+ y

	-- Get the height of the number
	local font = love.graphics.getFont()
	local number_height = font:getHeight()
	local number_width = font:getWidth(number)

	-- Translate the number to the correct position based on the size of the font
	-- local number_y = arrow_top_y + y_offset

	-- local number_y_pos = arrow_top_y - number_height * scale - ((number - 1))
	local number_y_pos = arrow_top_y - number_height * scale - y_offset
	local number_x_pos = x - (number_width * scale) / 2

    -- love.graphics.setColor(1, 0, 0)
    love.graphics.setColor(G.C.UI.TEXT_LIGHT)
    -- love.graphics.print(number, x, y)
	-- love.graphics.printf(number, x, y, G.TILESIZE * 0.5, number_size, "center")
	-- love.graphics.print(number, number_x_pos, arrow.left_corner.y, nil, scale, scale)
	love.graphics.print(number, number_x_pos, number_y_pos, nil, scale, scale)

	-- if not dumped_number_info then
	-- 	-- INFO - [G] X: 18.687804878049 Y: -16.330866149136 Width: 9 Height: 20
	-- 	print("X: " .. number_x_pos .. " Y: " .. number_y_pos .. " Width: " .. number_width .. " Height: " .. number_height)
	-- 	dumped_number_info = true
	-- end

end
