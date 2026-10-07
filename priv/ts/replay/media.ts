import type { Media } from '../shared/payloads'
/**
 * Makes a replayed page's media rules follow the media features the user's
 * browser had, rather than the viewer's: the color scheme, reduced motion,
 * contrast, the kind of pointer and whether it hovers.
 *
 * A frame's `color-scheme` sets the scheme its page prefers in Safari, but
 * Chrome keeps the viewer's, and no browser lets a frame set the others,
 * so the page's own rules are rewritten: each condition on a recorded
 * feature, such as `(prefers-color-scheme: dark)` or `(pointer: coarse)`,
 * becomes one that always or never matches. Tailwind's `dark:`,
 * `motion-reduce:`, `contrast-more:`, `pointer-coarse:` and `hover:`
 * variants compile to such rules. Stylesheets from another origin cannot
 * be read, and are left as they are; so is script that asks `matchMedia`.
 */

const FEATURES = [
  'prefers-color-scheme',
  'prefers-reduced-motion',
  'prefers-contrast',
  'pointer',
  'hover'
]
// `(pointer: coarse)`, but not `(any-pointer: coarse)`.
const QUERY = new RegExp(`\\(\\s*(${FEATURES.join('|')})\\s*:\\s*([a-z-]+)\\s*\\)`, 'g')
const ALWAYS = '(color)'
const NEVER = '(not (color))'

// Each rewritten rule's own media text, to put back. A reloaded page has
// new rule objects, which start from their own text; the old ones' entries
// go with them, as the map holds them weakly. So a rule is never given
// the text of another.
const originals = new WeakMap<CSSRule, string>()

interface MediaRule extends CSSRule {
  media: MediaList
}

interface GroupingRule extends CSSRule {
  cssRules: CSSRuleList
}

/** Applies `media` to the media rules of `doc`, or puts them back without any. */
export const applyMedia = (doc: Document | null | undefined, media: Media = {}): void => {
  if (!doc) return

  for (const sheet of Array.from(doc.styleSheets)) {
    let rules: CSSRuleList
    try {
      rules = sheet.cssRules
    } catch {
      continue
    }
    rewrite(rules, media)
  }
}

// Rules come from the frame's own window, so they are told apart by shape
// rather than by class.
const rewrite = (rules: CSSRuleList, media: Media): void => {
  for (const rule of Array.from(rules)) {
    if ('media' in rule) rewriteMedia(rule as MediaRule, media)
    if ('cssRules' in rule) rewrite((rule as GroupingRule).cssRules, media)
  }
}

const rewriteMedia = (rule: MediaRule, media: Media): void => {
  const original = originals.get(rule) ?? rule.media.mediaText
  if (!new RegExp(QUERY.source).test(original)) return

  originals.set(rule, original)
  rule.media.mediaText = original.replace(QUERY, (condition, feature: string, value: string) => {
    const recorded = media[feature]
    if (recorded === undefined) return condition
    return recorded === value ? ALWAYS : NEVER
  })
}
