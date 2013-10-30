JSCK = require "jsck"

module.exports = class SchemaManager

  constructor: (@schemas...) ->
    for schema in @schemas
      # `definitions` is the conventional place to put schemas,
      # so we'll define fragment IDs by default where they are
      # not explicitly specified.
      if definitions = schema.definitions
        for name, definition of definitions
          definition.id ||= "##{name}"

    @jsck = new JSCK.draft3 @schemas...
    @uris = @jsck.references

  find: (args...) ->
    @jsck.find(args...)

  #schema: (args...) ->
    #@jsck.validate(args...)

  #validate: (args...) ->
    #@jsck.validate(args...)


