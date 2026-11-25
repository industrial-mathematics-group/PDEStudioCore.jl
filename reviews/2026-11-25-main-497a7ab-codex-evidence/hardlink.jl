using PDEStudioCore, Logging
Logging.disable_logging(Logging.Warn)

const INCLUDES = Ref(0)
link_solver(p) = create_sim_data([0.0], [Float64(INCLUDES[])], p)
if Sys.isunix()
    mktempdir() do root
        set_save_path!(joinpath(root, "runs"))
        src, hard, sym = joinpath.(Ref(root), ("source.jl", "hard.jl", "sym.jl"))
        write(src, "INCLUDES[] += 1\n")
        Base.Filesystem.hardlink(src, hard)
        symlink(src, sym)
        for alias in (sym, hard)
            println(basename(alias), ": paths name same file=", Base.samefile(src, alias))
            INCLUDES[] = 0
            c = SimulationConfig(create_param_dict(:sim_func_name => :link_solver); sources = [src, alias])
            try
                s = run_all_simulations(c; force_overwrite = true)
                println(basename(alias), ": includes=", INCLUDES[], " field=", load_sim_data(only(s.tasks)).u[1][1])
            catch e
                e isa ArgumentError || rethrow()
                println(basename(alias), ": rejected, includes=", INCLUDES[])
            end
        end
    end
end
