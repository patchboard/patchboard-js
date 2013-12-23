Request = require "./request"

SchemaManager = require("./schema_manager")

Action = require("./action")

module.exports = class Client

  @discover: (args...) ->
    if args.length == 2
      [url, callback] = args
      options = {}
    else if args.length == 3
      [url, options, callback] = args

    if url.constructor != String
      throw new Error("Discovery URL must be a string")

    request =
      url: url
      method: "GET"
      headers:
        "Accept": "application/json"

    if options.gzip
      request.headers["Accept-Encoding"] = "gzip"

    new Request request, (error, response) =>
      if error
        callback error
      else
        if response.data
          client = new Client(response.data, options)
          callback null, client
        else
          callback new Error "Unparseable response body"



  constructor: (@api, @options={}) ->
    {@authorizer, @gzip} = @options

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
    @create_references(@api.mappings, @resource_constructors)

  # Create resource instances and constructor-helpers using the URLs supplied
  # in the API mappings.
  create_references: (mappings, constructors) ->
    for name, mapping of mappings
      do (name, mapping) =>
        {url, query, path, template} = mapping

        # TODO error handling for invalid mappings
        if constructor = constructors[name]
          if template || query
            @resources[name] = (params={}) ->
              new constructor(null, params)
          else if path
            url = @generate_url(mapping)
            @resources[name] = new constructor(url: @generate_url(mapping))
          else if url
            @resources[name] = new constructor(url: url)
          else
            #console.log name, mapping
        else
          throw new Error "No constructor for '#{name}'"

  create: (name, params) ->
    constructor = @resource_constructors[name]
    constructor(params, {})

  generate_url: (mapping, params={}) ->
    url = @api.service_url
    if mapping.url
      url = mapping.url
      path = ""
    else if template = mapping.template
      # this should never be needed when the API is served by a
      # Patchboard Server.  Including it for client-side only
      # uses, such as the GitHub API.
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
      # Ditto above comment.
      path = mapping.path
    else
      throw new Error """
        Unusable URL mapping.  Must have url, path, or template field.
        Mapping: #{JSON.stringify(mapping, null, 2)}
      """

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

    constructor = (data={}, params={}) ->

      # resource("http://something.com/foo")
      if params?.constructor == String
        data.url = params
      else if mapping
        {url, path, template, query} = mapping
        url ||= data.url
        data.url = client.generate_url({url, path, template, query}, params)

      for key, value of data
        @[key] = value
      return @

    constructor.prototype._actions = {}
    constructor.prototype.resource_type = type
    if mapping?.query
      constructor.query = mapping.query

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
        _data = data
        if constructor.query
          # Some resources require query parameters to instantiate.
          # For these, we've stuck the query definition onto the
          # constructor.  For these cases, we substitute a simple
          # function for the property.
          # In usage, this looks like:
          #   user.repository(name: "patchboard").update(content, callback)
          # TODO: this approach short circuits any further decoration
          # of resources inside the present resource.  Try to fix.
          data = (params) ->
            new constructor _data, params

        else
          data = new constructor(_data)
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



