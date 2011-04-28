require 'rubygems'
require 'rake'
require 'echoe'

Echoe.new('vmth', '0.0.2') do |p|
  p.description    = File.open(File.dirname(__FILE__+"/DESCRIPTION")).read
  p.summary        = "A VM test harness for testing operational configurations"
  p.url            = "http://github.com/gregretkowski/vmth"
  p.author         = "Greg Retkowski"
  p.email          = "greg@rage.net"
  p.ignore_pattern = ["tmp/*", "script/*", "ol/*"]
  p.rdoc_template  = nil
  p.rdoc_pattern = /^(lib|bin|tasks|ext)|^README|^CHANGELOG|^TODO|^LICENSE|^QUICKSTART|^CONFIG|^COPYING$/
#  p.rdoc_template = ""
  p.development_dependencies = []
  p.runtime_dependencies = [
    'formatr',
    'net-ssh',
    'net-scp',
  ]

end
