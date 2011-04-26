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

require 'yaml'


def load_obj(filename)
  $y = YAML.load_file(filename)
  true
end
def p_apply(service)
  puts $y['tests'][service]['apply']
  true
end
def p_test(service)
  puts $y['tests'][service]['test']
  true

end
# Write out the output of the 'apply' stage to a file.
def f_apply(service,file)
  File.open(file,'w') do |f|
    f.puts $y['tests'][service]['apply']
  end
end
def helpme()
  use = [] 
  use << "Usage:"
  use << ""
  use << "load_obj 'filename' # Load the output of your vmth run"    
  use << "p_apply 'scenario' # Shows output of apply step"
  use << "p_test 'scenario' # Shows output of test step"
  use << "f_apply 'scenario','filename' # Write out a scenario's output to a file"
  use << "helpme() # This help message"
  return use.join("\n")
end

puts helpme()
