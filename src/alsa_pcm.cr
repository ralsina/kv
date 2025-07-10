# Minimal ALSA PCM capture binding for Crystal

# Link to ALSA library
@[Link("asound")]
lib LibASound
  alias SndPcmT = Void*
  alias SndPcmTPtr = Pointer(SndPcmT)
  alias SndPcmHwParamsT = Void*
  alias SndPcmHwParamsTPtr = Pointer(SndPcmHwParamsT)

  SND_PCM_STREAM_CAPTURE        = 1
  SND_PCM_ACCESS_RW_INTERLEAVED = 3
  SND_PCM_FORMAT_S16_LE         = 2

  fun snd_pcm_open(handle : LibASound::SndPcmTPtr*, name : LibC::Char*, stream : LibC::Int, mode : LibC::Int) : LibC::Int
  fun snd_pcm_close(handle : SndPcmT) : LibC::Int
  fun snd_pcm_hw_params_malloc(params : LibASound::SndPcmHwParamsTPtr*) : LibC::Int
  fun snd_pcm_hw_params_any(handle : SndPcmT, params : SndPcmHwParamsT) : LibC::Int
  fun snd_pcm_hw_params_set_access(handle : SndPcmT, params : SndPcmHwParamsT, access : LibC::Int) : LibC::Int
  fun snd_pcm_hw_params_set_format(handle : SndPcmT, params : SndPcmHwParamsT, format : LibC::Int) : LibC::Int
  fun snd_pcm_hw_params_set_channels(handle : SndPcmT, params : SndPcmHwParamsT, channels : LibC::UInt) : LibC::Int
  fun snd_pcm_hw_params_set_rate(handle : SndPcmT, params : SndPcmHwParamsT, rate : LibC::UInt, dir : LibC::Int) : LibC::Int
  fun snd_pcm_hw_params(handle : SndPcmT, params : SndPcmHwParamsT) : LibC::Int
  fun snd_pcm_hw_params_free(params : SndPcmHwParamsT) : Void
  fun snd_pcm_readi(handle : SndPcmT, buffer : Void*, size : LibC::ULong) : LibC::Long
end

class AlsaPcmCapture
  @handle : LibASound::SndPcmT

  def initialize(@device : String, @channels : Int32, @rate : Int32)
    # Correct pointer-to-pointer for snd_pcm_open
    handle_ptr = Pointer(LibASound::SndPcmT).malloc(1)
    handle_ptr.value = Pointer(Void).null
    rc = LibASound.snd_pcm_open(handle_ptr.as(Pointer(Pointer(Pointer(Void)))), @device, LibASound::SND_PCM_STREAM_CAPTURE, 0)
    raise "ALSA open error" unless rc == 0
    @handle = handle_ptr.value

    params_ptr = Pointer(LibASound::SndPcmHwParamsT).malloc(1)
    params_ptr.value = Pointer(Void).null
    rc = LibASound.snd_pcm_hw_params_malloc(params_ptr.as(Pointer(Pointer(Pointer(Void)))))
    raise "ALSA hw_params_malloc error: rc=#{rc}" unless rc == 0
    params = params_ptr.value
    raise "ALSA hw_params_malloc returned null params" if params.null?

    rc = LibASound.snd_pcm_hw_params_any(@handle, params)
    raise "ALSA hw_params_any error: rc=#{rc}" unless rc == 0
    rc = LibASound.snd_pcm_hw_params_set_access(@handle, params, LibASound::SND_PCM_ACCESS_RW_INTERLEAVED)
    raise "ALSA hw_params_set_access error: rc=#{rc}" unless rc == 0
    rc = LibASound.snd_pcm_hw_params_set_format(@handle, params, LibASound::SND_PCM_FORMAT_S16_LE)
    raise "ALSA hw_params_set_format error: rc=#{rc}" unless rc == 0
    rc = LibASound.snd_pcm_hw_params_set_channels(@handle, params, @channels)
    raise "ALSA hw_params_set_channels error: rc=#{rc}" unless rc == 0
    rc = LibASound.snd_pcm_hw_params_set_rate(@handle, params, @rate, 0)
    raise "ALSA hw_params_set_rate error: rc=#{rc}" unless rc == 0
    rc = LibASound.snd_pcm_hw_params(@handle, params)
    raise "ALSA hw_params error: rc=#{rc}" unless rc == 0
    LibASound.snd_pcm_hw_params_free(params)
  end

  def read(buffer : Bytes, frames : Int32) : Int32
    rc = LibASound.snd_pcm_readi(@handle, buffer.to_unsafe, frames)
    rc.to_i32
  end

  def close
    LibASound.snd_pcm_close(@handle)
  end
end
