# Set some globally accessible properties
properties =
	namespace: 'snakes'
	public_canvas: 'public'

# Internal variables
canvases = {}               # Canvas storage
canvasLifetime = 15*60*1000 # Delete canvases after 15 minutes
cleanupInterval = 15*1000   # Run cleanup operation every 15 seconds
nsio = null                 # Store the namespace-restricted sockets
_ = null 					# Underscore reference

# Experiment initialization
module.exports = (input) -> 
	properties.namespace = input.namespace               # Merge passed properties with built-in properties
	nsio = input.socketio.of "/#{properties.namespace}"  # Cache the namespaced IO
	nsio.on 'connection', userJoin                       # Run userJoin on every connection
	setInterval cleanup, cleanupInterval                 # Run the cleanup operation every interval
	canvases[properties.public_canvas] = new canvas()    # Prepare the public canvas automatically
	properties.canvases = canvases
	
	# Configure routes
	input.app.get "/#{properties.namespace}/#{key}", route for key, route of routes

	_ = input.underscore
	# Return the namespace for use elsewhere
	properties

# Define routing information
routes = 
	':gameid?' : (req, res) ->
		options = 
			title : 'Snakes'
			css : ['canvas.css']
			js : ['processing-api.js', 'snakes.js', '/socket.io/socket.io.js']
			canvasID : req.params.gameid or properties.public_canvas
			newCanvasID : newCanvasID(8)
			
		options.isPublicCanvas = (options.canvasID is properties.public_canvas)
		
		res.render 'snakes', options

# Initialize a canvas
canvas = ->
	@players = {}
	@strokes = []
	@messages = []
	@sockets = {}
	@expires = 0
	
	# Prepare coordinate logs for brushes
	@coord_log = {}	
	
	@clientCount = ->
		size = 0
		size += 1 for socket of @sockets
		size
	
	@broadcast = (message, payload) ->
		for socketid, socket of @sockets
			socket.emit(message, payload)
	
	return this

# Define a cleanup function to be run periodically
cleanup = ->
	for key, canvas of canvases
		if key is properties.public_canvas
			# If this is the public canvas and has a passed expiry date
			if canvas.expires isnt 0 and canvas.expires <= Date.now()
				# Remove the expiry date - wait for first action to start countdown
				canvas.expires = 0
				# Reset stroke history
				canvas.strokes = []
				canvas.strokes.length = 0
				# Broadcast the new blank history to all connected clients
				canvas.broadcast 'stroke_history', canvas.strokes
		else
			# If this is a private canvas, we assume there is nobody here
			# and delete the canvas outright
			delete canvas if canvas.expires isnt 0 and canvas.expires <= Date.now()
	
	# Broadcast the progression through the public canvas life, as a fraction in [0,1]
	c = canvases[properties.public_canvas]
	c.broadcast 'canvas_ttl', if c.expires is 0 then 0 else (Date.now() + canvasLifetime - c.expires) / canvasLifetime

