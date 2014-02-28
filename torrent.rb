require 'socket'
require 'digest/sha1'
require 'bencode'
require 'net/http'
require 'eventmachine'
require 'pry'

class TorrentClient
  attr_reader :stream, :peer_id, :new_stash, :peer_hash, :uri

  def initialize(stream)
    @stream  = stream
    @peer_id = '-MATT16548651231825-'
    @uri     = URI(stream['announce'])
  end

  # url gets reformatted to include query parameters

  def begin
    uri.query = URI.encode_www_form(peer_hash)
    data      = BEncode.load(Net::HTTP.get(uri))
    peer_list(data['peers'].bytes)
  end

  def piece_length
    stream['info']['piece length'].to_s
  end

  def sha
    Digest::SHA1.digest(stream['info'].bencode)
  end

  # data stored as a hash in the order made necessary

  def peer_hash
    { 
      :info_hash => sha,
      :peer_id   => peer_id,
      :left      => piece_length,
      :pieces    => stream['info']['files']
    } 
  end

  # Using the peers key of the torrent file, the hex-encoded data gets reinterpreted as ips addresses.

  def peer_list(peers)
    inc     = 0
    ip_list = []
    while inc < peers.size 
      ip = peers[inc...inc+=6]

      if ip.size == 6
        ip_list << ip
      else
        raise 'too big'
      end
    end

    # ip key contains the ip address, port the port number. 

    return ip_list.map { |e| { :ip   => e[0..3].join('.'), :port => (e[4] * 256) + e[5] } }, peer_hash
  end

end

class PeerList
  attr_reader :socket, :packet_index, :handshake

  def initialize(socket)
    @socket    = socket
    @handshake = get_initial_response
  end

  def parse_response

    # After handshake message is sent and the sha digest interpreted, the next round of transmission comes in
    # if the id is 5, then a bitfield process occurs

    len = socket.read(4).unpack("N")[0]
    id  = socket.read(1).ord



    if id == 5
      process_bitfield_msg(len)
      bitfield      = socket.read(len - 1)
      @packet_index = bitfield.unpack("B*").join.split('').map { |e| e == '1' } # => array of 1's and 0's - 1 being piece is in poss, 0 not

      begin
        have_data = socket.readpartial(2**14) # <= this sometimes creates an EOF break. Check the IO library for workarounds
      rescue EOFError => e
        p e 
      end


      socket.write("\x00\x00\x00\x01\x02")
      if socket.read(5) == "\x00\x00\x00\x01\x01"
        initial_request(socket)
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

  def process_have_msg(have_data) # <= possible nil errors will occur with have_data
    until have_data.length < 9

      have_data.slice!(0..4)

      data = have_data.slice!(0..3)
      @packet_index[data.unpack("N")[0]] = true
    end
  end

  def get_initial_response
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

  def initial_request(offset=0)
    binding.pry
    # response <len>13<id>6 index begin length (usually 2**14)
    len = [13].pack("I>") + "\x06" + "\x00\x00\x00\x00\x00\x00\x00\x00" + [2**14].pack("I>")
    socket.write(len)

    offset = socket.read(5).unpack("N*").join.to_i - 9 # => (2**14) - 9

    # what's needed here is a record of the offset, 

    file_download = DownloadFile.new(socket, initial, files)
  end
end

class DownloadFile < PeerList
  attr_reader :files, :socket, :offset
  def initialize(socket, res, files)
    @socket = socket
    @offset = res.unpack("N*").join.to_i - 9
    @init   = socket.read(8)
    @files  = files
    @length = 0
  end

  def download_data
    p "Downloading Packet: #{offset}"
    File.open('data', 'a') { |f| f << socket.read(offset) }
  end

  def handshake_response(socket)
    
  end

  def length(seg)
    seg.unpack("n*")
  end
end


stream = BEncode.load_file('sky.torrent')
peer   = TorrentClient.new(stream)


live_streams = []

streams, peer_hash = peer.begin
first = streams[0..3]
second = streams[4..streams.size-1]
[first, second].each do |streams|
  streams.each do |stream|
    begin 
      Timeout::timeout(5) do 
        live_streams << TCPSocket.new(stream[:ip], stream[:port])
        binding.pry
        # p sock.write("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{peer_hash[:info_hash]}#{peer_hash[:peer_id]}")
      end
    rescue Errno::ECONNREFUSED => e
      p 'nah'
    rescue Timeout::Error
      p 'timeout'
    rescue Errno::EADDRNOTAVAIL
      p 'not avail'
    end
  end
end

live_streams.map! do |stream|
  Thread.new {
    begin 
      stream.write("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{peer_hash[:info_hash]}#{peer_hash[:peer_id]}") 
      stream.read(68) 
    rescue Errno::EPIPE => e
      p e
    rescue Errno::ECONNRESET => e
      p e
    end
  }
end
live_streams.each { |x| x.join }
binding.pry

# .map { |s| Thread.new { s } }.each do |t|  
#             a = PeerList.new(t)
