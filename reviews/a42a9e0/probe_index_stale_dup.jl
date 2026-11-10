# A newer duplicate of a known hash added by someone else while the directory time looks unchanged (as the
# package's own test simulates a file system that caches directory times): which file do lookups return?
include(joinpath(@__DIR__, "common.jl"))
p = create_param_dict(:n => 5)
save_sim_data(lin_solver(p); verbose = false)
old = get_file_name(p)
run(`touch -d "2020-01-01" $old`)
idx = PDEStudioCore._data_index()
h = PDEStudioCore._filename_hash(basename(old))
newer = joinpath(dirname(old), "2030-01-01_00-00-00_000_" * h * ".jld2")
cp(old, newer)                                  # "another process" stores the run again
idx.stamp = mtime(dirname(old)); idx.listed = idx.stamp + 2   # directory time unchanged / listing trusted
println("lookup returns: ", basename(get_file_name(p)) == basename(old) ? "the OLDER file" : "the newer file",
        "; with a fresh listing: ", basename(PDEStudioCore._sort_newest!(copy(PDEStudioCore._data_index(fresh = true).by_hash[h]))[1]) == basename(newer) ? "newer" : "older")
