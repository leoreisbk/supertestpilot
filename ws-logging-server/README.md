This node package is a tiny websocket server that directs messages from one client to another. The receiver must register its "address", and the sender specifies which receiver should get its messages. This is a 1-1 connection, since only one receiver can be registered per address.

This solution solves an Xcode constraint that blocks UI Targets from communicating within the local network ([Apple Dev Forum thread](https://developer.apple.com/forums/thread/727620)).

# Recommended Usage

Host the websocket server in which ever hosting service you prefer. Then send the URL to your server to `testpilot` using the `--loging-server` option. The URL must use the `ws://` or `wss://` protocol!

```sh
$ testpilot --bundle-id 'your.bundle.id' --logging-server 'ws://yourwebsocketserver.domain'
```

# Hosting locally

To host this server locally, you have to use a TCP tunnel like [ngrok](https://ngrok.com/docs/secure-tunnels/tunnels/tcp-tunnels/) to reroute the local traffic through a remote connection.

### Launching the server

Install the required dependencies and launch the server:
```sh
$ cd ws-logging-server
$ npm i
$ npm start [server-port]
```

The server runs on port `23153` by default, but you can use any port you want. Now launch the `ngrok` TCP tunnel **using the same port as the server**:
```sh
$ ngrok tcp [server-port]
```

That should start the tunnel and print something like the following:

```
ngrok                                                                                                                                                                                                                    (Ctrl+C to quit)
                                                                                                                                                                                                                                         
Announcing ngrok-rs: The ngrok agent as a Rust crate: https://ngrok.com/rust                                                                                                                                                             
                                                                                                                                                                                                                                         
Session Status                reconnecting (The tunnel 'tcp://2.tcpod.ngrok.io:16366' is already bound to another tunnel sessionERR_NGROK_334)                                                                                             
Account                       Flavio (Plan: Free)                                                                                                                                                                                        
Update                        update available (version 3.2.2, Ctrl-U to update)                                                                                                                                                         
Version                       3.2.1                                                                                                                                                                                                      
Region                        United States (us)                                                                                                                                                                                         
Latency                       -                                                                                                                                                                                                          
Web Interface                 http://127.0.0.1:4040                                                                                                                                                                                      
Forwarding                    tcp://2.tcp.ngrok.io:16366 -> localhost:23153                                                                                                                                                              
                                                                                                                                                                                                                                         
Connections                   ttl     opn     rt1     rt5     p50     p90                                                                                                                                                                
                              9       0       0.00    0.00    23.02   328.96
```

Grab that `tcp://` URL in the "Forwarding" section and use that as the logging server argument sent to `testpilot`. **Remember to change the protocol to `ws://`!**

```sh
$ testpilot --bundle-id 'your.bundle.id' --logging-server 'ws://2.tcp.ngrok.io:16366'
```

> ngrok's URL port might be different from the one you're using for the websocket server. Note that in the "Forwarding" section, the redirection to `localhost` should be the websocket server port