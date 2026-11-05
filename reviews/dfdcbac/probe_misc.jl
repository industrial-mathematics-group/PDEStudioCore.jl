using PDEStudioCore, Test
const S = PDEStudioCore
# 1) first call (compilation included) of the timing test in a fresh process, after a light warm-up like the testset
str2val("1:10"); str2val("[1, 2, 3]")
println("first call reshape(1:2^48, ...): ", @elapsed(str2val("reshape(1:2^48, (2^24, 2^24))")), " s")
println("second call: ", @elapsed(str2val("reshape(1:2^48, (2^24, 2^24))")), " s")
# 2) a reshape whose dims overflow (length wraps to 0) is accepted; what does normalisation/hashing do?
v = str2val("reshape(1:0, (2^32, 2^32))")
println("value: ", summary(v), "  length = ", length(v))
for (name, g) in (("val2str", () -> val2str(v)), ("_normalize_param", () -> S._normalize_param(v)), ("calculate_hash", () -> calculate_hash(Dict(:a => v))))
    r = try; g(); catch e; "THROWS " * sprint(showerror, e); end
    println(name, ": ", r)
end
# 3) the legit sizes at the limit still round-trip, one above doesn't
for x in (collect(1:10^6), reshape(collect(1.0:10^6), 1000, 1000), [collect(1:500_000), collect(1:500_000)], collect(1:10^6 + 1),
          Dict(:a => (1, 2), :b => [1.0, 2.0]), (1, "a", :b, 'c', 2.5f0, 1//3, 1 + 2im, big(2)^200), Any[1, "x", [1, 2]], Int[], ())
    y = S._normalize_param(x)
    println(rpad(summary(x), 50), " round-trips: ", y == x && typeof(y) == typeof(x))
end
