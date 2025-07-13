// --- Toast Notification System ---
function showToast (message, type = 'error') {
  let toast = document.getElementById('toast-notification')
  if (!toast) {
    toast = document.createElement('div')
    toast.id = 'toast-notification'
    toast.style.position = 'fixed'
    toast.style.bottom = '32px'
    toast.style.left = '50%'
    toast.style.transform = 'translateX(-50%)'
    toast.style.background = 'rgba(40,40,40,0.97)'
    toast.style.color = 'white'
    toast.style.padding = '12px 28px'
    toast.style.borderRadius = '6px'
    toast.style.fontSize = '1.1em'
    toast.style.zIndex = '9999'
    toast.style.boxShadow = '0 2px 12px rgba(0,0,0,0.2)'
    toast.style.display = 'none'
    toast.style.transition = 'opacity 0.4s ease'
    document.body.appendChild(toast)
  }
  toast.textContent = message
  toast.style.background = type === 'error' ? 'rgba(200,40,40,0.97)' : (type === 'success' ? 'rgba(40,160,40,0.97)' : 'rgba(40,40,40,0.97)')
  toast.style.display = 'block'
  toast.style.opacity = '1'
  setTimeout(() => {
    toast.style.opacity = '0'
    setTimeout(() => { toast.style.display = 'none' }, 400)
  }, 3500)
}
// --- DRY Principle: Unified fetch helper for API calls with consistent error handling ---
function apiFetch (endpoint, options = {}, onSuccess, onError) {
  fetch(endpoint, options)
    .then(response => {
      if (!response.ok) throw new Error('Network response was not ok')
      return response.json().catch(() => ({}))
    })
    .then(data => {
      if (data && data.success === false) {
        if (onError) onError(data)
        else showToast('API error: ' + (data.message || 'Unknown error'), 'error')
        console.error('API error:', data)
        return
      }
      if (onSuccess) onSuccess(data)
    })
    .catch(error => {
      if (onError) onError(error)
      else showToast('Error: ' + error.message, 'error')
      console.error('API fetch error:', error)
    })
}
// Initialization on DOMContentLoaded
document.addEventListener('DOMContentLoaded', () => {
  // Upload input handler
  const uploadInput = document.getElementById('image-upload')
  if (uploadInput) {
    uploadInput.addEventListener('change', () => {
      if (uploadInput.files && uploadInput.files.length > 0) {
        uploadUsbImage()
      }
    })
  }

  // Ensure sidebar summary elements are focusable for accessibility
  document.querySelectorAll('#sidebar details > summary').forEach(summary => {
    summary.setAttribute('tabindex', '0')
  })

  // Initialize functions that need to run on page load
  loadSidebarState()
  initializeVideo()
  updateStatus()
  measureLatency()
  refreshUsbImages()

  // Set up periodic updates
  setInterval(updateStatus, 5000)
  setInterval(measureLatency, 3000)

  // Setup video capture and input handling (only once!)
  setupVideoCapture()

  // Show controls hint briefly
  setTimeout(() => {
    const controlsHint = document.getElementById('controls-hint')
    if (controlsHint) {
      controlsHint.style.display = 'inline-block'
      setTimeout(() => {
        controlsHint.style.opacity = '0'
        controlsHint.style.transition = 'opacity 1s ease'
        setTimeout(() => {
          controlsHint.style.display = 'none'
          controlsHint.style.opacity = '1'
        }, 1000)
      }, 5000)
    }
  }, 2000)

  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/assets/service-worker.js')
        .then(registration => {
          console.log('Service Worker registered with scope:', registration.scope)
        })
        .catch(error => {
          console.error('Service Worker registration failed:', error)
        })
    })
  }

  // Video quality menu button event
  const btn = document.getElementById('video-quality-btn')
  if (btn) {
    btn.addEventListener('click', e => {
      e.stopPropagation()
      const menu = document.getElementById('video-quality-menu')
      if (menu.classList.contains('active')) {
        hideVideoQualityMenu()
      } else {
        showVideoQualityMenu()
      }
    })
  }

  // Sidebar Toggle
  const sidebar = document.getElementById('sidebar')
  const sidebarToggle = document.getElementById('sidebar-toggle')
  sidebarToggle.addEventListener('click', () => {
    const isCollapsed = sidebar.classList.toggle('collapsed')
    sidebarToggle.innerHTML = isCollapsed ? '‹' : '›'
    saveSidebarState(isCollapsed)
  })

  // Close sidebar when clicking outside of it
  document.addEventListener('click', (e) => {
    if (!sidebar.contains(e.target) && e.target !== sidebarToggle) {
      if (!sidebar.classList.contains('collapsed')) {
        sidebar.classList.add('collapsed')
        sidebarToggle.innerHTML = '‹'
        saveSidebarState(true)
      }
    }
  })

  // Status bar icon click handlers
  document.getElementById('keyboard-status').addEventListener('click', e => {
    e.stopPropagation()
    sidebar.classList.remove('collapsed')
    sidebarToggle.innerHTML = '›'
    saveSidebarState(false);
    // Open all keyboard-related sections
    ['section-text', 'section-quickkeys', 'section-shortcuts'].forEach(id => {
      const d = document.getElementById(id)
      if (d) d.open = true
    });
    // Collapse others
    ['section-mouse', 'section-video', 'section-usb', 'section-ethernet'].forEach(id => {
      const d = document.getElementById(id)
      if (d) d.open = false
    })
  })
  document.getElementById('mouse-status').addEventListener('click', e => { e.stopPropagation(); openSidebarSection('section-mouse') })
  document.getElementById('storage-status').addEventListener('click', e => { e.stopPropagation(); openSidebarSection('section-usb') })
  document.getElementById('ethernet-status-bar').addEventListener('click', e => { e.stopPropagation(); openSidebarSection('section-ethernet') })

  // Fullscreen change listeners
  document.addEventListener('fullscreenchange', handleFullscreenChange)
  document.addEventListener('webkitfullscreenchange', handleFullscreenChange)
  document.addEventListener('mozfullscreenchange', handleFullscreenChange)
  document.addEventListener('MSFullscreenChange', handleFullscreenChange)

  // Text input focus handler
  document.getElementById('text-input').addEventListener('focus', () => document.getElementById('video-stream').blur())

  // Global keyboard shortcuts
  document.addEventListener('keydown', (e) => {
    if (!videoFocused) {
      if (e.ctrlKey && e.shiftKey && e.key === 'V') {
        e.preventDefault()
        pasteFromClipboard()
      }
      if (e.key === 'F11' || (e.ctrlKey && e.key === 'f')) {
        e.preventDefault()
        window.toggleFullscreen()
      }
      if ((e.ctrlKey && e.key === 's') || (e.altKey && e.key === 's')) {
        e.preventDefault()
        takeScreenshot()
      }
    }
  })
})

