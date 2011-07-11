class ChatPage
  constructor: (@session) ->
    @session.onRoster   ( ) => this.roster()
    @session.onCard     (c) => this.card(c)
    @session.onMessage  (m) => this.message(m)
    @session.onPresence (p) => this.presence(p)
    @chats = {}
    @currentContact = null

  datef: (millis) ->
    d = new Date(millis)
    meridian = if d.getHours() >= 12 then ' pm' else ' am'
    hour = if d.getHours() > 12 then d.getHours() - 12 else d.getHours()
    hour = 12 if hour == 0
    minutes = d.getMinutes() + ''
    minutes = '0' + minutes if minutes.length == 1
    hour + ':' + minutes + meridian

  card: (card) ->
    this.eachContact card.jid, (node) =>
      $('.vcard-img', node).attr 'src', @session.avatar card.jid

  roster: ->
    roster = $('#roster')

    $('li', roster).each (ix, node) =>
      jid = $(node).attr('data-jid')
      $(node).remove() unless @session.roster[jid]

    setName = (node, contact) ->
      $('.text', node).text contact.name || contact.jid
      node.attr 'data-name', contact.name || ''

    for jid, contact of @session.roster
      found = $("li[data-jid='#{jid}']")
      setName(found, contact)
      if found.length == 0
        node = $("""
          <li data-jid="#{jid}" data-name="" class="offline">
            <span class="text"></span>
            <span class="status-msg">Offline</span>
            <span class="unread" style="display:none;"></span>
            <img class="vcard-img" alt="#{jid}" src="#{@session.avatar jid}"/>
          </li>
        """).appendTo roster
        setName(node, contact)
        node.click (event) => this.selectContact(event)

  message: (message) ->
    this.queueMessage message
    me   = message.from == @session.jid()
    from = message.from.split('/')[0]

    if me || from == @currentContact
      bottom = this.atBottom()
      this.appendMessage message
      this.scroll() if bottom
    else
      chat = this.chat message.from
      chat.unread++
      this.eachContact from, (node) ->
        $('.unread', node).text(chat.unread).show()

  eachContact: (jid, callback) ->
    for node in $("#roster li[data-jid='#{jid}']").get()
      callback $(node)

  appendMessage: (message) ->
    from    = message.from.split('/')[0]
    contact = @session.roster[from]
    name    = if contact then (contact.name || from) else from
    name    = 'Me' if message.from == @session.jid()
    node    = $("""
      <li data-jid="#{from}" style="display:none;">
        <p></p>
        <img alt="#{from}" src="#{@session.avatar from}"/>
        <footer>
          <span class="author"></span>
          <span class="time">#{this.datef message.received}</span>
        </footer>
      </li>
    """).appendTo '#messages'

    $('p', node).text message.text
    $('.author', node).text name
    node.fadeIn 200

  queueMessage: (message) ->
    me   = message.from == @session.jid()
    full = message[if me then 'to' else 'from']
    chat = this.chat full
    chat.jid = full
    chat.messages.push message

  chat: (jid) ->
    bare = jid.split('/')[0]
    chat = @chats[bare]
    unless chat
      chat = jid: jid, messages: [], unread: 0
      @chats[bare] = chat
    chat

  presence: (presence) ->
    from = presence.from.split('/')[0]
    return if from == @session.bareJid()
    if !presence.type || presence.offline
      contact = @session.roster[from]
      this.eachContact from, (node) ->
        $('.status-msg', node).text contact.status()
        if contact.offline()
          node.addClass 'offline'
        else
          node.removeClass 'offline'

    if presence.offline
      this.chat(from).jid = from

    if presence.type == 'subscribe'
      node = $("""
        <li data-jid="#{presence.from}" style="display:none;">
          <form class="notify-form">
            <h2>Buddy Approval</h2>
            <p>#{presence.from} wants to add you as a buddy.</p>
            <fieldset class="buttons">
              <input type="button" value="Decline"/>
              <input type="submit" value="Accept"/>
            </fieldset>
          </form>
        </li>
      """).appendTo '#notifications'
      node.fadeIn 200
      $('form', node).submit => this.acceptContact node, presence.from
      $('input[type="button"]', node).click => this.rejectContact node, presence.from

  acceptContact: (node, jid) ->
    node.fadeOut 200, -> node.remove()
    @session.sendSubscribed jid
    @session.sendSubscribe  jid
    false

  rejectContact: (node, jid) ->
    node.fadeOut 200, -> node.remove()
    @session.sendUnsubscribed jid

  selectContact: (event) ->
    jid = $(event.currentTarget).attr 'data-jid'
    contact = @session.roster[jid]
    return if @currentContact == jid
    @currentContact = jid

    $('#roster li').removeClass 'selected'
    $(event.currentTarget).addClass 'selected'
    $('#chat-title').text('Chat with ' + (contact.name || contact.jid))
    $('#messages').empty()

    chat = @chats[jid]
    messages = []
    if chat
      messages = chat.messages
      chat.unread = 0
      this.eachContact jid, (node) ->
        $('.unread', node).text('').hide()

    this.appendMessage msg for msg in messages
    this.scroll()

    $('#remove-contact-msg').html "Are you sure you want to remove " +
      "<strong>#{@currentContact}</strong> from your buddy list?"
    $('#remove-contact-form .buttons').fadeIn 200

    $('#edit-contact-jid').text @currentContact
    $('#edit-contact-name').val @session.roster[@currentContact].name
    $('#edit-contact-form input').fadeIn 200
    $('#edit-contact-form .buttons').fadeIn 200

  scroll: ->
    msgs = $ '#messages'
    msgs.animate(scrollTop: msgs.prop('scrollHeight'), 400)

  atBottom: ->
    msgs = $('#messages')
    bottom = msgs.prop('scrollHeight') - msgs.height()
    msgs.scrollTop() == bottom

  send: ->
    return false unless @currentContact
    input = $('#message')
    text = input.val().trim()
    if text
      chat = @chats[@currentContact]
      jid = if chat then chat.jid else @currentContact
      this.message
        from: @session.jid()
        text: text
        to: jid
        received: new Date()
      @session.sendMessage jid, text
    input.val ''
    false

  addContact: ->
    this.toggleForm '#add-contact-form'
    contact =
      jid: $('#add-contact-jid').val()
      name: $('#add-contact-name').val()
      groups: ['Buddies']
    @session.updateContact contact, true if contact.jid
    false

  removeContact: ->
    this.toggleForm '#remove-contact-form'
    @session.removeContact @currentContact
    @currentContact = null

    $('#chat-title').text 'Select a buddy to chat'
    $('#messages').empty()

    $('#remove-contact-msg').html "Select a buddy in the list above to remove."
    $('#remove-contact-form .buttons').hide()

    $('#edit-contact-jid').text "Select a buddy in the list above to update."
    $('#edit-contact-name').val ''
    $('#edit-contact-form input').hide()
    $('#edit-contact-form .buttons').hide()
    false

  updateContact: ->
    this.toggleForm '#edit-contact-form'
    contact =
      jid: @currentContact
      name: $('#edit-contact-name').val()
      groups: @session.roster[@currentContact].groups
    @session.updateContact contact
    false

  toggleForm: (form, fn) ->
    form = $(form)
    $('.contact-form').each ->
      $(this).hide() unless this.id == form.attr 'id'
    if form.is ':hidden'
      fn() if fn
      form.fadeIn 100
    else
      form.fadeOut 100, ->
        form[0].reset()
        fn() if fn

  filterRoster: ->
    text = $('#search-roster-text').val().toLowerCase()
    if text == ''
      $('#roster li').show()
      return

    $('#roster li').each ->
      node  = $(this)
      jid   = (node.attr('data-jid') || '').toLowerCase()
      name  = (node.attr('data-name') || '').toLowerCase()
      match = jid.indexOf(text) != -1 || name.indexOf(text) != -1
      if match then node.show() else node.hide()

  draw: ->
    unless @session.connected()
      window.location.hash = ''
      return

    $('body').attr 'id', 'chat-page'
    $('#container').hide().empty()
    $("""
      <div id="alpha">
        <h2>Buddies <div id="search-roster"></div></h2>
        <form id="search-roster-form" style="display:none;">
          <input id="search-roster-text" type="search" placeholder="Filter" results="5"/>
        </form>
        <ul id="roster"></ul>
        <div id="roster-controls">
          <div id="add-contact"></div>
          <div id="remove-contact"></div>
          <div id="edit-contact"></div>
        </div>
        <form id="add-contact-form" class="contact-form" style="display:none;">
          <h2>Add Buddy</h2>
          <input id="add-contact-jid" type="email" maxlength="1024" placeholder="Account name"/>
          <input id="add-contact-name" type="text" maxlength="1024" placeholder="Real name"/>
          <fieldset class="buttons">
            <input id="add-contact-cancel" type="button" value="Cancel"/>
            <input id="add-contact-ok" type="submit" value="Add"/>
          </fieldset>
        </form>
        <form id="remove-contact-form" class="contact-form" style="display:none;">
          <h2>Remove Buddy</h2>
          <p id="remove-contact-msg">Select a buddy in the list above to remove.</p>
          <fieldset class="buttons" style="display:none;">
            <input id="remove-contact-cancel" type="button" value="Cancel"/>
            <input id="remove-contact-ok" type="submit" value="Remove"/>
          </fieldset>
        </form>
        <form id="edit-contact-form" class="contact-form" style="display:none;">
          <h2>Update Profile</h2>
          <p id="edit-contact-jid">Select a buddy in the list above to update.</p>
          <input id="edit-contact-name" type="text" maxlength="1024" placeholder="Real name" style="display:none;"/>
          <fieldset class="buttons" style="display:none;">
            <input id="edit-contact-cancel" type="button" value="Cancel"/>
            <input id="edit-contact-ok" type="submit" value="Save"/>
          </fieldset>
        </form>
      </div>
      <div id="beta">
        <h2 id="chat-title">Select a buddy to chat</h2>
        <ul id="messages"></ul>
        <form id="message-form">
          <input id="message" name="message" type="text" maxlength="1024" placeholder="Type a message and press enter to send"/>
        </form>
      </div>
      <div id="charlie">
        <h2>Notifications</h2>
        <ul id="notifications"></ul>
        <div id="notification-controls">
          <div id="clear-notices"></div>
        </div>
      </div>
    """).appendTo '#container'

    this.roster()
    this.button 'clear-notices', ICONS.no
    this.button 'add-contact', ICONS.plus
    this.button 'remove-contact', ICONS.minus
    this.button 'edit-contact', ICONS.user
    this.button 'search-roster', ICONS.search, scale: 0.5, translation: '-8 -8'

    $('#message').focus -> $('.contact-form').fadeOut()
    $('#message-form').submit  => this.send()

    $('#clear-notices').click  -> $('#notifications li').fadeOut 200

    $('#add-contact').click    => this.toggleForm '#add-contact-form'
    $('#remove-contact').click => this.toggleForm '#remove-contact-form'
    $('#edit-contact').click   => this.toggleForm '#edit-contact-form', =>
      if @currentContact
        $('#edit-contact-jid').text @currentContact
        $('#edit-contact-name').val @session.roster[@currentContact].name

    $('#add-contact-cancel').click    => this.toggleForm '#add-contact-form'
    $('#remove-contact-cancel').click => this.toggleForm '#remove-contact-form'
    $('#edit-contact-cancel').click   => this.toggleForm '#edit-contact-form'

    $('#add-contact-form').submit    => this.addContact()
    $('#remove-contact-form').submit => this.removeContact()
    $('#edit-contact-form').submit   => this.updateContact()
    $('#search-roster-form').submit  -> false

    $('#search-roster-text').keyup  => this.filterRoster()
    $('#search-roster-text').change => this.filterRoster()
    $('#search-roster-text').click  => this.filterRoster()
    $('#search-roster').click =>
      this.toggleForm '#search-roster-form', => this.filterRoster()

    $('#container').fadeIn 200
    this.resize()

  resize: ->
    win    = $ window
    header = $ '#navbar'
    nav    = $ '#app-nav'
    page   = $ '#container'
    a      = $ '#alpha'
    b      = $ '#beta'
    c      = $ '#charlie'
    atitle = $ '#alpha > h2'
    btitle = $ '#beta > h2'
    ctitle = $ '#charlie > h2'
    rctrls = $ '#roster-controls'
    nctrls = $ '#notification-controls'
    msg    = $ '#message'
    msgs   = $ '#messages'
    form   = $ '#message-form'
    roster = $ '#roster'
    notify = $ '#notifications'
    sizer = ->
      height = win.height() - header.height() - 1
      page.height height
      a.height height
      b.height height
      c.height height

      roster.height a.height() - rctrls.height() - atitle.height()
      msgs.height   b.height() - form.height() - btitle.height()
      notify.height c.height() - nctrls.height() - ctitle.height()

      b.width win.width() - a.width() - c.width()
      nav.width b.width()
      c.css 'left', a.width() + b.width()
      msg.width form.width() - 32

    id = null
    win.resize ->
      clearTimeout id
      id = setTimeout sizer, 10
      sizer()

    sizer()
    setTimeout sizer, 500

  button: (id, path, options) ->
    options ||= {}
    paper = Raphael(id)
    icon = paper.path(path).attr
      fill: '#000'
      stroke: '#fff'
      'stroke-width': 0.3
      opacity: 0.6
      scale: options.scale || 0.85
      translation: options.translation || ''

    node = $('#' + id)
    node.hover(
      -> icon.animate(opacity: 1.0, 200),
      -> icon.animate(opacity: 0.6, 200))
    node.get 0