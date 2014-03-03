

class PeerList
  attr_reader :socket, :packet_index, :pieces, :peer_hash, :block_count, :sha_list
  attr_accessor :handshake

  BLOCK = 2**14

  def initialize(socket, handshake, pieces={}, peer_hash, sha_list)
    @socket     = socket
    @handshake  = {
                    :pstrlen   => handshake.slice!(0).unpack("C")[0],
                    :pstr      => handshake.slice!(0..18),
                    :reserved  => handshake.slice!(0..7),
                    :info_hash => handshake.slice!(0..19),
                    :peer_id   => handshake.slice!(0..19)
                  }
    @block_count = pieces[:piece_size] / BLOCK
    @peer_hash   = peer_hash
    @sha_list    = sha_list
    @data_file   = File.open('data', 'a+')
  end

  # TODO add exception in case of nil being returned from host

  def parse_response
    p 'parsing response...'

    # After handshake message is sent and the sha digest interpreted, the next round of transmission comes in
    # if the id is 5, then a bitfield process occurs

    len = begin
            Timeout::timeout(5) { socket.read(4).unpack("N")[0] }
          rescue Timeout::Error
            false
          end

    id  = socket.read(1).ord if len

    if id == 5
      process_bitfield_msg(len)
    else
      puts "#{id} #{len}"
      process_have_msg(data)
      send_unchoke
      request_packet if interested?
    end


  end

  def send_unchoke
    socket.write("\x00\x00\x00\x01\x02")
  end

  def interested?
    socket.read(5) == "\x00\x00\x00\x01\x01"
  end

  def process_bitfield_msg(len)
    p 'processing bitfield'
    bitfield      = socket.read(len - 1)
    @packet_index = bitfield.unpack("B*").join.split('').map { |e| e == '1' } # => array of 1's and 0's - 1 being piece is in poss, 0 not

    # if there's data past the bitfield, it is likely the have msg's coming through in a bulk size.
    # so the first 9 bytes are measured

    data =  begin
              Timeout::timeout(5) { socket.read(9) } # <= this sometimes creates an EOF break. Check the IO library for workarounds
            rescue Timeout::Error
              false
            end

    # if the bytes indicate a have msg, then it loops recursively through until there are no more bytes to retrieve
    # otherwise, the interested msg is sent to the host. Once the host responds positively, the initial request for files is sentt

    if data
      process_have_msg(data)
    else
      show_interest
    end
  end

  def process_have_msg(data) # <= possible nil errors will occur with have_data
    @packet_index[data.unpack("C*").last] = true
    p data
    data = msg(9)
    if data
      process_have_msg(data)
    else
      show_interest
    end
  end

  def msg(n)
    begin
      Timeout::timeout(5) { socket.read(n) }
    rescue Timeout::Error
      false
    end
  end

  def show_interest
    socket.write("\x00\x00\x00\x01\x02")

    if interested?
      request_packet
    else
      raise 'not interested in me, apparently. What a jerkface.'
    end
  end

  def request_packet(index=0)
    index += 1 if !@packet_index[index]
    until index == (@packet_index.count(true) - 1)
      piece = ''
      0.upto(block_count - 1) do |t|
        req_msg = pack_request(13) + "\x06" + pack_request(index) + pack_request(t * BLOCK) + pack_request(BLOCK)
        socket.write(req_msg)
        socket.read(13)
        piece << socket.read(BLOCK)
        puts "num: #{t} of index: #{index}  block downloaded..."
      end
      distribute_to_file(piece, index)
      index += 1
    end
    peer_hash.each do |file|
      create_file(file)
    end
    @file_data.close
  end

  def distribute_to_file(piece, index)
    @file_data << data if hash_verified?(piece, index)
  end

  def hash_verified?(piece, index)
    Digest::SHA1.digest(piece) == sha_list[index]
  end

  def pack_request(i)
    [i].pack("I>")
  end
end


# live_streams.map! do |stream|
#   Thread.new {
#     begin
#       stream.write("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{peer_hash[:info_hash]}#{peer_hash[:peer_id]}")
#       peer = PeerList.new(stream)
#
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
#
# end

# .map { |s| Thread.new { s } }.each do |t|
#             a = PeerList.new(t)
