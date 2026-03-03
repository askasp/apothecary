// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/apothecary"
import topbar from "../vendor/topbar"

let Hooks = {
  ...colocatedHooks,
  DashboardKeys: {
    mounted() {
      this.el.focus()

      // Block hotkeys when typing in an input/textarea so keys like 's'
      // don't trigger hotkey actions. Capture phase runs before LiveView's
      // phx-window-keydown handler. Allow Escape through for closing overlays.
      // Also allow native OS shortcuts (Cmd/Ctrl+C, V, X, A, etc.) to work
      // everywhere by blocking propagation when modifier keys are held.
      window.addEventListener("keydown", (e) => {
        if (e.metaKey || e.ctrlKey) {
          e.stopPropagation()
          return
        }
        const tag = e.target.tagName
        const isInput = tag === "INPUT" || tag === "TEXTAREA" || e.target.isContentEditable
        if (isInput && e.key !== "Escape" && e.key !== "Enter") {
          e.stopPropagation()
        }
      }, true)

      this.handleEvent("focus-element", ({ selector }) => {
        const el = document.querySelector(selector)
        if (el) el.focus()
      })
      this.handleEvent("scroll-to-selected", () => {
        const el = document.querySelector("[data-selected]")
        if (el) el.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" })
      })
      this.handleEvent("blur-input", () => {
        if (document.activeElement) document.activeElement.blur()
        this.el.focus()
      })
      this.handleEvent("scroll-to-diff-file", () => {
        const el = document.querySelector("[data-diff-selected]")
        if (el) el.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" })
      })
      this.handleEvent("set-input-value", ({ selector, value }) => {
        const el = document.querySelector(selector)
        if (el) {
          el.value = value
          el.dispatchEvent(new Event("input", { bubbles: true }))
        }
      })
    },
    updated() {
      if (!document.activeElement || document.activeElement === document.body) {
        this.el.focus()
      }
    }
  },
  TextareaSubmit: {
    mounted() {
      this.mentionActive = false
      this.mentionStart = -1
      this.selectedIndex = 0
      this.results = []

      this.dropdown = document.getElementById("file-autocomplete-dropdown")

      this.el.addEventListener("keydown", (e) => {
        if (this.mentionActive && this.results.length > 0) {
          if (e.key === "ArrowDown") {
            e.preventDefault()
            this.selectedIndex = (this.selectedIndex + 1) % this.results.length
            this.renderDropdown()
            return
          }
          if (e.key === "ArrowUp") {
            e.preventDefault()
            this.selectedIndex = (this.selectedIndex - 1 + this.results.length) % this.results.length
            this.renderDropdown()
            return
          }
          if (e.key === "Tab" || e.key === "Enter") {
            e.preventDefault()
            this.selectFile(this.results[this.selectedIndex])
            return
          }
          if (e.key === "Escape") {
            e.preventDefault()
            this.closeMention()
            return
          }
        }

        if (e.key === "Enter" && !e.shiftKey && !this.mentionActive) {
          e.preventDefault()
          const text = this.el.value.trim()
          if (text) {
            this.pushEvent("submit-input", { text })
            this.el.value = ""
          }
        }
      })

      this.el.addEventListener("input", () => {
        const pos = this.el.selectionStart
        const text = this.el.value.substring(0, pos)

        // Find the last @ that starts a mention (after whitespace or at start)
        const match = text.match(/(^|[\s\n])@([^\s]*)$/)
        if (match) {
          const query = match[2]
          this.mentionStart = pos - query.length - 1 // -1 for the @
          this.mentionQuery = query

          if (query.length >= 1) {
            this.pushEvent("file-search", { query }, (reply) => {
              this.results = reply.files || []
              this.selectedIndex = 0
              if (this.results.length > 0) {
                this.mentionActive = true
                this.renderDropdown()
              } else {
                this.closeMention()
              }
            })
          } else {
            // Just typed @, show nothing until they type more
            this.closeMention()
          }
        } else {
          this.closeMention()
        }
      })

      // Close on click outside
      document.addEventListener("click", (e) => {
        if (!this.el.contains(e.target) && this.dropdown && !this.dropdown.contains(e.target)) {
          this.closeMention()
        }
      })
    },

    selectFile(filePath) {
      if (!filePath) return
      const before = this.el.value.substring(0, this.mentionStart)
      const after = this.el.value.substring(this.el.selectionStart)
      this.el.value = before + "@" + filePath + " " + after
      const newPos = this.mentionStart + 1 + filePath.length + 1
      this.el.selectionStart = newPos
      this.el.selectionEnd = newPos
      this.el.focus()
      this.closeMention()
    },

    closeMention() {
      this.mentionActive = false
      this.results = []
      this.selectedIndex = 0
      if (this.dropdown) {
        this.dropdown.classList.add("hidden")
        this.dropdown.innerHTML = ""
      }
    },

    renderDropdown() {
      if (!this.dropdown || this.results.length === 0) return
      this.dropdown.classList.remove("hidden")

      this.dropdown.innerHTML = this.results.map((file, i) => {
        const parts = file.split("/")
        const fileName = parts.pop()
        const dir = parts.join("/")
        const isSelected = i === this.selectedIndex
        return `<div class="file-ac-item ${isSelected ? "file-ac-selected" : ""}" data-index="${i}">
          <span class="file-ac-name">${this.escapeHtml(fileName)}</span>
          ${dir ? `<span class="file-ac-dir">${this.escapeHtml(dir)}/</span>` : ""}
        </div>`
      }).join("")

      // Scroll selected into view
      const selected = this.dropdown.querySelector(".file-ac-selected")
      if (selected) selected.scrollIntoView({ block: "nearest" })

      // Click handlers
      this.dropdown.querySelectorAll(".file-ac-item").forEach(item => {
        item.addEventListener("mousedown", (e) => {
          e.preventDefault()
          const idx = parseInt(item.dataset.index)
          this.selectFile(this.results[idx])
        })
        item.addEventListener("mouseenter", () => {
          this.selectedIndex = parseInt(item.dataset.index)
          this.renderDropdown()
        })
      })
    },

    escapeHtml(text) {
      const div = document.createElement("div")
      div.textContent = text
      return div.innerHTML
    }
  },
  InlineSubmit: {
    mounted() {
      this.el.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault()
          const form = this.el.closest("form")
          if (form && this.el.value.trim()) {
            form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
            this.el.value = ""
          }
        }
      })
    }
  },
  ScrollBottom: {
    mounted() {
      this.scrollToBottom()
      this.observer = new MutationObserver(() => this.scrollToBottom())
      this.observer.observe(this.el, { childList: true, subtree: true })
    },
    updated() {
      this.scrollToBottom()
    },
    destroyed() {
      if (this.observer) this.observer.disconnect()
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#34d399"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

