# SPARQL Query Parser
# Parses SPARQL query strings into query objects

"""
    parse_sparql(query_string::String) -> SPARQLQuery

Parse a SPARQL query string and return a query object.
"""
function parse_sparql(query_string::String)::SPARQLQuery
    # Tokenize
    tokens = tokenize(query_string)

    # Determine query type from first non-PREFIX keyword
    query_type = nothing
    for token in tokens
        if token.type == :keyword && token.value != "PREFIX"
            query_type = token.value
            break
        elseif token.type == :keyword && token.value == "PREFIX"
            continue
        elseif token.type == :iri
            # PREFIX name:, skip the IRI tokens that follow PREFIX
            continue
        end
    end

    if query_type == "SELECT"
        return parse_select(tokens)
    elseif query_type == "CONSTRUCT"
        return parse_construct(tokens)
    elseif query_type == "ASK"
        return parse_ask(tokens)
    elseif query_type == "DESCRIBE"
        return parse_describe(tokens)
    else
        throw(ArgumentError("Unknown query type. Query must start with SELECT, CONSTRUCT, ASK, or DESCRIBE"))
    end
end

# ============================================================================
# Tokenization
# ============================================================================

struct Token
    type::Symbol  # :keyword, :variable, :iri, :literal, :symbol, :number
    value::String
end

"""
Tokenize a SPARQL query string.
"""
function tokenize(query::String)::Vector{Token}
    tokens = Token[]
    i = 1

    while i <= length(query)
        c = query[i]

        # Skip whitespace
        if isspace(c)
            i += 1
            continue
        end

        # Variables (?x, ?y)
        if c == '?'
            var_match = match(r"^\?[a-zA-Z_][a-zA-Z0-9_]*", query[i:end])
            if !isnothing(var_match)
                push!(tokens, Token(:variable, var_match.match))
                i += length(var_match.match)
                continue
            end
        end

        # IRIs in angle brackets <http://...>
        if c == '<'
            end_idx = findnext('>', query, i + 1)
            if !isnothing(end_idx)
                push!(tokens, Token(:iri, query[i:end_idx]))
                i = end_idx + 1
                continue
            end
        end

        # String literals "..."
        if c == '"'
            end_idx = i + 1
            while end_idx <= length(query) && query[end_idx] != '"'
                if query[end_idx] == '\\'
                    end_idx += 2  # Skip escaped character
                else
                    end_idx += 1
                end
            end
            if end_idx <= length(query)
                push!(tokens, Token(:literal, query[i:end_idx]))
                i = end_idx + 1
                continue
            end
        end

        # Numbers
        if isdigit(c) || (c == '-' && i + 1 <= length(query) && isdigit(query[i + 1]))
            num_match = match(r"^-?[0-9]+\.?[0-9]*", query[i:end])
            if !isnothing(num_match)
                push!(tokens, Token(:number, num_match.match))
                i += length(num_match.match)
                continue
            end
        end

        # Prefixed names (prefix:name)
        if isletter(c)
            # Try to match keyword or prefixed name
            word_match = match(r"^[a-zA-Z_][a-zA-Z0-9_]*:?[a-zA-Z0-9_]*", query[i:end])
            if !isnothing(word_match)
                word = word_match.match
                word_upper = uppercase(word)

                # Check if it's a keyword
                if word_upper in ["SELECT", "CONSTRUCT", "ASK", "DESCRIBE", "WHERE", "FILTER",
                                  "OPTIONAL", "UNION", "DISTINCT", "LIMIT", "OFFSET", "ORDER",
                                  "BY", "ASC", "DESC", "PREFIX", "A"]
                    push!(tokens, Token(:keyword, word_upper))
                else
                    # Prefixed name or IRI
                    push!(tokens, Token(:iri, word))
                end
                i += length(word_match.match)
                continue
            end
        end

        # Symbols
        if c in ['.', ';', ',', '{', '}', '(', ')', '=', '!', '<', '>', '&', '|', '*']
            # Handle multi-character operators
            if i + 1 <= length(query)
                two_char = query[i:i+1]
                if two_char in ["<=", ">=", "!=", "&&", "||"]
                    push!(tokens, Token(:symbol, two_char))
                    i += 2
                    continue
                end
            end
            push!(tokens, Token(:symbol, string(c)))
            i += 1
            continue
        end

        # Skip unrecognized characters
        i += 1
    end

    return tokens
end

# ============================================================================
# Parser State
# ============================================================================

mutable struct ParserState
    tokens::Vector{Token}
    position::Int
    prefixes::Dict{String, String}  # prefix -> namespace URI