// --- Video Quality Menu Logic ---
function showVideoQualityMenu () {
  const menu = document.getElementById('video-quality-menu')
  if (!menu) return
  menu.classList.add('active')
  document.addEventListener('mousedown', hideVideoQualityMenuOnClick, { once: true })
}

function hideVideoQualityMenuOnClick (e) {
  const menu = document.getElementById('video-quality-menu')
  if (!menu) return
  if (!menu.contains(e.target) && e.target.id !== 'video-quality-btn') {
    menu.classList.remove('active')
  } else {
    document.addEventListener('mousedown', hideVideoQualityMenuOnClick, { once: true })
  }
}

function hideVideoQualityMenu () {
  const menu = document.getElementById('video-quality-menu')
  if (menu) menu.classList.remove('active')
}

function updateVideoQualityMenu (qualities, selected) {
  const list = document.getElementById('video-quality-list')
  if (!list) return
  list.innerHTML = ''
  qualities.forEach(q => {
    const li = document.createElement('li')
    li.textContent = q
    if (q === selected) {
      li.classList.add('selected')
      li.innerHTML = '<span class="material-icons">check</span>' + q
    }
    li.onclick = () => {
      if (q !== selected) {
        window.changeVideoQuality(q)
      }
      hideVideoQualityMenu()
    }
    list.appendChild(li)
  })
}

// --- Video Quality Selection ---
// window.loadVideoQualities is no longer needed and has been removed.

