// Modules without bundled type declarations.

declare module 'phoenix_html'

declare module 'phoenix-colocated/example' {
  import type { HooksOptions } from 'phoenix_live_view'

  export const hooks: HooksOptions
}
