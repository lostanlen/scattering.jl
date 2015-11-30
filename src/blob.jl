# ScatteredBlob
immutable ScatteredBlob{NODE<:AbstractNode,N} <: Mocha.Blob
    nodes::Dict{Path,NODE}
    subscripts::NTuple{N,PathKey}
end

function Base.show(io::IO, blob::ScatteredBlob)
    nNodes = length(blob.nodes)
    plural = repeat("s", nNodes > 1)
    print(io, "ScatteredBlob(", nNodes, " node", plural, ")")
end

pathdepth(path::Path, refkey::PathKey) =
    mapreduce(path -> pathdepth(path, refkey), max, 1, keys(path))

function pathdepth(key::PathKey, refkey::PathKey)
    while ~isempty(key) && ~isempty(refkey) && (back(key) == back(refkey))
        pop!(key)
        pop!(refkey)
    end
    if isempty(refkey) && ~isempty(key)
        keyback = pop!(key)
        isempty(key) && (keyback.symbol == :γ) && return (1 + keyback.level)
    end
    return 1
end

function pathdepth(blob::ScatteredBlob, refkey::PathKey)
    anypath = keys(blob.nodes)[1]
    pathdepth_dictlevel = pathdepth(anypath)
    pathdepth_tensorlevel = pathdepth(blob.nodes[anypath])
    return max(pathdepth_dictlevel, pathdepth_tensorlevel)
end

function forward!(
        backend::Mocha.CPUBackend,
        blob_out::ScatteredBlob,
        bank::Bank1D,
        blob_in::ScatteredBlob)
    pathdepth(blob_in, bank.behavior.pathkey)

    map(node -> pathdepth(bank.behavior.pathkey, keys(blob_in.nodes)))
    γkey = cons(Literal(:γ, 1), bank.behavior.pathkey)
    for j in bank.behavior.j_range
        for χ in 0:(bank.spec.nFilters_per_octave-1)
            ψ = bank.ψs[1 + θ, 1 + χ, 1 + j]
            for (path_in, node_in) in input.nodes
                path_out = copy(path_in)
                path_out[γkey] = γ
                transform!(blob[path_out], blob_in[path_in], ψ)
            end
        end
    end
end
