
-- Primary Global Namespace
if not AMA then AMA = {} end

-- ---------- Configs ----------

--- Enables Debug Mode.
--- This will enable several hardcoded debugging keybinds as well a few other things.
--- @type boolean
local DEBUG_MODE = true

--- Controls whether or not to enable the `evalLua` RPC Command.
--- This is a security risk and should only be enabled if you know what you are doing.
--- @type boolean
local ENABLE_ARBITRARY_EVAL = true

--- When false, the only keybind the TalonRPC Keybind & DEBUG_MODE Keybinds (if DEBUG_MODE is enabled) will be available.
--- This as useful for when using DebugPlus to prevent conflicts.
--- Regardless of this setting, actions tied to key presses can still be triggered via the `pressKey` RPC Command.
--- @type boolean
local ENABLE_NON_RPC_KEYBINDS = true


-- ---------- Core Imports ----------

--- @module 'inspect'
local inspect, err = SMODS.load_file("lib/inspect.lua")()
if err then
	print("Error loading library `inspect`: " .. err)
	error(err)
end

--- @module 'talon_rpc'
local Talon_RPC, err = SMODS.load_file("core/talon_rpc.lua")()
if err then
	print("Error loading library `talon_rpc`: " .. err)
	error(err)
end

--- @module 'utils'
local utils, err = SMODS.load_file("core/utils.lua")()
if err then
	print("Error loading library `utils`: " .. err)
	error(err)
end

--- @module 'DPrint'
local DPrint, err = SMODS.load_file("lib/DPrint.lua")()
if err then
	print("Error loading library `dprint`: " .. err)
	error(err)
end


-- ---------- Create AMA ----------
AMA.dprint = DPrint:n{enabled=true, log_console=false, log_file=true, file_name="debug.log", folder_name="debug_logs", add_datetime=true}
AMA.talon_rpc = Talon_RPC:new()

local runEvalCommand = nil
local success, dpAPI = pcall(require, "debugplus-api")
if success and dpAPI.isVersionCompatible(1) then
    -- print("DebugPlus API is available")
	runEvalCommand, err = SMODS.load_file("core/eval_code.lua")()
	if err then
		print("Error loading library `eval_code`: " .. err)
		runEvalCommand = nil
	end
else
	runEvalCommand, err = SMODS.load_file("core/evalCodeBundled/eval_code_ndpb.lua")()
	if err then
		print("Error loading library `evalCodeBundled/eval_code_ndpb.lua`: " .. err)
		runEvalCommand = nil
	end
end

if not runEvalCommand then
	print("Note! Arbitrary Lua code execution is disabled as the DebugPlus API is not available and/or the fallback `evalCodeBundled` library failed to load or is not available and/or `eval_code_ndpb.lua` / `eval_code.lua` failed to load.")
end

local _, err = SMODS.load_file("core/card_selection.lua")()
if err then
	print("Error loading library `card_selection`: " .. err)
	error(err)
end

-- ---------- Local Variables ----------

local mod = SMODS.current_mod
AMA.current_mod = mod  -- This is for debugging mostly

-- ---- Keybinding Tables ----
-- The following tables are used to store the keybinding_name: function pairs.

--- Keybinds that are only available when the overlay menu is closed.
--- In general, these are all/most of the keybinds that do not trigger an RPC Command.
--- @type table<string, function>
local keybinds = {}

--- Keybinds that are always available, regardless of the state of the overlay menu.
--- For now, this is just the TalonRPC keybind. I don't think there will be anymore added in the future however, as we are focusing primarily on RPC command Actions.
--- @type table<string, function>
local always_available_keybinds = {}

-- ---------- Local Functions ----------

--- Sort the hand by suit (descending)
--- @return nil
local function sort_suit()
	if not G.hand then return end
	G.FUNCS.sort_hand_suit()  -- 'suit desc'
end

--- Sort the hand by rank (descending)
--- @return nil
local function sort_rank()
	if not G.hand then return end
	G.FUNCS.sort_hand_value()  -- 'desc'
end

--- This function is used to sort the hand in different ways.
--- The sort type is passed in as a string.
--- Valid values are: 'desc', 'asc', 'suit desc', 'suit asc'
--- @param sort_type string The type of sort to perform. Valid values are: 'desc', 'asc', 'suit desc', 'suit asc'
--- @return boolean Whether the sort_type was valid.
local function sort_custom(sort_type)
	
	-- Validate sort_type. Valid values are: desc', 'asc', 'suit desc', 'suit asc'
	sort_type = string.lower(sort_type)
	if sort_type ~= 'desc' and 
		sort_type ~= 'asc' and 
		sort_type ~= 'suit desc' and
		sort_type ~= 'suit asc'
	then
		print("Invalid Sort Type: " .. sort_type)
		return false
	end

	if not G.hand then return true end

	-- Do the sort
	G.hand:sort(sort_type)
	play_sound('paper1')
	return true
end

--- Toggles the current sorting method for your hand between `Rank` & `Suit`.
--- Maintains the sorting order (ascending or descending) when switching between `Rank` & `Suit`.
--- @return nil
local function sort_toggle()
	if not G.hand then return end
	local current_sort_type = G.hand.config.sort
	if current_sort_type == 'suit desc' then
		sort_custom('desc')
	elseif current_sort_type == 'desc' then
		sort_custom('suit desc')
	elseif current_sort_type == 'suit asc' then
		sort_custom('asc')
	elseif current_sort_type == 'asc' then
		sort_custom('suit asc')
	else
		sort_custom('desc')
	end
end

--- This triggers the deck preview UIBox. This is the UI Element that shows when you move the cursor over the deck.
local function peek_deck()
	if not G.deck then return end
	if not G.deck_preview and not G.OVERLAY_MENU then
		G.deck_preview = UIBox{
            definition = G.UIDEF.deck_preview(),
            config = {align='tm', offset = {x=0,y=-0.8},major = G.hand, bond = 'Weak'}
        }
	else
		if G.deck_preview then
			G.deck_preview:remove()
		end
		G.deck_preview = nil
	end
