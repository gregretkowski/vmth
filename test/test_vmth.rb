#!/bin/ruby
require File.dirname(__FILE__)+"/helpers.rb"
require 'vmth'

class VmthTest < Test::Unit::TestCase
  def setup
    true
  end
  def test_true
    assert true
  end
  
  
  def test_new
    assert_nothing_raised do
      @vmth = Vmth.new()
    end
  end
  def test_vmcl
    @vmth = Vmth.new()
    vmcl = @vmth.vmcl()
    assert vmcl.class == String, "vmcl did not return a string"
    assert ! vmcl.empty?
  end
end
