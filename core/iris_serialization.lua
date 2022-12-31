local json = require("libs.json")
local errors = require("core.errors")

local fileVersion = "1"

local function Encode(iris)
    local file = {
        version = fileVersion,
        data = {
            iris = {
                lastScannedAt = iris.irisData.iris.lastScannedAt
            },
            chests = iris.irisData.chests
        }
    }

    local jsonEncode = json.Encode(file)

    assert(type(jsonEncode) == "string")

    return jsonEncode, nil
end

local function Decode(file)
    if file == "" or file == nil then
        return nil, errors.ErrFailedToDecode
    end

    local jsonDecode = json.Decode(file)
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
