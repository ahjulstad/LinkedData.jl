# SPARQL Query Executor
# Executes SPARQL queries against an RDFStore

"""
    query(store::RDFStore, query::SPARQLQuery) -> QueryResult

Execute a SPARQL query against the RDF store.
"""
function query(store::RDFStore, q::SPARQLQuery)::QueryResult
    if q isa SelectQuery
        return execute_select(store, q)
    elseif q isa ConstructQuery
        return execute_construct(store, q)
    elseif q isa AskQuery
        return execute_ask(store, q)
    elseif q isa DescribeQuery
        return execute_describe(store, q)
    else
        throw(ArgumentError("Unknown query type: $(typeof(q))"))
    end
end

# ============================================================================
# SELECT Query Execution
# ============================================================================

"""
Execute a SELECT query and return variable bindings.
"""
function execute_select(store::RDFStore, q::SelectQuery)::SelectResult
    # Execute graph patterns to get solutions
    solutions = execute_graph_patterns(store, q.where_clause)

    # Apply DISTINCT if requested
    if q.distinct
        solutions = unique(solutions)
    end

    # Apply ORDER BY
    if !isempty(q.modifiers.order_by)
        solutions = apply_order_by(solutions, q.modifiers.order_by)
    end

    # Apply OFFSET
    if !isnothing(q.modifiers.offset)
        offset = q.modifiers.offset
        solutions = offset < length(solutions) ? solutions[(offset+1):end] : Dict{Symbol, RDFNode}[]
    end

    # Apply LIMIT
    if !isnothing(q.modifiers.limit)
        limit = q.modifiers.limit
        solutions = solutions[1:min(limit, length(solutions))]
    end

    # Project to selected variables only
    projected = map(solutions) do binding
        Dict(var => binding[var] for var in q.variables if haskey(binding, var))
    end

    return SelectResult(q.variables, projected)
end

# ============================================================================
# CONSTRUCT Query Execution
# ============================================================================

"""
Execute a CONSTRUCT query and return constructed triples.
"""
function execute_construct(store::RDFStore, q::ConstructQuery)::ConstructResult
    # Execute WHERE clause to get solutions
    solutions = execute_graph_patterns(store, q.where_clause)

    # Apply modifiers
    if !isempty(q.modifiers.order_by)
        solutions = apply_order_by(solutions, q.modifiers.order_by)
    end
    if !isnothing(q.modifiers.offset)
        offset = q.modifiers.offset
        solutions = offset < length(solutions) ? solutions[(offset+1):end] : Dict{Symbol, RDFNode}[]
    end
    if !isnothing(q.modifiers.limit)
        limit = q.modifiers.limit
        solutions = solutions[1:min(limit, length(solutions))]
    end

    # Construct triples from template
    constructed = Triple[]
    for solution in solutions
        for pattern in q.template
            triple = instantiate_pattern(pattern, solution)
            if !isnothing(triple)
                push!(constructed, triple)
            end
        end
    end

    return ConstructResult(unique(constructed))
end

# ============================================================================
# ASK Query Execution
# ============================================================================

"""
Execute an ASK query and return boolean result.
"""
function execute_ask(store::RDFStore, q::AskQuery)::AskResult
    solutions = execute_graph_patterns(store, q.where_clause)
    return AskResult(!isempty(solutions))
end

# ============================================================================
# DESCRIBE Query Execution
# ============================================================================

"""
Execute a DESCRIBE query and return RDF description.
"""
function execute_describe(store::RDFStore, q::DescribeQuery)::DescribeResult
    # Get resources to describe
    resources = if isnothing(q.where_clause)
        # Direct resource IRIs
        RDFNode[r for r in q.resources if r isa RDFNode]
    else
        # Execute WHERE clause and collect variable bindings
        solutions = execute_graph_patterns(store, q.where_clause)
        nodes = RDFNode[]
        for solution in solutions
            for resource in q.resources
                if resource isa Symbol && haskey(solution, resource)
                    push!(nodes, solution[resource])
                elseif resource isa RDFNode
                    push!(nodes, resource)
                end
            end
        end
        unique(nodes)
    end

    # Get all triples about these resources (where they are subject or object)
    described = Triple[]
    for resource in resources
        # Triples where resource is subject
        append!(described, triples(store; subject=resource))
        # Triples where resource is object
        append!(described, triples(store; object=resource))
    end

    return DescribeResult(unique(described))
end