window.changeVideoQuality = function (quality) {
  apiFetch(
    '/api/video/quality',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ quality })
    },
    () => {
      setTimeout(() => initializeVideo(), 500)
      setTimeout(() => updateStatus(), 1000)
    },
    (err) => {
      showToast('Failed to change video quality: ' + (err.message || err?.message || 'Unknown error'), 'error')
      console.error('Error changing video quality:', err)
    }
  )
}

/* eslint-disable no-unused-vars */
/* global WebSocket, location, prompt, XMLHttpRequest, localStorage, alert, updateStatus, measureLatency, initializeVideo, updateFpsIndicator, setupInputWebSocket, wsSendInput, sendApiRequest, sendMousePress, sendMouseRelease, sendMouseWheel, sendSingleMouseMove, keyEventToHIDKey, getModifiers, setupVideoCapture, pasteFromClipboard, handleFullscreenChange, takeScreenshot, refreshUsbImages, uploadUsbImage, openSidebarSection, loadSidebarState, saveSidebarState */
/* global confirm */

// ECM/Ethernet enable/disable controls
window.setEthernet = function (enable) {
  apiFetch(
    '/api/ethernet/' + (enable ? 'enable' : 'disable'),
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    },
    () => updateStatus(),
    (err) => {
      showToast('Failed to set ethernet: ' + (err.message || err?.message || 'Unknown error'), 'error')
      console.error('Failed to set ethernet:', err)
    }
  )
}

// --- Audio ---
let audioStream = null
let audioLatencyInterval = null

function manageAudioLatency (audioElement) {
  if (audioLatencyInterval) clearInterval(audioLatencyInterval)

  audioLatencyInterval = setInterval(() => {
    if (audioElement.buffered.length > 0) {
      const bufferEnd = audioElement.buffered.end(audioElement.buffered.length - 1)
      const currentTime = audioElement.currentTime
      const latency = bufferEnd - currentTime

      if (latency > 1.0) {
        console.log(`High audio latency detected (${latency.toFixed(2)}s), seeking to live edge.`)
        audioElement.currentTime = bufferEnd
      }
    }
  }, 30000)
}

window.toggleAudio = function () {
  const audioBtn = document.getElementById('audio-btn')
  const icon = audioBtn.querySelector('.material-icons')

  if (audioStream) {
    if (audioLatencyInterval) clearInterval(audioLatencyInterval)
    audioStream.pause()
    audioStream.src = ''
    audioStream.load()
    try {
      document.body.removeChild(audioStream)
    } catch (e) {}
    audioStream = null
    icon.textContent = 'volume_up'
    audioBtn.title = 'Start Audio'
    audioBtn.classList.remove('active')
  } else {
    audioStream = document.createElement('audio')
    audioStream.src = '/audio.ogg'
    audioStream.autoplay = false
    audioStream.style.display = 'none'

    audioStream.addEventListener('play', () => {
      icon.textContent = 'volume_off'
      audioBtn.title = 'Stop Audio'
      audioBtn.classList.add('active')
      manageAudioLatency(audioStream)
    })

    audioStream.addEventListener('error', (e) => {
      console.error('Audio playback error:', e)
      if (audioLatencyInterval) clearInterval(audioLatencyInterval)
      if (audioStream) {
        audioStream.pause()
        audioStream.src = ''
        audioStream.load()
        try {
          document.body.removeChild(audioStream)
        } catch (err) {}
        audioStream = null
      }
      icon.textContent = 'volume_up'
      audioBtn.title = 'Start Audio'
      audioBtn.classList.remove('active')
    })

    document.body.appendChild(audioStream)
    audioStream.play().catch(e => console.error('Audio play failed:', e))
  }
}

// --- Status & Video ---
window.updateFpsIndicator = function (fps) {
  const fpsIndicator = document.getElementById('fps-indicator')
  if (fpsIndicator) {
    const fpsVal = (typeof fps === 'number' && !isNaN(fps)) ? fps.toFixed(1) : '--'
    fpsIndicator.innerHTML = `<span class="material-icons">timer</span>FPS:${fpsVal}`
    fpsIndicator.className = ''
    if (fps >= 30) fpsIndicator.classList.add('good')
    else if (fps >= 15) fpsIndicator.classList.add('warning')
    else fpsIndicator.classList.add('bad')
  }
}

let videoFocused = false
let pointerLocked = false
const pressedButtons = new Set()

