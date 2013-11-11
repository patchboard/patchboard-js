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
        assert.ok(!response.data.headers["Content-Type"])

      context.test "response.body", (context) ->
        context.test "is a String", ->
          assert.equal(response.body.constructor, String)

        context.test "has correct length", ->
          assert.equal response.headers["Content-Length"], response.body.length

      context.test "response.data is an Object", ->
        assert.equal(response.data.constructor, Object)


  context.test "A minimal valid POST request", (context) ->
    options =
      url: "#{base}/200"
      method: "POST"
    request options, (error, response) ->
      context.test "Successful", ->
        assert.ifError error
        assert.equal response.status, 200

      context.test "headers", ->
        assert.ok(!response.data.headers["Content-Type"])



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
        assert.equal response.data.headers["Content-Type"], "application/json"


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

  #context.test "Request with timeout set using an Integer", (context) ->

    #context.test "Only the timeout handler fires", (context) ->
      #shred.get
        #url: "#{base}/timeout"
        #timeout: 100
        #on:
          #request_error: (error) ->
            #context.fail "request_error handler fired"
          #error: (response) ->
            #context.fail "generic error handler fired"
          #response: (response) ->
            #context.fail "generic response handler fired"
          #timeout: ->
            #context.pass()


  ##context.test "Request with a timeout set using an object", (context) ->
    ##context.test "Only the timeout handler fires", (context) ->
      ##shred.get
        ##url: "#{base}/timeout"
        ##timeout: { seconds: 1 }
        ##on:
          ##request_error: (error) ->
            ##context.fail "request_error handler fired"
          ##error: (response) ->
            ##context.fail "generic error handler fired"
          ##response: (response) ->
            ##context.fail "generic response handler fired"
          ##timeout: ->
            ##context.pass()


  ##context.test "Request with Accept-Encoding 'gzip'", (context) ->
    ##shred.get
      ##url: "http://www.example.com/"
      ##headers:
        ##"Accept-Encoding": "gzip"
      ##on:
        ##request_error: request_error_handler
        ##error: http_error_handler(context)
        ##200: (response) ->
          ##context.test "has proper gzip data", ->
            ## TODO: this test doesn't appear to be really helpful
            ##assert.ok (response.content._body.toString().length > 0)




