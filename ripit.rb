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
DRIVES=['/dev/sr1', '/dev/sr2']
RIPDIR='/rip'

$log = Logger.new("#{RIPDIR}/ripit.log", 'daily')
$log.level = Logger::INFO

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
    $log.info "stdout:#{title}"

    title = title.match(/media\/(.*)$/) if title
    title = title[1] if title
    $log.info "title:\t#{title}"
    return title
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

def log_disc_info(drive_num)
  title=disc_title(drive_num)
  info=disc_info(drive_num)
  File.open("#{RIPDIR}/#{title}.log", 'w') {|f| f.puts info}
end

def load_disc(slot_num, drive_num)
  raise "Invalid slot number" unless valid_slot?(slot_num)
  raise "Invalid drive number" unless valid_drive?(drive_num)

  load_cmd = "mtx -f #{CAROUSEL_DEVICE} load #{slot_num} #{drive_num}"
  puts load_cmd if $dry_run
  $log.info load_cmd

  unless $dry_run
    pid, stdin, stdout, stderr = Open4::popen4(load_cmd)
    ignored, status = Process::waitpid2(pid)

    # TODO: add logic to deal with return code
    $log.info "status:\t#{status}"
    $log.info "stdout:#{stdout.readlines.to_s}"
    $log.info "stderr:#{stderr.readlines.to_s}"
    disc_title(drive_num)
  end
end

def unload_disc(slot_num, drive_num)
  raise "Invalid slot number" unless valid_slot?(slot_num)
  raise "Invalid drive number" unless valid_drive?(drive_num)

  unload_cmd = "mtx -f #{CAROUSEL_DEVICE} unload #{slot_num} #{drive_num}"
  puts unload_cmd if $dry_run
  $log.info unload_cmd

  unless $dry_run
    pid, stdin, stdout, stderr = Open4::popen4(unload_cmd)
    ignored, status = Process::waitpid2(pid)

    # TODO: add logic to deal with return code
    $log.info "status:\t#{status}"
    $log.info "stdout:#{stdout.readlines.to_s}"
    $log.info "stderr:#{stderr.readlines.to_s}"
    $log.info `df | grep #{DRIVES[drive_num]}`
    disc_title(drive_num)
  end
end

# should I ever do this? takes 20 min. but may save headaches.
def slot_status()
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

    # TODO: add logic to deal with return code
    # 0 on success
    # 1 on usage error
    # 2 on title name error
    # -1 on failure
    case status
      when 1
        $log.error "command usage error!"
      when 2
      if use_generic_title
        $log.error "error ripping with generic name!"
      end
        $log.info "title has generic name; retrying"
      when 
    end
    $log.error "command usage error!" if status==1
    if status==2

      $log.warn "title name invalid"
      if use_generic_title
      end
    end
    $log.warn "title name invalid" if status==

    $log.info "status:\t#{status}"
    $log.info "stdout:#{stdout.readlines.to_s}"
    $log.info "stderr:#{stderr.readlines.to_s}"
    $log.info `df | grep #{DRIVES[drive_num]}`
    disc_title(drive_num)
  end
  log_disc_info(drive_num)
end

##########################################################
# RIPPING OPERATIONS
##########################################################


def rip_all_discs
  # fork off two processes
  
  # rip odd-numbered 
  spawn (1..MAX_SLOTS).step(2) { |o| process_rip(o) }
  # rip even-numbered
  spawn (2..MAX_SLOTS).step(2) { |e| process_rip(e)}

  # wait for them to finish
end


##########################################################
# MAIN BODY
##########################################################

# record the command & start time in the log
$log.info ARGV 
$dry_run = opts[:dry_run]

# process the command
case cmd
  when "load"   then load_disc(opts[:slot], opts[:drive])
  when "unload" then unload_disc(opts[:slot], opts[:drive])
  when "rip"    then rip_disc(opts[:drive])
  when "info"   then puts disc_info(opts[:drive])
  when "title"  then puts disc_title(opts[:drive])
end



# TODO: fail gracefully and return disc to original slot on error
# TODO: cartridge-level ops
# TODO: looping ops


