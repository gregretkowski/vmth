#!/usr/bin/ruby

#--
# Copyright 2011 Greg Retkowski
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#++

require 'rubygems'
require 'net/ssh'
require 'net/scp'
require 'pty'
require 'expect'
require 'fileutils'
require 'tempfile'
require 'erb'


class VmthError < RuntimeError;end

=begin rdoc
This class provides a VM test harness to allow testing of operational
code (puppet policies, chef configs, etc..) against a environment
similar to your production environment.

The VM test harness uses features of the VM monitor (qemu) to freeze
and re-use system memory/disk state so that a series of test scenarios
can be rapidly tested.

This class provides all the logic to implement the VM test harness. It
manages the VM, loads and runs tests for each scenario, and produces
a 'results' hash with the results of the test.
=end

class Vmth
  # Set the directory where your puppet code directory is.
  attr_accessor :source_dir
  # A boolean, should we use QEMU or not? Should almost always be true.
  attr_accessor :vmm_enabled
  # The machdb services.yaml location. Describes which services should be tested.
  attr_accessor :scenarios_file
  # The system/disk image file booted by QEMU
  attr_accessor :image_file
  # Contains the hash of all test output and results. Read this after
  # you've completed your test run.
  attr_reader :results
  # So we can flush this if there's an error.
  attr_accessor :vmm_r
  attr_reader :options
  #
  # new takes no arguments.
  #
  DEFAULT_OPTIONS={
    :source_path => ".",
    :vmm_enabled => true,
    :config_file => nil,
    :scenarios_file => nil,
    :image_file => nil,
    :debug => false,
    :action => 'all',
    :outfile => self.class.to_s.downcase+"_out.yaml",
    :out_format => 'text',
    :services => []
  }
  
  def initialize(options={})
    @options=DEFAULT_OPTIONS.merge(options)
    @config = YAML.load_file(File.dirname(__FILE__)+'/defaults.yaml')
    if @options[:config_file]
      @config.merge!(YAML.load_file(@options[:config_file]))
    end
    @log = Logger.new(STDERR)
    if @options[:debug]
      @log.level = Logger::DEBUG
    else
      @log.level = Logger::WARN
    end
    @tmp_state = Tempfile.new("pth").path
    @results = {
      'tests' => {}
    }
    ssh_port_range=@config['vmm']['ssh_port_start']..@config['vmm']['ssh_port_end']
    @vm_ssh_port = Vmth.allocate_tcp_port(ssh_port_range)
    vnc_port_range=@config['vmm']['vnc_port_start']..@config['vmm']['vnc_port_end']
    @vm_vnc_port = Vmth.allocate_tcp_port(vnc_port_range) - 5900
    @vm_mac_addr = @config['vmm']['mca_start'] + "%02x" % (rand()*256).round
    @vmm_prompt = eb(@config['vmm']['prompt'])
    @vmm_timeout = @config['vmm']['timeout']
    @image_file=@options[:image_file]
    @source_path=@options[:source_path]
    # Try to cleanly shutdown the vmm.
    trap("INT") do
      if @vm_running
        stop_vm()
      end
      raise
    end
  end
  # Expand a string with ERB.
  def eb(string)
    renderer = ERB.new(string)
    return renderer.result(binding)
  end
  # Change the loglevel of the logger. Argument should
  # be a loglevel constant, i.e. Logger::INFO
  def loglevel=(level)
    @log.level=level
  end
  # Test all testable services - this is indicated by if a service in machdb
  # has the 'testable' field set to true. It takes no arguments and returns
  # an array of booleans, indicating the success or failure of tests. You
  # should query results() for your results.
  def test_all
    @results['test_start'] = Time.now()
    passed = []
    boot_vm() if @options[:vmm_enabled]
    prep
    freeze_vm() if @options[:vmm_enabled]
    @log.info "RUNNING NO-SERVICE TEST"
    passed << one_test(@config['init_scenario'])
    # Stop testing if our initial test fails.
    unless passed.first == true
      @log.error "Initial setup failed.. sleeping 60 seconds for debugging."
      sleep 60
      stop_vm() if @options[:vmm_enabled]
      return passed
    end
    freeze_vm() if @options[:vmm_enabled]
    @log.info "RUNNING TESTS"
    scenarios = get_scenarios
    test_counter = 0
    scenarios.each do |scenario|
      test_counter += 1
      @log.info "Running test for #{scenario} - #{test_counter} of #{scenarios.size}"
      passed << one_test(scenario)
    end
    stop_vm() if @config[:vmm_enabled]
    all_passed = passed.select{|p| p == false}.size == 0
    @log.info "Number of tests run : #{passed.size}"
    @log.info "Result of ALL tests: Passed? #{all_passed}"
    @results['test_stop'] = Time.now()
    @results['elapsed_time'] = @results['test_stop'] - @results['test_start']
    return all_passed
  end
  alias :test :test_all
  
  # Set up a vm, and drop it off for a developer to use.
  def console
    create_private_disk
    @results['test_start'] = Time.now()
    passed = []
    boot_vm() if @options[:vmm_enabled]
    prep
    freeze_vm() if @options[:vmm_enabled]
    # Print out ssh & vnc port, and freeze name.
    @log.info "Handing off VM to you.. Type #{@config['vmm']['quitvmm']} to end session."
    @log.info "Ports - SSH: #{@vm_ssh_port}  VNC: #{@vm_vnc_port}"

    # hand off console.
    print @config['vmm']['prompt']
    begin
      system('stty raw -echo')
      Thread.new{ loop { @vmm_w.print $stdin.getc.chr } }
      loop { $stdout.print @vmm_r.readpartial(512); STDOUT.flush }
    rescue
      nil # User probably caused the VMM to exit.
    ensure
      system "stty -raw echo"
    end
    # Done via the user?
    # stop_vm()
    cleanup_private_disk
    return
  end
  def create_private_disk
    @orig_image_file = @image_file
    @image_file = "#{@orig_image_file}.#{$$}"
    @log.debug "Copying #{@orig_image_file} to #{@image_file}"
    FileUtils.cp(@orig_image_file,@image_file)
  end
  def cleanup_private_disk
    @log.debug "Removing tmp imagefile #{@image_file}"
    if defined?(@orig_image_file) and @orig_image_file != @image_file
      File.delete(@image_file)
    end
  end
  
  # Cleanup state file, but only if everything is done!
  def cleanup
    File.delete(@tmp_state) rescue nil
  end
  # Really only for development/testing of this class.
  # Will run tests against an already running VM (presumably the
  # developer is running it in another window)
  def test_without_vm
    prep
    test_services
  end
  # Test a bunch of services. Pass in an array containing the names
  # of services to test. Returns an array of booleans, indicating
  # the success or failure of the tests. You should read detailed
  # results from results()
  def test_services(services)
    @results['test_start'] = Time.now()
    boot_vm() if @options[:vmm_enabled]
    prep
    freeze_vm() if @options[:vmm_enabled]
    passed = []
    @log.info "RUNNING NO-SERVICE TEST"
    passed << one_test(eb(@config["init_scenario"]))
    # Stop testing if our initial test fails.
    unless passed.first == true
      stop_vm() if @options[:vmm_enabled]
      return passed
    end
    freeze_vm() if @options[:vmm_enabled]
    @log.info "RUNNING TESTS"
    test_counter = 0
    services.each do |service|
      test_counter += 1
      @log.info "Running test for #{service} - #{test_counter} of #{services.size}"
      passed << one_test(service)
    end
    stop_vm() if @options[:vmm_enabled]
    @results['test_stop'] = Time.now()
    @results['elapsed_time']= @results['test_stop'] - @results['test_start']
    return passed
  end
  # Return the command-line that would have been used to start QEMU.
  # This can be used for developing this library, or to get a new
  # disk image prepped to be used with the test harness.
  def vmcl
    return vmm_command_line
  end
  #
  # START PRIVATE METHODS
  #
  private
  # This starts the QEMU instance for the test VM. Spawns the VM
  # and then sets @qemu_r (read socket for qemu), @qemu_w (write
  # socket for qemu) and @qemu_pid (qemu process ID).
  # These class variables are used to interact with the QEMU
  # supervisor.
  def start_vm
    unless File.exists?(@image_file) and File.owned?(@image_file)
      @log.error "Image file #{@image_file} doesn't exist or is not owned by you!"
      exit 255
    end
    @log.info "VM Will use SSH Port #{@vm_ssh_port} and VNC Port #{@vm_vnc_port}"
    @log.info "Starting vmm now..."
    @log.debug "vmm command line is: " + vmm_command_line()
    @vmm_r, @vmm_w, @vmm_pid = PTY.spawn vmm_command_line()
    @vmm_r.expect(@vmm_prompt,@vmm_timeout) do |line|
      true
    end
    @vm_running = true
    @log.debug "vmm instance pid is #{@vmm_pid}"
  end
  # Read in the scenarios file and return it as an array.
  def get_scenarios
    scenarios = []
    File.open(@options[:scenarios_file]) do |f|
      f.each_line do |line|
        scenarios << line.chomp
      end
    end
    return scenarios.sort
  end
  # Returns a command-line for invoking QEMU. Used by
  # start_qemu
  def vmm_command_line
    return eb(@config['vmm']['cmdline'])
  end
  # Stops the vmm process. First tries to issue the 'quit'
  # command on the qemu console.
  def stop_vm
    exit_status = nil
    @vm_running = false
    begin
      exit_status = vmm_command(eb(@config['vmm']['quitvmm']))
      sleep 1
      # Check to see if it is still running.
      is_alive = (Process.kill(0, @vmm_pid) rescue 0)
      if is_alive != 0
        @log.warn "Warning, vmm didn't die.. killing manually"
        Process.kill("TERM",@vmm_pid)
        sleep 2
      end
    rescue PTY::ChildExited
      true # expected
    end
    return exit_status
  end
  # Issue a command to the QEMU supervisor. Used
  # for saving or restoring VM state between tests.
  def vmm_command(command)
    return nil unless @options[:vmm_enabled]
    result = nil
    @log.debug "Issuing '#{command}' to vmm"
    return nil unless @vmm_w
    @vmm_w.puts("#{command}\n")
    begin
      @vmm_r.expect(@vmm_prompt,@vmm_timeout) do |line|
        @log.debug "Expect line was: #{line}"
        result = line
      end
    # Handle quick exit on 'quit' commands.
    rescue PTY::ChildExited, Errno::EIO => e
      if command == eb(@config['vmm']['quitvmm'])
        @log.debug "Command 'quit' exited before completion."
      else
        raise e
      end
    end
    @log.debug "Command completed with result '#{result}'"
    return result
  end
  def one_test(service)
    reset_vm
    passed = true
    @log.info "Running test for #{service}"
    passed = run_vmth_test(service)
    @log.info "Did it pass?: #{passed}"
    return passed
  end
  # Run a command on a ssh channel. Return false if we get a
  # match on bad_match - otherwise return true. bad_match
  # is used to pattern match text that indicates a bad exit
  # state - used when running something that'll trip a test
  def run_on_channel(session,command,bad_match)
    if bad_match.class == Regexp
      bad_match_regexp = bad_match
    else
      bad_match_regexp = /#{bad_match}/
    end
    output = []
    test_passed = true
    @log.debug "Running #{command}"
    session.open_channel do |ch|
      ch.exec command do |ch, success|
        unless success
          @log.info "could not execute #{command}"
          test_passed = false
        end
        ch.on_data do |ch, data|
          @log.debug data
          output << data
          if data =~ bad_match_regexp
            test_passed = false
          end
        end
        # Test failed if program/script exited nonzero
        ch.on_request("exit-status") do |ch,data|
          exit_code = data.read_long
          @log.debug "Command exited with #{exit_code.to_s}"
          if exit_code != 0
            test_passed = false
          end
        end
      end
    end
    # Causes this to block until the command completes.
    session.loop
    # So far if there's no output, the command failed..
    if output.empty?
      test_passed = false
    end
    return ({"passed" => test_passed, "output" => output.join("\n") })
  end
  
  # Run a test for a specific scenario on the guest VM. Will set 'service'
  # class on the VM and then execute puppet - which will invoke all
  # rules related to that class. It will then execute any unit
  # tests associated with that service. 
  # Fills in the @results instance variable with information
  # about the test then returns true|false indicating pass|fail
  def run_vmth_test(scenario)
    @scenario=scenario
    service=scenario # legacy/lazy
    start_timer = Time.now()
    @results['tests'][service] = {}
    test_passed = true
    begin
      ssh_session do |session|
        @results['tests'][service]['apply'] =
          _recursor(@config['applying'],session)
        @results['tests'][service]['test'] =
          _recursor(@config['testing'],session)
        @results['tests'][service]['passed'] =  @results['tests'][service]['apply']['passed'] \
          and @results['tests'][service]['test']['passed']
        _recursor(@config['teardown'],session)
        @results['tests'][service]['teardown'] =
           _recursor(@config['teardown'],session)
      end
    rescue => e
      # If anything was raised here it is big problems yo.
      @results['tests'][service]['apply'] ||= {}
      @results['tests'][service]['apply']['passed'] = false
      @results['tests'][service]['test'] ||= {}
      @results['tests'][service]['test']['passed'] = false
      @results['tests'][service]['passed'] = false
      @results['tests'][service]['error'] = {
        'class' => e.class.to_s, 'message' => e.message, 'backtrace' => e.backtrace
      }
    end
    @results['tests'][service]['elapsed_time'] = (Time.now() - start_timer)
    write_out_state()
    return @results['tests'][service]['passed']
  end
  
  # Write out a state file, handy for debugging later.
  def write_out_state
    if @options[:out_file]
      filename = @options[:out_file]
    else
      filename = @tmp_state
    end
    @log.debug "Writing out state into #{filename}"
    File.open(filename,'w') do |f|
      f.puts YAML.dump(@results)
    end
  end
  # Starts the QEMU instance and then immediately loads the saved
  # VM via 'loadvm foo'
  def boot_vm
    start_vm()
    @log.debug "Loading initial vm..."
    vmm_command(eb(@config['vmm']['loadinit']))
  end
  # Freeze the current state of the VM - so we can use it later
  # to reset the VM so that it is immediately ready for the next test.
  def freeze_vm()
    @log.debug "Freezing vm for test series"
    vmm_command(eb(@config['vmm']['saveteststate']))
  end
  # Reset the VM for the next test - using the instance saved by 'freeze'
  def reset_vm()
    @log.debug "Reseting vm for next test"
    vmm_command(eb(@config['vmm']['loadteststate']))
    # Give it a half a tic to reset...
    sleep 0.5
  end
  # Set up an ssh session.
  def ssh_session
    retry_flag=true
    @log.debug "ssh is #{@config['ssh'].inspect}"
    ssh_config = @config['ssh'].clone
    host = ssh_config['host']
    ssh_config.delete('host')
    user = ssh_config['user']
    ssh_config.delete('user')
    # Convert strings to symbols..
    ssh_config = ssh_config.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
    ssh_config[:port] = @vm_ssh_port
    begin
      Net::SSH.start(host,user,ssh_config) do |session|
        yield session
      end
    rescue EOFError => e
      raise(e) unless retry_flag
      retry_flag = false
      @log.info "SSH session creation failed, retrying!"
      retry
    end
  end
  # This function executes all the commands on the just-started VM to
  # sync over all files and state needed before testing can start.
  def prep
    ssh_session do |session|
      @results['prep'] = _recursor(@config['prep'],session)
    end
    @log.info "FINISHED PREP STEPS...."
  end
  
  private
  # Allocate a TCP port.
  def self.allocate_tcp_port(valid_ports=[])
    last_error = ArgumentError.new("Port range not given.")
    # Try to bind to each port until we don't error out
    # because of permission or it already being used.
    valid_ports.each do |port|
      begin
        s = TCPServer.open('0.0.0.0',port)
        s.close
        return port
      rescue => e
        last_error = e
        next
      end
    end
    # If we can't allocate a port raise an error.
    raise last_error.class, last_error.message
  end
  # Execute commands on vm, recurse if required.
  def _recursor(cmds,session)
    results = []
    passed = true
    @log.debug "Processing #{cmds.inspect}"
    cmds.each do |myhash|
      if myhash.size != 1
        @log.error "Config format problem with #{myhash.inspect}"
        raise VmthError
      end
      cmd = myhash.keys.first
      values = myhash[cmd]
      @log.debug "Values is #{values.inspect}"
      if cmd=='foreach'
        args = values.shift['args']
        args.each do |arg|
          @log.debug "Arg is #{arg.inspect}"
          @arg = arg
          res_hash = _recursor(values,session)
          results << res_hash['output']
          passed = res_hash['passed'] and passed
        end
      elsif cmd=='cmd'
        command_string = eb(values)+" 2>&1"
        @log.debug "Running on vm.. '#{command_string}"
        result = session.exec!(command_string)
        @log.debug "output is: #{result}"
        results << result
      elsif %{upload download upload_recurse download_recurse}.include?(cmd)
        first=eb(values[0])
        second=eb(values[1])
        @log.debug "File transfer with #{first} => #{second}"
        if cmd=='upload'
          results << session.scp.upload!(first,second)
        elsif cmd=='upload_recurse'
          results << session.scp.upload!(first,second,{:recursive=>true})
        elsif cmd=='download'
          results << session.scp.download!(first,second )
        elsif cmd=='download_recurse'
          results << session.scp.download!(first,second,{:recursive=>true})
        end
      elsif cmd=='cmdtest'
          res_hash = run_on_channel(session,eb(values[0]),values[1])
          results << res_hash['output']
          passed = res_hash['passed'] and passed
      else
        @log.error "unknown command #{cmd.inspect}"
        raise VmthError
      end
    end
    return {'output'=>results,'passed'=>passed}
  end
end # Class


