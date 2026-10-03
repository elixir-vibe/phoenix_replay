defmodule PhoenixReplay.RouterTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Router

  test "builds live sessions with the dashboard context and host hooks" do
    assert {:admin_replay, :admin_replay_frame, dashboard, frame} =
             Router.__live_sessions__("/replay",
               on_mount: {MyAuth, :admin},
               authorize: MyAuthorization,
               frame_layout: {MyLayouts, :root},
               as: :admin_replay
             )

    context = %{base_path: "/replay", authorize: MyAuthorization, live_socket_path: "/live"}
    assert dashboard[:on_mount] == [{PhoenixReplay.Web.Context, context}, {MyAuth, :admin}]
    assert dashboard[:root_layout] == {PhoenixReplay.Web.Layouts, :dashboard}
    assert frame[:root_layout] == {MyLayouts, :root}
  end

  test "rejects unknown options" do
    assert_raise ArgumentError, ~r/:authorise/, fn ->
      Router.__live_sessions__("/replay", authorise: Mod)
    end
  end

  test "defines dashboard routes" do
    paths = for route <- Phoenix.Router.routes(PhoenixReplay.Test.Router), do: route.path

    for path <-
          ~w(/replay /replay/:id /replay/:id/frame /replay/assets/:asset /restricted/replay/:id),
        do: assert(path in paths)
  end
end
