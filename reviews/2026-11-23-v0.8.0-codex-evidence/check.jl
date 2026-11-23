using PDEStudioCore, JLD2, Logging

params(k) = create_param_dict(:k => k)
dataset(p, v) = create_sim_data([0.0, 1.0], fill(Float64(v), 2), p)
save(p, v) = save_sim_data(dataset(p, v); verbose=false)
fresh() = set_save_path!(mktempdir())
field(p) = load_sim_data(p).u[1][1]

const pending = Ref{Tuple{String,String}}()
function replace_during_prompt()
    src, replacement = pending[]
    mv(replacement, src; force=true)
    return "other"
end

function source_changes_after_check()
    fresh()
    p = params("run")
    dest = save(p, 7)
    original = read(dest)
    folder = mktempdir()
    src = joinpath(folder, "a-incoming.jld2")
    cp(save(params("other"), 11), joinpath(folder, "z-next.jld2"))
    replacement = joinpath(mktempdir(), "replacement.jld2")
    cp(dest, src)
    cp(dest, replacement)
    jldopen(replacement, "a+") do f
        delete!(f, "raw")
        f["raw"] = "unusable replacement"
    end
    # The callback models an atomic source replacement while the importer waits for input.
    pending[] = (src, replacement)
    imported = mktemp() do path, io
        write(io, "\nreplace_during_prompt()\n")
        flush(io)
        seekstart(io)
        redirect_stdin(io) do
            import_sim_data(folder; prompt_keys=[:k], overwrite=true)
        end
    end
    println("earlier source changed during later prompt: imports=",length(imported)," original bytes preserved=",read(dest)==original,
            " exists=",does_sim_data_exist(p)," loaded type=",typeof(load_sim_data(p)))
end

function rejected_filter_allocation()
    fresh()
    p = params("large")
    nodes = collect(range(0.0,1.0,length=1_000_000))
    file = save_sim_data(create_sim_data(nodes,ones(length(nodes)),p);verbose=false)
    other = joinpath(mktempdir(),"large.jld2")
    mv(file,other)
    filter = Dict(:k=>"unmatched")
    @assert isempty(import_sim_data(other;filter_pairs=filter))
    GC.gc()
    allocated = @allocated @assert isempty(import_sim_data(other;filter_pairs=filter))
    println("excluded source: size_bytes=",filesize(other)," allocated_bytes=",allocated," imports=0")
end

function regular_save_follows_link()
    fresh()
    p = params("run")
    dest = save(p,7)
    external = joinpath(mktempdir(),"shared.jld2")
    mv(dest,external)
    symlink(external,dest)
    original=read(external)
    save_sim_data(dataset(p,9);overwrite=true,verbose=false)
    println("ordinary save to linked destination: link preserved=",islink(dest),
            " external bytes preserved=",read(external)==original," field=",field(p))
end

with_logger(NullLogger()) do
    println("PDEStudioCore ",pkgversion(PDEStudioCore),", Julia ",VERSION)
    source_changes_after_check()
    rejected_filter_allocation()
    regular_save_follows_link()
end
