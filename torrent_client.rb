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
    stream['info']['piece length']
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

  def file_data
    { total: total, file_sizes: file_sizes, piece_size: piece_length }
  end

  def file_sizes
    stream['info']['files'].map { |file| file['length'].to_i }
  end

  def total
    file_sizes.inject { |x, y| x + y }
  end

  def create_files
    peer_hash[:pieces].each { |file| File.open("#{file[:filename]}", 'w') }
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

    ip_list.map! { |e| { :ip => e[0..3].join('.'), :port => (e[4] * 256) + e[5] } }

    # ip key contains the ip address, port the port number.

    return ip_list, peer_hash
  end
end
