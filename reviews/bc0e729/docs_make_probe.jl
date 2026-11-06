using Documenter
using PDEStudioCore

makedocs(
    sitename = "PDEStudioCore.jl",
    modules = [PDEStudioCore],
    checkdocs = :exports, remotes = nothing,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://industrial-mathematics-group.github.io/PDEStudioCore.jl/",
        # The sidebar logo needs no entry here: Documenter shows docs/src/assets/logo.svg (and logo-dark.svg for the
        # dark themes) automatically. `assets` only takes CSS/JS files and favicons.
        assets = [asset("assets/favicon.png", class = :ico, islocal = true)],
        sidebar_sitename = true,
    ),
    pages = [
        "Home" => "index.md",
        "Simulation Config" => "simulation_config.md",
        "Advanced Config" => "advanced_config.md",
        "Data & Storage" => "data.md",
        "Statistics" => "statistics.md",
        "Examples" => "examples.md",
        "API Reference" => "api.md",
    ],
)

