using Test
using LinkedData

@testset "LinkedData.jl" begin
    @testset "RDF" begin
        include("rdf/test_types.jl")
        include("rdf/test_store.jl")
        include("rdf/test_serialization.jl")
    end

    # SPARQL tests
    @testset "SPARQL" begin
        include("sparql/test_parser.jl")
        include("sparql/test_executor.jl")
    end

    # SHACL tests
    @testset "SHACL" begin
        include("shacl/test_validator.jl")
    end
end