# ============================================================================
# Graph Pattern Execution
# ============================================================================

"""
Execute graph patterns and return all matching solutions.
"""
function execute_graph_patterns(store::RDFStore, patterns::Vector{GraphPattern})::Vector{Dict{Symbol, RDFNode}}
    if isempty(patterns)
        return [Dict{Symbol, RDFNode}()]
    end

    # Start with first pattern
    solutions = execute_single_pattern(store, patterns[1], [Dict{Symbol, RDFNode}()])

    # Join with remaining patterns
    for pattern in patterns[2:end]
        solutions = execute_single_pattern(store, pattern, solutions)
    end

    return solutions
end

"""
Execute a single graph pattern given current solutions.
"""
function execute_single_pattern(store::RDFStore, pattern::GraphPattern,
                                solutions::Vector{Dict{Symbol, RDFNode}})::Vector{Dict{Symbol, RDFNode}}
    if pattern isa TriplePattern
        return execute_triple_pattern(store, pattern, solutions)
    elseif pattern isa FilterPattern
        return execute_filter(pattern, solutions)
    elseif pattern isa OptionalPattern
        return execute_optional(store, pattern, solutions)
    elseif pattern isa UnionPattern
        return execute_union(store, pattern, solutions)
    elseif pattern isa GroupPattern
        return execute_group(store, pattern, solutions)
    else
        throw(ArgumentError("Unknown pattern type: $(typeof(pattern))"))
    end
end

"""
Execute a triple pattern and join with existing solutions.
"""
function execute_triple_pattern(store::RDFStore, pattern::TriplePattern,
                                solutions::Vector{Dict{Symbol, RDFNode}})::Vector{Dict{Symbol, RDFNode}}
    new_solutions = Dict{Symbol, RDFNode}[]

    for solution in solutions
        # Substitute variables with bound values
        subj = is_variable(pattern.subject) ? get(solution, pattern.subject, nothing) : pattern.subject
        pred = is_variable(pattern.predicate) ? get(solution, pattern.predicate, nothing) : pattern.predicate
        obj = is_variable(pattern.object) ? get(solution, pattern.object, nothing) : pattern.object

        # Find matching triples
        matches = find_matching_triples(store, subj, pred, obj)

        # Create new solutions for each match
        for (s, p, o) in matches
            new_solution = copy(solution)

            # Bind variables
            if is_variable(pattern.subject)
                if haskey(new_solution, pattern.subject) && new_solution[pattern.subject] != s
                    continue  # Conflict - skip this match
                end
                new_solution[pattern.subject] = s
            end

            if is_variable(pattern.predicate)
                if haskey(new_solution, pattern.predicate) && new_solution[pattern.predicate] != p
                    continue  # Conflict - skip this match
                end
                new_solution[pattern.predicate] = p
            end

            if is_variable(pattern.object)
                if haskey(new_solution, pattern.object) && new_solution[pattern.object] != o
                    continue  # Conflict - skip this match
                end
                new_solution[pattern.object] = o
            end

            push!(new_solutions, new_solution)
        end
    end

    return new_solutions
end

"""
Find triples matching the pattern (with Nothing representing unbound variables).
"""
function find_matching_triples(store::RDFStore,
                              subj::Union{RDFNode, Nothing},
                              pred::Union{IRI, Nothing},
                              obj::Union{RDFNode, Nothing})::Vector{Tuple{RDFNode, IRI, RDFNode}}
    # Query the store with appropriate filters
    kwargs = Dict{Symbol, Any}()
    !isnothing(subj) && (kwargs[:subject] = subj)
    !isnothing(pred) && (kwargs[:predicate] = pred)
    !isnothing(obj) && (kwargs[:object] = obj)

    matches = Tuple{RDFNode, IRI, RDFNode}[]
    for triple in triples(store; kwargs...)
        push!(matches, (triple.subject, triple.predicate, triple.object))
    end

    return matches
end

# ============================================================================
# FILTER Execution
# ============================================================================

"""
Apply FILTER to solutions.
"""
function execute_filter(pattern::FilterPattern,
                       solutions::Vector{Dict{Symbol, RDFNode}})::Vector{Dict{Symbol, RDFNode}}
    return filter(solutions) do solution
        evaluate_filter(pattern.expression, solution)
    end
end

