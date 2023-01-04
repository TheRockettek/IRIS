local errors = require("current.core.errors")

local fileVersion = "1"

local function Encode(iris)
    local file = {
        version = fileVersion,
        data = {
            inventories = iris.irisData.inventories
        }
    }

    local jsonEncode = textutils.serializeJSON(file)

    assert(type(jsonEncode) == "string")

    return jsonEncode, nil
end

local function Decode(file)
    if file == "" or file == nil then
        return nil, errors.ErrFailedToDecode
    end

    local jsonDecode = textutils.unserializeJSON(file)
    if jsonDecode == nil then
        return nil, errors.ErrFailedToJSONDecode
    end

    assert(type(jsonDecode) == "table")

    return jsonDecode, nil
end

return {
    Encode = Encode,
    Decode = Decode
}
