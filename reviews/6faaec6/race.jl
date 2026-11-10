using PDEStudioCore, StaticArrays
set_save_path!(mktempdir())
p = create_param_dict(:race => 1)
d = create_sim_data((collect(range(0.0, 1.0, length = 300)), collect(range(0.0, 1.0, length = 300))),
                    [SVector(rand(), rand()) for i in 1:300, j in 1:300, k in 1:10], collect(1.0:10.0), p;
                    metadata = Dict(:iterations => 412))
save_sim_data(d; verbose = false)
seen_empty = Threads.Atomic{Int}(0); done = Threads.Atomic{Bool}(false)
reader = Threads.@spawn while !done[]
    isempty(d.metadata) && Threads.atomic_add!(seen_empty, 1)
end
writer = Threads.@spawn for i in 1:5
    PDEStudioCore._save_sim_data(d, true, false, Dict{String, Any}())
end
wait(writer); done[] = true; wait(reader)
println("reader saw empty metadata ", seen_empty[], " times; after: ", d.metadata)
# a write by another task during the save is lost
lost = 0
for i in 1:5
    t = Threads.@spawn PDEStudioCore._save_sim_data(d, true, false, Dict{String, Any}())
    while isempty(d.metadata) == false && !istaskdone(t); end
    d.metadata[:flag] = i   # lands in the temporary dict if the save swapped it
    wait(t)
    global lost += !haskey(d.metadata, :flag)
    delete!(d.metadata, :flag)
end
println("writes lost: ", lost, " of 5")
