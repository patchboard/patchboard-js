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

  Context: class Context

    constructor: ->
      @schemes = {}

    # Supply auth scheme credentials for a particular auth scheme
    # Creates an authorization string that will be placed in the header
    authorize: (scheme, params) ->
      if scheme == "Basic"
        {login, password} = params
        encoded = new Buffer("#{login}:#{password}").toString("base64")
        @schemes[scheme] = encoded
      else
        @schemes[scheme] = @format_params(params)

    authorizer: (schemes, resource, action) ->
      for scheme in schemes
        if credential = @schemes[scheme]
          return [scheme, credential]

    format_params: (params) ->
      ("#{key}=\"#{value}\"" for key, value of params).join(", ")



