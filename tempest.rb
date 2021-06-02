#!/usr/bin/env ruby
# Tempest - read and interpret events from WeatherFlow Tempest weather station
# Andrew Ho (andrew@zeuscat.com)
#
# Tempest API docs: https://weatherflow.github.io/Tempest/api/udp/v143/
#
# TODO: should pass through source (serial number, IP address)
# TODO: need to add a lot of error checking.

require 'optparse'
require 'logger'
require 'socket'
require 'json'

ME = File.basename($0)
USAGE = "usage: #{ME} [-h] [-v] [-x] [-t sec] [-o log] [-d data] [-s state]\n"
FULL_USAGE = USAGE + <<'end'
    -h                display this help text and exit
    -v, --verbose     verbose mode, log extra information
    -x, --debug       debug mode, run in foreground
    -o, --logfile     write log messages to this file (default stderr)
    -d, --datafile    write tab-separated data to this file (default stdout)
    -s, --statefile   atomically update this file with current state as JSON
end

# Main loop, run at end of file
def main(argv)
  # Parse command line arguments
  orig_argv = argv.dup
  verbose = false
  debug = false
  logfile = nil      # write log messages (logger output) to this file
  datafile = nil     # write tab-separated (timeseries) data to this file
  statefile = nil    # atomically update this file with current state as JSON
    OptionParser.new do |opts|
    opts.on('-h', '--help')    { puts FULL_USAGE; exit 0 }
    opts.on('-v', '--verbose') { verbose = true }
    opts.on('-x', '--debug')   { debug = true }
    opts.on('-o', '--logfile=LOG')     { |str| logfile = str }
    opts.on('-d', '--datafile=DATA')   { |str| datafile = str }
    opts.on('-s', '--statefile=STATE') { |str| statefile = str }
    begin
      opts.parse!(argv)
    rescue OptionParser::InvalidOption => e
      abort "#{ME}: #{e}\n#{USAGE}"
    end
  end

  # Set up diagnostic logging
  logger = Logger.new((debug || logfile.nil?) ? $stderr :
                      logfile == '-' ? $stdout :
                      logfile)
  logger.level = verbose ? Logger::DEBUG : Logger::INFO
  logger.info("#{ME} starting up: #{ME} #{orig_argv.join(' ')}")

  # Set up tab-separated timeseries data output stream
  datastream = datafile && datafile != '-' ? open(datafile, 'a') : $stdout

  # Get absolute path to statefile, since daemonizing does chdir()
  statefile = File.expand_path(statefile) if statefile

  # Daemonize, unless in debug mode
  if debug
    logger.info("running in foreground (#{Process.pid})")
  else
    logger.debug('daemonize()')
    daemonize
    logger.info("daemonized (#{Process.pid})")
  end

  # Main loop
  status = 0
  begin
    tempest = Tempest::Client.new
    while true
      event = tempest.read_event
      datastream.puts(event.inspect)
    end

  # Exit cleanly on usual termination signals
  rescue Interrupt => e
    logger.debug("Interrupt(#{e.message})")
    logger.info('exiting cleanly on interrupt')
    status = 0
  rescue SignalException => e
    logger.debug("SignalException(#{e.message})")
    if e.message == 'SIGINT' || e.message == 'SIGTERM'
      logger.info("exiting cleanly on #{e.message}")
      status = 0
    end

  # Log and exit with non-zero status on uncaught exceptions
  rescue Exception => e
    logger.error("uncaught exception:\n#{e.message}, backtrace:\n" +
                 e.backtrace.map { |s| "    #{s}" }.join("\n"))
    status = 1
  end

  status
end

