
# Implementation of the FBP protocol
# http://noflojs.org/documentation/protocol

debug = require('debug')('msgflo:fbp')
EventEmitter = require('events').EventEmitter

fbpPort = (port) ->
  m =
    id: port.id
    type: port.type or "any"
    description: port.description or ""
    addressable: false
    required: false # TODO: implement
  return m

fbpComponentFromMsgflo = (name, component) ->
  if component.definition
    # full info available
    info =
      name: name
      description: component.label or component.cmd or ""
      icon: component.definition.icon
      subgraph: false
      inPorts: component.definition.inports.map fbpPort
      outPorts: component.definition.outports.map fbpPort
  else
    # just inifial info
    info =
      name: name
      description: component.cmd
      icon: null
      subgraph: false
      inPorts: []
      outPorts: []

  return info

# JSON serialization of Error objects is empty
serializeErr = (err) ->
  return { message: err.message }

handleMessage = (proto, sub, cmd, payload, ctx) ->
  debug 'RECV:', sub, cmd, payload

  defaultGraph = 'default/main'

  if sub == 'runtime' and cmd == 'getruntime'
    runtime =
      type: 'msgflo'
      version: '0.4'
      capabilities: [
        'protocol:component'
        'protocol:graph'
        'protocol:network'
        'component:getsource'
        'component:setsource'
      ]
      graph: defaultGraph
    proto.transport.send 'runtime', 'runtime', runtime, ctx

  else if sub == 'runtime' and cmd == 'packet'
    proto.coordinator.sendToExportedPort payload.port, payload.payload, (err) ->
      return proto.transport.send 'runtime', 'error', serializeErr(err), ctx if err
      # No ACK in this case apparently, as it is interpreted as output

  # Component
  else if sub == 'component' and cmd == 'list'


    debug 'attempting to list components'
    components = []
    for name, component of proto.coordinator.library.components
      info = fbpComponentFromMsgflo name, component
      components.push info

    for info in components
      proto.transport.send 'component', 'component', info, ctx
    proto.transport.send 'component', 'componentsready', components.length, ctx
    debug 'sent components', components.length

  else if sub == 'component' and cmd == 'getsource'

    sendMainGraphSource = () ->
      graph = proto.coordinator.serializeGraph 'main'
      resp =
        code: JSON.stringify graph
        name: 'main'
        library: 'default'
        language: 'json'
      proto.transport.send 'component', 'source', resp, ctx
    if payload.name == defaultGraph
      # Main graph. Ref https://github.com/noflo/noflo-ui/issues/390
      setTimeout sendMainGraphSource, 0
    else
      # Regular component
      proto.coordinator.getComponentSource payload.name, (err, source) ->
        if err
          # return empty component response, as clients handle errors badly...
          source =
            language: 'javascript'
            code: ""
          proto.transport.send 'component', 'error', { name: payload.name, error: err.message }, ctx
        source.name = payload.name
        proto.transport.send 'component', 'source', source, ctx

  else if sub == 'component' and cmd == 'source'
    p = payload
    proto.coordinator.addComponent p.name, p.language, p.code, (err) ->
      return proto.transport.send 'component', 'error', err, ctx if err
      return proto.transport.sendAll 'component', 'source', payload

  # Network
  else if sub == 'network' and cmd == 'start'
    proto.coordinator.startNetwork payload.graph, (err) ->
      return proto.transport.sendAll 'network', 'error', err if err
      proto.transport.sendAll 'network', 'started',
        running: true
        started: true
        graph: payload.graph
        time: new Date()

  else if sub == 'network' and cmd == 'stop'
    proto.coordinator.stopNetwork payload.graph, (err) ->
      return proto.transport.sendAll 'network', 'error', err if err
      proto.transport.sendAll 'network', 'stopped',
        running: false
        started: true
        graph: payload.graph
        time: new Date()

  # Graph
  else if sub == 'graph'
    handleGraphMessage proto, cmd, payload, ctx

  else
    debug 'Unhandled FBP protocol message: ', sub, cmd


handleGraphMessage = (proto, cmd, payload, ctx) ->
  graph = payload.graph

  if cmd == 'clear'
    # FIXME: support multiple graphs
  else if cmd == 'addnode'
    proto.coordinator.startParticipant payload.id, payload.component, (err) ->
      return proto.transport.send 'graph', 'error', serializeErr(err), ctx if err
      proto.transport.sendAll 'graph', 'addnode', payload
  else if cmd == 'removenode'
    proto.coordinator.stopParticipant payload.id, payload.component, (err) ->
      return proto.transport.send 'graph', 'error', serializeErr(err), ctx if err
      proto.transport.sendAll 'graph', 'removenode', payload

  # Connections
  else if cmd == 'addedge'
    debug 'addedge', payload
    p = payload
    proto.coordinator.connect p.src.node, p.src.port, p.tgt.node, p.tgt.port, (err) ->
      return proto.transport.send 'graph', 'error', serializeErr(err), ctx if err
      proto.transport.sendAll 'graph', 'addedge', payload
  else if cmd == 'removeedge'
    p = payload
    proto.coordinator.disconnect p.src.node, p.src.port, p.tgt.node, p.tgt.port, (err) ->
      return proto.transport.send 'graph', 'error', serializeErr(err), ctx if err
      proto.transport.sendAll 'graph', 'removeedge', payload

  # IIPs
  else if cmd == 'addinitial'
    proto.coordinator.addInitial payload.tgt.node, payload.tgt.port, payload.src.data
    proto.transport.sendAll 'graph', 'addinitial', payload
  else if cmd == 'removeinitial'
    proto.coordinator.removeInitial payload.tgt.node, payload.tgt.port
    proto.transport.sendAll 'graph', 'removeinitial', payload

  # exported ports
  else if cmd == 'addinport'
    proto.coordinator.exportPort 'inport', payload.public, payload.node, payload.port, (err) ->
      return proto.transport.send 'graph', 'error', serializeErr(err), ctx if err
      proto.transport.sendAll 'graph', 'addinport', payload
  else if cmd == 'addoutport'
    proto.coordinator.exportPort 'outport', payload.public, payload.node, payload.port, (err) ->
      return proto.transport.send 'graph', 'error', serializeErr(err), ctx if err
      proto.transport.sendAll 'graph', 'addoutport', payload

  else
    debug 'Unhandled FBP protocol message: ', 'graph', cmd

class Protocol
  constructor: (@transport, @coordinator) ->
    throw Error 'Protocol' if not @coordinator

    @coordinator.on 'exported-port-data', (port, data, graph) =>
      @transport.sendAll 'runtime', 'packet',
        port: port
        event: 'data'
        payload: data
        graph: graph

    @transport.on 'message', (protocol, command, payload, ctx) =>
      handleMessage @, protocol, command, payload, ctx

    @coordinator.library.on 'components-changed', (names, allComponents) =>
      debug 'components-changed', names
      for name in names
        component = allComponents[name]
        info = fbpComponentFromMsgflo name, component
        @transport.sendAll 'component', 'component', info

    @coordinator.on 'data', (from, fromPort, to, toPort, data) =>
      debug 'on data', from, fromPort, data

      id = "#{from}() #{fromPort.toUpperCase()} -> #{toPort.toUpperCase()} #{to}()"
      msg =
        id: id # FIXME: https://github.com/noflo/noflo-ui/issues/293
        graph: 'default/main' # FIXME: unhardcode
        src:
          node: from
          port: fromPort
        tgt:
          node: to
          port: toPort
        data: data
      @transport.sendAll 'network', 'data', msg

exports.Protocol = Protocol
