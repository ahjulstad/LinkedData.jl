module SemanticWeb

# Export RDF types and functions
export RDFNode, RDFTerm, IRI, Literal, BlankNode, Triple, Quad
export RDFStore, add!, remove!, has_triple, triples, count_triples
export count_subjects, count_predicates, count_objects, get_predicate_count
export register_namespace!, expand, abbreviate
export load!, save, parse_string!

# Export SPARQL types and functions
export SPARQLQuery, SelectQuery, ConstructQuery, AskQuery, DescribeQuery
export query, SelectResult, ConstructResult, AskResult, DescribeResult

# Export SHACL types and functions
export Shape, NodeShape, PropertyShape
export validate, ValidationReport, ValidationResult

# Export common namespaces
export RDF, RDFS, OWL, XSD, SHACL

# Include RDF components
include("rdf/types.jl")
include("rdf/namespaces.jl")
include("rdf/store.jl")
include("rdf/serialization.jl")

# Include SPARQL components (to be implemented)
# include("sparql/types.jl")
# include("sparql/parser.jl")
# include("sparql/algebra.jl")
# include("sparql/optimizer.jl")
# include("sparql/executor.jl")

# Include SHACL components (to be implemented)
# include("shacl/types.jl")
# include("shacl/parser.jl")
# include("shacl/constraints.jl")
# include("shacl/validator.jl")

end # module SemanticWeb
