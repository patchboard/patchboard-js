assert = require "assert"
SchemaManager = require("../schema_manager")

# For this to work, you must have the main Patchboard repo living
# in the same directory as patchboard-js
api = require("../../patchboard/src/example_api")
api.directory = {}
SchemaManager.normalize(api.schema)

module.exports =
  api:
    directory: {}
    resources: api.resources
    schemas: [api.schema]

  partial_equal: (actual, expected) ->
    for key, val of expected
      assert.deepEqual(actual[key], val)

