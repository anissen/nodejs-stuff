
// Some namespaced helper functions that do not require the page to be loaded
var canvasUtils = new function () {
	this.isCanvasSupported = function () {
		var e = document.createElement('canvas')
		return !!(e.getContext && e.getContext('2d'))
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
		console.log("Canvas TTL: " + percentage * 100 + "%");
	})
	
	socket.on('stroke_history', function (strokeHistory) {
		console.log("stroke history recieved - doing nothing");
	})
	
	socket.on('chat_history', function (chatHistory) {
		for(var n in chatHistory)
			addChatMessage(chatHistory[n].user, chatHistory[n].message, chatHistory[n].time, false)
	})
	
	socket.on('chat_received', function (chat) { 
		addChatMessage(chat.user, chat.message, chat.time, false)
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
});