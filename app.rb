require 'bundler/setup'

require 'thumper'
require 'zlib'
require 'base64'
require 'mini_magick'
require 'aws-sdk'

TH = Thumper::Base.new(publish_to: 'amqp://localhost/avnsp',
                       consume_from: 'amqp://localhost/avnsp')
AWS.config(access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID"),
           secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY"))
TH.with_channel prefetch: 5 do |ch|
  ch.subscribe 'photo.upload', 'photo.upload' do |data|

    s3 = AWS::S3.new
    filename = data[:name]
    file = Base64.decode64(data[:file])
     
    image = MiniMagick::Image.read(file)
    image.quality 75

    objects = s3.buckets['avnsp'].objects

    ct = image.mime_type
    objects[data[:path]].write(:data => image.to_blob, :content_type => ct)

    thumb = image.dup
    thumb.resize '100'
    objects[data[:thumb_path]].write(:data => thumb.to_blob, :content_type => ct)

    puts "[INFO] Compressing: #{filename} saving #{(data[:size] - file_size)/1024} KB"
    ch.publish 'photo.uploaded', data
  end
end
puts "[INFO] AVNSP photo handler starting..."
sleep