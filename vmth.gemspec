# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{vmth}
  s.version = "0.0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Greg Retkowski"]
  s.date = %q{2011-04-26}
  s.description = %q{require 'rubygems' require 'rake' require 'echoe'  Echoe.new('vmth', '0.0.1') do |p| p.description    = File.open(File.dirname(__FILE__+"/DESCRIPTION")).read p.summary        = "A VM test harness for testing operational configurations" p.url            = "http://github.com/gregretkowski/vmth" p.author         = "Greg Retkowski" p.email          = "greg@rage.net" p.ignore_pattern = ["tmp/*", "script/*", "ol/*"] p.rdoc_template  = nil p.rdoc_pattern = /^(lib|bin|tasks|ext)|^README|^CHANGELOG|^TODO|^LICENSE|^QUICKSTART|^COPYING$/ #  p.rdoc_template = "" p.development_dependencies = [] p.runtime_dependencies = [ 'formatr', 'net-ssh', 'net-scp', ]  end}
  s.email = %q{greg@rage.net}
  s.executables = ["virb", "vmth"]
  s.extra_rdoc_files = ["CHANGELOG", "LICENSE", "QUICKSTART.rdoc", "README.rdoc", "bin/virb", "bin/vmth", "lib/defaults.yaml", "lib/virb.rb", "lib/vmth.rb"]
  s.files = ["CHANGELOG", "DESCRIPTION", "LICENSE", "Manifest", "QUICKSTART.rdoc", "README.rdoc", "Rakefile", "bin/virb", "bin/vmth", "lib/defaults.yaml", "lib/virb.rb", "lib/vmth.rb", "sample_config.yaml", "test/helpers.rb", "test/test_virb.rb", "test/test_vmth.rb", "vmth.gemspec"]
  s.has_rdoc = true
  s.homepage = %q{http://github.com/gregretkowski/vmth}
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Vmth", "--main", "README.rdoc"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{vmth}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{A VM test harness for testing operational configurations}
  s.test_files = ["test/test_vmth.rb", "test/test_virb.rb"]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<formatr>, [">= 0"])
      s.add_runtime_dependency(%q<net-ssh>, [">= 0"])
      s.add_runtime_dependency(%q<net-scp>, [">= 0"])
    else
      s.add_dependency(%q<formatr>, [">= 0"])
      s.add_dependency(%q<net-ssh>, [">= 0"])
      s.add_dependency(%q<net-scp>, [">= 0"])
    end
  else
    s.add_dependency(%q<formatr>, [">= 0"])
    s.add_dependency(%q<net-ssh>, [">= 0"])
    s.add_dependency(%q<net-scp>, [">= 0"])
  end
end
