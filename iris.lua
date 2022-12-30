local logging = require("libs.logging")
local irisAPI = require("irisAPI")
local gui = require("gui.main")

local logger = logging.NewLogger(nil, "iris.log")
logger.silent = true

local iris = irisAPI.NewIRIS(logger)

parallel.waitForAll(
    function() iris.init() end,
    function() gui.MainLoop(iris) end
)