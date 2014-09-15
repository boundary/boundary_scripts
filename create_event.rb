#!/usr/bin/ruby

###
### Copyright 2013, Boundary
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

require 'rubygems'
require 'json'
require 'excon'
require 'base64'

API_URL = "https://api.boundary.com"

def auth_encode(creds)
  auth = Base64.encode64(creds).strip
  auth.gsub("\n","")
end

def create_event(url, headers)
  event = {
    :title => "example",
    :message => "test",
    :tags => ["example", "test", "stuff"],
    :source => {
        :ref => "myhost",
        :type => "host"
    },
    :fingerprintFields => ["@title"]
  }

  event_json = event.to_json

  response = Excon.post(url, :headers => headers, :body => event_json)
  if response.status != 201
    raise "Error creating event: status=#{response.status}, body=#{response.body}"
  end
  response.headers["Location"]
end

def main
  if ARGV[0] == "-i" && ARGV[2] == "-a"
    auth = auth_encode("#{ARGV[3]}:")
    headers = {"Authorization" => "Basic #{auth}", "Content-Type" => "application/json"}

    location = create_event("#{API_URL}/#{ARGV[1]}/events", headers)
    puts "An event was created at #{location}"
  else
    puts "./create_event.rb -i ORGID -a APIKEY"
  end
end

main
