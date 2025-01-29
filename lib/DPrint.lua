-- Print debugging Util
-- Allows for easy configuration of debug prints
-- Such as:
--   - Printing to the console, file, or both
--   - Disabling debug prints

---@class DPrint
---@field private _enabled boolean
---@field private _print_to_console boolean
---@field private _print_to_file boolean
---@field private _file_path string
local DPrint = { _version = "0.1.0" }

-- ---------- Methods ----------

--- Create a new instance of the DPrint class
--- @param enabled boolean? Whether or not to enable debug prints. Defaults to `true`.
--- @param print_to_console boolean? Whether or not to print to the console. Defaults to `true`.
--- @param print_to_file boolean? Whether or not to print to a file. Defaults to `false`.
--- @param file_name string? The name of the file to print to. Defaults to `"debug.log"`. If `print_to_file` is `false`, this parameter is ignored.
--- @param folder_name string? Relative folder path to save log file to. Defaults to none. Files always saved relative to the Save Directory.
--- @param add_datetime boolean? Whether or not to add the current date and time to the file name. Defaults to `false`.
--- @return DPrint
function DPrint:new(enabled, print_to_console, print_to_file, file_name, folder_name, add_datetime)
    local newObject = setmetatable({}, self)
    self.__index = self

    print("Initializing DPrint... enabled: " .. tostring(enabled) .. ", print_to_console: " .. tostring(print_to_console) .. ", print_to_file: " .. tostring(print_to_file) .. ", file_name: " .. tostring(file_name) .. ", folder_name: " .. tostring(folder_name) .. ", add_datetime: " .. tostring(add_datetime))
    -- self._enabled = enabled == nil and true or enabled
    -- self._print_to_console = print_to_console == nil and true or print_to_console
    -- self._print_to_file = print_to_file == nil and false or print_to_file

    -- self._enabled = enabled ~= nil and enabled or true
    -- self._print_to_console = print_to_console ~= nil and print_to_console or true
    -- self._print_to_file = print_to_file ~= nil and print_to_file or false

    if enabled == nil then
        enabled = true
    end
    if print_to_console == nil then
        print_to_console = true
    end
    if print_to_file == nil then
        print_to_file = false
    end

    self._enabled = enabled
    self._print_to_console = print_to_console
    self._print_to_file = print_to_file
    
    local _file_name = file_name or "debug.log"
    local folder_name = folder_name or ""
    

    if not self._print_to_file and not self._print_to_console then
        self._enabled = false
    end

    if add_datetime then
        -- First split the file name into its parts
        local file_name_parts = _file_name:split(".")

        -- Then add the current date and time to the file name
        -- local date_time_str = os.date("%Y-%m-%d_%H-%M-%S")
        local date = os.date("%Y-%m-%d")
        local time = os.date("%H-%M-%S")

        -- If there's multiple extensions, Join them back together
        local file_extensions = table.concat(file_name_parts, ".", 2)

        -- Construct the new file name
        _file_name = file_name_parts[1] .. "_" .. date .. "_" .. time .. "." .. file_extensions
    end

    -- Normalize the folder name (strip leading/trailing slashes)
    folder_name = folder_name:match("^/*(.-)/*$") or ""

    -- Set the file path for logging
    if folder_name ~= "" then
        self._file_path = love.filesystem.getSaveDirectory() .. "/" .. folder_name .. "/" .. _file_name
    else
        self._file_path = love.filesystem.getSaveDirectory() .. "/" .. _file_name
    end

    print("DPrint Initialized! Enabled: " .. tostring(self._enabled) .. ", print_to_console: " .. tostring(self._print_to_console) .. ", print_to_file: " .. tostring(self._print_to_file) .. ", file_path: " .. tostring(self._file_path))
    return newObject
end

---@class DPrint.InitOptions
---@field enabled boolean? Whether or not to enable debug prints. Defaults to `true`.
---@field log_console boolean? Whether or not to print to the console. Defaults to `true`.
---@field log_file boolean? Whether or not to print to a file. Defaults to `false`.
---@field file_name string? The name of the file to print to. Defaults to `"debug.log"`. If `log_file` is `false`, this parameter is ignored.
---@field folder_name string? Relative folder path to save log file to. Defaults to none. Files always saved relative to Save Directory.
---@field add_datetime boolean? Whether or not to add the current date and time to the file name. Defaults to `false`.

--- Create a new instance of the DPrint class, with named parameters (Same as `new` but with named parameters)
--- @param options DPrint.InitOptions The options to pass to the `new` method.
--- @return DPrint
function DPrint:n(options)
    print("Creating DPrint with options: " .. convert_table_to_string(options))
    return self:new(options.enabled, options.log_console, options.log_file, options.file_name, options.folder_name, options.add_datetime)
end

--- Log a message to the appropriate destinations
--- @param message string The message to log
function DPrint:log(message)
    if not self._enabled then
        return
    end

    if self._print_to_console then
        print("<dpL> " .. message)
    end
    if self._print_to_file then
        self:_write_log_to_disk(message)
    end
end

--- Forces a log to be printed to the console. The message will be log to disk only if `log_file` is `true`.
--- Does not override the `enabled` parameter.
--- @param message string The message to log
function DPrint:alert(message)
    if not self._enabled then
        return
    end

    print("<dpA> " .. message)

    if self._print_to_file then
        self:_write_log_to_disk(message)
    end
end


--- Writes a message to the log file on disk
--- @param message string The message to write to the log file
--- @private
function DPrint:_write_log_to_disk(message)

    -- Open file in append mode (`a`)
    local file = io.open(self._file_path, "a")
    if not file then
        print("<dpE> ERROR! Unable to open file for writing: " .. self._file_path)
        return false
    end

    local success = pcall(function()
        file:write(message .. "\n")
    end)
	
	file:close()
    if not success then
        print("<dpE> ERROR! Unable to write to file: " .. self._file_path)
    end

    return success

end


--- Converts a table to a string. Only goes 1 level deep.
--- @param table table The table to convert to a string.
--- @return string The converted table as a string.
function convert_table_to_string(table)
    local result = ""
    for key, value in pairs(table) do
        result = result .. key .. ": " .. tostring(value) .. ", "
        -- result = result .. key .. ": " .. tostring(value) .. "\n"
    end
    return result
end


-- Helpers

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

return DPrint
