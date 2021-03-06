program = require 'commander'
msgflo_nodejs = require 'msgflo-nodejs'
fs = require 'fs'
path = require 'path'
foreigner = require '../foreign-participant'
common = require '../common'
yaml = require 'js-yaml'

onError = (err) ->
  console.log err
  process.exit 1

onComplete = ->
  process.exit 0

main = ->
  program
    .option('--broker <uri>', 'Broker address', String, '')
    .option('--role <role>', 'Role of this instance', String, '')
    .option('--forever <true>', 'Keep running forever', Boolean, false)
    .usage('[options] <definition>')
    .parse(process.argv)
  program = common.normalizeOptions program

  defPath = path.resolve process.cwd(), program.args[0]
  fs.readFile defPath, 'utf-8', (err, contents) ->
    return onError err if err
    return onError "No definition found in #{defPath}" unless contents
    try
      definition = yaml.safeLoad contents
    catch e
      return onError e

    definition.role = program.role if program.role
    definition.role = path.basename defPath, path.extname defPath unless definition.role
    definition.id = definition.role if not definition.id

    definition = foreigner.mapPorts definition
    messaging = msgflo_nodejs.transport.getClient program.broker
    messaging.connect (err) ->
      return onError err if err
      foreigner.register messaging, definition, (err) ->
        return onError err if err

        if not program.forever
          onComplete()

exports.main = main
