/* global fetch, WebSocket, location, XMLHttpRequest, document, window, navigator, FormData, Date, setTimeout, console, isNaN, alert, confirm, localStorage */

// --- Toast Notification System ---
function showToast (message, type = 'info') {
  let toast = document.getElementById('toast-notification')
  if (!toast) {
    toast = document.createElement('div')
    toast.id = 'toast-notification'
    document.body.appendChild(toast)
  }
  toast.textContent = message
  toast.className = `toast ${type}`
  toast.style.display = 'block'
  toast.style.opacity = '1'
  setTimeout(() => {
    toast.style.opacity = '0'
    setTimeout(() => { toast.style.display = 'none' }, 400)
  }, 3500)
}

// --- Device Status Handler ---
function handleDeviceStatus (videoStatus) {
  const wasAvailable = window.videoDeviceAvailable || false
  window.videoDeviceAvailable = videoStatus.available

  // Update video element visibility
  const videoElement = document.getElementById('video-stream') || document.getElementById('videoStream')
  const noVideoMessage = document.getElementById('no-video')
  const statusIndicator = document.getElementById('video-status')

  if (videoStatus.available) {
    // Video device connected
    if (videoElement) {
      videoElement.style.display = 'block'
      // Force reload video stream
      const currentTime = new Date().getTime()
      videoElement.src = '/video.mjpg?t=' + currentTime
    }
    if (noVideoMessage) {
      noVideoMessage.style.display = 'none'
    }
    if (!wasAvailable) {
      showToast(videoStatus.message || 'Video device connected', 'success')
    }
  } else {
    // Video device disconnected
    if (videoElement) {
      videoElement.style.display = 'none'
    }
    if (noVideoMessage) {
      noVideoMessage.style.display = 'block'
      noVideoMessage.textContent = videoStatus.message || 'No video device available'
    }
    if (wasAvailable) {
      showToast(videoStatus.message || 'Video device disconnected', 'warning')
    }
  }

  // Update status indicator if it exists
  if (statusIndicator) {
    statusIndicator.className = videoStatus.available ? 'status-connected' : 'status-disconnected'
    statusIndicator.title = videoStatus.message || (videoStatus.available ? 'Video device connected' : 'No video device')
  }

  // Dispatch custom event for other scripts to handle
  window.dispatchEvent(new CustomEvent('videoDeviceStatusChanged', {
    detail: videoStatus
  }))
}

// --- API Fetch Helper ---
window.apiFetch = function (endpoint, options = {}, onSuccess, onError) {
  fetch(endpoint, options)
    .then(response => {
      if (!response.ok) throw new Error(`Network response was not ok: ${response.statusText}`)
      return response.json().catch(() => ({})) // Handle empty responses
    })
    .then(data => {
      if (data && data.success === false) {
        const errorMessage = `API error: ${data.message || 'Unknown error'}`
        if (onError) onError(new Error(errorMessage))
        else showToast(errorMessage, 'error')
        console.error('API error:', data)
        return
      }
      if (onSuccess) onSuccess(data)
    })
    .catch(error => {
      const errorMessage = `Error: ${error.message}`
      if (onError) onError(error)
      else showToast(errorMessage, 'error')
      console.error('API fetch error:', error)
    })
}

// --- WebSocket Input Client ---
let wsInput = null
let wsInputReady = false
const wsInputQueue = []

window.wsSendInput = function (obj) {
  if (wsInputReady && wsInput && wsInput.readyState === WebSocket.OPEN) {
    wsInput.send(JSON.stringify(obj))
  } else {
    wsInputQueue.push(obj)
  }
}

