# Calibration of the small-stack detector: does the JuliaSyntax parser (parse!, no flisp fallback) overflow a Task
# with a 256 KB stack?
function overflows(s; stack = 256 * 1024)
    t = Task(() -> (Base.JuliaSyntax.parse!(Base.JuliaSyntax.ParseStream(s); rule = :statement); nothing), stack)
    schedule(t)
    try
        wait(t); return false
    catch e
        return e isa TaskFailedException && t.result isa StackOverflowError
    end
end
for (name, s) in [("begin_semi_2000", "x : begin 1; "^2000 * "1"), ("begin_semi_100", "x : begin 1; "^100 * "1"),
                  ("return_2000", "x : return 1, "^2000 * "1"), ("return_200", "x : return 1, "^200 * "1"),
                  ("at_2000", ":@a 1, "^2000 * "1"), ("paren32", "("^32 * "1" * ")"^32), ("paren33x32", ("("^32 * "1" * ")"^32 * ", ")^100),
                  ("semi_f_2000", "f(" * "1; "^2000 * "1)"), ("semi2_f_2000", "f(" * "1;; "^2000 * "1)"),
                  ("tuple_semi_2000", "(1, " * "1; "^2000 * "1)"), ("pow_500", "1^"^500 * "1"), ("pairsp_500", "[1 " * "=>:a "^500 * "]"),
                  ("dict_semi_1e5", "Dict(" * "1; "^100000 * "1)")]
    t = @elapsed r = overflows(s)
    println(rpad(name, 20), " overflow=", r, " ", round(t; digits = 3), " s")
end
