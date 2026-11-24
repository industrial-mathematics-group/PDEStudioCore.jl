using PDEStudioCore, Logging

action, root = ARGS
good = ParamDict(:case => "control", :map => Dict(1 => 2))
old = ParamDict(:case => "previously accepted", :map => Dict(0.5 => 2))

function print_outcome(f, label)
    try
        println(label, ": ", f())
    catch e
        e isa ArgumentError || rethrow()
        println(label, ": ", sprint(showerror, e))
    end
end

with_logger(NullLogger()) do
    set_save_path!(root)
    if action == "prepare"
        for p in (good, old)
            path = save_sim_data(create_sim_data([0.0], [1.0], p); verbose = false)
            println("Prepared ", p[:case], ": ", basename(path), " map type=", typeof(load_sim_data(p).params[:map]))
        end
    elseif action == "read"
        println("Direct lookup of control: ", does_sim_data_exist(good))
        print_outcome("Unfiltered listing") do
            length(find_sim_data(; verbose = false))
        end
        print_outcome("Filtered listing of unrelated control") do
            length(find_sim_data(Dict(:case => "control"); verbose = false))
        end
        print_outcome("Table for unrelated control") do
            size(sim_data_table(Dict(:case => "control")), 1)
        end
        print_outcome("Tidy dry run") do
            result = tidy_sim_data(; dry_run = true)
            (temp_files = length(result.temp_files), foreign = length(result.foreign))
        end
        print_outcome("Delete dry run for unrelated control") do
            length(delete_sim_data(Dict(:case => "control"); dry_run = true))
        end
        good_path = get_file_name(good)
        unsupported_path = only(filter(!=(good_path), readdir(joinpath(root, "data"); join = true)))
        mktempdir() do source
            cp(unsupported_path, joinpath(source, "a-old.jld2"))
            cp(good_path, joinpath(source, "b-control.jld2"))
            mktempdir() do destination
                set_save_path!(destination)
                print_outcome("Import of directory filtered for control") do
                    length(import_sim_data(source; filter_pairs = Dict(:case => "control")))
                end
                println("Imported control is present: ", does_sim_data_exist(good))
            end
        end
    end
end
