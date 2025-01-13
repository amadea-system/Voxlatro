--
-- Talon File RPC Library
-- This library is used to send and receive data from Talon
-- It does this by writing and reading from a temporary file.

-- ---------- Imports ----------

--- @module 'json'
local json, err = SMODS.load_file("lib/json.lua")()
if err then
	print("Error loading library `json`: " .. err)
	error(err)
end

--- @module 'inspect'
local inspect, err = SMODS.load_file("lib/inspect.lua")()
if err then
	print("Error loading library `inspect`: " .. err)
	error(err)
end

-- ---------- Class ----------

-- Reminder: module name must be the same as the file name

---@alias rpcFileLocation
---| '"temp"' # Saves to the OS temporary directory.
---| '"save"' # Saves to the Love2D save directory.


---@class Talon_RPC
---@field location_type rpcFileLocation
---@field rpc_response_path string
---@field rpc_request_path string
---@field _verbose_log boolean
local Talon_RPC = { _version = "0.1.0" }

-- ---------- Methods ----------

-- ----- Initialization -----

--- Create a new instance of the Talon_RPC class
---@param location? rpcFileLocation The location that the RPC file should be saved to. Defaults to `"save"`.
---@param verbose? boolean If true, will enable verbose debug logging. Defaults to false.
---@return Talon_RPC
function Talon_RPC:new(location, verbose)
    local newObject = setmetatable({}, self)
    self.__index = self

    location = location or "save"
    if location ~= "temp" and location ~= "save" then
        error("Invalid RPC File Location: " .. location)
    end

    self._verbose_log = (verbose ~= nil and {verbose} or {false})[1]

    self.location_type = location
    self.rpc_response_path = self:retrieve_path('/response.json')
    self.rpc_request_path = self:retrieve_path('/request.json')

    return newObject
end

-- ----- Directory Functions -----

--- Get OS-appropriate temp directory
local function get_temp_dir()
	local system = love.system.getOS()
	if system == 'Windows' then
		return os.getenv('TEMP') or os.getenv('TMP') or ''
	else
		return '/tmp'
	end
end

--- Get OS-agnostic Love Save Directory
local function get_love_save_dir()
    return love.filesystem.getSaveDirectory()
end

--- Retrieves the path to the RPC file depending on the location type
--- @return string
function Talon_RPC:retrieve_path(file_name)
    if self.location_type == "temp" then
        return get_temp_dir() .. file_name
    elseif self.location_type == "save" then
        return get_love_save_dir() .. file_name
    else
        error("Invalid RPC File Location Type: " .. self.location_type)
    end
end

-- ----- File Functions -----

--- Write data to the RPC file
--- @param data string The data to write to the RPC file as a JSON string
--- @return boolean True if the data was successfully written to the RPC file, false otherwise
function Talon_RPC:write(data)
	local file = io.open(self.rpc_response_path, 'w')
	if not file then return false end

	-- Write the data
	local success = pcall(function()
		file:write(data)
        file:write('\n')  -- Trailing newline indicates the write is complete
	end)

	file:close()
	return success
end

--- Write data to the RPC file - Time Sensitive Encoding
--- @param data string The data to write to the RPC file as a JSON string
--- @return boolean True if the data was successfully written to the RPC file, false otherwise
--- @deprecated
function Talon_RPC:write_time_sensitive(data)
	-- local file = io.open(get_rpc_path(), 'w')
	local file = io.open(self.rpc_response_path, 'w')
	if not file then return false end
	
	-- Write timestamp and data
	local success = pcall(function()
		file:write(tostring(os.time()) .. '\n')
		file:write(data)
	end)
	
	file:close()
	return success
end

--- Read data from the RPC file
--- @return string|nil The data from the RPC file as a JSON string
function Talon_RPC:read()
	
	local file = io.open(self.rpc_request_path, 'r')
	if not file then return nil end
	
	-- Read data
	local data = file:read('*all')
	file:close()

    return data
end

