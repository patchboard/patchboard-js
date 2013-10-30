assert = require "assert"
SchemaManager = require("../schema_manager")

api = require("./api")

module.exports =
  api:
    service_url: "http://smurf.com"
    mappings: api.mappings
    resources: api.resources
    schemas: [api.schema]
    media_type: api.media_type

