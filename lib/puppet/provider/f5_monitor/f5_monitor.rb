require 'puppet/provider/f5'

Puppet::Type.type(:f5_monitor).provide(:f5_monitor, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 monitor"

  confine :feature => :posix
  defaultfor :feature => :posix

  mk_resource_methods

  def self.wsdl
    'LocalLB.Monitor'
  end

  def wsdl
    self.class.wsdl
  end

  def self.instances
    f5monitors = Array.new
    monitor = Hash.new

    require 'pry'
    binding.pry
    transport[wsdl].call(:get_template_list).body[:get_template_list_response][:return][:item].collect do |monitor_template|
      monitor = { :name => monitor_template[:template_name],
                  :ensure => :present,
                  :type => monitor_template[:template_type] }
      f5monitors << new(monitor)
    end
    f5monitors
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name]
        resource.provider = prov
      end
    end
  end

  def flush
    @property_hash[:name] ||= resource[:name]
  end

  methods = [
    'manual_resume_state',
    'parent_template',
    'template_state',
    'template_transparent_mode',
    'template_user_defined_string_property'
  ]

  methods.each do |method|
    define_method(method.to_sym) do
      call = "get_#{method}".to_sym
      transport[wsdl].call(call, message: { template_names: @property_hash[:name]}).body["get_#{method}_response".to_sym][:return]
    end

    define_method("#{method}=") do |value|
      # Without this it appears to skip resources attributes on creation.
     # namevar = @property_hash[:name] || resource[:name]
      raise Puppet::Error, "Puppet::Provider::F5_monitor: missing namevar for resource" unless namevar
      transport[wsdl].call("set_#{method}".to_sym, message: { template_names: { item: value}})
    end
  end

  def monitor_ipport(value)
    # change ip/port to a hash F5 create_template accepts, process wildcards to 0.0.0.0:0 as appropriate.
    address_type = value[0]
    address      = network_address(value[1])
    port         = network_port(value[1])

    address = '0.0.0.0' if address == '*'
    port    = 0         if port == '*'

    {:address_type => address_type, :ipport => {:address => address, :port => port}}
  end

  def template_destination
    destination = transport[wsdl].call(:get_template_destination, message: { template_names: { item: resource[:name]}}).body[:get_template_destination_response][:return][:item]
    # need F5 eng review: http://devcentral.f5.com/wiki/iControl.LocalLB__AddressType.ashx
    case destination[:address_type]
    when 'ATYPE_STAR_ADDRESS_STAR_PORT'
      [ 'ATYPE_STAR_ADDRESS_STAR_PORT', "*:*" ]
    when 'ATYPE_STAR_ADDRESS_EXPLICIT_PORT'
      [ 'ATYPE_STAR_ADDRESS_EXPLICIT_PORT', "*:#{destination[:ipport][:port]}" ]
    when 'ATYPE_EXPLICIT_ADDRESS_EXPLICIT_PORT'
      [ 'ATYPE_EXPLICIT_ADDRESS_EXPLICIT_PORT', "#{destination[:ipport][:address]}:#{destination[:ipport][:port]}" ]
    when 'ATYPE_STAR_ADDRESS'
      [ 'ATYPE_STAR_ADDRESS', "*:*" ]
    when 'ATYPE_EXPLICIT_ADDRESS'
      [ 'ATYPE_EXPLICIT_ADDRESS', "#{destination[:ipport][:address]}:*" ]
    else
      [ 'ATYPE_UNSET', "#{destination[:ipport][:address]}:#{destination[:ipport][:port]}" ]
    end
  end

  def template_destination=(value)
    message = { template_names: { item: resource[:name]}, destinations: monitor_ipport(resource[:template_destination])}
    transport[wsdl].call(:set_template_destination, message: message)
  end

  def template_integer_property
    properties = [ 'ITYPE_UNSET',
                   'ITYPE_INTERVAL',
                   'ITYPE_TIMEOUT',
                   'ITYPE_PROBE_INTERVAL',
                   'ITYPE_PROBE_TIMEOUT',
                   'ITYPE_PROBE_NUM_PROBES',
                   'ITYPE_PROBE_NUM_SUCCESSES',
                   'ITYPE_TIME_UNTIL_UP',
                   'ITYPE_UP_INTERVAL']

    template_integer = {}
    properties.each do |property|
      message = { template_names: { item: @property_hash[:name] }, property_types: { item: property }}
      template_integer[property] = transport[wsdl].call(:get_template_integer_property, message: message).body[:get_template_integer_property_response][:return][:item]
    end
    template_integer
  end

  def template_integer_property=(value)
    resource[:template_integer_property].each do |k, v|
      # Trying to configure ITYPE_UNSET results in Exception: Common::OperationFailed
      message = { template_names: { item: resource[:name] }, values: { item: [{:type => k, :value => v}]}}
      transport[wsdl].call(:set_template_integer_property, message: message) unless k == 'ITYPE_UNSET'
    end
  end

  def template_string_property
    properties = [
      'STYPE_UNSET',
      'STYPE_SEND',
      'STYPE_GET',
      'STYPE_RECEIVE',
      'STYPE_USERNAME',
      'STYPE_PASSWORD',
      'STYPE_RUN',
      'STYPE_NEWSGROUP',
      'STYPE_DATABASE',
      'STYPE_DOMAIN',
      'STYPE_ARGUMENTS',
      'STYPE_FOLDER',
      'STYPE_BASE',
      'STYPE_FILTER',
      'STYPE_SECRET',
      'STYPE_METHOD',
      'STYPE_URL',
      'STYPE_COMMAND',
      'STYPE_METRICS',
      'STYPE_POST',
      'STYPE_USERAGENT',
      'STYPE_AGENT_TYPE',
      'STYPE_CPU_COEFFICIENT',
      'STYPE_CPU_THRESHOLD',
      'STYPE_MEMORY_COEFFICIENT',
      'STYPE_MEMORY_THRESHOLD',
      'STYPE_DISK_COEFFICIENT',
      'STYPE_DISK_THRESHOLD',
      'STYPE_SNMP_VERSION',
      'STYPE_COMMUNITY',
      'STYPE_SEND_PACKETS',
      'STYPE_TIMEOUT_PACKETS',
      'STYPE_RECEIVE_DRAIN',
      'STYPE_RECEIVE_ROW',
      'STYPE_RECEIVE_COLUMN',
      'STYPE_DEBUG',
      'STYPE_SECURITY',
      'STYPE_MODE',
      'STYPE_CIPHER_LIST',
      'STYPE_NAMESPACE',
      'STYPE_PARAMETER_NAME',
      'STYPE_PARAMETER_VALUE',
      'STYPE_PARAMETER_TYPE',
      'STYPE_RETURN_TYPE',
      'STYPE_RETURN_VALUE',
      'STYPE_SOAP_FAULT',
      'STYPE_SSL_OPTIONS',
      'STYPE_CLIENT_CERTIFICATE',
      'STYPE_PROTOCOL',
      'STYPE_MANDATORY_ATTRS',
      'STYPE_FILENAME',
      'STYPE_ACCOUNTING_NODE',
      'STYPE_ACCOUNTING_PORT',
      'STYPE_SERVER_ID',
      'STYPE_CALL_ID',
      'STYPE_SESSION_ID',
      'STYPE_FRAMED_ADDRESS',
      'STYPE_PROGRAM',
      'STYPE_VERSION',
      'STYPE_SERVER',
      'STYPE_SERVICE',
      'STYPE_GW_MONITOR_ADDRESS',
      'STYPE_GW_MONITOR_SERVICE',
      'STYPE_GW_MONITOR_INTERVAL',
      'STYPE_GW_MONITOR_PROTOCOL',
      'STYPE_DB_COUNT',
      'STYPE_REQUEST',
      'STYPE_HEADERS',
      'STYPE_FILTER_NEG',
      'STYPE_SERVER_IP',
      'STYPE_SNMP_PORT',
      'STYPE_POOL_NAME',
      'STYPE_NAS_IP',
      'STYPE_CLIENT_KEY',
      'STYPE_MAX_LOAD_AVERAGE',
      'STYPE_CONCURRENCY_LIMIT',
      'STYPE_FAILURES',
      'STYPE_FAILURE_INTERVAL',
      'STYPE_RESPONSE_TIME',
      'STYPE_RETRY_TIME',
      'STYPE_DIAMETER_ACCT_APPLICATION_ID',
      'STYPE_DIAMETER_AUTH_APPLICATION_ID',
      'STYPE_DIAMETER_ORIGIN_HOST',
      'STYPE_DIAMETER_ORIGIN_REALM',
      'STYPE_DIAMETER_HOST_IP_ADDRESS',
      'STYPE_DIAMETER_VENDOR_ID',
      'STYPE_DIAMETER_PRODUCT_NAME',
      'STYPE_DIAMETER_VENDOR_SPECIFIC_VENDOR_ID',
      'STYPE_DIAMETER_VENDOR_SPECIFIC_ACCT_APPLICATION_ID',
      'STYPE_DIAMETER_VENDOR_SPECIFIC_AUTH_APPLICATION_ID',
      'STYPE_RUN_V2',
      'STYPE_CLIENT_CERTIFICATE_V2',
      'STYPE_CLIENT_KEY_V2',
    ]

    template_string = {}
    message = { template_names: { item: @property_hash[:name] }, property_types: { item: properties }}
    require 'pry'
    binding.pry
    template_string = transport[wsdl].call(:get_template_string_property, message: message).body[:get_template_string_property_response][:return][:item]
    template_string
  end

  def template_string_property=(value)
    resource[:template_string_property].each do |k, v|
      message = { template_names: { item: resource[:name] }, property_types: { item: [{:type => k, :value => v}] }}
      transport[wsdl].call(:set_template_string_property, message: message)
    end
  end

  def template_type
    message = { template_names: { item: @property_hash[:name]}}
    transport[wsdl].call(:get_template_type, message: message).body[:get_template_type_response][:return][:item]
  end

  def template_type=(value)
    # can't alter template_type, so destroy and recreate resource.
    destroy
    create
  end

  def create
    Puppet.debug("Puppet::Provider::F5_Monitor: creating F5 monitor #{resource[:name]}")

    @property_hash[:ensure] = :present
    self.class.resource_type.validproperties.each do |property|
      if val = resource.should(property)
        @property_hash[property] = val
      end
    end

    monitor_template = { :template_name => resource[:name],
                         :template_type => resource[:template_type] }

    # configure timeout default based on F5 recommendation of 3x interval + 1 second.
    # http://devcentral.f5.com/wiki/iControl.LocalLB__Monitor__CommonAttributes.ashx
    if resource[:template_integer_property] then
      interval = resource[:template_integer_property]['ITYPE_INTERVAL']
      timeout  = resource[:template_integer_property]['ITYPE_TIMEOUT']
    end
    interval ||= 5
    timeout  ||= 3 * interval + 1

    common_attributes = { :parent_template    => resource[:parent_template],
                          :interval           => interval,
                          :timeout            => timeout,
                          :dest_ipport        => monitor_ipport(resource[:template_destination]),
                          :is_read_only       => resource[:is_read_only],
                          :is_directly_usable => resource[:is_directly_usable] }

    message = { templates: { item: [monitor_template] }, template_attributes: { item: [common_attributes]}}
    transport[wsdl].call(:create_template, message: message)

    # Update other monitor attributes after resource creation.
    methods = [
      'template_state',
      'template_transparent_mode',
      # We don't know which user_defined string to support yet.
      #template_user_defined_string_property',
      'template_integer_property',
      'template_string_property',
      'manual_resume_state'
    ]

    methods.each do |method|
      self.send("#{method}=", resource[method.to_sym]) if resource[method.to_sym]
    end
  end

  def destroy
    Puppet.debug("Puppet::Provider::F5_Monitor: deleting F5 monitor #{resource[:name]}")
    @property_hash[:ensure] = :absent
    transport[wsdl].call(:delete_template, message: { template_names: { item: @property_hash[:name]}})
  end

  def exists?
    @property_hash[:ensure] == :present
  end
end