end
	
--- This is the Overly Menu that opens up when you click on the deck.
local function toggle_deck_info(e)
	if not G.deck then return end
	G.FUNCS.deck_info(e)
end

local function click_on_btn_by_id(id)
	local button = G.OVERLAY_MENU:get_UIE_by_ID(id)
	if button then
		button:click()
		return true
	end
	print("Button " .. id .. " not found!")
	return false
end

local function navigate_overlay_menu_back()

	-- If there is no overlay menu open, there's nothing to do. Return.
	if not G.OVERLAY_MENU then return end

	-- Try to click on the back button
	if click_on_btn_by_id('overlay_menu_back_button') then return end

	print("Back Button Not Found! Exiting Overlay Menu Directly.")
	-- If the back button is not found, just exit the menu
	G.FUNCS.exit_overlay_menu()
end

-- Talon Functions

-- ::::: RPC Command Helpers :::::

---@enum overlay_menu_types
local OVERLAY_MENU_TYPES = {
	options = 1,
	run_info = 2,
	deck_info = 3,
	deck_peek = 4,
}

local _overlay_menu_functions_tbl = {
	[OVERLAY_MENU_TYPES.options] = {G.FUNCS.options, G.FUNCS.exit_overlay_menu},
	[OVERLAY_MENU_TYPES.run_info] = {G.FUNCS.run_info, G.FUNCS.exit_overlay_menu},
	[OVERLAY_MENU_TYPES.deck_info] = {toggle_deck_info, G.FUNCS.exit_overlay_menu},
	[OVERLAY_MENU_TYPES.deck_peek] = {peek_deck, peek_deck},

}

--- Helper function to toggle the different overlay menus
--- @param menu_type overlay_menu_types The type of menu to toggle
--- @param abort_on__no_esc? boolean If true, will abort if `G.OVERLAY_MENU.config.no_esc` is true. Default: true
--- @return {state: boolean?, msg: string} table The return value of the function. State: True=Opened, False=Closed, nil=menu could not be toggled (E.G., If no_esc, or other issues)
local function toggle_overlay_menu(menu_type, abort_on__no_esc)

	----------
	-- We should add in ability to switch by name
	-- local tab_but = G.OVERLAY_MENU:get_UIE_by_ID('tab_but_'..G.focused_profile)
	-- G.FUNCS.change_tab(tab_but)G.FUNCS.change_tab(tab_but)
	----------

	if abort_on__no_esc == nil then abort_on__no_esc = true end

	-- TODO: Write docs on `G.OVERLAY_MENU.config.no_esc` (See: `engine/controller.lua:#L795`)
	if abort_on__no_esc and G.OVERLAY_MENU and G.OVERLAY_MENU.config.no_esc then
		print("Aborting toggle_overlay_menu(" .. menu_type .. ") because G.OVERLAY_MENU.config.no_esc is true")
		return {state=nil, msg="Unable to Toggle. no_esc is true"}
	end

	if G.OVERLAY_MENU then
		_overlay_menu_functions_tbl[menu_type][2]({})
		return {state=false, msg="Menu Closed"}
	end

	_overlay_menu_functions_tbl[menu_type][1]({})
	return {state=true, msg="Menu Opened"}
end