# Define actions to be run when a user connects
userJoin = (socket) ->
	# Grab the session data
	session = socket.handshake.readOnlySession

	# Don't do anything on client connect, wait for a "canvas connect" message
	socket.on 'canvas_join', (canvasID) -> 
	
		# Create the canvas if it doesn't alrerady exist
		canvases[canvasID] ?= new canvas()
		
		# Add this socket to the list held by the canvas
		c = canvases[canvasID]
		c.sockets[socket.id] = socket
		
		# If this is the public canvas and it has no expiry date, set one now
		if canvasID is properties.public_canvas and c.expires is 0
			c.expires = Date.now() + canvasLifetime
		else if canvasID isnt properties.public_canvas and c.expires isnt 0
			c.expires = 0
		
		# Send the stroke history and chat history to the client
		#socket.emit 'stroke_history', c.strokes
		socket.emit 'chat_history', c.messages
		# Send the client count to all sockets connected to the canvas
		c.broadcast 'client_count', c.clientCount()
		
		# If we're on the public canvas, send the expiry time now rather
		# than waiting for the next TTL heartbeat
		if canvasID is properties.public_canvas and c.expires isnt 0
			socket.emit 'canvas_ttl', (Date.now() + canvasLifetime - c.expires) / canvasLifetime
		
		# Listen for messages received from the client, and send to everyone
		socket.on 'chat_sent', (message) ->
			# Only send if the session has a valid username
			if session.identity.username?
				message =
					user : session.identity.username
					message: message
					time: Date.now()
				
				# Broadcast the message
				c.broadcast 'chat_received', message
				# Add the message to the canvas history
				c.messages.push message
				# Only maintain the 20 latest messages
				c.messages.shift() while c.messages.length > 20

		# Listen for messages received from the client, and send to everyone
		socket.on 'move_sent', (moveData) ->		
			id = socket.id
			moveData.id = id
			player = c.players[id]

			player.direction = moveData.dir
			player.tail.push {x: moveData.x, y: moveData.y}
			# Broadcast the message
			c.broadcast 'move_received', moveData
		
		# Listen for disconnection and remove socket from canvas
		socket.on 'disconnect', ->
			delete c.sockets[socket.id]
			delete c.players[socket.id]
			
			c.broadcast 'player_left', socket.id

			# Tell all connected sockets about the updated client count
			c.broadcast 'client_count', c.clientCount() # TODO: This is redundant

			# If we're on a private canvas and there's nobody left,
			# set an expiry time for the cleanup function to monitor
			c.expires = Date.now() + canvasLifetime if c.clientCount() < 1 and canvasID isnt properties.public_canvas
			
		# Listen for strokes being sent from the client
		socket.on 'transmit_stroke', (stroke) ->
			
			# Sanitize the strokes sent from the client and ensure
			# they are well-formed
			#stroke = saneStroke stroke
			return false if stroke is false
			
			# Add the stroke to the canvas, and rebroadcast to
			# everybody except the source client
			c.strokes.push stroke
			for socketid, s of c.sockets when s isnt socket
				s.emit 'receive_stroke', stroke
			
			# If this is the public canvas and it has no expiry date, 
			# set one now
			if canvasID is properties.public_canvas and c.expires is 0
				c.expires = Date.now() + canvasLifetime

		# Player dies
		socket.on 'player_collided', (collidedData) ->
			player = c.players[socket.id]

			collidedData.id = player.id
			# Broadcast the message
			c.broadcast 'player_died', collidedData

			setTimeout (() =>
				# respawn the player
				player.x = 50 + Math.floor(Math.random() * (620 - 100))
				player.y = 50 + Math.floor(Math.random() * (485 - 100))
				player.direction =  0
				player.tail = []

				c.broadcast 'player_spawned', player), 5000

		# Player responds to synch. request
		socket.on 'synch_response', (playerData) ->
			player = c.players[socket.id]
			player.x = playerData.x
			player.y = playerData.y
			# Broadcast the message
			c.broadcast 'player_synch', 
				id: socket.id
				x: playerData.x
				y: playerData.y

		player = 
			id: socket.id
			name: _.uniqueId 'Anonymous '
			color: 
				red: 	55 + Math.floor(Math.random() * 200)
				green: 	55 + Math.floor(Math.random() * 200)
				blue: 	55 + Math.floor(Math.random() * 200)
			x: 50 + Math.floor(Math.random() * (620 - 100))
			y: 50 + Math.floor(Math.random() * (485 - 100))
			direction: 0
			tail: []
			score: 0

		# get the the players positions from the clients
		c.broadcast 'synch_request'

		# tell the new player all the existing player data
		socket.emit 'player_joined', c.players[p] for p of c.players

		# add the new player to the canvas
		c.players[player.id] = player

		# tell everybody that the new player joined
		c.broadcast 'player_joined', player

		# tell the new player his player ID and that he is ready
		socket.emit 'you_are_ready', player.id

		synchPlayer = ->
			socket.emit 'synch_request'
			setTimeout synchPlayer, 5000 # synch every five seconds
		
		setTimeout synchPlayer, 5000 # set initial synch after five seconds


# Generate random strings for creating new canvases
newCanvasID = (length) ->
	text = ''
	possible = 'abcdefghijkmnpqrstuvxyz0123456789'
	for i in [1..length]
		text += (possible.charAt Math.floor Math.random() * possible.length)
	text
