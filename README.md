# Patchboard Client for JavaScript

## Usage


```coffee
Client = require "patchboard-js"

# Give Client.discover the URL to a Patchboard API server
Client.discover "http://api.wherever.com/", (client) ->
  {users} = client.resources
  users.create {login: "matthew"}, (error, response) ->
    if error
      console.error error
    else
      user.update {email: "matthew@mail.com}, (error, response) ->

```

