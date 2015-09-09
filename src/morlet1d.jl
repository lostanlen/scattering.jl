immutable Morlet1DSpec{T<:Number} <: Abstract1DSpec{T}
    ɛ::Float64
    log2_size::Tuple{Int}
    max_qualityfactor::Float64
    max_scale::Float64
    motherfrequency::Float64
    nFilters_per_octave::Int
    nOctaves::Int
    signaltype::Type{T}
    function call{T<:Number}(::Type{Morlet1DSpec{T}}, ::Type{T};
                             ɛ=default_ɛ(T), log2_size=15,
                             max_qualityfactor=nothing, max_scale=Inf,
                             nFilters_per_octave=nothing, nOctaves=nothing,
                             tuningfrequency=nothing)
        "Integer log2_size is automatically converted to one-element tuple"
        isa(log2_size, Int) && (log2_size = tuple(log2_size))
        max_qualityfactor, nFilters_per_octave =
             default_max_qualityfactor(max_qualityfactor, nFilters_per_octave),
             default_nFilters_per_octave(nFilters_per_octave, max_qualityfactor)
        motherfrequency = tune_motherfrequency(tuningfrequency, Morlet1DSpec,
                                               nFilters_per_octave)
        nOctaves = default_nOctaves(nOctaves, Morlet1DSpec, log2_size,
                                    max_qualityfactor, max_scale,
                                    motherfrequency, nFilters_per_octave)
        spec = new{T}(ɛ, log2_size, max_qualityfactor, max_scale,
                      motherfrequency, nFilters_per_octave, nOctaves, T)
        checkspec(spec) && return spec
    end
end

"By default, `Morlet1DSpec operates on single-precision real input (Float32)."
Morlet1DSpec(T=Float32; args...) = Morlet1DSpec{T}(T; args...)

"""In the special case `nFilters_per_octave=1`, we manually set `ξ=0.39`, which
is more accurate with the Littlewood-Paley energy conservation criterion than
the generic fallback `ξ=0.4`, which is only valid when the wavelet has a
symmetric profile in the Fourier domain. This is no longer the case for
nFilters_per_octave==max_qualityfactor==1 as the Morlet low-frequency corrective
term is no longer negligible."""
default_motherfrequency(::Type{Morlet1DSpec}, nFilters_per_octave) =
    nFilters_per_octave==1 ? 0.39 : inv(3.0 - exp2(-1.0/nFilters_per_octave))

"""Computes gauss{T<:Real}(ω::T, den::T) = exp(- ω*ω/den).
The Gaussian bell curve is defined as gauss(ω) = exp(- ω² / 2σ²).
For performance reasons, we memoize the denominator 2σ², which is computed only
once in the caller morlet1d.
Also note that the exponentiation ω^2 is replaced by the explicit product ω*ω.
"""
gauss(ω, den) = @fastmath exp(- ω*ω/den)

"""Computes a one-dimensional Morlet wavelet in the Fourier domain.
A Morlet wavelet of center frequency ξ and of variance σ looks almost like
a Gaussian bell curve. To ensure that the wavelet has a vanishing moment, we
substract a corrective term around the zeroth frequency. Since we operate over
signals of finite length N, the corrective term must also be applied around the
frequencies -N, +N, and +2N."""
function fourierwavelet{T<:Real}(meta::AbstractMeta, spec::Morlet1DSpec{T})
    """1. **Gaussian denominator `den = 2σ²`**
    The FWHM (full width at half maximum) bw of a Gaussian bell curve of
    variance `σ` is defined by the equation
        `g(±bw/2) = exp(- (bw/2)²/(2σ²)) = 1/sqrt(2)`
    which leads to
        `bw² = 2 log(2) * 2σ²`.
    The denominator `den = 2σ²` of the Gaussian is thus equal to
        `den = 2σ² = bw² / (2 log(2))."""
    log2_length = spec.log2_size[1]
    half_length = 1 << (log2_length - 1)
    N = half_length << 1
    center = N * T(meta.centerfrequency)
    bw = N * T(meta.bandwidth)
    den = @fastmath bw * bw / T(2.0 * log(2.0))
    "2. **Main Gabor bell curve**"
    gauss_center = [gauss(ω-center, den) for ω in (1-3N/2):(5N/2)]
    "3. **Low-frequency corrective terms**"
    gauss_7periods = [gauss(ω, den) for ω in (1-7N/2):(7N/2)]
    gauss_mN = gauss_7periods[(1:4N)]
    gauss_0 =  gauss_7periods[(1:4N) + N]
    gauss_N =  gauss_7periods[(1:4N) + 2N]
    gauss_2N = gauss_7periods[(1:4N) + 3N]
    b = [gauss(-N - center, den) ;
         gauss( 0 - center, den) ;
         gauss( N - center, den) ;
         gauss(2N - center, den)  ]
    A = [gauss(  0, den)   gauss(  N, den)   gauss(2N, den)   gauss(3N, den) ;
         gauss( -N, den)   gauss(  0, den)   gauss( N, den)   gauss(2N, den) ;
         gauss(-2N, den)   gauss( -N, den)   gauss( 0, den)   gauss( N, den) ;
         gauss(-3N, den)   gauss(-2N, den)   gauss(-N, den)   gauss( 0, den)  ]
    y = A \ b
    (corr_mN, corr_0, corr_N, corr_2N) = tuple(y...)
    morlet = gauss_center  -
        corr_mN * gauss_mN -
        corr_0  * gauss_0  -
        corr_N  * gauss_N  -
        corr_2N * gauss_2N
    """5. **Trimming to true support boundaries**
    We look for the true ɛ boundaries of the vector above by looking
    at the first (resp. last) coefficient for which `|ψ|²(ω) > ɛ²`."""
    ɛ2 = T(spec.ɛ * spec.ɛ)
    morlet2 = abs2(morlet)
    first = findfirst(morlet2 .> ɛ2)
    last = findlast(morlet2 .> ɛ2)
    first = first + (sub_first-1)
    last = last - (length(morlet)-sub_last)
    morlet = morlet[sub_first:sub_last]
    "6. **Construction of AbstractFourier1DFilter object**"
    AbstractFourier1DFilter(morlet, first, last, log2_length)
end

"""
By neglecting the low-frequency corective term, we write the Morlet wavelet as a
Gaussian of variance σ in the Fourier domain. Its 3 dB bandwidth, defined as the
full width at half maximum (FWHM) of the squared magnitude in the Fourier
domain, is then equal to b = 2σ*sqrt(log(2)).

Therefore, for a given center frequency ω and a quality factor Q, the variance
σ of the Gaussian is equal to σ = b / (2*sqrt(log(2))). In the spatial domain,
this amounts to a Gabor wavelet (a Gaussian modulated by a sine wave, without
any low-frequency corrective term) of variance 1/σ. Its spatial scale (FWTM)
is equal to s = 2*sqrt(log(10))/σ. We conclude that the uncertainty
constant of the Morlet wavelet, defined as the (scale*bandwidth) constant,
is equal to
    h = b*s = sqrt(log(10)/log(2)) = 1.8226...
"""
uncertainty(::Type{Morlet1DSpec}) = sqrt(log(10.0) / log(2.0))
uncertainty{T<:Number}(::Type{Morlet1DSpec{T}}) = uncertainty(Morlet1DSpec)
