

-- Primary Global Namespace
if not AMA then AMA = {} end

-- ---------- Core Imports ----------

--- @module 'inspect'
local inspect, err = SMODS.load_file("lib/inspect.lua")()
if err then
	print("Error loading library `inspect`: " .. err)
	error(err)
end


--- @module 'utils'
local utils, err = SMODS.load_file("core/utils.lua")()
if err then
	print("Error loading library `utils`: " .. err)
	error(err)
end


-------------------- Local Variables ---------------------
local mod = SMODS.current_mod


-------------------- Helper Functions ---------------------
---
----- UI stuff

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
	--TODO: Refactor `args.info` -> `args.tooltip` to match `create_enhanced_toggle()`
	
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


--- @class ReferenceValueTable
--- @field ref_table table The reference table to extract a value from.
--- @field ref_value string The key to use on the reference table to extract the value from.

--- @class ToolTipTable
--- @field text table<string|ReferenceValueTable> The text to display in the tooltip. Can be a table of strings &/or reference value tables.
--- @field title string? The title of the tooltip. Default: `nil`
--- @field filler {func: function, args: table}? NEEDS VERIFICATION: A function to call to fill the tooltip. Default: `nil` (See: UI_definitions.lua::create_UIBox_hand_tip())

--- @class EnhancedToggleArgs
--- @field active_colour table? The colour to use when the toggle is active. Default: `G.C.RED`
--- @field inactive_colour table? The colour to use when the toggle is inactive. Default: `G.C.BLACK`
--- @field w number? The width of the toggle. Default: `3`
--- @field h number? The height of the toggle. Default: `0.5`
--- @field scale number? The scale of the toggle. Default: `1`
--- @field label string The label to use for the toggle. Default: `TEST?`
--- @field label_scale number? The scale of the label. Default: `0.4`
--- @field ref_table table? The reference table to use for the toggle. Default: `{}`
--- @field ref_value string? The corresponding key in the reference table.
--- @field info table<string>? If provided, this info will be displayed underneath the toggle. Default: `nil`
--- @field tooltip ToolTipTable? The tooltip to use for the toggle. Default: `nil`
--- @field tooltip_text string? Alias for args={tooltip={text='foobar'}}. Only used if args.tooltip is not set. Default: `nil`
--- @field callback function? An Optional function to call when the toggle is clicked. Default: `nil`
--- @field col boolean? <VERIFY TYPE & DESCRIPTION> If true, the toggle will be a column, otherwise row. Default: `false`

--- Equivalent to UI_definitions.lua::create_toggle() but with a few extra features such as tooltip support.
--- @param args EnhancedToggleArgs? The arguments to use for the toggle.
--- @return table The toggle UI element.
local function create_enhanced_toggle(args)

	-- ----- Arg handling -----

	-- --- Arg handling from UI_definitions.lua::create_toggle() ---
	args = args or {}
	args.active_colour = args.active_colour or G.C.RED
	args.inactive_colour = args.inactive_colour or G.C.BLACK
	args.w = args.w or 3
	args.h = args.h or 0.5
	args.scale = args.scale or 1
	args.label = args.label or 'ERROR!? TOGGLE MISSING LABEL'
	args.label_scale = args.label_scale or 0.4
	args.ref_table = args.ref_table or {}
	args.ref_value = args.ref_value or 'test'
	
	-- --- Arg handling from create_keybind_button() ---
	-- args.align = args.align or "cm"
	-- args.active_colour = args.active_colour or G.C.GREY
	-- args.w = args.w or 0.8
	-- args.h = args.h or 0.8
	-- args.scale = args.scale or 1
	-- args.label_scale = args.label_scale or 0.5

	-- --- Voxlatro Additional Arg handling ---
	if not args.tooltip and args.tooltip_text then args.tooltip = {text = args.tooltip_text} end

	-- ----- UI Creation -----

	local toggle_ui = create_toggle(args)
	
	-- Add in the ToolTips to the toggle_ui config
	toggle_ui.config.tooltip = args.tooltip

	-- Return the toggle_ui
	return toggle_ui