end

ParserState(tokens::Vector{Token}) = ParserState(tokens, 1, Dict{String, String}())

function peek(state::ParserState)::Union{Token, Nothing}
    state.position <= length(state.tokens) ? state.tokens[state.position] : nothing
end

function advance(state::ParserState)::Union{Token, Nothing}
    token = peek(state)
    if !isnothing(token)
        state.position += 1
    end
    return token
end

function expect(state::ParserState, type::Symbol, value::Union{String, Nothing}=nothing)::Token
    token = peek(state)
    if isnothing(token)
        throw(ArgumentError("Unexpected end of query, expected $type"))
    end
    if token.type != type || (!isnothing(value) && token.value != value)
        throw(ArgumentError("Expected $type $(isnothing(value) ? "" : "\'$value\'"), got $(token.type) '$(token.value)'"))
    end
    return advance(state)
end

# ============================================================================
# SELECT Query Parser
# ============================================================================

function parse_select(tokens::Vector{Token})::SelectQuery
    state = ParserState(tokens)

    # Parse PREFIX declarations if present
    parse_prefixes!(state)

    # SELECT
    expect(state, :keyword, "SELECT")

    # Check for DISTINCT
    distinct = false
    if !isnothing(peek(state)) && peek(state).type == :keyword && peek(state).value == "DISTINCT"
        distinct = true
        advance(state)
    end

    # Variables (* or list of variables)
    variables = Symbol[]
    if !isnothing(peek(state)) && peek(state).type == :symbol && peek(state).value == "*"
        advance(state)
        # Will collect all variables from WHERE clause
    else
        while !isnothing(peek(state)) && peek(state).type == :variable
            var_token = advance(state)
            var_name = Symbol(var_token.value[2:end])  # Remove ?
            push!(variables, var_name)
        end
    end

    # WHERE clause
    patterns = parse_where_clause(state)

    # If SELECT *, extract all variables from patterns
    if isempty(variables)
        var_set = Set{Symbol}()
        for pattern in patterns
            for var in get_variables(pattern)
                push!(var_set, var)
            end
        end
        variables = collect(var_set)
    end

    # Query modifiers
    modifiers = parse_modifiers(state)

    return SelectQuery(variables, patterns, modifiers, distinct)
end

# ============================================================================
# CONSTRUCT Query Parser
# ============================================================================

function parse_construct(tokens::Vector{Token})::ConstructQuery
    state = ParserState(tokens)

    parse_prefixes!(state)

    # CONSTRUCT
    expect(state, :keyword, "CONSTRUCT")

    # Template
    expect(state, :symbol, "{")
    template = parse_triple_patterns(state)
    expect(state, :symbol, "}")

    # WHERE clause
    patterns = parse_where_clause(state)

    # Query modifiers
    modifiers = parse_modifiers(state)

    return ConstructQuery(template, patterns, modifiers)
end

# ============================================================================
# ASK Query Parser
# ============================================================================

function parse_ask(tokens::Vector{Token})::AskQuery
    state = ParserState(tokens)

    parse_prefixes!(state)

    # ASK
    expect(state, :keyword, "ASK")

    # WHERE clause
    patterns = parse_where_clause(state)

    return AskQuery(patterns)
end

# ============================================================================
# DESCRIBE Query Parser
# ============================================================================

function parse_describe(tokens::Vector{Token})::DescribeQuery
    state = ParserState(tokens)

    parse_prefixes!(state)

    # DESCRIBE
    expect(state, :keyword, "DESCRIBE")

    # Resources (variables or IRIs)
    resources = Union{Symbol, RDFNode}[]
    while !isnothing(peek(state))
        token = peek(state)
        if token.type == :variable
            advance(state)
            push!(resources, Symbol(token.value[2:end]))
        elseif token.type == :iri
            advance(state)
            push!(resources, parse_iri_token(token, state.prefixes))
        elseif token.type == :keyword && token.value == "WHERE"
            break
        else
            break
        end
    end

    # Optional WHERE clause
    where_clause = nothing
    if !isnothing(peek(state)) && peek(state).type == :keyword && peek(state).value == "WHERE"
        where_clause = parse_where_clause(state)
    end

    return DescribeQuery(resources, where_clause)
end

# ============================================================================
# WHERE Clause Parser
# ============================================================================

function parse_where_clause(state::ParserState)::Vector{GraphPattern}
    # WHERE keyword is optional in SPARQL (e.g. ASK { ... })
    if !isnothing(peek(state)) && peek(state).type == :keyword && peek(state).value == "WHERE"
        advance(state)
    end
    expect(state, :symbol, "{")

    patterns = parse_graph_patterns(state)

    expect(state, :symbol, "}")

    return patterns
end

function parse_graph_patterns(state::ParserState)::Vector{GraphPattern}
    patterns = GraphPattern[]

    while !isnothing(peek(state)) && !(peek(state).type == :symbol && peek(state).value == "}")
        token = peek(state)

        # Check for special patterns
        if token.type == :keyword
            if token.value == "FILTER"
                push!(patterns, parse_filter_pattern(state))
            elseif token.value == "OPTIONAL"
                push!(patterns, parse_optional_pattern(state))
            elseif token.value == "UNION"
                # UNION handled specially - need to wrap previous patterns
                # Simplified: skip for now
                advance(state)
            else
                break
            end
        else
            # Regular triple pattern
            pattern = parse_triple_pattern(state)
            if !isnothing(pattern)
                push!(patterns, pattern)
            end

            # Skip optional . separator
            if !isnothing(peek(state)) && peek(state).type == :symbol && peek(state).value == "."
                advance(state)
            end
        end
    end

    return patterns
end

function parse_triple_patterns(state::ParserState)::Vector{TriplePattern}
    patterns = TriplePattern[]

    while !isnothing(peek(state)) && !(peek(state).type == :symbol && peek(state).value == "}")
        pattern = parse_triple_pattern(state)
        if !isnothing(pattern)
            push!(patterns, pattern)
        end

        # Skip optional . separator
        if !isnothing(peek(state)) && peek(state).type == :symbol && peek(state).value == "."
            advance(state)
        else
            break
        end
    end

    return patterns
end

function parse_triple_pattern(state::ParserState)::Union{TriplePattern, Nothing}
    # Subject
    subj_token = peek(state)
    isnothing(subj_token) && return nothing

    subject = parse_term(state)
    isnothing(subject) && return nothing

    # Predicate
    pred_token = peek(state)
    isnothing(pred_token) && return nothing

    # Handle 'a' as shorthand for rdf:type
    if pred_token.type == :keyword && pred_token.value == "A"
        advance(state)
        predicate = RDF.type_
    else
        predicate = parse_term(state)
        isnothing(predicate) && return nothing
    end

    # Object
    object = parse_term(state)
    isnothing(object) && return nothing

    return TriplePattern(subject, predicate, object)
end

# ============================================================================
# Term Parser
# ============================================================================

function parse_term(state::ParserState)::Union{Symbol, RDFNode, Nothing}
    token = peek(state)
    isnothing(token) && return nothing

    if token.type == :variable
        advance(state)
        return Symbol(token.value[2:end])  # Remove ?
    elseif token.type == :iri
        advance(state)
        return parse_iri_token(token, state.prefixes)
    elseif token.type == :literal
        advance(state)
        return parse_literal_token(token)
    elseif token.type == :number
        advance(state)
        return Literal(token.value, XSD.integer)
    else
        return nothing
    end
end

function parse_iri_token(token::Token, prefixes::Dict{String, String})::IRI
    value = token.value

    # Remove angle brackets if present
    if startswith(value, '<') && endswith(value, '>')
        return IRI(value[2:end-1])
    end

    # Handle prefixed name (prefix:name)
    if contains(value, ':')
        parts = split(value, ':', limit=2)
        prefix = parts[1]
        local_name = length(parts) > 1 ? parts[2] : ""

        if haskey(prefixes, prefix)
            return IRI(prefixes[prefix] * local_name)
        else
            # Unknown prefix - treat as literal IRI
            return IRI(value)
        end
    end

    return IRI(value)
end

function parse_literal_token(token::Token)::Literal
    value = token.value

    # Remove quotes
    if startswith(value, '"') && endswith(value, '"')
        value = value[2:end-1]
    end

    # TODO: Handle language tags and datatypes
    return Literal(value)
end

# ============================================================================
# FILTER Parser
# ============================================================================

function parse_filter_pattern(state::ParserState)::FilterPattern
    expect(state, :keyword, "FILTER")
    expect(state, :symbol, "(")

    expr = parse_filter_expression(state)

    expect(state, :symbol, ")")

    return FilterPattern(expr)
end

function parse_filter_expression(state::ParserState)::FilterExpression
    # Parse left side
    left = parse_filter_term(state)

    # Check for operator
    op_token = peek(state)
    if isnothing(op_token)
        return left
    end

    if op_token.type == :symbol
        if op_token.value in ["=", "!=", "<", ">", "<=", ">="]
            advance(state)
            right = parse_filter_term(state)

            op = if op_token.value == "="
                :eq
            elseif op_token.value == "!="
                :ne
            elseif op_token.value == "<"
                :lt
            elseif op_token.value == ">"
                :gt
            elseif op_token.value == "<="
                :le
            elseif op_token.value == ">="
                :ge
            else
                :eq
            end

            return ComparisonExpr(op, left, right)
        elseif op_token.value in ["&&", "||"]
            advance(state)
            right = parse_filter_expression(state)

            op = op_token.value == "&&" ? :and : :or
            return LogicalExpr(op, [left, right])
        end
    end

    return left
end

function parse_filter_term(state::ParserState)::FilterExpression
    token = peek(state)
    isnothing(token) && throw(ArgumentError("Expected filter expression"))

    if token.type == :variable
        advance(state)
        return VarExpr(Symbol(token.value[2:end]))
    elseif token.type == :literal
        advance(state)
        return LiteralExpr(parse_literal_token(token))
    elseif token.type == :number
        advance(state)
        return LiteralExpr(Literal(token.value, XSD.integer))
    elseif token.type == :iri
        # Could be a function call
        func_name = token.value
        advance(state)

        # Check for function call
        if !isnothing(peek(state)) && peek(state).type == :symbol && peek(state).value == "("
            advance(state)
            args = FilterExpression[]

            while !isnothing(peek(state)) && !(peek(state).type == :symbol && peek(state).value == ")")
                push!(args, parse_filter_term(state))

                if !isnothing(peek(state)) && peek(state).type == :symbol && peek(state).value == ","
                    advance(state)
                end
            end

            expect(state, :symbol, ")")
            return FunctionExpr(Symbol(lowercase(func_name)), args)
        end

        # Not a function - treat as literal IRI
        return LiteralExpr(parse_iri_token(token, state.prefixes))
    else
        throw(ArgumentError("Unexpected token in filter: $(token.type) '$(token.value)'"))
    end
end

# ============================================================================
# OPTIONAL Parser
# ============================================================================

function parse_optional_pattern(state::ParserState)::OptionalPattern
    expect(state, :keyword, "OPTIONAL")
    expect(state, :symbol, "{")

    patterns = parse_graph_patterns(state)

    expect(state, :symbol, "}")

    return OptionalPattern(patterns)
end

# ============================================================================
# PREFIX Parser
# ============================================================================

function parse_prefixes!(state::ParserState)
    while !isnothing(peek(state)) && peek(state).type == :keyword && peek(state).value == "PREFIX"
        advance(state)

        # Prefix name
        prefix_token = expect(state, :iri)
        prefix_name = prefix_token.value
        if endswith(prefix_name, ':')
            prefix_name = prefix_name[1:end-1]
        end

        # IRI
        iri_token = expect(state, :iri)
        iri_value = iri_token.value
        if startswith(iri_value, '<') && endswith(iri_value, '>')
            iri_value = iri_value[2:end-1]
        end

        state.prefixes[prefix_name] = iri_value
    end
end

# ============================================================================
# Query Modifiers Parser
# ============================================================================

function parse_modifiers(state::ParserState)::QueryModifiers
    limit = nothing
    offset = nothing
    order_by = Tuple{Symbol, Symbol}[]

    while !isnothing(peek(state))
        token = peek(state)

        if token.type == :keyword
            if token.value == "LIMIT"
                advance(state)
                num_token = expect(state, :number)
                limit = parse(Int, num_token.value)
            elseif token.value == "OFFSET"
                advance(state)
                num_token = expect(state, :number)
                offset = parse(Int, num_token.value)
            elseif token.value == "ORDER"
                advance(state)
                expect(state, :keyword, "BY")

                # Parse order variables
                while !isnothing(peek(state)) && peek(state).type == :variable
                    var_token = advance(state)
                    var = Symbol(var_token.value[2:end])

                    # Check for ASC/DESC
                    direction = :asc
                    if !isnothing(peek(state)) && peek(state).type == :keyword
                        if peek(state).value == "ASC"
                            advance(state)
                            direction = :asc
                        elseif peek(state).value == "DESC"
                            advance(state)
                            direction = :desc
                        end
                    end

                    push!(order_by, (var, direction))
                end
            else
                break
            end
        else
            break
        end
    end

    return QueryModifiers(limit=limit, offset=offset, order_by=order_by)
end

# ============================================================================
# Helper Functions
# ============================================================================

function startswith_ignore_case(s::String, prefix::String)::Bool
    length(s) >= length(prefix) && uppercase(s[1:length(prefix)]) == uppercase(prefix)
end
