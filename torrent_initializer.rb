require 'socket'
require 'digest/sha1'
require 'bencode'
require 'net/http'
require 'pry'
require 'fileutils'

require_relative 'torrent_client.rb'
require_relative 'torrent.rb'

class TorrentInitializer
  attr_reader :connections
  def initialize(stream)
    @connections = []
    @peer_info   = TorrentClient.new(stream)
    @files       = stream['info']['files'].map { |file| FileType.new(file).to_file }
    binding.pry
  end

  def peers
    @peer_info.peer_list
  end

  def peer_hash
    @peer_info.peer_hash
  end

  def file_data
    @peer_info.file_data
  end

  def file_index
    Array.new(@peer_info.sha_list.size) { false }
  end

  def connect_peers
    peers.each { |peer| make_connection(peer) { |p| @connections << Peer.new(@socket, file_data, file_index, peer_hash) } }
  end

  def make_connection(peer)
    puts "\nConnecting to IP: #{peer[:ip]} PORT: #{peer[:port]}"
    @socket = begin
                Timeout::timeout(5) { TCPSocket.new(peer[:ip], peer[:port]) }
              rescue Timeout::Error
                puts "Timed out."
                false
              rescue Errno::EADDRNOTAVAIL
                puts "Address not available."
                false
              rescue Errno::ECONNREFUSED
                puts "Connection refused."
                false
              end

    if @socket
      handshake_res = send_handshake
      if handshake_res
        print '....OK! '
        yield handshake_res
      end
    end
  end
  # make private


  private def send_handshake
    print 'Sending handshake...'
    @socket.write("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{peer_hash[:info_hash]}#{peer_hash[:peer_id]}")
    binding.pry
    msg(68)
  end

  def msg(n)
    begin
      Timeout::timeout(5) { @socket.read(n) }
    rescue Timeout::Error
      false
    end
  end

  def active_connections
    connections.select { |connection| connection.interested? }
  end
end


# so IF interested, send the package request. If no response, send a keep-alive msg and move on to the next peer and repeat the process.
# bitfield still needs to be modified to accurately reflect the pieces that are still missing.

file    = 'sky.torrent'
stream  = BEncode.load_file(file)
peer    = TorrentInitializer.new(stream)
binding.pry
peer.connect_peers
peer.connections.each { |conn| conn.parse_response }
connections = peer.active_connections

def connect!(conn)
  socket = conn.socket
  socket.read_nonblock(BLOCK)
end
connections.each do |conn|

end

# until step == connections.size


connections.each { |conn| conn.packet_index[i] = false }


# index is the starting point... So the file_index needs to be parceled out.








live_streams = []

# streams, peer_hash = peer.raw_peers
# sha_list           = peer.sha_list
binding.pry
streams.shuffle.each do |stream|
  begin
    pieces = peer.file_data
    socket =  begin
                Timeout::timeout(5) { TCPSocket.new(stream[:ip], stream[:port]) }
              rescue Timeout::Error
                false
              end

    if socket
      p 'Connected...'
      socket.write("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{peer_hash[:info_hash]}#{peer_hash[:peer_id]}")

      handshake = socket.read(68)

      if !handshake.nil?
        live_streams << PeerList.new(socket, pieces, peer_hash, sha_list)
        binding.pry

        peer_connect.parse_response
        files.each { |file| peer_connect.extract_file_bytes(file) }
        peer_connect.file_data.close
      end
    end
  rescue Errno::ECONNREFUSED => e
    p 'nah'
  rescue Errno::EADDRNOTAVAIL
    p 'not avail'
  end
end
