defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  @penalty_threshold_seconds 10
  @penalty_amount 20
  @default_arrival_seconds 30

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :step1, [:nosuspend])

    {:ok,
     %{
       request: request,
       phase: :allocating,
       timer: nil,
       penalty_timer: nil,
       penalty_window: false,
       taxi: nil,
       candidates: []
     }}
  end

  def handle_info(:step1, %{request: request} = state) do
    task = Task.async(fn -> candidate_taxis() end)
    %{"username" => username} = request

    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{
      "msg" => "Tu viaje costará 20 Mickey-dollars"
    })

    taxis = Task.await(task)

    case otraparte(state |> Map.put(:candidates, taxis |> Enum.shuffle())) do
      :no_more_taxis ->
        {:stop, :normal, state}

      {taxi, others, timer} ->
        {:noreply,
         state
         |> Map.put(:taxi, taxi)
         |> Map.put(:candidates, others)
         |> Map.put(:timer, timer)}
    end
  end

  def handle_info(:timeout, state) do
    case otraparte(state) do
      :no_more_taxis ->
        {:stop, :normal, state}

      {taxi, others, timer} ->
        {:noreply,
         state
         |> Map.put(:taxi, taxi)
         |> Map.put(:candidates, others)
         |> Map.put(:timer, timer)}
    end
  end

  def handle_info(:penalty_window, state) do
    {:noreply, Map.put(state, :penalty_window, true)}
  end

  def handle_cast({:process_accept, _username}, %{timer: timer} = state) do
    cancel_timer(timer)

    %{request: request, taxi: taxi} = state
    arrival_seconds = @default_arrival_seconds
    penalty_window = arrival_seconds <= @penalty_threshold_seconds

    penalty_timer =
      if penalty_window do
        nil
      else
        delay_ms = (arrival_seconds - @penalty_threshold_seconds) * 1_000
        Process.send_after(self(), :penalty_window, delay_ms)
      end

    %{"username" => customer} = request

    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      "msg" => "Tu taxi #{taxi.nickname} está en camino"
    })

    {:noreply,
     state
     |> Map.put(:phase, :accepted)
     |> Map.put(:timer, nil)
     |> Map.put(:penalty_timer, penalty_timer)
     |> Map.put(:penalty_window, penalty_window)}
  end

  def handle_cast({:process_reject, _username}, %{timer: timer} = state) do
    cancel_timer(timer)

    case otraparte(state) do
      :no_more_taxis ->
        {:stop, :normal, state}

      {taxi, others, timer} ->
        {:noreply,
         state
         |> Map.put(:taxi, taxi)
         |> Map.put(:candidates, others)
         |> Map.put(:timer, timer)}
    end
  end

  def handle_cast({:process_cancel, username}, state) do
    cancel_timer(state.timer)
    cancel_timer(state.penalty_timer)
    notify_driver_cancelled(state)

    charge =
      case state.phase do
        :allocating -> 0
        :accepted -> if state.penalty_window, do: @penalty_amount, else: 0
      end

    message =
      if charge > 0 do
        "Cancelación tardía: se aplicó un cargo de $#{charge}."
      else
        "Viaje cancelado sin cargo."
      end

    archive_service(state, username, charge, message)
  end

  defp archive_service(state, username, charge, message) do
    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{
      "msg" => message,
      "charge" => charge
    })

    IO.inspect(
      %{
        booking_id: state.request["booking_id"],
        charge: charge,
        phase: state.phase
      },
      label: "Archive service"
    )

    {:stop, :normal, state}
  end

  defp notify_driver_cancelled(%{taxi: %{nickname: nickname}} = _state) when not is_nil(nickname) do
    TaxiBeWeb.Endpoint.broadcast("driver:" <> nickname, "booking_request", %{
      "msg" => "El cliente canceló el viaje",
      "cancelled" => true
    })
  end

  defp notify_driver_cancelled(_state), do: :ok

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  def otraparte(%{request: %{"username" => username}, candidates: []}) do
    TaxiBeWeb.Endpoint.broadcast(
      "customer:" <> username,
      "booking_request",
      %{"msg" => "SUERTE PARA LA PROXIMA, NADIE TE QUIERE LLEVAR :c"}
    )

    :no_more_taxis
  end

  def otraparte(%{request: request, candidates: [taxi | others]}) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request

    TaxiBeWeb.Endpoint.broadcast(
      "driver:" <> taxi.nickname,
      "booking_request",
      %{
        "msg" => "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
        "bookingId" => booking_id
      }
    )

    timer = Process.send_after(self(), :timeout, 10_000)

    {taxi, others, timer}
  end

  def candidate_taxis() do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "samwise", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "pippin", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end
end
