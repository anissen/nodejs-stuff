
// Some namespaced helper functions that do not require the page to be loaded
var canvasUtils = new function () {
	
	this.isCanvasSupported = function () {
		var e = document.createElement('canvas')
		return !!(e.getContext && e.getContext('2d'))
	}
	
	this.hex2rgba = function (hexString, alpha) {
		
		if(false === hexString.match(/^#[0-9A-Fa-f]{6}$/)) return false
		
		var values = []
		for(var i = 1; i <= 5; i += 2)
			values.push(parseInt(hexString.substr(i,2), 16))
		
		return (
			(alpha === undefined || alpha === null) 
			? "rgb(" + values.join() + ")"
			: "rgba(" + values.concat(alpha).join() + ")"
		)
	}
	
	var paintCoordinateLog = {}
	this.clearPaintLog = function () { paintCoordinateLog = {} }
	
	var addPaintLog = function (b, x, y) {
		if(paintCoordinateLog[b] === undefined) paintCoordinateLog[b] = []
		paintCoordinateLog[b].push([x,y])
	}
	
	this.paint = function (ctx, brush, coords) {
		
		// Check it's a valid brush and drop out immediately if not
		var currentBrushSpec = BRUSH_SPECS.brushes[brush.type]
		if(currentBrushSpec === undefined) return false
		
		// Prepare for drawing with some initializations
		ctx.save()
		ctx.beginPath()
		ctx.lineCap = "round"
		ctx.lineJoin = "round"
		
		switch(brush.type) {
			
			// The circular primitives
			case "paint":
			case "airbrush":
				if(coords.length === 2) coords[2] = 1.0
				if (coords.length !== 3) {
					console.error("Invalid coordinate data received")
					break
				}
				
				addPaintLog(brush.type, coords[0], coords[1])
				
				ctx.lineWidth = 0
				ctx.strokeStyle = "transparent"
				ctx.fillStyle = canvasUtils.hex2rgba(brush.color, coords[2])
				ctx.arc(coords[0], coords[1], brush.size / 2.0, 0, 2.0 * Math.PI, true)
				break
			
			// The pencils
			case "pencil":
				if(coords.length === 4) coords[4] = 1.0
				if(coords.length !== 5) {
					console.error("Invalid coordinate data received")
					break
				}
				
				addPaintLog(brush.type, coords[0], coords[1])
				
				ctx.lineWidth = 1
				ctx.strokeStyle = canvasUtils.hex2rgba(brush.color, coords[4])
				ctx.fillStyle = "transparent"
				ctx.moveTo(coords[0], coords[1])
				ctx.lineTo(coords[2], coords[3])
				break
		}
		
		// Complete the stroke and restore previous settings
		ctx.stroke()
		ctx.fill()
		ctx.restore()
	}
}

////////////////////////////////////////////////////////////////////////////////
// Now begins the jQuery section for things that are dependent on the DOM
////////////////////////////////////////////////////////////////////////////////

$(function () {

	// Quit immediately if canvas is not supported
	if(false === canvasUtils.isCanvasSupported()) {
		$("#canvas-unsupported").show()
		return
	}
	
	// Load handles for the main canvas and preview canvas
	var mainCanvas = {
		element: $('#canvas').get(0),
		context: $('#canvas').get(0).getContext('2d'),
		id:      $('#canvas').attr('data-canvas-id')
	}
	
	var previewCanvas = {
		element: $('#brush-preview').get(0),
		context: $('#brush-preview').get(0).getContext('2d')
	}
	
	////////////////////////////////////////////////////////////////////////////
	// Toolbox event handling and initializers
	////////////////////////////////////////////////////////////////////////////
	
	var previewCanvasRefresh = function () {
	
		// Clear the canvas
		previewCanvas.context.clearRect(0, 0, canvas.width, canvas.height)
		
		// Do not draw unless primitive
		var currentBrushSpec = BRUSH_SPECS.brushes[$('#brush-type').val()]
		if(currentBrushSpec.kind !== "primitive")
			return
		
		// Draw the brush in the center of the canvas
		canvasUtils.paint(previewCanvas.context, {
			color:  $('#color-choice').val(),
			size:   $('#brush-size-slider').slider("option", "value"),
			type:   $('#brush-type').val(),
		}, [previewCanvas.element.width / 2.0, previewCanvas.element.height / 2.0])
	}
	
	// Build jQuery controls
	$('#brush-size-slider').slider({ min: 3, max: 50, value: 10,range: 'min'})
	
	// Bind all relevant events to the brush preview refresher
	previewCanvasRefresh()
	$('#color-choice').miniColors({ 'change': previewCanvasRefresh })
	$('#brush-size-slider').bind("slide", function () { previewCanvasRefresh() })
	$('.brush-control').change(function () { previewCanvasRefresh() })
	
	// Show and hide some extra controls depending on brush choice
	var showHideCircularControls = function () {
		switch ($('#brush-type').val()) {
			case "paint":
			case "airbrush":
				$('#filled-circle-controls').slideDown('fast')
				break
			default:
				$('#filled-circle-controls').slideUp('fast')
				break
		}
	}
	$('#brush-type').change(showHideCircularControls).keypress(showHideCircularControls)
	
	// Bind an action to the "random color" button
	$("#color-random").click(function (event) {
		event.preventDefault()
		$('#color-choice').miniColors('value', '#' + Math.floor(Math.random() * 16777215).toString(16))
	})
	
	// Bind an action to the "share to imgur" button
	$('#share-to-imgur').click(function (event) {
	
		event.preventDefault()
		
		var label = $('#share-to-imgur-label')
		var previousLabel = label.text()
		label.text("Uploading...")
		
		$('#share-to-imgur-link')
			.hide()
			.removeClass('btn-danger')
			.removeClass('btn-success')
		
		$.ajax({
			url: 'http://api.imgur.com/2/upload.json',
			type: 'POST',
			dataType: 'json',
			data: {
				type: 'base64',
				key: '8ba822fb5788eca3d187b5505c2cce72',
				image: canvas.toDataURL().split(',')[1]
			}
		}).success(function (data) {
			label.text(previousLabel)
			$('#share-to-imgur-link')
				.addClass('btn-success')
				.text("Open")
				.attr("href", data['upload']['links']['original'])
				.show()
			
		}).error(function () {
			label.text(previousLabel)
			$('#share-to-imgur-link')
				.addClass('btn-danger')
				.text("Error")
				.attr("href", "#")
				.show()
		})
	})
	
	////////////////////////////////////////////////////////////////////////////
	// Socket communication event handlers and initialization
	////////////////////////////////////////////////////////////////////////////
	
	var socket = io.connect('/canvas')
	
	socket.on('connect', function (data) {
		$("#server-link-lost").stop(true).slideUp()
		socket.emit("canvas_join", mainCanvas.id)
	})	
	socket.on('disconnect', function(data) {
		$("#server-link-lost").delay(5000).slideDown()
	})
	
	socket.on('client_count', function (count) {
	
		var oc = $("#online-count")
		if(this.prev === undefined) this.prev = count
		if(this.orig === undefined) this.orig = oc.css('color')
		
		oc.text(count + (count == 1 ? " person" : " people") + " on this canvas")
		
		var color = this.orig
		if (count > this.prev) color = "#090"
		if (count < this.prev) color = "#C00"
		this.prev = count
		
		$("#online-count")
			.css('color', color)
			.animate({'color': this.orig}, {duration: 2000, queue: false})
	})
	
	socket.on('canvas_ttl', function (percentage) {
		$('#canvas-clear-progress').css({width: percentage * 100 + "%"})
		$('#canvas-clear-progress-style')
			.toggleClass('progress-info', (percentage < 0.8))
			.toggleClass('progress-warning', (percentage >= 0.8 && percentage < 0.95))
			.toggleClass('progress-danger', (percentage >= 0.95))
	})
	
	socket.on('stroke_history', function (strokeHistory) {
		// Reset the canvas with a big white rectangle
		mainCanvas.context.fillStyle = "#FFFFFF"
		mainCanvas.context.fillRect(0, 0, mainCanvas.element.width, mainCanvas.element.height)
		
		canvasUtils.clearPaintLog()
		for(var n in strokeHistory) renderStroke(strokeHistory[n])
		$("#canvas").removeClass("loading")
	})
	
	socket.on('receive_stroke', function (stroke) { renderStroke(stroke) })
	
	socket.on('chat_history', function (chatHistory) {
		for(var n in chatHistory)
			addChatMessage(chatHistory[n].user, chatHistory[n].message, chatHistory[n].time, false)
	})
	
	socket.on('chat_received', function (chat) { 
		addChatMessage(chat.user, chat.message, chat.time, false)
	})
	
	///////////////////////////////////////////////////////
	// Set up canvas interaction
	//
	
	var renderStroke = function(stroke) {
		for(var i = 0; i < stroke.coords.length; i++)
			canvasUtils.paint(mainCanvas.context, stroke.brush, stroke.coords[i])
	}
	
	var brushInterpreter = new function() {
	
		var previousPoint = []
		var strokeCache = []
		var brush       = null
		var strokeCount = 0
		var strokeBreak = 20
		
		var emitStroke = function(coord_array) {
			var transmit = {'brush': brush, 'coords': coord_array}
			socket.emit('transmit_stroke', transmit)
		}
		
		this.startStroke = function(b, x, y) {
			brush = b
			this.moveBrush(x, y)
		}
		
		this.moveBrush = function(x, y) {
			
			if(!brush) return false
			
			var currentBrushSpec = BRUSH_SPECS.brushes[brush.type]
			if(currentBrushSpec === undefined) return false
			
			switch(currentBrushSpec.kind) {
				
				// Primitive types
				case "primitive":
					var c = [x, y]
					if(brush.type == "airbrush") c.push(0.1)
					strokeCache.push(c)
					canvasUtils.paint(mainCanvas.context, brush, c)
					strokeCount += 1
					break
				
				// Line types
				case "line":
					if(previousPoint.length == 2) {
						var c = [previousPoint[0], previousPoint[1], x, y]
						strokeCache.push(c)
						canvasUtils.paint(mainCanvas.context, brush, c)
						strokeCount += 1
					}
					previousPoint = [x,y]
					break
					
				default:
					console.error("Unimplemented brush")
					break
			}
			
			if(strokeCount >= strokeBreak) {
				emitStroke(strokeCache.splice(0, strokeCache.length))
				strokeCount = 0
			}
		}
		
		this.finishStroke = function(retainMousedown) {
			
			if(!brush) return
			
			if(strokeCache.length > 0) emitStroke(strokeCache)
			previousPoint = []
			previousPoint.length = 0
			strokeCache = []
			strokeCache.length = 0
			
			if(retainMousedown !== true) brush = null
		}
	}
	
	/////////////////////////////////////////
	// Record mouse interactions with canvas
	
	// On mousedown, store the current brush and keep it untilwe mouseup
	$('#canvas').mousedown(function(e) {
	
		event.preventDefault()
		// Left mouse button only
		if(e.which != 1) return false
		// Wait for the loading screen to disappear
		if($("#canvas").hasClass("loading")) return false
		
		// Ensure we've pushed all details from any previous strokes
		brushInterpreter.finishStroke()
		
		// Set the brush properties
		var brush = {
			color: $('#color-choice').val(),
			size: $('#brush-size-slider').slider("option", "value"),
			type: $('#brush-type').val(),
		}
		
		// Notify the brush interpreter of the brush type and stroke starting position
		brushInterpreter.startStroke(brush, e.pageX - this.offsetLeft, e.pageY - this.offsetTop)
		return false
	})
	
	// Finalize the stroke and push any remaining stroke objects to the server
	$(document).mouseup(function() { brushInterpreter.finishStroke() })
	// Clear the stroke log, but do not lift the mouse off the canvas
	$('#canvas').mouseleave(function () { brushInterpreter.finishStroke(true) })
	// Send the interpreter a new location in the chain
	$('#canvas').mousemove(function(e) { 
		brushInterpreter.moveBrush(e.pageX - this.offsetLeft, e.pageY - this.offsetTop) 
	})
	
	////////////////////////////////////////////////////////////////////////////
	// Chatbox interactions
	////////////////////////////////////////////////////////////////////////////
	
	$('#chat-input-form').submit(function(e) {
		e.preventDefault()
		socket.emit('chat_sent', $('#chat-input').val())
		$('#chat-input').val("")
	})
	
	var addChatMessage = function (user, message, time, self) {
	
		var self = !!self
		var t = new Date(time)
	
		$('#chat-history').append(
			$('<div>').addClass("chat-message").append(
				$('<span>').addClass("timestamp")
					.text(t.getHours() + ":" + t.getMinutes())
			).append(
				$('<a>').addClass("author")
					.toggleClass("author-me", self)
					.text("@"+user)
					.prop("href", "http://twitter.com/"+user)
			).append(document.createTextNode(message))
		)
	
		$("#chat-history").animate({ scrollTop: $("#chat-history").prop("scrollHeight") }, {queue: false})
	}
})

// case "stringed-pencil":
	// var maxHistory = Math.min(20, coords.length);
	
	// for(var i = 2; i < maxHistory; i++) {
		// var c = [coords[coords.length - i][0], coords[coords.length - i][1], x, y, (i==2) ? 1 : 0.1];
		// strokeCache.push(c);
		// paintObject.coords = c;
		// paint(canvasCtx, paintObject);
	// }
	// strokeCount += 1;
	// break;

// case "magnetic-pencil":
	// for(var i = 2; i < coords.length; i++) {
		// var sep = (coords[coords.length - i][0] - x) * (coords[coords.length - i][0] - x)
			// + (coords[coords.length - i][1] - y) * (coords[coords.length - i][1] - y);
		
		// if(sep > 2500) continue;
		
		// var c = [coords[coords.length - i][0], coords[coords.length - i][1], x, y, (i==2) ? 1 : 0.25 * (1 - (sep/2500))];
		// strokeCache.push(c);
		// paintObject.coords = c;
		// paint(canvasCtx, paintObject);
	// }
	// strokeCount += 1;
	// break;

// case "cobweb-pencil":
	// for(var i = 2; i < coords.length; i++) {
		// var sep = (coords[coords.length - i][0] - x) * (coords[coords.length - i][0] - x)
			// + (coords[coords.length - i][1] - y) * (coords[coords.length - i][1] - y);
		
		// if(sep > 5000) continue;
		// if(i > 2 && Math.random() > 0.2) continue;
		
		// var c = [coords[coords.length - i][0], coords[coords.length - i][1], x, y, (i==2) ? 1 : 0.25];
		// strokeCache.push(c);
		// paintObject.coords = c;
		// paint(canvasCtx, paintObject);
	// }
	// strokeCount += 1;
	// break;
