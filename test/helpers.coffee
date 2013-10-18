assert = require "assert"
SchemaManager = require("../schema_manager")

api = require("../../patchboard/src/example_api")
SchemaManager.normalize(api.schema)

module.exports =
  api:
    directory: api.directory
    resources: api.resources
    schemas: [api.schema]
    service_url: "http://smurf.com"

  partial_equal: (actual, expected) ->
    for key, val of expected
      assert.deepEqual(actual[key], val)

