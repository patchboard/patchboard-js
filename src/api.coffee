SchemaManager = require("./schema_manager")

module.exports = class API

  constructor: ({@service_url, mappings, @resources, @schemas}) ->
    if !(mappings && @resources && @schemas)
      throw new Error("API specification must provide mappings, resources, and schemas")

    @mappings = {}
    for name, mapping of mappings
      @mappings[name] = new Mapping(@, mapping)

    for name, definition of @resources
      definition.name = name

    @schema_manager = new SchemaManager(@schemas...)


  decorate: (context, schema, data) ->
    # Determine the resource by following the schema "name" to the mappings,
    # which define the resource names.
    if (name = schema.id?.split("#")[1])?
      if (mapping = @mappings[name])?
        constructor = mapping.constructor
        _data = data
        if mapping.query?
          # Some resources require query parameters to instantiate.
          # For these, we've stuck the query definition onto the
          # constructor.  For these cases, we substitute a simple
          # function for the property.
          # In usage, this looks like:
          #   user.repository(name: "patchboard").update(content, callback)
          data = (params) ->
            if _data.url?
              params.url = _data.url
            new constructor context, {url: mapping.generate_url(params)}

        else
          data = new constructor context, _data
    return @_decorate(context, schema, data) || data


  _decorate: (context, schema, data) ->
    if !schema? || !data?
      return
    if ref = schema.$ref
      if (schema = @schema_manager.find(ref))?
        @decorate(context, schema, data)
      else
        console.error "Can't find ref:", ref
        data
    else
      if schema.type == "array"
        if schema.items?
          for item, i in data
            if (result = @decorate(context, schema.items, item))?
              data[i] = result
      else
        switch schema.type
          when "string", "number", "integer", "boolean"
            null
          else
            # Declared properties
            for key, value of schema.properties
              if (result = @decorate(context, value, data[key]))?
                data[key] = result
            # Default for undeclared properties
            if addprop = schema.additionalProperties
              for key, value of data
                unless schema.properties?[key]
                  data[key] = @decorate(context, addprop, value)
            return data




API.Mapping = class Mapping
  constructor: (api, {@name, @resource, @url, @template, @path, @query}) ->
    {@service_url} = api
    if !@resource?
      @resource = @name
    if !(@url? || @path? || @template?)
      throw new Error "Mapping is missing any form of URL specification"
    if !(resource = api.resources[@resource])?
      throw new Error "Mapping specifies a resource that is not defined"
    @resource = resource

  generate_url: (params={}) ->
    url = @service_url
    path = ""
    if params.constructor == String
      url = params
    else if params.url
      url = params.url
    else if @url?
      url = @url
    else if (template = @template)?
      # this should never be needed when the API is served by a
      # Patchboard Server.  Including it for client-side only
      # uses, such as the GitHub API.
      parts = template.split("/")
      out = []
      for part in parts
        if part.indexOf(":") == 0
          key = part.slice(1)
          if (string = params[key])?
            out.push(string)
          else
            throw new Error(
              "Missing key: '#{key}' in params: #{JSON.stringify(params)}"
            )
        else
          out.push(part)
      url = url + out.join("/")
    else if @path?
      # Ditto above comment.
      path = @path
    else
      throw new Error """
        Unusable URL mapping.  Must have url, path, or template field.
        Mapping: #{JSON.stringify(@, null, 2)}
      """

    query_string = ""
    if (query = @query)?
      parts = []
      keys = Object.keys(query).sort()
      for key in keys
        schema = query[key]
        if (string = params[key])?
          parts.push "#{encodeURIComponent(key)}=#{encodeURIComponent(string)}"
      if parts.length > 0
        query_string = "?#{parts.join('&')}"
      else
        query_string = ""

    encodeURI(url + path) + query_string
