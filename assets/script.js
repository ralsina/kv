// --- MJPEG Stream Auto-Reconnect Logic ---
let videoStream // Declare at top for global use
function setupMjpegAutoReconnect (imgElementId, streamUrl, retryDelayMs = 2000) {
  const img = document.getElementById(imgElementId)
  if (!img) return

  let lastErrorTime = 0
  let reconnecting = false

  function tryReconnect () {
    if (reconnecting) return
    reconnecting = true
    // Remove the old image to force browser to drop the connection
    img.src = ''
    setTimeout(() => {
      // Add a cache-busting query param to avoid browser caching
      img.src = streamUrl + '?_=' + Date.now()
      reconnecting = false
    }, retryDelayMs)
  }

  img.addEventListener('error', function onError () {
    // Only reconnect if enough time has passed since last error
    const now = Date.now()
    if (now - lastErrorTime > retryDelayMs) {
      lastErrorTime = now
      tryReconnect()
    }
  })

  // Also reconnect if the stream ends (some browsers fire 'load' on broken MJPEG)
  img.addEventListener('load', function onLoad () {
    // If the image loaded is very small or blank, try to reconnect
    if (img.naturalWidth === 0 || img.naturalHeight === 0) {
      tryReconnect()
    }
  })
}

function measureLatency () {
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

// Initialization on DOMContentLoaded
document.addEventListener('DOMContentLoaded', () => {
  videoStream = document.getElementById('video-stream') // Assign early

  // --- Setup MJPEG auto-reconnect for video stream ---
  if (videoStream) {
    // Use the current src as the stream URL (strip any cache-busting param)
    const baseSrc = videoStream.src.replace(/([?&]_=[0-9]+)/, '').replace(/([?&])$/, '')
    setupMjpegAutoReconnect('video-stream', baseSrc)
  }

  // Ensure sidebar summary elements are focusable for accessibility
  document.querySelectorAll('#sidebar details > summary').forEach(summary => {
    summary.setAttribute('tabindex', '0')
  })

  // Initialize functions that need to run on page load
  setupVideoCapture('video-stream')
  loadSidebarState()
  initializeVideo()
  refreshUsbImages() // Add this call
  updateStatus() // Add this call
  setInterval(updateStatus, 2000)
  setInterval(measureLatency, 5000)

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

  // Pointer lock and mouse capture on video click
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

  // Sidebar logic (now always present)
  const sidebar = document.getElementById('sidebar')
  const sidebarToggle = document.getElementById('sidebar-toggle')
  if (sidebarToggle) {
    sidebarToggle.addEventListener('click', () => {
      const isCollapsed = sidebar.classList.toggle('collapsed')
      sidebarToggle.innerHTML = isCollapsed ? '‹' : '›'
      saveSidebarState(isCollapsed)
    })
  }

  // Close sidebar when clicking outside of it
  document.addEventListener('click', (e) => {
    if (sidebar && sidebarToggle) {
      if (!sidebar.contains(e.target) && e.target !== sidebarToggle) {
        if (!sidebar.classList.contains('collapsed')) {
          sidebar.classList.add('collapsed')
          sidebarToggle.innerHTML = '‹'
          saveSidebarState(true)
        }
      }
    }
  })

  // Status bar icon click handlers
  const keyboardStatus = document.getElementById('keyboard-status')
  if (keyboardStatus) {
    keyboardStatus.addEventListener('click', e => {
      e.stopPropagation()
      if (sidebar && sidebarToggle) {
        sidebar.classList.remove('collapsed')
        sidebarToggle.innerHTML = '›'
        saveSidebarState(false)
      }
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
  }
  const mouseStatus = document.getElementById('mouse-status')
  if (mouseStatus) {
    mouseStatus.addEventListener('click', e => { e.stopPropagation(); openSidebarSection('section-mouse') })
  }
  const storageStatus = document.getElementById('storage-status')
  if (storageStatus) {
    storageStatus.addEventListener('click', e => { e.stopPropagation(); openSidebarSection('section-usb') })
  }
  const ethernetStatusBar = document.getElementById('ethernet-status-bar')
  if (ethernetStatusBar) {
    ethernetStatusBar.addEventListener('click', e => { e.stopPropagation(); openSidebarSection('section-ethernet') })
  }

  // Text input focus handler
  const textInput = document.getElementById('text-input')
  // videoStream already declared above; do not redeclare here
  if (textInput && videoStream) {
    textInput.addEventListener('focus', () => videoStream.blur())
  }

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
    document.addEventListener('mousedown', hideVideoQualityMenuOnClick, { once: true })
  }
}

function hideVideoQualityMenu () {
  const menu = document.getElementById('video-quality-menu')
  if (menu) menu.classList.remove('active')
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
      hideVideoQualityMenu()
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
      hideVideoQualityMenu()
    }
    submenu.appendChild(subLi)
  })

  jpegLi.appendChild(submenu)
  list.appendChild(jpegLi)
}

// --- Video Quality Selection ---
// window.loadVideoQualities is no longer needed and has been removed.

/* eslint-disable no-unused-vars */
/* global WebSocket, location, prompt, XMLHttpRequest, localStorage, alert, updateStatus, measureLatency, initializeVideo, updateFpsIndicator, wsSendInput, sendApiRequest, sendMousePress, sendMouseRelease, sendMouseWheel, sendSingleMouseMove, keyEventToHIDKey, getModifiers, pasteFromClipboard, handleFullscreenChange, takeScreenshot, refreshUsbImages, uploadUsbImage, openSidebarSection, loadSidebarState, saveSidebarState, showToast, videoFocused, pointerLocked, pressedButtons, setupVideoCapture, setupInputWebSocket, sendKey, sendCombination, sendMouseClick, sendMousePress, sendMouseRelease, sendMouseWheel, sendSingleMouseMove, sendText, pasteFromClipboard */
/* global confirm */

// ECM/Ethernet enable/disable controls
window.setEthernet = function (enable) {
  window.apiFetch(
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
    icon.textContent = 'volume_off'
    audioBtn.title = 'Start Audio'
    audioBtn.classList.remove('active')
  } else {
    audioStream = document.createElement('audio')
    audioStream.src = '/audio.ogg'
    audioStream.autoplay = false
    audioStream.style.display = 'none'

    audioStream.addEventListener('play', () => {
      icon.textContent = 'volume_up'
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
      icon.textContent = 'volume_off'
      audioBtn.title = 'Start Audio'
      audioBtn.classList.remove('active')
    })

    document.body.appendChild(audioStream)
    audioStream.play().catch(e => console.error('Audio play failed:', e))
  }
}

// --- Status & Video ---

window.initializeVideo = function () {
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

// --- USB Mass Storage ---
// Remove window.refreshUsbImages, window.selectUsbImage, window.detachUsbImage definitions here; use global from common.js

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
// Remove window.toggleFullscreen, window.handleFullscreenChange definitions here; use global from common.js
