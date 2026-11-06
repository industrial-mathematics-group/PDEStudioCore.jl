# A candidate fix (probe only, not the repo): a closed group carries the longest chain it held (the maximum of the
# token counts of its elements), not only its tokens since its last separator; and assignment tokens right after
# `:` (quoted operator Symbols such as `:~`, `:+=`) or inside `:(…)` are not refused.
using PDEStudioCore
const _JS = Base.JuliaSyntax
const MAXT = PDEStudioCore._MAX_TERMS; const MAXD = PDEStudioCore._MAX_DEPTH
function too_nested_fix(s::AbstractString; exempt_quoted = true)
    terms, longest, outer, open = 0, 0, Tuple{Int, Int}[], 0
    previous = before = _JS.K"Whitespace"
    for token in _JS.Tokenize.tokenize(s)
        k = _JS.kind(token)
        (_JS.is_whitespace(k) || k in (_JS.K"Comment", _JS.K"EndMarker")) && continue
        if k in (_JS.K"(", _JS.K"[", _JS.K"{")
            push!(outer, (terms, longest)); open += terms
            length(outer) > MAXD && return true
            terms = longest = 0
        elseif k in (_JS.K")", _JS.K"]", _JS.K"}")
            if isempty(outer)
                terms = longest = 0
            else
                inner = max(longest, terms, 1)
                (enclosing, longest) = pop!(outer); open -= enclosing
                terms = enclosing + inner
            end
        elseif k in (_JS.K",", _JS.K";")
            longest = max(longest, terms); terms = 0
        elseif (_JS.is_keyword(k) && k != _JS.K"var" && previous != _JS.K":") || k == _JS.K"@" ||
               (_JS.is_prec_assignment(k) && !(exempt_quoted && (previous == _JS.K":" ||
                                                                (previous == _JS.K"(" && before == _JS.K":"))))
            return true
        else
            terms += 1
        end
        open + terms > MAXT && return true
        before, previous = previous, k
    end
    return false
end