--- Read data from the RPC file if it's new  - Only works with time sensitive encoded files
--- @return string|nil The data from the RPC file as a JSON string if it's new, nil otherwise
--- @deprecated
function Talon_RPC:read_time_sensitive()
	-- local file = io.open(self.rpc_file_path, 'r')
	local file = io.open(self.rpc_request_path, 'r')
	if not file then return nil end
	
	-- Read timestamp and data
	local timestamp = tonumber(file:read('*line'))
	local data = file:read('*all')
	file:close()
	
	-- Only return data if it's from the last 5 seconds
	if timestamp and os.time() - timestamp < 5 then
		return data
	end
	
	return nil
end

--- Clear the RPC file
--- @deprecated
function Talon_RPC:clear()

    local request_file = io.open(self.rpc_request_path, 'w')
    if request_file then
        request_file:close()
    end
    local response_file = io.open(self.rpc_response_path, 'w')
    if response_file then
        response_file:close()
    end
end

-- ----- RPC Functions -----

function Talon_RPC:read_request()
    local raw_json_str = self:read()
	if raw_json_str == nil then
		self:log_critical("ERROR! Talon RPC Triggered but no data was received")
		return nil
	end

	self:log("Got RPC Command from Talon! " .. raw_json_str)

	-- Decode JSON Command
	local command = json.decode(raw_json_str)
	if command == nil then
		self:log_critical("ERROR! Invalid Talon RPC Command. Unable to decode JSON from Raw JSON String: " .. raw_json_str)
		return nil
	end

	self:log("Decoded RPC Command: " .. inspect(command))

	
	-- Handle Command
	-- Command Format:
	-- {
	-- 	  uuid: string,
	-- 	  data = {
	-- 		        type: string,
	-- 		        value: any
	-- 	  },
	--    waitForFinish: boolean,
	--    returnCommandOutput: boolean
	-- }

	if command.uuid == nil then
		self:log_critical("ERROR! No UUID in Talon RPC Command. Unable to handle malformed command: " .. inspect(command))
		return nil
	end

    return command
end

--- @class TalonRPCParams
--- @field payload? any The return value for the response, if any.
--- @field error? string If the command failed, this is the error message to include in the response.
--- @field warning? string If there was a warning, a warning message to include in the response, if any.

--- Sends a response encoded as JSON to Talon via the talon_rpc library
---@param uuid string The UUID of the command that was sent. This will be encoded into the response.
---@param params TalonRPCParams The table containing the parameters for the response. Valid keys are:
---  - `payload`: The return value for the response, if any.
---  - `error`: If the command failed, this is the error message to include in the response.
---  - `warning`: If there was a warning, a warning message to include in the response, if any.
function Talon_RPC:send_response(uuid, params)
	local payload = params.payload
	local error = params.error
	local warning = params.warning

	-- Response Format:
	-- {
	-- 	  uuid: string,           # Must match the UUID of the command that was sent
	-- 	  error: string | None,   # If the command failed, this will contain the error message. This will cause Talon to throw an error
	-- 	  warnings: list[string], # If the command failed, this will contain the warning message. Talon will print the warning message to the console
	-- 	  returnValue: any,       # [Optional] If we need to return a value, this will contain it
	-- }

	local full_response = {
		uuid = uuid,
		-- error = "null",  -- We have to set this to `"null"` instead of `nil` because it will be stripped out by the JSON encoder otherwise
		error = json.null,  -- We have to set this to `json.null` instead of `nil` because it will be stripped out by the JSON encoder otherwise
		warnings = {},
	}
	if payload ~= nil then
		full_response.returnValue = payload
	end
	if error ~= nil then
		self:log_critical("RPC ERROR! " .. error)
		full_response.error = error
	end

	if warning ~= nil then
		self:log_critical("RPC WARNING! " .. warning)
		full_response.warnings = { warning }
	end

	self:log("Constructed Response: " .. inspect(full_response))

	local encoded_response = json.encode(full_response)
	self:log("Encoded Response: " .. encoded_response)
	
	if self:write(encoded_response) then
		self:log("Response Successfully Sent via RPC")
        return true
	end
    return false
end

-- ----- Logging -----

function Talon_RPC:log(message)
    if self._verbose_log then
        print(message)
    end
end

function Talon_RPC:log_critical(message)
    print(message)
end

return Talon_RPC