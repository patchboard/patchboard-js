{type} = require "fairmont"
Request = require "request"

Shred = require("shred")

SchemaManager = require("./schema_manager")

Action = require("./action")

module.exports = class Client

  @SchemaManager = SchemaManager

  @discover: (url, callback) ->
    if url.constructor != String
      throw new Error("Discovery URL must be a string")

    options =
      url: url
      method: "GET"
      headers:
        "Accept": "application/json"

    Request options, (error, response, body) =>
      if error
        callback error
      else
        try
          data = JSON.parse(body)
        catch error
          callback "Unparseable response body: #{error.message}"
          return
        client = new Client(data)
        callback null, client



  constructor: (@api, options={}) ->
    {@authorizer} = options

    # Validate API specification
    required_fields = ["schemas", "resources", "mappings"]
    missing_fields = []
    for field in required_fields
      unless @api[field]
        missing_fields.push(field)

    if missing_fields.length != 0
      throw new Error("API specification is missing fields: #{missing_fields.join(', ')}")

    @schema_manager = new SchemaManager(@api.schemas...)
    @resource_constructors = @create_resource_constructors(@api.resources, @api.mappings)

    @resources = {}
    @create_directory(@api.mappings, @resource_constructors)

  # Create resource instances using the URLs supplied in the service
  # description's mappings.
  create_directory: (mappings, constructors) ->
    for name, mapping of mappings
      do (name, mapping) =>
        {url, path, template} = mapping
        # TODO: use a JSON schema for this sort of thing
        if !(url || path || template)
          throw new Error "Mapping lacks a url, path, or template field"
        if constructor = constructors[mapping.resource]
          if mapping.url && !mapping.query
            # The API has provided a URL for this resource, so we do not have to
            # generate it.  This is the expected case for directories coming
            # from a Patchboard Server.
            url = mapping.url
            @resources[name] = new constructor(null, url: url)

          else if mapping.path && !mapping.query
            url = @generate_url(mapping)
            @resources[name] = new constructor(null, url: url)
          else
            @resources[name] = (params={}) ->
              new constructor(params)
        else
          throw new Error "No constructor for '#{name}'"

  create: (name, params) ->
    constructor = @resource_constructors[name]
    constructor(params, {})

  generate_url: (mapping, params) ->
    url = @api.service_url
    if template = mapping.template
      parts = template.split("/")
      out = []
      for part in parts
        if part.indexOf(":") == 0
          key = part.slice(1)
          if string = params[key]
            out.push(string)
          else
            string = "Missing key: '#{key}' in params: #{JSON.stringify(params)}"
            throw new Error(string)
        else
          out.push(part)
      path = out.join("/")
    else if mapping.path
      path = mapping.path
    else if mapping.url
      url = mapping.url
      path = ""
    else
      throw new Error "Unusable URL generator: #{JSON.stringify(mapping)}"

    query_string = ""
    if query = mapping.query
      parts = []
      keys = Object.keys(query).sort()
      for key in keys
        schema = query[key]
        if string = params[key]
          parts.push "#{key}=#{string}"
      if parts.length > 0
        query_string = "?#{parts.join('&')}"
      else
        query_string = ""

    encodeURI(url + path + query_string)


  create_resource_constructors: (definitions, mappings) ->
    constructors = {}

    for type, definition of definitions
      constructor = @resource_constructor({type, definition})
      constructors[type] = constructor

    for name, mapping of mappings
      type = mapping.resource
      definition = definitions[type]
      if !definition
        throw new Error "No resource defined for '#{type}'"
      constructor = @resource_constructor({type, mapping, definition})
      constructors[name] = constructor

      if definition.aliases
        for alias in definition.aliases
          constructors[alias] = constructor

    constructors

  resource_constructor: ({type, mapping, definition}) ->
    client = @
    constructor = (params, data={}) ->
      if mapping && params && !data.url
        data.url = client.generate_url(mapping, params)
      for key, value of data
        @[key] = value
      return @

    constructor.prototype._actions = {}
    constructor.prototype.resource_type = type
    # Hide the Patchboard client from such things as console.log
    Object.defineProperty constructor.prototype, "patchboard_client",
      value: @
      enumerable: false

    # Mix in default resource methods
    for name, method of @resource_methods
      constructor.prototype[name] = method

    for name, def of definition.actions
      do (name, def) ->
        action = constructor.prototype._actions[name] = new Action(client, name, def)
        constructor.prototype[name] = (args...) ->
          action.request(@url, args...)

    constructor


  resource_methods:

    # returns a string that (when logged to console) can be used as the
    # curl command that exactly represents this action.
    curl: (name, args...) ->
      action = @_actions[name]
      request = action.create_request(@url, args...)

      {method, url, headers, body} = request
      agent = headers["User-Agent"]
      command = []
      command.push "curl -v -A '#{agent}' -X #{method}"
      for header, value of headers when header != "User-Agent"
        command.push "  -H '#{header}: #{value}'"

      if body
        command.push "  -d '#{JSON.stringify(body)}'"
      command.push "  #{url}"
      command.join(" \\\n")

  # end resource_methods


  decorate: (schema, data) ->
    if name = schema.id?.split("#")[1]
      if constructor = @resource_constructors[name]
        data = new constructor(null, data)
    return @_decorate(schema, data) || data


  _decorate: (schema, data) ->
    if !schema || !data
      return
    if ref = schema.$ref
      if schema = @schema_manager.find(ref)
        @decorate(schema, data)
      else
        console.error "Can't find ref:", ref
        data
    else
      if schema.type == "array"
        if schema.items
          for item, i in data
            if result = @decorate(schema.items, item)
              data[i] = result
      else
        switch schema.type
          when "string", "number", "integer", "boolean"
            null
          else
            # Declared properties
            for key, value of schema.properties
              if result = @decorate(value, data[key])
                data[key] = result
            # Default for undeclared properties
            if addprop = schema.additionalProperties
              for key, value of data
                unless schema.properties?[key]
                  data[key] = @decorate(addprop, value)
            return data



