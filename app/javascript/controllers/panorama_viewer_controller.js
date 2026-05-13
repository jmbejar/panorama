// 360° equirectangular viewer for a completed PanoramaProject.
//
// Element shape:
//   <div data-controller="panorama-viewer"
//        data-panorama-viewer-image-url-value="/rails/active_storage/blobs/.../panorama_42.jpg">
//   </div>
//
// Drag horizontally to look around, vertically to tilt, scroll wheel to zoom.
// Falls back to a static <img> if WebGL is unavailable so the user still sees
// their panorama.
import { Controller } from "@hotwired/stimulus"
import * as THREE from "three"

const SPHERE_RADIUS = 500
// 60° vertical FOV ≈ 95° horizontal in a 2:1 container — close to how PSV /
// Marzipano default. 75° (the textbook three.js sphere viewer value) feels too
// wide-angle here, like edges-of-walls perspective. Min/max keep the user out
// of fisheye territory at one end and dolly-zoom-into-flatness at the other.
const INITIAL_FOV = 60
const MIN_FOV = 35
const MAX_FOV = 85
const ROTATE_SPEED = 0.15
const ZOOM_SPEED = 0.05
const LATITUDE_LIMIT = 85

export default class extends Controller {
  static values = { imageUrl: String }

  connect() {
    if (!this.#webglSupported()) {
      this.#renderFallback()
      return
    }
    this.#initScene()
    this.#bindControls()
    this.#bindResize()
    this.#loadTexture()
    this.#animate()
  }

  disconnect() {
    cancelAnimationFrame(this.frameId)
    this.controlsCleanup?.()
    window.removeEventListener("resize", this.onResize)
    this.renderer?.dispose()
    this.geometry?.dispose()
    this.material?.dispose()
    this.material?.map?.dispose()
    this.renderer?.domElement?.remove()
  }

  #webglSupported() {
    try {
      const canvas = document.createElement("canvas")
      return !!(window.WebGLRenderingContext &&
                (canvas.getContext("webgl") || canvas.getContext("experimental-webgl")))
    } catch (_e) {
      return false
    }
  }

  #renderFallback() {
    const img = document.createElement("img")
    img.src = this.imageUrlValue
    img.alt = "Stitched panorama"
    img.className = "w-full"
    this.element.appendChild(img)
  }

  #initScene() {
    this.lon = 0
    this.lat = 0
    this.targetLon = 0
    this.targetLat = 0
    this.fov = INITIAL_FOV
    this.targetFov = INITIAL_FOV

    const { clientWidth, clientHeight } = this.element

    this.scene = new THREE.Scene()
    this.camera = new THREE.PerspectiveCamera(this.fov, clientWidth / clientHeight, 1, 1100)
    this.camera.position.set(0, 0, 0.01)

    this.renderer = new THREE.WebGLRenderer({ antialias: true })
    this.renderer.setPixelRatio(window.devicePixelRatio)
    this.renderer.setSize(clientWidth, clientHeight)
    this.element.appendChild(this.renderer.domElement)

    this.geometry = new THREE.SphereGeometry(SPHERE_RADIUS, 60, 40)
    this.geometry.scale(-1, 1, 1) // turn the sphere inside-out
    this.material = new THREE.MeshBasicMaterial({ color: 0x111111 })
    this.mesh = new THREE.Mesh(this.geometry, this.material)
    this.scene.add(this.mesh)
  }

  #loadTexture() {
    if (!this.imageUrlValue) return

    new THREE.TextureLoader().load(
      this.imageUrlValue,
      (texture) => {
        texture.colorSpace = THREE.SRGBColorSpace
        this.material.map = texture
        this.material.color.set(0xffffff)
        this.material.needsUpdate = true
      }
    )
  }

  #bindControls() {
    let dragging = false
    let startX = 0
    let startY = 0
    let startLon = 0
    let startLat = 0

    const eventXY = (e) => {
      if (e.touches && e.touches[0]) return [ e.touches[0].clientX, e.touches[0].clientY ]
      return [ e.clientX, e.clientY ]
    }

    const onDown = (e) => {
      dragging = true
      const [ x, y ] = eventXY(e)
      startX = x; startY = y
      startLon = this.targetLon
      startLat = this.targetLat
      this.element.style.cursor = "grabbing"
    }

    const onMove = (e) => {
      if (!dragging) return
      const [ x, y ] = eventXY(e)
      this.targetLon = startLon - (x - startX) * ROTATE_SPEED
      this.targetLat = startLat + (y - startY) * ROTATE_SPEED
      this.targetLat = Math.max(-LATITUDE_LIMIT, Math.min(LATITUDE_LIMIT, this.targetLat))
    }

    const onUp = () => {
      dragging = false
      this.element.style.cursor = "grab"
    }

    const onWheel = (e) => {
      e.preventDefault()
      this.targetFov = Math.max(MIN_FOV, Math.min(MAX_FOV, this.targetFov + e.deltaY * ZOOM_SPEED))
    }

    this.element.style.cursor = "grab"
    this.element.addEventListener("pointerdown", onDown)
    window.addEventListener("pointermove", onMove)
    window.addEventListener("pointerup", onUp)
    this.element.addEventListener("wheel", onWheel, { passive: false })

    this.controlsCleanup = () => {
      this.element.removeEventListener("pointerdown", onDown)
      window.removeEventListener("pointermove", onMove)
      window.removeEventListener("pointerup", onUp)
      this.element.removeEventListener("wheel", onWheel)
    }
  }

  #bindResize() {
    this.onResize = () => {
      const { clientWidth, clientHeight } = this.element
      if (!clientWidth || !clientHeight) return
      this.camera.aspect = clientWidth / clientHeight
      this.camera.updateProjectionMatrix()
      this.renderer.setSize(clientWidth, clientHeight)
    }
    window.addEventListener("resize", this.onResize)
  }

  #animate = () => {
    this.frameId = requestAnimationFrame(this.#animate)

    this.lon += (this.targetLon - this.lon) * 0.15
    this.lat += (this.targetLat - this.lat) * 0.15
    this.fov += (this.targetFov - this.fov) * 0.15

    if (Math.abs(this.fov - this.camera.fov) > 0.01) {
      this.camera.fov = this.fov
      this.camera.updateProjectionMatrix()
    }

    const phi = THREE.MathUtils.degToRad(90 - this.lat)
    const theta = THREE.MathUtils.degToRad(this.lon)
    this.camera.lookAt(
      SPHERE_RADIUS * Math.sin(phi) * Math.cos(theta),
      SPHERE_RADIUS * Math.cos(phi),
      SPHERE_RADIUS * Math.sin(phi) * Math.sin(theta)
    )

    this.renderer.render(this.scene, this.camera)
  }
}
