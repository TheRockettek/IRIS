local logging = require("libs.logging")
local irisAPI = require("irisAPI")
local gui = require("gui.main")

local logger = logging.NewLogger("-", "iris.log")
logger.silent = true

local iris = irisAPI.NewIRIS(logger)

parallel.waitForAll(
    function() gui.NewGUI(iris).run() end,
    function() iris.init() end
)
