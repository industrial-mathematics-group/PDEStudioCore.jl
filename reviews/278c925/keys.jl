using PDEStudioCore; const JLD2 = PDEStudioCore.JLD2
for f in readdir(ARGS[1]; join = true)
    endswith(f, ".jld2") || continue
    JLD2.jldopen(f, "r") do h; println(basename(f)[end-20:end], " ", sort(collect(keys(h))), " v", PDEStudioCore._format_version(h)); end
end
