
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

--- Negatively OR positively index a table. (Table must start at 1)
--- @param a_table table The table to index
--- @param index number The index to index
--- @return any The value at the indexed position
function utils.get_at(a_table, index)
    if index < 1 then
        return a_table[#a_table + 1 + index]
    else
        return a_table[index]
    end
end

--- Checks if a table index is valid. Allows for negative indexing. (Table must start at 1)
function utils.is_table_idx_valid(a_table, index)
    if index == 0 then
        return false
    end

    if index < 0 then
        return #a_table + 1 + index >= 1
    else
        return index <= #a_table
    end
end

return utils