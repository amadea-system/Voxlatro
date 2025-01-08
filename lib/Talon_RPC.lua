--
-- Talon File RPC Library
-- This library is used to send and receive data from Talon
-- It does this by writing and reading from a temporary file.

-- Reminder: module name must be the same as the file name

---@alias rpcFileLocation
---| '"temp"' # Saves to the OS temporary directory.
---| '"save"' # Saves to the Love2D save directory.


---@class Talon_RPC
---@field location_type rpcFileLocation
---@field rpc_response_path string
---@field rpc_request_path string
local Talon_RPC = { _version = "0.1.0" }

-- ---------- Methods ----------

--- Create a new instance of the Talon_RPC class
---@param location? rpcFileLocation The location that the RPC file should be saved to. Defaults to `"save"`.
---@return Talon_RPC
function Talon_RPC:new(location)
    local newObject = setmetatable({}, self)
    self.__index = self

    location = location or "save"
    if location ~= "temp" and location ~= "save" then
        error("Invalid RPC File Location: " .. location)
    end

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

return Talon_RPC