http = require "http"
https = require "https"
URL = require "url"
try
  zlib = require "zlib"
catch error
  zlib = null

{EventEmitter} = require "events"

corsetCase = (string) ->
  string.toLowerCase()
    .replace("_", "-")
    .replace /(^|-)(\w)/g, (s) -> s.toUpperCase()

module.exports = class Request extends EventEmitter

  constructor: (options, handler) ->
    {@url, @method, @headers, @body, timeout, @redirects} = options
    @headers ?= {}
    @method = @method.toUpperCase()
    @redirects ?= 1
    # TODO: allow query params as object in options
    {protocol, hostname, port, path} = URL.parse @url

    if protocol == "http:"
      client = http
      port ?= 80
    else
      client = https
      port ?= 443

    parameters =
      host: hostname
      port: port
      path: path
      method: @method
      headers: @headers

    if @body? && Buffer?
      @headers["Content-Length"] = Buffer.byteLength(@body)

    callback = (error, response) =>
      if handler?
        handler(error, response)
      if error?
        @emit "error", error
      else
        @emit "success", response

    raw = client.request parameters, (response) =>
      switch response.statusCode
        when 300, 301, 302, 303, 307
          @redirect @, response, callback
        when 304, 305
          callback new Error "#{response.statusCode} handling not yet implemented"
        else
          response = new Response(response, callback)

    raw.on "error", (error) =>
      callback error

    if timeout?
      raw.setTimeout timeout, =>
        raw.abort()

    if @body?
      raw.write @body.toString()
    raw.end()

  redirect: (request, response, callback) ->
    {method, headers, body, timeout, redirects} = request
    if !(method == "GET" || method == "HEAD")
      callback new Error "Received redirect for method other than GET or HEAD"
    else if redirects == 0
      callback new Error "Exceeded allowed number of redirects"
    else
      location = response.headers["Location"] || response.headers["location"]
      if location?
        new Request {
          url: location
          redirects: redirects - 1
          method, headers, body, timeout
        }, callback
      else
        callback new Error "Redirect response did not provide Location"
        

class Response

  constructor: (@raw, callback) ->
    @_content = new ResponseContent @
    @status = @raw.statusCode

    @headers = {}
    @_normalized = {}
    for key, value of @raw.headers
      @headers[key] = value
      @_normalized[corsetCase(key)] = value

    @raw.on "end", =>
      @_content.process (@content) =>
        @body = @content.body
        @data = @content.data
        callback null, @

  getHeader: (name) ->
    @headers[name] || @_normalized[corsetCase(name)]


class ResponseContent

  constructor: (@response) ->
    @raw = @response.raw
    @chunks = []
    @length = 0

    {headers} = @raw
    @type = headers["Content-Type"] || headers["content-type"]
    switch (encoding = headers["Content-Encoding"] || headers["content-encoding"])
      when "gzip"
        @encoding = encoding
      else
        @encoding = null

    @raw.on "data", (chunk) =>
      @chunks.push chunk
      @length += chunk.length


  process: (callback) ->
    # TODO: take encoding into account
    # TODO: check content-length against actual length
    if Buffer?
      @buffer = Buffer.concat @chunks, @length
    else
      @buffer = @chunks.join("")

    @process_encoding =>
      @process_type callback

  process_encoding: (callback) ->
    if @encoding? && zlib?
      zlib.gunzip @buffer, (error, buffer) =>
        @body = buffer.toString("utf-8")
        callback()
    else
      @body = @buffer.toString("utf-8")
      callback()

  process_type: (callback) ->
    if @type?
      if /json/.test(@type)
        try
          @data = JSON.parse(@body)
        catch error
          @data = undefined

    callback
      buffer: @buffer, body: @body, data: @data