--- @param direction? string The direction to change the tab to. Valid values are 'left' and 'right'. If nil, will use `tab_number` instead.
--- @param tab_number? number The number of the tab to choose. If nil, will use `direction` instead.
local function change_overlay_menu_tab(direction, tab_number)

	-- - Parameter Validation -

	if direction == nil and tab_number == nil then 
		return {state=false, msg="Must Provide Either Direction or Tab Number"}
	end
	
	if direction ~= nil and direction ~= 'left' and direction ~= 'right' then 
		return {state=false, msg="Invalid Direction: " .. direction}
	end

	-- Hold off on validating `tab_number` until we know how many tabs there are

	-- Command Only Valid if `G.OVERLAY_MENU` is true (Aka a Menu is Open)
	if not G.OVERLAY_MENU then 
		return {state=false, msg="Overlay Menu Not Open"}
	end

	-- - Get Current Menu w/ Tabs -

	local tab_shoulders = G.OVERLAY_MENU:get_UIE_by_ID('tab_shoulders')
	if not tab_shoulders then 
		return {state=false, msg="Current Menu Does Not Have Tabs"}
	end

	if not tab_shoulders.config.focus_args or tab_shoulders.config.focus_args.type ~= 'tab' then
		-- print(inspect(tab_shoulders.config, {depth = 2}))
		return {state=false, msg="Current Menu Only Has One Tab, or other issue."}
	end

	-- - Get Tabs From Menu -
	local proto_choices = tab_shoulders.UIBox:get_group(nil, tab_shoulders.children[1].children[1].config.group)
	-- dprint:log("Proto Tabs: " .. inspect(proto_choices, {depth=3}))
	local choices = {}
	for _, v in ipairs(proto_choices) do
		if v.config.choice and v.config.button then choices[#choices+1] = v end
	end

	-- - Validate Current State -

	-- if not choices then 
	if #choices == 0 then
		-- I'm also not sure if this will ever happen, but it's here just in case. I'm not sure what would cause this.
		return {state=false, msg="No Valid Tabs Found"}
	end

	if tab_number ~= nil and (tab_number < 1 or tab_number > #choices) then 
		return {state=false, msg="Invalid Tab Number: " .. tab_number .. " (Valid Numbers: 1 - " .. #choices .. ")"}
	end

	if tab_number ~= nil then
		if choices[tab_number].config.chosen then
			return {state=false, msg="Tab #" .. tab_number .. " Already Chosen"}
		end

		choices[tab_number]:click()
		return {state=true, msg="Switched to Tab #" .. tab_number}
	end

	if direction ~= nil then
		for k, v in ipairs(choices) do
			if v.config.chosen then
				local next_i = nil
				if direction == 'left' then 
					next_i = k ~= 1 and (k-1) or (#choices)
					if tab_shoulders.config.focus_args.no_loop and next_i > k then return {state=false, msg="Can not go any further left"} end
				elseif direction == 'right' then 
					next_i = k ~= #choices and (k+1) or (1)
					if tab_shoulders.config.focus_args.no_loop and next_i < k then return {state=false, msg="Can not go any further right"} end
				end

				choices[next_i]:click()
				return {state=true, msg="Switched to Tab #" .. next_i}
			end
		end
	end
end

local function step_through_option_cycle(direction)
    -- TODO: This doesn't work very many places yet. Mostly in places where there are multiple cyclers. We probably need to provide a way to focus on specific cyclers?

	-- - Parameter Validation -
	if direction == nil or (direction ~= 'left' and direction ~= 'right') then 
		return {state=false, msg="Must Provide Valid Direction. Valid Values: 'left' or 'right'"}
	end

	-- Command Only Valid if `G.OVERLAY_MENU` is true (Aka a Menu is Open)
	if not G.OVERLAY_MENU then 
		return {state=false, msg="Overlay Menu Not Open"}
	end

	-- - Get Current Menu w/ Tabs -

	local cycler_shoulders = G.OVERLAY_MENU:get_UIE_by_ID('cycle_shoulders')
	if not cycler_shoulders then 
		return {state=false, msg="Could not find Cycle Shoulders UI Element"}
	end

	local cycler = cycler_shoulders.children[1]
	if not cycler then 
		return {state=false, msg="Current Menu Does Not Have Any Options to Cycle"}
	end

	if not cycler.config.focus_args or cycler.config.focus_args.type ~= 'cycle' then
		-- I'm not sure if this will ever happen, but it's here just in case. I'm not sure what would cause this.
		local value_to_dump = cycler.config.focus_args and cycler.config.focus_args.type or "nil"
		return {state=false, msg="Tab UI Element Not Focused or something... (cycler.config.focus_args.type = " .. value_to_dump .. ")"}
	end

	if direction == 'left' then
		cycler.children[1]:click()
		return {state=true, msg="Cycled Left"}
	elseif direction == 'right' then
		cycler.children[3]:click()
		return {state=true, msg="Cycled Right"}
	end

	return {state=false, msg="Critical Error: Unreachable location."}

end

-- ::::: RPC Command Processing :::::

-- ----- Talon RPC Command Handlers -----

local function handle_newRunMenu(command)
	-- TODO: Refactor to use `toggle_overlay_menu()` ?
	 -- ids: `restart_button`, `from_game_over`, `main_menu_play`

	if G.OVERLAY_MENU then
		-- return {state=false, msg="Overlay Menu Not Open"}
		-- AMA.talon_rpc:send_response(command.uuid, {warning = "Overlay Menu Open"})
		G.FUNCS.exit_overlay_menu()
		return {
			type = "no-action",
			reflection = {type = command.data.type, value = "New Run Menu Closed"}
		}
	end

	if not G.SETTINGS.tutorial_complete then
		-- I'm not sure if this will cause an issue but I'm just going to avoid this state in case.
		AMA.talon_rpc:send_response(command.uuid, {warning = "Tutorial Not Complete. Aborting..."})
		return
	end

	-- create appropriate config based on the current state.
	local e = nil
	if G.STAGE == G.STAGES.RUN then
		e = {config = {id = 'restart_button'}}
	elseif G.STAGE == G.STAGES.MAIN_MENU then
		e = {config = {id = 'main_menu_play'}}
	else
		AMA.talon_rpc:send_response(command.uuid, {error = "Unexpected State! G.STAGE: " .. inspect(G.STAGE)})
		return
	end

	G.FUNCS.setup_run(e)

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = "Restart Run Menu Opened"}
	}
end

local function handle_selectCard(command)

	local index = command.data.cardNumber or 1
	AMA.card_sel:toggle_selected_1idx(index)
	print("Toggled Selected as Requested: " .. index)

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = index}
	}
end

local function selectMultipleCardsWithTalonIDs_Helper(command)
	local talon_ids = command.data.cardIDs or {}
	local successes = {}
	for i, talon_id in ipairs(talon_ids) do
		local success = AMA.card_sel:toggle_with_talon_id(talon_id)
		successes[talon_id] = success
	end
	print("Toggled Selected by ID as Requested: " .. inspect(successes))

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = successes}
	}
end

local function handle_selectMultipleCards(command)
	-- Expected Command Data Format:
	-- cardNumbers: list of 1-based indices of cards to select
	print("Select Multiple Cards Command Received: " .. inspect(command, {depth=5}))
	if command.data.cardIDs ~= nil then
		return selectMultipleCardsWithTalonIDs_Helper(command)
	end

	local card_numbers = command.data.cardNumbers or {}
	for i, card_number in ipairs(card_numbers) do
		AMA.card_sel:toggle_selected_1idx(card_number)
	end
	print("Toggled Selected as Requested: " .. inspect(card_numbers))

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = card_numbers}
	}
end

local function handle_invertCardSelection(command)
	-- Expected Command Data Format:
	-- exceptCards: list of 1-based indices of cards to avoid inverting. Optional

	local except_cards = command.data.exceptCards or {}

	AMA.card_sel:try_select_default_cardarea()  -- If no cardArea is selected, select the default one.
	local number_of_cards = AMA.card_sel:get_size()
	if number_of_cards == 0 then
		AMA.talon_rpc:send_response(command.uuid, {error = "No Cards In Selected Area or No Area Selected (e1)"})
		return
	end

	local cards_to_raise = {}
	local cards_to_lower = {}

	if not G.kb_selected_area or not G.kb_selected_area.cards then
		AMA.talon_rpc:send_response(command.uuid, {error = "No Cards In Selected Area or No Area Selected (e2)"})
		return
	end
	for i, card in ipairs(G.kb_selected_area.cards) do
		if not utils.check_if_value_in_table(i, except_cards) then
			if card.highlighted then
				table.insert(cards_to_lower, i)
			else
				table.insert(cards_to_raise, i)
			end
		else
			print("Skipping Card #" .. i)
		end
	end

	for i, card_number in ipairs(cards_to_lower) do
		-- print("[INVERTING] Lowering Card #" .. card_number)
		AMA.card_sel:toggle_selected_1idx(card_number)
	end
	for i, card_number in ipairs(cards_to_raise) do
		-- print("[INVERTING] Raising Card #" .. card_number)
		AMA.card_sel:toggle_selected_1idx(card_number)
	end

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = except_cards}
	}
