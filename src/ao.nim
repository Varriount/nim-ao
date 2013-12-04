from posix import
  errno

# Dynamic linking failed for me at least, because of some path issue.

#when defined(windows):
#  const
#    LibName = "libao.dll"
#elif defined(macosx):
#  const
#    LibName = "libao.dylib"
#else:
#  const
#    LibName = "libao.so"

type
  ao_device* = pointer
  ao_sample_format* = object
    bitDepth, sampleRate, channels: cint
    byteFmt: TAoEndian
    matrix: cstring
  ao_option* = object
    key, value: cstring
    next: ptr ao_option
  TAoDeviceType* = enum
    AO_TYPE_LIVE = 1,
    AO_TYPE_FILE = 2,
  TAoError* = enum
    AO_ENODRIVER = 1,
    AO_ENOTFILE = 2,
    AO_ENOTLIVE = 3,
    AO_EBADOPTION = 4,
    AO_EOPENDEVICE = 5,
    AO_EOPENFILE = 6,
    AO_EFILEEXIST = 7,
    AO_EBADFORMAT = 8,
    AO_EFAIL = 100
  TAoEndian* = enum
    AO_FMT_LITTLE = 1,
    AO_FMT_BIG = 2,
    AO_FMT_NATIVE = 4,
    
{.push importc.}

proc ao_default_driver_id*(): cint
proc ao_driver_id*(short_name: cstring): cint
proc ao_open_live*(driver_id: cint, format: ptr ao_sample_format,
  options: ptr ao_option): ao_device
proc ao_play*(device: ao_device, output_samples: cstring, num_bytes: cuint):
  cint
proc ao_close*(device: ao_device): cint

{.pop.} # importc

proc init*() {.importc: "ao_initialize"}
proc shutdown*() {.importc: "ao_shutdown"}

# High-level.

type
  PDevice* = ref object
    device*: ao_device
    fmt*: TSampleFmt
  TSampleFmt = object
    val: ao_sample_format
  TDriver* = enum
    default = "",
    alsa = "alsa",
    wmm = "wmm",
    null = "null"
  EAo* = object of E_Base

# PDevice.

proc newDevice*(fmt: TSampleFmt, driver = TDriver.default): PDevice =
  var
    driverId: cint
    err: string
  case driver
  of default:
    driverId = ao_default_driver_id()
    err = "Unable to find a usable output device"
  of alsa, wmm, null:
    driverId = ao_driver_id($driver)
    err = "No audio driver named " & $driver

  if driver_id == -1:
    raise newException(EAo, err)

  new(result)
  var tmpFmt = fmt
  result.device = ao_open_live(driverId, tmpFmt.val.addr, nil)

  if result.device != nil:
    result.fmt = fmt
    return

  err = case errno
    of AO_ENODRIVER.cint:
      "No such audio driver: " & $driver
    of AO_ENOTLIVE.cint:
      " is not a live device"
    of AO_EBADOPTION.cint:
      "An invalid value has been specified for one of the options"
    of AO_EOPENDEVICE.cint:
      "Unable to open audio device"
    else:
      "Unknown error code: " & $errno

  raise newException(EAo, err)

proc play*[T](o: PDevice, samples: openArray[T]) =
  if ao_play(o.device, cast[cstring](samples), samples.len.cuint) == 0:
    o.close()
    raise newException(EAo, "Unable to play audio. Closing the device")

proc close*(o: PDevice) =
  if ao_close(o.device) != 1:
    raise newException(EAo, "Unable to close audio device")

# TSampleFmt.

proc newSampleFmt*(bitDepth, sampleRate: Positive, channels: Positive,
    endian: TEndian = cpuEndian): TSampleFmt =
  assert channels > 0

  result.val.bitDepth = bitDepth.cint
  result.val.sampleRate = sampleRate.cint
  result.val.channels = channels.cint
  result.val.byteFmt = case endian
    of bigEndian:
      AO_FMT_BIG
    of littleEndian:
      AO_FMT_LITTLE
