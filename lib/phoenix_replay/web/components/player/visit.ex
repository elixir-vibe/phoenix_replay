defmodule PhoenixReplay.Web.Components.Player.Visit do
  @moduledoc """
  The **Visit** tab: the device, the other sessions of the same browser
  tab, where the visit came from and how it started.

  Like the rest of the player's components, it takes the recording, the
  current position and URLs built by the player, never the socket.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Core, only: [badge: 1, data_list: 1]

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Client
  alias PhoenixReplay.Web.Format

  @doc """
  Where the session came from: the device, the page before it, the other
  sessions of its browser tab, and the visit's landing and headers.
  """
  attr :recording, Recording, required: true
  attr :viewport, :map, default: nil
  attr :journey, :map, default: nil, doc: "the tab's sessions, with URLs"

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
      </section>

      <section :if={@journey} id="replay-journey" aria-labelledby="replay-journey-heading">
        <h3 id="replay-journey-heading" class={heading()}>Browser tab</h3>
        <.link navigate={@journey.tab_path} class="underline decoration-line hover:text-ink">
          Session {@journey.position} of {@journey.total} in this tab
        </.link>
        <div class="mt-2 flex gap-3 text-muted">
          <.link
            :if={@journey.previous}
            navigate={@journey.previous}
            class="inline-flex items-center gap-1 hover:text-ink"
          >
            <.icon name="lucide:arrow-left" class="size-3.5" /> Previous
          </.link>
          <.link
            :if={@journey.next}
            navigate={@journey.next}
            class="inline-flex items-center gap-1 hover:text-ink"
          >
            Next <.icon name="lucide:arrow-right" class="size-3.5" />
          </.link>
        </div>
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
            at {Format.timestamp(@landing.at)}
          </span>
        </div>
        <.data_list>
          <:item
            :for={{name, value} <- Enum.sort(if(@landing, do: @landing.params, else: %{}))}
            title={name}
          >
            {value}
          </:item>
          <:item :if={@landing && @landing.referrer} title="referrer">{@landing.referrer}</:item>
          <:item :for={{name, value} <- Enum.sort(@headers)} title={name}>{value}</:item>
        </.data_list>
      </section>

      <section aria-labelledby="replay-session-heading">
        <h3 id="replay-session-heading" class={heading()}>Session</h3>
        <code class="font-mono text-xs break-all">{@recording.id}</code>
      </section>
    </div>
    """
  end

  defp heading, do: "mb-1.5 text-xs font-medium tracking-wide text-muted uppercase"
end
