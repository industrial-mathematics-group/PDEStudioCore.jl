# Re-measure the cost of _reconstructed_type on nested untyped containers, each case in a fresh warm state
using PDEStudioCore
using PDEStudioCore: _reconstructed_type as rt
rt(Any[Any[Any[Any[1.0]]]])
for (label, mk) in [("Any[30 x Any[30 x Any[30 x Any[30 Float64]]]] (8.1e5 leaves)",
                     () -> Any[Any[Any[Any[rand() for _ in 1:30] for _ in 1:30] for _ in 1:30] for _ in 1:30]),
                    ("Any[1000 x Any[1000 Float64]] (1e6 leaves)", () -> Any[Any[rand() for _ in 1:1000] for _ in 1:1000]),
                    ("Any[100 x Any[100 x Any[100 Float64]]] (1e6 leaves)",
                     () -> Any[Any[Any[rand() for _ in 1:100] for _ in 1:100] for _ in 1:100])]
    v = mk(); GC.gc()
    rt(v)
    t = @elapsed rt(v); a = @allocated rt(v)
    println(rpad(label, 64), round(t; sigdigits = 3), " s, ", round(a / 2^20; sigdigits = 3), " MiB")
end
