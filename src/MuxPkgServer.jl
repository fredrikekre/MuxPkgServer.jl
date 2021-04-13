module MuxPkgServer

import HTTP
using URIs: URI
using Base: UUID, SHA1

const uuid_re = raw"[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}(?-i)"
const hash_re = raw"[0-9a-f]{40}"
const registry_re = Regex("^/registry/($(uuid_re))/($(hash_re))\$")
const resource_re = Regex("""
                          ^/registry/$(uuid_re)/($(hash_re))\$ |
                          ^/package/$(uuid_re)/($(hash_re))\$ |
                          ^/artifact/($(hash_re))\$
                          """, "x")


function serve_registry(http::HTTP.Stream)
    # TODO: Maybe catch registries here to cache which upstream server it came from...
end

function serve_registries(http::HTTP.Stream, upstreams::Vector{URI})
    regs = Dict{UUID,SHA1}()
    for upstream in upstreams
        url = URI(upstream; path="/registries")
        req = HTTP.request("GET", url; status_exception=false)
        req.status == 200 || continue
        for l in eachline(IOBuffer(req.body))
            m = match(registry_re, l)
            m === nothing && continue
            get!(regs, UUID(m[1]), SHA1(m[2]))
        end
    end
    str = sprint() do io
        for (uuid, sha1) in regs
            println(io, "/registry/$(uuid)/$(sha1)")
        end
    end
    serve_data(http, str; content_type = "text/plain")
    return nothing
end

function find_upstream(http::HTTP.Stream, upstreams::Vector{URI})
    target = http.message.target
    # TODO: Could be done asynchronous
    for upstream in upstreams
        url = URI(upstream; path=target)
        req = HTTP.request("HEAD", url; status_exception=false)
        @info "HEAD request to" url req.status
        if req.status == 200
            return proxy_pass(http, upstream)
            # This could just 301 to take load from this server, but that can possibly
            # make client configuration more difficult if any of the upstream servers
            # are authenticated for example.
            # HTTP.setstatus(http, 302)
            # HTTP.setheader(http, "Location" => url)
            # HTTP.setheader(http, "Content-Length" => "0")
            # HTTP.startwrite(http)
        end
    end
    return fourxx(http, 404)
end

"""
    MuxPkgServer.start(;
        host="0.0.0.0",
        port=8080,
        upstreams=["https://pkg.julialang.org"])
"""
function start(; host="0.0.0.0", port=8080,
                 upstreams = ["https://pkg.julialang.org"],
              )
    upstreams = URI.(upstreams)

    @info "Starting MuxPkgServer" host port upstreams
    # Start the MuxPkgServer instance
    HTTP.listen(host, port) do http::HTTP.Stream
        # Target resource
        resource = http.message.target

        if occursin(resource_re, resource)
            # /registry/${UUID}/${SHA1}, /package/${UUID}/${SHA1} and /artifact/${SHA1}
            return find_upstream(http, upstreams)
        # elseif occursin(registry_re, resource)
        #     return serve_registry(http, gid)
        elseif resource == "/registries"
            return serve_registries(http, upstreams)
        end

        # Resource URL does not exist
        return fourxx(http, 404)
    end # HTTP.listen
end



##############################
## HTTP.jl helper functions ##
##############################

# Proxy a request to upstream and write back the response
function proxy_pass(http::HTTP.Stream, upstream::URI; target::String=http.message.target)
    # Upstream URI
    proxy_uri = URI(upstream; path=target)

    # Pass along all headers except Authorization
    filter!(x -> x.first != "Authorization", http.message.headers)
    filter!(x -> x.first != "Host", http.message.headers) # TODO: see what nginx does

    # Open connection to upstream (TODO: make sure downstream used GET...)
    HTTP.open("GET", proxy_uri, http.message.headers; status_exception=false) do http2
        # Read status code and headers
        req = HTTP.startread(http2)
        @info "In open remote" req.status HTTP.isredirect(http2)
        if HTTP.isredirect(req)
            # TODO: Should this function even be called for redirects?
            #       Have asked HTTP.jl developers.
            return nothing
        end
        # Write response back to http
        @info "writing response" req.status
        HTTP.setstatus(http, req.status)
        foreach(h -> HTTP.setheader(http, h), req.headers)
        HTTP.startwrite(http)
        if http.message.method == "GET"
            HTTP.write(http, http2)
        end
    end
    return nothing
end

# Throw 4XX status codes
function fourxx(http::HTTP.Stream, s::Int, msg::Union{String,Nothing}=nothing)
    HTTP.setstatus(http, s)
    if msg === nothing
        HTTP.setheader(http, "Content-Length" => "0")
        HTTP.startwrite(http)
        HTTP.close(http.stream)
    else
        HTTP.setheader(http, "Content-Type" => "text/plain")
        HTTP.setheader(http, "Content-Length" => string(sizeof(msg)))
        HTTP.startwrite(http)
        HTTP.write(http, msg)
        HTTP.close(http.stream)
    end
    return nothing
end

function serve_data(http::HTTP.Stream, data::String; content_type::String)
    HTTP.setstatus(http, 200)
    HTTP.setheader(http, "Content-Type" => content_type)
    HTTP.setheader(http, "Content-Length" => string(sizeof(data)))
    HTTP.startwrite(http)
    if http.message.method == "GET"
        HTTP.write(http, data)
    end
    return nothing
end

end # module
