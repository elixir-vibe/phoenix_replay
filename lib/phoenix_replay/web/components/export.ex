defmodule PhoenixReplay.Web.Components.Export do
  @moduledoc """
  The player's video export: the dialog that chooses what an export shows,
  and the bar under the header that follows it.

  Events are sent by name: `export` with the form's `export` params,
  `export_form` as they change, `export_at` with a `field`,
  `close_export_dialog`, `cancel_export` and `dismiss_export`.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Core, only: [button: 1]
  import PhoenixReplay.Web.Components.Dialog, only: [dialog: 1]

  @doc """
  The export dialog: the range of the recording, whether idle stretches
  are shortened and the pointer drawn, the orientation, and the size,
  frame rate and quality of the video. `params` are the form's values,
  as `PhoenixReplay.Export.Options.parse/2` reads them.
  """
  attr :params, :map, required: true
  attr :error, :string, default: nil
  attr :rotatable, :boolean, default: true, doc: "whether the recording has a viewport to rotate"
  attr :max_dpr, :integer, required: true

  @spec export_dialog(map()) :: Phoenix.LiveView.Rendered.t()
  def export_dialog(assigns) do
    ~H"""
    <.dialog
      id="replay-export-dialog"
      title="Export video"
      description="An MP4 of the replayed page, as the player shows it."
      close="close_export_dialog"
    >
      <form
        id="replay-export-form"
        phx-change="export_form"
        phx-submit="export"
        class="grid grid-cols-[auto_1fr] items-center gap-x-4 gap-y-3"
      >
        <span class="text-muted">Range</span>
        <div class="flex flex-wrap items-center gap-2">
          <.time_field field="from" value={@params["from"]} placeholder="start" />
          <span class="text-muted">to</span>
          <.time_field field="to" value={@params["to"]} placeholder="end" />
          <span class="text-xs text-muted">seconds</span>
        </div>

        <span class="text-muted">Show</span>
        <div class="flex flex-col gap-1.5">
          <.check_field field="skip_idle" params={@params}>Skip inactivity</.check_field>
          <.check_field field="pointer" params={@params} disabled={@params["rotated"] == "true"}>
            The pointer
          </.check_field>
          <.check_field :if={@rotatable} field="rotated" params={@params}>
            Rotated to the other orientation
          </.check_field>
        </div>

        <label for="replay-export-size" class="text-muted">Size</label>
        <.select_field
          id="replay-export-size"
          field="size"
          value={@params["size"]}
          options={[
            {"recorded", "As recorded, up to #{@max_dpr}×"},
            {"1x", "1×"},
            {"half", "Half"}
          ]}
        />

        <label for="replay-export-fps" class="text-muted">Frame rate</label>
        <.select_field
          id="replay-export-fps"
          field="fps"
          value={@params["fps"]}
          options={
            Enum.map(PhoenixReplay.Export.Options.frame_rates(), &{to_string(&1), "#{&1} fps"})
          }
        />

        <label for="replay-export-quality" class="text-muted">Quality</label>
        <.select_field
          id="replay-export-quality"
          field="quality"
          value={@params["quality"]}
          options={[{"small", "Smaller file"}, {"balanced", "Balanced"}, {"best", "Best"}]}
        />

        <p :if={@error} id="replay-export-error" role="alert" class="col-span-2 text-error">
          {@error}
        </p>
      </form>
      <:footer>
        <.button size="md" phx-click="close_export_dialog">Cancel</.button>
        <.button size="md" type="submit" form="replay-export-form" variant="primary">
          <.icon name="lucide:clapperboard" class="size-4" /> Export
        </.button>
      </:footer>
    </.dialog>
    """
  end

  attr :field, :string, required: true
  attr :value, :string, default: nil
  attr :placeholder, :string, required: true

  defp time_field(assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-md border border-line bg-surface">
      <input
        id={"replay-export-#{@field}"}
        type="number"
        name={"export[#{@field}]"}
        value={@value}
        min="0"
        step="0.01"
        placeholder={@placeholder}
        aria-label={if @field == "from", do: "From, in seconds", else: "To, in seconds"}
        class="h-8 w-20 rounded-l-md bg-transparent px-2 font-mono tabular-nums outline-none"
      />
      <button
        type="button"
        phx-click="export_at"
        phx-value-field={@field}
        title="The moment the player is at"
        aria-label={"Set #{@field} to the current moment"}
        class="inline-flex h-8 items-center border-l border-line px-1.5 text-muted hover:text-ink"
      >
        <.icon name="lucide:map-pin" class="size-3.5" />
      </button>
    </span>
    """
  end

  attr :field, :string, required: true
  attr :params, :map, required: true
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  # An unchecked box sends nothing, so a hidden field sends "false" for it.
  defp check_field(assigns) do
    ~H"""
    <label class={["inline-flex items-center gap-2", @disabled && "opacity-50"]}>
      <input type="hidden" name={"export[#{@field}]"} value="false" />
      <input
        id={"replay-export-#{@field}"}
        type="checkbox"
        name={"export[#{@field}]"}
        value="true"
        checked={@params[@field] == "true" and not @disabled}
        disabled={@disabled}
        class="size-4 accent-[var(--color-accent)]"
      />
      {render_slot(@inner_block)}
    </label>
    """
  end

  attr :id, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, default: nil
  attr :options, :list, required: true

  defp select_field(assigns) do
    ~H"""
    <select
      id={@id}
      name={"export[#{@field}]"}
      class="h-8 rounded-md border border-line bg-surface px-2"
    >
      <option :for={{value, label} <- @options} value={value} selected={value == @value}>
        {label}
      </option>
    </select>
    """
  end

  @doc """
  The state of a video export under the player's header: waiting, its
  progress, a link to the video once it is ready, or why it failed. A
  queued or running export can be cancelled.
  """
  attr :job, PhoenixReplay.Export.Job, required: true
  attr :download, :any, default: nil, doc: "the video's URL once it is ready"

  @spec export_status(map()) :: Phoenix.LiveView.Rendered.t()
  def export_status(assigns) do
    ~H"""
    <div
      id="replay-export-status"
      role="status"
      data-status={@job.status}
      class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-line bg-chrome px-4 py-2 text-sm sm:px-5"
    >
      <%= case @job.status do %>
        <% :queued -> %>
          <.icon name="lucide:loader-circle" class="size-4 animate-spin text-muted" />
          <span class="text-muted">Waiting to export the video…</span>
        <% :running -> %>
          <.icon name="lucide:loader-circle" class="size-4 animate-spin text-muted" />
          <span>Exporting video</span>
          <div
            role="progressbar"
            aria-label="Export progress"
            aria-valuemin="0"
            aria-valuemax="100"
            aria-valuenow={@job.progress}
            class="h-1.5 w-40 overflow-hidden rounded-full bg-line"
          >
            <div
              class="h-full rounded-full bg-accent transition-[width]"
              style={"width: #{@job.progress}%"}
            >
            </div>
          </div>
          <span class="font-mono text-xs text-muted tabular-nums">{@job.progress}%</span>
        <% :done -> %>
          <.icon name="lucide:circle-check" class="size-4 text-accent" />
          <span>Video ready</span>
          <a
            id="replay-export-download"
            href={@download}
            download
            class="inline-flex h-7 items-center gap-1.5 rounded-md border border-line bg-surface px-2.5 text-xs font-medium hover:bg-hover"
          >
            <.icon name="lucide:download" class="size-3.5" /> Download MP4
          </a>
        <% :cancelling -> %>
          <.icon name="lucide:loader-circle" class="size-4 animate-spin text-muted" />
          <span class="text-muted">Cancelling the export…</span>
        <% :cancelled -> %>
          <.icon name="lucide:circle-slash" class="size-4 text-muted" />
          <span class="text-muted">Export cancelled</span>
        <% :failed -> %>
          <.icon name="lucide:circle-alert" class="size-4 text-error" />
          <span class="text-error">{@job.error}</span>
          <button
            type="button"
            phx-click="export"
            class="inline-flex h-7 items-center rounded-md border border-line bg-surface px-2.5 text-xs font-medium hover:bg-hover"
          >
            Try again
          </button>
      <% end %>
      <span class="flex-1"></span>
      <button
        :if={PhoenixReplay.Export.Job.cancellable?(@job)}
        id="replay-export-cancel"
        type="button"
        phx-click="cancel_export"
        class="inline-flex h-7 items-center rounded-md border border-line bg-surface px-2.5 text-xs font-medium hover:bg-hover"
      >
        Cancel
      </button>
      <button
        :if={PhoenixReplay.Export.Job.finished?(@job)}
        type="button"
        phx-click="dismiss_export"
        aria-label="Dismiss"
        title="Dismiss"
        class="inline-flex size-7 items-center justify-center rounded-md text-muted hover:bg-hover hover:text-ink"
      >
        <.icon name="lucide:x" class="size-4" />
      </button>
    </div>
    """
  end
end