window.initializeVideo = function () {
  const video = document.getElementById('video-stream')
  video.src = '/video.mjpg?' + Date.now()
  video.style.display = 'block'
}

window.updateStatus = function () {
  fetch('/api/status')
    .then(response => {
      if (!response.ok) throw new Error('Network response was not ok')
      return response.json().catch(() => ({}))
    })
    .then(data => {
      // ECM/Ethernet sidebar indicator and controls
      const eth = data.ecm || data.ethernet
      const ethStatus = document.getElementById('ethernet-status-label')
      const ethIcon = document.getElementById('ethernet-status-icon')
      const enableBtn = document.getElementById('ethernet-enable-btn')
      const disableBtn = document.getElementById('ethernet-disable-btn')
      const ethIfname = document.getElementById('ethernet-ifname')
      if (ethStatus && ethIcon && enableBtn && disableBtn) {
        if (eth) {
          if (eth.enabled) {
            ethStatus.textContent = 'Enabled'
            ethIcon.textContent = 'lan'
            ethIcon.className = 'material-icons good'
            enableBtn.disabled = true
            disableBtn.disabled = false
          } else {
            ethStatus.textContent = 'Disabled'
            ethIcon.textContent = 'lan_off'
            ethIcon.className = 'material-icons bad'
            enableBtn.disabled = false
            disableBtn.disabled = true
          }
          if (eth.ifname) {
            ethIfname.textContent = 'Interface: ' + eth.ifname + (eth.ip ? ' (' + eth.ip + ')' : '')
          } else {
            ethIfname.textContent = ''
          }
        } else {
          ethStatus.textContent = 'Unavailable'
          ethIcon.textContent = 'cable'
          ethIcon.className = 'material-icons'
          enableBtn.disabled = false
          disableBtn.disabled = false
          ethIfname.textContent = ''
        }
      }
      const videoStatus = document.getElementById('video-status')
      const keyboardStatus = document.getElementById('keyboard-status')
      const mouseStatus = document.getElementById('mouse-status')
      const storageStatus = document.getElementById('storage-status')

      if (data.video && data.video.status === 'running') {
        videoStatus.innerHTML = `<span class="material-icons">videocam</span>Live (${data.video.resolution}@${data.video.fps}fps)`
        videoStatus.classList.add('good')
      } else {
        videoStatus.innerHTML = '<span class="material-icons">videocam_off</span>Connecting...'
        videoStatus.classList.remove('good')
      }

      // Update FPS indicator with server-reported FPS
      updateFpsIndicator(data.video ? data.video.actual_fps : undefined)

      // Update video quality menu
      if (data.video && data.video.qualities) {
        updateVideoQualityMenu(data.video.qualities, data.video.selected_quality)
      }

      // ECM/Ethernet status bar (icon-only, color for status)
      const ethBar = document.getElementById('ethernet-status-bar')
      if (ethBar) {
        if (eth) {
          if (eth.enabled) {
            ethBar.innerHTML = '<span class="material-icons good">lan</span>'
            ethBar.className = 'good'
          } else {
            ethBar.innerHTML = '<span class="material-icons bad">lan_off</span>'
            ethBar.className = 'bad'
          }
        } else {
          ethBar.innerHTML = '<span class="material-icons">cable</span>'
          ethBar.className = ''
        }
      }

      // Keyboard status (icon only)
      if (data.keyboard && data.keyboard.enabled) {
        keyboardStatus.innerHTML = '<span class="material-icons good">keyboard</span>'
        keyboardStatus.className = 'good'
      } else {
        keyboardStatus.innerHTML = '<span class="material-icons bad">keyboard</span>'
        keyboardStatus.className = 'bad'
      }

      // Mouse status (icon only)
      if (data.mouse && data.mouse.enabled) {
        mouseStatus.innerHTML = '<span class="material-icons good">mouse</span>'
        mouseStatus.className = 'good'
      } else {
        mouseStatus.innerHTML = '<span class="material-icons bad">mouse</span>'
        mouseStatus.className = 'bad'
      }

      if (data.storage && data.storage.enabled) {
        storageStatus.innerHTML = '<span class="material-icons good">usb</span>'
        storageStatus.className = 'good'
      } else {
        storageStatus.innerHTML = '<span class="material-icons bad">usb</span>'
        storageStatus.className = 'bad'
      }
    })
    .catch(error => {
      showToast('Error updating status: ' + error.message, 'error')
      console.error('Error updating status:', error)
      document.getElementById('video-status').innerHTML = '<span class="material-icons">monitor</span>'
      document.getElementById('keyboard-status').innerHTML = '<span class="material-icons">keyboard</span>'
      document.getElementById('mouse-status').innerHTML = '<span class="material-icons">mouse</span>'
      document.getElementById('storage-status').innerHTML = '<span class="material-icons">usb</span>'

      const ethStatus = document.getElementById('ethernet-status-label')
      const ethIcon = document.getElementById('ethernet-status-icon')
      const enableBtn = document.getElementById('ethernet-enable-btn')
      const disableBtn = document.getElementById('ethernet-disable-btn')
      if (ethStatus && ethIcon && enableBtn && disableBtn) {
        ethStatus.textContent = 'Error'
        ethIcon.textContent = 'error'
        ethIcon.className = 'material-icons bad'
        enableBtn.disabled = false
        disableBtn.disabled = false
      }
    })
}

