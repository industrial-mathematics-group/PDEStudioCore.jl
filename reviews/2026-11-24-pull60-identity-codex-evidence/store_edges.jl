using PDEStudioCore, Logging

p = ParamDict(:case => "ordinary")
make_run() = create_sim_data([0.0], [1.0], p)

function renamed_candidate()
    mktempdir() do root
        set_save_path!(joinpath(root, "original"))
        stored = save_sim_data(make_run(); verbose = false)
        source = joinpath(root, "renamed-run.jld2")
        cp(stored, source)
        set_save_path!(joinpath(root, "destination"))
        println("Renamed valid source: ", basename(source), " imported=", length(import_sim_data(source)),
                " lookup=", does_sim_data_exist(p))
    end
end

with_logger(renamed_candidate, NullLogger())
