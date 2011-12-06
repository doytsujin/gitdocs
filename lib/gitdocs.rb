require 'gitdocs/version'
require 'gitdocs/configuration'
require 'gitdocs/runner'
require 'gitdocs/server'
require 'gitdocs/cli'
require 'thread'
require 'rb-fsevent'
require 'growl'
require 'yajl'
require 'dante'
require 'socket'

module Gitdocs

  DEBUG = ENV['DEBUG']

  def self.run(config_root = nil, debug = DEBUG)
    loop do
      config = Configuration.new(config_root)
      yield config if block_given?
      puts "Gitdocs v#{VERSION}" if debug
      puts "Using configuration root: '#{config.config_root}'" if debug
      puts "Shares: #{config.shares.map(&:inspect).join(", ")}" if debug
      # Start the repo watchers
      runners = []
      threads = config.shares.map do |share|
        t = Thread.new(runners) { |r|
          runner = Runner.new(share)
          r << runner
          runner.run
        }
        t.abort_on_exception = true
        t
      end
      sleep 1
      unless defined?(pid) && pid
        # Start the web front-end
        pid = fork { Server.new(config, *runners).start }
        at_exit { Process.kill("KILL", pid) rescue nil }
      end
      puts "Watch threads: #{threads.map { |t| "Thread status: '#{t.status}', running: #{t.alive?}" }}" if debug
      puts "Joined #{threads.size} watch threads...running" if debug
      i = 0
      web_started = false
      begin
        TCPSocket.open('127.0.0.1', 8888).close
        web_started = true
      rescue Errno::ECONNREFUSED
        sleep 0.2
        i += 1
        retry if i <= 20
      end
      system("open http://localhost:8888/") if config.global.load_browser_on_startup && web_started
      threads.each(&:join)
      sleep(60)
    end
  end
end
