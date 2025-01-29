
-- Primary Global Namespace
if not AMA then AMA = {} end

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
	print("DebugPlus API is not available")
end

local _, err = SMODS.load_file("core/card_selection.lua")()
if err then
	print("Error loading library `card_selection`: " .. err)
	error(err)
end

-- ---------- Constants ----------
local ENABLE_ARBITRARY_EVAL = false  -- Only enable this if you know what you are doing. It is a security risk.

-- ---------- Local Variables ----------

local mod = SMODS.current_mod

-- ---------- Local Functions ----------

local function sort_suit()
	if not G.hand then return end
	G.FUNCS.sort_hand_suit()
end

local function sort_rank()
	if not G.hand then return end
	G.FUNCS.sort_hand_value()
end

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
	

-- Talon Functions

-- ::::: RPC Command Helpers :::::

---@enum overlay_menu_types
local OVERLAY_MENU_TYPES = {
	options = 1,
	run_info = 2,
}

local _overlay_menu_functions_tbl = {
	[OVERLAY_MENU_TYPES.options] = G.FUNCS.options,
	[OVERLAY_MENU_TYPES.run_info] = G.FUNCS.run_info,
}

--- Helper function to toggle the different overlay menus
--- @param menu_type overlay_menu_types The type of menu to toggle
--- @param abort_on__no_esc? boolean If true, will abort if `G.OVERLAY_MENU.config.no_esc` is true. Default: true
--- @return {state: boolean?, msg: string} table The return value of the function. State: True=Opened, False=Closed, nil=menu could not be toggled (E.G., If no_esc, or other issues)
local function toggle_overlay_menu(menu_type, abort_on__no_esc)

	if abort_on__no_esc == nil then abort_on__no_esc = true end

	-- TODO: Write docs on `G.OVERLAY_MENU.config.no_esc` (See: `engine/controller.lua:#L795`)
	if abort_on__no_esc and G.OVERLAY_MENU and G.OVERLAY_MENU.config.no_esc then
		print("Aborting toggle_overlay_menu(" .. menu_type .. ") because G.OVERLAY_MENU.config.no_esc is true")
		return {state=nil, msg="Unable to Toggle. no_esc is true"}
	end

	if G.OVERLAY_MENU then
		G.FUNCS:exit_overlay_menu()
		return {state=false, msg="Menu Closed"}
	end

	_overlay_menu_functions_tbl[menu_type]({})
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
		-- I'm not sure if this will ever happen, but it's here just in case. I'm not sure what would cause this.
		return {state=false, msg="Tab UI Element Not Focused or something... (tab_shoulders.config.focus_args.type = " .. tab_shoulders.config.focus_args.type .. ")"}
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

local function handle_selectCard(command)

		local index = command.data.cardNumber or 1
		-- TODO: Refactor `toggle_selected()` to use 1-based indexing
	AMA.Amilatro:toggle_selected(index - 1)
		print("Toggled Selected as Requested: " .. index)

	return {
			type = "no-action",
		reflection = {type = command.data.type, value = index}
		}
end
	
