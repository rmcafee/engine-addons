require 'active_record'  
require 'yaml'
require File.dirname(__FILE__) + '/../lib/engine_addons'
require 'ruby-debug'

namespace :engine_addons do  
  desc "Migrate engine databases. Target engine with ENGINE='underscored_name' and VERSION=x"  
  task :migrate => :environment do
    ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
    ActiveRecord::EngineMigrator.migrate(Rails.root.to_s + "/vendor/plugins/#{ENV["ENGINE"]}/db/migrate", ENV["ENGINE"], ENV["VERSION"] ? ENV["VERSION"].to_i : nil )  
  end  

  desc "Migrate all engine databases."  
  task :migrate_all => :environment do
    directories = Dir.entries(Rails.root.to_s + "/vendor/plugins").delete_if { |x| x =~ Regexp.new('^.*\.$') || x =~ Regexp.new('^.*\.svn$') || x =~ Regexp.new('^.*\.DS_Store$')} 
    directories.each do |engine|
      engine_path = Rails.root.to_s + "/vendor/plugins/#{engine}/db/migrate"
      ActiveRecord::EngineMigrator.migrate(engine_path, engine, ENV["VERSION"] ? ENV["VERSION"].to_i : nil )
    end
  end
  
  task :environment do
    ActiveRecord::Base.establish_connection(YAML::load(File.open(RAILS_ROOT + '/config/database.yml'))[RAILS_ENV])  
    ActiveRecord::Base.logger = Logger.new(File.open('database.log', 'a'))  
  end
end