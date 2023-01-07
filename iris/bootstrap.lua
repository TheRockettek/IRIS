local logging = require "iris.libs.logging"
local core = require "iris.core"

local logger = logging.NewLogger("-", "iris.log")
logger.setLevel("trace")

local iris = core.NewIRIS(logger)

iris.start()
