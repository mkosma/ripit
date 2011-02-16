#! /usr/bin/env ruby

##########################################################
# ripit.rb
#
# control Pioneer DRM-7000 DVD jukebox
#
##########################################################

require 'logger'
require 'trollop'
require 'open4'

##########################################################
# PARAMETERS & ERROR CHECKING
##########################################################

CAROUSEL_DEVICE='/dev/sg8'
MAX_SLOTS=350
FIRST_ERR_SLOT=701 # need to check that this works
DRIVES=['/dev/sr1', '/dev/sr2']
RIPDIR='/rip'

def valid_slot?(s)
  s.is_a?(Integer) && s >= 1 && s <= MAX_SLOTS
end

def valid_drive?(d)
  d.is_a?(Integer) && d >=0 && d < DRIVES.length
end

##########################################################
# COMMAND LINE PARSING
##########################################################
COMMANDS = %w(load unload rip info title)
opts = Trollop::options do
  version "ripit.rb v1.0 (c) 2011 Fandor.com / Our Film Festival, Inc."
  banner <<-EOS

ripit.rb controls Fandor's Pioneer DRM-7000 DVD jukebox.

Usage:
    ripit [action] [options]

where [action] is one of
  load    load from slot into drive
  unload  unload from drive into slot
  rip     rip disc in drive
  info    show info on disc in drive
  title   show title of disc in drive

and [options] include:
EOS

  opt :drive, "Drive number (0-#{DRIVES.length-1})", :type => :int
  opt :slot, "Slot number (1-#{MAX_SLOTS})", :type => :int
  opt :dry_run, "Display commands without doing anything", :short => "-n"
  opt :debug, "Display debugging information to console", :short => "-!"
end

cmd = ARGV.shift

# validate options
Trollop::die "Unknown command #{cmd}" unless COMMANDS.include?(cmd)
Trollop::die :drive, "must be a valid drive number" unless valid_drive?(opts[:drive])
if %w(rip info title).include? cmd
  Trollop::die :slot, "should not be specified for a #{cmd} command" unless opts[:slot].nil?
else
  Trollop::die :slot, "must be a valid slot number" unless valid_slot?(opts[:slot])
end

$dry_run = opts[:dry_run]
$debug = opts[:debug]

############################################################
# LOGGER
############################################################

$log = $debug ? Logger.new(STDOUT) : Logger.new("#{RIPDIR}/ripit.log", 'daily')
$log.level = Logger::INFO


############################################################
# DEVICE INFO
############################################################

# return the cassette number for a given slot
def cassette_num(slot_num)
  raise "Invalid slot number" unless valid_slot?(slot_num)
  slot_num / 50
end

def output_slot(slot_num)
  raise "Invalid slot number" unless valid_slot?(slot_num)
  slot_num+MAX_SLOTS
end

############################################################
# DEVICE CONTROL
############################################################

def disc_title(drive_num)
  raise "Invalid drive number" unless valid_drive?(drive_num)

  title_cmd = "df | grep #{DRIVES[drive_num]}"
  puts title_cmd if $dry_run
  $log.info title_cmd

  unless $dry_run
    pid, stdin, stdout, stderr = Open4::popen4(title_cmd)
    ignored, status = Process::waitpid2(pid)

    # TODO: add logic to deal with return code
    $log.info "status:\t#{status}"
    $log.info "stderr:#{stderr.readlines.to_s}"

    title=stdout.readlines.to_s
    $log.info "stdout:\t#{title}"

    title = title.match(/media\/(.*)$/) if title
    title = title[1] if title
    $log.info "title:\t#{title}"
    return title

    # add error checking to return nil on error or false on disc not in drive
  end
end

def disc_info(drive_num)
  raise "Invalid drive number" unless valid_drive?(drive_num)

  info_cmd = "dvdbackup --info --input=#{DRIVES[drive_num]}"
  puts info_cmd if $dry_run
  $log.info info_cmd

  unless $dry_run
    pid, stdin, stdout, stderr = Open4::popen4(info_cmd)
    ignored, status = Process::waitpid2(pid)

    # TODO: add logic to deal with return code
    $log.info "status:\t#{status}"
    $log.info "stderr:#{stderr.readlines.to_s}"

    info=stdout.readlines.to_s
    $log.info "stdout:#{info}"
    return info
  end
end


def load_disc(drive_num, slot_num)
  raise "Invalid drive number" unless valid_drive?(drive_num)
  raise "Invalid slot number" unless valid_slot?(slot_num)

  load_cmd = "mtx -f #{CAROUSEL_DEVICE} load #{slot_num} #{drive_num}"
  puts load_cmd if $dry_run
  $log.info load_cmd

  unless $dry_run
    pid, stdin, stdout, stderr = Open4::popen4(load_cmd)
    ignored, status = Process::waitpid2(pid)

    case status
      # success
      when 0
        $log.info "load successful."
        return true
      else
        # status = 256 on failure
        errmsg = stderr.gets
        $log.warn "stdout:\t#{stdout.readlines.to_s}"
        $log.warn "status:\t#{status}"
        $log.warn "stderr:\t#{errmsg}"
        $log.warn "No disc to load from slot #{slot_num}." if errmsg =~ /Empty/
        $log.error "Cannot load into full drive #{drive_num}." if errmsg =~ /Full/
        return nil
    end
  end
