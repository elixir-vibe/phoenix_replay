locals_without_parens = [phoenix_replay: 1, phoenix_replay: 2]

[
  plugins: [Volt.Formatter, Phoenix.LiveView.HTMLFormatter],
  import_deps: [:phoenix, :ecto, :ecto_sql],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "lib/**/*.heex",
    "priv/ts/**/*.ts"
  ],
  locals_without_parens: locals_without_parens,
  volt: [
    semi: false,
    single_quote: true,
    trailing_comma: :none,
    print_width: 100,
    arrow_parens: :always
  ],
  export: [locals_without_parens: locals_without_parens]
]
