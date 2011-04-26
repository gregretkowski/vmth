#!/bin/ruby
require File.dirname(__FILE__)+"/helpers.rb"
require 'virb'

class VirbTest < Test::Unit::TestCase
  def setup
    true
  end
  def test_new
    assert defined?(p_test)
    assert defined?(f_apply)
  end
end
