#!/usr/bin/env ruby
APP_PATH = File.expand_path('../config/application', __dir__)

require 'concurrent'
require 'gosu'

require_relative '../src/application'

