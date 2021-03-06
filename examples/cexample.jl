include("../src/SoapySDR.jl")
using Printf
using FFTW
using PyPlot
using DSP
using SampledSignals

# need to redefine
import SampledSignals: blocksize, samplerate, nchannels, unsafe_read!, unsafe_write
import Base: eltype

include("fmDemod.jl")

# enumerate devices
(kwargs, sz) = SoapySDR.SoapySDRDevice_enumerate()

t = unsafe_load(kwargs)
for i = 1:Int(sz[])
    @printf "\nnumber of results in device = %i\n" t.size
    @printf "Found device #%d: " i
    keys = unsafe_string.(unsafe_wrap(Array, t.keys, t.size))
    vals = unsafe_string.(unsafe_wrap(Array, t.vals, t.size))
    for j = 1:t.size
        @printf "%s=%s, " keys[j] vals[j]
    end
    @printf "\n"
end
#SoapySDR.SoapySDRKwargsList_clear(kwargs, sz)
@printf "\nnumber of devices = %i\n" Int(sz[])
SoapySDR.SoapySDRKwargs_clear(kwargs)

# create device instance
# args can be user defined or from the enumeration result

## does not work
#sdrk = Ref{SoapySDR.SoapySDRKwargs}()
#SoapySDR.SoapySDRKwargs_set(sdrk, "driver", "rtlsdr")

sdr = SoapySDR.SoapySDRDevice_make(kwargs)

if (unsafe_load(sdr) == C_NULL)
    @printf "SoapySDRDevice_make fail: %s\n" unsafe_string(SoapySDR.SoapySDRDevice_lastError())
end

# query device info
(name, sz) = SoapySDR.SoapySDRDevice_listAntennas(sdr, SoapySDR.SOAPY_SDR_RX, 0)
@printf "Rx antennas: "
for i=1:Int(sz[])
    @printf "%s, " unsafe_string.(unsafe_wrap(Array, name, Int(sz[])))[i]
end
@printf "\n"

(name2, sz2) = SoapySDR.SoapySDRDevice_listGains(sdr, SoapySDR.SOAPY_SDR_RX, 0)
@printf "Rx gains: "
for i=1:Int(sz[])
    @printf "%s, " unsafe_string.(unsafe_wrap(Array, name2, Int(sz2[])))[i]
end
@printf "\n"

## cannot do
#SoapySDR.SoapySDRStrings_clear(name, sz[])

(ranges, sz) = SoapySDR.SoapySDRDevice_getFrequencyRange(sdr, SoapySDR.SOAPY_SDR_RX, 0)

@printf "Rx freq ranges: "
for i = 1:Int(sz[])
    range =  unsafe_wrap(Array, ranges, Int(sz[]))[i]
    @printf "[%g Hz -> %g Hz], " range.minimum range.maximum
end
@printf "\n"

# apply settings
#sampRate = 1e6
#sampRate = 1024e3
sampRate = 2048e3
if (SoapySDR.SoapySDRDevice_setSampleRate(sdr, SoapySDR.SOAPY_SDR_RX, 0, sampRate) != 0)
    @printf "setSampleRate fail: %s\n" unsafe_string(SoapySDR.SoapySDRDevice_lastError())
end


#f0 = 103.3e6
f0 = 104.1e6
#f0 = 938e6
if (SoapySDR.SoapySDRDevice_setFrequency(sdr, SoapySDR.SOAPY_SDR_RX, 0, f0) != 0)
    @printf "setFrequency fail: %s\n" unsafe_string(SoapySDR.SoapySDRDevice_lastError())
end

# set up a stream (complex floats)
rxStream = SoapySDR.SoapySDRStream()
if (SoapySDR.SoapySDRDevice_setupStream(sdr, rxStream, SoapySDR.SOAPY_SDR_RX, SoapySDR.SOAPY_SDR_CF32, C_NULL, 0) != 0)
    @printf "setupStream fail: %s\n" unsafe_string(SoapySDR.SoapySDRDevice_lastError())
end

# start streaming
SoapySDR.SoapySDRDevice_activateStream(sdr, rxStream, 0, 0, 0)

# create a re-usable buffer for rx samples
buffsz = 1024
buff = Array{ComplexF32}(undef, buffsz)

# receive some samples
timeS = 15 
timeSamp = Int(floor(timeS * sampRate / buffsz))
storeIq = zeros(ComplexF32, buffsz*timeSamp)

flags = Ref{Cint}()
timeNs = Ref{Clonglong}()
buffs = [buff] 

#storeFft = zeros(timeSamp, buffsz)
storeBuff = zeros(ComplexF32,timeSamp, buffsz)
for i=1:timeSamp
    SoapySDR.SoapySDRDevice_readStream(sdr, rxStream, buffs, buffsz, flags, timeNs, 100000)
    local storeBuff[i,:] = buff
    #local storeFft[i,:] = 20 .*log10.(abs.(fftshift(fft(buff))))
end

b = blackman(20)
storeFft = zeros(timeSamp, buffsz)
for i = 1:size(storeBuff)[1]
    #local storeFft2[i,:] = 20 .*log10.(abs.(fftshift(fft(filt(b, [1], storeBuff[i,:])))))
    local storeFft[i,:] = 20 .*log10.(abs.(fftshift(fft(storeBuff[i,:]))))
end

# get IQ array
storeIq = Array(reshape(storeBuff', :, size(storeBuff)[1]*size(storeBuff)[2])')[:]

# shutdown the stream
SoapySDR.SoapySDRDevice_deactivateStream(sdr, rxStream, 0, 0)  # stop streaming
SoapySDR.SoapySDRDevice_closeStream(sdr, rxStream)
SoapySDR.SoapySDRDevice_unmake(sdr);

function plotTimeFreq(storeFft, fs, f0)
    figure()
    minF = (f0 - fs/2 )./ 1e6
    maxF = (f0 + fs/2 )./ 1e6
    maxT = 1/fs * size(storeFft)[1] * size(storeFft)[2]
    #t = range(0, maxT, length= size(storeFft)[1])
    imshow(storeFft, extent=[minF,maxF,0,maxT], aspect="auto")
    xlabel("Frequnecy (MHz)")
    ylabel("Time (s)")
    cb = colorbar()
    cb[:set_label]("Magnitude (dB)")
end

function plotTime(data, fs)
    figure()
    maxT = 1/fs * size(data)[1]
    t = range(0, maxT, length=size(data)[1])
    plot(t, data, linewidth=0.1)
    xlim([0, maxT])
    xlabel("Time (s)")
    ylabel("Amplitude")
end

plotTimeFreq(storeFft, sampRate, f0)

(data, fs) =  fmDemod(storeIq, sampRate)
plotTime(data, fs)

wavwrite(data, "demod.wav", Fs=fs)

