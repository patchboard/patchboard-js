merge = (a, b) ->
  for own key, value of b
    a[key] = value
  a

extend = (child, parent) ->
  ctor = ->
    @constructor = child
    return

  merge child, parent

  ctor.prototype = parent.prototype
  child.prototype = new ctor
  child.__super__ = parent.prototype
  child

hiddenProperty = (object, name, value) ->
  Object.defineProperty object, name, { value, enumerable: false }

constructorCase = (string) ->
  camel = camelCase(string)
  camel[0].toUpperCase() + camel.slice(1)
  

camelCase = (string) ->
  string.replace /(\_[a-z])/g, (match) ->
    match.toUpperCase().replace('_', '')
  
querify = (params) ->
  # TODO: uri encoding
  a = ([key, value].join("=") for key, value of params)
  a.join("&")

curlify = (request) ->
  throw new Error "Unimplemented"


callbackify = (fn) ->
  arity = fn.prototype.length
  (args...) ->
    callback = null
    if arity < args.length
      [args..., callback] = args

    promise = fn(args...)
    if callback
      promise
      .then (result) ->
        callback null, result
      .catch (error) ->
        callback error
    else
      return promise

module.exports = ({httpAdapter, JSCK}) ->

  class Client

    @discover: (url, options={}) ->
      headers = merge {"Accept": "application/json"}, options.headers
      httpAdapter {url, method: "GET", headers}
        .then (response) ->
          {status, data} = response
          if status == 200
            new Client data, options
          else
            throw new Error "Unexpected response code #{status}"



    constructor: (@api, @options) ->
      @jsck = new JSCK.draft4(@api.schemas)
      @defaultHeaders = @options.headers || {}
      @endpoints = {}
      @constructors = {}
      defineConstructors @
      defineEndpoints @

    updateDefaultHeaders: (headers) ->
      for name, value of headers
        @setDefaultHeader(name, value)

    setDefaultHeaders: (headers) ->
      @defaultHeaders = headers

    setDefaultHeader: (name, value) ->
      @defaultHeaders[name] = value

    makeResourceCreator: (endpointName, baseURL) ->
      mapper = @endpoints[endpointName]
      creator = (params) ->
        constructor = mapper params
        if !constructor?
          throw new Error "Invalid query params for this endpoint"
        else
          if params?
            url = baseURL + "?" + querify(params)
          else
            url = baseURL
          new constructor {url}

      if (base = mapper.base)?
        creator.base = new base {url: baseURL}
        for name, method of base.prototype.actions
          do (name, method) ->
            creator[name] = (content, options) ->
              creator.base[name](content, options)

      return creator


    decorate: (schema, data) ->
      if (resource = schema.resource)?
        constructor = @constructors[resource]
        data = new constructor {data}
      else if (endpoint = schema.endpoint)?
        data = @makeResourceCreator endpoint, data.url

      return @_decorate schema, data

    _decorate: (schema, data) ->
      return unless schema? && data?
      if (ref = schema.$ref)?
        if (_schema = @jsck.find ref)?
          return @decorate(_schema, data)
        else
          console.error "Can't find schema.$ref: #{ref}"
          return data
      else
        if schema.type == "array" && schema.items?
          for item, i in data
            if (result = @decorate schema.items, item)?
              data[i] = result
        else
          if (properties = schema.properties)? && typeof(data) == "object"
            for key, value of properties
              if (result = @decorate value, data[key])?
                data[key] = result

          if (additionalProperties = schema.additionalProperties)?
            schema.properties ||= {}
            for key, value of data
              if !schema.properties[key]?
                if (result = @decorate additionalProperties, value)?
                  data[key] = result

          return data



  defineConstructors = (client) ->
    {api} = client
    {resources} = api

    for name, definition of resources
      constructorName = constructorCase name
      fndef = """
        return function #{constructorName} (options) {
          #{constructorName}.__super__.constructor.call(this, options)
        }
      """
      constructor = new Function(fndef)()
      extend(constructor, Resource)
      constructor.setup(definition)
      constructor.register(client, name)


  defineEndpoints = (client) ->
    {api} = client
    {endpoints} = api
    for name, definition of endpoints
      do (name, definition) ->
        endpoint = new Endpoint name, definition
        client.endpoints[name] = (params) ->
          resourceName = endpoint.map(params)
          client.constructors[resourceName]

        if (base = endpoint.base)?
          client.endpoints[name].base = client.constructors[base]

        if (url = definition.url)?
          client[name] = client.makeResourceCreator name, url

  class Endpoint
    constructor: (@name, definition) ->
      @mappings = []
      @resources = {}
      if definition.mappings?
        for def in definition.mappings
          mapping = new Mapping def
          @mappings.push mapping
          if mapping.query == false
            @base = def.resource
      else if definition.resource
        @resource = definition.resource
      else
        error = new Error "Invalid endpoint definition for #{@name}"
        error.endpoint = definition

    map: (params) ->
      return @resource if @resource
      matches = []
      for mapping in @mappings
        if mapping.match(params)
          matches.push mapping.resource
      # last mapping is best mapping, for now
      [_..., match] = matches
      return match


  class Mapping
    constructor: (definition) ->
      {@resource, @query} = definition
      if @query != false
        @validator = new JSCK.draft4 {
          required: @query.required
          properties: @query.parameters
          additionalProperties: false
        }


    match: (params) ->
      if @query == false
        if params
          false
        else
          true
      else
        if params
          {valid} = @validator.validate(params)
          return valid
        else
          if @query.required
            false
          else
            true


  class Resource

    @actions: {}

    @register: (@client, name) ->
      {@api} = @client
      @client.constructors[name] = @
      @client[@name] = @
      @resource_name = name

    @setup: (definition) ->
      hiddenProperty @prototype, "actions", definition.actions
      for name, action of definition.actions
        @actions[name] = action
        @defineAction @prototype, name, action

    @defineAction: (prototype, name, definition) ->
      hiddenProperty prototype, name, (input, options) ->
        @actionRequest definition, input, options


    @responseHandler: (action) ->
      (response) =>
        {headers, status, data} = response
        if action.response.status.indexOf(status) == -1
          error = new Error "Unexpected response code: #{status}"
          error.response = response
          throw error

        type = headers["content-type"]
        if !type? && action.response.type?
          type = action.response.type[0]

        if !type?
          return merge(data, {response})

        if (schema = @client.jsck.find {mediaType: type})?
          if @client.options.validateResponses == true
            validator = @client.jsck.validator {mediaType: type}
            report = validator.validate(data)
            if report.valid != true
              error = new Error "Response content did not match the schema"
              error.reason = report.errors
              throw error

        data = @client.decorate schema, data
        hiddenProperty data, "response", response
        return data



    constructor: ({url, data}) ->
      if url?
        @url = url
      else if data
        # TODO: use Object.defineProperties to set these?
        for key, value of data
          @[key] = value
      else
        throw new Error "Resource needs either .url or .data"


  hiddenProperty Resource.prototype, "actionRequest",
    (action, input, options={}) ->
      request = @prepare(action, input, options)
      httpAdapter(request)
        .then @constructor.responseHandler(action)
        .catch (error) ->
          if error.status?
            throw new Error "Unexpected response code: #{error.status}"
          else
            throw error

  hiddenProperty Resource.prototype, "prepare",
    (action, content, options={}) ->
      url = @url
      method = action.request.method
      headers = {}
      merge headers, @constructor.client.defaultHeaders

      if (types = action.request.type)?
        headers["Content-Type"] ||= types[0]
        # FIXME: only do this if the Content-Type indicates JSON
        if typeof(input) != "string"
          content = JSON.stringify(content)
      
      if (types = action.response.type)?
        headers["Accept"] ||= types[0]

      merge headers, options.headers
      return { url, method, headers, data: content || "" }
        
  return Client
  

