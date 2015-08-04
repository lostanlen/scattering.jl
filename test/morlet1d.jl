import WaveletScattering: Morlet1DSpec, localize, realtype

numerictypes = [Float16, Float32, Float64,
    Complex{Float16}, Complex{Float32}, Complex{Float64}]

# Morlet1DSpec constructor
for T in numerictypes
    spec = Morlet1DSpec{T}(T, ɛ=1e-5, log2_length=15, max_qualityfactor=8.0,
        max_scale=1e4, nFilters_per_octave=12, nOctaves=8)
    @test isa(spec.ɛ, realtype(T))
    @test spec.signaltype == T
    @test isa(spec.max_qualityfactor, Float64)
    @test isa(spec.max_scale, Float64)
end

# Morlet1DSpec default options
for T in numerictypes
  RealT = realtype(T)
  # ordinary defaults, user-specified nOctaves
  spec = Morlet1DSpec(signaltype=T, nOctaves=8)
  @test spec.ɛ == eps(RealT)
  @test spec.log2_length == 15
  @test_approx_eq spec.max_qualityfactor 1.0
  @test_approx_eq spec.max_scale Inf
  @test spec.nFilters_per_octave == 1
  @test spec.nOctaves == 8
  # nFilters_per_octave defaults to max_qualityfactor when it is provided
  spec = Morlet1DSpec(max_qualityfactor=8.0)
  @test spec.nFilters_per_octave == 8
  @test spec.nOctaves == 10
  # max_qualityfactor defaults to nFilters_per_octave when it is provided
  spec = Morlet1DSpec(nFilters_per_octave=12)
  @test_approx_eq spec.max_qualityfactor 12.0
  @test spec.nOctaves == 9
end

# Zero-argument constructor
spec = Morlet1DSpec()
@test spec.nOctaves == spec.log2_length - 2

# localize
# in the dyadic case, check that the mother center center frequency is 0.39
spec = Morlet1DSpec(nFilters_per_octave=1)
(bandwidths, centerfrequencies, qualityfactors, scales) = localize(spec)
@test_approx_eq centerfrequencies[1] 0.39
nfos = [2, 4, 8, 12, 16, 24, 32]
for nfo in nfos[2:end]
    spec = Morlet1DSpec(nFilters_per_octave=nfo)
    # check that the mother center frequency is at the right place
    (bandwidths, centerfreqs, qualityfactors, scales) = localize(spec)
    @test_approx_eq (centerfreqs[1]-centerfreqs[2]) (1.0 - 2*centerfreqs[1])
    # check that log-frequencies are evenly spaced
    difflogfreqs = diff(log2(centerfreqs))
    @test_approx_eq difflogfreqs (-ones(difflogfreqs)/spec.nFilters_per_octave)
    # check that all center frequencies are strictly positive
    @test all(centerfreqs.>0.0)
end
for RealT in [Float16, Float32, Float64], nfo in nfos,
  max_q in 1:nfo, max_s in [exp2(11:16); Inf]
    machine_precision = max(1e-10, eps(RealT))
    spec = Morlet1DSpec(max_qualityfactor=max_q, max_scale=max_s,
        nFilters_per_octave=nfo, signaltype=RealT)
    (bandwidths, centerfrequencies, qualityfactors, scales) = localize(spec)
    ten_epsilon = 10.0*eps(RealT)
    @test all(qualityfactors.>=1.0)
    @test all(qualityfactors.<=max_q)
    @test all(scales.>0.0)
    @test all(scales[qualityfactors.>1.0].< (max_s+machine_precision))
    @test all(scales.< (exp2(spec.log2_length)+machine_precision))
    # TODO @test scales[end] > (0.5 * exp2(spec.log2_length))
    resolutions = centerfrequencies / centerfrequencies[1]
    @test_approx_eq_eps bandwidths resolutions./qualityfactors eps(RealT)
    heisenberg_tradeoff = bandwidths .* scales
    @test all(abs(diff(heisenberg_tradeoff)) .< 1e-6)
    # TODO: test bandwidths and scales on actual wavelets
end