"""
Evaluate a filter expression with given variable bindings.
"""
function evaluate_filter(expr::FilterExpression, bindings::Dict{Symbol, RDFNode})::Bool
    if expr isa VarExpr
        # Variable must be bound
        return haskey(bindings, expr.name)
    elseif expr isa LiteralExpr
        # Literals are always true (represent constant values)
        return true
    elseif expr isa ComparisonExpr
        return evaluate_comparison(expr, bindings)
    elseif expr isa LogicalExpr
        return evaluate_logical(expr, bindings)
    elseif expr isa FunctionExpr
        return evaluate_function(expr, bindings)
    else
        @warn "Unknown filter expression type: $(typeof(expr))"
        return false
    end
end

"""
Evaluate comparison expression.
"""
function evaluate_comparison(expr::ComparisonExpr, bindings::Dict{Symbol, RDFNode})::Bool
    left_val = get_expression_value(expr.left, bindings)
    right_val = get_expression_value(expr.right, bindings)

    isnothing(left_val) || isnothing(right_val) && return false

    if expr.operator == :eq
        return left_val == right_val
    elseif expr.operator == :ne
        return left_val != right_val
    elseif expr.operator in [:lt, :le, :gt, :ge]
        return evaluate_numeric_comparison(expr.operator, left_val, right_val)
    else
        @warn "Unknown comparison operator: $(expr.operator)"
        return false
    end
end

"""
Evaluate numeric comparison.
"""
function evaluate_numeric_comparison(op::Symbol, left::RDFNode, right::RDFNode)::Bool
    # Try to parse as numbers
    left_num = try_parse_number(left)
    right_num = try_parse_number(right)

    isnothing(left_num) || isnothing(right_num) && return false

    if op == :lt
        return left_num < right_num
    elseif op == :le
        return left_num <= right_num
    elseif op == :gt
        return left_num > right_num
    elseif op == :ge
        return left_num >= right_num
    else
        return false
    end
end

"""
Try to parse an RDF node as a number.
"""
function try_parse_number(node::RDFNode)::Union{Float64, Nothing}
    node isa Literal || return nothing

    try
        return parse(Float64, node.value)
    catch
        return nothing
    end
end

"""
Evaluate logical expression.
"""
function evaluate_logical(expr::LogicalExpr, bindings::Dict{Symbol, RDFNode})::Bool
    if expr.operator == :and
        return all(arg -> evaluate_filter(arg, bindings), expr.args)
    elseif expr.operator == :or
        return any(arg -> evaluate_filter(arg, bindings), expr.args)
    elseif expr.operator == :not
        return !evaluate_filter(expr.args[1], bindings)
    else
        @warn "Unknown logical operator: $(expr.operator)"
        return false
    end
end

"""
Evaluate function expression.
"""
function evaluate_function(expr::FunctionExpr, bindings::Dict{Symbol, RDFNode})::Bool
    if expr.name == :bound
        # Check if variable is bound
        var_expr = expr.args[1]
        if var_expr isa VarExpr
            return haskey(bindings, var_expr.name)
        end
        return false
    elseif expr.name == :isIRI || expr.name == :isURI
        val = get_expression_value(expr.args[1], bindings)
        return !isnothing(val) && val isa IRI
    elseif expr.name == :isLiteral
        val = get_expression_value(expr.args[1], bindings)
        return !isnothing(val) && val isa Literal
    elseif expr.name == :isBlank
        val = get_expression_value(expr.args[1], bindings)
        return !isnothing(val) && val isa BlankNode
    else
        @warn "Unsupported function: $(expr.name)"
        return false
    end
end

"""
Get the RDF value of an expression.
"""
function get_expression_value(expr::FilterExpression, bindings::Dict{Symbol, RDFNode})::Union{RDFNode, Nothing}
    if expr isa VarExpr
        return get(bindings, expr.name, nothing)
    elseif expr isa LiteralExpr
        return expr.value
    else
        return nothing
    end
end

# ============================================================================
# OPTIONAL Execution
# ============================================================================

"""
Execute OPTIONAL pattern (left outer join).
"""
function execute_optional(store::RDFStore, pattern::OptionalPattern,
                         solutions::Vector{Dict{Symbol, RDFNode}})::Vector{Dict{Symbol, RDFNode}}
    new_solutions = Dict{Symbol, RDFNode}[]

    for solution in solutions
        # Try to match optional patterns
        optional_matches = execute_graph_patterns(store, pattern.patterns)

        # Filter matches that are compatible with current solution
        compatible = filter(optional_matches) do opt_solution
            all(pairs(solution)) do (var, val)
                !haskey(opt_solution, var) || opt_solution[var] == val
            end
        end

        if isempty(compatible)
            # No match - keep original solution
            push!(new_solutions, solution)
        else
            # Merge each compatible match
            for opt_solution in compatible
                merged = merge(solution, opt_solution)
                push!(new_solutions, merged)
            end
        end
    end

    return new_solutions