window.measureLatency = function () {
  const startTime = performance.now()
  fetch('/api/latency-test')
    .then(response => {
      if (!response.ok) throw new Error('Network response was not ok')
      return response.json().catch(() => ({}))
    })
    .then(data => {
      const endTime = performance.now()
      const latency = Math.round(endTime - startTime)
      const indicator = document.getElementById('latency-indicator')
      indicator.innerHTML = `<span class="material-icons">speed</span>${latency}ms`
      indicator.className = 'latency-indicator'
      if (latency < 50) indicator.classList.add('good')
      else if (latency < 100) indicator.classList.add('warning')
      else indicator.classList.add('bad')
    })
    .catch(error => {
      showToast('Error measuring latency: ' + error.message, 'error')
      console.error('Error measuring latency:', error)
      document.getElementById('latency-indicator').textContent = '♾️ --ms'
      document.getElementById('latency-indicator').className = 'latency-indicator bad'
    })
}

// --- WebSocket input client ---
let wsInput = null
let wsInputReady = false
const wsInputQueue = []
window.wsSendInput = function (obj) {
  if (wsInputReady && wsInput && wsInput.readyState === 1) {
    wsInput.send(JSON.stringify(obj))
  } else {
    wsInputQueue.push(obj)
  }
}
window.setupInputWebSocket = function () {
  wsInput = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws/input')
  wsInputReady = false
  wsInput.onopen = function () {
    wsInputReady = true
    while (wsInputQueue.length > 0) wsSendInput(wsInputQueue.shift())
  }
  wsInput.onclose = function () { wsInputReady = false; setTimeout(setupInputWebSocket, 1000) }
  wsInput.onerror = function () { wsInput.close() }
  wsInput.onmessage = function (ev) {
    // Optionally handle status/errors
    // let msg = JSON.parse(ev.data);
  }
}
setupInputWebSocket()

// Fallback for non-input endpoints (text, storage, etc)
window.sendApiRequest = function (endpoint, body) {
  fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  })
    .then(response => {
      if (!response.ok) throw new Error('Network response was not ok')
      return response.json().catch(() => ({}))
    })
    .then(data => {
      if (!data.success) {
        showToast(`Request to ${endpoint} failed: ${data.message || 'Unknown error'}`, 'error')
        console.error(`Request to ${endpoint} failed:`, data.message)
      }
    })
    .catch(error => {
      showToast(`Error sending to ${endpoint}: ${error.message}`, 'error')
      console.error(`Error sending to ${endpoint}:`, error)
    })
}

// Input event senders (now use WebSocket)
window.sendKey = function (key) { wsSendInput({ type: 'key_press', key }) }
window.sendCombination = function (modifiers, keys) { wsSendInput({ type: 'key_combination', modifiers, keys }) }
window.sendMouseClick = function (button) { wsSendInput({ type: 'mouse_click', button }) }
window.sendMousePress = function (button) {
  pressedButtons.add(button)
  wsSendInput({ type: 'mouse_press', button })
}
window.sendMouseRelease = function (button) {
  pressedButtons.delete(button)
  wsSendInput({ type: 'mouse_release', button })
}
window.sendMouseWheel = function (delta) { wsSendInput({ type: 'mouse_wheel', delta }) }
window.sendSingleMouseMove = function (x, y) {
  wsSendInput({ type: 'mouse_move', x, y, buttons: Array.from(pressedButtons) })
}

