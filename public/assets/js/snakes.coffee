# Some namespaced helper functions that do not require the page to be loaded
class canvasUtils
  @isCanvasSupported: ->
    e = document.createElement("canvas")
    !!(e.getContext and e.getContext("2d"))

players = {}
thisPlayerId = null
thisPlayer = null

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

  socket.on "you_are_ready", (playerId) ->
    thisPlayerId = playerId
    thisPlayer = players[thisPlayerId]

  socket.on "player_joined", (playerData) ->
    playerData.dead = false
    players[playerData.id] = playerData
    console.log playerData

  socket.on "player_left", (playerId) ->
    delete players[playerId]

  socket.on "player_died", (collidedData) ->
    deadPlayer = players[collidedData.id]
    killer = players[collidedData.killerId]
    console.log deadPlayer.name + ' died at the "hands" of ' + killer.name
    deadPlayer.dead = true
    deadPlayer.tail = []

  socket.on "player_spawned", (playerData) ->
    playerData.dead = false
    $.extend players[playerData.id], playerData

  socket.on "move_received", (moveData) ->
    player = players[moveData.id]
    player.direction = moveData.dir
    player.tail.push
      x: player.x # SHOULD be moveData.x & .y, but this comes out of synch!
      y: player.y # SHOULD be moveData.x & .y, but this comes out of synch!

  processingFunctions = (pjs) ->
    headRadius = 15
    tailWidth = headRadius - 2
    direction = 0
    moveSpeed = 2

    pjs.setup = ->
      pjs.size mainCanvas.element.width, mainCanvas.element.height
      pjs.smooth()
      pjs.frameRate 60

    pjs.draw = ->
      pjs.background 50

      if not thisPlayer?
        pjs.fill 0, 102, 153
        pjs.textSize 24
        pjs.textAlign pjs.CENTER
        pjs.text "Loading... ", pjs.width / 2, pjs.height / 2
        return

      drawGrid()

      for i of players
        player = players[i]
        if thisPlayer.dead
          pjs.fill 255, 50, 100
          #pjs.textSize 28
          pjs.textAlign pjs.CENTER
          pjs.text "You are dead. Respawning in five seconds...", pjs.width / 2, pjs.height / 2
        continue if player.dead
        updatePlayer player
        drawPlayer player

      checkForCollision()

    updatePlayer = (player) ->
      switch player.direction
        when pjs.UP    then player.y -= moveSpeed
        when pjs.DOWN  then player.y += moveSpeed
        when pjs.RIGHT then player.x += moveSpeed
        when pjs.LEFT  then player.x -= moveSpeed

    checkForCollision = ->
      return if thisPlayer.dead

      for i of players
        otherPlayer = players[i]
        tail = otherPlayer.tail[0...otherPlayer.tail.length]
        if otherPlayer is thisPlayer
          # remove the last tail part to ensure that
          # the player do not hit himself when turning
          tail.pop()
        else
          # push the player head on to the tail list
          tail.push {x: otherPlayer.x, y: otherPlayer.y}

        if hasPointCollisionWithTail thisPlayer.x, thisPlayer.y, tail
          collidedOnPlayer otherPlayer.id
          return

    hasPointCollisionWithTail = (pointX, pointY, tail) ->
      for tailPart in tail
        if lastTailPart?
          #pjs.stroke 0, 255, 0, 50
          #pjs.line lastTailPart.x, lastTailPart.y, tailPart.x, tailPart.y
          if isPointInsideTailPart pointX, pointY, lastTailPart, tailPart
            #pjs.stroke 255, 0, 0, 100
            #pjs.line lastTailPart.x, lastTailPart.y, tailPart.x, tailPart.y
            return true
        lastTailPart = tailPart
      return false

    isPointInsideTailPart = (pointX, pointY, lastTailPart, tailPart) ->
      tailHalfWidth = Math.ceil(tailWidth / 2) + 1 # needs + 1 width for the line itself
      return pointX >= Math.min(lastTailPart.x, tailPart.x) - tailHalfWidth and
             pointX <= Math.max(lastTailPart.x, tailPart.x) + tailHalfWidth and 
             pointY >= Math.min(lastTailPart.y, tailPart.y) - tailHalfWidth and
             pointY <= Math.max(lastTailPart.y, tailPart.y) + tailHalfWidth

    drawGrid = ->
      tilesX = 12
      tilesY = 10
      gridSizeX = pjs.width / tilesX
      gridSizeY = pjs.height / tilesY

      pjs.noFill()
      pjs.stroke 255, 255, 255, 20
      pjs.strokeWeight 1
      pjs.line x, 0, x, pjs.height for x in [1..pjs.width] by gridSizeX
      pjs.line 0, y, pjs.width, y  for y in [1..pjs.height] by gridSizeY

    drawPlayer = (player) ->
      drawTail player
      drawHead player

    drawTail = (player) ->
      pjs.noFill()
      pjs.stroke 0
      pjs.strokeWeight tailWidth
      pjs.strokeCap pjs.ROUND
      pjs.strokeJoin pjs.ROUND
      pjs.beginShape()
      pjs.vertex tailPart.x, tailPart.y for tailPart in player.tail
      pjs.vertex player.x, player.y
      pjs.endShape()

      #pjs.noFill()
      pjs.stroke player.color.red, player.color.green, player.color.blue
      pjs.strokeWeight tailWidth - 5
      #pjs.strokeCap pjs.ROUND
      #pjs.strokeJoin pjs.ROUND
      pjs.beginShape()
      pjs.vertex tailPart.x, tailPart.y for tailPart in player.tail
      pjs.vertex player.x, player.y
      pjs.endShape()

    drawHead = (player) ->
      pjs.fill player.color.red, player.color.green, player.color.blue
      pjs.stroke player.color.red - 70, player.color.green - 70, player.color.blue - 70
      pjs.strokeWeight 3
      pjs.ellipse player.x, player.y, headRadius, headRadius

      pjs.fill 0
      pjs.text player.name, player.x + 1, player.y - 15 + 1 # hack for creating a shadow effect
      pjs.fill player.color.red, player.color.green, player.color.blue
      pjs.text player.name, player.x, player.y - 15

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

    collidedOnPlayer = (killerId) ->
      socket.emit "player_collided",
        killerId: killerId

    changeOwnDirection = (newDirection) ->
      socket.emit "move_sent",
        dir: newDirection
        x: thisPlayer.x
        y: thisPlayer.y

  p = new Processing(mainCanvas.element, processingFunctions)