window.setupInputWebSocket = function () {
  const wsUrl = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws/input'
  wsInput = new WebSocket(wsUrl)
  wsInputReady = false

  wsInput.onopen = function () {
    console.log('WebSocket connected')
    wsInputReady = true
    while (wsInputQueue.length > 0) {
      window.wsSendInput(wsInputQueue.shift())
    }
  }

  wsInput.onclose = function () {
    console.log('WebSocket disconnected, attempting to reconnect...')
    wsInputReady = false
    setTimeout(window.setupInputWebSocket, 2000) // Reconnect after 2 seconds
  }

  wsInput.onerror = function (error) {
    console.error('WebSocket error:', error)
    wsInput.close()
  }

  wsInput.onmessage = function (ev) {
    try {
      const msg = JSON.parse(ev.data)
      console.log('WS message received:', msg)

      // Handle device status messages
      if (msg.type === 'device_status') {
        handleDeviceStatus(msg.video)
      }
      // Handle other message types
      else if (msg.type === 'warning') {
        showToast(msg.message, 'warning')
      }
      else if (msg.type === 'info') {
        showToast(msg.message, 'info')
      }
      else if (msg.type === 'error') {
        showToast(msg.message, 'error')
      }
    } catch (e) {
      console.error('Failed to parse WebSocket message:', e)
    }
  }
}

// --- Input Event Senders ---
window.sendKey = (key) => window.wsSendInput({ type: 'key_press', key })
window.sendCombination = (modifiers, keys) => window.wsSendInput({ type: 'key_combination', modifiers, keys })
window.sendMouseClick = (button) => window.wsSendInput({ type: 'mouse_click', button })
window.sendMousePress = (button) => window.wsSendInput({ type: 'mouse_press', button })
window.sendMouseRelease = (button) => window.wsSendInput({ type: 'mouse_release', button })
window.sendMouseWheel = (delta) => window.wsSendInput({ type: 'mouse_wheel', delta })
window.sendMouseMove = (x, y, buttons = []) => window.wsSendInput({ type: 'mouse_move', x, y, buttons })
window.sendMouseAbsoluteMove = (x, y, buttons = []) => window.wsSendInput({ type: 'mouse_absolute', x, y, buttons })
window.sendText = (text) => {
  if (text) window.wsSendInput({ type: 'text', text })
}

// --- Keyboard Helpers ---
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
  if (key.startsWith('F') && key.length > 1 && !isNaN(key.substring(1))) return key.toLowerCase()
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

// --- Clipboard ---
window.pasteFromClipboard = async function () {
  try {
    const text = await navigator.clipboard.readText()
    if (text) {
      window.sendText(text)
      showToast('Pasted from clipboard.', 'success')
    }
  } catch (err) {
    console.error('Failed to read clipboard:', err)
    showToast('Clipboard access denied. Use manual paste.', 'error')
  }
}

// --- Fullscreen & Screenshot ---
window.toggleFullscreen = function () {
  const videoContainer = document.querySelector('.video-container')
  if (!document.fullscreenElement) {
    videoContainer.requestFullscreen().catch(err => {
      alert(`Error attempting to enable full-screen mode: ${err.message} (${err.name})`)
    })
  } else {
    document.exitFullscreen()
  }
}

window.takeScreenshot = function () {
  const videoStream = document.getElementById('videoStream') || document.getElementById('video-stream')
  if (!videoStream) return
  const canvas = document.createElement('canvas')
  canvas.width = videoStream.naturalWidth
  canvas.height = videoStream.naturalHeight
  const ctx = canvas.getContext('2d')
  ctx.drawImage(videoStream, 0, 0, canvas.width, canvas.height)
  const link = document.createElement('a')
  link.download = `kvm-screenshot-${new Date().toISOString()}.png`
  link.href = canvas.toDataURL()
  link.click()
}

// --- USB Mass Storage ---
window.refreshUsbImages = function () {
  window.apiFetch('/api/storage/images', {}, (data) => {
    const container = document.getElementById('usb-image-list')
    if (!container) return
    if (data.images && data.images.length > 0) {
      container.innerHTML = data.images.map(img => {
        const isSelected = img === data.selected
        const icon = isSelected ? 'eject' : 'play_arrow'
        const btnTitle = isSelected ? 'Detach' : 'Mount'
        return `
          <div class="usb-item ${isSelected ? 'selected' : ''}">
            <span class="usb-name" title="${img}">${img}</span>
            <button class="outline secondary" onclick="window.deleteUsbImage('${img}')" title="Delete" ${isSelected ? 'disabled' : ''}><span class="material-icons">delete</span></button>
            <button class="outline" onclick="${isSelected ? 'window.detachUsbImage()' : `window.selectUsbImage('${img}')`}" title="${btnTitle}"><span class="material-icons">${icon}</span></button>
          </div>`
      }).join('')
    } else {
      container.innerHTML = '<em>No disk images found.</em>'
    }
  })
}

