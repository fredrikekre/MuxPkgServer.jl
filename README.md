# MuxPkgServer.jl

Multiplexing package server for Julia's package manager Pkg.

Pkg connects to a single server (by design) but sometimes it is desirable to be able
to talk to multiple servers at the same time.

```
                                            +-------------------+
                                        +-->| pkg.julialang.org |
                                        |   +-------------------+
                                        |
+------------+      +---------------+   |   +-------------------+
| Pkg Client |<---->|  MuxPkgServer |<--+-->| pkg.mycompany.com |
+------------+      +---------------+   |   +-------------------+
                                        |
                                        |   +-------------------+
                                        +-->| ...               |
                                            +-------------------+
```

## Running the server

From the root of this repository, run
```
$ julia --project -e 'using Pkg; Pkg.instantiate()'
```
to install the dependencies, and then
```
$ julia --project bin/run_server.jl
```
to run the server.

Alternatively, you can use Docker:
```
docker run -d -p 8080:8080 fredrikekre/muxpkgserver.jl
```
which will pull the latest image from Docker hub. If you want to build the image yourself you can use the following command at the root directory of this repo:
```
docker build -t fredrikekre/muxpkgserver.jl .
```

### Configuration

MuxPkgServer is configured with the following environmental variables:

 - `JULIA_MUX_PKG_SERVER`: interface the server should listen to, defaults to `0.0.0.0:8080`.
 - `JULIA_MUX_PKG_SERVER_UPSTREAMS`: comma separated list of upstream package servers, defaults to just `"https://pkg.julialang.org"`.
 - `JULIA_MUX_PKG_SERVER_LOGS`: server log directory, defaults to a temporary directory.
