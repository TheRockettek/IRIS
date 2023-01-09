local logging = require "libs.logging"
local core = require "core"

local logger = logging.NewLogger("-", "iris.log")
logger.setLevel("debug")

local iris = core.NewIRIS(logger)

iris.start()

-- logging = require "libs.logging"; core = require "core"; logger = logging.NewLogger("-", "iris.log"); logger.setLevel("trace"); iris = core.NewIRIS(logger); iris.start()
