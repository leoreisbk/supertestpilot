This node package is a tiny websocket server that directs messages from one client to another. The receiver must register its "address", and the sender specifies which receiver should get its messages. This is a 1-1 connection, since only one receiver can be registered per address.

This solution solves an apparent iOS constraint that blocks UI Targets from communicating within the local network ([Apple Dev Forum thread](https://developer.apple.com/forums/thread/727620)).

To host this server locally, you have to use a TCP tunnel like [ngrok](https://ngrok.com/docs/secure-tunnels/tunnels/tcp-tunnels/) to reroute the local traffic through a remote connection. Alternatively, the websocket server can be properly hosted on a remote server.