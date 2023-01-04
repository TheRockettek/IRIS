local logging = require("current.libs.logging")
local irisAPI = require("current.irisAPI")
local gui = require("current.gui.main")

local logger = logging.NewLogger("-", "iris.log")
logger.setLevel("trace")

local iris = irisAPI.NewIRIS(logger)

iris.init()
gui.NewGUI(iris).run()
