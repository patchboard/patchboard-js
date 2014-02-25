Testify = require "testify"
assert = require "assert"

Request = require "../src/request"

base = "http://rephraser.pandastrike.com"

request = (args...) ->
  new Request args...

Testify.test "Simple request lib", (context) ->

  context.test "A minimal valid GET", (context) ->
    options =
      url: "#{base}/200"
      method: "GET"
    request options, (error, response) ->
      context.test "Successful", ->
        assert.ifError error
        assert.equal response.status, 200

      context.test "headers", ->
        assert.ok(!response.content.data.headers["Content-Type"])

      context.test "response.body", (context) ->
        context.test "is a String", ->
          assert.equal(response.body.constructor, String)

        context.test "has correct length", ->
          assert.equal response.getHeader("Content-Length"), response.body.length

      context.test "response.data is an Object", ->
        assert.equal(response.content.data.constructor, Object)


  context.test "A minimal valid POST request", (context) ->
    options =
      url: "#{base}/200"
      method: "POST"
    request options, (error, response) ->
      context.test "Successful", ->
        assert.ifError error
        assert.equal response.status, 200

      context.test "headers", ->
        assert.ok !response.content.data.headers["Content-Type"]
        assert.ok !response.content.data.headers["content-type"]



  context.test "A POST with content type", (context) ->
    options =
      url: "#{base}/201"
      method: "POST"
      body: JSON.stringify {foo: 1, bar: 2}
      headers:
        "Content-Type": "application/json"
    request options, (error, response) ->
      context.test "Successful", ->
        assert.ifError error
        assert.equal response.status, 201

      context.test "Request used content-type header: 'application/json'", ->
        assert.equal response.content.data.headers["Content-Type"], "application/json"


  context.test "A GET that receives a redirect (301)", (context) ->
    options =
      url: "#{base}/301"
      method: "GET"
    request options, (error, response) ->
      context.test "Transparent redirect", ->
        assert.ifError error
        assert.equal response.status, 200

  context.test "A GET that receives a redirect (302)", (context) ->
    options =
      url: "#{base}/302"
      method: "GET"
    request options, (error, response) ->
      context.test "Transparent redirect", ->
        assert.ifError error
        assert.equal response.status, 200

  context.test "Request with timeout", (context) ->
    options =
      url: "#{base}/timeout"
      method: "GET"
      timeout: 200
    request options, (error, response) ->
      context.test "produces appropriate error", ->
        assert.ok error

  ## TODO: get support for encodings into Rephraser
  #context.test "Request with Accept-Encoding 'gzip'", (context) ->
    #options =
      #url: "http://localhost:1979/"
      #method: "GET"
      #headers:
        #"Accept": "application/json"
        #"Accept-Encoding": "gzip"
    #request options, (error, response) ->
      #context.test "Successful request", ->
        #assert.ifError error
        #assert.equal response.status, 200
      #context.test "decodes", ->
        #assert.ok response.content.buffer
        #assert.ok response.content.body
        #assert.ok response.content.data
        #assert.equal response.content.data.constructor, Object




