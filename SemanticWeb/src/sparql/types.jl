# SPARQL Query Types and Structures

# ============================================================================
# Abstract Types (declare first)
# ============================================================================

abstract type SPARQLQuery end
abstract type GraphPattern end
abstract type FilterExpression end
abstract type QueryResult end

# ============================================================================
# Query Modifiers
# ============================================================================

"""
Query modifiers: LIMIT, OFFSET, ORDER BY, etc.
"""
struct QueryModifiers
    limit::Union{Int, Nothing}
    offset::Union{Int, Nothing}
    order_by::Vector{Tuple{Symbol, Symbol}}  # [(variable, :asc/:desc), ...]

    function QueryModifiers(;limit::Union{Int, Nothing}=nothing,
                            offset::Union{Int, Nothing}=nothing,
                            order_by::Vector{Tuple{Symbol, Symbol}}=Tuple{Symbol, Symbol}[])
        new(limit, offset, order_by)
    end
end

# ============================================================================
# Filter Expressions
# ============================================================================

# Variable reference
struct VarExpr <: FilterExpression
    name::Symbol
end

# Literal value
struct LiteralExpr <: FilterExpression
    value::RDFNode
end

# Comparison operators
struct ComparisonExpr <: FilterExpression
    operator::Symbol  # :eq, :ne, :lt, :le, :gt, :ge
    left::FilterExpression
    right::FilterExpression
end

# Logical operators
struct LogicalExpr <: FilterExpression
    operator::Symbol  # :and, :or, :not
    args::Vector{FilterExpression}
end

# Function calls
struct FunctionExpr <: FilterExpression
    name::Symbol  # :str, :lang, :datatype, :bound, :regex, etc.
    args::Vector{FilterExpression}
end

# Arithmetic operators
struct ArithmeticExpr <: FilterExpression
    operator::Symbol  # :add, :sub, :mul, :div
    left::FilterExpression
    right::FilterExpression
end

# ============================================================================
# Graph Patterns
# ============================================================================

"""
Triple pattern with variables
Variables are represented as Symbols (:x, :y, :z)
"""
struct TriplePattern <: GraphPattern
    subject::Union{Symbol, RDFNode}    # Variable or concrete value
    predicate::Union{Symbol, IRI}       # Variable or IRI
    object::Union{Symbol, RDFNode}      # Variable or concrete value

    function TriplePattern(subject::Union{Symbol, RDFNode},
                          predicate::Union{Symbol, IRI},
                          object::Union{Symbol, RDFNode})
        new(subject, predicate, object)
    end
end

"""
FILTER pattern with expression
"""
struct FilterPattern <: GraphPattern
    expression::FilterExpression

    FilterPattern(expr::FilterExpression) = new(expr)
end

"""
OPTIONAL pattern - pattern may not match
"""
struct OptionalPattern <: GraphPattern
    patterns::Vector{GraphPattern}

    OptionalPattern(patterns::Vector{GraphPattern}) = new(patterns)
end

"""
UNION pattern - alternative patterns
"""
struct UnionPattern <: GraphPattern
    left::Vector{GraphPattern}
    right::Vector{GraphPattern}

    UnionPattern(left::Vector{GraphPattern}, right::Vector{GraphPattern}) = new(left, right)
end

"""
Graph pattern group (for nesting)
"""
struct GroupPattern <: GraphPattern
    patterns::Vector{GraphPattern}

    GroupPattern(patterns::Vector{GraphPattern}) = new(patterns)
end

# ============================================================================
# Query Forms
# ============================================================================

"""
SELECT query - returns variable bindings
"""
struct SelectQuery <: SPARQLQuery
    variables::Vector{Symbol}  # Variables to select (?x, ?y)
    where_clause::Vector{GraphPattern}
    modifiers::QueryModifiers
    distinct::Bool

    function SelectQuery(variables::Vector{Symbol}, where_clause::Vector{GraphPattern},
                        modifiers::QueryModifiers=QueryModifiers(), distinct::Bool=false)
        new(variables, where_clause, modifiers, distinct)
    end
end

"""
CONSTRUCT query - returns RDF triples
"""
struct ConstructQuery <: SPARQLQuery
    template::Vector{TriplePattern}  # Template for constructing triples
    where_clause::Vector{GraphPattern}
    modifiers::QueryModifiers

    function ConstructQuery(template::Vector{TriplePattern}, where_clause::Vector{GraphPattern},
                           modifiers::QueryModifiers=QueryModifiers())
        new(template, where_clause, modifiers)
    end
end

"""
ASK query - returns boolean
"""
struct AskQuery <: SPARQLQuery
    where_clause::Vector{GraphPattern}

    AskQuery(where_clause::Vector{GraphPattern}) = new(where_clause)
