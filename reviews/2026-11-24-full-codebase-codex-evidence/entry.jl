using PDEStudioCore, JLD2, Logging

struct Calibration
    value::Int
end

# Model a writer whose loaded format can still read an old calibration,
# but cannot serialize it in the current environment.
const allow_write = Ref(true)
JLD2.writeas(::Type{Calibration}) = Int
JLD2.wconvert(::Type{Int}, x::Calibration) = allow_write[] ? x.value : error("calibration writer unavailable")
JLD2.rconvert(::Type{Calibration}, x::Int) = Calibration(x)

mktempdir() do dir
    set_save_path!(dir)
    p = create_param_dict(:case => 1)
    data = create_sim_data([0.0, 1.0], [1.0, 1.0], p)
    path = save_sim_data(data; verbose=false)
    jldopen(path, "a+") do f
        f["calibration"] = Calibration(47)
    end
    allow_write[] = false
    println("readable immediately before overwrite=", jldopen(f -> f["calibration"].value, path))
    data.metadata[:units] = "K"
    buf = IOBuffer()
    result = with_logger(ConsoleLogger(buf, Logging.Warn)) do
        save_sim_data(data; overwrite=true, verbose=false)
    end
    println("save returned destination=", result == path,
            " carry-over warning=", occursin("Could not carry over entry 'calibration'", String(take!(buf))),
            " key present after save=", jldopen(f -> haskey(f, "calibration"), path))
end
