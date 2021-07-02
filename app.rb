require 'json'
require 'net/http'
require 'webrick'
require 'zip'
require 'csv'

res = Net::HTTP.get_response(URI.parse('https://www.post.japanpost.jp/zipcode/dl/kogaki/zip/ken_all.zip'))
f = open('tmp/ken_all.zip', 'wb')
f.write(res.body.to_s)
f.close

Zip::File.open('tmp/ken_all.zip') do |zip_file|
  zip_file.each do |entry|
    next if entry.name != 'KEN_ALL.CSV'

    f = open("tmp/#{entry.name}", 'wb')
    f.write(entry.get_input_stream.read)
    f.close

    all = {}
    part = {}
    CSV.foreach("tmp/#{entry.name}", encoding: "CP932:UTF-8", headers: false) do |row|
      prefecture = row[6]
      city = row[7]
      town = row[8]
      city_kana = row[4]
      town_kana = row[5]
      next if town == '以下に掲載がない場合' || town.match?(/（[^階）]*階）/)

      town.gsub!(/（[^）]*）/, '')
      town_kana.gsub!(/\([^)]*\)/, '')

      all[prefecture] = [] unless all.key?(prefecture)
      all[prefecture].append([city, city_kana]) unless all[prefecture].select { |r| r[0] == city }.any?

      part[prefecture] = {} unless part.key?(prefecture)
      part[prefecture][city] = [] unless part[prefecture].key?(city)
      part[prefecture][city].append({ town: town, town_kana: town_kana }) unless part[prefecture][city].select { |r| r[:town] == town }.any?
    end
    all.each_key do |prefecture|
      all[prefecture].sort! { |a, b| a[1] <=> b[1] }.map! { |r| r[0] }
    end
    part.each_key do |prefecture|
      part[prefecture].each_key do |city|
        part[prefecture][city].sort! { |a, b| a[:town_kana] <=> b[:town_kana] }
      end
    end
    f = open("tmp/ja.json", 'w')
    f.write(all.to_json)
    f.close

    Dir.mkdir("tmp/ja", 0777)
    part.each_key do |prefecture|
      Dir.mkdir("tmp/ja/#{prefecture}", 0777)
      part[prefecture].each_key do |city|
        f = open("tmp/ja/#{prefecture}/#{city}.json", 'w')
        f.write(part[prefecture][city].to_json)
        f.close
      end
    end
  end
end
