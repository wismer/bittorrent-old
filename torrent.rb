

class Peer
  # for non outside vars use the @ and remove them from
  BLOCK = 2**14

  def initialize(socket, file_data, piece_index, pieces={})
    @socket      = socket
    @block_count = pieces[:piece_size] / BLOCK
    @file_data   = file_data
    @piece_index = piece_index
    # close the File stream within the class
    @data_file   = File.open('data', 'a+')
  end

  def parse_response
    puts 'parsing response...'

    # After handshake message is sent and the sha digest interpreted, the next round of transmission comes in
    # if the id is 5, then a bitfield process occurs

    len = msg(4)
    id  = msg(1).ord if len

    if id == 5
      process_bitfield_msg(len.unpack("N")[0])
    else
      puts "#{id} #{len.unpack("N")[0]}"
      process_have_msg(data)
      send_unchoke
      request_packet if interested?
    end
  end

  def send_unchoke
    socket.write("\x00\x00\x00\x01\x02")
  end

  def interested?
    msg(5) == "\x00\x00\x00\x01\x01"
  end

  def process_bitfield_msg(len)
    puts 'processing bitfield...'
    bitfield      = msg(len - 1)
    binding.pry
    @packet_index = bitfield.unpack("B*").join.split('').map { |e| e == '1' } # => array of 1's and 0's - 1 being piece is in poss, 0 not

    # if there's data past the bitfield, it is likely the have msg's coming through in a bulk size.
    # so the first 9 bytes are measured

    data = msg(9)

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

  def message(n)
    begin
      socket.read_nonblock(n)
    rescue IO::EAGAINWaitReadable
      false
    end
  end

  def request_block(index=0)
  end

  # num.times <block> == n.upto(n-1)
  # or use a range.each
  def request_packet(index=0)
    index += 1 if !@packet_index[index]
    until index == (@packet_index.count(true) - 1)
      piece = ''
      0.upto(block_count - 1) do |t|
        req_msg = pack_request(13) + "\x06" + pack_request(index) + pack_request(t * BLOCK) + pack_request(BLOCK)
        socket.write(req_msg)

        msg(13)
        piece << socket.read(BLOCK)
        puts "num: #{t+1} of index: #{index}  block downloaded..."
      end
      distribute_to_file(piece, index)
      index += 1
    end
  end

  def keep_alive
    socket.write("\x00\x00\x00\x00")
  end

  # also use fileutils for this

  def extract_file_bytes(file)
    open_file = if file[:folder].empty?
                  File.open("#{file[:filename]}", "a")
                else
                  Dir.mkdir("#{file[:folder]}") if !Dir.exists?("#{file[:folder]}")
                  File.open("#{file[:folder]}/#{file[:filename]}", 'a')
                end

    open_file << @file_data.read(file.size)
    open_file.close
  end

  def distribute_to_file(piece, index)
    @data_file << data if hash_verified?(piece, index)
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
