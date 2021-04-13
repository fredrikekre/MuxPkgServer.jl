#!/usr/bin/env julia
using MuxPkgServer

# Host/Port
try
    server = get(ENV, "JULIA_MUX_PKG_SERVER", "http://0.0.0.0:8080")
    m = match(r"(https?://)?(.+):(\d+)", server)
    global host = String(m.captures[2])
    global port = parse(Int, m.captures[3])
catch
    @warn("Invalid JULIA_MUX_PKG_SERVER setting, ignoring and using default of 0.0.0.0:8080!")
    global host = "0.0.0.0"
    global port = 8080
end

# Upstream PkgServers
upstreams = get(ENV, "JULIA_MUX_PKG_SERVER_UPSTREAMS", "https://pkg.julialang.org")
upstreams = split(upstreams, ','; keepempty=false)

# Logging
log_dir = get(ENV, "JULIA_MUX_PKG_SERVER_LOGS") do
    log_dir = mktempdir(; cleanup=false)
    @warn "JULIA_MUX_PKG_SERVER_LOGS is not set, using temp directory for logs" log_dir
    return log_dir
end
mkpath(log_dir)

using Dates, Logging, LoggingExtras
const date_format = dateformat"yyyy-mm-dd\THH:MM:SS\Z"
timestamp_logger(logger) = TransformerLogger(logger) do log
    merge(log, (; message = "[$(Dates.format(unix2datetime(time()), date_format))] $(log.message)"))
end
global_logger(TeeLogger(
    timestamp_logger(
        MinLevelLogger(
            DatetimeRotatingFileLogger(
                log_dir,
                string(raw"yyyy-mm-dd-\m\u\x\p\k\g\s\e\r\v\e\r.\l\o\g"),
            ),
            Logging.Info,
        ),
    ),
    current_logger(),
))

MuxPkgServer.start(;
    host=host, port=port,
    upstreams = upstreams,
)
