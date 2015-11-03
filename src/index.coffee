#Promise = require "bluebird"
httpAdapter = require "axios"
JSCK = require "jsck"

module.exports = require("./client") { httpAdapter, JSCK }