window.selectUsbImage = (image) => window.apiFetch('/api/storage/select', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image }) }, () => { window.refreshUsbImages(); window.updateStatus() })
window.detachUsbImage = () => window.apiFetch('/api/storage/select', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ image: null }) }, () => { window.refreshUsbImages(); window.updateStatus() })
window.deleteUsbImage = (filename) => {
  if (confirm(`Are you sure you want to delete ${filename}?`)) {
    window.apiFetch(`/api/storage/images/${filename}`, { method: 'DELETE' }, (data) => {
      showToast(data.message, 'success')
      window.refreshUsbImages()
    })
  }
}

window.uploadUsbImage = function () {
  const uploadInput = document.getElementById('usb-upload-input')
  const file = uploadInput.files[0]
  if (!file) {
    showToast('No file selected.', 'error')
    return
  }
  const formData = new FormData()
  formData.append('file', file)
  const xhr = new XMLHttpRequest()
  xhr.open('POST', '/api/storage/upload', true)
  xhr.onload = () => {
    if (xhr.status >= 200 && xhr.status < 300) {
      const response = JSON.parse(xhr.responseText)
      showToast(response.message, response.success ? 'success' : 'error')
      if (response.success) window.refreshUsbImages()
    } else {
      showToast(`Upload failed: ${xhr.statusText}`, 'error')
    }
    uploadInput.value = ''
  }
  xhr.onerror = () => { showToast('Upload failed due to a network error.', 'error'); uploadInput.value = '' }
  xhr.send(formData)
}

// --- Ethernet ---
window.setEthernet = (enable) => window.apiFetch(`/api/ethernet/${enable ? 'enable' : 'disable'}`, { method: 'POST' }, () => window.updateStatus())

// --- Status Update ---
window.updateStatus = function () {
  window.apiFetch('/api/status', {}, (data) => {
    // Handle disabled features
    if (data.disabled) {
      // Show/hide USB storage section
      const usbSection = document.getElementById('section-usb')
      if (usbSection) {
        usbSection.style.display = data.disabled.mass_storage ? 'none' : ''
      }

      // Show/hide ethernet controls
      const ethernetControl = document.getElementById('ethernet-control')
      if (ethernetControl) {
        ethernetControl.style.display = data.disabled.ethernet ? 'none' : ''
      }

      // Show/hide network section in mobile
      const networkSection = document.getElementById('section-network')
      if (networkSection) {
        networkSection.style.display = data.disabled.ethernet ? 'none' : ''
      }

      // Show/hide mouse section in mobile
      const mouseSection = document.getElementById('section-mouse')
      if (mouseSection) {
        mouseSection.style.display = data.disabled.mouse ? 'none' : ''
      }

      // Disable mouse events if mouse is disabled
      if (data.disabled.mouse) {
        window.sendMouseClick = () => {}
        window.sendMousePress = () => {}
        window.sendMouseRelease = () => {}
        window.sendMouseWheel = () => {}
        window.sendMouseMove = () => {}
        window.sendMouseAbsoluteMove = () => {}
      }
    }

    // Video Status (Desktop only)
    const videoStatus = document.getElementById('video-status')
    if (videoStatus) {
      if (data.video?.status === 'running') {
        videoStatus.innerHTML = `<span class="material-icons">monitor</span> ${data.video.resolution}@${data.video.fps}fps`
      } else {
        videoStatus.innerHTML = '<span class="material-icons">videocam_off</span> Stopped'
      }
    }

    // Video Quality Menu (Desktop and Mobile)
    if (data.video) {
      window.updateVideoQualityMenu(data.video.qualities, data.video.selected_quality, data.video.jpeg_quality)
    }

    // FPS
    const fpsIndicator = document.getElementById('fps-indicator')
    if (fpsIndicator) fpsIndicator.innerHTML = `<span class="material-icons">timer</span> FPS: ${data.video?.actual_fps?.toFixed(1) || '--'}`
    // Latency
    const latencyIndicator = document.getElementById('latency-indicator')
    if (latencyIndicator) window.measureLatency()
    // Keyboard
    const keyboardStatus = document.getElementById('keyboard-status')
    if (keyboardStatus) keyboardStatus.classList.toggle('active', data.keyboard?.enabled)
    // Mouse
    const mouseStatus = document.getElementById('mouse-status')
    if (mouseStatus) mouseStatus.classList.toggle('active', data.mouse?.enabled)
    // Storage
    const storageStatus = document.getElementById('storage-status')
    if (storageStatus) storageStatus.classList.toggle('active', data.storage?.attached)
    // Ethernet
    const ethSwitch = document.getElementById('ethernet-switch')
    const ethStatusLabel = document.getElementById('ethernet-status-label')
    const ethIfname = document.getElementById('ethernet-ifname')
    const ethStatusIcon = document.getElementById('ethernet-status-icon')
    const ethStatusBar = document.getElementById('ethernet-status-bar')

    if (ethSwitch) {
      ethSwitch.checked = data.ecm?.enabled
    }

    if (ethStatusLabel) {
      ethStatusLabel.textContent = data.ecm?.enabled ? 'Enabled' : 'Disabled'
    }

    if (ethIfname) {
      if (data.ecm?.enabled && data.ecm?.up) {
        ethIfname.textContent = `IP: ${data.ecm.ip || 'N/A'}`
      } else if (data.ecm?.enabled && !data.ecm?.up) {
        ethIfname.textContent = 'Interface Down'
      } else {
        ethIfname.textContent = ''
      }
    }

    if (ethStatusIcon) {
      if (data.ecm?.enabled && data.ecm?.up) {
        ethStatusIcon.style.color = '#4ade80' // Green
      } else if (data.ecm?.enabled && !data.ecm?.up) {
        ethStatusIcon.style.color = '#facc15' // Yellow/Orange for enabled but down
      } else {
        ethStatusIcon.style.color = '#ef4444' // Red for disabled
      }
    }

    if (ethStatusBar) {
      ethStatusBar.classList.toggle('active', data.ecm?.up)
    }
  })
}

