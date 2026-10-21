// The same surface and typography as SearchBar, in the native floating window.
import '@konstantinopolskii/design-system/vars.css'
import '@konstantinopolskii/design-system/style.css'
import './style.css'
import './components/circleField.css'
import './quickEntry.css'

type Native = Window & {
  webkit?: { messageHandlers: { quickEntry: { postMessage(message: unknown): void } } }
  quickEntry?: { state(busy: boolean, error: string, clear?: boolean): void; focus(): void }
}
const host = window as Native
const field = document.querySelector('textarea')!
const shape = document.querySelector<HTMLElement>('.circle-field__shape')!
const status = document.querySelector<HTMLElement>('[role=status]')!
let busy = false
const post = (message: unknown) => host.webkit?.messageHandlers.quickEntry.postMessage(message)
function resize(): void {
  field.style.height = '0px'
  const height = Math.min(216, Math.max(36, field.scrollHeight))
  field.style.height = height + 'px'
  shape.style.height = height + 48 + 'px'
  post({ action: 'resize', height: height + 48 + (status.textContent ? status.offsetHeight + 12 : 0) })
}
host.quickEntry = {
  state(working, error, clear = false) {
    busy = working
    field.readOnly = working
    status.textContent = error || (working ? 'Отправляем…' : '')
    if (clear) field.value = ''
    resize()
    if (!working) field.focus()
  },
  focus() { field.focus(); resize() },
}
field.addEventListener('input', resize)
field.addEventListener('keydown', (event) => {
  if (event.isComposing) return
  if (event.key === 'Escape' && !busy) { event.preventDefault(); post({ action: 'cancel' }); return }
  if (event.key !== 'Enter' || event.shiftKey) return
  event.preventDefault()
  if (busy || !field.value.trim()) return
  host.quickEntry!.state(true, '')
  post({ action: event.metaKey ? 'agent' : 'inbox', text: field.value })
})
document.fonts.ready.then(() => { resize(); field.focus() })
