#!/usr/bin/env ruby

require 'rubygems'
require 'eventmachine'
require 'xmpp4r'
require 'xmpp4r/roster'
require 'nagios/status.rb'

class Bot
  include Jabber
  
  attr_accessor :channel, :botname, :password, :host, :roster, :client, :status_log, :nagios, :cmd_file
  
  def initialize args = Hash.new
    conf = args
    if args[:config]
      conf = YAML.load(File.open(args[:config]))
    end

    ##Assign all the values we respond to from the config    
    conf.each do |attr,value|
      if self.respond_to?("#{attr}=")
        self.send("#{attr}=", value)
      end
    end
    
    @nagios = Nagios::Status.new
  end
  
  ##Send an XMPP message
  def send_msg to, text, type = :normal, id = nil
    message = Message.new(to, text).set_type(type)
    message.id = id if id
    @client.send(message)
  end 

  def clientSetup
    begin
      @client = Client.new(JID.new(@botname))
      @client.connect(@host)
      @client.auth(@password)
      @roster = Roster::Helper.new(@client)
      pres = Presence.new
      pres.priority = 5
      pres.set_type(:available)
      pres.set_status('online')
      @client.send(pres)
      @roster.wait_for_roster
      
      @client.on_exception do |ex, stream, symb|
        puts "Exception #{ex.message}"
        puts ex.backtrace.join("\n")
        exit
      end
    rescue Exception => e
      puts "Exception: #{e.message}"
      puts e.backtrace.join("\n")
    end
    
    @client.add_message_callback {|msg|
      command,host,service = msg.body.split(/\n/)
      case command
        when 'roster' then 
          reply = @roster.items.keys.join("\n")
          send_msg(msg.from.to_s, "#{reply}", msg.type, msg.id)
        when 'host_downtime' then
          begin
            nagios.parsestatus(@status_log)
            start = Time.strftime('%s')
            dend = Time.strftime('%s').to_i + 3600
            action ="[#{start}] SCHEDULE_HOST_DOWNTIME;#{host};#{start};#{dend};0;0;3600;#{msg.from.to_s};'Scheduled over IM by #{msg.from.to_s}'"
            options = {:forhost => host, :action => action}
            foo = nagios.find_services(options)
            File.open(@cmd_file, 'w') do |f|
              f.puts foo
            end
            send_msg(msg.from.to_s, "Scheduled downtome for #{host} for 1 hour", msg.type, msg.id)        
          rescue Exception => e
            send_msg(msg.from.to_s, "#{e.message}", msg.type, msg.id)
          end
          
        when 'service_downtime' then
          begin
            nagios.parsestatus(@status_log)
            start = Time.strftime('%s')
            dend = Time.strftime('%s').to_i + 3600
            action = "[#{start}] SCHEDULE_HOST_SVC_DOWNTIME;#{host};#{service};#{start};#{dend};3600;#{msg.from.to_s};'Scheduled over IM by #{msg.from.to_s}"
            foo = nagios.find_services(:forhost => host, :action => action)
            File.open(@cmd_file, 'w') do |f|
              f.puts foo
            end
            send_msg(msg.from.to_s, "Scheduled downtime for #{service} on #{host} for 1 hour", msg.type, msg.id)
          rescue Exception => e
            send_msg(msg.from.to_s, "#{e.message}", msg.type, msg.id)
          end
      end
    }
  end
  
  def run
    EM.run do
      clientSetup
    end
  end
end

#b = Bot.new(:botname =>  'bot@jabber.thereisnoarizona.org',:host =>  'jabber.thereisnoarizona.org',:password =>  'm0rph3us', :status_log => '/var/cache/nagios3/status.dat', :cmd_file => '/var/lib/nagios3/rw/nagios.cmd')