end

local function handle_moveCard(command)
	-- TODO: I'm very much unhappy with the way the Command Data is structured. We should refactor this!!!

	-- Expected Command Data Format:
	-- cardNumber: 1-based index of card to move. Required
	-- movement: Table. Required. This table will contain the instructions on how to move the card. There are several ways to specify how to move the card:
	--                       Move the card to the specified position. Keys: `position`
	--                       Move the card a relative amount of places left or right. Keys: `vector`
	--                       Swap the card with another card. Keys: `swapWith`
	-- -- Keys: (one must be provided)
	--   -- position: 1-based index of the card to move the card to. Optional.
	--   -- vector: number of places to move the card. Optional.
	--   -- swapWith: 1-based index of the card to swap the card with. Optional.

	print("Move Card Command Received: " .. inspect(command, {depth=5}))

	local card_number = command.data.cardNumber or command.data.cardID
	local cardArea = command.data.cardArea
	local movement = command.data.movement
	local move_type = command.data.moveType

	local cardName = (type(card_number) == "string" and ("Card ID: " .. tostring(card_number))) or ("Card #" .. tostring(card_number))

	if not card_number or not movement or not move_type then
		AMA.talon_rpc:send_response(command.uuid, {error = "Missing Required Keys in Move Card Command: " .. inspect(command.data)})
		return
	end

	local required_movement_keys = {
		vector = {"vector"},
		position = {"position"},
		swapWith = {"swapWith"},
		moveToLimit = {"direction"}
	}

	if not utils.check_if_key_in_table(move_type, required_movement_keys) then
		AMA.talon_rpc:send_response(command.uuid, {error = "Invalid Move Type: " .. move_type})
		return
	end
	local required_move_type_keys = required_movement_keys[move_type]
	for _, key in ipairs(required_move_type_keys) do
		if not movement[key] then
			AMA.talon_rpc:send_response(command.uuid, {error = "Missing Required Key in Move Card Command: " .. key})
			return
		end
	end

	local result = {state=false, msg="Invalid Movement Instructions"}
	if move_type == "position" then
		-- Move the card to the specified position
		result = AMA.card_sel:move_card_to_position(card_number, movement.position, cardArea)
		print("Moved " .. cardName .. " to Position #" .. movement.position)
	elseif move_type == "moveToLimit" then
		result = AMA.card_sel:move_card_to_limit(card_number, movement.direction, cardArea)
		print("Moved " .. cardName .. " to Limit " .. movement.direction)

	elseif move_type == "vector" then
		-- Move the card a relative amount of places left or right
		result = AMA.card_sel:move_card_relative(card_number, movement.vector, cardArea)
		print("Moved " .. cardName .. " " .. movement.vector .. " places")
	elseif move_type == "swapWith" then
		-- Swap the card with another card
		result = AMA.card_sel:move_cards_swap_positions(card_number, movement.swapWith, cardArea, nil, nil)
		print("Swapped " .. cardName .. " with Card #" .. movement.swapWith)
	end

	if not result.state then
		AMA.talon_rpc:send_response(command.uuid, {warning = result.msg})
		return
	end

	if result.state and command.data.resetAreaAfterMove then
		AMA.card_sel:reset_vars()
	end

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = result.msg}
	}
end

local function handle_toggleRunInfo(command)
	-- TODO: Refactor keybinding generation code to allow for actions while `G.OVERLAY_MENU` is true
	-- TODO: !Critical! Prevent this from running when a Run is not in progress.
	local new_menu_state = toggle_overlay_menu(OVERLAY_MENU_TYPES.run_info)
	print("Toggled Run Info as Requested: " .. inspect(new_menu_state))

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = new_menu_state.msg}
	}
end

local function handle_toggleOptionsMenu(command)
	-- TODO: Refactor keybinding generation code to allow for actions while `G.OVERLAY_MENU` is true
	local new_menu_state = toggle_overlay_menu(OVERLAY_MENU_TYPES.options)
	print("Toggled Options Menu as Requested: " .. inspect(new_menu_state))

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = new_menu_state.msg}
	}
end

local function handle_toggleDeckView(command)
	local deck_view_mode = command.data.deckViewMode
	local valid_deck_view_modes = {peek=true, info=true}
	if not deck_view_mode or not valid_deck_view_modes[deck_view_mode] then
		-- print(inspect(deck_view_mode))
		-- print(inspect(deck_view_modes[deck_view_mode]))
		-- print(inspect(deck_view_modes))
		-- print(inspect(command.data))
		AMA.talon_rpc:send_response(command.uuid, {error = "Invalid Deck View Mode: " .. deck_view_mode})
		return
	end
	local menu_type = deck_view_mode == "peek" and OVERLAY_MENU_TYPES.deck_peek or OVERLAY_MENU_TYPES.deck_info

	local new_view_state = toggle_overlay_menu(menu_type)
	print("Toggled Deck View as Requested: " .. inspect(new_view_state))
	return {
		type = "no-action",
		reflection = {type = command.data.type, value = new_view_state.msg}
	}
end

local function handle_changeCycleOption(command)
	local direction = command.data.direction
	local result = step_through_option_cycle(direction)
	if not result.state then
		AMA.talon_rpc:send_response(command.uuid, {warning = result.msg})
		return
	end
	print("Cycled Option Menu via RPC Command: " .. inspect(result))

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = result.msg}
	}