module Tempest
  # An event reported by the Tempest base station.
  class Event
    # Map event name to human readable description, which event field holds
    # the actual observation data, and field names for the observation fields.
    # At least one observation type (obs_st) has an array containing an array
    # with the data; flatten such a doubled array if doubled_array is true.
    # For debug events, passthrough_all means copy all fields as is.
    METADATA = {
      evt_precip: {
        description: 'Rain Start',
        observation_field: 'evt',
        fields: ['time_epoch_s'],
      },
      evt_strike: {
        description: 'Lightning Strike',
        observation_field: 'evt',
        fields: ['time_epoch_s', 'distance_km', 'energy'],
      },
      rapid_wind: {
        description: 'Rapid Wind',
        observation_field: 'ob',
        fields: ['time_epoch_s', 'wind_speed_mps', 'wind_direction_degrees'],
      },
      obs_air: {
        description: 'Observation (Air)',
        observation_field: 'obs',
        fields: [
          'time_epoch_s',
          'station_pressure_mb',
          'air_temperature_c',
          'relative_humidity_pct',
          'lightning_strike_count',
          'lightning_strike_avg_distance_km',
          'battery_volts',
          'report_interval_min',
        ],
      },
      obs_sky: {
        description: 'Observation (Sky)',
        observation_field: 'obs',
        fields: [
          'time_epoch_s',
          'illuminance_lux',
          'uv_index',
          'rain_accumulated_mm',
          'wind_lull_mps',
          'wind_avg_mps',
          'wind_gust_mps',
          'wind_direction_degrees',
          'battery_volts',
          'report_interval_min',
          'solar_radiation_wpm2',
          'local_day_rain_accumulation_mm',
          'precipitation_type',
          'wind_sample_interval_s',
        ],
      },
      obs_st: {
        description: 'Observation (Tempest)',
        observation_field: 'obs',
        double_array: true,
        fields: [
          'time_epoch_s',
          'wind_lull_mps',
          'wind_avg_mps',
          'wind_gust_mps',
          'wind_direction_degrees',
          'wind_sample_interval_s',
          'station_pressure_mb',
          'air_temperature_c',
          'relative_humidity_pct',
          'illuminance_lux',
          'uv_index',
          'solar_radiation_wpm2',
          'precipitation_accumulated_mm',  # TODO: same as rain_accumulated_mm?
          'precipitation_type',
          'lightning_strike_avg_distance_km',
          'lightning_strike_count',
          'battery_volts',
          'report_interval_min',
        ],
      },
      device_status: {
        description: 'Status (device)',
        passthrough_all: true,
      },
      hub_status: {
        description: 'Status (hub)',
        passthrough_all: true,
      },
    }

    # Translate a raw event data packet to a hash with more meaningful names
    # and values (for example, obsevation name/value pairs instead of arrays
    # of indexed observation values).
    def self.from(event)
      type = event['type']
      metadata = METADATA[type.to_sym]
      retval = {}
      retval['type'] = type
      retval['description'] = metadata[:description]
      observation_field = metadata[:observation_field]
      if observation_field && event[observation_field]
        observations = event[observation_field]
        observations = observations[0] if metadata[:double_array]
        observations.each_with_index do |value, i|
          name = metadata[:fields][i]
          retval[name] = value
        end
      end
      if metadata[:passthrough_all]
        event.each do |name, value|
          retval[name] ||= value
        end
      end
      retval
    end
  end

  # A network client to read events from the Tempest base station.
  class Client
    DEFAULT_PORT = 50222
    MAXLEN_BYTES = 65536

    attr_reader :ipaddr
    attr_reader :port
    attr_reader :socket

    def initialize(ipaddr = '', port = DEFAULT_PORT)
      @ipaddr = ipaddr
      @port = port
      @socket = UDPSocket.new
      @socket.bind(@ipaddr, @port)
    end

    def read_event
      message, sender = @socket.recvfrom(MAXLEN_BYTES)
      event = JSON.parse(message)
      Tempest::Event.from(event)
    end
  end
end

# Daemonize
def daemonize
  exit!(0) if fork
  Process::setsid
  exit!(0) if fork
  Dir::chdir('/var/tmp')
  File::umask(0)
  $stdin.reopen('/dev/null')
  $stdout.reopen('/dev/null', 'w')
  $stderr.reopen('/dev/null', 'w')
end

# Write to a file atomically by writing to tempfile and calling rename()
def atomic_write(filename)
  # Generate probably-unique temporary filename, preserving extension
  dir = File.dirname(filename)
  extension = File.extname(filename)
  basename = File.basename(filename, extension)
  nonce = "#{Process.pid}_#{Time.now.strftime('%s%L')}_#{rand(1000000)}"
  tmpfile = File.join(dir, "#{basename}.#{nonce}#{extension}")

  File.open(tmpfile, 'w') do |fh|
    retval = yield(fh)
    fh.close

    # Try to match old file permissions, if any
    begin
      old_stat = File.stat(filename)
    rescue Errno::ENOENT
    end
    if old_stat
      begin
        File.chown(old_stat.uid, old_stat.gid, fh.path)
        File.chmod(old_stat.mode, fh.path)
      rescue Errno::EPERM, Errno::EACCES
      end
    end

    # Atomically overwrite previous file, if any
    File.rename(fh.path, filename)
    retval
  end
end

# Run main loop and exit
exit main(ARGV)
