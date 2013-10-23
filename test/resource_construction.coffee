assert = require "assert"
Testify = require "testify"

Client = require "../client"

{api} = require "./helpers"
client = new Client(api)

{resources} = client

Testify.test "Resource construction", (context) ->

  context.test "mapping contains URL", ->
    user = resources.authenticated_user
    assert.equal user.resource_type, "user"
    assert.equal user.url, "http://smurf.com/user"

  context.test "mapping requires path params", ->
    user = resources.user(login: "dyoder")
    assert.equal user.resource_type, "user"
    assert.equal user.url, "http://smurf.com/users/dyoder"

  context.test "mapping requires query params", ->
    user = resources.user_search(match: "dyoder")
    assert.equal user.resource_type, "user_search"
    assert.equal user.url, "http://smurf.com/users?match=dyoder"


#org_search = resources.org_search(limit: 12, offset: 25)
#console.log org_search.resource_type, org_search.url

#org_search = resources.org_search()
#console.log org_search.resource_type, org_search.url




#org_search = client.create "org_search", limit: 12, offset: 25
#puts org_search.url
#org_list.get (error, response) ->

#orgs = resources.orgs
#orgs.create input, (error, response) ->



