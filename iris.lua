local logging = require("libs.logging")
local irisAPI = require("irisAPI")

local logger = logging.NewLogger(nil, "iris.log")
local iris = irisAPI.NewIRIS(logger)

iris.init()