end

"""
DESCRIBE query - returns RDF description of resources
"""
struct DescribeQuery <: SPARQLQuery
    resources::Vector{Union{Symbol, RDFNode}}  # Variables or IRIs to describe
    where_clause::Union{Vector{GraphPattern}, Nothing}

    function DescribeQuery(resources::Vector{Union{Symbol, RDFNode}},
                          where_clause::Union{Vector{GraphPattern}, Nothing}=nothing)
        new(resources, where_clause)
    end
end

# ============================================================================
# Query Results
# ============================================================================

"""
Result of a SELECT query - variable bindings
"""
struct SelectResult <: QueryResult
    variables::Vector{Symbol}
    bindings::Vector{Dict{Symbol, RDFNode}}

    SelectResult(variables::Vector{Symbol}, bindings::Vector{Dict{Symbol, RDFNode}}) = new(variables, bindings)
end

# Iterator interface for SelectResult
Base.iterate(result::SelectResult) = isempty(result.bindings) ? nothing : (result.bindings[1], 2)
Base.iterate(result::SelectResult, state) = state > length(result.bindings) ? nothing : (result.bindings[state], state + 1)
Base.length(result::SelectResult) = length(result.bindings)
Base.getindex(result::SelectResult, i::Int) = result.bindings[i]

"""
Result of a CONSTRUCT query - RDF triples
"""
struct ConstructResult <: QueryResult
    triples::Vector{Triple}

    ConstructResult(triples::Vector{Triple}) = new(triples)
end

Base.iterate(result::ConstructResult) = isempty(result.triples) ? nothing : (result.triples[1], 2)
Base.iterate(result::ConstructResult, state) = state > length(result.triples) ? nothing : (result.triples[state], state + 1)
Base.length(result::ConstructResult) = length(result.triples)

"""
Result of an ASK query - boolean
"""
struct AskResult <: QueryResult
    result::Bool

    AskResult(result::Bool) = new(result)
end

"""
Result of a DESCRIBE query - RDF triples
"""
struct DescribeResult <: QueryResult
    triples::Vector{Triple}

    DescribeResult(triples::Vector{Triple}) = new(triples)
end

Base.iterate(result::DescribeResult) = isempty(result.triples) ? nothing : (result.triples[1], 2)
Base.iterate(result::DescribeResult, state) = state > length(result.triples) ? nothing : (result.triples[state], state + 1)
Base.length(result::DescribeResult) = length(result.triples)

# ============================================================================
# Helper Functions
# ============================================================================

"""
Check if a term is a variable (Symbol)
"""
is_variable(term::Any) = term isa Symbol

"""
Check if a term is bound (not a variable)
"""
is_bound(term::Any) = !is_variable(term)

"""
Get all variables from a triple pattern
"""
function get_variables(pattern::TriplePattern)::Vector{Symbol}
    vars = Symbol[]
    is_variable(pattern.subject) && push!(vars, pattern.subject)
    is_variable(pattern.predicate) && push!(vars, pattern.predicate)
    is_variable(pattern.object) && push!(vars, pattern.object)
    return vars
end

"""
Get all variables from a graph pattern
"""
function get_variables(pattern::GraphPattern)::Vector{Symbol}
    if pattern isa TriplePattern
        return get_variables(pattern)
    elseif pattern isa FilterPattern
        return get_variables(pattern.expression)
    elseif pattern isa OptionalPattern
        return unique(vcat([get_variables(p) for p in pattern.patterns]...))
    elseif pattern isa UnionPattern
        left_vars = unique(vcat([get_variables(p) for p in pattern.left]...))
        right_vars = unique(vcat([get_variables(p) for p in pattern.right]...))
        return unique(vcat(left_vars, right_vars))
    elseif pattern isa GroupPattern
        return unique(vcat([get_variables(p) for p in pattern.patterns]...))
    else
        return Symbol[]
    end
end

"""
Get all variables from a filter expression
"""
function get_variables(expr::FilterExpression)::Vector{Symbol}
    if expr isa VarExpr
        return [expr.name]
    elseif expr isa LiteralExpr
        return Symbol[]
    elseif expr isa ComparisonExpr
        return unique(vcat(get_variables(expr.left), get_variables(expr.right)))
    elseif expr isa LogicalExpr
        return unique(vcat([get_variables(arg) for arg in expr.args]...))
    elseif expr isa FunctionExpr
        return unique(vcat([get_variables(arg) for arg in expr.args]...))
    elseif expr isa ArithmeticExpr
        return unique(vcat(get_variables(expr.left), get_variables(expr.right)))
    else
        return Symbol[]
    end
end
