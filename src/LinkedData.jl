module SemanticWeb

# Export RDF types and functions
export RDFNode, RDFTerm, IRI, Literal, BlankNode, Triple, Quad
export RDFStore, add!, remove!, has_triple, triples, count_triples
export count_subjects, count_predicates, count_objects, get_predicate_count
export register_namespace!, expand, abbreviate
export load!, save, parse_string!

# Export SPARQL types and functions
export SPARQLQuery, SelectQuery, ConstructQuery, AskQuery, DescribeQuery
export TriplePattern, FilterPattern, OptionalPattern, UnionPattern, GroupPattern
export GraphPattern, FilterExpression, QueryModifiers
export VarExpr, LiteralExpr, ComparisonExpr, LogicalExpr, FunctionExpr, ArithmeticExpr
export query, parse_sparql, SelectResult, ConstructResult, AskResult, DescribeResult
export is_variable, is_bound, get_variables

# Export SHACL types and functions
export Shape, NodeShape, PropertyShape
export Target, TargetClass, TargetNode, TargetSubjectsOf, TargetObjectsOf
export Constraint, MinCount, MaxCount, Datatype, Class, NodeKind
export MinLength, MaxLength, Pattern, LanguageIn, HasValue, In
export MinInclusive, MaxInclusive, MinExclusive, MaxExclusive
export Equals, Disjoint, LessThan, LessThanOrEquals
export And, Or, Not, Xone, Closed, UniqueLang
export validate, ValidationReport, ValidationResult

# Export common namespaces
export RDF, RDFS, OWL, XSD, SHACL

# Include RDF components
include("rdf/types.jl")
include("rdf/namespaces.jl")
include("rdf/store.jl")
include("rdf/serialization.jl")

# Include SPARQL components
include("sparql/types.jl")
include("sparql/executor.jl")
include("sparql/parser.jl")
# include("sparql/algebra.jl")  # To be implemented
# include("sparql/optimizer.jl")  # To be implemented

# Include SHACL components
include("shacl/types.jl")
include("shacl/validator.jl")
# include("shacl/parser.jl")  # To be implemented

end # module SemanticWeb
