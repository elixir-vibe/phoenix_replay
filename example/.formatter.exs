[
  import_deps: [:ecto, :ecto_sql, :phoenix, :phoenix_replay],
  plugins: [Volt.Formatter, Phoenix.LiveView.HTMLFormatter],
  volt: [
    print_width: 100,
    semi: false,
    single_quote: true,
    trailing_comma: :none,
    arrow_parens: :always
  ],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
]
