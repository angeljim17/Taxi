import React, {useEffect, useState} from 'react';
import Button from '@mui/material/Button';

import { getSocket } from '../services/taxi_socket';
import { Card, CardContent, Typography } from '@mui/material';

function Driver(props) {
  let [message, setMessage] = useState();
  let [bookingId, setBookingId] = useState();
  let [visible, setVisible] = useState(false);

  useEffect(() => {
    const socket = getSocket();
    const channel = socket.channel("driver:" + props.username, {token: "123"});

    channel.on("booking_request", data => {
      console.log("Driver received", props.username, data);
      if (data.cancelled) {
        setVisible(false);
        setMessage(data.msg);
        return;
      }
      setMessage(data.msg);
      setBookingId(data.bookingId);
      setVisible(true);
    });

    channel.join()
      .receive("error", resp => console.error("Driver join failed", props.username, resp));

    return () => {
      channel.leave();
    };
  }, [props.username]);

  let reply = (decision) => {
    fetch(`http://localhost:4000/api/bookings/${bookingId}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({action: decision, username: props.username})
    }).then(() => setVisible(false));
  };

  return (
    <div style={{textAlign: "center", borderStyle: "solid"}}>
        Driver: {props.username}
        <div style={{backgroundColor: "lavender", height: "100px"}}>
          {
            visible ?
            <Card variant="outlined" style={{margin: "auto", width: "600px"}}>
              <CardContent>
                <Typography>
                {message}
                </Typography>
              </CardContent>
              <Button onClick={() => reply("accept")} variant="outlined" color="primary">Accept</Button>
              <Button onClick={() => reply("reject")} variant="outlined" color="secondary">Reject</Button>
            </Card> :
            null
          }
        </div>
    </div>
  );
}

export default Driver;
