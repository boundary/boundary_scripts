#!/usr/bin/ruby

require "rubygems"
require "excon"
require "json"
require "base64"
require "fileutils"

API_HOST = "api.boundary.com"
EC2_INTERNAL = "http://169.254.169.254/latest/meta-data/"
TAGS = ["ami-id",
        "hostname",
        "instance-id",
        "instance-type",
        "kernel-id",
        "local-hostname",
        "local-ipv4",
        "mac",
        "placement/availability-zone",
        "public-hostname",
        "public-ipv4",
        "reservation-id",
        "security-groups"]

def auth_encode(creds)
  auth = Base64.encode64(creds).strip
  auth.gsub("\n","")
end

def create_meter(id, headers)
  hostname = Socket.gethostbyname(Socket.gethostname).first

  if  hostname == nil || hostname.include?("localhost")
    abort("Hostname set to localhost or nil, exiting.")
  end

  body = {:name => hostname}
  url = "https://#{API_HOST}/#{id}/meters"

  response = Excon.post(url, :headers => headers, :body => body.to_json)
  if response.headers["Location"]
    puts "Meter created at #{response.headers["Location"]}"
    response.headers["Location"]
  else
    abort("No location header received, error creating meter!")
  end
end

def ec2_tags(url, headers)
  begin
    if Excon.get(EC2_INTERNAL).status == 200
      puts "Auto generating ec2 tags for this meter ..."

      TAGS.each do |tag|
        response = Excon.get("#{EC2_INTERNAL}#{tag}")
        if response.status == 200
          Excon.put("#{url}/tags/#{response.body}", :headers => headers, :body => "")
        else
          # do nothing
        end
      end

      Excon.put("#{url}/tags/ec2", :headers => headers, :body => "")
    end
  rescue Exception => e
    # do nothing
  end
end

def download_file(url, headers, filename)
  puts "downloading #{filename.gsub(".pem", "")} for #{url}"

  pem = Excon.get("#{url}/#{filename}", :headers => headers)

  begin
    file = File.new("./#{filename}", "w")
    file.puts(pem.body)
  rescue Exception => e
    puts "something went wrong with writing #{filename}:"
    puts e
  ensure
    file.close
    FileUtils.chmod(0600, "./#{filename}")
  end
end

def main
  if ARGV[0] == "-i" && ARGV[2] == "-a"
    auth = auth_encode("#{ARGV[3]}:")
    headers = {"Authorization" => "Basic #{auth}", "Content-Type" => "application/json"}

    url = create_meter(ARGV[1], headers)
    ec2_tags(url, headers)
    download_file(url, headers, "cert.pem")
    download_file(url, headers, "key.pem")
  else
    puts "./provision_meter.rb -i APIID -a APIKEY"
  end
end

main
