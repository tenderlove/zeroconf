# ZeroConf: a Pure Ruby multicast DNS client and server

ZeroConf is a multicast DNS client and server written in pure Ruby.  Use it to
find multicast services, or advertise your own!

## Client Example

I've got some Elgato Key lights that can be controlled via the network.
In this example, we're going to use ZeroConf to find them on the network,
then we'll connect with `net/http` and control them.

Lets start by getting a list of Multicast DNS services on the network:

```ruby
all_services = ZeroConf.find_services
service = all_services.grep(/_elg/).first # => "_elg._tcp.local"
```

We've found the Elgato service name on the network, next lets get the host
names and connection information:

```ruby
addr_infos = ZeroConf.find_addrinfos(service)
```

I have two lights on my network, and both of them have an IPv4 and IPv6 addresses,
so we get back an array with 4 tuples:

```
[["elgato-key-light-2d93.local", #<Addrinfo: 10.0.1.249:9123 (elgato-key-light-2d93.local)>],
 ["elgato-key-light-2d93.local", #<Addrinfo: [fe80::3e6a:9dff:fe19:b313]:9123 (elgato-key-light-2d93.local)>],
 ["elgato-key-light-48c6.local", #<Addrinfo: 10.0.1.151:9123 (elgato-key-light-48c6.local)>],
 ["elgato-key-light-48c6.local", #<Addrinfo: [fe80::3e6a:9dff:fe19:3a99]:9123 (elgato-key-light-48c6.local)>]]
 ```

We can connect either via IP address or host name.  In this example, I'm just
going to get the unique host names and ports, connect to those, and shut off
the lights.

```ruby
require "uri"
require "net/http"
require "json"

# Get unique host / port
connection_info = addr_infos.uniq(&:first).map { |host, addr| [host, addr.ip_port] }

# Turn the lights off
connection_info.each { |host, port|
  req = Net::HTTP::Put.new("/elgato/lights")
  req.body = { "numberOfLights": 1, "lights": [ { "on": 0 } ] }.to_json
  Net::HTTP.start(host, port) { |http| http.request(req) }
}
```

Here is the whole script:

```ruby
require "zeroconf"
require "uri"
require "net/http"
require "json"

# Find all services
all_services = ZeroConf.find_services

# Look for Elgato
service = all_services.grep(/_elg/).first || raise # => "_elg._tcp.local"

# Get addrinfo objects associated with that service
addr_infos = ZeroConf.find_addrinfos(service)

# Get unique host / port
connection_info = addr_infos.uniq(&:first).map { |host, addr| [host, addr.ip_port] }

# Turn the lights off
connection_info.each { |host, port|
  req = Net::HTTP::Put.new("/elgato/lights")
  req.body = { "numberOfLights": 1, "lights": [ { "on": 0 } ] }.to_json
  Net::HTTP.start(host, port) { |http| http.request(req) }
}
```

Once you've discovered the host names of the devices, you really don't need to
use the ZeroConf library anymore.  You can just hardcode the host names in your
script.  If the host names ever change, just rediscover them with ZeroConf.

## Server Example

Advertising a service requires the service name, the hostname, and the port
you want to advertise on the network.

For example, we want to advertise an HTTP service running on port 8080, and
we want the hostname to be "test-hostname.local".

Use the following code (note that the hostname should _omit_ `.local`):

```ruby
require "zeroconf"

ZeroConf.service "_http._tcp.local.", 8080, "test-hostname"
```

While this script is running, you should be able to ping `test-hostname.local`.

`ZeroConf.service` can be run in a thread, so we could combine it with WEBrick
to run an HTTP server and simultaneously advertise the server:

```ruby
require "zeroconf"
require 'webrick'

port = 8080
host = "test-hostname"

Thread.new { ZeroConf.service "_http._tcp.local.", port, host }

server = WEBrick::HTTPServer.new(:Port => port,
                                 :SSLEnable => false,
                                 :ServerAlias => host + ".local")

server.mount_proc '/' do |req, res|
  res.body = 'Hello, world!'
end

trap 'INT' do server.shutdown end

server.start
```
