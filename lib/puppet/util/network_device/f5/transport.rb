## This code is simply the icontrol gem renamed and mashed up.
require 'openssl'
require 'savon'

module Savon
  class Client
    def get(call, message=nil)
      if message
        response = self.call(call, message: message).body["#{call}_response".to_sym][:return][:item]
      else
        response = self.call(call).body["#{call}_response".to_sym][:return][:item]
      end
      return response if response.is_a?(String)
      if response.is_a?(Hash)
        if response[:item]
          return response[:item]
        else
          return response
        end
      end
      return {}
    end
  end
end

module Puppet::Util::NetworkDevice::F5
  class Transport
    attr_reader :hostname, :username, :password, :directory
    attr_accessor :wsdls, :endpoint, :interfaces

    def initialize hostname, username, password, wsdls = []
      @hostname = hostname
      @username = username
      @password = password
      @directory = File.join(File.dirname(__FILE__), '..', 'wsdl')
      @wsdls = wsdls
      @endpoint = '/iControl/iControlPortal.cgi'
      @interfaces = {}
    end

    def get_interfaces
      @wsdls.each do |wsdl|
        # We use + here to ensure no / between wsdl and .wsdl
        wsdl_path = File.join(@directory, wsdl + '.wsdl')

        if File.exists? wsdl_path
          namespace = 'urn:iControl:' + wsdl.gsub(/(.*)\.(.*)/, '\1/\2')
          url = 'https://' + @hostname + '/' + @endpoint
          @interfaces[wsdl] = Savon.client(wsdl: wsdl_path, ssl_verify_mode: :none,
            basic_auth: [@username, @password], endpoint: url,
            namespace: namespace, convert_request_keys_to: :none,
            strip_namespaces: true, log: false)
        end
      end

      @interfaces
    end

    def get_all_interfaces
      @wsdls = self.available_wsdls
      puts @wsdls
      self.get_interfaces
    end

    def available_interfaces
      @interfaces.keys.sort
    end

    def available_wsdls
      Dir.entries(@directory).delete_if {|file| !file.end_with? '.wsdl'}.sort
    end
  end
end
