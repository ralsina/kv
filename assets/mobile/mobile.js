/* global WebSocket */
document.addEventListener('DOMContentLoaded', () => {
  const videoStream = document.getElementById('videoStream')
  const virtualKeyboard = document.getElementById('virtualKeyboard')
  const fullscreenBtn = document.getElementById('fullscreen-btn')

  // Keyboard toggle button logic
  const keyboardToggleBtn = document.getElementById('keyboard-toggle')
  if (keyboardToggleBtn && virtualKeyboard) {
    keyboardToggleBtn.addEventListener('click', () => {
      virtualKeyboard.classList.toggle('collapsed')
      // Optionally change icon to indicate state
      const icon = keyboardToggleBtn.querySelector('.material-icons')
      if (virtualKeyboard.classList.contains('collapsed')) {
        icon.textContent = 'keyboard_hide'
      } else {
        icon.textContent = 'keyboard'
      }
    })
  }

  window.toggleFullscreen = function () {
    if (document.fullscreenElement) {
      document.exitFullscreen()
    } else {
      document.documentElement.requestFullscreen()
    }
  }

  document.addEventListener('fullscreenchange', () => {
    const isFullscreen = !!document.fullscreenElement
    fullscreenBtn.querySelector('.material-icons').textContent = isFullscreen ? 'fullscreen_exit' : 'fullscreen'
  })

  // Determine backend URL from current URL
  const backendUrl = window.location.origin
  const ws = new WebSocket(backendUrl.replace(/^http/, 'ws') + '/ws/input')

  ws.onopen = () => {
    console.log('WebSocket connected')
  }

  ws.onmessage = (event) => {
    console.log('WebSocket message received:', event.data)
  }

  ws.onerror = (error) => {
    console.error('WebSocket error:', error)
  }

  ws.onclose = () => {
    console.log('WebSocket closed')
  }

  function sendWsMessage (message) {
    console.log('Attempting to send WebSocket message:', message)
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message))
    } else {
      console.warn('WebSocket not open. Message not sent:', message)
    }
  }

  // Absolute Mouse Positioning
  let isMouseDown = false
  let pressedButtons = [] // To track which buttons are currently pressed

  function getMouseButtons (event) {
    const buttons = []
    if (event.buttons & 1) buttons.push('left')
    if (event.buttons & 2) buttons.push('right')
    if (event.buttons & 4) buttons.push('middle')
    return buttons
  }

  videoStream.addEventListener('pointerdown', (event) => {
    isMouseDown = true
    pressedButtons = getMouseButtons(event)
    const buttonName = getMouseButtonName(event.button)
    if (buttonName) {
      sendWsMessage({
        type: 'mouse_press',
        button: buttonName
      })
    }
    sendAbsoluteMouseMove(event)
  })

  videoStream.addEventListener('pointermove', (event) => {
    // Always send absolute move on pointermove
    sendAbsoluteMouseMove(event)
    if (isMouseDown) {
      // If mouse is down, also handle drag (which is already covered by sendAbsoluteMouseMove)
    }
  })

  videoStream.addEventListener('pointerup', (event) => {
    isMouseDown = false
    const releasedButtonName = getMouseButtonName(event.button)
    if (releasedButtonName) {
      sendWsMessage({
        type: 'mouse_release',
        button: releasedButtonName
      })
    }
    pressedButtons = getMouseButtons(event)
    sendAbsoluteMouseMove(event) // Send final position with updated button state
  })

  function getMouseButtonName (buttonCode) {
    if (buttonCode === 0) return 'left'
    if (buttonCode === 2) return 'right'
    if (buttonCode === 1) return 'middle'
    return null
  }

  function sendAbsoluteMouseMove (event) {
    const rect = videoStream.getBoundingClientRect()
    const x = event.clientX - rect.left
    const y = event.clientY - rect.top

    // Scale to 0-32767 range
    const absX = Math.round((x / rect.width) * 32767)
    const absY = Math.round((y / rect.height) * 32767)

    sendWsMessage({
      type: 'mouse_absolute',
      x: absX,
      y: absY,
      buttons: pressedButtons
    })
  }

  // Virtual Keyboard
  let shiftOn = false
  let ctrlOn = false
  let altOn = false
  let metaOn = false

  const baseKeys = [
    ['esc', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 'backspace'],
    ['tab', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\\'],
    // Add invisible key left of 'a' and right of 'up'
    ['invisible', 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', 'enter'],
    ['shift', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 'up', 'invisible'],
    ['ctrl', 'win', 'alt', 'space', 'menu', 'left', 'down', 'right']
  ]

  const shiftMap = {
    1: '!',
    2: '@',
    3: '#',
    4: '$',
    5: '%',
    6: '^',
    7: '&',
    8: '*',
    9: '(',
    0: ')',
    '-': '_',
    '=': '+',
    '[': '{',
    ']': '}',
    '\\': '|',
    ';': ':',
    '\'': '"',
    ',': '<',
    '.': '>',
    '/': '?'
  }

  function getActiveModifiers () {
    const mods = []
    if (ctrlOn) mods.push('control')
    if (altOn) mods.push('alt')
    if (shiftOn) mods.push('shift')
    if (metaOn) mods.push('meta')
    return mods
  }

  function handleKeyPress (key) {
    const lowerKey = key.toLowerCase()
    let sendKey = key
    let type = 'key_press'
    let keysToSend = [] // Initialize as empty array

    // Handle modifier keys first
    if (lowerKey === 'ctrl') {
      ctrlOn = !ctrlOn
      keysToSend = ['control'] // Send 'control' as the key
    } else if (lowerKey === 'alt') {
      altOn = !altOn
      keysToSend = ['alt'] // Send 'alt' as the key
    } else if (lowerKey === 'shift') {
      shiftOn = !shiftOn
      keysToSend = ['shift'] // Send 'shift' as the key
    } else if (lowerKey === 'win') {
      metaOn = !metaOn
      keysToSend = ['meta'] // Send 'meta' as the key
    } else {
      // Handle other keys
      if (lowerKey === 'menu') {
        sendKey = 'contextmenu'
      } else if (lowerKey === 'space') {
        sendKey = 'space'
      } else if (lowerKey === 'tab') {
        sendKey = 'tab'
      } else if (lowerKey === 'enter') {
        sendKey = 'enter'
      } else if (lowerKey === 'backspace') {
        sendKey = 'backspace'
      } else if (lowerKey === 'esc') {
        sendKey = 'escape'
      } else if (['left', 'right', 'up', 'down'].includes(lowerKey)) {
        sendKey = lowerKey // Arrow keys are already lowercase
      } else {
        // Handle letter/number/symbol keys
        if (shiftOn) {
          if (key.length === 1 && /[a-z]/.test(key)) {
            sendKey = key.toUpperCase()
          } else if (shiftMap[key]) {
            sendKey = shiftMap[key]
          }
        }
      }
      keysToSend = [sendKey] // For non-modifier keys, keysToSend is just the single key
    }

    const modifiers = getActiveModifiers() // Get updated modifiers after state changes

    // Determine message type: key_combination if any modifiers are active or multiple keys are sent
    if (modifiers.length > 0 || keysToSend.length > 1) {
      type = 'key_combination'
    } else {
      type = 'key_press' // Default for single key without modifiers
    }

    const messageToSend = {
      type,
      modifiers
    }

    if (type === 'key_press') {
      messageToSend.key = keysToSend[0]
    } else {
      messageToSend.keys = keysToSend
    }
    console.log('Sending WebSocket message:', messageToSend)
    sendWsMessage(messageToSend)

    renderKeyboard() // Re-render to update modifier key states
  }

  function renderKeyboard () {
    virtualKeyboard.innerHTML = ''
    baseKeys.forEach(rowKeys => {
      const rowDiv = document.createElement('div')
      rowDiv.classList.add('key-row')
      rowKeys.forEach(key => {
        const keyDiv = document.createElement('div')
        keyDiv.classList.add('key')
        keyDiv.dataset.key = key
        if (key === 'invisible') {
          keyDiv.style.visibility = 'hidden'
          keyDiv.style.pointerEvents = 'none'
        } else {
          let displayKey = key
          if (key.length === 1 && /[a-z]/.test(key)) {
            displayKey = shiftOn ? key.toUpperCase() : key.toLowerCase()
          } else if (shiftOn && shiftMap[key]) {
            displayKey = shiftMap[key]
          }
          if (key === 'up') displayKey = '↑'
          if (key === 'down') displayKey = '↓'
          if (key === 'left') displayKey = '←'
          if (key === 'right') displayKey = '→'
          if (key === 'backspace') displayKey = '⌫'
          if (key === 'enter') displayKey = '⏎'
          if (key === 'tab') displayKey = '⇥'
          if (key === 'shift') displayKey = '⇧'
          if (key === 'shift') {
            keyDiv.classList.add('modifier')
            if (shiftOn) keyDiv.classList.add('active')
          }
          if (key === 'ctrl') {
            keyDiv.classList.add('modifier')
            if (ctrlOn) keyDiv.classList.add('active')
          }
          if (key === 'alt') {
            keyDiv.classList.add('modifier')
            if (altOn) keyDiv.classList.add('active')
          }
          if (key === 'space') {
            keyDiv.classList.add('space')
            keyDiv.style.flex = '8 1 0'
            keyDiv.style.minWidth = '310px'
          }
          if (key === 'backspace') keyDiv.classList.add('backspace')
          if (key === 'enter') {
            keyDiv.classList.add('enter')
            keyDiv.style.flex = '2.3 1 0'
            keyDiv.style.minWidth = '90px'
          }
          if (key === 'tab') keyDiv.classList.add('tab')
          if (key === 'esc') displayKey = 'Esc'
          if (key === 'win') {
            keyDiv.classList.add('modifier')
            if (metaOn) keyDiv.classList.add('active')
          }
          if (key === 'menu') {
            displayKey = ''
            keyDiv.innerHTML = '<span class="material-icons" style="font-size:1.1em;vertical-align:middle;">menu</span>'
          } else {
            keyDiv.textContent = displayKey
          }
          keyDiv.addEventListener('click', () => handleKeyPress(key))
        }
        rowDiv.appendChild(keyDiv)
      })
      virtualKeyboard.appendChild(rowDiv)
    })
  }

  // Video quality menu button event
  const videoQualityBtn = document.getElementById('video-quality-btn')
  if (videoQualityBtn) {
    videoQualityBtn.addEventListener('click', e => {
      e.stopPropagation()
      const menu = document.getElementById('video-quality-menu')
      if (menu.classList.contains('active')) {
        window.hideVideoQualityMenu()
      } else {
        window.updateStatus() // Call updateStatus to populate the menu
        window.showVideoQualityMenu()
      }
    })
  }

  renderKeyboard()
  setInterval(window.updateStatus, 2000)
  setInterval(window.measureLatency, 5000)
})