window.sendText = function () {
  const textInput = document.getElementById('text-input')
  const text = textInput.value.trim()
  if (!text) return
  sendApiRequest('/api/keyboard/text', { text })
  textInput.value = ''
}

window.pasteFromClipboard = async function () {
  try {
    const text = await navigator.clipboard.readText()
    if (text) {
      sendApiRequest('/api/keyboard/text', { text })
      console.log('Pasted text:', text.substring(0, 50) + (text.length > 50 ? '...' : ''))
    }
  } catch (err) {
    console.error('Failed to read clipboard:', err)
    // Fallback: show a prompt for manual paste
    const text = prompt('Paste your text here (automatic clipboard access not available):')
    if (text) {
      sendApiRequest('/api/keyboard/text', { text })
    }
  }
}

window.keyEventToHIDKey = function (event) {
  const key = event.key
  const keyMap = {
    Enter: 'enter',
    Escape: 'escape',
    Backspace: 'backspace',
    Tab: 'tab',
    Delete: 'delete',
    ArrowUp: 'up',
    ArrowDown: 'down',
    ArrowLeft: 'left',
    ArrowRight: 'right',
    Home: 'home',
    End: 'end',
    PageUp: 'pageup',
    PageDown: 'pagedown',
    Insert: 'insert',
    CapsLock: 'caps-lock',
    NumLock: 'num-lock',
    ' ': 'space'
  }
  if (key.startsWith('F') && key.length > 1 && key.length <= 3) return key.toLowerCase()
  if (keyMap[key]) return keyMap[key]
  if (key.length === 1) return key
  return null
}

window.getModifiers = function (event) {
  const modifiers = []
  if (event.ctrlKey) modifiers.push('ctrl')
  if (event.shiftKey) modifiers.push('shift')
  if (event.altKey) modifiers.push('alt')
  if (event.metaKey) modifiers.push('meta')
  return modifiers
}

window.setupVideoCapture = function () {
  const video = document.getElementById('video-stream')
  const videoStatusBar = document.getElementById('video-status-bar')
  const inputStatus = document.getElementById('input-status')

  // Prevent duplicate handler attachment
  if (video._kvHandlersAttached) return
  video._kvHandlersAttached = true

  document.addEventListener('pointerlockchange', () => {
    pointerLocked = (document.pointerLockElement === video)
    videoFocused = pointerLocked
    videoStatusBar.classList.toggle('input-active', pointerLocked)
    inputStatus.innerHTML = pointerLocked ? 'Input Active (ESC to release)' : ''
    // Hide controls when pointer is locked
    const videoContainer = video.closest('.video-container')
    if (videoContainer) {
      if (pointerLocked) {
        videoContainer.classList.add('pointer-locked')
      } else {
        videoContainer.classList.remove('pointer-locked')
      }
    }
    if (!pointerLocked) {
      pressedButtons.forEach(button => sendMouseRelease(button))
    }
  })

  video.addEventListener('focus', () => {
    if (!pointerLocked) {
      videoFocused = true
      videoStatusBar.classList.add('input-active')
      inputStatus.innerHTML = 'Input Active'
    }
  })
  video.addEventListener('blur', () => {
    if (!pointerLocked) {
      videoFocused = false
      videoStatusBar.classList.remove('input-active')
      inputStatus.textContent = ''
    }
  })
  video.addEventListener('click', (e) => { e.preventDefault(); video.requestPointerLock() })
  video.addEventListener('mousemove', (e) => {
    if (pointerLocked) sendSingleMouseMove(e.movementX, e.movementY)
  })
  video.addEventListener('mousedown', (e) => {
    if (!videoFocused) return
    e.preventDefault()
    const button = e.button === 0 ? 'left' : e.button === 1 ? 'middle' : 'right'
    sendMousePress(button)
  })
  video.addEventListener('mouseup', (e) => {
    if (!videoFocused) return
    e.preventDefault()
    const button = e.button === 0 ? 'left' : e.button === 1 ? 'middle' : 'right'
    sendMouseRelease(button)
  })
  video.addEventListener('keydown', (e) => {
    if (!videoFocused) return
    const hidKey = keyEventToHIDKey(e)
    if (hidKey) {
      e.preventDefault()
      const modifiers = getModifiers(e)
      if (videoFocused && pointerLocked && e.target === video) {
        window.sendCombination(modifiers, [hidKey])
      }
    }
  })
  video.addEventListener('wheel', (e) => {
    if (!videoFocused) return
    e.preventDefault()
    const delta = e.deltaY > 0 ? -1 : 1
    sendMouseWheel(delta)
  })
  video.addEventListener('contextmenu', (e) => e.preventDefault())
  video.addEventListener('paste', (e) => {
    if (!videoFocused) return
    e.preventDefault()
    const text = e.clipboardData.getData('text')
    if (text) sendApiRequest('/api/keyboard/text', { text })
  })
}

