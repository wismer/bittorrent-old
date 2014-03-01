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
binding.pry

# from the torrent file, the file list is generated and applied to the current
# directory by creating empty files.

# peer.create_files
#
#
live_streams = []

streams, peer_hash = peer.begin
first = streams[0..3]
second = streams[4..(streams.size-1)]
[first, second].each do |streams|
  streams.each do |stream|
    begin
      p 'connected!'
      socket = TCPSocket.new(stream[:ip], stream[:port])
      socket.write("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{peer_hash[:info_hash]}#{peer_hash[:peer_id]}")
      peer = PeerList.new(socket)
      binding.pry
      peer.parse_response
      # end
    rescue Errno::ECONNREFUSED => e
      p 'nah'
    rescue Timeout::Error
      p 'timeout'
    rescue Errno::EADDRNOTAVAIL
      p 'not avail'
    end
  end
end
