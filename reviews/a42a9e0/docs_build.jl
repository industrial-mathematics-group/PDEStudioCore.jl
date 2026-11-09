# docs/make.jl's makedocs with remotes = nothing (the review checkout's remote isn't GitHub), built outside the repo
using Documenter, PDEStudioCore
root = joinpath(ARGS[1], "docs")
makedocs(root = root, build = mktempdir(), remotes = nothing, sitename = "PDEStudioCore.jl", modules = [PDEStudioCore],
         checkdocs = :exports, format = Documenter.HTML(assets = [asset("assets/favicon.png", class = :ico, islocal = true)]),
         pages = ["Home" => "index.md", "Simulation Config" => "simulation_config.md", "Advanced Config" => "advanced_config.md",
                  "Data & Storage" => "data.md", "Statistics" => "statistics.md", "Examples" => "examples.md", "API Reference" => "api.md"])
println("DOCS OK")
