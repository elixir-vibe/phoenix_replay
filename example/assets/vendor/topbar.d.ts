interface TopbarOptions {
  autoRun?: boolean
  barThickness?: number
  barColors?: Record<number, string>
  shadowBlur?: number
  shadowColor?: string
  className?: string
}

declare const topbar: {
  config(options: TopbarOptions): void
  show(delay?: number): void
  progress(to?: number | string): number
  hide(): void
}

export default topbar
