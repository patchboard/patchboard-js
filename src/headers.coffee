
www_auth_regex = ///
  # keys are not quoted
  ([^\s,]+)
  =
  # value might be quoted
  "?
    # the value currently may not contain whitespace
    ([^\s,"]+)
  "?

///

parse_www_auth = (string) ->

  arrays = []
  current = null

  tokens = string.split(" ")

  for token in tokens
    if token.indexOf("=") != -1
      current.push token
    else
      current = [token]
      arrays.push current


  challenges = {}
  for challenge in arrays
    [name, pairs...] = challenge

    if pairs.length == 0
      throw new Error "Invalid WWW-Authenticate header"

    params = challenges[name] = {}

    for pair in pairs
      match = www_auth_regex.exec(pair)
      if match?
        [full, key, value] = match
        params[key] = value
      else
        throw new Error "Invalid WWW-Authenticate header"

  return challenges


module.exports = {
  parse_www_auth
}


