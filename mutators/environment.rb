#!/usr/bin/env ruby
#
# This mutator will check the producing node's operating environment
# for specific keywords and will mutate the event to 'OK'
# if the node belongs there, so as not to trigger handlers for development/testing
# servers. It will also suppress the event if the subscription
# that has triggered the mutator belongs to the "maintenance:subscriptions" or the node name
# belongs to the "maintenance:names" Redis set on the Sensu server.
# If any of the sets contains the string 'all', then the handler
# will be supressed independently of the subscription/node name.
# Cool for setting maintenance mode for a specific set of subscriptions or all of them.
#
# To set an environment for the node, use /etc/sensu/conf.d/client.json like:
# {
#   "client": {
#     "name": "web-server",
#     "address": "10.0.0.1",
#     "subscriptions": [
#       "base",
#       "web-server"
#     ],
#     "environment": "prod"
# }
#
# Please make sure your Redis settings are correct and Sensu's redis is accessible from this
# script.
#
# Copyright 2013, Panagiotis Papadomitsos <pj@ezgr.net>
#
# Released under the same terms as Sensu (the MIT license); see
# LICENSE for details.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'json'
require 'redis'

MUTED_ENVIRONMENTS = [
  /dev(el)?(opment)?/,
  /test(ing)?/,
  /qa/,
  /stag(ei)?(ng)?/
]

def mute(event)
  event[:mutated] = true
  event[:check][:output] = "OK: Check #{event[:check][:name]} status suppressed due to maintenance or testing environment"
  event[:check][:status] = 0
  puts event.to_json
end

event = JSON.parse(STDIN.read, :symbolize_names => true)
begin
  # Mute if we are on a testing environment
  environment = event[:client][:environment]
  if MUTED_ENVIRONMENTS.select{ |env| environment.match(env) }.size > 0
    mute(event)
  else
    redis = Redis.new(:host => '127.0.0.1', :port => 6379)
    realsubs = [event[:check][:subscribers], 'all'].flatten
    realnames = [event[:client][:name], 'all'].flatten
    maintsubs = redis.smembers('maintenance:subscriptions')
    maintnames = redis.smembers('maintenance:names')

    # If the subscriptions are included in the maintenance set, suppress warnings
    if ((realsubs & maintsubs).size > 0) || ((realnames & maintnames).size > 0)
      mute(event)
    else
      puts event.to_json
    end
  end
rescue Exception => e
  puts event.to_json
end
