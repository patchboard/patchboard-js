deap = require "deap"
assert = require "assert"
Testify = require "testify"

{Client} = require "../helpers"


base_api =
  mappings:
    smurf:
      resource: "smurf"
      url: "http://smurf.com/smurf"
  resources:
    smurf:
      actions:
        get:
          method: "GET"
          response_schema: "urn:smurf#smurf"
          status: 200
  schemas: [
    id: "urn:smurf"
    definitions:
      smurf:
        type: "object"
        properties:
          name:
            type: "string"
      smurf_list:
        type: "array"
        items: {$ref: "#/definitions/smurf"}
  ]

Testify.test "invalid API definitions", (context) ->

  context.test "base API is valid", ->
    assert.doesNotThrow ->
      new Client base_api

  context.test "invalid mapping", ->
    assert.throws ->
      api = deap.clone(base_api)
      delete api.mappings.smurf.resource
      new Client api
    assert.throws ->
      api = deap.clone(base_api)
      delete api.mappings.smurf.url
      new Client api

  context.test "invalid reference in schema", ->
    assert.throws ->
      api = deap.clone(base_api)
      api.schemas[0].definitions.smurf_list.items = {$ref: "#/definitions/dwarf"}
      new Client api

  context.test "invalid reference in mappings", ->
    assert.throws ->
      api = deap.clone(base_api)
      api.mappings.smurf.resource = "dwarf"
      new Client api
  

