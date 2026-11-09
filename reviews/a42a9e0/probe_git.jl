using PDEStudioCore
for d in ARGS
    println(d, " => ", PDEStudioCore._git_commit(d))
end
println("default (active project ", Base.active_project(), ") => ", PDEStudioCore._git_commit())
