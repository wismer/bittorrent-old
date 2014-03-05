class TorrentClient
  attr_reader :stream, :peer_id, :new_stash, :peer_hash, :uri

  def initialize(stream)
    @stream  = stream
    @peer_id = '-MATT16548651231825-'
    @uri     = URI(stream['announce'])
  end

  # url gets reformatted to include query parameters

  def raw_peers
    uri.query = URI.encode_www_form(peer_hash)
    data      = BEncode.load(Net::HTTP.get(uri))
    data['peers'].bytes
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

  def peer_list
    ip_list = []
    raw_peers.each_slice(6) { |e| ip_list << e if e.length == 6 }

    ip_list.map! { |e| { :ip => e[0..3].join('.'), :port => (e[4] * 256) + e[5] } }
  end

  def sha_list
    n, e = 0, 20
    list = []
    until stream['info']['pieces'].bytesize < e
      list << stream['info']['pieces'].byteslice(n...e)
      n += 20
      e += 20
    end
    list
  end
end

class FileType
  def initialize(type={})
    @path = type['path']
    @size = type['length']
  end

  def to_file
    FileUtils.mkdir_p(@path[0..(@path.size - 2)]) if @path.size > 1
    FileUtils.touch(File.join(@path))
  end
end
