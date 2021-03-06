
[Source](http://man.hubwiz.com/docset/Consul.docset/Contents/Resources/Documents/docs/guides/connect-envoy.html "Permalink to Using Envoy with Connect")

# Using Envoy with Connect

Consul Connect has first class support for using [Envoy][1] as a proxy. This guide will describe how to setup a development-mode Consul server and two services that use Envoy proxies on a single machine with [Docker][2]. The aim of this guide is to demonstrate a minimal working setup and the moving parts involved, it is not intended for production deployments.

For reference documentation on how the integration works and is configured, please see our [Envoy documentation][3].

##  [»][4] Setup Overview 

We'll start all containers using Docker's `host` network mode and will have a total of five containers running by the end of this guide.

1. A single Consul server 
2. An example TCP `echo` service as a destination 
3. An Envoy sidecar proxy for the `echo` service 
4. An Envoy sidecar proxy for the `client` service 
5. An example `client` service (netcat) 

We choose to run in Docker since Envoy is only distributed as a Docker image so it's the quickest way to get a demo running. The same commands used here will work in just the same way outside of Docker if you build an Envoy binary yourself.

##  [»][5] Building an Envoy Image 

Starting Envoy requires a bootstrap configuration file that points Envoy to the local agent for discovering the rest of it's configuration. The Consul binary includes the [`consul connect envoy` command][6] which can generate the bootstrap configuration for Envoy and optionally run it directly.

Envoy's official Docker image can be used with Connect directly however it requires some additional steps to generate bootstrap configuration and inject it into the container.

Instead, we'll use Docker multi-stage builds (added in version 17.05) to make a local image that has both `envoy` and `consul` binaries.

We'll create a local Docker image to use that contains both binaries. First create a `Dockerfile` containing the following:
    
    
    FROM consul:latest
    FROM envoyproxy/envoy:v1.8.0
    COPY --from=0 /bin/consul /bin/consul
    ENTRYPOINT ["dumb-init", "consul", "connect", "envoy"]
    

This takes the Consul binary from the latest release image and copies it into a new image based on the official Envoy image.

This can be built locally with:
    
    
    docker build -t consul-envoy .
    

We will use the `consul-envoy` image we just made to configure and run Envoy processes later.

##  [»][7] Deploying a Consul Server 

Next we need a Consul server. We'll work with a single Consul server in `-dev` mode for simplicity.

In order to start a proxy instance, a [proxy service definition][8] must exist on the local Consul agent. We'll create one using the [sidecar service registration][9] syntax.

Create a configuration file called `envoy_demo.hcl` containing the following service definitions.
    
    
    services {
      name = "client"
      port = 8080
      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "echo"
              local_bind_port = 9191
            }
          }
        }
      }
    }
    services {
      name = "echo"
      port = 9090
      connect {
        sidecar_service {}
      }
    }
    

The Consul container can now be started with that configuration.
    
    
    $ docker run --rm -d -v$(pwd)/envoy_demo.hcl:/etc/consul/envoy_demo.hcl 
      --network host --name consul-agent consul:latest 
      agent -dev -config-file /etc/consul/envoy_demo.hcl
    1c90f7fcc83f5390332d7a4fdda2f1bf74cf62762de9ea2f67cd5a09c0573641
    

Running with `-d` like this puts the container into the background so we can continue in the same terminal. Log output can be seen using the name we gave.
    
    
    docker logs -f consul-agent
    

Note that the Consul server has registered two services `client` and `echo`, but also registered two proxies `client-sidecar-proxy` and `echo-sidecar-proxy`. Next we'll need to run those services and proxies.

##  [»][10] Running the Echo Service 

Next we'll run the `echo` service. We can use an existing TCP echo utility image for this.

Start the echo service on port 9090 as registered before.
    
    
    $ docker run -d --network host abrarov/tcp-echo --port 9090
    1a0b0c569016d00aadc4fc2b2954209b32b510966083f2a9e17d3afc6d185d87
    

##  [»][11] Running the Proxies 

