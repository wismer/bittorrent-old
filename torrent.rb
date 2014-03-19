

class Peer
  # for non outside vars use the @ and remove them from
  attr_reader :socket, :data_file
  attr_accessor :piece_index

  BLOCK = 2**14

  def initialize(socket, piece_index, peer, sha_list, file_data={})
    @peer        = peer
    @socket      = socket
    @block_count = file_data[:piece_size] / BLOCK
    @file_data   = file_data
    @piece_index = piece_index
    @data_file   = File.open('data', 'a+')
    @delayed     = []
    @sha_list    = sha_list
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
      data = @socket.read(8)
      # puts "#{id} #{len.unpack("N")[0]}"
      process_have_msg(data)
      send_unchoke
      # request_packet if interested?
    end
  end

  def send_unchoke
    @socket.write("\x00\x00\x00\x01\x02")
  end

  def interested?
    msg(5) == "\x00\x00\x00\x01\x01"
  end

  def unpack_bitfield(bitfield)
    bitfield.each_with_index do |bit, i|
      if i < @piece_index.size
        @piece_index[i] = bit == '1' ? true : false
      end
    end
  end

  def process_bitfield_msg(len)
    puts 'processing bitfield...'
    bitfield      = msg(len - 1).unpack("B*").join.split('')
    unpack_bitfield(bitfield)

    data = msg(9)

    if data
      process_have_msg(data)
    else
      show_interest
    end
  end

  def process_have_msg(data) # <= possible nil errors will occur with have_data
    @piece_index[data.unpack("C*").last] = true
    data = msg(9)
    if data
      process_have_msg(data)
    else
      binding.pry 
      show_interest
    end
  end

  def msg(n)
    begin
      Timeout::timeout(5) { @socket.read(n) }
    rescue Timeout::Error
      false
    end
  end

  def show_interest
    @socket.write("\x00\x00\x00\x01\x02")

    if interested?
      # request_packet
    else
      @socket.close
      # raise 'not interested in me, apparently. What a jerkface.'
    end
  end

  def message(n)
    begin
      @socket.read_nonblock(n)
    rescue IO::EAGAINWaitReadable
      false
    end
  end

  # num.times <block> == n.upto(n-1)
  # or use a range.each
  def request_packet
    @piece_index.each_with_index do |e, index|
      download_block(index) if e
    end
  end

  def download_block(index)
    arr = []
    0.upto(@block_count - 1) do |t|
      req_msg = pack_request(13) + "\x06" + pack_request(index) + pack_request(t * BLOCK) + pack_request(BLOCK)
      binding.pry
      arr << [req_msg, index]
    end
    @delayed << arr
  end

  def recv_msg(n, m)
    begin
      @socket.read(n)
    rescue IO::EAGAINWaitReadable
      p 'a packet did not go in!'
    end
  end

  def download_queue
    @track = 0
    @delayed.each_with_index do |chunk, i|
      piece = download_packets(chunk, i)
      @data_file << piece if hash_verified?(piece, chunk[0][1])
    end
  end

  def download_packets(chunk, num, data='')
    # empty string for use of collecting piece data
    # since the @delayed is now split into sub-arrays by index, process is passed downwards.
    puts "Downloading piece: #{chunk[0][1]} for IP: #{@peer[:ip]} PORT: #{@peer[:port]}"
    chunk.each_with_index do |group, i|
      msg, index = group
      send_msg(msg)
      res = recv_msg(13, group)
      # rarely the recv_msg comes back as nil. Need to prevent this and resusitate the connection
      if res.nil?
        @track += 1
      else
        data << recv_msg(BLOCK, group)   
      end
    end
    binding.pry if @track == 10    # data should contain an entire pieces worth of data (1MB)
    data
  end

  def send_msg(msg)
    begin
      @socket.write(msg)
    rescue IO::EAGAINWaitWritable
      keep_alive
      false
    end
  end

  def keep_alive
    @socket.write("\x00\x00\x00\x00")
  end

  # also use fileutils for this

  def extract_file_bytes(file)
    open_file << @file_data.read(file.size)
    open_file.close
  end

  def distribute_to_file(piece, index)
    @data_file << data if hash_verified?(piece, index)
  end

  def hash_verified?(piece, index)
    Digest::SHA1.digest(piece) == @sha_list[index]
  end

  def pack_request(i)
    [i].pack("I>")
  end
end

#     
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
