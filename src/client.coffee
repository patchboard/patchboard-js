Request = require "./request"

SchemaManager = require("./schema_manager")

Action = require("./action")

class API

  constructor: ({mappings, @resources, @schemas}) ->
    if !(mappings && @resources && @schemas)
      throw new Error("API specification must provide mappings, resources, and schemas")

    for name, definition of @resources
      definition.name = name

    @mappings = {}
    for name, mapping of mappings
      @mappings[name] = new Mapping(@, mapping)


class Mapping
  constructor: (api, {@name, @resource, @url, @template, @path, @query}) ->
    {@service_url} = api
    if !@resource?
      throw new Error "Mapping does not specify 'resource'"
    if !(@url? || @path? || @template?)
      throw new Error "Mapping is missing any form of URL specification"
    if !(resource = api.resources[@resource])?
      throw new Error "Mapping specifies a resource that is not defined"
    @resource_definition = resource

  generate_url: (params={}) ->
    url = @service_url
    path = ""
    if params.url
      url = params.url
    else if @url?
      url = @url
    else if (template = @template)?
      # this should never be needed when the API is served by a
      # Patchboard Server.  Including it for client-side only
      # uses, such as the GitHub API.
      parts = template.split("/")
      out = []
      for part in parts
        if part.indexOf(":") == 0
          key = part.slice(1)
          if (string = params[key])?
            out.push(string)
          else
            throw new Error(
              "Missing key: '#{key}' in params: #{JSON.stringify(params)}"
            )
        else
          out.push(part)
      url = url + out.join("/")
    else if @path?
      # Ditto above comment.
      path = @path
    else
      throw new Error """
        Unusable URL mapping.  Must have url, path, or template field.
        Mapping: #{JSON.stringify(@, null, 2)}
      """

    query_string = ""
    if (query = @query)?
      parts = []
      keys = Object.keys(query).sort()
      for key in keys
        schema = query[key]
        if (string = params[key])?
          parts.push "#{key}=#{string}"
      if parts.length > 0
        query_string = "?#{parts.join('&')}"
      else
        query_string = ""

    encodeURI(url + path + query_string)


module.exports = class Client
  @Request = Request

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

    if options.gzip?
      request.headers["Accept-Encoding"] = "gzip"

    new Request request, (error, response) =>
      if error?
        callback error
      else
        if response.data?
          client = new Client(response.data, options)
          callback null, client
        else
          callback new Error "Unparseable response body"



  constructor: (api, @options={}) ->
    {@authorizer, @gzip} = @options
    @api = new API(api)

    @schema_manager = new SchemaManager(@api.schemas...)
    @create_resource_constructors(@api.resources, @api.mappings)

    @resources = @create_endpoints(@api.mappings)

  # Create resource instances and constructor-helpers using the URLs supplied
  # in the API mappings.
  create_endpoints: (mappings) ->
    endpoints = {}
    for name, mapping of mappings
      do (name, mapping) =>
        {url, query, path, template} = mapping
        constructor = mapping.constructor
        if template? || query?
          endpoints[name] = (params={}) ->
            new constructor {url: mapping.generate_url(params)}
        else if path?
          endpoints[name] = new constructor(url: mapping.generate_url())
        else if url?
          endpoints[name] = new constructor(url: url)
        else
          console.error "Unexpected mapping:", name, mapping
    endpoints

  create_resource_constructors: (definitions, mappings) ->
    constructors = {}

    for name, mapping of mappings
      definition = mapping.resource_definition
      constructor = @resource_constructor({mapping, definition})
      mapping.constructor = constructor
      constructors[name] = constructor

      if definition.aliases?
        for alias in definition.aliases
          constructors[alias] = constructor

    constructors

  resource_constructor: ({mapping, definition}) ->
    client = @
    constructor = (data={}) ->
      if data?.constructor == String
        # for cases like: resource("http://something.com/foo")
        @url = data
      else
        for key, value of data
          @[key] = value
      return @

    constructor.prototype._actions = {}
    constructor.prototype.resource_type = definition.name

    # Hide the Patchboard client from such things as console.log
    Object.defineProperty constructor.prototype, "patchboard_client",
      value: @
      enumerable: false

    for name, def of definition.actions
      do (name, def) ->
        action = constructor.prototype._actions[name] = new Action(client, name, def)
        constructor.prototype[name] = (args...) ->
          action.request(@url, args...)

    # Mix in default resource methods
    for name, method of @resource_methods
      constructor.prototype[name] = method


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

      if body?
        command.push "  -d #{JSON.stringify(body)}"
      command.push "  #{url}"
      command.join(" \\\n")

  # end resource_methods


  decorate: (schema, data) ->
    # Determine the resource by following the schema "name" to the mappings,
    # which define the resource names.
    if (name = schema.id?.split("#")[1])?
      if (mapping = @api.mappings[name])?
        constructor = mapping.constructor
        _data = data
        if mapping.query?
          # Some resources require query parameters to instantiate.
          # For these, we've stuck the query definition onto the
          # constructor.  For these cases, we substitute a simple
          # function for the property.
          # In usage, this looks like:
          #   user.repository(name: "patchboard").update(content, callback)
          data = (params) ->
            if _data.url?
              params.url = _data.url
            new constructor {url: mapping.generate_url(params)}

        else
          data = new constructor(_data)
    return @_decorate(schema, data) || data


  _decorate: (schema, data) ->
    if !schema? || !data?
      return
    if ref = schema.$ref
      if (schema = @schema_manager.find(ref))?
        @decorate(schema, data)
      else
        console.error "Can't find ref:", ref
        data
    else
      if schema.type == "array"
        if schema.items?
          for item, i in data
            if (result = @decorate(schema.items, item))?
              data[i] = result
      else
        switch schema.type
          when "string", "number", "integer", "boolean"
            null
          else
            # Declared properties
            for key, value of schema.properties
              if (result = @decorate(value, data[key]))?
                data[key] = result
            # Default for undeclared properties
            if addprop = schema.additionalProperties
              for key, value of data
                unless schema.properties?[key]
                  data[key] = @decorate(addprop, value)
            return data