end

def unload_disc(drive_num, slot_num)
  raise "Invalid drive number" unless valid_drive?(drive_num)
  raise "Invalid slot number" unless valid_slot?(slot_num)

  unload_cmd = "mtx -f #{CAROUSEL_DEVICE} unload #{slot_num} #{drive_num}"
  puts unload_cmd if $dry_run
  $log.info unload_cmd

  unless $dry_run
    pid, stdin, stdout, stderr = Open4::popen4(unload_cmd)
    ignored, status = Process::waitpid2(pid)

    case status
      # success
      when 0
        $log.info "unload successful."
        return true
      else
        # status = 256 on failure
        errmsg = stderr.gets
        $log.warn "stdout:#{stdout.readlines.to_s}"
        $log.warn "status:\t#{status}"
        $log.warn "stderr:\t#{errmsg}"
        $log.warn "No disc to unload from drive #{drive_num}." if errmsg =~ /Empty/
        $log.error "Cannot unload drive #{drive_num} into full slot #{slot_num}." if errmsg =~ /Full/
        return nil
    end
  end
end

# should I ever do this? takes 20 min. but may save headaches.
def slot_status()
  # not yet implemented  
end

def rip_disc(drive_num, use_generic_title=false)
  raise "Invalid drive number" unless valid_drive?(drive_num)

  rip_cmd = "dvdbackup --mirror --input=#{DRIVES[drive_num]} --output=#{RIPDIR}"
  
  # if use_generic_title is true, we need to create a unique title
  ripcmd += '--name="' + "generic_rip #{Time.now}" + '"' if use_generic_title

  puts rip_cmd if $dry_run
  $log.info rip_cmd

  unless $dry_run
    pid, stdin, stdout, stderr = Open4::popen4(rip_cmd)
    ignored, status = Process::waitpid2(pid)

    case status
      # success
      when 0
        $log.info "rip successful."
        return true
      # status 2 = occurs when disc title is blank / generic
      when 2 && !use_generic_title
        # call recursively if it has a generic name
        $log.info "title has generic name; retrying"
        return rip_disc(drive_num, true)
      else
        # status -1 = failure
        # status  1 = usage error (should never occur)
        # status  2 = title name error (should never occur if use_generic_title is true)
        $log.error "ripping error!"
        $log.error "status:\t#{status}"
        $log.error "stdout:#{stdout.readlines.to_s}"
        $log.error "stderr:#{stderr.readlines.to_s}"
        return nil
    end
  end
end

##########################################################
# RIPPING OPERATIONS
##########################################################

def log_disc_info(drive_num, error=false)
  title=disc_title(drive_num)
  info=disc_info(drive_num)
  File.open("#{RIPDIR}/#{title}.log", 'w') {|f| f.puts info}
  File.open("#{RIPDIR}/error.log", "w") { |f| f.puts error } if error
end

def process_rip(slot)
  # use drive 0 for even, drive 1 for odd source slots
  drive = slot % 2
  $log.info("Ripping slot #{slot} using drive #{drive}...")
  
  # load disc from slot
  l=load_disc(drive, slot) 
  # if no disc (false) or a failure (nil), return
  return l unless l
  
  # wait for disc to mount
  while disc_title(drive) == false
    sleep 10
  end

  # rip disc
  r = rip_disc(drive) 
  # log the disc info and set output slot to the "success" bank on success, original slot on error
  out_slot = r ? output_slot(slot) : slot

  log_disc_info(drive, r)
  u = unload_disc(drive, out_slot)
  # check for error, if slot is full return to overflow bank?
  while !u 
    # handle error on unloading disc
    err_slot = FIRST_ERR_SLOT unless err_slot
    $log.warn("Attempting alternate unload.")
    u = unload_disc(drive, err_slot)
  end

  return r
end

# run two ripping processes in parallel
def rip_all_discs()
  results = []
  start_time = Time.now()

  # fork to rip odd-numbered 
  pid = fork {
    (1..MAX_SLOTS).step(2) { |o| results[o]=process_rip(o) }
  }   
  # rip even-numbered
  (2..MAX_SLOTS).step(2) { |e| results[e]=process_rip(e)}

  # wait for things to finish
  Process.waitpid(pid)

  # generate summary report based on results array
  
  # create an output file to log all discs
  success = 0
  failure = 0
  empty = 0
  results.each do |r|
    case r
      when true
        success += 1
      when false
        empty += 1
      when nil
        failure += 1  
    end 
  end

  File.open("rip_all.log", 'w') do |f|
    f.puts "rip_all operation completed:"
    f.puts "  Successful rips: #{success}"
    f.puts "  Empty slots:     #{empty}"
    f.puts "  Failed rips:     #{failure}"
    f.puts "Elapsed time: #{(Time.now - start_time).round} seconds"
  end
end


##########################################################
# MAIN BODY
##########################################################

# record the command & start time in the log
$log.info ARGV 

# process the command
case cmd
  when "load"    then load_disc(opts[:drive], opts[:slot])
  when "unload"  then unload_disc(opts[:drive], opts[:slot])
  when "rip"     then rip_disc(opts[:drive])
  when "info"    then puts disc_info(opts[:drive])
  when "title"   then puts disc_title(opts[:drive])
  when "rip_all" then rip_all_discs()
end
