api = require "../node_modules/patchboard-api/src/test_api.coffee"

module.exports =
  api:
    service_url: "http://smurf.com"
    mappings: api.mappings
    resources: api.resources
    schemas: [api.schema]
    type: api.type

  SchemaManager: require "../src/schema_manager"
  Action: require "../src/action"
  Client: require "../src/client"
