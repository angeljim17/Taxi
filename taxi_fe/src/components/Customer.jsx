import React, {useEffect, useState} from 'react';
import Button from '@mui/material/Button'

import { getSocket } from '../services/taxi_socket';
import { TextField } from '@mui/material';

function Customer(props) {
  let [pickupAddress, setPickupAddress] = useState("Tecnologico de Monterrey, campus Puebla, Mexico");
  let [dropOffAddress, setDropOffAddress] = useState("Triangulo Las Animas, Puebla, Mexico");
  let [msg, setMsg] = useState("");
  let [msg1, setMsg1] = useState("");
  let [connected, setConnected] = useState(false);
  let [bookingId, setBookingId] = useState(null);

  useEffect(() => {
    const socket = getSocket();
    const channel = socket.channel("customer:" + props.username, {token: "123"});

    channel.on("greetings", data => console.log(data));
    channel.on("booking_request", dataFromPush => {
      console.log("Customer received", dataFromPush);
      setMsg1(dataFromPush.msg);
      if (dataFromPush.charge != null || dataFromPush.msg.includes("SUERTE")) {
        setBookingId(null);
      }
    });

    channel.join()
      .receive("ok", () => setConnected(true))
      .receive("error", resp => {
        console.error("Customer join failed", resp);
        setConnected(false);
      });

    return () => {
      channel.leave();
      setConnected(false);
    };
  }, [props.username]);

  let submit = () => {
    fetch(`http://localhost:4000/api/bookings`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({pickup_address: pickupAddress, dropoff_address: dropOffAddress, username: props.username})
    })
      .then(resp => {
        const location = resp.headers.get("Location");
        if (location) {
          setBookingId(location.split("/").pop());
        }
        return resp.json();
      })
      .then(dataFromPOST => setMsg(dataFromPOST.msg));
  };

  let cancel = () => {
    if (!bookingId) return;

    fetch(`http://localhost:4000/api/bookings/${bookingId}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({action: "cancel", username: props.username})
    })
      .then(resp => resp.json())
      .then(dataFromPOST => {
        setMsg(dataFromPOST.msg);
        setBookingId(null);
      });
  };

  return (
    <div style={{textAlign: "center", borderStyle: "solid"}}>
      Customer: {props.username}
      <div>
          <TextField id="outlined-basic" label="Pickup address"
            fullWidth
            onChange={ev => setPickupAddress(ev.target.value)}
            value={pickupAddress}/>
          <TextField id="outlined-basic" label="Drop off address"
            fullWidth
            onChange={ev => setDropOffAddress(ev.target.value)}
            value={dropOffAddress}/>
        <Button onClick={submit} variant="outlined" color="primary" disabled={!connected}>
          Submit
        </Button>
        <Button onClick={cancel} variant="outlined" color="secondary" disabled={!connected || !bookingId}>
          Cancel
        </Button>
      </div>
      <div style={{backgroundColor: "lightcyan", height: "50px"}}>
        {msg}
      </div>
      <div style={{backgroundColor: "lightblue", height: "50px"}}>
        {msg1}
      </div>
    </div>
  );
}

export default Customer;
