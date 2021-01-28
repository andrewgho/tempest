# Tempest - read and interpret events from WeatherFlow Tempest weather station
# Andrew Ho (andrew@zeuscat.com)
#
# Tempest API docs: https://weatherflow.github.io/Tempest/api/udp/v143/
#
# TODO: should pass through source (serial number, IP address)
# TODO: need to add a lot of error checking.

require 'socket'
require 'json'

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
