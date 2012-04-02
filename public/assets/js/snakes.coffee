# Some namespaced helper functions that do not require the page to be loaded
class canvasUtils
  @isCanvasSupported: ->
    e = document.createElement("canvas")
    !!(e.getContext and e.getContext("2d"))

players = {}

$ ->
  if not canvasUtils.isCanvasSupported()
    $("#canvas-unsupported").show()
    return

  mainCanvas =
    element: $("#canvas").get(0)
    context: $("#canvas").get(0).getContext("2d")
    id: $("#canvas").attr("data-canvas-id")

  socket = io.connect("/snakes")
  socket.on "connect", (data) ->
    $("#server-link-lost").stop(true).slideUp()
    socket.emit "canvas_join", mainCanvas.id

  socket.on "disconnect", (data) ->
    $("#server-link-lost").delay(5000).slideDown()

  socket.on "client_count", (count) ->
    oc = $("#online-count")
    @prev = count  if @prev is `undefined`
    @orig = oc.css("color")  if @orig is `undefined`
    oc.text count + (if count is 1 then " person" else " people") + " on this canvas"
    color = @orig
    color = "#090"  if count > @prev
    color = "#C00"  if count < @prev
    @prev = count
    $("#online-count").css("color", color).animate
      color: @orig
    ,
      duration: 2000
      queue: false

  socket.on "canvas_ttl", (percentage) ->

  socket.on "stroke_history", (strokeHistory) ->
    console.log "stroke history recieved - doing nothing"

  socket.on "chat_history", (chatHistory) ->
    for n of chatHistory
      addChatMessage chatHistory[n].user, chatHistory[n].message, chatHistory[n].time, false

  socket.on "chat_received", (chat) ->
    addChatMessage chat.user, chat.message, chat.time, false

  $("#chat-input-form").submit (e) ->
    e.preventDefault()
    socket.emit "chat_sent", $("#chat-input").val()
    $("#chat-input").val ""

  addChatMessage = (user, message, time, self) ->
    self = !!self
    t = new Date(time)
    $("#chat-history").append $("<div>").addClass("chat-message").append($("<span>").addClass("timestamp").text(t.getHours() + ":" + t.getMinutes())).append($("<a>").addClass("author").toggleClass("author-me", self).text("@" + user).prop("href", "http://twitter.com/" + user)).append(document.createTextNode(message))
    $("#chat-history").animate
      scrollTop: $("#chat-history").prop("scrollHeight")
    ,
      queue: false

  socket.on "player_joined", (playerData) ->
    #console.log "Player with id: " + playerData.id + " joined"
    players[playerData.id] = playerData

  socket.on "player_left", (playerId) ->
    delete players[playerId]

  socket.on "move_received", (moveData) ->
    player = players[moveData.id]
    player.x = moveData.x
    player.y = moveData.y



  processingFunctions = (pjs) ->
    radius = 50
    direction = RIGHT

    pjs.setup = ->
      pjs.size mainCanvas.element.width, mainCanvas.element.height
      pjs.strokeWeight 3
      pjs.frameRate 60

    pjs.draw = ->
      pjs.background 50
      for i of players
        player = players[i]
        drawPlayer player

    drawPlayer = (player) ->
      pjs.fill player.color.red, player.color.green, player.color.blue
      pjs.stroke 255
      pjs.ellipse player.x, player.y, radius, radius

    pjs.keyPressed = ->
      if key is CODED and keyCode != direction
        if keyCode in [UP, DOWN, LEFT, RIGHT]
          direction = keyCode
          lastKeyDown = keyCode

        # TODO: Send the direction instead of the player coordinates
        socket.emit "move_sent",
          x: pjs.mouseX
          y: pjs.mouseY

  p = new Processing(mainCanvas.element, processingFunctions)