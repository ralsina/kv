// Unified show/hideVideoQualityMenu for desktop and mobile
window.showVideoQualityMenu = function () {
  const menu = document.getElementById('video-quality-menu')
  if (!menu) return
  menu.classList.add('active')
  document.addEventListener('mousedown', window.hideVideoQualityMenuOnClick)
}

window.hideVideoQualityMenuOnClick = function (e) {
  const menu = document.getElementById('video-quality-menu')
  if (!menu) return
  if (!menu.contains(e.target) && e.target.id !== 'video-quality-btn') {
    menu.classList.remove('active')
    document.removeEventListener('mousedown', window.hideVideoQualityMenuOnClick)
  }
}

window.hideVideoQualityMenu = function () {
  const menu = document.getElementById('video-quality-menu')
  if (menu) menu.classList.remove('active')
  document.removeEventListener('mousedown', window.hideVideoQualityMenuOnClick)
}
// Unified measureLatency for desktop and mobile
window.measureLatency = function () {
  window.apiFetch('/api/latency-test', {}, (data) => {
    if (data.success && data.timestamp) {
      const latency = Date.now() - data.timestamp
      const latencyIndicator = document.getElementById('latency-indicator')
      if (latencyIndicator) {
        latencyIndicator.innerHTML = `<span class="material-icons">speed</span>${latency}ms`
      }
    }
  })
}
// Unified initializeVideo for desktop and mobile
window.initializeVideo = function () {
  // Try both possible video element IDs
  const videoStream = document.getElementById('videoStream') || document.getElementById('video-stream')
  if (videoStream) {
    videoStream.addEventListener('click', () => {
      if (videoStream.requestPointerLock) {
        videoStream.requestPointerLock()
      }
      window.pointerLocked = true
      window.videoFocused = true
      videoStream.classList.add('pointer-locked')
    })
    document.addEventListener('pointerlockchange', () => {
      if (document.pointerLockElement === videoStream) {
        window.pointerLocked = true
        window.videoFocused = true
        videoStream.classList.add('pointer-locked')
      } else {
        window.pointerLocked = false
        window.videoFocused = false
        videoStream.classList.remove('pointer-locked')
      }
    })
  }
}
/* eslint-disable no-unused-vars */
/* global sendMouseRelease, sendMousePress, keyEventToHIDKey, getModifiers, sendMouseWheel, wsSendInput, setupInputWebSocket, sendKey, sendCombination, sendMouseClick, sendSingleMouseMove, sendText, pasteFromClipboard, WebSocket, location, prompt, refreshUsbImages, uploadUsbImage, detachUsbImage, setEthernet, XMLHttpRequest, updateStatus, confirm */
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

// --- Unified API Fetch Helper ---
window.apiFetch = function (endpoint, options = {}, onSuccess, onError) {
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
let videoFocused = false
let pointerLocked = false
const pressedButtons = new Set()

window.setupVideoCapture = function (videoElementId) {
  const video = document.getElementById(videoElementId)
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
    if (pointerLocked) {
      window.sendSingleMouseMove(e.movementX, e.movementY)
    }
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
    if (text) wsSendInput({ type: 'text', text })
  })
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
  const text = textInput.value
  if (!text) return
  wsSendInput({ type: 'text', text })
  textInput.value = ''
}

window.pasteFromClipboard = async function () {
  try {
    const text = await navigator.clipboard.readText()
    if (text) {
      wsSendInput({ type: 'text', text })
      console.log('Pasted text:', text.substring(0, 50) + (text.length > 50 ? '...' : ''))
    }
  } catch (err) {
    console.error('Failed to read clipboard:', err)
    // Fallback: show a prompt for manual paste
    const text = prompt('Paste your text here (automatic clipboard access not available):')
    if (text) {
      wsSendInput({ type: 'text', text })
    }
  }
}

