{type} = require "fairmont"
Request = require "request"

Shred = require("shred")

SchemaManager = require("./schema_manager")
Action = require("./action")

module.exports = class Client

  @SchemaManager = SchemaManager

  @discover: (service_url, handlers) ->
    if service_url.constructor != String
      throw new Error("Expected to receive a String, but got something else")

    create_client = (response) ->
      client = new Client(response.content.data)
      
    if handler = handlers["200"]
      handlers["200"] = (response) ->
        client = new Client(response.content.data)
        handler(client)

    else if handler = handlers["response"]
      handlers["response"] = (response) ->
        client = new Client(response.content.data)
        handler(client)

    new Shred().request
      url: service_url
      method: "GET"
      headers:
        "Accept": "application/json"
      cookieJar: null
      on: handlers



  constructor: (@api, options={}) ->
    {@authorizer} = options
    @shred = new Shred()

    # Validate API specification
    required_fields = ["schemas", "resources", "directory"]
    missing_fields = []
    for field in required_fields
      unless @api[field]
        missing_fields.push(field)

    if missing_fields.length != 0
      throw new Error("API specification is missing fields: #{missing_fields.join(', ')}")

    @schema_manager = new SchemaManager(@api.schemas...)

    @resource_constructors = @create_resource_constructors(@api.resources)

    @resources = {}
    @create_directory(@api.directory, @resource_constructors)


  # Create resource instances using the URLs supplied in the service
  # description's directory.
  create_directory: (directory, constructors) ->
    for key, options of directory
      if options.constructor == String
        # FIXME: This is here for temporary backwards compatibility while
        # reworking the service to provide the right directory format
        @resources[key] = new constructors[key](url: options)
      else if constructors[options.resource]
        if options.url
          # The API has provided a URL for this resource, so we do not have to
          # generate it.  This is the expected case for directories coming
          # from a Patchboard Server.
          url = options.url
          @resources[key] = new constructors[options.resource](url: url)
        else if options.path
          # When using a Patchboard definition for a third party API, you may
          # choose to specify paths in the directory, instead of full URLs,
          # to avoid the redundancy.
          url = @api.service_url + options.path
          @resources[key] = new constructors[options.resource](url: url)
        else if options.template
          # Patchboard can use path templates to provide support for
          # insufficiently hyperlinked APIs.  First we create methods for
          # instantiating parameterized resources.
          # Example:
          #     client.resources.user(login: "dyoder")
          @resources[key] = @create_resource(options.resource, options.template)
          # Then, if an association is specified, we imbue the associated
          # constructor with a method for instantiating this resource.
          if options.association
            @associate(options)

  create_resource: (name, template) ->
    (options) =>
      constructor = @resource_constructors[name]
      options.url = @generate_url(template, options)
      return new constructor(options)

  generate_url: (template, options) ->
    parts = template.split("/")
    out = []
    for part in parts
      if part.indexOf(":") == 0
        key = part.slice(1)
        if string = options[key]
          out.push(string)
        else
          string = "Missing key: '#{key}' in options: #{JSON.stringify(options)}"
          throw new Error(string)
      else
        out.push(part)
    @api.service_url + out.join("/")

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
          url = client.generate_url(spec.template, identifier)
          new extension_constructor(url: url)


  create_resource_constructors: (definitions) ->
    resource_constructors = {}
    for type, definition of definitions
      constructor = @create_resource_constructor(type, definition)
      resource_constructors[type] = constructor
      if definition.aliases
        for alias in definition.aliases
          resource_constructors[alias] = constructor
    resource_constructors

  create_resource_constructor: (type, definition) ->
    client = @
    constructor = (data) ->
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
        data = new constructor(data)
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



