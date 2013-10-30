assert = require "assert"
Testify = require "testify"

Client = require "../src/client"

{api} = require "./helpers"
client = new Client(api)

{resources} = client

Testify.test "Resource construction", (context) ->

  context.test "From the directory", (context) ->

    context.test "mapping contains URL", ->
      user = resources.authenticated_user
      assert.equal user.resource_type, "user"
      assert.equal user.url, "http://smurf.com/user"

    context.test "mapping requires path params", ->
      user = resources.user(login: "dyoder")
      assert.equal user.resource_type, "user"
      assert.equal user.url, "http://smurf.com/user/dyoder"

    context.test "mapping requires query params", ->
      user = resources.user_search(match: "dyoder")
      assert.equal user.resource_type, "user_search"
      assert.equal user.url, "http://smurf.com/user?match=dyoder"






