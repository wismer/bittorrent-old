

class PeerList
  attr_reader :socket, :packet_index, :pieces, :peer_hash
  attr_accessor :handshake

  BLOCK = 2**14

  def initialize(socket, handshake, pieces, peer_hash)
    @socket     = socket
    @handshake  = {
                    :pstrlen   => handshake.slice!(0).unpack("C")[0],
                    :pstr      => handshake.slice!(0..18),
                    :reserved  => handshake.slice!(0..7),
                    :info_hash => handshake.slice!(0..19),
                    :peer_id   => handshake.slice!(0..19)
                  }
    @pieces    = pieces
    @peer_hash = peer_hash
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
      request_packet(0, 0) if interested?
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
      request_packet(0, 0)
    else
      raise 'not interested in me, apparently. What a jerkface.'
    end
  end

  def request_packet(offset, index, off=0, size=0)
    # TODO
    # TODO
    # TODO 1.) Cut up the pieces into parts of strings of 20 length. Whenever a piece is finished, trigger a SHA1
    # TODO     HASH check on the downloaded data. If they match, continue on and ratchet up the array of hashes.
    # TODO 2.) A seperate class should be created for downloading of individual pieces so as to better keep track
    # TODO     of the download progression.
    # TODO
    # TODO


    # checks to see if the peer has the piece necessary. If it doesn't, moves on to the next spot and repeats.
    if !@packet_index[index]
      request_packet(offset, index+=1, size)
    else
      # response <len>13<id>6 index begin length (usually 2**14)
      # proper length, proper ID, maybe the right index, offset needs to be incremented, length is fine

      off += BLOCK

      len = pack_request(13) + "\x06" + pack_request(index) + pack_request(off) + pack_request(BLOCK)

      socket.write(len)
      response = socket.read(4)

      if response == "\x00\x00\x00\x00"
        socket.read(13)
      else
        socket.read(9)
      end
      #

      # until the entire piece has been downloaded, loop through the download request/receive_piece process
      # until piece.complete?
      #
      #  piece.download_packet
      #





      data    = socket.read(BLOCK)
      # approaching the end of the piece, data unfortunately becomes nil. Either I am exceeding the normal size
      # of a piece, or nil is being returned
      # binding.pry if data.nil?



      if data.nil?
        index += 1
        off    = 0
      else
        size += data.size
        insert_data(data) if hash_verified?(data)
      end
      puts "#{size} bytes downloaded --- remaining: #{pieces[:piece_size] - size}..."
      request_packet(offset, index, off, size) if index < @packet_index.size
    end
  end

  def hash_verified?(data)
    # Digest::SHA1.digest(data) == piece_hash
    true
  end

  def insert_data(data)
    File.open('data', 'a+') { |io| io << data }
  end

  def pack_request(i)
    [i].pack("I>")
  end
end

class Piece < PeerList
  attr_reader :files, :socket, :offset
  def initialize(socket, file_data)
    @socket = socket
    @init   = socket.read(8)
  end

  def download_data
    p "Downloading
    et: #{offset}"
    File.open('data', 'a') { |f| f << socket.read(offset) }
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
