http = require "http"
https = require "https"
URL = require "url"

corsetCase = (string) ->
  string.toLowerCase()
    .replace("_", "-")
    .replace /(^|-)(\w)/g, (s) -> s.toUpperCase()


module.exports = class Request

  constructor: (options, callback) ->
    {@url, @method, @headers, @body, @timeout, @redirects} = options
    @method = @method.toUpperCase()
    @redirects ?= 1
    {protocol, hostname, port, path} = URL.parse @url

    client = (if protocol is "http:" then http else https)

    parameters =
      hostname: hostname
      port: port
      path: path
      method: @method
      headers: @headers

    if @body
      @headers["Content-Length"] = Buffer.byteLength(@body)

    raw = client.request parameters, (response) =>
      switch response.statusCode
        when 300, 301, 302, 303, 307
          @redirect @, response, callback
        when 304, 305
          callback new Error "#{response.statusCode} handling not implemented"
        else
          response = new Response(response, callback)

    raw.on "error", (error) =>
      callback error

    if @timeout
      @timeout = raw.setTimeout raw, =>
        callback new Error "Request timed out"

    if @body
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
      if location
        new Request {
          url: location
          redirects: redirects - 1
          method, headers, body, timeout
        }, callback
      else
        callback new Error "Redirect response did not provide Location"
        

class Response

  constructor: (@_raw, callback) ->
    @content = new ResponseContent @
    @status = @_raw.statusCode
    @headers = {}
    for key, value of @_raw.headers
      @headers[corsetCase(key)] = value

    @_raw.on "end", =>
      # TODO: getters with Object.defineProperties
      @body = @content.body()
      @data = @content.data()
      callback null, @


class ResponseContent

  constructor: (@response) ->
    @raw = @response._raw
    @chunks = []
    @length = 0

    {headers} = @raw
    @type = headers["Content-Type"] || headers["content-type"]

    @raw.on "data", (chunk) =>
      @chunks.push chunk
      @length += chunk.length

  body: ->
    # TODO: take encoding into account
    # TODO: check content-length against actual length
    @_body ||= @chunks.join("")

  data: ->
    if @type
      if /json/.test @type
        JSON.parse @body()
      else
        undefined



