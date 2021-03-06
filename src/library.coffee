
fs = require 'fs'
path = require 'path'
debug = require('debug')('msgflo:library')
EventEmitter = require('events').EventEmitter

common = require './common'

defaultHandlers =
  ".yml":     "msgflo-register-foreign --role #ROLE #FILENAME"
  ".js":      "msgflo-nodejs --name #ROLE #FILENAME"
  ".coffee":  "msgflo-nodejs --name #ROLE #FILENAME"
  ".py":  "msgflo-python #FILENAME #ROLE"
  ".json":    "noflo-runtime-msgflo --name #ROLE --graph #COMPONENT --iips #IIPS"
  ".fbp":     "noflo-runtime-msgflo --name #ROLE --graph #COMPONENT --iips #IIPS"

languageExtensions =
  'python': 'py'
  'coffeescript': 'coffee'
  'javascript': 'js'
  'yaml': 'yml'
extensionToLanguage = {}
for lang, ext of languageExtensions
  extensionToLanguage[ext] = lang

replaceMarker = (str, marker, value) ->
  marker = '#'+marker.toUpperCase()
  str.replace(new RegExp(marker,  'g'), value)

exports.replaceVariables = replaceVariables = (str, variables) ->
  for marker, value of variables
    str = replaceMarker str, marker, value
  return str

baseComponentCommand = (config, component, cmd, filename) ->
  variables = common.clone config.variables
  componentName = component.split('/')[1]
  componentName = component if not componentName
  variables['FILENAME'] = filename if filename
  variables['COMPONENTNAME'] = componentName
  variables['COMPONENT'] = component
  return replaceVariables cmd, variables

componentCommandForFile = (config, filename) ->
  ext = path.extname filename
  component = path.basename filename, ext
  cmd = config.handlers[ext]
  return baseComponentCommand config, component, cmd, filename

componentsFromConfig = (config) ->
  components = {}
  for component, cmd of config.components
    components[component] =
      language: null # XXX: Could try to guess from cmd/template??
      command: baseComponentCommand config, component, cmd
  return components

componentsFromDirectory = (directory, config, callback) ->
  components = {}
  extensions = Object.keys config.handlers
  fs.exists directory, (exists) ->
    return callback null, {} if not exists

    fs.readdir directory, (err, filenames) ->
      return callback err if err
      supported = filenames.filter (f) -> path.extname(f) in extensions
      unsupported = filenames.filter (f) -> not (path.extname(f) in extensions)
      debug 'unsupported component files', unsupported if unsupported.length
      for filename in supported
        ext = path.extname filename
        lang = extensionToLanguage[ext]
        component = path.basename(filename, ext)
        debug 'loading component from file', filename, component
        filepath = path.join directory, filename
        components[component] =
          language: lang
          command: componentCommandForFile config, filepath

      return callback null, components

normalizeConfig = (config) ->
  config = {} if not config
  config = config.msgflo if config.msgflo # Migth be under a .msgflo key, for instance in package.json

  config.components = {} if not config.components
  config.variables = {} if not config.variables
  config.handlers = {} if not config.handlers

  for k, v of defaultHandlers
    config.handlers[k] = defaultHandlers[k] if not config.handlers[k]

  return config

class Library extends EventEmitter
  constructor: (options) ->
    options.config = JSON.parse(fs.readFileSync options.configfile, 'utf-8') if options.configfile
    options.componentdir = 'participants' if not options.componentdir
    options.config = normalizeConfig options.config
    @options = options

    @components = {} # "name" -> { command: "", language: ''|null }.  lazy-loaded using load()

  _updateComponents: (components) ->
    names = Object.keys components
    for name, comp of components
      if not comp
        # removed
        @components[name] = null
      else if not @components[name]
        # added
        @components[name] = comp
      else
        # update
        for k, v of comp
          @components[name][k] = v

    @emit 'components-changed', names, @components

  load: (callback) ->
    componentsFromDirectory @options.componentdir, @options.config, (err, components) =>
      return callback err if err
      @_updateComponents components
      @_updateComponents componentsFromConfig(@options.config)
      return callback null

  # call when MsgFlo discovery message has come in
  _updateDefinition: (name, def) ->
    return if not def # Ignore participants being removed
    changes = {}
    changes[name] =
      definition: def
    @_updateComponents changes

  getSource: (name, callback) ->
    debug 'requesting component source', name
    name = path.basename name # TODO: support multiple libraries?
    return callback new Error "Component not found for #{name}" if not @components[name]?
    lang = @components[name].language
    ext = languageExtensions[lang]
    filename = path.join @options.componentdir, "#{name}.#{ext}"
    fs.readFile filename, 'utf-8', (err, code) ->
      debug 'component source file', filename, lang, err
      return callback new Error "Could not find component source for #{name}" if err
      source =
        language: 'coffeescript' # FIXME don't hardcode
        code: code
      return callback null, source

  addComponent: (name, language, code, callback) ->
    debug 'adding component', name, language
    ext = languageExtensions[language]
    ext = ext or language  # default to input lang for open-ended extensibility
    name = path.basename name # TODO: support multiple libraries?
    filename = path.join @options.componentdir, "#{name}.#{ext}"

    fs.writeFile filename, code, (err) =>
      return callback err if err
      changes = {}
      changes[name] =
        language: language
        command: componentCommandForFile @options.config, filename
      @_updateComponents changes
      return callback null

  componentCommand: (component, role, iips={}) ->
    cmd = @components[component]?.command
    componentName = path.basename component
    cmd = @components[componentName]?.command if not cmd
    throw new Error "No component #{component} defined for role #{role}" if not cmd

    vars =
      'ROLE': role
      'IIPS': "'#{JSON.stringify(iips)}'"
    cmd = replaceVariables cmd, vars
    return cmd

exports.Library = Library
