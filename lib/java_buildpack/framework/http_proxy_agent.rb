# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright 2013 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/framework'
require 'java_buildpack/util/dash_case'

module JavaBuildpack::Framework

  # Encapsulates the functionality for contributing custom Java options to an application.
  class HttpProxyAgent < JavaBuildpack::Component::VersionedDependencyComponent

    def detect
      HttpProxyAgent.to_s.dash_case
    end

    def compile
      download_jar "http-proxy-agent.jar"
    end

    def release
      @droplet.java_opts.concat ["$(eval 'if [ -n \"$http_proxy\" ] || [ -n \"$https_proxy\" ]; then  echo \"#{httpproxy_opts}\"; fi')"]
    end
    
    def supports?
      true
    end
    
    private
    
    def httpproxy_opts
      "-javaagent:#{@droplet.sandbox + 'http-proxy-agent.jar'}"
    end
  end
end
