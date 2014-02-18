Request = require "./request"
{type} = require "fairmont"
{Evie} = require "evie"

module.exports = class Action

  constructor: (@client, @name, @definition) ->
    {@schema_manager, @gzip} = @client

    {request, response} = @definition
    @status = response?.status || 200
    if request?.type?
      @request_schema = @schema_manager.find mediaType: request.type

    if response?.type?
      @response_schema = @schema_manager.find mediaType: response.type

    @_base_headers = @base_headers(@definition)


  base_headers: ->
    headers =
      "User-Agent": "patchboard-js"

    if @request_schema?
      headers["Content-Type"] = @request_schema.mediaType

    # FIXME:  we should also check for definition.accept
    if @response_schema?
      headers["Accept"] = @response_schema.mediaType

    headers


  create_request: (url, args...) ->
    resource = @
    options = @process_args(args)
    request =
      url: url
      method: @definition.method
      headers: {}

    if (body = @prepare_body(options))?
      request.body = body

    for key, value of @_base_headers
      request.headers[key] = value

    auth_type = @definition.request?.authorization
    if auth_type? && @client.authorizer?
      credential = @client.authorizer(auth_type, @name)
      request.headers["Authorization"] = "#{auth_type} #{credential}"

    if @gzip?
      request.headers["Accept-Encoding"] = "gzip"

    request

  #request: (url, args..., callback) ->
  request: (url, args...) ->
    events = new Evie()
    [_args..., callback] = args
    if typeof(callback) == "function"
      args = _args
    else
      callback = undefined

    try
      options = @create_request(url, args...)
    catch error
      callback?(error)
      events.emit "error", error
      return

    request = new Request options
    request.on "error", (error) =>
      callback?(error)
      events.emit "error", error
    request.on "success", (response) =>
      if response.status != @status
        error = new Error "Unexpected response status: #{response.status}"
        error.status = response.status
        error.response = response
        callback?(error)
        events.emit "error", error
      else
        if @response_schema?
          try
            response.data = JSON.parse(response.body)
          catch error
            error = new Error "Unparseable response body"
            return
          response.resource = @client.decorate(@response_schema, response.data)
          callback?(null, response)
          events.emit "success", response

    events


  process_args: (args) ->
    options = {}
    signature = (args.map (arg) -> type(arg)).join(".")

    content_required = @request_schema
    if content_required?
      switch signature
        when "string"
          [options.body] = args
        when "object"
          [options.content] = args
        when "array"
          [options.content] = args
        else
          throw new Error "Invalid arguments for action; content required"
    else
      switch signature
        when ""
          [] = args
        else
          throw new Error "Invalid arguments for action"
    options


  prepare_body: (options) ->
    if options.content?
      JSON.stringify(options.content)
    else if options.body?
      options.body
    else
      undefined

