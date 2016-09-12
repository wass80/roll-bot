# -*- coding: utf-8 -*-

require "slack"
require "cgi"
require "pp"
require "open3"
require "timeout"

BOT_NAME = "shell"
ICON_EMOJI = ":tsumugi:"
channelID = "C0D595XEG"
Slack.configure {|config| config.token = ENV["TOKEN"] }

p Slack.auth_test
client = Slack.realtime

$list = Slack.users_list["members"]

def id2user(id)
  ( $list.find{|n|n["id"] == id} || {"name" => id} )["name"]
end

def postTo(text, chan)
  text = if text.size > 200 then text[0..200] + "..." else text end
  Slack.chat_postMessage text: text, channel: chan, username:BOT_NAME, icon_emoji: ICON_EMOJI
end

def validMsg(data, chan)
  if data["channel"] == chan &&
     data['subtype'] != 'bot_message'
    yield id2user(data["user"]), data["text"], data
  end
end

client.on :hello do
  puts "Successfully connected!"
  postTo "restart", channelID
end

require_relative "roll.rb"
Thread.abort_on_exception=true

client.on :message do |data|
  validMsg(data, channelID) do |name, text, data|
    begin;Timeout.timeout(3){
      begin
        if m = text.match(/roll\s+(.+)/)
          r = m[1]
            postTo "#{r} => #{getRoll(r).roll}", channelID
        elsif m = text.match(/rol\s+(.+)/)
          r = m[1]
            postTo "#{r} => #{getRoll(r)}", channelID
        end
      rescue => e
        puts e
      end
    };rescue;puts "timeout";end
  end
end

client.start
