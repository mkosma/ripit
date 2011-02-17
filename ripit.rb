#! /usr/bin/env ruby

##########################################################
# ripit.rb
#
# control Pioneer DRM-7000 DVD jukebox
#
##########################################################

require 'trollop'
require 'open4'
# TODO: switch to color logging and tee to STDOUT
#require 'log4r-color'
#include Log4r
require 'logger'

# TODO: check for "not ready" status return by mtx - warn about front panel lockout


##########################################################
# PARAMETERS & ERROR CHECKING
##########################################################

CAROUSEL_DEVICE='/dev/sg8'

FIRST_INPUT_SLOT=1
LAST_INPUT_SLOT=350
FIRST_OUTPUT_SLOT=401
LAST_OUTPUT_SLOT=750
FIRST_ERR_SLOT=751
LAST_ERR_SLOT=770

SLOTS_PER_CASSETTE=50

DRIVES=['/dev/sr1', '/dev/sr2']

RIPDIR='/rip'

def valid_slot?(s, slot_type=:any)
  return unless s.is_a?(Integer)
  case slot_type
    when :input
      return s >= FIRST_INPUT_SLOT && s <= LAST_INPUT_SLOT
    when :output
      return s >= FIRST_OUTPUT_SLOT && s <= LAST_OUTPUT_SLOT
    when :error
      return valid_slot?(s, :input) || (s >= FIRST_ERR_SLOT && s <= LAST_ERR_SLOT)
    else # :any
      return valid_slot?(s, :input) || valid_slot?(s, :output) || valid_slot?(s, :error)
  end
end

def valid_drive?(d)
  d.is_a?(Integer) && d >=0 && d < DRIVES.length
end

##########################################################
# COMMAND LINE PARSING
##########################################################
COMMANDS = %w(load unload rip info title status test_all_cassettes rip_one rip_all)
opts = Trollop::options do
  version "ripit.rb v1.0 (c) 2011 Fandor.com / Our Film Festival, Inc."
  banner <<-EOS

ripit.rb controls Fandor's Pioneer DRM-7000 DVD jukebox.

Usage:
    ripit [action] [options]

where [action] is one of the following:

main actions:
  status  show status of all device slots
  rip_one run rip process on a single slot
  rip_all run rip process on all discs in robot

test actions:
  test_all_cassettes   test error state of all cassettes

controller actions:
  load    load from slot into specified drive
  unload  unload from drive into slot
  rip     rip disc in specified drive
  info    show info on disc in specified drive
  title   show title of disc in specified drive

and [options] include:
EOS

  opt :drive, "Drive number (0-#{DRIVES.length-1})", :type => :int
  opt :slot, "Slot number (#{FIRST_INPUT_SLOT}-#{LAST_ERR_SLOT})", :type => :int
  opt :dry_run, "Display commands without doing anything", :short => "-n"
  opt :debug, "Display debugging information to console", :short => "-!"
end

cmd = ARGV.shift

# validate options
Trollop::die "Unknown command #{cmd}" unless COMMANDS.include?(cmd)

# most commands should include a drive number
if %w(rip_all status test_all_cassettes rip_one).include? cmd
  Trollop::die :drive, "should not be specified for a #{cmd} command" unless opts[:drive].nil?
  if %w(rip_one).include? cmd
    Trollop::die :slot, "must be a valid slot number" unless valid_slot?(opts[:slot])
  else
    Trollop::die :slot, "should not be specified for a #{cmd} command" unless opts[:slot].nil?
  end
else
  Trollop::die :drive, "must be a valid drive number" unless valid_drive?(opts[:drive])
  # only some commands should include a slot number
  if %w(rip info title).include? cmd
    Trollop::die :slot, "should not be specified for a #{cmd} command" unless opts[:slot].nil?
  else
    Trollop::die :slot, "must be a valid slot number" unless valid_slot?(opts[:slot])
  end
end

$dry_run = opts[:dry_run]
$debug = opts[:debug]

############################################################
# LOGGER
############################################################

#Logger.global.level = ALL
#formatter = 


$log = $debug ? Logger.new(STDOUT) : Logger.new("#{RIPDIR}/ripit.log", 'daily')
$log.level = Logger::INFO


############################################################
# DEVICE INFO
############################################################

