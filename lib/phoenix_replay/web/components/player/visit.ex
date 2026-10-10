defmodule PhoenixReplay.Web.Components.Player.Visit do
  @moduledoc """
  The **Visit** tab: the device, the other sessions of the same browser
  tab, where the visit came from and how it started.

  Like the rest of the player's components, it takes the recording, the
  current position and URLs built by the player, never the socket.
  """

  use Phoenix.Component

  import PhoenixReplay.Web.Components.Layout, only: [data_list: 1]
  import PhoenixReplay.Web.Components.Core, only: [badge: 1, local_time: 1]

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Client
  alias PhoenixReplay.Web.Format

  @doc """
  Where the session came from: the device, the page before it, the other
  sessions of its browser tab, and the visit's landing and headers.
  """
  attr :recording, Recording, required: true
  attr :viewport, :map, default: nil
  attr :pages, :map, default: nil, doc: "the visit's pages; see `PhoenixReplay.Web.Player.Pages`"
  attr :migrations, :list, default: [], doc: "the names of the migrations replay applies"

  attr :filter_path, :any,
    required: true,
    doc:
      "a function from criteria, such as `[source: \"google\"]`, to the recording list filtered by them"

  @spec visit(map()) :: Phoenix.LiveView.Rendered.t()
  def visit(%{recording: %{client: client}} = assigns) do
    assigns =
      assign(assigns,
        user_agent: client.user_agent,
        navigated_from: client.navigated_from,
        landing: client.landing,
        params: if(client.landing, do: Enum.sort(client.landing.params), else: []),
        headers: client.headers,
        traffic: Client.traffic(client)
      )

    ~H"""
    <div class="flex flex-col gap-5 p-4 text-sm">
      <section :if={@viewport || @user_agent} aria-labelledby="replay-device-heading">
        <h3 id="replay-device-heading" class={heading()}>Device</h3>
        <p :if={@viewport} id="replay-device" title={@user_agent}>
          {Format.viewport(@viewport)}<span :if={label = Client.device(@user_agent)}> · {label}</span>
        </p>
        <p :if={!@viewport} title={@user_agent}>
          {Client.device(@user_agent) || "Unknown browser"}
        </p>
        <p :if={settings = settings(@viewport)} id="replay-settings" class="mt-0.5 text-muted">
          {settings}
        </p>
      </section>

      <section
        :if={@pages && length(@pages.pages) > 1}
        id="replay-visit-pages"
        aria-labelledby="replay-visit-pages-heading"
      >
        <h3 id="replay-visit-pages-heading" class={heading()}>Pages of this visit</h3>
        <ol class="flex flex-col gap-1">
          <li :for={page <- @pages.pages}>
            <button
              type="button"
              phx-click="page"
              phx-value-id={page.id}
              aria-current={page.id == @recording.id && "page"}
              class={[
                "flex w-full items-baseline gap-2 text-left hover:text-ink",
                if(page.id == @recording.id, do: "font-medium text-ink", else: "text-muted")
              ]}
            >
              <span class="font-mono text-xs tabular-nums">+{Format.clock(page.offset)}</span>
              <code class="truncate font-mono text-xs">{Format.path_of(page.url || "—")}</code>
            </button>
          </li>
        </ol>
      </section>

      <section :if={@navigated_from} aria-labelledby="replay-navigated-from-heading">
        <h3 id="replay-navigated-from-heading" class={heading()}>Came from</h3>
        <code class="font-mono text-xs break-all" title={@navigated_from}>
          {Format.path_of(@navigated_from)}
        </code>
      </section>

      <section
        :if={@landing || @headers != %{}}
        id="replay-visit"
        aria-labelledby="replay-visit-heading"
      >
        <h3 id="replay-visit-heading" class={heading()}>Visit</h3>
        <div :if={@landing} class="mb-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-muted">
          <.link
            :if={campaign = Client.campaign(@landing.params)}
            id="replay-visit-campaign"
            navigate={@filter_path.(@traffic |> Map.from_struct() |> Map.to_list())}
            title="Recordings from this campaign"
            class="rounded-full hover:opacity-80"
          >
            <.badge>{campaign}</.badge>
          </.link>
          <.link
            :if={host = Client.referrer_host(@landing.referrer)}
            navigate={@filter_path.(source: host)}
            title={@landing.referrer}
            class="hover:text-ink hover:underline"
          >
            from {host}
          </.link>
          <span>
            landed on <code class="font-mono text-ink">{@landing.path}</code>
            at
            <.local_time id="replay-visit-landed" at={@landing.at}>
              {Format.timestamp(@landing.at)} UTC
            </.local_time>
          </span>
        </div>
        <%!-- The list keeps a value's whitespace, so each item is on one line. --%>
        <.data_list>
          <:item :for={{name, value} <- @params} title={name}>{value}</:item>
          <:item :if={@landing && @landing.referrer} title="referrer">{@landing.referrer}</:item>
          <:item :for={{name, value} <- Enum.sort(@headers)} title={name}>{value}</:item>
        </.data_list>
      </section>

      <section :if={@recording.code} id="replay-code" aria-labelledby="replay-code-heading">
        <h3 id="replay-code-heading" class={heading()}>Code</h3>
        <p :if={@recording.code.release}>
          Release <code class="font-mono text-xs">{@recording.code.release}</code>
        </p>
        <p class="text-muted">
          {Enum.map_join(Enum.sort(@recording.code.deps), " · ", fn {dep, vsn} -> "#{dep} #{vsn}" end)}
        </p>
      </section>

      <section
        :if={@migrations != []}
        id="replay-migrations"
        aria-labelledby="replay-migrations-heading"
      >
        <h3 id="replay-migrations-heading" class={heading()}>Migrations applied</h3>
        <p>{Enum.join(@migrations, ", ")}</p>
      </section>

      <section aria-labelledby="replay-session-heading">
        <h3 id="replay-session-heading" class={heading()}>Session</h3>
        <code class="font-mono text-xs break-all">{@recording.id}</code>
      </section>
    </div>
    """
  end

  defp heading, do: "mb-1.5 text-xs font-medium tracking-wide text-muted uppercase"

  # The media settings the page's CSS could see, as the browser reported
  # them at this moment; the replay applies the color scheme.
  defp settings(nil), do: nil

  defp settings(viewport) do
    [
      color_scheme: %{dark: "Dark theme", light: "Light theme"},
      reduced_motion: %{true => "Reduced motion"},
      contrast: %{more: "More contrast", less: "Less contrast"},
      pointer: %{coarse: "Touch screen", fine: "Mouse or trackpad", none: "No pointer"}
    ]
    |> Enum.flat_map(fn {name, labels} -> List.wrap(labels[viewport[name]]) end)
    |> case do
      [] -> nil
      labels -> Enum.join(labels, " · ")
    end
  end
end
