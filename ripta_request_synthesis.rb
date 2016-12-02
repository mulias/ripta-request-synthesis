require 'fuzzystringmatch'
require 'json'
require 'ostruct'

class Request
  attr_reader :route_ids, :directions, :stop_ids

  def initialize(static_data, route_ids, directions, stop_ids)
    @route_ids = route_ids
    @directions = directions
    @stop_ids = stop_ids
    @data = static_data
  end

  def self.new_stop_countdown(static_data: StaticData.new,
                              route: nil, direction: nil, stop_query:)
    route_ids = route ? [route] : static_data.route_ids
    directions = direction ? [direction] : static_data.directions
    stop_ids = static_data.fuzzy_match_stops(stop_query, threshold: 0.7)
    new(static_data, route_ids, directions, stop_ids)
  end

  def valid?
    !(@route_ids.empty? || @directions.empty? || @stop_ids.empty?)
  end

  def refine_routes_with_stops
    # add routes for the stop to route_ids
    # new_routes = @stops.each
    # Request.new(new_routes, @directions, @stops)
  end

  def refine_routes_with_directions
    # Request.new(new_routes, @directions, @stops)
  end

  def refine_directions_with_routes
    # restrict directions with route directions
    # Request.new(@route_ids, new_directions, @stops)
  end

  def refine_directions_with_stops
    # restrict directions with stop_directions
    # Request.new(@route_ids, new_directions, @stops)
  end

  def refine_stops_with_routes
    # restrict stop_ids with route stops
    # Request.new(@route_ids, @directions, new_stops)
  end

  def refine_stops_with_directions
    # restrict stop_ids by stop direction
    # Request.new(@route_ids, @directions, new_stops)
  end
end

class StaticData
  attr_reader :a, :routes, :route_ids, :directions, :stops, :stop_ids

  def initialize(routes_json: 'static_data/routes.json',
                 stops_json: 'static_data/stops.json')
    @routes = parse_routes(routes_json)
    @route_ids = @routes.keys
    @directions = ["Inbound", "Outbound", "North", "South", "East", "West"]
    @stops = parse_stops(stops_json)
    @stop_ids = @stops.keys
  end

  def parse_routes(routes_json)
    JSON.parse(IO.read(routes_json), object_class: OpenStruct).
      reduce({}) { |acc, route| acc.update(route.route_id => route) }
  end

  def parse_stops(stops_json)
    JSON.parse(IO.read(stops_json), object_class: OpenStruct).
      reduce({}) { |acc, stop| acc.update(stop.stop_id => stop) }
  end

  def fuzzy_match_stops(search_str, threshold: 0.7)
    matcher = FuzzyStringMatch::JaroWinkler.create(:native)
    @stops.select do |stop_id, stop|
      matcher.getDistance(stop.stop_desc, search_str) >= threshold
    end.map { |stop_id, _| stop_id }
  end
end

class DynamicData

end

class TUI

end
