# Does a temp file of a running _update_entries! (cp of the data file) look old to tidy_sim_data?
include(joinpath(@__DIR__, "common.jl"))
p = create_param_dict(:n => 5)
save_sim_data(lin_solver(p); verbose = false)
path = get_file_name(p)
run(`touch -d "2020-01-01" $path`)
tmp = PDEStudioCore._tmp_path(path)
cp(path, tmp)                       # what _update_entries! does first
println("mtime(data) = ", mtime(path), "  mtime(tmp after cp) = ", mtime(tmp), "  age(tmp) = ", round(time() - mtime(tmp)), " s")
r = tidy_sim_data(dry_run = true)
println("tidy would remove the running write's temp file: ", tmp in r.temp_files)
rm(tmp)
# two copies with identical mtime: which one do lookups use and which does tidy remove?
h = PDEStudioCore._filename_hash(basename(path))
a = joinpath(dirname(path), "2030-01-01_00-00-00_000_" * h * ".jld2")
cp(path, a)
run(`touch -d "2020-01-01" $path $a`)
println("lookup: ", basename(PDEStudioCore._find_file(p)), "  tidy removes: ", basename.(tidy_sim_data(dry_run = true).duplicates))
