#!/usr/bin/ruby

# This script is a erb2haml conversion wrapper.
# Run 'ruby convertERB2HAML.rb -h' to learn more.
# There's a kind of procedural programming feeling to it, but it works nonetheless :)

require 'fileutils'
require 'pathname'
require 'optparse'

class Pathname
  # Ever wanted to have a recursive each_entry? Here it is!
  # It takes a block, <Pathname> file yielded as block argument. Use case:
  #
  #   # get rid of any file but *.haml within app/**/*
  #   Pathname.new("app").visit do |f|
  #     FileUtils.rm_f(f) unless f.to_s =~ /haml$/
  #     logger.debug "removing #{f}"
  #   end
  #
  # TODO: add an option to allow including or avoiding directories
  def visit
    # let's memoize those, object instanciation's not so cheap these days
    @@avoided_pathnames_for_visit ||= [Pathname.new("."), Pathname.new("..")]

    if self.realpath.directory?
      self.entries.each do |entry|
        next if @@avoided_pathnames_for_visit.include? entry
        current_entry = Pathname.new(Pathname(self.to_s) + entry)
        if current_entry.directory?
          current_entry.visit { |sub_entry| yield sub_entry }
        else
          yield current_entry
        end
      end
    else
      yield self
    end
  end
end

class ERB2HAML
  # optparse
  @@options = {}
  @@options[:verbose] = false

  # useful flags and vars
  @@list = {:files => [], :directories => []}
  @@backup_location = nil
  @@external_backup_initialized = false

  def self.optparsing
    # optparsing
    optparse = OptionParser.new do |opts|
      opts.banner = "Usage: ruby convertERB2HAML.rb [options] file or directory/ies"
      opts.separator ""
      opts.separator "Options:"

      @@options[:force] = false
      opts.on('-f', '--force', 'Force conversion (destroy any previously existing and matching *.haml file).') do
        @@options[:force] = true
      end

      @@options[:clean] = false
      opts.on('-c', '--clean', 'Perform no backup of data, that is converts in place.') do
        @@options[:clean] = true
      end

      @@options[:preserve] = false
      opts.on('-p', '--preserve', 'Do not delete source files after conversion.') do
        @@options[:preserve] = true
      end

      @@options[:inner] = false
      opts.on('-i', '--inner', 'Backup converted files in their very own directories.') do
        @@options[:inner] = true
      end

      @@options[:backup_location] = false
      backup_location_desc = %{Backup defaults to directory.bak, but you can specify another location. Be aware it will be erased w/o any warning!}
      opts.on('--location [directory]', String, backup_location_desc) do |backup_location|
        @@options[:backup_location] = true
        @@backup_location = Pathname.new(backup_location) # solid, real directory pathname :) 
      end

      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        @@options[:verbose] = v
      end

      opts.on("-h", "--help", "You're reading this.") do
        msg = %{
This script converts .erb files into .haml versions, using the binary script
html2haml. It can handle a single file, one directory, or multiple directories
at a time. Directories are searched for recursively. Several options are
available so as to perform efficient backup and cleaning up.

Be advise that html2haml is no perfect script. You may need to edit converted
files by hand to correct indentation, for example.

}
        puts msg
        puts opts
        exit
      end
    end

    begin
      optparse.parse!
      check_for_arg_collisions
      handle_backup
    rescue OptionParser::InvalidOption => msg
      puts msg
      exit
    end
   
 
 
    if ARGV.include? "."
      # well, let's just KISS
      puts "Error: won't process . as a whole. Please specify your target directories."
      exit
    end

    # sort them out by type
    # not really useful, but you never know
    ARGV.each do |path|
      path = Pathname.new(path)

      if not path.exist?
        puts "Error: #{path} does not exist."
        exit
      end

      if path.directory?
        @@list[:directories] << path
      else
        @@list[:files] << path
      end
    end
  end
  
  def self.check_for_arg_collisions
    if ARGV.length == 0
      puts "Error: No data provided. You may read the help (--help) to learn more about this script."
      exit
    end 

    if @@options[:inner] and @@options[:backup_location]
      puts "Error: Cannot use a specific backup location and the 'inner' option at the same time."
      exit
    end

    if @@options[:clean] and (@@options[:preserve] || @@options[:backup_location] || @@options[:inner])
      puts "Error: Cannot use both 'clean' and any backup options at the same time."
      exit
    end
  end

  def self.handle_backup
   if @@options[:preserve] && @@options[:backup_location]
     puts "Warning: 'preserve' option's on, ignoring external backup location"
   end
   
   unless @@options[:preserve]
    if @@backup_location.exist?
        shall_purge?(@@backup_location)
      else
        @@backup_location.mkpath
      end
      @@backup_location = @@backup_location.realpath
   end
  end

  def self.get_backup_location_for(path)
    # case 1: backup within the same location
    backup_location = if @@options[:inner]
      # actually backup_location is a filename in this case
      Pathname.new(path.to_s + ".bak")
    else
      relative = path.relative_path_from(Pathname.getwd)

      # case 2: backup in a specific location
      if @@options[:backup_location]
        backdir = Pathname.new(@@backup_location.to_s + "/" + relative.dirname.to_s)
        backdir.mkpath # behaves like mkdir -p, that is silently create nested directories
                       # and does not complain about already existing ones
        backdir
      # case 3: backup in *.bak directories in the working directory
      else
        pathy = []
        # say relative is #<Pathname:app/views/inner/folder/test1.html.erb>
        relative.ascend { |v| pathy << v.basename }
        # then...
        relative_base = pathy.pop # #<Pathname:app>
        pathy.reverse!.pop # ascending (path) order, and get rid of the filename btw
        relative_subbase = pathy.join("/") # "views/inner/folder" (as a string, not a Pathname object)

        backdir = Pathname.new(Pathname.getwd.to_s + "/" + relative_base.to_s + ".bak" + "/" + relative_subbase)
        shall_purge?(backdir)
        backdir
      end
    end

    return backup_location
  end

  def self.shall_purge?(path, source = nil)
    if source
      return if path.dirname == source.dirname
    elsif path.exist? && !@@external_backup_initialized
      answer = nil
      while !["y", "yes", "n", "no"].include? answer
        puts "Backup directory '#{path}' already exists. Delete? [y/n]"
        answer = STDIN.gets.chomp
      end

      if ["y", "yes"].include? answer
        path.rmtree
        path.mkpath
      end
    else
      path.mkpath
      @@external_backup_initialized = true
    end
  end

  def self.backup_file(path)
    backdir = get_backup_location_for(path)
    puts if @@options[:verbose]
    FileUtils.cp_r(path, backdir, :verbose => @@options[:verbose])
  end

  def self.convert_file(path)
    match = Pathname.new(path.to_s.gsub(/\.erb$/, '.haml'))

    if !match.exist? or @@options[:force] 
      puts "> converting #{path} to #{match.basename}" if @@options[:verbose]

      `html2haml -rx #{path} #{match}`

      unless @@options[:preserve]
        puts "> deleting #{path}" if @@options[:verbose]
        FileUtils.rm_f path if path.exist?
      end
    else
      puts "#{match} already exists. Set option -f to force conversion."
    end
  end

  def self.convert!
    self.optparsing

    [@@list[:directories], @@list[:files]].flatten.each do |path|
      path = Pathname.new(path).realpath 
      @@external_backup_initialized = false if @@external_backup_initialized

      if @@options[:verbose]
        puts
        puts path
      end

      if path == @@backup_location
        puts "Skipping backup location" if @@options[:verbose]
        next
      end

      # I used to do:
      #Dir["#{@@path.realpath.to_s}/**/*.erb"].each do |file|
      # but now I can recursively visit paths :)
      path.visit do |f|
        f = f.realpath
        if f.to_s =~ /erb$/
          backup_file(f) unless @@options[:clean] || @@options[:preserve]
          convert_file(f)
        end
      end
    end
  end
end

ERB2HAML.convert!

