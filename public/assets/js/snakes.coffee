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
    player = players[playerData.id] = playerData

  socket.on "player_left", (playerId) ->
    delete players[playerId]

  socket.on "move_received", (moveData) ->
    player = players[moveData.id]
    player.direction = moveData.dir
    player.tail.push
      x: player.x
      y: player.y



  processingFunctions = (pjs) ->
    headRadius = 10
    tailWidth = headRadius
    direction = pjs.RIGHT

    pjs.setup = ->
      pjs.size mainCanvas.element.width, mainCanvas.element.height
      pjs.frameRate 60

    pjs.draw = ->
      pjs.background 50
      drawGrid()
      for i of players
        player = players[i]
        updatePlayer player
        drawPlayer player

    updatePlayer = (player) ->
      switch player.direction
        when pjs.UP    then player.y -= 1
        when pjs.DOWN  then player.y += 1
        when pjs.RIGHT then player.x += 1
        when pjs.LEFT  then player.x -= 1

    drawGrid = ->
      tilesX = 12
      tilesY = 10
      gridSizeX = pjs.width / tilesX
      gridSizeY = pjs.height / tilesY

      pjs.noFill()
      pjs.stroke 255, 255, 255, 20
      pjs.strokeWeight 1
      for x in [1..pjs.width] by gridSizeX
        pjs.line x, 0, x, pjs.height
      for y in [1..pjs.height] by gridSizeY
        pjs.line 0, y, pjs.width, y

    drawPlayer = (player) ->
      drawTail player
      drawHead player

    drawTail = (player) ->
      pjs.noFill()
      pjs.stroke player.color.red, player.color.green, player.color.blue
      pjs.strokeWeight tailWidth
      pjs.strokeCap pjs.ROUND
      pjs.strokeJoin pjs.ROUND
      pjs.beginShape()
      pjs.vertex tailJoint.x, tailJoint.y for tailJoint in player.tail
      pjs.vertex player.x, player.y
      pjs.endShape()

    drawHead = (player) ->
      pjs.fill player.color.red, player.color.green, player.color.blue
      pjs.stroke player.color.red + 70, player.color.green + 70, player.color.blue + 70
      pjs.strokeWeight 3
      pjs.ellipse player.x, player.y, headRadius, headRadius

    pjs.keyPressed = ->
      # we are not interested in input other than directional keys
      return if pjs.keyCode not in [pjs.UP, pjs.DOWN, pjs.LEFT, pjs.RIGHT]
      # no change in direction
      return if pjs.keyCode is direction
      # direction cannot change 180 degrees, e.g. from left to right
      return if pjs.keyCode is pjs.UP    and direction is pjs.DOWN
      return if pjs.keyCode is pjs.DOWN  and direction is pjs.UP
      return if pjs.keyCode is pjs.LEFT  and direction is pjs.RIGHT
      return if pjs.keyCode is pjs.RIGHT and direction is pjs.LEFT
      # we have a new proper direction
      changeOwnDirection pjs.keyCode

    changeOwnDirection = (playerId, newDirection) ->
      direction = pjs.keyCode

      socket.emit "move_sent",
        dir: direction

  p = new Processing(mainCanvas.element, processingFunctions)