// --- USB Mass Storage ---
window.refreshUsbImages = function () {
  apiFetch(
    '/api/storage/images',
    {},
    (data) => {
      const container = document.getElementById('usb-image-list')
      if (data.success && data.images) {
        if (data.images.length === 0) {
          container.innerHTML = '<em>No disk images found in ./disk-images</em>'
        } else {
          container.innerHTML = data.images.map(img => {
            const isSelected = (img === data.selected)
            const icon = isSelected ? 'eject' : 'play_arrow'
            const btnClass = isSelected ? 'detach-usb-btn' : 'mount-usb-btn'
            const btnTitle = isSelected ? 'Detach' : 'Mount'
            return `<div style="display:flex;align-items:center;padding:2px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;${isSelected ? 'font-weight:bold;color:#4ade80;' : ''}">` +
              '<div style="display:flex;gap:0.25em;align-items:center;margin-left:0.5em;">' +
                `<button class="outline ${btnClass}" style="min-width:32px;width:32px;height:32px;padding:0;display:flex;align-items:center;justify-content:center;" title="${btnTitle}" onclick="${isSelected ? 'detachUsbImage()' : `selectUsbImage('${img}')`}"><span class="material-icons">${icon}</span></button>` +
                `<button class="outline secondary" style="min-width:32px;width:32px;height:32px;padding:0;display:flex;align-items:center;justify-content:center;" title="Delete Image" onclick="deleteUsbImage('${img}')" ${isSelected ? 'disabled' : ''}><span class="material-icons">delete</span></button>` +
              '</div>' +
              `<span title="${img}" style="flex-grow:1;margin-left:0.75em;">${img}${isSelected ? ' (selected)' : ''}</span>` +
              '</div>'
          }).join('')
        }
      } else {
        container.innerHTML = '<em>Error loading disk images</em>'
      }
    },
    (err) => {
      document.getElementById('usb-image-list').innerHTML = '<em>Error loading disk images</em>'
      showToast('Error loading disk images: ' + (err.message || err?.message || 'Unknown error'), 'error')
      console.error('Error loading disk images:', err)
    }
  )
}

window.selectUsbImage = function (image) {
  apiFetch(
    '/api/storage/select',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image })
    },
    () => setTimeout(() => { refreshUsbImages(); updateStatus() }, 300),
    (err) => {
      showToast('Failed to select USB image: ' + (err.message || err?.message || 'Unknown error'), 'error')
      console.error('Error selecting USB image:', err)
    }
  )
}

window.detachUsbImage = function () {
  apiFetch(
    '/api/storage/select',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image: null })
    },
    () => setTimeout(() => { refreshUsbImages(); updateStatus() }, 300),
    (err) => {
      showToast('Failed to detach USB image: ' + (err.message || err?.message || 'Unknown error'), 'error')
      console.error('Error detaching USB image:', err)
    }
  )
}

window.deleteUsbImage = function (filename) {
  if (!confirm(`Are you sure you want to delete ${filename}? This action cannot be undone.`)) {
    return
  }
  fetch(`/api/storage/images/${filename}`, {
    method: 'DELETE'
  })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        showToast(data.message, data.success ? 'success' : 'error')
        refreshUsbImages()
      } else {
        showToast(`Failed to delete image: ${data.message}`, 'error')
      }
    })
    .catch(error => {
      console.error('Error deleting USB image:', error)
      showToast('Error deleting USB image.', 'error')
    })
}

