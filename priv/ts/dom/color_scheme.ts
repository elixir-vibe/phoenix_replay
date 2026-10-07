/**
 * Makes a replayed page's `prefers-color-scheme` media rules follow the
 * color scheme the user had, rather than the viewer's.
 *
 * A frame's `color-scheme` sets the scheme its page prefers in Safari, but
 * Chrome keeps the viewer's, so the page's own rules are rewritten: each
 * `(prefers-color-scheme: …)` condition becomes one that always or never
 * matches. Tailwind's `dark:` variant compiles to such rules. Stylesheets
 * from another origin cannot be read, and are left as they are; so is
 * script that asks `matchMedia`.
 */

const QUERY = /\(\s*prefers-color-scheme\s*:\s*(light|dark)\s*\)/g
const ALWAYS = '(color)'
const NEVER = '(not (color))'

// Each rewritten rule's own media text, to put back.
const originals = new WeakMap<CSSRule, string>()

interface MediaRule extends CSSRule {
  media: MediaList
}

interface GroupingRule extends CSSRule {
  cssRules: CSSRuleList
}

/** Applies `scheme` to the media rules of `doc`, or puts them back without one. */
export const applyColorScheme = (doc: Document | null | undefined, scheme?: string): void => {
  if (!doc) return

  for (const sheet of Array.from(doc.styleSheets)) {
    let rules: CSSRuleList
    try {
      rules = sheet.cssRules
    } catch {
      continue
    }
    rewrite(rules, scheme)
  }
}

// Rules come from the frame's own window, so they are told apart by shape
// rather than by class.
const rewrite = (rules: CSSRuleList, scheme?: string): void => {
  for (const rule of Array.from(rules)) {
    if ('media' in rule) rewriteMedia(rule as MediaRule, scheme)
    if ('cssRules' in rule) rewrite((rule as GroupingRule).cssRules, scheme)
  }
}

const rewriteMedia = (rule: MediaRule, scheme?: string): void => {
  const original = originals.get(rule) ?? rule.media.mediaText
  if (!original.includes('prefers-color-scheme')) return

  originals.set(rule, original)
  rule.media.mediaText = scheme
    ? original.replace(QUERY, (_match, wanted: string) => (wanted === scheme ? ALWAYS : NEVER))
    : original
}
