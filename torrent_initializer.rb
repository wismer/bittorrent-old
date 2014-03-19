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
  end

  def sha_list
    @peer.sha_list
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

  def sha_list
    @peer_info.sha_list
  end

  def file_index
    Array.new(@peer_info.sha_list.size) { false }
  end

  def connect_peers
    peers.each { |peer| make_connection(peer) { |p| @connections << Peer.new(@socket, file_index, peer, sha_list, file_data) } }
  end

  def make_connection(peer)
    puts "\nConnecting to IP: #{peer[:ip]} PORT: #{peer[:port]}"
    @socket = begin
                Timeout::timeout(2) { TCPSocket.new(peer[:ip], peer[:port]) }
              rescue Timeout::Error
                puts "Timed out."
                false
              rescue Errno::EADDRNOTAVAIL
                puts "Address not available."
                false
              rescue Errno::ECONNREFUSED
                puts "Connection refused."
                false
              rescue Errno::ECONNRESET
                puts "bastards."
                false
              end

    if @socket
      handshake_res = send_handshake
      if handshake_res
        print "....OK! \n"
        yield handshake_res
      else
        print 'no response... closing. '
        @socket.close
      end
    end
  end
  # make private


  private def send_handshake
    print "Sending handshake..."
    @socket.write("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{peer_hash[:info_hash]}#{peer_hash[:peer_id]}")
    msg(68)
  end

  def msg(n)
    begin
      Timeout::timeout(5) { @socket.read(n) }
    rescue Timeout::Error
      false
    rescue Errno::ECONNRESET
      false 
    end
  end

  def active_connections
    connections.select { |connection| connection.interested? }
  end

  def pick_piece
  end

  def start!
    # all the active connections that have gone through the entire process up to the requesting of packages
    # size  = file_index.size / inventory.size
    # start = 0
    @connections.each do |conn| 
      conn.parse_response
    #   conn.piece_index    = conn.piece_index.map.with_index { |x, i| i }[start..(start+=size)]
      # conn.request_packet
    end
    set_priorities
    @connections.each { |conn| conn.request_packet }
    
    threads = @connections.map { |x| Thread.new { x.download_queue } }
    threads.each { |x| x.join }
    @connections.each { |x| x.data_file.close }
  end

  def inventory
    @connections.map { |x| x.piece_index }
  end

  def map_priorities
    index = file_index.map.with_index do |piece, i|
              arr = []
              @connections.each_with_index { |x, y| arr << y if x.piece_index[i] }
              arr
            end
    @connections.each { |conn| conn.piece_index.map! { false } }
    return index
  end

  def set_priorities
    tally = Array.new(@connections.size) { 0 }
    map_priorities.each_with_index do |e, i|
      # e is the array of elements that show the corresponding index of @connections that point to the peer that has that piece.
      if e.size == 1
        tally[e[0]] += 1
        @connections[e[0]].piece_index[i] = true
      elsif e.size > 1
        min = tally.min
        ind = tally.find_index(min)
        tally[ind] += 1
        @connections[e[ind]].piece_index[i] = true
      else
        puts 'packet is missing'
      end
    end
  end

  def send(msg, peer, step)
    begin
      socket.write_nonblock(msg)
    rescue IO::EAGAINWaitWritable
      [msg, peer, step]
    end
  end

  def recv(msg)
    begin
      socket.recv_nonblock(msg)
    rescue IO::EAGAINWaitReadable
      false
    end
  end
end


# so IF interested, send the package request. If no response, send a keep-alive msg and move on to the next peer and repeat the process.
# bitfield still needs to be modified to accurately reflect the pieces that are still missing.

file    = 'sky.torrent'
stream  = BEncode.load_file(file)
peer    = TorrentInitializer.new(stream)
peer.connect_peers
peer.start!


# [15] pry(main)> main_array.map.with_index do |a,i|
# [15] pry(main)*   sub = []  
# [15] pry(main)*   [arr_one[i], arr_two[i], arr_three[i]].each_with_index { |x,y|   
# [15] pry(main)*     sub << y if x    
# [15] pry(main)*   }  
# [15] pry(main)*   sub
# [15] pry(main)* end 

# array.each_with_index do |x, i|
#   case x.size
#   when 1 
#     tally[x[0]] += 1
#     peers_array[x.join].piece_index[i] = true
#   when 2
#     ind = tally.find_lowest_with_index # => index
#     peers_array