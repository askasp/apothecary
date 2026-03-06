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

      // Theme: apply from localStorage on mount, sync changes
      this._applyTheme = (theme) => {
        const html = document.documentElement
        html.classList.add("theme-transitioning")
        html.classList.remove("theme-moonlight", "theme-studio", "theme-daylight")
        if (theme && theme !== "studio") {
          html.classList.add("theme-" + theme)
        }
        localStorage.setItem("apothecary-theme", theme)
        requestAnimationFrame(() => {
          setTimeout(() => html.classList.remove("theme-transitioning"), 250)
        })
      }

      // Restore from localStorage on first mount
      const stored = localStorage.getItem("apothecary-theme")
      if (stored && stored !== this.el.dataset.theme) {
        this.pushEvent("set-theme", { theme: stored })
      }
      this._applyTheme(stored || this.el.dataset.theme || "studio")

      // Block hotkeys when typing in an input/textarea so keys like 's'
      // don't trigger hotkey actions. Capture phase runs before LiveView's
      // phx-window-keydown handler. Allow Escape through for closing overlays.
      // Also allow native OS shortcuts (Cmd/Ctrl+C, V, X, A, etc.) to work
      // everywhere by blocking propagation when modifier keys are held.
      window.addEventListener("keydown", (e) => {
        const switcherOpen = document.querySelector("[data-project-switcher]")

        // In project switcher: let navigation keys reach LiveView
        if (switcherOpen) {
          if (e.key === "ArrowDown" || e.key === "ArrowUp" ||
              e.key === "j" || e.key === "k") {
            e.preventDefault()
            return
          }
          if ((e.ctrlKey || e.metaKey) && (e.key === "n" || e.key === "p" || e.key === "k")) {
            e.preventDefault()
            return
          }
          if (e.key === "Enter" || e.key === "Escape") {
            e.preventDefault()
            return
          }
        }

        // Ctrl+K / Cmd+K opens project switcher — let it through to LiveView
        if ((e.ctrlKey || e.metaKey) && e.key === "k") {
          e.preventDefault()
          return
        }

        // Allow Ctrl+N/P through when file autocomplete dropdown is visible
        if (e.metaKey || e.ctrlKey) {
          const fileDropdownVisible = document.querySelector("#file-autocomplete-dropdown:not(.hidden)")
          if (!(fileDropdownVisible && e.ctrlKey && (e.key === "n" || e.key === "p"))) {
            e.stopPropagation()
            return
          }
        }
        const tag = e.target.tagName
        const isInput = tag === "INPUT" || tag === "TEXTAREA" || e.target.isContentEditable
        if (isInput && e.key === "Escape") {
          // Blur immediately so subsequent j/k keys aren't blocked by the input check
          e.target.blur()
          this.el.focus()
        } else if (isInput && e.key !== "Enter" && e.key !== "Tab") {
          // Don't block Ctrl+N/P when file autocomplete is active
          const fileDropdownVisible = e.ctrlKey && (e.key === "n" || e.key === "p") &&
            document.querySelector("#file-autocomplete-dropdown:not(.hidden)")
          if (!fileDropdownVisible) e.stopPropagation()
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
      this.handleEvent("scroll-detail", ({ direction }) => {
        const el = document.getElementById("detail-pane")
        if (el) {
          const amount = direction === "down" ? 120 : -120
          el.scrollBy({ top: amount, behavior: "smooth" })
        }
      })
      this.handleEvent("focus-oracle-input", () => {
        const el = document.getElementById("oracle-input")
        if (el) el.focus()
      })
      this.handleEvent("focus-primary-input", () => {
        const el = document.getElementById("primary-input")
        if (el) el.focus()
      })
    },
    updated() {
      if (!document.activeElement || document.activeElement === document.body) {
        this.el.focus()
      }
      // Sync theme class when LiveView re-renders with new theme
      const theme = this.el.dataset.theme
      if (theme) this._applyTheme(theme)
    }
  },
  TaskAddInput: {
    mounted() {
      this.el.addEventListener("keydown", (e) => {
        // Escape is handled by DashboardKeys capture handler + hotkey handler
        if (e.key === "Backspace" && this.el.value === "") {
          e.preventDefault()
          e.stopPropagation()
          this.pushEvent("clear-task-input-mode", {})
          return
        }
        if (e.key === "Enter") {
          e.preventDefault()
          e.stopPropagation()
          const text = this.el.value.trim()
          if (text) {
            this.pushEvent("submit-input", { text })
            this.el.value = ""
          }
        }
      })
    },
    updated() {
      // Re-focus after server re-render (rapid entry)
      if (this.el.dataset.wtId) {
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
      this.autocompleteType = null // "file" or "branch"

      this.dropdown = document.getElementById("file-autocomplete-dropdown")

      this.el.addEventListener("keydown", (e) => {
        // Immediately blur on Escape so j/k navigation works right away
        if (e.key === "Escape" && !this.mentionActive) {
          this.el.blur()
          return // Let event propagate to LiveView hotkey handler
        }

        if (this.mentionActive && this.results.length > 0) {
          if (e.key === "ArrowDown" || e.key === "Tab" || (e.ctrlKey && e.key === "n")) {
            e.preventDefault()
            this.selectedIndex = (this.selectedIndex + 1) % this.results.length
            this.renderDropdown(false)
            return
          }
          if (e.key === "ArrowUp" || (e.ctrlKey && e.key === "p")) {
            e.preventDefault()
            this.selectedIndex = (this.selectedIndex - 1 + this.results.length) % this.results.length
            this.renderDropdown(false)
            return
          }
          if (e.key === "Enter") {
            e.preventDefault()
            if (this.autocompleteType === "branch") {
              this.selectBranch(this.results[this.selectedIndex])
            } else {
              this.selectFile(this.results[this.selectedIndex])
            }
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

        // Check for # at the very start of the input (branch autocomplete)
        const branchMatch = text.match(/^#([^\s]*)$/)
        if (branchMatch) {
          const query = branchMatch[1]
          this.mentionStart = 0
          this.mentionQuery = query
          this.autocompleteType = "branch"

          this.pushEvent("branch-search", { query }, (reply) => {
            this.results = reply.branches || []
            this.selectedIndex = 0
            if (this.results.length > 0) {
              this.mentionActive = true
              this.renderDropdown()
            } else {
              this.closeMention()
            }
          })
          return
        }

        // Find the last @ that starts a mention (after whitespace or at start)
        const match = text.match(/(^|[\s\n])@([^\s]*)$/)
        if (match) {
          const query = match[2]
          this.mentionStart = pos - query.length - 1 // -1 for the @
          this.mentionQuery = query
          this.autocompleteType = "file"

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

      // Handle image paste
      this.el.addEventListener("paste", (e) => {
        const items = e.clipboardData && e.clipboardData.items
        if (!items) return

        for (let i = 0; i < items.length; i++) {
          if (items[i].type.indexOf("image") !== -1) {
            e.preventDefault()
            const file = items[i].getAsFile()
            const reader = new FileReader()
            reader.onload = (evt) => {
              const base64 = evt.target.result.split(",")[1]
              const mimeType = file.type || "image/png"
              this.pushEvent("paste-image", { data: base64, mime: mimeType, name: file.name || "clipboard.png" })
            }
            reader.readAsDataURL(file)
            return
          }
        }
      })

      this.handleEvent("image-pasted", ({ path }) => {
        const cursor = this.el.selectionStart
        const before = this.el.value.substring(0, cursor)
        const after = this.el.value.substring(cursor)
        const ref = path + " "
        this.el.value = before + ref + after
        this.el.selectionStart = cursor + ref.length
        this.el.selectionEnd = cursor + ref.length
        this.el.focus()
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

    selectBranch(branch) {
      if (!branch) return
      // Replace input with #branch-name followed by a space for optional description
      this.el.value = "#" + branch + " "
      const newPos = this.el.value.length
      this.el.selectionStart = newPos
      this.el.selectionEnd = newPos
      this.el.focus()
      this.closeMention()
    },

    closeMention() {
      this.mentionActive = false
      this.autocompleteType = null
      this.results = []
      this.selectedIndex = 0
      if (this.dropdown) {
        this.dropdown.classList.add("hidden")
        this.dropdown.innerHTML = ""
      }
    },

    renderDropdown(rebuildContent = true) {
      if (!this.dropdown || this.results.length === 0) return
      this.dropdown.classList.remove("hidden")

      // Position fixed dropdown above the textarea
      const rect = this.el.getBoundingClientRect()
      this.dropdown.style.left = rect.left + "px"
      this.dropdown.style.width = rect.width + "px"

      if (rebuildContent) {
        // Temporarily render off-screen to measure height
        this.dropdown.style.top = "-9999px"

        if (this.autocompleteType === "branch") {
          this.dropdown.innerHTML = this.results.map((branch, i) => {
            const isSelected = i === this.selectedIndex
            // Split branch into prefix (e.g. "worktree/") and name
            const lastSlash = branch.lastIndexOf("/")
            const prefix = lastSlash >= 0 ? branch.substring(0, lastSlash + 1) : ""
            const name = lastSlash >= 0 ? branch.substring(lastSlash + 1) : branch
            return `<div class="file-ac-item ${isSelected ? "file-ac-selected" : ""}" data-index="${i}">
              <span class="file-ac-name">${this.escapeHtml(name)}</span>
              ${prefix ? `<span class="file-ac-dir">${this.escapeHtml(prefix)}</span>` : ""}
            </div>`
          }).join("")
        } else {
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
        }

        // Position above textarea (or below if not enough space above)
        const dropdownHeight = this.dropdown.offsetHeight
        const spaceAbove = rect.top
        if (spaceAbove >= dropdownHeight) {
          this.dropdown.style.top = (rect.top - dropdownHeight - 4) + "px"
        } else {
          this.dropdown.style.top = (rect.bottom + 4) + "px"
        }

        // Click handlers
        this.dropdown.querySelectorAll(".file-ac-item").forEach(item => {
          item.addEventListener("mousedown", (e) => {
            e.preventDefault()
            const idx = parseInt(item.dataset.index)
            this.selectFile(this.results[idx])
          })
          item.addEventListener("mouseenter", () => {
            this.selectedIndex = parseInt(item.dataset.index)
            this.updateSelection()
          })
        })
      } else {
        this.updateSelection()
      }

      // Scroll selected into view
      const selected = this.dropdown.querySelector(".file-ac-selected")
      if (selected) selected.scrollIntoView({ block: "nearest" })
    },

    updateSelection() {
      if (!this.dropdown) return
      this.dropdown.querySelectorAll(".file-ac-item").forEach(item => {
        const idx = parseInt(item.dataset.index)
        if (idx === this.selectedIndex) {
          item.classList.add("file-ac-selected")
        } else {
          item.classList.remove("file-ac-selected")
        }
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
  ChatKeys: {
    _isDropdownVisible() {
      return document.querySelector("#file-autocomplete-dropdown:not(.hidden)") ||
        document.querySelector(".chat-path-dropdown:not(:empty)")
    },
    mounted() {
      this.el.focus()
      window.addEventListener("keydown", (e) => {
        // Allow Ctrl+N/P through when file/path autocomplete dropdown is visible
        if (e.metaKey || e.ctrlKey) {
          if (!(this._isDropdownVisible() && e.ctrlKey && (e.key === "n" || e.key === "p"))) {
            e.stopPropagation()
            return
          }
        }
        const tag = e.target.tagName
        const isInput = tag === "INPUT" || tag === "TEXTAREA" || e.target.isContentEditable
        if (isInput && e.key === "Escape") {
          e.target.blur()
          this.el.focus()
        } else if (isInput && e.key !== "Enter" && e.key !== "Tab") {
          const dropdownActive = e.ctrlKey && (e.key === "n" || e.key === "p") && this._isDropdownVisible()
          if (!dropdownActive) e.stopPropagation()
        }
      }, true)
    },
    updated() {
      if (!document.activeElement || document.activeElement === document.body) {
        this.el.focus()
      }
    }
  },
  ChatScroll: {
    mounted() {
      this.autoScroll = true
      this.scrollToBottom()

      // Restore persisted messages
      try {
        const stored = localStorage.getItem("apothecary-chat-messages")
        if (stored) {
          const messages = JSON.parse(stored)
          if (Array.isArray(messages) && messages.length > 0) {
            this.pushEvent("restore-messages", { messages })
          }
        }
      } catch (_) {}

      // Listen for persist events
      this.handleEvent("persist-messages", ({ messages }) => {
        try {
          localStorage.setItem("apothecary-chat-messages", JSON.stringify(messages))
        } catch (_) {}
      })

      this.el.addEventListener("scroll", () => {
        const threshold = 50
        const atBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < threshold
        this.autoScroll = atBottom
      })

      this.observer = new MutationObserver(() => {
        if (this.autoScroll) this.scrollToBottom()
      })
      this.observer.observe(this.el, { childList: true, subtree: true })
    },
    updated() {
      if (this.autoScroll) this.scrollToBottom()
    },
    destroyed() {
      if (this.observer) this.observer.disconnect()
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight
    }
  },
  ChatInput: {
    mounted() {
      this.history = []
      this.historyIndex = -1
      this.pathActive = false

      // Auto-focus on mount
      this.el.focus()

      this.el.addEventListener("keydown", (e) => {
        // When path suggestions are showing, route nav keys to server
        const dropdown = document.querySelector(".chat-path-dropdown")
        this.pathActive = dropdown && dropdown.children.length > 0

        if (this.pathActive) {
          if (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "Tab" || (e.ctrlKey && (e.key === "n" || e.key === "p"))) {
            e.preventDefault()
            const mappedKey = (e.ctrlKey && e.key === "n") ? "ArrowDown" : (e.ctrlKey && e.key === "p") ? "ArrowUp" : e.key
            this.pushEvent("path-key", { key: mappedKey })
            return
          }
          if (e.key === "Escape") {
            e.preventDefault()
            this.pushEvent("path-key", { key: "Escape" })
            return
          }
        }

        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault()
          const text = this.el.value.trim()
          if (text) {
            this.history.unshift(text)
            if (this.history.length > 50) this.history.pop()
            this.historyIndex = -1
            const form = this.el.closest("form")
            if (form) {
              form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
            }
            this.el.value = ""
            this.el.style.height = "auto"
          }
        }
        if (e.key === "ArrowUp" && this.el.value === "" && this.history.length > 0) {
          e.preventDefault()
          this.historyIndex = Math.min(this.historyIndex + 1, this.history.length - 1)
          this.el.value = this.history[this.historyIndex]
        }
        if (e.key === "ArrowDown" && this.historyIndex >= 0) {
          e.preventDefault()
          this.historyIndex--
          this.el.value = this.historyIndex >= 0 ? this.history[this.historyIndex] : ""
        }
        if (e.key === "Escape") {
          this.el.blur()
        }
      })

      // Auto-resize + fire input-change for path autocomplete
      this.el.addEventListener("input", () => {
        this.el.style.height = "auto"
        this.el.style.height = Math.min(this.el.scrollHeight, 200) + "px"
        this.pushEvent("input-change", { value: this.el.value })
      })

      // Server push: set input value (for path drill-down)
      this.handleEvent("set-input", ({ value }) => {
        this.el.value = value
        this.el.focus()
        // Move cursor to end
        this.el.selectionStart = value.length
        this.el.selectionEnd = value.length
        // Trigger input event for autocomplete
        this.pushEvent("input-change", { value })
      })

      // Server push: clear input
      this.handleEvent("clear-input", () => {
        this.el.value = ""
        this.el.style.height = "auto"
      })
    }
  },
  ChatSwitcherFocus: {
    mounted() {
      this.el.focus()
      this.el.addEventListener("keydown", (e) => {
        if (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "Enter" || e.key === "Escape") {
          e.preventDefault()
          this.pushEvent("switcher-key", { key: e.key })
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