local function handle_selectMultipleCards(command)
		-- Expected Command Data Format:
		-- cardNumbers: list of 1-based indices of cards to select

		local card_numbers = command.data.cardNumbers or {}
		for i, card_number in ipairs(card_numbers) do
			-- TODO: Refactor `toggle_selected()` to use 1-based indexing
		AMA.Amilatro:toggle_selected(card_number - 1)
		end
		print("Toggled Selected as Requested: " .. inspect(card_numbers))

	return {
			type = "no-action",
		reflection = {type = command.data.type, value = card_numbers}
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
    selectCard = {
        handler = handle_selectCard,
        data_keys = {cardNumber = true},
        overlay_menu = RequiredOverlayMenuState.FORBID
    },
    selectMultipleCards = {
        handler = handle_selectMultipleCards,
        data_keys = {cardNumbers = true},
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
	-- TODO: Be able to handle more than just payload. Handle any Warnings/Errors as well.
    local payload = handler_entry.handler(command)
    if payload then
        AMA.talon_rpc:send_response(command.uuid, {payload = payload})
    end

end


-- Mod stuff


--- Table defining the default keybinds for the mod that are only available when no Overlay Menu is open
local keybinds = {
	["Inc10"] = function()
		AMA.Amilatro:add_offset(10) -- 
	end,
	["Dec10"] = function()
		AMA.Amilatro:add_offset(-10) --
	end,
	["Discard"] = function() AMA.Amilatro:discard() end,
	["Use"] = function() AMA.Amilatro:context_use() end,
	["BuyAndUse"] = function() AMA.Amilatro:buy_and_use() end,
	["SelectHand"] = function()
		AMA.Amilatro:set_selected("hand")
	end,
	["SelectJokers"] = function()
		AMA.Amilatro:set_selected("jokers")
	end,
	["SelectConsumeables"] = function()
		AMA.Amilatro:set_selected("consumeables")
	end,
	["SelectShopJokers"] = function()
		AMA.Amilatro:set_selected("shop_jokers")
	end,
	["SelectShopVouchers"] = function()
		AMA.Amilatro:set_selected("shop_vouchers")
	end,
	["SelectShopBooster"] = function()
		AMA.Amilatro:set_selected("shop_booster")
	end,
	["SelectPackCards"] = function()
		AMA.Amilatro:set_selected("pack_cards")
	end,
	["SelectCycleLeft"] = function()
		AMA.Amilatro:cycle_selected(-1)
	end,
	["SelectCycleRight"] = function()
		AMA.Amilatro:cycle_selected(1)
	end,
	["DeselectAll"] = function()
		AMA.Amilatro:reset_vars()
	end,
	["Reroll"] = function() AMA.Amilatro:reroll() end,
	["Sell"] = function() AMA.Amilatro:sell() end,
	["SortSuit"] = sort_suit,
	["SortRank"] = sort_rank,
	["PeekDeck"] = peek_deck,
}

for i = 1, 10 do
	keybinds["Select" .. tostring(i % 10)] = function()
		AMA.Amilatro:toggle_selected((i + 9) % 10)
	end
end

--- Table defining the default keybinds for the mod that are always available regardless of the state of `G.OVERLAY_MENU`
local always_available_keybinds = {
	["TalonRPC"] = run_talon_RPC_command
}


local function register_keybinds(keybinding_table, block_by_overlay_menu)
	for key, action in pairs(keybinding_table) do
	if mod.config[key] ~= false then
		SMODS.Keybind {
			key = "vilatro_binding_" .. key,
			key_pressed = mod.config[key],
			action = function()
					if not G.OVERLAY_MENU or not block_by_overlay_menu then action() end
			end
		}
		end
	end
end

register_keybinds(keybinds, true)
register_keybinds(always_available_keybinds, false)



-- UI stuff

-- from https://gist.github.com/GabrielBdeC/b055af60707115cbc954b0751d87ec23
function string:split(delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(self, delimiter, from, true)
    while delim_from do
        if (delim_from ~= 1) then
            table.insert(result, string.sub(self, from, delim_from-1))
        end
        from = delim_to + 1
        delim_from, delim_to = string.find(self, delimiter, from, true)
    end
    if (from <= #self) then table.insert(result, string.sub(self, from)) end
    return result
end

local function create_keybind_button(args)
	args.align = args.align or "cm"
	args.active_colour = args.active_colour or G.C.GREY
	args.w = args.w or 0.8
	args.h = args.h or 0.8
	args.scale = args.scale or 1
	args.label_scale = args.label_scale or 0.5
	
	local children = {}
	
	if args.label then
		children[#children+1] = {
			n = G.UIT.C,
			config = { align = "cm", colour = G.C.CLEAR },
			nodes = {
				{
					n = G.UIT.T,
					config = {
						text = localize(args.label),
						scale = args.label_scale,
						colour = G.C.UI.TEXT_LIGHT,
						shadow = true
					}
				},
				{
					n = G.UIT.B,
					config = { w = 0.1, h = 0.1, colour = G.C.CLEAR }
				}
			}
		}
	end
	
	children[#children+1] = {
		n = G.UIT.C,
		config = {
			align = "cm", colour = args.active_colour,
			hover = true, r = 0.1, padding = 0.1,
			minw = args.w, minh = args.h,
			button = 'bind_key',
			ref_table = args.ref_table,
			ref_value = args.ref_value,
		},
		nodes = {{
			n = G.UIT.T,
			config = {
				text = args.ref_table[args.ref_value] or localize("vi_keybind_unset"),
				scale = 0.4,
				colour = G.C.UI.TEXT_LIGHT,
				shadow = false,
			}
		}}
	}
	
	return {
		n = G.UIT.C,
		config = {
			align = args.align,
			padding = 0.1,
			r = 0.1,
			colour = G.C.CLEAR,
			focus_args = { funnel_from = true },
			tooltip = args.info and {text = localize(args.info):split("\n")}
		},
		nodes = children
	}
end

function G.FUNCS.bind_key(e)
	e.children[1].config.text = "..."
	e.children[1].UIBox:recalculate()
	
	G.keybind_callback = function(key)
		if not e then return end
		if not e.children then return end
		if not e.children[1] then return end
		if not e.children[1].config then return end
		
		local bound_key = key
		if bound_key == "escape" then
			bound_key = false
		end
		
		e.config.ref_table[e.config.ref_value] = bound_key
		e.children[1].config.text = bound_key or localize("vi_keybind_unset")
		e.children[1].UIBox:recalculate()
		
	end
end

mod.config_tab = function()
	return {
		n=G.UIT.ROOT,
		config = {align = "cm", padding = 0.05, r = 0.1, minw=8, minh=6, colour = G.C.BLACK}, 
		nodes = {
			{
				n = G.UIT.R,
				config = {
					align = "cm", colour = G.C.UI.CLEAR, padding = 0
				},
				nodes = {{
					n = G.UIT.C,
					config = {
						align = "cm", colour = G.C.RED, r = 0.1, padding = 0.1
					},
					nodes = {{
						n = G.UIT.T,
						config = {
							text = localize("vi_keybind_restart"),
							colour = G.C.UI.TEXT_LIGHT,
							scale = 0.6,
							padding = 0.05,
							shadow = false
						}
					}}
				}}
			},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select1",
					label = "vi_keybind_sel",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select2",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select3",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select4",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select5",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select6",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select7",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select8",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select9",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Select0",
					info = "vi_keybind_sel_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Dec10",
					label = "vi_keybind_dec10",
					info = "vi_keybind_dec10_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Inc10",
					label = "vi_keybind_inc10",
					info = "vi_keybind_inc10_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "DeselectAll",
					label = "vi_keybind_desel",
					info = "vi_keybind_desel_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SelectHand",
					label = "vi_keybind_sel_hand",
					info = "vi_keybind_sel_hand_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SelectJokers",
					label = "vi_keybind_sel_jokers",
					info = "vi_keybind_sel_jokers_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SelectConsumeables",
					label = "vi_keybind_sel_consumables",
					info = "vi_keybind_sel_consumables_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SelectPackCards",
					label = "vi_keybind_sel_pack_cards",
					info = "vi_keybind_sel_pack_cards_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SelectShopJokers",
					label = "vi_keybind_sel_shop",
					info = "vi_keybind_sel_shop_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SelectShopVouchers",
					info = "vi_keybind_sel_shop_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SelectShopBooster",
					info = "vi_keybind_sel_shop_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SelectCycleLeft",
					label = "vi_keybind_sel_left",
					info = "vi_keybind_sel_left_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SelectCycleRight",
					label = "vi_keybind_sel_right",
					info = "vi_keybind_sel_right_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Discard",
					label = "vi_keybind_discard",
					info = "vi_keybind_discard_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Use",
					label = "vi_keybind_use",
					info = "vi_keybind_use_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "BuyAndUse",
					label = "vi_keybind_buy_and_use",
					info = "vi_keybind_buy_and_use_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "PeekDeck",
					label = "vi_keybind_peek_deck",
					info = "vi_keybind_peek_deck_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Reroll",
					label = "vi_keybind_reroll",
					info = "vi_keybind_reroll_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "Sell",
					label = "vi_keybind_sell",
					info = "vi_keybind_sell_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SortSuit",
					label = "vi_keybind_sort_suit",
					info = "vi_keybind_sort_suit_desc"
				},
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "SortRank",
					label = "vi_keybind_sort_rank",
					info = "vi_keybind_sort_rank_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config,
					ref_value = "TalonRPC",
					label = "vi_keybind_talon_rpc",
					info = "vi_keybind_talon_rpc_desc"
				},
				
			}},
		}
	}
end