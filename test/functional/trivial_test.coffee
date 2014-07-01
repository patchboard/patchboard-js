Testify = require "testify"
assert = require "assert"

{Client} = require("../helpers")

Client.discover "http://localhost:1979/", (error, client) ->
  throw error if error
  {resources} = client

  Testify.test "Trivial API", (suite) ->

    suite.test "invalid content", (context) ->
      resources.users.create {name: "foo"}, (error) ->
        context.test "Expected error", ->
          assert.ok error
          assert.equal error.status, 400

    suite.test "abusive content", (context) ->
      resources.users.create {login: "__proto__"}, (error) ->
        context.test "Expected error", ->
          assert.ok error
          assert.equal error.status, 400

    create_test = suite.test "create a user", (context) ->

      login = new Buffer(Math.random().toString().slice(0, 6)).toString("hex")

      resources.users.create {login: login}, (error, user) ->
        context.test "Expected response", ->
          assert.ifError(error)

        context.test "has expected fields", ->
          assert.equal user.login, login
          assert.ok user.url
          assert.ok !user.email

        context.test "has expected subresources", ->
          assert.equal user.questions.constructor, Function
          context.result(user)

    create_test.on "done", (user) ->
      suite.test "searching for a user", (context) ->
        {login} = user
        resources.user_search(login: login).get (error, user) ->
          context.test "Expected response", ->
            assert.ifError(error)

          context.test "user is good", ->
            assert.equal user.resource_type, "user"

      question_test = suite.test "asking for a question", (context) ->
        user.questions(category: "Science").ask (error, question) ->

          context.test "Expected response", ->
            assert.ifError(error)

          context.test "question has expected fields", ->
            assert.ok question.url
            assert.ok question.question
            assert.ok "abcd".split("").every (item) ->
              question[item]

          context.result(question)

      question_test.on "done", (question) ->

        answer_test = suite.test "answering the question", (context) ->
          question.answer {letter: "d"}, (error, result) ->

            context.test "Expected response", ->
              assert.ifError(error)

            context.test "success", ->
              assert.equal result.success, true
              assert.equal result.correct, "d"

        answer_test.on "done", ->
          suite.test "attempting to answer again", (context) ->
            question.answer {letter: "d"}, (error) ->

              context.test "receive expected HTTP error", ->
                assert.ok error
                assert.equal error.status, 409
                data = JSON.parse error.response.body
                assert.equal data.reason,
                  "Question has already been answered"


