const WebSocketServer = require('ws');
const port = process.argv[2] || 23153;

const wss = new WebSocketServer.Server({ port });
const receivers = {};

const unregister = ws => {
  // removing by value
  for (let rcv in receivers) {
    if (receivers[rcv] == ws) {
      console.log(`Unregistering receiver: \(${rcv})`);
      delete receivers[rcv]
      return;
    }
  }

  console.log("Couldn't find receiver to unregister");
}

wss.on("connection", ws => {
  console.log("New client connected");

  ws.on("message", data => {
    try {
      const json = JSON.parse(data);
      const { rcv, msg } = json;
      if (!rcv) {
        throw new Error('Invalid message');
      }

      if (!msg) {
        console.log(`Registering receiver: \(${rcv})`)
        receivers[rcv] = ws
      } else {
        if (!receivers[rcv]) {
          console.error(`Receiver not registered: ${rcv}`)
          ws.send(`{"error":"Receiver not registered"}`);
        } else {
          if (Object.keys(json).length == 2) {
            // legacy logging
            console.log(`Sending msg to legacy receiver (${rcv}) - ${msg}`);
            receivers[rcv].send(msg);
          } else {
            console.log(`Sending msg to receiver (${rcv}) - ${data}`);
            receivers[rcv].send(data.toString());
          }
        }
      }
    } catch (err) {
      console.error(err);
      ws.send(`{"error":"Invalid message"}`);
    }
  });

  ws.on("close", () => {
    console.log("Client disconnected");
    unregister(ws);
  });

  ws.onerror = err => {
    console.error(err);
    unregister(ws);
  }
});
console.log(`The WebSocket server is running on port ${port}`);