import { Socket } from 'phoenix';

let socket;

export function getSocket() {
  if (!socket) {
    socket = new Socket('ws://localhost:4000/socket', { params: { userToken: '123' } });
    socket.connect();
  }
  return socket;
}

export default getSocket();
