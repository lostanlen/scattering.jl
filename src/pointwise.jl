abstract AbstractPointwise

immutable Identity <: AbstractPointwise end

call{T,N}(ρ::Identity, data::AbstractArray{T,N}) = data

immutable Log1P{T<:AbstractFloat} <: AbstractPointwise
    threshold::T
    function call{T}(::Type{Log1P}, threshold::T)
        (threshold<0) && throw(DomainError)
        new{T}(threshold)
    end
end

function Base.map(ρ::AbstractPointwise, blob_in::ScatteredBlob)
    blob_out = ScatteredBlob(map(ρ, blob_in.nodes))
end

function Base.map(ρ::AbstractPointwise, innodes::SortedDict)
    outnodes =
        DataStructures.SortedDict{Path,Node,Base.Order.ForwardOrdering}()
    for path in keys(innodes)
        outnodes[path] = ρ(innodes[path])
    end
    return outnodes
end

function Base.map!(
        ρ::AbstractPointwise,
        blob_out::ScatteredBlob,
        blob_in::ScatteredBlob)
    @inbounds for id in eachindex(blob_in.nodes)
        map!(ρ, blob_out.nodes[id].data, blob_in.nodes[id].data)
    end
end

for T in subtypes(AbstractPointwise)
    @eval begin
        function call{NODE<:AbstractNode}(ρ::$T, node::NODE)
            return Node(ρ(node.data), node.ranges)
        end
    end
end
