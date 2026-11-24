using PDEStudioCore, Logging

struct KeyWithWork
    work::Int
    id::Int
end
PDEStudioCore.param_identity(k::KeyWithWork) = (; id = k.id)

struct TaggedIndex <: Integer
    index::Int
    side::Symbol
end
Base.isequal(a::TaggedIndex, b::TaggedIndex) = a.index == b.index && a.side === b.side
Base.:(==)(a::TaggedIndex, b::TaggedIndex) = isequal(a, b)
Base.hash(k::TaggedIndex, h::UInt) = hash(k.index, h)
Base.string(k::TaggedIndex) = string(k.index)

function try_hash(label, value)
    try
        println(label, ": hash=", calculate_hash(ParamDict(:value => value)))
    catch e
        e isa ArgumentError || rethrow()
        println(label, ": ", sprint(showerror, e))
    end
end

tagged_solver(p) = create_sim_data([0.0], [Float64(p[:mapping][TaggedIndex(1, :left)])], p)

function check_custom_integer_keys()
    left = TaggedIndex(1, :left)
    right = TaggedIndex(1, :right)
    a = Dict(left => 10, right => 20)
    b = Dict(right => 10, left => 20)
    println("Custom integer: concrete=", isconcretetype(keytype(a)), " count=", length(a),
            " identical text=", string(left) == string(right), " equal mappings=", isequal(a, b))
    mktempdir() do root
        set_save_path!(root)
        for mapping in (a, b)
            p = ParamDict(:sim_func_name => :tagged_solver, :mapping => mapping)
            try
                s = run_all_simulations(SimulationConfig(p))
                println("Custom integer mapping: expected=", mapping[left], " actual=", only(only(load_sim_data(p).u)),
                        " ran=", length(s.ran), " cached=", length(s.cached),
                        " stored=", repr(get_clean_params(p)[:mapping]), " hash=", calculate_hash(p))
            catch e
                e isa ArgumentError || rethrow()
                println("Custom integer mapping: ", sprint(showerror, e))
            end
        end
    end
end

with_logger(NullLogger()) do
    try_hash("Vector of declared structs as key", Dict([KeyWithWork(1, 2)] => 10))
    try_hash("Mixed String/Symbol keys", Dict{Any, Int}("label" => 1, :label => 2))
    try_hash("Declared struct as key", Dict(KeyWithWork(1, 2) => 10))
    try_hash("Nonconcrete Integer key type", Dict{Integer, Int}(1 => 10))
    try_hash("Float64 key type", Dict(0.5 => 10))
    for (label, keys_) in (("Symbol", (:a, :b)), ("escaped String", ("phase\tA", "phase0")),
                           ("Int8", (Int8(1), Int8(-2))), ("UInt64", (UInt64(1), typemax(UInt64))),
                           ("BigInt", (big(1), big(2)^130)), ("Bool", (true, false)))
        a, b = keys_
        first_map = Dict(a => 1, b => 2)
        second_map = Dict(b => 2, a => 1)
        p = ParamDict(:v => first_map)
        q = ParamDict(:v => second_map)
        println(label, " key control: hashes_match=", calculate_hash(p) == calculate_hash(q),
                " normalized_keys_type=", keytype(get_clean_params(p)[:v]))
    end
    check_custom_integer_keys()
end
