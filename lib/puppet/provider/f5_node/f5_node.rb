require 'puppet/provider/f5'

Puppet::Type.type(:f5_node).provide(:f5_node, :parent => Puppet::Provider::F5) do
  @doc = "Manages f5 node"

  confine :feature => :posix
  defaultfor :feature => :posix

  def self.wsdl
    'LocalLB.NodeAddressV2'
  end

  def wsdl
    self.class.wsdl
  end

  def self.instances
    Puppet.debug("Puppet::Provider::F5_Node: instances")
    transport[wsdl].call(:get_list).body[:get_list_response][:return][:item].collect do |item|
      new(:name   => item,
          :ensure => :present
         )
    end
  end

  def dynamic_ratio
    message = { nodes: { item: resource[:name]}}
    transport[wsdl].call(:get_dynamic_ratio, message: message).body[:get_dynamic_ratio_response][:return][:item]
  end

  def dynamic_ratio=(value)
    message = { nodes: { item: resource[:name] }, dynamic_ratios: { item: resource[:dynamic_ratio] } }
    transport[wsdl].call(:set_dynamic_ratio, message: message)
  end

  def ratio
    message = { nodes: { item: resource[:name]}}
    transport[wsdl].call(:get_ratio, message: message).body[:get_ratio_response][:return][:item]
  end

  def ratio=(value)
    message = { nodes: { item: resource[:name] }, ratios: { item: resource[:ratio] } }
    transport[wsdl].call(:set_ratio, message: message)
  end

  def connection_limit
    message = { nodes: { item: resource[:name]}}
    transport[wsdl].call(:get_connection_limit, message: message).body[:get_connection_limit_response][:return][:item]
  end

  def connection_limit=(value)
    message = { nodes: { item: resource[:name]}, limits: { item: resource[:connection_limit]}}
    transport[wsdl].call(:set_connection_limit, message: message)
  end

  def session_enabled_state 
    message = { nodes: { item: resource[:name]}}
    value = transport[wsdl].call(:get_session_status, message: message).body[:get_session_status_response][:return][:item]
    case
    when value.match(/DISABLED$/)
      'STATE_DISABLED'
    when value.match(/ENABLED$/)
      'STATE_ENABLED'
    else
      nil
    end
  end

  def session_enabled_state=(value)
    message = { nodes: { item: resource[:name]}, states: { item: resource[:session_enabled_state]}}
    transport[wsdl].call(:set_session_enabled_state, message: message)
  end

  def monitor_association
    transport[wsdl].get_monitor_association(resource[:name])
  end

  def create
    Puppet.debug("Puppet::Provider::F5_Node: creating F5 node #{resource[:name]}")
    # The F5 API isn't consistent, it accepts long instead of ULong64 so we set connection limits later.
    message = { 
      nodes: { item: resource[:name] },
      addresses: { item: resource[:addresses] },
      limits: { item: resource[:connection_limit] }
    }
    transport[wsdl].call(:create, message: message)

    methods = [ 'connection_limit',
      'dynamic_ratio',
      'ratio',
      'session_enabled_state' ]

    methods.each do |method|
      self.send("#{method}=", resource[method.to_sym]) if resource[method.to_sym]
    end
  end

  def destroy
    Puppet.debug("Puppet::Provider::F5_Pool: destroying F5 node #{resource[:name]}")
    transport[wsdl].call(:delete_node_address, message: { nodes: { item: resource[:name]}})
  end

  def exists?
    response = transport[wsdl].call(:get_list)
    if response.body[:get_list_response][:return][:item]
      response.body[:get_list_response][:return][:item].include?(resource[:name])
    end
  end
end