end

# ============================================================================
# UNION Execution
# ============================================================================

"""
Execute UNION pattern (alternatives).
"""
function execute_union(store::RDFStore, pattern::UnionPattern,
                      solutions::Vector{Dict{Symbol, RDFNode}})::Vector{Dict{Symbol, RDFNode}}
    left_solutions = execute_graph_patterns(store, pattern.left)
    right_solutions = execute_graph_patterns(store, pattern.right)

    # Join each branch with existing solutions
    left_joined = join_solutions(solutions, left_solutions)
    right_joined = join_solutions(solutions, right_solutions)

    # Combine both branches
    return unique(vcat(left_joined, right_joined))
end

"""
Join two sets of solutions.
"""
function join_solutions(left::Vector{Dict{Symbol, RDFNode}},
                       right::Vector{Dict{Symbol, RDFNode}})::Vector{Dict{Symbol, RDFNode}}
    result = Dict{Symbol, RDFNode}[]

    for l in left
        for r in right
            # Check if compatible
            compatible = all(pairs(l)) do (var, val)
                !haskey(r, var) || r[var] == val
            end

            if compatible
                push!(result, merge(l, r))
            end
        end
    end

    return result
end

# ============================================================================
# GROUP Execution
# ============================================================================

"""
Execute grouped patterns.
"""
function execute_group(store::RDFStore, pattern::GroupPattern,
                      solutions::Vector{Dict{Symbol, RDFNode}})::Vector{Dict{Symbol, RDFNode}}
    # Execute patterns within group and join with existing solutions
    group_solutions = execute_graph_patterns(store, pattern.patterns)
    return join_solutions(solutions, group_solutions)
end

# ============================================================================
# Helper Functions
# ============================================================================

"""
Instantiate a triple pattern with variable bindings.
"""
function instantiate_pattern(pattern::TriplePattern, bindings::Dict{Symbol, RDFNode})::Union{Triple, Nothing}
    subj = is_variable(pattern.subject) ? get(bindings, pattern.subject, nothing) : pattern.subject
    pred = is_variable(pattern.predicate) ? get(bindings, pattern.predicate, nothing) : pattern.predicate
    obj = is_variable(pattern.object) ? get(bindings, pattern.object, nothing) : pattern.object

    # All positions must be bound
    if isnothing(subj) || isnothing(pred) || isnothing(obj)
        return nothing
    end

    # Subject must be IRI or BlankNode
    if !(subj isa Union{IRI, BlankNode})
        return nothing
    end

    # Predicate must be IRI
    if !(pred isa IRI)
        return nothing
    end

    return Triple(subj, pred, obj)
end

"""
Apply ORDER BY to solutions.
"""
function apply_order_by(solutions::Vector{Dict{Symbol, RDFNode}},
                       order_spec::Vector{Tuple{Symbol, Symbol}})::Vector{Dict{Symbol, RDFNode}}
    isempty(solutions) && return solutions

    sorted = copy(solutions)

    # Sort by each variable in reverse order (last variable is primary sort key)
    for (var, direction) in reverse(order_spec)
        sort!(sorted, by = s -> get(s, var, nothing),
              rev = (direction == :desc),
              lt = rdf_less_than)
    end

    return sorted
end

"""
Compare RDF nodes for ordering.
"""
function rdf_less_than(a::Union{RDFNode, Nothing}, b::Union{RDFNode, Nothing})::Bool
    isnothing(a) && return true   # Nothing sorts first
    isnothing(b) && return false

    # Both are nodes - compare by type then value
    a_type = typeof(a)
    b_type = typeof(b)

    if a_type != b_type
        # Order: IRI < BlankNode < Literal
        type_order = Dict(IRI => 1, BlankNode => 2, Literal => 3)
        return type_order[a_type] < type_order[b_type]
    end

    # Same type - compare values
    if a isa IRI
        return a.value < b.value
    elseif a isa BlankNode
        return a.id < b.id
    elseif a isa Literal
        # Compare literals by value
        return a.value < b.value
    else
        return false
    end
end
