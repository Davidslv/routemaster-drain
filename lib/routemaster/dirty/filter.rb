require 'routemaster/dirty/state'
require 'routemaster/config'
module Routemaster
  module Dirty
    # Service object, filters an event payload, only include events that reflect
    # an entity state that is _more recent_ than previously received events.
    #
    # Can be used to Ignore events received out-of-order (e.g. an `update` event
    # about en entity received after the `delete` event for that same entity),
    # given Routemaster makes no guarantee of in-order delivery of events.
    #
    class Filter
      EXPIRY = 86_400

      # @param redis [Redis, Redis::Namespace] a connection to Redis, used to
      # persists the known state
      def initialize(redis:nil)
        @redis  = redis || Config.drain_redis
        @expiry = Config.cache_expiry
      end

      # Process a payload, and returns part if this payload containing
      # only the latest event for a given entity.
      #
      # Events are skipped if they are older than a previously processed
      # event for the same entity.
      #
      # Order of kept events is not guaranteed to be preserved.
      def run(payload)
        events = {} # url -> event

        payload.each do |event|
          known_state = State.get(@redis, event['url'])

          # skip events older than what we already know
          next if known_state.t > event['t']

          new_state = State.new(event['url'], event['t'])

          next if new_state == known_state
          new_state.save(@redis, @expiry)
          events[event['url']] = event
        end

        events.values
      end
    end
  end
end
