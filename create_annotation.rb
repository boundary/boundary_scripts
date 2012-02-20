###
### Copyright 2011, Boundary
###
### Licensed under the Apache License, Version 2.0 (the "License");
### you may not use this file except in compliance with the License.
### You may obtain a copy of the License at
###
###     http://www.apache.org/licenses/LICENSE-2.0
###
### Unless required by applicable law or agreed to in writing, software
### distributed under the License is distributed on an "AS IS" BASIS,
### WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
### See the License for the specific language governing permissions and
### limitations under the License.
###


#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'excon'
require 'base64'

API_URL = "https://api.boundary.com/"

def auth_encode(creds)
  auth = Base64.encode64(creds).strip
  auth.gsub("\n","")
end

def create_annotation(url, headers)
  annotation = {
      :type => "example",
      :subtype => "test",
      :loc => {
                :country  => "US",
                :city     => "San Francisco",
                :region   => "California",
                :lat      => 37.759965,
                :lon      => -122.390289
              },
      :start_time => 1320965015,
      :end_time => 1320966015,
      :tags => ["example", "test", "stuff"]
    }

  annotation_json = annotation.to_json

  response = Excon.post(url, :headers => headers, :body => annotation_json)
  response.headers["Location"]
end

def main
  if ARGV[0] == "-i" && ARGV[2] == "-a"
    auth = auth_encode("#{ARGV[3]}:")
    headers = {"Authorization" => "Basic #{auth}", "Content-Type" => "application/json"}

    annotation = create_annotation("#{API_URL}/#{ARGV[1]}/annotations", headers)
    puts "An annotation was created at #{annotation}"
  else
    puts "./create_annotation.rb -i ORGID -a APIKEY"
  end
end

main
