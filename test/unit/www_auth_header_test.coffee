
assert = require "assert"
Testify = require "testify"

{parse_www_auth} = require "../../src/headers"

Testify.test "Parsing WWW-Authenticate headers", (context) ->

  context.test "valid", (context) ->

    context.test "single challenge, single param", ->
      params = parse_www_auth 'Monkey name=Bongo'
      assert.deepEqual params,
        "Monkey":
          name: "Bongo"


    context.test "single challenge, multiple params", ->
      params = parse_www_auth 'Monkey name=Bongo, color=brown'
      assert.deepEqual params,
        "Monkey":
          name: "Bongo"
          color: "brown"

    context.test "quoted and unquoted param values", ->
      params = parse_www_auth 'Monkey name=Bongo, color="brown"'
      assert.deepEqual params,
        "Monkey":
          name: "Bongo"
          color: "brown"


    context.test "multiple challenges, multiple params", ->
      string = 'Monkey name=Bongo, color=brown, Leopard spots=many'
      params = parse_www_auth string
      assert.deepEqual params,
        "Monkey":
          name: "Bongo"
          color: "brown"
        "Leopard":
          spots: "many"


  context.test "invalid", (context) ->

    context.test "single challenge, no params", ->
      assert.throws ->
        string = "Monkey"
        params = parse_www_auth string

    context.test "single challenge, invalid params", ->
      assert.throws ->
        string = "Monkey foobar"
        params = parse_www_auth string

      assert.throws ->
        string = "Monkey foobar="
        params = parse_www_auth string

      assert.throws ->
        string = "Monkey =foobar"
        params = parse_www_auth string


    context.test "multiple challenges, one without params", ->
      assert.throws ->
        string = "Monkey foo=bar, Leopard"
        params = parse_www_auth string


    context.test "multiple challenges, invalid params", ->
      assert.throws ->
        parse_www_auth "Monkey foobar, Leopard bazbat"