end

local function handle_changeTab(command)
	local direction = command.data.direction
	local tab_number = command.data.tabNumber
	local result = change_overlay_menu_tab(direction, tab_number)
	if not result.state then
		AMA.talon_rpc:send_response(command.uuid, {warning = result.msg})
		return
	end

	print("Changed Tab via RPC Command: " .. inspect(result))

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = result.msg}
	}
end

local function handle_debugCounter(command)
	local cb_debug_counter = 42
	print("Received Debug Counter Command from Talon. Responding With Debug Counter: " .. cb_debug_counter)
	cb_debug_counter = cb_debug_counter + 1
	return {type = "debug-counter", value = cb_debug_counter}
end

local function handle_requestTimedOut(command)
	print("WARNING! Did not respond to Talon Request in time!!")
	return nil
end

local function handle_evalLua(command)
	if not ENABLE_ARBITRARY_EVAL then
		local msg = 'Unable to run arbitrary Lua code. ENABLE_ARBITRARY_EVAL is false.'
		AMA.talon_rpc:send_response(command.uuid, {error = msg})
		return
	end
	if runEvalCommand == nil then
		local msg = 'Unable to run arbitrary Lua code. runEvalCommand is nil.'
		AMA.talon_rpc:send_response(command.uuid, {error = msg})
		return
	end

	local lua_code = command.data.luaCode
	if not lua_code then
		-- We should never get here, as the RPC Command Handler should have already checked for this. But just in case...
		print("WARNING! Missing `luaCode` in RPC Command!")
		return
	end
	local result = runEvalCommand(lua_code)
	if not result then
		AMA.talon_rpc:send_response(command.uuid, {error = "WARNING! Error in Lua Code: " .. inspect(result)})
		return
	end
	return {
		type = "no-action",
		reflection = {type = command.data.type, value = result or "nil"}
	}
end

-- --- Keypress Action Handler ---

--- Helper function to handle simple actions that just trigger a keybind action
--- @param kb_action string The keybind action to trigger. This should be the name of the item in the `keybinds` table (optionally prefixed with "kb__")
--- @param key_name string? The name of the key to trigger the action for. Only used for logging & response purposes.
--- @return {state: boolean, msg: string} The result of the action. `state` is true if the key action was triggered. `msg` is a string message describing the result.
local function keyPressRPCCommand_triggerByKeyActionName(kb_action, key_name)

	--[[
	-- kb_action is a string that should be kb__{name_of_item_in_keybinds_table}
	-- First, validate that the string starts with "kb__"
	if not string.match(kb_action, "^kb__") then
		return nil
	end
	
	-- Next, remove the "kb__" prefix
	local keybind_name = string.sub(kb_action, 5)

	-- Next, check if the keybind exists
	if not keybinds[keybind_name] then
		return {activated=false, state=false, msg="Keybind Name Not Found: " .. keybind_name}
	end

	-- Finally, trigger the keybind
	print("Triggering Keybind: " .. keybind_name)
	keybinds[keybind_name]()
	-]]

	local key_name_msg = ""
	if key_name then
		key_name_msg = " (Key: `" .. key_name .. "`)"
	end

	-- Check if the key action name starts with "kb__", if it does, remove it
	local keybind_name = kb_action
	if string.match(keybind_name, "^kb__") then
		keybind_name = string.sub(keybind_name, 5)
	end

	-- if not keybinds[keybind_name] and not always_available_keybinds[keybind_name] then return {...} end

	-- Get the keybind function from the appropriate table
	local kb_action_func = keybinds[keybind_name] or always_available_keybinds[keybind_name]

	-- If the keybind function is not found, return an error
	if not kb_action_func then
		-- return {activated=false, state=false, msg="Key Action Name Not Found: " .. keybind_name}
		return {state=false, msg="Key Action Name Not Found: " .. keybind_name .. key_name_msg}
	end

	-- Finally, trigger the keybind
	print("Triggering Keybind: " .. keybind_name .. key_name_msg)
	kb_action_func()

	-- return {activated=true, state=true, msg=kb_action .. " Triggered"}
	return {state=true, msg=kb_action .. " Triggered" .. key_name_msg}
end


--- Helper function to trigger a keybind action by the bound key name
--- @param key_name string The name of the key to trigger the action for
--- @return {state: boolean, msg: string} The result of the action. `state` is true if the key action was triggered. `msg` is a string message describing the result.
local function keyPressRPCCommand_triggerByKeyName(key_name)
	key_name = string.lower(key_name)
	for action, key in pairs(mod.config.KeyBinds) do
		if string.lower(key) == key_name and type(action) == "string" then
			-- return keyPressRPCCommand_triggerByKeyActionName("kb__" .. action)
			return keyPressRPCCommand_triggerByKeyActionName(action, key_name)
		end
	end
	-- return {activated=false, state=false, msg="Key Not Found: " .. key_name}
	return {state=false, msg="Key Not Found: " .. key_name}
end

local function handle_keyPress(command)

	-- the RPC Command Handler should have already ensured that either keyName or keyAction are present
	-- local key_name = command.data.keyName
	-- local key_action = command.data.keyAction

	local outcome = nil
	if command.data.keyName then
		outcome = keyPressRPCCommand_triggerByKeyName(command.data.keyName)
	elseif command.data.keyAction then
		outcome = keyPressRPCCommand_triggerByKeyActionName(command.data.keyAction)
	end

	if not outcome or not outcome.state then
		return {warning = "`keyPress` Action Failed: " .. "\nCommand Data: " .. inspect(command.data)}
	end

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = command.data},
		result = outcome
	}
end


-- --- Card Sorting Action Handler ---

