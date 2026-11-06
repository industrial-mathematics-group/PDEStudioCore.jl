# Candidate fix (not committed): fbae679's _too_nested, but the exemption applies only to a quote `:` in prefix
# position (at the start, after an opening bracket, a separator or `=>`) directly followed by the token (`:begin`,
# `:~`, `:(=)`), and never to `@`. Usage: julia patched.jl <script.jl> [args...] runs the script with the patch.
using PDEStudioCore
Core.eval(PDEStudioCore, quote
function _too_nested(s::AbstractString)
    terms, longest, outer, open = 0, 0, Tuple{Int, Int}[], 0
    # the last three tokens other than whitespace (K"Whitespace" = start of the text), and whether whitespace
    # followed the last one / the one before
    p1, p2, p3 = _JS.K"Whitespace", _JS.K"Whitespace", _JS.K"Whitespace"
    ws1, ws2 = false, false
    prefix(k) = k in (_JS.K"Whitespace", _JS.K"(", _JS.K"[", _JS.K"{", _JS.K",", _JS.K";", _JS.K"=>")
    for token in _JS.Tokenize.tokenize(s)
        k = _JS.kind(token)
        if _JS.is_whitespace(k) || k == _JS.K"Comment"
            ws1 = true; continue
        end
        k == _JS.K"EndMarker" && continue
        quoted = (p1 == _JS.K":" && !ws1 && prefix(p2)) ||
                 (p1 == _JS.K"(" && p2 == _JS.K":" && !ws1 && !ws2 && prefix(p3))
        if k in (_JS.K"(", _JS.K"[", _JS.K"{")
            push!(outer, (terms, longest)); open += terms
            length(outer) > _MAX_DEPTH && return true
            terms = longest = 0
        elseif k in (_JS.K")", _JS.K"]", _JS.K"}")
            if isempty(outer)
                terms = longest = 0
            else
                inner = max(longest, terms, 1); enclosing, longest = pop!(outer)
                open -= enclosing; terms = enclosing + inner
            end
        elseif k in (_JS.K",", _JS.K";")
            longest = max(longest, terms); terms = 0
        elseif k == _JS.K"@" || (((_JS.is_keyword(k) && k != _JS.K"var") || _JS.is_prec_assignment(k)) && !quoted)
            return true
        else
            terms += 1
        end
        open + terms > _MAX_TERMS && return true
        p3, p2, p1 = p2, p1, k
        ws2, ws1 = ws1, false
    end
    return false
end
end)
if !isempty(ARGS)
    script = abspath(popfirst!(ARGS))
    include(script)
end