end


-------------------- Config Tabs Creators ---------------------
local function general_config_UItab()

	return {
		n=G.UIT.ROOT,
		config = {align = "cm", padding = 0.05, r = 0.1, minw=8, minh=6, colour = G.C.BLACK}, 
		nodes = {
			
			create_enhanced_toggle {
				ref_table = mod.config, 
				ref_value = 'NonEssentialKeybindsDisabled',
				label = localize('vi_config_disable_non_essential_keybinds'),
				-- tooltip = {text=localize('vi_config_disable_non_essential_keybinds_info')},
				info = localize('vi_config_disable_non_essential_keybinds_info'),
			},
		},
	}
end

local function keybinds_config_UITab()
	-- TODO: Dynamically generate this from the config file?
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
					ref_table = mod.config.KeyBinds,
					ref_value = "Select1",
					label = "vi_keybind_sel",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Select2",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Select3",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Select4",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Select5",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Select6",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Select7",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Select8",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Select9",
					info = "vi_keybind_sel_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Select0",
					info = "vi_keybind_sel_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Dec10",
					label = "vi_keybind_dec10",
					info = "vi_keybind_dec10_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Inc10",
					label = "vi_keybind_inc10",
					info = "vi_keybind_inc10_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "DeselectAll",
					label = "vi_keybind_desel",
					info = "vi_keybind_desel_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SelectHand",
					label = "vi_keybind_sel_hand",
					info = "vi_keybind_sel_hand_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SelectJokers",
					label = "vi_keybind_sel_jokers",
					info = "vi_keybind_sel_jokers_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SelectConsumeables",
					label = "vi_keybind_sel_consumables",
					info = "vi_keybind_sel_consumables_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SelectPackCards",
					label = "vi_keybind_sel_pack_cards",
					info = "vi_keybind_sel_pack_cards_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SelectShopJokers",
					label = "vi_keybind_sel_shop",
					info = "vi_keybind_sel_shop_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SelectShopVouchers",
					info = "vi_keybind_sel_shop_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SelectShopBooster",
					info = "vi_keybind_sel_shop_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SelectCycleLeft",
					label = "vi_keybind_sel_left",
					info = "vi_keybind_sel_left_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SelectCycleRight",
					label = "vi_keybind_sel_right",
					info = "vi_keybind_sel_right_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Discard",
					label = "vi_keybind_discard",
					info = "vi_keybind_discard_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Use",
					label = "vi_keybind_use",
					info = "vi_keybind_use_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "BuyAndUse",
					label = "vi_keybind_buy_and_use",
					info = "vi_keybind_buy_and_use_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "PeekDeck",
					label = "vi_keybind_peek_deck",
					info = "vi_keybind_peek_deck_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Reroll",
					label = "vi_keybind_reroll",
					info = "vi_keybind_reroll_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "Sell",
					label = "vi_keybind_sell",
					info = "vi_keybind_sell_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SortSuit",
					label = "vi_keybind_sort_suit",
					info = "vi_keybind_sort_suit_desc"
				},
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "SortRank",
					label = "vi_keybind_sort_rank",
					info = "vi_keybind_sort_rank_desc"
				},
			}},
			{n=G.UIT.R, config={align = "cm", colour = G.C.CLEAR}, nodes={
				create_keybind_button {
					ref_table = mod.config.KeyBinds,
					ref_value = "TalonRPC",
					label = "vi_keybind_talon_rpc",
					info = "vi_keybind_talon_rpc_desc"
				},
			}},
		}
	}
end
-------------------- Setup General Config Tab & Extra Tabs ---------------------


-- mod.config_tab = keybinds_config_UITab
mod.config_tab = general_config_UItab
mod.extra_tabs = function()
	return {
		-- {label = 'General Configs', tab_definition_function = general_config_UItab},
		{
			label = 'Keybinds',
			tab_definition_function = keybinds_config_UITab,
		},
	}
end