def output_slot(slot_num)
  raise "Invalid slot number" unless valid_slot?(slot_num, :input)
  (slot_num-FIRST_INPUT_SLOT)+FIRST_OUTPUT_SLOT
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

    case status
      # success
      when 0
        $log.info "Title read successful."
        title=stdout.readlines.to_s
        $log.info "stdout:\t#{title}"

        title = title.match(/media\/(.*)$/) if title
        title = title[1] if title
        $log.info "title:\t#{title}"
        return title
      when 256
        # status = 256 on empty drive / drive not ready
        $log.warn "No disc in drive #{drive_num}"
        return false
      else
        $log.error "Error reading disc title"
        return nil
    end
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
        errmsg = stderr.readlines.to_s
        case errmsg
          when /Empty/
            $log.warn "No disc to load from slot #{slot_num}."
            return false
          when /Full/
            $log.error "Cannot load into full drive #{drive_num}."
            return nil
          else
            $log.error "Cartridge or device not ready loading from slot #{slot_num}."
            return nil
        end
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
        errmsg = stderr.readlines.to_s
        case errmsg
          when /Empty/
            $log.warn "No disc to unload from drive #{drive_num}."
            return false
          when /Full/
            $log.error "Cannot unload drive #{drive_num} into full slot #{slot_num}."
            return nil
          else
            $log.error "Cartridge or device not ready unloading into slot #{slot_num}."
            return nil
        end
    end
  end
end

def device_status()
  status_cmd = "mtx -f #{CAROUSEL_DEVICE} status"
  puts status_cmd if $dry_run
  $log.info status_cmd

  unless $dry_run
    pid, stdin, stdout, stderr = Open4::popen4(status_cmd)
    ignored, status = Process::waitpid2(pid)

    $log.info "status:\t#{status}"
    $log.info "stderr:#{stderr.readlines.to_s}"

    dev_status=stdout.readlines.to_s
    $log.info "stdout:#{dev_status}"
    return dev_status
  end
end

def test_all_cassettes()
  (1..LAST_ERR_SLOT).step(SLOTS_PER_CASSETTE) do |s|
    begin
      # nil is the only real "failure" case
      if !load_disc(0, s).nil?
        unload_disc(0, s)
        puts "Slot #{s} - cassette tests okay."
      else
        puts "Slot #{s} - cassette missing or failed test."
      end
    rescue
      puts "Slot #{s} - error."
    end
  end
end

def rip_disc(drive_num, use_generic_title=false)
  raise "Invalid drive number" unless valid_drive?(drive_num)

  rip_cmd = "dvdbackup --mirror --input=#{DRIVES[drive_num]} --output=#{RIPDIR}"
  
  if use_generic_title
    # if use_generic_title is true, we need to create a unique "anonymous" title
    ripcmd += '--name="' + "generic_rip #{Time.now}" + '"'
  else
    # check that the current disc's title is not already used (e.g., same-named disc or previously failed rip)
    #MK TODO FIX THIS
  end

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
  puts s="Ripping slot #{slot} using drive #{drive}..."
  $log.info(s)
  
  # load disc from slot
  l=load_disc(drive, slot) 
  # if no disc (false) or a failure (nil), return
  unless l
    if l==false 
      puts s = "No disc in slot #{slot}"
      $log.info(s)
    else
      puts s = "Error loading slot #{slot}"
      $log.error(s)
    end
    return l
  end

  # wait for disc to mount
  while disc_title(drive)==false
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
    out_slot = (out_slot < FIRST_ERR_SLOT) ? FIRST_ERR_SLOT : out_slot + 1
    raise "CRISIS:  ALL OUTPUT SLOTS FULL!" if out_slot > LAST_ERR_SLOT
    $log.warn("Attempting alternate unload to slot #{out_slot}.")
    u = unload_disc(drive, out_slot)
  end
  s="Done ripping slot #{slot}, returned to slot #{out_slot}"

  return r
end

# run two ripping processes in parallel
def rip_all_discs()
  results = []
  start_time = Time.now()

  # fork to rip odd-numbered 
  pid = fork {
    (FIRST_INPUT_SLOT..LAST_INPUT_SLOT).step(2) { |o| results[o]=process_rip(o) }
  }   
  # rip even-numbered
  ((FIRST_INPUT_SLOT+1)..LAST_INPUT_SLOT).step(2) { |e| results[e]=process_rip(e)}

  # wait for things to finish
  Process.waitpid(pid)

  # generate summary report based on results array
  
  # create an output file to log all discs
  success = 0
  failure = 0
  empty = 0
  1.upto(LAST_INPUT_SLOT) do |i|
    case results[i]
      when true
        success += 1
      when false
        empty += 1
      when nil
        failure += 1  
    end 
  end

  File.open("#{RIPDIR}/rip_all.log", 'w') do |f|
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
  when "status"  then puts device_status()
  when "test_all_cassettes" then test_all_cassettes()
  when "rip_one" then process_rip(opts[:slot])
  when "rip_all" then rip_all_discs()
end