// --- Video Quality Menu ---
window.updateVideoQualityMenu = function (qualities = [], selected, jpegQuality) {
  const list = document.getElementById('video-quality-list')
  if (!list) return
  list.innerHTML = '' // Clear existing
  qualities.forEach(q => {
    const li = document.createElement('li')
    li.textContent = q
    if (q === selected) li.classList.add('selected')
    li.onclick = () => { if (q !== selected) window.changeVideoQuality(q); window.hideVideoQualityMenu() }
    list.appendChild(li)
  })
}

window.changeVideoQuality = (quality) => window.apiFetch('/api/video/quality', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ quality }) }, () => setTimeout(window.updateStatus, 500))
window.hideVideoQualityMenu = () => document.getElementById('video-quality-menu')?.classList.remove('active')
window.showVideoQualityMenu = () => {
  const menu = document.getElementById('video-quality-menu')
  if (menu) {
    menu.classList.add('active')
    document.addEventListener('click', (e) => {
      if (!menu.contains(e.target) && e.target.id !== 'video-quality-btn') {
        window.hideVideoQualityMenu()
      }
    }, { once: true })
  }
}

// --- Latency Measurement ---
window.measureLatency = () => window.apiFetch('/api/latency-test', {}, (data) => {
  if (data.timestamp) {
    const latency = Date.now() - data.timestamp
    const indicator = document.getElementById('latency-indicator')
    if (indicator) indicator.innerHTML = `<span class="material-icons">speed</span> ${latency}ms`
  }
})

// --- Initial Setup ---
document.addEventListener('DOMContentLoaded', () => {
  window.setupInputWebSocket()

  // Theme switch logic
  const themeSwitch = document.getElementById('theme-switch')
  const currentTheme = localStorage.getItem('theme')

  const applyTheme = (theme) => {
    document.documentElement.dataset.theme = theme
    localStorage.setItem('theme', theme)
    themeSwitch.checked = (theme === 'dark')
  }

  // Set initial theme based on localStorage or system preference
  if (currentTheme) {
    applyTheme(currentTheme)
  } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    applyTheme('dark')
  } else {
    applyTheme('light')
  }

  themeSwitch.addEventListener('change', () => {
    applyTheme(themeSwitch.checked ? 'dark' : 'light')
  })

  // Specific initializations will be in script.js and mobile.js
})
