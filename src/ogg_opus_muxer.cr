# src/ogg_opus_muxer.cr

require "io"

# Crystal FFI bindings for libogg
@[Link("ogg")]
lib LibOgg
  # These structs are just for FFI, we'll interact with them via pointers
  struct OggPacket
    packet : UInt8*
    bytes : LibC::Long
    b_o_s : LibC::Long
    e_o_s : LibC::Long
    granulepos : Int64
    packetno : Int64
  end

  struct OggPage
    header : UInt8*
    header_len : LibC::Long
    body : UInt8*
    body_len : LibC::Long
  end

  # OggStreamState is an opaque struct managed by libogg
  alias OggStreamState = Void

  fun ogg_stream_init(os : Pointer(OggStreamState), serialno : LibC::Int) : LibC::Int
  fun ogg_stream_clear(os : Pointer(OggStreamState)) : LibC::Int
  fun ogg_stream_packetin(os : Pointer(OggStreamState), op : OggPacket*) : LibC::Int
  fun ogg_stream_pageout(os : Pointer(OggStreamState), og : OggPage*) : LibC::Int
  fun ogg_stream_flush(os : Pointer(OggStreamState), og : OggPage*) : LibC::Int
end

# A pure Crystal implementation of an Ogg/Opus muxer.
class OggOpusMuxer
  @io : IO
  @os_ptr : Pointer(LibOgg::OggStreamState)
  @packetno : Int64

  def initialize(@io : IO, serial : Int, sample_rate : Int, channels : Int)
    @packetno = 0
    # Allocate a large buffer (32KB) for the ogg_stream_state to prevent memory corruption
    @os_ptr = Pointer(UInt8).malloc(32 * 1024).as(Pointer(LibOgg::OggStreamState))
    if LibOgg.ogg_stream_init(@os_ptr, serial) != 0
      LibC.free(@os_ptr.as(Void*)) # Free allocated memory on error
      raise "Ogg stream init failed"
    end

    write_headers(sample_rate, channels)
  end

  private def write_headers(sample_rate, channels)
    # 1. OpusHead (RFC 7845)
    opus_head = Bytes.new(19)
    opus_head.copy_from("OpusHead".to_slice.to_unsafe, 8)
    opus_head[8] = 1 # Version
    opus_head[9] = channels.to_u8
    opus_head[10] = 0_u8 # pre-skip LSB
    opus_head[11] = 0_u8 # pre-skip MSB
    opus_head[12] = (sample_rate & 0xFF).to_u8
    opus_head[13] = ((sample_rate >> 8) & 0xFF).to_u8
    opus_head[14] = ((sample_rate >> 16) & 0xFF).to_u8
    opus_head[15] = ((sample_rate >> 24) & 0xFF).to_u8
    opus_head[16] = 0_u8 # output gain LSB
    opus_head[17] = 0_u8 # output gain MSB
    opus_head[18] = 0 # Channel mapping family

    Log.info { "OpusHead packet: #{opus_head.hexstring}" }
    write_packet_internal(opus_head, 0, b_o_s: true)

    # 2. OpusTags (minimal)
    vendor = "kv-crystal"
    vendor_len = vendor.bytesize
    comment = IO::Memory.new
    comment.write("OpusTags".to_slice)
    comment.write_bytes(vendor_len.to_u32, IO::ByteFormat::LittleEndian)
    comment.write(vendor.to_slice)
    comment.write_bytes(0_u32, IO::ByteFormat::LittleEndian) # 0 user comments

    Log.info { "OpusTags packet: #{comment.to_slice.hexstring}" }
    write_packet_internal(comment.to_slice, 0)
  end

  def write_packet(packet : Bytes, granulepos : Int64)
    write_packet_internal(packet, granulepos)
  end

  private def write_packet_internal(packet_bytes : Bytes, granulepos : Int64, b_o_s : Bool = false, e_o_s : Bool = false)
    packet = LibOgg::OggPacket.new
    packet.packet = packet_bytes.to_unsafe
    packet.bytes = packet_bytes.size
    packet.b_o_s = b_o_s ? 1 : 0
    packet.e_o_s = e_o_s ? 1 : 0
    packet.granulepos = granulepos
    packet.packetno = @packetno
    @packetno += 1

    if LibOgg.ogg_stream_packetin(@os_ptr, pointerof(packet)) != 0
      raise "Ogg stream packetin failed"
    end

    flush_pages
  end

  private def flush_pages
    page = uninitialized LibOgg::OggPage
    while LibOgg.ogg_stream_pageout(@os_ptr, pointerof(page)) != 0
      write_page(page)
    end
  end

  private def write_page(page : LibOgg::OggPage)
    header_slice = Slice.new(page.header, page.header_len)
    body_slice = Slice.new(page.body, page.body_len)
    @io.write(header_slice)
    @io.write(body_slice)
    @io.flush
  end

  def close
    if @os_ptr.null?
      return # Already closed or not initialized
    end

    page = uninitialized LibOgg::OggPage
    while LibOgg.ogg_stream_flush(@os_ptr, pointerof(page)) != 0
      write_page(page)
    end
    LibOgg.ogg_stream_clear(@os_ptr)
    LibC.free(@os_ptr.as(Void*)) # Free the allocated memory
    @os_ptr = Pointer(LibOgg::OggStreamState).null # Mark as freed
  end
end
