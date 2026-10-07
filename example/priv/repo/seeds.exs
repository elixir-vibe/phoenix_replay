alias Example.Repo
alias Example.Tasks.Task

now = DateTime.utc_now() |> DateTime.truncate(:second)

# Enough tasks that the list scrolls on a phone, newest first, an hour apart.
[
  {"Review PR #42", "Check the new authentication flow", "high", false},
  {"Update dependencies", "Run mix deps.update --all", "low", true},
  {"Write documentation", "Add module docs for the Tasks context", "medium", false},
  {"Fix the flaky login test", "It times out on CI once a week", "high", false},
  {"Plan the October release", "Pick the features that make the cut", "medium", false},
  {"Answer support email", "Three questions about exports", "low", true},
  {"Profile the dashboard query", "Slow with a month of sessions", "medium", false},
  {"Design the onboarding tour", "Five steps at most", "low", false},
  {"Rotate the API keys", "Before the end of the quarter", "high", false},
  {"Clean up feature flags", "Remove the ones fully rolled out", "low", true}
]
|> Enum.with_index()
|> Enum.each(fn {{title, description, priority, completed}, hours_ago} ->
  at = DateTime.add(now, -3600 * hours_ago)

  Repo.insert!(%Task{
    title: title,
    description: description,
    priority: priority,
    completed: completed,
    inserted_at: at,
    updated_at: at
  })
end)
