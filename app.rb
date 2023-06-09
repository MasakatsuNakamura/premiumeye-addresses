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

    x = open('tmp/excludes.csv', 'w')

    all = {}
    part = {}
    zipcodes = {}
    CSV.foreach("tmp/#{entry.name}", encoding: "CP932:UTF-8", headers: false) do |row|
      code = row[0]
      zipcode = row[2]
      prefecture = row[6]
      city = row[7]
      town = row[8]
      city_kana = row[4]
      town_kana = row[5]

      town.gsub!(/（[^）]*）/, '')
      town_kana.gsub!(/\([^)]*\)/, '')

      town_excludes = (['\A以下に掲載がない場合\z'] + ENV['TOWN_EXCLUDES'].split(',')).join('|')
      if town.match?(Regexp.new(town_excludes))
        x.write("#{[prefecture, city, city_kana, town, town_kana].join(',')}\n")
        next
      end

      all[prefecture] = [] unless all.key?(prefecture)
      all[prefecture].append([city, code]) unless all[prefecture].select { |r| r[0] == city }.any?

      part[prefecture] = {} unless part.key?(prefecture)
      part[prefecture][city] = [] unless part[prefecture].key?(city)
      part[prefecture][city].append({ town: town, town_kana: town_kana }) unless part[prefecture][city].select { |r| r[:town] == town }.any?

      zipcodes[zipcode[0..2]] = {} unless zipcodes.key?(zipcode[0..2])
      zipcodes[zipcode[0..2]][zipcode] = [prefecture, city, town]
    end

    x.close

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
    Dir.mkdir("tmp/zipcode", 0777)
    zipcodes.each do |zipcode, address|
      open("tmp/zipcode/#{zipcode}.json", 'w') do |f|
        f.write(address.to_json)
      end
    end
  end
end
