using Test
using SemanticWeb

@testset "SemanticWeb.jl" begin
    @testset "RDF" begin
        include("rdf/test_types.jl")
        include("rdf/test_store.jl")
        include("rdf/test_serialization.jl")
    end

    # SPARQL tests (to be implemented)
    # @testset "SPARQL" begin
    #     include("sparql/test_parser.jl")
    #     include("sparql/test_executor.jl")
    #     include("sparql/test_queries.jl")
    # end

    # SHACL tests (to be implemented)
    # @testset "SHACL" begin
    #     include("shacl/test_parser.jl")
    #     include("shacl/test_validator.jl")
    # end
end
