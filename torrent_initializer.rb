require 'socket'
require 'digest/sha1'
require 'bencode'
require 'net/http'
require 'eventmachine'
require 'pry'

require_relative 'torrent_client.rb'
require_relative 'torrent.rb'

stream = BEncode.load_file('sky.torrent')
peer   = TorrentClient.new(stream)

# from the torrent file, the file list is generated and applied to the current
# directory by creating empty files.

live_streams = []

streams, peer_hash = peer.begin
sha_list           = peer.sha_list

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
        peer_connect = PeerList.new(socket, handshake, pieces, peer_hash, sha_list)
        peer_connect.parse_response
      end
    end
  rescue Errno::ECONNREFUSED => e
    p 'nah'
  rescue Errno::EADDRNOTAVAIL
    p 'not avail'
  end
end
