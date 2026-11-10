# Concurrent writes and lookups from threads + an external process adding/removing files
include(joinpath(@__DIR__, "common.jl"))
n = 200
params = [create_param_dict(:n => 3 + (i % 5), :id => i) for i in 1:n]
misses = Threads.Atomic{Int}(0)
stale = Threads.Atomic{Int}(0)
dir = joinpath(get_save_path(), "data")
# external writer: shell copies a foreign file in and removes it again, repeatedly
ext = mktempdir()
save_path_ext = mktempdir()
foreign = "2020-01-01_00-00-00_000_" * "a"^64 * ".jld2"
with_logger(NullLogger()) do
    Threads.@threads for i in 1:n
        save_sim_data(lin_solver(params[i]); verbose = false)
        PDEStudioCore._find_file(params[i]) === nothing && Threads.atomic_add!(misses, 1)
        j = rand(1:i)   # an earlier one (may or may not be written yet by another thread)
        f = PDEStudioCore._find_file(params[j])
        f === nothing || isfile(f) || Threads.atomic_add!(stale, 1)
        if i % 10 == 0
            fn = joinpath(dir, "2020-01-01_00-00-00_000_" * lpad(string(i, base = 16), 64, "a") * ".jld2"); run(`sh -c "touch $fn && rm $fn"`)
        end
    end
end
println("threads=", Threads.nthreads(), " own-file misses right after save: ", misses[], ", stale hits: ", stale[])
println("all found at the end: ", all(p -> PDEStudioCore._find_file(p) !== nothing, params),
        "  files listed: ", length(PDEStudioCore._data_files()), " (expected ", n, ")")
# external process adds a file right after a listing (within the racy window)
p = create_param_dict(:n => 4, :id => -1)
PDEStudioCore._data_files()
run(`julia --project=$(Base.active_project()) -e "using PDEStudioCore, StaticArrays; set_save_path!(\"$(get_save_path())\"); x=collect(range(0.0,1.0,length=4)); save_sim_data(create_sim_data(x, fill(SVector(1.0),4,2), [0.0,1.0], create_param_dict(:n=>4, :id=>-1)); verbose=false)"`)
println("file of another process seen: ", does_sim_data_exist(p))
# external process removes a file
rm(get_file_name(p))
println("removed by another process -> not found: ", !does_sim_data_exist(p))
