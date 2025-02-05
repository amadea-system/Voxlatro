
local utils = {}


--- Checks if a value is in a table
--- @param value any The value to check if it is in the table
--- @param a_table table The table to check if the value is in
--- @return boolean True if the value is in the table, false otherwise
function utils.check_if_value_in_table(value, a_table)
    for _, v in ipairs(a_table) do
        if v == value then return true end
    end
    return false
end

--- Checks if a table contains a key
--- @param key any The key to check if it is in the table
--- @param a_table table The table to check if the key is in
--- @return boolean True if the key is in the table, false otherwise
function utils.check_if_key_in_table(key, a_table)
    for k, _ in pairs(a_table) do
        if k == key then return true end
    end
    return false
end

return utils