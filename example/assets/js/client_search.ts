import { replayState } from 'phoenix_replay'
import { ViewHook } from 'phoenix_live_view'

/**
 * Filters the task titles as you type, in the browser alone, and reports
 * the query to PhoenixReplay so the replay can show the same list.
 */
export class ClientSearch extends ViewHook {
  mounted(): void {
    // A stylesheet hides the rows, so LiveView's patches leave the filter alone.
    const style = document.createElement('style')
    style.id = 'client-search-style'
    document.head.append(style)

    const input = this.el.querySelector('input') as HTMLInputElement

    input.addEventListener('input', () => {
      const query = input.value.trim()
      style.textContent = query
        ? `#task-titles [data-title]:not([data-title*="${CSS.escape(query)}" i]) { display: none }`
        : ''
      replayState('search', { query })
    })
  }

  destroyed(): void {
    document.getElementById('client-search-style')?.remove()
  }
}