local function handle_sortCards(command)
	local sort_type = command.data.sortType
	if not sort_type then
		AMA.talon_rpc:send_response(command.uuid, {error = "Missing Required Key: `sortType`"})
		return
	end
	
	if sort_type == "suit" then
		sort_suit()
	elseif sort_type == "rank" then
		sort_rank()
	elseif sort_type == "toggle" then
		sort_toggle()
	else
		local valid = sort_custom(sort_type)
		if not valid then
			return {error = "Invalid Sort Type: " .. sort_type}
		end
	end

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = sort_type}
	}
end

-- --- Card Area Selection Action Handler ---

local function handle_selectCardArea(command)
	local card_area = command.data.cardArea
	if not type(card_area) == "string" then
		return {error = "Key `cardArea` Must Be a String"}
	end
	card_area = string.lower(card_area)

	local valid_areas = {

		"hand",           -- Hand of Playing Cards
		"jokers",         -- Currently owned jokers
		"consumeables",   -- Currently owned consumable cards
		"shop_jokers",    -- Jokers in the shop
		"shop_vouchers",  -- Vouchers in the shop
		"shop_booster",   -- Booster packs in the shop
		"pack_cards",     -- The second row of cards in Arcana & Spectral Packs		
	}
	if not utils.check_if_value_in_table(card_area, valid_areas) then
		return {error = "Invalid Card Area: " .. tostring(card_area)}
	end

	local result = AMA.card_sel:set_selected(card_area)
	if not result.state then
		return {warning = "Selecting Card Area `" .. tostring(card_area) .. "` Failed: " .. tostring(result.msg)}
	end

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = card_area}
	}
end

-- --- Generic Simple Action Handler ---

--- RPC Command Handler for simple actions
--- @param command TalonRPCCommand The command to handle
--- @return {type: string, reflection: {type: string, value: any}}? The result of the action. `type` is always "no-action". `reflection` contains the `type` of the command and the `value` of the action.
---         If a response was sent by this function, nil will be returned.
local function handle_voxlatroAction(command)
	local action = command.data.action
	local outcome = nil
	if type(action) ~= "string" then
		print("Error! Command: " .. inspect(command))
		return {error = "Key `action` Must Be a String"}
	end

	if action == "cashOut" then
		outcome = AMA.card_sel:use__cash_out()
	elseif action == "playHand" then
		outcome = AMA.card_sel:use__play_hand()
	elseif action == "selectBlind" then
		outcome = AMA.card_sel:use__select_blind()
	elseif action == "buyOrRedeemOrUse" then
		outcome = AMA.card_sel:use__buy_or_use_or_redeem()
	elseif action == "discard" then
		outcome = AMA.card_sel:discard__discard_cards()
	elseif action == "skip" then
		outcome = AMA.card_sel:discard__skip_or_next()
	else 
		return {error = "Unknown General Action: " .. tostring(action)}
	end

	if not outcome then
		return {warning = "Action Failed with unknown error (nil outcome): " .. tostring(action)}
	end

	if not outcome.state or not outcome.activated then
		return {warning = "General Action `" .. tostring(action) .. "` Failed: " .. tostring(outcome.msg)}
	end

	return {
		type = "no-action",
		reflection = {type = command.data.type, value = outcome}
	}
end

--- Enum for overlay menu states
--- @enum RequiredOverlayMenuState
local RequiredOverlayMenuState = {
    FORBID = "forbid",  -- Command cannot run when an overlay menu is open
    ALLOW = "allow",    -- Command can run regardless of overlay menu state
    REQUIRE = "require" -- Command requires an active overlay menu
}

--- @class CommandHandlers
--- @field handler function(command: TalonRPCCommand) The function to call when the command is received
--- @field data_keys table<string, boolean> The keys that are valid for the command. The Key is the key name, and the value is a boolean indicating if the key is required or not.
--- @field overlay_menu RequiredOverlayMenuState Default: `allow`. The type of overlay menu to open when the command is received. Valid values are "forbid", "allow", and "require". "forbid": The command cannot run while an overlay menu is open. "allow": The command can run regardless of the state of any overlay menu. "require": The command can only run when an overlay menu is open.
--- @field conditions function(command: TalonRPCCommand)? An optional function to call to determine if the command can be handled. If the function returns `true`, the command will be handled. Otherwise, it will be ignored.

