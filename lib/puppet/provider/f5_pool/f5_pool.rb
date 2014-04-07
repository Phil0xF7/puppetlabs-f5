require 'puppet/provider/f5'

Puppet::Type.type(:f5_pool).provide(:f5_pool, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 pool"

  confine :feature => :posix
  defaultfor :feature => :posix

  def self.wsdl
    'LocalLB.Pool'
  end

  def wsdl
    self.class.wsdl
  end

  def self.instances
    Array(transport[wsdl].get(:get_list)).collect do |name|
      new(:name => name)
    end
  end

  methods = [
    'action_on_service_down',
    'allow_nat_state',
    'allow_snat_state',
    'client_ip_tos',                      # Array
    'client_link_qos',                    # Array
    'gateway_failsafe_device',
    'lb_method',
    'minimum_active_member',              # Array
    'minimum_up_member',                  # Array
    'minimum_up_member_action',
    'minimum_up_member_enabled_state',
    'server_ip_tos',
    'server_link_qos',
    'simple_timeout',
    'slow_ramp_time'
  ]

  methods.each do |method|
    define_method(method.to_sym) do
      transport[wsdl].get("get_#{method}".to_sym, { pool_names:  { item: resource[:name] }})
    end
  end

  methods.each do |method|
    define_method("#{method}=") do |value|
      message = { pool_names: { item: resource[:name] }, actions: { item: resource[method.to_sym] }}
      transport[wsdl].call("set_#{method}".to_sym, message: message)
    end
  end

  def member
    result = {}
    addressport = []
    members = []

    members << transport[wsdl].get(:get_member_v2, { pool_names: { item: resource[:name] }})

    members.each do |node|
      #result["#{system[:address]}:#{system[:port]}"] = {}
      addressport << { address: node[:address], port: node[:port] }

      methods = [
        'connection_limit',
        'dynamic_ratio',
        'priority',
        'ratio',
      ]

      methods.each do |method|
        result = nil
        message = { pool_names: resource[:name], members: { address: node[:address], port: node[:port] }}
        require 'pry'
        binding.pry
        response = transport[wsdl].get("get_member_#{method}".to_sym, message)
        response ||= []

        response.each do |val|
          # F5 A.B.C.D%ID routing domain requires special handling.
          #   If we don't detect a routine domain in get_member, we ignore %ID.
          #   If we detect routine domain in get_member, we provide %ID.
          address = val.member.address
          noroute = address.split("%").first
          port    = val.member.port

          if result.member?("#{address}:#{port}")
            result["#{address}:#{port}"][method] = val.send(method).to_s
          elsif result.member?("#{noroute}:#{port}")
            result["#{noroute}:#{port}"][method] = val.send(method).to_s
          else
            raise Puppet::Error, "Puppet::Provider::F5_Pool: LocalLB.Pool get_#{method} returned #{address}:#{port} that does not exist in get_member."
          end
        end
      end
    end
    result
  end

  def member=(value)
    current_members = transport[wsdl].get(:get_member_v2, { pool_names: { item: resource[:name]}})
    current_members ||= []

    current_members = current_members.collect { |system|
      "#{system.address}:#{system.port}"
    }

    members = resource[:member].keys

    # Should add new members first to avoid removing all members of the pool.
    (members - current_members).each do |node|
      Puppet.debug "Puppet::Provider::F5_Pool: adding member #{node}"
      message = { pool_names: resource[:name], members: { address: network_address(node), port: network_port(node) }}
      puts message
      transport[wsdl].call(:add_member_v2, message: message)
    end

    (current_members - members).each do |node|
      Puppet.debug "Puppet::Provider::F5_Pool: removing member #{node}"
      message = { pool_names: resource[:name], members: { item: {address: network_address(node), port: network_port(node)}} }
      transport[wsdl].call(:remove_member_v2, message: message)
    end

    properties = {
      'connection_limit' => 'limits',
      'dynamic_ratio'    => 'dynamic_ratios',
      'priority'         => 'priorities',
      'ratio'            => 'ratios',
    }

    properties.each do |name, message_name|
      value.each do |address,hash|
        address, port = address.split(':')
        message = { pool_names: resource[:name], members: { address: address, port: port }, message_name => hash[name] }
        transport[wsdl].call("set_member_#{name}".to_sym, message: message)
      end
    end
  end

  def monitor_association
    monitor = transport[wsdl].get(:get_monitor_association, { pool_names: { item: resource[:name] }})

    if monitor
      {
        'type'              => monitor['type'],
        'quorum'            => monitor['quorum'].to_s,
        'monitor_templates' => monitor['monitor_templates']
      }
    end
  end

  def monitor_association=(value)
    monitor = resource[:monitor_association]

    if monitor.empty? then
      transport[wsdl].call(:remove_monitor_association, message: { pool_names: { item: resource[:name]}})
    else
      newval = { :pool_name => resource[:name],
        :monitor_rule => {
          :type              => monitor['type'],
          :quorum            => monitor['quorum'],
          :monitor_templates => monitor['monitor_templates']
        }
      }

      transport[wsdl].call(:set_monitor_association, message: { monitor_associations: { item: [newval] }})
    end
  end

  def create
    Puppet.debug("Puppet::Provider::F5_Pool: creating F5 pool #{resource[:name]}")
    # [[]] because we will add members later using member=...
    message = { pool_names: { item: resource[:name] }, lb_methods: { item: resource[:lb_method] }, members: {}}
    transport[wsdl].call(:create_v2, message: message)

    methods = [
      'action_on_service_down',
      'allow_nat_state',
      'allow_snat_state',
      'client_ip_tos',                      # Array
      'client_link_qos',                    # Array
      'gateway_failsafe_device',
      'lb_method',
      'minimum_active_member',              # Array
      'minimum_up_member',                  # Array
      'minimum_up_member_action',
      'minimum_up_member_enabled_state',
      'server_ip_tos',
      'server_link_qos',
      'simple_timeout',
      'slow_ramp_time',
      'monitor_association',
      'member'
    ]

    methods.each do |method|
      self.send("#{method}=", resource[method.to_sym]) if resource[method.to_sym]
    end
  end

  def destroy
    Puppet.debug("Puppet::Provider::F5_Pool: destroying F5 pool #{resource[:name]}")
    transport[wsdl].call(:delete_pool, message: { pool_names: { item: resource[:name]}})
  end

  def exists?
    transport[wsdl].get(:get_list).include?(resource[:name])
  end
end
