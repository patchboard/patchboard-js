Request = require "request"
{type} = require "fairmont"

module.exports = class Action

  constructor: (@client, @name, @definition) ->
    {@schema_manager, @authorizer} = @client

    {request, response} = @definition
    @status = response?.status || 200
    if request?.type
      @request_schema = @schema_manager.find mediaType: request.type
      unless @request_schema
        throw new Error "No schema found for request '#{request.type}'"

    if response?.type
      @response_schema = @schema_manager.find mediaType: response.type
      unless @response_schema
        throw new Error "No schema found for response '#{request_schema}'"

    @_base_headers = @base_headers(@definition)


  base_headers: ->
    headers =
      "User-Agent": "patchboard-js"

    if @request_schema
      headers["Content-Type"] = @request_schema.mediaType

    # FIXME:  we should also check for definition.accept
    if @response_schema
      headers["Accept"] = @response_schema.mediaType

    headers


  create_request: (url, args...) ->
    resource = @
    options = @process_args(args)
    request =
      url: url
      method: @definition.method
      headers: {}

    if body = @prepare_body(options)
      request.body = body

    for key, value of @_base_headers
      request.headers[key] = value

    if auth_type = @definition.authorization
      credential = @authorizer(auth_type, @name)
      request.headers["Authorization"] = "#{auth_type} #{credential}"

    request

  request: (url, args..., callback) ->
    if !callback?
      # TODO: rewire for EventEmitter
      callback = (error, response) =>
        if error
          console.error error
        else
          console.log response.body
    try
      options = @create_request(url, args...)
    catch error
      callback?(error)
      return
    Request(options, @request_handler(callback))


  request_handler: (callback) ->
    (error, response, body) =>
      if error
        callback(error)
      else if response.statusCode == @status
        if @response_schema
          response.body = body
          try
            response.data = JSON.parse(response.body)
          catch error
            callback "Unparseable response body: #{error.message}"
            return
          response.resource = @client.decorate(@response_schema, response.data)
        callback null, response
      else
        error = new Error "Unexpected response status: #{response.statusCode}"
        error.status = response.statusCode
        error.response = response
        callback(error)


  process_args: (args) ->
    options = {}
    signature = (args.map (arg) -> type(arg)).join(".")

    content_required = @request_schema
    if content_required
      switch signature
        when "string"
          [options.body] = args
        when "object"
          [options.content] = args
        when "array"
          [options.content] = args
        else
          throw new Error "Invalid arguments for action"
    else
      switch signature
        when ""
          [] = args
        else
          throw new Error "Invalid arguments for action"
    options


  prepare_body: (options) ->
    if options.content
      JSON.stringify(options.content)
    else if options.body
      options.body
    else
      undefined