// --- USB Mass Storage ---
window.refreshUsbImages = function () {
  window.apiFetch(
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
  window.apiFetch(
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
  window.apiFetch(
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
    .catch(function (error) {
      console.error('Error deleting USB image:', error)
      showToast('Error deleting USB image.', 'error')
    })
}

window.uploadUsbImage = function () {
  const uploadInput = document.getElementById('usb-upload-input')
  const uploadProgress = document.getElementById('usb-upload-progress')
  const uploadStatus = document.getElementById('usb-upload-status')

  if (!uploadInput || !uploadInput.files || uploadInput.files.length === 0) {
    showToast('No file selected for upload.', 'error')
    return
  }

  const file = uploadInput.files[0]
  const formData = new FormData()
  formData.append('file', file)

  uploadProgress.value = 0
  uploadProgress.style.display = 'block'
  uploadStatus.textContent = 'Uploading...'

  const xhr = new XMLHttpRequest()

  xhr.upload.addEventListener('progress', (event) => {
    if (event.lengthComputable) {
      const percent = (event.loaded / event.total) * 100
      uploadProgress.value = percent
      uploadStatus.textContent = `Uploading: ${percent.toFixed(0)}%`
    }
  })

  xhr.addEventListener('load', () => {
    uploadProgress.style.display = 'none'
    if (xhr.status >= 200 && xhr.status < 300) {
      const response = JSON.parse(xhr.responseText)
      if (response.success) {
        showToast(response.message, 'success')
        uploadStatus.textContent = 'Upload complete!'
        refreshUsbImages() // Refresh the list after successful upload
      } else {
        showToast(`Upload failed: ${response.message}`, 'error')
        uploadStatus.textContent = `Upload failed: ${response.message}`
      }
    } else {
      showToast(`Upload failed: Server responded with status ${xhr.status}`, 'error')
      uploadStatus.textContent = `Upload failed: ${xhr.status}`
    }
    uploadInput.value = '' // Clear the file input
  })

  xhr.addEventListener('error', () => {
    uploadProgress.style.display = 'none'
    showToast('Upload failed: Network error.', 'error')
    uploadStatus.textContent = 'Upload failed: Network error.'
    uploadInput.value = ''
  })

  xhr.addEventListener('abort', () => {
    uploadProgress.style.display = 'none'
    showToast('Upload aborted.', 'error')
    uploadStatus.textContent = 'Upload aborted.'
    uploadInput.value = ''
  })

  xhr.open('POST', '/api/storage/upload')
  xhr.send(formData)
}

// ECM/Ethernet enable/disable controls
window.setEthernet = function (enable) {
  window.apiFetch(
    '/api/ethernet/' + (enable ? 'enable' : 'disable'),
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    },
    () => { updateStatus() },
    (err) => {
      showToast('Failed to set ethernet: ' + (err.message || err?.message || 'Unknown error'), 'error')
      console.error('Failed to set ethernet:', err)
    }
  )
}

window.updateStatus = function () {
  window.apiFetch(
    '/api/status',
    {},
    (data) => {
      // Video Status
      const videoStatusElem = document.getElementById('video-status')
      if (videoStatusElem) {
        if (data.video && data.video.status === 'running') {
          videoStatusElem.innerHTML = `<span class="material-icons">monitor</span>Video: ${data.video.resolution} @ ${data.video.fps}fps`
          window.updateVideoQualityMenu(data.video.qualities, data.video.selected_quality, data.video.jpeg_quality)
        } else {
          videoStatusElem.innerHTML = '<span class="material-icons">videocam_off</span>Video: Stopped'
          window.updateVideoQualityMenu(data.video.qualities, data.video.selected_quality, data.video.jpeg_quality)
        }
      }

      // FPS Indicator
      const fpsIndicator = document.getElementById('fps-indicator')
      if (fpsIndicator) {
        if (data.video && data.video.actual_fps) {
          fpsIndicator.innerHTML = `<span class="material-icons">timer</span>FPS:${data.video.actual_fps.toFixed(2)}`
        } else {
          fpsIndicator.innerHTML = '<span class="material-icons">timer</span>FPS:--'
        }
      }

      // Keyboard Status
      const keyboardStatusElem = document.getElementById('keyboard-status')
      if (keyboardStatusElem) {
        if (data.keyboard && data.keyboard.enabled) {
          keyboardStatusElem.innerHTML = '<span class="material-icons" style="color: #4ade80;">keyboard</span>'
        } else {
          keyboardStatusElem.innerHTML = '<span class="material-icons" style="color: #ef4444;">keyboard_off</span>'
        }
      }

      // Mouse Status
      const mouseStatusElem = document.getElementById('mouse-status')
      if (mouseStatusElem) {
        if (data.mouse && data.mouse.enabled) {
          mouseStatusElem.innerHTML = '<span class="material-icons" style="color: #4ade80;">mouse</span>'
        } else {
          mouseStatusElem.innerHTML = '<span class="material-icons" style="color: #ef4444;">mouse_off</span>'
        }
      }

      // Storage Status
      const storageStatusElem = document.getElementById('storage-status')
      if (storageStatusElem) {
        if (data.storage && data.storage.attached) {
          storageStatusElem.innerHTML = '<span class="material-icons" style="color: #4ade80;">usb</span>'
        } else {
          storageStatusElem.innerHTML = '<span class="material-icons" style="color: #ef4444;">usb_off</span>'
        }
      }

      // Ethernet Status
      const ethernetStatusElem = document.getElementById('ethernet-status-bar')
      const ethernetSwitch = document.getElementById('ethernet-switch')
      const ethernetIfname = document.getElementById('ethernet-ifname')
      const ethernetStatusIcon = document.getElementById('ethernet-status-icon')
      const ethernetStatusLabel = document.getElementById('ethernet-status-label')

      if (ethernetSwitch) {
        if (data.ecm && data.ecm.enabled) {
          ethernetSwitch.checked = true
          if (ethernetStatusLabel) ethernetStatusLabel.textContent = 'Enabled'
          if (ethernetStatusIcon) ethernetStatusIcon.style.color = '#4ade80'
          if (data.ecm.up) {
            if (ethernetStatusElem) ethernetStatusElem.innerHTML = '<span class="material-icons" style="color: #4ade80;">cable</span>'
            if (ethernetIfname) ethernetIfname.textContent = `IP: ${data.ecm.ip || 'N/A'}`
          } else {
            if (ethernetStatusElem) ethernetStatusElem.innerHTML = '<span class="material-icons" style="color: #facc15;">cable</span>'
            if (ethernetIfname) ethernetIfname.textContent = 'Interface Down'
          }
        } else {
          ethernetSwitch.checked = false
          if (ethernetStatusLabel) ethernetStatusLabel.textContent = 'Disabled'
          if (ethernetStatusIcon) ethernetStatusIcon.style.color = '#ef4444'
          if (ethernetStatusElem) ethernetStatusElem.innerHTML = '<span class="material-icons" style="color: #ef4444;">cable</span>'
          if (ethernetIfname) ethernetIfname.textContent = ''
        }
      }
    },
    (err) => {
      console.error('Error fetching status:', err)
      showToast('Error fetching status: ' + (err.message || err?.message || 'Unknown error'), 'error')
    }
  )
}

window.updateVideoQualityMenu = function (qualities, selected, jpegQuality) {
  const list = document.getElementById('video-quality-list')
  if (!list) return
  list.innerHTML = ''

  // Resolution options
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
      window.hideVideoQualityMenu()
    }
    list.appendChild(li)
  })

  // Separator
  const separator = document.createElement('li')
  separator.className = 'separator'
  list.appendChild(separator)

  // JPEG Quality submenu
  const jpegLi = document.createElement('li')
  jpegLi.className = 'has-submenu'
  jpegLi.innerHTML = '<span>JPEG Quality</span><span class="submenu-icon">»</span>'
  const submenu = document.createElement('ul')
  submenu.className = 'submenu'

  const jpegQualities = [100, 75, 50, 25]
  jpegQualities.forEach(q => {
    const subLi = document.createElement('li')
    subLi.textContent = `${q}%`
    if (q === jpegQuality) {
      subLi.classList.add('selected')
      subLi.innerHTML = '<span class="material-icons">check</span>' + subLi.innerHTML
    }
    subLi.onclick = (e) => {
      e.stopPropagation()
      if (q !== jpegQuality) {
        window.changeVideoQuality(`jpeg:${q}`)
      }
      window.hideVideoQualityMenu()
    }
    submenu.appendChild(subLi)
  })

  jpegLi.appendChild(submenu)
  list.appendChild(jpegLi)

  jpegLi.appendChild(submenu)
  list.appendChild(jpegLi)
}

window.changeVideoQuality = function (quality) {
  window.apiFetch(
    '/api/video/quality',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ quality })
    },
    () => {
      setTimeout(() => window.initializeVideo(), 500)
      setTimeout(() => window.updateStatus(), 1000)
    },
    (err) => {
      showToast('Failed to change video quality: ' + (err.message || err?.message || 'Unknown error'), 'error')
      console.error('Error changing video quality:', err)
    }
  )
}

// Initial fetch and update on load
document.addEventListener('DOMContentLoaded', () => {
  refreshUsbImages()
  updateStatus()
})
/* eslint-enable no-unused-vars */
