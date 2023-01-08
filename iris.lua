local logging = require "libs.logging"
local core = require "core"

local logger = logging.NewLogger("-", "iris.log")
logger.setLevel("trace")

local iris = core.NewIRIS(logger)

iris.start()
