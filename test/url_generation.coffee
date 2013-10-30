assert = require "assert"
Testify = require "testify"

Client = require "../src/client"

{api} = require "./helpers"
client = new Client(api)


Testify.test "URL generation", (context) ->

  context.test "mapping.url and mapping.query", ->
    mapping =
      url: "http://dwarf.com/foo"
      query:
        thing: {}

    url = client.generate_url mapping,
      thing: "ax"
    assert.equal url, "http://dwarf.com/foo?thing=ax"

  context.test "mapping.path", ->
    url = client.generate_url {path: "/foo"}, {}
    assert.equal url, "http://smurf.com/foo"

  context.test "mapping.path and mapping.query", ->
    mapping =
      path: "/cows"
      query:
        color: {}
        limit: {}

    url = client.generate_url mapping,
      limit: 34
      color: "brown"
    assert.equal url, "http://smurf.com/cows?color=brown&limit=34"

  context.test "mapping.template", ->
    mapping =
      template: "/user/:login/repo/:repo"

    url = client.generate_url mapping,
      repo: "testify"
      login: "automatthew"
    assert.equal url, "http://smurf.com/user/automatthew/repo/testify"

  context.test "mapping.template", ->
    mapping =
      template: "/user/:login/repo/:repo"
      query:
        color: {}

    url = client.generate_url mapping,
      repo: "testify"
      login: "automatthew"
      color: "blue"
    assert.equal url, "http://smurf.com/user/automatthew/repo/testify?color=blue"


