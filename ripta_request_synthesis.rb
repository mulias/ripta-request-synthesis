require 'fuzzystringmatch'
require 'json'
require 'ostruct'

class Request
  attr_reader :route_ids, :directions, :stop_ids

  def initialize(route_ids, directions, stop_ids, static_data)
    @route_ids = route_ids
    @directions = directions
    @stop_ids = stop_ids
    @data = static_data

    if @route_ids.empty?
      raise "no valid routes for this request"
    elsif @directions.empty?
      raise "no valid directions for this request"
    elsif @stop_ids.empty?
      raise "no valid stops for this request"
    end
  end

  def self.new_stop_countdown(stop_query, route: nil, direction: nil,
                              static_data: StaticData.new)
    route_ids = route ? [route] : static_data.route_ids
    directions = direction ? [direction] : static_data.directions
    stop_ids = static_data.fuzzy_match_stops(stop_query, threshold: 0.7)
    new(route_ids, directions, stop_ids, static_data)
  end

  def select_route(route_id)
    Request.new([route_id], @directions, @stop_ids, @data)
  end

  def select_direction(direction)
    Request.new(@route_ids, [direction], @stop_ids, @data)
  end

  def select_stop(stop_id)
    Request.new(@route_ids, @directions, [stop_id], @data)
  end

  def route_names
    @route_ids.map { |id| @data.routes[id].route_short_name }
  end

  def stop_descriptions
    @stop_ids.map { |id| @data.stops[id].stop_desc }
  end

  def refine_routes_with_stops
    # restrict routes with stop routes
    first_stop_routes = @data.stops[@stop_ids.first].route_ids
    all_stop_routes = @stop_ids.reduce(first_stop_routes) do |acc, stop_id|
      acc | @data.stops[stop_id].route_ids
    end
    new_routes = @route_ids & all_stop_routes
    Request.new(new_routes, @directions, @stop_ids, @data)
  end

  def refine_routes_with_directions
    new_routes = @route_ids.select do |route_id|
      (@directions.include? @data.routes[route_id].direction_0) ||
      (@directions.include? @data.routes[route_id].direction_1)
    end
    Request.new(new_routes, @directions, @stop_ids, @data)
  end

  def refine_directions_with_routes
    # restrict directions with route directions
    first_route = @data.routes[@route_ids.first]
    first_route_dirs = [first_route.direction_0, first_route.direction_1]
    all_route_dirs = @route_ids.reduce(first_route_dirs) do |acc, route_id|
      route = @data.routes[route_id]
      acc | [route.direction_0, route.direction_1]
    end
    new_directions = @directions & all_route_dirs
    Request.new(@route_ids, new_directions, @stop_ids, @data)
  end

  def refine_directions_with_stops
    # restrict directions with stop_directions
    first_stop_dirs = @data.stops[@stop_ids.first].directions
    all_stop_dirs = @stop_ids.reduce(first_stop_dirs) do |acc, stop_id|
      acc | @data.stops[stop_id].directions
    end
    new_directions = @directions & all_stop_dirs
    Request.new(@route_ids, new_directions, @stop_ids, @data)
  end

  def refine_stops_with_routes
    # restrict stop_ids with route stops
    first_route_stops = @data.routes[@route_ids.first].stop_ids
    all_route_stops = @route_ids.reduce(first_route_stops) do |acc, route_id|
      acc | @data.routes[route_id].stop_ids
    end
    new_stops = @stop_ids & all_route_stops
    Request.new(@route_ids, @directions, new_stops, @data)
  end

  def refine_stops_with_directions
    # restrict stop_ids by stop direction
    new_stops = @stop_ids.select do |stop_id|
      !(@directions & @data.stops[stop_id].directions).empty?
    end
    Request.new(@route_ids, @directions, new_stops, @data)
  end

  def refine_all
    self.
      refine_routes_with_stops.
      refine_directions_with_stops.
      refine_routes_with_directions.
      refine_stops_with_directions.
      refine_directions_with_routes.
      refine_stops_with_routes
  end

  def results
    @route_ids.map do |route_id|
      route = @data.routes[route_id]
      dir_0_results =
        if @directions.include? route.direction_0
          (route.direction_0_stop_ids & @stop_ids).map do |stop_id|
            Result.new(route, route.direction_0, @data.stops[stop_id])
          end
        else
          []
        end
      dir_1_results =
        if @directions.include? route.direction_1
          (route.direction_1_stop_ids & @stop_ids).map do |stop_id|
            Result.new(route, route.direction_1, @data.stops[stop_id])
          end
        else
          []
        end
      [dir_0_results, dir_1_results]
    end.flatten
  end

  def min_results
    [@route_ids.count, @directions.count, @stop_ids.count].max
  end
end

class Result < Struct.new(:route, :direction, :stop)
  def to_s
    "#{route.route_short_name} #{direction} to #{stop.stop_desc}"
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
    matcher = FuzzyStringMatch::JaroWinkler.create(:pure)
    @stops.select do |stop_id, stop|
      matcher.getDistance(stop.stop_desc, search_str) >= threshold
    end.keys
  end
end

class TUI
  def self.ask(question)
    print "#{question} "
    gets.chomp
  end

  def self.ask_stop_countdown
    stop_query = ask("Stop location (Required):")

    get_route = ask("Bus Route (Enter to skip):")
    route = get_route.empty? ? nil : get_route.to_i

    get_direction = ask("Bus Direction (Enter to skip):")
    direction = get_direction.empty? ? nil : get_direction

    return stop_query, route, direction
  end

  def self.ask_list(question, entries_list)
    puts question
    entries_list.each.with_index { |entry, i| puts "\t#{i+1}.\t#{entry}" }
    gets.chomp.to_i - 1
  end

  def self.ask_route_list(req)
    n = ask_list("Which bus route are you looking for?", req.route_names)
    route = req.route_ids[n]
    req.select_route(route)
  end

  def self.ask_route_number(req)
    route_str = ask("Which bus route are you looking for?")
    req.select_route(route_str.to_i)
  end

  def self.ask_direction_list(req)
    n = ask_list("Which route direction are you looking for?", req.directions)
    direction = req.directions[n]
    req.select_direction(direction)
  end

  def self.ask_stop_list(req)
    n = ask_list("Which stop are you looking for?", req.stop_descriptions)
    stop = req.stop_ids[n]
    req.select_stop(stop)
  end

  def self.ask_result_list(results)
    n = ask_list("Which request would you like?", results)
    results[n]
  end
end
