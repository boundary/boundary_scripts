require 'rubygems'
require 'json'
require 'net/https'
require 'trollop'
require 'pp'
require 'highline/import'

opts = Trollop::options do
  opt :orgid, "Your Boundary organization id, found on your account page: https://app.boundary.com/account", :type => :string
  opt :apikey, "Your Boundary api key, found on your account page: https://app.boundary.com/account", :type => :string
  opt :since, "How long ago is the cutoff for disconnected meters? format is \\d+[wdhms]", :type => :string, :default => "0s"
  opt :delete, "Shall I delete the selected list of meters? Will ask for confirmation", :type => :boolean, :default => false
  opt :force, "Do not ask for confirmation before deleting.", :type => :boolean, :default => false
  opt :verify_none, "Set verify_none for the https connection.", :type => :boolean, :default => false
end

@verify_mode = opts[:verify_none] ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER

Trollop::die :orgid, "must be supplied" if opts[:orgid].nil?
Trollop::die :apikey, "must be supplied" if opts[:apikey].nil?
Trollop::die :since, "must be in the \\d+[wdhms] format" if /\d+[wdhms]/ !~ opts[:since]

@ivals = {
  's' => 1,
  'm' => 60,
  'h' => 3600,
  'd' => 86400,
  'w' => 604800
}

#from https://gist.github.com/botimer/2891186
def yesno(prompt, default)
  a = ''
  s = default ? '[Y/n]' : '[y/N]'
  d = default ? 'y' : 'n'
  until %w[y n].include? a
    a = ask("#{prompt} #{s} ") { |q| q.limit = 1; q.case = :downcase }
    a = d if a.length == 0
  end
  a == 'y'
end

def get(orgid, apikey, path)
  uri = URI.parse("https://api.boundary.com/#{orgid}/#{path}")
  req = Net::HTTP::Get.new(uri.path)
  req.basic_auth(apikey,'')

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = @verify_mode
  res = http.start do |http|
    http.request(req)
  end

  case res
  when Net::HTTPSuccess then
    return JSON.parse(res.body)
  else
    puts "#{uri} returned status #{response.status}"
    puts "body: #{response.body}"
    exit
  end
end

def delete(orgid, apikey, path)
  uri = URI.parse("https://api.boundary.com/#{orgid}/#{path}")
  puts "deleting #{uri}"
  req = Net::HTTP::Delete.new(uri.path)
  req.basic_auth(apikey,'')
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  res = http.start do |http|
    http.request(req)
  end
  
  case res
  when Net::HTTPSuccess then
    true
  else
    puts "#{uri} returned status #{response.status}"
    puts "body: #{response.body}"
    exit
  end
end

def seconds_ago(string)
  /(\d+)([wdhms])/ =~ string
  num = $1.to_i
  ival = @ivals[$2]
  num * ival
end

meterlist = get(opts[:orgid], opts[:apikey], "meters")
meter_status = get(opts[:orgid], opts[:apikey], "query_state/meter_status")

meters = {}
meterlist.each do |meter|
  meters[meter["obs_domain_id"]] = meter
end

status_msgs = meter_status['insert'].map do |entry|
  status_msg = {}
  meter_status['schema'].zip(entry) do |field,value|
    status_msg[field] = value
  end
  status_msg
end

millis_ago = seconds_ago(opts[:since]) * 1000
since = Time.now.to_i * 1000 - millis_ago

disconnected_since = status_msgs.select do |msg|
  msg["connected"] == false && msg["epochMillis"] < since && !meters[msg["observationDomainId"].to_s].nil?
end

disconnected_since.each do |msg|
  m = meters[msg["observationDomainId"].to_s]
  next if m.nil?
  mId = m["id"]
  date = Time.at(msg['epochMillis'] / 1000)
  msg["id"] = mId
  puts "#{m['os_node_name']} - last seen #{date} - https://api.boundary.com/#{opts[:orgid]}/meters/#{mId}"
end

exit unless opts[:delete]

if !opts[:force]
  exit unless yesno("Are you sure you want to delete these meters?", false)
end

disconnected_since.each do |msg|
  delete(opts[:orgid], opts[:apikey], "meters/#{msg['id']}")
end