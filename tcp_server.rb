require 'socket'
require 'digest/sha1'
require 'bencode'
require 'net/http'
require 'eventmachine'
class TorrentClient
  attr_reader :stream, :peer_id, :new_stash, :get_peers
  def initialize(stream)
    @stream  = stream
    @peer_id = '-MATT16548651231825-'
  end

  def show
    uri       = URI(stream['announce']) 
    uri.query = URI.encode_www_form(get_peers)
    data      = BEncode.load(Net::HTTP.get(uri))
    peer_list(data['peers'].bytes)
  end

  def piece_length
    stream['info']['piece length'].to_s
  end

  def get_peers
    { 
      :info_hash => sha,
      :peer_id   => peer_id,
      :left      => piece_length,
      :pieces    => stream['info']['files']
    }
  end

  def peer_list(peers)
    inc     = 0
    ip_list = []
    until inc > 21
      p sha
      ip = peers[inc..inc+=5]
      ip_list << ip if ip.size == 6
    end

    ip_list.each do |peer|
      list = PeerList.new(peer, peer_id, get_peers)
      list.connect
    end
  end

  def sha
    Digest::SHA1.digest(stream['info'].bencode)
  end
end

class PeerList
  attr_reader :peer_ip, :port, :handshake
  include Socket::Constants

  def initialize(peer, peer_id, data = {})
    @peer_ip   = peer[0..3].join('.')
    @port      = peer[4..5].inject { |x,y| (x * 256) + y }
    @handshake = "\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{data[:info_hash]}#{peer_id}"
  end

  # HANDSHAKE <pstrlen><pstr><reserved><info_hash><peer_id>

  def connect
    p handshake
    socket = Socket.new(AF_INET, SOCK_STREAM)
    socket.connect(Socket.pack_sockaddr_in(port, peer_ip))

    socket.send(handshake)
    res = socket.recv(1028)
    p res

  end
end

class Peer < PeerList
end


file   = File.read('sky.torrent')
stream = BEncode.load(file)
peer   = TorrentClient.new(stream)
peer.show

