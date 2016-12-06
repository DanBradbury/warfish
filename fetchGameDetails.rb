require 'mechanize'
require 'digest/md5'
require 'slack-ruby-client'
require 'aws-sdk'
require 'pg'
#require 'active_record'

HOST_PREFIX = 'http://warfish.net/war/play/'
GAME_ID = 77969345
GAME_DETAILS_LINK = "http://warfish.net/war/play/gamedetails?gid=#{GAME_ID}"
GAME_MAP_LINK = "http://warfish.net/war/play/game?gid=#{GAME_ID}"

def perform(password, key)
  testvar = Digest::MD5.hexdigest(password)
  return Digest::MD5.hexdigest(testvar+key)
end

user_hash = {
	"kdam20161116211554" => "@kev",
	"sami20161005201423" => "@samir",
	"jay20161005201423" => "@jay",
	"keit20161005201423" => "@keithyc",
	"pete20161005201423" => "@petesta",
	"lbal20100115233217" => "@lbalceda",
}

Slack.configure do |config|
  config.token = ENV['SLACK_BOT_TOKEN']
end

client = Slack::Web::Client.new
client.auth_test

http = Mechanize.new
# BEGIN LOGIN CRAP
content = http.get('http://warfish.net/war/login').body
content_index = content.index(/document\.aform\.comment\.value = calcMD5\(testvar +/)
doc_cont = content[content_index..-1]
start = doc_cont.index("'")+1
ends = doc_cont.index("');")-1
random_key = doc_cont[start..ends]
secret_comment = perform(ENV['WARFISH_PASS'], random_key)
headers = {
  'Accept' =>'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
  'Content-Type' =>'application/x-www-form-urlencoded',
  'Host' =>'warfish.net',
  'Origin' => 'http://warfish.net',
  'Referer' => 'http://warfish.net/war/login'
}

data =  {'login' => ENV['WARFISH_USER'], 'password' => '', 'comment' => secret_comment, 'remotetime' => 420, 'submitbutton' => 'Login'}
login_attempt = http.post('http://warfish.net/war/login', data, headers)
raise 'Failed to Login' if login_attempt.body.include? 'If you have having trouble logging in'
# END LOGIN
#
game_details = http.get(GAME_DETAILS_LINK)
last_user = 'none'
current_player = ''

while true
  # fetch all the players names
  # XXX: two cases is pretty ridiculous
  # FIX: create a new account that will never join games and make it work that way always
  #rows = game_details.css('table')[16].children[1..-1] # magic number for gamaes logged in user is in
  rows = game_details.css('table')[14].children[1..-1] # magic number for games logged in user isnt in
  user_info = rows.map do |row|
    if row.children[2].text.include? '*'
      current_player = row.children[2].text
    end
    "#{row.children[2].text}|##{row.children[1].search('table tr td table td')[0].attributes['bgcolor'].value}"
  end
  # > user_info.first
  # > KillaKev(kdam...@...)|#6b8e23

  # intermediary page to be used to fetch the true user information about the people at the table
  # we will use this to fetch the profile id of the current "seat"
  # the link we are looking for will be on the page we build
  seat_paths = game_details.links.map(&:href).reject { |f| !f.include? '&seat' }.uniq
  pids = seat_paths.map do |path|
    url = "#{HOST_PREFIX}#{path}"
    seat_info = http.get(url)
   profile_link = seat_info.links.map(&:href).select{ |f| f.include? 'userprofile' }.uniq.first
    # [1] pry(main)> profile_link
    # => "../browse/userprofile?pid=lbal20100115233217"
    profile_link.match(/=.*/)[0][1..-1]
  end
  # > pids.first
  # > kdam20161116211554
  current_player_pid = pids.select { |f| current_player.include? f.match(/[a-zA-Z]*/)[0] }.first
  current_user = user_hash[current_player_pid]
  # Match the profile_ids we just found with the row data we collected earlier
  # this is thrown into an array for the purposes of saving conveniently
  # XXX: terrible implementation but "it just works"
  player_to_pid = pids.map do |pid|
    matching = user_info.select { |f| f.include? pid.match(/[a-zA-Z]*/)[0] }.first
    [ matching.match(/[a-zA-Z]*/)[0], pid, matching.split('|').last ]
  end

  players = {}
  player_to_pid.each do |k|
    players[k[1]] = { name: k[0], color: k[2] }
  end

  if current_user != last_user
    last_user = current_user
    msg = "TURN CHANGE: #{last_user} to play"
    client.chat_postMessage(channel: '#risk', text: msg, as_user: true, link_names: 1)
  end
end
