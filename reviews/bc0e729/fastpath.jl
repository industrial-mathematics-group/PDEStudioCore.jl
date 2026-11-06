# Whether get_sim_data_info answers without loading "raw": run it on a copy of the file whose "raw" entry is deleted
using Logging
function fast_path(params)
    path = get_file_name(params); old = get_save_path()
    ref = get_sim_data_info(params)
    tmp = mktempdir(); mkpath(joinpath(tmp, "data")); cp(path, joinpath(tmp, "data", basename(path)))
    with_logger(NullLogger()) do
        set_save_path!(tmp)
        try
            JLD2.jldopen(f -> delete!(f, "raw"), joinpath(tmp, "data", basename(path)), "a+")
            i = get_sim_data_info(params)
            return Base.structdiff(i, (; path = 0)) == Base.structdiff(ref, (; path = 0))
        catch
            return false
        finally
            set_save_path!(old)
        end
    end
end