We can now run "sidecar" proxy instances.
    
    
    $ docker run --rm -d --network host --name echo-proxy 
      consul-envoy -sidecar-for echo
    3f213a3cf9b7583a194dd0507a31e0188a03fc1b6e165b7f9336b0b1bb2baccb
    $ docker run --rm -d --network host --name client-proxy 
      consul-envoy -sidecar-for client -admin-bind localhost:19001
    d8399b54ee0c1f67d729bc4c8b6e624e86d63d2d9225935971bcb4534233012b
    

The `-admin-bind` flag on the second proxy command is needed because both proxies are running on the host network and so can't bind to the same port for their admin API (which cannot be disabled).

Again we can see the output using docker logs. To see more verbose information from Envoy you can add `\-- -l debug` to the end of the commands above. This passes the `-l` (log level) option directly through to Envoy. With debug level logs you should see the config being delivered to the proxy in the output.

The [`consul connect envoy` command][6] here is connecting to the local agent, getting the proxy configuration from the proxy service registration and generating the required Envoy bootstrap configuration before `exec`ing the envoy binary directly to run it with the generated configuration.

Envoy uses the bootstrap configuration to connect to the local agent directly via gRPC and use it's xDS protocol to retrieve the actual configuration for listeners, TLS certificates, upstream service instances and so on. The xDS API allows the Envoy instance to watch for any changes so certificate rotations or changes to the upstream service instances are immediately sent to the proxy.

##  [»][12] Running the Client Service 

Finally, we can see the connectivity by running a dummy "client" service. Rather than run a full service that itself can listen, we'll simulate the service with a simple netcat process that will only talk to the `client-sidecar-proxy` Envoy instance.

Recall that we configured the `client` sidecar with one declared "upstream" dependency (the `echo` service). In that declaration we also requested that the `echo` service should be exposed to the client on local port 9191.

This configuration causes the `client-sidecar-proxy` to start a TCP proxy listening on `localhost:9191` and proxying to the `echo` service. Importantly, the listener will use the correct `client` service mTLS certificate to authorize the connection. It discovers the IP addresses of instances of the echo service via Consul service discovery.

We can now see this working if we run netcat.
    
    
    $ docker run -ti --rm --network host gophernet/netcat localhost 9191
    Hello World!
    Hello World!
    ^C
    

##  [»][13] Testing Authorization 

To demonstrate that Connect is controlling authorization for the echo service, we can add an explicit deny rule.
    
    
    $ docker run -ti --rm --network host consul:latest intention create -deny client echo
    Created: client => echo (deny)
    

Now, new connections will be denied. Depending on a few factors, netcat may not see the connection being closed but will not get a response from the service.
    
    
    $ docker run -ti --rm --network host gophernet/netcat localhost 9191
    Hello?
    Anyone there?
    ^C
    

**Note:** Envoy will not currently re-authenticate already established TCP connections so if you still have the netcat terminal open from before, that will still be able to communicate with "echo". _New_ connections should be denied though.

Removing the intention restores connectivity.
    
    
    $ docker run -ti --rm --network host consul:latest intention delete client echo
    Intention deleted.
    $ docker run -ti --rm --network host gophernet/netcat localhost 9191
    Hello?
    Hello?
    ^C
    

##  [»][14] Summary 

In this guide we walked through getting a minimal working example of two plain TCP processes communicating over mTLS using Envoy sidecars configured by Connect.

For more details on how the Envoy integration works, please see the [Envoy reference documentation][3].

To see how to get Consul Connect working in different environments like Kubernetes see the [Connect Getting Started][15] overview.

[1]: https://www.envoyproxy.io/
[2]: https://www.docker.com/
[3]: http://man.hubwiz.com/connect/proxies/envoy.html
[4]: http://man.hubwiz.com#setup-overview
[5]: http://man.hubwiz.com#building-an-envoy-image
[6]: http://man.hubwiz.com/commands/connect/envoy.html
[7]: http://man.hubwiz.com#deploying-a-consul-server
[8]: http://man.hubwiz.com/connect/proxies.html
[9]: http://man.hubwiz.com/connect/proxies/sidecar-service.html
[10]: http://man.hubwiz.com#running-the-echo-service
[11]: http://man.hubwiz.com#running-the-proxies
[12]: http://man.hubwiz.com#running-the-client-service
[13]: http://man.hubwiz.com#testing-authorization
[14]: http://man.hubwiz.com#summary
[15]: http://man.hubwiz.com/connect/index.html#getting-started-with-connect

  
