
runtime = require './runtime'
common = require './common'

## Main
program = require 'commander'

collectArray = (val, list) ->
  list.push val
  return list

main = () ->
  program
    .option('--host <hostname>', 'Host', String, 'localhost')
    .option('--port <port>', 'Port', Number, 3569)
    .option('--broker <uri>', 'Broker address', String, '')
    .option('--ide <uri>', 'FBP IDE address', String, 'http://app.flowhub.io')
    .option('--library <FILE.json>', 'Library configuration file', String, 'package.json')
    .option('--graph <file.json>', 'Initial graph to load', String, '')
    .option('--ignore [process]', "Don't set up these processes", collectArray, [])
    .option('--forward stderr,stdout', "Forward these streams from child", String, 'stderr,stdout')
    .option('--auto-save [true|false]', "Autosave changes to graph", Boolean, false)
    .parse(process.argv)

  options = common.normalizeOptions program
  r = new runtime.Runtime options
  r.start (err, address, liveUrl) ->
    throw err if err
    console.log "msgflo started on #{address}"
    console.log 'Open in Flowhub: ' + liveUrl

exports.main = main
exports.transport = require('msgflo-nodejs').transport
exports.participant = require('msgflo-nodejs').participant
exports.foreignParticipant = require '../src/foreign-participant'

exports.coordinator = require '../src/coordinator'
exports.runtime = require '../src/runtime'
exports.common = require '../src/common'
exports.setup = require '../src/setup'
exports.library = require '../src/library'
exports.procfile = require '../src/procfile'
exports.utils =
  spy: require '../src/utils/spy'
