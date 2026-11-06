include(joinpath(@__DIR__, "rec_common.jl"))
struct UserNote; a::Int; end
mutable struct MutNote; a::Int; end
set_save_path!(ARGS[1])
save_sim_data(mkdata(P); metadata = Dict("note" => UserNote(3), "notes" => [UserNote(1)], "dnote" => Dict("k" => UserNote(2)),
    "mnote" => MutNote(4), "snote" => Some(UserNote(5)), "tnote" => (UserNote(6), 1)))
