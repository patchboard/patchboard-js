{type} = require "fairmont"
Request = require "request"

Shred = require("shred")

SchemaManager = require("./schema_manager")
Action = require("./action")

module.exports = class Client

  @SchemaManager = SchemaManager

  #@discover: (service_url, handlers) ->
    #if service_url.constructor != String
      #throw new Error("Expected to receive a String, but got something else")

    #create_client = (response) ->
      #client = new Client(response.content.data)
      
    #if handler = handlers["200"]
      #handlers["200"] = (response) ->
        #client = new Client(response.content.data)
        #handler(client)

    #else if handler = handlers["response"]
      #handlers["response"] = (response) ->
        #client = new Client(response.content.data)
        #handler(client)

    #new Shred().request
      #url: service_url
      #method: "GET"
      #headers:
        #"Accept": "application/json"
      #cookieJar: null
      #on: handlers



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
            # Then, if an association is specified, we imbue the associated
            # constructor with a method for instantiating this resource.
            if mapping.association
              # TODO: apply @associate everywhere appropriate, not just for
              # resources created at startup
              @associate(mapping)
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





  associate: (spec) ->
    client = @
    # TODO: error checking
    target = spec.association

    target_constructor = @resource_constructors[target]
    # TODO: handle situation where no identifiers object has been created.
    # TODO: handle situation where named identifier does not exist.
    identify = @identifiers[target]

    extension_constructor = @resource_constructors[spec.resource]

    if target_constructor && extension_constructor
      Object.defineProperty target_constructor.prototype, spec.resource,
        get:  ->
          identifier = identify(@)
          url = client.generate_url(spec, identifier)
          new extension_constructor(null, url: url)


  create_resource_constructors: (definitions, mappings) ->
    resource_constructors = {}

    for name, mapping of mappings
      type = mapping.resource
      resource_definition = definitions[type]
      constructor = @create_resource_constructor(type, mapping, resource_definition)
      resource_constructors[name] = constructor

      # FIXME: I am not sure aliasing belongs in the resource defs.
      # May be better in the mappings
      if resource_definition.aliases
        for alias in resource_definition.aliases
          resource_constructors[alias] = constructor

    resource_constructors

  create_resource_constructor: (type, mapping, definition) ->
    client = @
    constructor = (params, data={}) ->
      if params
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
      else if !SchemaManager.is_primitive(schema.type)
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



