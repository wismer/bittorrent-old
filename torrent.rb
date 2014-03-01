

class PeerList
  attr_reader :socket, :packet_index, :handshake

  def initialize(socket)
    @socket    = socket
    @handshake = get_handshake
  end


  # TODO add exception in case of nil being returned from host

  def get_handshake
    initial_byte = socket.read(1)
    if !initial_byte.nil?
      len = initial_byte.bytes[0]
      {
        :pstrlen   => len,
        :pstr      => socket.read(len),
        :reserved  => socket.read(8),
        :info_hash => socket.read(20),
        :peer_id   => socket.read(20)
      }
    end
  end

  def parse_response

    # After handshake message is sent and the sha digest interpreted, the next round of transmission comes in
    # if the id is 5, then a bitfield process occurs

    len = socket.read(4).unpack("N")[0]
    id  = socket.read(1).ord

    binding.pry

    if id == 5
      process_bitfield_msg(len)
      binding.pry
      if socket.read(4).unpack("N")[0] == 4
        process_have_msg
      else
        socket.write("\x00\x00\x00\x01\x02")
      end
      # begin
      #   have_data = socket.readpartial(2**14) # <= this sometimes creates an EOF break. Check the IO library for workarounds
      #   process_have_msg(have_data)
      # rescue EOFError => e
      #   p e
      # end



      if socket.read(5) == "\x00\x00\x00\x01\x01"
        binding.pry
        request_packet(0, 0)
      end
    end
  end


  def process_bitfield_msg(len)
    bitfield      = socket.read(len - 1)
    @packet_index = bitfield.unpack("B*").join.split('').map { |e| e == '1' } # => array of 1's and 0's - 1 being piece is in poss, 0 not

    have_data = begin
                  socket.readpartial(2**14) # <= this sometimes creates an EOF break. Check the IO library for workarounds
                rescue EOFError => e
                  false
                end

    process_have_msg(have_data) if have_data
  end

  def process_have_msg(have_data = nil) # <= possible nil errors will occur with have_data
    have_data = socket.read(2**14)

    until have_data.length < 9
      data = have_data.byteslice!(6..8)
      @packet_index[data.unpack("C*").last] = true
      process_have_msg(have_data)
    end
  end

  def request_packet(offset, index)
    if @packet_data[index] != true
      request_packet(offset, index+=1)
    else
      # response <len>13<id>6 index begin length (usually 2**14)
      len = [13].pack("I>") + "\x06" + pack_request(index) + pack_request(offset) + pack_request((2**14))
      binding.pry
      socket.write(len)

      packet_length = socket.read(5).unpack("N*").join.to_i - 9

      # what's needed here is a record of the offset,

      file = DownloadFile.new(socket, offset, files)
      file.download_data
      offset += packet_length # => (2**14) - 9
      index  += 1
      request_packet(offset, index)
    end
  end

  def pack_request(i)
    [i].pack("I>")
  end
end

class DownloadFile < PeerList
  attr_reader :files, :socket, :offset
  def initialize(socket, offset, files)
    @socket = socket
    @offset = offset
    @init   = socket.read(8)
    @files  = files
    @length = 0
  end

  def download_data
    p "Downloading Packet: #{offset}"
    File.open('data', 'a') { |f| f << socket.read(offset) }
  end
end


# live_streams.map! do |stream|
#   Thread.new {
#     begin
#       stream.write("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{peer_hash[:info_hash]}#{peer_hash[:peer_id]}")
#       peer = PeerList.new(stream)
#       binding.pry
#     rescue Errno::EPIPE => e
#       p e
#     rescue Errno::ECONNRESET => e
#       p e
#     end
#   }
# end
#
# live_streams.each do |stream|
#   stream.write("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{peer_hash[:info_hash]}#{peer_hash[:peer_id]}")
#   peer = PeerList.new(stream)
#   binding.pry
# end

# .map { |s| Thread.new { s } }.each do |t|
#             a = PeerList.new(t)
