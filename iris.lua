local logging = require("libs.logging")
local irisAPI = require("irisAPI")
local gui = require("gui.main")

local logger = logging.NewLogger("-", "iris.log")

local iris = irisAPI.NewIRIS(logger)

iris.init()
gui.NewGUI(iris).run()