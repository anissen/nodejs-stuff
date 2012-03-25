# Set some globally accessible properties
properties =
	namespace: 'canvas'

# Internal variables
canvases = null           # Canvas data

# Experiment initialization
module.exports = (input) -> 
	properties.namespace = input.namespace               # Merge passed properties with built-in properties
	canvases = input.canvas.canvases
	
	# Configure routes
	input.app.get "/canvas-overview/", overviewRoute
	# Return the namespace for use elsewhere
	properties

# Define routing information
overviewRoute = (req, res) ->
	canvasData = []
	for key, canvas of canvases
		count = canvas.clientCount()
		strokeCount = canvas.strokes.length
		canvasData.push
			key: key
			count: count
			strokeCount: strokeCount

	options = 
		title : 'Canvas overview'
		css : ['canvas.css']
		js : []
		canvasData : canvasData
	
	res.render 'overview', options