local command_handlers = {
	-- Select/Deselect a single card
	selectCard = {
		handler = handle_selectCard,
		data_keys = {cardNumber = true},
		overlay_menu = RequiredOverlayMenuState.FORBID
	},

	-- Select/Deselect multiple cards
	selectMultipleCards = {
 		handler = handle_selectMultipleCards,
		data_keys = {cardNumbers = false, cardIDs = false},
		overlay_menu = RequiredOverlayMenuState.FORBID,
		conditions = function(command)
			-- Ensure at least one of `cardNumbers` or `cardIDs` is provided
			return command.data.cardNumbers or command.data.cardIDs
		end
	},

	-- Invert the current selection of cards
	invertCardSelection = {
		handler = handle_invertCardSelection,
		data_keys = {exceptCards = false},
		overlay_menu = RequiredOverlayMenuState.FORBID
	},

	-- Move a card to a new position, relative position, or swap with another card
    moveCard = {
        handler = handle_moveCard,
        data_keys = {cardNumber = false, movement = true, moveType = true, cardID = false},
        overlay_menu = RequiredOverlayMenuState.FORBID,
		conditions = function(command)
			-- Ensure at least one of `cardNumber` or `cardID` is provided
			return command.data.cardNumber or command.data.cardID
		end
    },
	selectCardArea = {
		handler = handle_selectCardArea,
		data_keys = {cardArea = true},
		overlay_menu = RequiredOverlayMenuState.FORBID
	},
	generalAction = {
		handler = handle_voxlatroAction,
		data_keys = {action = true},
		overlay_menu = RequiredOverlayMenuState.FORBID
	},
	keyPress = {
		handler = handle_keyPress,
		data_keys = {keyName = false, keyAction = false},
		overlay_menu = RequiredOverlayMenuState.FORBID,	-- As all the keypress actions currently can only run with the overlay menu closed, we will set this to FORBID.
														-- Be sure to update this if we add keypress actions that can run with the overlay menu open.
		conditions = function(command)
			-- Ensure at least one of `keyName` or `keyAction` is provided
			return command.data.keyName or command.data.keyAction
		end
	},
	sortCards = {
		handler = handle_sortCards,
		data_keys = {sortType = true},
		overlay_menu = RequiredOverlayMenuState.FORBID
	},
    toggleRunInfo = {
        handler = handle_toggleRunInfo,
        data_keys = {},  -- No required keys
        overlay_menu = RequiredOverlayMenuState.ALLOW  -- Can run regardless of overlay menu state
    },
    toggleOptionsMenu = {
        handler = handle_toggleOptionsMenu,
        data_keys = {},  -- No required keys
        overlay_menu = RequiredOverlayMenuState.ALLOW  -- Can run regardless of overlay menu state
    },
	openNewRunMenu = {
		handler = handle_newRunMenu,
		data_keys = {},  -- No required keys
		overlay_menu = RequiredOverlayMenuState.ALLOW  -- Closing runstat in some conditions can cause issues. Just have this RC allow for opening it, not closing it.
	},
	toggleDeckView = {
		handler = handle_toggleDeckView,
		data_keys = {deckViewMode = true},
		overlay_menu = RequiredOverlayMenuState.ALLOW  -- Can run regardless of overlay menu state
	},
    changeCycleOption = {
        handler = handle_changeCycleOption,
        data_keys = {direction = true},
        overlay_menu = RequiredOverlayMenuState.REQUIRE  -- Can run regardless of overlay menu state
    },
    changeTab = {
        handler = handle_changeTab,
        data_keys = {direction = false, tabNumber = false},
        overlay_menu = RequiredOverlayMenuState.ALLOW,  -- Can run regardless of overlay menu state
        conditions = function(command)
            -- Ensure at least one of `direction` or `tabNumber` is provided
            return command.data.direction or command.data.tabNumber
        end
    },
	menuGoBack = {
		handler = navigate_overlay_menu_back,
		data_keys = {},  -- No required keys
		-- TODO: This should only run if the overlay menu is open
		overlay_menu = RequiredOverlayMenuState.ALLOW  -- Can run regardless of overlay menu state
	},
    debugCounter = {
        handler = handle_debugCounter,
        data_keys = {},  -- No required keys
        overlay_menu = RequiredOverlayMenuState.ALLOW  -- Can run regardless of overlay menu state
    },
	evalLua = {
		handler = handle_evalLua,
		data_keys = {luaCode = true},
		overlay_menu = RequiredOverlayMenuState.ALLOW  -- Can run regardless of overlay menu state
	},
    requestTimedOut = {
        handler = handle_requestTimedOut,
        data_keys = {},  -- No required keys
        overlay_menu = RequiredOverlayMenuState.ALLOW  -- Can run regardless of overlay menu state
    }
}

-- Main function to handle the RPC command
local function run_talon_RPC_command()
	local command = AMA.talon_rpc:read_request()
	if not command then
		-- For now, no need to log this here. As it is currently logged in the Talon_RPC:read_request() function
		-- print("ERROR! Talon RPC Triggered but no data was received")
		return
	end

	-- Check for necessary `data` and `type` keys
	if not command.data or not command.data.type then
		local msg = not command.data and "Missing `data` key in RPC Command" or "Missing `data.type` key in RPC Command"
		AMA.talon_rpc:send_response(command.uuid, {error = msg})
		print("ERROR! " .. msg .. ": " .. inspect(command))
		return
	end

	local handler_entry = command_handlers[command.data.type]
	if not handler_entry then
		AMA.talon_rpc:send_response(command.uuid, {error = "Unknown Balatro RPC Command: " .. command.data.type})
		return
	end

	-- Check overlay menu condition
	if handler_entry.overlay_menu == RequiredOverlayMenuState.FORBID and G.OVERLAY_MENU then
		AMA.talon_rpc:send_response(command.uuid, {warning = "Cannot use `" .. command.data.type .. "` command while in Overlay Menu"})
		return
	elseif handler_entry.overlay_menu == RequiredOverlayMenuState.REQUIRE and not G.OVERLAY_MENU then
		AMA.talon_rpc:send_response(command.uuid, {warning = "Command `" .. command.data.type .. "` requires an active Overlay Menu"})
		return
	end

	-- print("Overlay Menu Status> handler_entry.overlay_menu: " .. handler_entry.overlay_menu .. " G.OVERLAY_MENU: " .. tostring(G.OVERLAY_MENU) .. " not G.OVERLAY_MENU: " .. tostring(not G.OVERLAY_MENU))

	-- Validate required keys in the command data
	for key, is_required in pairs(handler_entry.data_keys) do
		if is_required and not command.data[key] then
			AMA.talon_rpc:send_response(command.uuid, {error = "Missing required key `" .. key .. "` in RPC Command"})
			print("ERROR! Missing required key `" .. key .. "` in RPC Command: " .. inspect(command))  -- This print statement is redundant.
			return
		end
	end

	-- Check additional conditions (if provided)
	if handler_entry.conditions and not handler_entry.conditions(command) then
		AMA.talon_rpc:send_response(command.uuid, {warning = "Unable to run command. Conditions for command `" .. command.data.type .. "` failed"})
		return  -- Ignore the command if the condition function returns false
	end

	-- Call the handler function for the command
	local result = handler_entry.handler(command)
	-- TODO: I'm not sure that I love having the sentinal value of nil to indicate that the handler function has already sent a response.
	--       If we forget to return the result & don't send a responese in the handler function, it will just silently fail.
	--       We should probably refactor this to be more explicit. Maybe return an empty table to indicate that the handler function has already sent a response?
	if not result then
		-- If the handler function returns nil, it has already sent a response.
		return
	end

	-- if the results are an empty table, construct a default response
	if next(result) == nil then
		result = {type = "no-action", reflection = {type = command.data.type, value=command.data}, result="Default Canned Response"}
	end

	-- If the results are just raw payload, wrap them in the appropriate response format
	if result.payload == nil and result.error == nil and result.warning == nil then
		result = {payload = result}
	end

	-- Send the response to Talon
	AMA.talon_rpc:send_response(command.uuid, result)

