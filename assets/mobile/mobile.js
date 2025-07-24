/* global document */
/* global setupInputWebSocket, updateStatus, refreshUsbImages, measureLatency, takeScreenshot, toggleFullscreen, sendCombination, sendMouseClick, sendMouseAbsoluteMove, sendMouseRelease, showVideoQualityMenu */

// --- Mobile-Specific Initializations ---
document.addEventListener('DOMContentLoaded', () => {
  // Initialize common components
  setupInputWebSocket()
  updateStatus()
  refreshUsbImages()
  setInterval(updateStatus, 2000)
  setInterval(measureLatency, 5000)

  // Mobile-specific features
  setupMobileVideoStream('videoStream')
  setupVirtualKeyboard()
  setupMobileSidebar()
  setupMobileButtons()
})

// --- Mobile Video Stream Handling (Touch as Absolute Mouse) ---
function setupMobileVideoStream (videoElementId) {
  const video = document.getElementById(videoElementId)
  if (!video) return

  let isPointerDown = false
  let longPressTimer = null

  const getCoords = (e) => {
    const rect = video.getBoundingClientRect()
    const x = e.clientX - rect.left
    const y = e.clientY - rect.top
    const absX = Math.round((x / rect.width) * 32767)
    const absY = Math.round((y / rect.height) * 32767)
    return { absX, absY }
  }

  video.addEventListener('pointerdown', (e) => {
    e.preventDefault()
    isPointerDown = true
    const { absX, absY } = getCoords(e)

    // The move event now carries the button press information
    sendMouseAbsoluteMove(absX, absY, ['left'])

    // Set a timer for right-click (long press)
    longPressTimer = setTimeout(() => {
      sendMouseRelease('left') // Release the left-click from the initial press
      sendMouseClick('right') // Send a right-click
      isPointerDown = false // Prevent further move/up events for this interaction
    }, 500) // 500ms for long press
  })

  video.addEventListener('pointermove', (e) => {
    if (!isPointerDown) return
    e.preventDefault()
    clearTimeout(longPressTimer) // Cancel the long-press timer

    const { absX, absY } = getCoords(e)
    sendMouseAbsoluteMove(absX, absY, ['left'])
  })

  video.addEventListener('pointerup', (e) => {
    if (!isPointerDown) return
    e.preventDefault()
    clearTimeout(longPressTimer)

    // Get final coordinates for the 'up' event
    const { absX, absY } = getCoords(e)

    // Send an absolute move event with NO buttons pressed to signify release
    sendMouseAbsoluteMove(absX, absY, [])

    isPointerDown = false
  })

  // Prevent context menu on video
  video.addEventListener('contextmenu', (e) => e.preventDefault())
}

// --- Mobile UI Setup ---
function setupMobileSidebar () {
  const sidebar = document.getElementById('sidebar')
  const overlay = document.getElementById('sidebar-overlay')
  const toggle = document.getElementById('sidebar-toggle')

  const openSidebar = () => {
    sidebar.classList.remove('collapsed')
    overlay.classList.remove('collapsed')
  }
  const closeSidebar = () => {
    sidebar.classList.add('collapsed')
    overlay.classList.add('collapsed')
  }

  toggle.addEventListener('click', openSidebar)
  overlay.addEventListener('click', closeSidebar)
}

function setupMobileButtons () {
  document.getElementById('keyboard-toggle')?.addEventListener('click', () => document.getElementById('virtualKeyboard').classList.toggle('collapsed'))
  document.getElementById('fullscreen-btn')?.addEventListener('click', toggleFullscreen)
  document.getElementById('screenshot-btn')?.addEventListener('click', takeScreenshot)
  document.getElementById('video-quality-btn')?.addEventListener('click', (e) => {
    e.stopPropagation()
    showVideoQualityMenu()
  })
}

// --- Virtual Keyboard ---
function setupVirtualKeyboard () {
  const keyboardContainer = document.getElementById('virtualKeyboard')
  if (!keyboardContainer) return

  let shiftOn = false
  let ctrlOn = false
  let altOn = false
  let metaOn = false

  const baseKeys = [
    ['esc', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 'backspace'],
    ['tab', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\\'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', 'enter'],
    ['shift', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 'up'],
    ['ctrl', 'win', 'alt', 'space', 'menu', 'left', 'down', 'right']
  ]
  const shiftMap = { 1: '!', 2: '@', 3: '#', 4: '$', 5: '%', 6: '^', 7: '&', 8: '*', 9: '(', 0: ')', '-': '_', '=': '+', '[': '{', ']': '}', '\\': '|', ';': ':', "'": '"', ',': '<', '.': '>', '/': '?' }

  const renderKeyboard = () => {
    keyboardContainer.innerHTML = ''
    baseKeys.forEach(row => {
      const rowDiv = document.createElement('div')
      rowDiv.className = 'key-row'
      row.forEach(key => {
        const btn = document.createElement('button')
        btn.className = 'key'
        btn.dataset.key = key

        let display = key
        if (key.length === 1) {
          display = shiftOn ? (shiftMap[key] || key.toUpperCase()) : key
        } else {
          const iconMap = { up: '↑', down: '↓', left: '←', right: '→', backspace: '⌫', enter: '⏎', tab: '⇥', shift: '⇧', space: ' ' }
          if (iconMap[key]) display = iconMap[key]
        }

        btn.innerHTML = display
        btn.classList.add(key.length > 1 ? `key-${key}` : `key-${key.charCodeAt(0)}`)
        if (key === 'space') btn.classList.add('space')

        if (['shift', 'ctrl', 'alt', 'win'].includes(key)) {
          btn.classList.add('modifier')
        }

        if ((key === 'shift' && shiftOn) || (key === 'ctrl' && ctrlOn) || (key === 'alt' && altOn) || (key === 'win' && metaOn)) {
          btn.classList.add('active')
        }

        btn.addEventListener('click', () => handleKeyPress(key))
        rowDiv.appendChild(btn)
      })
      keyboardContainer.appendChild(rowDiv)
    })
  }

  const handleKeyPress = (key) => {
    const lowerKey = key.toLowerCase()
    if (lowerKey === 'shift') {
      shiftOn = !shiftOn
    } else if (lowerKey === 'ctrl') {
      ctrlOn = !ctrlOn
    } else if (lowerKey === 'alt') {
      altOn = !altOn
    } else if (lowerKey === 'win') {
      metaOn = !metaOn
    } else {
      const modifiers = []
      if (shiftOn) modifiers.push('shift')
      if (ctrlOn) modifiers.push('ctrl')
      if (altOn) modifiers.push('alt')
      if (metaOn) modifiers.push('meta')

      let finalKey = lowerKey
      if (shiftOn && lowerKey.length === 1) {
        finalKey = shiftMap[lowerKey] || lowerKey.toUpperCase()
      }

      sendCombination(modifiers, [finalKey])
    }
    renderKeyboard()
  }

  renderKeyboard()
}
