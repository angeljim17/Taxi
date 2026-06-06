defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  @allocation_timeout_seconds 30
  @penalty_threshold_seconds 10
  @penalty_amount 20
  @default_arrival_seconds 30
  @drivers_to_contact 3

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
       contacted: [],
       pending: []
     }}
  end

  def handle_info(:step1, %{request: request} = state) do
    fare_task = Task.async(fn -> notify_customer_ride_fare(request) end)
    taxis = select_candidate_taxis()
    Task.await(fare_task)

    contacted = Enum.take(taxis, @drivers_to_contact)
    forward_ride_request(request, contacted)
    timer = Process.send_after(self(), :allocation_timeout, @allocation_timeout_seconds * 1_000)

    pending = Enum.map(contacted, & &1.nickname)

    {:noreply,
     state
     |> Map.put(:contacted, contacted)
     |> Map.put(:pending, pending)
     |> Map.put(:timer, timer)}
  end

  def handle_info(:allocation_timeout, %{phase: :allocating} = state) do
    notify_allocation_failed(state)
    {:stop, :normal, state}
  end

  def handle_info(:allocation_timeout, state), do: {:noreply, state}

  def handle_info(:penalty_window, state) do
    {:noreply, Map.put(state, :penalty_window, true)}
  end

  def handle_cast({:process_accept, username}, %{phase: :allocating, pending: pending} = state) do
    if username in pending do
      cancel_timer(state.timer)

      taxi = Enum.find(state.contacted, &(&1.nickname == username))
      notify_other_drivers(state.contacted, username, "Otro conductor aceptó el viaje")
      notify_customer_taxi_assigned(state.request, taxi)

      arrival_seconds = @default_arrival_seconds
      penalty_window = arrival_seconds <= @penalty_threshold_seconds

      penalty_timer =
        if penalty_window do
          nil
        else
          delay_ms = (arrival_seconds - @penalty_threshold_seconds) * 1_000
          Process.send_after(self(), :penalty_window, delay_ms)
        end

      {:noreply,
       state
       |> Map.put(:phase, :accepted)
       |> Map.put(:taxi, taxi)
       |> Map.put(:timer, nil)
       |> Map.put(:pending, [])
       |> Map.put(:penalty_timer, penalty_timer)
       |> Map.put(:penalty_window, penalty_window)}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:process_accept, _username}, state), do: {:noreply, state}

  def handle_cast({:process_reject, username}, %{phase: :allocating, pending: pending} = state) do
    pending = List.delete(pending, username)

    if pending == [] do
      cancel_timer(state.timer)
      notify_allocation_failed(state)
      {:stop, :normal, %{state | pending: []}}
    else
      {:noreply, %{state | pending: pending}}
    end
  end

  def handle_cast({:process_reject, _username}, state), do: {:noreply, state}

  def handle_cast({:process_cancel, username}, state) do
    cancel_timer(state.timer)
    cancel_timer(state.penalty_timer)
    notify_drivers_cancelled(state)

    charge =
      case state.phase do
        :allocating -> 0
        :accepted -> if state.penalty_window, do: @penalty_amount, else: 0
      end

    message =
      if charge > 0 do
        "Cancelación tardía: un cargo de $#{charge} ha sido arrojado a las llamas del Monte del Destino."
      else
        "Viaje cancelado sin cargo."
      end

    archive_service(state, username, charge, message)
  end

  def candidate_taxis do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "samwise", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "pippin", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end

  defp notify_customer_ride_fare(%{"username" => username}) do
    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{
      "msg" => "Tu viaje costará 20 Mickey-dollars"
    })
  end

  defp select_candidate_taxis do
    candidate_taxis() |> Enum.shuffle()
  end

  defp forward_ride_request(request, taxis) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request

    Enum.each(taxis, fn taxi ->
      TaxiBeWeb.Endpoint.broadcast(
        "driver:" <> taxi.nickname,
        "booking_request",
        %{
          "msg" => "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
          "bookingId" => booking_id
        }
      )
    end)
  end

  defp notify_customer_taxi_assigned(%{"username" => customer}, taxi) do
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      "msg" => "Tu taxi #{taxi.nickname} está en camino"
    })
  end

  defp notify_allocation_failed(%{request: %{"username" => username}} = state) do
    notify_other_drivers(state.contacted, nil, "El viaje ya no está disponible")

    TaxiBeWeb.Endpoint.broadcast("customer:" <> username, "booking_request", %{
      "msg" => "nadie quiere llevarte en este momento :(",
      "failed" => true
    })

    IO.inspect(
      %{booking_id: state.request["booking_id"], result: :allocation_failed},
      label: "Taxi allocation failed"
    )
  end

  defp notify_other_drivers(taxis, accepted_username, message) do
    Enum.each(taxis, fn taxi ->
      if taxi.nickname != accepted_username do
        TaxiBeWeb.Endpoint.broadcast("driver:" <> taxi.nickname, "booking_request", %{
          "msg" => message,
          "cancelled" => true
        })
      end
    end)
  end

  defp notify_drivers_cancelled(%{contacted: contacted}) do
    Enum.each(contacted, fn taxi ->
      TaxiBeWeb.Endpoint.broadcast("driver:" <> taxi.nickname, "booking_request", %{
        "msg" => "El cliente canceló el viaje",
        "cancelled" => true
      })
    end)
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

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)
end
