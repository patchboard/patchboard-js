assert = require "assert"
Testify = require "testify"

Client = require "../client"

{api} = require "./helpers"
client = new Client(api)

{resources} = client

user = resources.authenticated_user
console.log user.resource_type, user.url

user = resources.user(login: "dyoder")
console.log user.resource_type, user.url


org_search = resources.org_search(limit: 12, offset: 25)
console.log org_search.resource_type, org_search.url

org_search = resources.org_search()
console.log org_search.resource_type, org_search.url




#org_search = client.create "org_search", limit: 12, offset: 25
#puts org_search.url
#org_list.get (error, response) ->

#orgs = resources.orgs
#orgs.create input, (error, response) ->



