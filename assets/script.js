/* global document, window, localStorage, navigator, Audio */
/* global setupInputWebSocket, updateStatus, refreshUsbImages, measureLatency, takeScreenshot, toggleFullscreen, pasteFromClipboard, sendCombination, sendMousePress, sendMouseRelease, sendMouseMove, keyEventToHIDKey, getModifiers, sendMouseWheel */

// --- Desktop-Specific Initializations ---
document.addEventListener('DOMContentLoaded', () => {
  // Initialize common components
  setupInputWebSocket()
  updateStatus()
  refreshUsbImages()
  setInterval(updateStatus, 2000)
  setInterval(measureLatency, 5000)

  // Desktop-specific features
  setupDesktopVideoStream('video-stream')
  setupSidebar()
  setupDesktopShortcuts()
  setupAudioToggle()
  setupDesktopControls()

  // Service worker
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/assets/service-worker.js')
    })
  }
})

// --- Desktop Video Stream Handling ---
function setupDesktopVideoStream (videoElementId) {
  const video = document.getElementById(videoElementId)
  if (!video) return

  // MJPEG auto-reconnect
  const baseSrc = video.src.split('?')[0]
  let reconnecting = false
  function tryReconnect () {
    if (reconnecting) return
    reconnecting = true
    video.src = '' // Force drop connection
    setTimeout(() => {
      video.src = `${baseSrc}?_=${Date.now()}` // Reconnect with cache-busting
      reconnecting = false
    }, 2000)
  }
  video.addEventListener('error', tryReconnect)
  video.addEventListener('load', () => { if (video.naturalWidth === 0) tryReconnect() })

  // Pointer lock for input capture
  video.addEventListener('click', (e) => {
    e.preventDefault()
    video.requestPointerLock()
  })

  document.addEventListener('pointerlockchange', () => {
    const isLocked = document.pointerLockElement === video
    video.classList.toggle('pointer-locked', isLocked)
    document.getElementById('input-status').textContent = isLocked ? 'Input Active (ESC to release)' : ''
    if (!isLocked) {
      // Release any pressed mouse buttons when pointer lock is lost
      window.pressedButtons.forEach(button => sendMouseRelease(button))
      window.pressedButtons.clear()
    }
  })

  // Mouse and keyboard event listeners
  window.pressedButtons = new Set()
  video.addEventListener('mousemove', (e) => { if (document.pointerLockElement === video) sendMouseMove(e.movementX, e.movementY, Array.from(window.pressedButtons)) })
  video.addEventListener('mousedown', (e) => { if (document.pointerLockElement === video) { e.preventDefault(); const button = e.button === 0 ? 'left' : e.button === 1 ? 'middle' : 'right'; window.pressedButtons.add(button); sendMousePress(button) } })
  video.addEventListener('mouseup', (e) => { if (document.pointerLockElement === video) { e.preventDefault(); const button = e.button === 0 ? 'left' : e.button === 1 ? 'middle' : 'right'; window.pressedButtons.delete(button); sendMouseRelease(button) } })
  video.addEventListener('wheel', (e) => { if (document.pointerLockElement === video) { e.preventDefault(); sendMouseWheel(e.deltaY > 0 ? -1 : 1) } })
  video.addEventListener('contextmenu', (e) => e.preventDefault())

  // Keyboard events are handled globally when pointer is locked
  document.addEventListener('keydown', (e) => {
    if (document.pointerLockElement === video) {
      const hidKey = keyEventToHIDKey(e)
      if (hidKey) {
        e.preventDefault()
        sendCombination(getModifiers(e), [hidKey])
      }
    }
  })
}

// --- Desktop Sidebar ---
function setupSidebar () {
  const sidebar = document.getElementById('sidebar')
  const toggle = document.getElementById('sidebar-toggle')

  const setSidebarState = (collapsed) => {
    sidebar.classList.toggle('collapsed', collapsed)
    toggle.innerHTML = collapsed ? '‹' : '›'
    localStorage.setItem('sidebarCollapsed', collapsed)
  }

  toggle.addEventListener('click', () => setSidebarState(!sidebar.classList.contains('collapsed')))

  document.addEventListener('click', (e) => {
    if (!sidebar.contains(e.target) && e.target !== toggle) {
      setSidebarState(true)
    }
  })

  // Load initial state
  setSidebarState(localStorage.getItem('sidebarCollapsed') === 'true')

  // Status bar icon clicks to open sidebar sections
  document.getElementById('keyboard-status')?.addEventListener('click', () => openSidebarSection('section-text'))
  document.getElementById('mouse-status')?.addEventListener('click', () => openSidebarSection('section-mouse'))
  document.getElementById('storage-status')?.addEventListener('click', () => openSidebarSection('section-usb'))
  document.getElementById('ethernet-status-bar')?.addEventListener('click', () => openSidebarSection('section-ethernet'))
}

function openSidebarSection (sectionId) {
  const sidebar = document.getElementById('sidebar')
  sidebar.classList.remove('collapsed')
  document.getElementById('sidebar-toggle').innerHTML = '›'
  localStorage.setItem('sidebarCollapsed', false)
  document.querySelectorAll('#sidebar details').forEach(d => {
    d.open = d.id === sectionId
  })
}

function setupDesktopControls () {
  const videoQualityBtn = document.getElementById('video-quality-btn')
  if (videoQualityBtn) {
    videoQualityBtn.addEventListener('click', (e) => {
      e.stopPropagation()
      const menu = document.getElementById('video-quality-menu')
      if (menu.classList.contains('active')) {
        window.hideVideoQualityMenu()
      } else {
        window.showVideoQualityMenu()
      }
    })
  }
}

// --- Desktop Global Shortcuts ---
function setupDesktopShortcuts () {
  document.addEventListener('keydown', (e) => {
    if (document.pointerLockElement) return // Don't trigger global shortcuts when video has focus

    if (e.key === 'F11' || (e.ctrlKey && e.key === 'f')) {
      e.preventDefault()
      toggleFullscreen()
    }
    if ((e.ctrlKey || e.altKey) && e.key === 's') {
      e.preventDefault()
      takeScreenshot()
    }
    if (e.ctrlKey && e.shiftKey && e.key === 'V') {
      e.preventDefault()
      pasteFromClipboard()
    }
  })
}

// --- Audio ---
function setupAudioToggle () {
  let audioStream = null
  let audioLatencyInterval = null

  const manageAudioLatency = (audioElement) => {
    if (audioLatencyInterval) clearInterval(audioLatencyInterval)
    audioLatencyInterval = setInterval(() => {
      if (audioElement.buffered.length > 0) {
        const bufferEnd = audioElement.buffered.end(audioElement.buffered.length - 1)
        const latency = bufferEnd - audioElement.currentTime
        if (latency > 1.0) {
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
      audioStream = null
      icon.textContent = 'volume_off'
      audioBtn.classList.remove('active')
    } else {
      audioStream = new Audio('/audio.ogg')
      audioStream.play().catch(e => console.error('Audio play failed:', e))
      audioStream.onplay = () => {
        icon.textContent = 'volume_up'
        audioBtn.classList.add('active')
        manageAudioLatency(audioStream)
      }
      audioStream.onerror = () => {
        window.toggleAudio() // Turn it off on error
        window.showToast('Audio stream failed to load.', 'error')
      }
    }
  }
}