// --- Sidebar ---
// Helper: open sidebar and expand a section
window.openSidebarSection = function (sectionId) {
  const sidebar = document.getElementById('sidebar')
  sidebar.classList.remove('collapsed')
  document.getElementById('sidebar-toggle').innerHTML = '›'
  saveSidebarState(false)
  document.querySelectorAll('#sidebar details').forEach(d => {
    if (d.id === sectionId) {
      d.open = true
      const summary = d.querySelector('summary')
      if (summary) summary.focus()
    } else {
      d.open = false
    }
  })
}

window.loadSidebarState = function () {
  const sidebar = document.getElementById('sidebar')
  const isCollapsed = localStorage.getItem('sidebarCollapsed') === 'true'
  if (isCollapsed) {
    sidebar.classList.add('collapsed')
    document.getElementById('sidebar-toggle').innerHTML = '‹'
  } else {
    sidebar.classList.remove('collapsed')
    document.getElementById('sidebar-toggle').innerHTML = '›'
  }
}

window.saveSidebarState = function (isCollapsed) {
  localStorage.setItem('sidebarCollapsed', isCollapsed.toString())
}

// --- Fullscreen & Screenshot ---
window.toggleFullscreen = function () {
  const videoContainer = document.querySelector('.video-container')
  const fullscreenBtn = document.getElementById('fullscreen-btn')

  if (videoContainer.classList.contains('fullscreen')) {
    if (document.exitFullscreen) document.exitFullscreen()
    else if (document.webkitExitFullscreen) document.webkitExitFullscreen()
    else if (document.mozCancelFullScreen) document.mozCancelFullScreen()
    else if (document.msExitFullscreen) document.msExitFullscreen()
  } else {
    if (videoContainer.requestFullscreen) videoContainer.requestFullscreen()
    else if (videoContainer.webkitRequestFullscreen) videoContainer.webkitRequestFullscreen()
    else if (videoContainer.mozRequestFullScreen) videoContainer.mozRequestFullScreen()
    else if (videoContainer.msRequestFullscreen) videoContainer.msRequestFullscreen()
  }
}

window.handleFullscreenChange = function () {
  const videoContainer = document.querySelector('.video-container')
  const fullscreenBtn = document.getElementById('fullscreen-btn')
  const isFullscreen = document.fullscreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement

  videoContainer.classList.toggle('fullscreen', !!isFullscreen)
  fullscreenBtn.querySelector('.material-icons').textContent = isFullscreen ? 'fullscreen_exit' : 'fullscreen'
}

window.takeScreenshot = function () {
  const video = document.getElementById('video-stream')
  const canvas = document.createElement('canvas')
  canvas.width = video.naturalWidth
  canvas.height = video.naturalHeight
  const ctx = canvas.getContext('2d')
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height)

  try {
    const dataURL = canvas.toDataURL('image/png')
    const a = document.createElement('a')
    a.href = dataURL
    const timestamp = new Date().toISOString().replace(/:/g, '-').replace(/\..+/, '').replace('T', '_')
    a.download = `kvm_screenshot_${timestamp}.png`
    document.body.appendChild(a)
    a.click()
    setTimeout(() => {
      document.body.removeChild(a)
      URL.revokeObjectURL(dataURL)
    }, 100)

    const notification = document.createElement('div')
    notification.style.position = 'fixed'
    notification.style.bottom = '20px'
    notification.style.left = '50%'
    notification.style.transform = 'translateX(-50%)'
    notification.style.background = 'rgba(0, 0, 0, 0.8)'
    notification.style.color = 'white'
    notification.style.padding = '10px 20px'
    notification.style.borderRadius = '4px'
    notification.style.zIndex = '9999'
    notification.innerHTML = '<span class="material-icons" style="vertical-align: middle; margin-right: 8px;">check_circle</span> Screenshot saved'
    document.body.appendChild(notification)
    setTimeout(() => {
      notification.style.opacity = '0'
      notification.style.transition = 'opacity 0.5s ease'
      setTimeout(() => document.body.removeChild(notification), 500)
    }, 2000)
  } catch (error) {
    console.error('Error taking screenshot:', error)
    showToast('Failed to take screenshot. This may be due to security restrictions.', 'error')
  }
}
