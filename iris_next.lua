local logging = require "iris.libs.logging"
local irisAPI = require "iris.iris"

local logger = logging.NewLogger("-", "iris.log")
logger.setLevel("trace")

local iris = irisAPI.NewIRIS(logger)

iris.init()