end


-- Mod stuff

-- ----- Keybinds Registration -----

--- Table defining the default keybinds for the mod that are only available when no Overlay Menu is open
keybinds = {
	["Inc10"] = function()
		AMA.card_sel:add_offset(10)
	end,
	["Dec10"] = function()
		AMA.card_sel:add_offset(-10)
	end,
	["Discard"] = function() AMA.card_sel:context_discard_or_skip() end,
	["Use"] = function() AMA.card_sel:context_use() end,
	["BuyAndUse"] = function() AMA.card_sel:buy_and_use() end,
	["SelectHand"] = function()
		AMA.card_sel:set_selected("hand")
	end,
	["SelectJokers"] = function()
		AMA.card_sel:set_selected("jokers")
	end,
	["SelectConsumeables"] = function()
		AMA.card_sel:set_selected("consumeables")
	end,
	["SelectShopJokers"] = function()
		AMA.card_sel:set_selected("shop_jokers")
	end,
	["SelectShopVouchers"] = function()
		AMA.card_sel:set_selected("shop_vouchers")
	end,
	["SelectShopBooster"] = function()
		AMA.card_sel:set_selected("shop_booster")
	end,
	["SelectPackCards"] = function()
		AMA.card_sel:set_selected("pack_cards")
	end,
	["SelectCycleLeft"] = function()
		AMA.card_sel:cycle_selected(-1)
	end,
	["SelectCycleRight"] = function()
		AMA.card_sel:cycle_selected(1)
	end,
	["DeselectAll"] = function()
		AMA.card_sel:reset_vars()
	end,
	["Reroll"] = function() AMA.card_sel:reroll() end,
	["Sell"] = function() AMA.card_sel:sell() end,
	["SortSuit"] = sort_suit,
	["SortRank"] = sort_rank,
	["PeekDeck"] = peek_deck,
}

for i = 1, 10 do
	keybinds["Select" .. tostring(i % 10)] = function()
		AMA.card_sel:toggle_selected_0idx((i + 9) % 10)
	end
end

--- Table defining the default keybinds for the mod that are always available regardless of the state of `G.OVERLAY_MENU`
always_available_keybinds = {
	["TalonRPC"] = run_talon_RPC_command
}

--- Register a single keybinding with Steamodded
--- @param keybind_name string The name of the keybinding to register. Must match the key used in the Config GUI and config.lua
--- @param keybind_function function The function to call when the keybinding is triggered
--- @param block_by_overlay_menu boolean If true, the keybinds will be blocked if the overlay menu is open
--- @param disableable boolean If true, the keybinds will be disabled when the NonEssentialKeybindsDisabled setting is true. (ie. For RPC Trigger Keybind)
local function register_single_keybind(keybind_name, keybind_function, block_by_overlay_menu, disableable)
	local key = keybind_name
	local kb_action = keybind_function
	if mod.config.KeyBinds ~= nil and mod.config.KeyBinds[key] ~= false then
		SMODS.Keybind {
			key = "vilatro_binding_" .. key,
			key_pressed = mod.config.KeyBinds[key],
			action = function()
				if (not G.OVERLAY_MENU or not block_by_overlay_menu) and (not disableable or not mod.config.NonEssentialKeybindsDisabled) then
					print("Keybind Triggered: " .. key)
					kb_action()
				end
			end
		}
	end
end

--- Register multiple keybinds with Steamodded
--- @param keybinding_table table<string, function> The table of keybinds to register
--- @param block_by_overlay_menu boolean If true, the keybinds will be blocked if the overlay menu is open
--- @param disableable boolean If true, the keybinds will be disabled when the NonEssentialKeybindsDisabled setting is true. (ie. For RPC Trigger Keybind)
local function register_keybinds(keybinding_table, block_by_overlay_menu, disableable)
	for key, action in pairs(keybinding_table) do
		register_single_keybind(key, action, block_by_overlay_menu, disableable)
	end
end

if ENABLE_NON_RPC_KEYBINDS then
	register_keybinds(keybinds, true, true)
end
register_keybinds(always_available_keybinds, false, false)


if DEBUG_MODE then

	--    [SMODS.Keybind · Steamodded/smods Wiki](https://github.com/Steamodded/smods/wiki/SMODS.Keybind/)
	--    [KeyConstant - LOVE](https://love2d.org/wiki/KeyConstant)

	-- ----- Trigger Restart Keybinds -----
	-- Holding the `m` key is annoying, as it ends up spamming VSCode with mmmmmm.
	-- So I am adding a different keybind that does not need to be held to restart the game.

	local restart_keys = { "f10" }
	for i, kb_key in ipairs(restart_keys) do
		SMODS.Keybind {
			key_pressed = kb_key,
			action = function() SMODS.restart_game() end
		}
	end

	-- Debugging Misc Func
	-- SMODS.Keybind {
	-- 	key_pressed = "f3",
	-- 	action = function()
	-- 		print("Testing Random Code")
	-- 	end
	-- }

	-- ----- Debug Card Info Dump Keybinds -----

	-- Toggle Trigger / Off
	SMODS.Keybind {
		key_pressed = "f1",
		action = function()
			if info_dump_mode == "off" then
				AMA.card_sel.info_dump_mode = "trigger"
			else
				AMA.card_sel.info_dump_mode = "off"
			end
		end
	}

	-- Set to Trigger Once
	SMODS.Keybind {
		key_pressed = "f2",
		action = function()
			AMA.card_sel.info_dump_mode = "once"
		end
	}

end

-- ----- Load Config Tab UIs -----
local _, err = SMODS.load_file("core/config_tab_ui.lua")()
if err then
	print("Error loading library `config_tab_ui`: " .. err)
	error(err)
end
