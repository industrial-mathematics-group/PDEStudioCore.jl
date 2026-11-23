using PDEStudioCore, Logging

const pending = Ref{Tuple{String,String}}()
function replace_first_source()
    original, replacement = pending[]
    mv(replacement, original; force=true)
    return "second"
end

params(k) = create_param_dict(:k => k)
dataset(p, v) = create_sim_data([0.0, 1.0], fill(Float64(v), 2), p)
save(p, v; overwrite=false) = save_sim_data(dataset(p,v); overwrite,verbose=false)
fresh() = set_save_path!(mktempdir())
value(p) = load_sim_data(p).u[1][1]

function valid_replacement()
    fresh()
    p = params("first")
    dest = save(p, 7)
    before = read(dest)
    srcdir = mktempdir()
    firstsrc = joinpath(srcdir, "a.jld2")
    cp(dest, firstsrc)
    cp(save(params("second"), 11), joinpath(srcdir, "z.jld2"))
    fresh()
    replacement = save(p, 91)
    set_save_path!(dirname(dirname(dest)))
    pending[] = (firstsrc, replacement)
    results = mktemp() do _, io
        write(io, "\nreplace_first_source()\n")
        flush(io)
        seekstart(io)
        redirect_stdout(devnull) do
            redirect_stdin(io) do
                import_sim_data(srcdir; prompt_keys=[:k], overwrite=true)
            end
        end
    end
    println("same-parameter replacement at second prompt: reported imports=", length(results),
            " original destination preserved=", read(dest)==before," first field=", value(p))
end

function unusable_output_directory()
    fresh()
    source = save(params("first"), 7)
    external = joinpath(mktempdir(), "run.jld2")
    mv(source, external)
    dir = joinpath(get_save_path(), "data")
    rm(dir)
    write(dir, "store path occupied by regular file")
    result = try
        "returned $(length(import_sim_data(external))) results"
    catch e
        "threw $(typeof(e))"
    end
    println("unusable output directory: ",result," original source present=",isfile(external))
end

with_logger(NullLogger()) do
    println("Julia ",VERSION)
    valid_replacement()
    unusable_output_directory()
end
