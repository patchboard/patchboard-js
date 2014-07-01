assert = require "assert"
Testify = require "testify"

{api, Client} = require "../helpers"

client = new Client(api)

schema = client.api.schema_manager.find "urn:gh-knockoff#repository"

data =
  name: "jsck"
  url: "http://gh-knockoff.com/repos/automatthew/jsck"
  # for testing a resource as a top level property
  login: "automatthew"
  owner:
    url: "http://gh-knockoff.com/user/automatthew"
    login: "automatthew"
    email: "automatthew@mail.com"
  # for testing a sub-object with resources as defined properties
  refs:
    main:
      name: "master"
      commit: "6ed180cc0"
      message: "some new stuff"
    # for testing dictionaries
    branches:
      master:
        name: "master"
        commit: "6ed180cc0"
        message: "some new stuff"
      release:
        name: "release"
        commit: "dbc63b011"
        message: "some new stuff"
    # for testing resources in an array
    tags: [
      {
        name: "0.5.0"
        commit: "3bcab91f3"
        message: "some stuff"
      }
    ]

repo = client.api.decorate schema, data
#require("fs").writeFileSync("dectest.json", JSON.stringify(data, null, 2)

assert_properties = (object, names) ->
  for name in names
    assert.ok object[name]

assert_resource = (object) ->
  assert.ok object.constructor != Object

assert_actions = (object, names) ->
  for name in names
    assert.equal typeof(object[name]), "function"

# TODO: see if JSV is a better solution for verifying we aren't destroying
# data, as we are using a JSON schema after all.

Testify.test "Resource decoration", (context) ->

  context.test "Main object", (context) ->
    context.test "has correct properties", ->
      assert_properties repo, ["name", "owner", "refs"]

    context.test "has correct constructor", ->
      assert_resource repo
      assert.equal repo.resource_type, "repository"

    context.test "has expected action methods", ->
      assert_actions repo, ["get", "update", "delete"]

  context.test "An object as top level property", (context) ->
    object = repo.owner
    context.test "has correct properties", ->
      assert_properties object, ["login", "email"]
    context.test "has correct constructor", ->
      assert_resource object
      assert.equal object.resource_type, "user"
    context.test "has expected action methods", ->
      assert_actions object, ["get", "update"]

  context.test "Items in array", (context) ->
    array = repo.refs.tags
    context.test "have correct properties", ->
      for item in array
        assert_properties item, ["name", "commit", "message"]
    context.test "have correct constructor", ->
      for item in array
        assert_resource item
        assert.equal item.resource_type, "tag"
    context.test "have expected action methods", ->
      for item in array
        assert_actions item, ["get", "delete"]

  context.test "Resources in a dictionary", (context) ->
    dict = repo.refs.branches
    context.test "have correct properties", ->
      assert.ok dict.master
      assert.ok dict.release
      for name, branch of dict
        assert_properties branch, ["name", "commit", "message"]
    context.test "have correct constructor", ->
      for name, project of repo.projects
        assert_resource project
    context.test "have expected action methods", ->
      for name, project of repo.projects
        assert_actions project, ["get", "update", "delete"]



