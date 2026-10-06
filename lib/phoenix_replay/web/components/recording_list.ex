defmodule PhoenixReplay.Web.Components.RecordingList do
  @moduledoc """
  Components of the recording list. They take
  `PhoenixReplay.Recording.Summary` structs and functions that build URLs,
  never the socket.

  Each row is a single link stretched over the whole row, so the row opens
  the recording; its delete button sits above the link. The filter bar
  above the list is `PhoenixReplay.Web.Components.Filters`.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  import PhoenixReplay.Web.Components.Core, only: [badge: 1, local_time: 1]

  alias PhoenixReplay.Recording.{Client, Summary}
  alias PhoenixReplay.Web.Format

  # Columns on wider screens: mark, session, started, duration, events,
  # status, action. Phones show the mark, the session and the status.
  @columns "grid-cols-[1rem_minmax(0,1fr)_auto] sm:grid-cols-[1rem_minmax(0,1fr)_8rem_4.5rem_4.5rem_6.5rem_2rem]"

  @doc """
  A section of recordings: sessions still recording with `live`, or saved
  ones under a header row. `delete` names the event that deletes a saved
  recording, or is `nil` when the viewer may not delete. Where each visit
  came from links to the list filtered by it, through `filter_path`.
  """
  attr :recordings, :list, required: true
  attr :now, :integer, required: true
  attr :path, :any, required: true, doc: "a function from a summary to its URL"

  attr :filter_path, :any,
    required: true,
    doc: "a function from a criterion and its value to the list's URL filtered by it"

  attr :live, :boolean, default: false
  attr :delete, :string, default: nil

  @spec recording_list(map()) :: Phoenix.LiveView.Rendered.t()
  def recording_list(%{live: true} = assigns) do
    ~H"""
    <section :if={@recordings != []} aria-labelledby="recordings-live" class="mb-6">
      <h2
        id="recordings-live"
        class="mb-2 flex items-center gap-2 text-xs font-medium tracking-wide text-muted uppercase"
      >
        <span class="size-2 animate-pulse rounded-full bg-live"></span> Live now
      </h2>
      <ul class="divide-y divide-line overflow-hidden rounded-xl border border-line bg-surface">
        <.row
          :for={recording <- @recordings}
          recording={recording}
          path={@path.(recording)}
          filter_path={@filter_path}
        >
          <:mark><span class="size-2.5 animate-pulse rounded-full bg-live"></span></:mark>
          <:meta>
            Live · {Format.clock(recording.duration_ms)} · {Format.count(
              recording.event_count,
              "event"
            )}
          </:meta>
          <:started>Started {Format.relative(recording.connected_at, @now)}</:started>
          <:status><span class="font-medium text-live">Recording</span></:status>
          <:action>
            <.icon name="lucide:chevron-right" class="size-4 text-muted" />
          </:action>
        </.row>
      </ul>
    </section>
    """
  end

  def recording_list(assigns) do
    # Older starts read as dates, in the viewer's time zone.
    assigns = assign(assigns, columns: @columns, two_days: :timer.hours(48))

    ~H"""
    <section :if={@recordings != []} aria-labelledby="recordings-saved">
      <h2 id="recordings-saved" class="mb-2 text-xs font-medium tracking-wide text-muted uppercase">
        Saved
      </h2>
      <div class="overflow-hidden rounded-xl border border-line bg-surface">
        <div
          aria-hidden="true"
          class={[
            "hidden gap-x-4 border-b border-line px-4 py-2.5 text-xs text-muted sm:grid",
            @columns
          ]}
        >
          <span></span><span>Session</span><span>Started</span><span>Duration</span>
          <span>Events</span><span>Errors</span><span></span>
        </div>
        <ul class="divide-y divide-line">
          <.row
            :for={recording <- @recordings}
            recording={recording}
            path={@path.(recording)}
            filter_path={@filter_path}
          >
            <:mark><.device_icon viewport={recording.viewport} /></:mark>
            <:meta>
              {Format.relative(recording.connected_at, @now)} · {Format.count(
                recording.event_count,
                "event"
              )}
            </:meta>
            <:started>
              <.local_time
                id={"recording-#{recording.id}-started"}
                at={recording.connected_at}
                format={if @now - recording.connected_at < @two_days, do: "title", else: "date"}
              >
                {Format.relative(recording.connected_at, @now)}
              </.local_time>
            </:started>
            <:status>
              <.badge :if={recording.error_count > 0} tone="error" dot="static">
                {Format.count(recording.error_count, "error")}
              </.badge>
              <span :if={recording.error_count == 0} class="hidden text-muted sm:inline">None</span>
            </:status>
            <:action>
              <button
                :if={@delete}
                type="button"
                phx-click={@delete}
                phx-value-id={recording.id}
                data-confirm="Delete this recording?"
                aria-label={"Delete recording #{short_id(recording)}"}
                title="Delete recording"
                class="relative z-10 inline-flex size-8 items-center justify-center rounded-md text-muted opacity-0 transition group-hover:opacity-100 hover:bg-error-soft hover:text-error focus-visible:opacity-100 pointer-coarse:opacity-100"
              >
                <.icon name="lucide:trash-2" class="size-4" />
              </button>
            </:action>
          </.row>
        </ul>
      </div>
    </section>
    """
  end

  @doc """
  How many sessions started over time, from
  `PhoenixReplay.Catalog.activity/3`: a bar for each stretch, with the
  ones that had an error in red. Each bar links to the list narrowed to
  its stretch, through `path`, a function from a `{from, to}` range.
  """
  attr :activity, :map, required: true
  attr :path, :any, required: true

  @spec activity_chart(map()) :: Phoenix.LiveView.Rendered.t()
  def activity_chart(assigns) do
    %{buckets: buckets, size: size} = assigns.activity
    top = buckets |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end) |> max(1)

    assigns =
      assign(assigns,
        bars:
          for {{start, sessions, errors}, index} <- Enum.with_index(buckets) do
            %{
              index: index,
              start: start,
              sessions: sessions,
              errors: errors,
              height: Float.round(sessions / top * 100, 1),
              error_share: if(sessions > 0, do: Float.round(errors / sessions * 100, 1), else: 0),
              path: assigns.path.({start, start + size - 1})
            }
          end
      )

    ~H"""
    <section id="recordings-activity" aria-label="Sessions over time" class="mb-5">
      <div class="flex h-14 items-end gap-px">
        <.link
          :for={bar <- @bars}
          patch={bar.path}
          aria-label={"#{Format.count(bar.sessions, "session")}, #{bar.errors} with errors"}
          data-tip
          class="group/tip flex h-full min-w-0 flex-1 flex-col justify-end rounded-sm hover:bg-hover/50 focus-visible:bg-hover/50"
        >
          <%!-- An empty stretch is a baseline; any session at all shows. --%>
          <span :if={bar.sessions == 0} class="h-px w-full bg-line group-hover/tip:bg-muted"></span>
          <span
            :if={bar.sessions > 0}
            class="flex w-full flex-col justify-end overflow-hidden rounded-sm"
            style={"height: max(4px, #{bar.height}%)"}
          >
            <span class="w-full flex-1 bg-faint/60 group-hover/tip:bg-muted"></span>
            <span :if={bar.errors > 0} class="w-full bg-error" style={"height: #{bar.error_share}%"}></span>
          </span>
          <span
            aria-hidden="true"
            data-tip-content
            class="pointer-events-none fixed top-0 left-0 z-50 not-data-placed:invisible w-max rounded-md bg-ink px-2 py-1 text-xs whitespace-nowrap text-on-ink opacity-0 shadow-md group-hover/tip:opacity-100 group-focus-visible/tip:opacity-100"
          >
            <.local_time id={"recordings-activity-#{bar.index}"} at={bar.start}>
              {Format.started(bar.start)} UTC
            </.local_time>
            · {Format.count(bar.sessions, "session")}<span :if={bar.errors > 0}>, {bar.errors} with errors</span>
          </span>
        </.link>
      </div>
      <div class="mt-1 flex justify-between text-xs text-muted">
        <.local_time id="recordings-activity-from" at={@activity.from}>
          {Format.started(@activity.from)} UTC
        </.local_time>
        <.local_time id="recordings-activity-to" at={@activity.to}>
          {Format.started(@activity.to)} UTC
        </.local_time>
      </div>
    </section>
    """
  end

  @doc """
  Says how many recordings ended since the list was read, with a button
  that sends `show_new` to bring it up to date.
  """
  attr :count, :integer, required: true

  @spec new_recordings(map()) :: Phoenix.LiveView.Rendered.t()
  def new_recordings(assigns) do
    ~H"""
    <div id="recordings-new" role="status" aria-live="polite">
      <button
        :if={@count > 0}
        type="button"
        phx-click="show_new"
        class="mb-4 flex w-full items-center justify-center gap-2 rounded-xl border border-accent/30 bg-accent-soft px-4 py-2.5 text-sm font-medium text-ink transition-colors hover:border-accent/60 pointer-coarse:py-3"
      >
        <.icon name="lucide:arrow-up" class="size-4 text-accent" />
        {Format.count(@count, "new recording")} · Show
      </button>
    </div>
    """
  end

  attr :recording, Summary, required: true
  attr :path, :string, required: true
  attr :filter_path, :any, required: true
  slot :mark, required: true
  slot :meta, required: true, doc: "the second line on phones"
  slot :started, required: true
  slot :status, required: true
  slot :action, required: true

  defp row(assigns) do
    assigns = assign(assigns, columns: @columns, traffic: traffic_of(assigns.recording))

    ~H"""
    <li
      id={"recording-#{@recording.id}"}
      class={[
        "group relative grid items-center gap-x-4 px-4 py-3 transition-colors hover:bg-hover",
        @columns
      ]}
    >
      <span class="flex justify-center">{render_slot(@mark)}</span>
      <div class="min-w-0">
        <div class="flex min-w-0 items-center gap-2">
          <.link
            navigate={@path}
            class="truncate font-medium after:absolute after:inset-0 focus-visible:outline-none after:focus-visible:outline-2 after:focus-visible:-outline-offset-2 after:focus-visible:outline-accent"
          >
            {@recording.view}
          </.link>
          <.link
            :for={{name, count} <- Enum.sort(@recording.marks)}
            patch={@filter_path.(:mark, name)}
            title={"Reached #{name}" <> if(count > 1, do: " #{count} times", else: "")}
            class="relative z-10 inline-flex shrink-0 items-center gap-1 rounded-full bg-kind-mark/15 px-2 py-px text-xs font-medium text-kind-mark hover:bg-kind-mark/25"
          >
            <.icon name="lucide:flag" class="size-3" />
            {name}<span :if={count > 1} class="opacity-70">×{count}</span>
          </.link>
        </div>
        <p class="mt-0.5 truncate font-mono text-xs text-muted">
          <span class="sm:hidden">{render_slot(@meta)}</span>
          <span class="hidden sm:inline">
            {page(@recording)}<span :if={@recording.device}> · {@recording.device}</span><.traffic
              :if={@traffic != []}
              traffic={@traffic}
              filter_path={@filter_path}
            /> · {short_id(@recording)}
          </span>
        </p>
      </div>
      <span class="hidden text-sm text-muted sm:block">{render_slot(@started)}</span>
      <span class="hidden font-mono text-sm tabular-nums sm:block">
        {Format.clock(@recording.duration_ms)}
      </span>
      <span class="hidden text-sm text-muted tabular-nums sm:block">{@recording.event_count}</span>
      <span class="justify-self-end text-sm sm:justify-self-start">{render_slot(@status)}</span>
      <span class="hidden justify-center sm:flex">{render_slot(@action)}</span>
    </li>
    """
  end

  attr :viewport, :map, default: nil

  # The kind of device the session ran on; see `Client.device_type/1`.
  defp device_icon(assigns) do
    ~H"""
    <%= case Client.device_type(@viewport) do %>
      <% nil -> %>
        <.icon name="lucide:circle-play" class="size-4 text-muted" />
      <% "phone" -> %>
        <.icon name="lucide:smartphone" class="size-4 text-muted" label="Phone" />
      <% "tablet" -> %>
        <.icon name="lucide:tablet" class="size-4 text-muted" label="Tablet" />
      <% "desktop" -> %>
        <.icon name="lucide:monitor" class="size-4 text-muted" label="Desktop" />
    <% end %>
    """
  end

  attr :traffic, :list, required: true
  attr :filter_path, :any, required: true

  # Each part of where the visit came from links to the list filtered by it.
  defp traffic(%{traffic: _traffic} = assigns) do
    ~H"""
    <span phx-no-format> · from <%= for {{criterion, value}, index} <- Enum.with_index(@traffic) do %><%= if index > 0 do %> / <% end %><.link patch={@filter_path.(criterion, value)} class="relative z-10 hover:text-ink hover:underline">{value}</.link><% end %></span>
    """
  end

  # Where the visit came from, leaving out what says nothing: a direct
  # visit, no medium, or a referral, which the referrer's host as the
  # source already tells.
  defp traffic_of(%Summary{source: source, medium: medium, campaign: campaign}) do
    [
      {:source, if(source != "(direct)", do: source)},
      {:medium, if(medium not in ["(none)", "referral"], do: medium)},
      {:campaign, campaign}
    ]
    |> Enum.reject(fn {_criterion, value} -> is_nil(value) end)
  end

  defp page(%Summary{url: nil}), do: "—"
  defp page(%Summary{url: url}), do: Format.path_of(url)

  defp short_id(%Summary{id: id}), do: String.slice(id, 0, 8)
end
